{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    {
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
