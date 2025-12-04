# Secrets management

Manage secrets using sops for version-controlled encrypted files and platform-specific secrets for deployment environments.

## Philosophy

### When to use sops

Use sops for project-level secrets that need to be:
- Version controlled in git repositories
- Shared among team members with role-based access
- Available during local development
- Decrypted in CI/CD pipelines

**Examples**: API tokens, database credentials, service account keys, `.env` file contents.

### When to use platform secrets

Use platform-specific secret management when:
- Secrets are deployment environment-specific (development, staging, production)
- Platform provides better integration (Cloudflare Workers, GitHub Actions)
- Secrets should not exist in version control

**Examples**:
- Cloudflare Workers secrets (via `wrangler secret put`)
- GitHub Actions repository/environment secrets
- Nix runtime secrets (via sops-nix at evaluation time)

### Hybrid approach

Combine sops and platform secrets:
- Store encrypted baseline secrets in repository with sops
- Override with platform secrets for environment-specific values
- Use sops in CI/CD to decrypt and upload to platforms

**Example**: Encrypt shared API tokens in `vars/shared.yaml`, decrypt in GitHub Actions, upload to Cloudflare Workers via `wrangler secret put`.

## System-level secrets with sops-nix

Use sops-nix for declarative secrets management in NixOS, nix-darwin, and home-manager.

### Integration in flake.nix

```nix
{
  inputs = {
    sops-nix.url = "github:mic92/sops-nix";
    sops-nix.inputs.nixpkgs.follows = "nixpkgs";
  };

  outputs = { self, nixpkgs, sops-nix, ... }: {
    nixosConfigurations.hostname = nixpkgs.lib.nixosSystem {
      modules = [
        sops-nix.nixosModules.sops
        ./configuration.nix
      ];
    };

    darwinConfigurations.hostname = nix-darwin.lib.darwinSystem {
      modules = [
        sops-nix.darwinModules.sops
        ./configuration.nix
      ];
    };

    homeConfigurations.username = home-manager.lib.homeManagerConfiguration {
      modules = [
        sops-nix.homeManagerModules.sops
        ./home.nix
      ];
    };
  };
}
```

### .sops.yaml for system configuration

```yaml
keys:
  # Admin recovery key (stored securely offline)
  - &admin age1vy7wsnf8eg5229evq3ywup285jzk9cntsx5hhddjtwsjh0kf4c6s9fmalv

  # User key (stored in ~/.config/sops/age/keys.txt)
  - &crs58 age1whsxa8rlfm8c9hgjc2yafq5dvuvkz58pfd85nyuzdcjndufgfucs7ll3ke

  # Host key (derived from SSH host key via ssh-to-age)
  # cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
  - &hostname age18rgyca7ptr6djqn5h7rhgu4yuv9258v5wflg7tefgvxr06nz7cgsw7qgmy

creation_rules:
  # User-specific secrets (only user + admin can decrypt)
  - path_regex: users/crs58/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *crs58

  # Host-specific secrets (admin + user + host can decrypt)
  - path_regex: hosts/hostname/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *crs58
        - *hostname

  # Shared service secrets (all authorized keys)
  - path_regex: services/.*\.yaml$
    key_groups:
      - age:
        - *admin
        - *crs58
        - *hostname
```

### NixOS/nix-darwin secrets configuration

```nix
# configuration.nix
{ config, pkgs, ... }:
{
  # Specify sops file location
  sops.defaultSopsFile = ./secrets/secrets.yaml;

  # Age key location for decryption
  sops.age.keyFile = "/var/lib/sops-nix/key.txt";

  # SSH host key derivation (alternative to dedicated age key)
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];

  # Define secrets
  sops.secrets."github/token" = {
    owner = "username";
    group = "users";
    mode = "0400";
  };

  # Use secrets in services
  services.some-service = {
    enable = true;
    tokenFile = config.sops.secrets."github/token".path;
  };
}
```

### home-manager secrets configuration

```nix
# home.nix
{ config, pkgs, ... }:
{
  sops.defaultSopsFile = ./secrets.yaml;

  # User age key location
  sops.age.keyFile = "${config.home.homeDirectory}/.config/sops/age/keys.txt";

  # Define user-level secrets
  sops.secrets."git/credentials" = {
    path = "${config.home.homeDirectory}/.git-credentials";
  };

  sops.secrets."api/tokens/github" = { };

  # Use secrets in programs
  programs.git = {
    enable = true;
    extraConfig = {
      credential.helper = "store --file=${config.sops.secrets."git/credentials".path}";
    };
  };
}
```

