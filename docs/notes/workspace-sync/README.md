# Workspace synchronization documentation

Documentation for the workspace synchronization system that manages migration of development environments between machines.

## What is workspace synchronization?

The workspace synchronization system captures the state of all git repositories across your `~/projects/*-workspace/` directories and provides tools to recreate that structure on new machines.

This enables:
- Migrating development environments to new hardware
- Setting up consistent workspace structures across multiple machines
- Documenting project dependencies and remote configurations
- Automating repository cloning and remote setup

## Documentation structure

### [workflow.md](./workflow.md)
Comprehensive workflow guide covering:
- Initial manifest generation
- Verification procedures
- Sync operations on new machines
- Manifest maintenance
- Troubleshooting
- Best practices

**Read this first** for complete understanding of the system.

### [quick-reference.md](./quick-reference.md)
Quick lookup for:
- Essential commands
- Common workflows
- Flag reference tables
- Troubleshooting shortcuts

**Use this** for day-to-day operations after understanding the workflow.

## Quick start

### On source machine (first time)

```bash
cd ~/projects/nix-workspace/nix-config

# Generate manifest
./scripts/generate-workspace-manifest.sh

# Commit to git
git add manifests/workspace-manifest.yaml
git commit -m "feat(manifests): add workspace synchronization manifest"
git push
```

### On new machine

```bash
cd ~/projects/nix-workspace/nix-config

# Preview
./scripts/sync-workspace-manifest.sh --dry-run

# Sync
./scripts/sync-workspace-manifest.sh --sync
```

## System components

### Scripts
- `scripts/generate-workspace-manifest.sh` - Phase 1: Manifest generation
- `scripts/sync-workspace-manifest.sh` - Phase 2: Synchronization

### Artifacts
- `manifests/workspace-manifest.yaml` - Current workspace state (version controlled)
- `schemas/workspace-manifest/schema.cue` - Validation schema
- `schemas/workspace-manifest/test-fixture.json` - Schema test data

## When to use

### Manifest generation
Run when:
- Setting up workspace sync for the first time
- Adding/removing repositories from workspaces
- Remote URLs have changed
- Preparing to migrate to a new machine

### Verification
Run when:
- Checking if local state matches manifest
- After pulling manifest updates
- Debugging workspace discrepancies

### Synchronization
Run when:
- Setting up a new machine
- Restoring workspace structure after reset
- Applying manifest updates to existing machine

## Safety guarantees

The sync tool:
- Never removes existing repositories
- Never modifies working trees
- Never changes checked-out branches
- Skips repos with uncommitted changes
- Only performs additive operations (clone, remote add)

## Getting help

```bash
# Generation help
./scripts/generate-workspace-manifest.sh --help

# Sync help
./scripts/sync-workspace-manifest.sh --help
```

## Related documentation

- Nix development practices: `~/.claude/commands/preferences/nix-development.md`
- Git workflow: `~/.claude/commands/preferences/git-version-control.md`
- Incident response: `docs/notes/nixpkgs-incident-response.md`
