#!/bin/bash
# Small-Hacker Optimized Vless+Argo & TUIC v5 (LXC Ready)
# 支持并行运行 Vless+Argo 和 TUIC v5

set -e

# 颜色
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m'

# 工作目录
WORKDIR="$HOME/.cyber-proxy"
BIN_DIR="$WORKDIR/bin"
CONFIG_FILE="$WORKDIR/config.json"
SB_BINARY="$BIN_DIR/sing-box"
CF_BINARY="$BIN_DIR/cloudflared"
CERT_DIR="$WORKDIR/cert"

# 1. 架构自适应
get_arch() {
    case "$(uname -m)" in
        x86_64)  echo "amd64" ;;
        aarch64) echo "arm64" ;;
        armv7l)  echo "armv7" ;;
        *)       echo "unknown" ;;
    esac
}

ARCH=$(get_arch)

init_dirs() {
    mkdir -p "$BIN_DIR" "$CERT_DIR"
}

# 2. 组件下载
download_components() {
    echo -e "${BLUE}检测架构: $ARCH. 获取组件...${NC}"
    if [ ! -f "$SB_BINARY" ]; then
        local LATEST_SB=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | grep tag_name | cut -d '"' -f 4 | sed 's/v//')
        local SB_URL="https://github.com/SagerNet/sing-box/releases/download/v${LATEST_SB}/sing-box-${LATEST_SB}-linux-${ARCH}.tar.gz"
        curl -L "$SB_URL" -o /tmp/sb.tar.gz
        tar -xzf /tmp/sb.tar.gz -C /tmp
        find /tmp/sing-box-${LATEST_SB}-linux-${ARCH} -name "sing-box" -exec mv {} "$SB_BINARY" \;
        chmod +x "$SB_BINARY"
    fi
    if [ ! -f "$CF_BINARY" ]; then
        local CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-${ARCH}"
        [ "$ARCH" == "arm64" ] && CF_URL="https://github.com/cloudflare/cloudflared/releases/latest/download/cloudflared-linux-arm64"
        curl -L "$CF_URL" -o "$CF_BINARY"
        chmod +x "$CF_BINARY"
    fi
}

# 3. 生成并行配置
generate_dual_config() {
    local vless_port=$1
    local tuic_port=$2
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local vless_path="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
    local tuic_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
    
    if [ ! -f "$CERT_DIR/cert.pem" ]; then
        openssl req -x509 -nodes -newkey rsa:2048 -keyout "$CERT_DIR/privkey.pem" -out "$CERT_DIR/cert.pem" -days 3650 -subj "/CN=google.com" 2>/dev/null
    fi

    cat > "$CONFIG_FILE" <<EOF
{
  "log": { "level": "error" },
  "inbounds": [
    {
      "type": "vless",
      "tag": "vless-ws-in",
      "listen": "127.0.0.1",
      "listen_port": $vless_port,
      "users": [{ "uuid": "$uuid" }],
      "transport": { "type": "ws", "path": "$vless_path" }
    },
    {
      "type": "tuic",
      "tag": "tuic-in",
      "listen": "::",
      "listen_port": $tuic_port,
      "users": [{ "uuid": "$uuid", "password": "$tuic_pass" }],
      "congestion_control": "bbr",
      "zero_rtt_handshake": true,
      "tls": {
        "enabled": true,
        "certificate_path": "$CERT_DIR/cert.pem",
        "key_path": "$CERT_DIR/privkey.pem",
        "alpn": ["h3"]
      }
    }
  ],
  "outbounds": [{ "type": "direct", "tag": "direct" }]
}
EOF
    # 保存参数
    echo "$uuid" > "$WORKDIR/uuid.txt"
    echo "$vless_path" > "$WORKDIR/vless_path.txt"
    echo "$vless_port" > "$WORKDIR/vless_port.txt"
    echo "$tuic_pass" > "$WORKDIR/tuic_pass.txt"
    echo "$tuic_port" > "$WORKDIR/tuic_port.txt"
}

# 4. 安装并运行服务
setup_services() {
    local user_name=$(whoami)
    local vless_port=$(cat "$WORKDIR/vless_port.txt")
    local argo_token=$(cat "$WORKDIR/argo_token.txt" 2>/dev/null || echo "")
    
    # Sing-box
    sudo tee /etc/systemd/system/cyber-sb.service > /dev/null <<EOF
[Unit]
Description=Cyber Dual Proxy Service
After=network.target
[Service]
ExecStart=$SB_BINARY run -c $CONFIG_FILE
Restart=always
User=$user_name
WorkingDirectory=$WORKDIR
[Install]
WantedBy=multi-user.target
EOF

    # Argo Tunnel
    local argo_cmd="$CF_BINARY tunnel --url http://127.0.0.1:$vless_port"
    if [ -n "$argo_token" ]; then
        argo_cmd="$CF_BINARY tunnel run --token $argo_token"
    fi

    sudo tee /etc/systemd/system/cyber-argo.service > /dev/null <<EOF
[Unit]
