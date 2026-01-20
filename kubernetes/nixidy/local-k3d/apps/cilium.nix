# Cilium CNI adoption Application for Phase 4 bootstrap
#
# Adopts existing Cilium deployment from Phase 3b (kluctl/easykubenix).
# ArgoCD takes ownership via ServerSideApply without recreating resources.
#
# The Helm values MUST match what easykubenix deployed exactly to avoid
# drift detection during adoption. Use the flake input for chart source
# to ensure version alignment with kluctl deployment.
{
  lib,
  config,
  charts,
  cilium-src,
  ...
}:
let
  # Match easykubenix clusterName/clusterHost (from kubernetes/clusters/local-k3d.nix)
  clusterName = "local-k3d";
  clusterHost = "host.k3d.internal";
in
{
  applications.cilium = {
    namespace = "kube-system";

    # Adoption-safe sync options
    syncPolicy = {
      autoSync = {
        enable = true;
        prune = true;
        selfHeal = true;
      };
      syncOptions = {
        serverSideApply = true;
        applyOutOfSyncOnly = true;
        # Namespace exists from kluctl deployment
        createNamespace = false;
      };
    };

    # Sync wave: CNI is early infrastructure (-1)
    # CRDs would be -2, but Cilium CRDs are bundled in helm chart
    annotations."argocd.argoproj.io/sync-wave" = "-1";

    # Use flake input for chart source (same as easykubenix)
    # This ensures exact version match with kluctl deployment
    helm.releases.cilium = {
      chart = "${cilium-src}/install/kubernetes/cilium";

      # Values MUST match easykubenix kubernetes/modules/cilium/default.nix exactly
      values = {
        # Core settings for local dev
        cluster.name = clusterName;

        # kube-proxy replacement with eBPF
        kubeProxyReplacement = true;

        # Use tunnel mode for simplicity (works with any network)
        routingMode = "tunnel";
        tunnelProtocol = "geneve";

        # IPAM via kubernetes (simple, works with k3s)
        ipam.mode = "kubernetes";

        # API server access (local/loopback for single-node)
        k8sServiceHost = clusterHost;
        k8sServicePort = 6443;

        # Single replica for local dev
        operator.replicas = 1;

        # Disable optional features for minimal footprint
        hubble.relay.enabled = false;
        hubble.ui.enabled = false;

        # BPF masquerade for outbound NAT
        bpf.masquerade = true;

        # Roll out pods on config changes
        rollOutCiliumPods = true;
        operator.rollOutPods = true;

        # IPv4 only for local dev (simpler)
        ipv6.enabled = false;
      };
    };

    # Ignore controller-managed fields that may differ
    ignoreDifferences = {
      # Cilium agent daemonset has controller-managed fields
      DaemonSet-cilium = {
        group = "apps";
        kind = "DaemonSet";
        name = "cilium";
        namespace = "kube-system";
        # Controller may update status and observed generation
        jsonPointers = [
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
      # Cilium operator deployment
      Deployment-cilium-operator = {
        group = "apps";
        kind = "Deployment";
        name = "cilium-operator";
        namespace = "kube-system";
        jsonPointers = [
          "/spec/replicas"
          "/spec/template/metadata/annotations/kubectl.kubernetes.io~1restartedAt"
        ];
      };
    };
  };
}
