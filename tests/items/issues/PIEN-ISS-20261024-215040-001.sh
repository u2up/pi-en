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

# Snapshot output must be the project-local artifact, never a symlink target.
target="$tmp/snapshot-target.yaml"
printf 'unchanged\n' > "$target"
rm "$project/pi-en-behaviors/requirements.snapshot.yaml"
ln -s "$target" "$project/pi-en-behaviors/requirements.snapshot.yaml"
if "$runner" --project-root "$project" requirements snapshot --coord-dir "$coord" --repo-id example; then
  echo 'snapshot unexpectedly followed symlink output' >&2
  exit 1
fi
grep -Fxq 'unchanged' "$target"
rm "$project/pi-en-behaviors/requirements.snapshot.yaml"

# Replacing a hard link must not truncate the external name.  Atomic replace
# leaves the target unchanged and installs an independent local snapshot.
ln "$target" "$project/pi-en-behaviors/requirements.snapshot.yaml"
"$runner" --project-root "$project" requirements snapshot --coord-dir "$coord" --repo-id example >/dev/null
grep -Fxq 'unchanged' "$target"
[ "$(stat -c %h "$project/pi-en-behaviors/requirements.snapshot.yaml")" -eq 1 ]
grep -Fq 'BHV-ONE' "$project/pi-en-behaviors/requirements.snapshot.yaml"

# A snapshot must identify the exact committed coordination source.  Refuse a
# dirty checkout rather than recording a HEAD revision for uncommitted content.
printf '\n# uncommitted requirement change\n' >> "$coord/requirements/EXAMPLE-FRQ-20261024-215040-001.yaml"
if "$runner" --project-root "$project" requirements snapshot --coord-dir "$coord" --repo-id example > "$tmp/dirty.out" 2>&1; then
  echo 'snapshot unexpectedly accepted dirty coordination source' >&2
  exit 1
fi
grep -Fq 'must be a clean Git checkout' "$tmp/dirty.out"
grep -Fq 'BHV-ONE' "$project/pi-en-behaviors/requirements.snapshot.yaml"
git -C "$coord" checkout -- requirements/EXAMPLE-FRQ-20261024-215040-001.yaml

# Ignored, untracked requirement YAML must not enter a snapshot that identifies
# only the committed source revision.
printf 'requirements/ignored.yaml\n' > "$coord/.gitignore"
git -C "$coord" add .gitignore
git -C "$coord" commit -qm ignore-untracked-requirement
cat > "$coord/requirements/ignored.yaml" <<'YAML'
schema: coordination-item/v1
id: EXAMPLE-FRQ-20261024-215040-099
type: functional-requirement
status: active
requirement_key: IGNORED
title: Ignored
body: ignored
behavior_coverage: required
YAML
"$runner" --project-root "$project" requirements snapshot --coord-dir "$coord" --repo-id example >/dev/null
if grep -Fq 'IGNORED' "$project/pi-en-behaviors/requirements.snapshot.yaml"; then
  echo 'snapshot unexpectedly included ignored requirement YAML' >&2
  exit 1
fi

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

# Coverage must report an active BHV without executable scenarios instead of
# failing structural validation before it can produce an advisory report.
sed -i 's/compliance: enforced/compliance: advisory/' "$project/pi-en-behaviors/MANIFEST.yaml"
sed -i '/^scenarios:/,$c\scenarios: []' "$project/pi-en-behaviors/specifications/EXAMPLE-BHV-20261024-215040-001.yaml"
"$runner" --project-root "$project" coverage --format json > "$tmp/no-scenarios.json"
grep -Fq '"passed": false' "$tmp/no-scenarios.json"
grep -Fq 'has no executable scenarios' "$tmp/no-scenarios.json"
# A behavior without scenarios is not executable coverage: report both its
# structural violation and the missing required requirement coverage.
grep -Fq 'required requirement BHV-TWO has no active BHV coverage' "$tmp/no-scenarios.json"

echo 'PIEN-ISS-20261024-215040-001 passed'
