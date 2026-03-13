#!/usr/bin/env bash

set -euo pipefail

STATE_FILE="/etc/sing-box/install.env"
SERVICE_FILE="/etc/systemd/system/sing-box.service"
SINGBOX_BINARY="/usr/local/bin/sing-box"
SINGBOX_CONFIG_DIR="/etc/sing-box"

install_stage=""
domain=""
hy2_port=""
hy2_password=""
tuic_port=""
tuic_password=""
bbr_choice=""
requested_kernel_package=""
kernel_before_reboot=""

# Sing-box 一键部署脚本
# 作者: Opencode
# 日期: 2026-03-11

save_install_state() {
    mkdir -p "$SINGBOX_CONFIG_DIR"
    {
        printf 'install_stage=%q\n' "$install_stage"
        printf 'domain=%q\n' "$domain"
        printf 'hy2_port=%q\n' "$hy2_port"
        printf 'hy2_password=%q\n' "$hy2_password"
        printf 'tuic_port=%q\n' "$tuic_port"
        printf 'tuic_password=%q\n' "$tuic_password"
        printf 'bbr_choice=%q\n' "$bbr_choice"
        printf 'requested_kernel_package=%q\n' "$requested_kernel_package"
        printf 'kernel_before_reboot=%q\n' "$kernel_before_reboot"
    } > "$STATE_FILE"
    chmod 600 "$STATE_FILE"
}

load_install_state() {
    if [[ -f "$STATE_FILE" ]]; then
        # shellcheck disable=SC1090
        source "$STATE_FILE"
    fi
}

discard_install_state() {
    rm -f "$STATE_FILE"
    install_stage=""
    domain=""
    hy2_port=""
    hy2_password=""
    tuic_port=""
    tuic_password=""
    bbr_choice=""
    requested_kernel_package=""
    kernel_before_reboot=""
}

load_saved_install_config() {
    if [[ -n "$domain" && -n "$hy2_port" && -n "$hy2_password" && -n "$tuic_port" && -n "$tuic_password" ]]; then
        echo "继续使用已保存的安装配置。"
        echo "域名: $domain"
        return 0
    fi

    echo "已保存的安装配置不完整，将重新采集配置。"
    prompt_install_config
    install_stage="config_collected"
    save_install_state
}

prompt_saved_install_resolution() {
    echo "检测到未完成的安装配置。"
    echo "1. 继续使用已保存的配置"
    echo "2. 丢弃已保存的配置并重新开始"

    if ! exec 3</dev/tty; then
        echo "此脚本需要在交互式终端中运行。"
        exit 1
    fi

    read -r -p "检测到未完成的安装配置，请选择 [1-2]: " saved_install_choice <&3
    exec 3<&-
}

requested_kernel_is_installed() {
    if [[ -z "$requested_kernel_package" ]]; then
        return 1
    fi

    if [[ "$OS" == "debian" ]]; then
        dpkg-query -W -f='${Status}' "$requested_kernel_package" 2>/dev/null | grep -Fq 'install ok installed'
    else
        rpm -q "$requested_kernel_package" >/dev/null 2>&1
    fi
}

running_kernel_matches_requested_family() {
    local current_kernel
    current_kernel=$(uname -r)

    if [[ -z "$requested_kernel_package" ]]; then
        return 1
    fi

    if [[ "$OS" == "debian" ]]; then
        [[ "$requested_kernel_package" == linux-xanmod-* ]] && [[ "$current_kernel" == *xanmod* ]]
    else
        [[ "$requested_kernel_package" == "kernel-ml" ]] && [[ "$current_kernel" == *elrepo* || "$current_kernel" == *ml* ]]
    fi
}

resume_is_safe() {
    local current_kernel
    current_kernel=$(uname -r)

    if [[ -z "$kernel_before_reboot" ]]; then
        return 1
    fi

    [[ "$current_kernel" != "$kernel_before_reboot" ]] && requested_kernel_is_installed && running_kernel_matches_requested_family
}

prompt_pending_reboot_resolution() {
    echo "检测到待恢复安装状态，但当前内核尚未满足继续安装条件。"
    echo "1. 保留当前状态，稍后重启后再继续"
    echo "2. 丢弃当前状态并重新开始安装"

    if ! exec 3</dev/tty; then
        echo "此脚本需要在交互式终端中运行。"
        exit 1
    fi

    read -r -p "检测到待恢复安装状态，请选择 [1-2]: " pending_reboot_choice <&3
    exec 3<&-

    case "$pending_reboot_choice" in
        1)
            echo "已保留待恢复安装状态。请在重启进入目标内核后再次运行安装。"
            exit 1
            ;;
        2)
            discard_install_state
            echo "已丢弃待恢复安装状态，将重新开始安装。"
            return 0
            ;;
        *)
            echo "无效选择，未更改待恢复安装状态。"
            exit 1
            ;;
    esac
}

