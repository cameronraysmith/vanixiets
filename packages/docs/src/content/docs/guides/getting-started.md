---
title: Getting started
description: Quick start guide for bootstrapping and using this nix-config
sidebar:
  order: 2
---

This guide walks through bootstrapping a new machine with this configuration.

## Prerequisites

Before you begin, ensure you have:
- Physical access or SSH access to the target machine
- macOS (for nix-darwin) or NixOS system
- Internet connection for downloading Nix and packages

## Quick setup

### Step 1: Clone the repository

```bash
git clone https://github.com/cameronraysmith/infra.git
cd infra
```

### Step 2: Bootstrap Nix and essential tools

```bash
make bootstrap && exec $SHELL
```

**What this does:**
- Installs Nix using the [NixOS community installer](https://github.com/NixOS/experimental-nix-installer)
- Configures Nix with comprehensive settings for optimal performance:
  - Enables flakes and nix-command experimental features
  - Enables store optimization (auto-optimise-store) and parallel builds (max-jobs)
  - Allows binary cache substitution for all derivations (always-allow-substitutes)
  - Configures legacy NIX_PATH compatibility (extra-nix-path)
- Installs direnv for automatic environment activation

### Step 3: Allow direnv

```bash
direnv allow
# or if already in the shell:
direnv reload
```

**What this does:**
- Automatically loads the Nix development shell
- Makes `just` and other dev tools available
- Activates the project environment

### Step 4: Verify installation

```bash
make verify
```

**This checks:**
- Nix installation
- Flakes support
- Flake validity

### Step 5: Set up secrets (optional, for existing users)

```bash
make setup-user
```

**What this does:**
- Generates age key at `~/.config/sops/age/keys.txt` for secrets encryption
- Skip this if you're just exploring the configuration

### Step 6: Activate configuration

**For admin users** (Darwin/NixOS with integrated home-manager):
```bash
nix run . hostname
# Example: nix run . stibnite
```

**For non-admin users** (standalone home-manager, no sudo required):
```bash
nix run . user@hostname
# Example: nix run . runner@stibnite
```

Or use the justfile shortcut:
```bash
just activate
```

## Essential commands

Once you've activated direnv, you have access to the `just` task runner:

```bash
# Show all available commands
just help

# Or just run 'just' to see the command list
just
```

### Common tasks

**System management:**
```bash
just activate          # Activate configuration for current user/host
just update            # Update nix flake inputs
just verify            # Verify system builds without activating
```

**Development:**
```bash
just dev               # Enter development shell manually
just lint              # Lint nix files
just clean             # Remove build output links
```

**Secrets:**
```bash
just check-secrets     # Verify secrets access
just edit-secret FILE  # Edit encrypted secret
just validate-secrets  # Validate all secrets decrypt correctly
```

**Troubleshooting:**
```bash
just bisect-nixpkgs    # Find breaking nixpkgs commits
just verify            # Test if configuration builds
```

See the full command reference by running `just help` after activating the dev shell.

## Understanding the structure

This nix-config uses directory-based autowiring:

```
infra/
├── configurations/   # System and home configurations
│   ├── darwin/       # macOS (nix-darwin)
│   ├── nixos/        # Linux (NixOS)
│   └── home/         # Standalone home-manager
├── modules/          # Reusable modules
├── overlays/         # Package overlays
└── lib/              # Shared library functions
```

See [Repository Structure](/reference/repository-structure) for complete directory mapping.

## Next steps

### Learn the architecture

- [Nix-Config Architecture](/concepts/nix-config-architecture) - Understand the three-layer design
- [Understanding Autowiring](/concepts/understanding-autowiring) - How directory-based autowiring works
- [Multi-User Patterns](/concepts/multi-user-patterns) - Admin vs non-admin users

### Set up a new machine

- [Host Onboarding](/guides/host-onboarding) - Add a new Darwin/NixOS host
- [Home Manager Onboarding](/guides/home-manager-onboarding) - Add a new standalone user

### Operational tasks

- [Secrets Management](/guides/secrets-management) - Managing encrypted secrets with SOPS
- [Handling broken packages](/guides/handling-broken-packages) - Fixing broken packages from nixpkgs unstable

## Troubleshooting

### Nix not found after bootstrap

**Solution:** Restart your shell or source the nix profile:
```bash
exec $SHELL
# or
source /nix/var/nix/profiles/default/etc/profile.d/nix-daemon.sh
```

### Direnv not activating

**Solution:** Ensure direnv is installed and hooked into your shell.
Check `~/.bashrc` or `~/.zshrc` for:
```bash
eval "$(direnv hook bash)"  # or zsh
```

### Build failures

**Solution:** Check if nixpkgs unstable has breaking changes:
```bash
just verify  # Test build without activating
```

If build fails, see [Handling broken packages](/guides/handling-broken-packages) for troubleshooting workflow.

### Secrets not decrypting

**Solution:** Ensure your age key is properly set up:
```bash
make setup-user                    # Generate age key
just check-secrets                 # Verify access
```

See [Secrets Management](/guides/secrets-management) for detailed troubleshooting.

## Getting help

### Documentation

- [Guides](/guides/) - Task-oriented how-tos
- [Concepts](/concepts/) - Understanding-oriented explanations
- [Reference](/reference/repository-structure/) - Information-oriented lookup

### External resources

- [Nix manual](https://nixos.org/manual/nix/stable/) - Official Nix documentation
- [NixOS wiki](https://nixos.wiki/) - Community documentation
- [nix-darwin](https://github.com/LnL7/nix-darwin) - macOS system configuration
- [home-manager](https://github.com/nix-community/home-manager) - User environment management

### Community

- [GitHub Discussions](https://github.com/cameronraysmith/infra/discussions) - Ask questions
- [GitHub Issues](https://github.com/cameronraysmith/infra/issues) - Report bugs

## What's next?

Now that you're set up, you can:
- Explore the configuration files to understand the setup
- Customize the configuration for your needs
- Add new hosts or users following the onboarding guides
- Set up secrets management for sensitive data
