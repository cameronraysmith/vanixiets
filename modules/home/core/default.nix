# Core aggregate directory marker
# Individual modules in core/ are auto-discovered by import-tree
# and merged into homeManager.core aggregate namespace
{ ... }:
{
  # Pattern A empty stub - defines flake module namespace
  # All configuration in core/*.nix files:
  # - catppuccin.nix (global theme enable)
  # - fonts.nix (fontconfig enable)
  # - bitwarden.nix (bitwarden CLI config)
  # - xdg.nix (XDG base directory spec)
  # - session-variables.nix (environment variables)
  flake.modules.homeManager.core = { ... }: { };
}
