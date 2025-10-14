# CI Run 18500875303 Failure Analysis

**Workflow**: multi-user architecture CI
**Branch**: beta
**Trigger**: workflow_dispatch
**Date**: 2025-10-14
**Duration**: ~8 minutes
**Result**: 3 failures, 8 passed

## Executive Summary

Three jobs failed in this CI run:

1. **nix (aarch64-linux)** - Disk space exhaustion (no logs available)
2. **nix (x86_64-linux)** - Disk space exhaustion during bitwarden-cli Rust compilation
3. **justfile-activation** - Test used wrong command to query flake outputs

### Impact Assessment

- **Severity**: High (blocks CI for any commit)
- **Scope**: Platform-specific (Linux builds) + Test implementation bug
- **Root causes**: Independent failures (not cascading)

---

## Failure 1: nix (aarch64-linux)

### Job Details

- **Job ID**: 52717127008
- **Duration**: 6m52s
- **Exit code**: 1
- **Step failed**: "build all outputs via omnix" (annotated but no logs)

### Root Cause

**Disk space exhaustion on GitHub Actions runner**

### Evidence

System annotation shows:
```
System.IO.IOException: No space left on device
```

The runner ran out of disk space while building outputs. No detailed logs available, but pattern matches the x86_64-linux failure (see below).

### Contributing Factors

1. **GitHub Actions runner size**: 72GB root, 74GB /mnt
2. **Build requirements**: Multiple large Rust packages (bitwarden-cli, etc.)
3. **Temp directory location**: Builds happen in /mnt which filled up
4. **Cachix effectiveness**: Even with cachix, some packages must build from source

### Why This Matters

Linux builds are part of the multi-architecture CI strategy. If Linux builds consistently fail due to disk space, CI becomes unreliable for cross-platform development.

### Immediate Impact

- Cannot validate that home configurations build on Linux
- Cannot verify that packages work on non-darwin platforms
- Blocks PRs that need full CI validation

---

## Failure 2: nix (x86_64-linux)

### Job Details

- **Job ID**: 52717127025
- **Duration**: 8m4s
- **Exit code**: 1
- **Step failed**: "build all outputs via omnix"

### Root Cause

**Disk space exhaustion during bitwarden-cli (bws) Rust compilation**

### Evidence

#### Build Failure Log
```
bws> error: failed to build archive at `/mnt/tmp.p1FEIiDgsc/nix-shell.LRp2ju/
nix-build-bws-1.0.0.drv-0/source/target/x86_64-unknown-linux-gnu/release/deps/
libobject-02629ecadd90fb15.rlib`: No space left on device (os error 28)

bws> error: could not compile `object` (lib) due to 1 previous error
```

#### Disk Usage at Failure
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root        72G   70G  2.0G  98% /
/dev/sda1        74G   69G  1.0G  99% /mnt
/dev/loop0       85G   12G   74G  14% /nix
```

**Critical**: TMPDIR is `/mnt/tmp.p1FEIiDgsc` on `/dev/sda1` with only 1.0G free.

#### Build Context

Compiling when failure occurred:
```
bws>    Compiling rustix v0.38.37
bws>    Compiling semver v1.0.23
bws> error: failed to build archive...
```

The `object` crate and `rustix` are large Rust dependencies. Rust compilation generates significant intermediate artifacts (rlibs, rmeta files).

### Cascading Failures

Once bws fails, all dependent derivations fail:
- `home-manager-path.drv` (3 instances - for runner@stibnite, runner@blackphos, raquel@blackphos)
- `home-manager-generation.drv` (3 instances)
- `hm_fontconfigconf.d10hmfonts.conf.drv` (3 instances)
- `user-environment.drv`
- `devour-output.json.drv` (final omnix output)

### Why bws Specifically?

Bitwarden-cli (`bws`) is a large Rust project with many dependencies:
- **Size**: ~1GB in dependencies and build artifacts
- **Complexity**: Crypto libraries, networking, CLI frameworks
- **Build time**: Several minutes of intensive compilation
- **Disk usage spike**: Intermediate .rlib and .rmeta files before final linking

This makes it a common culprit for disk exhaustion in CI environments.

### Contributing Factors

1. **Temp directory location**: `/mnt/tmp.*` instead of `/nix`
2. **Build isolation**: Nix builds in sandboxed temp directories
3. **No incremental compilation**: Each build starts from scratch
4. **Multiple home configs**: Building 3 home configs = 3x the disk pressure

### Immediate Impact

- All home configurations fail to build
- Cannot validate that user environments work on Linux
- Blocks PRs that modify home-manager configs

---

## Failure 3: justfile-activation

### Job Details

- **Job ID**: 52717127067
- **Duration**: 2m11s
- **Exit code**: 1
- **Step failed**: "verify configuration outputs"

### Root Cause

**Test implementation bug: Using `nix flake show --json` instead of `nix eval`**

### Evidence

#### Test Output
```bash
flake outputs:
darwin:type
nixos:blackphos-nixos
nixos:orb-nixos
nixos:stibnite-nixos

