#!/bin/bash
# Small-Hacker Optimized Vless+Argo & Hysteria2 (LXC Ready)
# 支持并行运行 Vless+Argo 和 Hysteria2

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
    local hy2_port=$2
    local uuid=$(cat /proc/sys/kernel/random/uuid)
    local vless_path="/$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)"
    local hy2_pass=$(head /dev/urandom | tr -dc A-Za-z0-9 | head -c 12)
    
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
      "type": "hysteria2",
      "tag": "hy2-in",
      "listen": "::",
      "listen_port": $hy2_port,
      "users": [{ "password": "$hy2_pass" }],
      "ignore_client_bandwidth": false,
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
    echo "$hy2_pass" > "$WORKDIR/hy2_pass.txt"
    echo "$hy2_port" > "$WORKDIR/hy2_port.txt"
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
Description=Cyber Argo Tunnel
After=network.target
[Service]
ExecStart=$argo_cmd
Restart=always
User=$user_name
WorkingDirectory=$WORKDIR
[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    sudo systemctl enable --now cyber-sb cyber-argo
}

# 5. 卸载
uninstall() {
    echo -e "${RED}正在注销并清理...${NC}"
    sudo systemctl disable --now cyber-sb cyber-argo 2>/dev/null || true
    sudo rm -f /etc/systemd/system/cyber-sb.service /etc/systemd/system/cyber-argo.service
    sudo systemctl daemon-reload
    rm -rf "$WORKDIR"
    echo -e "${GREEN}清理完成。${NC}"
}

# 6. 展示双链接
show_results() {
    echo -e "\n${GREEN}=== 并行环境部署完成 ===${NC}"
    
    local uuid=$(cat "$WORKDIR/uuid.txt")
    local path=$(cat "$WORKDIR/vless_path.txt")
    local preferred="saas.sin.fan"
    local fixed_domain=$(cat "$WORKDIR/argo_domain.txt" 2>/dev/null || echo "")
    
    # 1. Argo 结果
    if [ -n "$fixed_domain" ]; then
        echo -e "${CYAN}[1] Vless + Argo (固定隧道)${NC}"
        local vless_link="vless://${uuid}@${preferred}:443?encryption=none&security=tls&sni=${fixed_domain}&host=${fixed_domain}&fp=chrome&type=ws&path=$(echo $path | sed 's/\//%2F/g')#Argo_Fixed"
        echo -e "固定域名: $fixed_domain"
        echo -e "节点链接: $vless_link"
    else
        echo -e "${YELLOW}正在打通 Argo 临时隧道 (8秒)...${NC}"
        sleep 8
        local raw_domain=$(sudo journalctl -u cyber-argo --no-hostname -n 50 | grep -o 'https://[a-zA-Z0-9-]*\.trycloudflare\.com' | tail -1 | sed 's#https://##')
        if [ -n "$raw_domain" ]; then
            local vless_link="vless://${uuid}@${preferred}:443?encryption=none&security=tls&sni=${raw_domain}&host=${raw_domain}&fp=chrome&type=ws&path=$(echo $path | sed 's/\//%2F/g')#Argo_Temp"
            echo -e "\n${CYAN}[1] Vless + Argo (临时隧道)${NC}"
            echo -e "临时域名: $raw_domain"
            echo -e "节点链接: $vless_link"
        fi
    fi

    # 2. Hysteria2 结果
    local hy2_port=$(cat "$WORKDIR/hy2_port.txt")
    local hy2_pass=$(cat "$WORKDIR/hy2_pass.txt")
    local ip=$(curl -s ifconfig.me)
    local hy2_link="hysteria2://${hy2_pass}@${ip}:${hy2_port}?sni=google.com&insecure=1#Hy2_Dual"
    
    echo -e "\n${CYAN}[2] Hysteria2 (UDP专精)${NC}"
    echo -e "IP: $ip, 端口: $hy2_port"
    echo -e "节点链接: $hy2_link"
}

# 菜单
clear
echo -e "${CYAN}Small-Hacker LXC Proxy Master (Dual Mode)${NC}"
echo "1. 一键安装并运行 (Argo + Hy2 并行)"
echo "2. 仅查看当前链接"
echo "3. 彻底卸载"
echo "4. 退出"
read -p "指令 [1-4]: " choice

case $choice in
    1)
        init_dirs && download_components
        echo -e "\n${YELLOW}Argo 隧道配置:${NC}"
        echo "1) 临时隧道 (无需配置)"
        echo "2) 固定隧道 (需输入 Token 和域名)"
        read -p "选择 [1]: " argo_mode
        if [ "$argo_mode" == "2" ]; then
            read -p "请输入 Cloudflare Tunnel Token: " token
            read -p "请输入对应的固定域名: " domain
            echo "$token" > "$WORKDIR/argo_token.txt"
            echo "$domain" > "$WORKDIR/argo_domain.txt"
        else
            rm -f "$WORKDIR/argo_token.txt" "$WORKDIR/argo_domain.txt"
        fi

        read -p "Vless 本地端口 (默认随机): " vp
        [ -z "$vp" ] && vp=$(shuf -i 10000-20000 -n 1)
        read -p "Hy2 外部端口 (默认随机): " hp
        [ -z "$hp" ] && hp=$(shuf -i 20000-60000 -n 1)
        generate_dual_config $vp $hp
        setup_services
        show_results
        ;;
    2)
        [ -f "$WORKDIR/vless_port.txt" ] && show_results || echo "未发现已安装的服务。"
        ;;
    3)
        uninstall
        ;;
    *)
        exit 0
        ;;
esac
