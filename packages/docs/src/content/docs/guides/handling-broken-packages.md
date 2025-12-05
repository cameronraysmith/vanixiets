---
title: Handling broken packages
sidebar:
  order: 7
---

Systematic approach to fixing broken packages from nixpkgs unstable using the hotfixes infrastructure.

## Quick reference

| Scenario | Strategy | File | Recovery time |
|----------|----------|------|---------------|
| Single package broken | Stable fallback | modules/nixpkgs/overlays/hotfixes.nix | 5 minutes |
| Tests fail only | Build modification | modules/nixpkgs/overlays/overrides.nix | 5 minutes |
| Fix exists in PR | Upstream patch | modules/nixpkgs/overlays/channels.nix (patches list) | 10 minutes |
| Multiple packages broken | Flake.lock rollback | flake.lock | 2 minutes |
| Darwin-specific issue | Platform hotfix | modules/nixpkgs/overlays/hotfixes.nix (darwin section) | 5 minutes |

## Incident workflow

### Phase 1: Detection and assessment

#### 1.1 Detect breakage

Symptoms:
- `darwin-rebuild switch` fails
- `nix flake check` reports errors
- Specific package build fails
- System activation fails

Capture error:
```bash
# Save full error output
darwin-rebuild build --flake . 2>&1 | tee ~/incident-$(date +%Y%m%d-%H%M%S).log

# Or for specific package
nix build .#packages.aarch64-darwin.myPackage 2>&1 | tee ~/incident-package.log
```

#### 1.2 Identify broken package(s)

From error output, identify:
- Package name (e.g., `buf`, `ghc_filesystem`)
- Error type (compilation, tests, runtime)
- Platform specificity (darwin only? linux too?)

Check hydra status:
```bash
# Visit hydra for the package on your system
# https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.SYSTEM
# Example: https://hydra.nixos.org/job/nixpkgs/trunk/buf.aarch64-darwin

# Green = building in unstable
# Red = failing in unstable (confirms breakage)
```

#### 1.3 Assess scope

Questions to answer:
1. How many packages are affected?
   - Single package → Use hotfix
   - Multiple (5+) → Consider rollback

2. Is it platform-specific?
   - Darwin only → Use platform-specific hotfix section
   - All platforms → Use cross-platform section

3. Is upstream fix available?
   - PR exists → Use patches.nix
   - No fix yet → Use stable fallback

4. Can I work around it?
   - Tests only → Use overrides with doCheck = false
   - Compilation → Use stable or patches

### Phase 2: Resolution

#### Strategy A: Stable fallback (fastest, recommended for single packages)

When to use:
- Package completely broken in unstable
- No immediate upstream fix
- Package works in stable

Steps:

1. Edit modules/nixpkgs/overlays/hotfixes.nix:

```nix
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.aarch64-darwin
    # Error: [paste relevant error line]
    # Issue: [link to upstream issue if exists]
    # TODO: Remove when [condition]
    # Added: $(date +%Y-%m-%d)
    packageName
    ;
})
```

2. Test the fix:

```bash
cd ~/projects/nix-workspace/infra

# Test flake check
nix flake check 2>&1 | grep -E "(checking|error)" | head -20

# Test darwin-rebuild
darwin-rebuild build --flake . --dry-run

# If successful, activate
darwin-rebuild switch --flake .
```

3. Commit the hotfix:

```bash
git add modules/nixpkgs/overlays/hotfixes.nix
git commit -m "fix(overlays): add packageName stable hotfix for llvm 21.x issue

- Package fails to compile with llvm 21.x in unstable
- Using stable version (llvm 19.x) until upstream fixes land
- Hydra: https://hydra.nixos.org/job/nixpkgs/trunk/packageName.aarch64-darwin
- TODO: Remove when upstream llvm 21.x compatibility PR merges"
```

Time: 5 minutes total

#### Strategy B: Build modification (for test failures)

When to use:
- Package compiles but tests fail
- Runtime works fine
- Test failure is known issue

Steps:

1. Add override to modules/nixpkgs/overlays/overrides.nix:

```nix
# In the overlay's attribute set, add:
# packageName: [brief issue description]
# Issue: Tests fail with [compiler/runtime] version X
# Reference: [link to upstream issue]
# TODO: Remove when [specific condition]
# Date added: $(date +%Y-%m-%d)
packageName = prev.packageName.overrideAttrs (old: {
  doCheck = false;
  # If also marked broken:
  # meta = (old.meta or {}) // { broken = false; };
});
```

2. Test (auto-imported, no rebuild needed):

```bash
cd ~/projects/nix-workspace/infra

# Verify override applied
nix eval .#packages.aarch64-darwin.packageName.dontCheck
# Should output: true

# Test build
nix build .#packages.aarch64-darwin.packageName

# If successful, rebuild system
darwin-rebuild switch --flake .
```

3. Commit the override:

```bash
git add modules/nixpkgs/overlays/overrides.nix
git commit -m "fix(overlays): disable packageName tests due to clang 21.x

- Tests fail with -Werror on new warnings
- Runtime functionality unaffected
- Reference: https://github.com/upstream/packageName/issues/XXX
- TODO: Remove when upstream fixes tests"
```

Time: 5 minutes total

#### Strategy C: Upstream patch application

When to use:
- Upstream PR exists with fix
- Fix not yet merged or not in your channel
- Need specific fix without full stable fallback

Patches are now integrated directly into the channels.nix overlay, which provides a `patched` attribute containing nixpkgs with all patches applied.

Steps:

1. Find the PR patch URL:

```bash
# For nixpkgs PR #123456
# URL: https://github.com/NixOS/nixpkgs/pull/123456.patch
```

2. Edit modules/nixpkgs/overlays/channels.nix to add the patch:

```nix
# In the patched section (around lines 41-46), add to the patches list:
patched = import (prev.applyPatches {
  name = "nixpkgs-patched";
  src = inputs.nixpkgs.outPath;
  patches = [
    # nixpkgs PR#123456: Fix packageName compilation on darwin
    # TODO: Remove when merged to unstable
    (prev.fetchpatch {
      url = "https://github.com/NixOS/nixpkgs/pull/123456.patch";
      hash = "";  # Leave empty initially
    })
  ];
}) nixpkgsConfig;
```

3. Get the hash:

```bash
cd ~/projects/nix-workspace/infra

# Try to build - it will fail with hash mismatch
nix build .#packages.aarch64-darwin.patched.hello 2>&1 | grep "got:"

# Output example:
# got:    sha256-ABC123...

# Copy the hash and update channels.nix
```

4. Use patched package in hotfixes.nix:

```nix
{
  inherit (final.patched)
    # Uses nixpkgs with PR#123456 applied
    # TODO: Remove when PR merges and reaches unstable
    packageName
    ;
}
```

5. Test and commit:

```bash
# Test
nix flake check
darwin-rebuild build --flake . --dry-run

# Commit both files
git add modules/nixpkgs/overlays/channels.nix modules/nixpkgs/overlays/hotfixes.nix
git commit -m "fix(overlays): apply nixpkgs#123456 for packageName

- Applies upstream fix from PR#123456
- Fixes [describe issue]
- TODO: Remove when PR merges to unstable"
```

Time: 10 minutes total

#### Strategy D: Flake.lock rollback (for widespread breakage)

When to use:
- Multiple packages broken (5+)
- Hotfixes would be too numerous
- Need immediate system stability
- Plan to apply selective hotfixes later

Steps:

1. Find last working commit:

```bash
cd ~/projects/nix-workspace/infra

# Check flake.lock history
git log --oneline -10 flake.lock

# Or check when system last worked
git log --since="1 week ago" --oneline
```

2. Rollback flake.lock:

```bash
# Option 1: Rollback flake.lock only
git show COMMIT:flake.lock > flake.lock

# Option 2: Full repo rollback (if needed)
git checkout COMMIT flake.lock

# Update flake
nix flake update
```

3. Test and commit:

```bash
# Test
darwin-rebuild build --flake . --dry-run

# If successful
git add flake.lock
git commit -m "fix(flake): rollback nixpkgs to working version

- Multiple packages broken in latest unstable
- Rolled back to nixpkgs commit from $(git log COMMIT -1 --format=%ci)
- Will apply selective hotfixes as needed"

darwin-rebuild switch --flake .
```

