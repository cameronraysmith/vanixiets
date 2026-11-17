# easykubenix flake-parts bridge
#
# Evaluates Kubernetes cluster configurations using easykubenix and exposes
# manifest outputs as packages and deployment scripts.
#
# Usage:
#   nix build .#k8s-manifests-local-json     # Build JSON manifests
#   nix run .#k8s-deploy-local -- --dry-run  # Dry-run kluctl deployment
#   nix run .#k8s-deploy-local -- --yes      # Deploy with kluctl
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Evaluate easykubenix with cluster configuration
      # Optional deploymentLayer parameter for staged deployments
      easykubenix = (import inputs.easykubenix { inherit pkgs; }).lib.easykubenix;
      evalCluster =
        clusterPath:
        {
          deploymentLayer ? "all",
        }:
        easykubenix {
          modules = [
            ../kubernetes/modules
            clusterPath
          ];
          # Pass flake inputs to easykubenix modules via specialArgs
          specialArgs = {
            inherit deploymentLayer;
            cilium-src = inputs.cilium-src;
            step-ca-src = inputs.step-ca-src;
            sops-secrets-operator-src = inputs.sops-secrets-operator-src;
            argocd-src = inputs.argocd-src;
            argocd-helm-src = inputs.argocd-helm-src;
            gateway-api-src = inputs.gateway-api-src;
          };
        };

      # Local development cluster
      localCluster = evalCluster ../kubernetes/clusters/local { };

      # Local k3d cluster - staged deployment support
      # Foundation: CNI (Cilium) - must be ready before infrastructure
      # Infrastructure: Platform services (ArgoCD, cert-manager, secrets)
      localK3dCluster = evalCluster ../kubernetes/clusters/local-k3d { };
      localK3dFoundation = evalCluster ../kubernetes/clusters/local-k3d {
        deploymentLayer = "foundation";
      };
      localK3dInfrastructure = evalCluster ../kubernetes/clusters/local-k3d {
        deploymentLayer = "infrastructure";
      };
    in
    {
      # JSON manifest files only. easykubenix renders YAML through its `ekn`
      # CLI unless Nix has a `builtins.toYAML` primop, and that CLI's closure
      # (a patched Nix among it) costs more than the YAML is worth: nothing
      # here consumes it, and the deploy apps read the module output directly.
      packages = {
        k8s-manifests-local-json = localCluster.manifestJSONFile;
        k8s-manifests-local-k3d-json = localK3dCluster.manifestJSONFile;
      };

      # Deployment scripts (kluctl-based)
      apps.k8s-deploy-local = {
        type = "app";
        program = "${localCluster.deploymentScript}/bin/kubenixDeploy";
      };

      apps.k8s-deploy-local-k3d = {
        type = "app";
        program = "${localK3dCluster.deploymentScript}/bin/kubenixDeploy";
      };

      # Staged deployment for local k3d cluster
      # Usage: deploy foundation first, wait for CNI, then deploy infrastructure
      apps.k8s-deploy-local-k3d-foundation = {
        type = "app";
        program = "${localK3dFoundation.deploymentScript}/bin/kubenixDeploy";
      };

      apps.k8s-deploy-local-k3d-infrastructure = {
        type = "app";
        program = "${localK3dInfrastructure.deploymentScript}/bin/kubenixDeploy";
      };
    };
}
