---
title: nix-csi
---

# nix-csi

nix-csi is a Kubernetes CSI driver that dynamically mounts Nix store closures into pod volumes.
It enables pods to request Nix dependencies as ephemeral CSI volumes without pre-baking them into container images.

## When to use nix-csi

Use nix-csi when you need to run binaries from the Nix store inside Kubernetes pods without including them in the container image.
This is particularly useful for development environments, CI jobs, and workloads that benefit from declarative dependency management.

The CSI ephemeral volume approach means volumes share lifetime with pods and are embedded directly in the pod spec.
There are no persistent volume claims to manage separately.

## Architecture

nix-csi consists of two main components: a node DaemonSet that runs on every cluster node, and an optional cache StatefulSet for distributed builds.

### Node DaemonSet

The DaemonSet deploys the CSI driver to each cluster node.
It runs privileged to perform bind mounts from the host Nix store into pod volumes.

Key components in each DaemonSet pod:

- `nix-node`: The main CSI driver container that handles volume mount requests
- `csi-node-driver-registrar`: Registers the driver with kubelet
- `livenessprobe`: Health checking for the CSI socket

The DaemonSet uses bidirectional mount propagation to expose `/nix` and `/var/lib/kubelet` between the host and containers.
Host storage is persisted at `/var/lib/nix-csi` by default.

### Cache StatefulSet

The optional cache service provides distributed build capabilities for multi-node clusters.
When enabled, nodes can offload builds to the cache and share results.

The cache pod exposes SSH on port 22 internally and via a LoadBalancer service on a configurable port (default 2222).
It maintains a persistent volume claim for the Nix store.

### SSH coordination

Both node and cache components use SSH for Nix remote builds and store copying.
SSH keys are generated at evaluation time and distributed via Kubernetes secrets.
The `nix-builders` headless service provides DNS-based discovery between builder nodes and the cache.

## Volume specification methods

nix-csi supports three methods for specifying what to mount, evaluated in priority order.

### storePath (priority 1)

Direct Nix store paths are the fastest option since no evaluation is needed.
Use architecture-specific keys for multi-arch support.

```yaml
volumes:
  - name: nix-csi
    csi:
      driver: nix.csi.store
      volumeAttributes:
        x86_64-linux: /nix/store/abc123-hello-2.12
        aarch64-linux: /nix/store/def456-hello-2.12
```

In easykubenix/Nix configuration:

```nix
volumes = lib.mkNamedList {
  nix-csi.csi = {
    driver = "nix.csi.store";
    volumeAttributes.${pkgs.stdenv.hostPlatform.system} = pkgs.hello;
  };
};
```

### flakeRef (priority 2)

Flake references are evaluated and built at mount time.
This is convenient but slower than pre-evaluated store paths.

```yaml
volumes:
  - name: nix-csi
    csi:
      driver: nix.csi.store
      volumeAttributes:
        flakeRef: "github:nixos/nixpkgs/nixos-unstable#hello"
```

```nix
volumes = lib.mkNamedList {
  nix-csi.csi = {
    driver = "nix.csi.store";
    volumeAttributes.flakeRef = "github:nixos/nixpkgs/nixos-unstable#hello";
  };
};
```

### nixExpr (priority 3)

Raw Nix expressions provide maximum flexibility but require full evaluation.

```yaml
volumes:
  - name: nix-csi
    csi:
      driver: nix.csi.store
      volumeAttributes:
        nixExpr: |
          let
            nixpkgs = builtins.fetchTree {
              type = "github";
              owner = "nixos";
              repo = "nixpkgs";
              ref = "nixos-unstable";
            };
            pkgs = import nixpkgs { };
          in
          pkgs.hello
```

```nix
volumes = lib.mkNamedList {
  nix-csi.csi = {
    driver = "nix.csi.store";
    volumeAttributes.nixExpr = ''
      let
        nixpkgs = builtins.fetchTree {
          type = "github";
          owner = "nixos";
          repo = "nixpkgs";
          ref = "nixos-unstable";
        };
        pkgs = import nixpkgs { };
      in
      pkgs.hello
    '';
  };
};
```

