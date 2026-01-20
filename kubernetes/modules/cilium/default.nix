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
      default = "1.18.6";
      description = "Cilium version to deploy (must match cilium-src flake input)";
    };

    helmValues = lib.mkOption {
      type = lib.types.anything;
      default = { };
      description = "Additional Helm values to merge";
    };

    containerized = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = ''
        Enable accommodations for containerized environments (k3d, kind, etc.)
        where /proc/sys is read-only and direct sysctl writes fail.

        When enabled:
        - sysctlfix init container is disabled (would fail writing to /etc/sysctl.d)
        - BPF and cgroup automount remain enabled (K3D_FIX_MOUNTS handles mount sharing)

        Note: K3D_FIX_MOUNTS=1 must be set in the k3d cluster configuration
        to enable shared mounts for BPF filesystem operations.
      '';
    };
  };

  config =
    let
      # Use flake input instead of dynamic fetchTree for pure evaluation
      src = cilium-src;
      crdDirV2 = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2";
      crdDirV2alpha1 = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2alpha1";

      # Create derivation for each CRD file (required for importyaml)
      # importyaml expects either a derivation or URL, not a store path string
      mkCrdDrv =
        crdDir: filename:
        pkgs.runCommand "cilium-crd-${filename}" { } ''
          cp ${crdDir}/${filename} $out
        '';

      # Import CRDs from a directory as importyaml attrset
      importCrdsFromDir =
        crdDir:
        lib.pipe (builtins.readDir crdDir) [
          (lib.mapAttrs' (
            filename: _type: {
              name = filename;
              value.src = mkCrdDrv crdDir filename;
            }
          ))
        ];
    in
    lib.mkMerge [
      (lib.mkIf cfg.enable {
        helm.releases.${moduleName} = {
          namespace = "kube-system";
          chart = "${src}/install/kubernetes/cilium";

          # Add kluctl wait-readiness annotation to DaemonSets
          # This ensures prio-20 barrier waits for Cilium pods to be Ready,
          # not just applied. Without this, dependent pods fail with
          # "network plugin is not ready" because CNI isn't running yet.
          overrides = [
            {
              metadata.annotations."kluctl.io/wait-readiness" = "true";
            }
          ];

          values = lib.recursiveUpdate (
            {
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
            }
            // lib.optionalAttrs cfg.containerized {
              # Containerized environment accommodations (k3d, kind, etc.)
              # Disable sysctlfix init container - it fails in containers because
              # /proc/sys/net is read-only and systemd-sysctl.service doesn't exist.
              # The sysctl settings it would configure (rp_filter=0 for Cilium interfaces)
              # are not strictly required for basic functionality in dev environments.
              sysctlfix.enabled = false;
            }
          ) cfg.helmValues;
        };

        # Import Cilium CRDs from source (v2 + v2alpha1)
        # v2alpha1 contains L2 announcement policies and pod IP pools
        importyaml = importCrdsFromDir crdDirV2 // importCrdsFromDir crdDirV2alpha1;
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
