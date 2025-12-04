# Catppuccin theme configuration
# Extracted from vanixiets/modules/home/all/terminal/default.nix lines 302-303
{ ... }:
{
  flake.modules.homeManager.core =
    { ... }:
    {
      # Global catppuccin theme enable
      # Individual programs (tmux, bat, etc.) will use this theme automatically
      catppuccin = {
        enable = true;
        flavor = "mocha";
      };
    };
}
