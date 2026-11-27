# Runtime wiring of the Omnigent worker runtime-isolation guards and of
# per-worker container access.
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
#      default environment plus a control variable that is expected to survive;
#   5. container access is per worker and survives that hardening: one worker
#      selects containers.engine = "rootless-podman" and incus = "restricted", the
#      other keeps the defaults. The rootless worker's spawned process carries
#      XDG_RUNTIME_DIR, DOCKER_HOST, CONTAINER_HOST and the extended runner
#      passthrough list, and the default worker's carries none of them. Its
#      lingering user manager holds podman.socket listening with podman.service
#      inactive until first use. From a cold start (no pause process), under
#      NoNewPrivileges and the unit's own environment, a dockerTools image loaded
#      offline runs through the docker CLI via DOCKER_HOST and through the podman
#      CLI in remote mode via CONTAINER_HOST. Neither worker can open the rootful
#      /run/podman/podman.sock, the default worker cannot reach the rootless
#      worker's socket, the rootless worker is confined to its own restricted
#      Incus project, and the default worker cannot reach either Incus socket.
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
#   - It never launches an Incus instance: that needs a network image, so the
#     restricted project is shown to exist and confine the worker, not to run
#     workloads. Nothing pulls from a registry either; the only container image
#     is built with dockerTools and loaded from the store.
#   - Rootless podman runs here inside one VM with its own kernel; it says
#     nothing about a host's subuid ranges, cgroup delegation or storage driver
#     beyond what this VM's defaults provide.
#
# The evaluation-time siblings remain the cheap, fleet-wide regulators:
# checks.x86_64-linux.omnigent-worker-linux already executes the emitted ExecStartPre
# script under a private HOME and rejects a wrong-owner, world-readable, or
# symlinked home, and the host module's assertions already require createHome with
# homeMode 0700 and a worker absent from nix.settings.trusted-users on every real
# machine. This test adds only the runtime wiring and resolution those cannot reach.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      fleetPkgs,
      ...
    }:
    let
      # The test's name depends on `system` alone, so reading the vmTests
      # names instantiates no nixpkgs (declare-test-size-classes design D5).
      linux = lib.elem system [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      # Size class: on x86_64-linux the script measured 27 to 39 s on pyrite
      # (logs/vmtest-worker-isolation-20261116-131043.log). The fleet has no
      # aarch64-linux builder, so no run can measure that system's test, which
      # is declared medium and unmeasured (declare-test-size-classes design D4).
      testSizes.vmTests =
        lib.optionalAttrs (system == "x86_64-linux") {
          omnigent-worker-isolation.class = "small";
        }
        // lib.optionalAttrs (system == "aarch64-linux") {
          omnigent-worker-isolation = {
            class = "medium";
            measured = false;
          };
        };
      vmTests = lib.optionalAttrs linux {
        omnigent-worker-isolation =
          let
            # The same package set every machine builds against: perSystem `pkgs`
            # omits the first-party pkgs-by-name attributes that the worker Home
            # Manager profile resolves, such as linear-cli.
            nodePkgs = fleetPkgs;
            # Effective fleet account shape, read from the machine that declares it
            # rather than restated here, so an inventory change cannot drift past
            # this test silently.
            reference = self.nixosConfigurations.pyrite.config;
            workers = {
              cameron = "omnigent-cameron";
              janettesmith = "omnigent-janettesmith";
            };
            # The worker that selects container access; the other keeps the
            # defaults and serves as the control.
            containerOwner = "cameron";
            containerUser = workers.${containerOwner};
            account = user: {
              inherit (reference.users.users.${user})
                uid
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
            # Offline image: dockerTools packs the closure of its command, so no
            # registry is reachable or needed.
            probeImage = pkgs.dockerTools.buildLayeredImage {
              name = "omnigent-probe";
              tag = "test";
              config.Cmd = [ "${pkgs.hello}/bin/hello" ];
            };
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
                  containers = lib.mkIf (owner == containerOwner) {
                    engine = "rootless-podman";
                    incus = "restricted";
                  };
                }) workers;
              };
              # Room for the Incus daemon and a rootless podman service.
              virtualisation.memorySize = 2048;
              # The rootful socket the workers must stay out of, and the per-user
              # podman.socket the rootless worker uses.
              virtualisation.podman.enable = true;
              # Incus refuses the iptables firewall. The preseed gives incus-user a
              # storage pool and network to build each restricted project from.
              networking.nftables.enable = true;
              virtualisation.incus = {
                enable = true;
                preseed = {
                  networks = [
                    {
                      name = "incusbr0";
                      type = "bridge";
                      config = {
                        "ipv4.address" = "10.0.100.1/24";
                        "ipv4.nat" = "true";
                        "ipv6.address" = "none";
                      };
                    }
                  ];
                  storage_pools = [
                    {
                      name = "default";
                      driver = "dir";
                    }
                  ];
                  profiles = [
                    {
                      name = "default";
                      devices = {
                        eth0 = {
                          name = "eth0";
                          network = "incusbr0";
                          type = "nic";
                        };
                        root = {
                          path = "/";
                          pool = "default";
                          type = "disk";
                        };
                      };
                    }
                  ];
                };
              };
            };
            testScript = ''
              import json
              import shlex

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

              rootless = "${containerUser}"
              control = next(u for u in owners.values() if u != rootless)
              rootless_uid = "${toString reference.users.users.${containerUser}.uid}"
              runtime_dir = f"/run/user/{rootless_uid}"
              socket = f"unix://{runtime_dir}/podman/podman.sock"
              probe_image = "${probeImage}"

              def as_worker(user, command, expect_success=True):
                  # The unit's own process environment, account and NoNewPrivileges,
                  # which is what a session forked from the runner inherits.
                  owner = next(o for o, u in owners.items() if u == user)
                  pid = machine.succeed(
                      f"systemctl show -p MainPID --value omnigent-host-{owner}.service"
                  ).strip()
                  machine.succeed(f"tr '\\0' '\\n' < /proc/{pid}/environ > /run/{user}.env")
                  run = (
                      "systemd-run --quiet --wait --pipe --collect "
                      f"-p User={user} -p Group={user} -p NoNewPrivileges=yes "
                      f"-p EnvironmentFile=/run/{user}.env -p WorkingDirectory=/home/{user} "
                      f"-- /bin/sh -c {shlex.quote(command)}"
                  )
                  return machine.succeed(run) if expect_success else machine.fail(run)

              def user_unit_state(unit):
                  # setpriv rather than `systemctl --user -M`, whose stdio bridge opens
                  # a PAM login session for the worker.
                  return machine.execute(
                      f"setpriv --reuid={rootless} --regid={rootless} --init-groups "
                      f"env XDG_RUNTIME_DIR={runtime_dir} systemctl --user is-active {unit}"
                  )[1].strip()

              def recorded_env(user):
                  return dict(
                      line.split("=", 1)
                      for line in machine.succeed(f"cat /home/{user}/omnigent-test.env").splitlines()
                      if "=" in line
                  )

              with subtest("container environment reaches only the rootless worker"):
                  env = recorded_env(rootless)
                  assert env["XDG_RUNTIME_DIR"] == runtime_dir, env
                  assert env["DOCKER_HOST"] == socket, env
                  assert env["CONTAINER_HOST"] == socket, env
                  assert env["OMNIGENT_RUNNER_ENV_PASSTHROUGH"] == "DOCKER_HOST,CONTAINER_HOST", env
                  assert "/run/wrappers/bin" in env["PATH"].split(":"), env
                  env = recorded_env(control)
                  for name in ("XDG_RUNTIME_DIR", "DOCKER_HOST", "CONTAINER_HOST"):
                      assert name not in env, (name, env)
                  assert "OMNIGENT_RUNNER_ENV_PASSTHROUGH" not in env, env
                  # Atomic's state selectors belong to its ACP command, not the unit.
                  for worker in (rootless, control):
                      env = recorded_env(worker)
                      for name in ("PI_ACP_PI_COMMAND", "PI_CODING_AGENT_DIR"):
                          assert name not in env, (worker, name, env)

              with subtest("the lingering user manager holds podman socket-activated and cold"):
                  machine.wait_for_unit(f"user@{rootless_uid}.service")
                  machine.wait_for_file(f"{runtime_dir}/podman/podman.sock")
                  assert user_unit_state("podman.socket") == "active"
                  assert user_unit_state("podman.service") == "inactive"
                  machine.fail(f"pgrep -u {rootless} podman")
                  # The control worker selects nothing, so it has no user manager.
                  machine.fail(f"test -e /run/user/$(id -u {control})")

              with subtest("cold start under NoNewPrivileges needs the remote podman CLI"):
                  # Control: a local podman CLI cannot create the rootless user
                  # namespace, because NoNewPrivileges voids the setuid newuidmap.
                  as_worker(rootless, "env -u CONTAINER_HOST podman info", expect_success=False)
                  machine.fail(f"pgrep -u {rootless} podman")
                  info = as_worker(
                      rootless,
                      "podman info --format '{{.Host.ServiceIsRemote}} {{.Host.Security.Rootless}}'",
                  )
                  assert info.split() == ["true", "true"], info
                  assert user_unit_state("podman.service") == "active"
                  as_worker(rootless, f"podman load -i {probe_image}")
                  out = as_worker(rootless, "podman run --rm omnigent-probe:test")
                  assert "Hello, world!" in out, out
                  out = as_worker(rootless, "docker run --rm omnigent-probe:test")
                  assert "Hello, world!" in out, out

              with subtest("rootful and foreign podman sockets stay out of reach"):
                  ping = "curl -sf --unix-socket {} http://d/_ping"
                  # Controls: root reaches the rootful socket and the owner its own.
                  assert machine.succeed(ping.format("/run/podman/podman.sock")) == "OK"
                  assert as_worker(rootless, ping.format(f"{runtime_dir}/podman/podman.sock")) == "OK"
                  for user in owners.values():
                      as_worker(user, ping.format("/run/podman/podman.sock"), expect_success=False)
                  as_worker(control, ping.format(f"{runtime_dir}/podman/podman.sock"), expect_success=False)

              with subtest("restricted Incus confines the rootless worker to its own project"):
                  machine.wait_for_unit("incus-preseed.service")
                  project = f"user-{rootless_uid}"
                  assert as_worker(rootless, "incus project get-current").strip() == project
                  assert as_worker(rootless, f"incus project get {project} restricted").strip() == "true"
                  listed = as_worker(rootless, "incus project list -f csv -c n").splitlines()
                  assert len(listed) == 1 and listed[0].split()[0] == project, listed
                  # The admin socket stays with root and incus-admin.
                  as_worker(
                      rootless,
                      "curl -sf --unix-socket /var/lib/incus/unix.socket http://d/1.0",
                      expect_success=False,
                  )
                  for path in ("/var/lib/incus/unix.socket", "/var/lib/incus/unix.socket.user"):
                      as_worker(control, f"curl -sf --unix-socket {path} http://d/1.0", expect_success=False)

              with subtest("container probes leave no workload behind"):
                  as_worker(rootless, "podman rmi omnigent-probe:test")
                  assert as_worker(rootless, "podman ps -aq").strip() == ""

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
