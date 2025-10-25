{ inputs, ... }:
{
  imports = [
    (inputs.git-hooks + /flake-module.nix)
  ];
  perSystem =
    {
      inputs',
      config,
      pkgs,
      system,
      ...
    }:
    let
      # Playwright driver from versioned flake (synced with package.json)
      playwrightDriver = inputs.playwright-web-flake.packages.${system}.playwright-driver;
    in
    {
      devShells.default = pkgs.mkShell {
        name = "dev";
        meta.description = "Dev environment for nix-config";
        inputsFrom = [ config.pre-commit.devShell ];
        packages = with pkgs; [
          # Core development tools
          git # Version control (used in justfile recipes)
          just # Task runner

          # GNU tools (justfile dependencies)
          # Provides consistent behavior across platforms, especially for:
          # - cut: hash/field extraction (7+ uses)
          # - grep: pattern matching
          # - sed: text transformation and --in-place editing
          # - head/tail/sort/basename: text processing
          coreutils # cut, head, tail, basename, sort, echo, cat, tr, etc.
          gnugrep # grep with PCRE2 support
          gnused # sed with --in-place
          findutils # find, xargs (rarely used but available)

          # Nix tooling
          nixd # Nix language server
          nix-output-monitor # Pretty nix build output (nom)
          omnix # Nix CI orchestration (om)
          cachix # Binary cache management
          ratchet # GitHub Actions version pinning

          # Secrets management
          sops # Secrets encryption
          age # Age encryption
          ssh-to-age # SSH to age key conversion
          inputs'.agenix.packages.default # Agenix CLI
          bitwarden-cli # Bitwarden CLI (bw) for key extraction

          # Utilities
          jq # JSON processing
          gh # GitHub CLI

          # Documentation toolchain
          bun # JavaScript runtime and package manager
          nodePackages.typescript # TypeScript compiler
          # E2E testing browsers from playwright-web-flake (pinned to 1.56.1)
        ];

        shellHook = ''
          # Playwright browser configuration (version-locked via flake input)
          export PLAYWRIGHT_BROWSERS_PATH="${playwrightDriver.browsers}"
          export PLAYWRIGHT_SKIP_BROWSER_DOWNLOAD=1
          export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
        '';
      };

      pre-commit.settings = {
        hooks.nixfmt-rfc-style.enable = true;
      };
    };
}
