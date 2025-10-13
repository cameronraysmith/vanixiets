# Main overlay composition
#
# Architecture:
#   1. inputs       - Multi-channel nixpkgs access (stable, patched, etc.)
#   2. hotfixes     - Platform-specific stable fallbacks for broken packages
#   3. packages     - Custom derivations
#   4. debugPackages - Development/debug packages
#   5. overrides    - Per-package build modifications
#   6. flakeInputs  - Overlays from flake inputs (nuenv, etc.)
#
# Merge order matters: later layers can reference earlier layers
#
# Note: Infrastructure files are in infra/ subdirectory (Phase 1 design)
#       to avoid nixos-unified autowiring conflicts
#
{ flake, ... }:
let
  # Flake argument object for overlay modules
  overlayArgs = { inherit flake; };
in
self: super:
let
  inherit (super) lib;
  inherit (flake) inputs;

  # Import custom packages using nixpkgs helper
  fromDirectory =
    directory:
    lib.packagesFromDirectoryRecursive {
      callPackage = lib.callPackageWith self;
      inherit directory;
    };

  packages = fromDirectory ./packages;
  debugPackages = fromDirectory ./debug-packages;

  # Import overlay layers
  # Each layer gets overlayArgs for access to flake (inputs, lib, etc.)
  inputs' = import ./inputs.nix overlayArgs self super;
  hotfixes = import ./infra/hotfixes.nix self super; # Note: infra/ subdirectory
  overrides = import ./overrides overlayArgs self super;

  # Overlays from flake inputs
  flakeInputs = {
    # Expose nuenv for nushell script packaging (analogous to writeShellApplication for bash)
    nuenv = (inputs.nuenv.overlays.nuenv self super).nuenv;

    # nvim-treesitter override is now provided by LazyVim-module's overlay
    # See: inputs.lazyvim.overlays.nvim-treesitter-main applied in flake.nix
    # This approach is preferred as it:
    # - Uses LazyVim-module's flake inputs (automatically updated)
    # - Centralizes all LazyVim/neovim configuration in LazyVim-module
    # - Avoids duplicate overlay logic with hardcoded hashes
  };

in
# Merge all layers
# Order matters: inputs first (provides stable, patched), then hotfixes (uses stable),
# then packages, then overrides (can reference everything prior), then flakeInputs
lib.mergeAttrsList [
  inputs' # Multi-channel nixpkgs access
  hotfixes # Platform-specific stable fallbacks
  packages # Custom derivations from packages/
  debugPackages # Debug/development packages
  overrides # Per-package build modifications (includes ghc_filesystem)
  flakeInputs # Overlays from flake inputs (nuenv, etc.)
]
