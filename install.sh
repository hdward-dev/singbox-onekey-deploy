#!/usr/bin/env bash

# Sing-box 一键部署脚本
# 作者: Opencode
# 日期: 2026-03-11

# --- 主执行流程 ---

echo "--- Sing-box 部署配置 ---"
read -p "请输入域名: " domain
read -p "Hysteria2 端口: " hy2_port
read -p "Hysteria2 密码: " hy2_password
read -p "TUIC 端口: " tuic_port
read -p "TUIC 密码: " tuic_password
echo "$domain" > /tmp/domain.txt

# 检查是否为 Root 用户
if [[ $EUID -ne 0 ]]; then
   echo "此脚本必须以 root 权限运行。" 
   exit 1
fi

# 检测操作系统和架构
os_check() {
    if [ -f /etc/debian_version ]; then
        OS="debian"
    elif [ -f /etc/redhat-release ]; then
        if grep -q "Rocky" /etc/redhat-release; then
            OS="rocky"
        else
            OS="centos"
        fi
    else
        echo "不支持的操作系统。"
        exit 1
    fi
}

# 安装依赖
install_dependencies() {
    echo "正在安装依赖..."
    if [[ "$OS" == "debian" ]]; then
        apt-get update -y
        apt-get install -y curl wget tar socat jq openssl net-tools
    elif [[ "$OS" == "centos" || "$OS" == "rocky" ]]; then
        if command -v dnf >/dev/null 2>&1; then
            dnf install -y curl wget tar socat jq openssl net-tools
        else
            yum install -y curl wget tar socat jq openssl net-tools
        fi
    fi
}

# ACME.sh 证书管理
acme_setup() {
    echo "正在安装 acme.sh..."
    curl https://get.acme.sh | sh -s
    
    export PATH=$PATH:/root/.acme.sh
    ACME_BIN="/root/.acme.sh/acme.sh"

    # 简单检查 80 端口
    if netstat -tulpn | grep -E ':80\s' > /dev/null; then
        echo "80 端口被占用，请先停止相关服务。"
        exit 1
    fi

    echo "使用的域名: $domain"
    
    $ACME_BIN --issue -d "$domain" --standalone --force
    
    mkdir -p /etc/sing-box/certs/
    $ACME_BIN --install-cert -d "$domain" \
        --key-file /etc/sing-box/certs/"$domain".key \
        --fullchain-file /etc/sing-box/certs/"$domain".crt
}

# 内核优化 (BBR)
kernel_optimization() {
    echo "1. 开启 BBR v1 (推荐)"
    echo "2. 开启 BBR v3 (需要安装新内核并重启)"
    read -p "请选择 BBR 版本 [1-2]: " bbr_choice

    if [[ "$bbr_choice" == "1" ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    elif [[ "$bbr_choice" == "2" ]]; then
        if [[ "$OS" == "debian" ]]; then
            echo "BBR v3 需要 XanMod 内核。正在安装..."
            wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod.gpg
            echo 'deb [signed-by=/usr/share/keyrings/xanmod.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
            apt-get update
            apt-get install -y linux-xanmod-x64v3
        elif [[ "$OS" == "rocky" || "$OS" == "centos" ]]; then
            echo "BBR v3 需要 Mainline 内核 (ELRepo)。正在安装..."
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
            rhel_version=$(rpm -E %rhel)
            if [ -z "$rhel_version" ]; then rhel_version=8; fi 
            yum install -y https://www.elrepo.org/elrepo-release-${rhel_version}.elrepo.noarch.rpm
            yum --enablerepo=elrepo-kernel install -y kernel-ml
            grub2-set-default 0
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi
        echo "内核已安装。请重启服务器并再次运行此脚本。"
        exit 0
    fi

    # UDP 调优
    echo "net.core.rmem_max=67108864" >> /etc/sysctl.conf
    echo "net.core.wmem_max=67108864" >> /etc/sysctl.conf
    sysctl -p
}

# 安装 Sing-box
install_singbox() {
    echo "正在安装 sing-box..."
    local arch=$(uname -m)
    local pkg_arch="amd64"
    if [[ "$arch" == "aarch64" ]]; then
        pkg_arch="arm64"
    fi
    local download_url=$(curl -s https://api.github.com/repos/SagerNet/sing-box/releases/latest | jq -r ".assets[] | select(.name | contains(\"linux-$pkg_arch\")) | .browser_download_url")
    wget -qO sing-box.tar.gz "$download_url"
    tar -xzf sing-box.tar.gz --strip-components=1 -C /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    mkdir -p /etc/sing-box
}

# 生成配置
generate_config() {
    domain=$(cat /tmp/domain.txt)
    echo "正在为域名生成配置: $domain..."
    cat <<EOF > /etc/sing-box/config.json
{
  "inbounds": [
    {
      "type": "hysteria2",
      "listen_port": $hy2_port,
      "password": "$hy2_password",
      "tls": {
        "certificate_path": "/etc/sing-box/certs/$domain.crt",
        "key_path": "/etc/sing-box/certs/$domain.key"
      }
    },
    {
      "type": "tuic",
      "listen_port": $tuic_port,
      "uuid": "$(cat /proc/sys/kernel/random/uuid)",
      "password": "$tuic_password",
      "tls": {
        "certificate_path": "/etc/sing-box/certs/$domain.crt",
        "key_path": "/etc/sing-box/certs/$domain.key"
      }
    }
  ]
}
EOF
}

# 配置服务
setup_service() {
    cat <<EOF > /etc/systemd/system/sing-box.service
[Unit]
Description=Sing-box Service
After=network.target

[Service]
ExecStart=/usr/local/bin/sing-box run -c /etc/sing-box/config.json
Restart=always

[Install]
WantedBy=multi-user.target
EOF
    systemctl daemon-reload
    systemctl enable sing-box
    systemctl start sing-box
}

os_check
install_dependencies
acme_setup
kernel_optimization
install_singbox
generate_config
setup_service

echo "安装完成。"
echo "环境设置完成。"
