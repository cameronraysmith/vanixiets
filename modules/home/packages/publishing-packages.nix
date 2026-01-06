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
        impressive # pkgs/by-name - PDF presentations with OpenGL transitions
        markdown-tree-parser # pkgs/by-name
        poppler-utils
        qpdf
        quarto
        repomix
        svg2pdf
      ];
    };
}
