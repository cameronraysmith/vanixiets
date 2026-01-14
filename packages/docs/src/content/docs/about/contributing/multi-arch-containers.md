---
title: Multi-Arch Container Builds
sidebar:
  order: 10
---

This configuration builds multi-architecture (x86_64-linux and aarch64-linux) container images using nix2container with pkgsCross for cross-compilation.

## Architecture

The container build system uses a modern Nix-native approach that eliminates the need for QEMU emulation or Docker-based manifest creation.

**nix2container** builds container images as JSON manifests with pre-computed layer digests instead of traditional tarballs.
This enables direct pushing to registries via the nix: transport without intermediate Docker daemon loading.

**pkgsCross** provides cross-compilation at native speed.
An x86_64 host can build aarch64 binaries through cross-compilation rather than emulation, making multi-architecture builds practical on standard CI runners.

**skopeo** with nix: transport pushes images directly from the Nix store to container registries without creating intermediate tarballs or loading into Docker.

**crane** creates multi-architecture manifest lists by referencing already-pushed per-architecture images, then applies additional tags through server-side operations that avoid re-uploading image data.

The containerMatrix flake output provides structured data for CI to discover which containers and architectures to build without hardcoding matrix values in workflow files.

## Platform behavior

The system adapts to the host platform:

On x86_64-linux hosts, x86_64 containers build natively while aarch64 containers are cross-compiled.
On aarch64-linux hosts, aarch64 containers build natively while x86_64 containers are cross-compiled.
On aarch64-darwin hosts, both architectures require remote Linux builds (see nix-rosetta-builder section below).

CI uses ubuntu-latest (x86_64) runners and builds both architectures through a combination of native and cross-compilation.

## Building containers locally

The justfile provides recipes for common container operations.

### Single container, single architecture

Build a specific container for one target architecture:

```bash
just container-build fd x86_64
just container-build fd aarch64
just container-build rg x86_64
```

Load the container into your local Docker daemon and test it:

```bash
just container-load fd aarch64
just container-test fd
```

Complete workflow in one command:

```bash
just container-all fd "" aarch64
just container-all rg "" x86_64
```

The empty string in the second parameter uses the container name as the binary name.
Use this parameter when the binary name differs from the container name.

### Single container, both architectures

Build both x86_64 and aarch64 variants of a container:

```bash
just container-build-all fd
just container-build-all rg
```

This creates `result-x86_64` and `result-aarch64` symlinks in the current directory.

Verify the architecture metadata in the built containers:

```bash
just container-verify fd x86_64
just container-verify fd aarch64
```

### All containers

Build every defined container for both architectures:

```bash
just container-build-all-defs
```

View the container matrix that CI uses for dynamic job generation:

```bash
just container-matrix
```

This shows the same JSON structure that the discover job in `.github/workflows/containers.yaml` evaluates.

### Pushing to registry

Push a multi-architecture manifest list to the container registry:

```bash
just container-push fd 1.0.0
just container-push fd 1.0.0 "latest,stable"
```

The version parameter becomes the primary tag (1.0.0).
The optional tags parameter accepts comma-separated additional tags applied via crane without re-uploading image data.

Push single-architecture manifests when testing or when multi-arch builds aren't needed:

```bash
just container-push-x86 fd 1.0.0
just container-push-arm fd 1.0.0
```

Push all defined containers in one command:

```bash
just container-push-all 1.0.0
just container-push-all 1.0.0 "latest"
```

Complete release workflow that builds and pushes everything:

```bash
just container-release 1.0.0 "latest,stable"
```

## Manual nix commands

If you prefer to use nix commands directly instead of justfile recipes, use these patterns.

### Building containers

Build specific container and architecture combinations:

```bash
nix build '.#fdContainer-x86_64'
nix build '.#fdContainer-aarch64'
nix build '.#rgContainer-x86_64'
nix build '.#rgContainer-aarch64'
```

The naming pattern is `{containerName}Container-{architecture}` where architecture is either x86_64 or aarch64.

