# Literal pins on the fleet and home-configuration sets.
#
# The eval-time asserts in modules/checks/machines.nix already require the
# inventory, clan.machines, the per-class nixos/darwinConfigurations and the
# modules/machines/<class>/ directories to agree with each other. What they
# cannot catch is a machine or user dropped from all of them at once: the
# per-machine and per-user checks would simply disappear. These pins fail
# in that case, and the fleet pin also fails when a machine's class flips.
#
# The values do not depend on the build system, so the checks exist only on
# x86_64-linux. Update the literals deliberately when adding or retiring a
# machine or user (`nix eval .#homeConfigurations --apply builtins.attrNames`).
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 8.7 s, slowest 71 s, all 3 runs 2026-10-07..2026-11-11
        structure-fleet.class = "small";
        # nixbot: median 2.8 s, slowest 30 s, all 10 runs 2026-09-04..2026-11-11
        structure-home-configurations.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-fleet = mkCheck {
          name = "fleet";
          actual = lib.mapAttrs (_: m: m.machineClass) self.clan.inventory.machines;
          expected = {
            argentum = "darwin";
            blackphos = "darwin";
            cinnabar = "nixos";
            electrum = "nixos";
            galena = "nixos";
            magnetite = "nixos";
            pyrite = "nixos";
            rosegold = "darwin";
            scheelite = "nixos";
            stibnite = "darwin";
          };
        };

        structure-home-configurations = mkCheck {
          name = "home-configurations";
          actual = builtins.attrNames self.homeConfigurations;
          expected = [
            "cameron@aarch64-darwin"
            "cameron@aarch64-linux"
            "cameron@x86_64-linux"
            "christophersmith@aarch64-darwin"
            "christophersmith@aarch64-linux"
            "christophersmith@x86_64-linux"
            "claude-sandbox@x86_64-linux"
            "crs58@aarch64-darwin"
            "crs58@aarch64-linux"
            "crs58@x86_64-linux"
            "janettesmith@aarch64-darwin"
            "janettesmith@aarch64-linux"
            "janettesmith@x86_64-linux"
            "raquel@aarch64-darwin"
            "raquel@aarch64-linux"
            "raquel@x86_64-linux"
            "tara@aarch64-darwin"
            "tara@aarch64-linux"
            "tara@x86_64-linux"
            "ubuntu@x86_64-linux"
          ];
        };
      };
    };
}
