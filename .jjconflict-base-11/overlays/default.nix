# Main overlay composition
#
# Architecture:
#   1. inputs       - Multi-channel nixpkgs access (stable, patched, etc.)
#   2. hotfixes     - Platform-specific stable fallbacks for broken packages
#   3. packages     - Custom derivations
#   4. overrides    - Per-package build modifications
#   5. flakeInputs  - Overlays from flake inputs (nuenv, etc.)
#
# Merge order matters: later layers can reference earlier layers
#
# Note: Infrastructure files are in infra/ subdirectory (Phase 1 design)
#       to avoid nixos-unified autowiring conflicts
#
# Note: Debug/experimental packages are in legacyPackages.debug (not overlay)
#       See modules/flake-parts/debug-packages.nix
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

  # Import overlay layers
  # Each layer gets overlayArgs for access to flake (inputs, lib, etc.)
  inputs' = import ./inputs.nix overlayArgs self super;
  hotfixes = import ./infra/hotfixes.nix self super; # Note: infra/ subdirectory
  overrides = import ./overrides overlayArgs self super;

  # Overlays from flake inputs
  flakeInputs = {
    # Expose nuenv for nushell script packaging (analogous to writeShellApplication for bash)
    nuenv = (inputs.nuenv.overlays.nuenv self super).nuenv;

    # NOTE: jujutsu overlay disabled due to disk space constraints in CI
    # Building jujutsu from source (inputs.jj) causes "No space left on device" errors
    # Using nixpkgs version instead until CI runners have more disk space
    #
    # Original overlay (disabled):
    # jujutsu = inputs.jj.packages.${super.system}.jujutsu or super.jujutsu;
    #
    # To re-enable: uncomment above line and ensure sufficient disk space (~20GB+)
    # Reference: https://github.com/martinvonz/jj

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
  overrides # Per-package build modifications (includes ghc_filesystem)
  flakeInputs # Overlays from flake inputs (nuenv, etc.)
]
