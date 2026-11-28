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
      fleetPin =
        actual:
        mkCheck {
          name = "fleet-pin";
          inherit actual;
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
      fleetClasses = lib.mapAttrs (_: m: m.machineClass) self.clan.inventory.machines;
      # structure-fleet also builds the pin over two mutants of the fleet, one
      # machine dropped and that machine's class flipped, and fails unless the
      # pin fails on each.
      mutated = lib.head (lib.attrNames fleetClasses);
      fleetMutants = {
        dropped = removeAttrs fleetClasses [ mutated ];
        flipped = fleetClasses // {
          ${mutated} = if fleetClasses.${mutated} == "darwin" then "nixos" else "darwin";
        };
      };
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-fleet.class = "small";
        structure-home-configurations.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        structure-fleet =
          pkgs.runCommand "structure-fleet"
            { meta.description = "structural check: fleet, and its failure on mutants of the fleet"; }
            ''
              : ${fleetPin fleetClasses}
              ${lib.concatStringsSep "\n" (
                lib.mapAttrsToList (mutant: actual: ''
                  if ! grep -qF "structural check 'fleet-pin' failed" ${pkgs.testers.testBuildFailure (fleetPin actual)}/testBuildFailure.log; then
                    echo "structure-fleet: the pin did not fail on the ${mutant} mutant (${mutated})"
                    exit 1
                  fi
                '') fleetMutants
              )}
              touch $out
            '';

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
