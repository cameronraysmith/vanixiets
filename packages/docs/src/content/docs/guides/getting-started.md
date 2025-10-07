---
title: Getting started
description: Quick start guide for using typescript-nix-template
---

Welcome to typescript-nix-template!
This guide will help you get started quickly whether you're using this template for a new project or exploring its features.

## Prerequisites

Before you begin, ensure you have:

- [Nix](https://nixos.org/download.html) with flakes enabled
- [direnv](https://direnv.net/) (recommended for automatic shell activation)
- [Git](https://git-scm.com/) for version control
- A [GitHub](https://github.com) account (for CI/CD features)

### Enabling Nix flakes

If you haven't enabled flakes yet, add this to `~/.config/nix/nix.conf`:

```
experimental-features = nix-command flakes
```

Or for NixOS, add to `/etc/nixos/configuration.nix`:

```nix
nix.settings.experimental-features = [ "nix-command" "flakes" ];
```

## Quick setup

### 1. Get the template

Choose one of these methods:

**Option A: Use as GitHub template**
```bash
# Click "Use this template" on GitHub, then:
git clone https://github.com/YOUR_USERNAME/YOUR_REPO.git
cd YOUR_REPO
```

**Option B: Fork manually**
```bash
git clone https://github.com/sciexp/typescript-nix-template.git my-project
cd my-project
rm -rf .git
git init
```

### 2. Enter the development environment

```bash
# Allow direnv (recommended)
direnv allow

# Or enter manually
nix develop
```

The first time may take a few minutes as Nix downloads dependencies.

### 3. Install JavaScript dependencies

```bash
bun install
```

### 4. Start development server

```bash
just dev
```

Visit http://localhost:4321 to see your site.

## Understanding the structure

This is a Bun workspace monorepo:

```
typescript-nix-template/
├── packages/
│   └── docs/                 # Astro Starlight documentation
│       ├── src/             # Source code
│       ├── e2e/             # End-to-end tests
│       ├── tests/           # Unit test fixtures
│       └── package.json     # Package configuration
├── package.json             # Workspace root
├── flake.nix                # Nix development environment
├── justfile                 # Task automation
└── CONTRIBUTING.md          # Contribution guidelines
```

See [Architecture decisions](/reference/architecture) for design rationale.

## Essential commands

### Development

```bash
# Start dev server
just dev

# Build for production
just build

# Preview production build
just preview
```

### Testing

```bash
# Run all tests
just test

# Run unit tests only
just test-unit

# Run E2E tests only
just test-e2e

# Watch mode
just test-watch
```

See [Testing guide](/guides/testing) for comprehensive documentation.

### Code quality

```bash
# Format code
just format

# Lint code
just lint

# Check and fix
just check
```

### Nix environment

```bash
# Rebuild flake
nix flake check --impure

# Show flake info
nix flake show

# Update dependencies
nix flake update
```

## Next steps

### For template users

If you're using this as a template for your project:

1. **Customize the template** - Follow [Template usage guide](/guides/template-usage) to rename packages and update configuration
2. **Set up CI/CD** - Follow [CI/CD setup guide](/guides/ci-cd-setup) for GitHub Actions automation
3. **Configure secrets** - Follow [Secrets management guide](/guides/secrets-management) for SOPS setup
4. **Write tests** - Follow [Testing guide](/guides/testing) to add your own tests
5. **Deploy** - Deploy to Cloudflare Workers or your preferred platform

### For contributors

If you're contributing to this template:

1. **Read contributing guidelines** - See [CONTRIBUTING.md](https://github.com/sciexp/typescript-nix-template/blob/main/CONTRIBUTING.md)
2. **Understand architecture** - Read [Architecture decisions](/reference/architecture)
3. **Follow conventions** - Use conventional commits for semantic versioning
4. **Test changes** - Run full test suite before committing
5. **Create atomic commits** - Commit changes immediately after editing

## Common tasks

### Adding a new page

Create a new markdown file in `packages/docs/src/content/docs/`:

```bash
# Create a guide
touch packages/docs/src/content/docs/guides/my-guide.md

# Add frontmatter
cat > packages/docs/src/content/docs/guides/my-guide.md << 'EOF'
---
title: My guide
description: Description of my guide
---

Content here...
EOF
```

The page will be automatically available at `/guides/my-guide/`.

### Adding a new package

To add another package to the monorepo:

```bash
# Create package directory
mkdir -p packages/my-package/src

# Create package.json
cd packages/my-package
# ... add package configuration
```

See [Template usage guide](/guides/template-usage#adding-more-packages) for details.

### Running commands in specific packages

```bash
# Using just (recommended)
just docs dev              # Run dev in docs package

# Using bun directly
bun run --filter '@typescript-nix-template/docs' dev
```

### Deploying to Cloudflare Workers

```bash
# Build and deploy
cd packages/docs
bun run deploy

# Or use justfile
just cf-deploy-production
```

See [CI/CD setup guide](/guides/ci-cd-setup) for automated deployment.

## Troubleshooting

### Nix issues

**Problem:** "experimental features not enabled"

**Solution:** Enable flakes in nix configuration (see Prerequisites above)

---

**Problem:** Direnv not activating automatically

**Solution:**
```bash
# Add to ~/.bashrc or ~/.zshrc
eval "$(direnv hook bash)"  # or zsh
```

---

**Problem:** "error: getting status of '/nix/store/...': No such file or directory"

**Solution:** Rebuild the flake:
```bash
nix develop --rebuild
```

### Bun issues

**Problem:** "command not found: bun"

**Solution:** Ensure you're in the Nix development shell:
```bash
nix develop
```

---

**Problem:** Workspace dependencies not resolving

**Solution:** Reinstall dependencies:
```bash
rm -rf node_modules packages/*/node_modules
bun install
```

### Build issues

**Problem:** "Module not found" during build

**Solution:** Check TypeScript paths and ensure all imports are correct:
```bash
just check  # Run biome check
```

---

**Problem:** Playwright browsers not found

**Solution:** The browsers are managed by Nix. Rebuild the development shell:
```bash
exit  # Exit current shell
nix develop --rebuild
```

### Test issues

**Problem:** Tests timing out

**Solution:** Increase timeout in test configuration or check for hanging async operations

---

**Problem:** E2E tests failing with "page not found"

**Solution:** Ensure dev server is running or build is complete:
```bash
just build  # Build before E2E tests
just test-e2e
```

## Getting help

### Documentation

- [Template usage guide](/guides/template-usage) - Forking and customization
- [CI/CD setup guide](/guides/ci-cd-setup) - Automated deployment
- [Testing guide](/guides/testing) - Comprehensive testing
- [Secrets management guide](/guides/secrets-management) - SOPS workflow
- [Architecture decisions](/reference/architecture) - Design rationale

### External resources

- [Nix manual](https://nixos.org/manual/nix/stable/) - Nix package manager
- [Bun documentation](https://bun.sh/docs) - Bun runtime and package manager
- [Astro documentation](https://docs.astro.build/) - Astro framework
- [Starlight documentation](https://starlight.astro.build/) - Starlight docs framework
- [Vitest documentation](https://vitest.dev/) - Unit testing
- [Playwright documentation](https://playwright.dev/) - E2E testing

### Community

- [GitHub Discussions](https://github.com/sciexp/typescript-nix-template/discussions) - Ask questions
- [GitHub Issues](https://github.com/sciexp/typescript-nix-template/issues) - Report bugs or request features

## What's next?

Now that you're set up, you can:

- **Explore the codebase** - Look at example components and tests
- **Customize for your needs** - Follow the template usage guide
- **Build something awesome** - Start creating your project

Happy coding!
