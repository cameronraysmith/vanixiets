{
  perSystem =
    {
      pkgs,
      inputs',
      config,
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
          pkgs.just
          pkgs.nh
          pkgs.nix-output-monitor
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
        ];

        passthru.meta.description = "Development environment with clan CLI and build tools";
      };
    };
}
