#!/usr/bin/env bash

# Sing-box One-Key Deploy Script
# Author: Opencode
# Date: 2026-03-11

# Ensure the script runs as root
if [[ $EUID -ne 0 ]]; then
   echo "This script must be run as root." 
   exit 1
fi

# Detect OS and Architecture
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
        echo "Unsupported OS."
        exit 1
    fi
}

install_dependencies() {
    echo "Installing dependencies..."
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

# Run setup
os_check
install_dependencies

# ACME.sh Certificate Management
acme_setup() {
    echo "Installing acme.sh..."
    curl https://get.acme.sh | sh
    source ~/.bashrc
    export PATH=$PATH:$HOME/.acme.sh
    
    # Simple check for 80 port
    if netstat -tulpn | grep :80 > /dev/null; then
        echo "Port 80 is occupied. Please stop any web server first."
        exit 1
    fi

    read -p "Enter your domain: " domain
    ~/.acme.sh/acme.sh --issue -d $domain --standalone
    mkdir -p /etc/sing-box/certs/
    ~/.acme.sh/acme.sh --install-cert -d $domain --key-file /etc/sing-box/certs/$domain.key --fullchain-file /etc/sing-box/certs/$domain.crt
    echo "$domain" > /tmp/domain.txt
}

acme_setup

# Kernel Optimization
kernel_optimization() {
    # [Restoring the original kernel_optimization logic]
    echo "1. Enable BBR v1 (Recommended)"
    echo "2. Enable BBR v3 (Requires new kernel, reboot)"
    read -p "Select BBR version [1-2]: " bbr_choice

    if [[ "$bbr_choice" == "1" ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    elif [[ "$bbr_choice" == "2" ]]; then
        echo "BBR v3 requires XanMod kernel. Installing..."
        # Simplified logic for example; assumes user confirms reboot
        wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod.gpg
        echo 'deb [signed-by=/usr/share/keyrings/xanmod.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
        apt-get update
        apt-get install -y linux-xanmod-x64v3
        echo "Kernel installed. Please reboot and run this script again."
        exit 0
    fi

    # UDP Tuning
    echo "net.core.rmem_max=67108864" >> /etc/sysctl.conf
    echo "net.core.wmem_max=67108864" >> /etc/sysctl.conf
    sysctl -p
}

kernel_optimization

# Sing-box Installation
install_singbox() {
    echo "Installing sing-box..."
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

# Config Generation
generate_config() {
    domain=$(cat /tmp/domain.txt)
    echo "Generating config for domain: $domain..."
    # Placeholder: need to generate UUID and credentials
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

# Service Setup
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

# Get User Input
read -p "Hysteria2 Port: " hy2_port
read -p "Hysteria2 Password: " hy2_password
read -p "TUIC Port: " tuic_port
read -p "TUIC Password: " tuic_password

install_singbox
generate_config
setup_service
echo "Installation complete."

echo "Environment setup complete."
