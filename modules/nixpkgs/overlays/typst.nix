{ ... }:
{
  flake.nixpkgsOverlays = [
    (final: prev: {
      # Typst with pre-fetched packages for reproducible builds.
      # Note: typst.withPackages does NOT auto-resolve typstDeps from
      # nixpkgs' typst-packages-from-universe.toml, so transitive deps
      # must be listed explicitly.
      typstWithPackages = prev.typst.withPackages (
        ps: with ps; [
          # Transitive dependencies (must be explicit)
          oxifmt_0_2_1 # required by cetz 0.3.4

          # Top-level packages
          fletcher # diagrams with nodes and arrows (pulls cetz)
          chronos # sequence diagrams
          polylux # presentations
        ]
      );
    })
  ];
}
