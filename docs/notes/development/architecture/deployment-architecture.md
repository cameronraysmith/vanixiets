# Deployment Architecture

## Development Workflow

**Local Development**:
```bash
# Activate development shell (direnv automatic)
cd ~/projects/nix-workspace/infra
direnv allow  # or: nix develop

# Validate changes
nix flake check                  # Fast structural validation
nix build .#darwinConfigurations.blackphos.system --dry-run  # Build check

# Run test suite
nix build .#checks.x86_64-linux.test-nix-unit-all  # Fast tests (~1s)
nix flake check                                     # Full validation (~11s)

# Generate vars for machine
clan vars generate blackphos

# Deploy to local machine
darwin-rebuild switch --flake .#blackphos

# Deploy to remote machine (VPS)
clan machines update cinnabar
```

**Git Workflow**:
```bash
# Development on clan branch
git checkout clan
git pull origin clan

# Per-host feature branches (optional)
git checkout -b blackphos-migration
# ... make changes ...
git commit -m "feat(blackphos): migrate to dendritic + clan"
git push origin blackphos-migration

# Merge after validation
git checkout clan
git merge blackphos-migration
```

## Terraform Deployment

**Infrastructure Provisioning**:
```bash
# Generate terraform configuration
nix build .#terraform.terraform

# Initialize terraform
nix run .#terraform.terraform -- init

# Plan changes (dry-run)
nix run .#terraform.terraform -- plan

# Apply changes
nix run .#terraform.terraform -- apply

# Destroy infrastructure (toggle enabled=false in config, then apply)
nix run .#terraform.terraform -- apply
```

**State Management**:
- **Local state**: `terraform/terraform.tfstate` (git-ignored)
- **Manual locking**: Single developer, no remote state backend needed
- **Backup**: `terraform.tfstate.backup` automatically created

## NixOS VPS Deployment

**Initial Installation** (Hetzner Cloud):
```bash
# 1. Provision VPS via terraform
nix run .#terraform.terraform -- apply

# 2. Install NixOS via clan (automatic disko partitioning)
clan machines install cinnabar --target-host root@<ip> --update-hardware-config nixos-facter --yes

# 3. System boots with full configuration
# SSH access via clan sshd service (certificate-based)
# Zerotier controller operational
# Clan vars deployed to /run/secrets/
```

**Configuration Updates**:
```bash
# Generate vars (if generator changed)
clan vars generate cinnabar

# Deploy configuration update
clan machines update cinnabar

# Or use nixos-rebuild directly
nixos-rebuild switch --flake .#cinnabar --target-host root@cinnabar.zerotier.ip
```

## Darwin Deployment

**Initial Setup** (blackphos example):
```bash
# 1. Create machine configuration
# modules/machines/darwin/blackphos/default.nix created

# 2. Add to clan inventory
# modules/clan/inventory/machines.nix: blackphos entry added

# 3. Generate vars
clan vars generate blackphos

# 4. Deploy on machine (local execution)
cd ~/projects/nix-workspace/infra
darwin-rebuild switch --flake .#blackphos

# 5. Join zerotier network (if using zerotier)
# Manual or homebrew-based setup (see Darwin Networking Options)
```

**Configuration Updates**:
```bash
# On blackphos machine
cd ~/projects/nix-workspace/infra
git pull origin clan
darwin-rebuild switch --flake .#blackphos
```

## Rollback Procedures

**Per-Machine Rollback**:
```bash
# Darwin (boot menu selection or command)
darwin-rebuild switch --flake .#blackphos --rollback

# NixOS (boot menu selection or command)
nixos-rebuild switch --flake .#cinnabar --rollback --target-host root@cinnabar.zerotier.ip
```

**Git-Based Rollback**:
```bash
# Revert last commit
git revert HEAD

# Redeploy previous configuration
darwin-rebuild switch --flake .#blackphos
```

**Terraform Rollback**:
```bash
# VPS is disposable - destroy and recreate
nix run .#terraform.terraform -- destroy
nix run .#terraform.terraform -- apply
clan machines install cinnabar  # Reinstall from configuration
```

## CI/CD Integration

**GitHub Actions** (future enhancement):
```yaml
name: Validation

on: [push, pull_request]

jobs:
  check:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v24
      - run: nix flake check
```

**Pre-Commit Hooks** (current):
```yaml
# .pre-commit-config.yaml
repos:
  - repo: https://github.com/gitleaks/gitleaks
    rev: v8.18.0
    hooks:
      - id: gitleaks  # Prevent committing secrets

  - repo: https://github.com/nix-community/nixpkgs-fmt
    rev: master
    hooks:
      - id: nixfmt-rfc-style  # Nix code formatting
```