resume_install_after_reboot() {
    echo "检测到 BBR v3 重启后的待恢复安装状态。"

    if ! resume_is_safe; then
        prompt_pending_reboot_resolution
        return 1
    fi

    echo "已确认新内核生效，继续完成安装。"
    install_stage="kernel_ready"
    save_install_state

    install_singbox
    install_stage="singbox_installed"
    save_install_state

    generate_config
    install_stage="config_generated"
    save_install_state

    setup_service
    install_stage="completed"
    save_install_state

    echo "安装完成。"
    echo "环境设置完成。"
}

prompt_install_config() {
    echo "--- Sing-box 部署配置 ---"
    if ! exec 3</dev/tty; then
       echo "此脚本需要在交互式终端中运行。"
       exit 1
    fi

    read -r -p "请输入域名: " domain <&3
    read -r -p "Hysteria2 端口: " hy2_port <&3
    read -r -p "Hysteria2 密码: " hy2_password <&3
    read -r -p "TUIC 端口: " tuic_port <&3
    read -r -p "TUIC 密码: " tuic_password <&3
    exec 3<&-
}

require_root() {
    if [[ $EUID -ne 0 ]]; then
        echo "此脚本必须以 root 权限运行。"
        exit 1
    fi
}

singbox_service_exists() {
    [[ -f "$SERVICE_FILE" ]]
}

singbox_is_installed() {
    singbox_service_exists || [[ -x "$SINGBOX_BINARY" ]] || [[ -d "$SINGBOX_CONFIG_DIR" ]] || [[ -f "$STATE_FILE" ]]
}

ensure_singbox_installed() {
    if ! singbox_is_installed; then
        echo "sing-box 尚未安装，请先执行安装。"
        exit 1
    fi
}

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
    $ACME_BIN --set-default-ca --server letsencrypt

    mkdir -p /etc/sing-box/certs/
    
    local cert_key="/etc/sing-box/certs/$domain.key"
    local cert_crt="/etc/sing-box/certs/$domain.crt"
    
    if [[ -f "$cert_crt" && -f "$cert_key" ]]; then
        echo "证书已存在，跳过重新签发。"
        echo "如需强制更新，请删除 /etc/sing-box/certs/ 目录后重新运行。"
        return 0
    fi

    # 简单检查 80 端口
    if netstat -tulpn | grep -E ':80\s' > /dev/null; then
        echo "80 端口被占用，请先停止相关服务。"
        exit 1
    fi

    echo "使用的域名: $domain"
    
    $ACME_BIN --issue -d "$domain" --standalone
    
    $ACME_BIN --install-cert -d "$domain" \
        --key-file "$cert_key" \
        --fullchain-file "$cert_crt"
}

# 内核优化 (BBR)
kernel_optimization() {
    echo "1. 开启 BBR v1 (推荐)"
    echo "2. 开启 BBR v3 (需要安装新内核并重启)"
    if ! exec 3</dev/tty; then
        echo "此脚本需要在交互式终端中运行。"
        exit 1
    fi
    read -r -p "请选择 BBR 版本 [1-2]: " bbr_choice <&3
    exec 3<&-
    install_stage="kernel_selected"
    save_install_state

    if [[ "$bbr_choice" == "1" ]]; then
        echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
        echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
        sysctl -p
    elif [[ "$bbr_choice" == "2" ]]; then
        kernel_before_reboot=$(uname -r)
        if [[ "$OS" == "debian" ]]; then
            echo "BBR v3 需要 XanMod 内核。正在安装..."
            requested_kernel_package="linux-xanmod-x64v3"
            wget -qO - https://dl.xanmod.org/archive.key | gpg --dearmor -o /usr/share/keyrings/xanmod.gpg
            echo 'deb [signed-by=/usr/share/keyrings/xanmod.gpg] http://deb.xanmod.org releases main' | tee /etc/apt/sources.list.d/xanmod-release.list
            apt-get update
            apt-get install -y "$requested_kernel_package"
        elif [[ "$OS" == "rocky" || "$OS" == "centos" ]]; then
            echo "BBR v3 需要 Mainline 内核 (ELRepo)。正在安装..."
            requested_kernel_package="kernel-ml"
            rpm --import https://www.elrepo.org/RPM-GPG-KEY-elrepo.org
            rhel_version=$(rpm -E %rhel)
            if [ -z "$rhel_version" ]; then rhel_version=8; fi
            if command -v dnf >/dev/null 2>&1; then
                pkg_mgr="dnf"
            else
                pkg_mgr="yum"
            fi
            "$pkg_mgr" install -y "https://www.elrepo.org/elrepo-release-${rhel_version}.el${rhel_version}.elrepo.noarch.rpm"
            "$pkg_mgr" --enablerepo=elrepo-kernel install -y "$requested_kernel_package"
            grub2-set-default 0
            grub2-mkconfig -o /boot/grub2/grub.cfg
        fi

        if requested_kernel_is_installed && running_kernel_matches_requested_family; then
            echo "已检测到目标 BBR v3 内核正在运行，继续安装。"
        else
            install_stage="pending_reboot"
            save_install_state
            echo "内核已安装。请重启服务器并再次运行此脚本。"
            exit 0
        fi
    fi

    # UDP 调优
    echo "net.core.rmem_max=67108864" >> /etc/sysctl.conf
    echo "net.core.wmem_max=67108864" >> /etc/sysctl.conf
    sysctl -p
    install_stage="kernel_ready"
    save_install_state
}

