#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'start_singbox() {'
  'stop_singbox() {'
  'restart_singbox() {'
  'status_singbox() {'
  'uninstall_singbox() {'
  'singbox_service_exists() {'
  'singbox_is_installed() {'
  'systemctl --no-pager start sing-box'
  'systemctl --no-pager stop sing-box'
  'systemctl --no-pager restart sing-box'
  'systemctl --no-pager status sing-box'
  'rm -f /etc/systemd/system/sing-box.service'
  'rm -f /usr/local/bin/sing-box'
  'rm -rf /etc/sing-box'
  'rm -f "$STATE_FILE"'
  'systemctl daemon-reload'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing service action pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

if ! perl -0ne 'exit 0 if /uninstall_singbox\(\) \{.*systemctl --no-pager stop sing-box.*systemctl disable sing-box.*rm -f \/etc\/systemd\/system\/sing-box\.service.*rm -f \/usr\/local\/bin\/sing-box.*rm -rf \/etc\/sing-box.*rm -f "\$STATE_FILE".*systemctl daemon-reload/s; exit 1' "$script_path"; then
  printf 'uninstall flow is missing required cleanup order\n' >&2
  exit 1
fi

service_checks=(
  'start_singbox:systemctl --no-pager start sing-box'
  'stop_singbox:systemctl --no-pager stop sing-box'
  'restart_singbox:systemctl --no-pager restart sing-box'
  'status_singbox:systemctl --no-pager status sing-box'
)

for check in "${service_checks[@]}"; do
  function_name=${check%%:*}
  systemctl_call=${check#*:}

  if ! perl -0ne "exit 0 if /${function_name}\(\) \{.*singbox_service_exists.*${systemctl_call}/s; exit 1" "$script_path"; then
    printf '%s must check singbox_service_exists before systemctl\n' "$function_name" >&2
    exit 1
  fi
done

if grep -Fq '/root/.acme.sh' "$script_path" && perl -0ne 'exit 0 if /uninstall_singbox\(\).*\/root\/\.acme\.sh/s; exit 1' "$script_path"; then
  printf 'uninstall must not remove /root/.acme.sh\n' >&2
  exit 1
fi

status_info_patterns=(
  'jq -r'
  'hysteria2'
  'tuic'
  'listen_port'
  'password'
  'Hysteria2:'
  'TUIC:'
  '端口:'
  '密码:'
)

for pattern in "${status_info_patterns[@]}"; do
  if ! perl -0ne "exit 0 if /status_singbox\(\).*${pattern}/s; exit 1" "$script_path"; then
    printf 'status_singbox must show config info: %s\n' "$pattern" >&2
    exit 1
  fi
done

printf 'service actions and uninstall flow look guarded\n'
