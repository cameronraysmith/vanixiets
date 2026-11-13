# Profile-level relations and predicate controls for commit signing keys, the
# agent-free signing program's runtime behaviour, the valid-before round trip,
# and the scan of every sops recipient for a signing key's age image. Per-host
# facts are asserted by modules/checks/machines.nix through
# flake.lib.commitSigningObligations.failures; no host is evaluated here.
{ config, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      o = config.flake.lib.commitSigningObligations;
      users = config.flake.users;
      inherit (o) keyMaterial;
      program = lib.getExe (config.flake.lib.agentFreeSshKeygen pkgs);
      loginKeys = lib.concatMap (user: user.meta.sshKeys) (lib.attrValues users);
      signingKeys = lib.unique (
        lib.filter (key: key != null) (lib.mapAttrsToList (_: user: user.meta.signingKey) users)
      );

      apart =
        meta: login:
        !lib.elem (keyMaterial meta.signingKey) (
          map keyMaterial (login ++ map (retired: retired.key) meta.retiredSigningKeys)
        );
      crs58 = users.crs58.meta;

      fixtureKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureSigningKeyFixtureSigningKeyFixture0 fixture";
      host =
        {
          root ? [ ],
          user ? [ ],
          initrd ? [ ],
          keyFiles ? [ ],
          command ? "none",
          extra ? "AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u",
        }:
        {
          users.users = {
            root.openssh.authorizedKeys = {
              keys = root;
              keyFiles = [ ];
            };
            person.openssh.authorizedKeys = {
              keys = user;
              inherit keyFiles;
            };
          };
          boot.initrd.network.ssh = {
            enable = true;
            authorizedKeys = initrd;
            authorizedKeyFiles = [ ];
          };
          services.openssh = {
            authorizedKeysCommand = command;
            authorizedKeysFiles = [ "/etc/ssh/authorized_keys.d/%u" ];
            extraConfig = extra;
          };
        };
      denies =
        hostConfig:
        !o.unauthorized {
          isDarwin = false;
          inherit hostConfig;
          signingKeys = [ fixtureKey ];
        };

      goodGenerator = {
        share = true;
        prompts = { };
        files.key = {
          secret = true;
          owner = "cameron";
          mode = "0400";
        };
        files."key.pub".secret = false;
      };

      homeKey = "/run/secrets/vars/shared/fixture-commit-signing-key/key";
      homeProgram = "/nix/store/00000000000000000000000000000000-ssh-keygen/bin/ssh-keygen";
      homeMeta = {
        gitEmail = "a@example.invalid";
        signingKey = "ssh-ed25519 AAAAnew";
        retiredSigningKeys = [
          {
            key = "ssh-ed25519 AAAAold";
            validBefore = null;
          }
        ];
      };
      homeSigners = ''
        a@example.invalid namespaces="git" ssh-ed25519 AAAAnew
        a@example.invalid namespaces="git" ssh-ed25519 AAAAold
      '';
      home =
        {
          gitKey ? homeKey,
          jjKey ? homeKey,
          gitProgram ? homeProgram,
          signers ? homeSigners,
        }:
        {
          programs.git.signing = {
            key = gitKey;
            format = "ssh";
            signByDefault = true;
          };
          programs.git.settings.gpg.ssh.program = gitProgram;
          programs.jujutsu.settings.signing = {
            key = jjKey;
            behavior = "own";
            backend = "ssh";
            backends.ssh.program = homeProgram;
          };
          xdg.configFile."git/allowed_signers".text = signers;
        };
      bound =
        h:
        o.homeSigningBound {
          home = h;
          meta = homeMeta;
          program = homeProgram;
          keyPath = homeKey;
        };
      ubuntuHome = config.flake.homeConfigurations."ubuntu@x86_64-linux".config;

      cases = {
        profilesApart = lib.all (user: user.meta.signingKey == null || apart user.meta loginKeys) (
          lib.attrValues users
        );
        signingKeyIsLoginKey = !apart (crs58 // { signingKey = lib.head crs58.sshKeys; }) loginKeys;
        signingKeyIsRecommentedLoginKey =
          !apart (crs58 // { signingKey = "${keyMaterial (lib.head crs58.sshKeys)} other"; }) loginKeys;
        signingKeyIsOthersLoginKey =
          !apart (crs58 // { signingKey = lib.head users.janettesmith.meta.sshKeys; }) loginKeys;

        unauthorizedControl =
          !denies (host {
            user = [ (lib.head crs58.sshKeys) ];
          });
        keyInAccount = denies (host {
          user = [ fixtureKey ];
        });
        keyInRoot = denies (host {
          root = [ fixtureKey ];
        });
        keyInInitrd = denies (host {
          initrd = [ fixtureKey ];
        });
        keyRecommented = denies (host {
          user = [ "${keyMaterial fixtureKey} other" ];
        });
        keyFilesPresent = denies (host {
          keyFiles = [ "/etc/extra" ];
        });
        commandPresent = denies (host {
          command = "/bin/true";
        });
        extraFilePresent = denies (host {
          extra = "AuthorizedKeysFile /etc/ssh/authorized_keys.d/%u /etc/extra";
        });

        generatorControl = o.personGenerator {
          generator = goodGenerator;
          owner = "cameron";
        };
        generatorMissing =
          !o.personGenerator {
            generator = null;
            owner = "cameron";
          };
        generatorPrompted =
          !o.personGenerator {
            generator = goodGenerator // {
              prompts.key.type = "hidden";
            };
            owner = "cameron";
          };
        generatorWrongOwner =
          !o.personGenerator {
            generator = goodGenerator;
            owner = "root";
          };

        ubuntuHomeBound = o.homeSigningBound {
          home = ubuntuHome;
          meta = users.ubuntu.meta;
          inherit program;
          keyPath = ubuntuHome.sops.secrets.commit-signing-key.path;
        };
        homeControl = bound (home { });
        homeDarwinBranch =
          !bound (home {
            gitKey = "/Users/crs58/.config/sops-nix/secrets/ssh-public-key";
          });
        homeNoProgram =
          !bound (home {
            gitProgram = null;
          });
        homeJjRadicleKey =
          !bound (home {
            jjKey = "/Users/crs58/.radicle/keys/radicle";
          });
        homeMissingRetired =
          !bound (home {
            signers = ''
              a@example.invalid namespaces="git" ssh-ed25519 AAAAnew
            '';
          });

        presenceControl = o.signingKeyPresent {
          signingKey = null;
          legacy = true;
          recipients = [ ];
        };
        presenceGenerated = o.signingKeyPresent {
          signingKey = fixtureKey;
          legacy = true;
          recipients = [ "cinnabar" ];
        };
        nullKeyOffLegacy =
          !o.signingKeyPresent {
            signingKey = null;
            legacy = false;
            recipients = [ ];
          };
        nullKeyGeneratedElsewhere =
          !o.signingKeyPresent {
            signingKey = null;
            legacy = true;
            recipients = [ "cinnabar" ];
          };
        keyWithoutGeneration =
          !o.signingKeyPresent {
            signingKey = fixtureKey;
            legacy = true;
            recipients = [ ];
          };
        legacyListed = lib.all o.unenrolled config.flake.lib.commitSigningLegacyMachines;
        enrolledMachineListed = !o.unenrolled "magnetite";
      };
      failed = lib.attrNames (lib.filterAttrs (_: ok: !ok) cases);
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.commit-signing-key =
        assert lib.assertMsg (
          failed == [ ]
        ) "commit-signing-key cases failed: ${lib.concatStringsSep ", " failed}";
        pkgs.runCommand "commit-signing-key"
          {
            nativeBuildInputs = [
              pkgs.openssh
              pkgs.ssh-to-age
              pkgs.jq
              pkgs.yq-go
            ];
            signingKeys = lib.concatMapStrings (key: key + "\n") signingKeys;
            passAsFile = [ "signingKeys" ];
            tree = lib.fileset.toSource {
              root = ../..;
              fileset = lib.fileset.unions [
                ../../.sops.yaml
                ../../sops
                ../../secrets
                ../../vars
              ];
            };
          }
          ''
            set -euo pipefail
            export HOME=$TMPDIR
            cd "$TMPDIR"

            # The agent-free program never asks an agent holding the signing key.
            ssh-keygen -q -t ed25519 -N "" -C test -f key
            ssh-agent -d -a "$TMPDIR/agent.sock" 2> agent.log &
            agent=$!
            for _ in $(seq 50); do test -S agent.sock && break; sleep 0.1; done
            SSH_AUTH_SOCK=$TMPDIR/agent.sock ssh-add -c key
            echo payload > msg
            before=$(wc -l < agent.log)
            SSH_AUTH_SOCK=$TMPDIR/agent.sock ${program} -Y sign -f key -n git msg
            test "$(wc -l < agent.log)" -eq "$before" || { echo "agent-free program contacted the agent"; exit 1; }
            rm msg.sig
            before=$(wc -l < agent.log)
            SSH_AUTH_SOCK=$TMPDIR/agent.sock ssh-keygen -Y sign -f key -n git msg || true
            test "$(wc -l < agent.log)" -gt "$before" || { echo "mutant: plain ssh-keygen did not contact the agent"; exit 1; }
            kill "$agent"

            # A retired key's signature verifies before its valid-before bound and not after.
            ssh-keygen -q -t ed25519 -N "" -f old
            rm -f msg.sig
            ssh-keygen -Y sign -f old -n git msg
            printf 'a@example.invalid namespaces="git",valid-before="20260101000000Z" %s\n' "$(cut -d' ' -f1-2 old.pub)" > signers
            ${program} -Y verify -f signers -I a@example.invalid -n git -s msg.sig -Overify-time=20251231000000Z < msg
            if ${program} -Y verify -f signers -I a@example.invalid -n git -s msg.sig -Overify-time=20260102000000Z < msg; then
              echo "valid-before did not bound the retired key"; exit 1
            fi

            # No signing key is a sops recipient; every file is parsed in its sops format.
            while IFS= read -r line; do
              test -n "$line" || continue
              printf '%s\n' "$line" | ssh-to-age
            done < "$signingKeysPath" | sort -u > signing.age
            test "$(wc -l < signing.age)" -eq ${toString (lib.length signingKeys)}
            {
              grep -oE 'age1[0-9a-z]{58}' "$tree/.sops.yaml"
              for f in "$tree"/sops/users/*/key.json "$tree"/sops/machines/*/key.json; do
                jq -er '.[].publickey' "$f"
              done
              find "$tree/secrets" -type f ! -name '.*' -print0 | while IFS= read -r -d "" f; do
                case "$f" in
                  *.yaml | *.yml) yq -e '.sops.age[].recipient' "$f" ;;
                  *) jq -er '.sops.age[].recipient' "$f" ;;
                esac || { echo "not parseable in its sops format: $f" >&2; exit 1; }
              done
              find "$tree/vars" -type f -name secret -print0 | while IFS= read -r -d "" f; do
                jq -er '.sops.age[].recipient' "$f" || { echo "not parseable in its sops format: $f" >&2; exit 1; }
              done
            } | sort -u > recipients
            test -s recipients
            if comm -12 signing.age recipients | grep .; then
              echo "a signing key is a sops recipient"; exit 1
            fi
            { cat recipients; head -n1 signing.age; } | sort -u > fixture
            comm -12 signing.age fixture | grep -q . || { echo "mutant: recipient scan missed a planted recipient"; exit 1; }

            touch "$out"
          '';
    };
}