### Age vs GPG key selection

Prefer age keys over GPG for modern deployments:

**Use age when**:
- Starting new projects
- Simpler key management is priority
- No existing GPG infrastructure
- CI/CD integration needed (age is simpler)

**Use GPG when**:
- Existing GPG key infrastructure
- Yubikey/hardware token integration required
- Team already uses GPG for signing

**Recommendation**: Use age for all new projects.

## Project-level secrets with sops

Manage project secrets using sops with encrypted YAML/JSON files.

### .sops.yaml for project secrets

```yaml
keys:
  # Development key (shared among 1-3 person teams initially)
  - &dev age1dn8w7y4t4h23fmeenr3dghfz5qh53jcjq9qfv26km3mnv8l44g0sghptu3

  # CI/CD key (single key for GitHub Actions)
  - &ci age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8

creation_rules:
  # Shared secrets (dev + ci)
  - path_regex: vars/.*\.yaml$
    key_groups:
      - age:
          - *dev
          - *ci

  # Environment-specific overrides
  - path_regex: vars/.*\.json$
    key_groups:
      - age:
          - *dev
          - *ci
```

### Encrypted .env pattern

```yaml
# vars/shared.yaml
DATABASE_URL: "postgresql://user:password@host:5432/db"
GOOGLE_CLIENT_SECRET: "secret-value"
BETTER_AUTH_SECRET: "auth-secret-value"
CLOUDFLARE_API_TOKEN: "cloudflare-token"
CACHIX_AUTH_TOKEN: "cachix-token"
```

Encrypt with sops:

```bash
sops -e vars/shared.yaml
```

### Just recipes for sops operations

```make
# justfile

# Show decrypted secrets
[group('secrets')]
show-secrets:
  @echo "=== Shared secrets (vars/shared.yaml) ==="
  @sops -d vars/shared.yaml
  @echo

# Edit encrypted secrets file
[group('secrets')]
edit-secrets:
  @sops vars/shared.yaml

# Create new encrypted file
[group('secrets')]
new-secret file:
  @sops {{ file }}

# Export secrets to .env format
[group('secrets')]
export-secrets:
  @echo "# Exported from sops secrets" > .secrets.env
  @sops -d vars/shared.yaml | grep -E '^[A-Z_]+:' | sed 's/: /=/' >> .secrets.env
  @sort -u .secrets.env -o .secrets.env

# Run command with secrets as environment variables
[group('secrets')]
run-with-secrets +command:
  @sops exec-env vars/shared.yaml '{{ command }}'

# Get specific secret value
[group('secrets')]
get-secret key:
  @sops -d vars/shared.yaml | grep "^{{ key }}:" | cut -d' ' -f2-

# Validate all encrypted files can be decrypted
[group('secrets')]
validate-secrets:
  @echo "Validating sops encrypted files..."
  @for file in $(find vars -name "*.yaml"); do \
    echo "Testing: $file"; \
    sops -d "$file" > /dev/null && echo "  ● Valid" || echo "  ⊘ Failed"; \
  done

# Initialize age key for new developers
[group('secrets')]
sops-init:
  @echo "Checking sops configuration..."
  @if [ ! -f ~/.config/sops/age/keys.txt ]; then \
    echo "Generating age key..."; \
    mkdir -p ~/.config/sops/age; \
    age-keygen -o ~/.config/sops/age/keys.txt; \
    echo ""; \
    echo "● Age key generated. Add this public key to .sops.yaml:"; \
    grep "public key:" ~/.config/sops/age/keys.txt; \
  else \
    echo "● Age key already exists"; \
    grep "public key:" ~/.config/sops/age/keys.txt; \
  fi

# Add existing age key to local configuration
[group('secrets')]
sops-add-key:
  #!/usr/bin/env bash
  set -euo pipefail

  mkdir -p ~/.config/sops/age
  touch ~/.config/sops/age/keys.txt
  chmod 600 ~/.config/sops/age/keys.txt

  printf "Enter age key description (e.g., 'project [dev|ci|admin]'): "
  read -r key_description
  [[ -z "${key_description}" ]] && { echo "⊘ Description cannot be empty"; exit 1; }

  printf "Paste age PRIVATE key (starts with AGE-SECRET-KEY-): "
  read -rs private_key
  echo ""

  # Derive public key
  public_key=$(echo "${private_key}" | age-keygen -y)

  if grep -q "${private_key}" ~/.config/sops/age/keys.txt 2>/dev/null; then
    echo "⚠️  This private key already exists in keys.txt"
    exit 1
  fi

  {
    echo "# ${key_description}"
    echo "# public key: ${public_key}"
    echo "${private_key}"
    echo ""
  } >> ~/.config/sops/age/keys.txt

  echo "● Age key added successfully for: ${key_description}"
  echo "   Public key: ${public_key}"

# Set or update secret non-interactively
[group('secrets')]
set-secret secret_name secret_value:
  @sops set vars/shared.yaml '["{{ secret_name }}"]' '"{{ secret_value }}"'
  @echo "● {{ secret_name }} has been set/updated"

# Rotate secret interactively
[group('secrets')]
rotate-secret secret_name:
  #!/usr/bin/env bash
  printf "Enter new value for {{ secret_name }}: "
  read -rs NEW_VALUE
  echo ""
  sops set vars/shared.yaml '["{{ secret_name }}"]' "\"$NEW_VALUE\"" && \
    echo "● {{ secret_name }} rotated successfully"

# Update keys for existing secrets files
[group('secrets')]
updatekeys:
  @echo "Updating keys for all sops files..."
  @for file in $(find vars -name "*.yaml"); do \
    echo "Updating: $file"; \
    sops updatekeys "$file"; \
  done
  @echo "● Keys updated for all secrets files"
```

