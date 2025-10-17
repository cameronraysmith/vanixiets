# Workspace synchronization workflow

Complete workflow for migrating development environments between machines using workspace manifests.

## Overview

The workspace synchronization system consists of two tools:

1. **Generation** (`generate-workspace-manifest.sh`): Scans local workspace directories and creates a manifest capturing all repositories and their remote configurations
2. **Synchronization** (`sync-workspace-manifest.sh`): Reads the manifest and syncs local machine state to match it

## Quick reference

| Task | Command | Mode | Safety |
|------|---------|------|--------|
| Generate manifest | `generate-workspace-manifest.sh` | Read | Safe (read-only) |
| Update manifest | `generate-workspace-manifest.sh` | Read | Safe (overwrites YAML) |
| Verify local state | `sync-workspace-manifest.sh` | Verify | Safe (read-only) |
| Preview sync changes | `sync-workspace-manifest.sh --dry-run` | Dry-run | Safe (no changes) |
| Sync specific workspace | `sync-workspace-manifest.sh --sync -w WORKSPACE` | Sync | Modifies (additive) |
| Sync all workspaces | `sync-workspace-manifest.sh --sync` | Sync | Modifies (additive) |

## System architecture

```
Source Machine (stibnite)              New Machine (target)
┌─────────────────────────┐           ┌─────────────────────────┐
│ ~/projects/             │           │ ~/projects/             │
│   nix-workspace/        │           │   (empty or partial)    │
│   planning-workspace/   │           │                         │
│   ...                   │           │                         │
└────────┬────────────────┘           └────────┬────────────────┘
         │                                     │
         │ generate-workspace-manifest.sh      │
         ▼                                     │
┌─────────────────────────┐                   │
│ workspace-manifest.yaml │───────────────────┤
│ (343 repos, 18 spaces)  │  copy via        │
│ ├─ remotes              │  git/rsync       │
│ ├─ default branches     │                  │
│ └─ paths                │                  ▼
└─────────────────────────┘           sync-workspace-manifest.sh
         │                                     │
         │ (commit to nix-config)              │ (reads manifest)
         ▼                                     ▼
    Version controlled                  Clones & configures
```

## Phase 1: Initial manifest generation

### On source machine (e.g., stibnite)

Generate the initial manifest from your existing workspace structure.

```bash
# Navigate to nix-config
cd ~/projects/nix-workspace/nix-config

# Generate manifest for all workspaces
./scripts/generate-workspace-manifest.sh

# Output: manifests/workspace-manifest.yaml created
```

Expected output:
```
=== Workspace Manifest Generation ===

Scanning workspaces in /Users/crs58/projects/...
  ✓ nix-workspace (142 repos)
  ✓ planning-workspace (28 repos)
  ✓ sciops-workspace (45 repos)
  ...

Validating with CUE schema...
  ✓ Schema validation passed

Exporting to YAML...
  ✓ manifests/workspace-manifest.yaml

=== ✓ Generated manifest for 18 workspaces (343 repositories) ===
```

### Inspect the generated manifest

```bash
# View manifest structure
head -50 manifests/workspace-manifest.yaml

# Check specific workspace
yq '.workspaces.nix-workspace' manifests/workspace-manifest.yaml

# Count repositories
yq '.workspaces | to_entries | map(.value.repos | length) | add' manifests/workspace-manifest.yaml
```

### Commit to version control

```bash
# Stage and commit the manifest
git add manifests/workspace-manifest.yaml
git commit -m "feat(manifests): add workspace synchronization manifest

Captures current state of 18 workspaces with 343 repositories.
Includes all remote configurations for migration to new machines."

# Push to remote
git push
```

## Phase 2: Verification workflow

### Verify local state matches manifest

Run on the source machine to ensure the manifest accurately reflects reality.

```bash
# Verify all workspaces
./scripts/sync-workspace-manifest.sh

# Verify specific workspace
./scripts/sync-workspace-manifest.sh --workspace nix-workspace

# Quiet mode (summary only)
./scripts/sync-workspace-manifest.sh --quiet
```

