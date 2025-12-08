# Nushell modern structured shell with config files
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
        programs.nushell = {
          enable = true;
          envFile.source = ./env.nu;
          configFile.source = ./config.nu;
          inherit (config.home) shellAliases;
        };
      };
  };
}
