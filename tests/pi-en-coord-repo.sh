#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
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
project: registry-demo
item_key: REG
created: 2026-01-01T00:00:00Z
---

# Registry Demo
EOF_PROJECT
mkdir -p "$coord_dir/issues/open" "$coord_dir/issues/blocked" "$coord_dir/issues/done" "$coord_dir/issues/closed"
git -C "$coord_dir" add -A
git -C "$coord_dir" commit -q -m "Initialize registry test"

cat >"$coord_dir/issues/open/ROOT-ISS-1.yaml" <<'EOF_ROOT_ISSUE'
schema: coordination-item/v1
id: ROOT-ISS-1
type: issue
status: open
project: root
EOF_ROOT_ISSUE
git -C "$coord_dir" add issues/open/ROOT-ISS-1.yaml
git -C "$coord_dir" commit -q -m "Add root issue"
pi-en-coord-repo --coord-dir "$coord_dir" migrate-root-issues root-repo >/dev/null
test -f "$coord_dir/repos/root-repo/REPO.md"
grep -q '^domain_generated_files: \[\]$' "$coord_dir/repos/root-repo/REPO.md"
test ! -e "$coord_dir/REPOS.md"
test -f "$coord_dir/repos/root-repo/issues/open/ROOT-ISS-1.yaml"
test ! -e "$coord_dir/issues/open/ROOT-ISS-1.yaml"
git -C "$coord_dir" diff --cached --name-status | grep -q $'^R.*issues/open/ROOT-ISS-1.yaml.*repos/root-repo/issues/open/ROOT-ISS-1.yaml$'
git -C "$coord_dir" commit -q -m "Migrate root issue"
printf 'legacy registry index\n' >"$coord_dir/REPOS.md"
cp "$coord_dir/REPOS.md" "$tmp/legacy-REPOS.md"

cat >"$coord_dir/issues/open/ROOT-ISS-1.yaml" <<'EOF_DUP_ISSUE'
schema: coordination-item/v1
id: ROOT-ISS-1
type: issue
status: open
project: root
EOF_DUP_ISSUE
if pi-en-coord-repo --coord-dir "$coord_dir" migrate-root-issues root-repo >"$tmp/migrate-dup.out" 2>"$tmp/migrate-dup.err"; then
  printf 'duplicate root issue unexpectedly migrated\n' >&2
  exit 1
fi
grep -q 'target already exists' "$tmp/migrate-dup.err"
rm -f "$coord_dir/issues/open/ROOT-ISS-1.yaml"
cat >"$coord_dir/issues/open/ROOT-ISS-DUP.yaml" <<'EOF_DUP_ID'
schema: coordination-item/v1
id: ROOT-ISS-1
type: issue
status: open
project: root
EOF_DUP_ID
if pi-en-coord-repo --coord-dir "$coord_dir" migrate-root-issues root-repo >"$tmp/migrate-dup-id.out" 2>"$tmp/migrate-dup-id.err"; then
  printf 'duplicate issue id unexpectedly migrated\n' >&2
  exit 1
fi
grep -q 'duplicate issue id' "$tmp/migrate-dup-id.err"
rm -f "$coord_dir/issues/open/ROOT-ISS-DUP.yaml"

pi-en-coord-repo --coord-dir "$coord_dir" add other-repo >/dev/null
cat >"$coord_dir/repos/other-repo/issues/open/OTHER-ISS-1.yaml" <<'EOF_GLOBAL_DUP_ID'
schema: coordination-item/v1
id: GLOBAL-DUP-1
type: issue
status: open
project: other-repo
EOF_GLOBAL_DUP_ID
cat >"$coord_dir/issues/open/ROOT-GLOBAL-DUP.yaml" <<'EOF_ROOT_GLOBAL_DUP_ID'
schema: coordination-item/v1
id: GLOBAL-DUP-1
type: issue
status: open
project: root
EOF_ROOT_GLOBAL_DUP_ID
if pi-en-coord-repo --coord-dir "$coord_dir" migrate-root-issues root-repo >"$tmp/migrate-global-dup-id.out" 2>"$tmp/migrate-global-dup-id.err"; then
  printf 'global duplicate issue id unexpectedly migrated\n' >&2
  exit 1
fi
grep -q 'duplicate issue id' "$tmp/migrate-global-dup-id.err"
rm -f "$coord_dir/issues/open/ROOT-GLOBAL-DUP.yaml"

pi-en-coord-repo --coord-dir "$coord_dir" add alpha --remote https://example.invalid/alpha.git >/dev/null
test -f "$coord_dir/repos/alpha/REPO.md"
grep -q '^domain_generated_files: \[\]$' "$coord_dir/repos/alpha/REPO.md"
for state in open blocked done closed; do
  test -d "$coord_dir/repos/alpha/issues/$state"
done
pi-en-coord-repo --coord-dir "$coord_dir" list --active >"$tmp/list-active.out"
grep -q $'^alpha\tactive$' "$tmp/list-active.out"
pi-en-coord-repo --coord-dir "$coord_dir" show alpha | grep -q '^repo_id: alpha$'

