{
  perSystem =
    {
      pkgs,
      inputs',
      config,
      self',
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [
          config.pre-commit.devShell
          # Inherit playwright browser setup (sets PLAYWRIGHT_BROWSERS_PATH, etc.)
          inputs'.playwright-web-flake.devShells.default
        ];

        packages = [
          inputs'.clan-core.packages.default
          inputs'.nix2container.packages.skopeo-nix2container
          pkgs.just
          pkgs.nh
          pkgs.nix-output-monitor
          pkgs.nix-update
          pkgs.nix-prefetch-github
          self'.packages.beads-viewer
          self'.packages.gastown
          # Tools required by Makefile verify target
          pkgs.age
          pkgs.ssh-to-age
          pkgs.sops
          # Tools required by TypeScript packages CI
          pkgs.bun
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
    };
}
