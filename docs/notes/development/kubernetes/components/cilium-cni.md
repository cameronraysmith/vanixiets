---
title: Cilium CNI
---

# Cilium CNI

Cilium provides eBPF-based container networking, replacing both the default flannel CNI and kube-proxy in our k3s clusters.
This document covers deployment via easykubenix/kubenix Helm integration with configuration suitable for both local development (Colima) and production (Hetzner via ClusterAPI).

## Why Cilium over flannel

Flannel provides basic overlay networking but lacks advanced features we require for production parity.
Cilium offers eBPF-based packet processing that scales better than iptables, native kube-proxy replacement eliminating the iptables service routing bottleneck, and built-in network policy enforcement without separate components.

Production parity matters because networking issues that only manifest in production are difficult to debug.
Running identical CNI configuration locally catches configuration errors, network policy violations, and routing issues before deployment.
The GENEVE tunnel mode works identically on a single-node Colima cluster and multi-node Hetzner infrastructure.

## Deployment method

Cilium deploys via Helm chart through the easykubenix/kubenix Helm release mechanism.
The hetzkube pattern fetches the chart directly from the Cilium GitHub repository, pinning to a specific version tag.

```nix
# Version pinning via builtins.fetchTree
let
  ciliumVersion = "1.18.4";
  src = builtins.fetchTree {
    type = "github";
    owner = "cilium";
    repo = "cilium";
    ref = "v${ciliumVersion}";
  };
in {
  helm.releases.cilium = {
    namespace = "kube-system";
    chart = "${src}/install/kubernetes/cilium";
    values = { /* configuration */ };
  };
}
```

The nixidy pattern uses a charts input for cleaner separation.

```nix
{ charts, ... }:
{
  applications.cilium = {
    namespace = "kube-system";
    helm.releases.cilium = {
      chart = charts.cilium.cilium;
      values = { /* configuration */ };
    };
  };
}
```

Both approaches support version pinning; choose based on your flake structure.

## Core configuration

The essential Helm values establish Cilium as the primary networking layer with kube-proxy replacement.

```nix
{
  # Kube-proxy replacement - Cilium handles all service routing
  kubeProxyReplacement = true;

  # Tunnel mode for maximum compatibility
  routingMode = "tunnel";
  tunnelProtocol = "geneve";

  # IPAM delegated to Kubernetes
  ipam.mode = "kubernetes";

  # eBPF masquerading for NAT
  bpf.masquerade = true;

  # API server connectivity (required since Cilium uses hostNetwork)
  k8sServiceHost = "10.43.0.1";  # or cluster-specific IP
  k8sServicePort = 6443;
}
```

### kube-proxy replacement

Setting `kubeProxyReplacement = true` tells Cilium to handle all ClusterIP, NodePort, and LoadBalancer service routing.
This eliminates the kube-proxy daemonset entirely, replacing iptables rules with eBPF programs that perform better under load.
The k3s cluster must be started with `--disable-kube-proxy` or the services will conflict.

### Tunnel mode selection

GENEVE tunneling (`tunnelProtocol = "geneve"`) encapsulates pod traffic between nodes, requiring only basic IP connectivity between hosts.
This mode works through NAT, firewalls, and cloud provider networks without special configuration.
VXLAN is an alternative but GENEVE offers better extensibility and is the modern standard.

Direct routing modes (`routingMode = "native"`) require BGP peering or custom route distribution, which adds complexity without benefit for our use cases.

### IPAM modes

The `kubernetes` IPAM mode lets Kubernetes manage pod CIDR allocation, integrating with the cluster's existing pod network configuration.
For more control, `cluster-pool` mode lets Cilium manage allocation from a specified CIDR.

```nix
# Alternative: Cilium-managed IPAM
ipam = {
  mode = "cluster-pool";
  operator.clusterPoolIPv4PodCIDRList = [ "10.244.0.0/16" ];
};
```

Use `kubernetes` mode unless you need specific CIDR control or multi-cluster configurations.

## k3s integration

k3s bundles flannel and network policy controller by default; these must be disabled for Cilium.

### Required k3s flags

```bash
# Server node flags
k3s server \
  --flannel-backend=none \
  --disable-network-policy \
  --disable-kube-proxy
```

In NixOS k3s module configuration:

```nix
services.k3s = {
  enable = true;
  role = "server";
  extraFlags = [
    "--flannel-backend=none"
    "--disable-network-policy"
    "--disable-kube-proxy"
  ];
};
```

