#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PATH="$repo_root/scripts:$PATH"

serial_script="$repo_root/scripts/pi-en-serial-roles"
role_manager="$repo_root/role-manager"
tmp="$(mktemp -d)"
cleanup() { rm -rf "$tmp"; }
trap cleanup EXIT

export HOME="$tmp/home"
mkdir -p "$HOME"
git config --global user.name "Serial Scope Test"
git config --global user.email "serial-scope@example.invalid"

make_project_and_coord() {
  local name repo_id scenario project coord remote
  name="$1"
  repo_id="$2"
  scenario="$tmp/$name"
  project="$scenario/project"
  coord="$project/.pi-en/coordination"
  remote="$scenario/coordination.git"

  mkdir -p "$project"
  git -C "$project" init -q
  git -C "$project" checkout -q -b main
  git -C "$project" config user.name "Serial Scope Project"
  git -C "$project" config user.email "project@example.invalid"
  printf '/.pi-en/\n' >"$project/.gitignore"
  printf 'version: 1\nrepo_id: %s\n' "$repo_id" >"$project/.pi-en-coordination.yaml"
  git -C "$project" add .gitignore .pi-en-coordination.yaml
  git -C "$project" commit -q -m "Seed project"

  git init --bare -q "$remote"
  git --git-dir="$remote" symbolic-ref HEAD refs/heads/main
  mkdir -p "$coord"
  git -C "$coord" init -q
  git -C "$coord" checkout -q -b main
  git -C "$coord" config user.name "Serial Scope Coordination"
  git -C "$coord" config user.email "coordination@example.invalid"
  git -C "$coord" remote add origin "$remote"
  printf '# Coordination rules\n' >"$coord/AGENTS.md"
  printf 'project: pi-en\nitem_key: PIEN\n' >"$coord/PROJECT.md"

  SCENARIO_DIR="$scenario"
  SCENARIO_PROJECT="$project"
  SCENARIO_COORD="$coord"
}

add_repo_manifest() {
  local coord repo_id
  coord="$1"
  repo_id="$2"
  mkdir -p "$coord/repos/$repo_id"
  cat >"$coord/repos/$repo_id/REPO.md" <<EOF_REPO
---
repo_id: $repo_id
status: active
item_key: PIEN
project: pi-en
---

# $repo_id
EOF_REPO
}

add_issue() {
  local coord repo_path id status reviewed verified dir done_value event_type
  coord="$1"
  repo_path="$2"
  id="$3"
  status="$4"
  reviewed="$5"
  verified="$6"
  case "$status" in
    done) dir="$coord/$repo_path/issues/done"; done_value="2026-09-12T00:00:00Z"; event_type="done" ;;
    open) dir="$coord/$repo_path/issues/open"; done_value="null"; event_type="opened" ;;
    *) test_fail "unsupported status: $status" ;;
  esac
  mkdir -p "$dir"
  cat >"$dir/$id.yaml" <<EOF_ITEM
schema: coordination-item/v1
id: $id
type: issue
status: $status
project: pi-en
title: '$id'
owner: null
priority: medium
created: 2026-09-12T00:00:00Z
updated: 2026-09-12T00:00:00Z
done: $done_value
closed: null
reviewed: $reviewed
verified: $verified
testable: yes
testability_note: null
current:
  event: evt-0001
  message: msg-0001
events:
  - id: evt-0001
    type: $event_type
    at: 2026-09-12T00:00:00Z
    actor:
      id: serial-scope-test
      role: architect
    message: msg-0001
messages:
  - id: msg-0001
    event: evt-0001
    body: |-
      # $id
EOF_ITEM
}

commit_coord() {
  git -C "$1" add .
  git -C "$1" commit -q -m "Seed coordination"
  git -C "$1" push -q -u origin main
}

