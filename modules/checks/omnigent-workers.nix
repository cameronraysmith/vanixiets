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
    in
    {
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
