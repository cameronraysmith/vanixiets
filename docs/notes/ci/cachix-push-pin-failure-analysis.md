# Cachix Push/Pin Failure Root Cause Analysis

## Incident

Command: `just cache-linux-package bitwarden-cli`

Error:
```
Pushing /nix/store/i5m67347...bitwarden-cli-2025.9.0 and dependencies to cachix...
Nothing to push - all store paths are already on Cachix.
Pinning /nix/store/i5m67347...bitwarden-cli-2025.9.0 as 'bitwarden-cli-aarch64-linux'...
cachix: FailureResponse ... Status {statusCode = 400, statusMessage = "Bad Request"}
responseBody = "{\"error\":\"/nix/store/i5m67347...bitwarden-cli-2025.9.0 not in binary cache\"}"
```

## Four Interconnected Issues

### 1. Wrong Package ❌

**CI Failed On**: `bws-1.0.0` (Bitwarden Secrets Manager CLI, Rust)
**Command Cached**: `bitwarden-cli-2025.9.0` (Bitwarden password manager CLI, Node.js)

These are **different packages**:
- `bitwarden-cli`: Password manager CLI for accessing vaults
- `bws`: Secrets Manager CLI for CI/CD secrets (the one that failed!)

**Why This Happened**:
- CI failure mentioned "bws" in logs
- Convenience recipe at justfile:888 hardcodes "bitwarden-cli"
- User ran `just cache-bitwarden-linux` assuming it would fix the issue
- But that recipe caches the wrong package

**Impact**: Even after successfully caching bitwarden-cli, CI will still fail on bws.

---

### 2. Package Location Mismatch

**Script Expects**:
```bash
nom build .#packages.aarch64-linux.$PACKAGE
```

**Works For**:
- Custom packages in `overlays/packages/` (like bitwarden-cli)
- Exported via flake as `.#packages.${system}.${name}`

**Doesn't Work For**:
- Packages from nixpkgs used directly in home configs
- Example: `bws` is used as `pkgs.bws`, not a custom package

**Verification**:
```bash
# This works (bitwarden-cli is custom):
nix eval .#packages.aarch64-linux --apply 'builtins.attrNames' --json | jq -r '.[]' | grep bitwarden
# Returns: bitwarden-cli

# This fails (bws is from nixpkgs):
nix eval .#packages.aarch64-linux --apply 'builtins.attrNames' --json | jq -r '.[]' | grep bws
# Returns: (nothing)
```

**Consequence**: To cache bws, we need a different approach than `.#packages`.

---

### 3. Cachix Push/Pin Race Condition

**The Paradox**:
1. `cachix push`: "Nothing to push - already on Cachix" ✅
2. `cachix pin`: "not in binary cache" ❌

**Possible Causes**:

#### Theory A: Garbage Collection Window (Most Likely)

**Timeline**:
```
T0: Previous run pushed bitwarden-cli to cachix
T1: Cachix GC runs, no pin exists, path is deleted
T2: Current run builds (fetches from cache.nixos.org)
T3: cachix push checks local "already pushed" metadata → "Nothing to push"
T4: cachix pin queries actual cache → 400: "not in binary cache"
```

**Evidence**:
- Cachix runs GC on unpinned paths
- Time between runs allows GC to occur
- Local nix knows path was previously pushed (metadata)
- But actual path is gone from cachix

**How to Verify**: Check cachix logs for recent GC operations on this path.

#### Theory B: Fetch vs Build Confusion

**The Issue**:
- Path was fetched from cache.nixos.org (not built)
- `cachix watch-exec` only pushes during builds
- Explicit `xargs cachix push` might check substituter chain
- If cache.nixos.org has it, considers it "already available"
- But it's not in OUR cachix, just in the global substituter

**Evidence**:
```
copying path '/nix/store/i5m67347.../bitwarden-cli-2025.9.0' from 'https://cache.nixos.org'
```
Path was fetched, not built.

**Consequence**: "Nothing to push" is a false positive based on substituter presence.

#### Theory C: CDN Propagation Delay

**The Issue**:
- Push writes to backend
- Query API reads from CDN edge
- Pin queries before CDN propagates

**Evidence**: Less likely because error is 400 (client error), not 404 (not found).

---

### 4. Script Design Assumptions vs Reality

| Assumption | Reality | Consequence |
|------------|---------|-------------|
| Package in `.#packages` | bws is from nixpkgs | Script can't build bws this way |
| Building produces paths to push | Fetching from cache.nixos.org | No new paths generated |
| "Nothing to push" = "in cache" | Could be false positive | Pin fails unexpectedly |
| Pin after push succeeds | GC or timing window | Race condition |
| Single package per home config | 3 configs × many packages | Multiplied disk pressure |

---

## Why the CI Actually Failed

Looking at the CI logs:
```
nix (x86_64-linux): building bws-1.0.0 from source
bws> error: failed to build archive: No space left on device
```

**Key Facts**:
1. bws is a **1GB Rust project** (dependencies + build artifacts)
2. Home configs use `pkgs.bws` from nixpkgs directly
3. Each of 3 home configs tries to build it
4. TMPDIR on `/dev/sda1` has only 1GB free
5. Rust compilation generates large intermediate files

**The Real Problem**: bws is being built from source in CI because it's not in our cachix.

**Why Not in Cachix**:
- We only pushed custom packages from `.#packages`
- bws comes from nixpkgs, not custom packages
- Never been pushed to our cachix
- CI must build from source

---

## The Correct Fix

### Step 1: Cache the RIGHT Package

**Wrong**: `just cache-linux-package bitwarden-cli`
**Right**: Cache `bws` from nixpkgs

