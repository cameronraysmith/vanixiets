# ADR-004: Local cluster networking with cloud-init and parameterized port forwarding

## Status

Proposed

## Context

The local development environment uses a nested virtualization topology: macOS hosts a Colima VM, which in turn hosts incus-managed k3s VMs.
Network access from macOS to services running in k3s VMs must traverse two network boundaries:

```
macOS localhost → Colima VM (Lima/QEMU) → incus bridge (incusbr0) → k3s VM
```

The incus bridge network uses the `192.100.0.0/24` range with the bridge interface at `192.100.0.1`.
K3s VMs receive IP addresses from this range.

The architecture must support multiple k3s clusters from a single NixOS image:
- `k3s-dev`: Persistent development environment for iterative work
- `k3s-capi`: Ephemeral ClusterAPI management cluster for bootstrap operations
- Future clusters as needed (e.g., testing specific Kubernetes versions)

Each cluster requires:
- A deterministic static IP address for reliable kubeconfig generation and tooling
- Predictable port mappings to macOS localhost for external access
- Configuration that is version-controlled and reproducible

The challenge is avoiding per-cluster NixOS image builds while maintaining deterministic network configuration.

## Decision

### Three-layer architecture

The solution separates concerns across three configuration layers:

1. **Single reusable NixOS image** (`k3s-local.nix`)
2. **Per-cluster incus profiles** (`incus.nix`)
3. **Parameterized port forwarding** (`colima.nix`)

### Layer 1: NixOS image with cloud-init

The `k3s-local.nix` image is cloud-init enabled and contains no hardcoded network configuration.
It uses systemd-networkd with DHCP fallback, allowing cloud-init to override with static configuration.

Key characteristics:
- Cloud-init service enabled and configured for NoCloud datasource
- systemd-networkd manages network interfaces
- Hostname derived from cloud-init `user.meta-data`
- No IP addresses, hostnames, or cluster-specific settings in the image

This enables one image to be instantiated as any cluster by varying the cloud-init configuration.

### Layer 2: Per-cluster incus profiles

Each k3s cluster has an incus profile that supplies cloud-init configuration:
- `user.network-config`: Cloud-init network-config v2 with static IP assignment
- `user.meta-data`: Instance metadata including hostname

IP address assignment scheme:

| Cluster | IP Address | Purpose |
|---------|-----------|---------|
| k3s-dev | 192.100.0.10 | Persistent development |
| k3s-capi | 192.100.0.11 | Ephemeral ClusterAPI bootstrap |
| k3s-test | 192.100.0.12 | Future: version testing |
| k3s-N | 192.100.0.(10+N) | Extensible pattern |

The profiles are defined in the home-manager `incus.nix` module and applied declaratively when creating cluster instances.

### Layer 3: Parameterized port forwarding

Lima provision scripts in the Colima configuration create systemd services that forward ports from the Colima VM to k3s VM IPs.
Each port forwarder uses socat and runs as a user systemd service.

Port offset scheme uses `base_port + cluster_index`:

| Port | k3s-dev (index 0) | k3s-capi (index 1) | Service |
|------|-------------------|-------------------|---------|
| Kubernetes API | 6443 | 6444 | kube-apiserver |
| HTTP | 8080 | 8081 | Ingress HTTP |
| HTTPS | 8443 | 8444 | Ingress HTTPS |
| SSH | 2210 | 2211 | Node access |

The port forwarding configuration lives in `colima.nix` and generates Lima provision scripts that create persistent systemd services.
Lima's port forwarding from macOS localhost to the Colima VM then completes the chain.

Complete path example for k3s-dev Kubernetes API:
```
macOS :6443 → Lima → Colima VM :6443 → socat → 192.100.0.10:6443 → k3s-dev VM
```

## Consequences

### Positive

- Single NixOS image avoids duplication and ensures all clusters run identical configurations
- Cloud-init is the industry standard pattern for VM configuration injection
- Predictable port mapping enables reliable kubeconfig generation and scripting
- Version-controlled configuration in Nix modules provides reproducible environments
- Adding new clusters requires only profile and port definitions, not image rebuilds
- Static IPs enable stable kubeconfig files that survive VM restarts

### Negative

- Port offset scheme limits the number of clusters (ports must not collide with other services)
- socat port forwarders add a small latency overhead
- Cloud-init adds boot-time delay for configuration application
- Three-layer configuration requires understanding the full stack to troubleshoot network issues

### Neutral

- incus profiles must be applied manually or via deployment scripts (not automatically discovered)
- Port mappings must be coordinated across `colima.nix` and kubeconfig generation

## Alternatives considered

### Per-cluster NixOS images

Building a separate NixOS image for each cluster with hardcoded network configuration would eliminate the cloud-init layer.
However, this creates image proliferation and requires rebuilds for any network change.
The cloud-init approach provides runtime flexibility while maintaining reproducibility through version-controlled profiles.

### DHCP with mDNS/Avahi

Using DHCP with multicast DNS for service discovery would eliminate static IP management.
However, DHCP leases can change, breaking kubeconfig files and scripts.
The nested virtualization topology also complicates mDNS propagation.
Static IPs provide the determinism required for reliable development tooling.

### Kubernetes LoadBalancer with MetalLB

MetalLB could provide LoadBalancer IPs from the incus bridge range, reducing port forwarding complexity.
However, this adds another component to manage and still requires port forwarding from macOS to the Colima VM.
The direct socat approach is simpler and sufficient for development use cases.

### Lima native port forwarding

Lima supports port forwarding configuration directly, which could eliminate the socat layer.
However, Lima's port forwarding targets the VM itself, not nested VMs within incus.
The explicit socat forwarders provide the hop from Colima VM to incus guest IPs that Lima cannot address natively.