Load a container into your Docker daemon:

```bash
nix run '.#fdContainer-aarch64.copyToDockerDaemon'
docker run --rm fd:latest --help
```

Note that nix2container produces JSON manifests, not tarballs, so `docker load < result` does not work with this system.

### Pushing manifests

Push multi-architecture manifest lists to the registry:

```bash
VERSION=1.0.0 nix run --impure '.#fdManifest'
VERSION=1.0.0 TAGS="latest,stable" nix run --impure '.#fdManifest'
```

The --impure flag is required because the manifest builder reads environment variables at evaluation time.

Push single-architecture manifests:

```bash
VERSION=1.0.0 nix run --impure '.#fdManifest-x86_64'
VERSION=1.0.0 nix run --impure '.#fdManifest-aarch64'
```

### Inspecting the matrix

View the containerMatrix structure that CI uses:

```bash
nix eval .#containerMatrix --json | jq .
```

This shows the build matrix (container × target combinations) and manifest list (container names).

## Adding new containers

Container definitions live in `~/projects/nix-workspace/vanixiets/modules/containers/default.nix` within the `containerDefs` attrset.

Add a new container by extending the containerDefs attrset:

```nix
containerDefs = {
  fd = {
    name = "fd";
    packages = [ "fd" ];
    entrypoint = "fd";
  };
  rg = {
    name = "rg";
    packages = [ "ripgrep" ];
    entrypoint = "rg";
  };
  # Add your container here
  mytool = {
    name = "mytool";
    packages = [ "mytool" ];
    entrypoint = "mytool";
  };
};
```

The schema for each definition:

- `name`: Container image name (used in tags and manifest lists)
- `packages`: List of nixpkgs attribute names to include in the container
- `entrypoint`: Binary name to use as the container entrypoint (defaults to name if omitted)
- `targets`: Optional list of target architectures (defaults to `["x86_64" "aarch64"]`)

When the package attribute name differs from the binary name, only the entrypoint parameter needs adjustment.
The rg container demonstrates this pattern: the package is ripgrep but the binary is rg.

After adding a container definition, the module automatically generates:

- `mytoolContainer-x86_64` and `mytoolContainer-aarch64` build outputs
- `mytoolManifest` for pushing multi-arch manifest lists
- `mytoolManifest-x86_64` and `mytoolManifest-aarch64` for single-arch manifests
- Entries in the containerMatrix for CI discovery

Update the `_containers` variable in justfile to enable the container-build-all-defs and container-push-all recipes:

```just
_containers := "fd rg mytool"
```

Test your new container:

```bash
just container-all mytool "" aarch64
just container-verify mytool aarch64
```

## CI/CD integration

The `.github/workflows/containers.yaml` workflow provides automated multi-architecture container builds and optional registry publishing.

### Workflow structure

The workflow consists of three jobs that run sequentially:

**discover** evaluates `nix eval .#containerMatrix` to generate dynamic job matrices without hardcoding container names or architectures in the workflow file.

**build** runs a matrix job for each container × target combination (fd × x86_64, fd × aarch64, rg × x86_64, rg × aarch64, etc) using a single ubuntu-latest runner with pkgsCross for cross-compilation.

**manifest** runs a matrix job for each container to push multi-architecture manifest lists, but only when the push input is true.

### Workflow inputs

- `version`: Primary version tag (default: "latest")
- `tags`: Comma-separated additional tags applied via crane without re-uploading (default: "")
- `push`: Whether to push images to registry (default: false for workflow_dispatch, true for workflow_call)
- `debug_enabled`: Enable tmate debug session (default: false)

### Running the workflow

Trigger manually through GitHub Actions UI with workflow_dispatch, or call from another workflow with workflow_call.

For manual testing, leave push disabled to verify builds without publishing.
For releases, enable push and set appropriate version and tags.

### Adding containers to CI

The CI workflow automatically discovers containers from containerMatrix, so adding a new container definition in modules/containers/default.nix is sufficient.
No workflow file changes are needed.

