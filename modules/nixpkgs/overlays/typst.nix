{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      typstWithPackages = prev.typst.withPackages (
        ps: with ps; [
          cetz
          fletcher
        ]
      );
    })
  ];
}
