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
        largeBenignSettings = valid (mkHome [
          {
            programs.atomic.settings.workerFixture = lib.concatStrings (lib.genList (_: "x") 300000);
          }
        ]);
        largeForeignSettings =
          rejected "Omnigent worker configuration must use its own home, not a foreign human home."
            [
              {
                programs.atomic.settings.workerFixture =
                  lib.concatStrings (lib.genList (_: "x") 150000)
                  + " /home/human/private "
                  + lib.concatStrings (lib.genList (_: "x") 150000);
              }
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
      linuxRejects =
        message: extra:
        let
          evaluate =
            modules:
            builtins.tryEval (
              let
                c = (mkLinux modules).config;
              in
              assert linuxFailures c == [ ];
              c.networking.hostName
            );
          withoutGuard.options.assertions = lib.mkOption {
            apply = lib.filter (a: a.assertion || a.message != message);
          };
        in
        !(evaluate extra).success && (evaluate (extra ++ [ withoutGuard ])).success;
      sudoRule = users: groups: {
        security.sudo.extraRules = [
          {
            inherit users groups;
            commands = [ "ALL" ];
          }
        ];
      };
      linuxCases = {
        valid = linuxFailures linux == [ ];
        disabledPrepared =
          !(prepared.systemd.services ? omnigent-host-cameron)
          && !(prepared.systemd.services ? omnigent-host-raquel)
          && prepared.home-manager.users.omnigent-cameron.programs.omnigent.enable
          && builtins.hasAttr "home-manager-omnigent\\x2dcameron" prepared.systemd.services;
        noLegacyFallback = !(linux.systemd.services ? omnigent-host);
        root = lib.elem "Omnigent worker cameron: requires a dedicated non-root normal account." (
          linuxFailures (mkLinux [ { users.users.omnigent-cameron.uid = 0; } ]).config
        );
        duplicateUser = linuxRejects "Omnigent workers require distinct accounts." [
          {
            services.omnigent-host.workers.duplicate = {
              owner = "cameron";
              user = "omnigent-cameron";
              hostName = "fixture-cameron";
            };
          }
        ];
        duplicateHome =
          let
            c =
              (mkLinux [ { users.users.omnigent-raquel.home = lib.mkForce "/home/omnigent-cameron"; } ]).config;
          in
          lib.elem "Omnigent worker cameron: requires a private distinct home and home-local workspace." (
            linuxFailures c
          )
          && lib.elem "Omnigent worker raquel: requires a private distinct home and home-local workspace." (
            linuxFailures c
          );
        publicHome =
          linuxRejects "Omnigent worker cameron: requires a private distinct home and home-local workspace."
            [ { users.users.omnigent-cameron.homeMode = "0755"; } ];
        admin =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [ { users.users.omnigent-cameron.extraGroups = [ "wheel" ]; } ];
        groupMembership =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [ { users.groups.docker.members = [ "omnigent-cameron" ]; } ];
        sudo =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [
              {
                security.sudo.extraRules = [
                  {
                    users = [ "omnigent-cameron" ];
                    commands = [ "ALL" ];
                  }
                ];
              }
            ];
        sudoAll =
          linuxFailures (mkLinux [ (sudoRule [ "ALL" ] [ ]) ]).config
          == map (owner: "Omnigent worker ${owner}: administrative groups or sudo grants are prohibited.") [
            "cameron"
            "raquel"
          ];
        sudoUid =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [
              { users.users.omnigent-cameron.uid = 22001; }
              (sudoRule [ 22001 ] [ ])
            ];
        sudoPrimaryGid =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [
              { users.groups.omnigent-cameron.gid = 22001; }
              (sudoRule [ ] [ 22001 ])
            ];
        sudoSupplementaryGid =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [
              {
                users.users.omnigent-cameron.extraGroups = [ "fixture" ];
                users.groups.fixture.gid = 22001;
              }
              (sudoRule [ ] [ 22001 ])
            ];
        sudoMemberGid =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [
              {
                users.groups.fixture = {
                  gid = 22001;
                  members = [ "omnigent-cameron" ];
                };
              }
              (sudoRule [ ] [ 22001 ])
            ];
        sudoPrimaryGroup =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [ (sudoRule [ ] [ "omnigent-cameron" ]) ];
        sudoSupplementaryGroup =
          linuxRejects "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
            [
              {
                users.users.omnigent-cameron.extraGroups = [ "fixture" ];
                users.groups.fixture = { };
              }
              (sudoRule [ ] [ "fixture" ])
            ];
        sudoUnrelated =
          linuxFailures
            (mkLinux [
              {
                users.users.omnigent-cameron.uid = 22001;
                users.groups.omnigent-cameron.gid = 22001;
              }
              (sudoRule [ "unrelated" 22002 "22001" ] [ "unrelated" 22002 "22001" "ALL" ])
            ]).config == [ ];
        sudoUnallocatedIds = linuxFailures (mkLinux [ (sudoRule [ 22001 ] [ 22001 ]) ]).config == [ ];
        trusted = linuxRejects "Omnigent worker cameron: Nix trusted-user authority is prohibited." [
          { nix.settings.trusted-users = [ "omnigent-cameron" ]; }
        ];
        trustedGroup = linuxRejects "Omnigent worker cameron: Nix trusted-user authority is prohibited." [
          { nix.settings.trusted-users = [ "@omnigent-cameron" ]; }
        ];
        selectors =
          lib.all
            (
              key:
              linuxRejects
                "Omnigent worker cameron: environment cannot override identity, state or authority selectors."
                [ { services.omnigent-host.workers.cameron.environment.${key} = "foreign"; } ]
            )
            [
              "HOME"
              "USER"
              "LOGNAME"
              "PATH"
              "XDG_CONFIG_HOME"
              "PI_CODING_AGENT_DIR"
              "ATOMIC_CODING_AGENT_DIR"
              "OMP_CODING_AGENT_DIR"
              "OMNIGENT_RUNNER_ENV_PASSTHROUGH"
              "SSH_AUTH_SOCK"
              "NIX_CONFIG"
            ];
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
      darwinRejects =
        message: extra:
        let
          evaluate =
            modules:
            builtins.tryEval (
              let
                c = (mkDarwin modules).config;
              in
              assert darwinFailures c == [ ];
              c.networking.hostName
            );
          withoutGuard.options.assertions = lib.mkOption {
            apply = lib.filter (a: a.assertion || a.message != message);
          };
        in
        !(evaluate extra).success && (evaluate (extra ++ [ withoutGuard ])).success;
      darwinCases = {
        valid = darwinFailures darwin == [ ];
        disabledPrepared =
          !(darwinPrepared.launchd.daemons ? omnigent-host-cameron)
          && darwinPrepared.environment.etc ? "omnigent/workers/cameron"
          && darwinPrepared.home-manager.users == { };
        noLegacyFallback = darwin.home-manager.users == { };
        root = darwinRejects "Omnigent worker cameron: requires a dedicated non-root managed account." [
          { users.users.omnigent-cameron.uid = lib.mkForce 0; }
        ];
        admin = darwinRejects "Omnigent worker cameron: administrative groups are prohibited." [
          {
            users.groups.admin = {
              gid = 80;
              members = [ "omnigent-cameron" ];
            };
          }
        ];
        primaryAdmin = darwinRejects "Omnigent worker cameron: administrative groups are prohibited." [
          { users.users.omnigent-cameron.gid = lib.mkForce 80; }
        ];
        trusted = darwinRejects "Omnigent worker cameron: Nix trusted-user authority is prohibited." [
          { nix.settings.trusted-users = [ "omnigent-cameron" ]; }
        ];
        trustedGroup = darwinRejects "Omnigent worker cameron: Nix trusted-user authority is prohibited." [
          { nix.settings.trusted-users = [ "@omnigent-cameron" ]; }
        ];
        noNix = darwinRejects "Omnigent worker cameron: ordinary Nix daemon access is required." [
          { nix.settings.allowed-users = lib.mkForce [ "root" ]; }
        ];
        duplicateActivation =
          darwinRejects "Omnigent worker cameron: standalone Home Manager must be the only activation owner."
            [
              { home-manager.users.omnigent-cameron.home.stateVersion = "25.11"; }
            ];
        workerAgent =
          darwinRejects "Omnigent worker cameron: worker Home Manager must not require a user launchd domain."
            [
              {
                services.omnigent-host.workers.cameron.extraHomeModules = [
                  {
                    launchd.agents.unwanted = {
                      enable = true;
                      config.ProgramArguments = [ "/usr/bin/true" ];
                    };
                  }
                ];
              }
            ];
        desktopActivation =
          darwinRejects
            "Omnigent worker cameron: worker Home Manager must not require desktop application activation."
            [
              {
                services.omnigent-host.workers.cameron.extraHomeModules = [
                  { targets.darwin.copyApps.enable = lib.mkForce true; }
                ];
              }
            ];
        selectors =
          lib.all
            (
              key:
              darwinRejects
                "Omnigent worker cameron: environment cannot override identity, state or authority selectors."
                [
                  { services.omnigent-host.workers.cameron.environment.${key} = "foreign"; }
                ]
            )
            [
              "HOME"
              "PATH"
              "SSH_AUTH_SOCK"
              "NIX_CONFIG"
              "ATOMIC_CODING_AGENT_DIR"
              "OMP_CODING_AGENT_DIR"
              "BASH_ENV"
              "SKIP_SANITY_CHECKS"
            ];
      };
      darwinWrongUser =
        (mkDarwin [
          {
            launchd.daemons.omnigent-host-cameron.serviceConfig.UserName = lib.mkForce "root";
          }
        ]).config;
      darwinWrongDomain =
        (mkDarwin [
          {
            environment.launchDaemons."org.nixos.omnigent-host-cameron.plist".enable = false;
            environment.launchAgents."org.nixos.omnigent-host-cameron.plist".text =
              darwin.environment.launchDaemons."org.nixos.omnigent-host-cameron.plist".text;
          }
        ]).config;
      darwinMissingPath =
        path:
        (mkDarwin [
          {
            launchd.daemons.omnigent-host-cameron.environment.PATH = lib.mkForce path;
          }
        ]).config;
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
        for root, reason in zip(sys.argv[2:6], ["wrong user", "wrong domain", "missing runtime", "missing profile"], strict=True):
            try:
                inspect(root)
            except AssertionError as error:
                assert str(error) == reason, (reason, str(error))
            else:
                raise AssertionError("accepted " + reason)
        control = inspect(sys.argv[6])
        _, _, activation, merger, declaration = production
        assert str(Path(activation).parent) == sys.argv[8], "enrollment generation differs from launched generation"
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

        system_activation = Path(sys.argv[7]).read_text()
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
      inventoryRealMachines = {
        inherit (config.flake.nixosConfigurations) magnetite pyrite;
        inherit (config.flake.darwinConfigurations) stibnite;
      };
      inventoryDeliveryFixture = pkgs.runCommandLocal "omnigent-inventory-synthetic-delivery" { } (
        lib.concatStringsSep "\n" (
          lib.concatLists (
            lib.mapAttrsToList (
              _: d:
              lib.concatMap (
                worker:
                map (source: ''
                  mkdir -p "$out/vars/shared/${source.generator}/${source.file}"
                  install -m 0644 ${../home/ai/omnigent/fixtures/vars/per-machine/fixture/fixture-signing/credential/secret} \
                    "$out/vars/shared/${source.generator}/${source.file}/secret"
                '') (lib.attrValues (config.flake.lib.omnigentCredentialSelection worker.credentials))
              ) (lib.attrValues d.config.services.omnigent-host.workers)
              ++ lib.concatMap (
                generator:
                lib.concatMap (
                  file:
                  lib.optional (!file.secret && file.flakePath != null && builtins.pathExists file.flakePath) ''
                    mkdir -p "$out/vars/${file.rel_dir}/${file.name}"
                    install -m 0644 ${file.flakePath} "$out/vars/${file.rel_dir}/${file.name}/value"
                  ''
                ) (lib.attrValues generator.files)
              ) (lib.attrValues d.config.clan.core.vars.generators)
            ) inventoryRealMachines
          )
        )
      );
      inventoryMachines = lib.mapAttrs (
        _: d:
        d.extendModules {
          modules = [
            {
              clan.core.settings.directory = lib.mkForce inventoryDeliveryFixture;
              sops.validateSopsFiles = false;
            }
          ];
        }
      ) inventoryRealMachines;
      expectedOwners = {
        magnetite = [
          "cameron"
          "janettesmith"
        ];
        pyrite = [
          "cameron"
          "janettesmith"
        ];
        stibnite = [ "cameron" ];
      };
      inspectInventory =
        machine: c:
        let
          isDarwin = machine == "stibnite";
          workers = c.services.omnigent-host.workers;
          owners = expectedOwners.${machine};
          workerUsers = map (owner: "omnigent-${owner}") owners;
        in
        lib.attrNames workers == owners
        && lib.filter (lib.hasPrefix "omnigent-") (lib.attrNames c.users.users) == workerUsers
        && lib.all (a: a.assertion) c.assertions
        && lib.all (
          owner:
          let
            worker = workers.${owner};
            user = "omnigent-${owner}";
            account = c.users.users.${user};
            group = c.users.groups.${user};
            home = "${if isDarwin then "/Users" else "/home"}/${user}";
            memberships = lib.attrNames (lib.filterAttrs (_: g: lib.elem user g.members) c.users.groups);
            h = c.home-manager.users.${user};
          in
          worker.owner == owner
          && worker.user == user
          && worker.hostName == "${machine}-${owner}"
          && worker.workspaceRoot == "${home}/projects"
          && !worker.autoApproveDirenv
          && worker.environment == { }
          && account.home == home
          && account.createHome
          && account.openssh.authorizedKeys.keys == [ ]
          && account.openssh.authorizedKeys.keyFiles == [ ]
          && lib.all (name: name == user) memberships
          && lib.all (name: name == user) group.members
          && lib.all (other: other.name == user || other.home != account.home) (lib.attrValues c.users.users)
          && (
            if isDarwin then
              account.uid == 551
              && account.gid == 551
              && group.gid == 551
              && lib.elem user c.users.knownUsers
              && lib.elem user c.users.knownGroups
              && !(builtins.hasAttr user c.home-manager.users)
              && c.environment.etc ? "omnigent/workers/${owner}"
              && (builtins.hasAttr "omnigent-host-${owner}" c.launchd.daemons) == worker.enable
            else
              account.isNormalUser
              && account.group == user
              && account.extraGroups == [ ]
              && lib.elem account.homeMode [
                "700"
                "0700"
              ]
              && account.hashedPassword == "!"
              && account.hashedPasswordFile == null
              && h.home.username == user
              && h.home.homeDirectory == home
              && h.programs.omnigent.enable
              && h.programs.gh.gitCredentialHelper.enable
              && h.programs.omnigent.settings.host.name == "${machine}-${owner}"
              && (owner != "janettesmith" || inspectJanetteHome h)
              && lib.all (a: a.assertion) h.assertions
              && (builtins.hasAttr "omnigent-host-${owner}" c.systemd.services) == worker.enable
          )
        ) owners;
      inventoryVariant =
        machine: module:
        (inventoryMachines.${machine}.extendModules {
          modules = [ module ];
        }).config;
      inventoryEnabled =
        machine: enable:
        inventoryVariant machine {
          services.omnigent-host.workers = lib.genAttrs expectedOwners.${machine} (_: {
            enable = lib.mkForce enable;
          });
        };
      inventoryRejects = machine: module: !inspectInventory machine (inventoryVariant machine module);
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
      janetteGitEmail = "125711642+janetteasmith@users.noreply.github.com";
      janetteAuthor = {
        name = "Janette Smith";
        email = janetteGitEmail;
      };
      janetteMeta = config.flake.users.janettesmith.meta;
      janetteHuman = config.flake.darwinConfigurations.rosegold.config.home-manager.users.janettesmith;
      inspectJanetteHome =
        h:
        h.programs.git.settings.user.name == janetteAuthor.name
        && h.programs.git.settings.user.email == janetteGitEmail
        && h.programs.jujutsu.settings.user == janetteAuthor
        && !(h ? sops)
        && !(h.home.sessionVariables ? SSH_AUTH_SOCK);
      identityBinding =
        modules:
        (lib.evalModules {
          modules = [
            {
              options.programs = lib.mkOption { type = lib.types.attrs; };
            }
          ]
          ++ modules;
        }).config == {
          programs.git.settings.user = janetteAuthor;
          programs.jujutsu.settings.user = janetteAuthor;
        };
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
      cacheDownloads = c: c.nix.settings.substituters != [ ] && c.nix.settings.trusted-public-keys != [ ];
      inventoryCases = {
        declaredCredentials = lib.all (
          machine:
          lib.all (
            worker:
            let
              credentials = worker.credentials;
              meta = config.flake.users.${if worker.owner == "cameron" then "crs58" else worker.owner}.meta;
            in
            credentials.signingKey == {
              enable = true;
              generator = "${worker.user}-signing-key";
              file = "key";
            }
            &&
              credentials.githubTokens
              == lib.genAttrs ([ "sciexp" ] ++ lib.optional (worker.owner == "cameron") "cameronraysmith")
                (owner: {
                  enable = true;
                  generator = "${worker.user}-github-token-${owner}";
                  file = "token";
                  expectedLogin = meta.githubUser;
                })
            && credentials.defaultOwner == (if worker.owner == "cameron" then "cameronraysmith" else "sciexp")
            &&
              credentials.linearApiKeys
              == lib.genAttrs ([ "personal" ] ++ lib.optional (worker.owner == "cameron") "work") (label: {
                enable = true;
                generator = "${worker.user}-linear-${label}";
              })
            && !credentials.claudeSetupToken.enable
            &&
              credentials.expected == {
                gitEmail = meta.gitEmail;
                signingPublicKey = lib.head meta.sshKeys;
                omnigentEmail = meta.email;
              }
            && lib.all (
              source:
              let
                generator = machine.config.clan.core.vars.generators.${source.generator};
                file = generator.files.${source.file};
              in
              generator.prompts.${source.file}.type == "hidden"
              && generator.share
              && file.secret
              && file.neededFor == "services"
              && file.owner == worker.user
              && file.mode == "0400"
            ) (lib.attrValues (config.flake.lib.omnigentCredentialSelection credentials))
          ) (lib.attrValues machine.config.services.omnigent-host.workers)
        ) (lib.attrValues inventoryMachines);
        realEnrollment = lib.all (
          d:
          let
            c = d.config;
            missing =
              worker:
              lib.any (
                source:
                !builtins.pathExists (
                  c.clan.core.settings.directory + "/vars/shared/${source.generator}/${source.file}/secret"
                )
              ) (lib.attrValues (config.flake.lib.omnigentCredentialSelection worker.credentials));
            expectedFailures = lib.concatMap (
              worker:
              lib.optionals (missing worker) [
                "Omnigent worker ${worker.user}: credentials require private shared services files owned by the worker with mode 0400."
                "Omnigent worker ${worker.user}: only the declared Clan vars ciphertext and delivered paths are allowed."
              ]
            ) (lib.attrValues c.services.omnigent-host.workers);
            failures = map (a: a.message) (lib.filter (a: !a.assertion) c.assertions);
          in
          lib.sort builtins.lessThan failures == lib.sort builtins.lessThan expectedFailures
          &&
            (builtins.tryEval (
              assert lib.all (a: a.assertion) c.assertions;
              true
            )).success == (expectedFailures == [ ])
        ) (lib.attrValues inventoryRealMachines);
        enableMap = lib.all (
          name:
          let
            c = inventoryMachines.${name}.config;
            workersEnabled = lib.all (w: w.enable) (lib.attrValues c.services.omnigent-host.workers);
            legacy = c.services.omnigent-host.enable;
          in
          workersEnabled && !legacy
        ) (lib.attrNames inventoryMachines);
        humanProfilesRetained =
          config.flake.users ? raquel
          && config.flake.users ? janettesmith
          && config.flake.darwinConfigurations.blackphos.config.home-manager.users ? raquel
          && janetteHuman.home.username == "janettesmith";
        canonicalJanette =
          janetteMeta.username == "janettesmith"
          && janetteMeta.fullname == "Janette Smith"
          && janetteMeta.email == "janette.a.smith@gmail.com"
          && janetteMeta.githubUser == "janetteasmith"
          && janetteMeta.gitEmail == janetteGitEmail
          && janetteMeta.sopsAgeKeyId == null
          &&
            janetteMeta.sshKeys == [
              "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
            ];
        publicRecipient = lib.hasInfix "&janettesmith-user age1mqfqckczkulpne7265j5cxn0pspdlxd3d0kav368u2c2fwknnc4qe27dec" (
          builtins.readFile ../../.sops.yaml
        );
        humanAuthor =
          janetteHuman.programs.git.settings.user.email == janetteGitEmail
          && janetteHuman.programs.jujutsu.settings.user.email == janetteGitEmail
          && janetteHuman.programs.git.settings.github.user == "janetteasmith"
          &&
            janetteHuman.sops.templates.allowed_signers.content
            == "${janetteGitEmail} namespaces=\"git\" ${janetteHuman.sops.placeholder.ssh-public-key}\n";
        gitEmailDefault = metaFixture { } == "primary@example.invalid";
        gitEmailOverride = metaFixture { gitEmail = "author@example.invalid"; } == "author@example.invalid";
        gitEmailType =
          !(builtins.tryEval (metaFixture {
            gitEmail = 42;
          })).success;
        narrowIdentityBinding =
          lib.all
            (
              machine:
              let
                modules =
                  inventoryMachines.${machine}.config.services.omnigent-host.workers.janettesmith.extraHomeModules;
              in
              identityBinding modules && inspectJanetteHome (mkHome modules).config
            )
            [
              "magnetite"
              "pyrite"
            ];
        unrelatedBindingRejected =
          !identityBinding [
            {
              programs.git.settings.user = janetteAuthor;
              programs.jujutsu.settings.user = janetteAuthor;
              programs.unrelated.enable = true;
            }
          ];
        wrongGitAuthor = inventoryRejects "magnetite" {
          services.omnigent-host.workers.janettesmith.extraHomeModules = [
            {
              programs.git.settings.user.email = lib.mkForce "janette.a.smith@gmail.com";
            }
          ];
        };
        wrongJjAuthor = inventoryRejects "pyrite" {
          services.omnigent-host.workers.janettesmith.extraHomeModules = [
            {
              programs.jujutsu.settings.user.email = lib.mkForce "janettesmith@example.com";
            }
          ];
        };
        wrongHostName = inventoryRejects "pyrite" {
          services.omnigent-host.workers.janettesmith.hostName = lib.mkForce "pyrite-raquel";
        };
        hostMatrix =
          lib.attrNames inventoryRoles.host.machines == [
            "magnetite"
            "pyrite"
            "stibnite"
          ];
        serverMatrix =
          lib.attrNames inventoryRoles.server.machines == [ "magnetite" ]
          && inventoryMachines.magnetite.config.services.omnigent.domain == "omni.scientistexperience.net";
        cacheDownloads = lib.all (d: cacheDownloads d.config) (lib.attrValues inventoryMachines);
        missingCaches =
          !cacheDownloads (
            inventoryVariant "pyrite" {
              nix.settings.substituters = lib.mkForce [ ];
            }
          );
        missingCacheKeys =
          !cacheDownloads (
            inventoryVariant "stibnite" {
              nix.settings.trusted-public-keys = lib.mkForce [ ];
            }
          );
        missingWorker = inventoryRejects "pyrite" {
          services.omnigent-host.workers = lib.mkForce { };
        };
        extraDarwinWorker = inventoryRejects "stibnite" {
          services.omnigent-host.workers.raquel = {
            owner = "raquel";
            user = "omnigent-cameron";
          };
        };
        wrongOwner = inventoryRejects "magnetite" {
          services.omnigent-host.workers.janettesmith.owner = lib.mkForce "cameron";
        };
        duplicateHome = inventoryRejects "pyrite" {
          users.users.omnigent-janettesmith.home = lib.mkForce "/home/omnigent-cameron";
        };
        adminMembership = inventoryRejects "magnetite" {
          users.groups.wheel.members = [ "omnigent-cameron" ];
        };
        trustedDaemon = inventoryRejects "stibnite" {
          nix.settings.trusted-users = [ "omnigent-cameron" ];
        };
        deniedNix = inventoryRejects "pyrite" {
          nix.settings.allowed-users = lib.mkForce [ "root" ];
        };
        inheritedSsh = inventoryRejects "stibnite" {
          users.users.omnigent-cameron.openssh.authorizedKeys.keys = [ "fixture-unwanted-key" ];
        };
        signer = inventoryRejects "pyrite" {
          services.omnigent-host.workers.cameron.extraHomeModules = [
            {
              programs.git.settings.user.signingKey = lib.mkForce "/synthetic-undeclared-signing-key";
            }
          ];
        };
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
        serverIndependent =
          let
            serverUnit = c: c.systemd.units."omnigent.service".unit.drvPath;
            current = inventoryMachines.magnetite.config;
            without = inventoryVariant "magnetite" { services.omnigent-host.workers = lib.mkForce { }; };
          in
          serverUnit current == serverUnit without
          && serverUnit current == serverUnit (inventoryEnabled "magnetite" true);
      }
      // lib.mapAttrs' (
        machine: d:
        lib.nameValuePair "machine-${machine}" (
          inspectInventory machine d.config
          && inspectInventory machine (inventoryEnabled machine false)
          && inspectInventory machine (inventoryEnabled machine true)
        )
      ) inventoryMachines;
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
      disclosureFixture =
        leak:
        (credentialFixture [
          credentialPathAssertion
          {
            sops.secrets =
              lib.genAttrs
                (
                  (map (name: "vars/shared/fixture-${name}/credential") credentialSources)
                  ++ map (owner: "vars/shared/omnigent-cameron-github-token-${owner}/token") credentialGithubOwners
                )
                (_: {
                  path = lib.mkForce (toString evaluationMaterial);
                });
            services.omnigent-host.workers.cameron.extraHomeModules = lib.optional leak {
              home.sessionVariables.OMNIGENT_DISCLOSURE_CONTROL = builtins.readFile evaluationMaterial;
            };
          }
        ]).config;
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
      disclosureClean = disclosureFixture false;
      disclosureLeaking = disclosureFixture true;
      disclosureDerivations = map (drv: builtins.unsafeDiscardOutputDependency drv.drvPath) [
        (disclosureSettings credentialConfig)
        (disclosureSettings disclosureClean)
        linearResolver
      ];
      credentialArtifact = pkgs.writeText "omnigent-credential-artifacts.json" (
        builtins.toJSON {
          root = credentialRoot;
          evaluationMaterial = toString evaluationMaterial;
          derivationRoots = map builtins.unsafeDiscardStringContext disclosureDerivations;
          generatedArtifacts = map toString (
            (disclosureArtifacts credentialConfig) ++ (disclosureArtifacts disclosureClean)
          );
          leakingGeneration = toString (credentialGenerationFor disclosureLeaking);
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
              toString inventoryRealMachines.stibnite.config.environment.etc."omnigent/workers/cameron".source
            else
              null;
          keychainLaunchd =
            if pkgs.stdenv.isDarwin then
              toString inventoryRealMachines.stibnite.config.system.build.launchd
            else
              null;
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
      credentialRejects =
        message: module:
        let
          evaluates =
            extra:
            (builtins.tryEval (
              let
                c = (credentialFixture extra).config;
              in
              assert lib.all (a: a.assertion) c.assertions;
              c.networking.hostName
            )).success;
          removeGuard.options.assertions = lib.mkOption {
            apply = lib.filter (a: a.assertion || a.message != message);
          };
        in
        !evaluates [ module ]
        && evaluates [
          module
          removeGuard
        ];
      credentialCases = {
        linearRenderedOutsideHomes = lib.all (
          machine:
          let
            c = machine.config;
            homes = map (worker: toString c.users.users.${worker.user}.home) (
              lib.attrValues c.services.omnigent-host.workers
            );
            templates = lib.filterAttrs (name: _: lib.hasPrefix "omnigent-" name) c.sops.templates;
          in
          lib.all (
            template:
            template.path == "/run/secrets/rendered/${template.name}"
            && !lib.any (home: lib.hasPrefix "${home}/" template.path) homes
            && template.mode == "0400"
            && lib.any (worker: worker.user == template.owner) (lib.attrValues c.services.omnigent-host.workers)
          ) (lib.attrValues templates)
        ) (lib.attrValues inventoryRealMachines);
        hostLocalCredentials =
          let
            c =
              (credentialFixture [
                {
                  clan.core.vars.generators.fixture-signing.share = lib.mkForce false;
                  sops.secrets."vars/shared/fixture-signing/credential".sopsFile =
                    ../home/ai/omnigent/fixtures/vars/per-machine/fixture/fixture-signing/credential/secret;
                }
              ]).config;
          in
          lib.any (
            a:
            !a.assertion
            &&
              a.message
              == "Omnigent worker omnigent-cameron: credentials require private shared services files owned by the worker with mode 0400."
          ) c.assertions;
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
        adapterAllowList =
          credentialRejects
            "Omnigent worker cameron: Home Manager credential paths must match the host adapter's allow-list."
            {
              services.omnigent-host.workers.cameron.extraHomeModules = [
                { _module.args.omnigentCredentialPolicy = lib.mkForce null; }
              ];
            };
        defaultOff = lib.all (
          worker: config.flake.lib.omnigentCredentialSelection worker.credentials == { }
        ) (lib.attrValues linux.services.omnigent-host.workers);
        inherit (inventoryCases) declaredCredentials enableMap realEnrollment;
        moduleAssertions = lib.all (a: a.assertion) credentialConfig.assertions;
        keychainScope = lib.all (
          machine:
          lib.all (
            name:
            (inventoryRealMachines.${machine}.config.services.omnigent-host.workers.${name}.keychainEnable
              or false
            ) == (machine == "stibnite" && name == "cameron")
          ) expectedOwners.${machine}
        ) (lib.attrNames inventoryRealMachines);
        keychainSecret =
          let
            g = inventoryRealMachines.stibnite.config.clan.core.vars.generators.omnigent-cameron-keychain;
          in
          !g.share
          && g.files.password.secret
          && g.files.password.owner == "omnigent-cameron"
          && g.files.password.mode == "0400"
          && g.files.password.neededFor == "services";
        fleetLinearGeneratorScript =
          let
            g =
              inventoryRealMachines.magnetite.config.clan.core.vars.generators.omnigent-janettesmith-linear-personal;
          in
          lib.attrNames g.files == lib.sort builtins.lessThan credentialLinearFiles
          && lib.all (
            file: lib.hasInfix ''cp "$prompts/${file}" "$out/${file}"'' g.script
          ) credentialLinearFiles;
        declaredLinearFiles = lib.all (
          file:
          let
            g = credentialConfig.clan.core.vars.generators.omnigent-cameron-linear-personal;
            f = g.files.${file};
          in
          g.prompts.${file}.type == "hidden"
          && g.prompts.${file}.persist
          && g.share
          && f.secret
          && f.neededFor == "services"
          && f.owner == "omnigent-cameron"
          && f.mode == "0400"
          && f.path == "${credentialRoot}/linear-${file}"
        ) credentialLinearFiles;
        linearMetadataMode =
          credentialRejects
            "Omnigent worker omnigent-cameron: credentials require private shared services files owned by the worker with mode 0400."
            {
              clan.core.vars.generators.omnigent-cameron-linear-personal.files.workspace.mode =
                lib.mkForce "0644";
            };
        declaredGithubTokens = lib.all (
          owner:
          let
            g = credentialConfig.clan.core.vars.generators."omnigent-cameron-github-token-${owner}";
            f = g.files.token;
          in
          g.prompts.token.type == "hidden"
          && g.share
          && f.secret
          && f.neededFor == "services"
          && f.owner == "omnigent-cameron"
          && f.mode == "0400"
          && f.path == "${credentialRoot}/github-${owner}"
        ) credentialGithubOwners;
        githubDefaultOwner =
          credentialRejects
            "Omnigent worker omnigent-cameron: defaultOwner must select an enabled GitHub token."
            {
              services.omnigent-host.workers.cameron.credentials.defaultOwner = lib.mkForce "unknown";
            };
        githubExpectedPerson =
          credentialRejects
            "Omnigent worker omnigent-cameron: GitHub owner tokens require the same explicit expected person login."
            {
              services.omnigent-host.workers.cameron.credentials.githubTokens.second.expectedLogin =
                lib.mkForce "another-person";
            };
        declaredSources = lib.all (
          name:
          let
            g = credentialConfig.clan.core.vars.generators."fixture-${name}";
            f = g.files.credential;
          in
          g.prompts.credential.type == "hidden"
          && g.share
          && f.secret
          && f.neededFor == "services"
          && f.owner == "omnigent-cameron"
          && f.mode == "0400"
          && f.path == "${credentialRoot}/${name}"
        ) credentialSources;
        wrongOwner =
          credentialRejects
            "Omnigent worker omnigent-cameron: credentials require private shared services files owned by the worker with mode 0400."
            {
              clan.core.vars.generators.omnigent-cameron-github-token-first.files.token.owner =
                lib.mkForce "root";
            };
        wrongMode =
          credentialRejects
            "Omnigent worker omnigent-cameron: credentials require private shared services files owned by the worker with mode 0400."
            {
              clan.core.vars.generators.omnigent-cameron-github-token-first.files.token.mode = lib.mkForce "0644";
            };
        privateBundle =
          credentialRejects
            "Omnigent worker omnigent-cameron: only the declared Clan vars ciphertext and delivered paths are allowed."
            {
              sops.secrets."vars/shared/omnigent-cameron-github-token-first/token".sopsFile = lib.mkForce (
                pkgs.writeText "synthetic-personal-bundle" "personal bundle fixture"
              );
            };
        inherit (cases)
          privateSecrets
          signer
          socket
          foreignHome
          ;
        agentForward =
          rejected "Omnigent worker capabilities must not inherit an SSH agent or signing socket."
            [
              { programs.ssh.matchBlocks."*".forwardAgent = true; }
            ];
        ageIdentity =
          rejected "Omnigent worker capabilities must not import personal sops secrets or templates."
            [
              inputs.sops-nix.homeManagerModules.sops
              { sops.age.keyFile = "${cfg.home.homeDirectory}/personal-age-key"; }
            ];
        bridgeEnrollment =
          pkgs.stdenv.isDarwin
          || credentialRejects "Omnigent worker cameron: personal age-bridge enrollment is prohibited." {
            options.hm-sops-bridge.users = lib.mkOption {
              type = lib.types.attrs;
              default = { };
            };
            config.hm-sops-bridge.users.omnigent-cameron.sopsIdentity = "cameron";
          };
        linuxReadiness =
          pkgs.stdenv.isDarwin
          || (
            let
              active = (credentialFixture [ { sops.useSystemdActivation = true; } ]).config;
              unit = active.systemd.services.omnigent-host-cameron;
              hm = active.systemd.services."home-manager-omnigent\\x2dcameron";
            in
            lib.all
              (
                service:
                lib.elem "sops-install-secrets.service" service.requires
                && lib.elem "sops-install-secrets.service" service.after
              )
              [
                unit
                hm
              ]
            && lib.elem "writeBoundary" active.home-manager.users.omnigent-cameron.home.activation.omnigentCredentialReadiness.before
          );
      };
    in
    {
      checks.omnigent-worker-credentials =
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
      checks.omnigent-worker-inventory =
        assert lib.assertMsg (lib.all
          (
            machine:
            lib.attrNames inventoryMachines.${machine}.config.services.omnigent-host.workers
            == expectedOwners.${machine}
          )
          (lib.attrNames expectedOwners)
        ) "Omnigent inventory requires exactly five declared human workers.";
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
      checks.omnigent-worker-darwin = lib.mkIf pkgs.stdenv.isDarwin (
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
              ${darwinWrongUser.system.build.launchd} \
              ${darwinWrongDomain.system.build.launchd} \
              ${(darwinMissingPath "/usr/bin:/bin").system.build.launchd} \
              ${
                (darwinMissingPath (
                  (lib.makeBinPath (config.flake.lib.omnigentRuntimePackages pkgs)) + ":/usr/bin:/bin:/usr/sbin:/sbin"
                )).system.build.launchd
              } \
              ${darwinControl.system.build.launchd} \
              ${darwin.system.activationScripts.script.source} \
              ${darwin.environment.etc."omnigent/workers/cameron".source}
            python3 ${darwinLauncherTest}
            mkdir "$out"
            cp artifacts.json "$out/"
          ''
      );
      checks.omnigent-worker-linux = lib.mkIf pkgs.stdenv.isLinux (
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
          ''
      );
      checks.omnigent-worker-capabilities =
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
}