### Git pre-commit hooks

Prevent committing unencrypted secrets:

```bash
# .git/hooks/pre-commit
#!/usr/bin/env bash

# Check for potentially unencrypted secret files
if git diff --cached --name-only | grep -E '(\.env$|vars/.*\.yaml$)'; then
  echo "⚠️  Detected potential secret files in commit"
  echo "Verifying encryption with sops..."

  for file in $(git diff --cached --name-only | grep -E '(vars/.*\.yaml$)'); do
    if ! grep -q "sops:" "$file"; then
      echo "⊘ File $file does not appear to be encrypted with sops"
      echo "Run: sops -e $file > $file.enc && mv $file.enc $file"
      exit 1
    fi
  done
fi

exit 0
```

Make executable:

```bash
chmod +x .git/hooks/pre-commit
```

## Key management

### Development key strategy

**Shared dev key pattern** (acceptable for 1-3 person teams):

1. Generate single age key for development team:
   ```bash
   age-keygen -o dev-key.txt
   # Share via secure channel (Bitwarden, 1Password)
   ```

2. Add to `.sops.yaml`:
   ```yaml
   keys:
     - &dev age1dn8w7y4t4h23fmeenr3dghfz5qh53jcjq9qfv26km3mnv8l44g0sghptu3
   ```

3. Team members install key:
   ```bash
   just sops-add-key  # Interactive prompt
   ```

**Migration to per-developer keys** (when team grows beyond 3 people):

1. Each developer generates personal key:
   ```bash
   age-keygen -o ~/.config/sops/age/keys.txt
   grep "public key:" ~/.config/sops/age/keys.txt
   ```

2. Update `.sops.yaml` with all developer keys:
   ```yaml
   keys:
     - &alice age1...
     - &bob age1...
     - &charlie age1...
     - &ci age1...

   creation_rules:
     - path_regex: vars/.*\.yaml$
       key_groups:
         - age:
             - *alice
             - *bob
             - *charlie
             - *ci
   ```

3. Re-encrypt all secrets with new keys:
   ```bash
   just updatekeys
   ```

4. Rotate all secrets (old shared key may be compromised):
   ```bash
   just rotate-secret DATABASE_PASSWORD
   just rotate-secret API_TOKEN
   ```

### CI/CD key strategy

Use single age key shared with GitHub Actions (acceptable for most projects):

**Benefits**:
- One secret to manage in GitHub Actions
- Simple key rotation (update one secret vs many)
- No proliferation of individual secrets

