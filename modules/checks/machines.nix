# Machine toplevel build-realization checks.
#
# Programmatic per-system derivation: iterates self.{nixos,darwin}Configurations,
# partitions by config.nixpkgs.hostPlatform.system, and emits one check per
# machine assigned to the current system. Mirrors home.nix's derivation-from-
# config precedent (enumerableUsers from flake.users) rather than the hardcoded
# mic92 attrset style.
#
# Excludes: scheelite (deferred pending GPU/CUDA cache readiness; see
# project_scheelite-gpu-deployment memory; coverage-map Q4).
#
# Closes: nix-144.3 (Phase 2 - darwin machine coverage).
{ self, lib, ... }:
{
  perSystem =
    { system, ... }:
    let
      deferred = [ "scheelite" ];

      nixosForSystem = lib.filterAttrs (
        name: cfg: cfg.config.nixpkgs.hostPlatform.system == system && !(builtins.elem name deferred)
      ) self.nixosConfigurations;

      darwinForSystem = lib.filterAttrs (
        name: cfg: cfg.config.nixpkgs.hostPlatform.system == system
      ) self.darwinConfigurations;
    in
    {
      checks =
        (lib.mapAttrs' (
          name: cfg: lib.nameValuePair "nixos-${name}" cfg.config.system.build.toplevel
        ) nixosForSystem)
        // (lib.mapAttrs' (name: cfg: lib.nameValuePair "darwin-${name}" cfg.system) darwinForSystem);
    };
}
