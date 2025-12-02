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

The workflow executes these jobs with intelligent per-job caching (jobs skip if already succeeded for this commit):

**Core jobs (always run on PR/push):**
1. ✅ **secrets-scan**: Gitleaks secret scanning (security critical, no caching)
2. ✅ **set-variables**: Configure workflow variables (produces outputs, always runs)

**Preview jobs (PR only, fast feedback):**
3. ✅ **preview-release-version**: Show what version would be released
4. ✅ **preview-docs-deploy**: Deploy docs to branch-specific preview URL

**Validation jobs (run based on file changes):**
5. ✅ **bootstrap-verification**: Validate Makefile bootstrap workflow
6. ✅ **config-validation**: Test config.nix user definitions
7. ✅ **autowiring-validation**: Verify nixos-unified autowiring
8. ✅ **secrets-workflow**: Test sops-nix mechanics
9. ✅ **justfile-activation**: Validate justfile recipes

**Build jobs (run based on file changes, with matrix):**
10. ✅ **cache-overlay-packages**: Pre-cache overlay packages (per system)
11. ✅ **nix**: Build all flake outputs (per category/system)
12. ✅ **typescript**: Test TypeScript packages (per package)

**Production jobs (main/beta only):**
13. ✅ **production-release-packages**: Release packages to production
14. ✅ **production-docs-deploy**: Deploy documentation to production

Jobs use path-based filtering to skip when irrelevant files change (e.g., nix jobs skip on markdown-only changes).
Each job queries GitHub Checks API to skip if it already succeeded for the current commit SHA.

### 3.4 Check Deployment

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

1. **Manual dispatch** (`workflow_dispatch`)
   - `debug_enabled`: Enable tmate debugging session
   - `deploy_enabled`: Force deployment even on non-main branch
   - `force_run`: Force all jobs to run, ignoring per-job caching

2. **Pull requests** (`pull_request`)
   - Runs CI checks only (no deployment)
   - Jobs use intelligent caching (skip if already succeeded for this commit)

3. **Push to main** (`push` to `main` branch)
   - Runs full CI with intelligent caching
   - Automatically deploys to production

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

```bash
# List workflows
gh workflow list

# View workflow runs
gh run list --workflow=ci.yaml

# Trigger manual deployment
gh workflow run ci.yaml -f deploy_enabled=true

# View latest run
gh run view

# Download workflow artifacts
gh run download

# Re-run failed workflow
gh run rerun <run-id>
```

## References

- Cloudflare Workers: https://developers.cloudflare.com/workers/
- Wrangler CLI: https://developers.cloudflare.com/workers/wrangler/
- SOPS: https://github.com/getsops/sops
- GitHub Actions: https://docs.github.com/actions
