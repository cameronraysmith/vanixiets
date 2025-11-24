# Zellij terminal multiplexer with catppuccin theme
# Pattern A: flake.modules (plural) with homeManager.shell aggregate
{ ... }:
{
  flake.modules = {
    homeManager.shell =
      {
        pkgs,
        config,
        lib,
        flake,
        ...
      }:
      {
        programs.zellij = {
          enable = true;
          settings = {
            # https://github.com/nix-community/home-manager/issues/3854
            theme = "catppuccin-mocha";
          };
        };
      };
  };
}
