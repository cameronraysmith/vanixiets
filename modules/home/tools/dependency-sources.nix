{ config, ... }:
{
  flake.modules.homeManager.tools.imports = [ config.flake.modules.homeManager.dependency-sources ];
  flake.modules.homeManager.dependency-sources =
    { pkgs, ... }:
    {
      key = "vanixiets/dependency-sources-home-module";
      home.packages = [ pkgs.dependency-sources ];
    };
}
