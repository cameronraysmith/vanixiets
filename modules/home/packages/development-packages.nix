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
      # from nix-ai-tools
      coderabbit-cli =
        flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.coderabbit-cli;
      crush = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.crush;
      droid = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.droid;
      gemini-cli = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli;
      opencode = flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.opencode;
    in
    {
      home.packages =
        with pkgs;
        [
          # nix dev
          cachix
          nil
          nix-info
          nix-output-monitor
          nix-prefetch-scripts
          nixd
          nixfmt
          nixpkgs-reviewFull
          omnix

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
          gitmux
          graphite-cli
          graphviz
          jc
          jqp
          jjui
          # lazyjj
          just
          # markdown-tree-parser # custom overlay in infra, not available in test-clan
          mkcert
          # from nix-ai-tools
          coderabbit-cli
          crush
          droid
          gemini-cli
          opencode
          #------
          plantuml-c4
          pre-commit
          proto # version manager NOT protobuf-related
          ratchet
          shellcheck
          # starship-jj # custom overlay in infra, not available in test-clan
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
        ++ lib.optionals (pkgs.stdenv.hostPlatform.system == "x86_64-linux") [
          flake.inputs.nix-ai-tools.packages.${pkgs.stdenv.hostPlatform.system}.backlog-md
        ];
    };
}
