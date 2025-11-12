# Performance Considerations

## Build Performance

**Baseline Measurements** (test-clan validation):
- **Flake evaluation**: ~1-2s (pure import-tree, 29 modules)
- **NixOS build** (cinnabar): ~45s (cached), ~5min (uncached)
- **Darwin build** (test-darwin): ~30s (cached), ~3min (uncached)
- **Test suite** (17 tests): ~5s (fast), ~11s (with integration)

**Optimization Strategies**:
- **Shared nixpkgs**: `useGlobalPkgs = true` (share packages across system/home-manager)
- **Binary cache**: Use cachix or nix-community cache for common packages
- **Parallel builds**: `nix.settings.max-jobs = "auto"` (utilize all CPU cores)
- **Flake lock**: Pin dependencies to avoid unexpected rebuilds

## Deployment Performance

**Clan Vars Generation**:
- **Per-machine**: ~2-5s (generate identity + secrets)
- **Parallelizable**: Generate vars for multiple machines concurrently
- **Cached**: Vars only regenerated if generator changes

**Terraform Operations**:
- **Plan**: ~5-10s (API queries to cloud providers)
- **Apply** (new VPS): ~2-3min (VM creation + SSH key distribution)
- **Apply** (no changes): ~5s (state verification only)

**System Activation**:
- **darwin-rebuild switch**: ~10-30s (depending on changes)
- **nixos-rebuild switch**: ~20-60s (depending on changes)
- **Remote deployment**: Add ~10-30s for SSH overhead + nix-copy-closure

## Network Performance

**Zerotier Latency**:
- **Direct connection** (local network): ~1-5ms overhead
- **Relayed connection** (via moon): ~20-50ms overhead (depends on moon location)
- **WAN latency**: Depends on internet connection (not critical for development)

**Build Transfer**:
- **nix-copy-closure**: Transfer built artifacts to remote machines
- **Optimization**: Use `--use-substitutes` to fetch from binary cache on target

## Scalability Limits

**Current Fleet**: 5 machines (1 VPS + 4 darwin workstations)

**Proven Scalability** (from production examples):
- **clan-infra**: 20+ machines (web servers, build machines, jitsi, gitea)
- **Dendritic pattern**: Scales to hundreds of modules (drupol-dendritic-infra)
- **Zerotier**: Free tier supports up to 100 peers

**Performance Bottlenecks**:
- **Flake evaluation**: Linear with module count (import-tree auto-discovery overhead)
- **Test suite**: Integration tests scale with VM count (2-5min per VM)
- **Terraform state**: Single state file for all infrastructure (manual locking)
