# nixidy flake-parts bridge
#
# Generates ArgoCD Application CRs for GitOps management.
# Phase 4 of the deployment architecture: ArgoCD adopts Phase 3 infrastructure
# and manages future applications declaratively.
#
# Usage:
#   nix run .#nixidy -- build .#local-k3d        # Build environment manifests
#   nix run .#nixidy -- info .#local-k3d         # Show environment info
#   nix run .#nixidy -- bootstrap .#local-k3d    # Output bootstrap Application CR
#   nix run .#nixidy-build-local-k3d             # Convenience wrapper for build
#
# Direct nix build (alternative):
#   nix build .#nixidyEnvs.aarch64-darwin.local-k3d.environmentPackage  # Full environment
#   nix build .#nixidyEnvs.aarch64-darwin.local-k3d.bootstrapPackage    # Bootstrap Application CR
{ inputs, lib, ... }:
{
  # Expose nixidyEnvs as a top-level flake output (per-system)
  flake.nixidyEnvs = lib.genAttrs [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (
    system:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
    in
    {
      local-k3d = inputs.nixidy.lib.mkEnv {
        inherit pkgs;
        charts = inputs.nixhelm.chartsDerivations.${system};
        modules = [ ../kubernetes/nixidy/local-k3d ];
        # Pass flake inputs for charts not available in nixhelm
        extraSpecialArgs = {
          inherit (inputs)
            cilium-src
            step-ca-src
            sops-secrets-operator-src
            argocd-src
            argocd-helm-src
            ;
        };
      };
    }
  );

  perSystem =
    { pkgs, system, ... }:
    {
      # nixidy CLI tool for build/info commands
      packages.nixidy = inputs.nixidy.packages.${system}.cli;

      # Convenience app for building manifests
      apps.nixidy-build-local-k3d = {
        type = "app";
        program =
          (pkgs.writeShellScript "nixidy-build-local-k3d" ''
            set -euo pipefail
            ${inputs.nixidy.packages.${system}.cli}/bin/nixidy build .#nixidyEnvs.${system}.local-k3d
          '').outPath;
      };
    };
}
