{ ... }:
{
  flake.modules.homeManager.publishing =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        asciinema-agg
        exiftool
        ghostscript
        imagemagick
        impressive # pkgs/by-name - PDF presentations with OpenGL transitions
        librsvg # provides rsvg-convert
        markdown-tree-parser # pkgs/by-name
        mermaid-cli # provides mmdc
        poppler-utils
        qpdf
        quarto-bin # pkgs/by-name
        resvg
        shot-scraper
        svgo
      ];
    };
}
