# Typst markup-based typesetting system
#
# Uses pkgs.typstWithPackages from the typst overlay which includes
# pre-fetched packages (CeTZ, Fletcher) for reproducible builds.
{ config, ... }:
{
  flake.modules.homeManager.tools.imports = [ config.flake.modules.homeManager.typst ];
  flake.modules.homeManager.typst =
    { pkgs, ... }:
    {
      key = "vanixiets/typst-home-module";
      home.packages = [
        pkgs.typstWithPackages
      ];
    };
}
