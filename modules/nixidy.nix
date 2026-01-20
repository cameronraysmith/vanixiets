# nixidy flake-parts bridge
#
# Generates ArgoCD Application CRs for GitOps management.
# Phase 4 of the deployment architecture: ArgoCD adopts Phase 3 infrastructure
# and manages future applications declaratively.
#
# Usage:
#   nix build .#nixidyEnvs.local-k3d.config.build.app  # Build app-of-apps manifest
#   nix run .#nixidy -- build .#nixidyEnvs.local-k3d   # Build with nixidy CLI
#   nix run .#nixidy -- info .#nixidyEnvs.local-k3d    # Show environment info
{ inputs, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    {
      # nixidy environments - one per cluster
      nixidyEnvs.local-k3d = inputs.nixidy.lib.mkEnv {
        inherit pkgs;
        charts = inputs.nixhelm.chartsDerivations.${system};
        modules = [ ../kubernetes/nixidy/local-k3d ];
      };

      # nixidy CLI tool for build/info commands
      packages.nixidy = inputs.nixidy.packages.${system}.cli;

      # Convenience app for building manifests
      apps.nixidy-build-local-k3d = {
        type = "app";
        program =
          (pkgs.writeShellScript "nixidy-build-local-k3d" ''
            set -euo pipefail
            ${inputs.nixidy.packages.${system}.cli}/bin/nixidy build .#nixidyEnvs.local-k3d
          '').outPath;
      };
    };
}
