# Landrun aarch64-linux Build Failure

## Issue Summary

The `landrun` package fails to build on `aarch64-linux` (ARM) in GitHub Actions CI, specifically on the `ubuntu-24.04-arm` runner.
This failure cascades to dependent packages: `ccds-sandboxed`, `ccstatusline`, and `claude-sandboxed`.

**Status:** Known issue as of 2025-10-21 (CI run 18672789600)

**Impact:**
- `cache-overlay-packages (aarch64-linux)` job fails
- ARM architecture overlay packages not cached
- Does NOT block x86_64-linux builds ✓
- Does NOT block main nix job matrix (marked `fail-fast: false`)

## Technical Details

### Failing Test

```
landrun> [TEST] Running test: Execute a file with --add-exec and --ldd flag
landrun> [landrun:debug] 2025/10/21 04:24:13 Added executable path: /nix/store/.../bin/true
landrun> [landrun:debug] 2025/10/21 04:24:13 Added library paths: [...]
landrun> [landrun] 2025/10/21 04:24:13 Landlock restrictions applied successfully
landrun> [landrun] 2025/10/21 04:24:13 Executing: [/nix/store/.../coreutils-9.7/bin/true]
landrun> [landrun:error] 2025/10/21 04:24:13 permission denied
landrun> [ERROR] Test failed: Execute a file with --add-exec and --ldd flag (expected exit 0, got 1)
```

### Root Cause

**Landlock LSM incompatibility on aarch64-linux runners:**
- Landlock (Linux Security Module) test suite expects specific kernel features
- GitHub's ubuntu-24.04-arm runner may have different Landlock ABI version or feature flags
- The test applies Landlock restrictions successfully but exec still fails with permission denied
- This suggests the runner's kernel Landlock implementation differs from x86_64

### Package Details

- **Package:** `landrun` (Go-based sandboxing tool using Linux Landlock)
- **Source:** github:srid/landrun-nix
- **Version:** 0.1.15 (as of flake.lock)
- **Purpose:** Used by Claude Code wrapper scripts for sandboxed command execution

### Cascading Failures

```
landrun (build fails)
  └─> ccds-sandboxed (1 dependency failed)
  └─> ccstatusline-2.0.21 (depends on landrun)
  └─> claude-sandboxed (depends on landrun)
```

## Mitigation Options

### Option 1: Skip Tests on aarch64-linux (Recommended)

Override `landrun` package to disable tests on ARM:

```nix
# overlays/packages.nix or similar
landrun = prev.landrun.overrideAttrs (old: {
  doCheck = !pkgs.stdenv.isAarch64;  # Skip tests on ARM
});
```

**Pros:**
- Simple, minimal change
- landrun binary may still work despite test failure
- Unblocks CI for ARM overlay caching

**Cons:**
- No test coverage on ARM
- Might hide runtime issues

### Option 2: Platform-Specific Availability

Mark landrun and dependents as x86_64-only:

```nix
# In package definitions
meta.platforms = lib.platforms.linux ++ lib.platforms.darwin;
meta.broken = pkgs.stdenv.isAarch64;  # Broken on ARM for now
```

**Pros:**
- Honest about platform support
- Prevents runtime surprises

**Cons:**
- No Claude Code sandboxing on ARM hosts
- Reduces package availability

### Option 3: Upstream Fix

Report issue to landrun-nix maintainer:

**Investigation needed:**
1. Check landrun GitHub issues for similar reports
2. Test locally on ARM hardware (if available)
3. Compare Landlock kernel versions between x86 and ARM runners
4. Potentially patch test suite to handle ARM differences

**Pros:**
- Proper long-term fix
- Benefits all users

**Cons:**
- Time investment
- Requires ARM testing environment

### Option 4: Accept CI Failure (Current State)

Keep `fail-fast: false` and document the known issue:

**Pros:**
- No code changes needed
- Doesn't block other CI jobs
- ARM overlay caching is nice-to-have, not critical

**Cons:**
- CI always shows red ✗ for this job
- Reduces confidence in CI green status

## Recommended Action

**Short-term:** Proceed with Option 4 (accept failure), document in this file.

**Mid-term:** Implement Option 1 (skip tests) if ARM overlay caching becomes important.

**Long-term:** Investigate Option 3 (upstream fix) when time permits.

## CI Run References

- Initial failure: [Run 18672789600](https://github.com/cameronraysmith/nix-config/actions/runs/18672789600)
- Job: `cache-overlay-packages (aarch64-linux)` (ID: 53236980048)

## Related Files

- `.github/workflows/ci.yaml:425-462` - cache-overlay-packages job definition
- `overlays/packages.nix` - Where landrun override would go
- `flake.lock` - Current landrun-nix input pin

## Testing Locally

To reproduce (requires ARM hardware or VM):

```bash
nix build .#legacyPackages.aarch64-linux.landrun
```

To test with disabled checks:

```bash
nix build .#legacyPackages.aarch64-linux.landrun --override-input landrun-nix github:srid/landrun-nix --impure
# Then add doCheck = false to the override
```
