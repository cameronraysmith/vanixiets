# Container build refactoring: dockerTools to nix2container

This plan describes refactoring `~/projects/nix-workspace/infra/modules/containers/default.nix` from `dockerTools.buildLayeredImage` to `nix2container.buildImage` for optimal build and push performance while retaining flocken for multi-arch manifest publishing.

## Problem statement

The current implementation at `~/projects/nix-workspace/infra/modules/containers/default.nix:24` uses `pkgs.dockerTools.buildLayeredImage` with three inefficiencies:

1. **Store duplication**: Layer tarballs written to Nix store duplicate existing store paths (~2x storage overhead)
2. **Monolithic rebuilds**: Any layer change rebuilds the entire OCI archive
3. **Full re-push**: Complete image pushed to registry even when only one layer changed

## Target architecture

Replace `dockerTools.buildLayeredImage` with `nix2container.buildImage` while retaining flocken's `mkDockerManifest` for multi-arch ghcr publishing.

**Performance characteristics:**

| Metric | dockerTools.buildLayeredImage | nix2container.buildImage |
|--------|-------------------------------|--------------------------|
| Build time | O(image size) | O(manifest size) |
| Store space | O(image size) - full tarballs | O(manifest size) - JSON only |
| Push time | O(image size) - full archive | O(changed layers) - incremental |
| Rebuild speed | ~10s (per benchmark) | ~1.8s (per benchmark) |

## Implementation plan

### Phase 1: Add nix2container flake input

Add nix2container to flake inputs in `~/projects/nix-workspace/infra/flake.nix`:

```nix
inputs = {
  # ... existing inputs ...
  nix2container.url = "github:nlewo/nix2container";
  nix2container.inputs.nixpkgs.follows = "nixpkgs";
};
```

Expose nix2container in perSystem via flake-parts:

```nix
perSystem = { pkgs, system, ... }: {
  _module.args.nix2container = inputs.nix2container.packages.${system}.nix2container;
};
```

### Phase 2: Refactor mkToolContainer function

Replace the current implementation at `~/projects/nix-workspace/infra/modules/containers/default.nix:18-41` with nix2container.buildImage.

**Current implementation:**
```nix
mkToolContainer = { name, package, tag ? "latest" }:
  pkgs.dockerTools.buildLayeredImage {
    inherit name tag;
    contents = [ pkgs.bashInteractive pkgs.coreutils package ];
    config = {
      Entrypoint = [ "${package}/bin/${name}" ];
      Env = [ "PATH=${package}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin" ];
      Labels = { /* ... */ };
    };
  };
```

**New implementation:**
```nix
mkToolContainer = { name, package, tag ? "latest" }:
  let
    # Separate base layer for stable packages (bash, coreutils)
    # These rarely change and will be cached across tool containers
    baseLayer = nix2container.buildLayer {
      deps = [ pkgs.bashInteractive pkgs.coreutils ];
    };
  in
  nix2container.buildImage {
    inherit name tag;

    # Explicit layer separation: base packages cached, tool package in top layer
    layers = [ baseLayer ];

    # Tool package goes in the main image layer
    copyToRoot = pkgs.buildEnv {
      name = "root";
      paths = [ package ];
      pathsToLink = [ "/bin" ];
    };

    # OCI ImageConfig (note: nix2container uses lowercase keys)
    config = {
      entrypoint = [ "${package}/bin/${name}" ];
      Env = [
        "PATH=${package}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin"
      ];
      Labels = {
        "org.opencontainers.image.description" = "Minimal container with ${name}";
        "org.opencontainers.image.source" = "https://github.com/cameronraysmith/infra";
      };
    };

    # Further split main layer if beneficial (popularity-based)
    maxLayers = 2;
  };
```

**Key changes:**
- `contents` → `copyToRoot` with `pkgs.buildEnv` for store path stripping
- Added explicit `layers` with `buildLayer` for base package isolation
- Config keys: `Entrypoint` → `entrypoint` (nix2container uses camelCase)
- Added `maxLayers = 2` for popularity-based layer optimization