**Security considerations**:
- Scope to repository or environment level
- Use separate CI keys per repository
- Rotate when team members with CI access leave

**Setup**:

1. Generate dedicated CI key:
   ```bash
   age-keygen -o ci-key.txt
   # Do NOT commit ci-key.txt
   ```

2. Add public key to `.sops.yaml`:
   ```yaml
   keys:
     - &ci age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8
   ```

3. Store private key in GitHub Actions secret:
   ```bash
   # Copy private key (starts with AGE-SECRET-KEY-)
   cat ci-key.txt

   # Add to GitHub repository secrets as CI_AGE_KEY
   gh secret set CI_AGE_KEY --repo=owner/repo
   ```

4. Use in workflows:
   ```yaml
   # .github/workflows/deploy.yaml
   jobs:
     deploy:
       runs-on: ubuntu-latest
       steps:
         - uses: actions/checkout@v4

         - name: Install sops
           run: |
             wget https://github.com/getsops/sops/releases/latest/download/sops-linux-amd64
             chmod +x sops-linux-amd64
             sudo mv sops-linux-amd64 /usr/local/bin/sops

         - name: Decrypt and use secrets
           env:
             SOPS_AGE_KEY: ${{ secrets.CI_AGE_KEY }}
           run: |
             sops exec-env vars/shared.yaml 'echo "DATABASE_URL=$DATABASE_URL" >> $GITHUB_ENV'

         - name: Deploy with secrets
           run: |
             # Secrets available as environment variables
             echo $DATABASE_URL
   ```

**Alternative**: OIDC with cloud providers (more complex, better security):
- GitHub Actions OIDC to AWS/GCP/Azure
- No long-lived credentials
- Requires cloud provider integration

### SSH-to-age derivation

Derive age keys from existing SSH keys (useful for hosts and CI bots):

**Use cases**:
- NixOS/nix-darwin hosts (derive from `/etc/ssh/ssh_host_ed25519_key`)
- CI bot with existing SSH deploy key
- Reuse existing SSH infrastructure

**Process**:

```bash
# Derive age public key from SSH public key
cat /etc/ssh/ssh_host_ed25519_key.pub | ssh-to-age
# Output: age18rgyca7ptr6djqn5h7rhgu4yuv9258v5wflg7tefgvxr06nz7cgsw7qgmy

# Add to .sops.yaml
# keys:
#   - &hostname age18rgyca7ptr6djqn5h7rhgu4yuv9258v5wflg7tefgvxr06nz7cgsw7qgmy
```

**sops-nix auto-derivation**:

```nix
# configuration.nix
{
  sops.age.sshKeyPaths = [ "/etc/ssh/ssh_host_ed25519_key" ];
  # sops-nix automatically derives age key for decryption
}
```

**Security consideration**:
- SSH key material used for both SSH and encryption
- Acceptable risk for host keys (already trusted for system access)
- Less ideal for user keys (prefer dedicated age keys)

**Recommendation**: Use SSH-to-age for hosts, dedicated age keys for users and CI.

### Bitwarden integration

Store age private keys securely in Bitwarden:

1. Create Bitwarden secure note:
   - Title: "Project X - Dev Age Key"
   - Note content: Paste full private key (including header)
   - Custom field "Public Key": age1...

2. Retrieve when needed:
   ```bash
   # Manual: Copy from Bitwarden UI

   # CLI (if using Bitwarden CLI)
   bw get notes "Project X - Dev Age Key" > ~/.config/sops/age/keys.txt
   chmod 600 ~/.config/sops/age/keys.txt
   ```

3. **Never** store in:
   - Unencrypted cloud storage
   - Email
   - Slack/chat messages
   - Git repositories

## CI/CD integration

### GitHub Actions with sops

**Pattern**: Single age key secret, just recipes in workflows.

```yaml
# .github/workflows/deploy.yaml
name: Deploy

on:
  push:
    branches: [main]

jobs:
  deploy:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4

      - name: Install Nix
        uses: DeterminateSystems/nix-installer-action@main

      - name: Deploy with secrets
        env:
          SOPS_AGE_KEY: ${{ secrets.CI_AGE_KEY }}
        run: |
          # Secrets available via sops exec-env
          nix develop --accept-flake-config -c just deploy
```

**justfile deploy recipe**:

