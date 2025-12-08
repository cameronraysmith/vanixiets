# WezTerm terminal emulator configuration
# Reference: https://alexplescan.com/posts/2024/08/10/wezterm/
{ ... }:
{
  flake.modules = {
    homeManager.development =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.wezterm = {
          enable = true;
          extraConfig = builtins.readFile ./wezterm.lua;
        };
      };
  };
}
