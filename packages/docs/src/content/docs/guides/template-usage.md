---
title: Using as a template
description: How to fork and customize typescript-nix-template for your projects
---

This guide explains how to use typescript-nix-template as a starting point for your TypeScript monorepo projects.

## Quick start

### Option 1: GitHub template

1. Click "Use this template" button on GitHub
2. Create your new repository
3. Clone to your local machine
4. Follow customization steps below

### Option 2: Nix flake (coming soon)

```bash
nix flake init --template github:sciexp/typescript-nix-template
```

### Option 3: Manual fork

```bash
git clone https://github.com/sciexp/typescript-nix-template.git my-project
cd my-project
rm -rf .git
git init
git add .
git commit -m "chore: initial commit from typescript-nix-template"
```

## Understanding the naming pattern

This template uses framework-agnostic, purpose-based naming that works for both the template itself and your forked projects.

### Package naming strategy

**Template package:** `@typescript-nix-template/docs`

**Why this naming works:**

1. **Framework independence:** No mention of Astro/Starlight - these are implementation details
2. **Template perspective:** Most projects need documentation - immediately useful
3. **Brevity:** Shortest meaningful name
4. **Pattern clarity:** `@{scope}/{purpose}` scales to multiple packages
5. **Template duality:** Works as both a working deployment and a forkable template

### For your project

When you fork this template, you'll rename packages to match your organization and project:

**Single-package projects:**
```
@myorg/docs        # If docs are your main/only package
@myorg/api         # If building an API service
@myorg/web         # If building a web application
```

**Multi-package projects:**
```
@mycompany/docs    # Documentation site
@mycompany/api     # API backend
@mycompany/web     # Web frontend
@mycompany/shared  # Shared utilities
```

**Pattern:** Use the package's purpose, not its implementation framework.

## Deployment subdomain patterns

Understanding how to structure your deployment URLs is important for scalability.

### Subdomain hierarchy

#### Top-level (reserved, precious namespace)

Reserve these for organization-wide services:

```
example.com              # Main org site
www.example.com          # Main org site
docs.example.com         # Org-wide documentation
api.example.com          # Org-wide API gateway
blog.example.com         # Org blog
```

#### Project-level (scalable)

Use project subdomains for individual applications:

```
{project}.example.com                      # Project main site
{component}.{project}.example.com          # Project components
```

### Deployment examples

#### Single-package projects

If your project has only one public-facing site:

**Configuration:**
- Package: `@myorg/docs`
- Worker: `myproject`
- Route: `myproject.example.com`

**When to use:**
- Documentation sites
- Simple web applications
- Single-purpose services

#### Multi-package projects

If your project has multiple public-facing components:

**Configuration:**
- Package: `@myorg/docs` → Worker: `myproject-docs` → `docs.myproject.example.com`
- Package: `@myorg/api` → Worker: `myproject-api` → `api.myproject.example.com`
- Package: `@myorg/web` → Worker: `myproject-web` → `www.myproject.example.com`

**When to use:**
- Multi-component architectures
- Clear separation of concerns needed
- Professional multi-service setup

### Template deployment example

**For typescript-nix-template:**
- Package: `@typescript-nix-template/docs`
- Worker: `ts-nix-docs`
- Route: `ts-nix.scientistexperience.net`

**Rationale:**
- Preserves `docs.*` for actual org documentation
- `ts-nix` is short identifier for the template project
- Shows project-level subdomain pattern

## Customization checklist

When forking this template, update these files:

### 1. Root package.json

```json
{
  "name": "my-project",
  "description": "Your project description",
  "repository": {
    "type": "git",
    "url": "https://github.com/yourorg/my-project.git"
  },
  "workspaces": ["packages/*"]
}
```

### 2. Package directories

Rename `packages/docs/` to match your package purpose:

```bash
mv packages/docs packages/my-package-name
```

### 3. Package package.json

Update `packages/my-package-name/package.json`:

```json
{
  "name": "@yourorg/my-package-name",
  "description": "Your package description",
  "repository": {
    "type": "git",
    "url": "https://github.com/yourorg/my-project.git"
  },
  "release": {
    "plugins": [
      // ... existing plugins ...
      [
        "semantic-release-major-tag",
        {
          "customTags": [
            "my-package-name-v${major}",
            "my-package-name-v${major}.${minor}"
          ]
        }
      ]
    ]
  }
}
```

### 4. Wrangler configuration

Update `packages/my-package-name/wrangler.jsonc`:

```jsonc
{
  "name": "my-project-package-name",
  "routes": [
    {
      "pattern": "my-project.example.com",
      "custom_domain": true
    }
  ]
}
```

### 5. GitHub Actions workflows

Update workflow matrices in `.github/workflows/`:

**ci.yaml:**
```yaml
matrix:
  package:
    - name: my-package-name
      path: packages/my-package-name
```

