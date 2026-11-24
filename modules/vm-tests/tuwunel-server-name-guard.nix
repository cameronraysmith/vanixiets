# vmTests.x86_64-linux.tuwunel-server-name-guard: cinnabar's homeserver units
# on a QEMU node, judging the one-shot reset that moves a database made for
# another server name aside before tuwunel starts (design D3). The node runs
# tuwunel with cinnabar's evaluated server name, state directory and
# ExecStartPre, plus cinnabar's tuwunel-server-name-guard unit when it has one,
# so the check judges the units as deployed, sandbox included; the script's
# own cases are in checks.x86_64-linux.matrix-server-name-reset.
#
# Cases, in one boot: no state directory (first start), a marker naming the
# configured server (kept), data without a marker (cinnabar's database before
# the marker existed), and a marker naming another server; each retirement
# lands beside the state directory and tuwunel then starts on an empty one.
#
# Non-gating, like every vmTest; it requires kvm, so it builds on pyrite.
{ self, lib, ... }:
let
  reference = self.nixosConfigurations.cinnabar.config;
  tuwunel = reference.services.matrix-tuwunel;
  units = reference.systemd.services;
  serverName = tuwunel.settings.global.server_name;
  state = "/var/lib/private/${tuwunel.stateDirectory}";
in
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size class (declare-test-size-classes design D4): no run measured yet.
      # Declared medium, the largest class that needs no run notice, so a wrong
      # guess fails at the 300 s timeout and that run is its measurement.
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        tuwunel-server-name-guard = {
          class = "medium";
          measured = false;
        };
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        tuwunel-server-name-guard = pkgs.testers.runNixOSTest {
          name = "tuwunel-server-name-guard";
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          nodes.machine = {
            services.matrix-tuwunel = {
              enable = true;
              inherit (tuwunel) stateDirectory;
              settings.global = {
                inherit (tuwunel.settings.global)
                  server_name
                  address
                  port
                  allow_federation
                  trusted_servers
                  ;
              };
            };
            # Started by the test script, after it lays down each case.
            systemd.services = {
              tuwunel = {
                wantedBy = lib.mkForce [ ];
                serviceConfig.ExecStartPre = units.tuwunel.serviceConfig.ExecStartPre or [ ];
              };
            }
            // lib.optionalAttrs (units ? tuwunel-server-name-guard) {
              tuwunel-server-name-guard = {
                inherit (units.tuwunel-server-name-guard) description before requiredBy;
                inherit (units.tuwunel-server-name-guard) serviceConfig;
              };
            };
          };
          testScript = ''
            state = "${state}"
            new = "${serverName}"

            def start():
                machine.succeed("systemctl start tuwunel.service")
                machine.wait_for_unit("tuwunel.service")

            def marker():
                return machine.succeed(f"cat {state}/.server-name").strip()

            def retired(name):
                return machine.succeed(f"find {state}.retired-{name}-* -maxdepth 0 -type d 2>/dev/null || true").split()

            machine.wait_for_unit("multi-user.target")

            with subtest("first start creates the state directory and marks it"):
                start()
                assert marker() == new, f"marker names {marker()}"
                assert retired("*") == [], f"retired on a first start: {retired('*')}"

            with subtest("a marker naming the configured server keeps the database"):
                machine.succeed("systemctl stop tuwunel.service", f"touch {state}/kept")
                start()
                machine.succeed(f"test -e {state}/kept")
                assert retired("*") == [], f"retired the current database: {retired('*')}"

            with subtest("data without a marker is retired"):
                machine.succeed("systemctl stop tuwunel.service", f"rm {state}/.server-name")
                start()
                [dest] = retired("unmarked")
                machine.succeed(f"test -e {dest}/kept", f"test ! -e {state}/kept")
                assert marker() == new, f"marker names {marker()}"

            with subtest("a marker naming another server is retired"):
                machine.succeed(
                    "systemctl stop tuwunel.service",
                    f"echo matrix.old > {state}/.server-name",
                    f"touch {state}/old-data",
                )
                start()
                [dest] = retired("matrix.old")
                machine.succeed(f"test -e {dest}/old-data", f"test ! -e {state}/old-data")
                assert marker() == new, f"marker names {marker()}"
          '';
        };
      };
    };
}
