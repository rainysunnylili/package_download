import fs from 'fs-extra';
import path from 'path';
import pacote from 'pacote';
import pLimit from 'p-limit';
import { fileURLToPath } from 'url';

// ================= ESM 兼容性处理 =================
const __filename = fileURLToPath(import.meta.url);
const __dirname = path.dirname(__filename);
// ===============================================

// ================= 配置区 =================
// 你的 lock 文件
const LOCK_FILE_PATH = path.resolve(__dirname, 'package-lock.json');
// 下载目录
const DOWNLOAD_DIR = path.resolve(__dirname, 'npm-offline-packages');

// 并发数
const CONCURRENCY = 15;
// 是否包含开发依赖
const INCLUDE_DEV = true; 

// 强制下载所有平台的包
const TARGET_PLATFORMS = ['linux', 'win32', 'darwin'];
const TARGET_ARCHS = ['x64', 'arm64'];
// =========================================

const processedPackages = new Set();
const failedPackages = [];
const limit = pLimit(CONCURRENCY);

async function main() {
    console.log('🚀 开始全量依赖分析与下载 (ESM Mode)...');
    
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

            if (meta.resolved && meta.name && meta.version) {
                queue.push({ 
                    name: meta.name, 
                    version: meta.version,
                    resolved: meta.resolved,
                    integrity: meta.integrity
                });
            }
        }
    } else if (lockData.dependencies) {
        console.log('⚠️ 检测到旧版 Lockfile V1 格式。');
        for (const [name, meta] of Object.entries(lockData.dependencies)) {
             if (!INCLUDE_DEV && meta.dev) continue;
             queue.push({
                 name: name,
                 version: meta.version,
                 resolved: meta.resolved,
                 integrity: meta.integrity
             });
        }
    }

    console.log(`📊 共解析出 ${queue.length} 个基础依赖项，开始下载...`);

    const downloadTasks = queue.map(pkg => limit(() => processPackage(pkg)));

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
                            console.log(`🔍 补全跨平台包: ${childPkgId}`);
                            await limit(() => processPackage({ name: depName, version: depVersion }));
                        }
                    }
                }
            }
        }

    } catch (err) {
        console.error(`❌ 下载失败 [${pkgId}]: ${err.message}`);
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

    console.log(`⬇️  下载: ${pkg.name}@${pkg.version}`);
    
    // 【修改点】这里从 toFile 改成了 file
    await pacote.tarball.file(spec, destPath, {
        integrity: pkg.integrity,
        timeout: 60000,
        retry: { retries: 3 }
    });
}

function shouldDownloadPlatformSpecific(pkgName) {
    const isPlatformSpecific = TARGET_PLATFORMS.some(p => pkgName.includes(p));
    const isArchSpecific = TARGET_ARCHS.some(a => pkgName.includes(a));
    return isPlatformSpecific || isArchSpecific;
}

main().catch(err => {
    console.error('Fatal Error:', err);
});
