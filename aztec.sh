#!/usr/bin/env bash
set -euo pipefail

CYAN='\033[0;36m'
BOLD='\033[1m'
RESET='\033[0m'

echo -e "${CYAN}${BOLD}"
echo "               修改自 雪糕战神  @Xuegaogx"
echo ""

# ====================================================
# Aztec alpha-testnet 节点自动部署脚本（macOS 版）
# 版本：v0.85.0-alpha-testnet.5
# 系统：macOS（Apple Silicon/Intel）
# 依赖：自动安装 Docker（Desktop 或 Colima）
# ====================================================

# 检查是否为 macOS
if [[ "$(uname)" != "Darwin" ]]; then
  echo "❌ 此脚本仅支持 macOS 系统！"
  exit 1
fi

# 函数：安装 Docker
install_docker() {
  echo "🐋 未检测到 Docker，开始自动安装..."
  
  # 检查是否已安装 Homebrew
  if ! command -v brew &> /dev/null; then
    echo "🍺 正在安装 Homebrew..."
    /bin/bash -c "$(curl -fsSL https://raw.githubusercontent.com/Homebrew/install/HEAD/install.sh)"
    echo 'eval "$(/opt/homebrew/bin/brew shellenv)"' >> ~/.zprofile
    eval "$(/opt/homebrew/bin/brew shellenv)"
  fi

  # 提供两种安装选项
  echo -e "${CYAN}${BOLD}"
  echo "请选择 Docker 安装方式："
  echo "1. Docker Desktop（图形界面，推荐新手）"
  echo "2. Colima（命令行，轻量级）"
  echo -e "${RESET}"
  read -p "▶️ 输入选择 (1/2): " DOCKER_CHOICE

  case $DOCKER_CHOICE in
    1)
      echo "📦 正在安装 Docker Desktop..."
      brew install --cask docker
      open /Applications/Docker.app
      echo "⏳ 等待 Docker Desktop 启动（约30秒），请确认完成初始化..."
      sleep 30
      ;;
    2)
      echo "🚀 正在安装 Colima + Docker CLI..."
      brew install colima docker docker-compose
      colima start --arch aarch64 --memory 4
      ;;
    *)
      echo "❌ 无效选择，默认安装 Docker Desktop"
      brew install --cask docker
      ;;
  esac

  # 验证安装
  if ! command -v docker &> /dev/null; then
    echo "❌ Docker 安装失败，请手动安装后重试！"
    exit 1
  fi
  echo "✅ Docker 安装成功！"
}

# 检查并安装 Docker
if ! command -v docker &> /dev/null; then
  install_docker
else
  echo "🐋 Docker 已安装。"
fi

# 检查 Docker Compose
if ! command -v docker-compose &> /dev/null; then
  echo "📦 正在安装 Docker Compose..."
  brew install docker-compose
fi

# 检查 Node.js
if ! command -v node &> /dev/null; then
  echo "🟢 正在通过 Homebrew 安装 Node.js..."
  brew install node
else
  echo "🟢 Node.js 已安装。"
fi

# 安装 Aztec CLI
echo "⚙️ 正在安装 Aztec CLI 并初始化测试网环境..."
curl -sL https://install.aztec.network | bash

export PATH="$HOME/.aztec/bin:$PATH"

if ! command -v aztec-up &> /dev/null; then
  echo "❌ Aztec CLI 安装失败，请检查网络或重试。"
  exit 1
fi

aztec-up alpha-testnet

# 提示获取 RPC
echo -e "\n📋 RPC URL 获取说明："
echo "  🔹 执行客户端（EL）RPC 获取方法："
echo "     1. 前往 https://dashboard.alchemy.com/"
echo "     2. 创建 Sepolia 网络 App"
echo "     3. 复制 HTTPS URL（如：https://eth-sepolia.g.alchemy.com/v2/你的KEY）"
echo ""
echo "  🔹 共识客户端（CL）RPC 获取方法："
echo "     1. 前往 https://drpc.org/"
echo "     2. 创建 Sepolia API Key"
echo "     3. 复制 URL（如：https://lb.drpc.org/ogrpc?network=sepolia&dkey=你的KEY）"
echo ""

# 输入配置
read -p "▶️ 执行客户端（EL）RPC URL: " ETH_RPC
read -p "▶️ 共识客户端（CL）RPC URL: " CONS_RPC
read -p "▶️ Blob Sink URL（可留空）: " BLOB_URL
read -p "▶️ 验证者私钥: " VALIDATOR_PRIVATE_KEY

# 获取公网 IP
echo "🌐 正在获取公网 IP..."
PUBLIC_IP=$(curl -s ifconfig.me || echo "127.0.0.1")
echo "    → 检测到公网 IP: $PUBLIC_IP"

# 生成 .env 文件
cat > .env <<EOF
ETHEREUM_HOSTS="$ETH_RPC"
L1_CONSENSUS_HOST_URLS="$CONS_RPC"
P2P_IP="$PUBLIC_IP"
VALIDATOR_PRIVATE_KEY="$VALIDATOR_PRIVATE_KEY"
DATA_DIRECTORY="/data"
LOG_LEVEL="debug"
EOF

if [ -n "$BLOB_URL" ]; then
  echo "BLOB_SINK_URL=\"$BLOB_URL\"" >> .env
fi

# 构造 blobFlag
BLOB_FLAG=""
if [ -n "$BLOB_URL" ]; then
  BLOB_FLAG="--sequencer.blobSinkUrl \$BLOB_SINK_URL"
fi

# 生成 docker-compose.yml
cat > docker-compose.yml <<EOF
version: "3.8"
services:
  node:
    image: aztecprotocol/aztec:0.85.0-alpha-testnet.5
    network_mode: host
    environment:
      - ETHEREUM_HOSTS=\${ETHEREUM_HOSTS}
      - L1_CONSENSUS_HOST_URLS=\${L1_CONSENSUS_HOST_URLS}
      - P2P_IP=\${P2P_IP}
      - VALIDATOR_PRIVATE_KEY=\${VALIDATOR_PRIVATE_KEY}
      - DATA_DIRECTORY=\${DATA_DIRECTORY}
      - LOG_LEVEL=\${LOG_LEVEL}
      - BLOB_SINK_URL=\${BLOB_SINK_URL:-}
    entrypoint: >
      sh -c 'node --no-warnings /usr/src/yarn-project/aztec/dest/bin/index.js start --network alpha-testnet --node --archiver --sequencer $BLOB_FLAG'
    volumes:
      - $(pwd)/data:/data
EOF

mkdir -p data

# 启动节点
echo "🚀 正在启动 Aztec 节点（docker-compose up -d）..."
docker-compose up -d

# 成功提示
echo -e "\n✅ 节点已成功启动！"
echo "   - 查看日志：docker-compose logs -f"
echo "   - 数据目录：$(pwd)/data"
echo "   - 停止节点：docker-compose down"