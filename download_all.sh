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

const ROOT_DIR = process.cwd();
const PACKAGE_JSON_PATH = path.join(ROOT_DIR, 'package.json');
const PACKAGE_LOCK_PATH = path.join(ROOT_DIR, 'package-lock.json');
const NPMRC_PATH = path.join(ROOT_DIR, '.npmrc');
const DOWNLOAD_DIR = process.env.NPM_DOWNLOAD_DIR || path.join(ROOT_DIR, 'npm-offline-packages');

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

function tarballName(pkgName, version) {
    const safeName = pkgName.startsWith('@')
        ? pkgName.slice(1).replace(/\//g, '-')
        : pkgName.replace(/\//g, '-');
    return `${safeName}-${version}.tgz`;
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

        const tree = listDependencies(tempDir);
        const packages = collectDependencies(tree);
        const known = new Set(packages.map((pkg) => `${pkg.name}@${pkg.version}`));
        const lockData = loadLockData();
        const peerDeps = collectPeerDependenciesFromLock(lockData);
        const peerFailed = [];

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

        console.log(`📊 共解析出 ${packages.length} 个依赖项 (已去重)，开始下载...`);

        const failed = [];
        for (const pkg of packages) {
            const spec = `${pkg.name}@${pkg.version}`;
            const fileName = tarballName(pkg.name, pkg.version);
            const destPath = path.join(DOWNLOAD_DIR, fileName);

            if (fs.existsSync(destPath)) {
                continue;
            }

            const result = spawnSync('npm', ['pack', spec, '--pack-destination', DOWNLOAD_DIR], {
                cwd: tempDir,
                encoding: 'utf8'
            });

            if (result.error || result.status !== 0) {
                const message = (result.stderr || result.stdout || '').trim();
                console.error(`❌ ${spec} 下载失败${message ? `: ${message}` : ''}`);
                failed.push(spec);
                continue;
            }
            process.stdout.write('.');
        }
        if (packages.length > 0) {
            process.stdout.write('\n');
        }

        if (failed.length || peerFailed.length) {
            const allFailed = failed.concat(peerFailed);
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