issue_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id alpha "Alpha issue" | tail -n 1)"
case "$issue_path" in
  repos/alpha/issues/open/ALPHA-ISS-*.yaml) ;;
  *) printf 'unexpected repo issue path: %s\n' "$issue_path" >&2; exit 1 ;;
esac
issue_id="$(basename "$issue_path" .yaml)"
pi-en-coord-cat --coord-dir "$coord_dir" "$issue_id" | grep -q '^project: alpha$'

if pi-en-coord-repo --coord-dir "$coord_dir" retire alpha >"$tmp/retire.out" 2>"$tmp/retire.err"; then
  printf 'retire unexpectedly succeeded with open issue\n' >&2
  exit 1
fi
grep -q 'open issues' "$tmp/retire.err"

pi-en-coord-repo --coord-dir "$coord_dir" retire alpha --force | grep -q '^retired alpha$'
pi-en-coord-repo --coord-dir "$coord_dir" list --retired | grep -q $'^alpha\tretired$'
if pi-en-coord-new --coord-dir "$coord_dir" --repo-id alpha "Blocked by retirement" >"$tmp/new-retired.out" 2>"$tmp/new-retired.err"; then
  printf 'new issue unexpectedly succeeded for retired repo\n' >&2
  exit 1
fi
grep -q 'retired' "$tmp/new-retired.err"

pi-en-coord-repo --coord-dir "$coord_dir" add delta --remote https://example.invalid/not-delta.git >/dev/null
impl_dir="$tmp/impl"
mkdir -p "$impl_dir"
git -C "$impl_dir" init -q
git -C "$impl_dir" remote add origin https://example.invalid/not-delta.git
resolved_remote_repo="$(cd "$impl_dir" && bash -c '. "$0"; coord_resolve_repo_id "" "$1"' "$repo_root/scripts/pi-en-coord-lib.sh" "$coord_dir")"
test "$resolved_remote_repo" = delta
pi-en-coord-repo --coord-dir "$coord_dir" add epsilon --remote https://example.invalid/not-delta.git >/dev/null
if cd "$impl_dir" && bash -c '. "$0"; coord_resolve_repo_id "" "$1"' "$repo_root/scripts/pi-en-coord-lib.sh" "$coord_dir" >"$tmp/amb-remote.out" 2>"$tmp/amb-remote.err"; then
  printf 'ambiguous registry remote unexpectedly resolved\n' >&2
  exit 1
fi
grep -q 'ambiguous' "$tmp/amb-remote.err"

pi-en-coord-repo --coord-dir "$coord_dir" add beta >/dev/null
pi-en-coord-repo --coord-dir "$coord_dir" rename beta gamma >/dev/null
test "$(cat "$coord_dir/REPOS.md")" = "$(cat "$tmp/legacy-REPOS.md")"
test -d "$coord_dir/repos/gamma"
test ! -e "$coord_dir/repos/beta"
grep -q '^repo_id: gamma$' "$coord_dir/repos/gamma/REPO.md"
grep -q '^  - beta$' "$coord_dir/repos/gamma/REPO.md"
pi-en-coord-repo --coord-dir "$coord_dir" show beta 2>"$tmp/show-alias.err" | grep -q '^repo_id: gamma$'
grep -q "alias for 'gamma'" "$tmp/show-alias.err"

alias_issue_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id beta "Alias issue" 2>"$tmp/new-alias.err" | tail -n 1)"
case "$alias_issue_path" in
  repos/gamma/issues/open/GAMMA-ISS-*.yaml) ;;
  *) printf 'unexpected alias issue path: %s\n' "$alias_issue_path" >&2; exit 1 ;;
esac
grep -q "alias; update" "$tmp/new-alias.err"
alias_issue_id="$(basename "$alias_issue_path" .yaml)"
pi-en-coord-cat --coord-dir "$coord_dir" --path "$alias_issue_id" \
  | grep -q "^repos/gamma/issues/open/$alias_issue_id.yaml$"

pi-en-coord-claim \
  --coord-dir "$coord_dir" \
  --repo-id beta \
  --agent-id agent-a \
  --role developer \
  --no-pull \
  --no-push \
  "$alias_issue_id" >/dev/null
grep -q '^status: claimed$' "$coord_dir/$alias_issue_path"

done_path="$(pi-en-coord-done \
  --coord-dir "$coord_dir" \
  --repo-id beta \
  --agent-id agent-a \
  --role developer \
  --result "Repo issue implemented." \
  --implementation-ref \
  "delta:main@0123456789abcdef0123456789abcdef01234567" \
  --no-pull \
  --no-push \
  "$alias_issue_id" | tail -n 1)"
test "$done_path" = "repos/gamma/issues/done/$alias_issue_id.yaml"
test -f "$coord_dir/$done_path"
test ! -e "$coord_dir/repos/gamma/issues/open/$alias_issue_id.yaml"
grep -q '^status: done$' "$coord_dir/$done_path"
grep -q '^      - repo: delta$' "$coord_dir/$done_path"

