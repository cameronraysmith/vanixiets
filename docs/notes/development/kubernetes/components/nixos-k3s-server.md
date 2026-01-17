---
title: NixOS k3s server configuration
---

# NixOS k3s server configuration

This document describes configuring the nixpkgs `services.k3s` module and accompanying system settings for running k3s as a Kubernetes server node.
The configuration targets x86_64-linux VMs running via Rosetta on aarch64-darwin hosts using Colima's vz backend.
Production parity with Hetzner deployment is maintained through consistent module configuration.

## Overview

k3s provides a lightweight Kubernetes distribution suitable for local development and production workloads.
The NixOS module at `services.k3s` handles server initialization, agent management, and cluster coordination.
This architecture uses Cilium as the CNI, requiring k3s bundled components (flannel, traefik, servicelb) to be disabled.

The nixpkgs module lives at `/nixos/modules/services/cluster/rancher/default.nix` with k3s-specific options in `k3s.nix`.
Reference implementations exist in the sini-dendritic-k8s-nix-config and hetzkube repositories.

## Kernel requirements

Kubernetes networking requires specific kernel modules for bridge filtering, connection tracking, and overlay filesystems.
These modules enable container networking, pod-to-pod communication, and CNI operation.

```nix
boot.kernelModules = [
  "br_netfilter"    # Bridge netfilter support for iptables
  "nf_conntrack"    # Connection tracking for stateful firewalling
  "overlay"         # OverlayFS for container layers
  "ip_tables"       # IPv4 firewall rules
  "ip6_tables"      # IPv6 firewall rules
  "ip6table_mangle" # IPv6 packet mangling (Cilium)
  "ip6table_raw"    # IPv6 raw table access (Cilium)
  "ip6table_filter" # IPv6 filtering (Cilium)
];
```

The hetzkube reference shows that Cilium requires additional IPv6 modules for full functionality.
The base modules (br_netfilter, nf_conntrack, overlay) appear in the clusterctl default templating.

## Sysctl settings

Network forwarding and bridge netfilter settings enable pod networking and CNI operation.
These settings are mandatory for Kubernetes and Cilium to function correctly.

```nix
boot.kernel.sysctl = {
  # IPv4 forwarding for pod networking
  "net.ipv4.ip_forward" = 1;

  # IPv6 forwarding for dual-stack support
  "net.ipv6.conf.all.forwarding" = 1;
  "net.ipv6.conf.default.forwarding" = 1;

  # Bridge traffic passes through iptables
  "net.bridge.bridge-nf-call-iptables" = 1;
  "net.bridge.bridge-nf-call-ip6tables" = 1;

  # Cilium-specific: disable reverse path filtering on lxc interfaces
  "net.ipv4.conf.lxc*.rp_filter" = 0;

  # Kubelet stability settings
  "vm.overcommit_memory" = 1;
  "kernel.panic" = 10;
  "kernel.panic_on_oops" = 1;
};
```

The kubelet stability settings ensure the node reboots rather than hanging on kernel panics.

## Firewall configuration

Kubernetes components require specific ports for API access, inter-node communication, and CNI traffic.

### TCP ports

| Port | Service | Description |
|------|---------|-------------|
| 6443 | kube-apiserver | Kubernetes API server |
| 10250 | kubelet | Kubelet metrics and exec API |
| 2379 | etcd | etcd client requests (HA mode) |
| 2380 | etcd | etcd peer communication (HA mode) |
| 4240 | Cilium | Cilium health check |
| 4244 | Hubble | Hubble observability API |

### UDP ports

| Port | Service | Description |
|------|---------|-------------|
| 8472 | VXLAN | Cilium overlay network |
| 4789 | VXLAN | Cilium VXLAN fallback |

```nix
networking.firewall.allowedTCPPorts = [
  6443 10250 2379 2380 4240 4244
];

networking.firewall.allowedUDPPorts = [
  8472 4789
];

# Trust CNI interfaces for pod traffic
networking.firewall.trustedInterfaces = [
  "cni+"
  "cilium+"
  "lxc+"
];
```

