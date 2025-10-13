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
      ...
    }:
    {
      devShells.default = pkgs.mkShell {
        name = "nix-config-shell";
        meta.description = "Dev environment for nix-config";
        inputsFrom = [ config.pre-commit.devShell ];
        packages = with pkgs; [
          just
          nixd
          nix-output-monitor
          omnix
          cachix
          ratchet
          # teller removed: migration to sops-nix complete
          sops
          age
          ssh-to-age
          inputs'.agenix.packages.default

          # SOPS key management tools
          bitwarden-cli # bw command for key extraction
          jq # JSON processing for Bitwarden API
          gh # GitHub CLI for secrets management

          # TypeScript documentation tools
          bun # JavaScript runtime and package manager
          nodePackages.typescript # TypeScript compiler
          playwright-driver.browsers # E2E testing browsers
        ];

        shellHook = ''
          # Playwright browser configuration
          export PLAYWRIGHT_BROWSERS_PATH="${pkgs.playwright-driver.browsers}"
          export PLAYWRIGHT_SKIP_VALIDATE_HOST_REQUIREMENTS=true
        '';
      };

      pre-commit.settings = {
        hooks.nixfmt-rfc-style.enable = true;
      };
    };
}