```make
# Deploy to production with secrets
[group('deploy')]
deploy:
  #!/usr/bin/env bash
  set -euo pipefail

  # Decrypt secrets and export to environment
  sops exec-env vars/shared.yaml '\
    wrangler secret put DATABASE_PASSWORD --env production <<< "$DATABASE_PASSWORD" && \
    wrangler secret put BETTER_AUTH_SECRET --env production <<< "$BETTER_AUTH_SECRET" && \
    wrangler deploy --env production'
```

### Secret scope in GitHub Actions

Scope secrets to specific environments or jobs:

```yaml
# Environment-scoped secrets (recommended)
jobs:
  deploy-production:
    runs-on: ubuntu-latest
    environment: production  # Requires environment secret CI_AGE_KEY_PROD
    steps:
      - name: Deploy
        env:
          SOPS_AGE_KEY: ${{ secrets.CI_AGE_KEY }}
        run: just deploy-production

  deploy-staging:
    runs-on: ubuntu-latest
    environment: staging  # Requires environment secret CI_AGE_KEY_STAGE
    steps:
      - name: Deploy
        env:
          SOPS_AGE_KEY: ${{ secrets.CI_AGE_KEY }}
        run: just deploy-staging
```

### Security hardening

1. **Minimize secret exposure**:
   ```yaml
   jobs:
     build:
       steps:
         - name: Build (no secrets)
           run: nix build

     deploy:
       needs: build
       steps:
         - name: Deploy (with secrets)
           env:
             SOPS_AGE_KEY: ${{ secrets.CI_AGE_KEY }}
           run: just deploy
   ```

2. **Use environments** for production deployments (requires approval)

3. **Audit secret usage** with structured logging:
   ```bash
   sops exec-env vars/shared.yaml '\
     echo "Deploying with secrets: $(env | grep -E "DATABASE|API" | cut -d= -f1 | tr "\n" "," | sed "s/,$//")"'
   ```

## Multi-environment patterns

### Development, staging, production separation

**Option 1: Separate .sops.yaml files**

```
secrets/
  dev/
    .sops.yaml       # Dev keys only
    vars.yaml
  staging/
    .sops.yaml       # Staging keys only
    vars.yaml
  production/
    .sops.yaml       # Production keys only
    vars.yaml
```

**Option 2: Single .sops.yaml with path-based rules**

```yaml
# .sops.yaml
keys:
  - &dev age1...
  - &ci age1...
  - &prod-deployer age1...

creation_rules:
  # Development secrets (dev + ci)
  - path_regex: vars/dev/.*\.yaml$
    key_groups:
      - age:
          - *dev
          - *ci

  # Production secrets (ci + prod-deployer only)
  - path_regex: vars/production/.*\.yaml$
    key_groups:
      - age:
          - *ci
          - *prod-deployer
```

**Recommendation**: Use path-based rules in single `.sops.yaml` for easier management.

### Integration with Cloudflare Workers

Hybrid approach: sops in repo, wrangler secrets for deployment.

**vars/shared.yaml** (encrypted with sops):

```yaml
DATABASE_PASSWORD: "production-db-password"
BETTER_AUTH_SECRET: "production-auth-secret"
GOOGLE_CLIENT_SECRET: "google-oauth-secret"
```

**justfile recipes**:

```make
# Upload secrets to Cloudflare Workers
[group('deploy')]
cf-secrets-upload env="production":
  @sops exec-env vars/shared.yaml '\
    wrangler secret put DATABASE_PASSWORD --env {{ env }} <<< "$DATABASE_PASSWORD" && \
    wrangler secret put BETTER_AUTH_SECRET --env {{ env }} <<< "$BETTER_AUTH_SECRET" && \
    wrangler secret put GOOGLE_CLIENT_SECRET --env {{ env }} <<< "$GOOGLE_CLIENT_SECRET"'

# List secrets in Cloudflare Workers
[group('deploy')]
cf-secrets-list env="production":
  wrangler secret list --env {{ env }}
```

**wrangler.jsonc** (non-sensitive config):

```jsonc
{
  "vars": {
    "API_URL": "https://api.example.com",
    "FEATURE_FLAG_NEW_UI": "true"
  },

  "env": {
    "production": {
      "vars": {
        "API_URL": "https://api.production.example.com"
      }
      // Secrets set via wrangler secret put
    }
  }
}
```