## Deployment via easykubenix

nix-csi provides an easykubenix module at `${nix-csi}/kubenix`.

### Configuration options

| Option | Type | Default | Description |
|--------|------|---------|-------------|
| `nix-csi.enable` | bool | false | Enable nix-csi deployment |
| `nix-csi.namespace` | string | "nix-csi" | Namespace for nix-csi resources |
| `nix-csi.version` | string | (from pyproject.toml) | Version tag for images |
| `nix-csi.hostMountPath` | path | /var/lib/nix-csi | Host directory for Nix store |
| `nix-csi.authorizedKeys` | list of strings | [] | Additional SSH public keys |
| `nix-csi.cache.enable` | bool | false | Enable cache StatefulSet |
| `nix-csi.cache.storageClassName` | string | null | Storage class for cache PVC |
| `nix-csi.cache.loadBalancerPort` | int | 2222 | LoadBalancer port for SSH |

### Module import

```nix
{
  imports = [
    "${nix-csi}/kubenix"
  ];
}
```

## Local development setup

For local Kubernetes clusters (kind, minikube, k3d), nix-csi can run in single-node mode without the cache service.

```nix
{ config, lib, ... }:
{
  nix-csi = {
    enable = true;
    namespace = "nix-csi";
    # Cache is optional for single-node clusters
    cache.enable = false;
  };
}
```

### Host /nix mount considerations

Local clusters may have limited access to the host Nix store.
Verify your cluster runtime supports the required bind mounts.

For kind, you may need to configure extra mounts in the cluster config.
For minikube with the docker driver, the host Nix store is typically accessible.

The DaemonSet init container copies the node environment into the persistent host path at `/var/lib/nix-csi`.
Subsequent pod mounts read from this location.

### Privileged pod requirements

nix-csi requires privileged pods for bind mount operations.
Ensure your local cluster allows privileged containers.

For kind, this is typically allowed by default.
For minikube, check the security configuration.

## Production setup

Production deployments should enable the cache service for distributed builds across multiple nodes.

```nix
{ config, lib, ... }:
{
  nix-csi = {
    enable = true;
    namespace = "nix-csi";

    cache = {
      enable = true;
      # Use your cluster's storage class for the cache PVC
      storageClassName = "local-path";
      # External SSH access for debugging (optional)
      loadBalancerPort = 2222;
    };

    # Add external SSH keys for remote build access
    authorizedKeys = [
      "ssh-ed25519 AAAA... user@example.com"
    ];
  };
}
```

### Storage class for cache PVC

The cache StatefulSet requires a storage class for its persistent volume claim.
Configure `cache.storageClassName` to match your cluster's available storage.

For Hetzner clusters using local-path-provisioner:

```nix
nix-csi.cache.storageClassName = "local-path";
```

### Multi-architecture support

nix-csi supports both x86_64-linux and aarch64-linux.
The node and cache packages are built for both architectures automatically.

When specifying store paths, provide both architecture keys to support heterogeneous clusters:

```nix
volumeAttributes = {
  x86_64-linux = pkgs.x86_64-linux.hello;
  aarch64-linux = pkgs.aarch64-linux.hello;
};
```

## Security considerations

### Privileged DaemonSet

The nix-csi DaemonSet runs with `securityContext.privileged = true`.
This is required for:

- Bind mounting from the host Nix store into pod volumes
- Bidirectional mount propagation to kubelet
- Chroot store operations during init

This grants significant host access.
Review your cluster security policies before deployment.

### RBAC requirements

nix-csi requires cluster-wide RBAC permissions:

```nix
ClusterRole.nix-csi.rules = [
  # Read nodes and pods for SSH machine discovery
  {
    apiGroups = [ "" ];
    resources = [ "nodes" "pods" ];
    verbs = [ "get" "list" "watch" ];
  }
  # Manage SSH secrets
  {
    apiGroups = [ "" ];
    resources = [ "secrets" ];
    verbs = [ "get" "list" "create" "patch" ];
  }
  # Read authorized keys configmap
  {
    apiGroups = [ "" ];
    resources = [ "configmaps" ];
    verbs = [ "get" "list" ];
  }
];
```

