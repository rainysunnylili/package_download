#!/usr/bin/env node
/* resolve-peers.js */

const { execFile, spawnSync } = require("child_process");
const { promisify } = require("util");
const fs = require("fs");
const path = require("path");
const os = require("os");

const execFileAsync = promisify(execFile);

function ensurePackage(pkg) {
  try {
    require.resolve(pkg);
  } catch {
    console.log(`未检测到 ${pkg}，正在自动安装...`);
    spawnSync("npm", ["i", "-D", pkg], { stdio: "inherit" });
  }
}

ensurePackage("cli-progress");
const cliProgress = require("cli-progress");

const args = process.argv.slice(2);
const getArg = (k, def) => {
  const i = args.indexOf(k);
  return i !== -1 ? args[i + 1] : def;
};

const mode = getArg("--mode", "list"); // list | pack
const out = getArg("--out", "peers.json");
const outDir = getArg("--out-dir", "./tgz");
const missingOut = getArg("--missing", "peer-missing.json");
const concurrency = parseInt(getArg("--concurrency", "6"), 10);

if (!["list", "pack"].includes(mode)) {
  console.error("mode 只能是 list 或 pack");
  process.exit(1);
}

/** 修复 ENOBUFS：用临时文件接收 npm ls 输出 */
function npmLsTree() {
  const tmp = path.join(os.tmpdir(), `npm-ls-${Date.now()}.json`);
  const outFd = fs.openSync(tmp, "w");

  const res = spawnSync("npm", ["ls", "--all", "--json", "--long"], {
    stdio: ["ignore", outFd, "pipe"],
  });

  fs.closeSync(outFd);

  if (res.status !== 0 && res.status !== 1) {
    const err = res.stderr ? res.stderr.toString() : "";
    throw new Error(`npm ls 失败: ${err}`);
  }

  const json = fs.readFileSync(tmp, "utf-8");
  fs.unlinkSync(tmp);
  return JSON.parse(json);
}

function collectPackages(tree) {
  const set = new Map(); // key: name@version
  function walk(node) {
    if (!node || !node.dependencies) return;
    for (const [name, info] of Object.entries(node.dependencies)) {
      if (info && info.version) {
        const key = `${name}@${info.version}`;
        if (!set.has(key)) set.set(key, { name, version: info.version });
      }
      walk(info);
    }
  }
  walk(tree);
  return Array.from(set.values());
}

/** npm view 缓存 + 超时 */
const peerCache = new Map();
const verCache = new Map();
const latestCache = new Map();

async function npmViewPeer(name, version) {
  const key = `${name}@${version}`;
  if (peerCache.has(key)) return peerCache.get(key);

  try {
    const { stdout } = await execFileAsync(
      "npm",
      ["view", `${name}@${version}`, "peerDependencies", "peerDependenciesMeta", "--json"],
      { timeout: 120000 }
    );
    const json = stdout ? JSON.parse(stdout) : { peerDependencies: {}, peerDependenciesMeta: {} };
    peerCache.set(key, json);
    return json;
  } catch {
    const empty = { peerDependencies: {}, peerDependenciesMeta: {} };
    peerCache.set(key, empty);
    return empty;
  }
}

async function npmViewVersion(name, range) {
  const key = `${name}@${range}`;
  if (verCache.has(key)) return verCache.get(key);

  try {
    const { stdout } = await execFileAsync(
      "npm",
      ["view", `${name}@${range}`, "version", "--json"],
      { timeout: 120000 }
    );
    const json = stdout ? JSON.parse(stdout) : null;
    verCache.set(key, json);
    return json;
  } catch {
    verCache.set(key, null);
    return null;
  }
}

async function npmViewLatest(name) {
  if (latestCache.has(name)) return latestCache.get(name);

  try {
    const { stdout } = await execFileAsync(
      "npm",
      ["view", name, "version", "--json"],
      { timeout: 120000 }
    );
    const json = stdout ? JSON.parse(stdout) : null;
    latestCache.set(name, json);
    return json;
  } catch {
    latestCache.set(name, null);
    return null;
  }
}

async function npmPackAsync(name, version, dir) {
  const { stdout } = await execFileAsync(
    "npm",
    ["pack", `${name}@${version}`, "--silent"],
    { timeout: 120000 }
  );
  const filename = stdout.trim();
  if (!filename) return;
  const src = path.resolve(filename);
  const dest = path.resolve(dir, filename);
  fs.renameSync(src, dest);
}