❌ darwin:blackphos missing from flake outputs
❌ darwin:stibnite missing from flake outputs
```

Notice: Shows `darwin:type` instead of `darwin:blackphos` and `darwin:stibnite`.

#### Verification

The autowiring-validation job (which passed) uses the correct command:
```bash
DARWIN_CONFIGS=$(nix eval .#darwinConfigurations --apply 'x: builtins.attrNames x' --json)
# Returns: ["blackphos","stibnite"]  ✅ Works!
```

The justfile-activation job uses the wrong command:
```bash
FLAKE_OUTPUTS=$(nix flake show --json 2>/dev/null | jq -r '
  (.darwinConfigurations // {} | keys[] as $k | "darwin:\($k)")
')
# Returns: "darwin:type"  ❌ Broken!
```

#### Why nix flake show Fails

`nix flake show --json` uses schema inference and can't properly traverse complex output structures created by flake-parts and nixos-unified. It sees the darwinConfigurations attribute set but reports it as `{"type": "unknown"}` because it can't evaluate the nested structure.

This is a known limitation of `nix flake show` with complex flakes.

### Why This Matters

The test was introduced to validate that nixos-unified autowiring is working correctly. However, the test itself had a bug that made it report false negatives.

The actual configurations ARE properly autowired (as proven by autowiring-validation job passing). The test just couldn't see them.

### Immediate Impact

- False negative: Reports configs missing when they exist
- Test was supposed to validate UX but instead breaks CI
- This was a NEW test added in commit a973a5a (my redesign)

### Additional Context

This test step was designed to replace hardcoded config lists with dynamic discovery. The intention was good, but the implementation used the wrong tool for querying outputs.

**Working approach** (from autowiring-validation):
```bash
nix eval .#darwinConfigurations --apply 'x: builtins.attrNames x' --json
```

**Broken approach** (from justfile-activation):
```bash
nix flake show --json | jq '.darwinConfigurations | keys[]'
```

---

## Cross-Failure Patterns

### Independence

The three failures are **not related**:
- Disk space issues affect nix jobs only
- Test bug affects justfile-activation only
- No cascading relationship between failures

### Timing

All failures occurred in the same run, but for different reasons:
- nix jobs: Infrastructure limitation (disk space)
- justfile-activation: Code bug (wrong command)

---

## Recommended Actions

### Immediate (Fix This Run)

#### Fix 1: Update justfile-activation Test

Replace this:
```bash
FLAKE_OUTPUTS=$(nix flake show --json 2>/dev/null | jq -r '
  (.darwinConfigurations // {} | keys[] as $k | "darwin:\($k)"),
  (.nixosConfigurations // {} | keys[] as $k | "nixos:\($k)")
')
```

With this:
```bash
DARWIN_CONFIGS=$(nix eval .#darwinConfigurations --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]? // empty')
NIXOS_CONFIGS=$(nix eval .#nixosConfigurations --apply 'x: builtins.attrNames x' --json 2>/dev/null | jq -r '.[]? // empty')

FLAKE_OUTPUTS=$(printf "%s\n%s" \
  "$(echo "$DARWIN_CONFIGS" | sed 's/^/darwin:/')" \
  "$(echo "$NIXOS_CONFIGS" | sed 's/^/nixos:/')")
```

**Priority**: High
**Effort**: 5 minutes
**Impact**: Unblocks CI immediately for justfile-activation

#### Fix 2: Cache bitwarden-cli for Linux

From previous commits, there's already a justfile recipe for this:
```bash
just cache-bitwarden-linux
```

This should be run to cache the bitwarden-cli build for both aarch64-linux and x86_64-linux.

**Priority**: High
**Effort**: 30 minutes (one-time build + cachix push)
**Impact**: Eliminates disk space issue for future builds

### Short-Term (Improve Resilience)

1. **Monitor disk usage trends**
   - Add pre-build disk check in nix jobs
   - Alert when usage >80% before starting build

2. **Optimize build order**
   - Build large packages first (fail fast if disk issues)
   - Consider splitting nix job into smaller jobs per output type

3. **Document TMPDIR issue**
   - Add note to README about Linux CI disk limitations
   - Explain why some packages must be pre-cached

### Long-Term (Architectural)

1. **Self-hosted runners**
   - Larger disk space available
   - Persistent cache across runs
   - Better cost for frequent builds

2. **Build matrix optimization**
   - Don't rebuild unchanged outputs
   - Smart dependency graph analysis
   - Incremental omnix builds

3. **Test improvement**
   - Extract config discovery logic to shared script
   - Reuse autowiring-validation logic in justfile-activation
   - Add test for "test uses correct command" (meta-testing)

---

## Lessons Learned

### 1. Verify Test Implementation

The justfile-activation test was well-intentioned (replace hardcoded lists with discovery) but used the wrong tool. The autowiring-validation job already had the correct implementation.

**Takeaway**: When adding new tests, check if similar tests exist and reuse their proven approaches.

### 2. Disk Space Is Real

Even with 70GB of cachix setup, Linux builds still run out of space due to:
- Large Rust projects (bws, rust-analyzer, etc.)
- Multiple home configurations being built
- Temp directory location on limited partition

**Takeaway**: Either pre-cache large packages or use larger runners.

### 3. Complex Flakes Need Careful Querying

`nix flake show --json` doesn't work well with flake-parts + nixos-unified structures. Use `nix eval` with `--apply` for reliable output inspection.

**Takeaway**: Test discovery commands locally with `nix eval` before using in CI.

---

## Verification Steps

To verify these fixes work:

### 1. Test justfile-activation Fix Locally

```bash
# Should return: ["blackphos","stibnite"]
nix eval .#darwinConfigurations --apply 'x: builtins.attrNames x' --json

# Should return: ["blackphos-nixos","orb-nixos","stibnite-nixos"]
nix eval .#nixosConfigurations --apply 'x: builtins.attrNames x' --json
```

### 2. Cache bitwarden-cli

```bash
just cache-bitwarden-linux
# Wait ~15-30 minutes for build + push
```

### 3. Trigger CI Again

```bash
gh workflow run ci.yaml --ref beta
# Monitor: gh run watch
```

Expected outcome:
- ✅ justfile-activation passes (test fixed)
- ✅ nix (aarch64-linux) passes (bws cached)
- ✅ nix (x86_64-linux) passes (bws cached)

---

## Related Documentation

- **CI Testing Strategy**: `docs/notes/ci/ci-testing-strategy.md`
- **Justfile Activation Redesign**: `docs/notes/ci/justfile-activation-redesign.md`
- **Cachix Linux Package Recipe**: `justfile:794-885` (`cache-linux-package`)
- **Autowiring Validation Job**: `.github/workflows/ci.yaml:130-211`
