# Kernel OOM kill order between the CI evaluator, the telemetry store and the
# collector (openspec/changes/stand-up-greptimedb-on-magnetite, design D3 and
# D13, tasks 6.2; world assumption A32).
#
# What this establishes, in one QEMU VM with forced KVM (pyrite):
#   1. the real nix-eval-jobs lock wrapper raises its evaluator to
#      oom_score_adj 900, and the real greptimedb.service runs its process at
#      magnetite's evaluated OOMScoreAdjust (500);
#   2. when three equally growing consumers exhaust memory (one under the
#      wrapper, one inside greptimedb.service's cgroup at the unit's value, one
#      at magnetite's evaluated collector OOMScoreAdjust, 300), the kernel kills
#      them in that order (host-wide OOMs, not cgroup-limit OOMs), systemd
#      records a kernel OOM kill in each owning unit, and greptimedb.service
#      fails with result 'oom-kill' under the default OOMPolicy=stop.
#
# What it does not establish: the collector's own unit is not the third
# consumer, because its MemoryMax (512M) makes a hog inside its cgroup die to
# the cgroup's own OOM before any host-wide OOM, so a stand-in unit carries
# the collector's evaluated OOMScoreAdjust instead; nothing about magnetite's
# zram swap (the VM has none) or nixbot's bubblewrap sandbox; nothing about the
# store's real memory use, which R7.2 measures hourly on magnetite. It lives in
# the non-gating vmTests lane: on-demand evidence, not pull-request coverage.
{ self, inputs, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        greptimedb-oom-order =
          let
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              config.allowUnfree = true;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config;
            storeAdj = reference.systemd.services.greptimedb.serviceConfig.OOMScoreAdjust;
            collectorAdj = reference.systemd.services.opentelemetry-collector.serviceConfig.OOMScoreAdjust;
            usersGenerator = reference.clan.core.vars.generators.greptimedb-users;
            vars = "/run/greptimedb-test-vars";
            credentialConsumers = [
              "greptimedb.service"
              "greptimedb-schema.service"
            ];
            # Records its pid, waits for the shared gate, then grows by 8 MiB
            # of touched memory every 20 ms until killed, so all three
            # consumers grow at the same rate.
            memoryHog = pkgs.writeScriptBin "memory-hog" ''
              #!${pkgs.python3.interpreter}
              import os
              import sys
              import time

              name = sys.argv[1]
              with open(f"/run/memory-hog/{name}.pid.tmp", "w") as ready:
                  ready.write(str(os.getpid()))
              os.rename(f"/run/memory-hog/{name}.pid.tmp", f"/run/memory-hog/{name}.pid")
              while not os.path.exists("/run/memory-hog/go"):
                  time.sleep(0.1)
              held = []
              while True:
                  held.append(b"\x01" * (8 << 20))
                  time.sleep(0.02)
            '';
          in
          pkgs.testers.runNixOSTest {
            name = "greptimedb-oom-order";
            requiredFeatures = {
              kvm = true;
              nixos-test = true;
            };
            qemu.forceAccel = true;
            node.pkgs = lib.mkForce nodePkgs;
            nodes.machine =
              { config, pkgs, ... }:
              let
                evaluator = self.lib.mkNixEvalLockWrapper pkgs {
                  evaluator = "${memoryHog}/bin/memory-hog";
                  inherit (config.services.nixEvalLock) lockFile;
                };
              in
              {
                imports = [
                  self.modules.nixos.greptimedb
                  self.modules.nixos.nix-eval-lock
                  self.modules.nixos.memory-pressure-guards
                ];
                system.stateVersion = lib.trivial.release;
                virtualisation.memorySize = 2048;
                virtualisation.cores = 2;
                # The test instrumentation panics on any OOM
                # (nixos/modules/testing/test-instrumentation.nix, vm.panic_on_oom
                # mkDefault 2); the kernel's default 0 lets the OOM killer choose.
                boot.kernel.sysctl."vm.panic_on_oom" = 0;
                environment.systemPackages = [
                  pkgs.curl
                  memoryHog
                ];

                services.greptimedb = {
                  enable = true;
                  inherit (reference.services.greptimedb) databases;
                };
                services.nixEvalLock.enable = true;
                services.memoryPressureGuards.enable = reference.services.memoryPressureGuards.enable;

                systemd.services.greptimedb-test-vars = {
                  description = "Test credentials from magnetite's greptimedb-users generator";
                  requiredBy = credentialConsumers;
                  before = credentialConsumers;
                  path = [
                    pkgs.bash
                    pkgs.coreutils
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    install -d -m 0700 ${vars}
                    out=${vars} bash ${usersGenerator.finalScript}
                  '';
                };
                systemd.services.greptimedb.serviceConfig.LoadCredential = [ "users:${vars}/users" ];
                systemd.services.greptimedb-schema.serviceConfig.LoadCredential = [
                  "admin-password:${vars}/admin-password"
                ];

                systemd.tmpfiles.rules = [ "d /run/memory-hog 0755 root root -" ];

                # The evaluator behind the same wrapper magnetite installs; the
                # wrapper, not this unit, sets oom_score_adj 900.
                systemd.services.evaluator-standin = {
                  description = "nix-eval-jobs stand-in behind the host evaluation lock wrapper";
                  serviceConfig.ExecStart = "${evaluator}/bin/nix-eval-jobs evaluator";
                };
                systemd.services.collector-standin = {
                  description = "Collector stand-in at the collector's evaluated OOMScoreAdjust";
                  serviceConfig = {
                    ExecStart = "${memoryHog}/bin/memory-hog collector";
                    OOMScoreAdjust = collectorAdj;
                  };
                };
              };
            testScript = ''
              import datetime as dt
              import re

              EVALUATOR_ADJ = 900
              STORE_ADJ = ${toString storeAdj}
              COLLECTOR_ADJ = ${toString collectorAdj}
              EXPECTED = [
                  ("evaluator", EVALUATOR_ADJ, "/system.slice/evaluator-standin.service"),
                  ("store", STORE_ADJ, "/system.slice/greptimedb.service"),
                  ("collector", COLLECTOR_ADJ, "/system.slice/collector-standin.service"),
              ]
              KILLED = "Out of memory: Killed process"

              start_all()
              machine.wait_for_unit("greptimedb.service")
              machine.wait_until_succeeds(
                  "curl -sf http://127.0.0.1:4000/health", timeout=dt.timedelta(minutes=2)
              )
              assert KILLED not in machine.succeed("journalctl -k -o cat --no-pager")

              with subtest("each consumer runs at its envelope's oom_score_adj"):
                  main_pid = machine.succeed("systemctl show -P MainPID greptimedb.service").strip()
                  assert int(machine.succeed(f"cat /proc/{main_pid}/oom_score_adj")) == STORE_ADJ
                  machine.succeed("systemctl start evaluator-standin.service collector-standin.service")
                  machine.succeed(
                      "setsid sh -c 'echo $$ > /sys/fs/cgroup/system.slice/greptimedb.service/cgroup.procs"
                      f" && echo {STORE_ADJ} > /proc/$$/oom_score_adj && exec memory-hog store'"
                      " </dev/null >/dev/null 2>&1 &"
                  )
                  pids = {}
                  for name, adj, cgroup in EXPECTED:
                      machine.wait_for_file(f"/run/memory-hog/{name}.pid")
                      pids[name] = machine.succeed(f"cat /run/memory-hog/{name}.pid").strip()
                      assert int(machine.succeed(f"cat /proc/{pids[name]}/oom_score_adj")) == adj, name
                      assert machine.succeed(f"cat /proc/{pids[name]}/cgroup").strip() == f"0::{cgroup}", name

              with subtest("the kernel kills evaluator, store and collector in that order"):
                  machine.succeed("touch /run/memory-hog/go")
                  machine.wait_until_succeeds(
                      f"[ \"$(journalctl -k -o cat --no-pager | grep -c '{KILLED}')\" -ge 3 ]",
                      timeout=dt.timedelta(minutes=5),
                  )
                  kernel = machine.succeed("journalctl -k -o cat --no-pager")
                  # mm/oom_kill.c:447-457 at v6.18, with mm/memcontrol.c:1539-1553: only
                  # host-wide OOMs carry ",global_oom"; a cgroup-limit OOM carries ",oom_memcg=".
                  victims = re.findall(
                      r"^oom-kill:constraint=[^\n]*,global_oom,task_memcg=([^,\n]+),task=[^,\n]*,pid=(\d+),uid=\d+$",
                      kernel,
                      re.MULTILINE,
                  )
                  # mm/oom_kill.c:960-966 and :1184 at v6.18.
                  adjs = [
                      int(adj)
                      for adj in re.findall(r"^Out of memory: Killed process \d+ \([^\n]*\) [^\n]* oom_score_adj:(-?\d+)$", kernel, re.MULTILINE)
                  ]
                  assert "oom_memcg=" not in kernel, "a cgroup-limit OOM preceded the host-wide ones"
                  assert victims == [(cgroup, pids[name]) for name, _, cgroup in EXPECTED], victims
                  assert adjs == [adj for _, adj, _ in EXPECTED], adjs

              with subtest("systemd records the OOM kill in each owning unit"):
                  # systemd v261.3 src/core/cgroup.c:3098-3101.
                  for unit in ("evaluator-standin", "greptimedb", "collector-standin"):
                      machine.wait_until_succeeds(
                          f"journalctl -u {unit}.service -o cat --no-pager"
                          " | grep -F 'The kernel OOM killer killed some processes in this unit.'",
                          timeout=dt.timedelta(minutes=1),
                      )
                  # systemd v261.3 src/core/service.c:4538-4543 and src/core/unit.c:6261-6268:
                  # greptimedb's main process survives, so OOMPolicy=stop stops it with oom-kill.
                  machine.wait_until_succeeds(
                      "journalctl -u greptimedb.service -o cat --no-pager"
                      " | grep -F \"Failed with result 'oom-kill'.\"",
                      timeout=dt.timedelta(minutes=1),
                  )
            '';
          };
      };
    };
}
