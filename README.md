# Sing-box 一键部署脚本

这是一个用于在 Linux 服务器上一键部署 [sing-box](https://sing-box.sagernet.org/) 的 Bash 脚本，专为追求极致网络性能和自动化配置的用户设计。

## 功能特性
- **协议支持**: 预配置 Hysteria2 和 TUIC v5 协议（独立端口）。
- **证书自动管理**: 集成 `acme.sh`，自动申请并续期 Let's Encrypt TLS 证书。
- **内核性能优化**:
    - 支持一键开启系统原生 BBR (v1)。
    - 支持一键安装/切换高性能内核以启用 BBR v3。
    - 自动调优 UDP 缓冲区以适配高速代理协议。
- **高兼容性**: 支持 Debian、Ubuntu、CentOS、Rocky Linux。
- **自动化安装**: 自动识别系统架构（amd64/arm64）并下载最新版程序。

## 使用方法

在服务器上以 root 权限直接运行以下命令即可开始部署：

```bash
curl -fsSL https://raw.githubusercontent.com/hdward-dev/singbox-onekey-deploy/main/install.sh | sudo bash
```

根据提示输入：
- 解析到该服务器的域名。
- Hysteria2 和 TUIC 的端口及密码。
- 选择 BBR 版本（推荐 BBR v1 以获得最大兼容性）。

## 注意事项
- **端口**: 请确保服务器防火墙（如 `ufw`, `firewalld` 或安全组）已放行您配置的端口。
- **BBR v3**: 选择 BBR v3 会自动安装第三方内核并修改引导设置，操作完成后**必须重启服务器**以生效。
- **证书**: 申请过程中会临时占用 80 端口，请确保 80 端口未被其他服务占用。

## 免责声明
本脚本仅供学习与个人网络优化使用。请遵守当地法律法规，切勿用于非法用途。
