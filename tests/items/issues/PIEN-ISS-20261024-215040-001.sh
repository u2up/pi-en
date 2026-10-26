#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../.." && pwd -P)"
runner="$repo_root/scripts/pi-en-behavior"
tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT
command -v python3 >/dev/null
python3 -c 'import yaml' 2>/dev/null || { echo 'PyYAML unavailable; skipped'; exit 0; }

project="$tmp/project"
coord="$tmp/coordination"
"$runner" --project-root "$project" init >/dev/null
cat > "$project/pi-en-behaviors/MANIFEST.yaml" <<'YAML'
schema: v1
repository_id: example
authoritative: local
item_key: EXAMPLE
glossary: GLOSSARY.yaml
adapter: ./adapter
compliance: advisory
YAML
cat > "$project/pi-en-behaviors/GLOSSARY.yaml" <<'YAML'
language_version: v1
groups: [features]
terms:
  setup: {phase: given, args: {}}
  action: {phase: when, args: {}}
  result: {phase: then, args: {}}
YAML
cat > "$project/pi-en-behaviors/adapter" <<'SH'
#!/usr/bin/env bash
if [ "$1" = describe ]; then printf '%s\n' '{"terms":{"setup":{},"action":{},"result":{}}}'; fi
SH
chmod +x "$project/pi-en-behaviors/adapter"
cat > "$project/pi-en-behaviors/specifications/EXAMPLE-BHV-20261024-215040-001.yaml" <<'YAML'
schema: v1
language_version: v1
id: EXAMPLE-BHV-20261024-215040-001
group: features
status: active
title: Trace two requirements
feature: Traceability
rule: Required local requirements are covered
satisfies: [BHV-ONE, BHV-TWO]
scenarios:
  - id: executable
    title: works
    given: [{term: setup, args: {}}]
    when: [{term: action, args: {}}]
    then: [{term: result, args: {}}]
YAML

git init -q "$coord"
git -C "$coord" config user.email test@example.invalid
git -C "$coord" config user.name test
mkdir "$coord/requirements"
# Snapshot accepts coordination item files, and records only requirements that
# apply to its explicitly named repository.
cat > "$coord/requirements/EXAMPLE-FRQ-20261024-215040-001.yaml" <<'YAML'
schema: coordination-item/v1
id: EXAMPLE-FRQ-20261024-215040-001
type: functional-requirement
status: active
requirement_key: BHV-ONE
title: One
body: one
applicable_repos: [example]
behavior_coverage: required
YAML
cat > "$coord/requirements/EXAMPLE-QRQ-20261024-215040-001.yaml" <<'YAML'
schema: coordination-item/v1
id: EXAMPLE-QRQ-20261024-215040-001
type: quality-requirement
status: active
requirement_key: BHV-TWO
title: Two
body: two
behavior_coverage: required
YAML
git -C "$coord" add requirements
git -C "$coord" commit -qm requirements

# An ambient coordination directory is ignored; both explicit options are
# mandatory and the only file written is the local tracked snapshot.
PI_EN_COORD_DIR="$tmp/ignored" "$runner" --project-root "$project" requirements snapshot \
  --coord-dir "$coord" --repo-id example >/dev/null
[ -f "$project/pi-en-behaviors/requirements.snapshot.yaml" ]
[ ! -e "$tmp/ignored" ]
grep -Fq 'source_revision:' "$project/pi-en-behaviors/requirements.snapshot.yaml"
grep -Fq 'BHV-ONE' "$project/pi-en-behaviors/requirements.snapshot.yaml"
"$runner" --project-root "$project" coverage --format json > "$tmp/advisory.json"
grep -Fq '"passed": true' "$tmp/advisory.json"

# Inactive claims are advisory by default but fail when the local manifest
# explicitly opts into enforcement.
sed -i '0,/status: active/s//status: superseded/' "$project/pi-en-behaviors/requirements.snapshot.yaml"
"$runner" --project-root "$project" coverage > "$tmp/advisory.out"
grep -Fq 'claims inactive requirement BHV-ONE' "$tmp/advisory.out"
sed -i 's/compliance: advisory/compliance: enforced/' "$project/pi-en-behaviors/MANIFEST.yaml"
if "$runner" --project-root "$project" coverage --format json > "$tmp/enforced.json"; then
  echo 'enforced coverage unexpectedly passed' >&2
  exit 1
fi
grep -Fq 'claims inactive requirement BHV-ONE' "$tmp/enforced.json"

echo 'PIEN-ISS-20261024-215040-001 passed'
