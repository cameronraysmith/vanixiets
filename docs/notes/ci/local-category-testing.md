# Local CI Category Testing

## Purpose

Test CI matrix job categories locally on aarch64-darwin before pushing changes, ensuring builds succeed and cachix caching works correctly.

Uses nix-rosetta-builder to build aarch64-linux targets locally, pushing all store paths to cachix so CI jobs fetch from cache instead of rebuilding.

## Prerequisites

- Running on aarch64-darwin with nix-rosetta-builder configured
- Secrets access: `sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME'`
- Sufficient disk space (~20-30GB free recommended)

## Quick Reference

### Test Individual Category
```bash
# Small category (fastest test)
just ci-cache-category aarch64-linux checks-devshells

# Medium categories
just ci-cache-category aarch64-linux packages
just ci-cache-category aarch64-linux home

# Large categories (system builds)
just ci-cache-category aarch64-linux nixos blackphos-nixos
just ci-cache-category aarch64-linux nixos orb-nixos
just ci-cache-category aarch64-linux nixos stibnite-nixos
```

### Test All Categories (Unattended)
```bash
# In nix develop shell
./scripts/ci/test-all-categories-unattended.sh aarch64-linux

# Results logged to: ci-category-test-TIMESTAMP.log
# Duration: 60-120 minutes depending on cache hits
```

### For Long Sessions
```bash
# Run in background, check progress later
nohup ./scripts/ci/test-all-categories-unattended.sh aarch64-linux > /dev/null 2>&1 &

# Monitor progress
tail -f ci-category-test-*.log

# Or use screen/tmux
screen -S ci-test
./scripts/ci/test-all-categories-unattended.sh aarch64-linux
# Detach: Ctrl-A D, reattach: screen -r ci-test
```

## Verification

### Check Build Success
```bash
# View summary at end of log
tail -50 ci-category-test-*.log

# Should see: "status: success" for each category
```

### Verify Cachix Upload
```bash
# Visit cache web UI
CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
echo "https://app.cachix.org/cache/$CACHE_NAME"

# Or check specific path
nix path-info --store https://cameronraysmith.cachix.org /nix/store/...
```

### Test CI Will Use Cache
```bash
# Rebuild without cache, should fetch quickly
nix build .#nixosConfigurations.blackphos-nixos.config.system.build.toplevel \
    --print-out-paths --no-link

# Should see "copying path" (fetching) not "building"
```

## Common Patterns

### Test Before CI Push
```bash
# 1. Test changed categories locally
just ci-cache-category aarch64-linux packages

# 2. Verify success and cachix upload
# 3. Push changes
git push origin beta

# 4. Monitor CI (should be much faster)
gh run watch
```

### After Flake Changes
If you modify flake.nix, flake.lock, or add/remove outputs:
```bash
# Re-test affected categories
just ci-cache-category aarch64-linux packages  # if packages changed
just ci-cache-category aarch64-linux nixos blackphos-nixos  # if system config changed
```

### Selective Re-caching
If CI shows a category failed but you fixed it:
```bash
# Re-cache just that category
just ci-cache-category aarch64-linux nixos stibnite-nixos

# Verify in cachix, then re-run CI
```

## Troubleshooting

### nix-rosetta-builder not working
```bash
# Check builder config
nix show-config | grep builders

# Test builder
nix build --system aarch64-linux nixpkgs#hello --print-out-paths

# Verify SSH access
ssh rosetta-builder uname -a  # Should output: Linux ... aarch64
```

### cachix push fails
```bash
# Verify secrets are accessible
sops exec-env secrets/shared.yaml 'env | grep CACHIX'

# Should show CACHIX_AUTH_TOKEN and CACHIX_CACHE_NAME
```

### Disk space issues
```bash
# Check usage
df -h /

# Clean up if needed
nix-collect-garbage -d
rm -f result*
```

### Build taking very long
Check if building from source vs fetching:
- "copying path" = fetching from cache (fast, good)
- "building" = compiling locally (slow, indicates missing cache)

If building from source for common packages, check network connectivity to cache.nixos.org.

## Integration with CI Workflow

### Matrix Strategy
The CI workflow uses a 12-job matrix splitting builds by category:
- 2 jobs: packages (x86_64-linux, aarch64-linux)
- 2 jobs: checks-devshells
- 2 jobs: home configurations
- 6 jobs: nixos configurations (3 configs × 2 systems)

Local testing validates each category will succeed in isolation.

### Cache-Overlay-Packages Job
CI runs cache-overlay-packages first (before the matrix), caching resource-intensive overlay packages. Local testing assumes this has run, matching CI behavior.

### Disk Space Optimization
Each matrix job builds ~2-8 outputs instead of ~21 total, reducing per-job disk usage from ~25-35GB to ~4-15GB. Local testing verifies categories stay within these limits.

## Scripts Reference

### ci-cache-category.sh
Builds specific category and pushes to cachix with all dependencies.

Features:
- Discovery: Finds all outputs in category via nix eval
- Building: Uses `--print-out-paths` to capture store paths
- Dependency query: `nix-store --query --requisites --include-outputs`
- Caching: Pushes via `sops exec-env` to cachix

### test-all-categories-unattended.sh
Tests all matrix categories with robust error handling.

Features:
- Continues through failures (tests all categories even if some fail)
- Comprehensive logging to timestamped file
- Summary report with per-category timing
- Safe to re-run (cachix handles duplicates)

## Expected Timings

First run (cold cache):
- checks-devshells: ~2-5 minutes
- packages: ~10-20 minutes
- home: ~5-15 minutes
- nixos configs: ~15-30 minutes each

With good cache:
- checks-devshells: ~2-3 minutes
- packages: ~5-10 minutes
- home: ~3-8 minutes
- nixos configs: ~5-10 minutes each

Full matrix test: ~60-120 minutes (first run), ~30-60 minutes (cached)
