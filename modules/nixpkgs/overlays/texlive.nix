{ ... }:
{
  nixpkgsOverlaysByName.texlive = [
    (final: prev: {
      texliveWithPackages = prev.texliveSmall.withPackages (
        ps: with ps; [
          algorithm2e
          algorithmicx
          algorithms
          algpseudocodex
          apacite
          appendix
          caption
          classicthesis
          cm-super
          currvita
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
        ]
      );
    })
  ];
}
