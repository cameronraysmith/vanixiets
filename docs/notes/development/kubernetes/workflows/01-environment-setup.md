---
title: Environment setup
---

# Environment setup

This workflow documents setting up the local Kubernetes development environment on macOS with Apple Silicon.
The architecture uses Colima with Virtualization.framework (vz backend) to run NixOS x86_64-linux VMs via Rosetta emulation.
This approach maintains parity with Hetzner production deployments while enabling rapid local iteration.

## Prerequisites

Before starting, ensure the following requirements are met.

Apple Silicon Mac (M1, M2, or M3 processor) running macOS 13 Ventura or later is required.
Rosetta 2 must be installed for x86_64 emulation.

```sh
softwareupdate --install-rosetta --agree-to-license
```

Nix with flakes enabled must be available.
The vanixiets flake provides nix-darwin configuration for the development environment.

Colima must be installed either via nix-darwin (recommended) or Homebrew.
The nix-darwin module at `modules/darwin/colima.nix` provides declarative Colima configuration with helper scripts.

Resource requirements for running the full development stack:

| Resource | Minimum | Recommended |
|----------|---------|-------------|
| CPU cores | 8 | 12+ |
| RAM | 32 GB | 48+ GB |
| Disk | 100 GB | 200+ GB |

The recommended configuration allocates sufficient headroom for running multiple Kubernetes workloads alongside local development tools.

## Colima profile strategy

Two Colima profiles serve distinct purposes in the development workflow.

### k3s-dev profile

The `k3s-dev` profile runs application workloads during iterative development.
This profile uses moderate resources and can be started and stopped frequently.

| Setting | Value | Rationale |
|---------|-------|-----------|
| CPU | 4 | Sufficient for typical workloads |
| Memory | 8 GiB | Covers common application pods |
| Disk | 60 GiB | Standard container image storage |
| Architecture | x86_64 | Hetzner parity |
| VM type | vz | Virtualization.framework for performance |
| Mount type | virtiofs | Low-latency host filesystem access |

### k3s-capi profile

The `k3s-capi` profile runs ClusterAPI management infrastructure.
This profile requires more resources for running the management cluster components.

| Setting | Value | Rationale |
|---------|-------|-----------|
| CPU | 6 | ClusterAPI controllers overhead |
| Memory | 12 GiB | Management cluster requirements |
| Disk | 80 GiB | Additional manifest and state storage |
| Architecture | x86_64 | Hetzner parity |
| VM type | vz | Virtualization.framework for performance |
| Mount type | virtiofs | Low-latency host filesystem access |

Both profiles enable Rosetta via `--vz-rosetta` for x86_64 binary execution on aarch64-darwin hosts.

## NixOS VM image building

The VM image uses nixos-generators to produce a qcow-efi format image targeting x86_64-linux.
This format is compatible with Colima's vz backend and provides UEFI boot support.

### Image configuration

The image configuration builds on patterns from nix-rosetta-builder.
Key components include:

- UEFI boot with systemd-boot loader
- Rosetta integration via virtiofs mount tag `vz-rosetta`
- SSH server with key-based authentication
- Nix with flakes enabled
- k3s server configured for Cilium CNI

The Rosetta mount enables transparent x86_64 binary execution inside the VM.
Lima (which Colima wraps) configures the Rosetta virtiofs share automatically when using vz backend with `--vz-rosetta`.

### Building the image

Build the k3s-local image from the flake.

```sh
nix build .#k3s-local-image
```

The build produces a qcow2 image at `./result/nixos.qcow2`.
First-time builds may take several minutes depending on network and CPU speed.

### Example flake configuration

The flake output defines the VM image using nixos-generators.

