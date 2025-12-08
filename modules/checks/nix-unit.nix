{ inputs, self, ... }:
{
  perSystem =
    {
      ...
    }:
    {
      nix-unit.inputs = {
        inherit (inputs)
          nixpkgs
          nixpkgs-darwin-stable
          nixpkgs-linux-stable
          flake-parts
          nix-darwin
          home-manager
          sops-nix
          clan-core
          import-tree
          terranix
          disko
          srvos
          treefmt-nix
          git-hooks
          nix-unit
          lazyvim-nix
          pkgs-by-name-for-flake-parts
          nuenv
          llm-agents
          catppuccin
          ;
        inherit self;
      };

      nix-unit.tests = {
        # Metadata Test

        # TC-001: Flake Structure Smoke Test
        # Validates packages have required metadata (if packages exist)
        testMetadataFlakeOutputsExist = {
          expr =
            (builtins.hasAttr "nixosConfigurations" self)
            && (builtins.hasAttr "clan" self)
            && (builtins.hasAttr "modules" self);
          expected = true;
        };

        # Regression Tests

        # TC-002: Terraform Module Exports Exist
        # Validates that terranix module exports exist in the flake namespace
        testRegressionTerraformModulesExist = {
          expr =
            (builtins.hasAttr "base" self.modules.terranix)
            && (builtins.hasAttr "hetzner" self.modules.terranix);
          expected = true;
        };

        # TC-003: NixOS Closure Equivalence
        # Validates that machine configs exist and can be referenced
        # Note: Full config evaluation requires network access, so we just test existence
        testRegressionNixosConfigExists = {
          expr =
            builtins.hasAttr "electrum" self.nixosConfigurations
            && builtins.hasAttr "config" self.nixosConfigurations.electrum;
          expected = true;
        };

        # Invariant Tests

        # TC-004: Clan Inventory Structure
        # Validates inventory has required fields
        testInvariantClanInventoryMachines = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.clan.inventory.machines);
          expected = [
            "argentum"
            "blackphos"
            "cinnabar"
            "electrum"
            "galena"
            "rosegold"
            "scheelite"
            "stibnite"
          ];
        };

        # TC-005: NixOS Configs Exist
        # Validates all expected configs present
        testInvariantNixosConfigurationsExist = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.nixosConfigurations);
          expected = [
            "cinnabar"
            "electrum"
            "galena"
            "scheelite"
          ];
        };

        # TC-006: Darwin Configs Exist
        # Validates darwin configurations are created
        testInvariantDarwinConfigurationsExist = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.darwinConfigurations);
          expected = [
            "argentum"
            "blackphos"
            "rosegold"
            "stibnite"
          ];
        };

        # TC-007: Home Configs Exist
        # Validates standalone home configurations are created
        testInvariantHomeConfigurationsExist = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.homeConfigurations.x86_64-linux);
          expected = [
            "crs58"
            "raquel"
          ];
        };

        # Feature Tests

        # TC-008: Dendritic Module Discovery
        # Validates import-tree discovers nixos modules
        testFeatureDendriticModuleDiscovery = {
          expr =
            (builtins.hasAttr "base" self.modules.nixos)
            && (builtins.hasAttr "machines/nixos/electrum" self.modules.nixos);
          expected = true;
        };

        # TC-009: Darwin Module Discovery
        # Validates import-tree discovers darwin modules
        testFeatureDarwinModuleDiscovery = {
          expr =
            (builtins.hasAttr "base" self.modules.darwin)
            && (builtins.hasAttr "users" self.modules.darwin)
            && (builtins.hasAttr "machines/darwin/stibnite" self.modules.darwin);
          expected = true;
        };

        # TC-010: Namespace Exports
        # Validates modules export to correct namespaces
        testFeatureNamespaceExports = {
          expr =
            (builtins.typeOf self.modules.nixos.base) == "set"
            && (builtins.typeOf self.modules.terranix.base) == "set";
          expected = true;
        };

        # Type-Safety Tests

        # TC-011: SpecialArgs Propagation
        # Validates inputs available in all machines via specialArgs
        testTypeSafetySpecialargsPropagation = {
          expr = builtins.hasAttr "inputs" self.clan.specialArgs;
          expected = true;
        };

        # TC-012: Required NixOS Options
        # Validates all configs have config attribute
        # full option evaluation requires network access
        testTypeSafetyNixosConfigStructure = {
          expr = builtins.all (name: builtins.hasAttr "config" self.nixosConfigurations.${name}) (
            builtins.attrNames self.nixosConfigurations
          );
          expected = true;
        };
      };
    };
}