### CNI plugin binaries

The Cilium agent requires CNI plugin binaries on each node.
For NixOS, the containerd configuration must include the Cilium CNI plugin in the binary path.

```nix
# From sini-dendritic-k8s-nix-config pattern
let
  k3s-cni-plugins = pkgs.buildEnv {
    name = "k3s-cni-plugins";
    paths = with pkgs; [
      cni-plugins
      cni-plugin-flannel  # may still be needed for portmap
      pkgs.local.cni-plugin-cilium
    ];
  };
in {
  plugins."io.containerd.grpc.v1.cri".cni = {
    bin_dir = "${k3s-cni-plugins}/bin/";
    conf_dir = "/etc/cni/net.d";
  };
}
```

### Service host configuration

Cilium agents run with `hostNetwork: true` and need to reach the Kubernetes API before pod networking is established.
The `k8sServiceHost` must point to an IP reachable from the host network.

For single-node clusters, use the node IP or localhost.
For multi-node clusters, use the control plane endpoint IP or a stable load-balanced address.

```nix
# Single node (Colima local)
k8sServiceHost = "127.0.0.1";
k8sServicePort = 6443;

# Multi-node (production)
k8sServiceHost = config.clusterHost;  # e.g., "10.0.0.1" or VIP
k8sServicePort = 6443;
```

## Kernel requirements

Cilium's eBPF features require Linux kernel 4.19 or later, with 5.10+ recommended for full feature support.
NixOS and most modern distributions meet this requirement.

### Required kernel features

The kernel must have eBPF JIT enabled and the following features compiled in or as modules:

- `CONFIG_BPF=y`
- `CONFIG_BPF_SYSCALL=y`
- `CONFIG_BPF_JIT=y`
- `CONFIG_HAVE_EBPF_JIT=y`

### Kernel modules

Cilium loads these modules automatically when available:

- `ip_tables` (for legacy compatibility)
- `xt_socket` (socket lookup)
- `ip_set` (IP set handling)
- `geneve` (tunnel encapsulation)

On NixOS, ensure these are available via `boot.kernelModules` if not built-in.

### Colima/macOS considerations

Colima runs a Linux VM (Lima) on macOS, which has a modern kernel with full eBPF support.
No special kernel configuration is needed for Colima-based local development.

## Network policies

Cilium supports both Kubernetes NetworkPolicy resources and its own CiliumNetworkPolicy/CiliumClusterwideNetworkPolicy CRDs.
The CRDs offer additional features including L7 policy, DNS-aware rules, and identity-based selection.

### Kubernetes NetworkPolicy

Standard Kubernetes NetworkPolicy resources work with Cilium as the enforcement backend.
These are portable across CNI implementations but limited to L3/L4 rules.

```yaml
apiVersion: networking.k8s.io/v1
kind: NetworkPolicy
metadata:
  name: allow-frontend-to-backend
spec:
  podSelector:
    matchLabels:
      app: backend
  ingress:
  - from:
    - podSelector:
        matchLabels:
          app: frontend
    ports:
    - port: 8080
```

### CiliumNetworkPolicy

Cilium's native policy CRD enables advanced features like entity selectors (`cluster`, `world`, `host`) and L7 rules.

```nix
# From hetzkube: cluster-wide default policies
kubernetes.resources.none.CiliumClusterwideNetworkPolicy = {
  ep-default = {
    spec = {
      endpointSelector = { };  # matches all endpoints
      ingress = [
        { fromEntities = [ "cluster" "ingress" ]; }
      ];
      egress = [
        { toEntities = [ "all" ]; }
      ];
    };
  };
};
```

### Policy enforcement modes

Cilium supports three enforcement modes controlled by `policyEnforcementMode`:

- `default`: enforce policies only when policies exist for an endpoint
- `always`: deny-by-default, require explicit allow policies
- `never`: disable enforcement entirely

The hetzkube pattern uses `default` mode with catch-all cluster-wide policies rather than `always` mode, avoiding bootstrap issues where Cilium cannot start due to missing policies.

### Policy audit mode

For debugging, enable audit mode to log policy decisions without enforcement.

```nix
# Requires manual pod restart to take effect
policyAuditMode = true;
```

## Observability with Hubble

Hubble provides deep visibility into network flows, policy decisions, and service dependencies.
It consists of a server component on each node, a relay aggregating data, and an optional UI.

