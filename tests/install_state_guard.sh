#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'STATE_FILE="/etc/sing-box/install.env"'
  'load_install_state() {'
  'save_install_state() {'
  'prompt_saved_install_resolution() {'
  'load_saved_install_config() {'
  'continue_install_from_stage() {'
  'running_kernel_matches_requested_family() {'
  'prompt_pending_reboot_resolution() {'
  'install_stage="pending_reboot"'
  'discard_install_state'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing install state pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

if ! perl -0ne 'exit 0 if /if \[\[ \"\$install_stage\" == \"pending_reboot\" \]\].*resume/s; exit 1' "$script_path"; then
  printf 'missing pending_reboot resume logic\n' >&2
  exit 1
fi

if ! grep -Fq 'xanmod' "$script_path"; then
  printf 'missing XanMod kernel-family heuristic\n' >&2
  exit 1
fi

if ! grep -Eq 'elrepo|ml' "$script_path"; then
  printf 'missing ELRepo mainline kernel-family heuristic\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /resume_is_safe.*?prompt_pending_reboot_resolution/s; exit 1' "$script_path"; then
  printf 'missing stale pending_reboot prompt handling\n' >&2
  exit 1
fi

if ! grep -Fq 'read -r -p "检测到待恢复安装状态' "$script_path"; then
  printf 'missing tty prompt for stale pending_reboot state\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /if \[\[ -f "\$STATE_FILE" \]\].*install_stage.*!=.*completed.*install_stage.*!=.*pending_reboot.*prompt_saved_install_resolution/s; exit 1' "$script_path"; then
  printf 'missing non-completed saved install prompt handling\n' >&2
  exit 1
fi

if ! grep -Fq 'read -r -p "检测到未完成的安装配置，请选择 [1-2]: " saved_install_choice <&3' "$script_path"; then
  printf 'missing tty prompt for saved install config choice\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /prompt_saved_install_resolution.*?load_saved_install_config/s; exit 1' "$script_path"; then
  printf 'missing saved install resume path\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /install_flow\(\) \{.*prompt_saved_install_resolution.*load_saved_install_config/s; exit 1' "$script_path"; then
  printf 'saved install prompt handling must live in install_flow\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /install_flow\(\) \{.*case "\$saved_install_choice" in.*2\).*discard_install_state.*prompt_install_config.*install_stage="config_collected".*save_install_state/s; exit 1' "$script_path"; then
  printf 'restarting from saved install must clear old state before recollecting config\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /continue_install_from_stage\(\) \{.*config_collected.*install_dependencies.*dependencies_installed.*acme_setup.*acme_ready.*kernel_optimization.*install_singbox.*singbox_installed.*generate_config.*config_generated.*setup_service.*completed/s; exit 1' "$script_path"; then
  printf 'missing stage-aware continuation helper\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /continue_install_from_stage\(\) \{.*kernel_selected.*kernel_optimization/s; exit 1' "$script_path"; then
  printf 'kernel_selected must resume from kernel processing\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /install_flow\(\) \{.*load_saved_install_config.*continue_install_from_stage/s; exit 1' "$script_path"; then
  printf 'saved install continuation must resume from install_stage\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /resume_is_safe\(\) \{.*current_kernel=.*uname -r.*\[\[ "\$current_kernel" != "\$kernel_before_reboot" \]\].*requested_kernel_is_installed && running_kernel_matches_requested_family/s; exit 1' "$script_path"; then
  printf 'pending_reboot resume must require changed kernel plus matching target family\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /kernel_optimization\(\) \{.*requested_kernel_is_installed && running_kernel_matches_requested_family.*install_stage="kernel_ready"/s; exit 1' "$script_path"; then
  printf 'kernel optimization must continue directly when target kernel is already active\n' >&2
  exit 1
fi

if ! perl -0ne 'exit 0 if /kernel_optimization\(\) \{.*install_stage="pending_reboot".*save_install_state.*echo "内核已安装。请重启服务器并再次运行此脚本。"/s; exit 1' "$script_path"; then
  printf 'kernel optimization must still persist pending_reboot when reboot is required\n' >&2
  exit 1
fi

printf 'install state persistence and resume logic look guarded\n'
