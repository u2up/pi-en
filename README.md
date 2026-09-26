# Pi-en

`pi-en` runs Pi Coding Agent safely against one selected project, with optional
guaranteed-reproducible tooling and optional managed agentic coordination.

It is built around three layers:

1. **Sandboxed project isolation with Bubblewrap**

   Every run is confined to a mandatory Bubblewrap sandbox where the selected
   project is mounted read-write at `/workspace`. The agent does not receive
   wholesale access to your home directory, credentials, shell configuration,
   Docker socket, or unrelated projects.

   **Problem addressed:** reducing the blast radius of agentic coding tools
   that can inspect files, run commands, and edit code.

2. **Optional guaranteed-reproducible runtime with Nix**

   When selected, the Nix runtime provides pinned tools and dependencies so
   teams can run the agent with the same command-line environment across
   machines. Direct host-runtime mode remains available for convenience, but is
   intentionally unpinned.

   **Problem addressed:** avoiding “works on my machine” drift in agent runs,
   checks, and development tooling.

3. **Optional coordination repository for managed agentic development**

   `pi-en` includes Git-backed coordination helpers and role workflows for
   teams that want structured multi-agent or multi-role development. This acts
   as a reference implementation of the
   [coordination repository pattern](https://github.com/u2up/coordination-repository-pattern):
   requirements, decisions, ownership, handoffs, and validation can be tracked
   outside the working project.

   **Problem addressed:** preventing ad-hoc agent work from becoming hard to
   audit, reproduce, assign, or hand off.

In short:

```text
Without Pi-en:
  Pi -> host environment
     -> home directory, SSH keys, cloud credentials, Docker socket,
        shell config, unrelated projects

With Pi-en:
  Pi -> Bubblewrap sandbox
     -> selected repo at /workspace, isolated HOME,
        selected auth/config only
```

Most users start with one of two workflows:

1. **Direct use**: run this checkout's `pi-en` launcher from any project.
2. **Flake integration**: add `pi-en` as an input to a project's own flake so
   the team shares the same pinned runtime.

## 60-second example

Assuming Linux, Git, and a configured host `pi` command are already available,
try Pi-en on an existing public repository:

```bash
git clone https://github.com/spog/evm.git
cd evm

git clone https://github.com/u2up/pi-en.git ~/src/pi-en
~/src/pi-en/pien \
  "Summarize this repository and suggest safe first checks."
```

That direct checkout command starts in the default **host runtime** mode: Pi
runs inside the Bubblewrap sandbox, but runtime tools are unpinned host tools.
You can make the selection explicit or opt in to the reproducible Nix runtime:

```bash
~/src/pi-en/pien --runtime host "Inspect this repo with host tools."
~/src/pi-en/pien --runtime nix "Inspect this repo with pinned Nix tools."
```

You can also use the Nix flake app directly when you want the pinned runtime
without cloning first:

```bash
nix run github:u2up/pi-en -- \
  "Summarize this repository and suggest safe first checks."
```

All of these run Pi against the cloned repository with that repository mounted
read-write at `/workspace` inside the Bubblewrap sandbox. They are intended for
inspection. If you ask Pi to build or test a project, supply the project's
build tools with the host runtime policy or declare them in a devshell for the
Nix runtime as described below.

### Optional: enable local coordination for the example

For tracked role-based agent work, enter the Pi-en shell:

```bash
cd evm
nix develop github:u2up/pi-en
```

Then bootstrap a local coordination repository for the checkout and run Pi:

```bash
pien coord bootstrap \
  --project-root "$PWD" \
  --project evm \
  --project-key EVM \
  --repo-id evm
pien coord status
pien "Inspect this repository and review its state."
```

This creates local coordination state under `.pi-en/` for agent issue, TODO,
and synchronization tracking. `.pi-en/` is operational state and should
normally stay untracked.

Implementation repositories may commit a small root-level attachment hint named
`.pi-en-coordination.yaml` so helpers can find their shared coordination domain:

```yaml
version: 1
coordination_domain: my-product
coordination_remote: git@example.com:org/my-product-coordination.git
repo_id: backend-api
```

The file is read from the implementation repository root, not from inside the
coordination checkout. Explicit command options and environment variables still
win: repo id resolution is `--repo-id`, `PI_EN_COORD_REPO_ID`,
`.pi-en-coordination.yaml`, then Git remote-name inference; coordination remote
resolution is explicit `--remote`, `PI_EN_COORD_REMOTE`, then
`.pi-en-coordination.yaml`. No legacy implementation attachment filename is
read as a fallback. The coordination repository registry remains authoritative
for canonical and active repo ids when `repositories.yaml` or the
`repos/<repo_id>/REPO.md` registry is present. For the full model, see
[One coordination domain across multiple implementation repos](#one-coordination-domain-across-multiple-implementation-repos).

Domain-wide generated files that are committed to implementation repositories
are declared in the owning repo's coordination manifest, not in the per-repo
attachment hint:

```yaml
# repos/backend-api/REPO.md
---
repo_id: backend-api
status: active
domain_generated_files:
  - REQUIREMENTS.md
  - REQUIREMENTS_COVERAGE.md
---
```

The `repo_id` must be canonical and active, and paths are relative to that
implementation repository root. Agents should regenerate and commit those paths
only in implementation repos whose `REPO.md` lists them. More than one active
repo may list the same domain-wide generated path when the domain intentionally
keeps committed copies in several implementation repositories.

`pi-en-coord-lint` validates repo manifests and all repo-scoped issue structure
under `repos/<repo_id>/issues/<status>`. Item-matched issue tests are expected
only for the current implementation repo resolved from `--repo-id`,
`PI_EN_COORD_REPO_ID`, `.pi-en-coordination.yaml`, or Git remote registry data.
`--all-repos` keeps structural validation across every registered repo but does
not require tests from unavailable implementation checkouts unless `--repo-id`
selects that repo explicitly. Fresh `pi-en-coord-init` scaffolds the initial
implementation namespace at
`repos/<repo_id>/issues/{open,blocked,done,closed}` and writes the sole registry
record at `repos/<repo_id>/REPO.md`; no root `REPOS.md` index is generated.
Existing `REPOS.md` files from older coordination repositories are ignored by
tooling and may be deleted manually. Existing root-layout domains can move
tracked root issue files with `pi-en-coord-repo migrate-root-issues <repo_id>`;
the command creates or validates the target repo manifest, uses `git mv` for
tracked files, and refuses target overwrites or duplicate issue ids. Root
`issues/` paths are migration-compatible by default with warnings; set
`PI_EN_COORD_LINT_ROOT_ISSUES=fail` to reject them.

Coordination lint can optionally reuse item-local parse facts from an
implementation-local content-addressed cache. Set
`PI_EN_COORD_LINT_CACHE_DIR` to a writable directory outside coordination item
YAML to enable it. Cache keys include the lint script hash (plus optional
`PI_EN_COORD_LINT_VERSION_SALT`), the item path and content hash, repo manifest
content hashes, and item-test content hashes. Unset the variable or set
`PI_EN_COORD_LINT_CACHE=0` for a full uncached run. Missing, stale, corrupt, or
incompatible entries are recomputed safely, and cached facts never bypass global
checks such as duplicate IDs, duplicate active requirement keys, orphan tests,
repo manifest consistency, selected-repo test scope, or design coverage.
`PI_EN_COORD_LINT_CACHE_DEBUG=1` prints cache hit/miss/fallback diagnostics.

### Simple coordination workflow

A typical human-and-agent workflow with a coordination repository is:

1. **Bootstrap or clone coordination state** for the project. Automatic Pi-en
   workflows use the project-local working clone at `.pi-en/coordination`; for
   team use, keep that working clone local and point it at a shared Git remote.
2. **Capture project knowledge there**: requirements, decisions, notes, issues,
   TODOs, ownership, and validation expectations that should survive beyond one
   chat session.
3. **Pick or create a work item** before starting implementation. Pull the
   coordination repo, inspect open items, and claim or assign one when work
   begins.
4. **Run Pi with the project and coordination state mounted**. The agent can use
   the coordination repository as shared memory and should record meaningful
   events, decisions, handoffs, and validation results there.
5. **Review two diffs separately**: project-source changes in the project repo,
   and coordination changes in the coordination repo. Commit/push each to its
   own repository when accepted.
6. **Repeat from coordination state**, not from chat history. The next human or
   agent pulls the coordination repo and sees the current requirements,
   decisions, item status, and handoff notes.

In short, the project repository remains the source of product code, while the
coordination repository is the source of shared process memory and work state.
For a serial automation loop that applies this pattern across developer,
reviewer, and tester roles, see
[Serial role automation](#serial-role-automation).

## 1. Host prerequisites

Install or configure these on the host before using this repository.

### Required host dependencies

- **Linux** with unprivileged user namespaces/Bubblewrap support.
- **`pi-coding-agent`** installed on the host and available as `pi` on `PATH`.
  `pi-en` does not pin or install Pi itself.
- **Model credentials** for Pi, either in Pi's normal auth files under
  `~/.pi/agent` or as provider environment variables such as
  `ANTHROPIC_API_KEY` / `OPENAI_API_KEY`.
- **Git** or another way to fetch this repository.

### Optional Nix dependency

Install **Nix** with flakes enabled for Nix runtime workflows (`--runtime nix`,
`nix run`, `nix develop`, profile installs, or project flake integration). You
can either enable the `nix-command` and `flakes` experimental features globally
or pass them when running Nix. Direct checkout use defaults to the host runtime
and does not require Nix.

Quick checks:

```bash
pi --version
# Needed only for Nix runtime workflows:
nix --version
```

If Pi is not installed yet, install it using the upstream package. A common npm
installation is:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
pi --version
```

Node/npm are needed on the host for this Pi installation or upgrade step and
for host-runtime launches that use the npm-installed Pi launcher. In host
runtime mode, `node` for an npm-installed Pi launcher must resolve under
`/usr/local/bin`, `/usr/bin`, or `/bin`; `PI_EN_BWRAP_HOST_EXTRA_PATH` does not
admit that launcher interpreter. The Pi-en Nix shell provides Node and the
other runtime tools when you select the Nix runtime.

### Provided by Pi-en

When you enter the devshell, select `--runtime nix`, run `nix run`, or consume
Pi-en as a flake, Nix supplies the pinned runtime tools used by the wrappers:

```text
bash bubblewrap cacert coreutils fd findutils gawk git gnugrep gnused
gnutar gzip jq nodejs ripgrep which
```

The development shell also includes review and patch utilities for contributor
workflows:

```text
diff diff3 patch
```

Verify the devshell tools with:

```bash
nix develop --command bash -lc 'command -v diff diff3 patch'
```

You normally do not need to install these separately for Pi-en itself.

## 2. Install Pi-en

Clone this repository for direct host-runtime use:

```bash
git clone https://github.com/u2up/pi-en.git ~/src/pi-en
```

Enter the devshell when you want Nix-pinned Pi-en commands and helper tools:

```bash
cd ~/src/pi-en
nix develop
```

If flakes are not enabled globally, use:

```bash
nix --extra-experimental-features 'nix-command flakes' develop
```

Verify the commands are available:

```bash
pien help
pien completion bash
pien sandbox --help
```

### Non-Nix installation

Use the non-Nix installer when you want Pi-en commands copied into a normal
prefix without entering Nix during installation. The installer copies commands
to `$PREFIX/bin`, support files to `$PREFIX/share/pi-en`, and writes wrappers
that resolve coordination support, coordination templates, and the role-manager
package from that installed prefix.

The installer does not install or pin runtime tools. Host tools such as Bash,
Bubblewrap, Git, jq, Node, the `pi` launcher, and standard POSIX text/file
utilities must already be available for host-runtime use.

- **Install directly from GitHub.** Prefer tagged releases or release artifact
  URLs for stable installs:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/u2up/pi-en/v0.1.0/scripts/pi-en-install-non-nix \
    | bash -s -- --ref v0.1.0 --prefix "$HOME/.local" --check-deps
  export PATH="$HOME/.local/bin:$PATH"
  pien --runtime host --help
  ```

  For latest/development testing, use the mutable `main` branch instead:

  ```bash
  curl -fsSL https://raw.githubusercontent.com/u2up/pi-en/main/scripts/pi-en-install-non-nix \
    | bash -s -- --ref main --prefix "$HOME/.local" --check-deps
  ```

  `--ref main` is mutable and non-reproducible; treat it as a development/latest
  channel, not the recommended stable install path. Use `--repo OWNER/REPO` for
  forks, or `--artifact-url URL` to install from a specific archive URL.

- **Install from a local Git checkout or unpacked archive.** Run the installer
  from the checkout/archive root:

  ```bash
  ./scripts/pi-en-install-non-nix --prefix "$HOME/.local" --check-deps
  export PATH="$HOME/.local/bin:$PATH"
  pien --runtime host --help
  ```

  Release artifacts can contain only the Pi-en payload directories
  (`scripts/`, `role-manager/`, and `pi-skill-templates/`); end users do not
  need a full Git clone for installation.

- **Install from a Git URL and update later.** `--url` accepts local
  repositories and arbitrary Git remotes, while `--ref` accepts branches, tags,
  or `COMMIT@BRANCH` pins:

  ```bash
  pi-en-install-non-nix \
    --url https://github.com/u2up/pi-en.git \
    --ref v0.1.0 \
    --prefix "$HOME/.local"
  pi-en-update
  # or through the canonical dispatcher:
  pien update
  ```

  Installed origin metadata records the requested URL/ref and resolved commit so
  `pi-en-update` and `pien update` can reuse them unless you pass replacement
  source options such as `--url`, `--ref`, `--repo`, or `--artifact-url`. Treat
  arbitrary Git installs as trusted-code installs; mutable branches are useful
  for latest/development workflows but are not reproducible.

- **Upgrade or repair an existing local installation.** Re-run the same
  installer command with the same prefix, or run `pien update --prefix PREFIX`
  from the outer terminal. From a direct checkout where `pi-en-update` is not
  installed, pass explicit source options, for example `pien update --url
  https://github.com/u2up/pi-en.git --ref main --prefix "$HOME/.local"`. To
  remove installed files later, use the manifest-backed uninstall command:

  ```bash
  pi-en-uninstall
  # or, without PATH setup:
  "$HOME/.local/bin/pi-en-uninstall"
  ```

Installed non-Nix commands default to host-runtime startup. If you select
`--runtime nix` from a project checkout, the installed launcher enters that
project's `flake.nix` with `nix develop` before starting Pi through the Nix
runtime. Run from the target project root (or a Git subdirectory) so Pi-en can
find the project flake, or pass `--flake REF` / set `PI_EN_FLAKE=REF` to select
a flake explicitly.

Inside `nix develop` the prompt is prefixed with `(nix-dev)`. The shell exports
`PI_EN_ROLE_MANAGER_PACKAGE` to the Nix-built role-manager package path and
prints a short reminder unless `PI_EN_QUIET` is set.

### Optional profile installation

For the smallest profile that can launch Pi in the sandbox, install the core
runtime package. It puts `pien`, `pi-en`, `pi-en-shell`, `pi-en-bwrap`, and
the runtime tools on `PATH` without the Git-backed coordination helper
commands:

```bash
nix profile install ~/src/pi-en#pi-core
```

If you also use coordination helpers, either install them separately or install
the combined runtime bundle:

```bash
nix profile install ~/src/pi-en#pi-en-coordination
# or, for the combined core plus coordination bundle:
nix profile install ~/src/pi-en#pi-runtime
```

`pi-runtime` continues to include the core runtime plus coordination helpers.
None of these packages install `pi-coding-agent`; the host `pi` command must
already exist.

A profile install gives you Nix-built Pi-en commands and Pi-en's pinned core
runtime on `PATH`. Selecting `--runtime nix` from a target project enters that
project's `flake.nix` with `nix develop`, so project-specific devshell tools are
available before Pi starts. Without `--runtime nix`, profile commands keep using
the profile-provided Pi-en runtime on `PATH`.

## 3. Use Pi-en directly from any project

Use direct mode for local, ad hoc, or internal runs where selecting a Pi-en
checkout is enough and the target project does not need to pin Pi-en in its
own `flake.lock`. Direct checkout startup defaults to **host runtime** mode:
`pi-en` still enters the Bubblewrap sandbox, but command-line tools are the
unpinned host tools admitted by Pi-en's conservative mount policy.

From the target project directory, run this checkout's launcher:

```bash
cd /path/to/project
~/src/pi-en/pien
~/src/pi-en/pien "Inspect this repo"
~/src/pi-en/pien raw -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
```

If you installed Pi-en into a prefix with the non-Nix installer, or installed
`#pi-core` or `#pi-runtime` into a Nix profile, you can run the shorter command:

```bash
cd /path/to/project
pien
pien "Inspect this repo"
```

The checkout launcher defaults to host runtime mode. It preserves the current
project as the detected project root; inside the sandbox that project is
mounted read-write at `/workspace`. The Pi-en checkout is only the source of
launcher code and runtime policy.

Select a runtime explicitly with `--runtime` or `PI_EN_RUNTIME`:

```bash
~/src/pi-en/pien --runtime host "Inspect this repo"
~/src/pi-en/pien --runtime nix "Inspect this repo with pinned tools"
PI_EN_RUNTIME=nix ~/src/pi-en/pien
```

Use `--runtime host` for direct startup with unpinned host tools. Use
`--runtime nix`, `nix run`, `nix develop`, profile packages, or project flake
integration when you need the reproducible/pinned Nix runtime. Installed and
profile launchers with `--runtime nix` require the detected target project to
have `flake.nix` unless you pass `--flake REF` or set `PI_EN_FLAKE=REF`. When
a project flake is selected, Nix runtime startup prefers `.#agent` when that
shell exists, falls back to the default shell when `.#agent` is absent, and
fails visibly if an existing or explicitly selected `.#agent` cannot evaluate
or build. That visible failure prevents silently running agents in the wrong or
under-provisioned shell. `--runtime auto` keeps compatibility with environments
that already provide Pi-en commands and falls back to the Nix runtime when
needed.

Use `pien shell` when you want an interactive shell inside the same selected
runtime and Bubblewrap sandbox instead of starting the Pi agent:

```bash
~/src/pi-en/pien shell --runtime host
~/src/pi-en/pien shell --runtime nix
```

`pien shell` owns runtime selection just like `pien`; the lower-level
sandbox payload switch remains `pien sandbox shell`. Normal `pien`
invocations apply the default startup policy and Pi arguments continue to pass
through as shown above.

Use `pien raw --` when you want to pass arguments directly to Pi through the
sandbox layer instead of using the default startup policy:

```bash
pien raw -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
```

Select another Pi-en flake reference with either form:

```bash
PI_EN_FLAKE=github:u2up/pi-en ~/src/pi-en/pien
~/src/pi-en/pien --flake github:u2up/pi-en
```

## 4. Use Pi-en through a project flake

Use project-integrated mode when a repository should:

- pin Pi-en for the team in the repository's `flake.lock`;
- share the same Pi-en revision across machines and CI jobs;
- combine Pi-en with project-specific Nix dependencies; or
- expose one committed `nix develop` entrypoint for both project tools and Pi.

After integration, the usual workflow is:

```bash
cd /path/to/project
nix develop
pien
pien "Inspect this repo"
pien raw -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
```

Both direct and flake-integrated modes keep the selected project root as the
single project mounted at `/workspace`. Direct use gets Pi-en from a checkout
or profile; flake integration lets the project pin Pi-en in its own
`flake.lock` and combine it with project-specific tools. Neither mode turns
Pi-en into a separate workspace-env repository or multi-project manager.

### New project flake

For a project that does not yet have a flake, use this as a starting
`flake.nix`. Replace the `pi-en.url` with either a local checkout or a Git
reference that your team can access.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";

    # Local checkout example. A shared repo could use github:u2up/pi-en.
    pi-en.url = "git+file:///home/me/src/pi-en";
    pi-en.inputs.nixpkgs.follows = "nixpkgs";
    pi-en.inputs.flake-utils.follows = "flake-utils";
  };

  outputs = { nixpkgs, flake-utils, pi-en, ... }:
    flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        projectShell = pi-en.lib.mkPiShell {
          inherit pkgs;

          # Smallest project shell: omit pi-en-coord-* helper commands unless
          # this project uses Git-backed coordination.
          includeCoordinationHelpers = false;

          extraPackages = with pkgs; [
            # project-specific tools, for example:
            # nodejs
            # python3
          ];

          shellHook = ''
            echo "project shell loaded"
          '';
        };
      in {
        devShells.default = projectShell;
        # Pi-en-aware projects should also expose the agent selector.
        devShells.agent = projectShell;
      });
}
```

Then run either selector:

```bash
nix develop
nix develop .#agent
pien
```

`mkPiShell` defaults `includeCoordinationHelpers` to `true` so existing
consumers keep `pi-en-bootstrap-coordination` and `pi-en-coord-*` commands on `PATH`.
Set it to `false` for core-only project shells.

### Existing project flake

If the project already has a `flake.nix`, keep its existing structure and add
only the Pi-en pieces. The canonical, copyable helper for this integration is
non-mutating:

```bash
pien recipe flake-agent-shell
```

Use that output as the stable source for agent-oriented `.#agent` shell edits.
For Pi-en-integrated projects, prefer always providing
`devShells.<system>.agent`: use a dedicated agent shell when the default shell
belongs to the project, or alias `agent` to the default shell when the default
shell is already Pi-en-aware.

