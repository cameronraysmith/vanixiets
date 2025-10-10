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
      # main branch has different structure: no parser/ directory
      # Make postPatch conditional to avoid rm failing on non-existent directory
      postPatch = ''
        [ -d parser ] && rm -r parser || true
      '';
      # Skip Lua Language Server meta annotation files from require check
      # _meta/parsers.lua is a type definition file that errors when required
      nvimSkipModules = [ "nvim-treesitter._meta.parsers" ];
    });

    # nvim-treesitter-textobjects must also use main branch to be compatible
    # master branch uses define_modules API which was removed in main branch rewrite
    nvim-treesitter-textobjects =
      super.vimPlugins.nvim-treesitter-textobjects.overrideAttrs
        (oldAttrs: {
          src = super.fetchFromGitHub {
            owner = "nvim-treesitter";
            repo = "nvim-treesitter-textobjects";
            rev = "main";
            hash = "sha256-+KmOpRi4JAqm6UqYdtk80jwFrJhLCs0lZM/Liofq0R4=";
          };
          version = "unstable-2025-10-09";
        });
  };
}
