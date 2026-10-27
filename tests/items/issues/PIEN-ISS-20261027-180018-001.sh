#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

fail() {
  printf 'PIEN-ISS-20261027-180018-001: %s\n' "$*" >&2
  exit 1
}

# Behavior adapters run with a fixed, minimal PATH. The bundled adapter uses
# grep for behavior assertions, so this sealed runtime must explicitly retain
# GNU grep rather than relying on the caller's PATH.
behavior_runtime="$(awk '
  /mkBehaviorPython = pkgs:/ { in_behavior = 1 }
  /mkRuntime = pkgs:/ { in_behavior = 0 }
  in_behavior { print }
' "$repo_root/flake.nix")"

grep -Eq 'adapterRuntimePath = pkgs\.lib\.makeBinPath \[' <<<"$behavior_runtime" ||
  fail 'Could not locate the isolated adapter runtime.'
grep -Fq 'pkgs.gnugrep' <<<"$behavior_runtime" ||
  fail 'The isolated adapter runtime must provide GNU grep.'

printf 'PIEN-ISS-20261027-180018-001 passed\n'