## nix-rosetta-builder for Darwin

On Darwin (macOS) systems, Linux container builds require a remote Linux builder.
The nix-rosetta-builder provides fast Linux builds on Apple Silicon through a NixOS VM.

This builder is only necessary for Darwin hosts.
Linux hosts (including CI runners) build containers directly using pkgsCross without any remote builder configuration.

### Initial setup

The nix-rosetta-builder VM image is automatically fetched from the cameronraysmith.cachix.org cache during system build.

On a fresh macOS machine:

```bash
cd ~/projects/nix-workspace/vanixiets
just activate --ask
```

The VM image (approximately 2GB) downloads from cache automatically, which is significantly faster than building it locally.

### VM configuration

The builder VM is configured with:

- onDemand: Powers off when idle to conserve resources
- cores: 8 CPU cores
- memory: 6GiB RAM
- diskSize: 100GiB disk

### Maintaining the cache

Update the cached image after changing the nix-rosetta-builder flake input or module configuration:

```bash
nix flake lock --update-input nix-rosetta-builder
darwin-rebuild switch
just cache-rosetta-builder
```

Check if your current system's image is cached:

```bash
just check-rosetta-cache
```

The VM uses pinned nixpkgs and evolves independently from your system nixpkgs, so infra nixpkgs updates do not require cache updates.

### Container management with Colima

The nix-rosetta-builder focuses on building container images from Nix expressions.
For running and managing OCI containers, see the complementary Colima configuration documented in colima-container-management.md.

Both can run simultaneously:

- nix-rosetta-builder: 8 cores, 6GB RAM (on-demand)
- Colima: 4 cores, 4GB RAM (manual control)

Example workflow combining both:

```bash
# Build with nix-rosetta-builder
just container-all fdContainer fd

# Load into Colima's Docker runtime
nix run '.#fdContainer-aarch64.copyToDockerDaemon'
docker run --rm fd:latest --help
```

## Implementation details

### Container image structure

Each container includes:

- Base layer: bash and coreutils (shared across containers, cached effectively)
- Application layer: the specified packages from nixpkgs
- Minimal environment: only the listed packages plus essential utilities

The two-layer strategy optimizes for registry caching since the base layer rarely changes while application layers vary per container.

### Cross-compilation strategy

The pkgsCross mechanism selects the appropriate cross-compilation toolchain:

- `pkgsCross.gnu64` for x86_64-linux targets
- `pkgsCross.aarch64-multiplatform` for aarch64-linux targets

When the host system matches the target system, Nix automatically optimizes to native compilation instead of cross-compilation.

### Manifest list creation

Multi-architecture manifest lists are created through a two-phase process:

1. skopeo pushes per-architecture images with arch-suffixed tags (1.0.0-amd64, 1.0.0-arm64)
2. crane creates a manifest list referencing the pushed images by digest and tags it with the version (1.0.0)

Additional tags are applied via crane's tag command which performs server-side operations without re-uploading image data.

Single-architecture builds skip the manifest list creation and push directly to the primary tag.

### Registry configuration

The manifest builder in `lib/mk-multi-arch-manifest.nix` accepts registry configuration:

```nix
registry = {
  name = "ghcr.io";
  repo = "cameronraysmith/vanixiets/${containerName}";
  username = getEnvOr "GITHUB_ACTOR" "cameronraysmith";
  password = "$GITHUB_TOKEN";
};
```

Environment variables can be read at build time using the getEnvOr helper, which requires --impure when invoking nix run.

### Version and tag handling

The version parameter becomes the primary tag and must be set explicitly.
The tags parameter accepts comma-separated additional tags.
If tags is empty and branch is "main", the system automatically adds "latest".

Tag application order:

1. Version tag (1.0.0)
2. Explicit tags from TAGS environment variable
3. Auto-generated "latest" tag on main branch (when no explicit tags provided)

Each additional tag is applied via crane's server-side tag operation referencing the version tag's manifest list.
