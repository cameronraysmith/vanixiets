# Terminal aggregate directory marker
# Individual modules in terminal/ are auto-discovered by import-tree
# and merged into homeManager.terminal aggregate namespace
{ ... }:
{
  # Namespace stub for import-tree aggregate discovery
  # All configuration in terminal/*.nix files:
  # - direnv.nix (direnv + nix-direnv)
  # - fzf.nix (fuzzy finder)
  # - lsd.nix (modern ls)
  # - bat.nix (syntax highlighting cat)
  # - btop.nix (resource monitor)
  # - htop.nix (process viewer)
  # - jq.nix (JSON processor)
  # - nix-index.nix (nix package search)
  # - nnn.nix (file manager)
  # - zoxide.nix (smart cd)
  # - autojump.nix (directory navigation)
  flake.modules.homeManager.terminal = { ... }: { };
}
