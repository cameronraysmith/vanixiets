# The omnigraph seed unit end to end, in one QEMU VM with forced KVM (pyrite).
#
# The node runs services.omnigraph with magnetite's cluster configuration
# (graphs, policies, the cookbooks' schema and queries, the cluster actor) and
# magnetite's seed declaration for graph `dev`, on a fresh local root under
# the StateDirectory instead of R2, with test bearer tokens.
#
# What this establishes:
#   1. on a fresh root the bootstrap marks the seed of `dev` pending, and
#      omnigraph-seed-dev loads the cookbooks' seed through the running server
#      as the seed actor, under magnetite's graph policy, and deletes the
#      pending marker; the graph then answers the cookbook's `ready` question;
#   2. run again with no pending marker, the unit sends nothing and the graph
#      does not change, also when a server restart starts it;
#   3. with the marker put back over a seeded graph, the load is refused with
#      key_conflict, the unit counts that as success, deletes the marker and
#      the graph does not change;
#   4. the seed actor's token reads nothing.
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
      # Size class: the script measured 33.37 s, 47 s for the whole build with
      # the driver already built, on pyrite on 2026-11-25
      # (logs/omnigraph-seed-vmtest-20261125T2356Z.log).
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
            graph = "dev";
            seed = reference.cluster.graphs.${graph}.seed;
            stateDirectory = "/var/lib/omnigraph";
            markers = "${stateDirectory}/clusters/_omnigraph-markers";
            adminToken = "admin-test-token";
            seederToken = "seeder-test-token";
            # The cookbook's documented answer for `ready` on the seed
            # (dev-graph/README.md), as checks.omnigraph-dev-graph-seed holds it.
            readyRows = 5;
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
                  graphs.${graph} = {
                    exampleDataOnly = true;
                    seed = {
                      inherit (seed) file actor;
                      tokenFile = "/etc/omnigraph-test/seeder-token";
                    };
                  };
                };
              };
            };
            testScript = ''
              import json

              GRAPH = "${graph}"
              BASE = "http://127.0.0.1:${toString reference.port}/graphs/" + GRAPH
              PENDING = "${markers}/test.${graph}.seed-pending"
              INITIALIZED = "${markers}/test.initialized"

              def api(token, method, path, body=None):
                  data = "" if body is None else f" -H 'content-type: application/json' -d '{json.dumps(body)}'"
                  return machine.succeed(
                      f"curl -sS -o /tmp/body -w '%{{http_code}}' -X {method}"
                      f" -H 'Omnigraph-Http-Api: 0.14' -H 'authorization: Bearer {token}'{data} '{BASE}{path}'"
                      " && echo && cat /tmp/body"
                  )

              def admin_json(method, path, body=None):
                  status, _, body = api("${adminToken}", method, path, body).partition("\n")
                  assert status == "200", f"{method} {path}: {status} {body}"
                  return json.loads(body)

              def manifest_version():
                  return admin_json("GET", "/snapshot")["graph_manifest_version"]

              def seed_journal():
                  return machine.succeed("journalctl -u omnigraph-seed-dev.service -o cat --no-pager")

              start_all()
              machine.wait_for_unit("omnigraph-server.service")

              with subtest("a fresh root is seeded once through the server"):
                  machine.wait_until_succeeds("systemctl is-active omnigraph-seed-dev.service", timeout=300)
                  bootstrap = machine.succeed("journalctl -u omnigraph-cluster-bootstrap.service -o cat --no-pager")
                  assert "marked the seed of graph dev pending" in bootstrap, bootstrap
                  machine.succeed(f"test -e {INITIALIZED}")
                  machine.succeed(f"test ! -e {PENDING}")
                  assert "loaded 341 entities into graph dev" in seed_journal(), seed_journal()
                  rows = admin_json("POST", "/queries/ready", {"params": {}})["rows"]
                  assert len(rows) == ${toString readyRows}, rows
                  seeded = manifest_version()

              with subtest("with nothing pending the unit sends nothing"):
                  machine.succeed("systemctl restart omnigraph-seed-dev.service")
                  machine.succeed("systemctl restart omnigraph-server.service")
                  machine.wait_until_succeeds(
                      "[ \"$(journalctl -u omnigraph-seed-dev.service -o cat --no-pager | grep -c 'nothing to do')\" = 2 ]",
                      timeout=300,
                  )
                  assert manifest_version() == seeded

              with subtest("a key conflict counts as an earlier, committed seed"):
                  machine.succeed(f"echo '{{}}' > {PENDING}")
                  machine.succeed("systemctl restart omnigraph-seed-dev.service")
                  assert "already holds the seed" in seed_journal(), seed_journal()
                  machine.succeed(f"test ! -e {PENDING}")
                  assert manifest_version() == seeded

              with subtest("the seed actor reads nothing"):
                  status = api("${seederToken}", "POST", "/queries/ready", {"params": {}}).partition("\n")[0]
                  assert status in ("403", "404"), status
                  status = api("${seederToken}", "GET", "/snapshot").partition("\n")[0]
                  assert status in ("403", "404"), status
            '';
          };
      };
    };
}