```nix
{
  inputs = {
    nixpkgs.url = "github:NixOS/nixpkgs/nixos-unstable";
    nixos-generators = {
      url = "github:nix-community/nixos-generators";
      inputs.nixpkgs.follows = "nixpkgs";
    };
  };

  outputs = { self, nixpkgs, nixos-generators, ... }:
  let
    system = "aarch64-darwin";
    linuxSystem = "x86_64-linux";
  in
  {
    packages.${system}.k3s-local-image = nixos-generators.nixosGenerate {
      system = linuxSystem;
      format = "qcow-efi";
      modules = [
        ./modules/nixos/k3s-local.nix
        {
          # Rosetta integration for x86_64 emulation
          virtualisation.rosetta = {
            enable = true;
            mountTag = "vz-rosetta";
          };

          # Boot configuration
          boot = {
            kernelParams = [ "console=tty0" ];
            loader = {
              efi.canTouchEfiVariables = true;
              systemd-boot.enable = true;
            };
          };

          # Nix configuration
          nix.settings = {
            experimental-features = [ "flakes" "nix-command" ];
            trusted-users = [ "@wheel" ];
          };

          system.stateVersion = "24.11";
        }
      ];
    };
  };
}
```

The k3s-local.nix module contains the k3s server configuration documented in the [NixOS k3s server module](../components/nixos-k3s-server.md) component reference.

## VM image import to Colima

Starting Colima with a custom NixOS image requires specifying the image location.

### First-time setup

Create the k3s-dev profile with the custom image.

```sh
# Build the image first
nix build .#k3s-local-image

# Start Colima with custom image
colima start \
  --profile k3s-dev \
  --arch x86_64 \
  --vm-type vz \
  --mount-type virtiofs \
  --vz-rosetta \
  --cpus 4 \
  --memory 8 \
  --disk 60 \
  --image-path ./result/nixos.qcow2
```

The `--image-path` flag instructs Colima to use the custom NixOS image instead of the default Lima base image.

### Profile management

Common profile management commands.

```sh
# List all profiles
colima list

# Check profile status
colima status --profile k3s-dev

# Stop profile
colima stop --profile k3s-dev

# Delete profile (removes VM and all data)
colima delete --profile k3s-dev

# Start existing profile (after initial creation)
colima start --profile k3s-dev
```

The nix-darwin colima module provides wrapper scripts `colima-init`, `colima-stop`, and `colima-restart` that use declarative configuration values.

### Creating the ClusterAPI profile

Follow the same process for the k3s-capi profile with adjusted resources.

```sh
colima start \
  --profile k3s-capi \
  --arch x86_64 \
  --vm-type vz \
  --mount-type virtiofs \
  --vz-rosetta \
  --cpus 6 \
  --memory 12 \
  --disk 80 \
  --image-path ./result/nixos.qcow2
```

## Initial verification

After starting the VM, verify all components are functioning correctly.

### SSH access

Colima provides SSH access to the VM.

```sh
colima ssh --profile k3s-dev
```

Once inside the VM, verify the system.

```sh
# Check NixOS version
nixos-version

# Verify Rosetta is working
file /run/rosetta/rosetta
# Should show: /run/rosetta/rosetta: Mach-O universal binary ...
```

### k3s verification

Verify k3s is running and accessible.

```sh
# Inside the VM
systemctl status k3s

# Check k3s is ready
k3s kubectl get nodes
# Should show single node in Ready state

# Verify no default CNI (waiting for Cilium)
k3s kubectl get pods -A
# coredns pods should be Pending until CNI installed
```

### Host kubectl access

Configure kubectl on the host to access the cluster.

```sh
# Copy kubeconfig from VM
colima ssh --profile k3s-dev -- sudo cat /etc/rancher/k3s/k3s.yaml > ~/.kube/k3s-dev.yaml

# Update server address to use Colima VM IP
COLIMA_IP=$(colima list --json | jq -r '.[] | select(.name == "k3s-dev") | .address')
sed -i '' "s/127.0.0.1/${COLIMA_IP}/" ~/.kube/k3s-dev.yaml

# Test access
KUBECONFIG=~/.kube/k3s-dev.yaml kubectl get nodes
```

### Rosetta emulation verification

