#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
runner="$repo_root/scripts/pi-en-behavior"
command -v python3 >/dev/null
python3 -c 'import yaml' 2>/dev/null || { echo 'PyYAML unavailable; behavior runtime test skipped'; exit 0; }
"$runner" --project-root "$tmp" init
[ -f "$tmp/pi-en-behaviors/MANIFEST.yaml" ]
[ -f "$tmp/pi-en-behaviors/GLOSSARY.yaml" ]
# init is additive.
printf '# retained\n' >> "$tmp/pi-en-behaviors/GLOSSARY.yaml"
"$runner" --project-root "$tmp" init
grep -Fq '# retained' "$tmp/pi-en-behaviors/GLOSSARY.yaml"
cat > "$tmp/pi-en-behaviors/MANIFEST.yaml" <<'YAML'
schema: v1
repository_id: test
item_key: TEST
glossary: GLOSSARY.yaml
adapter: ./adapter
YAML
cat > "$tmp/pi-en-behaviors/GLOSSARY.yaml" <<'YAML'
language_version: v1
groups: [features/demo]
terms:
  prepared: {phase: given, args: {name: string}}
  invoked: {phase: when, args: {}}
  observed: {phase: then, args: {ok: boolean}}
YAML
cat > "$tmp/pi-en-behaviors/adapter" <<'SH'
#!/usr/bin/env bash
set -euo pipefail
if [ "$1" = describe ]; then printf '%s\n' '{"terms":{"prepared":{},"invoked":{},"observed":{}}}'; exit 0; fi
[ -f "$3" ] && [ -d "$4" ]
SH
chmod +x "$tmp/pi-en-behaviors/adapter"
cat > "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml" <<'YAML'
schema: v1
language_version: v1
id: TEST-BHV-20261024-215036-001
group: features/demo
status: active
title: Demonstrate behavior
feature: Demo
rule: A public result is observed
tags: [demo]
satisfies: [BHV-001]
scenarios:
  - id: normal
    title: works
    given: [{term: prepared, args: {name: safe}}]
    when: [{term: invoked, args: {}}]
    then: [{term: observed, args: {ok: true}}]
YAML
"$runner" --project-root "$tmp" lint
"$runner" --project-root "$tmp" test --group features
"$runner" --project-root "$tmp" list --group features/demo | grep -Fq 'TEST-BHV-20261024-215036-001'
"$runner" --project-root "$tmp" index | grep -Fq 'scenario_count'
"$runner" --project-root "$tmp" regroup TEST-BHV-20261024-215036-001 --group features/demo/renamed
! "$runner" --project-root "$tmp" new --id TEST-BHV-20261024-215036-002 --group ../unsafe --title unsafe
cp "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml" "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-003.yaml"
! "$runner" --project-root "$tmp" lint
printf 'pi-en behavior tests passed\n'