For local development, disabling the firewall simplifies initial testing.
Production deployments should enable granular firewall rules.

## containerd integration

k3s uses containerd as its container runtime by default.
The hetzkube reference shows explicit containerd configuration for ClusterAPI compatibility.

```nix
virtualisation.containerd = {
  enable = true;
  settings = {
    # Use systemd cgroups for Kubernetes compatibility
    plugins."io.containerd.grpc.v1.cri".containerd.runtimes.runc.options.SystemdCgroup = true;

    # CNI plugins expect /opt/cni/bin
    plugins."io.containerd.grpc.v1.cri".cni.bin_dir = lib.mkForce "/opt/cni/bin";

    # Workaround for cgroups hugetlb controller issue
    plugins."io.containerd.grpc.v1.cri".disable_hugetlb_controller = true;

    # Enable systemd (NixOS) in containers
    plugins."io.containerd.cri.v1.runtime".containerd.runtimes.runc.cgroup_writable = true;
  };
};

# Copy CNI plugins to expected location
system.activationScripts.cni-install.text = ''
  ${lib.getExe pkgs.rsync} --mkpath --recursive ${pkgs.cni-plugins}/bin/ /opt/cni/bin/
'';
```

The systemd cgroup driver ensures Kubernetes and containerd agree on resource accounting.
This configuration is required when using containerd independently of k3s's bundled runtime.

## k3s server configuration

The k3s module provides declarative options for server role, clustering, and component management.

### Disabling bundled components

For Cilium CNI integration, disable k3s bundled networking components.

```nix
services.k3s = {
  enable = true;
  role = "server";

  # Disable bundled components for Cilium
  disable = [
    "flannel"        # Cilium replaces flannel
    "local-storage"  # Use external storage provisioner
    "metrics-server" # Deploy via Helm for control
    "servicelb"      # Cilium provides load balancing
    "traefik"        # Use external ingress controller
  ];

  extraFlags = [
    "--flannel-backend=none"     # Required for external CNI
    "--disable-network-policy"   # Cilium handles NetworkPolicy
    "--disable-kube-proxy"       # Cilium replaces kube-proxy
    "--disable-cloud-controller" # No cloud provider integration
  ];
};
```

### HA cluster initialization

For multi-node clusters, use embedded etcd with `clusterInit`.

```nix
# First server node
services.k3s = {
  enable = true;
  role = "server";
  clusterInit = true;  # Initialize etcd-backed HA cluster
  tokenFile = config.age.secrets.k3s-token.path;
};

# Additional server nodes
services.k3s = {
  enable = true;
  role = "server";
  serverAddr = "https://10.0.0.10:6443";  # First server address
  tokenFile = config.age.secrets.k3s-token.path;
};
```

### Graceful shutdown

Enable graceful node shutdown to allow pods to terminate cleanly.

```nix
services.k3s.gracefulNodeShutdown = {
  enable = true;
  shutdownGracePeriod = "30s";
  shutdownGracePeriodCriticalPods = "10s";
};
```

## Storage paths

k3s stores data in `/var/lib/rancher/k3s` with configuration in `/etc/rancher/k3s`.

| Path | Contents |
|------|----------|
| `/var/lib/rancher/k3s/server/` | Server state, manifests, TLS certs |
| `/var/lib/rancher/k3s/agent/` | Agent data, containerd state |
| `/var/lib/rancher/k3s/server/manifests/` | Auto-deployed manifests |
| `/var/lib/rancher/k3s/agent/images/` | Pre-loaded container images |
| `/etc/rancher/k3s/k3s.yaml` | kubeconfig (server only) |
| `/var/lib/kubelet/` | Kubelet state directory |

For persistent storage across reboots (impermanence setups), persist these directories.

```nix
environment.persistence."/persist".directories = [
  "/var/lib/rancher"
  "/var/lib/kubelet"
  "/etc/rancher"
];
```

## Local development vs production

Configuration differences between local Colima VMs and Hetzner production.

### Local development

