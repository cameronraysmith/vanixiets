{ ... }:
{
  flake.modules.homeManager.packages =
    { pkgs, ... }:
    let
      python = pkgs.python3.withPackages (
        ps: with ps; [
          duckdb
          huggingface-hub
          pip
          trafilatura
        ]
      );
      # scala - pin sbt to specific JDK
      jdk = pkgs.temurin-bin-21;
      sbtWithJdk = pkgs.sbt.override { jre = jdk; };
    in
    {
      home.packages = with pkgs; [
        # Note: for quick experiments with different versions
        # of language toolchains, use proto as a dynamic version manager
        # versus a reproducible language-specific flake.
        # Versions installed below will be latest stable from nixpkgs.

        # rust
        dioxus-cli
        rustup

        # typescript
        bun
        nodejs_22
        pnpm
        tailwindcss_4
        yarn-berry

        # go
        go

        # scala
        sbtWithJdk

        # python
        # Disabled: dotnet-sdk requires Swift which has not been cached on
        # Hydra for aarch64-darwin since Dec 30, 2025. Monitor build status:
        #   https://hydra.nixos.org/job/nixpkgs/trunk/swiftPackages.swift.aarch64-darwin
        #   https://hydra.nixos.org/job/nixpkgs/trunk/dotnet-sdk.aarch64-darwin
        # dotnet-sdk_8 # for fable transpiler
        pixi
        poethepoet
        pydeps
        pylint
        pyright
        python
        ruff
        uv

        # haskell
        ghc
        cabal-install

        # ocaml
        ocaml
        dune_3
        opam

        # elixir
        beamPackages.elixir
        beamPackages.elixir-ls

        # dependently typed / proof assistants
        idris2
        idris2Packages.idris2Lsp
        rocq-core
      ];
    };
}
