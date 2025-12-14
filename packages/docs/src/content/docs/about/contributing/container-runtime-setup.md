---
title: Container Runtime Setup
sidebar:
  order: 9
---

This configuration uses a hybrid approach for optimal container and VM management on macOS:

- **nix-rosetta-builder**: Linux builds for Nix packages
- **Colima + Incus**: OCI container management (Docker Desktop replacement)

## Architecture

```
┌─────────────────────────────────────────┐
│         macOS (aarch64-darwin)          │
├─────────────────────────────────────────┤
│                                         │
│  nix-rosetta-builder (Lima + QEMU)     │
│  └─ Nix builds (aarch64/x86_64-linux)  │
│                                         │
│  Colima (Lima + Virtualization.framework)│
│  └─ Incus runtime                       │
│     ├─ System containers (NixOS, etc)   │
│     └─ VMs (nested virt on M3+)         │
│                                         │
└─────────────────────────────────────────┘
```

## First-time setup

After activating the system configuration, initialize Colima:

```bash
# Apply the configuration (installs Colima via nix, Incus via homebrew)
darwin-rebuild switch --flake .#stibnite

# Initialize Colima with configured settings
colima-init

# Verify status
colima status
```

The `colima-init` helper script reads your declarative configuration from `configurations/darwin/stibnite.nix` and starts Colima with those settings.

Note: The Incus client is installed via Homebrew (not nixpkgs) since the nixpkgs Incus package is Linux-only (server + client), while macOS only needs the client.

### Test with incus

Colima automatically configures the Incus remote during startup.
No manual `incus remote add` is needed.

```bash
# Launch a NixOS container
incus launch images:nixos/unstable test-container

# Execute commands in the container
incus exec test-container -- nixos-version

# Clean up
incus delete test-container --force
```

## Working alongside OrbStack

Colima (with Incus runtime) works seamlessly alongside OrbStack's Docker runtime.
Both tools use isolated state directories and separate sockets, allowing you to run Docker containers via OrbStack and system containers via Colima simultaneously.

### Verify both tools work

After initializing Colima, confirm both runtimes are operational:

```bash
# OrbStack Docker is still active
docker ps
docker context show  # Shows "orbstack"

# Colima Incus is ready
colima status
incus list
```

### Using both simultaneously

Run containers from both runtimes at the same time:

```bash
# Terminal 1: OrbStack Docker container
docker run -it --rm alpine sh

# Terminal 2: Colima Incus container
incus launch images:alpine/edge colima-alpine
incus exec colima-alpine -- sh
```

Both containers run concurrently without conflicts.

### Tool selection guide

| Use OrbStack when | Use Colima when |
|-------------------|-----------------|
| Docker Compose projects | System containers (full init) |
| Standard OCI containers | NixOS/declarative containers |
| Kubernetes workflows | Nested VMs (M3+ only) |
| Docker Desktop compatibility | Testing different distros |

### Managing Colima profiles

Stop or remove Colima without affecting OrbStack:

```bash
# Stop Colima temporarily (OrbStack unaffected)
colima stop

# Restart later
colima start

# Remove profile completely (keeps binary installed)
colima delete --profile default

# Reinitialize if needed
colima-init
```

## Daily usage

### Starting and stopping

```bash
# Start Colima (uses configured profile)
colima start

# Stop Colima
colima-stop

# Restart after config changes
colima-restart

# Check status
colima status
```

### Using incus

The Incus runtime provides system containers and VMs with native Linux environments:

```bash
# Launch NixOS container
incus launch images:nixos/unstable mycontainer

# Execute commands
incus exec mycontainer -- bash

# List containers
incus list

# Stop container
incus stop mycontainer

# Delete container
incus delete mycontainer --force

# Launch other distros
incus launch images:ubuntu/24.04 ubuntu-container
incus launch images:alpine/edge alpine-container
```

### Container management

```bash
# Copy files to/from container
incus file push localfile.txt mycontainer/root/
incus file pull mycontainer/root/file.txt .

# Execute commands
incus exec mycontainer -- apt update
incus exec mycontainer -- nix-shell -p hello --run hello

# View container logs
incus console mycontainer

# Container resource usage
incus info mycontainer
```

## Configuration changes

After modifying Colima settings in `configurations/darwin/stibnite.nix`:

```bash
# 1. Rebuild system (applies changes to module, doesn't restart VM)
darwin-rebuild switch --flake .#stibnite

# 2. Restart Colima to apply changes to the running VM
colima-restart
```

Configuration changes requiring VM restart:
- CPU, memory, or disk allocation
- Architecture or VM type
- Mount type
- Rosetta setting

The activation script will remind you to restart after configuration changes.

## Using docker runtime (alternative)

If you prefer Docker-compatible workflows, you can switch to the Docker runtime:

```nix
# In configurations/darwin/stibnite.nix
services.colima = {
  runtime = "docker";  # Change from "incus"
  # ... other settings
};
```

After rebuilding and restarting:

```bash
darwin-rebuild switch --flake .#stibnite
colima-restart

# Now use Docker commands
docker run -it nixos/nix
docker ps
docker compose up
```

