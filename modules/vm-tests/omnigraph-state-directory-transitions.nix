# The omnigraph units' state directory /var/lib/omnigraph across the moves
# a host makes between its generations and root stores, in one QEMU VM with
# forced KVM (pyrite). systemd sets the directory up before every start
# (setup_exec_directory, src/core/exec-invoke.c in systemd 262): a
# DynamicUser unit keeps it at /var/lib/private/omnigraph behind a symlink,
# moving a plain directory there by rename(2), and a unit with a static user
# moves such a private directory back. The omnigraph module runs every unit
# as the static user `omnigraph` on either store; generations before it ran
# them as a DynamicUser.
#
# RustFS on the node stands in for R2: the root
# s3://sciexp/omnigraph/clusters/cookbooks-f17 is served from its bucket
# with path-style requests, as magnetite's is from R2. ZFS dataset
# zroot/root/omnigraph, on a second virtual disk, is mounted at
# /var/lib/omnigraph by the test script, as an operator mounts it on
# magnetite. One graph, cookbook-beads, with its seed and featured query.
#
# The node boots the module on the bucket. The specialisation `earlier` is
# a stand-in for a generation before the static user: the same
# configuration, its units with DynamicUser and a user name that exists
# nowhere, so systemd allocates one. The specialisation `local` is the
# module on the root /var/lib/omnigraph/clusters/cookbooks-f17 of the
# dataset. The script switches between the three with
# switch-to-configuration test.
#
# What this establishes, each step serving the same entity count and
# stored-query answer:
#   1. the earlier generation leaves /var/lib/omnigraph a symlink to
#      /var/lib/private/omnigraph owned 65534:65534, as on magnetite today;
#   2. its first start under the static user moves the directory back to a
#      plain /var/lib/omnigraph, and the server serves from the bucket
#      (what deploying the module to magnetite on R2 does);
#   3. a switch back to the earlier generation from there, with no dataset
#      mounted, moves it into /var/lib/private again and serves (a rollback
#      of that deploy);
#   4. the runbook's preparation of a local root from that state (stop,
#      remove the symlink and the private directory, mount the dataset,
#      root-owned) and a switch to `local`: systemd hands the dataset to
#      `omnigraph`, the bootstrap and seed run on it, and it serves;
#   5. a switch back to `r2` with the dataset still mounted at
#      /var/lib/omnigraph: every unit starts and serves from the bucket;
#   6. a switch to the earlier generation with the dataset still mounted
#      fails the units' start at the state directory step (EBUSY from
#      rename(2) of a mountpoint), and once the dataset is unmounted, the
#      runbook's step for rolling back past the static user, they start and
#      serve.
#
# What it does not establish: R2 itself, the generation before the static
# user exactly (a stand-in that differs from it only in the units' user;
# activation removes the static user of a later generation, which this
# test cannot do while switching specialisations), or the disko-declared
# dataset magnetite mounts at boot.
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
      # Medium: its script took 64.90, 63.80 and 69.27 s in three runs on
      # pyrite on 2026-11-26, over the small limit of 60 s.
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-state-directory-transitions.class = "medium";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        omnigraph-state-directory-transitions =
          let
            nodePkgs = import inputs.nixpkgs {
              inherit system;
              overlays = [ self.overlays.default ];
            };
            reference = self.nixosConfigurations.magnetite.config.services.omnigraph;
            roots = self.lib.omnigraphClusterRoots;
            backup = self.lib.omnigraphBackup;
            graph = "cookbook-beads";
            question = "blocked";
            adminToken = "admin-test-token";
            seederToken = "seeder-test-token";
            s3User = "omnigraph-test";
            s3Secret = "omnigraph-test-secret";
            units = [
              "omnigraph-cluster-bootstrap"
              "omnigraph-cluster-apply"
              "omnigraph-server"
              "omnigraph-seed-${graph}"
            ];

            # The node's configuration, on the bucket.
            common =
              { config, ... }:
              let
                zfs = config.boot.zfs.package;
              in
              {
                imports = [
                  self.modules.nixos.omnigraph
                  self.modules.nixos.node-exporter-textfile
                  self.modules.nixos.observability-notify
                  # Every omnigraph unit waits for the bucket.
                  {
                    systemd.services = lib.genAttrs units (_: {
                      requires = [ "omnigraph-test-bucket.service" ];
                      after = [ "omnigraph-test-bucket.service" ];
                    });
                  }
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
                  "omnigraph-test/rustfs".text = ''
                    RUSTFS_ACCESS_KEY=${s3User}
                    RUSTFS_SECRET_KEY=${s3Secret}
                  '';
                  "omnigraph-test/s3.env".text = ''
                    AWS_ACCESS_KEY_ID=${s3User}
                    AWS_SECRET_ACCESS_KEY=${s3Secret}
                  '';
                };

                # The pool and the dataset, created on the first boot,
                # imported on later ones; the script mounts the dataset.
                systemd.services.omnigraph-test-pool = {
                  wantedBy = [ "zfs-import.target" ];
                  before = [
                    "zfs-import-zroot.service"
                    "zfs-import.target"
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

                services.rustfs = {
                  enable = true;
                  environmentFile = "/etc/omnigraph-test/rustfs";
                  settings = {
                    RUSTFS_ADDRESS = "127.0.0.1:9000";
                    RUSTFS_CONSOLE_ENABLE = "false";
                  };
                };
                systemd.services.omnigraph-test-bucket = {
                  wantedBy = [ "multi-user.target" ];
                  requires = [ "rustfs.service" ];
                  after = [ "rustfs.service" ];
                  path = [ nodePkgs.curl ];
                  serviceConfig = {
                    Type = "oneshot";
                    RemainAfterExit = true;
                  };
                  # 409 once the bucket exists, on a later boot.
                  script = ''
                    for _ in $(seq 60); do
                      status=$(curl -s -o /dev/null -w '%{http_code}' --aws-sigv4 aws:amz:us-east-1:s3 \
                        --user ${s3User}:${s3Secret} -X PUT http://127.0.0.1:9000/sciexp || true)
                      case $status in
                        200 | 409) exit 0 ;;
                      esac
                      sleep 1
                    done
                    exit 1
                  '';
                };
                services.omnigraph = {
                  enable = true;
                  inherit (reference) package bindAddress port;
                  storageUri = roots.uriIn "r2" "cookbooks-f17";
                  requireAllGraphs = true;
                  bearerTokensFile = nodePkgs.writeText "tokens.json" (builtins.toJSON { admin = adminToken; });
                  cluster = {
                    settings = {
                      inherit (reference.cluster.settings) metadata;
                      graphs = lib.getAttrs [ graph ] reference.cluster.settings.graphs;
                      policies = lib.mapAttrs (
                        _: policy:
                        policy
                        // {
                          applies_to = lib.filter (g: g == "cluster" || g == graph) policy.applies_to;
                        }
                      ) reference.cluster.settings.policies;
                    };
                    inherit (reference.cluster) extraFiles actor;
                    graphs.${graph} = {
                      exampleDataOnly = true;
                      seed = {
                        inherit (reference.cluster.graphs.${graph}.seed) file actor;
                        tokenFile = "/etc/omnigraph-test/seeder-token";
                      };
                    };
                  };
                  s3 = {
                    endpointUrl = "http://127.0.0.1:9000";
                    region = "us-east-1";
                  };
                  environmentFile = "/etc/omnigraph-test/s3.env";
                  # The stand-in answers plain HTTP, which Lance's object
                  # store refuses unless allowed.
                  extraEnvironment.AWS_ALLOW_HTTP = "true";
                };
              };

            # A generation before the static user: every omnigraph unit a
            # DynamicUser under a name no static user has.
            earlierGeneration = {
              systemd.services = lib.genAttrs units (_: {
                serviceConfig = {
                  DynamicUser = lib.mkForce true;
                  User = lib.mkForce "omnigraph-earlier";
                  Group = lib.mkForce "omnigraph-earlier";
                };
              });
            };

            # The module on the local root of the dataset.
            localStore = {
              services.omnigraph = {
                storageUri = lib.mkForce (roots.uriIn "local" "cookbooks-f17");
                s3.endpointUrl = lib.mkForce null;
                s3.region = lib.mkForce null;
                environmentFile = lib.mkForce null;
              };
            };
          in
          pkgs.testers.runNixOSTest {
            name = "omnigraph-state-directory-transitions";
            requiredFeatures = {
              kvm = true;
              nixos-test = true;
            };
            qemu.forceAccel = true;
            node.pkgs = lib.mkForce nodePkgs;
            nodes.machine = {
              imports = [ common ];
              specialisation = {
                earlier.configuration = earlierGeneration;
                local.configuration = localStore;
              };
            };
            testScript = ''
              import json

              DATASET = "${backup.dataset}"
              STATE = "${backup.mountpoint}"
              PRIVATE = "/var/lib/private/omnigraph"
              UNITS = ${builtins.toJSON (map (u: "${u}.service") units)}

              def answers():
                  """The graph's entity count on main and its featured query's rows."""
                  def call(method, path, data=""):
                      out = machine.succeed(
                          f"curl -sS -o /tmp/body -w '%{{http_code}}' -X {method} -H 'Omnigraph-Http-Api: 0.14'"
                          f" -H 'authorization: Bearer ${adminToken}'{data}"
                          f" 'http://127.0.0.1:${toString reference.port}/graphs/${graph}{path}' && echo && cat /tmp/body"
                      )
                      status, _, body = out.partition("\n")
                      assert status == "200", f"{method} {path}: {status} {body}"
                      return json.loads(body)
                  snapshot = call("GET", "/snapshot")
                  rows = call("POST", "/queries/${question}", " -H 'content-type: application/json' -d '{\"params\": {}}'")["rows"]
                  return {"entities": sum(d["entity_count"] for d in snapshot["datasets"]), "rows": rows}

              def serving():
                  machine.wait_for_unit("omnigraph-server.service")
                  machine.wait_until_succeeds("systemctl is-active omnigraph-seed-${graph}.service", timeout=120)
                  return answers()

              def switch(name):
                  """switch-to-configuration test into the specialisation, or the booted generation for None."""
                  top = "/run/booted-system" + ("" if name is None else f"/specialisation/{name}")
                  return machine.execute(f"{top}/bin/switch-to-configuration test 2>&1")

              def layout():
                  out = machine.succeed(f"stat -c '%F %U(%u):%G(%g) %N' {STATE}; stat -c '%F %u:%g %n' {PRIVATE} 2>&1 || true").strip()
                  print(out)
                  return out

              def static_units():
                  for unit in UNITS:
                      assert machine.succeed(f"systemctl show -P User {unit}").strip() == "omnigraph", unit
                      assert machine.succeed(f"systemctl show -P DynamicUser {unit}").strip() == "no", unit

              def stop_units():
                  machine.succeed("systemctl stop " + " ".join(UNITS))

              def start_server():
                  machine.succeed("systemctl reset-failed")
                  return machine.execute("systemctl start omnigraph-server.service 2>&1")

              start_all()
              before = serving()
              print(f"answers: {json.dumps(before, sort_keys=True)}")

              with subtest("the earlier generation keeps the state directory private, as on magnetite"):
                  stop_units()
                  machine.succeed(f"rm -r {STATE}")
                  code, out = switch("earlier")
                  assert code == 0, out
                  code, out = start_server()
                  assert code == 0, out
                  assert serving() == before
                  assert machine.succeed(f"readlink {STATE}").strip() == "private/omnigraph", layout()
                  assert machine.succeed(f"stat -c %u:%g {PRIVATE}").strip() == "65534:65534", layout()
                  layout()

              with subtest("the static user's first start moves it back to a plain directory, and serves from the bucket"):
                  code, out = switch(None)
                  assert code == 0, out
                  code, out = start_server()
                  assert code == 0, out
                  static_units()
                  assert serving() == before
                  machine.succeed(f"test -d {STATE} && test ! -L {STATE} && test ! -e {PRIVATE}")
                  print(machine.succeed("journalctl -o cat --no-pager | grep -A1 'Found pre-existing private StateDirectory=' | tail -2"))
                  layout()

              with subtest("rolling back from there moves it into /var/lib/private again, and serves"):
                  code, out = switch("earlier")
                  assert code == 0, out
                  code, out = start_server()
                  assert code == 0, out
                  assert serving() == before
                  assert machine.succeed(f"readlink {STATE}").strip() == "private/omnigraph", layout()
                  layout()

              with subtest("the runbook's dataset at the state directory, root-owned, is handed to omnigraph and serves locally"):
                  stop_units()
                  machine.succeed(f"rm {STATE} && rm -r {PRIVATE}")
                  machine.succeed(f"zfs mount {DATASET}")
                  assert machine.succeed(f"stat -c %U:%G {STATE}").strip() == "root:root", layout()
                  code, out = switch("local")
                  assert code == 0, out
                  code, out = start_server()
                  assert code == 0, out
                  static_units()
                  assert serving() == before
                  machine.succeed(f"findmnt -n -o SOURCE {STATE} | grep -qx {DATASET}")
                  machine.succeed("test -e ${roots.uriIn "local" "cookbooks-f17"}/__cluster")
                  stray = machine.succeed(f"find {STATE} -xdev ! -user omnigraph -print -o ! -group omnigraph -print")
                  assert stray == "", stray
                  layout()

              with subtest("back to the bucket with the dataset still mounted: every unit starts and serves"):
                  code, out = switch(None)
                  assert code == 0, out
                  code, out = start_server()
                  assert code == 0, out
                  static_units()
                  assert serving() == before
                  machine.succeed(f"findmnt -n -o SOURCE {STATE} | grep -qx {DATASET}")
                  layout()

              with subtest("rolling back past the static user needs the dataset unmounted"):
                  switch("earlier")
                  code, out = start_server()
                  print(out)
                  assert code != 0, out
                  journal = machine.succeed("journalctl -o cat --no-pager -u omnigraph-server.service -u omnigraph-cluster-bootstrap.service")
                  refused = [line for line in journal.splitlines() if "STATE_DIRECTORY" in line or "execution directory" in line]
                  assert refused, journal
                  print("\n".join(refused[-3:]))
                  stop_units()
                  machine.succeed(f"zfs unmount {DATASET}")
                  code, out = start_server()
                  assert code == 0, out
                  assert serving() == before
                  assert machine.succeed(f"readlink {STATE}").strip() == "private/omnigraph", layout()
                  layout()
            '';
          };
      };
    };
}
