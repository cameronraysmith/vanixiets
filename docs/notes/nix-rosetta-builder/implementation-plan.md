# Implementation plan: eliminate nix-rosetta-builder bootstrap complexity

Concrete steps to implement cachix-based bootstrap elimination for GitHub issue #7.

## Quick summary

Add `nixConfig` to nix-config/flake.nix to automatically fetch the cached VM image from cachix, eliminating the need for the three-step bootstrap process.

## Prerequisites

The following are already in place:
- [x] Cachix cache: `cameronraysmith.cachix.org`
- [x] Public key: `cameronraysmith.cachix.org-1:aC8ZcRCVcQql77Qn//Q1jrKkiDGir+pIUjhUunN6aio=`
- [x] Recipe: `just cache-rosetta-builder` (uploads current system's image)
- [x] Bootstrap completed: Current system has working nix-rosetta-builder
- [x] Image cached: Run `just cache-rosetta-builder` to ensure current image is uploaded

## Implementation steps

### Step 1: Add nixConfig to flake.nix

Edit: `/Users/crs58/projects/nix-workspace/nix-config/flake.nix`

Add after line 2 (after `description`):

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
```

### Step 2: Add cache checking recipe

Edit: `/Users/crs58/projects/nix-workspace/nix-config/justfile`

Add after the existing `cache-rosetta-builder` recipe (around line 628):

```just
# Check if nix-rosetta-builder image is in Cachix
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

    echo "Found config: $YAML_PATH"

    IMAGE_PATH=$(grep -A1 "images:" "$YAML_PATH" | grep "location:" | awk '{print $3}')

    if [ -z "$IMAGE_PATH" ]; then
        echo "❌ Could not extract image path"
        exit 1
    fi

    echo "Checking cache for: $IMAGE_PATH"

    # Check if the image is in cache
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')

    if nix path-info --store "https://$CACHE_NAME.cachix.org" "$IMAGE_PATH" &>/dev/null; then
        echo "✅ Image is cached"
        echo "   Cache: https://$CACHE_NAME.cachix.org"
        echo "   Path: $IMAGE_PATH"
    else
        echo "❌ Image NOT in cache"
        echo "   Path: $IMAGE_PATH"
        echo "   Run: just cache-rosetta-builder"
        exit 1
    fi
```

### Step 3: Update documentation

Edit: `/Users/crs58/projects/nix-workspace/nix-config/docs/notes/containers/multi-arch-container-builds.md`

**Replace** section "Initial bootstrap" (lines 13-81) with:

```markdown
## Initial setup

The nix-rosetta-builder VM image is automatically fetched from the `cameronraysmith.cachix.org` cache during system build.
No manual bootstrap process is required thanks to `nixConfig` in the flake.

If you're setting up on a fresh machine:

```bash
cd /Users/crs58/projects/nix-workspace/nix-config
darwin-rebuild switch
```

The VM image (~2GB) will be downloaded from cache automatically.
This is much faster than building it locally (~10-20 minutes).
```

**Update** section "Caching to avoid rebuilds" (lines 90-103) to:

```markdown
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

Note: Regular nixpkgs updates do NOT require cache updates.
The VM uses nix-rosetta-builder's own nixpkgs input, not nix-config's.

### Checking cache status

Verify if your current system's image is cached:

```bash
just check-rosetta-cache
```

This is useful before pushing commits that update nix-rosetta-builder.

### Automatic cache updates

The image is automatically cached after system builds via the `cache-rosetta-builder` recipe.
Run it manually after configuration changes to ensure the cache is up-to-date for other machines and CI.
```

### Step 4: Verify the solution

1. **Verify current image is cached:**
   ```bash
   cd /Users/crs58/projects/nix-workspace/nix-config
   just cache-rosetta-builder  # Upload current image if not already cached
   ```

2. **Test cache checking:**
   ```bash
   just check-rosetta-cache  # Should show "✅ Image is cached"
   ```

3. **Commit the changes:**
   ```bash
   git add flake.nix justfile docs/notes/
   git commit -m "feat: add nixConfig to eliminate nix-rosetta-builder bootstrap

   - Add nixConfig with cameronraysmith.cachix.org substituter
   - Add check-rosetta-cache recipe to verify cache status
   - Update documentation to remove manual bootstrap steps
   - Resolves bootstrap complexity from cpick/nix-rosetta-builder#7"
   ```

4. **Test on a clean environment (optional but recommended):**
   - Clone the repo on a different machine or VM
   - Run `darwin-rebuild switch`
   - Verify the image is fetched from cache (check build logs for "copying path... from 'https://cameronraysmith.cachix.org'")
   - Verify no manual bootstrap steps are needed

## Cache maintenance workflow

### Regular workflow (no cache updates needed)

```bash
# Regular system updates
nix flake update
darwin-rebuild switch

# Regular package additions, config changes, etc. - no cache update needed
```

### When cache update is needed

```bash
# Update nix-rosetta-builder input
nix flake lock --update-input nix-rosetta-builder
darwin-rebuild switch

# Push updated image to cache
just cache-rosetta-builder

# Verify cache
just check-rosetta-cache

# Commit flake.lock
git add flake.lock
git commit -m "chore(deps): update nix-rosetta-builder

Updated VM image cached to Cachix."
```

### Configuration changes

```bash
# Edit configurations/darwin/stibnite.nix
# (change onDemand, cores, memory, etc.)

darwin-rebuild switch
just cache-rosetta-builder
just check-rosetta-cache

git add configurations/darwin/stibnite.nix
git commit -m "feat(darwin): update nix-rosetta-builder configuration

Updated VM image cached to Cachix."
```

## Impact on CI/CD

With nixConfig in place:

1. **GitHub Actions can build darwin configurations** without bootstrap complexity
2. **Faster CI builds**: 2GB download instead of 10-20min build
3. **Deterministic builds**: Same config always uses same cached image
4. **No special CI setup**: Standard nix flake build works out of the box

Ensure CI has access to cameronraysmith.cachix.org (public read access, no auth required).

## Rollback plan

If issues arise, rollback is simple:

1. Remove nixConfig from flake.nix
2. Revert to manual bootstrap process documented in git history
3. Report issue to investigate

The cache remains available and the existing `cache-rosetta-builder` recipe is unaffected.

## Future enhancements

Consider these improvements later:

1. **Automated cache updates in CI:**
   - Trigger cache update after nix-rosetta-builder flake input changes
   - Use GitHub Actions to build and push image automatically

2. **Configuration variant detection:**
   - Detect all nix-rosetta-builder config combinations in use
   - Automatically cache images for each variant

3. **Cache health monitoring:**
   - Alert when cache is stale (flake input updated but cache not)
   - Track cache hit rates and storage usage

4. **Upstream contribution:**
   - Propose nixConfig addition to cpick/nix-rosetta-builder
   - Benefits all users, not just this configuration
   - Requires dedicated cachix cache and CI infrastructure

## References

- Bootstrap analysis: `./bootstrap-caching-analysis.md`
- GitHub issue: https://github.com/cpick/nix-rosetta-builder/issues/7
- Upstream precedent: https://github.com/Gabriella439/macos-builder (used same approach)
