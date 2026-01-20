# easykubenix flake-parts bridge
#
# Evaluates Kubernetes cluster configurations using easykubenix and exposes
# manifest outputs as packages and deployment scripts.
#
# Usage:
#   nix build .#k8s-manifests-local          # Build YAML manifests
#   nix run .#k8s-deploy-local -- --dry-run  # Dry-run kluctl deployment
#   nix run .#k8s-deploy-local -- --yes      # Deploy with kluctl
{ inputs, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      # Evaluate easykubenix with cluster configuration
      evalCluster =
        clusterPath:
        import inputs.easykubenix {
          inherit pkgs;
          modules = [
            ../kubernetes/modules
            clusterPath
          ];
          # Pass flake inputs to easykubenix modules via specialArgs
          specialArgs = {
            cilium-src = inputs.cilium-src;
            step-ca-src = inputs.step-ca-src;
            sops-secrets-operator-src = inputs.sops-secrets-operator-src;
            argocd-src = inputs.argocd-src;
            argocd-helm-src = inputs.argocd-helm-src;
          };
        };

      # Local development cluster
      localCluster = evalCluster ../kubernetes/clusters/local;

      # Local k3d cluster
      localK3dCluster = evalCluster ../kubernetes/clusters/local-k3d;
    in
    {
      packages = {
        # YAML manifest file for local cluster
        k8s-manifests-local = localCluster.manifestYAMLFile;

        # JSON manifest file (alternative format)
        k8s-manifests-local-json = localCluster.manifestJSONFile;

        # YAML manifest file for local k3d cluster
        k8s-manifests-local-k3d = localK3dCluster.manifestYAMLFile;

        # JSON manifest file for local k3d cluster
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
    };
}