### Phase 3: Update flocken manifest builders

Replace `imageFiles` with `imageStreams` in the manifest definitions at `~/projects/nix-workspace/infra/modules/containers/default.nix:86-106`.

**Current implementation:**
```nix
fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
  version = getEnvOr "VERSION" "1.0.0";
  branch = getEnvOr "GITHUB_REF_NAME" "main";
  imageFiles = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
  registries."ghcr.io" = { /* ... */ };
};
```

**New implementation:**
```nix
fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
  version = getEnvOr "VERSION" "1.0.0";
  branch = getEnvOr "GITHUB_REF_NAME" "main";
  # nix2container produces streaming outputs compatible with imageStreams
  imageStreams = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
  registries."ghcr.io" = {
    repo = "cameronraysmith/fd";
    username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
    password = "$GITHUB_TOKEN";
  };
};
```

**How imageStreams works:**
1. nix2container.buildImage produces a derivation that outputs a tar stream when executed
2. flocken's mkDockerManifest invokes each imageStream, pipes through gzip to tmpdir
3. podman manifest add reads the temporary archives
4. Temporary files cleaned up at exit

### Phase 4: Add copyToRegistry passthru for development workflow

Add a development convenience for single-arch push without flocken (useful for rapid iteration).

Modify the container output to expose copyToRegistry directly:

```nix
mkToolContainer = { name, package, tag ? "latest" }:
  let
    baseLayer = nix2container.buildLayer { /* ... */ };
    image = nix2container.buildImage { /* ... */ };
  in
  image // {
    # Preserve nix2container passthrus for development use
    # Usage: nix run .#fdContainer.copyToRegistry
    # Or: nix run .#fdContainer.copyToDockerDaemon
    passthru = image.passthru // {
      # Additional convenience: direct skopeo push with auth
      pushToGhcr = pkgs.writeShellScript "push-to-ghcr" ''
        ${image.passthru.copyToRegistry}/bin/copy-to-registry \
          --dest-creds "$GITHUB_ACTOR:$GITHUB_TOKEN"
      '';
    };
  };
```

**Development workflow:**
```bash
# Single-arch local testing (fast iteration)
nix run .#fdContainer.copyToDockerDaemon
docker run --rm fd:latest --help

# Single-arch push (development)
GITHUB_TOKEN=xxx nix run .#fdContainer.copyToRegistry

# Multi-arch manifest (CI/CD)
VERSION=1.0.0 nix run --impure .#fdManifest
```

### Phase 5: Update documentation

Update `~/projects/nix-workspace/infra/packages/docs/src/content/docs/about/contributing/multi-arch-containers.md` to reflect the new approach.

**Sections to update:**

1. **Architecture section** - Add nix2container to the stack:
   - nix2container: Deferred tar creation, pre-computed digests, incremental push
   - flocken: Multi-arch manifest creation from nix2container streams
   - nix-rosetta-builder: Cross-architecture builds on Darwin

2. **Building containers section** - Update workflow descriptions:
   - Explain that builds now produce JSON manifests, not tarballs
   - Document copyToDockerDaemon passthru for local testing
   - Note that unchanged layers skip re-push

3. **Adding new containers section** - Update code examples with new API

4. **Performance section** (new) - Document the efficiency gains:
   - Build time: JSON manifest generation only (~1.8s vs ~10s)
   - Store space: No tarball duplication
   - Push time: Only changed layers transferred
   - Layer caching: Base packages shared across tool containers

5. **Future options section** (new) - Document alternative approaches:
   - nix-snapshotter: CRI-layer for containerd on NixOS hosts
   - nix-csi: CSI-layer for Kubernetes volume provisioning

### Phase 6: Add inline documentation comments

Add explanatory comments to the refactored module explaining performance characteristics.

