#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"

fail() {
  printf 'PIEN-ISS-20261027-171642-001: %s\n' "$*" >&2
  exit 1
}

# The behavior runtime is constructed before mkRuntime.  Coordination commands
# depend on mkRuntime, so including them here recreates the flake evaluation
# cycle.  This source-level assertion is executable without a Nix daemon,
# which is intentionally unavailable in the sandbox that runs item tests.
behavior_runtime="$(awk '
  /mkBehaviorPython = pkgs:/ { in_behavior = 1 }
  /mkRuntime = pkgs:/ { in_behavior = 0 }
  in_behavior { print }
' "$repo_root/flake.nix")"

[ -n "$behavior_runtime" ] || fail 'Could not locate mkBehaviorPython.'
if grep -Fq 'mkAgentCoordCommands' <<<"$behavior_runtime"; then
  fail 'Behavior runtime must not depend on coordination commands.'
fi

grep -Fq 'adapterRuntimePath = pkgs.lib.makeBinPath' <<<"$behavior_runtime" ||
  fail 'Behavior runtime must define its own adapter path.'

printf 'PIEN-ISS-20261027-171642-001 passed\n'
