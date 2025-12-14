---
title: CI/CD Setup
description: Setting up GitHub Actions CI/CD pipeline with Cloudflare Workers deployment
sidebar:
  order: 6
---

This guide walks through setting up the GitHub Actions CI/CD pipeline for automated Cloudflare Workers deployment.

## Prerequisites

1. Cloudflare account with Workers enabled
2. GitHub repository with Actions enabled
3. SOPS installed locally (`nix profile install nixpkgs#sops`)
4. Age key pair for encryption

## Step 1: Create and Encrypt Secrets

### 1.1 Create Cloudflare API Token

1. Visit https://dash.cloudflare.com/profile/api-tokens
2. Click "Create Token"
3. Use "Edit Cloudflare Workers" template or create custom token with:
   - Account.Workers Scripts (Edit)
   - Account.Workers Routes (Edit)
4. Copy the generated token

### 1.2 Get Cloudflare Account ID

1. Visit https://dash.cloudflare.com/
2. Select your account
3. Go to Workers & Pages
4. Find Account ID in the right sidebar

### 1.3 Get Other Service Tokens

Optional but recommended for full CI functionality:

- **CACHIX_AUTH_TOKEN**: Get from https://app.cachix.org/cache/YOUR_CACHE/settings
- **CACHIX_CACHE_NAME**: Your Cachix cache name

### 1.4 Create Unencrypted Secrets File

Create `secrets/shared.yaml` with your secrets:

```yaml
CLOUDFLARE_ACCOUNT_ID: your-actual-account-id
CLOUDFLARE_API_TOKEN: your-actual-api-token
CACHIX_AUTH_TOKEN: your-actual-cachix-token
CACHIX_CACHE_NAME: your-cache-name
CI_AGE_KEY: age-secret-key-1... # CI age private key from .sops.yaml
```

The `CI_AGE_KEY` should be the private key corresponding to the public key:
`age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8` <!-- gitleaks:allow - age public key -->

### 1.5 Encrypt the Secrets File

```bash
# Verify you have the correct age keys configured
cat .sops.yaml

# Encrypt the file in place
sops --encrypt --in-place secrets/shared.yaml

# Verify encryption succeeded
head secrets/shared.yaml
# Should show encrypted content starting with ENC[...]
```

### 1.6 Commit Encrypted Secrets

```bash
git add secrets/shared.yaml
git commit -m "build: add encrypted secrets for CI/CD"
git push
```

## Step 2: Configure GitHub Repository

### 2.1 Upload SOPS Age Key to GitHub Secrets

The CI needs the private age key to decrypt `secrets/shared.yaml`:

```bash
# Extract the CI_AGE_KEY from the encrypted file
sops --decrypt --extract '["CI_AGE_KEY"]' secrets/shared.yaml | gh secret set SOPS_AGE_KEY
```

Or manually:
1. Decrypt the file: `sops secrets/shared.yaml`
2. Copy the `CI_AGE_KEY` value
3. Go to https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions
4. Click "New repository secret"
5. Name: `SOPS_AGE_KEY`
6. Value: Paste the age private key
7. Click "Add secret"

### 2.2 Set GitHub Variables (Optional)

If using Cachix, set these as repository variables (not secrets):

1. Go to https://github.com/YOUR_USERNAME/YOUR_REPO/settings/variables/actions
2. Add variable `CACHIX_CACHE_NAME` with your cache name

Alternatively, the workflow will read from the encrypted `secrets/shared.yaml`.

### 2.3 Configure Fast-forward Merge Workflow

The repository enforces fast-forward-only merges to maintain linear history.
Two workflows handle this:
- `pr-check.yaml`: Validates that PRs can be fast-forward merged (runs automatically)
- `pr-merge.yaml`: Performs the fast-forward merge when `/fast-forward` is commented on a PR

To enable the `/fast-forward` command functionality:

1. Create a fine-grained Personal Access Token (PAT):
   - Go to https://github.com/settings/personal-access-tokens/new
   - Token name: `Fast-forward merge token`
   - Expiration: Set according to your security policy (90 days recommended)
   - Repository access: Select only this repository
   - Repository permissions:
     - **Contents**: Read and write (required for merging)
     - **Issues**: Read and write (required for commenting)
     - **Pull requests**: Read and write (required for PR updates)
   - Click "Generate token" and copy the value immediately

