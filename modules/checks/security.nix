{ self, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks =
        {
          x86_64-linux = {
            # nixbot: median 4.6 s, slowest 52 s, 911 runs in 30 days
            gitleaks.class = "small";
          };
          aarch64-darwin = {
            # nixbot: median 16 s, slowest 870 s, 804 runs in 30 days
            gitleaks.class = "small";
          };
        }
        .${system} or { };
      checks.gitleaks =
        pkgs.runCommand "gitleaks-check"
          {
            nativeBuildInputs = [ pkgs.gitleaks ];
            src = self;
          }
          ''
            # Canary: the repo config must detect a fake GitHub token. The token is
            # assembled here so it never exists in the tree being scanned below.
            mkdir canary
            printf 'token = "%s%s"\n' 'ghp_' 'Zq7Xw3Rt9Lk2Mn5Bv8Cx1Jh4Gf6Ds0Pa3Yu7E' > canary/canary.txt
            rc=0
            gitleaks detect --no-git --no-banner --redact --source canary --config $src/.gitleaks.toml || rc=$?
            if [ "$rc" != 1 ]; then
              echo "gitleaks canary: expected exit 1 (leak found) with .gitleaks.toml, got $rc" >&2
              exit 1
            fi

            cd $src
            gitleaks detect --no-git --source . --config .gitleaks.toml --verbose
            touch $out
          '';
    };
}