### Basic Hubble configuration

```nix
hubble = {
  enabled = true;
  relay.enabled = true;
  ui.enabled = true;
};
```

### Network policies for Hubble

Hubble components need network policies allowing their communication patterns.

```nix
# Allow hubble-relay to reach hubble-server on nodes
ciliumNetworkPolicies.allow-hubble-relay-server-egress.spec = {
  endpointSelector.matchLabels."app.kubernetes.io/name" = "hubble-relay";
  egress = [{
    toEntities = [ "remote-node" "host" ];
    toPorts = [{
      ports = [{ port = "4244"; protocol = "TCP"; }];
    }];
  }];
};
```

### Hubble CLI usage

The `hubble` CLI connects to the relay service for flow observation.

```bash
# Port-forward to hubble-relay
kubectl port-forward -n kube-system svc/hubble-relay 4245:80

# Observe flows
hubble observe --server localhost:4245

# Filter by namespace
hubble observe --namespace default

# Filter by verdict (dropped packets)
hubble observe --verdict DROPPED
```

### Local development considerations

Hubble adds resource overhead that may be unnecessary for local development.
Consider disabling the UI and running with minimal relay configuration locally.

```nix
# Minimal Hubble for local
hubble = {
  enabled = true;
  relay.enabled = false;  # use hubble CLI directly to agents
  ui.enabled = false;
};
```

## Gateway API

Gateway API is the successor to Ingress, providing more expressive routing and better separation of concerns.
Cilium implements Gateway API natively, replacing the need for separate ingress controllers.

### Enabling Gateway API

```nix
gatewayAPI.enabled = true;

# Version mapping from hetzkube
gateway-api.version = {
  "1.16" = "1.1.0";
  "1.17" = "1.2.0";
  "1.18" = "1.2.0";
  "1.19" = "1.3.0";
}.${lib.versions.majorMinor ciliumVersion};
```

### Gateway and HTTPRoute resources

```yaml
apiVersion: gateway.networking.k8s.io/v1
kind: Gateway
metadata:
  name: main-gateway
spec:
  gatewayClassName: cilium
  listeners:
  - name: http
    port: 80
    protocol: HTTP
---
apiVersion: gateway.networking.k8s.io/v1
kind: HTTPRoute
metadata:
  name: app-route
spec:
  parentRefs:
  - name: main-gateway
  hostnames:
  - "app.example.com"
  rules:
  - matches:
    - path:
        type: PathPrefix
        value: /
    backendRefs:
    - name: app-service
      port: 8080
```

### Ingress controller mode

Cilium can also act as a traditional Ingress controller for compatibility with existing Ingress resources.

```nix
ingressController = {
  enabled = true;
  default = true;
  loadbalancerMode = "shared";  # single LB service
};
```

## Local vs production differences

Most configuration remains identical between environments.
The following parameters typically differ:

| Parameter | Local (Colima) | Production (Hetzner) |
|-----------|---------------|---------------------|
| `k8sServiceHost` | `127.0.0.1` | Control plane VIP |
| `operator.replicas` | `1` | `2` |
| `hubble.ui.enabled` | `false` | `true` |
| `hubble.relay.enabled` | `false` | `true` |
| IPv6 | disabled | enabled |
| BGP | disabled | enabled |

### Production-specific features

The following features are production-only and should be disabled locally:

- BGP control plane (`bgpControlPlane.enabled`)
- Host firewall (`hostFirewall.enabled`)
- L2 announcements and load balancer IP pools
- Multi-replica operator deployment

### Local simplifications

```nix
# Local development values
{
  k8sServiceHost = "127.0.0.1";
  k8sServicePort = 6443;

  kubeProxyReplacement = true;
  routingMode = "tunnel";
  tunnelProtocol = "geneve";
  ipam.mode = "kubernetes";
  bpf.masquerade = true;

  operator.replicas = 1;
  hubble.enabled = true;
  hubble.relay.enabled = false;
  hubble.ui.enabled = false;

  gatewayAPI.enabled = true;
}
```

## Troubleshooting

### Cilium status commands

The `cilium` CLI provides cluster health and connectivity information.

```bash
# Overall status
kubectl exec -n kube-system ds/cilium -- cilium status

# Endpoint list (pods managed by Cilium)
kubectl exec -n kube-system ds/cilium -- cilium endpoint list

# BPF map status
kubectl exec -n kube-system ds/cilium -- cilium bpf lb list

# Service routing table
kubectl exec -n kube-system ds/cilium -- cilium service list

# Connectivity test (deploys test pods)
cilium connectivity test
```

