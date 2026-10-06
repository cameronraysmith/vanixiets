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
      failedCases = cases: lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
      sortedEqual = a: b: lib.sort builtins.lessThan a == lib.sort builtins.lessThan b;

      # Capabilities: one positive worker home and one composite invalid home. The four
      # worker guards hold positively on every real worker home through the machine checks;
      # only the negative direction needs a fixture.
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
                if pkgs.stdenv.hostPlatform.isDarwin then "/Users/omnigent-fixture" else "/home/omnigent-fixture";
              home.stateVersion = "25.11";
            }
          ]
          ++ extra;
        };
      # An unsigned author, a documentation mention of a foreign path and a synthetic
      # credential policy must all stay accepted by the guards.
      home = mkHome [
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
          programs.git.settings = {
            user.name = "Worker fixture";
            user.email = "worker@example.invalid";
            commit.gpgSign = false;
            tag.gpgSign = "off";
          };
          programs.jujutsu.settings.user = {
            name = "Worker fixture";
            email = "worker@example.invalid";
          };
          home.file."example.md".text =
            "Documentation example: /home/human/project is an example path, not an input.";
        }
      ];
      cfg = home.config;
      # Home Manager throws on any failed assertion before `config` is readable, so the
      # failure set is only observable through an apply that neutralises the assertions.
      observedAssertions = {
        options.assertions = lib.mkOption {
          apply = map (
            a:
            a
            // {
              failed = !a.assertion;
              assertion = true;
            }
          );
        };
      };
      capabilityInvalid = [
        observedAssertions
        inputs.sops-nix.homeManagerModules.sops
        (
          { lib, ... }:
          {
            sops = {
              age.keyFile = "${cfg.home.homeDirectory}/fixture-age";
              secrets.personal.sopsFile = pkgs.writeText "fixture-secret.yaml" "personal: fixture";
            };
            programs.git = {
              signing = {
                key = "${cfg.home.homeDirectory}/signing-key";
                signByDefault = true;
              };
              settings = lib.mkForce [
                { user.name = "Worker fixture"; }
                {
                  user.signingKey = "${cfg.home.homeDirectory}/private-signing-key";
                  commit.gpgSign = true;
                }
                { tag.gpgSign = "yes"; }
                {
                  COMMIT.GPGSIGN = [
                    false
                    1
                  ];
                }
              ];
            };
            programs.atomic = {
              configDir = "/Users/human/.atomic/agent";
              settings.packages = lib.mkForce [ "/home/human/extensions" ];
            };
            home = {
              sessionVariables.SSH_AUTH_SOCK = "/run/user/1000/agent";
              file.foreign.source = "/home/human/private";
              activation.foreignInput = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
                cat /home/human/config
              '';
            };
          }
        )
      ];
      capabilityMessages = [
        "Omnigent worker capabilities must not import personal sops secrets or templates."
        "Omnigent worker capabilities do not grant Git or Jujutsu signing authority."
        "Omnigent worker capabilities must not inherit an SSH agent or signing socket."
        "Omnigent worker configuration must use its own home, not a foreign human home."
      ];
      workerPath = lib.splitString ":" (
        config.flake.lib.omnigentWorkerPath {
          inherit pkgs;
          home = cfg;
        }
      );
      pathIndex = entry: lib.lists.findFirstIndex (e: e == entry) null workerPath;
      acp = config.flake.lib.omnigentACP;
      cases = {
        composition = lib.all (a: a.assertion) cfg.assertions;
        compositeInvalid = sortedEqual (map (a: a.message) (
          lib.filter (a: a.failed) (mkHome capabilityInvalid).config.assertions
        )) capabilityMessages;
        workerACPApproval =
          cfg.programs.omnigent.settings.acp == {
            agents = [
              (builtins.head acp.agents)
              ((builtins.elemAt acp.agents 1) // { command = "omp acp --approval-mode yolo"; })
            ];
          };
        runtimeBeforeProfile = pathIndex "${pkgs.nodejs_22}/bin" < pathIndex "${cfg.home.path}/bin";
        credentialWrapperPrecedence =
          pathIndex "${cfg.programs.gh.package}/bin" != null
          && pathIndex "${pkgs.gh}/bin" == null
          && pathIndex "${cfg.programs.claude-code.package}/bin" == 0;
        tools = cfg.programs.ripgrep.enable && cfg.programs.fd.enable && cfg.programs.gh.enable;
        browserAutomation =
          lib.elem pkgs.playwright-cli cfg.home.packages
          &&
            toString cfg.programs.claude-code.skills.playwright-cli
            == "${cfg.aiSkills.composed}/.claude/skills/playwright-cli"
          && !(cfg.aiSkills.extraSkills ? playwright-cli);
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
        harnesses =
          cfg.programs.atomic.enable
          && cfg.programs.omp.enable
          && cfg.programs.pi-coding-agent.enable
          && cfg.programs.claude-code.enable;
        linear = lib.elem pkgs.linear-cli cfg.home.packages;
        skills = cfg.home.file."${cfg.home.homeDirectory}/.claude/skills/linear-cli".enable;
        githubHelper = cfg.programs.gh.gitCredentialHelper.enable;
      };

      # Linux: one container NixOS fixture. Cameron is enabled and violates the private
      # home, admin-group, trusted-user and environment guards; Raquel stays disabled and
      # aliases the wheel gid. The same evaluation supplies the composite message set, the
      # disabled-worker preparation, Cameron's emitted ExecStartPre and his ACP settings.
      linux =
        (inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            inputs.home-manager.nixosModules.home-manager
            config.flake.modules.nixos.omnigent-host
            (
              { config, ... }:
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
                users.users.omnigent-cameron = {
                  isNormalUser = true;
                  home = "/home/omnigent-cameron";
                  group = "omnigent-cameron";
                  homeMode = "0755";
                  extraGroups = [ "wheel" ];
                };
                users.users.omnigent-raquel = {
                  isNormalUser = true;
                  home = "/home/omnigent-raquel";
                  group = "omnigent-raquel";
                };
                users.groups.omnigent-cameron = { };
                # NixOS rejects duplicate gids unless uniqueness enforcement is off, so this is the declarable form of the runtime alias.
                users.enforceIdUniqueness = false;
                users.groups.omnigent-raquel.gid = config.users.groups.wheel.gid;
                nix.settings.trusted-users = [
                  "omnigent-cameron"
                  "@wheel"
                ];
                services.omnigent-host = {
                  serverUrl = "https://fixture.invalid";
                  workers.cameron = {
                    enable = true;
                    owner = "cameron";
                    user = "omnigent-cameron";
                    environment.NIX_CONFIG = "foreign";
                  };
                  workers.raquel = {
                    owner = "raquel";
                    user = "omnigent-raquel";
                  };
                };
              }
            )
          ];
        }).config;
      linuxMessages = [
        "Omnigent worker cameron: requires a private distinct home and home-local workspace."
        "Omnigent worker cameron: administrative groups or sudo grants are prohibited."
        "Omnigent worker cameron: Nix trusted-user authority is prohibited."
        "Omnigent worker cameron: environment cannot override identity, state or authority selectors."
        "Omnigent worker raquel: administrative groups or sudo grants are prohibited."
        "Omnigent worker raquel: Nix trusted-user authority is prohibited."
      ];
      linuxCases = {
        compositeInvalid = sortedEqual (map (a: a.message) (
          lib.filter (a: !a.assertion) linux.assertions
        )) linuxMessages;
        disabledPrepared =
          !(linux.systemd.services ? omnigent-host-raquel)
          && linux.home-manager.users.omnigent-raquel.programs.omnigent.enable
          && builtins.hasAttr "home-manager-omnigent\\x2draquel" linux.systemd.services;
        noLegacyFallback = !(linux.systemd.services ? omnigent-host);
      };
      privateHome = linux.systemd.services.omnigent-host-cameron.serviceConfig.ExecStartPre;
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

      # Darwin: one nix-darwin fixture whose worker holds an administrative group and Nix
      # trust, and whose omnigent package is a canary asserting the launch environment.
      # Plist and account facts are fleet obligations on stibnite.
      profileOnly = pkgs.writeShellScriptBin "worker-profile-only" "echo worker-profile";
      shadow = pkgs.writeShellScriptBin "node" "exit 99";
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
      darwin =
        (inputs.nix-darwin.lib.darwinSystem {
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
              users.groups.admin = {
                gid = 80;
                members = [ "omnigent-cameron" ];
              };
              users.users.omnigent-cameron = {
                uid = 22001;
                gid = 22001;
                home = "/Users/omnigent-cameron";
                createHome = true;
              };
              nix.settings.trusted-users = [ "omnigent-cameron" ];
              services.omnigent-host = {
                serverUrl = "https://fixture.invalid";
                package = darwinHostCanary;
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
          ];
        }).config;
      darwinMessages = [
        "Omnigent worker cameron: administrative groups are prohibited."
        "Omnigent worker cameron: Nix trusted-user authority is prohibited."
      ];
      darwinCases = {
        compositeInvalid = sortedEqual (map (a: a.message) (
          lib.filter (a: !a.assertion) darwin.assertions
        )) darwinMessages;
      };
      darwinDaemon = darwin.launchd.daemons.omnigent-host-cameron;
      darwinPrepareTest = pkgs.writeText "omnigent-darwin-prepare-home.py" ''
        import os
        from pathlib import Path
        import shlex
        import subprocess
        import sys

        worker_home = "/Users/omnigent-cameron"
        launchd = Path(sys.argv[1]).read_text()
        preparation_lines = [line for line in launchd.splitlines() if "-omnigent-prepare-darwin-home " in line]
        assert len(preparation_lines) == 1
        invocation = shlex.split(preparation_lines[0])
        assert invocation[:5] == ["/usr/bin/sudo", "-u", "omnigent-cameron", "--set-home", "--"], "preparation must run as the worker"
        prepare, user, uid, gid, home = invocation[5:]
        assert [user, uid, gid, home] == ["omnigent-cameron", "22001", "22001", worker_home]
        assert launchd.index(preparation_lines[0]) < launchd.index("setting up launchd services")
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
      '';
      darwinLauncherTest = pkgs.writeText "omnigent-darwin-launcher-test.py" ''
        import json
        import os
        from pathlib import Path
        import re
        import shlex
        import subprocess
        import sys

        launcher = sys.argv[1]
        script = Path(launcher).read_text()
        activations = re.findall(r"^(/nix/store/[^\n ]+/activate)$", script, re.M)
        assert len(activations) == 1
        activation = activations[0]
        env = os.environ | json.loads(Path(sys.argv[2]).read_text())
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
        assert script.count(activation + "\n") == 1
        mutant.write_text(script.replace(activation + "\n", activation + " || true\n"))
        assert run(42, source=str(mutant)).returncode == 0
        assert (home / "host-executed").exists(), "activation-failure mutant did not discriminate"
      '';

      inventoryRoles = config.flake.clan.inventory.instances.omnigent.roles;
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

      # Pure credential policy over a synthetic vars-shaped view, the form the host adapter
      # derives from Clan generators and SOPS placeholders. Real-host delivery and Home
      # Manager wiring are fleet obligations; the consumer's runtime logic is the
      # in-process unit test `omnigent-credentials-unit`.
      credentialRoot = "/synthetic/omnigent-credentials";
      credentialHomePath = "${credentialRoot}/home";
      credentialsOf =
        definition:
        (lib.evalModules {
          modules = [
            {
              options.credentials = lib.mkOption {
                type = lib.types.submodule { options = config.flake.lib.omnigentWorkerCredentialOptions; };
              };
            }
            { credentials = definition; }
          ];
        }).config.credentials;
      credentialGithubOwners = [
        "first"
        "second"
      ];
      credentialVar = generator: file: {
        path = "${credentialRoot}/${generator}-${file}";
        placeholder = "<SYNTHETIC:${generator}/${file}>";
      };
      credentialVars =
        lib.genAttrs [ "fixture-signing" "fixture-claude" ] (generator: {
          credential = credentialVar generator "credential";
        })
        //
          lib.genAttrs (map (owner: "omnigent-cameron-github-token-${owner}") credentialGithubOwners)
            (generator: {
              token = credentialVar generator "token";
            })
        // lib.genAttrs [ "omnigent-cameron-linear-personal" "omnigent-cameron-linear-work" ] (
          generator:
          lib.genAttrs [
            "key"
            "workspace"
            "workspace-id"
            "viewer-email"
          ] (credentialVar generator)
        );
      credentialPolicy =
        definition: linearRendered:
        config.flake.lib.omnigentCredentialPolicy {
          inherit pkgs linearRendered;
          credentials = credentialsOf definition;
          vars = credentialVars;
          home = credentialHomePath;
          serverUrl = "https://fixture.invalid";
        };
      credentialSource = name: {
        enable = true;
        generator = "fixture-${name}";
        file = "credential";
      };
      credentialLinearKey = label: {
        enable = true;
        generator = "omnigent-cameron-linear-${label}";
      };
      workerCredentials = {
        signingKey = credentialSource "signing";
        githubTokens = lib.genAttrs credentialGithubOwners (owner: {
          enable = true;
          generator = "omnigent-cameron-github-token-${owner}";
          expectedLogin = "fixture-human";
        });
        defaultOwner = "first";
        claudeSetupToken = credentialSource "claude";
        linearApiKeys.personal = credentialLinearKey "personal";
        expected = {
          gitEmail = "fixture@example.invalid";
          omnigentEmail = "fixture@example.invalid";
          signingPublicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdamAGCsQq31Uv+08lkBzoO4XLz2qYjJa8CGmj3B1Ea";
        };
      };
      credentialRendered = "${credentialRoot}/rendered-linear";
      credentialDelivery = credentialPolicy workerCredentials credentialRendered;
      loginHelper = builtins.readFile ../apps/omnigent-worker-login.sh;
      offsetOf = infix: lib.stringLength (lib.head (lib.splitString infix loginHelper));
      credentialPolicyCases = {
        # Only the masked labels are accepted; the option's `apply` rejects any other name.
        maskedLinearLabels =
          let
            accepts =
              label:
              let
                keys = (credentialsOf { linearApiKeys.${label}.enable = false; }).linearApiKeys;
                probe = builtins.tryEval (builtins.attrNames keys == [ label ] && !keys.${label}.enable);
              in
              probe.success && probe.value;
          in
          accepts "personal" && accepts "work" && !accepts "synthetic-workspace-slug";
        defaultOff = config.flake.lib.omnigentCredentialSelection (credentialsOf { }) == { };
        # Disabled sources stay declared but are neither selected, required nor exposed.
        disabledSourcesOmitted =
          let
            policy =
              (credentialPolicy (
                workerCredentials
                // {
                  signingKey = credentialSource "signing" // {
                    enable = false;
                  };
                  githubTokens = workerCredentials.githubTokens // {
                    second = workerCredentials.githubTokens.second // {
                      enable = false;
                    };
                  };
                  claudeSetupToken = credentialSource "claude" // {
                    enable = false;
                  };
                  linearApiKeys = {
                    personal = credentialLinearKey "personal";
                    work = credentialLinearKey "work" // {
                      enable = false;
                    };
                  };
                }
              ) credentialRendered).policy;
            disabled = [
              credentialVars.fixture-signing.credential.path
              credentialVars.fixture-claude.credential.path
              credentialVars.omnigent-cameron-github-token-second.token.path
            ]
            ++ map (file: file.path) (lib.attrValues credentialVars.omnigent-cameron-linear-work);
          in
          policy.signingKey == null
          && policy.claudeSetupToken == null
          && lib.attrNames policy.githubTokens == [ "first" ]
          && lib.attrNames policy.linearApiKeys == [ "personal" ]
          && !lib.any (path: lib.elem path policy.requiredFiles) disabled
          && lib.elem credentialVars.omnigent-cameron-github-token-first.token.path policy.requiredFiles;
        # Readiness waits for the rendered template; the Home Manager link to it is created later.
        linearRequiresRendered =
          let
            policy = credentialDelivery.policy;
          in
          lib.elem credentialRendered policy.requiredFiles
          && policy.linearCredentials == "${credentialHomePath}/.config/linear/credentials.toml"
          && !lib.elem policy.linearCredentials policy.requiredFiles;
        # Without Linear grants the host has no rendered template, so the policy must not read one.
        # The probe forces exactly the fields that could read the throwing `linearRendered`.
        noLinearNoTemplate =
          let
            delivery = credentialPolicy (workerCredentials // { linearApiKeys = { }; }) (
              throw "rendered Linear template read without Linear grants"
            );
            probe = builtins.tryEval (
              delivery.policy.linearCredentials == null
              && builtins.all builtins.isString delivery.policy.requiredFiles
              && delivery.linearTemplate == null
            );
          in
          probe.success && probe.value;
        # The interactive login helper unlocks the worker Keychain before running the command.
        loginKeychainBeforeExec =
          offsetOf "omnigent-worker-keychain || exit" < offsetOf ''exec "$@"''
          && offsetOf ''exec "$@"'' < lib.stringLength loginHelper;
      };
    in
    {
      checks = {
        omnigent-worker-capabilities =
          assert lib.assertMsg (
            failedCases cases == [ ]
          ) "omnigent worker capability failures: ${lib.concatStringsSep ", " (failedCases cases)}";
          pkgs.runCommand "omnigent-worker-capabilities" { passthru = { inherit cases; }; } ''
            for executable in pi atomic omp claude; do
              test -x ${cfg.home.path}/bin/$executable
            done
            ${lib.getExe pkgs.playwright-cli} --version | grep -Fx ${lib.escapeShellArg pkgs.playwright-cli.version}
            touch "$out"
          '';
      }
      // lib.optionalAttrs (system == "x86_64-linux") {
        omnigent-worker-inventory = config.flake.lib.mkStructuralCheck pkgs {
          name = "omnigent-worker-inventory";
          actual = inventoryCases;
          expected = lib.mapAttrs (_: _: true) inventoryCases;
        };
        omnigent-credential-policy = config.flake.lib.mkStructuralCheck pkgs {
          name = "omnigent-credential-policy";
          actual = credentialPolicyCases;
          expected = lib.mapAttrs (_: _: true) credentialPolicyCases;
        };
        omnigent-credentials-unit = pkgs.runCommand "omnigent-credentials-unit" { } ''
          ${pkgs.python3.interpreter} ${../home/ai/omnigent/credentials-test.py} \
            ${../home/ai/omnigent/credentials.py} \
            ${../home/ai/omnigent/delivery.py} \
            ${../home/ai/omnigent/delivery-fixtures.py} \
            ${../home/ai/omnigent/keychain.py} \
            ${../home/ai/omnigent/keychain-fixtures.py}
          touch "$out"
        '';
        omnigent-worker-linux =
          assert lib.assertMsg (failedCases linuxCases == [ ])
            "Omnigent Linux failures: ${lib.concatStringsSep ", " (failedCases linuxCases)}; module assertions: ${
              builtins.toJSON (map (a: a.message) (lib.filter (a: !a.assertion) linux.assertions))
            }";
          pkgs.runCommand "omnigent-worker-linux" { passthru.cases = linuxCases; } ''
            export HOME="$TMPDIR/private"
            ${pkgs.coreutils}/bin/mkdir -m 700 "$HOME"
            ${privateHome}
            uid="$(${pkgs.coreutils}/bin/id -u)"
            ${homeUidFixture} ${privateHome} "$uid"
            if ${homeUidFixture} ${privateHome} "$((uid + 1))"; then
              echo "accepted a wrong-owner worker home (UID-observation fixture)" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/chmod 755 "$HOME"
            if ${privateHome}; then
              echo "accepted a public worker home" >&2
              exit 1
            fi
            ${pkgs.coreutils}/bin/chmod 700 "$HOME"
            ${pkgs.coreutils}/bin/ln -s "$HOME" "$TMPDIR/linked"
            export HOME="$TMPDIR/linked"
            if ${privateHome}; then
              echo "accepted a symlinked worker home" >&2
              exit 1
            fi
            ${pkgs.omnigent.python.interpreter} ${sandboxSelectionTest}
            ${pkgs.coreutils}/bin/touch "$out"
          '';
      }
      // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
        omnigent-worker-darwin =
          assert lib.assertMsg (failedCases darwinCases == [ ])
            "Omnigent Darwin failures: ${builtins.toJSON (failedCases darwinCases)}; assertions: ${
              builtins.toJSON (map (a: a.message) (lib.filter (a: !a.assertion) darwin.assertions))
            }";
          pkgs.runCommand "omnigent-worker-darwin"
            {
              nativeBuildInputs = [ pkgs.python3 ];
              passthru.cases = darwinCases;
              passAsFile = [ "launchd" ];
              launchd = darwin.system.activationScripts.launchd.text;
            }
            ''
              python3 ${darwinPrepareTest} "$launchdPath"
              python3 ${darwinLauncherTest} ${darwinDaemon.command} ${pkgs.writeText "omnigent-darwin-environment.json" (builtins.toJSON darwinDaemon.serviceConfig.EnvironmentVariables)}
              touch "$out"
            '';
      };
    };
}
