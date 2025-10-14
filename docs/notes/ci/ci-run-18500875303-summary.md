# CI Run 18500875303: Root Cause Summary

**TL;DR**: 3 independent failures - 2 from disk space exhaustion during Linux builds, 1 from test implementation bug in new justfile-activation test.

---

## The Three Failures

### 1. nix (aarch64-linux) - Disk Space Exhaustion

**Root Cause**: GitHub Actions runner ran out of disk space during builds

**Evidence**:
- System annotation: `IOException: No space left on device`
- No detailed logs available (runner crashed before logging)
- Same pattern as x86_64-linux failure

**Impact**: Cannot validate Linux builds for aarch64 architecture

---

### 2. nix (x86_64-linux) - Disk Space During bws Build

**Root Cause**: Disk exhaustion while compiling bitwarden-cli (bws) Rust package

**Evidence**:
```
Filesystem      Size  Used Avail Use% Mounted on
/dev/root        72G   70G  2.0G  98% /
/dev/sda1        74G   69G  1.0G  99% /mnt      <- TMPDIR here!
/dev/loop0       85G   12G   74G  14% /nix

bws> error: failed to build archive: No space left on device (os error 28)
```

**The Problem**:
- TMPDIR is `/mnt/tmp.*` on `/dev/sda1` with only 1.0G free
- bitwarden-cli is a large Rust project (~1GB dependencies + build artifacts)
- Rust compilation generates significant intermediate files (.rlib, .rmeta)
- Build failed during `object` crate compilation
- This caused cascading failures for all 3 home configurations (runner@stibnite, runner@blackphos, raquel@blackphos)

**Why bws Specifically**:
- Large dependency tree (crypto, networking, CLI frameworks)
- Multiple compilation units being built simultaneously
- No incremental compilation in Nix sandbox
- Each home config tries to build it independently

**Impact**: All home configurations fail to build, blocks Linux validation

---

### 3. justfile-activation - Test Implementation Bug

**Root Cause**: Test used `nix flake show --json` which doesn't work with complex flake structures

**Evidence**:
```bash
# What the test saw:
flake outputs:
darwin:type           <- Wrong! Should be darwin:blackphos and darwin:stibnite
nixos:blackphos-nixos
nixos:orb-nixos
nixos:stibnite-nixos

# What actually exists (from autowiring-validation job):
DARWIN_CONFIGS=$(nix eval .#darwinConfigurations --apply 'x: builtins.attrNames x' --json)
# Returns: ["blackphos","stibnite"]  ✅ Correct!
```

**The Problem**:
- `nix flake show --json` can't traverse flake-parts + nixos-unified structure
- Returns `{"type": "unknown"}` for darwinConfigurations
- Test incorrectly reported configs as missing
- This is a **false negative** - configs exist and work fine

**Why This Happened**:
- justfile-activation test was newly redesigned (commit a973a5a)
- Tried to replace hardcoded config lists with dynamic discovery
- Used wrong command - should have used `nix eval` like autowiring-validation does
- Test wasn't verified against existing working implementation

**Impact**: False failure, blocks CI even though configs are correct

---

## Ultrathinking Analysis

### Pattern Recognition

1. **Disk space is the dominant issue**
   - Affects 2/3 failures
   - Both Linux builds failed for same reason
   - Root cause: Large Rust packages + limited temp space
   - Even with 70GB cachix setup, still hits limits

2. **Test implementation is separate issue**
   - Independent from disk space
   - Result of using wrong tool for the job
   - Could have been prevented by reusing autowiring-validation approach

3. **No cascading failures**
   - Each failure is independent
   - Fixing one doesn't fix others
   - Requires separate remediation for each

### Why These Failures Matter

**Disk Space (nix jobs)**:
- Blocks all Linux builds
- Prevents validating cross-platform functionality
- Will recur on every CI run until fixed
- Affects: home configs, packages, system configs

**Test Bug (justfile-activation)**:
- Blocks PRs that modify configs
- Creates noise (false failures)
- Undermines trust in CI results
- Was supposed to improve CI, made it worse

### Critical Insights

1. **bitwarden-cli is the bottleneck**
   - Large, slow to build, disk-intensive
   - Used in all home configurations
   - Previous solution exists: `just cache-bitwarden-linux`
   - This should have been run before pushing changes