Verify x86_64 binaries execute correctly via Rosetta.

```sh
# Inside the VM
# Download and run an x86_64 binary
curl -LO https://dl.k8s.io/release/v1.29.0/bin/linux/amd64/kubectl
chmod +x kubectl
file kubectl
# Should show: kubectl: ELF 64-bit LSB executable, x86-64, ...

./kubectl version --client
# Should execute successfully via Rosetta
```

## Troubleshooting

Common issues and resolution procedures.

### Image boot failure

If the VM fails to boot, check the Colima logs.

```sh
# View VM logs
colima logs --profile k3s-dev

# Common causes:
# - Image format incompatibility: ensure qcow-efi format
# - UEFI boot issues: verify systemd-boot is enabled in NixOS config
# - Resource exhaustion: check host has sufficient memory
```

Regenerate the image if boot configuration changes are needed.

```sh
# Remove cached build
rm -rf result

# Rebuild with any configuration fixes
nix build .#k3s-local-image --rebuild
```

### Network connectivity issues

If the VM has no network access, verify Colima networking.

```sh
# Check VM network interface
colima ssh --profile k3s-dev -- ip addr

# Verify DNS resolution
colima ssh --profile k3s-dev -- cat /etc/resolv.conf
colima ssh --profile k3s-dev -- nslookup github.com

# Restart networking if needed
colima ssh --profile k3s-dev -- sudo systemctl restart systemd-networkd
```

### k3s startup failure

If k3s fails to start, check the service logs.

```sh
colima ssh --profile k3s-dev -- sudo journalctl -u k3s -f

# Common causes:
# - Port conflicts: ensure 6443 is not in use
# - Insufficient memory: increase VM memory allocation
# - Kernel module missing: verify br_netfilter loaded
```

Verify required kernel modules are loaded.

```sh
colima ssh --profile k3s-dev -- lsmod | grep -E 'br_netfilter|nf_conntrack|overlay'
```

### Reset procedures

For a clean restart, delete and recreate the profile.

```sh
# Stop and delete profile
colima stop --profile k3s-dev
colima delete --profile k3s-dev

# Rebuild image if needed
nix build .#k3s-local-image --rebuild

# Recreate profile
colima start \
  --profile k3s-dev \
  --arch x86_64 \
  --vm-type vz \
  --mount-type virtiofs \
  --vz-rosetta \
  --cpus 4 \
  --memory 8 \
  --disk 60 \
  --image-path ./result/nixos.qcow2
```

### Log locations

Key log locations for debugging.

| Location | Contents |
|----------|----------|
| `/tmp/colima-k3s-dev.out.log` | Colima stdout (if using launchd) |
| `/tmp/colima-k3s-dev.err.log` | Colima stderr (if using launchd) |
| `~/.colima/k3s-dev/colima.log` | Colima profile-specific logs |
| VM: `/var/log/` | NixOS system logs |
| VM: `journalctl -u k3s` | k3s service logs |
| VM: `journalctl -u containerd` | Container runtime logs |

## Next steps

After completing environment setup, proceed to:

- [02-local-development.md](./02-local-development.md) - Day-to-day local development workflow
- [03-clusterapi-bootstrap.md](./03-clusterapi-bootstrap.md) - Bootstrap ClusterAPI for Hetzner provisioning
- [04-hetzner-deployment.md](./04-hetzner-deployment.md) - Deploy full stack to Hetzner production

## References

- Component documentation: [NixOS k3s server module](../components/nixos-k3s-server.md)
- Colima nix-darwin module: `/Users/crs58/projects/nix-workspace/vanixiets/modules/darwin/colima.nix`
- nix-rosetta-builder patterns: `/Users/crs58/projects/nix-workspace/nix-rosetta-builder/package.nix`
- Colima documentation: https://github.com/abiosoft/colima
- Lima documentation: https://lima-vm.io/docs/
- nixos-generators: https://github.com/nix-community/nixos-generators