**Pattern**: Non-sensitive config in `wrangler.jsonc`, sensitive secrets via `wrangler secret put` from sops.

See @~/.claude/commands/preferences/web-application-deployment.md for Cloudflare secrets management details.

## Best practices

### Key rotation schedules

**Development keys**:
- Rotate when transitioning from shared key to per-developer keys
- Rotate when team member leaves (if they had access)
- Rotate every 12 months for long-lived projects

**CI keys**:
- Rotate every 6 months for production systems
- Rotate immediately if GitHub Actions logs exposed
- Rotate when repository access policies change

**Production secrets**:
- Rotate credentials every 90 days (databases, API tokens)
- Rotate immediately if compromise suspected
- Use automated rotation where possible (cloud provider integrations)

### Audit logging and access reviews

**Access audit checklist**:
- Review `.sops.yaml` creation rules quarterly
- Verify active developer keys match current team
- Remove keys for departed team members
- Audit GitHub Actions secret usage in workflow logs

**Logging pattern**:

```bash
# Log secret access (without revealing values)
sops exec-env vars/shared.yaml '\
  echo "[$(date -Iseconds)] Secrets accessed by: $USER" >> .sops-access.log'
```

**Regular reviews**:
- Monthly: Review `.sops.yaml` for outdated keys
- Quarterly: Rotate high-value credentials
- Annually: Complete security audit of secrets management

### Incident response (compromised keys)

**If age private key compromised**:

1. **Immediate actions**:
   ```bash
   # Generate new age key
   age-keygen -o ~/.config/sops/age/new-keys.txt

   # Update .sops.yaml with new key, remove compromised key
   # Re-encrypt all secrets
   just updatekeys

   # Update GitHub Actions secret
   gh secret set CI_AGE_KEY --repo=owner/repo < new-ci-key.txt
   ```

2. **Rotate all secrets** (assume attacker decrypted files):
   ```bash
   just rotate-secret DATABASE_PASSWORD
   just rotate-secret API_TOKEN
   just rotate-secret BETTER_AUTH_SECRET
   # ... all secrets in encrypted files
   ```

3. **Audit access**:
   - Review git history for who had access to compromised key
   - Check application logs for suspicious access patterns
   - Notify team of incident and remediation steps

4. **Update documentation**:
   - Document incident in security log
   - Update key distribution procedures
   - Consider moving to per-developer keys if using shared key

**If sops encrypted files exposed without key**:
- Low risk (files are encrypted)
- Monitor for key compromise
- Consider rotating keys as precaution

### Documentation requirements

**.sops.yaml comments**:

```yaml
# Development key (shared among core team)
# Rotation schedule: Every 12 months or when team changes
# Storage: Bitwarden "Project X - Dev Key"
- &dev age1dn8w7y4t4h23fmeenr3dghfz5qh53jcjq9qfv26km3mnv8l44g0sghptu3

# CI key (GitHub Actions only)
# Rotation schedule: Every 6 months
# Storage: GitHub secret CI_AGE_KEY
# Last rotated: 2025-10-01
- &ci age1m9m8h5vqr7dqlmvnzcwshmm4uk8umcllazum6eaulkdp3qc88ugs22j3p8
```

**README sections**:

```markdown
# Secrets Management

This project uses sops for secrets management.

## Setup

1. Install sops: `brew install sops age`
2. Request age key from team lead
3. Install key: `just sops-add-key`
4. Verify: `just show-secrets`

## Usage

- Edit secrets: `just edit-secrets`
- View secrets: `just show-secrets`
- Run with secrets: `just run-with-secrets <command>`

## Key Contacts

- Key rotation: @lead-developer
- Access requests: @security-team
```

**Security documentation**:
- Document key distribution process
- Maintain list of who has access to which keys
- Record key rotation dates in git history
- Link to incident response procedures

## Integration with other preferences

- Cloudflare Workers secrets: @~/.claude/commands/preferences/web-application-deployment.md
- sops-nix in flakes: @~/.claude/commands/preferences/nix-development.md
- Pre-commit hooks: @~/.claude/commands/preferences/git-version-control.md
- CI/CD patterns: @~/.claude/commands/preferences/typescript-nodejs-development.md
