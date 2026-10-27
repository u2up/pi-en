#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

fail() {
  printf 'PIEN-ISS-20261027-171642-001: %s\n' "$*" >&2
  exit 1
}

command -v nix >/dev/null 2>&1 || fail \
  'Nix is required to verify flake evaluation.'

# Evaluating the dev shell catches recursive package construction before a
# shell is entered. The behavior wrapper must not depend on coordination
# commands because those commands themselves depend on mkRuntime.
nix develop "$repo_root" --command true

printf 'PIEN-ISS-20261027-171642-001 passed\n'
