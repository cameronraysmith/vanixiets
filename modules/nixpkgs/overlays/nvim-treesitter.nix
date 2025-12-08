# nvim-treesitter-main overlay integration
#
# Uses iofq/nvim-treesitter-main flake to provide nvim-treesitter main branch
# with pre-compiled grammars from upstream parsers.lua. This ensures grammar
# versions are aligned with the nvim-treesitter plugin version.
#
# Benefits over manual overlay:
# - grammar-plugin version alignment
# - automated daily updates via nvim-treesitter-main CI
# - binary cache for pre-built grammars
# - withPlugins/withAllGrammars with proper install_dir patching
#
# The overlays provided are:
# - pkgs.vimPlugins.nvim-treesitter (main branch with grammars)
# - pkgs.vimPlugins.nvim-treesitter-unwrapped (base plugin without grammars)
# - pkgs.vimPlugins.nvim-treesitter-textobjects (main branch compatible)
# - pkgs.vimPlugins.nvim-treesitter.grammarPlugins (individual grammars)
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    inputs.nvim-treesitter-main.overlays.default
  ];
}
