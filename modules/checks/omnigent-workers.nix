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
      cases = {
        composition = valid home;
        tools = cfg.programs.ripgrep.enable && cfg.programs.fd.enable && cfg.programs.gh.enable;
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
      inventoryMachines = {
        inherit (config.flake.nixosConfigurations) magnetite pyrite;
        inherit (config.flake.darwinConfigurations) stibnite;
      };
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
        allDisabled = lib.all (
          d: lib.all (w: !w.enable) (lib.attrValues d.config.services.omnigent-host.workers)
        ) (lib.attrValues inventoryMachines);
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
              programs.git.settings.commit.gpgSign = true;
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
    in
    {
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
            test "$(worker-profile-only)" = worker-profile
            if ${cfg.home.path}/bin/node; then exit 1; else test "$?" = 99; fi
            test "$(command -v node)" = ${pkgs.nodejs_22}/bin/node
            node --version
            for executable in rg fd gh linear atomic omp pi claude codex nix direnv; do
              test -x "$(command -v "$executable")"
            done
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