4. Plan selective updates:

After system is stable, update specific packages:
```bash
# Update non-broken packages
nix flake lock --update-input some-other-input

# Add hotfixes for packages that need unstable features
# Edit modules/nixpkgs/overlays/hotfixes.nix with unstable packages you need
```

Time: 2 minutes for rollback, additional time for selective updates

### Phase 3: Verification

#### 3.1 Verify system builds

```bash
cd ~/projects/nix-workspace/infra

# Full flake check
nix flake check 2>&1 | tee verify-check.log

# Darwin rebuild
darwin-rebuild build --flake . 2>&1 | tee verify-build.log

# If successful
darwin-rebuild switch --flake .
```

#### 3.2 Verify package works

```bash
# Test the specific package
nix build .#packages.aarch64-darwin.packageName

# Run it if applicable
./result/bin/packageName --version

# Check package metadata
nix eval .#packages.aarch64-darwin.packageName.meta.broken
# Should be false or not exist
```

#### 3.3 Document resolution

Add notes to commit message or incident log:
- What broke
- Root cause
- Resolution strategy used
- Links to upstream issues/PRs
- Removal conditions

### Phase 4: Monitoring and cleanup

#### 4.1 Set removal reminder

Create tracking TODO in the hotfix file:

```nix
inherit (final.stable)
  # TODO: Remove when upstream fixes land
  # Check: https://hydra.nixos.org/job/nixpkgs/trunk/packageName.aarch64-darwin
  # Added: 2025-10-13
  packageName
  ;
```

#### 4.2 Weekly review

```bash
cd ~/projects/nix-workspace/infra

# List active hotfixes
echo "=== Active Hotfixes ==="
grep -B2 -A2 "inherit.*stable" modules/nixpkgs/overlays/hotfixes.nix

# List active overrides
echo "=== Active Overrides ==="
grep -B2 -A2 "overrideAttrs" modules/nixpkgs/overlays/overrides.nix

# List active patches
echo "=== Active Patches ==="
grep -A5 "patches = \[" modules/nixpkgs/overlays/channels.nix
```

For each hotfix/override/patch:
1. Check if still needed (hydra status)
2. Test without it (comment out, run flake check)
3. Remove if passing
4. Update TODO if still needed

#### 4.3 Cleanup when fixed

```bash
cd ~/projects/nix-workspace/infra

# For hotfixes: Remove inherit entry from modules/nixpkgs/overlays/hotfixes.nix

# For overrides: Remove override entry from modules/nixpkgs/overlays/overrides.nix

# For patches: Remove fetchpatch entry from modules/nixpkgs/overlays/channels.nix

# Test
nix flake check
darwin-rebuild build --flake . --dry-run

# Commit
git add modules/nixpkgs/overlays/
git commit -m "fix(overlays): remove packageName hotfix after upstream fix

- Upstream fix merged in nixpkgs commit abc123
- Package now builds successfully in unstable
- Verified: https://hydra.nixos.org/job/nixpkgs/trunk/packageName.aarch64-darwin"
```

## Advanced scenarios

### Multiple platform breakage

When same package breaks on multiple platforms:

```nix
# Cross-platform section (affects all)
{
  inherit (final.stable)
    # Broken on all platforms
    universalPackage
    ;
}

# Or platform-specific
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  inherit (final.stable) darwinPackage;
})
// (prev.lib.optionalAttrs prev.stdenv.isLinux {
  inherit (final.stable) linuxPackage;
})
```

### Package exists in stable with different name

```nix
# Map unstable name to stable equivalent
{
  unstableName = final.stable.stableName;
}
```

### Package doesn't exist in stable

Options:
1. Use patches.nix to apply fix
2. Use override to fix build
3. Use older unstable (flake.lock)
4. Build from source with custom derivation

### Dependency chain breakage

When package A breaks because dependency B broke:

