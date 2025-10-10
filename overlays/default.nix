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

  # Override nvim-treesitter to use main branch for LazyVim compatibility
  # The master branch (which nixpkgs uses) is archived and lacks get_installed()
  # function that LazyVim requires. Main branch is the active development branch.
  # Note: overrideAttrs preserves passthru attributes (withPlugins, builtGrammars, etc.)
  # from nixpkgs' nvim-treesitter/overrides.nix
  vimPlugins = super.vimPlugins // {
    nvim-treesitter = super.vimPlugins.nvim-treesitter.overrideAttrs (oldAttrs: {
      src = super.fetchFromGitHub {
        owner = "nvim-treesitter";
        repo = "nvim-treesitter";
        rev = "main";
        hash = "sha256-1zVgNJJiKVskWF+eLllLB51iwg10Syx9IDzp90fFDWU=";
      };
      version = "unstable-2025-10-09";
    });
  };
}
