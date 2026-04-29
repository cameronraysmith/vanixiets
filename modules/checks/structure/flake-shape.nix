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

        structure-home-configurations-linux = mkCheck {
          name = "home-configurations-linux";
          actual = sortedNames self.homeConfigurations.x86_64-linux;
          expected = [
            "crs58"
            "raquel"
          ];
        };

        structure-home-configurations-systems = mkCheck {
          name = "home-configurations-systems";
          actual = sortedNames self.homeConfigurations;
          expected = [
            "aarch64-darwin"
            "x86_64-linux"
          ];
        };
      };
    };
}
