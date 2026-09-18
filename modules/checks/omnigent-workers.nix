{
  config,
  inputs,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        overlays = [ config.flake.overlays.default ];
      };
      flake = config.flake // {
        inputs = inputs // {
          contentPrivate = throw "worker imported contentPrivate";
        };
        users = throw "worker imported a whole-user alias";
      };
      profileOnly = pkgs.writeShellScriptBin "worker-profile-only" "echo worker-profile";
      shadow = pkgs.writeShellScriptBin "node" "exit 99";
      mkHome =
        extra:
        inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          extraSpecialArgs = {
            inherit flake;
            osConfig = null;
          };
          modules = [
            config.flake.modules.homeManager.omnigent-worker
            {
              home.username = "omnigent-fixture";
              home.homeDirectory =
                if pkgs.stdenv.isDarwin then "/Users/omnigent-fixture" else "/home/omnigent-fixture";
              home.stateVersion = "25.11";
            }
          ]
          ++ extra;
        };
      cleanHome = mkHome [ ];
      humanACP =
        (inputs.home-manager.lib.homeManagerConfiguration {
          inherit pkgs;
          modules = [
            (import ../home/ai/omnigent/default.nix { inherit config; }).flake.modules.homeManager.ai
            {
              home = {
                inherit (cleanHome.config.home) username homeDirectory stateVersion;
              };
            }
          ];
        }).config.programs.omnigent.settings.acp;
      home = mkHome [
        {
          programs.git.settings.user = {
            name = "Worker fixture";
            email = "worker@example.invalid";
          };
          programs.jujutsu.settings.user = {
            name = "Worker fixture";
            email = "worker@example.invalid";
          };
          home.packages = [
            profileOnly
            (lib.hiPrio shadow)
          ];
        }
      ];
      cfg = home.config;
      valid = h: lib.all (a: a.assertion) h.config.assertions;
      rejected =
        message: extra:
        let
          evaluates = modules: (builtins.tryEval (mkHome modules).config.home.username).success;
          withoutGuard = {
            options.assertions = lib.mkOption {
              apply = assertions: lib.filter (a: a.message != message) assertions;
            };
          };
        in
        !evaluates extra && evaluates (extra ++ [ withoutGuard ]);
      workerPath = config.flake.lib.omnigentWorkerPath {
        inherit pkgs;
        home = cfg;
      };
      merge = config.flake.lib.omnigentMergeConfig pkgs;
      workflowFixture = pkgs.writeShellScript "worker-workflow-fixture" ''
        set -euo pipefail
        export HOME="$TMPDIR/workflow-home"
        export XDG_CONFIG_HOME="$HOME/.config" XDG_DATA_HOME="$HOME/.local/share"
        export OPENSPEC_TELEMETRY=0
        mkdir -p "$XDG_CONFIG_HOME" "$XDG_DATA_HOME" "$HOME/work"
        ${lib.concatMapStringsSep "\n"
          (file: ''
            target="$HOME"/${lib.escapeShellArg (lib.removePrefix "${cfg.home.homeDirectory}/" file.target)}
            mkdir -p "$(dirname "$target")"
            ln -s ${lib.escapeShellArg (toString file.source)} "$target"
          '')
          (
            lib.filter (
              file:
              file.enable
              && lib.elem (lib.removePrefix "${cfg.home.homeDirectory}/" file.target) [
                ".config/git/config"
                ".config/jj/config.toml"
                ".config/openspec/config.json"
                ".local/share/openspec/schemas/superpowers-bridge"
                ".local/share/openspec/schemas/superpowers-bridge-wrspm"
              ]
            ) (lib.attrValues cfg.home.file)
          )
        }
        cd "$HOME/work"
        for executable in ghq ghq-sync dependency-sources zoxide just shellcheck uncomment ratchet jc jaq yq nixfmt nil nixd openspec mergify nvim git-xet; do
          test -x "$(command -v "$executable")"
        done
        test "$(git config get core.editor)" = nvim
        test "$(jj config get ui.editor)" = nvim
        timeout 15 "$(git var GIT_EDITOR)" --headless '+call writefile(["editor-ok"], "editor-result")' +qa
        test "$(cat editor-result)" = editor-ok
        "$(git config get lfs.customtransfer.xet.path)" --version
        git init -q repository
        cd repository
        printf 'fixture\n' > tracked
        git add tracked
        git commit -qm 'Local fixture'
        test "$(git show HEAD:tracked)" = fixture
        jj git init --colocate
        jj describe -m 'Local jj fixture'
        jj log --no-graph -r @ -T description | grep 'Local jj fixture'
        cd ..
        mkdir -p "$HOME/ghq/example.test/fixture"
        mv repository "$HOME/ghq/example.test/fixture/repository"
        test "$(ghq root)" = "$HOME/ghq"
        test "$(ghq list)" = example.test/fixture/repository
        zoxide add "$HOME/ghq/example.test/fixture/repository"
        test "$(zoxide query repository)" = "$HOME/ghq/example.test/fixture/repository"
        openspec schemas --json > schemas.json
        jaq -e 'map(.name) | index("superpowers-bridge") != null and index("superpowers-bridge-wrspm") != null' schemas.json
        jaq -e '.profile == "custom" and .delivery == "skills" and (.workflows | length == 12)' "$XDG_CONFIG_HOME/openspec/config.json"
        printf 'check:\n    printf "fixture-ok" > result\n' > justfile
        just --shell ${pkgs.bash}/bin/bash check
        test "$(cat result)" = fixture-ok
        printf '#!/usr/bin/env bash\nprintf "fixture\\n"\n' > good.sh
        shellcheck good.sh
        printf '#!/usr/bin/env bash\necho $undefined\n' > bad.sh
        if shellcheck bad.sh > diagnostic; then exit 1; fi
        grep SC2154 diagnostic
        printf 'answer: 42\n' | yq '.answer' | jaq -e '. == 42'
        printf 'answer=42\n' | jc --ini | jaq -e '.answer == "42"'
      '';
      atomicActivation = pkgs.writeText "worker-atomic-activation" cfg.home.activation.atomicMergeSettings.data;
      atomicMergeTest = pkgs.writeText "worker-atomic-merge-test.py" ''
        import json
        import pathlib
        import shlex
        import stat
        import subprocess
        import sys

        dry_run, executable, declaration, destination = shlex.split(pathlib.Path(sys.argv[1]).read_text())
        assert dry_run == "$DRY_RUN_CMD"
        assert destination == sys.argv[2]
        declared = json.loads(pathlib.Path(declaration).read_text())
        target = pathlib.Path("atomic-state/settings.json")
        target.parent.mkdir()
        unknown = {"workerFixture": {"nested": "retained"}}
        assert not unknown.keys() & declared.keys()
        target.write_text(json.dumps(unknown | {"theme": "old"}))

        def merge():
            return subprocess.run([executable, declaration, str(target)], check=False)

        assert merge().returncode == 0
        assert json.loads(target.read_text()) == unknown | declared
        assert stat.S_IMODE(target.stat().st_mode) == 0o644
        first = target.read_bytes()
        assert merge().returncode == 0
        assert target.read_bytes() == first
        for invalid in ['{"unfinished":', '[]', 'null', '"scalar"']:
            target.write_text(invalid)
            before = target.read_bytes()
            assert merge().returncode != 0, "accepted invalid Atomic settings"
            assert target.read_bytes() == before, "modified invalid Atomic settings"
      '';
      cliHome = inputs.home-manager.lib.homeManagerConfiguration {
        inherit pkgs;
        modules = [
          config.flake.modules.homeManager.cli-tools
          {
            home = {
              inherit (cfg.home) username homeDirectory;
              stateVersion = "25.11";
            };
          }
        ];
      };
      cliSystem =
        if pkgs.stdenv.isDarwin then
          (mkDarwin [ config.flake.modules.darwin.cli-tools ]).config
        else
          (mkLinux [ config.flake.modules.nixos.cli-tools ]).config;
      cliProviders =
        packages:
        lib.all (p: lib.elem p packages) (
          config.flake.lib.cliUnixPackages pkgs
          ++ config.flake.lib.cliArchivePackages pkgs
          ++ config.flake.lib.cliNetworkPackages pkgs
          ++ [ pkgs.jq ]
        );
      wrappedHome =
        (mkHome [
          {
            _module.args.omnigentCredentialPolicy = {
              signingKey = null;
              githubTokens.fixture = {
                path = "/synthetic-github-token";
                expectedLogin = "fixture";
              };
              claudeSetupToken = "/synthetic-claude-token";
              linearApiKeys = { };
            };
          }
        ]).config;
      wrappedPath = config.flake.lib.omnigentWorkerPath {
        inherit pkgs;
        home = wrappedHome;
      };
      cases = {
        composition = valid home;
        workerACPApproval =
          cfg.programs.omnigent.settings.acp == {
            agents = [
              (builtins.head humanACP.agents)
              ((builtins.elemAt humanACP.agents 1) // { command = "omp acp --approval-mode yolo"; })
            ];
          }
          && humanACP == config.flake.lib.omnigentACP
          && (builtins.elemAt humanACP.agents 1).command == "omp acp"
          && (builtins.elemAt humanACP.agents 1).env_passthrough == [ ];
        cliHomeAdapter = cliHome.config.programs.jq.enable && cliProviders cliHome.config.home.packages;
        cliSystemAdapter = cliProviders cliSystem.environment.systemPackages;
        credentialWrapperPrecedence =
          lib.elem "${wrappedHome.programs.gh.package}/bin" (lib.splitString ":" wrappedPath)
          && !lib.elem "${pkgs.gh}/bin" (lib.splitString ":" wrappedPath)
          && lib.hasPrefix "${wrappedHome.programs.claude-code.package}/bin:" wrappedPath;
        tools = cfg.programs.ripgrep.enable && cfg.programs.fd.enable && cfg.programs.gh.enable;
        workflowCapabilities =
          (cfg.programs.openspec.enable or false)
          && (cfg.programs.mergify.enable or false)
          && lib.all (p: lib.elem p cfg.home.packages) [
            pkgs.ghq
            pkgs.ghq-sync
            pkgs.dependency-sources
            pkgs.just
            pkgs.shellcheck
            pkgs.nixfmt
          ];
        configuredDependencies =
          cfg.programs.neovim.enable
          && cfg.programs.git.settings.core.editor == "nvim"
          && cfg.programs.jujutsu.settings.ui.editor == "nvim"
          && lib.elem pkgs.git-xet cfg.home.packages;
        plainEditor =
          cfg.programs.neovim.plugins == [ ]
          && cfg.programs.neovim.extraConfig == ""
          && !(cfg.programs.lazyvim.enable or false);
        xetOwnedByTransfer =
          !lib.elem pkgs.git-xet
            (mkHome [ { programs.git.lfs.enable = lib.mkForce false; } ]).config.home.packages
          && !lib.elem pkgs.git-xet
            (mkHome [
              { programs.git.settings."lfs \"customtransfer.xet\"".path = lib.mkForce "another-transfer"; }
            ]).config.home.packages;
        duplicateCapabilities =
          let
            composed =
              (mkHome (
                map (name: config.flake.modules.homeManager.${name}) [
                  "repository-acquisition"
                  "engineering-tools"
                  "nix-development"
                  "openspec"
                  "mergify"
                  "neovim"
                ]
              )).config;
          in
          lib.all (package: builtins.length (lib.filter (p: p == package) composed.home.packages) == 1) [
            pkgs.ghq
            pkgs.just
            pkgs.nixfmt
            composed.programs.openspec.package
            composed.programs.mergify.package
            composed.programs.neovim.finalPackage
          ];
        harnesses =
          cfg.programs.atomic.enable
          && cfg.programs.omp.enable
          && cfg.programs.pi-coding-agent.enable
          && cfg.programs.claude-code.enable;
        linear = lib.elem pkgs.linear-cli cfg.home.packages;
        skills = cfg.home.file."${cfg.home.homeDirectory}/.claude/skills/linear-cli".enable;
        githubHelper = cfg.programs.gh.gitCredentialHelper.enable;
        privateSecrets =
          rejected "Omnigent worker capabilities must not import personal sops secrets or templates."
            [
              inputs.sops-nix.homeManagerModules.sops
              {
                sops.age.keyFile = "${cfg.home.homeDirectory}/fixture-age";
                sops.secrets.personal.sopsFile = pkgs.writeText "fixture-secret.yaml" "personal: fixture";
              }
            ];
        signer = rejected "Omnigent worker capabilities do not grant Git or Jujutsu signing authority." [
          {
            programs.git.signing = {
              key = "${cfg.home.homeDirectory}/signing-key";
              signByDefault = true;
            };
          }
        ];
        effectiveSigner =
          rejected "Omnigent worker capabilities do not grant Git or Jujutsu signing authority."
            [
              {
                programs.git.settings = {
                  user.signingKey = "${cfg.home.homeDirectory}/private-signing-key";
                  commit.gpgSign = true;
                };
              }
            ];
        effectiveTagSigner =
          rejected "Omnigent worker capabilities do not grant Git or Jujutsu signing authority."
            [
              { programs.git.settings.tag.gpgSign = "yes"; }
            ];
        signingFragments =
          rejected "Omnigent worker capabilities do not grant Git or Jujutsu signing authority."
            [
              {
                programs.git.settings = lib.mkForce [
                  { user.name = "Worker fixture"; }
                  {
                    COMMIT.GPGSIGN = [
                      false
                      1
                    ];
                  }
                ];
              }
            ];
        unsignedAuthor = valid (mkHome [
          {
            programs.git.settings = {
              user.name = "Worker fixture";
              user.email = "worker@example.invalid";
              commit.gpgSign = false;
              tag.gpgSign = "off";
            };
          }
        ]);
        socket = rejected "Omnigent worker capabilities must not inherit an SSH agent or signing socket." [
          { home.sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/agent"; }
        ];
        foreignHome =
          rejected "Omnigent worker configuration must use its own home, not a foreign human home."
            [ { home.file.foreign.source = "/home/human/private"; } ];
        foreignConfig =
          rejected "Omnigent worker configuration must use its own home, not a foreign human home."
            [ { programs.atomic.configDir = "/Users/human/.atomic/agent"; } ];
        foreignSettings =
          rejected "Omnigent worker configuration must use its own home, not a foreign human home."
            [ { programs.atomic.settings.packages = lib.mkForce [ "/home/human/extensions" ]; } ];
        foreignActivation =
          rejected "Omnigent worker configuration must use its own home, not a foreign human home."
            [
              ({ lib, ... }: {
                home.activation.foreignInput = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                  cat /home/human/config
                '';
              })
            ];
        benignDocumentation = valid (mkHome [
          {
            home.file."example.md".text =
              "Documentation example: /home/human/project is an example path, not an input.";
          }
        ]);
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
      mkLinux =
        extra:
        inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.home-manager.nixosModules.home-manager
            config.flake.modules.nixos.omnigent-host
            {
              nixpkgs.pkgs = pkgs;
              boot.isContainer = true;
              system.stateVersion = "25.11";
              networking.hostName = "fixture";
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs = { inherit flake; };
              };
              users.users = lib.genAttrs [ "omnigent-cameron" "omnigent-raquel" ] (user: {
                isNormalUser = true;
                home = "/home/${user}";
                group = user;
              });
              users.groups.omnigent-cameron = { };
              users.groups.omnigent-raquel = { };
              services.omnigent-host = {
                serverUrl = "https://fixture.invalid";
                workers = lib.genAttrs [ "cameron" "raquel" ] (owner: {
                  inherit owner;
                  user = "omnigent-${owner}";
                  extraHomeModules = [
                    {
                      home.packages = [
                        profileOnly
                        (lib.hiPrio shadow)
                      ];
                    }
                  ];
                  extraPackages = [
                    pkgs.hello
                    shadow
                  ];
                });
              };
            }
          ]
          ++ extra;
        };
      prepared = (mkLinux [ ]).config;
      activeModule.services.omnigent-host.workers = lib.genAttrs [ "cameron" "raquel" ] (_: {
        enable = true;
      });
      linux = (mkLinux [ activeModule ]).config;
      linuxFailures = c: map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);
      compositeInvalid = [
        {
          users.users.omnigent-cameron.homeMode = "0755";
          users.users.omnigent-cameron.extraGroups = [ "wheel" ];
          nix.settings.trusted-users = [ "omnigent-cameron" ];
          services.omnigent-host.workers.cameron.environment.NIX_CONFIG = "foreign";
        }
      ];
      compositeMessages = [
        "Omnigent worker cameron: requires a private distinct home and home-local workspace."
        "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
        "Omnigent worker cameron: Nix trusted-user authority is prohibited."
        "Omnigent worker cameron: environment cannot override identity, state or authority selectors."
      ];
      linuxCases = {
        valid = linuxFailures linux == [ ];
        compositeInvalid =
          lib.sort builtins.lessThan (linuxFailures (mkLinux compositeInvalid).config)
          == lib.sort builtins.lessThan compositeMessages;
        disabledPrepared =
          !(prepared.systemd.services ? omnigent-host-cameron)
          && !(prepared.systemd.services ? omnigent-host-raquel)
          && prepared.home-manager.users.omnigent-cameron.programs.omnigent.enable
          && builtins.hasAttr "home-manager-omnigent\\x2dcameron" prepared.systemd.services;
        noLegacyFallback = !(linux.systemd.services ? omnigent-host);
        direnvOptIn =
          prepared.home-manager.users.omnigent-cameron.programs.direnv.config.whitelist.prefix or [ ] == [ ];
      }
      // lib.mapAttrs' (
        owner: worker:
        let
          unit = linux.systemd.services."omnigent-host-${owner}";
          service = unit.serviceConfig;
          h = linux.home-manager.users.${worker.user};
          activation = "home-manager-omnigent\\x2d${owner}.service";
        in
        lib.nameValuePair "instance-${owner}" (
          service.User == "omnigent-${owner}"
          && service.Group == "omnigent-${owner}"
          && service.WorkingDirectory == "/home/omnigent-${owner}"
          && service.UMask == "0077"
          && service.NoNewPrivileges
          && linux.users.users.${worker.user}.homeMode == "700"
          && service.Type == "simple"
          && service.ExecStart == "${lib.getExe pkgs.omnigent} host --server https://fixture.invalid"
          && service.Restart == "on-failure"
          && service.RestartSec == 5
          && service.MemoryHigh == "6G"
          && service.MemoryMax == "8G"
          && lib.elem activation unit.after
          && unit.requires == [ activation ]
          && unit.wants == [ "network-online.target" ]
          && lib.elem "network-online.target" unit.after
          && unit.bindsTo == [ ]
          && unit.conflicts == [ ]
          && lib.elem h.home.activationPackage unit.restartTriggers
          && unit.environment.HOME == "/home/omnigent-${owner}"
          && unit.environment.USER == worker.user
          && unit.environment.LOGNAME == worker.user
          && unit.environment.PI_CODING_AGENT_DIR == "/home/omnigent-${owner}/.atomic/agent"
          && unit.environment.PI_ACP_PI_COMMAND == "atomic"
          && unit.environment.OMNIGENT_RUNNER_ENV_PASSTHROUGH == "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR"
          && h.programs.omp.configDir == "/home/omnigent-${owner}/.omp/agent"
          && (builtins.elemAt h.programs.omnigent.settings.acp.agents 1).env_passthrough == [ ]
          && h.programs.omnigent.settings.host.name == "fixture-${owner}"
          &&
            unit.environment.PATH == lib.makeBinPath (
              config.flake.lib.omnigentRuntimePackages pkgs
              ++ [ h.home.path ]
              ++ [
                pkgs.hello
                shadow
              ]
            )
        )
      ) linux.services.omnigent-host.workers;
      linuxFailed =
        if linuxFailures linux != [ ] then
          [ "valid" ]
        else
          lib.attrNames (lib.filterAttrs (_: ok: !ok) linuxCases);
      homeUidFixture = pkgs.writeShellScript "omnigent-home-uid-fixture" ''
        # Override only UID observation; source the emitted helper with real stat/mode checks, without chown.
        observedUid="$2"
        ${pkgs.coreutils}/bin/id() { printf '%s\n' "$observedUid"; }
        source "$1"
      '';
      sandboxSelectionTest = pkgs.writeText "omnigent-worker-sandbox-selection.py" ''
        import json
        import os
        from pathlib import Path
        import tempfile
        import yaml
        from omnigent.cli import _materialize_harness_launcher_file
        from omnigent.onboarding.acp_auth import acp_agents
        from omnigent.harnesses.pi_native.main import _materialize_pi_agent_spec

        settings = json.loads(Path("${pkgs.writeText "linux-worker-settings.json" (builtins.toJSON linux.home-manager.users.omnigent-cameron.programs.omnigent.settings)}").read_text())
        os.environ["HOME"] = tempfile.mkdtemp()
        entries = acp_agents(settings)
        assert [entry.name for entry in entries] == ["Atomic", "Oh My Pi"]
        assert entries[0].env_passthrough == ("PI_ACP_PI_COMMAND", "PI_CODING_AGENT_DIR")
        assert entries[1].env_passthrough == ()
        for entry in entries:
            generated = _materialize_harness_launcher_file(
                harness="acp", model=None, system_prompt=None, acp_agent=entry
            )
            spec = yaml.safe_load(generated.read_text())
            assert spec["os_env"] == {"type": "caller_process", "sandbox": {"type": "none"}}
            assert spec["executor"]["acp_agent"]["command"] == entry.command
            assert spec["executor"]["acp_agent"].get("env_passthrough", []) == list(entry.env_passthrough)
        with tempfile.TemporaryDirectory() as directory:
            spec = yaml.safe_load(_materialize_pi_agent_spec(Path(directory)).read_text())
            assert spec["os_env"] == {"type": "caller_process", "cwd": ".", "sandbox": {"type": "none"}}
        print("upstream native Pi and configured ACP select sandbox:none; no child path grants")
      '';
      mkDarwin =
        extra:
        inputs.nix-darwin.lib.darwinSystem {
          modules = [
            inputs.home-manager.darwinModules.home-manager
            config.flake.modules.darwin.omnigent-host
            {
              nixpkgs.pkgs = pkgs;
              system.stateVersion = 6;
              networking.hostName = "fixture";
              users.knownUsers = [ "omnigent-cameron" ];
              users.knownGroups = [ "omnigent-cameron" ];
              users.groups.omnigent-cameron.gid = 22001;
              users.users.omnigent-cameron = {
                uid = 22001;
                gid = 22001;
                home = "/Users/omnigent-cameron";
                createHome = true;
              };
              services.omnigent-host = {
                serverUrl = "https://fixture.invalid";
                workers.cameron = {
                  enable = true;
                  owner = "cameron";
                  user = "omnigent-cameron";
                  extraHomeModules = [
                    {
                      home.packages = [
                        profileOnly
                        (lib.hiPrio shadow)
                      ];
                    }
                  ];
                  extraPackages = [
                    pkgs.hello
                    shadow
                  ];
                };
              };
            }
          ]
          ++ extra;
        };
      darwin = (mkDarwin [ ]).config;
      darwinPrepared =
        (mkDarwin [ { services.omnigent-host.workers.cameron.enable = lib.mkForce false; } ]).config;
      darwinFailures = c: map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);
      darwinCases = {
        valid = darwinFailures darwin == [ ];
        disabledPrepared =
          !(darwinPrepared.launchd.daemons ? omnigent-host-cameron)
          && darwinPrepared.environment.etc ? "omnigent/workers/cameron"
          && darwinPrepared.home-manager.users == { };
        noLegacyFallback = darwin.home-manager.users == { };
      };
      darwinHostCanary = pkgs.writeShellScriptBin "omnigent" ''
        set -eu
        test "$*" = 'host --server https://fixture.invalid'
        test -e "$HOME/activation-succeeded"
        test "$(worker-profile-only)" = worker-profile
        test "$(command -v node)" = ${pkgs.nodejs_22}/bin/node
        test "$(command -v hello)" = ${pkgs.hello}/bin/hello
        test "$(umask)" = 0077
        test -z "''${SSH_AUTH_SOCK-}"
        printf '%s\n' host-executed > "$HOME/host-executed"
      '';
      darwinControl = (mkDarwin [ { services.omnigent-host.package = darwinHostCanary; } ]).config;
      darwinArtifactTest = pkgs.writeText "omnigent-darwin-artifacts.py" ''
        import json
        import os
        from pathlib import Path
        import plistlib
        import re
        import shlex
        import shutil
        import subprocess
        import sys
        import tempfile
        import yaml
        from omnigent.cli import _materialize_harness_launcher_file
        from omnigent.onboarding.acp_auth import acp_agents
        from omnigent.harnesses.pi_native.main import _materialize_pi_agent_spec

        label = "org.nixos.omnigent-host-cameron"
        worker_home = "/Users/omnigent-cameron"
        required = ["atomic", "omp", "pi", "claude", "codex", "nix", "direnv", "gh", "linear", "rg", "fd"]

        def inspect(root):
            root = Path(root)
            plist = root / "Library/LaunchDaemons" / (label + ".plist")
            assert plist.is_file(), "wrong domain"
            assert not (root / "Library/LaunchAgents" / plist.name).exists(), "duplicate agent"
            p = plistlib.loads(plist.read_bytes())
            assert p["Label"] == label
            assert p["UserName"] == "omnigent-cameron", "wrong user"
            assert p["WorkingDirectory"] == worker_home
            assert p["Umask"] == 63
            assert "SessionCreate" not in p
            assert p["ProcessType"] == "Standard"
            assert p["RunAtLoad"] and p["KeepAlive"] == {"SuccessfulExit": False}
            assert p["ThrottleInterval"] == 5
            assert not any(k in p for k in ["LimitLoadToSessionType", "LaunchOnlyOnce", "KeepAlivePathState"])
            assert p["StandardOutPath"] == p["StandardErrorPath"] == worker_home + "/.omnigent/logs/host/service.log"
            env = p["EnvironmentVariables"]
            assert env["HOME"] == worker_home
            assert env["USER"] == env["LOGNAME"] == "omnigent-cameron"
            assert env["PI_ACP_PI_COMMAND"] == "atomic"
            assert env["PI_CODING_AGENT_DIR"] == worker_home + "/.atomic/agent"
            assert env["OMNIGENT_RUNNER_ENV_PASSTHROUGH"] == "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR"
            assert "OMP_CODING_AGENT_DIR" not in env and "ATOMIC_CODING_AGENT_DIR" not in env
            argv = p["ProgramArguments"]
            assert argv[:2] == ["/bin/sh", "-c"]
            wait, store, conjunction, execute, launcher = shlex.split(argv[2])
            assert [wait, store, conjunction, execute] == ["/bin/wait4path", "/nix/store", "&&", "exec"]
            assert os.access(launcher, os.X_OK)
            script = Path(launcher).read_text()
            activations = re.findall(r"^(/nix/store/[^\n ]+/activate)$", script, re.M)
            assert len(activations) == 1
            activation = Path(activations[0])
            assert os.access(activation, os.X_OK)
            generation = activation.parent
            profile = (generation / "home-path").resolve(strict=True)
            assert shutil.which("node", path=env["PATH"]) == "${pkgs.nodejs_22}/bin/node", "missing runtime"
            assert str(profile / "bin") in env["PATH"].split(":"), "missing profile"
            assert env["PATH"].split(":").index("${pkgs.nodejs_22}/bin") < env["PATH"].split(":").index(str(profile / "bin"))
            assert shutil.which("hello", path=env["PATH"]) == "${pkgs.hello}/bin/hello"
            assert env["PATH"].endswith(":/usr/bin:/bin:/usr/sbin:/sbin")
            assert subprocess.check_output([str(profile / "bin/worker-profile-only")], text=True).strip() == "worker-profile"
            for exe in required:
                resolved = shutil.which(exe, path=env["PATH"])
                assert resolved and os.access(resolved, os.X_OK), exe
            assert list((generation / "LaunchAgents").iterdir()) == []
            actual_activation = activation.read_text()
            assert "launchctl" not in actual_activation and "sw_vers" not in actual_activation
            assert "checkStringEq UID" in actual_activation and "22001" in actual_activation
            merge_lines = [line for line in actual_activation.splitlines() if line.startswith("run ") and line.endswith("/.omnigent/config.yaml")]
            assert len(merge_lines) == 1
            run, merger, declaration, destination = shlex.split(merge_lines[0])
            assert destination == worker_home + "/.omnigent/config.yaml"
            return p, launcher, str(activation), merger, declaration

        production = inspect(sys.argv[1])
        for reason in ["wrong user", "wrong domain", "missing runtime", "missing profile"]:
            with tempfile.TemporaryDirectory() as directory:
                root = Path(directory)
                relative = Path("Library/LaunchDaemons") / (label + ".plist")
                plist = root / relative
                plist.parent.mkdir(parents=True)
                p = plistlib.loads((Path(sys.argv[1]) / relative).read_bytes())
                if reason == "wrong user":
                    p["UserName"] = "root"
                elif reason == "wrong domain":
                    plist = root / "Library/LaunchAgents" / plist.name
                    plist.parent.mkdir()
                elif reason == "missing runtime":
                    p["EnvironmentVariables"]["PATH"] = "/usr/bin:/bin"
                else:
                    p["EnvironmentVariables"]["PATH"] = "${lib.makeBinPath (config.flake.lib.omnigentRuntimePackages pkgs)}:/usr/bin:/bin:/usr/sbin:/sbin"
                plist.write_bytes(plistlib.dumps(p))
                try:
                    inspect(root)
                except AssertionError as error:
                    assert str(error) == reason, (reason, str(error))
                else:
                    raise AssertionError("accepted " + reason)
        control = inspect(sys.argv[2])
        _, _, activation, merger, declaration = production
        assert str(Path(activation).parent) == sys.argv[4], "enrollment generation differs from launched generation"
        settings = yaml.safe_load(Path(declaration).read_text())
        assert settings["host"]["name"] == "fixture-cameron"
        target = Path("worker-config.yaml")
        target.write_text("host:\n  host_id: retained-worker-id\nunknown: retained\n")
        subprocess.run([merger, declaration, str(target)], check=True)
        assert yaml.safe_load(target.read_text()) == settings | {"host": settings["host"] | {"host_id": "retained-worker-id"}, "unknown": "retained"}
        assert target.stat().st_mode & 0o777 == 0o600
        os.environ["HOME"] = tempfile.mkdtemp()
        entries = acp_agents(settings)
        assert [entry.name for entry in entries] == ["Atomic", "Oh My Pi"]
        assert entries[0].env_passthrough == ("PI_ACP_PI_COMMAND", "PI_CODING_AGENT_DIR")
        assert entries[1].env_passthrough == ()
        for entry in entries:
            generated = _materialize_harness_launcher_file(harness="acp", model=None, system_prompt=None, acp_agent=entry)
            spec = yaml.safe_load(generated.read_text())
            assert spec["os_env"] == {"type": "caller_process", "sandbox": {"type": "none"}}
            assert spec["executor"]["acp_agent"]["command"] == entry.command
            assert spec["executor"]["acp_agent"].get("env_passthrough", []) == list(entry.env_passthrough)
        with tempfile.TemporaryDirectory() as directory:
            spec = yaml.safe_load(_materialize_pi_agent_spec(Path(directory)).read_text())
            assert spec["os_env"] == {"type": "caller_process", "cwd": ".", "sandbox": {"type": "none"}}

        system_activation = Path(sys.argv[3]).read_text()
        preparation_lines = [line for line in system_activation.splitlines() if "-omnigent-prepare-darwin-home " in line]
        assert len(preparation_lines) == 1
        invocation = shlex.split(preparation_lines[0])
        assert invocation[:5] == ["/usr/bin/sudo", "-u", "omnigent-cameron", "--set-home", "--"], "preparation must run as the worker"
        prepare, user, uid, gid, home = invocation[5:]
        assert [user, uid, gid, home] == ["omnigent-cameron", "22001", "22001", worker_home]
        assert system_activation.index("setting up users") < system_activation.index(preparation_lines[0])
        assert system_activation.index(preparation_lines[0]) < system_activation.index("setting up launchd services")
        preparation_home = Path.cwd() / "prepared-home"
        actual_user = subprocess.check_output(["${pkgs.coreutils}/bin/id", "-un"], text=True).strip()
        def prepare_home(uid=os.getuid()):
            return subprocess.run([prepare, actual_user, str(uid), str(os.getgid()), str(preparation_home)], check=False)
        assert prepare_home().returncode == 0
        for suffix in ["", ".omnigent", ".omnigent/logs", ".omnigent/logs/host"]:
            directory = preparation_home / suffix
            assert directory.stat().st_mode & 0o777 == 0o700
            assert directory.stat().st_uid == os.getuid()
        assert prepare_home().returncode == 0
        assert prepare_home(os.getuid() + 1).returncode != 0
        logs = preparation_home / ".omnigent/logs/host"
        logs.rmdir()
        logs.symlink_to(preparation_home, target_is_directory=True)
        assert prepare_home().returncode != 0, "symlink log parent accepted"
        print("Darwin realized plist/activation/profile, private preparation, and sandbox:none checked")
        Path("artifacts.json").write_text(json.dumps({"production": production, "control": control}))
      '';
      darwinLauncherTest = pkgs.writeText "omnigent-darwin-launcher-test.py" ''
        import json
        import os
        from pathlib import Path
        import shlex
        import subprocess

        artifacts = json.loads(Path("artifacts.json").read_text())
        plist, launcher, activation, _, _ = artifacts["control"]
        env = os.environ | plist["EnvironmentVariables"]
        home = Path(os.environ["TMPDIR"]) / "worker-control"
        home.mkdir(mode=0o700)
        for suffix in [".omnigent", ".omnigent/logs", ".omnigent/logs/host"]:
            (home / suffix).mkdir(mode=0o700)
        env["HOME"] = str(home)
        env["SSH_AUTH_SOCK"] = "/fixture/no-signer"
        # Intercept account lookup and HM's effectful activation only; the emitted launcher,
        # filesystem checks, PATH, and foreground exec run unchanged without enrolling a user.
        def run(activation_status, selected_uid=os.getuid(), source=launcher):
            script = f"""
        ${pkgs.coreutils}/bin/id() {{
          if test "$*" = '-u omnigent-cameron'; then printf '%s\\n' {selected_uid};
          else command ${pkgs.coreutils}/bin/id "$@"; fi
        }}
        {activation}() {{
          test {activation_status} = 0 || return {activation_status}
          command ${pkgs.coreutils}/bin/touch "$HOME/activation-succeeded"
        }}
        source {shlex.quote(source)}
        """
            return subprocess.run(["${pkgs.bash}/bin/bash", "-c", script], env=env, check=False)

        assert run(0).returncode == 0
        assert (home / "host-executed").read_text() == "host-executed\n"
        (home / "host-executed").unlink()
        # Keep the previous success marker: stale activation must not mask a later failure.
        assert run(42).returncode == 42
        assert not (home / "host-executed").exists(), "host executed after failed activation"
        assert run(0, os.getuid() + 1).returncode != 0
        assert not (home / "host-executed").exists(), "wrong UID lookup accepted"
        home.chmod(0o755)
        assert run(0).returncode != 0
        assert not (home / "host-executed").exists(), "public home accepted"
        home.chmod(0o700)
        logs = home / ".omnigent/logs/host"
        logs.chmod(0o755)
        assert run(0).returncode != 0
        assert not (home / "host-executed").exists(), "public log parent accepted"
        logs.chmod(0o700)
        linked = home.parent / "linked-worker"
        linked.symlink_to(home, target_is_directory=True)
        env["HOME"] = str(linked)
        assert run(0).returncode != 0
        assert not (home / "host-executed").exists(), "symlink home accepted"
        env["HOME"] = str(home)
        mutant = home.parent / "unchecked-activation"
        original = Path(launcher).read_text()
        assert original.count(activation + "\n") == 1
        mutant.write_text(original.replace(activation + "\n", activation + " || true\n"))
        assert run(42, source=str(mutant)).returncode == 0
        assert (home / "host-executed").exists(), "activation-failure mutant did not discriminate"
      '';
      inventoryRoles = config.flake.clan.inventory.instances.omnigent.roles;
      stibnite = config.flake.darwinConfigurations.stibnite;
      expectedOwners = config.flake.lib.omnigentFleetObligations.expectedOwners;
      clanHostInterface =
        (
          (import ../clan/services/omnigent/flake-module.nix {
            inherit config;
          }).clan.modules.omnigent
          { inherit lib; }
        ).roles.host.interface;
      clanSettings =
        machine:
        (lib.evalModules {
          modules = [
            clanHostInterface
            inventoryRoles.host.machines.${machine}.settings
          ];
        }).config;
      janetteMeta = config.flake.users.janettesmith.meta;
      metaFixture =
        extra:
        (lib.evalModules {
          modules = [
            ../home/users/lib.nix
            {
              options.systems = lib.mkOption { type = lib.types.listOf lib.types.str; };
              options.flake.lib = lib.mkOption { type = lib.types.attrs; };
              config.systems = [ system ];
              config.flake.users.fixture.meta = {
                username = "fixture";
                fullname = "Fixture";
                email = "primary@example.invalid";
              }
              // extra;
            }
          ];
        }).config.flake.users.fixture.meta.gitEmail;
      inventoryCases = {
        canonicalJanette =
          janetteMeta.username == "janettesmith"
          && janetteMeta.fullname == "Janette Smith"
          && janetteMeta.email == "janette.a.smith@gmail.com"
          && janetteMeta.githubUser == "janetteasmith"
          && janetteMeta.gitEmail == "125711642+janetteasmith@users.noreply.github.com"
          && janetteMeta.sopsAgeKeyId == null
          &&
            janetteMeta.sshKeys == [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
            ];
        publicRecipient = lib.hasInfix "&janettesmith-user age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec" (
          builtins.readFile ../../.sops.yaml
        );
        gitEmailDefault = metaFixture { } == "primary@example.invalid";
        gitEmailOverride = metaFixture { gitEmail = "author@example.invalid"; } == "author@example.invalid";
        gitEmailType =
          !(builtins.tryEval (metaFixture {
            gitEmail = 42;
          })).success;
        hostMatrix =
          lib.attrNames inventoryRoles.host.machines == [
            "magnetite"
            "pyrite"
            "stibnite"
          ];
        serverMatrix = lib.attrNames inventoryRoles.server.machines == [ "magnetite" ];
        serializable = lib.all (
          machine:
          let
            settings = clanSettings machine;
          in
          builtins.fromJSON (builtins.toJSON settings) == settings
          && lib.attrNames settings.workers == expectedOwners.${machine}
        ) (lib.attrNames expectedOwners);
        nixOnlyModules =
          !(builtins.tryEval (
            builtins.deepSeq
              (lib.evalModules {
                modules = [
                  clanHostInterface
                  {
                    workers.cameron = {
                      owner = "cameron";
                      user = "omnigent-cameron";
                      extraHomeModules = [ { } ];
                    };
                  }
                ];
              }).config
              true
          )).success;
      };
      inventoryFailed = lib.attrNames (lib.filterAttrs (_: ok: !ok) inventoryCases);
      credentialRoot = "/tmp/omnigent-worker-credentials-${system}";
      credentialHomePath = "${credentialRoot}/home";
      credentialMock =
        tool:
        pkgs.writeShellScriptBin tool ''
          exec ${lib.getExe pkgs.python3} ${../home/ai/omnigent/credential-fixtures.py} mock-${tool} "$@"
        '';
      mockGh = credentialMock "gh";
      linearResolver = pkgs.runCommand "omnigent-linear-resolver-fixture" { } ''
        mkdir -p "$out"
        cp -r ${pkgs.linear-cli.src}/. "$out/"
        cp -r ${pkgs.linear-cli.denoDeps}/vendor "$out/vendor"
        cp ${pkgs.writeText "linear-resolver-fixture.ts" ''
          import { setCliWorkspace } from "./src/config.ts";
          import { loadCredentials } from "./src/credentials.ts";
          import { getGraphQLClient } from "./src/utils/graphql.ts";
          import { _setBackend } from "./src/keyring/index.ts";
          if (Deno.args[0] === "--prepare") Deno.exit(0);

          _setBackend({
            get: async () => { throw new Error("keyring forbidden in fixture"); },
            set: async () => { throw new Error("keyring forbidden in fixture"); },
            delete: async () => { throw new Error("keyring forbidden in fixture"); },
            isAvailable: async () => false,
          });
          globalThis.fetch = async (input, init) => {
            const request = new Request(input, init);
            const expected = (await Deno.readTextFile(Deno.env.get("FIXTURE_LINEAR_GRANT_PATH")!)).trim();
            if (request.headers.get("Authorization") !== expected) {
              throw new Error("unexpected synthetic grant");
            }
            const data = {
              viewer: { email: Deno.env.get("FIXTURE_LINEAR_VIEWER") ?? "fixture@example.invalid" },
              organization: {
                id: Deno.env.get("FIXTURE_LINEAR_WORKSPACE") ?? "workspace-id",
                urlKey: "fixture",
              },
            };
            return Response.json({ data });
          };
          try {
            if (Deno.env.get("LINEAR_IGNORE_ENV_FILE") !== "1") throw new Error("dotenv enabled");
            const [flag, workspace, command, query] = Deno.args;
            if (flag !== "--workspace" || command !== "api") throw new Error("unexpected fixture argv");
            setCliWorkspace(workspace);
            await loadCredentials();
            await Deno.writeTextFile(Deno.env.get("FIXTURE_ARGV")!, JSON.stringify(["linear", ...Deno.args]) + "\n", { append: true });
            console.log(JSON.stringify({ data: await getGraphQLClient().request(query) }));
          } catch {
            console.error("synthetic Linear resolver rejected request");
            Deno.exit(1);
          }
        ''} "$out/fixture.ts"
        ${lib.getExe pkgs.python3} ${../home/ai/omnigent/credential-fixtures.py} prepare-linear "$out"
        export DENO_DIR="$TMPDIR/deno"
        mkdir -p "$DENO_DIR"
        ln -s ${pkgs.linear-cli.denoDeps}/deno_dir/npm "$DENO_DIR/npm"
        chmod u+w "$out/deno.lock"
        export HOME="$TMPDIR/home" LINEAR_IGNORE_ENV_FILE=1
        mkdir -p "$HOME"
        ${lib.getExe pkgs.deno} run --quiet --cached-only --no-check --no-prompt --allow-read --allow-env --allow-sys --deny-run --deny-net "$out/fixture.ts" --prepare
      '';
      mockLinear =
        (pkgs.writeShellScriptBin "linear" ''
          export DENO_DIR="$HOME/.cache/linear-fixture"
          ${pkgs.coreutils}/bin/mkdir -p "$DENO_DIR"
          ${pkgs.coreutils}/bin/ln -sfn ${pkgs.linear-cli.denoDeps}/deno_dir/npm "$DENO_DIR/npm"
          exec ${lib.getExe pkgs.deno} run --quiet --cached-only --frozen --no-check --allow-read --allow-write --allow-env --allow-sys --allow-run=git --deny-net ${linearResolver}/fixture.ts "$@"
        '')
        // {
          inherit (pkgs.linear-cli) src;
        };
      credentialSources = [
        "signing"
        "claude"
      ];
      credentialGithubOwners = [
        "first"
        "second"
      ];
      credentialSource = name: {
        enable = true;
        generator = "fixture-${name}";
        file = "credential";
      };
      credentialLinearFiles = [
        "key"
        "workspace"
        "workspace-id"
        "viewer-email"
      ];
      credentialDirectory = pkgs.runCommandLocal "omnigent-credential-synthetic-delivery" { } ''
        cp -r ${../home/ai/omnigent/fixtures}/. "$out/"
        chmod -R u+w "$out"
        cp -r "$out/vars/per-machine/fixture" "$out/vars/shared"
        ${lib.concatMapStringsSep "\n" (file: ''
          mkdir -p "$out/vars/shared/omnigent-cameron-linear-personal/${file}"
          cp ${../home/ai/omnigent/fixtures/vars/per-machine/fixture/fixture-signing/credential/secret} \
            "$out/vars/shared/omnigent-cameron-linear-personal/${file}/secret"
        '') credentialLinearFiles}
        ${lib.concatMapStringsSep "\n" (owner: ''
          mkdir -p "$out/vars/shared/omnigent-cameron-github-token-${owner}/token"
          cp ${../home/ai/omnigent/fixtures/vars/per-machine/fixture/fixture-signing/credential/secret} \
            "$out/vars/shared/omnigent-cameron-github-token-${owner}/token/secret"
        '') credentialGithubOwners}
      '';
      credentialModule = {
        nixpkgs.pkgs = lib.mkForce (
          pkgs.extend (
            _: _: {
              gh = mockGh;
              linear-cli = mockLinear;
            }
          )
        );
        clan.core.settings = {
          directory = credentialDirectory;
          name = "fixture";
          icon = null;
          tld = "test";
          domain = "fixture.test";
          machine.name = "fixture";
        };
        sops = {
          validateSopsFiles = false;
          age.keyFile = "/synthetic-no-decryption-key";
          templates.omnigent-omnigent-cameron-linear.path = "${credentialRoot}/rendered-linear";
          secrets =
            lib.listToAttrs (
              map (
                name:
                lib.nameValuePair "vars/shared/fixture-${name}/credential" {
                  path = "${credentialRoot}/${name}";
                }
              ) credentialSources
            )
            // lib.listToAttrs (
              map (
                owner:
                lib.nameValuePair "vars/shared/omnigent-cameron-github-token-${owner}/token" {
                  path = "${credentialRoot}/github-${owner}";
                }
              ) credentialGithubOwners
            )
            // lib.listToAttrs (
              map (
                file:
                lib.nameValuePair "vars/shared/omnigent-cameron-linear-personal/${file}" {
                  path = "${credentialRoot}/linear-${file}";
                }
              ) credentialLinearFiles
            );
        };
        users.users.omnigent-cameron.home = lib.mkForce credentialHomePath;
        services.omnigent-host = {
          serverUrl = lib.mkForce "https://fixture.invalid";
          workers.cameron = {
            enable = true;
            credentials = {
              signingKey = credentialSource "signing";
              githubTokens = lib.genAttrs credentialGithubOwners (owner: {
                enable = true;
                generator = "omnigent-cameron-github-token-${owner}";
                expectedLogin = "fixture-human";
              });
              defaultOwner = "first";
              claudeSetupToken = credentialSource "claude";
              linearApiKeys.personal = {
                enable = true;
                generator = "omnigent-cameron-linear-personal";
              };
              expected = {
                gitEmail = "fixture@example.invalid";
                omnigentEmail = "fixture@example.invalid";
                signingPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea";
              };
            };
          };
        };
      };
      credentialPathAssertion =
        host@{ config, ... }:
        {
          services.omnigent-host.workers.cameron.extraHomeModules = [
            ({ config, ... }: {
              assertions = [
                {
                  assertion =
                    let
                      policy = config.programs.omnigent.workerCredentials;
                      path = name: host.config.clan.core.vars.generators."fixture-${name}".files.credential.path;
                    in
                    policy.signingKey == path "signing"
                    && lib.all (
                      owner:
                      policy.githubTokens.${owner}.path
                      == host.config.clan.core.vars.generators."omnigent-cameron-github-token-${owner}".files.token.path
                    ) credentialGithubOwners
                    && policy.claudeSetupToken == path "claude"
                    &&
                      lib.all
                        (
                          field:
                          policy.linearApiKeys.personal.${field}
                          == host.config.clan.core.vars.generators.omnigent-cameron-linear-personal.files.${
                            {
                              path = "key";
                              workspace = "workspace";
                              workspaceId = "workspace-id";
                              viewerEmail = "viewer-email";
                            }
                            .${field}
                          }.path
                        )
                        [
                          "path"
                          "workspace"
                          "workspaceId"
                          "viewerEmail"
                        ];
                  message = "Credential fixture: Home Manager credential options must remain Clan vars paths.";
                }
                {
                  assertion =
                    let
                      rendered = host.config.sops.templates.omnigent-omnigent-cameron-linear.path;
                      policy = config.programs.omnigent.workerCredentials;
                    in
                    lib.elem rendered policy.requiredFiles
                    && !lib.elem policy.linearCredentials policy.requiredFiles
                    &&
                      toString (config.xdg.configFile."linear/credentials.toml".source or "")
                      == toString (config.lib.file.mkOutOfStoreSymlink rendered);
                  message = "Credential fixture: Home Manager must link Linear credentials to the rendered-only readiness artifact.";
                }
              ];
            })
          ];
        };
      credentialFixture =
        extra:
        (if pkgs.stdenv.isDarwin then mkDarwin else mkLinux) (
          [
            inputs.clan-core.${if pkgs.stdenv.isDarwin then "darwinModules" else "nixosModules"}.clanCore
            credentialModule
          ]
          ++ extra
        );
      credentialConfig = (credentialFixture [ credentialPathAssertion ]).config;
      credentialGenerationFor =
        c:
        if pkgs.stdenv.isDarwin then
          c.environment.etc."omnigent/workers/cameron".source
        else
          c.home-manager.users.omnigent-cameron.home.activationPackage;
      credentialGeneration = credentialGenerationFor credentialConfig;
      evaluationMaterial = builtins.toFile "synthetic-evaluation-credential" (
        builtins.hashString "sha256" "omnigent-evaluation-disclosure-fixture"
      );
      disclosureLeakControl = pkgs.writeText "omnigent-disclosure-leak-control" (
        builtins.readFile evaluationMaterial
      );
      disclosureSettings =
        c:
        pkgs.writeText "omnigent-delivery-settings.json" (
          builtins.toJSON {
            templates = c.sops.templates;
            supervisor =
              if pkgs.stdenv.isDarwin then
                c.launchd.daemons.omnigent-host-cameron.serviceConfig
              else
                c.systemd.services.omnigent-host-cameron.serviceConfig;
          }
        );
      disclosureArtifacts = c: [
        (credentialGenerationFor c)
        (disclosureSettings c)
        (
          if pkgs.stdenv.isDarwin then
            c.launchd.daemons.omnigent-host-cameron.command
          else
            c.systemd.services.omnigent-host-cameron.serviceConfig.ExecStartPre
        )
      ];
      disclosureDerivations = map (drv: builtins.unsafeDiscardOutputDependency drv.drvPath) [
        (disclosureSettings credentialConfig)
        linearResolver
      ];
      credentialArtifact = pkgs.writeText "omnigent-credential-artifacts.json" (
        builtins.toJSON {
          root = credentialRoot;
          evaluationMaterial = toString evaluationMaterial;
          derivationRoots = map builtins.unsafeDiscardStringContext disclosureDerivations;
          generatedArtifacts = map toString (disclosureArtifacts credentialConfig);
          leakControl = toString disclosureLeakControl;
          generation = toString credentialGeneration;
          git = lib.getExe pkgs.git;
          mockGh = lib.getExe mockGh;
          linearTemplate = credentialConfig.sops.templates.omnigent-omnigent-cameron-linear.content;
          mockLinear = lib.getExe mockLinear;
          linearPlaceholders = lib.genAttrs credentialLinearFiles (
            file: credentialConfig.sops.placeholder."vars/shared/omnigent-cameron-linear-personal/${file}"
          );
          runtimePath =
            if pkgs.stdenv.isDarwin then
              credentialConfig.launchd.daemons.omnigent-host-cameron.environment.PATH
            else
              credentialConfig.systemd.services.omnigent-host-cameron.environment.PATH;
          consumerSource = ../home/ai/omnigent/credentials.py;
          deliverySource = ../home/ai/omnigent/delivery.py;
          deliveryFixtures = ../home/ai/omnigent/delivery-fixtures.py;
          keychainSource = ../home/ai/omnigent/keychain.py;
          keychainFixtures = ../home/ai/omnigent/keychain-fixtures.py;
          keychainHome =
            if pkgs.stdenv.isDarwin then
              toString stibnite.config.environment.etc."omnigent/workers/cameron".source
            else
              null;
          keychainLaunchd =
            if pkgs.stdenv.isDarwin then toString stibnite.config.system.build.launchd else null;
          loginHelperSource = ../apps/omnigent-worker-login.sh;
          hostLauncher =
            if pkgs.stdenv.isDarwin then
              toString credentialConfig.launchd.daemons.omnigent-host-cameron.command
            else
              toString credentialConfig.systemd.services.omnigent-host-cameron.serviceConfig.ExecStartPre;
          systemActivation =
            if pkgs.stdenv.isDarwin then
              toString credentialConfig.system.activationScripts.script.source
            else
              null;
          installer =
            if pkgs.stdenv.isDarwin then
              credentialConfig.launchd.daemons.sops-install-secrets.command
            else
              null;
        }
      );
      credentialCases = {
        maskedLinearLabels =
          let
            accepts =
              label:
              (builtins.tryEval (
                builtins.deepSeq
                  (lib.evalModules {
                    modules = [
                      {
                        options.credentials = lib.mkOption {
                          type = lib.types.submodule { options = config.flake.lib.omnigentWorkerCredentialOptions; };
                        };
                      }
                      { credentials.linearApiKeys.${label}.enable = false; }
                    ];
                  }).config.credentials
                  true
              )).success;
          in
          accepts "personal" && accepts "work" && !accepts "synthetic-workspace-slug";
        defaultOff =
          config.flake.lib.omnigentCredentialSelection
            (lib.evalModules {
              modules = [
                {
                  options.credentials = lib.mkOption {
                    type = lib.types.submodule { options = config.flake.lib.omnigentWorkerCredentialOptions; };
                  };
                }
              ];
            }).config.credentials == { };
        moduleAssertions = lib.all (a: a.assertion) credentialConfig.assertions;
      };
    in
    {
      checks = {
        omnigent-worker-credentials =
          assert lib.assertMsg (lib.all (ok: ok) (lib.attrValues credentialCases))
            "Omnigent credential fixture failures: ${
              builtins.toJSON (lib.attrNames (lib.filterAttrs (_: ok: !ok) credentialCases))
            }";
          pkgs.runCommand "omnigent-worker-credentials"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.git
                pkgs.openssh
              ];
              fixtureDerivations = disclosureDerivations;
              passthru.cases = credentialCases;
            }
            ''
              ${pkgs.python3.interpreter} - <<'PY'
              from pathlib import Path
              link = Path("${credentialGeneration}/home-files/.config/linear/credentials.toml")
              assert link.is_symlink()
              target = link.resolve()
              assert target == Path("${credentialConfig.sops.templates.omnigent-omnigent-cameron-linear.path}").resolve()
              assert not target.is_relative_to("/nix/store")
              PY
              ${pkgs.python3.interpreter} ${../home/ai/omnigent/credential-fixtures.py} owner-fixtures ${../home/ai/omnigent/credentials.py}
              ${pkgs.omnigent.python.interpreter} ${../home/ai/omnigent/credential-fixtures.py} ${credentialArtifact}
              touch "$out"
            '';
        omnigent-worker-inventory =
          assert lib.assertMsg (
            inventoryFailed == [ ]
          ) "Omnigent inventory failures: ${lib.concatStringsSep ", " inventoryFailed}";
          pkgs.runCommand "omnigent-worker-inventory"
            {
              passthru.cases = inventoryCases;
              passAsFile = [ "report" ];
              report = builtins.toJSON inventoryCases;
            }
            ''
              cp "$reportPath" "$out"
            '';
      }
      // lib.optionalAttrs pkgs.stdenv.isDarwin {
        omnigent-worker-darwin =
          assert lib.assertMsg (lib.all (ok: ok) (lib.attrValues darwinCases))
            "Omnigent Darwin failures: ${
              builtins.toJSON (lib.attrNames (lib.filterAttrs (_: ok: !ok) darwinCases))
            }; assertions: ${builtins.toJSON (darwinFailures darwin)}";
          pkgs.runCommand "omnigent-worker-darwin"
            {
              nativeBuildInputs = [
                pkgs.python3
                pkgs.coreutils
              ];
              passthru.cases = darwinCases;
            }
            ''
              ${pkgs.omnigent.python.interpreter} ${darwinArtifactTest} \
                ${darwin.system.build.launchd} \
                ${darwinControl.system.build.launchd} \
                ${darwin.system.activationScripts.script.source} \
                ${darwin.environment.etc."omnigent/workers/cameron".source}
              python3 ${darwinLauncherTest}
              mkdir "$out"
              cp artifacts.json "$out/"
            '';
      }
      // lib.optionalAttrs pkgs.stdenv.isLinux {
        omnigent-worker-linux =
          assert lib.assertMsg (linuxFailed == [ ])
            "Omnigent Linux failures: ${lib.concatStringsSep ", " linuxFailed}; module assertions: ${builtins.toJSON (linuxFailures linux)}";
          pkgs.runCommand "omnigent-worker-linux"
            {
              passthru = {
                cases = linuxCases;
              };
            }
            ''
              ${lib.concatMapStringsSep "\n"
                (owner: ''
                  export PATH=${lib.escapeShellArg linux.systemd.services."omnigent-host-${owner}".environment.PATH}
                  test "$(worker-profile-only)" = worker-profile
                  test "$(command -v node)" = ${pkgs.nodejs_22}/bin/node
                  test "$(command -v hello)" = ${pkgs.hello}/bin/hello
                  for executable in atomic omp pi claude codex nix direnv gh linear rg fd; do
                    test -x "$(command -v "$executable")"
                  done
                  export HOME="$TMPDIR/private-${owner}"
                  ${pkgs.coreutils}/bin/mkdir -m 700 "$HOME"
                  ${linux.systemd.services."omnigent-host-${owner}".serviceConfig.ExecStartPre}
                  uid="$(${pkgs.coreutils}/bin/id -u)"
                  ${homeUidFixture} ${
                    linux.systemd.services."omnigent-host-${owner}".serviceConfig.ExecStartPre
                  } "$uid"
                  if ${homeUidFixture} ${
                    linux.systemd.services."omnigent-host-${owner}".serviceConfig.ExecStartPre
                  } "$((uid + 1))"; then
                    echo "accepted a wrong-owner worker home (UID-observation fixture)" >&2
                    exit 1
                  fi
                  ${pkgs.coreutils}/bin/chmod 755 "$HOME"
                  if ${linux.systemd.services."omnigent-host-${owner}".serviceConfig.ExecStartPre}; then
                    echo "accepted a public worker home" >&2
                    exit 1
                  fi
                  ${pkgs.coreutils}/bin/chmod 700 "$HOME"
                  ${pkgs.coreutils}/bin/ln -s "$HOME" "$TMPDIR/linked-${owner}"
                  export HOME="$TMPDIR/linked-${owner}"
                  if ${linux.systemd.services."omnigent-host-${owner}".serviceConfig.ExecStartPre}; then
                    echo "accepted a symlinked worker home" >&2
                    exit 1
                  fi
                '')
                [
                  "cameron"
                  "raquel"
                ]
              }
              ${pkgs.omnigent.python.interpreter} ${sandboxSelectionTest}
              ${pkgs.coreutils}/bin/touch "$out"
            '';
      }
      // {
        omnigent-worker-capabilities =
          assert lib.assertMsg (
            failed == [ ]
          ) "omnigent worker capability failures: ${lib.concatStringsSep ", " failed}";
          pkgs.runCommand "omnigent-worker-capabilities"
            {
              nativeBuildInputs = [ pkgs.yq-go ];
              passthru = { inherit cases workerPath; };
            }
            ''
              test -x ${cleanHome.config.home.path}/bin/pi
              test -x ${cleanHome.config.home.path}/bin/atomic
              export PATH=${lib.escapeShellArg workerPath}
              id -u
              ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux "hostname"}
              ${lib.optionalString pkgs.stdenv.hostPlatform.isLinux ''
                test "$(type -P kill)" = ${pkgs.procps}/bin/kill
                test "$(readlink -f ${cfg.home.path}/bin/kill)" = "$(readlink -f ${pkgs.procps}/bin/kill)"
              ''}
              mkdir -p cli-fixture/input cli-fixture/output
              printf 'beta\nalpha\nalpha\n' > cli-fixture/input/text
              test "$(find cli-fixture/input -type f | wc -l)" -eq 1
              test "$(sort cli-fixture/input/text | uniq | grep alpha | sed s/alpha/42/ | awk '{print $1}')" = 42
              cp cli-fixture/input/text cli-fixture/copy
              cmp cli-fixture/input/text cli-fixture/copy
              printf 'gamma\n' > cli-fixture/replacement
              diff -u cli-fixture/copy cli-fixture/replacement > cli-fixture/change.patch || test "$?" -eq 1
              patch cli-fixture/copy < cli-fixture/change.patch
              cmp cli-fixture/copy cli-fixture/replacement
              tar -czf cli-fixture/archive.tar.gz -C cli-fixture/input text
              tar -xzf cli-fixture/archive.tar.gz -C cli-fixture/output
              cmp cli-fixture/input/text cli-fixture/output/text
              xz -c cli-fixture/input/text | xz -d | cmp - cli-fixture/input/text
              zstd -q -c cli-fixture/input/text | zstd -q -d | cmp - cli-fixture/input/text
              zip -q -j cli-fixture/archive.zip cli-fixture/input/text
              unzip -p cli-fixture/archive.zip text | cmp - cli-fixture/input/text
              printf '{"items":[1,2]}' | jq -e '.items | add == 3'
              for executable in curl ssh scp sftp ssh-keygen openssl; do
                test -x "$(command -v "$executable")"
              done
              test "$(worker-profile-only)" = worker-profile
              if ${cfg.home.path}/bin/node; then exit 1; else test "$?" = 99; fi
              test "$(command -v node)" = ${pkgs.nodejs_22}/bin/node
              node --version
              for executable in rg fd gh linear atomic omp pi claude codex nix direnv; do
                test -x "$(command -v "$executable")"
              done
              ${pkgs.bash}/bin/bash --noprofile --norc ${workflowFixture}
              export PATH=${
                lib.makeBinPath [
                  pkgs.coreutils
                  pkgs.diffutils
                  pkgs.yq-go
                ]
              }
              mkdir -p state
              printf 'host:\n  name: new\nsequence: [new]\n' > declared.yaml
              printf 'host:\n  name: old\n  host_id: fixture-id\nunknown:\n  nested: retained\nsequence: [old]\n' > state/config.yaml
              ${lib.getExe merge} declared.yaml state/config.yaml
              yq -e '.host.name == "new" and .host.host_id == "fixture-id" and .unknown.nested == "retained" and (.sequence | length) == 1 and .sequence[0] == "new"' state/config.yaml
              cp state/config.yaml expected.yaml
              ${lib.getExe merge} declared.yaml state/config.yaml
              cmp expected.yaml state/config.yaml
              test "$(stat -c %a state/config.yaml)" = 600
              for invalid in '[unterminated' '[sequence]' 'scalar' 'null' $'---\na: one\n---\nb: two'; do
                printf '%s\n' "$invalid" > state/config.yaml
                cp state/config.yaml before.yaml
                if ${lib.getExe merge} declared.yaml state/config.yaml; then
                  echo 'accepted invalid persisted configuration' >&2
                  exit 1
                fi
                cmp before.yaml state/config.yaml
              done
              ${lib.getExe merge} declared.yaml state/fresh.yaml
              yq -e '.host.name == "new"' state/fresh.yaml
              printf '[unterminated\n' > invalid-declaration.yaml
              cp state/fresh.yaml before.yaml
              if ${lib.getExe merge} invalid-declaration.yaml state/fresh.yaml; then exit 1; fi
              cmp before.yaml state/fresh.yaml
              if ${lib.getExe merge} invalid-declaration.yaml state/absent.yaml; then exit 1; fi
              test ! -e state/absent.yaml
              ${lib.getExe pkgs.python3} ${atomicMergeTest} ${atomicActivation} ${lib.escapeShellArg "${cfg.programs.atomic.configDir}/settings.json"}
              touch "$out"
            '';
      };
    };
}
