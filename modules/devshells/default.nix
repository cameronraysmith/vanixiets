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
      # Uses config.packages.python-duckdb (by-name) since the perSystem pkgs
      # overlay doesn't include customPackages from compose.nix.
      python = pkgs.python3.withPackages (
        ps:
        with ps;
        [
          huggingface-hub
          pip
          trafilatura
        ]
        ++ [
          config.packages.python-duckdb
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
          pkgs.nix-output-monitor
          self'.packages.nix-fast-build
          pkgs.nix-update
          pkgs.nix-prefetch-github
          # beads-viewer  # disabled: incompatible with dolt backend
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
