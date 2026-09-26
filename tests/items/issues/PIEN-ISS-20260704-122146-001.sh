#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

make_repo() {
  local coord_dir="$1"
  local repo_id="$2"
  local status="${3:-active}"
  mkdir -p "$coord_dir/repos/$repo_id/issues/open" \
    "$coord_dir/repos/$repo_id/issues/blocked" \
    "$coord_dir/repos/$repo_id/issues/done" \
    "$coord_dir/repos/$repo_id/issues/closed"
  cat >"$coord_dir/repos/$repo_id/REPO.md" <<EOF_REPO
---
repo_id: $repo_id
status: $status
item_key: ${repo_id^^}
project: $repo_id
---

# $repo_id
EOF_REPO
}

make_issue() {
  local file="$1"
  local id="$2"
  local status="$3"
  local testable="${4:-no}"
  mkdir -p "$(dirname "$file")"
  cat >"$file" <<EOF_ITEM
schema: coordination-item/v1
id: $id
type: issue
category: task
status: $status
project: alpha
owner: test
priority: medium
created: 2026-07-04T00:00:00Z
updated: 2026-07-04T00:00:00Z
done: null
closed: null
reviewed: false
verified: false
testable: $testable
testability_note: 'fixture item'
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: opened
    at: 2026-07-04T00:00:00Z
    actor:
      id: test
      role: developer
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      Fixture item.
EOF_ITEM
}

coord_dir="$tmp/coordination"
project_root="$tmp/project"
mkdir -p "$coord_dir" "$project_root/tests/items/issues"
git -C "$coord_dir" init -q
cat >"$coord_dir/PROJECT.md" <<'EOF_PROJECT'
---
project: domain
item_key: DOM
---
EOF_PROJECT
make_repo "$coord_dir" alpha active
make_repo "$coord_dir" beta active
make_issue "$coord_dir/repos/alpha/issues/open/ALPHA-ISS-1.yaml" ALPHA-ISS-1 claimed yes
make_issue "$coord_dir/repos/beta/issues/open/BETA-ISS-1.yaml" BETA-ISS-1 open yes
cat >"$project_root/.pi-en-coordination.yaml" <<'EOF_CFG'
version: 1
repo_id: alpha
EOF_CFG
cat >"$project_root/tests/items/issues/ALPHA-ISS-1.sh" <<'EOF_TEST'
#!/usr/bin/env bash
set -euo pipefail
EOF_TEST
chmod +x "$project_root/tests/items/issues/ALPHA-ISS-1.sh"

# Default lint resolves the current implementation repo and does not require
# item-matched tests for every repo in the coordination domain.
pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" >/dev/null
pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" --all-repos >/dev/null

# All-repos mode validates every repo structurally through the item index, but
# it does not require repo-scoped item tests unless --repo-id is explicit.
mv "$project_root/tests/items/issues/ALPHA-ISS-1.sh" "$tmp/ALPHA-ISS-1.sh"
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
  >"$tmp/default-missing-alpha.out" 2>"$tmp/default-missing-alpha.err"; then
  printf 'expected default lint to require selected alpha issue test\n' >&2
  exit 1
fi
grep -q 'ALPHA-ISS-1.yaml is testable but missing' "$tmp/default-missing-alpha.err"
pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" --all-repos >/dev/null
mv "$tmp/ALPHA-ISS-1.sh" "$project_root/tests/items/issues/ALPHA-ISS-1.sh"

# Explicit repo selection requires that repo's item-matched issue tests.
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
  --repo-id beta >"$tmp/beta.out" 2>"$tmp/beta.err"; then
  printf 'expected lint to require selected beta issue test\n' >&2
  exit 1
fi
grep -q 'BETA-ISS-1.yaml is testable but missing' "$tmp/beta.err"

# Invalid repo namespaces, invalid status directories, retired repos, and root
# issue migration failures are rejected.
mkdir -p "$coord_dir/repos/Mixed/issues/open"
make_issue "$coord_dir/repos/Mixed/issues/open/BADREPO-ISS-1.yaml" BADREPO-ISS-1 open no
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
  >"$tmp/badrepo.out" 2>"$tmp/badrepo.err"; then
  printf 'expected lint to fail for invalid repo id\n' >&2
  exit 1
fi
grep -q 'invalid repo id' "$tmp/badrepo.err"
rm -rf "$coord_dir/repos/Mixed"

mkdir -p "$coord_dir/repos/alpha/issues/weird"
make_issue "$coord_dir/repos/alpha/issues/weird/ALPHA-ISS-WEIRD.yaml" ALPHA-ISS-WEIRD open no
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
  >"$tmp/badstatus.out" 2>"$tmp/badstatus.err"; then
  printf 'expected lint to fail for invalid status directory\n' >&2
  exit 1
fi
grep -q 'not under a valid issues status directory' "$tmp/badstatus.err"
rm -rf "$coord_dir/repos/alpha/issues/weird"

make_repo "$coord_dir" old retired
make_issue "$coord_dir/repos/old/issues/open/OLD-ISS-1.yaml" OLD-ISS-1 open no
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
  >"$tmp/retired.out" 2>"$tmp/retired.err"; then
  printf 'expected lint to fail for retired repo issue\n' >&2
  exit 1
fi
grep -q 'non-active repo id old' "$tmp/retired.err"
rm -rf "$coord_dir/repos/old"

mkdir -p "$coord_dir/issues/open"
make_issue "$coord_dir/issues/open/ROOT-ISS-1.yaml" ROOT-ISS-1 open no
if PI_EN_COORD_LINT_ROOT_ISSUES=fail \
  pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
    >"$tmp/root.out" 2>"$tmp/root.err"; then
  printf 'expected lint to fail for root issue migration policy\n' >&2
  exit 1
fi
grep -q 'uses root issues/ during repo-scope migration' "$tmp/root.err"
rm -rf "$coord_dir/issues"

# Duplicate IDs fail globally across repo namespaces.
make_issue "$coord_dir/repos/beta/issues/open/ALPHA-ISS-1.yaml" ALPHA-ISS-1 open no
if pi-en-coord-lint --coord-dir "$coord_dir" --project-root "$project_root" \
  >"$tmp/dup.out" 2>"$tmp/dup.err"; then
  printf 'expected lint to fail for duplicate issue IDs\n' >&2
  exit 1
fi
grep -q 'duplicates item id ALPHA-ISS-1' "$tmp/dup.err"

printf 'repo-scoped issue lint tests passed\n'
