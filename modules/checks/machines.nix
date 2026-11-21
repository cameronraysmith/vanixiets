{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    let
      deferred = [ "scheelite" ];
      inventory = self.clan.inventory.machines;
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
        machine.machineClass == "nixos"
        && machineSystems.${name} == system
        && !(builtins.elem name deferred)
      ) inventory;

      darwinForSystem = lib.filterAttrs (
        name: machine: machine.machineClass == "darwin" && machineSystems.${name} == system
      ) inventory;

      # Every network clan may reach the machine through logs in as its login
      # user, and its deploy address is flake.lib.hosts.<name>.targetHost
      # (modules/lib/network-targets.nix).
      withNetworkTargets =
        name: machineConfig: toplevel:
        let
          unmet = self.lib.networkTargetObligations.failures name machineConfig;
        in
        assert lib.assertMsg (
          unmet == [ ]
        ) "networkTargetObligations unmet on ${name}: ${lib.concatStringsSep "; " unmet}";
        toplevel;

      obligations = self.lib.omnigentFleetObligations;
      deployRecordObligations = self.lib.deployRecordObligations;
      commitSigningObligations = self.lib.commitSigningObligations;
      resolverReloadObligations = self.lib.resolverReloadObligations;
      meshHostsObligations = self.lib.meshHostsObligations;
      harmoniaGcObligations = self.lib.harmoniaGcObligations;
      postgresqlBackupObligations = self.lib.postgresqlBackupObligations;
      r2UsageObligations = self.lib.r2UsageObligations;
      fleetDeployer = self.lib.fleetDeployer;

      withFleetObligations =
        name: machineConfig: toplevel:
        let
          unmet = obligations.failures name machineConfig;
          unmetDeployRecord = deployRecordObligations.failures name machineConfig;
          unmetSigning = commitSigningObligations.failures name machineConfig;
          # Darwin only: NixOS has no /etc/resolver.
          unmetResolverReload = lib.optionals (lib.hasSuffix "-darwin" machineSystems.${name}) (
            resolverReloadObligations.failures name machineConfig
          );
          unmetMeshHosts = meshHostsObligations.failures name machineConfig;
          unmetHarmoniaGc = harmoniaGcObligations.failures name machineConfig;
          unmetPostgresqlBackup = postgresqlBackupObligations.failures name machineConfig;
          unmetR2Usage = r2UsageObligations.failures name machineConfig;
          unmetFleetDeployer = fleetDeployer.failures name machineConfig;
          hostFailures = map (a: a.message) (lib.filter (a: !a.assertion) machineConfig.assertions);
        in
        assert lib.assertMsg
          (
            unmet == [ ]
            && unmetDeployRecord == [ ]
            && unmetSigning == [ ]
            && unmetResolverReload == [ ]
            && unmetMeshHosts == [ ]
            && unmetHarmoniaGc == [ ]
            && unmetPostgresqlBackup == [ ]
            && unmetR2Usage == [ ]
            && unmetFleetDeployer == [ ]
          )
          (
            "Fleet obligations unmet on ${name}: omnigentFleetObligations [${lib.concatStringsSep ", " unmet}]; deployRecordObligations [${lib.concatStringsSep ", " unmetDeployRecord}]; commitSigningObligations [${lib.concatStringsSep ", " unmetSigning}]; resolverReloadObligations [${lib.concatStringsSep ", " unmetResolverReload}]; meshHostsObligations [${lib.concatStringsSep ", " unmetMeshHosts}]; harmoniaGcObligations [${lib.concatStringsSep ", " unmetHarmoniaGc}]; postgresqlBackupObligations [${lib.concatStringsSep ", " unmetPostgresqlBackup}]; r2UsageObligations [${lib.concatStringsSep ", " unmetR2Usage}]; fleetDeployer [${lib.concatStringsSep ", " unmetFleetDeployer}]"
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
    assert lib.assertMsg (
      builtins.attrNames self.clan.machines == builtins.attrNames inventory
    ) "clan.machines names must match clan.inventory.machines";
    assert lib.assertMsg (
      machineDirs "nixos" == inventoryNamesFor "nixos"
    ) "modules/machines/nixos/ directories must match the NixOS inventory machines";
    assert lib.assertMsg (
      machineDirs "darwin" == inventoryNamesFor "darwin"
    ) "modules/machines/darwin/ directories must match the Darwin inventory machines";
    assert lib.assertMsg (lib.all (name: inventory ? ${name} && !(builtins.elem name deferred)) (
      lib.attrNames obligations.expectedOwners
    )) "every machine carrying Omnigent fleet obligations must have a machine check to assert them";
    assert lib.assertMsg (
      fleetDeployer.problems == [ ]
    ) "flake.lib.fleetDeployer: ${lib.concatStringsSep "; " fleetDeployer.problems}";
    {
      checks =
        (lib.mapAttrs' (
          name: _:
          lib.nameValuePair "nixos-${name}" (
            withFleetObligations name self.nixosConfigurations.${name}.config (
              withNetworkTargets name self.nixosConfigurations.${name}.config
                self.nixosConfigurations.${name}.config.system.build.toplevel
            )
          )
        ) nixosForSystem)
        // (lib.mapAttrs' (
          name: _:
          lib.nameValuePair "darwin-${name}" (
            withFleetObligations name self.darwinConfigurations.${name}.config (
              withNetworkTargets name self.darwinConfigurations.${name}.config
                self.darwinConfigurations.${name}.system
            )
          )
        ) darwinForSystem);
    };
}
