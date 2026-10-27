#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

fail() {
  printf 'PIEN-ISS-20261027-180018-001: %s\n' "$*" >&2
  exit 1
}

# Behavior adapters run with a fixed PATH. The bundled adapter uses grep for
# behavior assertions, so this sealed runtime must explicitly retain GNU grep
# rather than relying on the caller's PATH.
flake="$repo_root/flake.nix"

grep -Fq 'mkBehaviorRuntimeBase = pkgs:' "$flake" ||
  fail 'Could not locate the isolated adapter runtime base.'
grep -Fq 'mkAdapterBehaviorPython = pkgs:' "$flake" ||
  fail 'The isolated adapter runtime must provide the behavior interpreter.'
grep -Eq '^[[:space:]]+gnugrep$' "$flake" ||
  fail 'The isolated adapter runtime must provide GNU grep.'
grep -Fq 'export PI_EN_BEHAVIOR_RUNTIME_PATH="${adapterRuntimePath}"' "$flake" ||
  fail 'The packaged adapter runtime must not inherit a caller-controlled PATH.'
if grep -Fq "PI_EN_BEHAVIOR_RUNTIME_PATH=\"''\${PI_EN_BEHAVIOR_RUNTIME_PATH:-" "$flake"; then
  fail 'The packaged adapter runtime must not permit caller PATH overrides.'
fi
grep -Fq 'behavior-adapter-smoke' "$flake" ||
  fail 'Nix checks must execute the complete behavior adapter suite.'

printf 'PIEN-ISS-20261027-180018-001 passed\n'