2. Add the PAT as a repository secret:
   ```bash
   gh secret set FAST_FORWARD_PAT
   # Paste the token when prompted
   ```

   Or manually:
   - Go to https://github.com/YOUR_USERNAME/YOUR_REPO/settings/secrets/actions
   - Click "New repository secret"
   - Name: `FAST_FORWARD_PAT`
   - Value: Paste the PAT
   - Click "Add secret"

3. Set the GitHub actor as a repository variable:
   ```bash
   gh variable set FAST_FORWARD_ACTOR -b"YOUR_GITHUB_USERNAME"
   ```

   Or manually:
   - Go to https://github.com/YOUR_USERNAME/YOUR_REPO/settings/variables/actions
   - Click "New repository variable"
   - Name: `FAST_FORWARD_ACTOR`
   - Value: Your GitHub username
   - Click "Add variable"

4. Usage:
   - PRs will automatically be checked for fast-forward compatibility
   - If checks fail, rebase your branch: `git rebase main`
   - When ready to merge, comment `/fast-forward` on the PR
   - The workflow will automatically perform the fast-forward merge

**Token rotation:**
Fine-grained PATs expire and must be rotated periodically.
The token is stored in `secrets/shared.yaml` as `FAST_FORWARD_PAT`.
To rotate: update with `just edit-secrets`, upload with `just ghsecrets`, then revoke the old token.

### 2.4 Configure Mergify (Optional but Recommended)

Mergify provides automated merge queue functionality with fast-forward-only enforcement.
The repository includes a `.github/mergify.yml` configuration that:
- Enforces fast-forward merges exclusively
- Automatically queues approved PRs
- Handles skipped CI checks from duplicate detection
- Validates fast-forward compatibility before merging

To enable Mergify:

1. Install the Mergify GitHub App:
   - Visit https://github.com/apps/mergify
   - Click "Install"
   - Select your repository
   - Grant required permissions

2. Verify configuration:
   ```bash
   # The .github/mergify.yml file is already configured
   # Check the configuration at:
   cat .github/mergify.yml
   ```

3. Configure the update bot account:
   - The configuration uses `update_bot_account: cameronraysmith`
   - This allows Mergify to push rebased commits on your behalf
   - Ensure Mergify has write access to the repository

4. Usage:
   - When a PR is approved and all checks pass, Mergify automatically adds it to the merge queue
   - The queue uses `merge_method: fast-forward` and `update_method: rebase`
   - PRs are merged only if they can be fast-forwarded
   - Conflicting PRs are automatically rebased by the bot account

