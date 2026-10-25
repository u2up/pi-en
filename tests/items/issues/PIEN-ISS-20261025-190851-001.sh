#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

fail() {
  printf 'PIEN-ISS-20261025-190851-001: %s\n' "$*" >&2
  exit 1
}

command -v nix >/dev/null 2>&1 || fail \
  'Nix is required; rebuild and relaunch with `nix develop`.'

# Build the current flake and run inside its declared development shell. This
# intentionally fails if PyYAML or the exact behavior-runner wrapper is absent.
nix develop "$repo_root" --command bash -euo pipefail -c '
  python -c "import yaml"
  wrapper="$(command -v pi-en-behavior-python)"
  case "$wrapper" in
    /nix/store/*/bin/pi-en-behavior-python) ;;
    *)
      printf "unexpected behavior Python wrapper path: %s\\n" "$wrapper" >&2
      exit 1
      ;;
  esac
  pi-en-behavior-python -c "import yaml; print(yaml.__version__)" >/dev/null
'

printf 'PIEN-ISS-20261025-190851-001 tests passed\n'
