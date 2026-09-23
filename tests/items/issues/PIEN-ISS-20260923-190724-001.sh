#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home"
mkdir -p "$HOME"

git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

coord_dir="$tmp/coordination"
mkdir -p "$coord_dir"
git -C "$coord_dir" init -q
cat >"$coord_dir/PROJECT.md" <<'EOF_PROJECT'
---
project: docs-scope-demo
item_key: DOCD
created: 2026-01-01T00:00:00Z
---

# Docs Scope Demo
EOF_PROJECT
git -C "$coord_dir" add PROJECT.md
git -C "$coord_dir" commit -q -m "Initialize docs scope demo"

pi-en-coord-repo --coord-dir "$coord_dir" add alpha >/dev/null
pi-en-coord-repo --coord-dir "$coord_dir" add beta >/dev/null

alpha_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id alpha "Alpha issue" | tail -n 1)"
alpha_id="$(basename "$alpha_path" .yaml)"
beta_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id beta "Beta issue" | tail -n 1)"
beta_id="$(basename "$beta_path" .yaml)"

git -C "$coord_dir" add -A
git -C "$coord_dir" commit -q -m "Add repo-scoped issues"

# Lifecycle mutation is repo-scoped and rejects foreign repo IDs even with
# --force, matching the README/help contract for issue operations.
if pi-en-coord-claim --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id dev-a --role developer --force --no-pull --no-push \
  "$beta_id" >"$tmp/claim.out" 2>"$tmp/claim.err"; then
  printf 'foreign issue unexpectedly accepted by lifecycle helper\n' >&2
  exit 1
fi
grep -q 'outside repo scope' "$tmp/claim.err"

# Read-only issue inspection keeps explicit all-repo visibility.
all_list="$(pi-en-coord-list --coord-dir "$coord_dir" issues open --all-repos)"
printf '%s\n' "$all_list" | grep -q $'alpha\t'"$alpha_id"$'\topen\tAlpha issue'
printf '%s\n' "$all_list" | grep -q $'beta\t'"$beta_id"$'\topen\tBeta issue'

status_all="$(pi-en-coord-status --coord-dir "$coord_dir" --all-repos)"
printf '%s\n' "$status_all" | grep -q 'Issue scope: all repos'
printf '%s\n' "$status_all" | grep -q 'repo=alpha'
printf '%s\n' "$status_all" | grep -q 'repo=beta'

for helper in pi-en-coord-claim pi-en-coord-done pi-en-coord-review \
  pi-en-coord-verify pi-en-coord-close; do
  "$helper" --help | grep -q 'repo-scope protection'
done

printf 'cross-repo lifecycle documentation tests passed\n'