```nix
# Multi-architecture container builds using nix2container and flocken
#
# Architecture:
# - nix2container: Builds JSON manifests with pre-computed layer digests
#   No tarballs written to Nix store; layers synthesized at push time
# - flocken: Creates multi-arch Docker manifests from nix2container streams
#
# Performance characteristics:
# - Build time: O(manifest size) - JSON generation only, no tar creation
# - Store space: O(manifest size) - no layer tarball duplication
# - Push time: O(changed layers) - skopeo skips unchanged layers by digest
#
# Layer strategy:
# - Base layer (bash, coreutils): Shared across all tool containers
# - Tool layer: Package-specific, isolated for independent caching
#
# Development workflow:
# - Single-arch local: nix run .#fdContainer.copyToDockerDaemon
# - Single-arch push: nix run .#fdContainer.copyToRegistry
# - Multi-arch manifest: nix run --impure .#fdManifest
```

## Complete refactored module

The complete refactored `~/projects/nix-workspace/infra/modules/containers/default.nix`:

```nix
# Multi-architecture container builds using nix2container and flocken
#
# This module provides:
# - Container packages (fdContainer, rgContainer) for Linux systems
# - Multi-arch manifests (fdManifest, rgManifest) for CI/CD registry distribution
#
# Architecture:
# - nix2container: Builds JSON manifests with pre-computed layer digests
#   No tarballs written to Nix store; layers synthesized at push time by patched skopeo
# - flocken: Creates multi-arch Docker manifests from nix2container streams
#
# Performance characteristics:
# - Build time: O(manifest size) - JSON generation only, no tar creation
# - Store space: O(manifest size) - no layer tarball duplication
# - Push time: O(changed layers) - skopeo skips unchanged layers by digest
#
# See docs/about/contributing/multi-arch-containers.md for usage guide.
{ inputs, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      isLinux = lib.hasSuffix "-linux" system;
      isDarwin = lib.hasSuffix "-darwin" system;

      # Get nix2container for this system
      nix2container = inputs.nix2container.packages.${system}.nix2container;

      # Shared base layer: bash and coreutils
      # This layer is reused across all tool containers, maximizing cache hits
      baseLayer = nix2container.buildLayer {
        deps = [
          pkgs.bashInteractive
          pkgs.coreutils
        ];
      };

      # Build a minimal container image with a package
      # Makes it work like: docker run <name>:latest --version
      #
      # Layer strategy:
      # - Layer 0: baseLayer (bash, coreutils) - rarely changes, shared
      # - Layer 1: tool package - changes independently per tool
      #
      # Development workflow:
      # - Local test: nix run .#fdContainer.copyToDockerDaemon && docker run fd
      # - Single push: nix run .#fdContainer.copyToRegistry
      # - Multi-arch: nix run --impure .#fdManifest
      mkToolContainer =
        {
          name,
          package,
          tag ? "latest",
        }:
        nix2container.buildImage {
          inherit name tag;

          # Explicit layers: base packages in shared layer
          layers = [ baseLayer ];

          # Tool package in main image layer (copyToRoot strips /nix/store prefix)
          copyToRoot = pkgs.buildEnv {
            name = "root";
            paths = [ package ];
            pathsToLink = [ "/bin" ];
          };

          config = {
            entrypoint = [ "${package}/bin/${name}" ];
            Env = [
              "PATH=${package}/bin:${pkgs.coreutils}/bin:${pkgs.bashInteractive}/bin"
            ];
            Labels = {
              "org.opencontainers.image.description" = "Minimal container with ${name}";
              "org.opencontainers.image.source" = "https://github.com/cameronraysmith/infra";
            };
          };

          # Further split customization layer by popularity if beneficial
          maxLayers = 2;
        };

      # Systems to build images for (both architectures)
      imageSystems = [
        "x86_64-linux"
        "aarch64-linux"
      ];
    in
    {
      # Container packages - Linux only (built via nix-rosetta-builder on Darwin)
      # Manifests available on all systems for CI/CD coordination
      # Use lib.mkMerge to properly merge with pkgs-by-name packages
      packages = lib.mkMerge [
        # Container images - Linux only
        (lib.optionalAttrs isLinux {
          fdContainer = mkToolContainer {
            name = "fd";
            package = pkgs.fd;
          };

          rgContainer = mkToolContainer {
            name = "rg";
            package = pkgs.ripgrep;
          };
        })

        # Multi-arch manifests for CI/CD registry distribution
        # Darwin-only: requires nix-rosetta-builder to build both Linux architectures
        # Usage: nix run --impure .#fdManifest
        # Requires: GITHUB_TOKEN environment variable in CI
        #
        # Note: Manifests are Darwin-only because they depend on both x86_64-linux
        # and aarch64-linux container images. Darwin hosts with nix-rosetta-builder
        # can build both, but single-arch Linux CI runners cannot.
        (lib.optionalAttrs isDarwin (
          let
            # Helper to get env var with fallback (requires --impure for actual env var reading)
            getEnvOr =
              var: default:
              let
                val = builtins.getEnv var;
              in
              if val == "" then default else val;
          in
          {
            fdManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
              version = getEnvOr "VERSION" "1.0.0";
              branch = getEnvOr "GITHUB_REF_NAME" "main";
              # nix2container images produce streaming outputs for flocken
              imageStreams = map (sys: inputs.self.packages.${sys}.fdContainer) imageSystems;
              registries."ghcr.io" = {
                repo = "cameronraysmith/fd";
                username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
                password = "$GITHUB_TOKEN";
              };
            };

            rgManifest = inputs.flocken.legacyPackages.${system}.mkDockerManifest {
              version = getEnvOr "VERSION" "1.0.0";
              branch = getEnvOr "GITHUB_REF_NAME" "main";
              imageStreams = map (sys: inputs.self.packages.${sys}.rgContainer) imageSystems;
              registries."ghcr.io" = {
                repo = "cameronraysmith/rg";
                username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
                password = "$GITHUB_TOKEN";
              };
            };
          }
        ))
      ];
    };
}
```

