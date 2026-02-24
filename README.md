Small-Hacker LXC Proxy Master

这是一个专为 LXC 容器 优化的代理一键脚本系列。由黑客 AI “小小”重构，修复了原版脚本在架构适配、服务持久化、以及优选域名支持上的多个痛点。

🚀 一键安装命令

方案 A：Argo + Hysteria2 并行版 (暴力穿透)

适合网络环境较差、丢包严重，或者需要玩游戏、看 4K 视频的老板。Hy2 具备极强的 UDP 暴力穿透能力。

wget -O rebuilt_argo.sh https://raw.githubusercontent.com/hynize/singbox/main/rebuilt_argo.sh && chmod +x rebuilt_argo.sh && ./rebuilt_argo.sh

方案 B：Argo + TUIC v5 并行版 (UDP 极速)

适合网络环境较好，追求低延迟、高效率握手的场景。

wget -O argo-tuic https://raw.githubusercontent.com/hynize/singbox/main/argo-tuic && chmod +x argo-tuic && ./argo-tuic

───

✨ 核心亮点

1. 架构自适应：自动检测 amd64 / arm64 架构，完美适配甲骨文 ARM、树莓派等环境。
2. 双路并行：Vless+Argo 与 UDP 协议（Hy2/TUIC）同时运行，互不干扰，灵活切换。
3. 固定/临时隧道可选：支持交互式输入 Cloudflare Token 绑定固定域名，也支持一键生成临时隧道。
4. 优选域名集成：Argo 节点自动配置优选域名 saas.sin.fan，大幅提升直连速度。
5. 持久化守护：使用 systemd 托管服务，支持开机自启和进程崩溃自动重启。
6. 安全纯净：所有文件存放在 ~/.cyber-proxy 隐藏目录，一键彻底卸载，不留残留。

🛠️ 注意事项

• UDP 端口：在使用 Hysteria2 或 TUIC 协议时，请务必在 VPS 安全组中放行相应的 UDP 端口。
• 证书验证：由于使用自签名证书，请在客户端开启 “跳过证书验证 (AllowInsecure/true)”。
• Argo 延迟：临时隧道获取域名通常需要 8 秒左右，请耐心等待脚本输出。