2. **nix flake show limitations**
   - Known issue with complex flakes
   - autowiring-validation already has working solution
   - Should have reused proven approach
   - Documentation would have prevented this

3. **Temp directory location matters**
   - `/mnt` has 1GB free, `/nix` has 74GB free
   - Nix uses TMPDIR for builds
   - Can't easily change this in GitHub Actions
   - Root cause of space exhaustion

---

## Recommended Actions (Prioritized)

### CRITICAL (Do Now)

**1. Fix justfile-activation test** ✅ DONE
- Status: Fixed in commit a12eb4e
- Changed from `nix flake show` to `nix eval`
- Now matches autowiring-validation approach
- Should pass on next run

**2. Cache bitwarden-cli for Linux**
```bash
just cache-bitwarden-linux
```
- Builds for both aarch64-linux and x86_64-linux
- Pushes to cachix
- Takes ~30 minutes (one-time)
- Eliminates disk space issue

### HIGH (This Week)

**3. Add pre-build disk check**
```yaml
- name: check disk space
  run: |
    df -h
    AVAIL=$(df /mnt | tail -1 | awk '{print $4}' | sed 's/G//')
    if (( $(echo "$AVAIL < 5" | bc -l) )); then
      echo "❌ Less than 5GB free on /mnt"
      exit 1
    fi
```

**4. Document cachix workflow**
- Add to README: "Large packages must be cached before CI"
- List packages that need pre-caching: bws, rust-analyzer, etc.
- Link to `just cache-linux-package` recipe

### MEDIUM (This Month)

**5. Monitor disk usage trends**
- Track disk usage over time
- Identify which packages cause spikes
- Proactively cache before they become issues

**6. Optimize build order**
- Build large packages first (fail fast)
- Consider splitting nix job by output type
- Use build matrix more effectively

### LOW (Future)

**7. Consider self-hosted runners**
- Pros: Larger disks, persistent cache, better performance
- Cons: Maintenance overhead, cost
- Decision: Defer until CI becomes critical path

---

## Verification

To verify fixes work:

### 1. Test nix eval command locally
```bash
# Should return: ["blackphos","stibnite"]
nix eval .#darwinConfigurations --apply 'x: builtins.attrNames x' --json

# Should return: ["blackphos-nixos","orb-nixos","stibnite-nixos"]
nix eval .#nixosConfigurations --apply 'x: builtins.attrNames x' --json
```

### 2. Cache bitwarden-cli
```bash
just cache-bitwarden-linux
# Wait for build + push to complete
```

### 3. Trigger new CI run
```bash
gh workflow run ci.yaml --ref beta
gh run watch  # Monitor progress
```

**Expected outcome**:
- ✅ justfile-activation: passes (test fixed)
- ✅ nix (aarch64-linux): passes (bws cached)
- ✅ nix (x86_64-linux): passes (bws cached)

---

## Lessons Learned

### 1. Pre-cache large dependencies
Large Rust packages must be cached before CI:
- bitwarden-cli (bws): ~1GB
- rust-analyzer: ~800MB
- Others as identified

Recipe exists: `just cache-linux-package <name>`

### 2. Reuse proven test approaches
autowiring-validation job already had correct implementation.
Should have copied that instead of reinventing.

### 3. Verify tests locally first
Could have caught the nix flake show issue by:
- Testing command locally
- Comparing output to autowiring-validation
- Reading nix flake show docs

### 4. Disk monitoring is essential
Would have seen trend toward exhaustion before it became critical.
Add monitoring in next CI iteration.

---

## Related Documentation

- **Full analysis**: `ci-run-18500875303-analysis.md`
- **CI testing strategy**: `ci-testing-strategy.md`
- **Justfile activation redesign**: `justfile-activation-redesign.md`
- **Cache recipe**: `justfile:794-885` (cache-linux-package)

---

## Status

**Fixed**:
- ✅ justfile-activation test (commit a12eb4e)

**Pending**:
- ⏳ Cache bitwarden-cli for Linux (manual step required)

**Next Run Expected**:
- ✅ justfile-activation: will pass
- ❌ nix (aarch64-linux): will fail until bws cached
- ❌ nix (x86_64-linux): will fail until bws cached
