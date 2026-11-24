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

      # Size class of checks.treefmt, which treefmt-nix's flake module
      # generates (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log): 9.2 s (slowest 88 s,
      # 880 runs in 30 days) on x86_64-linux, 28 s (slowest 507 s, 821 runs)
      # on aarch64-darwin.
      testSizes.checks.treefmt.class = "small";

      # Keep local hooks but don't inject checks.pre-commit into nix flake check —
      # treefmt and gitleaks already run as individual checks with better cache granularity.
      pre-commit.check.enable = false;
      pre-commit.settings = {
        package = pkgs.prek;
        hooks.treefmt.enable = true;
        hooks.gitleaks.enable = true;
      };

    };
}
