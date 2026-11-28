# The internal overlay options. Overlay files in modules/nixpkgs/overlays/
# contribute `nixpkgsOverlaysByName.<name> = [ (final: prev: { ... }) ];`;
# modules/nixpkgs/compose.nix orders the names, defines nixpkgsOverlays and
# folds it into flake.overlays.default. These options live at the top level
# (not under `flake.*`) and are `internal = true`, so they are no flake
# outputs, after flake-parts core's `allSystems` (modules/perSystem.nix lines
# 141-145 in nix-workspace/flake-parts).
{ lib, ... }:
{
  options.nixpkgsOverlaysByName = lib.mkOption {
    type = lib.types.attrsOf (lib.types.uniq (lib.types.listOf lib.types.unspecified));
    default = { };
    internal = true;
    description = ''
      The nixpkgs overlays of each file in modules/nixpkgs/overlays/, under a
      name that modules/nixpkgs/compose.nix places in the overlay order. Not a
      flake output.
    '';
  };

  options.nixpkgsOverlays = lib.mkOption {
    type = lib.types.listOf lib.types.unspecified;
    readOnly = true;
    internal = true;
    description = ''
      nixpkgsOverlaysByName in the order modules/nixpkgs/compose.nix writes,
      which defines it. Not a flake output.
    '';
  };

  options.customPackageExcludes = lib.mkOption {
    type = lib.types.listOf lib.types.str;
    default = [ ];
    internal = true;
    description = ''
      Names of pkgs/by-name packages withheld from the composed default
      overlay (modules/nixpkgs/compose.nix) so that upstream nixpkgs provides
      them instead on machines. Not a flake output.
    '';
  };
}
