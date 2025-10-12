{ flake, ... }:

self: super:
let
  inherit (super) lib;

  fromDirectory =
    directory:
    lib.packagesFromDirectoryRecursive {
      callPackage = lib.callPackageWith self;
      inherit directory;
    };

  packageOverrides = fromDirectory ./packages;
in
packageOverrides
// {
  # Additional overrides
  # omnix = inputs.omnix.packages.${self.system}.default;

  # nvim-treesitter override is now provided by LazyVim-module's overlay
  # See: inputs.lazyvim.overlays.nvim-treesitter-main applied in flake.nix
  # This approach is preferred as it:
  # - Uses LazyVim-module's flake inputs (automatically updated)
  # - Centralizes all LazyVim/neovim configuration in LazyVim-module
  # - Avoids duplicate overlay logic with hardcoded hashes
}