Add the input:

```nix
inputs = {
  # existing inputs...

  pi-en.url = "git+file:///home/me/src/pi-en";
  # or: pi-en.url = "github:u2up/pi-en";
  pi-en.inputs.nixpkgs.follows = "nixpkgs";
  pi-en.inputs.flake-utils.follows = "flake-utils";
};
```

Include `pi-en` in the outputs arguments:

```nix
outputs = { self, nixpkgs, flake-utils, pi-en, ... }:
  # existing outputs...
```

Then choose one integration style. In both styles, keep `nix develop .#agent`
working for agents and avoid replacing project-owned default shells unless the
user explicitly requests that change.

#### Add a separate `.#agent` shell with `mkPiShell`

Use this when the project already has important devshells, FHS shells, container
outputs, or shell hooks that should remain unchanged, but you want a dedicated
Pi entrypoint:

```nix
devShells.${system} = existingDevShells // {
  agent = pi-en.lib.mkPiShell {
    inherit pkgs;

    # Set this to true when the project uses pi-en coordination helpers.
    includeCoordinationHelpers = false;

    extraPackages = with pkgs; [
      # project-specific tools Pi should see inside Bubblewrap
    ];

    shellHook = ''
      echo "Pi agent shell loaded. Use 'pien' or 'pien shell'."
    '';
  };
};
```

