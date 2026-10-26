#!/usr/bin/env bash
set -euo pipefail
repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp="$(mktemp -d)"; trap 'rm -rf "$tmp"' EXIT
runner="$repo_root/scripts/pi-en-behavior"
command -v python3 >/dev/null
python3 -c 'import yaml' 2>/dev/null || { echo 'PyYAML unavailable; behavior runtime test skipped'; exit 0; }
# The launcher must not fall back to a caller-selected host interpreter.
if env PATH=/bin:/usr/bin PYTHON="$(command -v python3)" "$runner" --help >"$tmp/no-runtime.out" 2>&1; then
  echo 'behavior runner unexpectedly used a host Python fallback' >&2
  exit 1
fi
grep -Fqx 'pi-en behavior: Python runtime unavailable; rebuild and relaunch with `nix develop`.' "$tmp/no-runtime.out"
"$runner" --project-root "$tmp" init
[ -f "$tmp/pi-en-behaviors/MANIFEST.yaml" ]
[ -f "$tmp/pi-en-behaviors/GLOSSARY.yaml" ]
grep -Fqx 'compliance: advisory' "$tmp/pi-en-behaviors/MANIFEST.yaml"
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
compliance: advisory
YAML
cat > "$tmp/pi-en-behaviors/GLOSSARY.yaml" <<'YAML'
language_version: v1
groups: [features/demo]
terms:
  prepared: {phase: given, args: {name: string}}
  invoked: {phase: when, args: {}}
  observed: {phase: then, args: {ok: boolean}}
YAML
runtime="$tmp/trusted-runtime"
mkdir "$runtime"
ln -s "$(command -v bash)" "$runtime/bash"
cat > "$runtime/python3" <<'SH'
#!/usr/bin/env bash
printf 'trusted runtime dependency\n'
SH
chmod +x "$runtime/python3"
cat > "$tmp/pi-en-behaviors/adapter" <<SH
#!/usr/bin/env bash
set -euo pipefail
if [ "\$1" = describe ]; then
  [ -z "\${PI_EN_COORD_DIR:-}" ]
  [ "\$PWD" != "\${0%/*}" ]
  printf '%s\\n' '{"terms":{"prepared":{},"invoked":{},"observed":{}}}'
  exit 0
fi
[ -f "\$3" ] && [ -d "\$4" ]
[ "\$PWD" = "\$4" ]
case "\$PATH" in
  /bin:/usr/bin) ;;
  "$runtime") [ "\$(python3)" = 'trusted runtime dependency' ] ;;
  *) exit 1 ;;
esac
[ -z "\${PI_EN_COORD_DIR:-}" ]
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
grep -v '^compliance:' "$tmp/pi-en-behaviors/MANIFEST.yaml" > "$tmp/MANIFEST.yaml"
mv "$tmp/MANIFEST.yaml" "$tmp/pi-en-behaviors/MANIFEST.yaml"
if "$runner" --project-root "$tmp" lint >"$tmp/missing-compliance.out" 2>&1; then
  echo 'behavior lint accepted a manifest without compliance mode' >&2
  exit 1
fi
grep -Fq 'compliance must be advisory or enforced' "$tmp/missing-compliance.out"
printf '%s\n' 'compliance: advisory' >> "$tmp/pi-en-behaviors/MANIFEST.yaml"
env PATH=/caller-controlled-path HOME="$HOME" PI_EN_COORD_DIR="$repo_root/.pi-en/coordination" PI_EN_BEHAVIOR_RUNTIME_PATH="$runtime" "$(command -v python3)" "$repo_root/scripts/pi-en-behavior.py" --project-root "$tmp" test --group features
"$runner" --project-root "$tmp" list --group features/demo | grep -Fq 'TEST-BHV-20261024-215036-001'
"$runner" --project-root "$tmp" index | grep -Fq 'scenario_count'
"$runner" --project-root "$tmp" document > "$tmp/behavior-documentation.md"
grep -Fq '# Behavior documentation: test' "$tmp/behavior-documentation.md"
grep -Fq '[features/demo](#features-demo)' "$tmp/behavior-documentation.md"
# Catalog links target an explicit stable anchor, not renderer-specific heading slugs.
grep -Fqx '<a id="features-demo"></a>' "$tmp/behavior-documentation.md"
grep -Fq '### Demonstrate behavior (`TEST-BHV-20261024-215036-001`)' "$tmp/behavior-documentation.md"
grep -Fq -- '- Feature: Demo' "$tmp/behavior-documentation.md"
"$runner" --project-root "$tmp" regroup TEST-BHV-20261024-215036-001 --group features/demo/renamed
! "$runner" --project-root "$tmp" regroup TEST-BHV-20261024-215036-001 --group unlisted
"$runner" --project-root "$tmp" lint
! "$runner" --project-root "$tmp" new --id TEST-BHV-20261024-215036-002 --group ../unsafe --title unsafe
! "$runner" --project-root "$tmp" new --id TEST-BHV-20261024-215036-002 --group unlisted --title unsafe
cp "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml" "$tmp/outside.yaml"
before="$(sha256sum "$tmp/outside.yaml")"
rm "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml"
ln -s "$tmp/outside.yaml" "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml"
! "$runner" --project-root "$tmp" lint
! "$runner" --project-root "$tmp" regroup TEST-BHV-20261024-215036-001 --group features/demo
[ "$before" = "$(sha256sum "$tmp/outside.yaml")" ]
rm "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml"
cp "$tmp/outside.yaml" "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml"
cp "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-001.yaml" "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-003.yaml"
! "$runner" --project-root "$tmp" lint
rm "$tmp/pi-en-behaviors/specifications/TEST-BHV-20261024-215036-003.yaml"
cat > "$tmp/pi-en-behaviors/GLOSSARY.yaml" <<'YAML'
language_version: v1
groups: [features/demo]
terms:
  prepared: {phase: given, args: {name: unsupported}}
  invoked: {phase: when, args: {}}
  observed: {phase: then, args: {ok: boolean}}
YAML
if "$runner" --project-root "$tmp" lint >"$tmp/unsupported-type.out" 2>&1; then
  echo 'behavior lint accepted an unsupported glossary argument type' >&2
  exit 1
fi
grep -Fq 'unsupported argument type' "$tmp/unsupported-type.out"
cat > "$tmp/pi-en-behaviors/GLOSSARY.yaml" <<'YAML'
language_version: v1
groups: [features/demo]
terms:
  prepared: {phase: unsupported, args: {name: string}}
  invoked: {phase: when, args: {}}
  observed: {phase: then, args: {ok: boolean}}
YAML
if "$runner" --project-root "$tmp" lint >"$tmp/invalid-phase.out" 2>&1; then
  echo 'behavior lint accepted an invalid glossary phase' >&2
  exit 1
fi
grep -Fq 'phase must be given, when, or then' "$tmp/invalid-phase.out"
printf 'pi-en behavior tests passed\n'
