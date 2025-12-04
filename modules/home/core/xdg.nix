# XDG base directory specification
# Migrated from vanixiets/modules/home/all/core/xdg.nix
{ ... }:
{
  flake.modules.homeManager.core =
    { config, pkgs, ... }:
    {
      # https://github.com/nix-community/home-manager/blob/master/modules/misc/xdg.nix
      # ~/.config, ~/.cache, ~/.local/share, ~/.local/state
      xdg.enable = true;
      # xdg.configHome = "${config.home.homeDirectory}/.config";
    };
}
