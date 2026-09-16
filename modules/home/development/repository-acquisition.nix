{ config, ... }:
let
  homeModules = config.flake.modules.homeManager;
in
{
  flake.modules.homeManager.ghq =
    { pkgs, ... }:
    {
      key = "vanixiets/ghq-home-module";
      home.packages = [ pkgs.ghq ];
    };

  flake.modules.homeManager.repository-acquisition =
    { config, lib, ... }:
    {
      key = "vanixiets/repository-acquisition-home-module";
      imports = [
        homeModules.ghq
        homeModules.ghq-sync
        homeModules.dependency-sources
      ];
      # An enabled zoxide module already installs its selected package and owns shell hooks.
      home.packages = lib.mkIf (!config.programs.zoxide.enable) [ config.programs.zoxide.package ];
    };
}