```nix
# Fix the root cause (dependency B)
{
  inherit (final.stable)
    dependencyB  # This fixes both B and A
    ;
}

# Or fix just the broken dependency
{
  packageA = prev.packageA.override {
    dependencyB = final.stable.dependencyB;
  };
}
```

## Templates

### Hotfix template (modules/nixpkgs/overlays/hotfixes.nix)

```nix
// (prev.lib.optionalAttrs prev.stdenv.isDarwin {
  inherit (final.stable)
    # https://hydra.nixos.org/job/nixpkgs/trunk/PACKAGE.aarch64-darwin
    # Error: [brief error description]
    # Issue: [upstream issue/PR link]
    # TODO: Remove when [specific condition]
    # Added: YYYY-MM-DD
    packageName
    ;
})
```

### Override template (modules/nixpkgs/overlays/overrides.nix)

```nix
# Add to the overlay's attribute set:
# packageName: [brief description of issue]
# Issue: [detailed description]
# Symptom: [what fails]
# Reference: [upstream issue/PR link]
# TODO: Remove when [condition]
# Date added: YYYY-MM-DD
packageName = prev.packageName.overrideAttrs (old: {
  # Modifications here
  doCheck = false;
});
```

### Patch template (modules/nixpkgs/overlays/channels.nix)

```nix
# Add to the patches list in the patched section:
(prev.fetchpatch {
  # nixpkgs PR#12345: Fix packageName compilation on darwin
  # TODO: Remove when merged to unstable
  url = "https://github.com/NixOS/nixpkgs/pull/12345.patch";
  hash = "sha256-AAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAAA=";
})
```

### Commit message template

```
fix(overlays): [action] [package] [brief reason]

- [Detailed description of issue]
- [Strategy used and why]
- [Verification performed]
- [Links to upstream issues/PRs]
- TODO: Remove when [specific condition]
```

## Common errors and solutions

### Error: infinite recursion encountered

Cause: Using flake.lib or similar recursive reference

Solution: Check overlay order in default.nix, ensure inputs' comes first

### Error: attribute 'stable' missing

Cause: Overlay not applied or wrong order

Solution: Verify modules/nixpkgs/overlays/channels.nix is loaded (it provides stable, unstable, patched attrs), check overlay composition order

### Error: hash mismatch in patch

Expected: This happens on first build when adding a new patch

Solution: Copy the "got:" hash from error output to the fetchpatch in channels.nix

### Error: package not found in stable

Cause: Package name differs or doesn't exist in stable

Solution:
```bash
# Search in both channels
nix search nixpkgs/nixpkgs-unstable#packageName
nix search nixpkgs/nixpkgs-stable#packageName
```

### Warning: dirty git tree

Expected: When testing changes before commit

Solution: Commit changes or use `--impure` if needed for testing

## Preventive measures

### Before nixpkgs update

```bash
# Check hydra status for critical packages
# Visit: https://hydra.nixos.org/jobset/nixpkgs/trunk

# Update in test branch first
git checkout -b test-nixpkgs-update
nix flake update
darwin-rebuild build --flake . --dry-run

# If successful, merge
git checkout main
git merge test-nixpkgs-update
```

### Regular maintenance

Weekly:
- Review active hotfixes (are they still needed?)
- Check hydra status for hotfixed packages
- Test removing old hotfixes

Monthly:
- Update nixpkgs and test
- Clean up resolved hotfixes/overrides/patches
- Document patterns for future incidents

### Incident log

Keep a log of incidents and resolutions:

```bash
# Create incident log entry
cat >> docs/notes/incident-log.md << EOF

## $(date +%Y-%m-%d): [Package] breakage

Issue: [description]
Strategy: [which strategy used]
Files changed: [list]
Resolution time: [X minutes]
Removal: [when/how to remove]

EOF
```

## See also

- [ADR-0017: Dendritic Overlay Patterns](/development/architecture/adrs/0017-dendritic-overlay-patterns) (architecture documentation)
- https://hydra.nixos.org/jobset/nixpkgs/trunk (build status)
- https://github.com/NixOS/nixpkgs/issues (upstream issues)
- https://nixos.org/manual/nixpkgs/stable/#chap-overlays (overlay documentation)