- Single-node cluster without `clusterInit` (sqlite backend)
- Firewall disabled for simplicity
- No TLS SAN configuration needed
- VM-local storage sufficient
- Token can be auto-generated

### Production (Hetzner)

- Multi-node with `clusterInit = true` (etcd backend)
- Explicit firewall rules enabled
- TLS SANs for external access: hostname, FQDN, external IP
- Persistent storage with Longhorn or similar
- Token from secrets management (sops-nix, agenix)
- VPN overlay (zerotier) for cross-node communication

```nix
# Production-specific extraFlags
extraFlags = [
  "--tls-san=${config.networking.fqdn}"
  "--tls-san=${config.networking.hostName}"
  "--tls-san=${externalIP}"
  "--bind-address=0.0.0.0"
  "--cluster-cidr=10.42.0.0/16"
  "--service-cidr=10.43.0.0/16"
  "--etcd-expose-metrics"
];
```

## Complete example configuration

A complete NixOS module for a k3s server with Cilium CNI.

```nix
{ config, lib, pkgs, ... }:

{
  # Kernel configuration
  boot.kernelModules = [
    "br_netfilter"
    "nf_conntrack"
    "overlay"
    "ip_tables"
    "ip6_tables"
    "ip6table_mangle"
    "ip6table_raw"
    "ip6table_filter"
  ];

  boot.kernel.sysctl = {
    "net.ipv4.ip_forward" = 1;
    "net.ipv6.conf.all.forwarding" = 1;
    "net.ipv6.conf.default.forwarding" = 1;
    "net.bridge.bridge-nf-call-iptables" = 1;
    "net.bridge.bridge-nf-call-ip6tables" = 1;
    "net.ipv4.conf.lxc*.rp_filter" = 0;
    "vm.overcommit_memory" = 1;
    "kernel.panic" = 10;
    "kernel.panic_on_oops" = 1;
  };

  # Firewall (disable for local dev, enable for production)
  networking.firewall = {
    enable = false;  # Set to true for production
    allowedTCPPorts = [ 6443 10250 2379 2380 4240 4244 ];
    allowedUDPPorts = [ 8472 4789 ];
    trustedInterfaces = [ "cni+" "cilium+" "lxc+" ];
  };

  # k3s server
  services.k3s = {
    enable = true;
    role = "server";

    # For single-node local dev, leave clusterInit false
    # For HA production, set clusterInit = true on first server
    clusterInit = false;

    # Token file from secrets management
    # tokenFile = config.sops.secrets.k3s-token.path;

    # Disable bundled components for Cilium
    disable = [
      "flannel"
      "local-storage"
      "metrics-server"
      "servicelb"
      "traefik"
    ];

    extraFlags = [
      "--flannel-backend=none"
      "--disable-network-policy"
      "--disable-kube-proxy"
      "--disable-cloud-controller"
      "--write-kubeconfig-mode=644"
    ];

    gracefulNodeShutdown = {
      enable = true;
      shutdownGracePeriod = "30s";
      shutdownGracePeriodCriticalPods = "10s";
    };
  };

  # System packages for cluster management
  environment.systemPackages = with pkgs; [
    k3s
    kubectl
    k9s
    cilium-cli
    kubernetes-helm
  ];
}
```

## Related components

- Cilium CNI: Deployed after k3s initialization via Helm or manifests
- ArgoCD: GitOps deployment via nixidy-rendered manifests
- Secrets: sops-nix or agenix for cluster token management
- Storage: Longhorn or local-path-provisioner for persistent volumes

## References

- nixpkgs module: `/nixos/modules/services/cluster/rancher/default.nix`
- k3s documentation: https://docs.k3s.io/
- Cilium k3s guide: https://docs.cilium.io/en/stable/installation/k3s/
- sini-dendritic reference: `/Users/crs58/projects/nix-workspace/sini-dendritic-k8s-nix-config/modules/services/k3s/k3s.nix`
- hetzkube reference: `/Users/crs58/projects/sciops-workspace/hetzkube/nixos/kubernetes.nix`
