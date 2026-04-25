# k3d-test-coverage.nix - Run chainsaw integration tests and emit coverage report.
#
# Subsumes scripts/k3d-test-coverage.sh (legacy root-level copy kept as
# a thin shim for backward compatibility). The coverage-report logic
# lives in-tree at modules/apps/cluster/k3d-test-coverage.sh.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-test-coverage = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-test-coverage";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.findutils
              pkgs.gawk
              pkgs.git
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.kubectl
              pkgs.kyverno-chainsaw
              pkgs.libxml2 # xmllint
            ];
            text = builtins.readFile ./k3d-test-coverage.sh;
          }
        );
      };
    };
}
