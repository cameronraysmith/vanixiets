{
  perSystem =
    {
      lib,
      pkgs,
      inputs',
      config,
      self',
      ...
    }:
    let
      # Match the home-manager python environment from development-packages.nix.
      # duckdb routes to nixpkgs' python3Packages.duckdb here because the
      # perSystem pkgs overlay does not include customPackages from compose.nix.
      # The local duckdb/python-duckdb pair lives in pkgs/by-name/ with the
      # machine-shadowing toggle in modules/nixpkgs/duckdb-local.nix; this
      # devshell intentionally still resolves python duckdb from nixpkgs.
      # To use the local build here instead: append `config.packages.python-duckdb`.
      python = pkgs.python3.withPackages (
        ps: with ps; [
          duckdb
          huggingface-hub
          pip
          trafilatura
        ]
      );
    in
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [
          config.pre-commit.devShell
          # Inherit playwright browser setup (sets PLAYWRIGHT_BROWSERS_PATH, etc.)
          inputs'.playwright-web-flake.devShells.default
        ];

        packages = [
          python
          inputs'.clan-core.packages.default
          inputs'.nix2container.packages.skopeo-nix2container
          pkgs.just
          pkgs.nh
          pkgs.omnix
          pkgs.nix-output-monitor
          self'.packages.nix-fast-build
          pkgs.nix-update
          pkgs.nix-prefetch-github
          self'.packages.gastown
          # Tools required by Makefile verify target
          pkgs.age
          pkgs.ssh-to-age
          pkgs.sops
          # Kubernetes cluster management
          pkgs.clusterctl
          pkgs.kluctl
          pkgs.k3d
          pkgs.ctlptl
          pkgs.kyverno-chainsaw
          pkgs.rsync # nixidy-sync manifest deployment
          # Tools required by TypeScript packages CI
          pkgs.bun
          inputs'.bun2nix.packages.default
          pkgs.nodejs_24 # semantic-release >= 24.10.0
          pkgs.fuc
          pkgs.rip2
          # Language detection
          pkgs.github-linguist
          # Document typesetting
          pkgs.typstWithPackages
          pkgs.svgo
        ]
        # buildbot-effects CLI for local dispatch of hercules-ci-effects
        # (see buildbot-nix/docs/EFFECTS.md). Linux-only: depends on bwrap.
        ++ lib.optionals pkgs.stdenv.isLinux [
          inputs'.buildbot-nix.packages.buildbot-effects
        ];

        passthru.meta.description = "Development environment with clan CLI and build tools";
      };
    };
}
