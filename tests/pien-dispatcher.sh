#!/usr/bin/env bash
set -euo pipefail

repo_root="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp_dir="$(mktemp -d)"
trap 'rm -rf "$tmp_dir"' EXIT

mkdir -p "$tmp_dir/support" "$tmp_dir/bin"
cp "$repo_root/scripts/pien" "$tmp_dir/support/pien"
chmod +x "$tmp_dir/support/pien"

make_stub_at() {
  local path="$1"
  local label="${2:-}"
  [ -n "$label" ] || label="$(basename "$path")"
  cat > "$path" <<STUB
#!/usr/bin/env bash
set -euo pipefail
{
  printf 'cmd=%s\\n' '$label'
  if [ "\${PIEN_TEST_LOG_CONTEXT:-0}" = "1" ]; then
    printf 'cwd=%s\\n' "\$PWD"
    printf 'PI_EN_COORD_DIR=%s\\n' "\${PI_EN_COORD_DIR:-}"
  fi
  for arg in "\$@"; do
    printf 'arg=%s\\n' "\$arg"
  done
} > "\$PIEN_TEST_LOG"
STUB
  chmod +x "$path"
}

make_stub() {
  local name="$1"
  make_stub_at "$tmp_dir/bin/$name"
}

make_stub_at "$tmp_dir/support/pi-en-update" pi-en-update-bundled

for name in \
  nix pi-en pi-en-shell pi-en-bwrap pi-en-behavior pi-en-bootstrap-coordination \
  pi-en-coord-init pi-en-coord-clone pi-en-coord-status pi-en-coord-list \
  pi-en-coord-cat pi-en-coord-new pi-en-coord-claim pi-en-coord-done \
  pi-en-coord-review pi-en-coord-verify pi-en-coord-close pi-en-coord-pull \
  pi-en-coord-push pi-en-coord-lint pi-en-coord-repo \
  pi-en-coord-upgrade-rules pi-en-coord-generate-requirements \
  pi-en-coord-generate-requirements-coverage pi-en-serial-roles \
  pi-en-install-non-nix pi-en-update pi-en-uninstall; do
  make_stub "$name"
done

run_case() {
  local expected="$1"
  shift
  : > "$tmp_dir/log"
  PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" "$@"
  actual="$(cat "$tmp_dir/log")"
  if [ "$actual" != "$expected" ]; then
    echo "pien dispatcher mismatch for args: $*" >&2
    echo "expected:" >&2
    printf '%s\n' "$expected" >&2
    echo "actual:" >&2
    printf '%s\n' "$actual" >&2
    exit 1
  fi
}

run_case $'cmd=pi-en'
run_case $'cmd=pi-en\narg=--first' -- --first
run_case $'cmd=pi-en\narg=--foo' run --foo
run_case $'cmd=pi-en\narg=--raw\narg=--\narg=run' raw -- run
run_case $'cmd=pi-en\narg=--raw\narg=--runtime\narg=host\narg=--flake\narg=.#agent\narg=--devshell=agent\narg=--\narg=run' raw --runtime host --flake .#agent --devshell=agent -- run
run_case $'cmd=pi-en-shell\narg=--runtime\narg=nix' shell --runtime nix
run_case $'cmd=pi-en-bwrap\narg=--continue' sandbox --continue
run_case $'cmd=pi-en-bwrap\narg=--shell\narg=--\narg=-l' sandbox shell -- -l
run_case $'cmd=pi-en-behavior\narg=lint\narg=--project-root\narg=/tmp/project' behavior lint --project-root /tmp/project
run_case $'cmd=pi-en-bootstrap-coordination\narg=--help' coord bootstrap --help
run_case $'cmd=pi-en-coord-status\narg=--repo-id\narg=pi-en' coord status --repo-id pi-en
run_case $'cmd=pi-en-coord-cat\narg=ITEM-1' coord show ITEM-1
run_case $'cmd=pi-en-coord-upgrade-rules\narg=--check' coord rules upgrade --check
run_case $'cmd=pi-en-coord-generate-requirements\narg=--repo-id\narg=pi-en' coord requirements generate --repo-id pi-en
run_case $'cmd=pi-en-coord-generate-requirements-coverage' coord requirements coverage
run_case $'cmd=pi-en-serial-roles\narg=--role\narg=developer' roles serial --role developer
run_case $'cmd=pi-en-install-non-nix\narg=--prefix\narg=/tmp/pien' install --prefix /tmp/pien
run_case $'cmd=pi-en-update\narg=--prefix\narg=/tmp/pien' update --prefix /tmp/pien
run_case $'cmd=pi-en-uninstall\narg=--prefix\narg=/tmp/pien' uninstall --prefix /tmp/pien
make_stub_at "$tmp_dir/bin/pi-en-update" pi-en-update-nix-shell
run_case $'cmd=pi-en-update-nix-shell\narg=--ref\narg=main' update --ref main
mkdir -p "$tmp_dir/wrapper-runtime"
make_stub_at "$tmp_dir/wrapper-runtime/pi-en-update" pi-en-update-wrapper-runtime
cat > "$tmp_dir/pien-wrapper" <<WRAPPER
#!/usr/bin/env bash
set -euo pipefail
if [ "\${PI_EN_NIX_SHELL:-0}" = "1" ]; then
  export PATH="\${PATH:-}:$tmp_dir/wrapper-runtime"
