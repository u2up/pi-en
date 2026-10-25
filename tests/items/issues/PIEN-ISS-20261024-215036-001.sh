#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
test -x "$repo_root/scripts/pi-en-behavior"
test -f "$repo_root/scripts/pi-en-behavior.py"
grep -Fq 'behavior' "$repo_root/scripts/pien"
"$repo_root/tests/pi-en-behavior.sh"
printf 'item PIEN-ISS-20261024-215036-001 passed\n'
