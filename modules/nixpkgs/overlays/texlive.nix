{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      texliveWithPackages = prev.texlive.combine {
        inherit (prev.texlive)
          scheme-small
          algorithm2e
          algorithmicx
          algorithms
          algpseudocodex
          apacite
          appendix
          caption
          cm-super
          dvipng
          framed
          git-latexdiff
          latexdiff
          latexmk
          latexpand
          multirow
          ncctools
          pdfcrop
          pdfjam
          placeins
          rsfs
          sttools
          threeparttable
          type1cm
          vruler
          wrapfig
          xurl
          ;
      };
    })
  ];
}
