---
name: issues-beads-init
description: Initialize beads issue tracking with dolt persistence for new repositories.
disable-model-invocation: true
---
# Beads initialization

Initialize beads issue tracking in a project with dolt database persistence.

## Initialize without auto-staging hooks

```bash
bd init --skip-hooks -p <prefix> -q
```

Replace `<prefix>` with the project-specific issue prefix (e.g., `INFRA`, `TS`, `CLAN`).

The `--skip-hooks` flag prevents installation of git hooks that would automatically stage `.beads/*.jsonl` files on every commit.
We keep the default merge driver (no `--skip-merge-driver`) since it only activates during merge conflicts and doesn't auto-stage.

For completely invisible beads usage without affecting repository collaborators, consider `--stealth` mode instead (see below).

## Alternative: Stealth mode (invisible beads)

For personal use without affecting repository collaborators:

```bash
bd init --stealth -p <prefix> -q
```

Stealth mode configures beads to be completely invisible to git:
- Adds `.beads/` to `.git/info/exclude` (local gitignore, not committed)
- Sets `no-git-ops: true` in `.beads/config.yaml`, suppressing git operations in agent session protocols
- Sets up Claude Code integration automatically
- Perfect for personal issue tracking without team coordination

With stealth mode, beads changes remain local and never enter git history.

## Post-init cleanup

After `bd init` completes, perform these cleanup steps:

```bash
# Review AGENTS.md - the new auto-generated version is minimal and useful:
# - Points to 'bd onboard' for getting started
# - Contains brief quick reference commands
# - Includes session completion protocol
# Customize if needed, or keep the generated version.

echo "README.md" >> .beads/.gitignore
```

## Dolt persistence

After initializing beads, mutations auto-commit to the dolt database.
Port configuration is handled by the `BEADS_DOLT_SERVER_PORT` environment variable, set declaratively by home-manager `dolt-config.nix`.
Do not hardcode a port in `.beads/metadata.json` as this suppresses auto-start for fork contributors who lack the matching dolt server.

Add a dolt remote for replication (dual-surface: SQL + CLI):

```bash
bd dolt remote add origin <url>
```

Push to the dolt remote for backup:

```bash
bd dolt push
```

## Backup configuration

Enable JSONL backup for offline or non-dolt recovery:

```bash
bd config set backup.enabled true
```

Backup is also available via `bd backup` for on-demand snapshots.

## Rationale

Beads uses a dolt database backend for issue persistence.
Mutations auto-commit when `dolt.auto-commit` is enabled, eliminating manual serialization steps.
The `bd dolt push` command replicates state to the git remote via `refs/dolt/data` for backup and cross-machine sync.

## Configuring no-git-ops mode

To suppress git commands in AI agent session protocols:

```bash
bd config set no-git-ops true
```

This configures `bd prime` to output stealth mode instructions, ensuring agents perform beads operations without attempting git operations.
Useful when you want manual control over when commits happen.

## See also

Additional commands for working with beads:

- `bd onboard` - Display integration snippet for AGENTS.md
- `bd prime` - Show AI-optimized workflow context
- `bd quickstart` - View quick start guide
- `bd setup` - Install AI editor integrations
