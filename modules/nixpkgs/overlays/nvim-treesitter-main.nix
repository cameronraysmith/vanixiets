# nvim-treesitter main branch tracking
#
# Overrides nixpkgs nvim-treesitter to track upstream main branch.
# Preserves nixpkgs grammar infrastructure (grammarPlugins passthru).
#
# Architecture note:
# - nvim-treesitter plugin: updated to main branch (Oct 2025+)
# - grammarPlugins: remain at nixpkgs versions (May 2025)
# - Grammars are built separately by nixpkgs with their own lockfile
#
# If grammar version mismatches cause issues during testing, report back
# to orchestrator for potential full LazyVim-module grammar port (3686 lines).
#
{ inputs, ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      vimPlugins = prev.vimPlugins.extend (
        finalVimPlugins: prevVimPlugins: {
          # Override nvim-treesitter to main branch
          nvim-treesitter = prevVimPlugins.nvim-treesitter.overrideAttrs (old: {
            version = "main-${builtins.substring 0 8 inputs.nvim-treesitter.lastModifiedDate}-${
              inputs.nvim-treesitter.shortRev or "dirty"
            }";
            src = inputs.nvim-treesitter;

            # Preserve passthru from nixpkgs (grammarPlugins, withPlugins, etc.)
            # The overrideAttrs keeps all original passthru attributes
          });

          # Also override textobjects to main branch
          nvim-treesitter-textobjects = prevVimPlugins.nvim-treesitter-textobjects.overrideAttrs (old: {
            version = "main-${builtins.substring 0 8 inputs.nvim-treesitter-textobjects.lastModifiedDate}-${
              inputs.nvim-treesitter-textobjects.shortRev or "dirty"
            }";
            src = inputs.nvim-treesitter-textobjects;
          });
        }
      );
    })
  ];
}
