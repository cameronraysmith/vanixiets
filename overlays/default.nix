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

  # ghc_filesystem: disable tests due to clang 21.x -Werror,-Wcharacter-conversion
  # Test suite fails on implicit char16_t to char32_t conversion in toUtf8
  # See: https://github.com/gulrak/filesystem/blob/v1.5.14/include/ghc/filesystem.hpp#L1675
  ghc_filesystem = super.ghc_filesystem.overrideAttrs (oldAttrs: {
    doCheck = false;
  });
}
