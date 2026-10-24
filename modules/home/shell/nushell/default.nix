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
          # env.nu sets the environment itself; loading home.sessionVariables as well would change it.
          loadSessionVariables = false;
          inherit (config.home) shellAliases;
        };
      };
  };
}
