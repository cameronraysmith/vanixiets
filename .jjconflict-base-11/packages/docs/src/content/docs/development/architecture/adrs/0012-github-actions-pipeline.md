---
title: "ADR-0012: GitHub Actions CI/CD pipeline"
---

## Status

Accepted

## Context

CI/CD pipelines can be implemented with various platforms:
- **GitHub Actions** - integrated with GitHub, YAML-based workflows
- **GitLab CI** - GitLab-native, YAML-based
- **CircleCI** - dedicated CI platform, config via YAML
- **Jenkins** - self-hosted, highly customizable
- **Buildkite** - agent-based, self-hosted runners
- **Drone** - container-native, self-hosted

For GitHub-hosted projects, the choice is primarily:
1. GitHub Actions (native)
2. External CI platform (CircleCI, Travis, etc.)

Pipeline architecture considerations:
- Workflow separation (CI vs release vs deploy)
- Matrix strategy for multiple packages
- Artifact reuse between jobs
- Caching strategies

## Decision

Use **GitHub Actions** with modular workflows and matrix strategies.

## Workflow Structure

This template includes three main workflows:

### ci.yaml
**Purpose:** Continuous integration on all commits

**Runs on:** PRs and pushes to main

**Steps:**
- GitGuardian secret scanning
- Nix flake checks
- Unit and E2E tests across packages
- Build artifacts uploaded for deployment

**Design:** Matrix strategy for packages (each package tested independently, parallel execution)

### release.yaml
**Purpose:** Automated versioning and changelog generation

**Runs on:** Disabled by default (triggers commented out), manual trigger available

**Steps:**
- Runs semantic-release for each package
- Creates GitHub releases and tags
- Commits CHANGELOG.md back to repository with `[skip ci]`

**Design:** Matrix strategy per package, disabled by default for template customization

### deploy-docs.yaml
**Purpose:** Deploy docs package to Cloudflare Workers

**Runs on:** Manual trigger or on successful CI completion

**Steps:**
- Downloads build artifact from CI
- Deploys to Cloudflare Workers using wrangler

## Key Design Decisions

### Test job uses matrix for packages

**Rationale:**
- Each package tested independently (isolation)
- Parallel execution when possible (speed)
- Artifacts uploaded per package (reusability)
- Easy to add new packages (just extend matrix)

### Build job reuses test artifacts

**Decision:** Build happens during test job, artifacts uploaded for deployment job.

**Rationale:**
- Avoids redundant builds (build once, deploy multiple times)
- Faster CI execution (no rebuild in deploy job)
- Consistent artifacts (deploy exactly what was tested)

### Modular workflows

**Decision:** Separate workflows for CI, release, deployment instead of one monolithic workflow.

**Rationale:**
- Easier to understand (each workflow has clear purpose)
- Easier to modify (change deployment without affecting CI)
- Can trigger independently (manual deployment without full CI)
- Better failure isolation (release failure doesn't block deploy)

## Rationale for GitHub Actions

**Positive:**
- **Native GitHub integration** - no external accounts, permissions managed in GitHub
- **Free for public repos** - no cost for open source
- **Generous free tier** for private repos
- **Matrix strategies** built-in for monorepo testing
- **Artifact storage** between jobs
- **Large ecosystem** of community actions
- **Nix support** - can use Nix in GitHub Actions easily

**Negative:**
- Vendor lock-in to GitHub
- YAML can become verbose
- Debugging requires pushing commits (no local testing)
- Runner limitations (macOS runners expensive)

## Trade-offs

**Positive:**
- Zero external dependencies for CI/CD
- Easy onboarding (everyone knows GitHub)
- Matrix strategies scale to multiple packages
- Artifact reuse reduces CI time and cost

**Negative:**
- YAML workflows can be hard to test locally
- Need to manage GitHub Secrets for sensitive data
- Workflow syntax learning curve

**Neutral:**
- Need to maintain multiple workflow files
- Must carefully manage workflow triggers to avoid loops

## Consequences

See [CI/CD Setup](/about/contributing/ci-cd-setup/) for detailed configuration.

**For developers:**
- CI runs automatically on all PRs
- Can view workflow logs in GitHub UI
- Can manually trigger deployment workflow

**For operations:**
- Secrets managed in GitHub repository settings
- Workflow changes require PR review
- Can re-run failed workflows from GitHub UI

**For template users:**
- Must enable release workflow explicitly (triggers commented out)
- Must set up Cloudflare credentials for deployment
- Can customize workflows for their needs
