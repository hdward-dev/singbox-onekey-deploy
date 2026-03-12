#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'main_menu() {'
  '1. 安装'
  '2. 启动'
  '3. 停止'
  '4. 重启'
  '5. 状态'
  '6. 卸载'
  'install_flow() {'
  'start_singbox() {'
  'stop_singbox() {'
  'restart_singbox() {'
  'status_singbox() {'
  'uninstall_singbox() {'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing expected menu pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

case_checks=(
  '1:[[:space:]]*install_flow'
  '2:[[:space:]]*start_singbox'
  '3:[[:space:]]*stop_singbox'
  '4:[[:space:]]*restart_singbox'
  '5:[[:space:]]*status_singbox'
  '6:[[:space:]]*uninstall_singbox'
)

for check in "${case_checks[@]}"; do
  menu_option=${check%%:*}
  target=${check#*:}
  pattern="${menu_option})[[:space:]]|${target}"

  if ! perl -0ne "exit 0 if /case \\\"\\\$menu_choice\\\" in.*?${menu_option}\)[[:space:]]*${target}[[:space:]]*;;/s; exit 1" "$script_path"; then
    printf 'missing expected case dispatch: %s -> %s\n' "$menu_option" "$target" >&2
    exit 1
  fi
done

printf 'menu flow structure looks guarded\n'
