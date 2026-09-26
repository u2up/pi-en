#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
export PI_EN_COORD_LIB="$repo_root/scripts/pi-en-coord-lib.sh"
export PI_EN_COORD_TEMPLATE_DIR="$repo_root/pi-skill-templates/agent-coordination"
export PATH="$repo_root/scripts:$PATH"

tmp="$(mktemp -d)"
trap 'rm -rf "$tmp"' EXIT

export HOME="$tmp/home"
unset PI_EN_COORD_REMOTE PI_EN_COORD_WORKSPACE \
  PI_EN_COORD_DIR PI_EN_COORD_AGENT_ID PI_EN_COORD_PROJECT PI_EN_COORD_PROJECT_KEY PI_EN_COORD_ROLE
mkdir -p "$HOME" "$tmp/project"
git config --global user.name "Coordination Test"
git config --global user.email "coordination-test@example.invalid"

cd "$tmp/project"
pi-en-coord-init \
  --root "$tmp/remotes" \
  --project pi-en \
  --agent-id agent-a \
  --dir .pi-en/coordination >/dev/null
export PI_EN_COORD_REPO_ID=pi-en

item_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type issue \
  "Lint item-matched tests" | tail -n 1)"
item_id="$(grep '^id: ' ".pi-en/coordination/$item_path" | sed 's/^id: //')"

grep -q '^testable: yes$' ".pi-en/coordination/$item_path"
cp ".pi-en/coordination/$item_path" "$tmp/item.clean.yaml"
printf 'issue_type: bug\n' >>".pi-en/coordination/$item_path"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for legacy issue_type field\n' >&2
  exit 1
fi
cp "$tmp/item.clean.yaml" ".pi-en/coordination/$item_path"
case "$item_path" in
  repos/pi-en/issues/open/"$item_id".yaml) ;;
  *) printf 'unexpected item path: %s\n' "$item_path" >&2; exit 1 ;;
esac

if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for missing item-matched test\n' >&2
  exit 1
fi

mkdir -p tests/items/issues
cat >"tests/items/issues/$item_id.sh" <<'EOF_TEST'
#!/usr/bin/env bash
set -euo pipefail
printf 'item-matched test placeholder passed\n'
EOF_TEST
chmod +x "tests/items/issues/$item_id.sh"

pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null

if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . \
  --require-done-or-closed >/dev/null 2>&1; then
  printf 'expected done-or-closed lint to fail for open issue\n' >&2
  exit 1
fi

requirement_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type functional-requirement \
  --requirement-key FRQ-001 \
  --testable no \
  --testability-note "Reviewed as a policy requirement." \
  "Lint functional requirement item" | tail -n 1)"
requirement_id="$(grep '^id: ' ".pi-en/coordination/$requirement_path" | sed 's/^id: //')"

case "$requirement_path" in
  requirements/"$requirement_id".yaml) ;;
  *) printf 'unexpected requirement path: %s\n' "$requirement_path" >&2; exit 1 ;;
esac
grep -q '^id: PIEN-FRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-en/coordination/$requirement_path"
grep -q '^status: active$' ".pi-en/coordination/$requirement_path"
grep -q '^body: |-$' ".pi-en/coordination/$requirement_path"
if grep -E '^(current|events|messages):' ".pi-en/coordination/$requirement_path" >/dev/null; then
  printf 'new requirement item should not contain embedded history\n' >&2
  exit 1
fi
cp ".pi-en/coordination/$requirement_path" "$tmp/requirement.clean.yaml"
printf 'current:\n  event: evt-0001\n  message: msg-0001\n' \
  >>".pi-en/coordination/$requirement_path"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for requirement with embedded history\n' >&2
  exit 1
fi
cp "$tmp/requirement.clean.yaml" ".pi-en/coordination/$requirement_path"
cp ".pi-en/coordination/$requirement_path" "$tmp/requirement.key.clean.yaml"
sed -i "s/^requirement_key: .*/requirement_key: $requirement_id/" \
  ".pi-en/coordination/$requirement_path"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for generated-ID-style requirement_key\n' >&2
  exit 1
fi
cp "$tmp/requirement.key.clean.yaml" ".pi-en/coordination/$requirement_path"

if pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type quality \
  --testable no \
  --testability-note "Missing requirement key check." \
  "Lint missing requirement key" >/dev/null 2>"$tmp/missing-requirement-key.err"; then
  printf 'expected requirement creation without --requirement-key to fail\n' >&2
  exit 1
fi
grep -q -- '--requirement-key is required for requirement items' \
  "$tmp/missing-requirement-key.err"

todo_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type todos \
  --testable no \
  --testability-note "Lint covers TODO single-body records." \
  "Lint TODO item" | tail -n 1)"
