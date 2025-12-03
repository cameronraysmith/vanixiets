---
title: Multi-Arch Container Builds
sidebar:
  order: 10
---

This configuration enables building multi-architecture (aarch64-linux and x86_64-linux) container images on Darwin using flocken and nix-rosetta-builder.

## Architecture

- **flocken**: Creates multi-arch Docker manifests from image files
- **nix-rosetta-builder**: Provides Linux build capability on Darwin
  - Native aarch64-linux builds on Apple Silicon
  - Fast x86_64-linux builds via Rosetta 2 emulation
- **Container pattern**: Simple tool containers that work like `nix shell`

## Initial setup

The nix-rosetta-builder VM image is automatically fetched from the `cameronraysmith.cachix.org` cache during system build.
No manual bootstrap process is required thanks to `nixConfig` in the flake.

If you're setting up on a fresh machine:

```bash
cd [PATH TO THIS REPO]
just activate --ask
```

The VM image (~2GB) will be downloaded from cache automatically.
This is much faster than building it locally (~10-20 minutes).

## Maintaining the cache

The nix-rosetta-builder VM image is cached in Cachix via `nixConfig` in the flake.
This enables automatic cache fetching during system builds.

### When to update the cache

Update the cached image when:

1. **After updating the nix-rosetta-builder flake input:**
   ```bash
   nix flake lock --update-input nix-rosetta-builder
   darwin-rebuild switch
   just cache-rosetta-builder
   ```

2. **After changing nix-rosetta-builder module configuration** in `configurations/darwin/stibnite.nix`:
   ```bash
   # Edit configuration (onDemand, cores, memory, etc.)
   darwin-rebuild switch
   just cache-rosetta-builder
   ```

3. **When upstream changes affect the image** (detected during flake updates)

Note: nix-config nixpkgs updates do NOT require cache updates.
The VM uses pinned nixpkgs (`e9f00bd8`) and evolves independently from system updates.

### Checking cache status

Verify if your current system's image is cached:

```bash
just check-rosetta-cache
```

This is useful before pushing commits that update nix-rosetta-builder.

### Automatic cache updates

The image is automatically cached after system builds via the `cache-rosetta-builder` recipe.
Run it manually after configuration changes to ensure the cache is up-to-date for other machines and CI.

## Building containers

### Three workflows for different use cases

**1. Single-arch (default - fastest for local testing)**

Auto-detects your native Linux architecture:

```bash
just container-all fdContainer fd
just container-all rgContainer rg
```

Or specify an architecture explicitly:

```bash
just container-all fdContainer fd x86_64-linux
```

Atomic steps:

```bash
just build-container fdContainer        # Auto-detects native arch
just build-container fdContainer aarch64-linux  # Explicit arch
just load-container
just test-container fd
```

**2. Multi-arch local validation (recommended for pre-registry testing)**

Build both aarch64-linux and x86_64-linux, load native arch only:

```bash
just container-all-multiarch fdContainer fd
just container-all-multiarch rgContainer rg
```

This proves both architectures build successfully before pushing to registry.

Atomic steps:

```bash
just build-multiarch fdContainer    # Builds both, outputs result-aarch64-linux and result-x86_64-linux
just load-native                    # Loads native arch from result-{arch}
just test-container fd
```

**3. Manifest workflow (CI/CD registry distribution)**

The `fdManifest` and `rgManifest` definitions use flocken to create multi-arch manifests for pushing to container registries. These require registry configuration (see `modules/flake-parts/containers.nix`).

For local multi-arch testing, use workflow #2 above instead.

Example manifest definition:
```nix
fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
  version = "latest";
  imageFiles = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
  registries = {
    "ghcr.io" = {
      username = "your-username";
      repo = "your-repo";
    };
  };
  tags = [ "latest" ];
};
```

Once configured:
```bash
nix run --impure .#fdManifest  # Builds + pushes to configured registries
nix run --impure .#rgManifest
```

### Architecture auto-detection

The justfile recipes automatically detect your host architecture and map it to the corresponding Linux target:

- **aarch64-darwin or aarch64-linux** → builds `aarch64-linux` containers
- **x86_64-darwin or x86_64-linux** → builds `x86_64-linux` containers

This means `just container-all fdContainer fd` does the right thing on any platform.

### Manual nix commands (advanced)

If you prefer to use nix commands directly:

```bash
# Single architecture
nix build '.#packages.aarch64-linux.fdContainer'
docker load < result
docker run --rm fd:latest --help

# Multi-arch manifest
nix run --impure .#fdManifest
nix run --impure .#rgManifest
```

Note: Never use `--system aarch64-linux` flag - it causes nix to attempt local execution instead of delegating to the builder. Always use the explicit flake path syntax.

## VM configuration

The nix-rosetta-builder VM is configured with:
- **onDemand**: Powers off when idle to save resources
- **cores**: 8 CPU cores
- **memory**: 6GiB RAM
- **diskSize**: 100GiB disk

## Adding new containers

To add a new tool container, edit `modules/flake-parts/containers.nix`:

**1. Add the container package:**

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
```

**2. Add the manifest (optional, for multi-arch registry distribution):**

```nix
legacyPackages = {
  fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
    version = "latest";
    imageFiles = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
    registries = { };
    tags = [ "latest" ];
  };

  rgManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
    version = "latest";
    imageFiles = map (sys: inputs.self.packages.${sys}.rgContainer) imageSystems;
    registries = { };
    tags = [ "latest" ];
  };

  myToolManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
    version = "latest";
    imageFiles = map (sys: inputs.self.packages.${sys}.myToolContainer) imageSystems;
    registries = { };
    tags = [ "latest" ];
  };
};
```

**3. Use the justfile workflows:**

```bash
# Single-arch (fast local testing)
just container-all myToolContainer mytool

# Multi-arch local validation
just container-all-multiarch myToolContainer mytool
```

**4. (Optional) Configure manifest for CI/CD registry push:**

Add registry configuration to the manifest definition and use in CI/CD pipelines.

## Container management with Colima

This setup focuses on **building** container images using nix-rosetta-builder.
For **running** and **managing** OCI containers, see the complementary Colima configuration.

### Complementary usage

- **nix-rosetta-builder** (this document): Build Linux binaries and container images from Nix expressions
- **Colima** (see [colima-container-management.md](./colima-container-management.md)): Run and manage OCI containers with Incus or Docker runtime

Both can run simultaneously:
- nix-rosetta-builder: 8 cores, 6GB RAM (on-demand)
- Colima: 4 cores, 4GB RAM (manual control)

### Example workflow

Build a container image with nix-rosetta-builder, then run it with Colima:

```bash
# Build container using nix-rosetta-builder
just container-all fdContainer fd

# Load into Colima's Docker runtime
# (requires services.colima.runtime = "docker")
docker load < result
docker run --rm fd:latest --help
```

Or use Incus for system containers:

```bash
# Launch a NixOS container with Colima's Incus runtime
incus launch images:nixos/unstable builder

# Use nix inside the container
incus exec builder -- nix shell nixpkgs#fd -c fd --help
```

For full Colima usage guide, see [colima-container-management.md](./colima-container-management.md).

## Notes

- Container images build on the Linux builder (via remote build)
- Manifest creation coordinates from Darwin
- Images are minimal: tool binary + bash + coreutils
- No registry push configured (local testing only)