For example, if an existing flake builds `devShells.${system}` with
`builtins.mapAttrs`, preserve that expression and merge the agent shell:

```nix
devShells.${system} = (builtins.mapAttrs (name: profile:
  (mkEnv profile).devShell.env
) profileSet) // {
  agent = pi-en.lib.mkPiShell {
    inherit pkgs;
    includeCoordinationHelpers = true;
    extraPackages = with pkgs; [ ];
  };
};
```

This is different from creating a project-native shell that is merely named
`agent`. A Pi-en-aware shell must expose `pien`, the Pi-en runtime, and the
Pi-en sandbox/runtime wiring, so it should use `pi-en.lib.mkPiShell` or
include the appropriate Pi-en package outputs explicitly.

#### Alias `.#agent` to an already Pi-en-aware default shell

Use this when the existing default shell already comes from `mkPiShell` and you
only need the conventional agent selector:

```nix
let
  existingDevShells = {
    default = pi-en.lib.mkPiShell {
      inherit pkgs;
      includeCoordinationHelpers = true;
      extraPackages = with pkgs; [ ];
    };
  };
in {
  devShells.${system} = existingDevShells // {
    agent = existingDevShells.default;
  };
}
```

This keeps human `nix develop` behavior unchanged while making
`nix develop .#agent` explicit for Pi-en startup.

#### Suggested prompt for external complex flakes

When asking Pi to make this edit from inside an external project, be explicit
or request the packaged skill. For complex flakes, use this canonical wording
from the project root:

```text
Use the pi-en-flake-integration skill. Modify flake.nix to add
devShells.${system}.agent using pi-en.lib.mkPiShell. Add pi-en as a
flake input, add it to outputs, preserve existing devShells and package
outputs, and do not create a project-native agentProfile unless I
explicitly ask for one.
```

An equivalent shorter request is:

```text
I am in an existing external project. Make `nix develop .#agent` start a
pi-en-aware shell, not a generic project shell named agent. Preserve the
current flake outputs and merge an `agent = pi-en.lib.mkPiShell { ... };`
devshell that exposes `pien` and pi-en's sandbox/runtime wiring.
```

The skill is shipped in `pi-skill-templates/pi-en-flake-integration/` so it is
available from Nix-built support payloads and non-Nix installs that copy the
Pi-en support files.

Then use:

```bash
nix develop .#agent
pien --runtime nix
```

With `--runtime nix`, `pien` enters the project's `.#agent` shell before Pi
starts, so the sandbox inherits the tools and Pi-en helpers from that Nix
shell. By contrast, Pi TUI `!` and `!!` shell escapes run later from inside the
already-created sandbox; they can use only the in-Pi command surface described
in the command reference and cannot change the outer runtime selection.

#### Wrap the devshell with `mkPiShell`

Use this when you want Pi-en to own the shell composition and add your project
tools through `extraPackages`:

```nix
devShells.default = pi-en.lib.mkPiShell {
  inherit pkgs;

  # Keep this false for a core-only runtime shell. Omit the option or set it
  # to true if the project uses pi-en-bootstrap-coordination or pi-en-coord-* helpers.
  includeCoordinationHelpers = false;

  extraPackages = with pkgs; [
    # existing project tools
  ];

  shellHook = ''
    # existing shell hook
  '';
};
```

### Project-specific build and test tools

Pi-en keeps its default runtime intentionally small. Host runtime mode uses
unpinned host tools from the conservative sandbox `PATH`; Nix runtime mode uses
the pinned tools provided by this flake. Neither mode bundles every compiler or
build system a target repository might need. Add host-runtime tools explicitly
with `PI_EN_BWRAP_HOST_EXTRA_PATH`, or declare reproducible project tools in the
consuming project's Nix flake. Bubblewrap remains the isolation boundary in both
modes.

For builds or tests, declare tools in the consuming project's flake:

```nix
devShells.default = pi-en.lib.mkPiShell {
  inherit pkgs;
  includeCoordinationHelpers = false;

  extraPackages = with pkgs; [
    gnumake
    gcc
    pkg-config
  ];
};
```

`mkPiShell` turns the `extraPackages` `bin` outputs into `PI_EN_BWRAP_EXTRA_PATH`.
In Nix runtime mode, `pi-en-bwrap` validates those entries before starting the
sandbox, accepts only canonical `/nix/store` directories, and then appends them
after the core Pi-en runtime path. Since `/nix/store` is already mounted
read-only, no host `/bin`, host `/usr/bin`, project-writable directory, or scan
of the whole store is needed. Pi-en does not infer tools from a repository
automatically.

Advanced Nix-runtime users may set `PI_EN_BWRAP_EXTRA_PATH` directly to a
colon-separated list of command directories, but entries must be absolute
existing directories that canonicalize under `/nix/store`; unsafe entries such
as `/tmp/bin`, `$HOME/bin`, `./bin`, `/usr/bin`, or `/bin` are rejected before
Pi starts. Host-runtime users should use `PI_EN_BWRAP_HOST_EXTRA_PATH` instead;
those entries are canonicalized, must exist, are mounted read-only, and are
rejected under host `$HOME`.

In Nix runtime mode, Pi-en may bind a generated read-only shadow directory over
`/home/pi/.pi/agent/bin`. This masks stale or host-specific Pi-provided tools
that would otherwise take precedence inside Pi, while leaving the user's host
agent directory untouched. The default curated shadow list includes `rg`, `fd`,
`grep`, `find`, `ls`, `bash`, `sh`, `node`, `jq`, `git`, `sed`, `awk`, `tar`,
and `gzip`. Each entry is a symlink resolved only from trusted Nix-store paths
already admitted by `PI_EN_RUNTIME_PATH` or by validated
`PI_EN_BWRAP_EXTRA_PATH`; Pi-en does not scan arbitrary host paths to populate
this directory.

Set `PI_EN_BWRAP_AGENT_BIN_SHADOW=0` to opt out and keep the normal sandbox
agent `bin` directory visible. Set `PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS` to a
space-separated replacement list when you need a narrower or custom shadow set,
for example `PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS="rg fd"`. Invalid tool names
fail before startup. Missing tools in an explicit list emit warnings and are
skipped; if the list is empty or no listed tool resolves from trusted Nix paths,
Pi-en does not bind the shadow directory.

#### Add Pi-en to an existing devshell

Use this when the project already has a custom `mkShell` and you only want to
add the Pi-en commands:

```nix
packages = existingPackages ++ [
  pi-en.packages.${system}.pi-core
];
```

If your shell uses `nativeBuildInputs` or `buildInputs`, add the same package
there instead. Use `pi-en.packages.${system}.pi-en-coordination` when you want
only the optional coordination helpers, or `pi-en.packages.${system}.pi-runtime`
when you want the combined bundle containing both the core runtime and
coordination helpers.

Update a consuming project's pinned input with:

```bash
nix flake update pi-en
```

`pi-en.lib.mkPiShell` provides a shell-local `pi-en-update`. In that context,
`pi-en-update` / `pien update` updates the consuming project's `pi-en` flake
input with only `--url` and `--ref` options. Omitted source parts are preserved:
`--url` alone keeps the current ref/rev selector and `--ref` alone keeps the
current base URL. With no options, the updater leaves `flake.nix` unchanged and
refreshes the current lock input. Explicit source options also refresh that lock
input even if `flake.nix` already contains the computed URL, so mutable
repository or branch inputs can advance to a newer commit. Outside a
Pi-en-enabled Nix shell, the same command name remains the non-Nix installed-prefix
updater. Normal Nix shell `PATH` precedence is the selection
mechanism: the Nix-store command shadows any locally installed prefix updater
inside `mkPiShell`, while the local installed command applies outside the Nix
shell.

Examples for the Nix-shell updater:

```bash
pi-en-update --ref main
pi-en-update --url github:u2up/pi-en --ref v0.2.0
pi-en-update --url https://github.com/u2up/pi-en.git --ref abc123@main
```

The `COMMIT@BRANCH` form maps internally to a Nix Git flake URL containing
both `ref=BRANCH` and `rev=COMMIT`, for example
`git+https://github.com/u2up/pi-en.git?ref=main&rev=abc123`. The updater
supports direct `pi-en` URL assignments such as `pi-en.url = "...";`,
`inputs.pi-en.url = "...";`, and `"pi-en".url = "...";`. Dynamic or otherwise
unsupported input definitions fail safely with manual-edit guidance instead of
guessed rewrites. Review and commit any resulting `flake.nix` and `flake.lock`
changes in the consuming project.

## 5. Command reference

`pien` is the canonical user-facing command namespace. Lower-level/debug
entrypoints use `pi-en-*` names: `pi-en`, `pi-en-shell`, `pi-en-bwrap`,
`pi-en-bootstrap-coordination`, `pi-en-coord-*`, `pi-en-serial-roles`,
`pi-en-install-non-nix`, `pi-en-update`, and `pi-en-uninstall`. The old
non-prefixed names
are intentionally not compatibility entrypoints. Operational state paths such
as `.pi-en/` and environment variables such as `PI_EN_RUNTIME` and
`PI_EN_COORD_DIR` keep their existing names.

### `pien`

Start Pi with Pi-en defaults:

```bash
pien
pien "Inspect this repo"
pien run "Inspect this repo"
```

Top-level `pien` subcommand names are reserved before Pi arguments. Use `--`
when the first Pi argument should be passed through literally instead of being
parsed as a `pien` command:

```bash
pien -- shell
pien -- coord status
```

Use `pien raw -- ...` to pass custom arguments directly through the sandbox
layer, `pien shell` for an interactive runtime/sandbox shell, and
`pien sandbox` only when you intentionally want the lower-level Bubblewrap
launcher:

```bash
pien raw -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
pien shell --runtime nix
pien sandbox -- --help
pien sandbox shell -- -l
```

Select the runtime with `--runtime host|nix|auto` or
`PI_EN_RUNTIME=host|nix|auto`; the command-line option wins. Host runtime is
unpinned and uses admitted host tools. Nix runtime is reproducible and pinned
by the selected Pi-en flake, entering `nix develop` when needed.

#### Outer-terminal vs in-Pi `pien` commands

Pi TUI shell escapes (`!command` and `!!command`) run after Pi has already
started, so they execute inside the Bubblewrap sandbox at `/workspace`, with the
isolated home and deliberately limited credential/host filesystem view described
below. They do not re-enter the outer terminal.

The full launcher surface is for the outer terminal before Pi starts. Run these
from your normal shell when you need to choose a runtime, enter a shell, manage
installation, or start a new Pi sandbox:

| Blocked inside Pi | Outer-terminal equivalent |
| --- | --- |
| `pien`, `pien run ...` | Start or resume Pi from the outer terminal with `pien ...`. |
| `pien --runtime nix|host|auto ...` | Select the runtime before launch, for example `pien --runtime nix ...`. |
| `pien shell ...` | Open a runtime/sandbox shell from outside Pi with `pien shell ...`. |
| `pien sandbox ...`, `pien sandbox shell ...` | Start the lower-level sandbox from outside Pi with the same command. |
| `pien install ...` | Install from the outer terminal, for example `pien install --prefix ~/.local`. |
| `pien update ...` | Update from the outer terminal or mkPiShell devshell with context-specific `pien update ...`; inside Pi's Bubblewrap sandbox it remains blocked. |
| `pien uninstall ...` | Uninstall from the outer terminal with `pien uninstall ...`. |
| `pien roles serial ...` | Run serial orchestration from the outer terminal; `pien roles serial --help` is allowed inside Pi for guidance. |

Inside Pi, use the sandbox-safe subset for discovery, diagnostics, recipes, and
coordination state that is already available in the sandbox:

- `pien help`, `pien help coord`, `pien help coord status`
- `pien version` and `pien diagnostics`
- `pien recipe flake-agent-shell`
- `pien coord status`, `pien coord list ...`, and `pien coord show ITEM`
- `pien coord bootstrap --print-only` for bootstrap planning
- other `pien coord ...` helpers when their required coordination repository,
  remotes, and credentials are intentionally available inside the sandbox

Blocked commands fail with an actionable diagnostic instead of dispatching to
the launcher. The same guidance is covered by `tests/pien-dispatcher.sh` so
humans and agents see consistent operational advice.

#### `pien` command mapping

| Canonical command | Behavior source |
| --- | --- |
| `pien [pi args...]` | `pi-en [pi args...]` |
| `pien run [pi args...]` | `pi-en [pi args...]` |
| `pien raw -- [pi args...]` | `pi-en --raw -- [pi args...]` |
| `pien shell [shell args...]` | `pi-en-shell [shell args...]` |
| `pien sandbox [pi args...]` | `pi-en-bwrap [pi args...]` |
| `pien sandbox shell [shell args...]` | `pi-en-bwrap --shell -- [shell args...]` |
| `pien coord bootstrap [options]` | `pi-en-bootstrap-coordination [options]` |
| `pien coord init [options]` | `pi-en-coord-init [options]` |
| `pien coord clone [options] [remote]` | `pi-en-coord-clone [options] [remote]` |
| `pien coord status [options]` | `pi-en-coord-status [options]` |
| `pien coord list [options] TYPE [STATUS]` | `pi-en-coord-list [options] TYPE [STATUS]` |
| `pien coord show [options] ITEM` | `pi-en-coord-cat [options] ITEM` |
| `pien coord new [options] "title"` | `pi-en-coord-new [options] "title"` |
| `pien coord claim [options] ITEM` | `pi-en-coord-claim [options] ITEM` |
| `pien coord done [options] ITEM` | `pi-en-coord-done [options] ITEM` |
| `pien coord review [options] ITEM` | `pi-en-coord-review [options] ITEM` |
| `pien coord verify [options] ITEM` | `pi-en-coord-verify [options] ITEM` |
| `pien coord close [options] ITEM` | `pi-en-coord-close [options] ITEM` |
| `pien coord pull [options] [git args...]` | `pi-en-coord-pull [options] [git args...]` |
| `pien coord push [options] [git args...]` | `pi-en-coord-push [options] [git args...]` |
| `pien coord lint [options]` | `pi-en-coord-lint [options]` |
| `pien coord repo ...` | `pi-en-coord-repo ...` |
| `pien coord rules upgrade [options]` | `pi-en-coord-upgrade-rules [options]` |
| `pien coord requirements generate [...]` | `pi-en-coord-generate-requirements [...]` |
| `pien coord requirements coverage [...]` | `pi-en-coord-generate-requirements-coverage [...]` |
| `pien roles serial [options]` | `pi-en-serial-roles [options]` |
| `pien install [options]` | `pi-en-install-non-nix [options]` |
| `pien update [options]` | context-specific `pi-en-update [options]`: inside `mkPiShell`, only `--url`, `--ref`, and help for the consuming flake input; outside Nix shells, the non-Nix installed-prefix updater or direct-checkout fallback with explicit non-Nix source options |
| `pien uninstall [options]` | `pi-en-uninstall [options]` |

#### Help and completion

Use `pien help` for namespace help, group help for command discovery, and leaf
help to delegate to the underlying command's `--help` output:

```bash
pien help
pien help coord
pien help coord status
pien coord status --help
```

Print and source portable Bash completion with:

```bash
pien completion bash
source <(pien completion bash)
```

Completion covers top-level commands, nested `coord`, `roles`, `sandbox`, and
`completion` subcommands, and known options for representative leaf commands,
including update source options such as `--url`, `--ref`, `--prefix`,
`--artifact-url`, and `--check-deps`.

### Lower-level entrypoints

These `pi-en-*` commands are the lower-level wrappers behind the canonical
`pien` namespace. Most users should prefer `pien`, `pien shell`, and
`pien sandbox` unless they need compatibility with an existing invocation or
are debugging a specific layer.

#### `pi-en`: default Pi launcher

Start Pi with Pi-en defaults:

```bash
pi-en
```

Direct checkout `pi-en` defaults to host runtime mode. It chooses the default
tool list from `PI_EN_BWRAP_DEFAULT_TOOLS` when set, otherwise uses Pi's
built-in tools:

```text
read,bash,edit,write,grep,find,ls
```

In all runtime modes, default `pi-en` startup runs the sandbox with the default
tool allowlist, `--continue`, and the default role-manager package when
available:

```bash
pi-en-bwrap --tools read,bash,edit,write,grep,find,ls --continue -e "$PI_EN_ROLE_MANAGER_PACKAGE"
```

By default, `pi-en` loads the packaged role-manager extension when the package
path exists. The role manager is inactive until you select a role, restore one
from session state, or request one through supported environment variables. Set
`PI_EN_ROLE_MANAGER_AUTO=0` to omit the automatic per-run extension argument,
especially if you prefer an installed-package workflow.

Select the runtime with `--runtime host|nix|auto` or
`PI_EN_RUNTIME=host|nix|auto`; the command-line option wins. Host runtime is
unpinned and uses admitted host tools. Nix runtime is reproducible and pinned
by the selected Pi-en flake, entering `nix develop` when needed.

For custom Pi arguments, use raw mode:

```bash
pi-en --raw -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
pi-en --runtime nix --raw -- --model anthropic/claude-sonnet-4-5 "Inspect this repo"
```

#### `pi-en-shell`: sandboxed interactive shell

Enter a shell inside the selected Pi-en runtime and the same Bubblewrap
sandbox used for Pi runs:

```bash
pi-en-shell
pi-en-shell --runtime nix
pi-en-shell -- -lc 'pwd && command -v git'
```

With no Bash arguments, `pi-en-shell` starts an interactive login shell and
requires both stdin and stdout to be TTYs. Non-TTY invocations fail before
entering Bubblewrap with a Pi-en diagnostic; use a terminal/PTY for interactive
shells, or pass explicit non-interactive Bash arguments such as
`-- -lc 'pwd && command -v git'` in scripts and CI. Explicit interactive Bash
requests such as `-- -i` follow the same TTY requirement.

`pi-en-shell` accepts the same `--runtime host|nix|auto`, `--flake REF`, and
`PI_EN_RUNTIME` selection inputs as `pi-en`. It does not reinterpret normal
Pi arguments; any remaining arguments are Bash arguments after runtime
selection. Use `pi-en` for normal agent startup and `pi-en --raw -- ...` when
you need custom Pi arguments.

#### `pi-en-bwrap`: direct Bubblewrap launcher

`pi-en-bwrap` runs `pi-coding-agent` inside the Bubblewrap sandbox. Use it
directly when you want full control over the Pi arguments or when running Pi
subcommands:

```bash
pi-en-bwrap -- --help
pi-en-bwrap -- config
pi-en-bwrap --shell
```

`pi-en-bwrap --shell [--] [bash args...]` keeps the same project mount,
isolated home, runtime `PATH`, and environment policy, but execs Bash as the
sandbox payload instead of `pi`. The default shell payload is interactive and
requires stdin/stdout TTYs; explicit non-interactive payloads such as
`pi-en-bwrap --shell -- -lc 'pwd'` are supported in non-TTY runners. Prefer
`pi-en-shell` unless you have already selected the runtime and intentionally
want to call the sandbox layer directly.

### Pi configuration inside and outside the sandbox

Pi's `config` subcommand enables or disables extensions, skills, prompt
templates, and themes.

To edit the **sandboxed Pi-en config**, run it through Bubblewrap:

```bash
pi-en-bwrap -- config
# or
pi-en-bwrap config
```

Inside the sandbox, Pi uses `/home/pi/.pi/agent/settings.json`, backed by
Pi-en's per-project state directory. Project-local config remains the mounted
repo's `.pi/settings.json` under `/workspace`.

By default, Pi-en copies the host `settings.json` into sandbox state on each
run when global extensions/packages are imported. If you want sandbox edits made
by `pi-en-bwrap -- config` to persist instead of being refreshed from the host
copy, use:

```bash
PI_EN_BWRAP_EXTENSIONS_SYNC=missing pi-en-bwrap -- config
```

To edit your **real host/global Pi config**, run `pi config` directly after
entering the Nix devshell:

```bash
nix develop
pi config
```

This uses the Nix-provided runtime/tools on `PATH`, but does **not** enter the
Bubblewrap sandbox. It modifies the host Pi agent config, normally
`~/.pi/agent/settings.json` unless `PI_CODING_AGENT_DIR` points elsewhere.

## 6. Runtime and sandbox behavior

