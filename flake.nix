{
  description = "Reusable Pi coding-agent runtime with bubblewrap isolation";

  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-25.05";
    flake-utils.url = "github:numtide/flake-utils";
  };

  outputs = { self, nixpkgs, flake-utils, ... }:
    let
      defaultTools = "read,bash,edit,write,grep,find,ls";

      mkBehaviorPythonEnv = pkgs:
        pkgs.python3.withPackages (pythonPackages: [ pythonPackages.pyyaml ]);

      # Keep adapter command dependencies separate from mkRuntime: the latter
      # includes mkBehaviorPython, whose sealed adapter PATH needs this base.
      mkBehaviorRuntimeBase = pkgs:
        with pkgs; [
          bash
          bubblewrap
          cacert
          coreutils
          fd
          findutils
          gawk
          git
          gnugrep
          gnused
          gnutar
          gzip
          jq
          nodejs
          (mkBehaviorPythonEnv pkgs)
          ripgrep
          which
        ];

      # Repository-local scripts win over PATH in the pien dispatcher.  Supply
      # their expected behavior interpreter without recursively constructing
      # the sealed adapter PATH.
      mkAdapterBehaviorPython = pkgs:
        let python = mkBehaviorPythonEnv pkgs;
        in pkgs.writeShellScriptBin "pi-en-behavior-python" ''
          export PYTHONPYCACHEPREFIX="''${XDG_CACHE_HOME:-''${HOME}/.cache}/pi-en/python-bytecode"
          exec ${python}/bin/python "$@"
        '';

      mkBehaviorPython = pkgs:
        let
          python = mkBehaviorPythonEnv pkgs;
          adapterRuntimePath = pkgs.lib.makeBinPath (
            (mkBehaviorRuntimeBase pkgs) ++ [ (mkAdapterBehaviorPython pkgs) ]
          );
        in
        pkgs.writeShellScriptBin "pi-en-behavior-python" ''
          export PYTHONPYCACHEPREFIX="''${XDG_CACHE_HOME:-''${HOME}/.cache}/pi-en/python-bytecode"
          # Adapters receive this fixed Nix runtime rather than the caller PATH.
          export PI_EN_BEHAVIOR_RUNTIME_PATH="''${PI_EN_BEHAVIOR_RUNTIME_PATH:-${adapterRuntimePath}}"
          exec ${python}/bin/python "$@"
        '';

      mkRuntime = pkgs:
        (mkBehaviorRuntimeBase pkgs) ++ [ (mkBehaviorPython pkgs) ];

      mkDevShellTools = pkgs:
        with pkgs; [
          diffutils
          patch
        ];

      mkPiBwrap = pkgs:
        let
          runtimePackages = mkRuntime pkgs;
          runtimePath = pkgs.lib.makeBinPath runtimePackages;
        in
        pkgs.writeShellScriptBin "pi-en-bwrap" ''
          set -euo pipefail
          export PI_EN_RUNTIME_PATH="${runtimePath}"
          export PI_EN_BWRAP_COMPILED_DEFAULT_TOOLS="${defaultTools}"
          export PI_EN_BWRAP_BASH="${pkgs.bash}/bin/bash"
          export PI_EN_BWRAP_ENV="${pkgs.coreutils}/bin/env"
          export PI_EN_BWRAP_CA_BUNDLE="${pkgs.cacert}/etc/ssl/certs/ca-bundle.crt"
          export PI_EN_BWRAP_BWRAP="${pkgs.bubblewrap}/bin/bwrap"
          exec ${pkgs.bash}/bin/bash ${./scripts/pi-en-bwrap} "$@"
        '';

      mkPiEnBehavior = pkgs:
        let
          python = mkBehaviorPython pkgs;
        in
        pkgs.writeShellScriptBin "pi-en-behavior" ''
          exec ${python}/bin/pi-en-behavior-python ${./scripts/pi-en-behavior.py} "$@"
        '';

      mkPiEn = pkgs:
        let
          piBwrap = mkPiBwrap pkgs;
          roleManagerPackage = mkRoleManagerPackage pkgs;
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
        in
        pkgs.writeShellScriptBin "pi-en" ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          export PI_EN_BWRAP_COMPILED_DEFAULT_TOOLS="${defaultTools}"
          export PI_EN_ROLE_MANAGER_PACKAGE="''${PI_EN_ROLE_MANAGER_PACKAGE:-${roleManagerPackage}}"
          export PI_EN_PI_EN_BWRAP="${piBwrap}/bin/pi-en-bwrap"
          exec -a pi-en ${pkgs.bash}/bin/bash ${./scripts/pi-en-launcher} "$@"
        '';

      mkPiEnShell = pkgs:
        let
          piBwrap = mkPiBwrap pkgs;
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
        in
        pkgs.writeShellScriptBin "pi-en-shell" ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          export PI_EN_SHELL_MODE=1
          export PI_EN_PI_EN_BWRAP="${piBwrap}/bin/pi-en-bwrap"
          exec -a pi-en-shell ${pkgs.bash}/bin/bash ${./scripts/pi-en-launcher} "$@"
        '';

      mkPien = pkgs: { includeCoordinationHelpers ? true }:
        let
          coordinationCommands = if includeCoordinationHelpers then builtins.attrValues (mkAgentCoordCommands pkgs) else [ ];
          installCommands = builtins.attrValues (mkInstallNonNixCommands pkgs);
          runtimePath = pkgs.lib.makeBinPath ((mkRuntime pkgs) ++ [
            (mkPiEn pkgs)
            (mkPiEnShell pkgs)
            (mkPiBwrap pkgs)
            (mkPiEnBehavior pkgs)
          ] ++ installCommands ++ coordinationCommands);
          pienBin = pkgs.writeShellScriptBin "pien" ''
            set -euo pipefail
            if [ "''${PI_EN_NIX_SHELL:-0}" = "1" ]; then
              export PATH="''${PATH:-}:${runtimePath}"
            else
              export PATH="${runtimePath}:''${PATH:-}"
            fi
            exec -a pien ${pkgs.bash}/bin/bash ${./scripts/pien} "$@"
          '';
        in
        pkgs.runCommand "pien" { } ''
          mkdir -p "$out/bin" "$out/share/bash-completion/completions"
          ln -s ${pienBin}/bin/pien "$out/bin/pien"
          ${pkgs.bash}/bin/bash ${./scripts/pien} completion bash > "$out/share/bash-completion/completions/pien"
        '';

      agentCoordCommandNames = [
        "pi-en-bootstrap-coordination"
        "pi-en-coord-init"
        "pi-en-coord-clone"
        "pi-en-coord-status"
        "pi-en-coord-list"
        "pi-en-coord-cat"
        "pi-en-coord-pull"
        "pi-en-coord-push"
        "pi-en-coord-new"
        "pi-en-coord-repo"
        "pi-en-coord-claim"
        "pi-en-coord-done"
        "pi-en-coord-review"
        "pi-en-coord-verify"
        "pi-en-coord-close"
        "pi-en-coord-lint"
        "pi-en-coord-generate-requirements"
        "pi-en-coord-generate-requirements-coverage"
        "pi-en-coord-upgrade-rules"
        "pi-en-serial-roles"
      ];

      mkAgentCoordSupport = pkgs:
        pkgs.runCommand "pi-en-agent-coordination-support" { } ''
          mkdir -p "$out/share/pi-en"
          cp -R ${./pi-skill-templates} "$out/share/pi-en/pi-skill-templates"
          cp -R ${./role-manager} "$out/share/pi-en/role-manager"
          cp -R ${./scripts} "$out/share/pi-en/scripts"
          chmod +x "$out/share/pi-en/scripts"/pi-en-coord-* \
            "$out/share/pi-en/scripts/pi-en-bootstrap-coordination" \
            "$out/share/pi-en/scripts/pi-en-serial-roles" \
            "$out/share/pi-en/scripts/pien" \
            "$out/share/pi-en/scripts/pi-en-install-non-nix"
        '';

      mkPiEnNixUpdate = pkgs:
        let
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
        in
        pkgs.writeShellScriptBin "pi-en-update" ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          exec ${pkgs.bash}/bin/bash ${./scripts/pi-en-update-nix-flake-input} "$@"
        '';

      mkInstallNonNixCommands = pkgs:
        let
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
          support = mkAgentCoordSupport pkgs;
          installNonNix = pkgs.writeShellScriptBin "pi-en-install-non-nix" ''
            set -euo pipefail
            export PATH="${runtimePath}:''${PATH:-}"
            exec ${pkgs.bash}/bin/bash "${support}/share/pi-en/scripts/pi-en-install-non-nix" "$@"
          '';
          piEnUpdate = pkgs.writeShellScriptBin "pi-en-update" ''
            set -euo pipefail
            export PATH="${runtimePath}:''${PATH:-}"
            export PI_EN_INSTALL_UPDATE_WRAPPER=1
            export PI_EN_INSTALL_PREFER_REMOTE=1
            exec ${pkgs.bash}/bin/bash "${support}/share/pi-en/scripts/pi-en-install-non-nix" "$@"
          '';
          piEnUninstall = pkgs.writeShellScriptBin "pi-en-uninstall" ''
            set -euo pipefail
            export PATH="${runtimePath}:''${PATH:-}"
            exec ${pkgs.bash}/bin/bash "${support}/share/pi-en/scripts/pi-en-install-non-nix" --uninstall "$@"
          '';
        in
        {
          inherit installNonNix piEnUpdate piEnUninstall;
        };

      mkAgentCoordCommand = pkgs: name:
        let
          runtimePath = pkgs.lib.makeBinPath (mkRuntime pkgs);
          support = mkAgentCoordSupport pkgs;
          roleManagerPackage = mkRoleManagerPackage pkgs;
        in
        pkgs.writeShellScriptBin name ''
          set -euo pipefail
          export PATH="${runtimePath}:''${PATH:-}"
          export PI_EN_COORD_TEMPLATE_DIR="${support}/share/pi-en/pi-skill-templates/agent-coordination"
          export PI_EN_COORD_LIB="${support}/share/pi-en/scripts/pi-en-coord-lib.sh"
          export PI_EN_ROLE_MANAGER_PACKAGE="''${PI_EN_ROLE_MANAGER_PACKAGE:-${roleManagerPackage}}"
          exec ${pkgs.bash}/bin/bash "${support}/share/pi-en/scripts/${name}" "$@"
        '';

      mkAgentCoordCommands = pkgs:
        builtins.listToAttrs (map (name: {
          inherit name;
          value = mkAgentCoordCommand pkgs name;
        }) agentCoordCommandNames);

      mkRoleManagerPackage = pkgs:
        pkgs.runCommand "pi-en-role-manager" { } ''
          mkdir -p "$out"
          cp -R ${./role-manager}/. "$out/"
        '';

      mkPiShell =
        { pkgs
        , extraPackages ? [ ]
        , shellHook ? ""
        , includeCoordinationHelpers ? true
        }:
        let
          piBwrap = mkPiBwrap pkgs;
          piEn = mkPiEn pkgs;
          piEnShell = mkPiEnShell pkgs;
          piEnBehavior = mkPiEnBehavior pkgs;
          pien = mkPien pkgs { inherit includeCoordinationHelpers; };
          piEnNixUpdate = mkPiEnNixUpdate pkgs;
          agentCoordCommands = builtins.attrValues (mkAgentCoordCommands pkgs);
          coordinationPackages = if includeCoordinationHelpers then agentCoordCommands else [ ];
          roleManagerPackage = mkRoleManagerPackage pkgs;
          # Only expose sandbox-aware commands inside Pi.  The outer runtime
          # launchers remain available in the dev shell itself, but are kept
          # off PI_EN_BWRAP_EXTRA_PATH so they cannot be invoked directly from
          # inside the Bubblewrap sandbox.
          piSandboxCommandPath = pkgs.lib.makeBinPath ([
            pien
          ] ++ coordinationPackages);
          extraPackagePath = pkgs.lib.makeBinPath (extraPackages ++ [
            pien
          ] ++ coordinationPackages);
        in
        pkgs.mkShell {
          packages = (mkRuntime pkgs) ++ (mkDevShellTools pkgs) ++ [
            piBwrap
            piEn
            piEnShell
            piEnBehavior
            pien
            piEnNixUpdate
          ] ++ coordinationPackages ++ extraPackages;

          shellHook = ''
            export PS1="(nix-dev) \u@\h:\w$ "
            export PI_EN_DEV_SHELL_PS1="$PS1"
            export PI_EN_ROLE_MANAGER_PACKAGE="${roleManagerPackage}"
            export PI_EN_NIX_PROJECT_BWRAP="${piBwrap}/bin/pi-en-bwrap"
            export PI_EN_NIX_SANDBOX_COMMAND_PATH="${piSandboxCommandPath}"
            export PI_EN_NIX_SHELL=1
            export PI_EN_FLAKE_INPUT_NAME=pi-en
            if [ -n "${extraPackagePath}" ]; then
              if [ -n "''${PI_EN_BWRAP_EXTRA_PATH:-}" ]; then
                export PI_EN_BWRAP_EXTRA_PATH="${extraPackagePath}:$PI_EN_BWRAP_EXTRA_PATH"
              else
                export PI_EN_BWRAP_EXTRA_PATH="${extraPackagePath}"
              fi
            fi
            if [ -z "''${PI_EN_QUIET:-}" ]; then
              echo "Pi agent runtime loaded"
              echo "Use 'pien' for default startup, 'pien shell' for a sandbox shell, or 'pien raw -- <pi args>' for custom runs."
            fi
          '' + shellHook;
        };
    in
    {
      lib = {
        inherit
          defaultTools
          mkRuntime
          mkDevShellTools
          mkPiBwrap
          mkPiEn
          mkPiEnShell
          mkPiEnBehavior
          mkPien
          mkPiEnNixUpdate
          mkInstallNonNixCommands
          agentCoordCommandNames
          mkAgentCoordSupport
          mkAgentCoordCommand
          mkAgentCoordCommands
          mkRoleManagerPackage
          mkPiShell;
      };
    }
    // flake-utils.lib.eachDefaultSystem (system:
      let
        pkgs = import nixpkgs { inherit system; };
        piBwrap = mkPiBwrap pkgs;
        piEn = mkPiEn pkgs;
        piEnShell = mkPiEnShell pkgs;
        piEnBehavior = mkPiEnBehavior pkgs;
        pien = mkPien pkgs { };
        agentCoordCommands = mkAgentCoordCommands pkgs;
        agentCoordCommandPackages = builtins.attrValues agentCoordCommands;
        roleManagerPackage = mkRoleManagerPackage pkgs;
        # Assemble the behavior fixture from explicit paths: flake source
        # filtering can otherwise omit the adapter required by this check.
        behaviorSmokeSource = pkgs.runCommand "pi-en-behavior-smoke-source" { } ''
          mkdir -p "$out/tests/behaviors"
          cp -R ${./pi-en-behaviors} "$out/pi-en-behaviors"
          cp ${./pien} "$out/pien"
          sed -i '1c #!${pkgs.bash}/bin/bash' "$out/pien"
          chmod +x "$out/pien"
          cp -R ${./scripts} "$out/scripts"
          chmod -R u+w "$out/scripts"
          grep -rl '^#!/usr/bin/env bash$' "$out/scripts" | while read -r script; do
            sed -i '1c #!${pkgs.bash}/bin/bash' "$script"
          done
          ln -s ${./role-manager} "$out/role-manager"
          ln -s ${./pi-skill-templates} "$out/pi-skill-templates"
          cp ${./tests/behaviors/adapter.sh} "$out/tests/behaviors/adapter.sh"
          sed -i '1c #!${pkgs.bash}/bin/bash' "$out/tests/behaviors/adapter.sh"
          chmod +x "$out/tests/behaviors/adapter.sh"
        '';
        piCorePien = mkPien pkgs { includeCoordinationHelpers = false; };
        coreRuntimePaths = (mkRuntime pkgs) ++ [
          piBwrap
          piEn
          piEnShell
          piEnBehavior
          piCorePien
        ];
        piCore = pkgs.buildEnv {
          name = "pi-en-core";
          paths = coreRuntimePaths;
        };
        piCoordination = pkgs.buildEnv {
          name = "pi-en-coordination";
          paths = agentCoordCommandPackages;
        };
        piRuntime = pkgs.buildEnv {
          name = "pi-en-runtime";
          paths = coreRuntimePaths ++ agentCoordCommandPackages;
        };
        smokeCheck = name: nativeBuildInputs: script:
          pkgs.runCommand name { inherit nativeBuildInputs; } ''
            set -euo pipefail
            ${script}
            touch "$out"
          '';
      in
      {
        packages = {
          default = piEn;
          pi-en = piEn;
          pien = pien;
          pi-en-shell = piEnShell;
          pi-en-bwrap = piBwrap;
          pi-core = piCore;
          pi-runtime = piRuntime;
          pi-en-coordination = piCoordination;
          pi-role-manager = roleManagerPackage;
        } // agentCoordCommands;

        apps = {
          default = {
            type = "app";
            program = "${piEn}/bin/pi-en";
          };
          pi-en = {
            type = "app";
            program = "${piEn}/bin/pi-en";
          };
          pien = {
            type = "app";
            program = "${pien}/bin/pien";
          };
          pi-en-shell = {
            type = "app";
            program = "${piEnShell}/bin/pi-en-shell";
          };
          pi-en-bwrap = {
            type = "app";
            program = "${piBwrap}/bin/pi-en-bwrap";
          };
        };

        checks = {
          pi-core-smoke = smokeCheck "pi-en-core-smoke" [ piCore ] ''
            command -v pi-en >/dev/null
            command -v pien >/dev/null
            command -v pi-en-shell >/dev/null
            if command -v pi-start >/dev/null 2>&1; then
              echo "pi-start leaked into pi-core" >&2
              exit 1
            fi
            for legacy in pi-bwrap pi-serial-roles install-non-nix; do
              if command -v "$legacy" >/dev/null 2>&1; then
                echo "$legacy leaked into pi-core" >&2
                exit 1
              fi
            done
            command -v pi-en-bwrap >/dev/null
            pi-en --help >/dev/null
            pien help >/dev/null
            pien help run >/dev/null
            pien help raw >/dev/null
            pien help shell >/dev/null
            pien help sandbox >/dev/null
            pien sandbox --help >/dev/null
            pien completion bash >/dev/null
            pien install --help >/dev/null
            pien update --help >/dev/null
            pien uninstall --help >/dev/null
            if pien coord status --help >/dev/null 2>&1; then
              echo "pien coord leaked into pi-core" >&2
              exit 1
            fi
            pi-en-shell --help >/dev/null
            pi-en-bwrap --help >/dev/null
            if command -v pi-en-coord-status >/dev/null 2>&1; then
              echo "agent coordination helpers leaked into pi-core" >&2
              exit 1
            fi
          '';

          pi-runtime-compat-smoke = smokeCheck "pi-en-runtime-compat-smoke" [ piRuntime ] ''
            command -v pi-en >/dev/null
            command -v pien >/dev/null
            command -v pi-en-shell >/dev/null
            if command -v pi-start >/dev/null 2>&1; then
              echo "pi-start leaked into pi-runtime" >&2
              exit 1
            fi
            for legacy in pi-bwrap pi-serial-roles install-non-nix; do
              if command -v "$legacy" >/dev/null 2>&1; then
                echo "$legacy leaked into pi-runtime" >&2
                exit 1
              fi
            done
            command -v pi-en-bwrap >/dev/null
            command -v pi-en-coord-status >/dev/null
            command -v pi-en-bootstrap-coordination >/dev/null
            pi-en --help >/dev/null
            pien help >/dev/null
            pien help run >/dev/null
            pien help raw >/dev/null
            pien help shell >/dev/null
            pien help sandbox >/dev/null
            pien sandbox --help >/dev/null
            pien coord status --help >/dev/null
            pien help coord status >/dev/null
            pien coord requirements coverage --help >/dev/null
            pien help coord requirements generate >/dev/null
            pien roles serial --help >/dev/null
            pien completion bash >/dev/null
            pien install --help >/dev/null
            pien update --help >/dev/null
            pien uninstall --help >/dev/null
            pi-en-shell --help >/dev/null
            pi-en-coord-status --help >/dev/null
          '';

          pi-en-coordination-smoke = smokeCheck "pi-en-coordination-smoke" [ piCoordination ] ''
            command -v pi-en-coord-status >/dev/null
            command -v pi-en-coord-repo >/dev/null
            command -v pi-en-coord-lint >/dev/null
            command -v pi-en-bootstrap-coordination >/dev/null
            pi-en-coord-lint --help >/dev/null
            pi-en-bootstrap-coordination --help >/dev/null
          '';

          behavior-adapter-smoke = smokeCheck "pi-en-behavior-adapter-smoke" [ pien ] ''
            PI_EN_BEHAVIOR_RUNTIME_PATH="${piRuntime}/bin" \
              pien behavior --project-root ${behaviorSmokeSource} test
          '';
        };

        devShells.default = mkPiShell { inherit pkgs; };
      });
}