# 安装 Sing-box
install_singbox() {
    echo "正在安装 sing-box..."
    local arch=$(uname -m)
    local pkg_arch="amd64"
    local release_api="https://api.github.com/repos/SagerNet/sing-box/releases/latest"
    local release_json
    local download_url

    if [[ "$arch" == "aarch64" ]]; then
        pkg_arch="arm64"
    fi

    release_json=$(curl -fsSL "$release_api") || {
        echo "无法获取 sing-box 发布信息，请检查 GitHub 访问或稍后重试。"
        exit 1
    }

    download_url=$(printf '%s' "$release_json" | jq -r ".assets[] | select((.name | contains(\"linux-$pkg_arch\")) and (.name | endswith(\".tar.gz\"))) | .browser_download_url" | head -n 1)

    if [[ -z "$download_url" || "$download_url" == "null" ]]; then
        echo "无法获取 sing-box 下载地址，可能是 GitHub API 限流或发布资产格式已变化。"
        exit 1
    fi

    echo "下载地址: $download_url"
    wget -O sing-box.tar.gz "$download_url"
    tar -xzf sing-box.tar.gz --strip-components=1 -C /usr/local/bin/
    chmod +x /usr/local/bin/sing-box
    mkdir -p "$SINGBOX_CONFIG_DIR"
}

# 生成配置
generate_config() {
    echo "正在为域名生成配置: $domain..."
    local tuic_uuid=$(cat /proc/sys/kernel/random/uuid)
    cat <<EOF > "$SINGBOX_CONFIG_DIR/config.json"
{
  "inbounds": [
    {
      "type": "hysteria2",
      "listen_port": $hy2_port,
      "users": [
        {
          "name": "hy2_user",
          "password": "$hy2_password"
        }
      ],
      "tls": {
        "enabled": true,
        "certificate_path": "/etc/sing-box/certs/$domain.crt",
        "key_path": "/etc/sing-box/certs/$domain.key"
      }
    },
    {
      "type": "tuic",
      "listen_port": $tuic_port,
      "users": [
        {
          "name": "tuic_user",
          "uuid": "$tuic_uuid",
          "password": "$tuic_password"
        }
      ],
      "tls": {
        "enabled": true,
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
    cat <<EOF > "$SERVICE_FILE"
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

continue_install_from_stage() {
    while [[ "$install_stage" != "completed" ]]; do
        case "$install_stage" in
            config_collected)
                install_dependencies
                install_stage="dependencies_installed"
                save_install_state
                ;;
            dependencies_installed)
                acme_setup
                install_stage="acme_ready"
                save_install_state
                ;;
            kernel_selected|acme_ready)
                kernel_optimization
                ;;
            kernel_ready)
                install_singbox
                install_stage="singbox_installed"
                save_install_state
                ;;
            singbox_installed)
                generate_config
                install_stage="config_generated"
                save_install_state
                ;;
            config_generated)
                setup_service
                install_stage="completed"
                save_install_state
                ;;
            *)
                echo "无法识别的安装阶段: $install_stage"
                exit 1
                ;;
        esac
    done

    echo "安装完成。"
    echo "环境设置完成。"
}