else
  export PATH="$tmp_dir/wrapper-runtime:\${PATH:-}"
fi
exec -a pien bash "$tmp_dir/support/pien" "\$@"
WRAPPER
chmod +x "$tmp_dir/pien-wrapper"
: > "$tmp_dir/log"
PI_EN_NIX_SHELL=1 PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/pien-wrapper" update --ref main
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en-update-nix-shell\narg=--ref\narg=main') ;;
  *) echo "pien wrapper did not preserve Nix-shell pi-en-update precedence" >&2; cat "$tmp_dir/log" >&2; exit 1 ;;
esac
: > "$tmp_dir/log"
PIEN_TEST_LOG="$tmp_dir/log" PATH="$PATH" "$tmp_dir/pien-wrapper" update --prefix /tmp/pien
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en-update-wrapper-runtime\narg=--prefix\narg=/tmp/pien') ;;
  *) echo "pien wrapper did not preserve packaged pi-en-update outside Nix shell" >&2; cat "$tmp_dir/log" >&2; exit 1 ;;
esac
make_stub pi-en-update
rm "$tmp_dir/bin/pi-en-update"
run_case $'cmd=pi-en-install-non-nix\narg=--url\narg=https://example.invalid/pi-en.git\narg=--ref\narg=main\narg=--prefix\narg=/tmp/pien' update --url https://example.invalid/pi-en.git --ref main --prefix /tmp/pien
rm "$tmp_dir/bin/pi-en-uninstall"
run_case $'cmd=pi-en-install-non-nix\narg=--uninstall\narg=--prefix\narg=/tmp/pien' uninstall --prefix /tmp/pien

version_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" version)"
case "$version_output" in
  'pien '*) ;;
  *) echo "pien version did not print version output" >&2; exit 1 ;;
esac

diagnostics_output="$(PI_EN_INSIDE_SANDBOX=1 PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" diagnostics)"
case "$diagnostics_output" in
  *'PI_EN_INSIDE_SANDBOX=1'*'coordination_helpers=available'* ) ;;
  *) echo "pien diagnostics did not report sandbox/runtime state" >&2; exit 1 ;;
esac

run_sandbox_outer_only_case() {
  local args=("$@")
  : > "$tmp_dir/log"
  if PI_EN_INSIDE_SANDBOX=1 PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" "${args[@]}" >"$tmp_dir/out" 2>"$tmp_dir/err"; then
    echo "in-sandbox outer-only command unexpectedly succeeded: pien ${args[*]}" >&2
    exit 1
  fi
  if [ -s "$tmp_dir/log" ]; then
    echo "in-sandbox outer-only command dispatched unexpectedly: pien ${args[*]}" >&2
    cat "$tmp_dir/log" >&2
    exit 1
  fi
  if ! grep -Fq 'must be run from the outer terminal' "$tmp_dir/err"; then
    echo "in-sandbox outer-only command missed actionable diagnostic: pien ${args[*]}" >&2
    cat "$tmp_dir/err" >&2
    exit 1
  fi
}

run_sandbox_outer_only_case
run_sandbox_outer_only_case run --foo
run_sandbox_outer_only_case --runtime nix
run_sandbox_outer_only_case shell -- -lc true
run_sandbox_outer_only_case sandbox --help
run_sandbox_outer_only_case roles serial --role developer
run_sandbox_outer_only_case install --prefix /tmp/pien
run_sandbox_outer_only_case update --help
run_sandbox_outer_only_case update --prefix /tmp/pien
run_sandbox_outer_only_case uninstall --prefix /tmp/pien

