# The realizer's strict basedpyright run and its offline tests (automate-package-version-bumps
# design D9, tasks 3.1-3.4). The tests drive realize-pin with fake Http, Nix and Git
# capabilities fed recorded upstream checksum files, and a Files rooted in a
# temporary tree; the sandbox has no network and the tests fail on any socket.
{ lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      src = lib.fileset.toSource {
        root = ../../pkgs/by-name/realize-pin;
        fileset = lib.fileset.unions [
          ../../pkgs/by-name/realize-pin/pyproject.toml
          ../../pkgs/by-name/realize-pin/src
          ../../pkgs/by-name/realize-pin/tests
        ];
      };
      python = pkgs.python3.withPackages (ps: [
        ps.beartype
        ps.expression
        ps.pytest
      ]);
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D9)
        realize-pin-tests = {
          class = "small";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        realize-pin-tests =
          pkgs.runCommand "realize-pin-tests"
            {
              nativeBuildInputs = [
                python
                pkgs.basedpyright
              ];
            }
            ''
              cp -r ${src} work
              chmod -R u+w work
              cd work
              export HOME=$TMPDIR
              basedpyright --pythonpath ${python}/bin/python
              PYTHONPATH=src python -m pytest -q
              touch $out
            '';
      };
    };
}
