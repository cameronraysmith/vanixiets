# Nixpkgs bisect guide

Finding which nixpkgs commit broke your build after flake updates.

## Overview

When `nix flake update nixpkgs` breaks your system and `just verify` fails, this tool uses git bisect to automatically identify the exact nixpkgs commit that introduced the breakage.

## Quick start

```bash
# After nix flake update nixpkgs breaks:
just bisect-nixpkgs
```

That's it! The tool will:
1. Detect the old (working) commit from git history
2. Get the new (broken) commit from current flake.lock
3. Automatically bisect through commits
4. Test each commit with `just verify`
5. Show you the exact breaking commit with GitHub link

## How it works

### Automatic workflow

```bash
# Full automatic bisect
just bisect-nixpkgs
```

**Process**:
1. **Detect commits**: Extracts old commit from `git log flake.lock`
2. **Setup bisect**: Initializes git bisect in ~/projects/nix-workspace/nixpkgs
3. **Iterate**: For each bisect step:
   - Updates flake.lock to test commit
   - Runs `just verify` (flake check + system build)
   - Reports good/bad back to git bisect
4. **Report**: Shows breaking commit with GitHub link
5. **Cleanup**: Restores original flake.lock automatically

**Estimated time**: ~log2(N) iterations where N = commit count
- 100 commits → ~7 iterations
- 1000 commits → ~10 iterations
- Each iteration = time for `just verify` (~2-5 minutes)

### Manual workflow

For more control or to inspect each step:

```bash
# Start bisect
just bisect-nixpkgs-manual start

# Execute one step at a time
just bisect-nixpkgs-manual step

# Check status
just bisect-nixpkgs-manual status

# Abort and cleanup
just bisect-nixpkgs-manual reset
```

## Prerequisites

### Required

1. **Nixpkgs repository**: Must exist at one of:
   - `~/projects/nix-workspace/nixpkgs` (default)
   - Set via: `export NIXPKGS_REPO=/path/to/nixpkgs`

   If missing, clone it:
   ```bash
   git clone https://github.com/nixos/nixpkgs ~/projects/nix-workspace/nixpkgs
   ```

2. **Git history**: Your flake.lock must have git history
   - Needed to extract the old (working) commit
   - If unavailable, provide manually: `GOOD_COMMIT=abc123 just bisect-nixpkgs-manual start`

3. **Working `just verify`**: Must be able to test builds
   - Flake check must work
   - System build must work

### Optional

- **bc command**: For commit count calculations (usually installed)
- **jq command**: For JSON parsing (included in nix-config devShell)

## Usage scenarios

### Scenario 1: Recent update broke everything

```bash
# Yesterday: just activate worked fine
# Today: nix flake update && just verify fails

# Find the breaking commit:
just bisect-nixpkgs

# Result shows:
# First bad commit: def456...
# GitHub: https://github.com/nixos/nixpkgs/commit/def456...
# "llvm: update to 21.0.0"
```

Now you know exactly what changed. Next steps:
- Check if there's a fix in a newer PR
- Apply a hotfix using the hotfixes infrastructure
- Report the issue upstream with the exact commit

### Scenario 2: Multiple updates happened

```bash
# Updated nixpkgs multiple times
# Not sure which update broke it

# Bisect will find the first bad commit automatically
just bisect-nixpkgs
```

### Scenario 3: Specific commit range

```bash
# You know the good commit was abc123
export GOOD_COMMIT=abc123
just bisect-nixpkgs-manual start
just bisect-nixpkgs-manual step  # repeat until done
```

### Scenario 4: Interrupted bisect

```bash
# Started bisect but had to stop
just bisect-nixpkgs-manual status  # check progress

# Continue from where you left off
just bisect-nixpkgs-manual step

# Or abort and start over
just bisect-nixpkgs-manual reset
```

## Understanding the output

### Successful bisect

```
=== Verifying nix-config after updates ===

Step 1/2: Running flake check...
✓ Flake check passed

Step 2/2: Building system configuration (without activation)...
✓ Darwin system builds successfully

=== ✓ All verification passed ===
Safe to activate: just activate

✓ Verification passed - marking as GOOD

ℹ Next commit to test: a1b2c3d
ℹ Run: just bisect-nixpkgs step
```

### Failed bisect iteration

```
=== Verifying nix-config after updates ===

Step 1/2: Running flake check...
✗ Flake check failed

=== ✗ Verification failed ===

✗ Verification failed - marking as BAD

=== Bisect complete! ===

First bad commit: def456789...

GitHub link:
  https://github.com/nixos/nixpkgs/commit/def456789...

Commit message:
llvm: update to 21.0.0

This update introduces breaking changes...
```

### Bisect status

```bash
just bisect-nixpkgs-manual status

# Output:
ℹ === Bisect Status ===

Good commit: abc123
Bad commit:  def456
Nixpkgs repo: /Users/user/projects/nix-workspace/nixpkgs

Current commit: a1b2c3d

Bisect log:
git bisect start
# bad: [def456] current HEAD
# good: [abc123] previous working commit
```

