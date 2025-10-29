---
title: Semantic Release Version Preview
sidebar:
  order: 8
---

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

### GitHub token not required

**The preview-version tool does NOT require a GitHub token.**

The script uses `--plugins` to exclude `@semantic-release/github`, running only:
- `@semantic-release/commit-analyzer` - determines version bump type
- `@semantic-release/release-notes-generator` - generates release notes

This is safe because dry-run mode skips the steps that @semantic-release/github handles:
- `publish` - creating GitHub releases (skipped in dry-run)
- `success` - commenting on issues/PRs (skipped in dry-run)
- `fail` - creating failure issues (skipped in dry-run)

The only step @semantic-release/github runs in dry-run is `verifyConditions`, which validates the GitHub token. Since we don't need this verification for local preview, we exclude the plugin entirely.

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
4. Runs `bun install` in worktree (instant with global cache)
5. Executes semantic-release with minimal plugins
6. Cleans up automatically (even on errors)

This is safer than:
- Creating temporary branches (pollutes ref namespace)
- Using detached HEAD (confusing state)
- Running in main working directory (risky)

### Plugin Exclusion Strategy

The script runs semantic-release with only essential plugins:

```bash
--plugins @semantic-release/commit-analyzer,@semantic-release/release-notes-generator
```

**Why exclude @semantic-release/github?**

From semantic-release issue #843 and #261 investigations:
- @semantic-release/github requires `GITHUB_TOKEN` even in dry-run mode
- The token is used for `verifyConditions` step to check repository push permissions
- This verification is intentional (helps find config issues before real releases)
- BUT for local preview, this verification adds no value

**What we lose by excluding it:**
- Nothing for version preview purposes
- The plugin only handles publish/success/fail steps (all skipped in dry-run)

**What we gain:**
- No authentication required for local preview
- Faster execution (no GitHub API calls)
- Works in any environment (no secrets needed)

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

## Release Configuration Considerations

### Current Setup: With Changelog Commits

The current configuration includes `@semantic-release/git` plugin which commits CHANGELOG.md:

```json
{
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/changelog",
    "@semantic-release/github",
    "semantic-release-major-tag",
    "@semantic-release/git"  // ← Commits CHANGELOG.md
  ]
}
```

This means each release creates a commit with the changelog before tagging.

### Alternative: Tag-Only Releases (Cleaner History)

For minimal git history pollution, you can remove the `@semantic-release/git` plugin:

```json
{
  "plugins": [
    "@semantic-release/commit-analyzer",
    "@semantic-release/release-notes-generator",
    "@semantic-release/github",  // Creates GitHub releases and git tags
    "semantic-release-major-tag"
  ]
}
```

**Benefits:**
- No automatic commits to your git history
- Cleaner linear history without "chore(release)" commits
- Release notes still available in GitHub Releases
- Git tags still created

**What you lose:**
- No CHANGELOG.md file in repository
- But GitHub Releases serve the same purpose

**GitHub Token Requirements:**

For actual releases (not preview), `@semantic-release/github` needs a token with:

**Personal Access Token (classic):**
- Public repo: `public_repo` scope
- Private repo: `repo` scope

**GitHub Actions GITHUB_TOKEN:**
- `contents: write` - create releases and tags
- `issues: write` - comment on issues (optional, can disable with `successComment: false`)
- `pull-requests: write` - comment on PRs (optional, can disable with `successComment: false`)

Note: Your current config already disables comments (`successComment: false`, `failComment: false`), so you only need `contents: write` for GitHub releases and tags.

## See Also

- [Semantic Release Documentation](https://semantic-release.gitbook.io/)
- [Conventional Commits Specification](https://www.conventionalcommits.org/)
- [semantic-release-monorepo Plugin](https://github.com/pmowrer/semantic-release-monorepo)
- [Pre-release Workflow](https://semantic-release.gitbook.io/semantic-release/recipes/release-workflow/pre-releases)
