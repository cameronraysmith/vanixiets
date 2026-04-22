# k3d-integration-ci.nix - CI-variant full integration: file:///manifests + tests.
#
# Usage:
#   nix run .#k3d-integration-ci
#
# Template form: pure readFile (no nix-computed variable injection).
# Orchestrates the seven-phase CI integration flow that is currently
# invoked by `.github/workflows/test-cluster.yaml`. Delegates to the
# sibling cluster/docs flake apps (nixidy-build, nixidy-bootstrap,
# k3d-wait-*, k3d-test-coverage) via `just <recipe>`; those recipes are
# thin `nix run` wrappers after M1. `just` is the single external
# dispatch mechanism, so it is the only orchestration-layer runtimeInput;
# the underlying tools (ctlptl, k3d, kubectl, …) come from the invoking
# dev shell's PATH (writeShellApplication prepends runtimeInputs to $PATH).
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.k3d-integration-ci = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "k3d-integration-ci";
            runtimeInputs = [
              pkgs.bash
              pkgs.coreutils
              pkgs.git
              pkgs.just
              pkgs.rsync
            ];
            text = builtins.readFile ./k3d-integration-ci.sh;
          }
        );
      };
    };
}
