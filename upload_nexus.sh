#!/usr/bin/env bash
set -e

# ================= 配置区 =================
# 你可以在这里修改默认值，或者通过环境变量传递
# 例如: NEXUS_PASS=mypassword ./upload_nexus.sh

NEXUS_URL="${NEXUS_URL:-http://localhost:8081}"
NEXUS_USER="${NEXUS_USER:-admin}"
NEXUS_PASS="${NEXUS_PASS:-admin123}"
NPM_REPO="${NPM_REPO:-npm-hosted}"
PYPI_REPO="${PYPI_REPO:-pypi-hosted}"

# ================= 脚本逻辑 =================

SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
NPM_DIR="$SCRIPT_DIR/downloads/npm-packages"
PYPI_DIR="$SCRIPT_DIR/downloads/python-packages"

# 颜色输出
GREEN='\033[0;32m'
BLUE='\033[0;34m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
NC='\033[0m'

echo -e "${BLUE}================================================${NC}"
echo -e "${BLUE}      Nexus 批量上传脚本${NC}"
echo -e "${BLUE}================================================${NC}"
echo -e "Nexus URL : ${YELLOW}$NEXUS_URL${NC}"
echo -e "用户      : ${YELLOW}$NEXUS_USER${NC}"
echo -e "NPM 仓库  : ${YELLOW}$NPM_REPO${NC}"
echo -e "PyPI 仓库 : ${YELLOW}$PYPI_REPO${NC}"
echo -e "${BLUE}================================================${NC}"

# 检查目录
if [ ! -d "$NPM_DIR" ] || [ ! -d "$PYPI_DIR" ]; then
    echo -e "${RED}❌ 错误: 未找到下载目录。请先运行 download_all.sh${NC}"
    echo "检查路径: $NPM_DIR 和 $PYPI_DIR"
    exit 1
fi

# 1. 上传 Python 包
echo ""
echo -e "${BLUE}>>> [Step 1/2] 上传 Python 包 (Python 3.13)...${NC}"

# 检查是否有文件
if [ -z "$(ls -A "$PYPI_DIR" 2>/dev/null)" ]; then
    echo -e "${YELLOW}⚠️  Python 包目录为空，跳过。${NC}"
else
    # 检查并安装 twine
    if ! command -v twine &> /dev/null; then
        echo "正在安装 twine (用于上传 PyPI 包)..."
        pip install twine -q
    fi

    echo "正在上传到: ${NEXUS_URL}/repository/${PYPI_REPO}/"
    
    # 使用 twine 上传
    # --skip-existing 忽略已存在的包错误
    twine upload \
        --repository-url "${NEXUS_URL}/repository/${PYPI_REPO}/" \
        -u "$NEXUS_USER" \
        -p "$NEXUS_PASS" \
        --skip-existing \
        --non-interactive \
        "$PYPI_DIR"/* || echo -e "${YELLOW}部分包上传可能失败或已存在${NC}"
        
    echo -e "${GREEN}✅ Python 包处理完成${NC}"
fi

# 2. 上传 NPM 包
echo ""
echo -e "${BLUE}>>> [Step 2/2] 上传 NPM 包...${NC}"

if [ -z "$(ls -A "$NPM_DIR"/*.tgz 2>/dev/null)" ]; then
    echo -e "${YELLOW}⚠️  NPM 包目录为空，跳过。${NC}"
else
    # 生成临时 .npmrc 用于认证
    NPMRC_FILE="$SCRIPT_DIR/.npmrc.temp"
    
    # 移除 URL 中的协议头，用于 //registry... 格式
    HOST_PATH="${NEXUS_URL#*://}"
    # 生成 Base64 认证串
    AUTH_TOKEN=$(echo -n "${NEXUS_USER}:${NEXUS_PASS}" | base64 -w 0)

    # 写入配置
    cat > "$NPMRC_FILE" << EOF
registry=${NEXUS_URL}/repository/${NPM_REPO}/
//${HOST_PATH}/repository/${NPM_REPO}/:_auth=${AUTH_TOKEN}
email=upload-script@local
always-auth=true
EOF

    echo "已生成临时认证配置: $NPMRC_FILE"

    COUNT=0
    TOTAL=$(ls "$NPM_DIR"/*.tgz | wc -l)
    
    for file in "$NPM_DIR"/*.tgz; do
        ((COUNT++))
        FILENAME=$(basename "$file")
        echo -ne "正在上传 [$COUNT/$TOTAL]: $FILENAME ... \r"
        
        # 尝试上传
        if npm publish "$file" --userconfig "$NPMRC_FILE" --quiet > /dev/null 2>&1; then
            echo -e "正在上传 [$COUNT/$TOTAL]: $FILENAME ${GREEN}OK${NC}"
        else
            # 如果失败，可能是包已存在 (E403/E400)，这里只打印警告不退出
            echo -e "正在上传 [$COUNT/$TOTAL]: $FILENAME ${YELLOW}Skip/Fail${NC}"
        fi
    done
    
    # 清理
    rm -f "$NPMRC_FILE"
    echo -e "${GREEN}✅ NPM 包处理完成${NC}"
fi

echo ""
echo -e "${BLUE}🎉 所有任务执行完毕!${NC}"
