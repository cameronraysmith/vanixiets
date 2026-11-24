# checks.x86_64-linux.fleet-deployer-obligations: the judges of
# flake.lib.fleetDeployer (modules/lib/fleet-deployer.nix) over literal
# fixtures, each mutant expected to yield exactly one problem.
#
# - targetsFrom keeps only enabled, non-excluded NixOS and darwin machines.
# - policyProblems fails a disabled, excluded or non-system target and a
#   reach outside the role policy (shared server: operators; personal
#   machine: its primary user and the admin).
# - hostProblems fails a missing primary-user account, a non-target or a
#   second account carrying the deployer's key, a target without exactly the
#   restricted key line (on the deployer host, the line that also admits
#   loopback, F82; elsewhere, the line that does not), a deployer account whose keys are not the
#   requesters' forced-command lines, a deployer host whose key
#   directory or key generation is declared wider, and a darwin target whose
#   rollback watcher job is undeclared, bootstrapped outside launchd's system
#   domain, run as another user, kept alive or running another program (F84).
#
# Per-host facts are asserted by modules/checks/machines.nix on every
# nixos-<host> and darwin-<host> check, which already evaluates the
# configuration; no host is evaluated here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      d = self.lib.fleetDeployer;
      key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFixtureDeployerKeyFixtureDeployerKeyFix deployer";
      other = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIOtherOtherOtherOtherOtherOtherOtherOthe other";
      reqKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIRequesterRequesterRequesterRequesterReq req";
      line = d.targetKeyLine false key;
      deployerLine = d.targetKeyLine true key;
      requesterLines = [ (d.requestKeyLine "cameron" reqKey) ];
      deployerUnit = {
        keysUMask = d.keyUMask;
        tmpfiles = [ "d /var/lib/${d.account}/keys ${d.keyDirMode} ${d.account} ${d.account} -" ];
      };

      # policy fixtures
      inventory = {
        a = "nixos";
        b = "darwin";
        off = "nixos";
        ws = "darwin";
        phone = "android";
      };
      primaries = {
        a = null;
        b = "pat";
        off = null;
        ws = "op";
        phone = null;
      };
      policyArgs = {
        targets = [
          "a"
          "b"
        ];
        enabledOf = name: name != "off";
        excluded = [ "ws" ];
        classOf = name: inventory.${name};
        primaryUserOf = name: primaries.${name};
        operators = [
          "op"
          "ops2"
        ];
        admin = "op";
        reach = {
          op = [
            "a"
            "b"
          ];
          ops2 = [ "a" ];
          pat = [ "b" ];
        };
      };
      policyCases = {
        accepted = {
          args = policyArgs;
          problems = 0;
        };
        disabledTarget = {
          args = policyArgs // {
            targets = policyArgs.targets ++ [ "off" ];
          };
          problems = 1;
        };
        excludedTarget = {
          args = policyArgs // {
            targets = policyArgs.targets ++ [ "ws" ];
          };
          problems = 1;
        };
        phoneTarget = {
          args = policyArgs // {
            targets = policyArgs.targets ++ [ "phone" ];
          };
          problems = 1;
        };
        operatorOnPersonal = {
          args = policyArgs // {
            reach = policyArgs.reach // {
              ops2 = [
                "a"
                "b"
              ];
            };
          };
          problems = 1;
        };
        primaryOnShared = {
          args = policyArgs // {
            reach = policyArgs.reach // {
              pat = [
                "a"
                "b"
              ];
            };
          };
          problems = 1;
        };
      };
      derivedTargets =
        d.targetsFrom {
          inherit (policyArgs) enabledOf excluded classOf;
        } (lib.attrNames inventory) == [
          "a"
          "b"
        ];

      # host fixtures
      host = {
        name = "h";
        isTarget = true;
        isDarwin = false;
        deployUser = "root";
        primaryUser = null;
        sshPublicKey = key;
        inherit requesterLines;
        isDeployer = false;
        facts = {
          users = {
            root = [ line ];
            alice = [ other ];
          };
          deployerUnit = null;
          localSecrets = [
            {
              path = "sops/secrets/h-age.key";
              readable = true;
            }
            {
              path = "vars/per-machine/h/initrd-ssh/id_ed25519";
              readable = true;
            }
          ];
          watcher = null;
        };
      };
      deployer = host // {
        isTarget = true;
        facts = host.facts // {
          users = host.facts.users // {
            root = [ deployerLine ];
            ${d.account} = requesterLines;
          };
          inherit deployerUnit;
        };
        isDeployer = true;
      };
      macJob = {
        Label = "org.vanixiets.fleet-deploy-watch";
        ProgramArguments = [
          "/nix/store/00000000000000000000000000000000-fleet-deploy-watch/bin/fleet-deploy-watch"
          "--run"
        ];
        RunAtLoad = true;
        KeepAlive = false;
      };
      mac = host // {
        isDarwin = true;
        deployUser = "op";
        facts = host.facts // {
          users = {
            op = [ line ];
            alice = [ other ];
          };
          watcher = {
            domain = "system";
            job = macJob;
          };
        };
      };
      macWith =
        watcher:
        mac
        // {
          facts = mac.facts // {
            inherit watcher;
          };
        };
      hostCases = {
        activationVarWithoutGroup = {
          args = host // {
            facts = host.facts // {
              localSecrets = host.facts.localSecrets ++ [
                {
                  path = "vars/per-machine/h/new-activation/key";
                  readable = false;
                }
              ];
            };
          };
          problems = 1;
        };
        machineKeyWithoutGroup = {
          args = host // {
            facts = host.facts // {
              localSecrets = [
                {
                  path = "sops/secrets/h-age.key";
                  readable = false;
                }
              ];
            };
          };
          problems = 1;
        };
        acceptedTarget = {
          args = host;
          problems = 0;
        };
        acceptedNonTarget = {
          args = host // {
            isTarget = false;
            facts = host.facts // {
              users = removeAttrs host.facts.users [ "root" ];
            };
          };
          problems = 0;
        };
        acceptedDeployer = {
          args = deployer;
          problems = 0;
        };
        unprovisionedTarget = {
          args = host // {
            sshPublicKey = null;
            facts = host.facts // {
              users.root = [ ];
            };
          };
          problems = 0;
        };
        primaryWithoutAccount = {
          args = host // {
            primaryUser = "pat";
          };
          problems = 1;
        };
        nonTargetCarriesKey = {
          args = host // {
            isTarget = false;
          };
          problems = 1;
        };
        secondAccountCarriesKey = {
          args = host // {
            facts = host.facts // {
              users = host.facts.users // {
                alice = [ line ];
              };
            };
          };
          problems = 1;
        };
        unrestrictedLine = {
          args = host // {
            facts = host.facts // {
              users = host.facts.users // {
                root = [ key ];
              };
            };
          };
          problems = 1;
        };
        targetLacksKey = {
          args = host // {
            facts = host.facts // {
              users = host.facts.users // {
                root = [ ];
              };
            };
          };
          problems = 1;
        };
        deployerLineWithoutLoopback = {
          args = deployer // {
            facts = deployer.facts // {
              users = deployer.facts.users // {
                root = [ line ];
              };
            };
          };
          problems = 1;
        };
        targetLineWithLoopback = {
          args = host // {
            facts = host.facts // {
              users = host.facts.users // {
                root = [ deployerLine ];
              };
            };
          };
          problems = 1;
        };
        deployerExtraKey = {
          args = deployer // {
            facts = deployer.facts // {
              users = deployer.facts.users // {
                ${d.account} = requesterLines ++ [ other ];
              };
            };
          };
          problems = 1;
        };
        deployerWideKeyDir = {
          args = deployer // {
            facts = deployer.facts // {
              deployerUnit = deployerUnit // {
                tmpfiles = [ "d /var/lib/${d.account}/keys 0755 ${d.account} ${d.account} -" ];
              };
            };
          };
          problems = 1;
        };
        deployerWideUMask = {
          args = deployer // {
            facts = deployer.facts // {
              deployerUnit = deployerUnit // {
                keysUMask = "0077";
              };
            };
          };
          problems = 1;
        };
        deployerOutsideHost = {
          args = host // {
            facts = host.facts // {
              inherit deployerUnit;
            };
          };
          problems = 1;
        };
        macAccepted = {
          args = mac;
          problems = 0;
        };
        macWatcherUndeclared = {
          args = macWith null;
          problems = 1;
        };
        macWatcherInUserDomain = {
          args = macWith {
            domain = "gui/502";
            job = macJob;
          };
          problems = 1;
        };
        macWatcherAsDeployUser = {
          args = macWith {
            domain = "system";
            job = macJob // {
              UserName = "op";
            };
          };
          problems = 1;
        };
        macWatcherKeptAlive = {
          args = macWith {
            domain = "system";
            job = macJob // {
              KeepAlive = true;
            };
          };
          problems = 1;
        };
        macWatcherOtherProgram = {
          args = macWith {
            domain = "system";
            job = macJob // {
              ProgramArguments = [
                "/bin/sh"
                "-c"
                "true"
              ];
            };
          };
          problems = 1;
        };
      };

      wrongPolicy = lib.filterAttrs (
        _: case: lib.length (d.policyProblems case.args) != case.problems
      ) policyCases;
      wrongHost = lib.filterAttrs (
        _: case: lib.length (d.hostProblems case.args) != case.problems
      ) hostCases;
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        fleet-deployer-obligations = {
          class = "medium";
          measured = false;
        };
      };
      checks.fleet-deployer-obligations =
        assert lib.assertMsg derivedTargets
          "fleet-deployer-obligations: targetsFrom misderives the targets";
        assert lib.assertMsg (wrongPolicy == { } && wrongHost == { })
          "fleet-deployer-obligations: the judges misjudge ${
            toString (lib.attrNames wrongPolicy ++ lib.attrNames wrongHost)
          }";
        pkgs.runCommand "fleet-deployer-obligations" { } "touch $out";
    };
}
