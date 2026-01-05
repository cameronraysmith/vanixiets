---
description: Initialize beads issue tracking with manual sync workflow (no auto-staging hooks)
---

# Beads initialization

Initialize beads issue tracking in a project with manual control over when issue database changes are staged and committed.

## Initialize without auto-staging hooks

```bash
bd init --skip-hooks -p <prefix> -q
```

Replace `<prefix>` with the project-specific issue prefix (e.g., `INFRA`, `TS`, `CLAN`).

The `--skip-hooks` flag prevents installation of git hooks that would automatically stage `.beads/*.jsonl` files on every commit.
We keep the default merge driver (no `--skip-merge-driver`) since it only activates during merge conflicts and doesn't auto-stage.

For completely invisible beads usage without affecting repository collaborators, consider `--stealth` mode instead (see below).

## Post-init cleanup

After `bd init` completes, perform these required cleanup steps:

```bash
touch .beads/issues.jsonl            # bd init bug: without this, auto-flush uses interactions.jsonl
git restore AGENTS.md                # discard auto-generated changes
echo "README.md" >> .beads/.gitignore
```

## Manual sync workflow

### Committing beads changes

When you've made changes to issues via `bd` commands, flush the database to JSONL and stage the files manually:

```bash
bd hooks run pre-commit   # flush DB→JSONL + stage .beads/*.jsonl files
git commit -m "chore(issues): <description of changes>"
```

Example commit messages:
- `chore(issues): add epic for CI integration`
- `chore(issues): update story status for authentication module`
- `chore(issues): close completed infrastructure stories`

### Importing after git operations

After any git operation that changes commits (pull, checkout, merge, rebase), import JSONL changes back to the database:

```bash
bd sync --import-only   # JSONL→DB without staging
```

This ensures your local beads database stays synchronized with the JSONL files tracked in git.

## Rationale

Manual sync workflow provides explicit control over when issue tracking state enters git history, allowing you to:

- Batch multiple issue operations into single commits
- Separate issue updates from code changes
- Review staged issue changes before committing
- Avoid automatic staging during experimental work

The merge driver remains enabled to handle merge conflicts in JSONL files during collaborative workflows, but it doesn't auto-stage changes during normal operations.
