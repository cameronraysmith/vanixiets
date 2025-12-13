# Typst markup-based typesetting system
#
# Uses pkgs.typstWithPackages from the typst overlay which includes
# pre-fetched packages (CeTZ, Fletcher) for reproducible builds.
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.typstWithPackages
      ];
    };
}
