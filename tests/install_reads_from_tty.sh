#!/usr/bin/env bash

set -euo pipefail

script_dir=$(cd "$(dirname "$0")/.." && pwd)
script_path="$script_dir/install.sh"

required_patterns=(
  'if ! exec 3</dev/tty; then'
  'read -r -p "请输入域名: " domain <&3'
  'read -r -p "Hysteria2 端口: " hy2_port <&3'
  'read -r -p "Hysteria2 密码: " hy2_password <&3'
  'read -r -p "TUIC 端口: " tuic_port <&3'
  'read -r -p "TUIC 密码: " tuic_password <&3'
  'read -r -p "请选择 BBR 版本 [1-2]: " bbr_choice <&3'
  'exec 3<&-'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing interactive tty read: %s\n' "$pattern" >&2
    exit 1
  fi
done

printf 'all interactive reads use /dev/tty\n'
