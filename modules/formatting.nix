{ inputs, ... }:
{
  imports = [
    inputs.treefmt-nix.flakeModule
    inputs.git-hooks.flakeModule
  ];

  perSystem =
    { pkgs, ... }:
    {
      treefmt = {
        projectRootFile = "flake.nix";
        programs.nixfmt.enable = true;
      };

      # Keep local hooks but don't inject checks.pre-commit into nix flake check —
      # treefmt and gitleaks already run as individual checks with better cache granularity.
      pre-commit.check.enable = false;
      pre-commit.settings = {
        package = pkgs.prek;
        hooks.treefmt.enable = true;
        hooks.gitleaks = {
          enable = true;
          name = "gitleaks";
          entry = "${pkgs.gitleaks}/bin/gitleaks protect --staged --verbose --redact";
          language = "system";
          pass_filenames = false;
        };
      };

    };
}
