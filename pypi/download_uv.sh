#!/usr/bin/env bash
set -euo pipefail

# ================= 配置区 =================
# 输出目录
DOWNLOAD_DIR="./wheels"
# 你的依赖文件
REQUIREMENTS="requirements.txt"
# Python 版本 (3.13)
PY_VER="313"
# 目标平台定义
PLATFORMS=("win_amd64" "manylinux2014_x86_64")

# 🔥 新增：清华镜像源地址
MIRROR_URL="https://pypi.tuna.tsinghua.edu.cn/simple"

# ================= 逻辑区 =================

if [ ! -f "$REQUIREMENTS" ]; then
    echo "❌ 错误: 找不到 $REQUIREMENTS 文件"
    exit 1
fi

mkdir -p "$DOWNLOAD_DIR"

echo "📦 准备下载 Python 3.13 的依赖包 (Windows + Linux)..."
echo "🌐 使用镜像源: $MIRROR_URL"
echo "📂 保存目录: $DOWNLOAD_DIR"

for PLATFORM in "${PLATFORMS[@]}"; do
    echo "---------------------------------------------------"
    echo "🚀 [正在处理平台]: $PLATFORM"
    echo "---------------------------------------------------"

    if pip download \
        -r "$REQUIREMENTS" \
        --dest "$DOWNLOAD_DIR" \
        --index-url "$MIRROR_URL" \
        --only-binary=:all: \
        --platform "$PLATFORM" \
        --python-version "$PY_VER" \
        --implementation cp \
        --abi "cp${PY_VER}"; then
        
        echo "✅ [${PLATFORM}] 下载完成"
    else
        echo "⚠️ [${PLATFORM}] 下载出现问题，请检查网络或包是否存在"
    fi
done

echo "---------------------------------------------------"
echo "🎉 任务结束！结果已保存于 $DOWNLOAD_DIR"
