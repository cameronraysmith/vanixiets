---
title: Environment setup
---

# Environment setup

This workflow documents setting up the local Kubernetes development environment on macOS with Apple Silicon.
The architecture uses k3d (k3s-in-docker) running on OrbStack's container runtime, providing a lightweight and fast local Kubernetes cluster.
This approach maintains Kubernetes distribution parity with Hetzner production deployments (k3s) while enabling rapid local iteration.

## Prerequisites

Before starting, ensure the following requirements are met.

Apple Silicon Mac (M1, M2, M3, or M4 processor) running macOS 13 Ventura or later is required.

Nix with flakes enabled must be available.
The vanixiets flake provides nix-darwin configuration for the development environment.

OrbStack must be installed for the container runtime.
OrbStack provides superior performance on Apple Silicon compared to Docker Desktop.

Resource requirements for running the full development stack:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU cores | 4 | 8+ |
| RAM | 16 GB | 32+ GB |
| Disk | 50 GB | 100+ GB |

The recommended configuration allocates sufficient headroom for running multiple Kubernetes workloads alongside local development tools.

## Tool installation

### OrbStack

OrbStack provides the container runtime for k3d.
Install via Homebrew or download from the OrbStack website.

```sh
brew install orbstack
```

After installation, ensure OrbStack is running and the Docker socket is available.

```sh
# Verify Docker CLI works with OrbStack
docker info | grep -i "operating system"
# Should show: Operating System: OrbStack
```

### k3d and ctlptl

k3d creates k3s clusters running as Docker containers.
ctlptl provides declarative cluster lifecycle management.

Install via Nix (recommended for consistency):

```sh
# Available in the vanixiets devshell
nix develop
```

Or install directly:

```sh
# Via Homebrew
brew install k3d ctlptl

# Verify installation
k3d version
ctlptl version
```

### kubectl and supporting tools

Essential Kubernetes CLI tools:

```sh
# Available in the vanixiets devshell, or install via:
brew install kubectl kubernetes-helm cilium-cli k9s kluctl
```

## k3d cluster configuration

The local k3d cluster is declared as a ctlptl `Cluster` in `kubernetes/clusters/local-k3d/ctlptl.nix` and rendered by the flake as `packages.<system>.k3d-cluster-config`.
The configuration enables Cilium CNI by disabling k3s bundled networking.

### Cluster configuration file

`just k3d-up` and `just k3d-down` build the rendered file and pass its store path to `ctlptl apply -f` and `ctlptl delete -f`.
To inspect it:

```sh
jq . "$(nix build --no-link --print-out-paths .#k3d-cluster-config)"
```

The node image is `rancher/k3s:v<version>`, where `<version>` is the locked nixpkgs `k3s.version` with its `+k3sN` suffix written as `-k3sN`, the form the upstream image tags use.
A nixpkgs bump therefore moves the k3d node to the same k3s release the NixOS `services.k3s` module defaults to.

Key configuration points:

- `K3D_FIX_MOUNTS=1` environment variable enables BPF mount propagation for Cilium
- Flannel, network-policy, and kube-proxy are disabled for Cilium replacement
- Traefik is disabled for Cilium Gateway API ingress; ServiceLB stays enabled and assigns the node IP to LoadBalancer services
- Ports 80/443 are exposed via the k3d load balancer
- Subnet `192.168.100.0/24` pins the node at `192.168.100.3` for the `*.192.168.100.3.sslip.io` hostnames
- `/tmp/k3d-manifests` is mounted at `/manifests` for the integration run's `file:///manifests` ArgoCD source

### ctlptl registry (optional)

For faster image pulls, ctlptl can manage a local registry:

```yaml
# ctlptl/registry.yaml
apiVersion: ctlptl.dev/v1alpha1
kind: Registry
metadata:
  name: local-registry
port: 5001
```

## Starting the cluster

### Using justfile recipes

The vanixiets repository provides justfile recipes for cluster management:

```sh
# Create cluster with full infrastructure
just k3d-full

# Create cluster only (no infrastructure deployment)
just k3d-up

# Delete cluster
just k3d-down
```

### Manual cluster creation

Create the cluster using k3d directly:

```sh
# Create cluster from configuration
k3d cluster create --config k3d/local-k3d.yaml

# Verify cluster is running
kubectl cluster-info
kubectl get nodes
```

Expected output shows a single node in Ready state:

```
NAME                      STATUS   ROLES                  AGE   VERSION
k3d-local-k3d-server-0    Ready    control-plane,master   1m    v1.31.4+k3s1
```

## Initial verification

After starting the cluster, verify all components are functioning correctly.

### kubeconfig access

k3d automatically updates your kubeconfig and switches context:

```sh
# Verify current context
kubectl config current-context
# Should show: k3d-local-k3d

# List available contexts
kubectl config get-contexts
```

### Node status

```sh
# Check node status
kubectl get nodes -o wide

# Verify system pods (will be Pending until Cilium deploys)
kubectl get pods -n kube-system
```

System pods will remain Pending or ContainerCreating until Cilium CNI is deployed.

### Container runtime verification

```sh
# Verify k3d containers are running
docker ps --filter "name=k3d"

# Should show server and loadbalancer containers
```

## Troubleshooting

### Cluster creation failure

If cluster creation fails, check Docker/OrbStack status:

```sh
# Verify OrbStack is running
docker info

# Check for port conflicts
lsof -i :6443
lsof -i :80
lsof -i :443
```

Delete and recreate if needed:

```sh
k3d cluster delete local-k3d
k3d cluster create --config k3d/local-k3d.yaml
```

### Network connectivity issues

If pods cannot reach external networks:

```sh
# Check CoreDNS status
kubectl get pods -n kube-system -l k8s-app=kube-dns

# Test DNS resolution from a debug pod
kubectl run -it --rm debug --image=busybox -- nslookup kubernetes
```

### Cilium BPF mount issues

If Cilium fails to start due to BPF mount issues:

```sh
# Verify K3D_FIX_MOUNTS was set
docker exec k3d-local-k3d-server-0 mount | grep bpf
# Should show /sys/fs/bpf mounted
```

If missing, recreate the cluster ensuring `K3D_FIX_MOUNTS=1` is in the configuration.

### Resource constraints

If pods fail to schedule due to resource constraints:

```sh
# Check node resources
kubectl describe node k3d-local-k3d-server-0

# Increase OrbStack resources via OrbStack settings
# Or reduce workload resource requests
```

## Log locations

Key log locations for debugging:

| Location | Contents |
|----------|----------|
| `docker logs k3d-local-k3d-server-0` | k3s server logs |
| `kubectl logs -n kube-system -l k8s-app=cilium` | Cilium agent logs |
| `kubectl logs -n kube-system -l name=cilium-operator` | Cilium operator logs |

## Next steps

After completing environment setup, proceed to:

- [02-local-development.md](./02-local-development.md) - Day-to-day local development workflow
- [03-clusterapi-bootstrap.md](./03-clusterapi-bootstrap.md) - Bootstrap ClusterAPI for Hetzner provisioning
- [04-hetzner-deployment.md](./04-hetzner-deployment.md) - Deploy full stack to Hetzner production

## References

- k3d documentation: https://k3d.io/
- ctlptl documentation: https://github.com/tilt-dev/ctlptl
- OrbStack documentation: https://docs.orbstack.dev/
- ADR-005: [Local cluster architecture revision](../decisions/ADR-005-local-cluster-architecture-revision.md)
