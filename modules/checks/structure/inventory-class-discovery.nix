# Cross-cutting invariant: for every machine in the clan inventory, its
# `machineClass` field agrees with the discovery namespace in which the
# machine's per-host module appears.
#
# Replaces the prior TC-014 nix-unit smoke test, which asserted only
# *existence* of the per-host modules and would not have failed if a
# machine's machineClass were silently mis-tagged (e.g., cinnabar tagged
# "darwin" while its module lives at modules/machines/nixos/cinnabar).
#
# This check fails iff inventory and discovery disagree, producing a JSON
# diff between the (machine -> "nixos"|"darwin") map computed from the
# inventory and the same map computed from the discovery namespaces.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      mkCheck = self.lib.mkStructuralCheck pkgs;

      inventoryClasses = lib.mapAttrs (_: m: m.machineClass) self.clan.inventory.machines;

      classFromDiscovery =
        machine:
        if builtins.hasAttr "machines/nixos/${machine}" self.modules.nixos then
          "nixos"
        else if builtins.hasAttr "machines/darwin/${machine}" self.modules.darwin then
          "darwin"
        else
          "missing";

      discoveryClasses = lib.mapAttrs (
        machine: _: classFromDiscovery machine
      ) self.clan.inventory.machines;
    in
    {
      checks.structure-inventory-class-discovery = mkCheck {
        name = "inventory-class-discovery";
        actual = discoveryClasses;
        expected = inventoryClasses;
      };
    };
}
