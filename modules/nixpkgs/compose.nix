# Overlay composition. Each file under overlays/ adds its overlays under a
# name in nixpkgsOverlaysByName; overlayOrder below is the one place their
# order is written, so moving or renaming an overlay file changes no package
# set. The list keeps the order the overlays had when it was written, which
# no overlay relies on; a new overlay's name is appended. nixpkgsOverlays is
# that order's list, applied by the perSystem pkgs (per-system.nix) and
# composed here into flake.overlays.default, which base-defaults.nix's
# fleetPkgs gives machines and standalone homes.
{
  config,
  lib,
  withSystem,
  ...
}:
let
  overlayOrder = [
    "zed-delta"
    "typst"
    "texlive"
    "stable-fallbacks"
    "shot-scraper"
    "opentelemetry-collector"
    "openclaw"
    "nuenv"
    "nixos-facter"
    "mactop"
    "gh-stack"
    "clipboard-jh"
    "channels"
    "bitwarden-cli"
    "apm"
    "aeneas"
  ];
  named = config.nixpkgsOverlaysByName;
  unordered = lib.subtractLists overlayOrder (lib.attrNames named);
  undefined = lib.subtractLists (lib.attrNames named) overlayOrder;
  repeated = lib.unique (lib.filter (name: lib.count (n: n == name) overlayOrder > 1) overlayOrder);
in
{
  nixpkgsOverlays =
    lib.throwIf (unordered != [ ])
      "nixpkgsOverlaysByName: ${lib.concatStringsSep ", " unordered} missing from overlayOrder; append it to the list in modules/nixpkgs/compose.nix"
      (
        lib.throwIf (undefined != [ ])
          "overlayOrder in modules/nixpkgs/compose.nix names ${lib.concatStringsSep ", " undefined}, which no file under modules/nixpkgs/overlays/ defines"
          (
            lib.throwIf (repeated != [ ])
              "overlayOrder in modules/nixpkgs/compose.nix lists ${lib.concatStringsSep ", " repeated} more than once"
              (lib.concatMap (name: named.${name}) overlayOrder)
          )
      );

  # Compose all overlays into flake.overlays.default
  flake.overlays.default =
    final: prev:
    let
      internalOverlays = lib.composeManyExtensions config.nixpkgsOverlays;

      # Custom packages from pkgs-by-name
      # Provides: Project-specific packages (ccstatusline, etc.)
      # Only for config.systems: nixpkgs re-applies this overlay to nested sets
      # such as pkgsi686Linux, whose perSystem packages do not exist.
      system = prev.stdenv.hostPlatform.system;
      customPackages = lib.optionalAttrs (lib.elem system config.systems) (
        withSystem system ({ config, ... }: config.packages or { })
      );
    in
    # Compose all, in this order:
    # 1. Internal overlays via composeManyExtensions, in overlayOrder
    # 2. Custom packages (standalone derivations), minus any withheld via
    #    config.customPackageExcludes so upstream nixpkgs provides them instead
    (internalOverlays final prev) // (removeAttrs customPackages config.customPackageExcludes);
}
