# nvim-treesitter upstream tracking
#
# Overrides nixpkgs nvim-treesitter to track upstream more closely.
# Preserves nixpkgs grammar infrastructure (grammarPlugins passthru).
#
# Architecture note:
# - nvim-treesitter plugin: updated to recent upstream
# - grammarPlugins: remain at nixpkgs versions
# - Grammars are built separately by nixpkgs with their own lockfile
#
# Uses fetchFromGitHub instead of flake inputs to avoid content address
# serialization issues between Nix versions.
#
# TODO: Remove when nixpkgs nvim-treesitter catches up or if unnecessary
# Date added: 2025-12-05
#
{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      vimPlugins = prev.vimPlugins.extend (
        finalVimPlugins: prevVimPlugins: {
          # Override nvim-treesitter to upstream
          nvim-treesitter = prevVimPlugins.nvim-treesitter.overrideAttrs (old: {
            version = "unstable-2025-11-17";
            src = final.fetchFromGitHub {
              owner = "nvim-treesitter";
              repo = "nvim-treesitter";
              rev = "c682a239a9404ce5f90a2d0da34790eff1ed2932";
              hash = "sha256-HwQTSSEW2yW3T0XbongCaOL+/STOuaAZhLkII/evoKM=";
            };
            # Preserve passthru from nixpkgs (grammarPlugins, withPlugins, etc.)
            # The overrideAttrs keeps all original passthru attributes
          });

          # Also override textobjects to upstream
          nvim-treesitter-textobjects = prevVimPlugins.nvim-treesitter-textobjects.overrideAttrs (old: {
            version = "unstable-2025-11-17";
            src = final.fetchFromGitHub {
              owner = "nvim-treesitter";
              repo = "nvim-treesitter-textobjects";
              rev = "227165aaeb07b567fb9c066f224816aa8f3ce63f";
              hash = "sha256-VUrpzaazSSo5KYJ/oOi2WH/QtpFDNFKs9CqqgO/tnmw=";
            };
          });
        }
      );
    })
  ];
}
