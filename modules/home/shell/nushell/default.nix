# Nushell modern structured shell with config files
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
        programs.nushell = {
          enable = true;
          envFile.source = ./env.nu;
          configFile.source = ./config.nu;
          inherit (config.home) shellAliases;
        };
      };
  };
}