todo_id="$(grep '^id: ' ".pi-en/coordination/$todo_path" | sed 's/^id: //')"
case "$todo_path" in
  todos/"$todo_id".yaml) ;;
  *) printf 'unexpected todo path: %s\n' "$todo_path" >&2; exit 1 ;;
esac
grep -q '^id: PIEN-TODO-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-en/coordination/$todo_path"
grep -q '^type: todo$' ".pi-en/coordination/$todo_path"
grep -q '^body: |-$' ".pi-en/coordination/$todo_path"
if grep -E '^(current|events|messages):' ".pi-en/coordination/$todo_path" >/dev/null; then
  printf 'new todo item should not contain embedded history\n' >&2
  exit 1
fi
cp ".pi-en/coordination/$todo_path" "$tmp/todo.clean.yaml"
printf 'events:\n  - id: evt-0001\n' >>".pi-en/coordination/$todo_path"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for todo with embedded history\n' >&2
  exit 1
fi
cp "$tmp/todo.clean.yaml" ".pi-en/coordination/$todo_path"

quality_requirement_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type quality \
  --requirement-key QRQ-001 \
  --testable no \
  --testability-note "Reviewed as a quality requirement." \
  "Lint quality requirement item" | tail -n 1)"
imported_requirement_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type quality \
  --requirement-key QRQ-002 \
  --testable no \
  --testability-note "Imported from REQUIREMENTS.md; reviewed as policy." \
  "Lint imported quality requirement" | tail -n 1)"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for imported requirement without source_refs\n' >&2
  exit 1
fi
printf 'source_refs:\n  - "REQUIREMENTS.md#lint-imported-quality-requirement"\n' \
  >>".pi-en/coordination/$imported_requirement_path"
imported_note_requirement_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type functional-requirement \
  --requirement-key FRQ-002 \
  --testable no \
  --testability-note "Imported requirement is review-only for now." \
  "Lint imported note wording" | tail -n 1)"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for imported requirement note without source_refs\n' >&2
  exit 1
fi
printf 'source_refs:\n  - "USE_CASES.md#lint-imported-note-wording"\n' \
  >>".pi-en/coordination/$imported_note_requirement_path"
constraint_requirement_path="$(pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type constraint \
  --requirement-key CRQ-001 \
  --testable no \
  --testability-note "Reviewed as a constraint requirement." \
  "Lint constraint requirement item" | tail -n 1)"
if pi-en-coord-new \
  --coord-dir .pi-en/coordination \
  --type requirement \
  --testable no \
  --testability-note "Legacy requirement compatibility check." \
  "Lint legacy requirement item" >/dev/null 2>"$tmp/legacy-requirement.err"; then
  printf 'expected generic requirement creation to fail\n' >&2
  exit 1
fi
grep -q 'generic requirement items have been removed' "$tmp/legacy-requirement.err"

grep -q '^id: PIEN-QRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-en/coordination/$quality_requirement_path"
grep -q '^id: PIEN-QRQ-[0-9]\{8\}-[0-9]\{6\}-[0-9]\{3\}$' \
  ".pi-en/coordination/$imported_requirement_path"
grep -q '^id: PIEN-CRQ-[0-9]\{8\}-[0-9]\{6\}-001$' \
  ".pi-en/coordination/$constraint_requirement_path"
cp ".pi-en/coordination/$constraint_requirement_path" "$tmp/constraint.clean.yaml"
sed -i 's/^requirement_key: .*/requirement_key: QRQ-001/' \
  ".pi-en/coordination/$constraint_requirement_path"
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for duplicate active requirement_key\n' >&2
  exit 1
fi
cp "$tmp/constraint.clean.yaml" ".pi-en/coordination/$constraint_requirement_path"

pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null

mkdir -p designs scripts
ln -sf "$repo_root/scripts/pi-en-coord-generate-requirements-coverage" \
  scripts/pi-en-coord-generate-requirements-coverage
requirement_key="$(grep '^requirement_key: ' ".pi-en/coordination/$requirement_path" | sed 's/^requirement_key: //')"
cat >designs/lint-coverage.md <<EOF_DESIGN
# Lint coverage

## Covers

| Requirement | Coordination item |
|-------------|-------------------|
| $requirement_key | $requirement_id |
EOF_DESIGN
pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null
sed -i "s/$requirement_id/PIEN-FRQ-20260614-000000-999/" designs/lint-coverage.md
if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for stale design Covers item ID\n' >&2
  exit 1
fi
sed -i "s/PIEN-FRQ-20260614-000000-999/$requirement_id/" designs/lint-coverage.md

cat >tests/items/issues/ORPHAN-ISS-20260607-204155-001.sh <<'EOF_TEST'
#!/usr/bin/env bash
set -euo pipefail
EOF_TEST
chmod +x tests/items/issues/ORPHAN-ISS-20260607-204155-001.sh

if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for orphan item-matched test\n' >&2
  exit 1
