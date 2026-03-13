#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  '"type": "hysteria2"'
  '"users": ['
  '"name": "hy2_user"'
  '"type": "tuic"'
  '"name": "tuic_user"'
  '"uuid": "$tuic_uuid"'
  '"enabled": true'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing config pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

printf 'config format looks correct\n'