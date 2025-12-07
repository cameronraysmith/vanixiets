# nvim-treesitter-main overlay integration
#
# Uses iofq/nvim-treesitter-main flake to provide nvim-treesitter main branch
# with pre-compiled grammars from upstream parsers.lua. This ensures grammar
# versions are aligned with the nvim-treesitter plugin version.
#
# Key benefits over manual overlay:
# - Grammar-plugin version alignment (prevents "Invalid node type" errors)
# - Automated daily updates via nvim-treesitter-main CI
# - Cachix binary cache for pre-built grammars
# - withPlugins/withAllGrammars with proper install_dir patching
#
# The overlay provides:
# - pkgs.vimPlugins.nvim-treesitter (main branch with grammars)
# - pkgs.vimPlugins.nvim-treesitter-unwrapped (base plugin without grammars)
# - pkgs.vimPlugins.nvim-treesitter-textobjects (main branch compatible)
# - pkgs.vimPlugins.nvim-treesitter.grammarPlugins (individual grammars)
#
# Date migrated: 2025-12-07
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    inputs.nvim-treesitter-main.overlays.default
  ];
}
