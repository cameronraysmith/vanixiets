# Multi-arch container builds with flocken and nix-rosetta-builder

This configuration enables building multi-architecture (aarch64-linux and x86_64-linux) container images on Darwin using flocken and nix-rosetta-builder.

## Architecture

- **flocken**: Creates multi-arch Docker manifests from image files
- **nix-rosetta-builder**: Provides Linux build capability on Darwin
  - Native aarch64-linux builds on Apple Silicon
  - Fast x86_64-linux builds via Rosetta 2 emulation
- **Container pattern**: Simple tool containers that work like `nix shell`

## Initial bootstrap

nix-rosetta-builder requires an existing Linux builder for initial setup because the VM image itself is a Linux derivation that must be built on Linux (chicken-and-egg problem).

### Why the bootstrap is necessary

The nix-rosetta-builder package is defined as:
```nix
packages."aarch64-linux".image = pkgs.callPackage ./package.nix { ... };
```

This is a Linux package that must be built on Linux, but nix-rosetta-builder **is** the Linux builder you're trying to create. The toggle sequence uses nix-darwin's built-in `linux-builder` (which can bootstrap from NixOS cache) to build the nix-rosetta-builder VM image.

### Required: Two-step bootstrap process

The configuration must be activated in two separate rebuilds:

**Step 1: Build linux-builder (bootstrap)**

In `configurations/darwin/stibnite.nix`:
```nix
imports = [
  self.darwinModules.default
  # Comment out nix-rosetta-builder import - it evaluates Linux packages!
  # inputs.nix-rosetta-builder.darwinModules.default
];

nix.linux-builder = {
  enable = true;
  config.virtualisation = {
    cores = lib.mkForce 4;         # default: 1 (increase for faster builds)
    memorySize = lib.mkForce 6144; # default: 3GB
    diskSize = lib.mkForce 40960;  # default: 20GB
  };
};

# nix-rosetta-builder config commented out
```

Run `darwin-rebuild switch`

**Step 2: Switch to nix-rosetta-builder**

Update `configurations/darwin/stibnite.nix`:
```nix
imports = [
  self.darwinModules.default
  inputs.nix-rosetta-builder.darwinModules.default  # Uncomment!
];

nix.linux-builder.enable = false;  # Disable bootstrap builder

nix-rosetta-builder = {
  enable = true;
  onDemand = true;
  cores = 8;
  memory = "6GiB";
  diskSize = "100GiB";
};
```

Run `darwin-rebuild switch` again

**Critical**: The nix-rosetta-builder module import must be commented out in step 1 because importing it evaluates the Linux VM image package, which requires a Linux builder to build.

### Alternative: Remote builder

If you have access to another Linux builder (cloud instance, remote server), configure it in `nix.buildMachines` before enabling nix-rosetta-builder to avoid the toggle entirely.

### Why not use Lima directly?

Lima is just a VM hypervisor. nix-rosetta-builder uses Lima internally but adds:
- Nix remote builder configuration
- SSH key management
- Rosetta 2 integration
- Automatic builder registration

## Caching to avoid rebuilds

After system updates that change nixpkgs, the nix-rosetta-builder VM image may need rebuilding. Cache it to avoid rebuilding multiple times:

```bash
just cache-rosetta-builder
```

This command:
- Automatically finds the VM image in your current system
- Pushes it to your Cachix cache (~2GB upload)
- Makes it available for future builds and CI

Run this after `darwin-rebuild switch` when nixpkgs updates.

## Building containers

### Using justfile recipes (recommended)

Build, load, and test a container in one command:

```bash
just container-all fdContainer fd
just container-all rgContainer rg
```

Or use individual steps:

```bash
just build-container fdContainer
just load-container
just test-container fd
```

The recipes support different architectures (defaults to aarch64-linux):

```bash
just build-container fdContainer x86_64-linux
```

### Build multi-arch manifest

```bash
cd /Users/crs58/projects/nix-workspace/nix-config
nix run --impure .#fdManifest
```

This builds both aarch64-linux and x86_64-linux images via nix-rosetta-builder.

### Build single architecture (manual)

Use the proper flake path syntax (not --system flag):

```bash
nix build '.#packages.aarch64-linux.fdContainer'
```

Note: The `--system aarch64-linux` flag is known to cause issues where nix attempts local execution instead of delegating to the builder. Always use the explicit flake path syntax.

### Load and test (manual)

```bash
nix build '.#packages.aarch64-linux.fdContainer'
docker load < result
docker run fd:latest --help
```

## VM configuration

The nix-rosetta-builder VM is configured with:
- **onDemand**: Powers off when idle to save resources
- **cores**: 8 CPU cores
- **memory**: 6GiB RAM
- **diskSize**: 100GiB disk

## Adding new containers

To add a new tool container, edit `modules/flake-parts/containers.nix`:

```nix
packages = lib.optionalAttrs isLinux {
  fdContainer = mkToolContainer {
    name = "fd";
    package = pkgs.fd;
  };

  rgContainer = mkToolContainer {
    name = "rg";
    package = pkgs.ripgrep;  # Note: package name != binary name
  };

  myToolContainer = mkToolContainer {
    name = "mytool";
    package = pkgs.mytool;
  };
};

legacyPackages = {
  myToolManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
    version = "latest";
    imageFiles = map (sys: inputs.self.packages.${sys}.myToolContainer) imageSystems;
    registries = { };
    tags = [ "latest" ];
  };
};
```

Then use the justfile recipes:

```bash
just container-all myToolContainer mytool
```

## Notes

- Container images build on the Linux builder (via remote build)
- Manifest creation coordinates from Darwin
- Images are minimal: tool binary + bash + coreutils
- No registry push configured (local testing only)