### SSH key management

SSH keys for in-cluster communication are generated at Nix evaluation time if not explicitly provided.
For production, consider providing your own keys via `nix-csi.pubKey` and `nix-csi.privKey`.

The keys are stored in Kubernetes secrets with mode 400 (owner read-only).

## Troubleshooting

### Pod mount failures

Check the nix-node container logs on the node where the pod is scheduled:

```bash
kubectl logs -n nix-csi daemonset/nix-node -c nix-node
```

Common causes:

- CSI driver not registered: Check `csi-node-driver-registrar` logs
- Missing store path: Verify the path exists or can be built
- Mount propagation issues: Ensure kubelet supports bidirectional mounts

### Build errors

For `flakeRef` and `nixExpr` volume specifications, build errors appear in the nix-node logs.

Common issues:

- Network access: Ensure nodes can reach required URLs (github.com, cache.nixos.org)
- GitHub rate limits: Configure `NIX_CONFIG` with access tokens if hitting API limits

### Cache service issues

Verify cache pod status:

```bash
kubectl get pods -n nix-csi -l app.kubernetes.io/name=cache
kubectl logs -n nix-csi statefulset/nix-cache -c nix-cache
```

Check SSH connectivity between nodes and cache:

```bash
kubectl exec -n nix-csi daemonset/nix-node -c nix-node -- ssh nix-cache.nix-csi.svc.cluster.local
```

### Init container failures

The DaemonSet init container copies the node environment to the host path.
If init fails, check:

```bash
kubectl logs -n nix-csi daemonset/nix-node -c initcopy
```

Verify the host path is writable and has sufficient space.

## Example configurations

### Minimal local development

```nix
{ nix-csi, ... }:
{
  imports = [ "${nix-csi}/kubenix" ];

  nix-csi.enable = true;
}
```

### Production with cache

```nix
{ nix-csi, ... }:
{
  imports = [ "${nix-csi}/kubenix" ];

  nix-csi = {
    enable = true;
    namespace = "nix-csi";
    hostMountPath = "/var/lib/nix-csi";

    cache = {
      enable = true;
      storageClassName = "local-path";
      loadBalancerPort = 2222;
    };

    authorizedKeys = [
      "ssh-ed25519 AAAA... admin@example.com"
    ];
  };
}
```

### Job using flakeRef

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.nix-csi;
in
{
  kubernetes.resources.${cfg.namespace}.Job.example = {
    spec.template.spec = {
      restartPolicy = "Never";
      containers = lib.mkNamedList {
        main = {
          image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
          command = [ "hello" ];
          volumeMounts = lib.mkNamedList {
            nix-csi.mountPath = "/nix";
          };
        };
      };
      volumes = lib.mkNamedList {
        nix-csi.csi = {
          driver = "nix.csi.store";
          volumeAttributes.flakeRef = "github:nixos/nixpkgs/nixos-unstable#hello";
        };
      };
    };
  };
}
```

### Multi-architecture deployment

```nix
{ config, lib, pkgs, ... }:
let
  cfg = config.nix-csi;
  x86Pkgs = import pkgs.path { system = "x86_64-linux"; };
  armPkgs = import pkgs.path { system = "aarch64-linux"; };
in
{
  kubernetes.resources.${cfg.namespace}.Deployment.example = {
    spec = {
      replicas = 3;
      selector.matchLabels.app = "example";
      template = {
        metadata.labels.app = "example";
        spec = {
          containers = lib.mkNamedList {
            main = {
              image = "ghcr.io/lillecarl/nix-csi/scratch:1.0.1";
              command = [ "hello" ];
              volumeMounts = lib.mkNamedList {
                nix-csi.mountPath = "/nix";
              };
            };
          };
          volumes = lib.mkNamedList {
            nix-csi.csi = {
              driver = "nix.csi.store";
              volumeAttributes = {
                x86_64-linux = x86Pkgs.hello;
                aarch64-linux = armPkgs.hello;
              };
            };
          };
        };
      };
    };
  };
}
```
