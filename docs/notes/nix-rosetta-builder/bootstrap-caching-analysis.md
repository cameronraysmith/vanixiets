# nix-rosetta-builder bootstrap caching analysis

Investigation of GitHub issue #7 bootstrap complexity and caching solution design.

## Problem statement

Currently, bootstrapping `nix-rosetta-builder` requires a complex three-step process:
1. First activate the nix-darwin `linux-builder` module
2. Then activate `nix-rosetta-builder`
3. Finally deactivate the nix-darwin `linux-builder` module

This involves manual code editing/commenting which is undesirable.

## Root cause analysis

### Why the bootstrap is needed

The `nix-rosetta-builder` VM image is defined as an aarch64-linux package:

```nix
# In nix-rosetta-builder/flake.nix
packages."${linuxSystem}" = {  # linuxSystem = "aarch64-linux"
  image = pkgs.callPackage ./package.nix { ... };
};
```

This creates a chicken-and-egg problem:
- The image must be built on a Linux system (it's an aarch64-linux derivation)
- But `nix-rosetta-builder` **is** the Linux builder you're trying to create
- Therefore, you need a different Linux builder to build the initial image

### The image contents

The image (`/path/to/store/nixos.qcow2`) is a full NixOS VM containing:
- Linux kernel and boot configuration (systemd-boot, EFI)
- NixOS system configuration
- openssh with custom key management
- Rosetta 2 integration via virtiofs
- Nix with flakes enabled
- Power management for on-demand operation

The image is generated using `nixos-generators.nixosGenerate` with format "qcow-efi".

### Configuration variants

The image derivation varies based on these parameters:
```nix
imageWithFinalConfig = image.override {
  inherit debugInsecurely;
  onDemand = cfg.onDemand;
  onDemandLingerMinutes = cfg.onDemandLingerMinutes;
  potentiallyInsecureExtraNixosModule = cfg.potentiallyInsecureExtraNixosModule;
};
```

Each unique combination of these values creates a **different** image derivation, requiring separate cache entries.

Current stibnite.nix configuration:
- `onDemand = true`
- `onDemandLingerMinutes` = 180 (default)
- `potentiallyInsecureExtraNixosModule` = {} (empty)
- `debugInsecurely` = false (hardcoded, not user-configurable)

## Cache invalidation triggers

The bootstrap image needs to be rebuilt when:

### 1. Flake input changes

**nix-rosetta-builder version** (in nix-config/flake.lock):
- Current: `ebb7162a975074fb570a2c3ac02bc543ff2e9df4`
- Updates when: `nix flake update nix-rosetta-builder` in nix-config

**nixpkgs version** (in nix-rosetta-builder/flake.lock):
- Current: `852ff1d9e153d8875a83602e03fdef8a63f0ecf8`
- This is separate from nix-config's nixpkgs
- Updates when: nix-rosetta-builder upstream updates its nixpkgs

**nixos-generators version** (in nix-rosetta-builder/flake.lock):
- Current: `d002ce9b6e7eb467cd1c6bb9aef9c35d191b5453`
- Updates when: nix-rosetta-builder upstream updates

### 2. Configuration changes

Any changes to nix-rosetta-builder module options in `configurations/darwin/stibnite.nix`:
- `onDemand` (currently: true)
- `onDemandLingerMinutes` (currently: 180)
- `potentiallyInsecureExtraNixosModule` (currently: {})

These options are passed to `image.override`, creating different derivations.

### 3. Source code changes

Changes to nix-rosetta-builder source files:
- `package.nix` (image build definition)
- `module.nix` (darwin module and image overrides)
- `constants.nix` (shared constants)

### 4. Packages do NOT trigger rebuilds

Notable: Changes to nix-config's nixpkgs do **not** affect the nix-rosetta-builder image.
The image uses nix-rosetta-builder's own nixpkgs input, not nix-config's.

## Existing caching infrastructure

### Current justfile recipe

The `just cache-rosetta-builder` recipe in nix-config/justfile:
1. Finds the VM image from the already-built system
2. Extracts the image path from the rosetta-builder.yaml config
3. Pushes the image to `cameronraysmith.cachix.org`

**Limitation**: This only works AFTER you've already built the system (i.e., after completing the three-step bootstrap).

### Current cache configuration

The cache is configured in `modules/nixos/shared/caches.nix`:
```nix
nix.settings.substituters = [
  "https://cameronraysmith.cachix.org"
];
nix.settings.trusted-public-keys = [
  "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
];
```

**Limitation**: These settings only apply AFTER the system is built, not during initial flake evaluation.

## Solution: nixConfig in flake

### How nixConfig solves the bootstrap problem

Adding `nixConfig` to nix-config/flake.nix tells nix to use the cachix substituter **during flake evaluation**, before building anything:

```nix
{
  nixConfig = {
    extra-substituters = [ "https://cameronraysmith.cachix.org" ];
    extra-trusted-public-keys = [
      "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
    ];
  };

  # rest of flake...
}
```

This is the same approach used by the upstream `macos-builder` before it was upstreamed to nixpkgs (see issue #7 comments).

### Workflow with nixConfig

**One-time setup (already done):**
1. Complete the three-step bootstrap process
2. Run `just cache-rosetta-builder` to upload the image to cachix

**Future builds (bootstrap-free):**
1. Clone nix-config with nixConfig in place
2. Run `darwin-rebuild switch`
3. Nix automatically fetches the cached image from cachix
4. No manual linux-builder toggling needed

### When to update the cache

Update the cached image (by running `just cache-rosetta-builder`) when:

1. **After updating nix-rosetta-builder input:**
   ```bash
   cd /Users/crs58/projects/nix-workspace/nix-config
   nix flake lock --update-input nix-rosetta-builder
   darwin-rebuild switch
   just cache-rosetta-builder
   ```

2. **After changing nix-rosetta-builder configuration** in stibnite.nix:
   ```bash
   # Edit configurations/darwin/stibnite.nix
   darwin-rebuild switch
   just cache-rosetta-builder
   ```

3. **After upstream updates** to nix-rosetta-builder that change the image
   (this is detected automatically when you update the flake input)

Note: Regular nixpkgs updates in nix-config do NOT require cache updates, since the image uses its own nixpkgs.

## Implementation plan

### 1. Add nixConfig to nix-config/flake.nix

Location: After the `description` line, before `inputs`:

```nix
{
  description = "Nix configuration";

  nixConfig = {
    extra-substituters = [ "https://cameronraysmith.cachix.org" ];
    extra-trusted-public-keys = [
      "cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio="
    ];
  };

  inputs = {
    # existing inputs...
  };

  # rest of flake...
}
```

### 2. Verify cached image is current

Check that the current system's image is in cachix:

```bash
cd /Users/crs58/projects/nix-workspace/nix-config
just cache-rosetta-builder
```

This ensures the cache has the image for the current configuration.

### 3. Create automated cache check recipe

Add a justfile recipe to detect if the cache needs updating:

```just
# Check if nix-rosetta-builder cache is up-to-date
[group('CI/CD')]
check-rosetta-cache:
    #!/usr/bin/env bash
    set -euo pipefail

    echo "Checking if nix-rosetta-builder image is cached..."

    # Find the image from current system
    YAML_PATH=$(nix-store --query --requisites /run/current-system | grep 'rosetta-builder.yaml$' || true)

    if [ -z "$YAML_PATH" ]; then
        echo "⚠️  nix-rosetta-builder not enabled in current system"
        exit 0
    fi

    IMAGE_PATH=$(grep -A1 "images:" "$YAML_PATH" | grep "location:" | awk '{print $3}')

    if [ -z "$IMAGE_PATH" ]; then
        echo "❌ Could not extract image path"
        exit 1
    fi

    # Check if the image is in cache
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')

    if nix path-info --store "https://$CACHE_NAME.cachix.org" "$IMAGE_PATH" &>/dev/null; then
        echo "✅ Image is cached: $IMAGE_PATH"
    else
        echo "⚠️  Image NOT in cache: $IMAGE_PATH"
        echo "   Run: just cache-rosetta-builder"
        exit 1
    fi
```

### 4. Update documentation

Update `docs/notes/containers/multi-arch-container-builds.md`:

**Remove section** "Initial bootstrap" (lines 13-81) since bootstrap is no longer needed.

**Update section** "Caching to avoid rebuilds" (lines 90-103):
- Explain that nixConfig enables automatic cache fetching
- Document when manual cache updates are needed
- Reference the new `check-rosetta-cache` recipe

### 5. Integration into workflow

Add cache checking to relevant justfile workflows:

```just
# Run before darwin-rebuild to ensure cache is available
pre-darwin-rebuild:
    just check-rosetta-cache || echo "Consider updating cache after rebuild"

# Run after darwin-rebuild to update cache if needed
post-darwin-rebuild:
    just check-rosetta-cache || just cache-rosetta-builder
```

## Alternative: Upstream nixConfig

Consider proposing a PR to cpick/nix-rosetta-builder to add nixConfig to their flake.
This would benefit all users, not just this configuration.

The PR would add:
```nix
nixConfig = {
  extra-substituters = [ "https://nix-rosetta-builder.cachix.org" ];
  extra-trusted-public-keys = [
    "nix-rosetta-builder.cachix.org-1:..." # would need to create this cache
  ];
};
```

However, this requires:
1. Creating a dedicated cachix cache for nix-rosetta-builder
2. Setting up CI to build and push images
3. Maintaining the cache for all configuration variants

For now, using cameronraysmith.cachix.org in nix-config is the pragmatic solution.

## Impact analysis

### Benefits

1. **Eliminates manual bootstrap process**: No more commenting/uncommenting code
2. **Faster rebuilds**: ~2GB image downloaded from cache vs ~10-20min rebuild
3. **CI-friendly**: GitHub Actions can build darwin configs without complicated bootstrap
4. **Deterministic**: Same configuration always uses same cached image

### Limitations

1. **Cache size**: VM image is ~2GB, increases cache storage requirements
2. **Configuration variants**: Each unique config combination needs separate cache entry
3. **Manual cache updates**: Must remember to run `just cache-rosetta-builder` after updates
4. **Single-user cache**: Only works for users with access to cameronraysmith.cachix.org

### Future enhancements

1. **Automated cache updates in CI**: Build and push after nix-rosetta-builder updates
2. **Cache garbage collection**: Remove old image versions periodically
3. **Configuration-specific caching**: Automatically detect and cache all config variants
4. **Upstream contribution**: Get nixConfig into cpick/nix-rosetta-builder

## References

- GitHub issue #7: https://github.com/cpick/nix-rosetta-builder/issues/7
- Upstream macos-builder precedent: https://github.com/Gabriella439/macos-builder
- nix-darwin linux-builder: https://daiderd.com/nix-darwin/manual/index.html#opt-nix.linux-builder.enable
- nixos-generators: https://github.com/nix-community/nixos-generators