(async () => {
  const tree = npmLsTree();
  const basePkgs = collectPackages(tree);

  const allSet = new Map(); // key: name@version
  const queue = [...basePkgs];
  const fallbackPeers = new Map(); // peerName@range -> latestVersion

  // 解析 peer 并发进度条
  const resolveBar = new cliProgress.SingleBar(
    { format: "解析peer [{bar}] {percentage}% | {value}/{total} | {pkg}" },
    cliProgress.Presets.shades_classic
  );

  let processed = 0;
  let total = queue.length || 1;
  resolveBar.start(total, 0, { pkg: "" });

  let inFlight = 0;

  async function resolveWorker() {
    while (true) {
      const item = queue.shift();
      if (!item) {
        if (inFlight === 0) break;
        await new Promise((r) => setTimeout(r, 50));
        continue;
      }

      const { name, version } = item;
      const key = `${name}@${version}`;
      if (allSet.has(key)) {
        processed++;
        resolveBar.update(processed, { pkg: key });
        continue;
      }

      inFlight++;
      allSet.set(key, { name, version });

      const peerInfo = await npmViewPeer(name, version);
      const peers = peerInfo.peerDependencies || {};

      for (const [peerName, peerRange] of Object.entries(peers)) {
        let resolvedVersion = await npmViewVersion(peerName, peerRange);
        if (!resolvedVersion) {
          resolvedVersion = await npmViewLatest(peerName);
          if (resolvedVersion) fallbackPeers.set(`${peerName}@${peerRange}`, resolvedVersion);
        }
        if (resolvedVersion) {
          const peerKey = `${peerName}@${resolvedVersion}`;
          if (!allSet.has(peerKey)) queue.push({ name: peerName, version: resolvedVersion });
        }
      }

      inFlight--;
      processed++;
      const newTotal = processed + queue.length;
      if (newTotal > total) {
        total = newTotal;
        resolveBar.setTotal(total);
      }
      resolveBar.update(processed, { pkg: key });
    }
  }

  await Promise.all(Array.from({ length: concurrency }, resolveWorker));
  resolveBar.stop();

  const pkgs = Array.from(allSet.values());
  const totalPkgs = pkgs.length;

  console.log(`总下载集合依赖数（含 peer）：${totalPkgs}`);

  if (mode === "pack") {
    fs.mkdirSync(outDir, { recursive: true });
  }

  const bar = new cliProgress.SingleBar(
    { format: "进度 [{bar}] {percentage}% | {value}/{total} | {pkg}" },
    cliProgress.Presets.shades_classic
  );
  bar.start(totalPkgs, 0, { pkg: "" });

  const result = {};

  if (mode === "pack") {
    let idx = 0;
    async function packWorker() {
      while (true) {
        const i = idx++;
        if (i >= pkgs.length) break;
        const { name, version } = pkgs[i];
        const id = `${name}@${version}`;
        bar.update(i + 1, { pkg: id });
        try {
          await npmPackAsync(name, version, outDir);
        } catch {
          console.warn(`下载失败: ${id}`);
        }
      }
    }
    await Promise.all(Array.from({ length: concurrency }, packWorker));
  } else {
    for (let i = 0; i < pkgs.length; i++) {
      const { name, version } = pkgs[i];
      const id = `${name}@${version}`;
      bar.update(i + 1, { pkg: id });
      const peerInfo = await npmViewPeer(name, version);
      result[id] = {
        peerDependencies: peerInfo.peerDependencies || {},
        peerDependenciesMeta: peerInfo.peerDependenciesMeta || {},
      };
    }
  }

  bar.stop();

  if (mode === "list") {
    fs.writeFileSync(out, JSON.stringify(result, null, 2), "utf-8");
    console.log(`已输出清单：${out}`);
  } else {
    console.log(`已下载 tgz 到：${outDir}`);
  }

  // 缺失报告：记录回退 latest 的 peer
  const fallback = {};
  for (const [k, v] of fallbackPeers.entries()) fallback[k] = v;
  fs.writeFileSync(missingOut, JSON.stringify(fallback, null, 2), "utf-8");
  console.log(`已输出 peer 缺失报告（回退 latest）：${missingOut}`);
})();
