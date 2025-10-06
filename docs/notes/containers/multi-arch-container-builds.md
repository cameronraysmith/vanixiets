# Multi-arch container builds with flocken and nix-rosetta-builder

This configuration enables building multi-architecture (aarch64-linux and x86_64-linux) container images on Darwin using flocken and nix-rosetta-builder.

## Architecture

- **flocken**: Creates multi-arch Docker manifests from image files
- **nix-rosetta-builder**: Provides Linux build capability on Darwin
  - Native aarch64-linux builds on Apple Silicon
  - Fast x86_64-linux builds via Rosetta 2 emulation
- **Container pattern**: Simple tool containers that work like `nix shell`

## Initial bootstrap

nix-rosetta-builder requires an existing Linux builder for initial setup.

### Option 1: Temporary built-in linux-builder

1. Comment out nix-rosetta-builder in `configurations/darwin/stibnite.nix`:
   ```nix
   # nix-rosetta-builder = {
   #   enable = true;
   #   ...
   # };
   ```

2. Enable the built-in builder:
   ```nix
   nix.linux-builder.enable = true;
   ```

3. Run `darwin-rebuild switch`

4. Uncomment nix-rosetta-builder, remove linux-builder config

5. Run `darwin-rebuild switch` again

### Option 2: Remote builder

If you have access to another Linux builder, configure it in `nix.buildMachines` before enabling nix-rosetta-builder.

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