run_serial() {
  local project coord lock_file
  project="$1"
  coord="$2"
  lock_file="$3"
  shift 3
  "$serial_script" \
    --project-root "$project" \
    --coord-dir "$coord" \
    --agent-id serial-agent \
    --sleep 0 \
    --lock-file "$lock_file" \
    --pi-en "$serial_script" \
    --role-manager "$role_manager" \
    --dry-run --once "$@"
}

# Repository-layout selection must ignore higher-priority issues from other
# registered repositories and preserve role priority within the current repo.
make_project_and_coord repo-layout-priority namp-web
add_repo_manifest "$SCENARIO_COORD" namp
add_repo_manifest "$SCENARIO_COORD" namp-web
add_issue "$SCENARIO_COORD" repos/namp CROSS-TESTER done true false
add_issue "$SCENARIO_COORD" repos/namp-web IN-TESTER done true false
add_issue "$SCENARIO_COORD" repos/namp-web IN-REVIEWER done false false
add_issue "$SCENARIO_COORD" repos/namp-web IN-DEVELOPER open false false
commit_coord "$SCENARIO_COORD"
out="$SCENARIO_DIR/out.txt"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" >"$out" 2>&1
test_grep '^selected role=tester item=IN-TESTER$' "$out"

make_project_and_coord repo-layout-cross-vs-open namp-web
add_repo_manifest "$SCENARIO_COORD" namp
add_repo_manifest "$SCENARIO_COORD" namp-web
add_issue "$SCENARIO_COORD" repos/namp CROSS-REVIEWER done false false
add_issue "$SCENARIO_COORD" repos/namp-web IN-OPEN open false false
commit_coord "$SCENARIO_COORD"
out="$SCENARIO_DIR/out.txt"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/lock" >"$out" 2>&1
test_grep '^selected role=developer item=IN-OPEN$' "$out"

make_project_and_coord repo-layout-explicit namp-web
add_repo_manifest "$SCENARIO_COORD" namp
add_repo_manifest "$SCENARIO_COORD" namp-web
add_issue "$SCENARIO_COORD" repos/namp FOREIGN-ISSUE open false false
add_issue "$SCENARIO_COORD" repos/namp-web LOCAL-ISSUE open false false
add_issue "$SCENARIO_COORD" . ROOT-ISSUE open false false
commit_coord "$SCENARIO_COORD"
out="$SCENARIO_DIR/local.txt"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/local.lock" \
  --issue LOCAL-ISSUE >"$out" 2>&1
test_grep '^selected role=developer item=LOCAL-ISSUE$' "$out"
foreign_out="$SCENARIO_DIR/foreign.txt"
set +e
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/foreign.lock" \
  --issue FOREIGN-ISSUE >"$foreign_out" 2>&1
foreign_status=$?
set -e
[ "$foreign_status" -ne 0 ] || test_fail 'foreign explicit issue unexpectedly succeeded'
test_grep 'requested issue is outside current repository scope (namp-web): FOREIGN-ISSUE' \
  "$foreign_out"
root_out="$SCENARIO_DIR/root.txt"
set +e
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/root.lock" \
  --issue ROOT-ISSUE >"$root_out" 2>&1
root_status=$?
set -e
[ "$root_status" -ne 0 ] || test_fail 'root explicit issue in repo layout unexpectedly succeeded'
test_grep 'requested issue is outside current repository scope (namp-web): ROOT-ISSUE' \
  "$root_out"

# Legacy root-only coordination layouts retain root issues/... selection.
make_project_and_coord legacy-root pi-en
mkdir -p "$SCENARIO_COORD/issues/open" "$SCENARIO_COORD/issues/done"
add_issue "$SCENARIO_COORD" . LEGACY-OPEN open false false
commit_coord "$SCENARIO_COORD"
out="$SCENARIO_DIR/legacy.txt"
run_serial "$SCENARIO_PROJECT" "$SCENARIO_COORD" "$SCENARIO_DIR/legacy.lock" >"$out" 2>&1
test_grep '^selected role=developer item=LEGACY-OPEN$' "$out"

printf 'serial role repo scope tests passed\n'
