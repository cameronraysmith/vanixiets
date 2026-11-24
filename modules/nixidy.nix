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
# Environments: local-k3d targets the private manifest repo (ADR-006);
# local-k3d-ci targets the file:///manifests mount used by integration tests.
#
# Direct nix build (alternative):
#   nix build .#nixidyEnvs.aarch64-darwin.local-k3d.environmentPackage  # Full environment
#   nix build .#nixidyEnvs.aarch64-darwin.local-k3d.bootstrapPackage    # Bootstrap Application CR
{
  config,
  inputs,
  lib,
  ...
}:
{
  # Expose nixidyEnvs as a top-level flake output (per-system)
  flake.nixidyEnvs = lib.genAttrs [ "aarch64-darwin" "x86_64-linux" "aarch64-linux" ] (
    system:
    let
      pkgs = import inputs.nixpkgs { inherit system; };
      extraSpecialArgs = {
        inherit (inputs)
          cilium-src
          step-ca-src
          sops-secrets-operator-src
          argocd-src
          argocd-helm-src
          gateway-api-src
          ;
      };
      mkLocalK3d =
        extraModules:
        inputs.nixidy.lib.mkEnv {
          inherit pkgs extraSpecialArgs;
          charts = inputs.nixhelm.chartsDerivations.${system};
          modules = [ ../kubernetes/nixidy/local-k3d ] ++ extraModules;
        };
    in
    {
      local-k3d = mkLocalK3d [ ];

      # Integration-test variant: ArgoCD reads the manifests mounted into the
      # cluster at /manifests instead of the private remote, so the test needs
      # no GitHub credential. Selected explicitly by attribute name rather than
      # by an environment variable, because nixidy evaluates the environment
      # purely and builtins.getEnv would silently yield "".
      local-k3d-ci = mkLocalK3d [ { nixidy.target.repository = "file:///manifests"; } ];
    }
  );

  perSystem =
    {
      pkgs,
      system,
      self',
      ...
    }:
    {
      # nixidy CLI tool for build/info commands. It runs `nix` from PATH to
      # render the manifests the cluster applies, so it gets the fleet's Nix.
      packages.nixidy = config.flake.lib.withFleetNix pkgs "nixidy" inputs.nixidy.packages.${system}.cli;

      # Convenience app for building manifests
      apps.nixidy-build-local-k3d = {
        type = "app";
        program =
          (pkgs.writeShellScript "nixidy-build-local-k3d" ''
            set -euo pipefail
            ${self'.packages.nixidy}/bin/nixidy build .#nixidyEnvs.${system}.local-k3d
          '').outPath;
      };
    };
}
