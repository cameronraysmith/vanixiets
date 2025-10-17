# Workspace synchronization quick reference

Fast reference for common workspace sync operations.

## Essential commands

### Generate manifest
```bash
cd ~/projects/nix-workspace/nix-config
./scripts/generate-workspace-manifest.sh
```

### Verify local state
```bash
./scripts/sync-workspace-manifest.sh
```

### Sync on new machine
```bash
# Preview first
./scripts/sync-workspace-manifest.sh --dry-run

# Then sync
./scripts/sync-workspace-manifest.sh --sync
```

## Common workflows

### Initial setup on new machine

```bash
# 1. Clone nix-config
mkdir -p ~/projects/nix-workspace
cd ~/projects/nix-workspace
git clone git@github.com:USER/nix-config.git
cd nix-config

# 2. Preview what will be synced
./scripts/sync-workspace-manifest.sh --dry-run

# 3. Sync workspaces
./scripts/sync-workspace-manifest.sh --sync --log-file ~/sync.log
```

### Update manifest after changes

```bash
# 1. Regenerate
./scripts/generate-workspace-manifest.sh

# 2. Review changes
git diff manifests/workspace-manifest.yaml

# 3. Commit and push
git add manifests/workspace-manifest.yaml
git commit -m "chore(manifests): update workspace manifest"
git push
```

### Sync specific workspace

```bash
# Verify single workspace
./scripts/sync-workspace-manifest.sh -w nix-workspace

# Sync single workspace
./scripts/sync-workspace-manifest.sh --sync -w planning-workspace
```

## Flag reference

### Generation flags

| Flag | Purpose | Example |
|------|---------|---------|
| `--help` | Show help | `./generate-workspace-manifest.sh --help` |
| `--debug` | Write JSON artifact | `./generate-workspace-manifest.sh --debug` |
| `--dry-run` | Preview without writing | `./generate-workspace-manifest.sh --dry-run` |
| `--quiet` | Suppress output | `./generate-workspace-manifest.sh --quiet` |
| `--workspace NAME` | Single workspace | `./generate-workspace-manifest.sh -w nix-workspace` |

### Sync flags

| Flag | Purpose | Example |
|------|---------|---------|
| `--help` | Show help | `./sync-workspace-manifest.sh --help` |
| `--sync` | Apply changes | `./sync-workspace-manifest.sh --sync` |
| `--dry-run` | Preview changes | `./sync-workspace-manifest.sh --dry-run` |
| `--quiet` | Suppress progress | `./sync-workspace-manifest.sh --quiet` |
| `--verbose` | Detailed output | `./sync-workspace-manifest.sh --verbose` |
| `--workspace NAME` | Single workspace | `./sync-workspace-manifest.sh -w nix-workspace` |
| `--manifest FILE` | Custom manifest | `./sync-workspace-manifest.sh --manifest /tmp/test.yaml` |
| `--log-file FILE` | Detailed logging | `./sync-workspace-manifest.sh --log-file ~/sync.log` |

## Troubleshooting shortcuts

### Check manifest validity
```bash
cd ~/projects/nix-workspace/nix-config
cue vet manifests/workspace-manifest.yaml schemas/workspace-manifest/schema.cue
```

### Find repos with issues
```bash
# Missing remotes
./scripts/sync-workspace-manifest.sh | grep "⚠"

# Missing locally
./scripts/sync-workspace-manifest.sh | grep "✗"
```

### Inspect manifest
```bash
# Count workspaces
yq '.workspaces | keys | length' manifests/workspace-manifest.yaml

# Count total repos
yq '.workspaces | to_entries | map(.value.repos | length) | add' manifests/workspace-manifest.yaml

# List workspace names
yq '.workspaces | keys' manifests/workspace-manifest.yaml

# Show specific workspace
yq '.workspaces.nix-workspace' manifests/workspace-manifest.yaml
```

### Manual remote operations
```bash
# Add missing remote
git remote add upstream https://github.com/user/repo.git

# Update remote URL
git remote set-url origin git@github.com:user/repo.git

# Verify remotes
git remote -v
```

## Safety checklist

Before syncing on new machine:
- [ ] Backed up any existing work in `~/projects/`
- [ ] Reviewed dry-run output
- [ ] Tested on single workspace first
- [ ] Have network connectivity to git remotes
- [ ] SSH keys configured if using git@ URLs

Before regenerating manifest:
- [ ] No uncommitted changes in critical repos
- [ ] Current manifest committed to git
- [ ] Verified all workspaces accessible

## Exit codes

| Code | Meaning | Action |
|------|---------|--------|
| 0 | Success or verify complete | Continue |
| 1 | Sync failures | Check log output |
| 2 | Catastrophic error | Check manifest/dependencies |

## See also

- Full workflow documentation: `docs/notes/workspace-sync/workflow.md`
- Generation script: `scripts/generate-workspace-manifest.sh`
- Sync script: `scripts/sync-workspace-manifest.sh`
- Manifest schema: `schemas/workspace-manifest/schema.cue`
- Current manifest: `manifests/workspace-manifest.yaml`