A Pi-en invocation operates on one selected project root. The launcher detects
or receives that root, and the Bubblewrap layer mounts it read-write at the
fixed in-sandbox path `/workspace`. Complex layouts such as monorepos,
submodules, worktrees, or integration checkouts remain project-owned policy;
Pi-en only chooses which root to expose for this run.

`pi-en-bwrap`:

- mounts the detected project root read-write at `/workspace`;
- mounts `/nix/store` read-only so declared devshell tools can be exposed
  through validated extra command paths;
- constructs the sandbox `PATH` from allowlisted host command directories
  (`/usr/local/bin`, `/usr/bin`, and `/bin`) instead of inheriting the caller's
  full host `PATH`;
- mounts `/usr/local/bin` and the global Pi npm package read-only when present,
  so a global npm-installed `pi` works;
- uses isolated `$HOME=/home/pi`;
- stores sandbox Pi state outside the project by default under
  `$XDG_STATE_HOME/pi-en/<project-hash>` or
  `$HOME/.local/state/pi-en/<project-hash>`;
- imports common Pi rules/skills/prompts/roles from the host Pi agent directory
  by default (`$PI_CODING_AGENT_DIR`, else `~/.pi/agent`), limited to
  `AGENTS.md`, `CLAUDE.md`, `SYSTEM.md`, `APPEND_SYSTEM.md`, `skills/`,
  `prompts/`, and `roles/`;
- exposes global Pi extensions and installed package directories from the host
  Pi agent directory by default (`extensions/`, `npm/`, `git/`) and copies
  `settings.json`, while project-local `.pi/extensions` and `.pi/settings.json`
  are available through `/workspace`;
- copies host Git config into the sandbox by default (`~/.gitconfig` and
  `$XDG_CONFIG_HOME/git/config` / `~/.config/git/config`), but not Git
  credentials or SSH keys;
- copies host Pi model auth files (`auth.json`, `models.json`) from
  `~/.pi/agent` into sandbox state by default;
- bind-mounts only the host Pi session directory for the current working
  directory into the sandbox by default (disabled for ephemeral homes), so
  `/resume` and `--continue` can access sessions for the directory/project
  without exposing all sessions;
- passes `PI_EN_COORD_REMOTE`, `PI_EN_COORD_PROJECT`,
  `PI_EN_COORD_AGENT_ID`, `PI_EN_COORD_PROJECT_KEY`,
  `PI_EN_COORD_ROLE`, and project-local coordination directory context,
  mapping `.pi-en/coordination` to `/workspace/.pi-en/coordination` and
  rejecting external coordination clone paths while still binding external
  local coordination remote parents as needed;
- accepts additional host-runtime command directories only through
  `PI_EN_BWRAP_HOST_EXTRA_PATH`; entries must be absolute, existing directories,
  are canonicalized, are mounted read-only, and are rejected under host `$HOME`;
- does **not** mount host `$HOME`, `~/.ssh`, cloud credential directories, or
  Docker sockets;
- clears the environment, then passes only terminal basics and selected LLM
  provider variables;
- shares the host network by default so Pi can reach model providers.

In host runtime mode, Pi-en also adds conservative read-only support mounts
for system runtime files: `/lib`, `/lib64`, `/usr/lib`, `/usr/lib64`, `/bin`,
`/usr/bin`, and certificate-related `/etc` paths when they exist. These support
mounts let admitted host binaries run inside Bubblewrap; they are not a general
host filesystem, `/usr/share`, locale, alternatives, or home-directory mount.

If your `pi` command or language-manager shims live under host `$HOME` (for
example `~/.local/bin`, `~/.nvm`, `~/.asdf`, or a per-user npm prefix), host
runtime rejects them by default because host `$HOME` is not mounted. Prefer a
system/global install under `/usr/local/bin`, `/usr/bin`, or `/bin`, move a
custom `pi` launcher or other needed command directory outside `$HOME` and opt
it in with `PI_EN_BWRAP_HOST_EXTRA_PATH`, or use `--runtime nix` for pinned tools.
Custom host tool directories admitted with `PI_EN_BWRAP_HOST_EXTRA_PATH` are
mounted read-only and only after validation.

When an admitted host `pi` launcher uses `#!/usr/bin/env node`, `node` itself
must resolve under `/usr/local/bin`, `/usr/bin`, or `/bin`; the launcher check
does not admit `node` from `PI_EN_BWRAP_HOST_EXTRA_PATH`. Use a system/global Node
install or `--runtime nix` when Node only exists in another custom directory.

Important: with the `bash`/`read` tools enabled, auth copied into the sandbox
and project sessions bind-mounted into the sandbox can be read by commands or
tools inside the sandbox. This is still safer than mounting your whole home, but
use least-privilege API keys or a provider proxy when possible.

## 7. Configuration reference

Common environment knobs:

```bash
PI_EN_BWRAP_PROJECT_ROOT=/path/to/repo     # default: git root, else $PWD
PI_EN_BWRAP_USE_GIT_ROOT=0                 # bind only $PWD
PI_EN_BWRAP_STATE_DIR=/path/to/state       # persistent sandbox home/config; .pi-en/state is opt-in
PI_EN_BWRAP_EPHEMERAL_HOME=1               # temporary home/config for this run
PI_EN_BWRAP_IMPORT_AUTH=0                  # do not import host ~/.pi/agent auth files
PI_EN_BWRAP_AUTH_SYNC=missing              # copy auth only if sandbox copy is absent; default is always
PI_EN_BWRAP_IMPORT_SESSIONS=0              # do not bind host sessions for the current working directory
PI_EN_BWRAP_HOST_AGENT_DIR=/path/to/agent  # default: $PI_CODING_AGENT_DIR or ~/.pi/agent
PI_EN_BWRAP_COMMON_AGENT_DIR=/path/to/dir  # common rules/skills/roles dir; default: host Pi agent dir
PI_EN_BWRAP_IMPORT_COMMON=0                # do not import common AGENTS/SYSTEM files, skills, prompts, or roles
PI_EN_BWRAP_COMMON_SYNC=missing            # copy common files only if sandbox copy is absent; default is always
PI_EN_BWRAP_IMPORT_EXTENSIONS=0            # do not expose global Pi extensions/packages from host agent dir
PI_EN_BWRAP_EXTENSIONS_SYNC=missing        # copy settings.json only if sandbox copy is absent; default is always
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0            # do not import host ~/.gitconfig and XDG git config
PI_EN_BWRAP_GIT_CONFIG_SYNC=missing        # copy git config only if sandbox copy is absent; default is always
PI_EN_BWRAP_HOST_GITCONFIG=/path           # host global git config; default: ~/.gitconfig
PI_EN_BWRAP_HOST_XDG_GIT_CONFIG=/path      # host XDG git config; default: $XDG_CONFIG_HOME/git/config or ~/.config/git/config
PI_EN_BWRAP_COORDINATION_DIR=/path/to/repo/.pi-en/coordination # must be the project-local coordination clone
PI_EN_COORD_REMOTE=.pi-en/agent-remotes/pi-en-coordination.git # exact coordination remote URL/path
PI_EN_COORD_PROJECT=pi-en                 # coordination project/domain name
PI_EN_COORD_PROJECT_KEY=PIEN              # optional generated item ID prefix
PI_EN_COORD_ROLE=architect                 # active coordination role for helper commits/events
PI_EN_BWRAP_DEFAULT_TOOLS="read,bash,..."  # override pi-en/pi-en-bwrap default tools
PI_EN_BWRAP_AGENT_BIN_SHADOW=0              # Nix runtime: do not mask /home/pi/.pi/agent/bin
PI_EN_BWRAP_AGENT_BIN_SHADOW_TOOLS="rg fd"  # Nix runtime: override generated shadow tool list
PI_EN_BWRAP_EXTRA_PATH=/nix/store/.../bin   # Nix runtime: validated /nix/store command dirs
PI_EN_BWRAP_HOST_EXTRA_PATH=/opt/tools/bin  # host runtime: validated read-only host command dirs
PI_EN_BWRAP_NET=0                          # disable network sharing
PI_EN_BWRAP_PASS_ENV="HTTP_PROXY,NO_PROXY" # pass extra env vars by name
```

Common per-project overrides can be set before running `pien`,
`pi-en`, or `pi-en-bwrap`, or exported in the project's shell hook:

```bash
PI_EN_BWRAP_PROJECT_ROOT=/path/to/repo pien  # mount this repo at /workspace
PI_EN_BWRAP_USE_GIT_ROOT=0 pien              # use $PWD instead of git root
PI_EN_BWRAP_EPHEMERAL_HOME=1 pien            # throw away sandbox home after the run
PI_EN_BWRAP_STATE_DIR=$PWD/.pi-en/state pien # opt in to project-local sandbox state
PI_EN_BWRAP_IMPORT_AUTH=0 pien               # do not copy host Pi auth into sandbox state
PI_EN_BWRAP_NET=0 pien                       # disable network access
```

Inside the sandbox, the selected project root is mounted read-write at
`/workspace`, while the sandbox home and Pi config live separately from the
host home. The default state location intentionally stays outside `.pi-en/`
because it can contain copied auth, settings, sessions, and caches; use
`PI_EN_BWRAP_STATE_DIR=$PWD/.pi-en/state` only when you explicitly want that
project-local operational state.

## 8. Common vs project-specific Pi resources

`pi-en` keeps the runtime separate from user-specific agent behavior. It does
not ship common rules, skills, prompts, or custom roles itself. Instead,
`pi-en-bwrap` imports common Pi resources from an external directory into the
sandbox Pi agent directory.

By default, the common directory is the user's normal Pi agent directory:

```bash
$PI_CODING_AGENT_DIR   # if set
~/.pi/agent            # otherwise
```

From that directory, `pi-en-bwrap` imports only common agent resources:

```text
AGENTS.md
CLAUDE.md
SYSTEM.md
APPEND_SYSTEM.md
skills/
prompts/
roles/
```

It does not import the whole host home, and auth/session handling remains
controlled separately by `PI_EN_BWRAP_IMPORT_AUTH` and
`PI_EN_BWRAP_IMPORT_SESSIONS`. Global extension/package exposure is controlled
separately by `PI_EN_BWRAP_IMPORT_EXTENSIONS`.

To keep common rules, skills, prompts, or roles in a separate repo or directory,
point `PI_EN_BWRAP_COMMON_AGENT_DIR` at it:

```bash
PI_EN_BWRAP_COMMON_AGENT_DIR=~/CODE/my-pi-common pien
```

Expected layout:

```text
my-pi-common/
  AGENTS.md
  skills/
    common-skill/
      SKILL.md
  prompts/
    review.md
  roles/
    domain-architect.md
```

Disable common resource import entirely with:

```bash
PI_EN_BWRAP_IMPORT_COMMON=0 pien
```

Project-specific rules, skills, roles, and extensions should live in the
project repository so they are versioned with the project:

