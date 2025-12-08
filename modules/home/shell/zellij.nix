# Zellij terminal multiplexer with catppuccin theme
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
