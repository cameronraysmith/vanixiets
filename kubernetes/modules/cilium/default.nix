# Cilium CNI module for easykubenix
#
# Minimal configuration for local k3s development clusters.
# Based on hetzkube reference but simplified for single-node local dev.
#
# Receives cilium-src from flake inputs via specialArgs to avoid
# impure fetchTree calls during pure evaluation.
{
  config,
  lib,
  pkgs,
  cilium-src,
  ...
}:
let
  moduleName = "cilium";
  cfg = config.${moduleName};
in
{
  options.${moduleName} = {
    enable = lib.mkEnableOption moduleName;

    version = lib.mkOption {
      type = lib.types.str;
      default = "1.16.5";
      description = "Cilium version to deploy (must match cilium-src flake input)";
    };

    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
      description = "Additional Helm values to merge";
    };
  };

  config =
    let
      # Use flake input instead of dynamic fetchTree for pure evaluation
      src = cilium-src;
      crdDir = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2";

      # Create derivation for each CRD file (required for importyaml)
      # importyaml expects either a derivation or URL, not a store path string
      mkCrdDrv = filename: pkgs.runCommand "cilium-crd-${filename}" { } ''
        cp ${crdDir}/${filename} $out
      '';
    in
    lib.mkMerge [
      (lib.mkIf cfg.enable {
        helm.releases.${moduleName} = {
          namespace = "kube-system";
          chart = "${src}/install/kubernetes/cilium";

          values = lib.recursiveUpdate {
            # Core settings for local dev
            cluster.name = config.clusterName;

            # kube-proxy replacement with eBPF
            kubeProxyReplacement = true;

            # Use tunnel mode for simplicity (works with any network)
            routingMode = "tunnel";
            tunnelProtocol = "geneve";

            # IPAM via kubernetes (simple, works with k3s)
            ipam.mode = "kubernetes";

            # API server access (local/loopback for single-node)
            k8sServiceHost = config.clusterHost;
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
          } cfg.helmValues;
        };

        # Import Cilium CRDs from source
        importyaml = lib.pipe (builtins.readDir crdDir) [
          (lib.mapAttrs' (
            filename: _type: {
              name = filename;
              value.src = mkCrdDrv filename;
            }
          ))
        ];
      })

      # API mappings always defined (allows other modules to reference Cilium types)
      {
        kubernetes.apiMappings = {
          CiliumCIDRGroup = "cilium.io/v2";
          CiliumClusterwideNetworkPolicy = "cilium.io/v2";
          CiliumEndpoint = "cilium.io/v2";
          CiliumIdentity = "cilium.io/v2";
          CiliumL2AnnouncementPolicy = "cilium.io/v2alpha1";
          CiliumLoadBalancerIPPool = "cilium.io/v2";
          CiliumNetworkPolicy = "cilium.io/v2";
          CiliumNode = "cilium.io/v2";
          CiliumNodeConfig = "cilium.io/v2";
          CiliumPodIPPool = "cilium.io/v2alpha1";
        };
        kubernetes.namespacedMappings = {
          CiliumCIDRGroup = false;
          CiliumClusterwideNetworkPolicy = false;
          CiliumEndpoint = true;
          CiliumIdentity = false;
          CiliumL2AnnouncementPolicy = false;
          CiliumLoadBalancerIPPool = false;
          CiliumNetworkPolicy = true;
          CiliumNode = false;
          CiliumNodeConfig = true;
          CiliumPodIPPool = false;
        };
      }
    ];
}