## Advanced usage

### Custom nixpkgs location

```bash
export NIXPKGS_REPO=/custom/path/to/nixpkgs
just bisect-nixpkgs
```

### Manually specify good commit

```bash
# When git history doesn't have it
export GOOD_COMMIT=abc123def456...
just bisect-nixpkgs-manual start
```

### Test specific package failure

The bisect uses `just verify` which tests your entire system. If you want to test only a specific package:

1. Create a custom test script:
   ```bash
   #!/usr/bin/env bash
   nix build .#packages.$(nix eval --raw .#currentSystem).problematic-package
   ```

2. Modify verify-system.sh temporarily to run your test
3. Run bisect
4. Restore verify-system.sh

### Resume interrupted bisect

If you interrupt a bisect (Ctrl-C) or it fails:

```bash
# Check status
just bisect-nixpkgs-manual status

# Continue
just bisect-nixpkgs-manual step

# Or abort
just bisect-nixpkgs-manual reset
```

## Troubleshooting

### "Could not find nixpkgs repository"

**Solution**: Clone the nixpkgs repo:
```bash
git clone https://github.com/nixos/nixpkgs ~/projects/nix-workspace/nixpkgs
```

Or specify custom location:
```bash
export NIXPKGS_REPO=/your/nixpkgs/path
```

### "Could not find previous nixpkgs commit"

**Cause**: No git history for flake.lock

**Solution**: Manually specify the good commit:
```bash
# Find last known good commit from your notes or GitHub
export GOOD_COMMIT=abc123...
just bisect-nixpkgs-manual start
```

### "Bisect already in progress"

**Solution**: Reset and start over:
```bash
just bisect-nixpkgs-manual reset
just bisect-nixpkgs
```

### Verification fails for unrelated reasons

If `just verify` fails for reasons unrelated to the bisect (e.g., syntax error in your config):

1. Fix your config first
2. Commit the fix
3. Start bisect again

### Very large commit range

If bisecting 1000+ commits:

- Consider using manual mode and checking intermediate commits manually
- Or let automatic mode run overnight
- Each iteration takes 2-5 minutes typically

## Integration with incident response

After finding the breaking commit, use the incident response workflow:

```bash
# 1. Bisect found the breaking commit
just bisect-nixpkgs

# 2. Analyze the commit on GitHub
# Check for related PRs, issues, fixes

# 3. Apply appropriate fix using hotfixes infrastructure
# See: docs/notes/nixpkgs-incident-response.md

# Options:
# - Wait for fix in unstable
# - Use stable fallback (overlays/infra/hotfixes.nix)
# - Apply upstream patch (overlays/infra/patches.nix)
# - Override package build (overlays/overrides/package.nix)
```

## Technical details

### State management

Bisect state is stored in:
- `.bisect-nixpkgs-state`: Tracks old/new commits, repo path
- `.flake.lock.bisect-backup`: Backup of original flake.lock
- Git bisect state in nixpkgs repo: `.git/BISECT_*` files

All automatically cleaned up on completion or reset.

### Commit detection

Old commit extraction from git history:
```bash
git log -2 --format="" -p -- flake.lock | \
  grep -A 1 '"nixpkgs"' | \
  grep -E '^\-.*"rev":' | \
  sed 's/.*"rev": "\([^"]*\)".*/\1/'
```

Current commit from flake.lock:
```bash
jq -r '.nodes.nixpkgs.locked.rev' flake.lock
```

### Flake.lock updates

Uses nix flake lock with override:
```bash
nix flake lock --override-input nixpkgs "github:nixos/nixpkgs/$COMMIT"
```

This ensures:
- Correct narHash calculation
- Proper lock file format
- Network fetching as needed

### Exit codes

- `0`: Success (bisect completed)
- `1`: Error (setup failed, verification error)
- `2`: Bisect in progress (use step or reset)

## Files created/modified

### Temporary files (auto-removed)

- `.bisect-nixpkgs-state`: State tracking
- `.flake.lock.bisect-backup`: Original flake.lock
- Git bisect state in nixpkgs repo

### Modified during bisect

- `flake.lock`: Updated for each test commit
- Nixpkgs repo: Git bisect state, HEAD pointer

### Permanent files (you keep)

- Git history with bisect results in your notes

## Best practices

1. **Commit before bisecting**: Ensure working tree is clean
2. **Don't modify during bisect**: Let it run to completion
3. **Document results**: Save the breaking commit info
4. **Report upstream**: Help the community by reporting issues
5. **Use hotfixes**: Apply workarounds while waiting for fixes

## See also

- [nixpkgs-incident-response.md](../nixpkgs-incident-response.md) - What to do after finding the break
- [nixpkgs-hotfixes.md](../nixpkgs-hotfixes.md) - Hotfixes infrastructure
- [verify-system.sh](../../../scripts/verify-system.sh) - Verification script used by bisect