## Verification checklist

After implementation, verify:

1. **Build succeeds**: `nix build .#fdContainer` produces JSON manifest (not tarball)
2. **Local load works**: `nix run .#fdContainer.copyToDockerDaemon && docker run fd`
3. **Single-arch push**: `nix run .#fdContainer.copyToRegistry` (requires auth)
4. **Multi-arch manifest**: `VERSION=test nix run --impure .#fdManifest` (requires auth)
5. **Layer caching**: Second build of different tool reuses baseLayer
6. **Store efficiency**: Check that no large tarballs appear in store for container builds

## Future enhancements

### nix-snapshotter integration (NixOS deployments)

For NixOS hosts running containerd, nix-snapshotter eliminates registry entirely:

```nix
# Reference: ~/projects/sciops-workspace/nix-snapshotter
image = nix-snapshotter.buildImage {
  name = "my-tool";
  resolvedByNix = true;  # Image resolved via nix-snapshotter, not registry
  config.entrypoint = [ "${pkgs.mytool}/bin/mytool" ];
};

# Pod spec uses nix: prefix
# image: nix:0/nix/store/abc123-my-tool
```

**When to use:** NixOS cluster nodes with direct Nix store access, where bypassing registry eliminates network overhead entirely.

### nix-csi integration (Kubernetes volumes)

For Kubernetes workloads needing Nix-derived volume content:

```nix
# Reference: ~/projects/sciops-workspace/nix-csi
# StorageClass: provisioner: nix.csi.store
# PersistentVolumeClaim with nix expression attribute
```

**When to use:** Kubernetes workloads where volume content should be computed from Nix expressions rather than pre-built images.

## Reference repositories

- **nix2container**: `~/projects/nix-workspace/nix2container` - Build-time optimization source
- **flocken**: `~/projects/nix-workspace/flocken` - Multi-arch manifest publishing
- **nixpod-home**: `~/projects/nix-workspace/nixpod-home` - Complex container build patterns
- **nix-snapshotter**: `~/projects/sciops-workspace/nix-snapshotter` - CRI-layer optimization
- **nix-csi**: `~/projects/sciops-workspace/nix-csi` - CSI-layer for Kubernetes
