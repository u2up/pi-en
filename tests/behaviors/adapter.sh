#!/usr/bin/env bash
# Behavior adapter: operates only in the runner-provided temporary fixture.
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd -P)"
pien="$repo_root/pien"
phase="${1:-}"

if [ "$phase" = describe ]; then
  printf '%s\n' '{"terms":{"isolated fixture":{},"coordination fixture":{},"dispatcher command":{},"open item command":{},"lint command":{},"status command":{},"dispatcher output":{},"item is listed":{},"lint rejects missing test":{},"state is unchanged":{}}}'
  exit 0
fi

term="$2"
args="$3"
state="$4"
value() {
  local key="$1"
  python3 -c 'import json, sys; v=json.load(open(sys.argv[1]))[sys.argv[2]]; print(str(v).lower() if isinstance(v, bool) else v)' "$args" "$key"
}
record_snapshot() {
  local repository="$state/project"
  [ -d "$state/project/.pi-en/coordination/.git" ] && repository="$state/project/.pi-en/coordination"
  git -C "$repository" rev-parse HEAD > "$state/before"
}

case "$phase:$term" in
  'given:isolated fixture')
    mkdir -p "$state/project"
    git -C "$state/project" init -q
    git -C "$state/project" config user.email behavior@example.invalid
    git -C "$state/project" config user.name behavior
    printf '%s\n' "$(value name)" > "$state/project/fixture"
    git -C "$state/project" add fixture
    git -C "$state/project" commit -qm fixture
    record_snapshot
    ;;
  'given:coordination fixture')
    mkdir -p "$state/project" "$state/remotes"
    git init -q --bare "$state/remotes/coordination.git"
    (
      cd "$state/project"
      "$pien" coord init --dir "$state/project/.pi-en/coordination" \
        --remote "$state/remotes/coordination.git" --project behavior \
        --project-key BHV --repo-id fixture --agent-id behavior --role developer
    ) >"$state/setup.out" 2>&1
    # The fixture starts with a testable repo-scoped issue but deliberately
    # has no implementation test, so lint can report that public condition.
    (cd "$state/project" && PI_EN_COORD_DIR="$state/project/.pi-en/coordination" \
      "$pien" coord new --repo-id fixture --type issue --category feature-request \
      --agent-id behavior --role developer 'Fixture issue') >>"$state/setup.out" 2>&1
    ;;
  'when:dispatcher command')
    command="$(value command)"
    set +e
    (cd "$state/project" && "$pien" "$command") >"$state/output" 2>&1
    printf '%s' "$?" >"$state/status"
    set -e
    ;;
  'when:open item command')
    title="$(value title)"
    (cd "$state/project" && PI_EN_COORD_DIR="$state/project/.pi-en/coordination" \
      "$pien" coord new --repo-id fixture --type issue --category feature-request \
      --agent-id behavior --role developer "$title") >"$state/output" 2>&1
    grep -Eo '[A-Z0-9]+-ISS-[0-9]{8}-[0-9]{6}-[0-9]{3}' "$state/output" | head -n1 > "$state/item"
    ;;
  'when:lint command')
    record_snapshot
    set +e
    (cd "$state/project" && PI_EN_COORD_DIR="$state/project/.pi-en/coordination" \
      "$pien" coord lint --repo-id fixture --project-root "$state/project") >"$state/output" 2>&1
    printf '%s' "$?" >"$state/status"
    set -e
    ;;
  'when:status command')
    record_snapshot
    (cd "$state/project" && PI_EN_COORD_DIR="$state/project/.pi-en/coordination" \
      "$pien" coord status --repo-id fixture) >"$state/output" 2>&1
    ;;
  'then:dispatcher output')
    grep -Fq "$(value contains)" "$state/output"
    expected="$(value succeeds)"; actual=false
    [ "$(cat "$state/status")" = 0 ] && actual=true
    [ "$actual" = "$expected" ]
    ;;
  'then:item is listed')
    item="$(cat "$state/item")"
    PI_EN_COORD_DIR="$state/project/.pi-en/coordination" "$pien" coord list issues \
      --repo-id fixture | grep -Fq "$item"
    ;;
  'then:lint rejects missing test')
    [ "$(cat "$state/status")" -ne 0 ]
    grep -Fq 'is testable but missing' "$state/output"
    ;;
  'then:state is unchanged')
    repository="$state/project"
    [ -d "$state/project/.pi-en/coordination/.git" ] && repository="$state/project/.pi-en/coordination"
    [ "$(git -C "$repository" rev-parse HEAD)" = "$(cat "$state/before")" ]
    ;;
  *)
    printf 'unsupported behavior term: %s %s\n' "$phase" "$term" >&2
    exit 2
    ;;
esac