Expected output for clean state:
```
=== Workspace Manifest Sync ===

Mode: Verification (read-only)

=== nix-workspace ===
  ✓ nix-config: exists with correct remotes
  ✓ atuin: exists with correct remotes
  ✓ cachix: exists with correct remotes
  ...

=== Summary ===

Processed 18 workspaces, 343 repositories

Status:
  ✓ 343 repos match manifest
  ⚠ 0 repos have missing remotes
  ✗ 0 repos not found locally

All repositories are in sync with manifest
```

### Handle discrepancies

If verification finds issues:

```
=== nix-workspace ===
  ✓ nix-config: exists with correct remotes
  ⚠ atuin: missing remote 'upstream'
  ✗ new-repo: not found locally

=== Summary ===
Status:
  ✓ 320 repos match manifest
  ⚠ 15 repos have missing remotes
  ✗ 8 repos not found locally
```

**For missing remotes:**
```bash
# Add the missing remote manually
cd ~/projects/nix-workspace/atuin
git remote add upstream https://github.com/atuinsh/atuin.git
```

**For missing repos:**
Either:
1. Clone them manually: `git clone <url> ~/projects/workspace/repo`
2. Remove them from manifest if no longer needed
3. Use sync mode to auto-clone (see Phase 3)

## Phase 3: Sync on new machine

### Prerequisites on target machine

Ensure nix-config is already set up:

```bash
# Clone your nix-config (if not already done)
mkdir -p ~/projects/nix-workspace
cd ~/projects/nix-workspace
git clone git@github.com:USER/nix-config.git
cd nix-config

# Verify scripts are executable
chmod +x scripts/generate-workspace-manifest.sh
chmod +x scripts/sync-workspace-manifest.sh

# Verify dependencies available
command -v git cue jq
```

### Preview what will be synced

```bash
# Dry-run mode shows what would happen
./scripts/sync-workspace-manifest.sh --dry-run

# Dry-run for specific workspace
./scripts/sync-workspace-manifest.sh --dry-run --workspace planning-workspace
```

Output:
```
=== Workspace Manifest Sync ===

Mode: Dry-run (preview changes)

=== planning-workspace ===
  [DRY-RUN] Would create workspace directory: /Users/crs58/projects/planning-workspace
  [DRY-RUN] Would clone context-engineering-dspy from origin
  [DRY-RUN] Would clone mcp-prompts-server from origin
  [DRY-RUN] Would add remote 'upstream' to mcp-prompts-server
  ...

=== Summary ===
Would clone: 28 repositories
Would add: 15 remotes
```

### Sync specific workspace (recommended first)

Start with a small, non-critical workspace:

```bash
# Sync a test workspace first
./scripts/sync-workspace-manifest.sh --sync --workspace test-workspace

# Sync a small workspace
./scripts/sync-workspace-manifest.sh --sync --workspace mojo-workspace
```

### Verify synced workspace

```bash
# Check repos were cloned
ls -la ~/projects/test-workspace/

# Verify remotes configured correctly
cd ~/projects/test-workspace/some-repo
git remote -v
```

### Sync all workspaces

Once confident in the sync process:

```bash
# Sync everything with detailed logging
./scripts/sync-workspace-manifest.sh --sync --log-file ~/sync-$(date +%Y%m%d).log

# Monitor progress (verbose mode)
./scripts/sync-workspace-manifest.sh --sync --verbose

# Quiet mode (summary only, faster)
./scripts/sync-workspace-manifest.sh --sync --quiet
```

### Handle sync failures

If sync encounters errors:

```
=== Summary ===

Sync operations:
  ✓ 280 repos cloned successfully
  ✓ 50 remotes added to existing repos
  ✗ 3 repos failed to clone (network error)

Clone failures (3):
  - planning-workspace/large-repo: timeout cloning from origin
  - sciops-workspace/private-repo: authentication failed
  - nix-workspace/broken-url: repository not found
```

**Resolve failures manually:**

```bash
# Check network connectivity
ping github.com

# For authentication issues, check SSH keys
ssh -T git@github.com

# For specific repo failures, clone manually
cd ~/projects/planning-workspace
git clone --verbose <url> large-repo
```

