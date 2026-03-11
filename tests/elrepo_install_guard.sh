#!/usr/bin/env bash

set -euo pipefail

script_path=$(cd "$(dirname "$0")/.." && pwd)/install.sh

required_patterns=(
  'set -euo pipefail'
  'pkg_mgr="dnf"'
  'pkg_mgr="yum"'
  'https://www.elrepo.org/elrepo-release-${rhel_version}.el${rhel_version}.elrepo.noarch.rpm'
)

for pattern in "${required_patterns[@]}"; do
  if ! grep -Fq "$pattern" "$script_path"; then
    printf 'missing expected pattern: %s\n' "$pattern" >&2
    exit 1
  fi
done

printf 'elrepo install logic looks guarded\n'
