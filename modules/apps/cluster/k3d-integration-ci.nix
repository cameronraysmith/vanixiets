# k3d-integration-ci.nix - CI-variant full integration: file:///manifests + tests.
#
# Usage:
#   nix run .#k3d-integration-ci
#
# Template bifurcation (writeShellApplication): PURE READFILE FORM.
# `text = builtins.readFile ./k3d-integration-ci.sh` — the sidecar is
# consumed verbatim, no nix-eval-time string interpolation. This is the
# cluster-domain representative of the pure form and the canonical
# starting point when converting a cluster script.
#
# Choose PURE form when the sidecar needs no nix-eval-time path injection
# (all inputs come from env vars, CLI args, or runtimeInputs). Choose
# INTERPOLATION form (a nix-string text attribute that concatenates an
# eval-time preamble with builtins.readFile of the sidecar) only when
# you must inject a nix-computed store path or derivation outPath into
# the script preamble — for the canonical example see
# `modules/apps/docs/deploy.nix`, which injects DOCS_PAYLOAD
# (config.packages.vanixiets-docs) at eval time. Secret env vars are
# never injected via the nix preamble (per ADR-002 env-var contract);
# the caller provides them through sops exec-env, direnv dotenv, GHA
# env:, or the M4 effect preamble that extracts from
# HERCULES_CI_SECRETS_JSON.
#
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
