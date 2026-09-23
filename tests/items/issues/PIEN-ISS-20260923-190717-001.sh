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
project: scope-demo
item_key: SCOPE
created: 2026-01-01T00:00:00Z
---

# Scope Demo
EOF_PROJECT
git -C "$coord_dir" add PROJECT.md
git -C "$coord_dir" commit -q -m "Initialize scope demo"

pi-en-coord-repo --coord-dir "$coord_dir" add alpha >/dev/null
pi-en-coord-repo --coord-dir "$coord_dir" add beta >/dev/null

alpha_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id alpha "Alpha scoped issue" | tail -n 1)"
alpha_id="$(basename "$alpha_path" .yaml)"
beta_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id beta "Beta scoped issue" | tail -n 1)"
beta_id="$(basename "$beta_path" .yaml)"
mkdir -p "$coord_dir/issues/open"
cat >"$coord_dir/issues/open/ROOT-ISS-1.yaml" <<'EOF_ROOT'
schema: coordination-item/v1
id: ROOT-ISS-1
type: issue
status: open
project: root
owner: null
EOF_ROOT

git -C "$coord_dir" add -A
git -C "$coord_dir" commit -q -m "Add scoped issues"

pi-en-coord-claim --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id dev-a --role developer --no-pull --no-push \
  "$alpha_id" >/dev/null
grep -q '^status: claimed$' "$coord_dir/$alpha_path"

if pi-en-coord-claim --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id dev-a --role developer --force --no-pull --no-push \
  "$beta_id" >"$tmp/foreign.out" 2>"$tmp/foreign.err"; then
  printf 'foreign repo issue unexpectedly claimed with --force\n' >&2
  exit 1
fi
grep -q 'outside repo scope' "$tmp/foreign.err"

if pi-en-coord-claim --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id dev-a --role developer --force --no-pull --no-push \
  ROOT-ISS-1 >"$tmp/root.out" 2>"$tmp/root.err"; then
  printf 'root issue unexpectedly claimed in repo-layout domain\n' >&2
  exit 1
fi
grep -q 'root issue outside repo scope' "$tmp/root.err"

if pi-en-coord-done --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id dev-a --role developer --force --no-pull --no-push \
  "repos/beta/issues/open/$beta_id.yaml" >"$tmp/path.out" 2>"$tmp/path.err"; then
  printf 'foreign direct path unexpectedly marked done with --force\n' >&2
  exit 1
fi
grep -q 'outside repo scope' "$tmp/path.err"

for lifecycle_cmd in pi-en-coord-review pi-en-coord-verify pi-en-coord-close; do
  if "$lifecycle_cmd" --coord-dir "$coord_dir" --repo-id alpha \
    --agent-id guard --role developer --force --no-pull --no-push \
    "$beta_id" >"$tmp/$lifecycle_cmd.out" 2>"$tmp/$lifecycle_cmd.err"; then
    printf '%s unexpectedly accepted a foreign issue with --force\n' \
      "$lifecycle_cmd" >&2
    exit 1
  fi
  grep -q 'outside repo scope' "$tmp/$lifecycle_cmd.err"
done

pi-en-coord-done --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id dev-a --role developer --no-pull --no-push \
  --implementation-ref alpha:main@0123456789abcdef0123456789abcdef01234567 \
  "$alpha_id" >/dev/null
done_path="repos/alpha/issues/done/$alpha_id.yaml"
grep -q '^status: done$' "$coord_dir/$done_path"

pi-en-coord-review --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id reviewer --role reviewer --pass --no-pull --no-push \
  "$alpha_id" >/dev/null
grep -q '^reviewed: true$' "$coord_dir/$done_path"

pi-en-coord-verify --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id tester --role tester --pass --no-pull --no-push \
  "$alpha_id" >/dev/null
grep -q '^verified: true$' "$coord_dir/$done_path"

closed_path="$(pi-en-coord-close --coord-dir "$coord_dir" --repo-id alpha \
  --agent-id tester --role tester --no-pull --no-push \
  "$alpha_id" | tail -n 1)"
test "$closed_path" = "repos/alpha/issues/closed/$alpha_id.yaml"

legacy_dir="$tmp/legacy"
mkdir -p "$legacy_dir/issues/open"
git -C "$legacy_dir" init -q
cat >"$legacy_dir/PROJECT.md" <<'EOF_LEGACY_PROJECT'
---
project: legacy
item_key: LEG
created: 2026-01-01T00:00:00Z
---
EOF_LEGACY_PROJECT
cat >"$legacy_dir/issues/open/LEG-ISS-1.yaml" <<'EOF_LEGACY'
schema: coordination-item/v1
id: LEG-ISS-1
type: issue
status: open
project: legacy
owner: null
EOF_LEGACY
git -C "$legacy_dir" add -A
git -C "$legacy_dir" commit -q -m "Initialize legacy domain"
pi-en-coord-claim --coord-dir "$legacy_dir" --agent-id dev-a \
  --role developer --no-pull --no-push LEG-ISS-1 >/dev/null
grep -q '^status: claimed$' "$legacy_dir/issues/open/LEG-ISS-1.yaml"
