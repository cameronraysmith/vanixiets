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

### Recommended: Concurrent enable with single toggle

This approach runs both builders simultaneously during the first switch, then disables the built-in one:

1. In `configurations/darwin/stibnite.nix`, enable both:
   ```nix
   nix.linux-builder.enable = true;  # Temporary bootstrap

   nix-rosetta-builder = {
     enable = true;
     onDemand = true;
     cores = 8;
     memory = "6GiB";
     diskSize = "100GiB";
   };
   ```

2. Run `darwin-rebuild switch` (builds nix-rosetta-builder using linux-builder)

3. Disable the built-in builder:
   ```nix
   nix.linux-builder.enable = false;
   # nix-rosetta-builder stays enabled
   ```

4. Run `darwin-rebuild switch` again (now using nix-rosetta-builder)

### Alternative: Remote builder

If you have access to another Linux builder (cloud instance, remote server), configure it in `nix.buildMachines` before enabling nix-rosetta-builder to avoid the toggle entirely.

### Why not use Lima directly?

Lima is just a VM hypervisor. nix-rosetta-builder uses Lima internally but adds:
- Nix remote builder configuration
- SSH key management
- Rosetta 2 integration
- Automatic builder registration

## Building containers

### Build multi-arch manifest

```bash
cd /Users/crs58/projects/nix-workspace/nix-config
nix run --impure .#fdManifest
```

This builds both aarch64-linux and x86_64-linux images via nix-rosetta-builder.

### Build single architecture

```bash
nix build .#fdContainer --system aarch64-linux
```

### Load and test

```bash
nix build .#fdContainer --system aarch64-linux
docker load < result
docker run fd:latest --version
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

## Notes

- Container images build on the Linux builder (via remote build)
- Manifest creation coordinates from Darwin
- Images are minimal: tool binary + bash + coreutils
- No registry push configured (local testing only)
