{ ... }:
{
  nixpkgsOverlays = [
    (final: prev: {
      # Typst with pre-fetched packages and font paths baked in for
      # reproducible rendering across devshell and nix-sandbox builds.
      # Note: typst.withPackages does NOT auto-resolve typstDeps from
      # nixpkgs' typst-packages-from-universe.toml, so transitive deps
      # must be listed explicitly.
      typstWithPackages =
        let
          base = prev.typst.withPackages (
            ps: with ps; [
              # Transitive dependencies (must be explicit)
              oxifmt_0_2_1 # required by cetz 0.3.4

              # Top-level packages
              fletcher # diagrams with nodes and arrows (pulls cetz)
              chronos # sequence diagrams
              polylux # presentations
            ]
          );
          fontPaths = prev.lib.concatStringsSep ":" [
            "${prev.inter}/share/fonts/truetype"
            "${prev.lmodern}/share/fonts"
            "${prev.newcomputermodern}/share/fonts"
          ];
        in
        prev.symlinkJoin {
          name = "typst-with-packages-and-fonts";
          paths = [ base ];
          nativeBuildInputs = [ prev.makeWrapper ];
          postBuild = ''
            wrapProgram $out/bin/typst \
              --set-default TYPST_FONT_PATHS "${fontPaths}"
          '';
          inherit (base) meta;
        };
    })
  ];
}
