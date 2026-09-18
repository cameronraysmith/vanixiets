{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    let
      deferred = [ "scheelite" ];
      inventory = self.clan.inventory.machines;
      machineSystems = self.lib.machineSystems;

      inventoryNamesFor =
        machineClass:
        builtins.attrNames (lib.filterAttrs (_: machine: machine.machineClass == machineClass) inventory);

      nixosForSystem = lib.filterAttrs (
        name: machine:
        machine.machineClass == "nixos"
        && machineSystems.${name} == system
        && !(builtins.elem name deferred)
      ) inventory;

      darwinForSystem = lib.filterAttrs (
        name: machine: machine.machineClass == "darwin" && machineSystems.${name} == system
      ) inventory;

      obligations = self.lib.omnigentFleetObligations;

      withFleetObligations =
        name: machineConfig: toplevel:
        let
          unmet = obligations.failures name machineConfig;
          hostFailures = map (a: a.message) (lib.filter (a: !a.assertion) machineConfig.assertions);
        in
        assert lib.assertMsg (unmet == [ ]) (
          "Omnigent fleet obligations unmet on ${name}: ${lib.concatStringsSep ", " unmet}"
          + lib.optionalString (hostFailures != [ ]) (
            "\n${name} assertion failures: ${lib.concatStringsSep "\n" hostFailures}"
          )
        );
        toplevel;
    in
    assert lib.assertMsg (
      builtins.attrNames machineSystems == builtins.attrNames inventory
    ) "flake.lib.machineSystems names must match clan.inventory.machines";
    assert lib.assertMsg (
      inventoryNamesFor "nixos" == builtins.attrNames self.nixosConfigurations
    ) "NixOS inventory names must match nixosConfigurations";
    assert lib.assertMsg (
      inventoryNamesFor "darwin" == builtins.attrNames self.darwinConfigurations
    ) "Darwin inventory names must match darwinConfigurations";
    assert lib.assertMsg (lib.all (name: inventory ? ${name} && !(builtins.elem name deferred)) (
      lib.attrNames obligations.expectedOwners
    )) "every machine carrying Omnigent fleet obligations must have a machine check to assert them";
    {
      checks =
        (lib.mapAttrs' (
          name: _:
          lib.nameValuePair "nixos-${name}" (
            withFleetObligations name self.nixosConfigurations.${name}.config
              self.nixosConfigurations.${name}.config.system.build.toplevel
          )
        ) nixosForSystem)
        // (lib.mapAttrs' (
          name: _:
          lib.nameValuePair "darwin-${name}" (
            withFleetObligations name self.darwinConfigurations.${name}.config
              self.darwinConfigurations.${name}.system
          )
        ) darwinForSystem);
    };
}
