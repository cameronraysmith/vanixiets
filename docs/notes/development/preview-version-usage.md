# Semantic Release Version Preview

Preview what version semantic-release would publish when merging the current branch to a target branch.

## Overview

The `preview-version` tool answers the question: "What production version will be released when this PR merges to main?"

It works by:
1. Creating a temporary git worktree at the target branch
2. Simulating a merge of your current branch
3. Running semantic-release in dry-run mode
4. Displaying the version that would be published

## Quick Start

```bash
# Preview version for root package when merging to main
just preview-version

# Preview version for docs package when merging to main
just preview-version main packages/docs

# Using bun directly (root only)
bun run preview-version
```

## Configuration

### Branch Configuration

Both root and package `package.json` files now include beta as a prerelease branch:

```json
{
  "release": {
    "branches": [
      { "name": "main" },
      { "name": "beta", "prerelease": true }
    ]
  }
}
```

This means:
- Commits to `main` → production releases (e.g., `1.2.3`)
- Commits to `beta` → prerelease versions (e.g., `1.2.3-beta.1`)
- Merging `beta` → `main` → production release with all beta commits

### Monorepo Support

The tool uses semantic-release-monorepo for per-package versioning:
- Each package has its own version and release cycle
- Tags are namespaced: `docs-v1.0.0`, `api-v2.0.0`, etc.
- Commits are attributed to packages based on file paths

## Usage Examples

### Preview root package version

```bash
# When on beta branch, preview what version main would get
just preview-version main
```

### Preview specific package version

```bash
# Preview docs package version when merging beta → main
just preview-version main packages/docs

# Preview docs version when merging feature branch → beta
just preview-version beta packages/docs
```

### Direct script invocation

```bash
# Root package on main
./scripts/preview-version.sh main

# Docs package on main
./scripts/preview-version.sh main packages/docs
```

## Expected Output

```
═══════════════════════════════════════════════════════════════
semantic-release version preview
═══════════════════════════════════════════════════════════════
current branch:  beta
target branch:   main
package:         packages/docs
───────────────────────────────────────────────────────────────

creating temporary worktree at main...
simulating merge of beta → main...

running semantic-release analysis...

[semantic-release output...]

═══════════════════════════════════════════════════════════════
next version: 1.0.0
release type: minor
═══════════════════════════════════════════════════════════════
```

## Common Scenarios

### Pre-merge PR validation

```bash
# On feature branch, check what version would be released
git checkout 42-feature-auth
just preview-version main packages/docs
```

### Beta → Main promotion

```bash
# On beta branch with multiple commits
git checkout beta
just preview-version main

# Shows the final production version that will be released
# when beta merges to main
```

### No version bump required

If there are no semantic commits (feat, fix, etc.) since the last release:

```
no version bump required
no semantic commits found since last release
```

### Merge conflicts

If the current branch cannot be cleanly merged into the target:

```
error: merge conflicts detected
please resolve conflicts in your branch before previewing
```

## Differences from test-release

| Feature | test-release | preview-version |
|---------|--------------|-----------------|
| Purpose | Test current branch release | Preview merge outcome |
| Branch context | Current branch | Target branch (simulated) |
| Use case | Validate config/commits | Preview before merging |
| Git changes | None | Temporary worktree |

## Troubleshooting

### "Target branch does not exist"

Ensure the target branch exists in your local repository:

```bash
git fetch origin
git branch -a  # List all branches
```

### "Package path does not exist"

Verify the package path is correct relative to repository root:

```bash
ls packages/docs  # Should show package contents
```

### GitHub token errors

The tool requires a GitHub token for semantic-release verification.
If running locally, either:

1. Set GITHUB_TOKEN environment variable
2. Use sops to load from secrets:
   ```bash
   sops exec-env secrets/shared.yaml 'just preview-version main packages/docs'
   ```

### Version not displayed

Check that:
1. Your commits follow conventional commit format (`feat:`, `fix:`, etc.)
2. The target branch is configured in `package.json` release.branches
3. There are commits since the last release tag

## Adaptation for Other Repositories

### typescript-nix-template

Already configured with bun and semantic-release-monorepo.
Copy these files:

```bash
# From nix-config to typescript-nix-template
cp scripts/preview-version.sh ../typescript-nix-template/scripts/
cp -r docs/notes/development/preview-version-usage.md \
  ../typescript-nix-template/docs/notes/development/
```

Update package.json:
```json
{
  "scripts": {
    "preview-version": "./scripts/preview-version.sh"
  }
}
```

Add to justfile (if present):
```just
[group('CI/CD')]
preview-version target="main" package="":
  ./scripts/preview-version.sh {{target}} {{package}}
```

### python-nix-template

Requires adapting to yarn workspaces:

1. Copy and modify preview-version.sh:
   - Change `bunx semantic-release` → `yarn workspace <package> semantic-release`
   - Update script path in package.json

2. Update package.json:
   ```json
   {
     "scripts": {
       "preview-version": "./scripts/preview-version.sh"
     }
   }
   ```

3. Add similar just recipe

## Implementation Details

### Git Worktree Approach

The script uses git worktrees to safely simulate merges without affecting your working directory:

1. Creates temporary directory in `$TMPDIR`
2. Adds worktree at target branch
3. Performs test merge (discarded after analysis)
4. Runs semantic-release in worktree context
5. Cleans up automatically (even on errors)

This is safer than:
- Creating temporary branches (pollutes ref namespace)
- Using detached HEAD (confusing state)
- Running in main working directory (risky)

### Version Parsing

The script parses semantic-release output to extract:
- Next version number (`1.2.3` or `1.2.3-beta.1`)
- Release type (`major`, `minor`, `patch`)
- Whether a release is needed

### Monorepo Tag Format

semantic-release-monorepo automatically configures tag format as:
```
<package-name>-v<version>
```

Examples:
- Root package: `v1.0.0`
- Docs package: `docs-v1.0.0`
- API package: `api-v2.0.0`

This prevents tag collisions in monorepos.

## See Also

- [Semantic Release Documentation](https://semantic-release.gitbook.io/)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [semantic-release-monorepo Plugin](https://github.com/pmowrer/semantic-release-monorepo)
- [Pre-release Workflow](https://semantic-release.gitbook.io/semantic-release/recipes/release-workflow/pre-releases)
