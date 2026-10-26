#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
cd "$repo_root"
. tests/lib/test-helpers.sh

tmpdir="$(mktemp -d)"
trap 'rm -rf "$tmpdir"' EXIT

fakebin="$tmpdir/fakebin"
project="$tmpdir/project"
state="$tmpdir/state"
capture="$tmpdir/bwrap.args"
mkdir -p "$fakebin" "$project" "$state"
cat >"$fakebin/pi" <<'SH'
#!/usr/bin/env bash
exit 99
SH
cat >"$fakebin/bwrap" <<'SH'
#!/usr/bin/env bash
printf '%s\n' "$@" >"$PI_EN_TEST_BWRAP_CAPTURE"
SH
chmod +x "$fakebin/pi" "$fakebin/bwrap"

PATH="$fakebin:$PATH" \
PI_EN_RUNTIME_PATH="$tmpdir/runtime/bin" \
PI_EN_BWRAP_BASH="$(command -v bash)" \
PI_EN_BWRAP_ENV="$(command -v env)" \
PI_EN_BWRAP_BWRAP="$fakebin/bwrap" \
PI_EN_TEST_BWRAP_CAPTURE="$capture" \
PI_EN_BWRAP_PROJECT_ROOT="$project" \
PI_EN_BWRAP_STATE_DIR="$state" \
PI_EN_BWRAP_IMPORT_COMMON=0 \
PI_EN_BWRAP_IMPORT_EXTENSIONS=0 \
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 \
PI_EN_BWRAP_IMPORT_AUTH=0 \
PI_EN_BWRAP_IMPORT_SESSIONS=0 \
bash scripts/pi-en-bwrap -- --version

test_grep '^--clearenv$' "$capture"
if ! awk 'prev == "--setenv" && $0 == "PYTHONPYCACHEPREFIX" { getline; found = ($0 == "/home/pi/.cache/python-bytecode") } { prev = $0 } END { exit found ? 0 : 1 }' "$capture"; then
  test_fail 'Bubblewrap must set the sandbox Python cache prefix after clearenv'
fi

command -v python3 >/dev/null 2>&1 || test_fail 'python3 is required'
python3 -c 'import yaml' 2>/dev/null || {
  printf 'PIEN-ISS-20261026-062812-001 skipped behavior check: PyYAML unavailable\n'
  exit 0
}

behavior_project="$tmpdir/behavior-project"
cache_home="$tmpdir/cache-home"
mkdir -p "$behavior_project/pi-en-behaviors/specifications" "$cache_home"
printf 'VALUE = 1\n' >"$behavior_project/local_module.py"
cat >"$behavior_project/pi-en-behaviors/MANIFEST.yaml" <<'YAML'
schema: v1
repository_id: test
item_key: TEST
glossary: GLOSSARY.yaml
adapter: ./adapter
YAML
cat >"$behavior_project/pi-en-behaviors/GLOSSARY.yaml" <<'YAML'
language_version: v1
groups: [cache]
terms:
  run: {phase: when, args: {}}
YAML
cat >"$behavior_project/pi-en-behaviors/specifications/TEST-BHV-20261026-062812-001.yaml" <<'YAML'
schema: v1
language_version: v1
id: TEST-BHV-20261026-062812-001
group: cache
status: active
title: Cache prefix reaches adapters
feature: Python cache isolation
rule: Adapters inherit Pi-en's cache prefix
scenarios:
  - id: import-local-module
    title: imports without project bytecode
    given: []
    when: [{term: run, args: {}}]
    then: []
YAML
cat >"$behavior_project/pi-en-behaviors/adapter" <<SH
#!/usr/bin/env bash
set -euo pipefail
if [ "\$1" = describe ]; then printf '%s\\n' '{"terms":{"run":{}}}'; exit 0; fi
printf '%s\\n' "\$PYTHONPYCACHEPREFIX" > "$tmpdir/adapter-cache-prefix"
PYTHONPATH="$behavior_project" python3 -c 'import local_module'
SH
chmod +x "$behavior_project/pi-en-behaviors/adapter"

HOME="$tmpdir/home" XDG_CACHE_HOME="$cache_home" \
  scripts/pi-en-behavior --project-root "$behavior_project" test

test_eq "$cache_home/pi-en/python-bytecode" "$(<"$tmpdir/adapter-cache-prefix")" \
  'behavior adapter cache prefix'
if find "$behavior_project" -type d -name __pycache__ | grep -q .; then
  test_fail 'behavior adapter created a project-local __pycache__'
fi
find "$cache_home/pi-en/python-bytecode" -name 'local_module*.pyc' | grep -q . \
  || test_fail 'redirected behavior bytecode cache was not created'

serial_project="$tmpdir/serial-project"
mkdir -p "$serial_project/.pi-en/coordination"
git -C "$serial_project" init -q
git -C "$serial_project" config user.email test@example.invalid
git -C "$serial_project" config user.name test
printf 'tracked\n' >"$serial_project/tracked"
git -C "$serial_project" add tracked
git -C "$serial_project" commit -qm initial
git -C "$serial_project/.pi-en/coordination" init -q
git -C "$serial_project/.pi-en/coordination" config user.email test@example.invalid
git -C "$serial_project/.pi-en/coordination" config user.name test
printf '# coordination rules\n' >"$serial_project/.pi-en/coordination/AGENTS.md"
git -C "$serial_project/.pi-en/coordination" add AGENTS.md
git -C "$serial_project/.pi-en/coordination" commit -qm initial
printf 'genuine untracked work\n' >"$serial_project/untracked-work"
if scripts/pi-en-serial-roles --dry-run --once --ui none \
  --project-root "$serial_project" \
  --coord-dir "$serial_project/.pi-en/coordination" >"$tmpdir/serial.out" 2>&1; then
  test_fail 'serial roles accepted a genuinely untracked project file'
fi
test_grep 'unexpected dirty project working tree' "$tmpdir/serial.out"
test_grep 'untracked-work' "$tmpdir/serial.out"

printf 'PIEN-ISS-20261026-062812-001 tests passed\n'