## Phase 4: Manifest maintenance

### Update manifest after workspace changes

When you've added or removed repositories on source machine:

```bash
# Regenerate manifest
cd ~/projects/nix-workspace/nix-config
./scripts/generate-workspace-manifest.sh

# Review changes
git diff manifests/workspace-manifest.yaml

# Commit updates
git add manifests/workspace-manifest.yaml
git commit -m "chore(manifests): update workspace manifest after adding new repos"
git push
```

### Pull manifest updates on other machines

```bash
# On target machine, pull latest manifest
cd ~/projects/nix-workspace/nix-config
git pull

# Verify what changed
./scripts/sync-workspace-manifest.sh

# Sync new additions
./scripts/sync-workspace-manifest.sh --sync
```

### Selective workspace updates

```bash
# Only sync specific workspace after manifest update
./scripts/sync-workspace-manifest.sh --workspace planning-workspace --sync

# Verify multiple specific workspaces
for ws in nix-workspace planning-workspace sciops-workspace; do
  ./scripts/sync-workspace-manifest.sh --workspace $ws
done
```

## Advanced usage

### Debug mode

Investigate manifest generation issues:

```bash
# Write intermediate JSON for inspection
./scripts/generate-workspace-manifest.sh --debug

# Examine raw JSON
cat manifests/workspace-manifest.json | jq '.workspaces.nix-workspace'
```

### Custom manifest location

Use alternate manifest for testing:

```bash
# Generate test manifest
./scripts/generate-workspace-manifest.sh > /tmp/test-manifest.yaml

# Sync from alternate manifest
./scripts/sync-workspace-manifest.sh --manifest /tmp/test-manifest.yaml --dry-run
```

### Filter workspace generation

Generate manifest for single workspace:

```bash
# Only scan nix-workspace
./scripts/generate-workspace-manifest.sh --workspace nix-workspace
```

### Detailed logging

Enable comprehensive logging for troubleshooting:

```bash
# Generate with debug output
./scripts/generate-workspace-manifest.sh --debug 2>&1 | tee generate-debug.log

# Sync with detailed log file
./scripts/sync-workspace-manifest.sh --sync --log-file ~/sync-detailed.log --verbose
```

### Verify before activate

Integrate verification into deployment workflow:

```bash
# In deployment script or justfile
./scripts/sync-workspace-manifest.sh || echo "Warning: workspace drift detected"
```

## Troubleshooting

### Issue: Repos with no remotes

**Symptom:**
```
⚠ test-workspace/local-only: no remotes configured
```

**Cause:** Local experimental repositories without remote origins.

**Resolution:**
- Expected behavior for local-only repos
- These will be skipped during sync operations
- Either add a remote or accept the warning

### Issue: URL mismatches

**Symptom:**
```
⚠ atuin: remote 'origin' URL mismatch
  Actual:   https://github.com/cameronraysmith/atuin.git
  Manifest: git@github.com:cameronraysmith/atuin.git
```

**Cause:** Changed from HTTPS to SSH (or vice versa) after manifest generation.

**Resolution:**
```bash
# Update remote URL to match manifest
cd ~/projects/nix-workspace/atuin
git remote set-url origin git@github.com:cameronraysmith/atuin.git

# Or regenerate manifest to capture current state
cd ~/projects/nix-workspace/nix-config
./scripts/generate-workspace-manifest.sh
```

### Issue: Uncommitted changes block operations

**Symptom:**
```
⚠ nix-config: uncommitted changes detected, skipping git operations
```

**Cause:** Safety mechanism prevents modifying repos with uncommitted work.

**Resolution:**
```bash
# Commit or stash changes
cd ~/projects/nix-workspace/nix-config
git status
git add . && git commit -m "wip: save work in progress"

# Or stash temporarily
git stash push -m "temporary for sync"
```

### Issue: Permission errors

**Symptom:**
```
✗ Failed to create workspace directory: /Users/crs58/projects/test-workspace
```

**Cause:** Insufficient permissions for `~/projects/` directory.

**Resolution:**
```bash
# Check permissions
ls -la ~/projects/

# Create directory manually if needed
mkdir -p ~/projects/test-workspace
chmod 755 ~/projects/test-workspace
```

