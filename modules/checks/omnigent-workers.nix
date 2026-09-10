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
    in
    {
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