install_flow() {
    require_root
    os_check
    load_install_state

    if [[ "$install_stage" == "pending_reboot" ]]; then
        if resume_install_after_reboot; then
            return
        fi
    fi

    if [[ -f "$STATE_FILE" ]] && [[ "$install_stage" != "completed" ]] && [[ "$install_stage" != "pending_reboot" ]]; then
        prompt_saved_install_resolution

        case "$saved_install_choice" in
            1)
                load_saved_install_config
                continue_install_from_stage
                return
                ;;
            2)
                discard_install_state
                prompt_install_config
                install_stage="config_collected"
                save_install_state
                ;;
            *)
                echo "无效选择。"
                exit 1
                ;;
        esac
    else
        prompt_install_config
        install_stage="config_collected"
        save_install_state
    fi

    continue_install_from_stage
}

start_singbox() {
    require_root
    if ! singbox_service_exists; then
        echo "sing-box 服务未安装，请先执行安装。"
        exit 1
    fi

    systemctl --no-pager start sing-box
    echo "sing-box 已启动。"
}

stop_singbox() {
    require_root
    if ! singbox_service_exists; then
        echo "sing-box 服务未安装，请先执行安装。"
        exit 1
    fi

    systemctl --no-pager stop sing-box
    echo "sing-box 已停止。"
}

restart_singbox() {
    require_root
    if ! singbox_service_exists; then
        echo "sing-box 服务未安装，请先执行安装。"
        exit 1
    fi

    systemctl --no-pager restart sing-box
    echo "sing-box 已重启。"
}

status_singbox() {
    require_root
    if ! singbox_service_exists; then
        echo "sing-box 服务未安装，请先执行安装。"
        exit 1
    fi

    systemctl --no-pager status sing-box
    
    echo ""
    echo "=== 配置信息 ==="
    
    local config_file="$SINGBOX_CONFIG_DIR/config.json"
    if [[ -f "$config_file" ]]; then
        local hy2_port=$(jq -r '.inbounds[] | select(.type=="hysteria2") | .listen_port' "$config_file" 2>/dev/null || echo "未知")
        local hy2_password=$(jq -r '.inbounds[] | select(.type=="hysteria2") | .users[0].password' "$config_file" 2>/dev/null || echo "未知")
        local tuic_port=$(jq -r '.inbounds[] | select(.type=="tuic") | .listen_port' "$config_file" 2>/dev/null || echo "未知")
        local tuic_uuid=$(jq -r '.inbounds[] | select(.type=="tuic") | .users[0].uuid' "$config_file" 2>/dev/null || echo "未知")
        local tuic_password=$(jq -r '.inbounds[] | select(.type=="tuic") | .users[0].password' "$config_file" 2>/dev/null || echo "未知")
        
        echo "Hysteria2:"
        echo "  端口: $hy2_port"
        echo "  密码: $hy2_password"
        echo ""
        echo "TUIC:"
        echo "  端口: $tuic_port"
        echo "  UUID: $tuic_uuid"
        echo "  密码: $tuic_password"
    else
        echo "配置文件不存在: $config_file"
    fi
}

uninstall_singbox() {
    require_root

    if ! singbox_is_installed; then
        echo "sing-box 未安装，无需卸载。"
        return 0
    fi

    if singbox_service_exists; then
        systemctl --no-pager stop sing-box || true
        systemctl disable sing-box || true
    fi

    rm -f /etc/systemd/system/sing-box.service
    rm -f /usr/local/bin/sing-box
    rm -rf /etc/sing-box
    rm -f "$STATE_FILE"
    systemctl daemon-reload

    echo "sing-box 已卸载。"
}

main_menu() {
    echo "--- Sing-box 菜单 ---"
    echo "1. 安装"
    echo "2. 启动"
    echo "3. 停止"
    echo "4. 重启"
    echo "5. 状态"
    echo "6. 卸载"

    if ! exec 3</dev/tty; then
       echo "此脚本需要在交互式终端中运行。"
       exit 1
    fi

    read -r -p "请选择操作 [1-6]: " menu_choice <&3
    exec 3<&-

    case "$menu_choice" in
        1)
            install_flow
            ;;
        2)
            start_singbox
            ;;
        3)
            stop_singbox
            ;;
        4)
            restart_singbox
            ;;
        5)
            status_singbox
            ;;
        6)
            uninstall_singbox
            ;;
        *)
            echo "无效选择。"
            exit 1
            ;;
    esac
}

main_menu
