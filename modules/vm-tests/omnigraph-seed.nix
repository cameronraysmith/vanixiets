# The omnigraph seed units end to end, in one QEMU VM with forced KVM (pyrite).
#
# The node runs services.omnigraph with magnetite's cluster configuration
# (all its graphs, its policies, the cookbooks' schemas and queries, the
# cluster actor) and magnetite's seed declarations for two of its graphs,
# cookbook-beads and cookbook-company-brain, on a fresh local root under the
# StateDirectory instead of R2, with test bearer tokens.
#
# What this establishes:
#   1. on a fresh root the bootstrap marks the seed of each seeded graph
#      pending, and omnigraph-seed-<graph> loads each cookbook's seed through
#      the running server as the seed actor, under magnetite's graph policy,
#      and deletes its pending marker; the second load starts only once the
#      first has finished; each graph then answers a featured question of its
#      cookbook as its seed.md documents;
#   2. run again with no pending marker, a unit sends nothing and its graph
#      does not change, also when a server restart starts it;
#   3. with the marker of cookbook-beads put back over its seeded graph, the
#      load is refused with key_conflict, the unit counts that as success,
#      deletes the marker and the graph does not change;
#   4. with the marker of cookbook-company-brain put back over its seeded
#      graph, whose seed writes edges under a `@card` maximum, the load is
#      refused with effects `unknown`; the unit fails, keeps the marker and
#      prints the command that clears it, the graph does not change, and that
#      command deletes the marker;
#   5. the seed actor's token reads nothing.
#
# What it does not establish: anything about R2 (the S3 marker requests are
# covered by checks.omnigraph-bootstrap-rehearsal), nor activation's handling
# of changed units, which follows from switch-to-configuration's source.
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
      # Size class: the script measured 39.83 s, 54 s for the whole build with
      # the driver already built, on pyrite on 2026-11-25.
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-seed.class = "small";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-seed =
          let
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config.services.omnigraph;
            # Two of the smallest seeds, in the order the seed units run
            # (graph id order). Each with a featured question of its cookbook
            # and the number of rows its seed.md documents for it on the seed.
            seeded = {
              cookbook-beads = {
                question = "blocked";
                rows = 3;
              };
              cookbook-company-brain = {
                question = "current_decisions";
                rows = 4;
              };
            };
            first = "cookbook-beads";
            second = "cookbook-company-brain";
            stateDirectory = "/var/lib/omnigraph";
            markers = "${stateDirectory}/clusters/_omnigraph-markers";
            adminToken = "admin-test-token";
            seederToken = "seeder-test-token";
          in
          pkgs.testers.runNixOSTest {
            name = "omnigraph-seed";
            requiredFeatures = {
              kvm = true;
              nixos-test = true;
            };
            qemu.forceAccel = true;
            node.pkgs = lib.mkForce nodePkgs;
            nodes.machine = {
              imports = [ self.modules.nixos.omnigraph ];
              system.stateVersion = lib.trivial.release;
              virtualisation.memorySize = 2048;
              virtualisation.cores = 2;
              environment.systemPackages = [
                nodePkgs.curl
                nodePkgs.jq
              ];
              environment.etc."omnigraph-test/seeder-token".text = seederToken;

              services.omnigraph = {
                enable = true;
                inherit (reference) package bindAddress port;
                storageUri = "${stateDirectory}/clusters/test";
                requireAllGraphs = true;
                bearerTokensFile = nodePkgs.writeText "tokens.json" (builtins.toJSON { admin = adminToken; });
                cluster = {
                  settings = {
                    inherit (reference.cluster.settings) metadata graphs policies;
                  };
                  inherit (reference.cluster) extraFiles actor;
                  graphs = lib.mapAttrs (graph: _: {
                    exampleDataOnly = true;
                    seed = {
                      inherit (reference.cluster.graphs.${graph}.seed) file actor;
                      tokenFile = "/etc/omnigraph-test/seeder-token";
                    };
                  }) seeded;
                };
              };
            };
            testScript = ''
              import json

              SEEDED = json.loads(r"""${
                builtins.toJSON (
                  lib.mapAttrs (graph: s: s // { inherit (reference.cluster.graphs.${graph}.seed) file; }) seeded
                )
              }""")
              FIRST, SECOND = "${first}", "${second}"
              BASE = "http://127.0.0.1:${toString reference.port}/graphs/"

              def pending(graph):
                  return f"${markers}/test.{graph}.seed-pending"

              def api(token, method, graph, path, body=None):
                  data = "" if body is None else f" -H 'content-type: application/json' -d '{json.dumps(body)}'"
                  return machine.succeed(
                      f"curl -sS -o /tmp/body -w '%{{http_code}}' -X {method}"
                      f" -H 'Omnigraph-Http-Api: 0.14' -H 'authorization: Bearer {token}'{data} '{BASE}{graph}{path}'"
                      " && echo && cat /tmp/body"
                  )

              def admin_json(method, graph, path, body=None):
                  status, _, body = api("${adminToken}", method, graph, path, body).partition("\n")
                  assert status == "200", f"{method} {graph}{path}: {status} {body}"
                  return json.loads(body)

              def manifest_version(graph):
                  return admin_json("GET", graph, "/snapshot")["graph_manifest_version"]

              def seed_journal(graph):
                  return machine.succeed(f"journalctl -u omnigraph-seed-{graph}.service -o cat --no-pager")

              def unit_time(graph, prop):
                  return int(machine.succeed(f"systemctl show -P {prop} omnigraph-seed-{graph}.service").strip())

              start_all()
              machine.wait_for_unit("omnigraph-server.service")

              with subtest("a fresh root is seeded once per graph through the server, one load at a time"):
                  for graph in SEEDED:
                      machine.wait_until_succeeds(f"systemctl is-active omnigraph-seed-{graph}.service", timeout=300)
                  bootstrap = machine.succeed("journalctl -u omnigraph-cluster-bootstrap.service -o cat --no-pager")
                  machine.succeed("test -e ${markers}/test.initialized")
                  seeded = {}
                  for graph, expected in SEEDED.items():
                      assert f"marked the seed of graph {graph} pending" in bootstrap, bootstrap
                      machine.succeed(f"test ! -e {pending(graph)}")
                      entities = machine.succeed(f"grep -c . {expected['file']}").strip()
                      assert f"loaded {entities} entities into graph {graph}" in seed_journal(graph), seed_journal(graph)
                      rows = admin_json("POST", graph, f"/queries/{expected['question']}", {"params": {}})["rows"]
                      assert len(rows) == expected["rows"], rows
                      seeded[graph] = manifest_version(graph)
                  first_done = unit_time(FIRST, "ExecMainExitTimestampMonotonic")
                  second_started = unit_time(SECOND, "ExecMainStartTimestampMonotonic")
                  assert 0 < first_done <= second_started, (first_done, second_started)

              with subtest("with nothing pending the units send nothing"):
                  machine.succeed(f"systemctl restart omnigraph-seed-{FIRST}.service")
                  machine.succeed("systemctl restart omnigraph-server.service")
                  machine.wait_until_succeeds(
                      f"[ \"$(journalctl -u omnigraph-seed-{FIRST}.service -o cat --no-pager | grep -c 'nothing to do')\" = 2 ]",
                      timeout=300,
                  )
                  machine.wait_until_succeeds(
                      f"[ \"$(journalctl -u omnigraph-seed-{SECOND}.service -o cat --no-pager | grep -c 'nothing to do')\" = 1 ]",
                      timeout=300,
                  )
                  for graph in SEEDED:
                      assert manifest_version(graph) == seeded[graph]

              with subtest("a key conflict counts as an earlier, committed seed"):
                  machine.succeed(f"echo '{{}}' > {pending(FIRST)}")
                  machine.succeed(f"systemctl restart omnigraph-seed-{FIRST}.service")
                  assert "already holds the seed" in seed_journal(FIRST), seed_journal(FIRST)
                  machine.succeed(f"test ! -e {pending(FIRST)}")
                  assert manifest_version(FIRST) == seeded[FIRST]

              with subtest("a @card refusal keeps the marker and names the command that clears it"):
                  machine.succeed(f"echo '{{}}' > {pending(SECOND)}")
                  machine.fail(f"systemctl restart omnigraph-seed-{SECOND}.service")
                  machine.succeed(f"test -e {pending(SECOND)}")
                  assert manifest_version(SECOND) == seeded[SECOND]
                  journal = seed_journal(SECOND)
                  assert "@card violation" in journal, journal
                  assert pending(SECOND) in journal, journal
                  marker = "clear the marker as root with:"
                  assert marker in journal, journal
                  command = journal.split(marker, 1)[1].strip().splitlines()[0].strip()
                  assert command.startswith("systemd-run ") and command.endswith(" --clear-pending"), command
                  machine.succeed(command)
                  machine.succeed(f"test ! -e {pending(SECOND)}")
                  assert manifest_version(SECOND) == seeded[SECOND]

              with subtest("the seed actor reads nothing"):
                  for graph, expected in SEEDED.items():
                      status = api("${seederToken}", "POST", graph, f"/queries/{expected['question']}", {"params": {}}).partition("\n")[0]
                      assert status in ("403", "404"), status
                      status = api("${seederToken}", "GET", graph, "/snapshot").partition("\n")[0]
                      assert status in ("403", "404"), status
            '';
          };
      };
    };
}
