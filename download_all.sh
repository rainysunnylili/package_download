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
import fs from 'fs-extra';
import path from 'path';
import pacote from 'pacote';
import pLimit from 'p-limit';
import { fileURLToPath } from 'url';

const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);

const LOCK_FILE_PATH = path.resolve(__dirname, 'package-lock.json');
const DOWNLOAD_DIR = process.env.NPM_DOWNLOAD_DIR || path.resolve(__dirname, 'npm-offline-packages');
const CONCURRENCY = 15;
const INCLUDE_DEV = true;
const TARGET_PLATFORMS = ['linux', 'win32', 'darwin'];
const TARGET_ARCHS = ['x64', 'arm64'];

const processedPackages = new Set();
const failedPackages = [];
const limit = pLimit(CONCURRENCY);

async function main() {
    console.log('🚀 开始全量依赖分析与下载...');
    
    if (!fs.existsSync(LOCK_FILE_PATH)) {
        console.error(`❌ 找不到文件: ${LOCK_FILE_PATH}`);
        return;
    }
    
    const lockData = fs.readJsonSync(LOCK_FILE_PATH);
    fs.ensureDirSync(DOWNLOAD_DIR);

    const queue = [];

    if (lockData.packages) {
        console.log('📦 检测到 Lockfile V2/V3 格式，开始解析...');
        for (const [pkgPath, meta] of Object.entries(lockData.packages)) {
            if (pkgPath === "") continue;
            if (!INCLUDE_DEV && meta.dev) continue;

            // 修复: 很多entry没有name字段，需要从path中解析
            let pkgName = meta.name;
            if (!pkgName && pkgPath.startsWith("node_modules/")) {
                const parts = pkgPath.split("node_modules/");
                pkgName = parts[parts.length - 1];
            }
            
            if (!pkgName) {
                // console.warn(`⚠️ 无法解析包名: ${pkgPath}`);
                continue;
            }

            if (meta.resolved && meta.version) {
                queue.push({ 
                    name: pkgName, 
                    version: meta.version,
                    resolved: meta.resolved,
                    integrity: meta.integrity
                });
            }
        }
    } else if (lockData.dependencies) {
        console.log('⚠️ 检测到旧版 Lockfile V1 格式。');
        // V1 格式通常需要递归，但这里简单处理顶层
        // 为了完整性，建议升级 lockfile
        // 这里做一个递归辅助函数
        function traverse(deps) {
            for (const [name, meta] of Object.entries(deps)) {
                 if (!INCLUDE_DEV && meta.dev) continue;
                 
                 queue.push({
                     name: name,
                     version: meta.version,
                     resolved: meta.resolved,
                     integrity: meta.integrity
                 });
                 
                 if (meta.dependencies) {
                     traverse(meta.dependencies);
                 }
            }
        }
        traverse(lockData.dependencies);
    }

    // 去重
    const uniqueQueue = [];
    const seen = new Set();
    for (const item of queue) {
        const key = `${item.name}@${item.version}`;
        if (!seen.has(key)) {
            seen.add(key);
            uniqueQueue.push(item);
        }
    }

    console.log(`📊 共解析出 ${uniqueQueue.length} 个依赖项 (已去重)，开始下载...`);

    const downloadTasks = uniqueQueue.map(pkg => limit(() => processPackage(pkg)));
    await Promise.all(downloadTasks);

    console.log('\n=============================================');
    if (failedPackages.length > 0) {
        console.log(`⚠️  完成，但有 ${failedPackages.length} 个包下载失败:`);
        failedPackages.forEach(f => console.log(` - ${f}`));
        fs.writeJsonSync(path.join(DOWNLOAD_DIR, 'failed_log.json'), failedPackages);
    } else {
        console.log(`✅ 所有依赖下载完成！文件数: ${fs.readdirSync(DOWNLOAD_DIR).length}`);
    }
    console.log('=============================================');
}

async function processPackage(pkg) {
    const pkgId = `${pkg.name}@${pkg.version}`;
    if (processedPackages.has(pkgId)) return;
    processedPackages.add(pkgId);

    try {
        await downloadTarball(pkg);

        // 检查可选依赖 (跨平台补全)
        // 只有当包名看起来像是可能有原生绑定时才去检查，或者对所有包检查
        // 为了确保 "win和linux都能用"，我们对所有包尝试获取 manifest 查看 optionalDependencies
        const manifest = await pacote.manifest(pkgId, { 
            fullMetadata: true,
            preferOnline: true 
        }).catch(() => null);

        if (manifest && manifest.optionalDependencies) {
            const optionalDeps = Object.keys(manifest.optionalDependencies);
            if (optionalDeps.length > 0) {
                for (const depName of optionalDeps) {
                    const depVersion = manifest.optionalDependencies[depName];
                    if (shouldDownloadPlatformSpecific(depName)) {
                        const childPkgId = `${depName}@${depVersion}`;
                        if (!processedPackages.has(childPkgId)) {
                            // console.log(`🔍 补全跨平台包: ${childPkgId}`);
                            await limit(() => processPackage({ name: depName, version: depVersion }));
                        }
                    }
                }
            }
        }

    } catch (err) {
        // console.error(`❌ 下载失败 [${pkgId}]: ${err.message}`);
        failedPackages.push(pkgId);
    }
}

async function downloadTarball(pkg) {
    const safeName = pkg.name.replace(/\//g, '-');
    const fileName = `${safeName}-${pkg.version}.tgz`;
    const destPath = path.join(DOWNLOAD_DIR, fileName);

    if (fs.existsSync(destPath)) {
        return;
    }

    const spec = pkg.resolved || `${pkg.name}@${pkg.version}`;
    // console.log(`⬇️  下载: ${pkg.name}@${pkg.version}`);
    process.stdout.write('.'); // 进度条效果
    
    await pacote.tarball.file(spec, destPath, {
        integrity: pkg.integrity,
        timeout: 60000,
        retry: { retries: 3 }
    });
}

function shouldDownloadPlatformSpecific(pkgName) {
    // 只要是 optional dependency，并且包含我们目标平台关键词的，都下载
    // 或者它可能没有任何平台关键词（通用包），也下载以防万一
    const isPlatformSpecific = TARGET_PLATFORMS.some(p => pkgName.includes(p));
    // 如果它包含其他平台的关键词（如 android, freebsd），则跳过
    // 这里我们只关心 win32, linux, darwin
    // 如果包名包含 'android' 但不包含 'linux' (虽然android是linux内核，但通常npm包区分)，可以过滤
    // 简单起见，只要包含目标平台，或者完全不包含任何平台特征（可能是通用补充包），就下载
    
    const knownPlatforms = ['linux', 'win32', 'darwin', 'android', 'freebsd', 'sunos', 'netbsd', 'openbsd'];
    const hasPlatformKeyword = knownPlatforms.some(p => pkgName.includes(p));
    
    if (!hasPlatformKeyword) return true; // 没有平台关键词，可能是通用包，下载
    
    return TARGET_PLATFORMS.some(p => pkgName.includes(p));
}

main().catch(err => {
    console.error('Fatal Error:', err);
});
EOF
    
    # 安装必要的依赖（如果还没有）
    if [ ! -d "node_modules" ]; then
        print_info "安装npm下载工具的依赖..."
        npm install
    fi
    
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
