# TeX Live distribution for LaTeX document processing
#
# Uses pkgs.texliveWithPackages from the texlive overlay which includes
# scheme-small plus packages for academic writing and algorithms.
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        pkgs.texliveWithPackages
      ];
    };
}
