#!/bin/bash
# Small-Hacker LXC Proxy Master - Entry Script (Fixed for Piping)
set -e

RED='\033[0;31m'; GREEN='\033[0;32m'; YELLOW='\033[1;33m'; BLUE='\033[0;34m'; CYAN='\033[0;36m'; NC='\033[0m'
BASE_URL="https://raw.githubusercontent.com/hynize/singbox/main"

[[ $EUID -ne 0 ]] && echo -e "${RED}错误: 必须使用 root 运行。${NC}" && exit 1

install_deps() {
    echo -e "${BLUE}检查系统依赖...${NC}"
    if ! command -v curl &> /dev/null || ! command -v wget &> /dev/null; then
        apt-get update && apt-get install -y curl wget openssl jq
    fi
}

show_menu() {
    clear
    echo -e "${CYAN}================================================${NC}"
    echo -e "${CYAN}   Small-Hacker LXC Proxy Master  👾${NC}"
    echo -e "${CYAN}================================================${NC}"
    echo -e "1. 安装 Argo + Hysteria2 (双路并行/暴力穿透)"
    echo -e "2. 安装 Argo + TUIC v5    (双路并行/极速响应)"
    echo -e "3. 彻底卸载所有代理服务"
    echo -e "4. 退出"
    echo -e "------------------------------------------------"
    # 强制从 /dev/tty 读取键盘输入
    read -p "请输入选项 [1-4]: " choice < /dev/tty
}

install_deps
show_menu

case $choice in
    1) wget -qO argo-hy2 ${BASE_URL}/argo-hy2 && chmod +x argo-hy2 && ./argo-hy2 ;;
    2) wget -qO argo-tuic ${BASE_URL}/argo-tuic && chmod +x argo-tuic && ./argo-tuic ;;
    3) wget -qO argo-hy2 ${BASE_URL}/argo-hy2 && chmod +x argo-hy2 && ./argo-hy2 <<EOF
3
EOF
    ;;
    *) exit 0 ;;
esac
