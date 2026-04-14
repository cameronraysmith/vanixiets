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
            cd $src
            gitleaks detect --no-git --source . --verbose
            touch $out
          '';
    };
}
