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
        markdown-tree-parser
        poppler-utils
        qpdf
        quarto
        repomix
        svg2pdf
      ];
    };
}
