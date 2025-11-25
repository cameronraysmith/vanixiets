{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        # publishing
        asciinema
        asciinema-agg
        exiftool
        ghostscript
        imagemagick
        markdown-tree-parser # pkgs/by-name
        poppler-utils
        qpdf
        quarto
        repomix
        svg2pdf
      ];
    };
}
