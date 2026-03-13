#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'cert_key="/etc/sing-box/certs/$domain.key"'
  'cert_crt="/etc/sing-box/certs/$domain.crt"'
  'if [[ -f "$cert_crt" && -f "$cert_key" ]]; then'
  '证书已存在，跳过重新签发'
  '$ACME_BIN --issue -d "$domain" --standalone'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing cert skip pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

printf 'cert skip logic looks guarded\n'