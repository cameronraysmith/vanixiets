{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # Typst with pre-fetched packages for reproducible builds.
      # Fletcher depends on CeTZ which depends on oxifmt, so we include all
      # transitive dependencies explicitly to avoid runtime downloads.
      typstWithPackages = prev.typst.withPackages (
        ps: with ps; [
          oxifmt # transitive dep of cetz
          cetz
          fletcher
        ]
      );
    })
  ];
}