The `DOCKER_HOST` environment variable is automatically configured to point to the Colima socket:

```bash
echo $DOCKER_HOST
# unix:///Users/user/.colima/default/docker.sock
```

### Legacy tools requiring /var/run/docker.sock

Modern Docker tools respect `DOCKER_HOST`.
For legacy tools that hardcode `/var/run/docker.sock`, create a symlink manually:

```bash
sudo ln -sf ~/.colima/default/docker.sock /var/run/docker.sock
```

Note: This requires `sudo` and is not managed by the nix-darwin module to avoid privilege escalation during system activation.

## Managing additional profiles

The nix-darwin module manages a single primary profile (default: "default").
You can manually create additional profiles for different use cases:

```bash
# Create a Docker profile for Docker workflows
colima start --profile docker --runtime docker --cpu 2 --memory 2

# Create an x86_64 profile for compatibility testing
colima start --profile x86 --arch x86_64 --runtime docker --cpu 2 --memory 4

# List all profiles
colima list

# Switch between profiles
colima stop --profile default
colima start --profile docker

# Delete a profile
colima delete --profile x86
```

Additional profiles are not declared in your system configuration but work fine alongside the managed profile.

## Comparison with nix-rosetta-builder

| Feature         | nix-rosetta-builder     | Colima                    |
|-----------------|-------------------------|---------------------------|
| Purpose         | Nix package builds      | OCI containers            |
| Use case        | nix build               | incus launch / docker run |
| Auto-configured | Yes (as remote builder) | Manual runtime            |
| Boot time       | ~10-15s                 | ~15-20s                   |
| Resources       | 8 cores, 6GB RAM        | 4 cores, 4GB RAM          |
| Primary use     | nixpkgs development     | Container workloads       |

Both can run simultaneously with different resource profiles.
They use separate VMs and don't interfere with each other.

## Troubleshooting

### Colima won't start

Check the logs for errors:

```bash
cat /tmp/colima-default.err.log
cat /tmp/colima-default.out.log
```

Common issues:
- Port conflicts (another VM using the same ports)
- Insufficient disk space
- macOS Virtualization.framework issues (try `vmType = "qemu"`)

Clean state and retry:

```bash
colima delete --profile default
colima-init
```

### Can't connect to incus

Verify Colima is running:

```bash
colima status
```

Check Incus socket exists:

```bash
ls -la ~/.colima/default/incus.sock
```

If Incus remote is misconfigured:

```bash
# Colima should configure this automatically, but you can verify:
incus remote list

# If the remote is missing, Colima may need to be restarted
colima-restart
```

### Resource conflicts

If both nix-rosetta-builder and Colima consume too many resources:

1. Adjust allocations in `configurations/darwin/stibnite.nix`
2. Enable `onDemand` for nix-rosetta-builder (already enabled)
3. Keep Colima stopped when not needed (`autoStart = false`)

### Shell completions not working

Completions are loaded dynamically during shell initialization.
Verify zsh or bash is enabled at the darwin level:

```bash
# Check if completion function is loaded
type _colima 2>/dev/null || echo "Not loaded"

# Reload shell configuration
exec $SHELL
```

## Advanced usage

### Nested virtualization

On Apple Silicon M3 and later, Incus supports nested virtualization:

```bash
# Launch a VM (not a container)
incus launch images:ubuntu/24.04 myvm --vm

# VMs provide full kernel isolation and can run Docker/Kubernetes
incus exec myvm -- docker run hello-world
```

### Volume mounts

Colima automatically mounts your home directory.
Access macOS files from containers:

```bash
# List mounts
colima list --json | jq '.[0].mounts'

# Files in your home directory are accessible
incus launch images:nixos/unstable builder
incus exec builder -- ls ~/
```

### Custom runtime configuration

For advanced Incus configuration, edit the runtime config inside the VM:

```bash
colima ssh
sudo incus config edit <container-name>
```

## References

- [Colima documentation](https://github.com/abiosoft/colima)
- [Incus documentation](https://linuxcontainers.org/incus/docs/main/)
- [Incus installation guide](https://linuxcontainers.org/incus/docs/main/installing/)
- [Lima documentation](https://lima-vm.io/)
- nixpkgs packages: `pkgs.colima`, `pkgs.docker`
- Homebrew formulas: `incus` (macOS client only)
- Architecture analysis: See evaluation comparing container runtimes

## Module options

See `modules/darwin/colima.nix` for all available options:

```nix
services.colima = {
  enable = true;
  runtime = "incus" | "docker" | "containerd";
  profile = "default";
  autoStart = false;
  cpu = 4;
  memory = 4;  # GiB
  disk = 60;   # GiB
  arch = "aarch64" | "x86_64";
  vmType = "vz" | "qemu";
  rosetta = true;
  mountType = "virtiofs" | "sshfs" | "9p";
  extraPackages = [ ];
};
```

Modify these in your host configuration (`configurations/darwin/stibnite.nix`), then rebuild and restart.
