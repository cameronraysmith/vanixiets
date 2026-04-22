# k3d-test-coverage.nix - Run chainsaw integration tests and emit coverage report.
#
# Usage:
#   nix run .#k3d-test-coverage -- [--raw] [chainsaw args...]
#
# Template form: pure readFile (no nix-computed variable injection).
# Subsumes scripts/k3d-test-coverage.sh (legacy root-level copy kept as
# a thin shim in M5 for backward compatibility). The coverage-report
# logic lives in-tree at modules/apps/cluster/k3d-test-coverage.sh.
#
# Resolves kubernetes/tests/local-k3d/ relative to the invoking git
# worktree via `git rev-parse --show-toplevel`.
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
