# Development Environment

## Prerequisites

**Host Machine Requirements**:
- **NixOS**: 24.11+ or darwin: macOS 13+ (Ventura or later)
- **Nix package manager**: 2.18+ with flakes enabled
- **Disk space**: 20GB+ free (for nix store, builds, VMs)
- **Internet**: Required for flake inputs, binary caches, terraform

**Developer Tools**:
- **Git**: 2.40+ (for repository management)
- **direnv**: 2.32+ (automatic nix develop activation)
- **Age**: 1.1+ (for secrets encryption, installed via nix)
- **Zerotier CLI**: 1.14+ (for network management, installed via nix or homebrew)

**Optional Tools**:
- **nix-unit**: For running test suite locally
- **terraform**: For manual infrastructure operations (provided via flake)
- **cachix**: For binary cache (faster builds)

## Setup Commands

**Initial Repository Setup**:
```bash
# Clone repository
git clone https://github.com/cameronraysmith/nix-config.git ~/projects/nix-workspace/infra
cd ~/projects/nix-workspace/infra

# Checkout migration branch
git checkout clan

# Allow direnv (automatic nix develop)
direnv allow

# Initialize clan secrets (first-time only)
nix run nixpkgs#clan-cli -- secrets key generate
YOUR_AGE_KEY=$(grep 'public key:' ~/.config/sops/age/keys.txt | awk '{print $4}')
echo "Provide this age key to repository maintainer: $YOUR_AGE_KEY"

# After maintainer adds you to admins group
clan secrets groups show admins  # Verify you're listed

# Generate vars for machine you'll manage
clan vars generate blackphos  # or cinnabar, etc.
```

**Hetzner Cloud Setup** (for VPS provisioning):
```bash
# Obtain API token from Hetzner Cloud console
# Store in clan secrets
clan secrets set hetzner-api-token
# Paste token when prompted
```

**Validation**:
```bash
# Verify flake evaluates
nix flake show

# Run test suite
nix flake check

# Build machine configuration (dry-run)
nix build .#darwinConfigurations.blackphos.system --dry-run
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel --dry-run
```

**Development Shell Activated**:
```bash
# Check available commands (from devShell)
nix flake show

# Available commands
clan                # Clan CLI for machine management
terraform           # Terraform CLI (via terranix)
nix-unit            # Test runner
# ... other tools in devShell
```

## Editor Integration

**VSCode/VSCodium**:
```json
// .vscode/settings.json
{
  "nix.enableLanguageServer": true,
  "nix.serverPath": "nil",
  "[nix]": {
    "editor.defaultFormatter": "jnoortheen.nix-ide",
    "editor.formatOnSave": true
  }
}
```

**Neovim** (with nil LSP):
```lua
-- ~/.config/nvim/lua/lsp.lua
require('lspconfig').nil_ls.setup({
  settings = {
    ['nil'] = {
      formatting = { command = { "nixfmt" } },
    },
  },
})
```

**Direnv Integration** (automatic nix develop):
```bash
# .envrc (already in repository)
use flake

# Allow direnv
direnv allow

# Shell automatically loads nix develop when entering directory
```
