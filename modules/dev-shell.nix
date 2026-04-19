{
  perSystem =
    {
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
          pkgs.fuc # (rm/cp)z
          pkgs.rip2
          # Language detection
          pkgs.github-linguist
          # Document typesetting
          pkgs.typstWithPackages
        ];

        # Make fonts available to typst for consistent rendering across environments
        TYPST_FONT_PATHS = pkgs.lib.concatStringsSep ":" [
          "${pkgs.inter}/share/fonts/truetype"
          "${pkgs.lmodern}/share/fonts"
          "${pkgs.newcomputermodern}/share/fonts"
        ];

        passthru.meta.description = "Development environment with clan CLI and build tools";
      };

      # Minimal shell for kubernetes CI (k3d integration tests)
      devShells.kubernetes = pkgs.mkShell {
        packages = [
          pkgs.git
          pkgs.just
          pkgs.k3d
          pkgs.ctlptl
          pkgs.kubectl
          pkgs.kluctl
          pkgs.sops
          pkgs.age
          pkgs.rsync
          pkgs.kyverno-chainsaw
        ];

        passthru.meta.description = "Minimal environment for k3d integration tests";
      };
    };
}
