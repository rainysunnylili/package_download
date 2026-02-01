#!/usr/bin/env bash
set -euo pipefail

# ================= 配置区 =================
ROOT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
DOWNLOADS_DIR="$ROOT_DIR/all-downloads"
NPM_DOWNLOAD_DIR="$DOWNLOADS_DIR/npm-packages"
PYPI_DOWNLOAD_DIR="$DOWNLOADS_DIR/python-packages"

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# ================= 函数定义 =================
print_header() {
    echo ""
    echo -e "${BLUE}================================================${NC}"
    echo -e "${BLUE}  $1${NC}"
    echo -e "${BLUE}================================================${NC}"
}

print_success() {
    echo -e "${GREEN}✅ $1${NC}"
}

print_error() {
    echo -e "${RED}❌ $1${NC}"
}

print_info() {
    echo -e "${YELLOW}📦 $1${NC}"
}

# ================= 主逻辑 =================
main() {
    print_header "开始下载所有依赖包"
    
    # 创建下载目录
    mkdir -p "$NPM_DOWNLOAD_DIR"
    mkdir -p "$PYPI_DOWNLOAD_DIR"
    
    print_info "NPM包保存目录: $NPM_DOWNLOAD_DIR"
    print_info "Python包保存目录: $PYPI_DOWNLOAD_DIR"
    echo ""
    
    # ================= 下载 NPM 包 =================
    T1_START=$SECONDS
    print_header "Step 1: 下载 NPM 依赖包"
    
    # 检查是否存在package-lock.json
    if [ ! -f "package-lock.json" ]; then
        print_info "未找到 package-lock.json，正在生成..."
        npm install --package-lock-only
    fi
    
    # 创建临时的下载脚本配置
    cat > download_npm_temp.mjs << 'EOF'
import fs from 'fs';
import path from 'path';
import os from 'os';
import { spawn, spawnSync } from 'child_process';

const ROOT_DIR = process.cwd();
const PACKAGE_JSON_PATH = path.join(ROOT_DIR, 'package.json');
const PACKAGE_LOCK_PATH = path.join(ROOT_DIR, 'package-lock.json');
const NPMRC_PATH = path.join(ROOT_DIR, '.npmrc');
const DOWNLOAD_DIR = process.env.NPM_DOWNLOAD_DIR || path.join(ROOT_DIR, 'npm-offline-packages');
const CONCURRENCY = Number(process.env.NPM_CONCURRENCY || '128');

function updateProgress(current, total, context) {
    const width = 30;
    const percentage = Math.round((current / total) * 100);
    const filled = Math.round((width * current) / total);
    const empty = width - filled;
    const bar = '█'.repeat(filled) + '░'.repeat(empty);
    process.stdout.write(`\r${context}: [${bar}] ${current}/${total} (${percentage}%)`);
}

function runCommandAsync(command, args, options = {}) {
    return new Promise((resolve, reject) => {
        const child = spawn(command, args, { ...options });
        let stdout = '';
        let stderr = '';
        if (child.stdout) child.stdout.on('data', (d) => { stdout += d.toString(); });
        if (child.stderr) child.stderr.on('data', (d) => { stderr += d.toString(); });
        child.on('error', reject);
        child.on('close', (code) => {
            if (code !== 0) {
                reject(new Error(`${command} ${args.join(' ')} failed\n${stderr || stdout}`));
            } else {
                resolve(stdout);
            }
        });
    });
}

function createLimiter(limit) {
    let active = 0;
    const queue = [];
    const next = () => {
        if (active >= limit || queue.length === 0) return;
        active++;
        const { fn, resolve, reject } = queue.shift();
        fn().then(resolve).catch(reject).finally(() => { active--; next(); });
    };
    return (fn) => new Promise((resolve, reject) => {
        queue.push({ fn, resolve, reject });
        next();
    });
}

const limiter = createLimiter(CONCURRENCY);

function ensureFileExists(filePath) {
    if (!fs.existsSync(filePath)) {
        console.error(`❌ 找不到文件: ${filePath}`);
        process.exit(1);
    }
}

function runCommand(command, args, options = {}) {
    const result = spawnSync(command, args, { ...options, encoding: 'utf8' });
    if (result.error) {
        throw result.error;
    }
    if (result.status !== 0) {
        const stdout = (result.stdout || '').trim();
        const stderr = (result.stderr || '').trim();
        const details = [stdout, stderr].filter(Boolean).join('\n');
        throw new Error(`命令失败: ${command} ${args.join(' ')}${details ? `\n${details}` : ''}`);
    }
    return result.stdout || '';
}

function listDependencies(tempDir) {
    const result = spawnSync('npm', ['list', '--all', '--json'], { cwd: tempDir, encoding: 'utf8' });
    if (result.error) {
        throw result.error;
    }
    if (!result.stdout || !result.stdout.trim()) {
        throw new Error('npm list 未返回有效 JSON');
    }
    if (result.status !== 0) {
        console.warn('⚠️ npm list 返回非零状态，继续解析输出');
    }
    return JSON.parse(result.stdout);
}

function collectDependencies(tree) {
    const collected = new Map();
    const visit = (node) => {
        if (!node || !node.dependencies) return;
        for (const [name, dep] of Object.entries(node.dependencies)) {
            if (!dep || !dep.version) {
                continue;
            }
            const key = `${name}@${dep.version}`;
            if (!collected.has(key)) {
                collected.set(key, { name, version: dep.version });
            }
            visit(dep);
        }
    };
    visit(tree);
    return Array.from(collected.values());
}

function collectPackagesFromLock(lockData) {
    const collected = new Map();
    if (!lockData) return [];
    
    // V2/V3 (packages)
    if (lockData.packages) {
        for (const [key, val] of Object.entries(lockData.packages)) {
            if (!key) continue;
            const name = key.split('node_modules/').pop();
            if (name && val.version) {
                const uniqueKey = `${name}@${val.version}`;
                collected.set(uniqueKey, { name, version: val.version });
            }
        }
    } 
    // V1 (dependencies)
    else if (lockData.dependencies) {
        const traverse = (deps) => {
            for (const [name, val] of Object.entries(deps)) {
                if (val.version) {
                    const uniqueKey = `${name}@${val.version}`;
                    collected.set(uniqueKey, { name, version: val.version });
                }
                if (val.dependencies) traverse(val.dependencies);
            }
        };
        traverse(lockData.dependencies);
    }
    return Array.from(collected.values());
}

function loadLockData() {
    if (!fs.existsSync(PACKAGE_LOCK_PATH)) {
        return null;
    }
    return JSON.parse(fs.readFileSync(PACKAGE_LOCK_PATH, 'utf8'));
}

function collectPeerDependenciesFromLock(lockData) {
    const peers = new Map();
    if (!lockData || !lockData.packages) return peers;
    for (const meta of Object.values(lockData.packages)) {
        if (!meta || !meta.peerDependencies) continue;
        for (const [name, range] of Object.entries(meta.peerDependencies)) {
            if (!peers.has(name)) {
                peers.set(name, new Set());
            }
            peers.get(name).add(range || '*');
        }
    }
    return peers;
}

function collectOptionalDependenciesFromLock(lockData) {
    const optionalDeps = new Map();
    if (!lockData || !lockData.packages) return optionalDeps;
    for (const meta of Object.values(lockData.packages)) {
        if (!meta || !meta.optionalDependencies) continue;
        for (const [name, range] of Object.entries(meta.optionalDependencies)) {
            if (!optionalDeps.has(name)) {
                optionalDeps.set(name, new Set());
            }
            optionalDeps.get(name).add(range || '*');
        }
    }
    return optionalDeps;
}

function resolvePeerVersion(name, range, tempDir) {
    const spec = range && range !== '*' ? `${name}@${range}` : name;
    const output = runCommand('npm', ['view', spec, 'version', '--json'], { cwd: tempDir });
    let version = '';
    try {
        const parsed = JSON.parse(output);
        if (Array.isArray(parsed)) {
            version = String(parsed[parsed.length - 1] || '').trim();
        } else if (parsed !== null && parsed !== undefined) {
            version = String(parsed).trim();
        }
    } catch {
        version = '';
    }
    if (!version) {
        version = output.trim().split(/\s+/).pop() || '';
        version = version.replace(/^['"]+|['"]+$/g, '');
    }
    if (!version) {
        throw new Error(`无法解析版本: ${spec}`);
    }
    return version;
}

function resolveVersionCached(name, range, tempDir, cache) {
    const spec = range && range !== '*' ? `${name}@${range}` : name;
    if (cache.has(spec)) {
        return cache.get(spec);
    }
    const version = resolvePeerVersion(name, range, tempDir);
    cache.set(spec, version);
    return version;
}

function fetchDependencyMap(name, version, tempDir, field, cache) {
    const key = `${name}@${version}:${field}`;
    if (cache.has(key)) {
        return cache.get(key);
    }
    let deps = {};
    try {
        const output = runCommand('npm', ['view', `${name}@${version}`, field, '--json'], { cwd: tempDir });
        if (output && output.trim()) {
            const parsed = JSON.parse(output);
            if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) {
                deps = parsed;
            }
        }
    } catch {
        deps = {};
    }
    cache.set(key, deps);
    return deps;
}

async function resolveVersionAsync(name, range, tempDir, cache) {
    const spec = range && range !== '*' ? `${name}@${range}` : name;
    if (cache.has(spec)) return cache.get(spec);
    const output = await limiter(() => runCommandAsync('npm', ['view', spec, 'version', '--json'], { cwd: tempDir }));
    let version = '';
    try {
        const parsed = JSON.parse(output);
        version = Array.isArray(parsed) ? String(parsed[parsed.length - 1] || '').trim() : String(parsed).trim();
    } catch { version = output.trim().split(/\s+/).pop()?.replace(/^['"]|['"]$/g, '') || ''; }
    if (!version) throw new Error(`无法解析版本: ${spec}`);
    cache.set(spec, version);
    return version;
}

async function fetchDependencyMapAsync(name, version, tempDir, field, cache) {
    const key = `${name}@${version}:${field}`;
    if (cache.has(key)) return cache.get(key);
    let deps = {};
    try {
        const output = await limiter(() => runCommandAsync('npm', ['view', `${name}@${version}`, field, '--json'], { cwd: tempDir }));
        if (output?.trim()) {
            const parsed = JSON.parse(output);
            if (parsed && typeof parsed === 'object' && !Array.isArray(parsed)) deps = parsed;
        }
    } catch { deps = {}; }
    cache.set(key, deps);
    return deps;
}

async function expandDependencies(packages, known, tempDir, onProgress) {
    const queue = [...packages];
    const processed = new Set();
    const versionCache = new Map();
    const depCache = new Map();
    const failed = [];
    const initialTotal = packages.length;

    while (queue.length) {
        const batch = queue.splice(0, CONCURRENCY).filter((pkg) => {
            const key = `${pkg.name}@${pkg.version}`;
            if (processed.has(key)) return false;
            processed.add(key);
            return true;
        });
        if (batch.length === 0) continue;

        if (typeof onProgress === 'function') {
            const totalEstimated = Math.max(initialTotal, processed.size + queue.length);
            onProgress(processed.size, queue.length, totalEstimated, known.size);
        }

        await Promise.all(batch.map(async (pkg) => {
            const [deps, optional] = await Promise.all([
                fetchDependencyMapAsync(pkg.name, pkg.version, tempDir, 'dependencies', depCache),
                fetchDependencyMapAsync(pkg.name, pkg.version, tempDir, 'optionalDependencies', depCache)
            ]);
            const merged = { ...deps, ...optional };
            await Promise.all(Object.entries(merged).map(async ([name, range]) => {
                try {
                    const version = await resolveVersionAsync(name, range, tempDir, versionCache);
                    const depKey = `${name}@${version}`;
                    if (!known.has(depKey)) {
                        known.add(depKey);
                        const item = { name, version };
                        packages.push(item);
                        queue.push(item);
                    }
                } catch { failed.push(`${name}@${range || '*'}`); }
            }));
        }));
    }

    if (typeof onProgress === 'function') {
        onProgress(processed.size, queue.length, initialTotal, known.size, true);
    }
    return failed;
}

function tarballName(pkgName, version) {
    const safeName = pkgName.startsWith('@')
        ? pkgName.slice(1).replace(/\//g, '-')
        : pkgName.replace(/\//g, '-');
    return `${safeName}-${version}.tgz`;
}

function readPackageJsonFromTarball(tarballPath) {
    const result = spawnSync('tar', ['-xOf', tarballPath, 'package/package.json'], {
        encoding: 'utf8'
    });
    if (result.error || result.status !== 0) {
        return null;
    }
    try {
        return JSON.parse(result.stdout || '');
    } catch {
        return null;
    }
}

function expandDependenciesFromTarballs(packages, known, tempDir, downloadDir) {
    const versionCache = new Map();
    const processed = new Set();
    const failed = [];
    const beforeSize = known.size;

    for (const pkg of packages) {
        const key = `${pkg.name}@${pkg.version}`;
        if (processed.has(key)) continue;
        processed.add(key);

        const tarPath = path.join(downloadDir, tarballName(pkg.name, pkg.version));
        if (!fs.existsSync(tarPath)) continue;

        const pkgJson = readPackageJsonFromTarball(tarPath);
        if (!pkgJson) continue;

        const deps = {
            ...(pkgJson.dependencies || {}),
            ...(pkgJson.optionalDependencies || {})
        };

        for (const [name, range] of Object.entries(deps)) {
            try {
                const version = resolveVersionCached(name, range, tempDir, versionCache);
                const depKey = `${name}@${version}`;
                if (!known.has(depKey)) {
                    known.add(depKey);
                    packages.push({ name, version });
                }
            } catch {
                failed.push(`${name}@${range || '*'}`);
            }
        }
    }

    return { added: known.size - beforeSize, failed };
}

async function packAllPackages(packages, tempDir, downloadDir) {
    const failed = [];
    const total = packages.length;
    let completed = 0;

    // Initial render
    updateProgress(0, total, '下载进度');

    const tasks = packages.map((pkg) => limiter(async () => {
        const spec = `${pkg.name}@${pkg.version}`;
        const fileName = tarballName(pkg.name, pkg.version);
        const destPath = path.join(downloadDir, fileName);

        if (fs.existsSync(destPath)) {
            completed++;
            updateProgress(completed, total, '下载进度');
            return;
        }

        try {
            await runCommandAsync('npm', ['pack', spec, '--pack-destination', downloadDir], { cwd: tempDir });
        } catch (err) {
            // Clear line to print error cleanly
            process.stdout.write('\r\x1b[K'); 
            console.error(`❌ ${spec} 下载失败`);
            failed.push(spec);
        }
        completed++;
        updateProgress(completed, total, '下载进度');
    }));

    await Promise.all(tasks);
    process.stdout.write('\n'); // New line after progress bar
    return failed;
}

async function main() {
    console.log(`🚀 开始使用 npm 解析依赖并批量下载 (并发: ${CONCURRENCY})...`);
    ensureFileExists(PACKAGE_JSON_PATH);
    fs.mkdirSync(DOWNLOAD_DIR, { recursive: true });

    const tempDir = fs.mkdtempSync(path.join(os.tmpdir(), 'npm-pack-'));
    const cleanup = () => fs.rmSync(tempDir, { recursive: true, force: true });

    try {
        fs.copyFileSync(PACKAGE_JSON_PATH, path.join(tempDir, 'package.json'));
        if (fs.existsSync(PACKAGE_LOCK_PATH)) {
            fs.copyFileSync(PACKAGE_LOCK_PATH, path.join(tempDir, 'package-lock.json'));
        }
        if (fs.existsSync(NPMRC_PATH)) {
            fs.copyFileSync(NPMRC_PATH, path.join(tempDir, '.npmrc'));
        }

        runCommand('npm', ['install', '--ignore-scripts', '--no-audit', '--no-fund'], {
            cwd: tempDir,
            stdio: 'inherit'
        });

        const tree = listDependencies(tempDir);
        let packages = collectDependencies(tree);
        const lockData = loadLockData();

        const lockPackages = collectPackagesFromLock(lockData);
        if (lockPackages.length > 0) {
            console.log(`📦 从 lockfile 解析出 ${lockPackages.length} 个依赖，合并中...`);
            packages = packages.concat(lockPackages);
        }

        const known = new Set(packages.map((pkg) => `${pkg.name}@${pkg.version}`));
        const peerDeps = collectPeerDependenciesFromLock(lockData);
        const optionalDeps = collectOptionalDependenciesFromLock(lockData);
        const peerFailed = [];
        const optionalFailed = [];
        let expandFailed = [];

        for (const [name, ranges] of peerDeps) {
            for (const range of ranges) {
                try {
                    const version = resolvePeerVersion(name, range, tempDir);
                    const key = `${name}@${version}`;
                    if (!known.has(key)) {
                        known.add(key);
                        packages.push({ name, version });
                    }
                } catch (err) {
                    console.error(`❌ 解析 peer 失败 ${name}@${range}: ${err.message}`);
                    peerFailed.push(`${name}@${range}`);
                }
            }
        }

        for (const [name, ranges] of optionalDeps) {
            for (const range of ranges) {
                try {
                    const version = resolvePeerVersion(name, range, tempDir);
                    const key = `${name}@${version}`;
                    if (!known.has(key)) {
                        known.add(key);
                        packages.push({ name, version });
                    }
                } catch (err) {
                    console.error(`❌ 解析 optional 依赖失败 ${name}@${range}: ${err.message}`);
                    optionalFailed.push(`${name}@${range}`);
                }
            }
        }

        const shouldExpand = process.env.NPM_EXPAND_REGISTRY === '1' || (process.env.NPM_EXPAND_REGISTRY !== '0' && (!lockPackages || lockPackages.length === 0));

        if (!shouldExpand && process.env.NPM_EXPAND_REGISTRY !== '0') {
            console.log('⚡ 检测到完整 lockfile，跳过 registry 递归扩展 (加速模式). 如需强制扩展请设置 NPM_EXPAND_REGISTRY=1');
        }

        if (shouldExpand) {
            try {
                console.log('🔎 开始扩展依赖 (128并发)...');
                expandFailed = await expandDependencies(packages, known, tempDir, (done, queued, initialTotal, knownTotal, finished) => {
                    const totalEstimated = Math.max(initialTotal, done + queued);
                    const percentage = totalEstimated > 0 ? Math.min(100, Math.round((done / totalEstimated) * 100)) : 0;
                    if (finished) {
                         process.stdout.write(`\r✅ 依赖扩展完成: 已处理 ${done}，当前总依赖 ${knownTotal}\n`);
                         return;
                    }
                    
                    const width = 30;
                    const filled = Math.round((width * done) / totalEstimated);
                    const empty = width - filled;
                    const bar = '█'.repeat(filled) + '░'.repeat(empty);
                    process.stdout.write(`\r🔎 依赖扩展: [${bar}] ${done}/${totalEstimated} (${percentage}%)`);
                });
            } catch (err) {
                console.error(`❌ 扩展依赖失败: ${err.message}`);
            }
        }

        console.log(`📊 共解析出 ${packages.length} 个依赖项 (已去重)，开始下载 (128并发)...`);

        let failed = await packAllPackages(packages, tempDir, DOWNLOAD_DIR);
        let tarballFailed = [];

        for (let i = 0; i < 2; i += 1) {
            const { added, failed: tarFailed } = expandDependenciesFromTarballs(
                packages,
                known,
                tempDir,
                DOWNLOAD_DIR
            );
            tarballFailed = tarballFailed.concat(tarFailed);
            if (added === 0) {
                break;
            }
            console.log(`📦 解析新增 ${added} 个依赖，继续下载...`);
            failed = failed.concat(await packAllPackages(packages, tempDir, DOWNLOAD_DIR));
        }

        if (failed.length || peerFailed.length || optionalFailed.length || expandFailed.length || tarballFailed.length) {
            const allFailed = failed.concat(peerFailed, optionalFailed, expandFailed, tarballFailed);
            fs.writeFileSync(path.join(DOWNLOAD_DIR, 'failed_log.json'), JSON.stringify(allFailed, null, 2));
            console.error(`⚠️ 下载完成，但有 ${allFailed.length} 个包失败`);
            process.exitCode = 1;
        } else {
            console.log('✅ 所有依赖下载完成！');
        }
    } catch (err) {
        console.error('Fatal Error:', err);
        process.exitCode = 1;
    } finally {
        cleanup();
    }
}

main().then(() => process.exit(process.exitCode || 0)).catch((err) => { console.error('Fatal:', err); process.exit(1); });
EOF
    
    # 执行npm包下载
    NPM_DOWNLOAD_DIR="$NPM_DOWNLOAD_DIR" node download_npm_temp.mjs
    
    # 清理临时文件
    rm -f download_npm_temp.mjs
    
    print_success "NPM包下载完成！"
    echo -e "${YELLOW}⏱️  Step 1 耗时: $((SECONDS - T1_START)) 秒${NC}"
    
    # ================= 下载 Python 包 =================
    T2_START=$SECONDS
    print_header "Step 2: 下载 Python 依赖包"
    
    if [ ! -f "requirements.txt" ]; then
        print_error "未找到 requirements.txt 文件"
        exit 1
    fi
    
    print_info "使用镜像源: https://pypi.tuna.tsinghua.edu.cn/simple"
    
    PLATFORMS=("win_amd64" "manylinux2014_x86_64")
    PY_VER="313"
    MIRROR_URL="https://pypi.tuna.tsinghua.edu.cn/simple"
    
    for PLATFORM in "${PLATFORMS[@]}"; do
        echo ""
        print_info "正在处理平台: $PLATFORM"
        
        if pip download \
            -r requirements.txt \
            --dest "$PYPI_DOWNLOAD_DIR" \
            --index-url "$MIRROR_URL" \
            --only-binary=:all: \
            --platform "$PLATFORM" \
            --python-version "$PY_VER" \
            --implementation cp \
            --abi "cp${PY_VER}"; then
            
            print_success "[${PLATFORM}] 下载完成"
        else
            print_error "[${PLATFORM}] 下载出现问题"
        fi
    done
    
    echo -e "${YELLOW}⏱️  Step 2 耗时: $((SECONDS - T2_START)) 秒${NC}"

    # ================= 完成汇总 =================
    
    print_header "下载完成汇总"
    
    NPM_COUNT=$(find "$NPM_DOWNLOAD_DIR" -type f -name "*.tgz" 2>/dev/null | wc -l)
    PYPI_COUNT=$(find "$PYPI_DOWNLOAD_DIR" -type f \( -name "*.whl" -o -name "*.tar.gz" \) 2>/dev/null | wc -l)
    
    echo ""
    print_success "NPM包数量: $NPM_COUNT 个"
    print_success "Python包数量: $PYPI_COUNT 个"
    echo ""
    print_info "NPM包位置: $NPM_DOWNLOAD_DIR"
    print_info "Python包位置: $PYPI_DOWNLOAD_DIR"
    echo ""
    
    print_header "全部完成 🎉"
}

# 执行主函数
main