```text
project/
  AGENTS.md
  .pi/
    extensions/
      project-extension.ts
    skills/
      project-skill/
        SKILL.md
    prompts/
    roles/
      release-builder.md
    settings.json
```

Pi loads the common/global resources from `/home/pi/.pi/agent` and also
discovers project resources from `/workspace`, giving a clean split:

- common rules/skills/roles and global extensions/packages: user-owned,
  reusable across projects;
- project-specific rules/skills/roles/extensions/packages: committed with the
  project;
- `pi-en`: neutral runtime and isolation layer only.

When a project-local coordination checkout exists at `.pi-en/coordination`,
`pi-en-bwrap` also appends a small generated Pi-en coordination block to the
sandbox copy of `/home/pi/.pi/agent/AGENTS.md`. That block is rewritten on each
launch, points Pi at `/workspace/.pi-en/coordination/AGENTS.md`, and tells the
agent to prefer sandbox-safe `pien coord ...` helpers for coordination item
state, linting, repo registry changes, and generated requirement views. This
makes coordination helper usage visible after updating Pi-en; external projects
do not need to commit extra root `AGENTS.md` text just to teach Pi about the
helper-first workflow.

## 9. Git config and credentials

`pi-en-bwrap` imports the user's host Git config into the isolated sandbox home by
default:

```text
~/.gitconfig
$XDG_CONFIG_HOME/git/config, or ~/.config/git/config
```

Inside the sandbox these become:

```text
/home/pi/.gitconfig
/home/pi/.config/git/config
```

This lets Git commands run by Pi use the user's normal identity, aliases,
default branch settings, diff settings, and other non-secret Git preferences
while still avoiding a host `$HOME` mount.

Disable this with:

```bash
PI_EN_BWRAP_IMPORT_GIT_CONFIG=0 pien
```

Use a different config source with:

```bash
PI_EN_BWRAP_HOST_GITCONFIG=/path/to/gitconfig pien
PI_EN_BWRAP_HOST_XDG_GIT_CONFIG=/path/to/xdg-git-config pien
```

By default the sandbox copy is refreshed on each run. Preserve an existing
sandbox copy with:

```bash
PI_EN_BWRAP_GIT_CONFIG_SYNC=missing pien
```

Git credentials, SSH keys, signing keys, credential helpers' backing stores,
and other files referenced from Git config are not imported automatically.

## 10. Role-manager package

`pi-en` ships a Pi role-manager package for agent roles such as architect,
developer, builder, tester, and reviewer. The package contains a Pi extension
plus Markdown role definitions under `role-manager/`. `pi-en` loads it by
default with Pi's per-run extension/package flag when the package path exists;
this does not modify global or project `settings.json`.

Inside `nix develop`, the shell exports `PI_EN_ROLE_MANAGER_PACKAGE` to the
Nix-built role-manager package path. To opt out of default loading for one run:

```bash
PI_EN_ROLE_MANAGER_AUTO=0 pien
```

You can still install it into project-local Pi settings if you want Pi to load
it normally without the per-run flag. In that workflow, use the opt-out variable
if you want to avoid loading the same package through both mechanisms:

```bash
pien sandbox install -l "$PI_EN_ROLE_MANAGER_PACKAGE"
PI_EN_ROLE_MANAGER_AUTO=0 pien
```

The role-manager package can also be built directly:

```bash
nix build /path/to/pi-en#pi-role-manager
pien sandbox install -l "$(readlink -f result)"
```

### Role files and precedence

Base roles are bundled with the package:

| Role | Purpose | Default tools |
|------|---------|---------------|
| `architect` | Design, trade-offs, decisions, and plans. | `read`, `grep`, `find`, `ls` |
| `developer` | Focused source changes. | `read`, `grep`, `find`, `ls`, `edit`, `write`, `bash` |
| `builder` | Build, packaging, integration, and release prep. | `read`, `grep`, `find`, `ls`, `bash`, `edit` |
| `tester` | Reproduction, tests, verification, and coverage gaps. | `read`, `grep`, `find`, `ls`, `bash`, `edit`, `write` |
| `reviewer` | Diff, risk, security, and maintainability review. | `read`, `grep`, `find`, `ls`, `bash` |

Role definitions are Markdown files with frontmatter. Project roles live in
`.pi/roles/*.md` beside other project Pi resources. Common roles can live in the
host/common agent resource directory as `roles/*.md`; `pi-en-bwrap` imports that
`roles/` directory with common `skills/` and `prompts/` when common import is
enabled. A mounted coordination clone may also provide roles for that project
coordination domain.

Roles are merged by `name`; later sources override earlier ones:

1. bundled base package roles;
2. global/common agent roles imported into `/home/pi/.pi/agent/roles`;
3. common roles from `PI_EN_BWRAP_COMMON_AGENT_DIR/roles` when directly visible;
4. coordination-domain roles from `$PI_EN_COORD_DIR/roles`;
5. project roles from `.pi/roles`.

See `role-manager/ROLE_FILE_SCHEMA.md` for the full schema. See
`examples/project-role-override/.pi/roles/domain-architect.md` for a minimal
project-specific role that adds a role without changing the base package.

### Role commands and tools

The extension registers these slash commands:

```text
/role                       select a role interactively
/role <name>                switch the current session to a role
/role-clear                 clear the role and restore prior settings
/role-cycle <name> <goal>   run one bounded role cycle in this session
/role-new <name> <goal>     start a fresh session and run one role cycle
```

When a role is active, only that role's instructions are injected into the
system prompt for each turn. Role frontmatter may request a thinking level,
model/provider, and tool allowlist. Unknown requested tools are warned and
ignored. The default `pi-en` allowlist includes every built-in tool used by
the bundled roles. `/role-cycle` includes the role's one-cycle checklist in the
kickoff prompt, enables the package's `role_cycle_done` tool for that cycle,
and instructs the model to call it as the final action so Pi can terminate the
cycle without an extra follow-up turn. If that tool is unavailable, the prompt
asks for a normal prose final report rather than JSON. `/role-new` requests
that Pi preserve the existing UI screen while switching to the fresh session.

When the role-manager extension has an active role, it sets `PI_EN_COORD_ROLE` for
Pi subprocesses to the role's `coordCommitter` value, or to the role name when
`coordCommitter` is omitted. Coordination helper commands use that value only
for coordination item event actors and per-command coordination Git identity;
project repository commits keep the normal imported Git identity unless the
user explicitly changes it.

See `designs/role-manager.md` for the architecture.

## 11. Agent coordination helpers

`pi-en` includes opt-in helpers for one Git-backed coordination domain per
selected project. A domain can cover multiple implementation repositories, but
each Pi-en invocation mounts and works in one implementation repository at
`/workspace`. They are plain Git/text-file tooling and are separate from
`pi-en`. Install `#pi-en-coordination`, use the combined `#pi-runtime`
bundle, or leave `includeCoordinationHelpers` enabled in `mkPiShell` when you
want these commands. Projects usually use the project-local
`.pi-en/coordination` clone as their attachment to the shared domain.

### One coordination domain across multiple implementation repos

Use one shared coordination repository when several implementation repos belong
to the same product, service family, or delivery domain and should share
requirements, decisions, notes, TODOs, and cross-agent work state. The shared
Git remote is the coordination domain; each implementation repo attaches to it
with its own canonical `repo_id`.

Each `pi-en` invocation still works in one implementation repository mounted at
`/workspace`. Repo-specific issues live under
`repos/<repo_id>/issues/{open,blocked,done,closed}/`, so each issue belongs to
exactly one implementation repo by path. For cross-repo work, create one issue
per affected repo and link them with stable item IDs instead of making one issue
span multiple codebases.

Domain records such as requirements, decisions, notes, and TODOs remain at the
coordination root and are common to the whole domain. Each implementation repo
can commit a root `.pi-en-coordination.yaml` pointing to the same coordination
remote, while `repos/<repo_id>/REPO.md` remains the authoritative manifest for
that repo. The manifest may also list domain-wide generated files, such as
`REQUIREMENTS.md` or `REQUIREMENTS_COVERAGE.md`, that this implementation repo
commits; multiple active repos may intentionally publish the same generated
view.

Use separate coordination domains when repositories should not share process
memory, requirements, decisions, or work queues.

Bootstrap option names are domain-oriented: `--project` names the coordination
domain and `--project-key` selects the domain-level item ID prefix stored in
root `PROJECT.md`. They are not implementation repository ids. The
coordination `--remote` is the shared coordination repository remote. Use
`--repo-id` for the current implementation repo namespace and
`--implementation-remote` for that implementation repo's Git remote when
registering it.

Guided setup with inferred, project-specific defaults:

```bash
pien coord bootstrap
# inspect another project root from this devshell
pien coord bootstrap --project-root /path/to/project --print-only
# or only print the suggested PI_EN_COORD_* environment and init command
pien coord bootstrap --print-only
```

From inside Pi, prefer planning first:

```bash
!pien coord status
!pien coord bootstrap --print-only
```

Review the printed `PI_EN_COORD_*` values and the suggested init/bootstrap
command. For local-only setup, run the real `pien coord bootstrap ...` from the
outer terminal or paste it into a controlled sandbox shell if that is the
intended context. For shared remotes that need SSH keys, tokens, or credential
helpers, run or copy the real bootstrap command in the outer terminal or in an
environment where those credentials have been deliberately provided; the normal
Pi sandbox does not receive host Git credentials automatically.

Create or bootstrap a local-only coordination domain for one implementation
repo:

```bash
pien coord bootstrap \
  --project-root "$PWD" \
  --project my-product \
  --project-key MYPROD \
  --repo-id backend-api
```

Attach an implementation repo to an existing coordination domain without
mutating shared coordination state. This writes/updates the local
`.pi-en-coordination.yaml` attachment hint and, if `backend-api` is not already
registered, reports how to register it explicitly:

```bash
pien coord bootstrap \
  --remote git@example.com:org/my-product-coordination.git \
  --project my-product \
  --project-key MYPROD \
  --repo-id backend-api
```

Attach and explicitly register a new implementation repo namespace. This
mutates shared coordination state by creating `repos/backend-api/REPO.md` and
issue status directories, then commits and pushes the coordination change:

```bash
pien coord bootstrap \
  --remote git@example.com:org/my-product-coordination.git \
  --project my-product \
  --project-key MYPROD \
  --repo-id backend-api \
  --implementation-remote git@example.com:org/backend-api.git \
  --register-repo
```

Manual minimal setup with a local bare remote:

```bash
export PI_EN_COORD_REMOTE=/workspace/.pi-en/agent-remotes/pi-en-coordination.git
export PI_EN_COORD_PROJECT=pi-en
export PI_EN_COORD_PROJECT_KEY=PIEN
export PI_EN_COORD_DIR=/workspace/.pi-en/coordination
export PI_EN_COORD_AGENT_ID=agent-a

pien coord init
```

