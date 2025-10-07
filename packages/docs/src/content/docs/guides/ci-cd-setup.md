---
title: CI/CD setup
description: Setting up GitHub Actions CI/CD pipeline with Cloudflare Workers deployment
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

- **GITGUARDIAN_API_KEY**: Get from https://dashboard.gitguardian.com/api/personal-access-tokens
- **CACHIX_AUTH_TOKEN**: Get from https://app.cachix.org/cache/YOUR_CACHE/settings
- **CACHIX_CACHE_NAME**: Your Cachix cache name

### 1.4 Create Unencrypted Secrets File

Create `vars/shared.yaml` with your secrets:

```yaml
CLOUDFLARE_ACCOUNT_ID: your-actual-account-id
CLOUDFLARE_API_TOKEN: your-actual-api-token
GITGUARDIAN_API_KEY: your-actual-gitguardian-key
CACHIX_AUTH_TOKEN: your-actual-cachix-token
CACHIX_CACHE_NAME: your-cache-name
CI_AGE_KEY: age-secret-key-1... # CI age private key from .sops.yaml
```

The `CI_AGE_KEY` should be the private key corresponding to the public key:
`age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8`

### 1.5 Encrypt the Secrets File

```bash
# Verify you have the correct age keys configured
cat .sops.yaml

# Encrypt the file in place
sops --encrypt --in-place vars/shared.yaml

# Verify encryption succeeded
head vars/shared.yaml
# Should show encrypted content starting with ENC[...]
```

### 1.6 Commit Encrypted Secrets

```bash
git add vars/shared.yaml
git commit -m "build: add encrypted secrets for CI/CD"
git push
```

## Step 2: Configure GitHub Repository

### 2.1 Upload SOPS Age Key to GitHub Secrets

The CI needs the private age key to decrypt `vars/shared.yaml`:

```bash
# Extract the CI_AGE_KEY from the encrypted file
sops --decrypt --extract '["CI_AGE_KEY"]' vars/shared.yaml | gh secret set SOPS_AGE_KEY
```

Or manually:
1. Decrypt the file: `sops vars/shared.yaml`
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

Alternatively, the workflow will read from the encrypted `vars/shared.yaml`.

### 2.3 Configure Production Environment

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
```

### 3.2 Monitor Workflow Execution

```bash
# Watch the workflow run
gh run watch

# Or view in browser
gh run view --web
```

### 3.3 Verify Each Job

The workflow should complete these jobs in order:
1. ✅ **scan**: GitGuardian secret scanning
2. ✅ **set-variables**: Configure workflow variables
3. ✅ **nixci**: Nix flake checks
4. ✅ **build**: Build Astro documentation site
5. ✅ **deploy**: Deploy to Cloudflare Workers (only if enabled)

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

2. **Pull requests** (`pull_request`)
   - Runs CI checks only (no deployment)
   - Skip with label: `skip-ci`
   - Enable debug with label: `actions-debug`

3. **Push to main** (`push` to `main` branch)
   - Runs full CI
   - Automatically deploys to production

## Troubleshooting

### Workflow fails at "Decrypt secrets"

Check:
- `SOPS_AGE_KEY` is set correctly in GitHub secrets
- `vars/shared.yaml` exists and is encrypted
- Age key has permissions to decrypt the file

```bash
# Test decryption locally
export SOPS_AGE_KEY_FILE=/path/to/your/age/key
sops --decrypt vars/shared.yaml
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

Ensure the `CI_AGE_KEY` in `vars/shared.yaml` matches the public key in `.sops.yaml`:
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
