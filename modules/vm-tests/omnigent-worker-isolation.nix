# Runtime wiring of the Omnigent worker runtime-isolation guards.
#
# What this establishes, and only on a KVM-capable x86_64-linux host:
#   1. the private-home precondition is wired as ExecStartPre on the real
#      omnigent-host-<owner>.service, runs as the worker account against the home
#      that useradd and Home Manager produced, and a home that stops being private
#      at runtime prevents ExecStart from running at all;
#   2. the Nix daemon resolves a worker account as untrusted at runtime, which no
#      evaluation-time check can establish because the eval guard can only inspect
#      the declared trusted-users list;
#   3. two workers on one node have separate accounts and private homes on disk,
#      and neither can read the other's home;
#   4. the unit's declared hardening (User, UMask, NoNewPrivileges, and the
#      unsetting of SSH_AUTH_SOCK and SSH_AGENT_PID) is in effect in the process
#      systemd actually spawns, demonstrated against values injected into systemd's
#      default environment plus a control variable that is expected to survive.
#
# What this does NOT establish, and must never be described as establishing:
#   - It is not a sandbox and says nothing about confining hostile code running
#     inside a worker account. Every guard here is a precondition or a discretionary
#     permission, not a confinement boundary.
#   - It says nothing about stibnite or any Darwin host: there is no Darwin NixOS
#     test node type, and the Darwin lane is a launchd daemon this test never loads.
#   - ExecStart is a stub that records its invocation, so nothing here is evidence
#     about the real omnigent client.
#   - Credential delivery is out of scope. The workers declare no credentials, so
#     the Clan-vars-to-sops path and the cross-worker credential-path question are
#     untested here rather than faked with synthetic vars scaffolding.
#   - It lives in the non-gating vmTests lane and runs only when a KVM-capable
#     builder is reachable, so it is on-demand evidence, not coverage.
#
# The evaluation-time siblings remain the cheap, fleet-wide regulators:
# checks.<system>.omnigent-worker-linux already executes the emitted ExecStartPre
# script under a private HOME and rejects a wrong-owner, world-readable, or
# symlinked home, and the host module's assertions already require createHome with
# homeMode 0700 and a worker absent from nix.settings.trusted-users on every real
# machine. This test adds only the runtime wiring and resolution those cannot reach.
{ self, inputs, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      vmTests = lib.optionalAttrs pkgs.stdenv.hostPlatform.isLinux {
        omnigent-worker-isolation =
          let
            # The same package set every machine builds against: perSystem `pkgs`
            # omits the first-party pkgs-by-name attributes that the worker Home
            # Manager profile resolves, such as linear-cli.
            nodePkgs = import inputs.nixpkgs {
              inherit (pkgs.stdenv.hostPlatform) system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            # Effective fleet account shape, read from the machine that declares it
            # rather than restated here, so an inventory change cannot drift past
            # this test silently.
            reference = self.nixosConfigurations.pyrite.config;
            workers = {
              cameron = "omnigent-cameron";
              janettesmith = "omnigent-janettesmith";
            };
            account = user: {
              inherit (reference.users.users.${user})
                isNormalUser
                home
                homeMode
                createHome
                group
                hashedPassword
                shell
                ;
            };
            # Stands in for the Omnigent client: records each invocation inside the
            # worker's own home and then stays alive so the unit settles active.
            hostStub = pkgs.writeShellScriptBin "omnigent" ''
              set -eu
              printf 'start %s\n' "$*" >> "$HOME/omnigent-test.record"
              ${pkgs.coreutils}/bin/env > "$HOME/omnigent-test.env"
              exec ${pkgs.coreutils}/bin/sleep infinity
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "omnigent-worker-isolation";
            requiredFeatures = {
              kvm = true;
              nixos-test = true;
            };
            qemu.forceAccel = true;
            node.pkgs = lib.mkForce nodePkgs;
            nodes.machine = {
              imports = [
                inputs.home-manager.nixosModules.home-manager
                self.modules.nixos.omnigent-host
              ];
              system.stateVersion = lib.trivial.release;
              networking.hostName = "omnigent-isolation";
              nix.settings.experimental-features = [ "nix-command" ];
              home-manager = {
                useGlobalPkgs = true;
                useUserPackages = true;
                extraSpecialArgs.flake = self // {
                  inherit inputs;
                };
              };
              users.users = lib.mapAttrs' (_: user: lib.nameValuePair user (account user)) workers;
              users.groups = lib.mapAttrs' (_: user: lib.nameValuePair user { }) workers;
              # Injected into every unit's default environment so that the absence of
              # SSH_AUTH_SOCK and SSH_AGENT_PID in the spawned process is evidence
              # about UnsetEnvironment rather than evidence that nothing ever set
              # them. The control value must survive the same path.
              systemd.globalEnvironment = {
                SSH_AUTH_SOCK = "/run/omnigent-isolation-agent.sock";
                SSH_AGENT_PID = "4242";
                OMNIGENT_TEST_INHERITANCE_CONTROL = "default-environment";
              };
              services.omnigent-host = {
                serverUrl = "https://omnigent-isolation.invalid";
                package = hostStub;
                workers = lib.mapAttrs (owner: user: {
                  enable = true;
                  inherit owner user;
                }) workers;
              };
            };
            testScript = ''
              import json

              owners = {"cameron": "omnigent-cameron", "janettesmith": "omnigent-janettesmith"}

              def record_lines(user):
                  out = machine.succeed(f"cat /home/{user}/omnigent-test.record")
                  return [line for line in out.splitlines() if line]

              start_all()
              machine.wait_for_unit("multi-user.target")
              for owner, user in owners.items():
                  machine.wait_for_unit(f"omnigent-host-{owner}.service")

              with subtest("separate accounts and private homes on disk"):
                  uids = set()
                  for user in owners.values():
                      assert machine.succeed(f"stat -c %U /home/{user}").strip() == user
                      assert machine.succeed(f"stat -c %G /home/{user}").strip() == user
                      assert machine.succeed(f"stat -c %a /home/{user}").strip() == "700"
                      uids.add(machine.succeed(f"id -u {user}").strip())
                  assert len(uids) == len(owners), uids

              with subtest("neither worker can read the other's home"):
                  machine.fail("su -l omnigent-cameron -c 'ls /home/omnigent-janettesmith'")
                  machine.fail("su -l omnigent-janettesmith -c 'ls /home/omnigent-cameron'")
                  machine.fail(
                      "su -l omnigent-cameron -c "
                      "'cat /home/omnigent-janettesmith/omnigent-test.env'"
                  )

              with subtest("the nix daemon resolves a worker as untrusted"):
                  # The control asserts the probe can observe trust at all, so an
                  # untrusted verdict is not merely a missing field.
                  root = json.loads(machine.succeed("nix store ping --json"))
                  assert root.get("trusted", False), root
                  for user in owners.values():
                      seen = json.loads(
                          machine.succeed(f"su -l {user} -c 'nix store ping --json'")
                      )
                      assert not seen.get("trusted", False), (user, seen)

              with subtest("declared hardening is in effect in the spawned process"):
                  for owner, user in owners.items():
                      unit = f"omnigent-host-{owner}.service"
                      shown = dict(
                          line.split("=", 1)
                          for line in machine.succeed(
                              "systemctl show -p User -p UMask -p NoNewPrivileges "
                              f"-p UnsetEnvironment {unit}"
                          ).splitlines()
                          if "=" in line
                      )
                      assert shown["User"] == user, shown
                      assert shown["UMask"] == "0077", shown
                      assert shown["NoNewPrivileges"] == "yes", shown
                      assert machine.succeed(f"systemctl show -p MainPID --value {unit}").strip() != "0"
                      env = dict(
                          line.split("=", 1)
                          for line in machine.succeed(
                              f"cat /home/{user}/omnigent-test.env"
                          ).splitlines()
                          if "=" in line
                      )
                      assert env["OMNIGENT_TEST_INHERITANCE_CONTROL"] == "default-environment", env
                      assert "SSH_AUTH_SOCK" not in env, env
                      assert "SSH_AGENT_PID" not in env, env
                      assert env["USER"] == user, env
                      assert env["HOME"] == f"/home/{user}", env
                      assert machine.succeed(f"stat -c %U /home/{user}/omnigent-test.env").strip() == user

              with subtest("a home that stops being private at runtime prevents ExecStart"):
                  user = owners["cameron"]
                  unit = "omnigent-host-cameron.service"
                  machine.succeed(f"systemctl stop {unit}")
                  before = len(record_lines(user))
                  assert before == 1, before
                  machine.succeed(f"chmod 750 /home/{user}")
                  machine.succeed(f"systemctl reset-failed {unit}")
                  machine.fail(f"systemctl start {unit}")
                  machine.succeed(f"systemctl stop {unit}")
                  assert len(record_lines(user)) == before, record_lines(user)
                  # The second worker is untouched, so the failure is the mutated
                  # precondition rather than a node-wide breakage.
                  machine.require_unit_state("omnigent-host-janettesmith.service", "active")

              with subtest("restoring the home restores the start, proving the mutation caused it"):
                  user = owners["cameron"]
                  unit = "omnigent-host-cameron.service"
                  machine.succeed(f"chmod 700 /home/{user}")
                  machine.succeed(f"systemctl reset-failed {unit}")
                  machine.succeed(f"systemctl start {unit}")
                  machine.wait_for_unit(unit)
                  assert len(record_lines(user)) == 2, record_lines(user)
            '';
          };
      };
    };
}
