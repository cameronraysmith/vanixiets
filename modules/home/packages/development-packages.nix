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
      python = pkgs.python312.withPackages (
        ps: with ps; [
          pip
          huggingface-hub
        ]
      );
      dvcWithOptionalRemotes = pkgs.dvc.override {
        enableGoogle = true;
        enableAWS = true;
        enableAzure = true;
        enableSSH = true;
      };
      # from llm-agents
      beads = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.beads;
      coderabbit-cli = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.coderabbit-cli;
      crush = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.crush;
      # droid: disabled - auto-patchelf fails on rosetta-builder (missing pyelftools)
      # opencode: disabled - bun node_modules cleanup fails during build
      # TODO: Re-enable when upstream llm-agents fixes these issues
      # Disabled: 2025-11-26
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
          nix-info
          nix-output-monitor
          nix-prefetch-scripts
          nixd
          nixfmt
          nixpkgs-reviewFull
          statix

          # dev
          act
          bazelisk
          bazel-buildtools
          buf
          claude-monitor
          dvcWithOptionalRemotes
          gh
          git-filter-repo
          git-machete
          git-revise
          gitmux
          graphite-cli
          graphviz
          jc
          jqp
          jjui
          # lazyjj
          just
          mkcert
          # from llm-agents
          beads
          coderabbit-cli
          crush
          # droid      # disabled: auto-patchelf fails
          gemini-cli
          # opencode   # disabled: bun cleanup fails
          # from pkgs/by-name
          beads-viewer
          #------
          plantuml-c4
          pre-commit
          proto # version manager NOT protobuf-related
          ratchet
          shellcheck
          # starship-jj # pkgs/by-name
          # step-ca
          tea
          tmate
          tree-sitter
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

          # python
          dotnet-sdk_8 # for fable transpiler
          micromamba
          pixi
          poethepoet
          pydeps
          pylint
          pyright
          python
          ruff
          uv
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