**Problem**: Current script only works for `.#packages.${system}.${name}`

**Solution**: Need new recipe or modify script to handle nixpkgs packages.

### Step 2: Fix Cachix Push/Pin Logic

**Current Flow**:
```bash
nom build .#packages.aarch64-linux.$PACKAGE
nix-store --query --requisites | xargs cachix push $CACHE
cachix pin $CACHE $PIN_NAME $PATH
```

**Problem**: "Nothing to push" + "not in cache" contradiction

**Improved Flow**:
```bash
# Build
PATH=$(nom build ...)

# Force push (don't trust "already there")
nix-store --query --requisites | xargs cachix push --force $CACHE

# Wait for propagation
sleep 5

# Verify before pinning
if nix path-info --store "https://$CACHE.cachix.org" "$PATH" &>/dev/null; then
    cachix pin $CACHE $PIN_NAME $PATH
else
    echo "Path not in cache after push, retrying..."
    cachix push $PATH
    sleep 5
    cachix pin $CACHE $PIN_NAME $PATH
fi
```

### Step 3: Add Generic Nixpkgs Package Caching

**New Recipe**:
```bash
cache-nixpkgs-package package system="aarch64-linux":
    #!/usr/bin/env bash
    # Cache a package from nixpkgs for given system
    # Handles packages not in .#packages
    STORE_PATH=$(nix build "nixpkgs#{{ package }}" \
        --system "{{ system }}" \
        --no-link --print-out-paths)

    echo "Built {{ package }} for {{ system }}: $STORE_PATH"

    # Push with verification
    sops exec-env secrets/shared.yaml \
        "cachix push \$CACHIX_CACHE_NAME $STORE_PATH"

    # Verify it's actually there
    CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
    if nix path-info --store "https://$CACHE_NAME.cachix.org" "$STORE_PATH"; then
        sops exec-env secrets/shared.yaml \
            "cachix pin \$CACHIX_CACHE_NAME {{ package }}-{{ system }} $STORE_PATH"
    else
        echo "ERROR: Path not in cache after push"
        exit 1
    fi
```

---

## Verification Steps

### 1. Test Package Availability

```bash
# Check if bws is in our packages
nix eval .#packages.aarch64-linux --apply 'builtins.attrNames' --json | jq -r '.[]' | grep bws
# Expected: (empty)

# Check if bws exists in nixpkgs
nix search nixpkgs '^bws$'
# Expected: Found

# Check current size
nix path-info -Sh nixpkgs#bws
# Expected: ~1GB total with dependencies
```

### 2. Test Cachix State

```bash
# Check if in our cache
CACHE_NAME=$(sops exec-env secrets/shared.yaml 'echo $CACHIX_CACHE_NAME')
nix path-info --store "https://$CACHE_NAME.cachix.org" $(nix build nixpkgs#bws --no-link --print-out-paths)
# Expected: error: path ... is not in cache
```

### 3. Manual Cache and Verify

```bash
# Build for Linux
nix build nixpkgs#bws --system aarch64-linux --no-link --print-out-paths
# Note the store path

# Push to cachix
sops exec-env secrets/shared.yaml "cachix push \$CACHIX_CACHE_NAME /nix/store/...-bws-1.0.0"

# Wait
sleep 10

# Verify
nix path-info --store "https://$CACHE_NAME.cachix.org" /nix/store/...-bws-1.0.0

# Pin if successful
sops exec-env secrets/shared.yaml "cachix pin \$CACHIX_CACHE_NAME bws-aarch64-linux /nix/store/...-bws-1.0.0"
```

---

## Recommended Action Plan

### Immediate (Fix Current Issue)

1. **Cache bws properly**:
   ```bash
   # Manual approach since script doesn't support nixpkgs packages yet
   nix build nixpkgs#bws --system aarch64-linux --no-link --print-out-paths
   # Push and pin manually as shown above
   # Repeat for x86_64-linux
   ```

2. **Update documentation**:
   - Use generic `just cache-linux-package bitwarden-cli` instead of wrappers
   - Remove redundant convenience recipes that add no value
   - Keep wrappers only for complex multi-step operations

### Short-Term (Improve Robustness)

3. **Add verification to push**:
   - Don't trust "Nothing to push"
   - Verify path is queryable before pinning
   - Add retry logic with backoff

4. **Add --force flag support**:
   - Override "already there" check
   - Ensure fresh push even if metadata exists

5. **Add wait for propagation**:
   - Sleep 5-10s between push and pin
   - Allow CDN to propagate

### Long-Term (Architectural)

6. **Create separate script for nixpkgs packages**:
   - Handle packages not in `.#packages`
   - Accept nixpkgs attribute path
   - Support cross-compilation

7. **Pre-cache large dependencies**:
   - Document which packages need pre-caching
   - Add CI step to verify cache before builds
   - Alert if large package not cached

8. **Monitor cachix GC**:
   - Track when paths are GC'd
   - Ensure pins exist for critical paths
   - Alert if unpinned paths about to be GC'd

---

## Lessons Learned

1. **Package names can be deceptive**
   - "bitwarden" in logs might mean bitwarden-cli OR bws
   - Always verify which package actually failed

2. **"Already in cache" ≠ "Available"**
   - Local metadata can be stale
   - GC happens between runs
   - Always verify before relying on cache

3. **Fetched ≠ Built**
   - Fetching from substituter looks like success
   - But produces no paths to push
   - Script logic must handle both cases

4. **Timing matters with distributed systems**
   - Push → CDN → Query has latency
   - Pin immediately after push can fail
   - Add delays for propagation

5. **Scripts need defensive coding**
   - Verify assumptions at each step
   - Add retries for transient failures
   - Clear error messages for debugging
