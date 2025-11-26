{
  perSystem =
    {
      pkgs,
      inputs',
      config,
      ...
    }:
    let
      playwright-driver = inputs'.playwright-web-flake.packages.playwright-driver;
    in
    {
      devShells.default = pkgs.mkShell {
        inputsFrom = [ config.pre-commit.devShell ];

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
          # Playwright browser binaries for e2e tests
          playwright-driver
        ];

        # Set Playwright to use nix-provided browsers
        PLAYWRIGHT_BROWSERS_PATH = playwright-driver;
        PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD = "1";

        passthru.meta.description = "Development environment with clan CLI and build tools";
      };
    };
}
