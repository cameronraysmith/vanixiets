{ config, ... }:
{
  flake.modules.homeManager.tools.imports = [ config.flake.modules.homeManager.ghq-sync ];
  flake.modules.homeManager.ghq-sync =
    { pkgs, ... }:
    {
      key = "vanixiets/ghq-sync-home-module";
      home.packages = [ pkgs.ghq-sync ];
    };
}