### Common issues

*Pods stuck in ContainerCreating with CNI errors*

Verify Cilium pods are running and CNI configuration is present.

```bash
kubectl get pods -n kube-system -l k8s-app=cilium
ls /etc/cni/net.d/
```

*Services not reachable*

Check kube-proxy replacement is active and service table is populated.

```bash
kubectl exec -n kube-system ds/cilium -- cilium status | grep KubeProxyReplacement
kubectl exec -n kube-system ds/cilium -- cilium service list
```

*Pod-to-pod connectivity fails*

Verify tunnel connectivity between nodes.

```bash
kubectl exec -n kube-system ds/cilium -- cilium-health status
```

*Network policies blocking traffic unexpectedly*

Enable policy audit mode or check Hubble for dropped flows.

```bash
hubble observe --verdict DROPPED
```

### Log inspection

```bash
# Cilium agent logs
kubectl logs -n kube-system -l k8s-app=cilium --tail=100

# Cilium operator logs
kubectl logs -n kube-system -l name=cilium-operator --tail=100
```

## Example configuration

Complete easykubenix/kubenix module for local development and production.

```nix
{
  config,
  lib,
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
      default = "1.18.4";
    };
    isLocal = lib.mkOption {
      type = lib.types.bool;
      default = false;
      description = "Whether this is a local development cluster";
    };
  };

  config = lib.mkIf cfg.enable (
    let
      src = builtins.fetchTree {
        type = "github";
        owner = "cilium";
        repo = "cilium";
        ref = "v${cfg.version}";
      };
    in
    {
      gateway-api.enable = true;
      gateway-api.version = {
        "1.16" = "1.1.0";
        "1.17" = "1.2.0";
        "1.18" = "1.2.0";
        "1.19" = "1.3.0";
      }.${lib.versions.majorMinor cfg.version};

      helm.releases.${moduleName} = {
        namespace = "kube-system";
        chart = "${src}/install/kubernetes/cilium";

        values = {
          # Core networking
          kubeProxyReplacement = true;
          routingMode = "tunnel";
          tunnelProtocol = "geneve";
          ipam.mode = "kubernetes";
          bpf.masquerade = true;

          # API server connectivity
          k8sServiceHost =
            if cfg.isLocal
            then "127.0.0.1"
            else config.clusterHost;
          k8sServicePort = 6443;

          # Gateway API
          gatewayAPI.enabled = true;

          # Hubble observability
          hubble.enabled = true;
          hubble.relay.enabled = !cfg.isLocal;
          hubble.ui.enabled = !cfg.isLocal;

          # Operator scaling
          operator.replicas = if cfg.isLocal then 1 else 2;

          # Pod rollout on config change
          rollOutCiliumPods = true;
        };
      };

      # Import Cilium CRDs
      importyaml = lib.pipe (builtins.readDir "${src}/pkg/k8s/apis/cilium.io/client/crds/v2") [
        (lib.mapAttrs' (
          filename: type: {
            name = filename;
            value.src = "${src}/pkg/k8s/apis/cilium.io/client/crds/v2/${filename}";
          }
        ))
      ];

      # API mappings for Cilium CRDs
      kubernetes.apiMappings = {
        CiliumNetworkPolicy = "cilium.io/v2";
        CiliumClusterwideNetworkPolicy = "cilium.io/v2";
        CiliumEndpoint = "cilium.io/v2";
        CiliumIdentity = "cilium.io/v2";
        CiliumNode = "cilium.io/v2";
        CiliumLoadBalancerIPPool = "cilium.io/v2";
      };

      kubernetes.namespacedMappings = {
        CiliumNetworkPolicy = true;
        CiliumClusterwideNetworkPolicy = false;
        CiliumEndpoint = true;
        CiliumIdentity = false;
        CiliumNode = false;
        CiliumLoadBalancerIPPool = false;
      };
    }
  );
}
```

## Related documentation

- Upstream Cilium documentation: https://docs.cilium.io/
- Gateway API specification: https://gateway-api.sigs.k8s.io/
- easykubenix Helm integration: see local `~/projects/sciops-workspace/easykubenix` repository
- hetzkube Cilium module: `/Users/crs58/projects/sciops-workspace/hetzkube/kubenix/modules/cilium.nix`
