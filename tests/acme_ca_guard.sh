#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'ACME_BIN="/root/.acme.sh/acme.sh"'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing expected pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

set_default_line=$(grep -nF '$ACME_BIN --set-default-ca --server letsencrypt' "$script_path" | cut -d: -f1)
issue_line=$(grep -nF '$ACME_BIN --issue -d "$domain" --standalone --force' "$script_path" | cut -d: -f1)

if [[ -z "$set_default_line" || -z "$issue_line" ]]; then
  printf 'missing CA ordering lines\n' >&2
  exit 1
fi

if (( set_default_line >= issue_line )); then
  printf 'set-default-ca must appear before issue\n' >&2
  exit 1
fi

printf 'acme.sh CA selection looks guarded\n'