For more details, see the [Mergify documentation](https://docs.mergify.com/).

### 2.5 Configure Production Environment

1. Go to https://github.com/YOUR_USERNAME/YOUR_REPO/settings/environments
2. Click "New environment"
3. Name: `production`
4. Add protection rules as desired (e.g., required reviewers)
5. Save

## Step 3: Test the Workflow

### 3.1 Manual Test with workflow_dispatch

Test the workflow manually before enabling automatic deployment:

```bash
# Trigger workflow with deployment disabled (safe test)
gh workflow run ci.yaml

# Or with deployment enabled
gh workflow run ci.yaml -f deploy_enabled=true

# Force all jobs to run (ignore caching)
gh workflow run ci.yaml -f force_run=true
```

### 3.2 Monitor Workflow Execution

```bash
# Watch the workflow run
gh run watch

# Or view in browser
gh run view --web
```

### 3.3 Verify Each Job

The workflow executes these jobs with intelligent per-job caching (jobs skip if already succeeded for this commit).
See [Caching Architecture](#caching-architecture) for details on the content-addressed caching mechanism.

**Core jobs (always run on PR/push):**

1. **secrets-scan** — Gitleaks secret scanning (security critical, no caching)
2. **set-variables** — Configure workflow variables and discover packages

**Preview jobs (PR only, fast feedback):**

3. **preview-release-version** — Show what version would be released (per package matrix)
4. **preview-docs-deploy** — Deploy docs to branch-specific preview URL

**Validation jobs (run based on file changes):**

5. **bootstrap-verification** — Validate Makefile bootstrap workflow
6. **secrets-workflow** — Test sops-nix mechanics with ephemeral keys
7. **flake-validation** — Validate flake structure and justfile recipes

**Build jobs (run based on file changes, with matrix):**

8. **cache-overlay-packages** — Pre-cache resource-intensive overlay packages (x86_64-linux, aarch64-linux)
9. **nix** — Build flake outputs by category (packages, checks-devshells, home, nixos) per system
10. **typescript** — Test TypeScript packages (per package matrix)

**Production jobs (main/beta only):**

11. **production-release-packages** — Release packages via semantic-release
12. **production-docs-deploy** — Deploy documentation to production

Jobs use `paths-ignore` filtering to skip on markdown-only changes.
Each job uses content-addressed caching to skip if source files haven't changed since last success.

### 3.4 Reusable Workflows

The CI system includes several reusable workflows that can be called from other workflows or used as building blocks for custom pipelines.

**`package-test.yaml`** — TypeScript package testing workflow.
Runs Vitest tests for all packages in the `packages/` directory.
Called by `ci.yaml` via the `typescript` job.
Can be called independently for focused package testing.

**`package-release.yaml`** — Semantic release workflow for package publishing.
Integrates with semantic-release to version, tag, and publish packages based on conventional commits.
Called by `ci.yaml` via the `production-release-packages` job on main/beta branches.
Requires `NPM_TOKEN` or similar registry credentials.

**`deploy-docs.yaml`** — Cloudflare Workers deployment workflow.
Deploys documentation site to Cloudflare Workers using Wrangler.
Called by `ci.yaml` for both preview deployments (PR branches) and production (main branch).
Supports branch-specific URLs for preview deployments.

All reusable workflows accept `workflow_call` trigger and expose inputs for customization.
See individual workflow files in `.github/workflows/` for input schemas and usage examples.

### 3.5 Check Deployment

If deployment succeeded, verify at:
- Cloudflare Dashboard: https://dash.cloudflare.com/
- Your Workers URL (shown in workflow deployment step)

## Step 4: Enable Automatic Deployment

Once manual testing succeeds, automatic deployment on push to main is already configured.

Push to main branch:
```bash
git checkout main
git pull
# Make changes...
git add .
git commit -m "your changes"
git push
```

The workflow will automatically:
1. Run all CI checks
2. Build the site
3. Deploy to Cloudflare Workers

## Workflow Triggers

The CI/CD workflow runs on:

1. **Manual dispatch** (`workflow_dispatch`) — supports interactive control via GitHub UI or `gh workflow run ci.yaml`
   - `job`: Run a specific job only (e.g., `flake-validation`, `nix`)
   - `debug_enabled`: Enable tmate debugging session for troubleshooting
   - `deploy_enabled`: Force deployment even on non-main branch (use cautiously)
   - `force_run`: Force all jobs to run, ignoring content-addressed caching

2. **Workflow call** (`workflow_call`) — allows reuse as a callable workflow from other workflows
   - Accepts same inputs as `workflow_dispatch`
   - Enables composition of CI workflows across repositories

3. **Pull requests** (`pull_request`) — runs on all PR events except those matching `paths-ignore`
   - Runs CI checks only (no deployment)
   - Skips on markdown-only changes via `paths-ignore: ['**/*.md', 'docs/**']`
   - Jobs use content-addressed caching to skip if source files unchanged
   - Preview jobs deploy to branch-specific URLs

4. **Push to main** (`push` to `main` branch) — production deployment trigger
   - Runs full CI with content-addressed caching
   - Automatically deploys to production environment
   - Runs semantic-release for package publishing

5. **Force-run override** — bypass caching for specific workflow runs
   - Add `force-ci` label to PR to force all jobs to run
   - Use `workflow_dispatch` with `force_run: true` for manual runs
   - Useful when cache corruption suspected or after dependency updates

## Caching Architecture

The CI system implements a three-tier caching strategy to minimize redundant work and reduce workflow execution time from hours to minutes.

### Content-Addressed Job Caching

Jobs use the `cached-ci-job` composite action (`.github/actions/cached-ci-job/action.yaml`) to implement content-addressed caching at the job level.
This is the first tier of caching and determines whether a job needs to run at all.

The mechanism works by computing a cache key from source files that affect the job's output, then checking GitHub's cache for a previous successful run with the same key.
If found, the job is skipped entirely.
If not found or if the job previously failed, it runs and caches the success state upon completion.

Each job declares its *hash-sources* — glob patterns identifying files that affect its output.
For example, the `flake-validation` job uses:

```yaml
hash-sources: 'justfile flake.nix flake.lock .github/actions/setup-nix/action.yml'
```

When any of these files change, the cache key changes, forcing the job to re-run.
When none have changed since the last successful run, the job skips immediately.

The cache key format is: `job-result-{sanitized-job-name}-{12-char-content-hash}`.
This ensures cache isolation per job and per source state, enabling independent caching for matrix job variants.

### Nix Store Cache

The second tier caches the Nix store itself across workflow runs.
The `setup-nix` composite action (`.github/actions/setup-nix/action.yml`) manages this through two installer strategies:

**Full mode** (default) — includes disk space reclamation via `nothing-but-nix` on Linux (or manual cleanup on macOS) and enables `nix-community/cache-nix-action` for store path persistence.
This mode reclaims 40-60GB of disk space on GitHub runners and maintains a cached Nix store across runs.

**Quick mode** (`installer: quick`) — skips space reclamation and store caching for faster initialization.
Both modes use `cachix/install-nix-action` for Nix installation but quick mode omits the caching overhead, useful for simple validation jobs.

In full mode, the `cache-nix-action` persists `/nix/store` paths between runs with automatic garbage collection when the store exceeds `gc-max-store-size` (default 5GB).
The cache key includes `runner.os` and a hash of all `.nix` files plus `flake.lock` to ensure invalidation when dependencies change.

### Binary Cache (Cachix)

The third tier uses Cachix as a remote binary cache for pre-built derivations.
This cache is shared across all developers and CI runs, not scoped to a single repository or workflow.

The `cache-overlay-packages` job pre-builds resource-intensive overlay packages (like LLVM, GCC, Rust toolchains) and pushes them to Cachix.
Subsequent jobs pull from Cachix instead of rebuilding from source, reducing build times from hours to minutes.

Cachix configuration is managed via `secrets/shared.yaml`:
- `CACHIX_CACHE_NAME` — the cache to push/pull from
- `CACHIX_AUTH_TOKEN` — authentication for write access (read access is public)

### Cache Invalidation

Caches invalidate when their key inputs change:

- **Job cache** — invalidates when hash sources change (per-job source patterns)
- **Nix store cache** — invalidates when `flake.lock` changes or Nix version updates
- **Cachix** — never invalidates (content-addressed), but may evict old entries per cache policy

Force-run overrides (`force_run` input or `force-ci` label) bypass only the job cache.
Nix store cache and Cachix remain active to accelerate builds even when forcing job re-execution.

## Local Development

### Running CI Locally

The repository maintains parity between CI and local environments through the `nix develop -c just [recipe]` pattern.
Every CI job has a corresponding justfile recipe that runs the same commands the workflow executes, using the same Nix flake environment.

This enables fast iteration: reproduce CI failures locally without waiting for GitHub Actions, validate fixes immediately, and push with confidence.

### CI Job to Local Command Mapping

| CI Job | Local Equivalent | Purpose |
|--------|------------------|---------|
| `flake-validation` | `just check` or `just check-fast` | Flake validation (full ~7 min, fast ~1-2 min) |
| `nix` (packages) | `just ci-build-category x86_64-linux packages` | Build all packages for a specific system |
| `nix` (checks) | `just ci-build-category x86_64-linux checks-devshells` | Run all checks and build devShells |
| `typescript` | `just test-package <name>` | Test a specific TypeScript package |
| `bootstrap-verification` | `make bootstrap && make verify` | Validate Makefile bootstrap workflow |
| `secrets-workflow` | `nix develop -c sops -d secrets/test.yaml` | Test sops-nix decryption |
| All jobs | `just ci-run-watch` | Trigger full CI and watch progress |

### Key Justfile Recipes

**`ci-run-watch`** — triggers the CI workflow via `gh workflow run` and watches execution in real-time.
Useful for validating changes before merging.

**`ci-status`** — shows current CI run status and summary.
Quickly check if CI is passing without opening GitHub.

**`ci-logs`** — downloads and displays CI logs, optionally filtering to failed jobs only via `ci-logs-failed`.
Faster than navigating GitHub UI for debugging.

**`ci-build-category <system> <category>`** — builds a specific category of flake outputs for a specific system.
Example: `just ci-build-category x86_64-linux packages` builds all packages.
Categories: `packages`, `checks-devshells`, `home`, `nixos`.

**`check-fast`** — runs fast flake validation (1-2 minutes) vs `nix flake check` (7+ minutes).
Validates flake structure, evaluates outputs, checks formatting without building everything.

### Debugging CI Failures

When a CI job fails:

1. **Identify the failing job** — use `just ci-status` or check GitHub Actions UI
2. **Run locally** — use the corresponding justfile recipe from the table above
3. **Reproduce the failure** — the local environment should match CI exactly
4. **Fix and validate** — iterate locally until the recipe succeeds
5. **Force re-run** — if needed, add `force-ci` label to PR or use `just ci-run-watch`

For Nix-specific failures, enter the development shell explicitly:
```bash
nix develop
# Then run the failing command manually
```

For failures in specific packages, use targeted builds:
```bash
# Build a specific package
nix build .#packages.x86_64-linux.some-package

# Build a specific check
nix build .#checks.x86_64-linux.some-check
```

If the failure is environment-specific (e.g., macOS vs Linux), use remote builders or platform-specific machines.
The justfile recipes respect the local platform but can be overridden via Nix's `--system` flag.

## Troubleshooting

### Workflow fails at "Decrypt secrets"

Check:
- `SOPS_AGE_KEY` is set correctly in GitHub secrets
- `secrets/shared.yaml` exists and is encrypted
- Age key has permissions to decrypt the file

```bash
# Test decryption locally
export SOPS_AGE_KEY_FILE=/path/to/your/age/key
sops --decrypt secrets/shared.yaml
```

### Deployment fails with "Invalid API token"

Check:
- Token has correct permissions (Workers Scripts Edit, Workers Routes Edit)
- Token hasn't expired
- Account ID matches your Cloudflare account

### Build fails with "Module not found"

Check:
- `bun install` succeeded
- All dependencies in `package.json` are correct
- Nix flake is up to date

Run locally:
```bash
nix develop
bun install
bun run build
```

### SOPS decryption shows wrong age key

Ensure the `CI_AGE_KEY` in `secrets/shared.yaml` matches the public key in `.sops.yaml`:
```yaml
keys:
  - &ci age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8
```

Generate the public key from private key:
```bash
echo "YOUR_PRIVATE_KEY" | age-keygen -y
```

## Security Notes

1. Never commit unencrypted secrets to the repository
2. Rotate API tokens regularly
3. Use minimal required permissions for tokens
4. Enable branch protection on main branch
5. Review workflow logs for exposed secrets
6. Use environment protection rules for production

## Next Steps

After successful setup:

1. Configure custom domain in Cloudflare
2. Set up monitoring and alerts
3. Add status badges to README
4. Configure additional environments (staging, preview)
5. Add deployment notifications (Slack, Discord, etc.)

## Useful Commands

### GitHub CLI Workflow Commands

```bash
# List workflows
gh workflow list

# View workflow runs
gh run list --workflow=ci.yaml

# Trigger manual deployment
gh workflow run ci.yaml -f deploy_enabled=true

# Force all jobs to run (ignore caching)
gh workflow run ci.yaml -f force_run=true

# Run a specific job only
gh workflow run ci.yaml -f job=flake-validation

# View latest run
gh run view

# View latest run in browser
gh run view --web

# Download workflow artifacts
gh run download

# Re-run failed workflow
gh run rerun <run-id>
```

### Justfile CI Commands

```bash
# Trigger CI and watch progress in real-time
just ci-run-watch

# View current CI status
just ci-status

# View all CI logs
just ci-logs

# View only failed job logs
just ci-logs-failed

# Build specific category locally (matches CI nix job)
just ci-build-category x86_64-linux packages
just ci-build-category x86_64-linux checks-devshells
just ci-build-category aarch64-darwin home

# Fast flake validation (~1-2 min vs ~7 min nix flake check)
just check-fast

# Full flake validation (includes VM tests, ~7 min)
just check

# Test a specific TypeScript package (matches CI typescript job)
just test-package docs

# Bootstrap verification (matches CI bootstrap-verification job)
make bootstrap && make verify

# Secrets workflow test (matches CI secrets-workflow job)
nix develop -c sops -d secrets/test.yaml
```

### Local Development Parity

```bash
# Enter development environment (same as CI uses)
nix develop

# Run any justfile recipe in dev environment
nix develop -c just <recipe>

# Build specific flake output
nix build .#packages.x86_64-linux.some-package
nix build .#checks.x86_64-linux.some-check

# Evaluate flake outputs without building
nix eval .#packages.x86_64-linux --apply builtins.attrNames

# Show flake structure
nix flake show
```

## References

- Cloudflare Workers: https://developers.cloudflare.com/workers/
- Wrangler CLI: https://developers.cloudflare.com/workers/wrangler/
- SOPS: https://github.com/getsops/sops
- GitHub Actions: https://docs.github.com/actions
