# Auto-import all package overrides
#
# This directory contains per-package build modifications:
# - overrideAttrs changes
# - Test disabling
# - Build flag modifications
# - Patch applications
#
# Each file should export an overlay: final: prev: { ... }
#
# See README.md for when to use overrides vs hotfixes vs patches
#
{ flake, ... }:
final: prev:
let
  inherit (flake.inputs.nixpkgs) lib;

  # Auto-import all *.nix files except default.nix and _*.nix
  filterPath =
    name: type:
    !lib.hasPrefix "_" name && type == "regular" && lib.hasSuffix ".nix" name && name != "default.nix";

  dirContents = builtins.readDir ./.;
  filteredContents = lib.filterAttrs filterPath dirContents;
  overlayFiles = builtins.attrNames filteredContents;

  # Import each overlay file and merge them
  importedOverlays = builtins.foldl' (
    acc: name:
    let
      overlay = import (./. + "/${name}") final prev;
    in
    acc // overlay
  ) { } overlayFiles;
in
importedOverlays
