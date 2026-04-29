# Structural shape checks for top-level flake outputs.
#
# These assertions enumerate machine and configuration sets and compare
# attribute-name lists to a literal expectation. Failures point at silent
# drift between the inventory (clan/inventory/machines.nix), the per-system
# discovery namespaces, and the consumer-facing flake outputs.
#
# Implemented as runCommand JSON-diff (via flake.lib.mkStructuralCheck)
# rather than nix-unit because the assertion target is a pure attribute-name
# list computed at outer eval time. nix-unit's expression-evaluation harness
# adds no value over `diff -u` here.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;
      sortedNames = attrset: lib.naturalSort (builtins.attrNames attrset);
    in
    {
      checks = {
        structure-inventory-machines = mkCheck {
          name = "inventory-machines";
          actual = sortedNames self.clan.inventory.machines;
          expected = [
            "argentum"
            "blackphos"
            "cinnabar"
            "electrum"
            "galena"
            "magnetite"
            "rosegold"
            "scheelite"
            "stibnite"
          ];
        };

        structure-nixos-configurations = mkCheck {
          name = "nixos-configurations";
          actual = sortedNames self.nixosConfigurations;
          expected = [
            "cinnabar"
            "electrum"
            "galena"
            "magnetite"
            "scheelite"
          ];
        };

        structure-darwin-configurations = mkCheck {
          name = "darwin-configurations";
          actual = sortedNames self.darwinConfigurations;
          expected = [
            "argentum"
            "blackphos"
            "rosegold"
            "stibnite"
          ];
        };

        structure-home-configurations = mkCheck {
          name = "home-configurations";
          actual = sortedNames self.homeConfigurations;
          expected = [
            "cameron@aarch64-darwin"
            "cameron@aarch64-linux"
            "cameron@x86_64-linux"
            "crs58@aarch64-darwin"
            "crs58@aarch64-linux"
            "crs58@x86_64-linux"
            "raquel@aarch64-darwin"
            "raquel@aarch64-linux"
            "raquel@x86_64-linux"
          ];
        };
      };
    };
}