To use a remote hosted by a Git server, pass it explicitly or set
`PI_EN_COORD_REMOTE`:

```bash
pien coord init --project pi-en --remote git@example.com:org/pi-en-coordination.git
pien coord clone --remote git@example.com:org/pi-en-coordination.git
pien coord bootstrap --remote git@example.com:org/pi-en-coordination.git --print-only
```

`pi-en-bootstrap-coordination` is a thin wrapper around `pi-en-coord-init`: it prints
the inferred root, coordination clone dir, coordination remote, agent ID,
coordination domain project, domain item key, implementation repo id, and
implementation repo remote(s), then initializes with those explicit values.
Coordination remote selection uses this precedence: explicit `--remote`, then
`PI_EN_COORD_REMOTE`, then `.pi-en-coordination.yaml` `coordination_remote`,
then the local bare remote under explicit `--root` or the project-local default.
After a real bootstrap, it records the selected coordination remote in
`.pi-en-coordination.yaml` as `coordination_remote` and the implementation repo
namespace as `repo_id` when one is resolved. If the local coordination clone
already exists but the planned local bare remote is missing or empty, it
recreates that remote from the clone's committed Git history and repairs
`origin` when it is absent or points to a missing local path.

Without a configured exact remote, this creates a bare remote at:

```text
<root>/<project>-coordination.git
```

When `--root` is omitted, helpers default to the project-local
`.pi-en/agent-remotes` directory. Inside the Pi-en sandbox, that is normally
`/workspace/.pi-en/agent-remotes`, available through the standard project bind
mount rather than a separate remotes mount. External local bare remotes remain
supported when configured as `.pi-en-coordination.yaml` `coordination_remote`;
Pi-en represents them as derived operational aliases under
`.pi-en/agent-remotes/`, while `.pi-en-coordination.yaml` remains the source of
truth.

If `PI_EN_COORD_REMOTE` or `.pi-en-coordination.yaml` names a project-local
remote path, `pi-en-bwrap` rewrites it to the matching `/workspace/...` path.
When that project-local path is a derived `.pi-en/agent-remotes/<name>.git`
symlink to an external local bare Git repo, `pi-en-bwrap` masks the sandbox
remotes directory and bind-mounts only the selected bare repo at the same
project-local logical path. If `.pi-en-coordination.yaml` directly names an
external local bare Git repo (detected by its `objects/` directory),
`pi-en-bwrap` mounts only that selected repo at
`/workspace/.pi-en/agent-remotes/<name>.git` and rewrites `PI_EN_COORD_REMOTE`
to the same project-local shape used by local clones. Outside the sandbox, Git
access to such an external remote requires running inside `pi-en-shell` or
providing a real or symlinked `.pi-en/agent-remotes` directory. Explicit
external `PI_EN_COORD_REMOTE` values similarly bind only the selected remote at
`/agent-remotes/<name>.git` and rewrite `PI_EN_COORD_REMOTE` inside the
sandbox. Coordination working clones are project-local only: default clone
operations use `<project-root>/.pi-en/coordination`, and
explicit `--dir`, `--coord-dir`, `PI_EN_COORD_DIR`, or
`PI_EN_BWRAP_COORDINATION_DIR` values for automatic Pi-en workflows must resolve
to that same checkout. External coordination working clones are not part of the
automatic workflow and are rejected with a diagnostic that points users at
`<project-root>/.pi-en/coordination`;
`pi-en-bwrap` does not bind an external clone at `/coordination`. Without
explicit remote overrides or `coordination_remote`, the sandbox launcher only
recognizes project-local `.pi-en/coordination`; root-level `coordination/` and
`agent-remotes/` directories are not selected or mounted automatically.

When `--remote` or `PI_EN_COORD_REMOTE` points to a Git-server URL, helpers use
that URL directly and no local remotes mount is
required. A local path remote is created by `pi-en-coord-init` when missing;
Git-server remotes must already exist and be accessible to Git. Provide SSH
keys, tokens, or credential helpers through narrowly-scoped sandbox/project
configuration as needed; Pi-en does not import the host `~/.ssh` directory or
all host Git credentials wholesale. Remote Git operations launched from inside
Pi remain constrained by the same sandbox credential policy and host-home
isolation: Git config may be copied, but credential stores, SSH keys, signing
keys, cloud credential directories, and the host home are not mounted unless you
explicitly arrange a narrower project-specific mechanism.

It then clones/scaffolds `$PI_EN_COORD_DIR` with `AGENTS.md`, domain
`PROJECT.md` metadata, a repo namespace at
`repos/<repo_id>/issues/{open,blocked,done,closed}`, shared `requirements/`,
`todos/`, `decisions/`, and `notes/` directories, protocol docs, item-format
docs, and `.pi/skills/agent-coordination/SKILL.md`. The repo manifest at
`repos/<repo_id>/REPO.md` is the authoritative registry record for that
implementation repo. When `PI_EN_COORD_DIR` is unset, fresh projects use
`.pi-en/coordination`.

Each `repos/<repo_id>/REPO.md` manifest can also declare the domain-wide
generated outputs committed by that implementation repo, with paths relative to
the implementation repo root. During `pien coord bootstrap`, pass repeatable
`--domain-generated-file PATH` options to write or update the resolved
implementation repo manifest's `domain_generated_files` list; paths must be
repo-root-relative and must not contain `..` traversal components. As a
convenience for repos that commit both generated requirements documents,
`--generated-requirements-docs` expands to `--domain-generated-file
REQUIREMENTS.md` and `--domain-generated-file REQUIREMENTS_COVERAGE.md`; it can
be combined with explicit generated-file options, with duplicates removed in
first-seen order. These options only update the resolved manifest list. They do
not imply `--register-repo`, select a different repo id, or change the
coordination `--project`/`--project-key` domain semantics. For example:

```yaml
domain_generated_files:
  - REQUIREMENTS.md
  - REQUIREMENTS_COVERAGE.md
```

Clone the same coordination domain elsewhere with:

```bash
pien coord clone
```

Create a type-coded timestamp-ID issue in the current repo namespace with:

```bash
pien coord new --repo-id pi-en --type issue --category bug \
  "Document pi config behavior"
pien coord push -m "Add PIEN documentation item"
```

The resulting issue path is
`repos/pi-en/issues/open/<ITEM-ID>.yaml`. Functional requirements, decisions,
and notes remain common domain records at the coordination root.

Issue items can use optional categories such as `bug`, `feature-request`,
`task`, `question`, or `improvement`; use `--type issue
--category task` for task-category work. Use `pien coord list --category
bug issues open` to filter, or `pien coord list --group-by-category issues`
to sort grouped issue output.

When top-level `PROJECT.md` exists, omit `--project` for domain-common items;
`PI_EN_COORD_PROJECT` can remain set for coordination-domain selection. For
issues, pass `--repo-id` or set `PI_EN_COORD_REPO_ID`; helpers may also resolve it
from the implementation repo's `.pi-en-coordination.yaml` or registry remote
metadata. In repo-layout domains, lifecycle helpers that mutate issue state
(`claim`, `done`, `review`, `verify`, and `close`) reject issue IDs or paths
outside the resolved current repo by default, including root `issues/...`
items; `--force` does not bypass this repo-scope protection. Explicit
`--all-repos` issue views remain limited to read-only inspection commands such
as `list` and `status`.

Generated item IDs use a project item key prefix, a type code, a UTC timestamp,
and a three-digit collision/order suffix that starts at `001`:

```text
<PROJECTKEY>-<TYPECODE>-<YYYYMMDD-HHMMSS>-<NNN>
```

For example, an issue can be created as
`PIEN-ISS-20260607-204155-001.yaml`; a functional requirement can be created as
`PIEN-FRQ-20260607-204155-001.yaml`. Use
`pi-en-coord-init --project-key PIEN` to set the initial project's stored key
during scaffolding. Project-root keys are stored in top-level `PROJECT.md` as `item_key`. Agents
should use stored keys instead of inventing new ones.

Key resolution for `pi-en-coord-new` is:

1. `--project-key KEY`;
2. stored root project `item_key`;
3. `PI_EN_COORD_PROJECT_KEY` when no stored key exists;
4. derived `--project` / `PI_EN_COORD_PROJECT` for project items;
5. derived coordination clone directory name when no project name is set.

Derived keys are uppercased and all delimiters, whitespace, pipes, slashes,
backslashes, and other non-alphanumeric characters are removed. For example,
`pi-en_test` becomes `PIENTEST`. `--id ID` overrides the whole item ID.
Built-in type codes are `ISS` for `issue`, `FRQ` for `functional-requirement`,
`QRQ` for `quality-requirement`, `CRQ` for `constraint-requirement`, `TODO` for
`todo`, `DEC` for `decision`, and `NOTE` for `note`.

Lifecycle helpers are also available through the `pien coord` and
`pien roles` namespaces:

```text
pien coord bootstrap
                      infer defaults and initialize via pi-en-coord-init
pien coord status    show sync status and open/blocked/done items
pien coord list      list issues, todos, notes, decisions, requirements, or
                      classes by status
pien coord show      print one resolved item's YAML or repo-relative path
pien coord pull      run git pull --rebase --autostash
pien coord push      commit and push coordination changes
pien coord new       create a templated item
pien coord claim     claim an item, commit, and push
pien coord done      mark developer work done, commit, and push
pien coord review    mark review pass/fail, commit, and push
pien coord verify    mark verification pass/fail, commit, and push
pien coord close     final-close reviewed+verified done items
pien coord lint      lint item IDs, status, and item-matched tests
pien coord rules upgrade --preview
                      preview/apply bundled rule template updates
pien roles serial    serially run one developer/reviewer/tester Pi job at a time
```

Items are YAML files with chronological `events` and linked Markdown messages.
Issue state group names are developer-centric: `open` means developer work is
needed, `blocked` means developer work cannot proceed, `done` means the
developer believes implementation is complete, and `closed` means final
accepted after review and verification.

Issue items live under `repos/<repo_id>/issues/<status>/`, and each issue
belongs to exactly one implementation repo by that path. Functional, quality,
and constraint requirements use the root-level `requirements/` directory while
preserving FRQ, QRQ, and CRQ item-ID type codes. TODO items use `todos/` and
single top-level `body: |-` records without issue history. The `pi-en-coord-list requirements` command reports functional,
quality, and constraint requirement items; use `functional`, `quality`, or
`constraint` for class-specific listings. Done issue listings append
review and verification sub-status after the title. Imported requirement items
record traceability in a top-level `source_refs` list using stable strings such
as old requirement IDs, `REQUIREMENTS.md#heading`, and `USE_CASES.md#section`;
lint checks imported FRQ/QRQ/CRQ items for non-empty source references plus the
standard `testable` metadata.