run_sandbox_safe_no_dispatch_case() {
  local args=("$@")
  : > "$tmp_dir/log"
  if ! PI_EN_INSIDE_SANDBOX=1 PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" "${args[@]}" >"$tmp_dir/out" 2>"$tmp_dir/err"; then
    echo "in-sandbox safe command unexpectedly failed: pien ${args[*]}" >&2
    cat "$tmp_dir/err" >&2
    exit 1
  fi
  if [ -s "$tmp_dir/log" ]; then
    echo "in-sandbox safe command dispatched unexpectedly: pien ${args[*]}" >&2
    cat "$tmp_dir/log" >&2
    exit 1
  fi
}

run_sandbox_context_case() {
  local expected="$1"
  shift
  : > "$tmp_dir/log"
  mkdir -p "$tmp_dir/project" "$tmp_dir/coord"
  (
    cd "$tmp_dir/project"
    PI_EN_INSIDE_SANDBOX=1 \
      PI_EN_COORD_DIR="$tmp_dir/coord" \
      PIEN_TEST_LOG_CONTEXT=1 \
      PIEN_TEST_LOG="$tmp_dir/log" \
      PATH="$tmp_dir/bin:$PATH" \
      "$tmp_dir/support/pien" "$@"
  )
  actual="$(cat "$tmp_dir/log")"
  if [ "$actual" != "$expected" ]; then
    echo "in-sandbox context dispatch mismatch for args: $*" >&2
    echo "expected:" >&2
    printf '%s\n' "$expected" >&2
    echo "actual:" >&2
    printf '%s\n' "$actual" >&2
    exit 1
  fi
}

run_sandbox_safe_no_dispatch_case help
run_sandbox_safe_no_dispatch_case help coord
run_sandbox_safe_no_dispatch_case recipe flake-agent-shell --help
(
  export PI_EN_INSIDE_SANDBOX=1
  run_case $'cmd=pi-en-coord-status\narg=--repo-id\narg=pi-en' coord status --repo-id pi-en
  run_case $'cmd=pi-en-serial-roles\narg=--help' roles serial --help
)
run_sandbox_context_case $'cmd=pi-en-coord-status\ncwd='"$tmp_dir"$'/project\nPI_EN_COORD_DIR='"$tmp_dir"$'/coord' coord status
run_sandbox_context_case $'cmd=pi-en-bootstrap-coordination\ncwd='"$tmp_dir"$'/project\nPI_EN_COORD_DIR='"$tmp_dir"$'/coord\narg=--print-only' coord bootstrap --print-only

completion_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" completion bash)"
case "$completion_output" in
  *'complete -F _pien pien'*) ;;
  *) echo "pien completion bash did not print sourceable completion" >&2; exit 1 ;;
esac
bash -n <(printf '%s\n' "$completion_output")

completion_env="$tmp_dir/completion-env.sh"
{
  printf '%s\n' "$completion_output"
  cat <<'COMPTEST'
assert_completion() {
  local expected="$1"
  shift
  COMP_WORDS=(pien "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _pien
  case " ${COMPREPLY[*]} " in
    *" $expected "*) ;;
    *) echo "missing completion '$expected' for: pien $* (got: ${COMPREPLY[*]})" >&2; exit 1 ;;
  esac
}
assert_no_completion() {
  local unexpected="$1"
  shift
  COMP_WORDS=(pien "$@")
  COMP_CWORD=$((${#COMP_WORDS[@]} - 1))
  _pien
  case " ${COMPREPLY[*]} " in
    *" $unexpected "*) echo "unexpected completion '$unexpected' for: pien $* (got: ${COMPREPLY[*]})" >&2; exit 1 ;;
  esac
}
assert_completion coord c
assert_completion rules coord r
assert_completion upgrade coord rules u
assert_completion generate coord requirements g
assert_completion coverage coord requirements c
assert_completion serial roles s
assert_completion recipe r
assert_completion flake-agent-shell recipe f
assert_completion update u
assert_completion --runtime --
assert_completion --runtime run --
assert_completion --runtime shell --
assert_no_completion --runtime raw --
assert_no_completion --flake raw --
assert_no_completion --runtime --raw --
assert_no_completion --runtime --runtime host --raw --
assert_no_completion host --runtime host --raw --runtime h
assert_completion host run --runtime h
assert_completion --url update --
assert_completion --ref update --
assert_completion --prefix update --
assert_completion --artifact-url update --
assert_completion --check-deps update --
assert_completion --repo-id coord status --
assert_completion --coordination-dir coord requirements generate --
assert_completion --coord-dir coord requirements generate --
assert_no_completion --designs-dir coord requirements generate --
assert_completion --designs-dir coord requirements coverage --
assert_no_completion --runtime coord --
assert_no_completion --runtime sandbox --
assert_no_completion --runtime recipe --
assert_no_completion host coord --runtime h
COMPTEST
} > "$completion_env"
bash "$completion_env"

help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help)"
for snippet in \
  'pien coord <command>' \
  'pien recipe flake-agent-shell' \
  '--raw --' \
  'pien raw --' \
  '--runtime host|nix|auto' \
  '--flake REF' \
  '--devshell NAME' \
  'PI_EN_RUNTIME' \
  'PI_EN_FLAKE' \
  'PI_EN_NIX_DEVSHELL' \
  'CLI options win' \
  'pien raw' \
  'pien diagnostics' \
  'pien update [args...]' \
  'pien version'; do
  if ! grep -Fq -- "$snippet" <<<"$help_output"; then
    echo "pien help missed command, recipe, or runtime launcher guidance: $snippet" >&2
    exit 1
  fi
