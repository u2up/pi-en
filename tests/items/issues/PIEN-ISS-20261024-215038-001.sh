#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

for path in \
  pi-en-behaviors/MANIFEST.yaml \
  pi-en-behaviors/GLOSSARY.yaml \
  pi-en-behaviors/specifications/PIEN-BHV-20261024-215038-001.yaml \
  pi-en-behaviors/specifications/PIEN-BHV-20261024-215038-002.yaml \
  tests/behaviors/adapter.sh; do
  test -e "$repo_root/$path"
done
test -x "$repo_root/tests/behaviors/adapter.sh"

cd "$repo_root"
if command -v nix >/dev/null 2>&1; then
  nix develop --command pien behavior lint
  nix develop --command pien behavior test
else
  # The packaged interpreter is the same trusted runtime used by pien.
  command -v pi-en-behavior-python >/dev/null
  PI_EN_BEHAVIOR_RUNTIME_PATH="$PATH" pi-en-behavior-python \
    scripts/pi-en-behavior.py lint
  PI_EN_BEHAVIOR_RUNTIME_PATH="$PATH" pi-en-behavior-python \
    scripts/pi-en-behavior.py test
fi
printf 'item PIEN-ISS-20261024-215038-001 passed\n'
