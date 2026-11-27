{
  self,
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      inventory = self.clan.inventory.machines;
      hosts = self.lib.hosts;
      machineSystems = self.lib.machineSystems;

      machineDirs =
        machineClass:
        builtins.attrNames (
          lib.filterAttrs (_: type: type == "directory") (builtins.readDir ../machines/${machineClass})
        );

      inventoryNamesFor =
        machineClass:
        builtins.attrNames (lib.filterAttrs (_: machine: machine.machineClass == machineClass) inventory);

      nixosForSystem = lib.filterAttrs (
        name: machine:
        machine.machineClass == "nixos" && machineSystems.${name} == system && hosts.${name}.checked
      ) inventory;

      darwinForSystem = lib.filterAttrs (
        name: machine:
        machine.machineClass == "darwin" && machineSystems.${name} == system && hosts.${name}.checked
      ) inventory;

      # The judges registered in fleetObligations, each beside its definition
      # (modules/lib/fleet-obligations.nix). Literal, so that adding or
      # removing one is a deliberate edit here as well as at its registration.
      registeredObligations = [
        "commitSigningObligations"
        "deployRecordObligations"
        "fleetDeployer"
        "harmoniaGcObligations"
        "meshHostsObligations"
        "networkTargetObligations"
        "nixEvalJobsObligations"
        "omnigentFleetObligations"
        "postgresqlBackupObligations"
        "r2UsageObligations"
        "resolverReloadObligations"
        "sopsBootInstallObligations"
      ];
      registered = builtins.attrNames config.fleetObligations;

      # Every registered judge whose classes contain the configuration's class,
      # folded into one assertion that names each unmet judge. The class is
      # the configuration set being mapped, never the host's system string.
      withFleetObligations =
        class: name: machineConfig: toplevel:
        let
          unmet = lib.concatLists (
            lib.mapAttrsToList (
              key: entry:
              lib.optionals (lib.elem class entry.classes) (
                map (message: "${key}: ${message}") (entry.failures name machineConfig)
              )
            ) config.fleetObligations
          );
          hostFailures = map (a: a.message) (lib.filter (a: !a.assertion) machineConfig.assertions);
        in
        assert lib.assertMsg (unmet == [ ]) (
          "Fleet obligations unmet on ${name}:\n${lib.concatStringsSep "\n" unmet}"
          + lib.optionalString (hostFailures != [ ]) (
            "\n${name} assertion failures: ${lib.concatStringsSep "\n" hostFailures}"
          )
        );
        toplevel;
    in
    assert lib.assertMsg (builtins.attrNames machineSystems == builtins.attrNames inventory)
      "flake.lib.machineSystems names must match clan.inventory.machines; only in machineSystems: [${lib.concatStringsSep ", " (lib.subtractLists (builtins.attrNames inventory) (builtins.attrNames machineSystems))}]; only in the inventory: [${lib.concatStringsSep ", " (lib.subtractLists (builtins.attrNames machineSystems) (builtins.attrNames inventory))}]";
    assert lib.assertMsg (
      inventoryNamesFor "nixos" == builtins.attrNames self.nixosConfigurations
    ) "NixOS inventory names must match nixosConfigurations";
    assert lib.assertMsg (
      inventoryNamesFor "darwin" == builtins.attrNames self.darwinConfigurations
    ) "Darwin inventory names must match darwinConfigurations";
    assert lib.assertMsg (
      builtins.attrNames self.clan.machines == builtins.attrNames inventory
    ) "clan.machines names must match clan.inventory.machines";
    assert lib.assertMsg (
      machineDirs "nixos" == inventoryNamesFor "nixos"
    ) "modules/machines/nixos/ directories must match the NixOS inventory machines";
    assert lib.assertMsg (
      machineDirs "darwin" == inventoryNamesFor "darwin"
    ) "modules/machines/darwin/ directories must match the Darwin inventory machines";
    assert lib.assertMsg (lib.all (name: inventory ? ${name} && hosts.${name}.checked) (
      lib.attrNames self.lib.omnigentFleetObligations.expectedOwners
    )) "every machine carrying Omnigent fleet obligations must have a machine check to assert them";
    assert lib.assertMsg (
      self.lib.fleetDeployer.problems == [ ]
    ) "flake.lib.fleetDeployer: ${lib.concatStringsSep "; " self.lib.fleetDeployer.problems}";
    assert lib.assertMsg (registered == registeredObligations)
      "fleetObligations keys must equal registeredObligations in modules/checks/machines.nix; missing: ${lib.concatStringsSep ", " (lib.subtractLists registered registeredObligations)}; unlisted: ${lib.concatStringsSep ", " (lib.subtractLists registeredObligations registered)}";
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 14 s, slowest 395 s, 694 runs in 30 days
            nixos-cinnabar.class = "small";
            # nixbot: median 25 s, slowest 496 s, 698 runs in 30 days
            nixos-electrum.class = "small";
            # nixbot: median 23 s, slowest 323 s, 698 runs in 30 days
            nixos-galena.class = "small";
            # nixbot: median 25 s, slowest 996 s, 711 runs in 30 days
            nixos-magnetite.class = "small";
            # nixbot: median 24 s, slowest 541 s, 678 runs in 30 days
            nixos-pyrite.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 126 s, slowest 539 s, 571 runs in 30 days
            darwin-argentum.class = "medium";
            # nixbot: median 125 s, slowest 511 s, 560 runs in 30 days
            darwin-blackphos.class = "medium";
            # nixbot: median 125 s, slowest 491 s, 569 runs in 30 days
            darwin-rosegold.class = "medium";
            # nixbot: median 130 s, slowest 563 s, 576 runs in 30 days
            darwin-stibnite.class = "medium";
          };
        }
        .${system} or { };
      checks =
        (lib.mapAttrs' (
          name: _:
          lib.nameValuePair "nixos-${name}" (
            withFleetObligations "nixos" name self.nixosConfigurations.${name}.config
              self.nixosConfigurations.${name}.config.system.build.toplevel
          )
        ) nixosForSystem)
        // (lib.mapAttrs' (
          name: _:
          lib.nameValuePair "darwin-${name}" (
            withFleetObligations "darwin" name self.darwinConfigurations.${name}.config
              self.darwinConfigurations.${name}.system
          )
        ) darwinForSystem);
    };
}