**release.yaml:**
```yaml
matrix:
  package:
    - name: my-package-name
      path: packages/my-package-name
```

### 6. Justfile

Update filter patterns:

```justfile
# Before
bun run --filter '@typescript-nix-template/docs' dev

# After
bun run --filter '@yourorg/my-package-name' dev
```

Search and replace `@typescript-nix-template/docs` with your package name.

### 7. Documentation

Update:
- `README.md` - Project name and description
- `CONTRIBUTING.md` - Scope examples in commit message section
- `packages/my-package-name/README.md` - Package-specific docs

### 8. Flake description

Update `flake.nix`:

```nix
{
  description = "my-project: Your project description";
  # ... rest of flake
}
```

## Verification steps

After customization:

### 1. Install dependencies

```bash
nix develop
bun install
```

### 2. Build and test

```bash
# Build
just build

# Run tests
just test

# Run in development
just dev
```

### 3. Verify Nix flake

```bash
nix flake check --impure
```

### 4. Test semantic-release

```bash
# Dry run to verify configuration
just test-release
```

### 5. Update secrets

If using SOPS for secrets management:

```bash
# Generate new age keys
just sops-bootstrap dev
just sops-bootstrap ci

# Add secrets
just edit-secrets

# Upload to GitHub
just sops-upload-github-key
just sops-setup-github
```

See [Secrets management guide](/guides/secrets-management) for details.

## Adding more packages

As your project grows, add additional packages:

### 1. Create package directory

```bash
mkdir -p packages/new-package/src
cd packages/new-package
```

### 2. Create package.json

```json
{
  "name": "@yourorg/new-package",
  "version": "0.0.0-development",
  "private": true,
  "description": "Package description",
  "type": "module",
  "repository": {
    "type": "git",
    "url": "https://github.com/yourorg/my-project.git"
  },
  "license": "MIT",
  "scripts": {
    "build": "...",
    "test": "...",
    "test-release": "semantic-release --dry-run --no-ci"
  },
  "release": {
    "extends": "semantic-release-monorepo",
    "branches": [{ "name": "main" }],
    "npmPublish": false,
    "plugins": [
      // Copy from existing package
    ]
  }
}
```

### 3. Update workflow matrices

Add to `.github/workflows/ci.yaml` and `.github/workflows/release.yaml`:

```yaml
matrix:
  package:
    - name: existing-package
      path: packages/existing-package
    - name: new-package
      path: packages/new-package
```

### 4. Create package-specific config

- `tsconfig.json` extending root config
- Test configuration if needed
- Build configuration

### 5. Install and test

```bash
cd ../..
bun install
just test-pkg new-package
```

## Removing template-specific content

After forking, you may want to remove template-specific documentation:

### Optional removals

- `docs/notes/` - Template development notes (safe to remove)
- Template-specific guides (if creating your own)
- Example content in `packages/docs/src/content/docs/`

### Keep these

- `CONTRIBUTING.md` - Conventional commit guidelines
- `.github/workflows/` - CI/CD automation
- `justfile` - Task automation (customize commands)
- Nix configuration - Development environment

## Enabling releases

When ready for public releases:

### 1. Verify conventional commits

Ensure your team understands and uses [conventional commit format](/reference/architecture#commit-message-conventions).

### 2. Test releases

```bash
# Test at root
bun run test-release

# Test per package
cd packages/my-package
bun run test-release
```

### 3. Enable workflow

Uncomment triggers in `.github/workflows/release.yaml`:

```yaml
# Change from:
on:
  workflow_dispatch:
    inputs:
      dry-run:
        default: true

# To:
on:
  push:
    branches:
      - main
  workflow_dispatch:
    inputs:
      dry-run:
        default: false
```

### 4. Verify first release

Push a conventional commit and watch the release workflow:

```bash
git commit -m "feat(my-package): add initial functionality"
git push
gh run watch
```

See [Architecture decisions](/reference/architecture#release-configuration) for release strategy details.

## Getting help

### Template issues

If you encounter issues with the template itself:
- Check [GitHub Issues](https://github.com/sciexp/typescript-nix-template/issues)
- Open a new issue with reproduction steps

### Project-specific issues

For your forked project:
- Consult the guides in this documentation
- Check the [Nix documentation](https://nixos.org/manual/nix/stable/)
- Review [Bun workspace docs](https://bun.sh/docs/install/workspaces)
- See [semantic-release docs](https://semantic-release.gitbook.io/)

## Next steps

After customization:

1. **Set up CI/CD** - Follow [CI/CD setup guide](/guides/ci-cd-setup)
2. **Configure secrets** - Follow [Secrets management guide](/guides/secrets-management)
3. **Add tests** - Follow [Testing guide](/guides/testing)
4. **Deploy** - Configure Cloudflare Workers or your deployment target
5. **Start building** - Create your application code

Welcome to your new TypeScript monorepo!
