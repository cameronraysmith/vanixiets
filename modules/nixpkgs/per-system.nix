# perSystem nixpkgs configuration
#
# configures pkgs for flake-parts perSystem (checks, packages, devShells, etc.)
#
# Use config.nixpkgsOverlays for overlay composition
# overlays/*.nix modules append to this list automatically via import-tree
{
  inputs,
  config,
  lib,
  ...
}:
{
  perSystem =
    { system, ... }:
    let
      # Configure nixpkgs with overlays
      pkgs = import inputs.nixpkgs {
        inherit system;
        config.allowUnfree = true;
        # Overlay composition from nixpkgsOverlays list
        # Auto-populated by overlays/*.nix modules (including nuenv.nix)
        overlays = config.nixpkgsOverlays;
      };
    in
    {
      # Provide pkgs to perSystem context
      _module.args.pkgs = pkgs;

      # Expose pkgs to flake level for clan-core consumption.
      # Clan-core reads flake.legacyPackages.${system} when building machines, so
      # our allowUnfree + overlay-composed scope must surface here.
      #
      # Force per-key (not the whole attrset) so other modules can additively
      # extend legacyPackages.${system}. lazyAttrsOf merges per-key, but
      # `lib.mkForce pkgs` claims the whole attrset at priority 50 and silently
      # drops sibling-module contributions. Per-key mkForce preserves the
      # priority-50 win for keys we own (resolving the original collision with
      # pkgs-by-name-for-flake-parts on key `packages`, which is a lambda in
      # nixpkgs but an attrset in the framework) while leaving novel keys at
      # default priority for other modules to define (e.g. modules/containers
      # exposes Darwin container variants under legacyPackages to escape strict
      # forcing by `nix flake check`).
      #
      # `packages` is excluded so pkgs-by-name-for-flake-parts can write its own
      # attrset there without triggering a lambda/attrset type clash.
      legacyPackages = lib.mapAttrs (_: lib.mkForce) (removeAttrs pkgs [ "packages" ]);

      # Custom packages via pkgs-by-name auto-discovery
      # Integrates custom derivations without depending on other overlay layers
      pkgsDirectory = ../../pkgs/by-name;
    };
}