fi

rm tests/items/issues/ORPHAN-ISS-20260607-204155-001.sh
chmod -x "tests/items/issues/$item_id.sh"

if pi-en-coord-lint \
  --coord-dir .pi-en/coordination \
  --project-root . >/dev/null 2>&1; then
  printf 'expected lint to fail for non-executable item-matched test\n' >&2
  exit 1
fi
chmod +x "tests/items/issues/$item_id.sh"

cat >"$tmp/counting-lib.sh" <<EOF_LIB
. "$repo_root/scripts/pi-en-coord-lib.sh"
eval "\$(declare -f coord_item_find_files | sed '1s/coord_item_find_files/coord_item_find_files_real/')"
coord_item_find_files() {
  printf x >>"\$PI_EN_COORD_LINT_FIND_COUNT_FILE"
  coord_item_find_files_real "\$@"
}
EOF_LIB
: >"$tmp/find-count"
PI_EN_COORD_LIB="$tmp/counting-lib.sh" \
PI_EN_COORD_LINT_FIND_COUNT_FILE="$tmp/find-count" \
  pi-en-coord-lint \
    --coord-dir .pi-en/coordination \
    --project-root . >/dev/null
find_call_count="$(wc -c <"$tmp/find-count" | tr -d ' ')"
if [ "$find_call_count" != "1" ]; then
  printf 'expected lint to build one item index, saw %s item scans\n' \
    "$find_call_count" >&2
  exit 1
fi

cache_dir="$tmp/lint-cache"
PI_EN_COORD_LINT_CACHE_DIR="$cache_dir" \
PI_EN_COORD_LINT_CACHE_DEBUG=1 \
  pi-en-coord-lint \
    --coord-dir .pi-en/coordination \
    --project-root . >/dev/null 2>"$tmp/cache-warm.err"
grep -q 'cache: miss ' "$tmp/cache-warm.err"
PI_EN_COORD_LINT_CACHE_DIR="$cache_dir" \
PI_EN_COORD_LINT_CACHE_DEBUG=1 \
  pi-en-coord-lint \
    --coord-dir .pi-en/coordination \
    --project-root . >/dev/null 2>"$tmp/cache-hit.err"
grep -q 'cache: hit ' "$tmp/cache-hit.err"

cp ".pi-en/coordination/$item_path" "$tmp/cache-item.clean.yaml"
printf '# cache invalidation marker\n' >>".pi-en/coordination/$item_path"
PI_EN_COORD_LINT_CACHE_DIR="$cache_dir" \
PI_EN_COORD_LINT_CACHE_DEBUG=1 \
  pi-en-coord-lint \
    --coord-dir .pi-en/coordination \
    --project-root . >/dev/null 2>"$tmp/cache-item-change.err"
grep -q "cache: miss $item_path" "$tmp/cache-item-change.err"
cp "$tmp/cache-item.clean.yaml" ".pi-en/coordination/$item_path"

PI_EN_COORD_LINT_CACHE_DIR="$cache_dir" \
PI_EN_COORD_LINT_CACHE_DEBUG=1 \
PI_EN_COORD_LINT_VERSION_SALT=changed-linter-version \
  pi-en-coord-lint \
    --coord-dir .pi-en/coordination \
    --project-root . >/dev/null 2>"$tmp/cache-version-change.err"
grep -q 'cache: miss ' "$tmp/cache-version-change.err"

cache_entry="$(find "$cache_dir/items" -type f | sort | head -n 1)"
printf 'not valid shell syntax ***\n' >"$cache_entry"
PI_EN_COORD_LINT_CACHE_DIR="$cache_dir" \
PI_EN_COORD_LINT_CACHE_DEBUG=1 \
  pi-en-coord-lint \
    --coord-dir .pi-en/coordination \
    --project-root . >/dev/null 2>"$tmp/cache-corrupt.err"
grep -q 'cache: fallback corrupt ' "$tmp/cache-corrupt.err"

cached_duplicate_path=".pi-en/coordination/repos/pi-en/issues/open/${item_id}-duplicate.yaml"
cp ".pi-en/coordination/$item_path" "$cached_duplicate_path"
if PI_EN_COORD_LINT_CACHE_DIR="$cache_dir" \
   PI_EN_COORD_LINT_CACHE_DEBUG=1 \
     pi-en-coord-lint \
       --coord-dir .pi-en/coordination \
       --project-root . >/dev/null 2>"$tmp/cache-duplicate.err"; then
  printf 'expected cached lint to fail for duplicate item IDs\n' >&2
  exit 1
fi
grep -q 'duplicates item id' "$tmp/cache-duplicate.err"
grep -q 'cache: hit ' "$tmp/cache-duplicate.err"
rm "$cached_duplicate_path"

printf 'agent coordination lint tests passed\n'
