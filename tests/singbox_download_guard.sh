#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'contains(\"linux-$pkg_arch\") and (.name | endswith(\".tar.gz\"))'
  'if [[ -z "$download_url" || "$download_url" == "null" ]]; then'
  '无法获取 sing-box 下载地址'
  'wget -O sing-box.tar.gz "$download_url"'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing sing-box download guard: %s\n' "$pattern" >&2
    exit 1
  fi
done

if grep -Fq 'wget -qO sing-box.tar.gz "$download_url"' "$script_path"; then
  printf 'silent sing-box download still present\n' >&2
  exit 1
fi

printf 'sing-box download logic looks guarded\n'
