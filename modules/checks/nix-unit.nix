{ inputs, self, ... }:
{
  perSystem =
    {
      ...
    }:
    {
      # Pass the inputs nix-unit needs to override during evaluation, plus
      # any transitive flake nodes whose locked URL is unreachable from the
      # buildbot worker sandbox (no DNS in pure-eval mode).
      #
      # nix-unit-flake-parts emits each entry as `--override-input <key>
      # <path>` (lib/modules/flake/system.nix). nix only honors the override
      # when <key> matches either:
      #   1. a top-level input of the flake under test, OR
      #   2. a transitive input expressed as <parent>/<child> (slash syntax).
      # Synthetic keys that don't match either form are SILENTLY DISCARDED
      # (nix prints a "non-existent input" warning and proceeds with the
      # original lockfile entry). Closure-presence of the path does NOT
      # cause fetchTree to short-circuit; substitution and override are
      # separate mechanisms.
      #
      # Transitive entries (slash-keyed, value is the transitive flake):
      #   - "clan-core/nixpkgs": clan-core/flake.lock pins nixpkgs to a
      #     releases.nixos.org/nixpkgs tarball not cached on cache.nixos.org
      #     and not reachable from the buildbot sandbox. We deliberately do
      #     NOT set clan-core.inputs.nixpkgs.follows in flake.nix because
      #     doing so breaks cache.clan.lol substitution of clan-cli in the
      #     devshell (different derivation hash). The transitive override
      #     here is scoped to the check only — flake-wide follows is
      #     unaffected.
      #
      # If a future buildbot run fails on a different transitive node
      # (e.g. nixpkgs_3 from llm-agents, or nixpkgs_7 from
      # nix-index-database), add a sibling entry of the form
      #   "<top-level>/<sub>" = inputs.<top-level>.inputs.<sub>;
      nix-unit.inputs = {
        inherit (inputs)
          nixpkgs
          nixpkgs-darwin-stable
          nixpkgs-linux-stable
          flake-parts
          systems
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
          hercules-ci-effects
          ;
        inherit self;
        "clan-core/nixpkgs" = inputs.clan-core.inputs.nixpkgs;
      };

      nix-unit.tests = {
        # TC-001: Flake Structure Smoke Test
        testMetadataFlakeOutputsExist = {
          expr =
            (builtins.hasAttr "nixosConfigurations" self)
            && (builtins.hasAttr "clan" self)
            && (builtins.hasAttr "modules" self);
          expected = true;
        };

        # TC-002: Terraform Module Exports Exist
        testRegressionTerraformModulesExist = {
          expr =
            (builtins.hasAttr "base" self.modules.terranix)
            && (builtins.hasAttr "hetzner" self.modules.terranix);
          expected = true;
        };

        # TC-003: NixOS Closure Equivalence
        # Full config evaluation requires network access, so we just test existence.
        testRegressionNixosConfigExists = {
          expr =
            builtins.hasAttr "electrum" self.nixosConfigurations
            && builtins.hasAttr "config" self.nixosConfigurations.electrum;
          expected = true;
        };

        # TC-004: Clan Inventory Structure
        testInvariantClanInventoryMachines = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.clan.inventory.machines);
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

        # TC-005: NixOS Configs Exist
        testInvariantNixosConfigurationsExist = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.nixosConfigurations);
          expected = [
            "cinnabar"
            "electrum"
            "galena"
            "magnetite"
            "scheelite"
          ];
        };

        # TC-006: Darwin Configs Exist
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
        testInvariantHomeConfigurationsExist = {
          expr = builtins.sort builtins.lessThan (builtins.attrNames self.homeConfigurations.x86_64-linux);
          expected = [
            "crs58"
            "raquel"
          ];
        };

        # TC-008: Module Discovery
        testFeatureModuleDiscovery = {
          expr =
            (builtins.hasAttr "base" self.modules.nixos)
            && (builtins.hasAttr "machines/nixos/electrum" self.modules.nixos);
          expected = true;
        };

        # TC-009: Darwin Module Discovery
        testFeatureDarwinModuleDiscovery = {
          expr =
            (builtins.hasAttr "base" self.modules.darwin)
            && (builtins.hasAttr "users" self.modules.darwin)
            && (builtins.hasAttr "machines/darwin/stibnite" self.modules.darwin);
          expected = true;
        };

        # TC-010: Namespace Exports
        # NixOS module system accepts both attrsets and functions as modules.
        testFeatureNamespaceExports = {
          expr =
            let
              isValidModule = m: builtins.isFunction m || builtins.isAttrs m;
            in
            isValidModule self.modules.nixos.base && isValidModule self.modules.terranix.base;
          expected = true;
        };

        # TC-011: SpecialArgs Propagation
        testTypeSafetySpecialargsPropagation = {
          expr = builtins.hasAttr "inputs" self.clan.specialArgs;
          expected = true;
        };

        # TC-012: Required NixOS Options
        # Full option evaluation requires network access, so we just test existence.
        testTypeSafetyNixosConfigStructure = {
          expr = builtins.all (name: builtins.hasAttr "config" self.nixosConfigurations.${name}) (
            builtins.attrNames self.nixosConfigurations
          );
          expected = true;
        };

        # TC-013: Namespace Merging
        # Files in the same module directory auto-merge into a single namespace.
        testInvariantNamespaceMerging = {
          expr =
            (builtins.hasAttr "ai" self.modules.homeManager)
            && (builtins.hasAttr "development" self.modules.homeManager)
            && (builtins.hasAttr "shell" self.modules.homeManager);
          expected = true;
        };

        # TC-014: Clan Module Integration
        testInvariantClanModuleIntegration = {
          expr =
            let
              darwinMachines = [
                "stibnite"
                "blackphos"
                "rosegold"
                "argentum"
              ];
              nixosMachines = [
                "cinnabar"
                "electrum"
                "galena"
                "scheelite"
              ];
              hasDarwinModule = m: builtins.hasAttr "machines/darwin/${m}" self.modules.darwin;
              hasNixosModule = m: builtins.hasAttr "machines/nixos/${m}" self.modules.nixos;
            in
            builtins.all hasDarwinModule darwinMachines && builtins.all hasNixosModule nixosMachines;
          expected = true;
        };

        # TC-015: Import-Tree Completeness
        testFeatureImportTreeCompleteness = {
          expr =
            (builtins.hasAttr "base" self.modules.darwin)
            && (builtins.hasAttr "base" self.modules.nixos)
            && (builtins.hasAttr "core" self.modules.homeManager)
            && (builtins.hasAttr "base" self.modules.terranix);
          expected = true;
        };

        # TC-016: Crossplatform Home Modules
        testInvariantCrossplatformHomeModules = {
          expr =
            (builtins.hasAttr "x86_64-linux" self.homeConfigurations)
            && (builtins.hasAttr "aarch64-darwin" self.homeConfigurations);
          expected = true;
        };
      };
    };
}