pi-en-coord-review \
  --coord-dir "$coord_dir" \
  --repo-id gamma \
  --agent-id reviewer-a \
  --role reviewer \
  --pass \
  --result "Repo issue reviewed." \
  --no-pull \
  --no-push \
  "$alias_issue_id" >/dev/null
grep -q '^reviewed: true$' "$coord_dir/$done_path"

pi-en-coord-verify \
  --coord-dir "$coord_dir" \
  --repo-id gamma \
  --agent-id tester-a \
  --role tester \
  --pass \
  --result "Repo issue verified." \
  --no-pull \
  --no-push \
  "$alias_issue_id" >/dev/null
grep -q '^verified: true$' "$coord_dir/$done_path"

closed_path="$(pi-en-coord-close \
  --coord-dir "$coord_dir" \
  --repo-id gamma \
  --agent-id tester-a \
  --role tester \
  --result "Repo issue closed." \
  --no-pull \
  --no-push \
  "$alias_issue_id" | tail -n 1)"
test "$closed_path" = "repos/gamma/issues/closed/$alias_issue_id.yaml"
test -f "$coord_dir/$closed_path"
test ! -e "$coord_dir/repos/gamma/issues/done/$alias_issue_id.yaml"
grep -q '^status: closed$' "$coord_dir/$closed_path"
grep -q '^project: gamma$' "$coord_dir/$closed_path"
grep -q '^    type: claimed$' "$coord_dir/$closed_path"
grep -q '^    type: done$' "$coord_dir/$closed_path"
grep -q '^    type: reviewed$' "$coord_dir/$closed_path"
grep -q '^    type: verified$' "$coord_dir/$closed_path"
grep -q '^    type: closed$' "$coord_dir/$closed_path"

repo_fail_path="$(pi-en-coord-new --coord-dir "$coord_dir" --repo-id gamma "Repo failure path" | tail -n 1)"
repo_fail_id="$(basename "$repo_fail_path" .yaml)"
pi-en-coord-claim \
  --coord-dir "$coord_dir" \
  --repo-id gamma \
  --agent-id agent-a \
  --role developer \
  --no-pull \
  --no-push \
  "$repo_fail_id" >/dev/null
pi-en-coord-done \
  --coord-dir "$coord_dir" \
  --repo-id gamma \
  --agent-id agent-a \
  --role developer \
  --result "Ready for repo-scoped failure." \
  --implementation-ref \
  "gamma:main@0123456789abcdef0123456789abcdef01234567" \
  --no-pull \
  --no-push \
  "$repo_fail_id" >/dev/null
review_failed_path="$(pi-en-coord-review \
  --coord-dir "$coord_dir" \
  --repo-id gamma \
  --agent-id reviewer-a \
  --role reviewer \
  --fail \
  --result "Repo issue needs work." \
  --no-pull \
  --no-push \
  "$repo_fail_id" | tail -n 1)"
test "$review_failed_path" = "repos/gamma/issues/open/$repo_fail_id.yaml"
grep -q '^status: open$' "$coord_dir/$review_failed_path"
grep -q '^owner: null$' "$coord_dir/$review_failed_path"
grep -q '^    type: review_failed$' "$coord_dir/$review_failed_path"

mkdir -p "$coord_dir/issues/open"
cp "$coord_dir/$review_failed_path" "$coord_dir/issues/open/$repo_fail_id.yaml"
if pi-en-coord-cat --coord-dir "$coord_dir" "$repo_fail_id" >"$tmp/dup.out" 2>"$tmp/dup.err"; then
  printf 'duplicate repo-scoped issue id unexpectedly resolved\n' >&2
  exit 1
fi
grep -q "multiple items match $repo_fail_id" "$tmp/dup.err"
rm -f "$coord_dir/issues/open/$repo_fail_id.yaml"

for bad in Alpha .alpha alpha/one alpha-; do
  if pi-en-coord-repo --coord-dir "$coord_dir" add "$bad" >"$tmp/bad.out" 2>"$tmp/bad.err"; then
    printf 'invalid repo id accepted: %s\n' "$bad" >&2
    exit 1
  fi
done

mkdir -p "$coord_dir/repos/amb1" "$coord_dir/repos/amb2"
cat >"$coord_dir/repos/amb1/REPO.md" <<'EOF_AMB1'
---
repo_id: amb1
status: active
aliases:
  - old
---
EOF_AMB1
cat >"$coord_dir/repos/amb2/REPO.md" <<'EOF_AMB2'
---
repo_id: amb2
status: active
aliases:
  - old
---
EOF_AMB2
if pi-en-coord-repo --coord-dir "$coord_dir" show old >"$tmp/amb.out" 2>"$tmp/amb.err"; then
  printf 'ambiguous alias unexpectedly resolved\n' >&2
  exit 1
fi
grep -q 'ambiguous' "$tmp/amb.err"
