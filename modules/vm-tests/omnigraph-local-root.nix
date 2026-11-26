# A local omnigraph root on its own ZFS dataset, end to end, in one QEMU VM
# with forced KVM (pyrite).
#
# The node runs services.omnigraph with two of magnetite's graphs,
# cookbook-beads and cookbook-company-brain, their seeds, magnetite's
# policies and the `monitor` actor, on the root
# /var/lib/omnigraph/clusters/cookbooks-f17, as magnetite's local root is
# named. ZFS dataset zroot/root/omnigraph, on a second virtual disk, is the
# units' state directory /var/lib/omnigraph itself, declared as a file
# system as disko declares magnetite's, with a quota. The omnigraph probe and
# the omnigraph backup module run as on a host, the backup's repository
# overridden to a local path with a fixed password.
#
# What this establishes:
#   1. the dataset's root, owned by root when the first boot mounts it, is
#      owned by `omnigraph` once the units have started (systemd re-owns a
#      state directory to its unit's static user); the bootstrap creates and
#      seeds the root and its markers on the dataset; every omnigraph unit
#      (bootstrap, seeds, server, apply) runs as the static user
#      `omnigraph` with no DynamicUser, and so does `omnigraph-cluster
#      apply` invoked as root: no file on the dataset is owned by anyone
#      else, after this or any later step, and the server then writes (a
#      load);
#   2. after `kill -9` of the server, the probe writes
#      `vanixiets_omnigraph_ready 0` (OmnigraphNotServing's input) and
#      still exits 0; the next start clears the stale serve lock by itself,
#      attempts its notice, serves the same entity counts and stored-query
#      answers, and counts the recovery;
#   3. with the server killed again and a direct `omnigraph` writer running
#      as `omnigraph` against the root, the start refuses, names the
#      writer, and leaves lock.json byte for byte; once the writer is gone
#      the start recovers;
#   4. the backup job takes the snapshot zroot/root/omnigraph@restic, backs up
#      its directory, destroys it and stamps its success, recording every
#      file of the dataset with omnigraph's uid and gid; after the dataset is
#      emptied, the runbook's
#      restore (stop the backup timer and the server, take
#      zroot/root/omnigraph@pre-restore, `restic-omnigraph restore` of the
#      chosen backup's snapshot directory, `chown -R omnigraph:omnigraph`,
#      `omnigraph-cluster force-unlock` of the restored lock, start, destroy
#      the pre-restore snapshot, start the timer) serves the same counts and
#      answers;
#   5. after a reboot the dataset is mounted before the units, which start
#      and serve the same answers, and the server, bootstrap, apply and seed
#      units each require the mounts of /var/lib/omnigraph/clusters
#      (`RequiresMountsFor`);
#   6. every series of the probe is in its textfile, per-graph ones
#      included, and the backup stamp in the backup's; with a wrong monitor
#      token the probe logs `GET /graphs` answered with its HTTP 4xx status,
#      writes vanixiets_omnigraph_graph_reads_ok 0 and leaves the per-graph
#      series out, and with the right one writes 1 again.
#
# This runtime test is the only check of the probe's behaviour; it does
# not gate pull requests.
#
# What it does not establish: R2 (the repository's bucket, path-style
# addressing, the token's scope), the real vars or their generators, the
# nightly timer, prune and check over many nights, magnetite's memory, or a
# reboot between a crash and the next start (the rehearsal
# checks.x86_64-linux.omnigraph-lock-recovery-rehearsal holds that row).
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
      # Medium: its script took 80.75, 81.36 and 79.84 s in three runs on
      # pyrite on 2026-11-26, over the small limit of 60 s.
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-local-root.class = "medium";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-local-root =
          let
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config.services.omnigraph;
            roots = self.lib.omnigraphClusterRoots;
            backup = self.lib.omnigraphBackup;
            # Each graph with a featured question of its cookbook.
            seeded = {
              cookbook-beads = "blocked";
              cookbook-company-brain = "current_decisions";
            };
            graphs = lib.attrNames seeded;
            root = roots.uriIn "local" "cookbooks-f17";
            lock = "${root}/__cluster/lock.json";
            adminToken = "admin-test-token";
            seederToken = "seeder-test-token";
            monitorToken = "monitor-test-token";
          in
          pkgs.testers.runNixOSTest {
            name = "omnigraph-local-root";
            requiredFeatures = {
              kvm = true;
              nixos-test = true;
            };
            qemu.forceAccel = true;
            node.pkgs = lib.mkForce nodePkgs;
            nodes.machine =
              { config, ... }:
              let
                zfs = config.boot.zfs.package;
              in
              {
                imports = [
                  self.modules.nixos.omnigraph
                  self.modules.nixos.node-exporter-textfile
                  self.modules.nixos.observability-notify
                ];
                system.stateVersion = lib.trivial.release;
                virtualisation.memorySize = 2048;
                virtualisation.cores = 2;
                virtualisation.emptyDiskImages = [ 1024 ];
                boot.supportedFilesystems = [ "zfs" ];
                networking.hostId = "8425e349";
                environment.systemPackages = [
                  nodePkgs.curl
                  nodePkgs.jq
                  zfs
                ];
                environment.etc = {
                  "omnigraph-test/seeder-token".text = seederToken;
                  # A copy rather than a link into the store, so that the
                  # probe's leg can hand it a wrong token and restore it.
                  "omnigraph-test/monitor-token" = {
                    text = monitorToken;
                    mode = "0644";
                  };
                  "restic-test-password".text = "restic-test-password";
                };

                # The pool and dataset an operator creates on magnetite by
                # hand: created on the first boot, imported on later ones,
                # before the dataset's mount.
                systemd.services.omnigraph-test-pool = {
                  wantedBy = [ "zfs-import.target" ];
                  requiredBy = [ "var-lib-omnigraph.mount" ];
                  before = [
                    "zfs-import-zroot.service"
                    "zfs-import.target"
                    "var-lib-omnigraph.mount"
                  ];
                  after = [
                    "systemd-modules-load.service"
                    "systemd-udev-settle.service"
                  ];
                  unitConfig.DefaultDependencies = false;
                  path = [ zfs ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    if ! zpool list zroot >/dev/null 2>&1 && ! zpool import -N zroot 2>/dev/null; then
                      zpool create -f -o cachefile=none -O mountpoint=none -O canmount=off zroot /dev/vdb
                      zfs create -o mountpoint=none zroot/root
                      zfs create -o canmount=noauto -o mountpoint=${backup.mountpoint} ${backup.dataset}
                    fi
                  '';
                };
                # A test VM mounts virtualisation.fileSystems in place of
                # fileSystems.
                virtualisation.fileSystems.${backup.mountpoint} = {
                  device = backup.dataset;
                  fsType = "zfs";
                  options = [ "zfsutil" ];
                };
                systemd.services.zfs-set-root-omnigraph-quota = {
                  wantedBy = [ "multi-user.target" ];
                  after = [ "var-lib-omnigraph.mount" ];
                  requires = [ "var-lib-omnigraph.mount" ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                    ExecStart = "${zfs}/bin/zfs set quota=1G ${backup.dataset}";
                  };
                };
                # The owner of the dataset's root as the first boot mounts it,
                # before any omnigraph unit starts: root, as on magnetite once
                # an operator creates the dataset at /var/lib/omnigraph.
                systemd.services.omnigraph-test-first-owner = {
                  wantedBy = [ "multi-user.target" ];
                  requires = [ "var-lib-omnigraph.mount" ];
                  after = [ "var-lib-omnigraph.mount" ];
                  before = [
                    "omnigraph-cluster-bootstrap.service"
                    "omnigraph-cluster-apply.service"
                    "omnigraph-server.service"
                  ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  script = ''
                    [ -e /var/lib/omnigraph-test-first-owner ] \
                      || stat -c '%U:%G %a' ${backup.mountpoint} >/var/lib/omnigraph-test-first-owner
                  '';
                };

                services.prometheus.exporters.node.enable = true;
                services.observability-notify.units = [
                  "restic-backups-omnigraph"
                  "omnigraph-backup-metric"
                  "zfs-set-root-omnigraph-quota"
                ];

                vanixiets.omnigraphBackup.enable = true;
                services.restic.backups.omnigraph = {
                  repository = lib.mkForce "/var/lib/restic-test";
                  passwordFile = "/etc/restic-test-password";
                  environmentFile = null;
                };

                services.omnigraph = {
                  enable = true;
                  inherit (reference) package bindAddress port;
                  storageUri = root;
                  requireAllGraphs = true;
                  bearerTokensFile = nodePkgs.writeText "tokens.json" (builtins.toJSON { admin = adminToken; });
                  extraBearerTokenFiles.monitor = "/etc/omnigraph-test/monitor-token";
                  cluster = {
                    settings = {
                      inherit (reference.cluster.settings) metadata;
                      graphs = lib.getAttrs graphs reference.cluster.settings.graphs;
                      policies = lib.mapAttrs (
                        _: policy:
                        policy
                        // {
                          applies_to = lib.filter (g: g == "cluster" || lib.elem g graphs) policy.applies_to;
                        }
                      ) reference.cluster.settings.policies;
                    };
                    inherit (reference.cluster) extraFiles actor;
                    graphs = lib.genAttrs graphs (graph: {
                      exampleDataOnly = true;
                      seed = {
                        inherit (reference.cluster.graphs.${graph}.seed) file actor;
                        tokenFile = "/etc/omnigraph-test/seeder-token";
                      };
                    });
                  };
                };
              };
            testScript = ''
              import json

              SEEDED = json.loads(r"""${builtins.toJSON seeded}""")
              BASE = "http://127.0.0.1:${toString reference.port}/graphs/"
              LOCK = "${lock}"
              COUNTER = "${self.lib.omnigraphProbe.lockRecoveriesFile}"
              TEXTFILE = "/run/node-exporter-textfile"
              DATASET = "${backup.mountpoint}"

              def request(method, graph, path, data=""):
                  out = machine.succeed(
                      f"curl -sS -o /tmp/body -w '%{{http_code}}' -X {method}"
                      f" -H 'Omnigraph-Http-Api: 0.14' -H 'authorization: Bearer ${adminToken}'{data} '{BASE}{graph}{path}'"
                      " && echo && cat /tmp/body"
                  )
                  status, _, body = out.partition("\n")
                  assert status == "200", f"{method} {graph}{path}: {status} {body}"
                  return json.loads(body)

              def admin_json(method, graph, path, body=None):
                  data = "" if body is None else f" -H 'content-type: application/json' -d '{json.dumps(body)}'"
                  return request(method, graph, path, data)

              def answers():
                  """Each graph's entity count on main and its featured query's rows."""
                  result = {}
                  for graph, question in SEEDED.items():
                      snapshot = admin_json("GET", graph, "/snapshot")
                      entities = sum(d["entity_count"] for d in snapshot["datasets"])
                      rows = admin_json("POST", graph, f"/queries/{question}", {"params": {}})["rows"]
                      result[graph] = {"entities": entities, "rows": rows}
                  return result

              def server_journal():
                  return machine.succeed("journalctl -u omnigraph-server.service -o cat --no-pager")

              def owned_by_omnigraph():
                  stray = machine.succeed(f"find {DATASET} -xdev ! -user omnigraph -print -o ! -group omnigraph -print")
                  assert stray == "", stray

              def kill_server():
                  pid = machine.succeed("systemctl show -P MainPID omnigraph-server.service").strip()
                  machine.succeed(f"kill -9 {pid}")
                  machine.wait_until_succeeds("systemctl show -P SubState omnigraph-server.service | grep -qx auto-restart")
                  machine.succeed(f"test -e {LOCK}")

              def start_server():
                  # The test starts the server more often than its start limit
                  # allows within one window, which is not what it judges.
                  machine.succeed("systemctl reset-failed omnigraph-server.service")
                  machine.succeed("systemctl restart omnigraph-server.service")

              def counter():
                  return machine.succeed(f"cat {COUNTER}").strip()

              def seeds_done():
                  for graph in SEEDED:
                      machine.wait_until_succeeds(f"systemctl is-active omnigraph-seed-{graph}.service", timeout=300)

              def probe():
                  """Runs omnigraph-probe once, which exits 0, and returns its textfile."""
                  machine.succeed("systemctl start omnigraph-probe.service")
                  return machine.succeed(f"cat {TEXTFILE}/omnigraph.prom")

              def has_sample(prom, sample):
                  return f"\n{sample}\n" in "\n" + prom

              start_all()
              machine.wait_for_unit("omnigraph-server.service")

              with subtest("the dataset is the state directory, and the root and its markers are on it"):
                  seeds_done()
                  first_owner = machine.succeed("cat /var/lib/omnigraph-test-first-owner").strip()
                  print(f"the dataset's root before the first omnigraph unit: {first_owner}")
                  assert first_owner.startswith("root:root "), first_owner
                  machine.succeed(f"findmnt -n -o SOURCE {DATASET} | grep -qx ${backup.dataset}")
                  for path in ["${root}", "${roots.localDirectory}/_omnigraph-markers/cookbooks-f17.initialized"]:
                      machine.succeed(f"findmnt -n -o SOURCE -T {path} | grep -qx ${backup.dataset}")
                  print(machine.succeed(f"stat -c '%U(%u):%G(%g) %a %n' {DATASET} ${root} ${root}/__cluster/*"))
                  owned_by_omnigraph()
                  before = answers()
                  print(f"answers before the kill: {json.dumps(before, sort_keys=True)}")
                  machine.succeed(f"test ! -e {COUNTER}")

              with subtest("every unit and the root-invoked wrapper write as omnigraph, and the server then writes"):
                  for unit in ["omnigraph-cluster-bootstrap", "omnigraph-cluster-apply", "omnigraph-server"] + [f"omnigraph-seed-{g}" for g in SEEDED]:
                      assert machine.succeed(f"systemctl show -P User {unit}.service").strip() == "omnigraph", unit
                      assert machine.succeed(f"systemctl show -P DynamicUser {unit}.service").strip() == "no", unit
                  pid = machine.succeed("systemctl show -P MainPID omnigraph-server.service").strip()
                  assert machine.succeed(f"ps -o user= -p {pid}").strip() == "omnigraph", pid
                  machine.succeed("systemctl stop omnigraph-server.service")
                  machine.succeed("systemctl start omnigraph-cluster-apply.service")
                  print(machine.succeed(f"cat {LOCK} 2>&1 || true"))
                  machine.succeed("omnigraph-cluster apply --json")
                  print(machine.succeed(f"cat {LOCK} 2>&1 || true"))
                  owned_by_omnigraph()
                  start_server()
                  request("POST", "cookbook-beads", "/load/ndjson?mode=merge&branch=main",
                          " -H 'content-type: application/x-ndjson' --data-binary @${reference.cluster.graphs.cookbook-beads.seed.file}")
                  owned_by_omnigraph()
                  assert answers() == before

              with subtest("a killed server's next start clears its lock and serves the same answers"):
                  kill_server()
                  stale = machine.succeed(f"jq -r .lock_id {LOCK}").strip()
                  # What OmnigraphNotServing reads while the server is down,
                  # from a probe that still exits 0.
                  down = probe()
                  assert has_sample(down, "vanixiets_omnigraph_ready 0"), down
                  assert has_sample(down, "vanixiets_omnigraph_graph_reads_ok 0"), down
                  start_server()
                  journal = server_journal()
                  assert f"cleared the stale serve lock {stale}" in journal, journal
                  # The notice is attempted; this VM reaches no ntfy server.
                  assert "omnigraph-lock-recovery: the recovery notice was not posted" in journal, journal
                  assert counter() == "1", counter()
                  after_recovery = answers()
                  print(f"answers after recovery: {json.dumps(after_recovery, sort_keys=True)}")
                  assert after_recovery == before
                  owned_by_omnigraph()

              with subtest("a direct writer on the root makes the start refuse and leave the lock"):
                  kill_server()
                  machine.succeed(f"sha256sum {LOCK} > /tmp/lock.sha256")
                  machine.succeed("mkfifo /tmp/writer-data")
                  machine.succeed(
                      "systemd-run --unit held-writer -p User=omnigraph -p Group=omnigraph -p Environment=OMNIGRAPH_HOME=/tmp/held-writer"
                      " ${reference.package}/bin/omnigraph --target ${root} --graph cookbook-beads"
                      " load --mode append --data /tmp/writer-data"
                  )
                  machine.wait_until_succeeds("systemctl is-active held-writer.service")
                  writer = machine.succeed("systemctl show -P MainPID held-writer.service").strip()
                  machine.fail("systemctl reset-failed omnigraph-server.service && systemctl restart omnigraph-server.service")
                  journal = server_journal()
                  refusal = f"an omnigraph process has the root open (pid {writer}: "
                  assert refusal in journal, journal
                  print(journal[journal.index(refusal) - 60:][:400])
                  machine.succeed("sha256sum --check --status /tmp/lock.sha256")
                  print(f"lock.json unchanged after the refusal: {machine.succeed(f'cat {LOCK}')}")
                  assert counter() == "1", counter()
                  machine.succeed("systemctl stop held-writer.service")
                  start_server()
                  assert counter() == "2", counter()
                  assert answers() == before
                  owned_by_omnigraph()

              with subtest("a backup from the snapshot restores to the same answers by the runbook"):
                  machine.succeed("systemctl start restic-backups-omnigraph.service")
                  machine.succeed("[ -z \"$(zfs list -H -t snapshot -o name ${backup.snapshot} 2>/dev/null)\" ]")
                  snapshots = json.loads(machine.succeed("restic-omnigraph snapshots --json"))
                  assert len(snapshots) == 1 and snapshots[0]["paths"] == ["${backup.snapshotPath}"], snapshots
                  chosen = snapshots[0]["short_id"]
                  nodes = [json.loads(line) for line in machine.succeed(f"restic-omnigraph ls {chosen} --json").splitlines()]
                  snap = "${backup.snapshotPath}"
                  within = lambda path: path == snap or path.startswith(snap + "/")
                  owners = {f"{n['uid']}:{n['gid']}" for n in nodes if within(n.get("path", ""))}
                  omnigraph_ids = machine.succeed("echo $(id -u omnigraph):$(id -g omnigraph)").strip()
                  assert owners == {omnigraph_ids}, f"owners recorded below the snapshot directory: {owners}"
                  print(f"recorded above it: {sorted((n['path'], n['uid'], n['gid']) for n in nodes if 'path' in n and not within(n['path']))}")
                  machine.succeed(f"grep -q '^${backup.seriesName} [0-9]' {TEXTFILE}/omnigraph-backup.prom")
                  machine.succeed("systemctl stop restic-backups-omnigraph.timer omnigraph-server.service")
                  machine.fail("systemctl is-active restic-backups-omnigraph.timer")
                  machine.succeed("zfs snapshot ${backup.dataset}@pre-restore")
                  machine.succeed(f"find {DATASET} -mindepth 1 -xdev -delete")
                  machine.succeed(f"[ -z \"$(ls -A {DATASET})\" ]")
                  machine.succeed(f"restic-omnigraph restore {chosen}:${backup.snapshotPath} --target {DATASET}")
                  # restic restores the recorded owners; the chown matters on a
                  # host where omnigraph has another uid.
                  owned_by_omnigraph()
                  machine.succeed(f"chown -R omnigraph:omnigraph {DATASET}")
                  owned_by_omnigraph()
                  restored = machine.succeed(f"jq -r .lock_id {LOCK}").strip()
                  machine.succeed(f"omnigraph-cluster force-unlock {restored}")
                  machine.succeed(f"test ! -e {LOCK}")
                  start_server()
                  after_restore = answers()
                  print(f"answers after restore: {json.dumps(after_restore, sort_keys=True)}")
                  assert after_restore == before
                  assert counter() == "2", counter()
                  owned_by_omnigraph()
                  machine.succeed("zfs destroy ${backup.dataset}@pre-restore")
                  machine.succeed("systemctl start restic-backups-omnigraph.timer")

              with subtest("after a reboot the dataset is mounted before the units, which serve"):
                  machine.shutdown()
                  machine.start()
                  machine.wait_for_unit("omnigraph-server.service")
                  seeds_done()
                  machine.succeed(f"findmnt -n -o SOURCE {DATASET} | grep -qx ${backup.dataset}")
                  for unit in ["omnigraph-cluster-bootstrap", "omnigraph-cluster-apply", "omnigraph-server"] + [f"omnigraph-seed-{g}" for g in SEEDED]:
                      mounts = machine.succeed(f"systemctl show -P RequiresMountsFor {unit}.service").split()
                      assert "${roots.localDirectory}" in mounts, (unit, mounts)
                      print(f"{unit} RequiresMountsFor: {mounts}")
                  after_reboot = answers()
                  print(f"answers after reboot: {json.dumps(after_reboot, sort_keys=True)}")
                  assert after_reboot == before
                  owned_by_omnigraph()

              with subtest("the probe publishes every series, and reports a refused graph list"):
                  prom = probe()
                  print(prom)
                  for name in ${builtins.toJSON self.lib.omnigraphProbe.seriesNames}:
                      assert f"\n{name}" in "\n" + prom, name
                  assert has_sample(prom, "vanixiets_omnigraph_ready 1"), prom
                  assert has_sample(prom, "vanixiets_omnigraph_graph_reads_ok 1"), prom
                  assert has_sample(prom, "vanixiets_omnigraph_lock_recoveries_total 2"), prom
                  for graph in SEEDED:
                      assert f'vanixiets_omnigraph_graph_entities{{graph="{graph}"}}' in prom, graph
                  machine.succeed("echo wrong-monitor-token > /etc/omnigraph-test/monitor-token")
                  refused = probe()
                  machine.succeed("printf %s ${monitorToken} > /etc/omnigraph-test/monitor-token")
                  assert has_sample(refused, "vanixiets_omnigraph_ready 1"), refused
                  assert has_sample(refused, "vanixiets_omnigraph_graph_reads_ok 0"), refused
                  assert "vanixiets_omnigraph_graph_entities" not in refused, refused
                  lines = machine.succeed("journalctl -u omnigraph-probe.service -o cat --no-pager | grep -E '^omnigraph-probe: GET /graphs answered HTTP 4[0-9]{2}$'")
                  print(f"the probe's line for the refused list: {lines.strip()}")
                  assert has_sample(probe(), "vanixiets_omnigraph_graph_reads_ok 1")
            '';
          };
      };
    };
}