Decision, note, and other non-issue item types live under their semantic type
directories shared by the coordination domain. Use `pi-en-coord-list notes` or
`pi-en-coord-list todos` to list those root-level groups, optionally filtered
by their YAML `status` values. The
accepted TODO type spellings are `todo` and `todos`; `tdo` is
not a supported alias. Stored implementation refs are structured objects with
`repo`,
`branch`, and full `commit` fields. For cross-repo implementation work, create
one issue per affected repo and link them with stable item IDs in `related:` or
messages rather than path-only references; repo renames preserve aliases and
should not require reference rewrites. `pi-en-coord-done --implementation-ref
Pi-en:main@<full-hash>` accepts the compact CLI form and writes the structured
YAML form. `pi-en-coord-close` finalizes only items that are done, reviewed, and
verified unless forced.

Commands that create item events or coordination commits accept `--role ROLE`
and read `PI_EN_COORD_ROLE`. Item events store actor ID/role metadata explicitly;
helper commits use per-command Git identity overrides such as `pi/architect
<pi+architect@coordination.local>`. These overrides are scoped to the helper's
coordination-repository `git commit`; normal project repository commits keep the
user's imported Git identity unless the user explicitly opts in to another
identity.

Existing coordination repositories are not silently overwritten. Rule upgrades
are explicit and diffable:

```bash
pien coord rules upgrade --preview
pien coord rules upgrade
```

The helpers do not make `pi-en` create, claim, mark done, review, verify,
close, commit, or push coordination state automatically. Coordination working
clones must live under the mounted project at `.pi-en/coordination` for
automatic Pi-en workflows. `pi-en-bwrap` exposes that checkout as normal project
files and sets `PI_EN_COORD_DIR` to `/workspace/.pi-en/coordination` inside the
sandbox. External coordination working clone paths provided through
`PI_EN_COORD_DIR`, `PI_EN_BWRAP_COORDINATION_DIR`, or coordination-directory
command options are rejected instead of being mounted at `/coordination`.

When the role-manager extension has an active role, it sets `PI_EN_COORD_ROLE` for
Pi subprocesses to the role's `coordCommitter` value, or to the role name when
`coordCommitter` is omitted. Bash-invoked `pi-en-coord-*` commands inherit the
active role without changing project Git identity.

### Serial role automation

`pien roles serial` is the canonical command for the first, deliberately
serial automation mode for coordination-backed role work. Use it when you want
one long-lived shell to
process developer, reviewer, and tester issue jobs over one project clone and
one coordination clone, without concurrent source edits or competing Git
operations in that clone. It is useful for initial small automation and prompt
shake-out before investing in parallel workers.

Serial mode prerequisites:

- run from a clean Git project root, or pass `--project-root DIR`;
- provide the writable project-local coordination checkout at
  `.pi-en/coordination`; `PI_EN_COORD_DIR` or `--coord-dir DIR` may be used
  only when they resolve to that same project-local checkout;
- run from the Pi-en devshell/profile so `pi-en`, `pi-en-coord-*` helpers,
  and `PI_EN_ROLE_MANAGER_PACKAGE` are available, or pass explicit `--pi-en`
  and `--role-manager` paths;
- configure Pi model credentials on the host the same way you do for normal
  `pi-en` runs, for example host Pi auth files or provider environment
  variables; and
- allow the orchestrator to pass only the sandbox-visible project-local
  coordination path into each raw sandbox job. It passes
  `PI_EN_COORD_DIR=/workspace/.pi-en/coordination`, `PI_EN_COORD_AGENT_ID`,
  and role context for the job, and exposes packaged lifecycle helpers through
  `PI_EN_BWRAP_EXTRA_PATH` when they live in the Nix store.

Start the loop from the project root:

```bash
cd /path/to/project
pien roles serial --sleep 30
```

Stop it with `Ctrl-C`, or use bounded modes when you want it to exit on its own:

```bash
pien roles serial --once
pien roles serial --max-jobs 3
pien roles serial --max-idle-polls 1 --sleep 5
pien roles serial --dry-run
pien roles serial --ui interactive --once
pien roles serial --ui json --once
pien roles serial --ui none --once
pien roles serial --issue PIEN-ISS-20260705-172018-001 --once
```

Use repeatable `--issue ID` options when you want a bounded batch for explicit
coordination issue IDs instead of the default all-eligible queue:

```bash
pien roles serial --issue ISSUE-1 --issue ISSUE-2 --max-jobs 2
```

With one or more `--issue` options, serial mode never selects an unlisted
issue. Tester, reviewer, then developer priority is preserved across the
requested set, and issues in the same role tier are considered in the order the
options were provided. Unknown IDs, duplicate IDs, and IDs that resolve to
non-issue items fail before any Pi job is run. Once the requested issues have
no eligible tester, reviewer, or developer work, the command exits successfully
instead of sleeping for unrelated queue work.

Each poll holds `.pi-en/locks/pi-en-serial-roles.lock` and creates
`.pi-en/locks` as needed. It requires a clean project working tree. A dirty
coordination checkout before selection is treated as busy: the loop skips
pulling, selecting, and claiming, then sleeps or exits according to the bounded
idle options. Clean coordination is still required before a pull, before a Pi
job, and after each job completes. Serial automation logs and future local
diagnostics default under
`.pi-en/logs`. Work priority is:

1. tester: done issues with `reviewed: true` and `verified: false`;
2. reviewer: done issues with `reviewed: false`;
3. developer: open issues that are unowned or already owned by the agent.

Developer items are claimed with `pi-en-coord-claim` before Pi is invoked.
Reviewer and tester prompts name only the selected done item and instruct the
role to use `pi-en-coord-review` or `pi-en-coord-verify`. If no issue is
eligible, the orchestrator sleeps and polls again without invoking Pi.

Every issue job starts a fresh raw Pi session with `pi-en --raw --` and does
not pass `--continue`. The default `--ui interactive` mode launches the normal
Pi TUI with the selected item prompt, active role environment, coordination
mount, and tool allowlist, but without `--mode json`, `--print`, or `-p`. It
also passes the role-manager extension flag that requests graceful TUI shutdown
after `role_cycle_done`, so the orchestrator can continue after the bounded
role cycle finishes.

Use `--ui json` for structured automation. It adds `--mode json` for JSONL
output, which is useful for unattended loops, CI-like supervision, or when you
want to parse the final `role_cycle_done` details from the corresponding
`tool_execution_end` event alongside other structured tool, usage, compaction,
and error events.

Use `--ui none` for non-interactive prompt/response output. It adds `--print`,
prints the generated role report, and exits without a TUI or JSON event stream.

The previous hold-open `interactive` behavior has intentionally been removed
and is not available under another `--ui` value or compatibility alias. If you
need to inspect a completed session, use normal logs/output or run Pi directly
instead of keeping `pien roles serial` blocked after each item. Coordination state
and Git history are the memory shared between jobs; a fresh conversation avoids
stale context from a previous issue influencing item selection, review,
verification, or lifecycle helper use.

The command fails closed around role execution. Dirty project trees stop the
loop before polling. A dirty coordination tree during idle pre-selection is
treated as a busy checkout: the loop does not pull, inspect, select, claim,
reset, discard, or stash, and it retries after the normal sleep. Dirty project
or coordination trees after a role job remain fatal. A failed coordination
pull/rebase stops with the helper's error so you can resolve the conflict and
rerun. A non-zero Pi job also stops the loop instead of moving on to another
issue; inspect the terminal output and clean up any project or coordination
changes before restarting.

Serial mode does not require tmux, per-role clones, worktrees, or
reviewer/tester leases, and the local lock prevents two serial loops from
sharing one clone.
Those pieces are future parallel-worker concerns. Parallel mode should use
separate clones/worktrees and additional lease rules before multiple roles edit
or mutate coordination concurrently.

See `designs/serial-role-automation.md` for the full design.

See `designs/agent-coordination.md` for the full design.

## 12. Upgrading Pi

`pi-en` does not pin or install `pi-coding-agent` through Nix. The wrappers
expect a `pi` executable to already exist on the host `PATH`, then `pi-en-bwrap`
bind-mounts the host/global Pi installation read-only into the sandbox.

When a new Pi version is available, upgrade Pi on the host, outside `pi-en` /
`pi-en-bwrap`:

```bash
npm install -g --ignore-scripts @earendil-works/pi-coding-agent@latest
pi --version
```

Then continue using `pien` normally:

```bash
nix develop
pien
```

Do not run Pi self-updates from inside the Bubblewrap sandbox: `/usr/local/bin`
and the global Pi npm package are mounted read-only there.

If your current global Pi supports self-update and your user has permission to
update the global install, this can also be run on the host:

```bash
pi update --self
```

That updates Pi itself. It is separate from updating a project's `pi-en` flake
input. If another project consumes this repository as a flake input and Pi-en
changed, update that input in the consuming project with:

```bash
nix flake update pi-en
```

## 13. Development and tests

Run the whole project test suite with:

```bash
tests/run.sh
```

Coordination helper smoke tests:

```bash
tests/pi-en-coord-blackbox.sh
tests/pi-en-coord-concurrency.sh
tests/pi-en-coord-lint.sh
tests/coordination-items-closed-or-done.sh
```

Role-manager package, schema/template, loader, and command smoke tests:

```bash
tests/role-manager-package.sh
tests/role-manager-schema.sh
tests/role-manager-loader.sh
tests/role-manager-commands.sh
```

Item-matched tests live in the owning implementation repository under
`tests/items/` and match the item ID by filename stem. Issue items belong to a
single repo namespace under `repos/{repo_id}/issues/{status}`, but project item
tests mirror only the root item type; they do not mirror repo namespaces or
issue lifecycle status directories:

```text
.pi-en/coordination/repos/pi-en/issues/closed/PIEN-ISS-20260607-204155-001.yaml
tests/items/issues/PIEN-ISS-20260607-204155-001.sh

.pi-en/coordination/requirements/PIEN-FRQ-20260607-204155-001.yaml
tests/items/requirements/PIEN-FRQ-20260607-204155-001.sh
```

## 14. Notes

- Pi's built-in tool list is `read,bash,edit,write,grep,find,ls`.
  `pi-en` allowlists those by default. If you need extension/custom tools
  too, include them in `PI_EN_BWRAP_DEFAULT_TOOLS` or call `pi-en-bwrap` with your own
  `--tools` list.
- Global Pi extensions and globally installed Pi packages are exposed read-only
  from the host agent directory by default. Disable this with
  `PI_EN_BWRAP_IMPORT_EXTENSIONS=0`. Project-local extensions/packages under
  `.pi/` are available because the project is mounted at `/workspace`.
- Use `git` through the `bash` tool unless you install/register a separate Git
  tool extension.
- Bubblewrap limits filesystem/environment exposure. It does not provide
  domain-level network allowlists. For tighter network policy, disable network
  with `PI_EN_BWRAP_NET=0`, use an external firewall/proxy, or add Pi's sandbox
  extension as an additional layer for `bash` commands.
