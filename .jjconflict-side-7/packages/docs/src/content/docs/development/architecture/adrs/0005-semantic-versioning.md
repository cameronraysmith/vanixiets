---
title: "ADR-0005: Semantic versioning with semantic-release"
---

## Status

Accepted

## Context

Automated versioning requires choosing:
- Version numbering scheme (semantic versioning, calendar versioning, etc.)
- Automation tool (semantic-release, changesets, release-please, manual)
- Plugin configuration for monorepo handling
- Changelog generation approach
- Initial release strategy

## Decision

Use [semantic-release](https://semantic-release.gitbook.io/) for automated versioning based on conventional commits.

## Configuration

### Disabled by default
- All semantic-release configuration is in place
- GitHub Actions workflow exists but triggers are commented out
- Releases are disabled initially to allow template customization
- Enable later by uncommenting workflow triggers

**Rationale:** Template users need time to customize before public releases.

### Changelog and git plugins
- Includes `@semantic-release/changelog` plugin - generates CHANGELOG.md
- Includes `@semantic-release/git` plugin - commits CHANGELOG.md back with `[skip ci]`
- Package.json version remains `"0.0.0-development"`
- Semantic-release determines actual version from commits
- No npm publishing (`npmPublish: false`)
- Git plugin commits only CHANGELOG.md (no package.json version updates)

**Rationale:**
- Provides complete audit trail in repository
- Automated commits are minimal and skip CI to prevent loops
- Version in package.json stays as development placeholder
- Actual version comes from git tags

### Monorepo scoping
- Uses `semantic-release-monorepo` plugin
- Automatically scopes analysis to commits affecting each package
- No manual path filtering needed in CI

**Rationale:**
- Plugin handles per-package change detection automatically
- Scales to multiple packages without workflow complexity

### Main branch only
- Single `main` branch (no beta branch initially)
- Initial version: `0.1.0` (when releases enabled)

**Rationale:**
- Simpler for template users starting out
- Can add beta/next branches later if needed

## Consequences

**Positive:**
- Fully automated version bumps from commit messages
- Conventional commits enforced via semantic-release requirements
- Changelog automatically generated and committed
- Clear version history through git tags
- Scales to multiple packages with monorepo plugin

**Negative:**
- Requires team discipline with conventional commit format
- Initial setup complexity with multiple plugins
- Package.json version doesn't reflect actual version (confusing for new contributors)

**Neutral:**
- Disabled by default requires manual enablement
- Commit message format becomes critical (can't release without proper format)