### Issue: CUE validation fails

**Symptom:**
```
✗ Manifest validation failed
  workspaces.nix-workspace.repos.0.remotes: invalid URL format
```

**Cause:** Manifest contains invalid data structure.

**Resolution:**
```bash
# Validate manually
cd ~/projects/nix-workspace/nix-config
cue vet manifests/workspace-manifest.yaml schemas/workspace-manifest/schema.cue

# Regenerate manifest from scratch
./scripts/generate-workspace-manifest.sh

# If regeneration fails, check for corrupted git repos
fd -t d '^\.git$' ~/projects/nix-workspace/ -x git -C {//} fsck
```

### Issue: Network timeouts during sync

**Symptom:**
```
✗ Failed to clone large-repo from origin: timeout
```

**Cause:** Large repositories or slow network.

**Resolution:**
```bash
# Clone problematic repos manually with progress
cd ~/projects/workspace
git clone --verbose --progress <url> large-repo

# Or increase git timeout
git config --global http.postBuffer 524288000
git config --global http.lowSpeedLimit 1000
git config --global http.lowSpeedTime 600
```

## Integration with nix-config workflow

### Pre-migration checklist

Before migrating to a new machine:

1. ✓ Generate fresh manifest on source machine
2. ✓ Verify manifest is complete and accurate
3. ✓ Commit and push manifest to nix-config
4. ✓ Verify nix-config pushed successfully
5. ✓ Document any local-only repos that shouldn't sync

### Post-migration verification

After syncing to new machine:

```bash
# Verify all critical workspaces present
ls -la ~/projects/

# Verify key repositories
cd ~/projects/nix-workspace/nix-config
git status
git remote -v

# Verify manifest matches local state
./scripts/sync-workspace-manifest.sh

# Test a few repos can pull updates
cd ~/projects/nix-workspace/atuin
git fetch --all
```

### Continuous verification

Add to regular workflow:

```bash
# Weekly verification
./scripts/sync-workspace-manifest.sh > /tmp/workspace-status.txt

# Alert on drift
if ! ./scripts/sync-workspace-manifest.sh --quiet; then
  echo "Workspace drift detected, review required"
fi
```

### Automation considerations

For automated sync in deployment scripts:

```bash
#!/usr/bin/env bash
# Automated workspace sync

set -euo pipefail

MANIFEST="$HOME/projects/nix-workspace/nix-config/manifests/workspace-manifest.yaml"
LOG_FILE="$HOME/.cache/workspace-sync-$(date +%Y%m%d-%H%M%S).log"

if [ ! -f "$MANIFEST" ]; then
  echo "Error: Manifest not found at $MANIFEST"
  exit 1
fi

# Verify first
echo "Verifying workspace state..."
if ./scripts/sync-workspace-manifest.sh --quiet; then
  echo "All workspaces in sync"
  exit 0
fi

# Sync if differences found
echo "Syncing workspaces..."
if ./scripts/sync-workspace-manifest.sh --sync --log-file "$LOG_FILE" --quiet; then
  echo "Sync completed successfully"
  exit 0
else
  echo "Sync encountered errors, see: $LOG_FILE"
  exit 1
fi
```

## Best practices

### Manifest hygiene

- Regenerate manifest after significant workspace changes
- Commit manifest updates with descriptive messages
- Keep manifest in version control (never gitignore it)
- Review manifest diffs before committing

### Safety practices

- Always run verification mode first on new machines
- Use `--dry-run` before `--sync` for unfamiliar manifests
- Start with selective workspace sync before full sync
- Keep backups of critical workspaces before syncing
- Never run sync with uncommitted changes in repos

### Performance optimization

- Use `--quiet` flag for faster execution when output not needed
- Sync specific workspaces rather than all at once
- Schedule large syncs during off-hours for network-intensive operations
- Use `--log-file` only when debugging to reduce I/O

### Workflow integration

- Integrate verification into pre-commit hooks
- Add manifest regeneration to workspace maintenance routines
- Document workspace-specific considerations in workspace READMEs
- Use manifest as documentation of project structure
