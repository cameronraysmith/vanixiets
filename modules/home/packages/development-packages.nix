{ ... }:
{
  flake.modules.homeManager.packages =
    {
      pkgs,
      lib,
      flake,
      ...
    }:
    let
      python = pkgs.python3.withPackages (
        ps: with ps; [
          duckdb
          huggingface-hub
          pip
          trafilatura
        ]
      );
      dvcWithOptionalRemotes = pkgs.dvc.override {
        enableGoogle = true;
        enableAWS = true;
        enableAzure = true;
        enableSSH = true;
      };
      # scala - pin sbt to specific JDK
      jdk = pkgs.temurin-bin-21;
      sbtWithJdk = pkgs.sbt.override { jre = jdk; };
      # coderabbit-cli = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.coderabbit-cli;
      # crush = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.crush;
      # opencode: disabled - bun node_modules cleanup fails during build
      droid = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.droid;
      gemini-cli = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli;
    in
    {
      home.packages =
        with pkgs;
        [
          # nix dev
          cachix
          deadnix
          nil
          nix-eval-jobs
          nix-info
          nix-output-monitor
          nix-prefetch-scripts
          nix-update
          nixd
          nixfmt
          nixpkgs-reviewFull
          statix

          # dev
          act
          bazelisk
          bazel-buildtools
          buf
          smithy-cli
          claude-monitor
          clipboard-jh
          dvcWithOptionalRemotes
          gh
          gh-dash
          git-filter-repo
          git-machete
          git-revise
          git-xet
          gitmux
          graphite-cli
          d2
          graphviz
          jc
          jqp
          jjui
          just
          mkcert
          # from llm-agents via modules/nixpkgs/overlays/beads.nix
          beads
          droid
          gemini-cli
          # from pkgs/by-name
          dolt
          gastown
          golem-binary
          #------
          plantuml-c4
          ratchet
          shellcheck
          tea
          tmate
          tree-sitter
          jaq
          yq

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
          micromamba
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
          elixir
          elixir-ls

          # dependently typed / proof assistants
          idris2
          idris2Packages.idris2Lsp
          lean4
          rocq-core
        ]
        # backlog-md disabled: auto-patchelf fails on rosetta-builder (elftools issue)
        # ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
        #   flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.backlog-md
        # ]
        # claudebox requires bubblewrap which is Linux-only
        ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
          flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.claudebox
        ];
    };
}