done

coord_help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help coord)"
case "$coord_help_output" in
  *'rules upgrade'*'pi-en-coord-upgrade-rules'*'requirements generate'*'pi-en-coord-generate-requirements'* ) ;;
  *) echo "pien help coord did not list nested command equivalents" >&2; exit 1 ;;
esac

coord_requirements_help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help coord requirements)"
case "$coord_requirements_help_output" in
  *'generate  Render active coordination requirement items'*'coverage  Generate requirements coverage report'* ) ;;
  *) echo "pien help coord requirements did not describe source semantics" >&2; exit 1 ;;
esac
if grep -Fq 'Generate requirements from designs' <<<"$coord_requirements_help_output"; then
  echo "pien help coord requirements still claims generation reads designs" >&2
  exit 1
fi

PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help coord status
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en-coord-status\narg=--help') ;;
  *) echo "pien help coord status did not dispatch to leaf help" >&2; exit 1 ;;
esac

PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help coord requirements generate
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en-coord-generate-requirements\narg=--help') ;;
  *) echo "pien help coord requirements generate did not dispatch to leaf help" >&2; exit 1 ;;
esac

make_stub pi-en-update
PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help update
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en-update\narg=--help') ;;
  *) echo "pien help update did not delegate to pi-en-update help" >&2; exit 1 ;;
esac
rm "$tmp_dir/bin/pi-en-update"
update_help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help update)"
case "$update_help_output" in
  *'pien update - run the context-specific pi-en updater'*'Usage inside pi-en.lib.mkPiShell:'*'--url URL'*'--ref REF'*'--artifact-url URL'* ) ;;
  *) echo "pien help update fallback did not describe Nix and non-Nix source options" >&2; exit 1 ;;
esac
make_stub pi-en-update

PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help run
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en\narg=--help') ;;
  *) echo "pien help run did not delegate to pi-en help" >&2; exit 1 ;;
esac
PIEN_TEST_LOG="$tmp_dir/log" PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help shell
case "$(cat "$tmp_dir/log")" in
  $'cmd=pi-en-shell\narg=--help') ;;
  *) echo "pien help shell did not delegate to pi-en-shell help" >&2; exit 1 ;;
esac

recipe_help_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" help recipe)"
case "$recipe_help_output" in
  *'flake-agent-shell'*'Recipes only print guidance'* ) ;;
  *) echo "pien help recipe did not describe recipe command" >&2; exit 1 ;;
esac

recipe_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" recipe flake-agent-shell)"
for snippet in \
  'pi-en.url = "git+file:///home/me/src/pi-en";' \
  'outputs = { self, nixpkgs, flake-utils, pi-en, ... }:' \
  'keep that expression on' \
  'devShells.${system} = {' \
  '} // {' \
  'agent = pi-en.lib.mkPiShell {' \
  'agent = existingDevShells.default;' \
  'includeCoordinationHelpers = false;' \
  'extraPackages = with pkgs; [' \
  'pi-en-update --url https://github.com/u2up/pi-en.git --ref abc123@main' \
  'Review and commit any' \
  'does not read, edit, or write project files'; do
  if ! grep -Fq "$snippet" <<< "$recipe_output"; then
    echo "pien recipe flake-agent-shell missed stable recipe snippet: $snippet" >&2
    exit 1
  fi
done
if grep -Fq 'self.devShells.${system}' <<< "$recipe_output"; then
  echo "pien recipe flake-agent-shell must not recurse through self.devShells" >&2
  exit 1
fi

recipe_help_alias_output="$(PATH="$tmp_dir/bin:$PATH" "$tmp_dir/support/pien" recipe flake-agent-shell --help)"
case "$recipe_help_alias_output" in
  *'pien recipe flake-agent-shell'*'nix develop .#agent'* ) ;;
  *) echo "pien recipe flake-agent-shell --help did not print recipe" >&2; exit 1 ;;
esac

printf 'pien dispatcher tests passed\n'
