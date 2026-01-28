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
import { spawnSync } from 'child_process';
import { createRequire } from 'module';

const ROOT_DIR = process.cwd();
const PACKAGE_JSON_PATH = path.join(ROOT_DIR, 'package.json');
const PACKAGE_LOCK_PATH = path.join(ROOT_DIR, 'package-lock.json');
const NPMRC_PATH = path.join(ROOT_DIR, '.npmrc');
const DOWNLOAD_DIR = process.env.NPM_DOWNLOAD_DIR || path.join(ROOT_DIR, 'npm-offline-packages');
let cliProgress = null;

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

function loadCliProgress(tempDir) {
    if (cliProgress) return cliProgress;
    const require = createRequire(path.join(tempDir, 'package.json'));
    cliProgress = require('cli-progress');
    return cliProgress;
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

function expandDependencies(packages, known, tempDir, onProgress) {
    const queue = [...packages];
    const processed = new Set();
    const versionCache = new Map();
    const depCache = new Map();
    const failed = [];
    const initialTotal = packages.length;

    while (queue.length) {
        const pkg = queue.shift();
        const key = `${pkg.name}@${pkg.version}`;
        if (processed.has(key)) continue;
        processed.add(key);

        if (typeof onProgress === 'function') {
            onProgress(processed.size, queue.length, initialTotal, known.size, false, pkg);
        }

        const deps = fetchDependencyMap(pkg.name, pkg.version, tempDir, 'dependencies', depCache);
        const optional = fetchDependencyMap(pkg.name, pkg.version, tempDir, 'optionalDependencies', depCache);
        const merged = { ...deps, ...optional };

        for (const [name, range] of Object.entries(merged)) {
            try {
                const version = resolveVersionCached(name, range, tempDir, versionCache);
                const depKey = `${name}@${version}`;
                if (!known.has(depKey)) {
                    known.add(depKey);
                    const item = { name, version };
                    packages.push(item);
                    queue.push(item);
                }
            } catch (err) {
                failed.push(`${name}@${range || '*'}`);
            }
        }
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
    if (!cliProgress) {
        throw new Error('cli-progress 未初始化');
    }
    const versionCache = new Map();
    const processed = new Set();
    const failed = [];
    const beforeSize = known.size;
    const total = packages.length;
    const bar = new cliProgress.SingleBar(
        {
            format: '🔎 下载进度 |{bar}| {percentage}% {value}/{total} {pkg}',
            hideCursor: true,
            clearOnComplete: true
        },
        cliProgress.Presets.shades_classic
    );
    if (total > 0) {
        bar.start(total, 0, { pkg: '' });
    }

    for (let i = 0; i < packages.length; i += 1) {
        const pkg = packages[i];
        const index = i + 1;
        if (total > 0) {
            bar.update(index, { pkg: `${pkg.name}@${pkg.version}` });
        }
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

    if (total > 0) {
        bar.stop();
    }
    return { added: known.size - beforeSize, failed };
}

function packAllPackages(packages, tempDir, downloadDir) {
    if (!cliProgress) {
        throw new Error('cli-progress 未初始化');
    }
    const timeoutMs = Number(process.env.NPM_PACK_TIMEOUT_MS || '0') || 0;
    const failed = [];
    const total = packages.length;
    const bar = new cliProgress.SingleBar(
        {
            format: '📦 下载进度 |{bar}| {percentage}% {value}/{total} {pkg}',
            hideCursor: true,
            clearOnComplete: true
        },
        cliProgress.Presets.shades_classic
    );
    if (total > 0) {
        bar.start(total, 0, { pkg: '' });
    }
    for (let i = 0; i < packages.length; i += 1) {
        const pkg = packages[i];
        const index = i + 1;
        const spec = `${pkg.name}@${pkg.version}`;
        if (total > 0) {
            bar.update(index, { pkg: spec });
        }
        const fileName = tarballName(pkg.name, pkg.version);
        const destPath = path.join(downloadDir, fileName);

        if (fs.existsSync(destPath)) {
            continue;
        }

        const result = spawnSync('npm', ['pack', spec, '--pack-destination', downloadDir], {
            cwd: tempDir,
            encoding: 'utf8',
            timeout: timeoutMs > 0 ? timeoutMs : undefined
        });

        if (result.error || result.status !== 0) {
            const message = (result.stderr || result.stdout || '').trim();
            console.error(`❌ ${spec} 下载失败${message ? `: ${message}` : ''}`);
            failed.push(spec);
            continue;
        }
    }

    if (packages.length > 0) {
        bar.stop();
    }

    return failed;
}

function main() {
    console.log('🚀 开始使用 npm 解析依赖并批量下载...');
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

        runCommand('npm', ['install', 'cli-progress', '--no-save', '--no-audit', '--no-fund'], {
            cwd: tempDir,
            stdio: 'inherit'
        });

        cliProgress = loadCliProgress(tempDir);

        const tree = listDependencies(tempDir);
        const packages = collectDependencies(tree);
        const known = new Set(packages.map((pkg) => `${pkg.name}@${pkg.version}`));
        const lockData = loadLockData();
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

        if (process.env.NPM_EXPAND_REGISTRY !== '0') {
            try {
                console.log('🔎 开始扩展解析依赖，请耐心等待...');
                const registryBar = new cliProgress.SingleBar(
                    {
                        format: '⏳ 依赖解析进度 |{bar}| {percentage}% {value}/{total} 队列 {queued} 当前 {known} {pkg}',
                        hideCursor: true,
                        clearOnComplete: true
                    },
                    cliProgress.Presets.shades_classic
                );
                registryBar.start(1, 0, { queued: 0, known: packages.length, pkg: '' });

                expandFailed = expandDependencies(
                    packages,
                    known,
                    tempDir,
                    (done, queued, initialTotal, knownTotal, finished, current) => {
                        const totalEstimated = Math.max(initialTotal, done + queued);
                        if (typeof registryBar.setTotal === 'function') {
                            registryBar.setTotal(totalEstimated);
                        } else {
                            registryBar.total = totalEstimated;
                        }
                        const currentLabel = current ? `${current.name}@${current.version}` : '';
                        registryBar.update(done, {
                            queued,
                            known: knownTotal,
                            pkg: currentLabel
                        });
                        if (finished) {
                            registryBar.stop();
                            console.log(`✅ registry 扩展完成: 已处理 ${done}，当前总依赖 ${knownTotal}`);
                        }
                    }
                );
            } catch (err) {
                console.error(`❌ 扩展依赖失败: ${err.message}`);
            }
        }

        console.log(`📊 共解析出 ${packages.length} 个依赖项 (已去重)，开始下载...`);

        let failed = packAllPackages(packages, tempDir, DOWNLOAD_DIR);
        let tarballFailed = [];

        if (process.env.NPM_SKIP_TARBALL_EXPAND !== '1') {
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
                failed = failed.concat(packAllPackages(packages, tempDir, DOWNLOAD_DIR));
            }
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

main();
EOF
    
    # 执行npm包下载
    NPM_DOWNLOAD_DIR="$NPM_DOWNLOAD_DIR" node download_npm_temp.mjs
    
    # 清理临时文件
    rm -f download_npm_temp.mjs
    
    print_success "NPM包下载完成！"
    
    # ================= 下载 Python 包 =================
    if [ "${NPM_SKIP_PYTHON:-0}" = "1" ]; then
        print_info "跳过 Python 包下载 (NPM_SKIP_PYTHON=1)"
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
        return 0
    fi

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
