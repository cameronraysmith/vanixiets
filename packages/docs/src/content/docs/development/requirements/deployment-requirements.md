---
title: Deployment
sidebar:
  order: 7
---

This document specifies requirements for deploying configurations to target systems across different platforms.

## Overview

Deployment requirements define how configurations are built, activated, validated, and rolled back on darwin (macOS) and NixOS systems.
Requirements reflect the deferred module composition + clan architecture currently used across the infrastructure.

## DR-001: Darwin deployment

### Build requirements

**Requirement**: System must build darwin configuration derivation without errors

**Inputs**:
- darwinConfigurations.<hostname> flake output
- All imported modules and dependencies
- nixpkgs with platform-appropriate overlays (aarch64-darwin or x86_64-darwin)

**Command**: `nix build .#darwinConfigurations.<hostname>.system`

**Success criteria**:
- Build completes without evaluation or build errors
- System derivation available in nix store
- Activation script generated

**Validation**:
```bash
# Verify build succeeds
nix build .#darwinConfigurations.<hostname>.system

# Check derivation exists
nix path-info .#darwinConfigurations.<hostname>.system

# Verify activation script
ls -l $(nix build .#darwinConfigurations.<hostname>.system --no-link --print-out-paths)/activate
```

### Activation requirements

**Requirement**: System must activate darwin configuration without breaking running system

**Command**: `darwin-rebuild switch --flake .#<hostname>`

**Process**:
1. Build new system configuration
2. Compare with current generation
3. Stop services that will be replaced
4. Install new system profile
5. Activate new configuration
6. Start new/updated services
7. Record generation in profile history

**Success criteria**:
- Activation completes successfully
- System remains responsive
- All services start correctly
- New generation recorded
- User can interact with system

**Validation**:
```bash
# Check system profile
darwin-rebuild --list-generations

# Verify services running
launchctl list | grep -i nix

# Test key functionality (e.g., shell, ssh, development tools)
```

### Rollback requirements

**Requirement**: System must support rollback to previous working generation

**Command**: `darwin-rebuild switch --rollback` or manual activation

**Process**:
1. Identify previous generation
2. Activate previous system profile
3. Restart services with previous configuration
4. Verify system operational

**Success criteria**:
- Rollback completes successfully
- System restored to previous state
- Services operational
- No data loss

**Validation**:
```bash
# Manual rollback
sudo /nix/var/nix/profiles/system-<N>-link/activate

# Or via darwin-rebuild
darwin-rebuild switch --rollback

# Verify generation active
darwin-rebuild --list-generations | grep current
```

### Dry-run requirements

**Requirement**: System must preview activation changes without applying them

**Command**: `darwin-rebuild switch --dry-run --flake .#<hostname>`

**Outputs**:
- List of package changes (additions, removals, updates)
- Service changes
- Configuration differences
- No actual system modification

**Use cases**:
- Pre-deployment validation (UC-007 migration)
- Understanding impact of changes
- CI validation before merge

## DR-002: NixOS deployment

### Build requirements

**Requirement**: System must build NixOS configuration toplevel derivation

**Inputs**:
- nixosConfigurations.<hostname> flake output
- All imported modules and dependencies
- nixpkgs with platform-appropriate overlays (x86_64-linux or aarch64-linux)

**Command**: `nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel`

**Success criteria**:
- Build completes without errors
- Toplevel derivation available
- Bootloader configuration generated
- Init system configured

**Validation**:
```bash
# Verify build succeeds
nix build .#nixosConfigurations.<hostname>.config.system.build.toplevel

# Check bootloader configuration
nix eval .#nixosConfigurations.<hostname>.config.boot.loader --json
```

### Activation requirements

**Requirement**: System must activate NixOS configuration via systemd

**Command**: `nixos-rebuild switch --flake .#<hostname>`

**Process**:
1. Build new system configuration
2. Create new boot entry
3. Switch system profile to new generation
4. Reload systemd daemon
5. Stop removed services
6. Start new/updated services
7. Record generation

**Success criteria**:
- Activation completes successfully
- Systemd services operational
- Boot entry created
- System remains accessible
- Generation recorded

**Validation**:
```bash
# Check system profile
nix-env --list-generations --profile /nix/var/nix/profiles/system

# Verify systemd state
systemctl status

# Check boot entries
ls /boot/loader/entries/
```

### Rollback requirements

**Requirement**: System must support generation rollback and boot entry selection

**Command**: `nixos-rebuild switch --rollback` or boot into previous generation

**Process**:
1. Switch to previous generation profile
2. Reload systemd with previous configuration
3. Restart affected services
4. Or: reboot and select previous boot entry

**Success criteria**:
- Rollback completes successfully
- System operational with previous configuration
- Boot entries preserved for emergency recovery

**Validation**:
```bash
# Rollback to previous generation
nixos-rebuild switch --rollback

# Or boot into specific generation (requires reboot)
# Select from bootloader menu
```

### Remote deployment requirements

**Requirement**: System must support remote deployment via SSH (for VPS)

**Command**: `nixos-rebuild switch --flake .#<hostname> --target-host <user>@<host> --use-remote-sudo`

**Prerequisites**:
- SSH access to target host
- Nix installed on target
- Sudo privileges for activation

**Success criteria**:
- Build executed locally (or on target via --build-host)
- Configuration copied to target
- Activation executes on target
- Remote system remains accessible

**Validation**:
```bash
# Test SSH access
ssh <user>@<host> 'nix --version'

# Deploy
nixos-rebuild switch --flake .#<hostname> --target-host <user>@<host> --use-remote-sudo

# Verify remotely
ssh <user>@<host> 'nix-env --list-generations --profile /nix/var/nix/profiles/system'
```

## DR-003: Home-manager deployment

### Standalone deployment

**Requirement**: Deploy home-manager configuration independently (current architecture)

**Command**: `home-manager switch --flake .#<username>@<hostname>`

**Process**:
1. Build home-manager configuration
2. Activate user environment
3. Link configuration files to home directory
4. Restart user services

**Success criteria**:
- User environment updated
- Dotfiles deployed correctly
- User services operational
- No system-level privileges required

### Integrated deployment

**Requirement**: Deploy home-manager as part of system configuration

**Process**:
- home-manager integrated into darwinConfiguration or nixosConfiguration
- Activates automatically during system activation
- Shares nix store paths with system configuration

**Success criteria**:
- Single activation command for system + user environment
- Consistent package versions between system and user

**Validation**:
```bash
# Verify home-manager generation
home-manager generations

# Check user services
systemctl --user status  # NixOS
launchctl list | grep home-manager  # darwin
```

## DR-004: Clan orchestration deployment

### Vars generation requirements

**Requirement**: Generate secrets and configuration values before deployment

**Command**: `clan vars generate <hostname>`

**Process**:
1. Evaluate generator definitions
2. Execute generator scripts in dependency order (DAG)
3. Encrypt secrets with host age key
4. Store public values as facts
5. Commit encrypted files to repository

**Success criteria**:
- All generators execute successfully
- Secrets encrypted in sops/machines/<hostname>/secrets/
- Facts stored in sops/machines/<hostname>/facts/
- Prompts answered (or defaults used)
- Dependencies resolved correctly

**Validation**:
```bash
# Generate vars
clan vars generate <hostname>

# Verify secrets encrypted
file sops/machines/<hostname>/secrets/*.yaml
# Should show: data (encrypted, not ASCII text)

# Check facts directory
ls sops/machines/<hostname>/facts/
```

### Machine deployment requirements

**Requirement**: Deploy configuration via clan orchestration workflow

**Command**: `clan machines update <hostname>`

**Process**:
1. Build system configuration
2. Deploy secrets to /run/secrets/
3. Activate system configuration
4. Verify services operational

**Success criteria**:
- Configuration deployed successfully
- Secrets accessible at expected paths
- System operational
- Role-based configuration applied (for service instances)

**Validation**:
```bash
# Deploy
clan machines update <hostname>

# Verify secrets deployed
ls /run/secrets/

# Check services
systemctl status <service>  # NixOS
launchctl list | grep <service>  # darwin
```

### Multi-host deployment requirements

**Requirement**: Deploy service instance across multiple hosts

**Process**:
1. Define service instance in inventory
2. Generate vars for all participating hosts
3. Deploy to controller role first
4. Deploy to remaining roles
5. Verify inter-host coordination

**Success criteria**:
- All hosts deployed successfully
- Role-appropriate configuration applied to each
- Service coordination operational
- Inter-host communication functional

**Example** (zerotier deployment across 8-machine fleet):
```bash
# Generate vars for all hosts
# NixOS VPS: cinnabar (controller), electrum, galena, scheelite (peers)
# Darwin: stibnite, blackphos, rosegold, argentum (peers)
for host in cinnabar electrum galena scheelite stibnite blackphos rosegold argentum; do
  clan vars generate $host
done

# Deploy controller first (NixOS VPS)
clan machines update cinnabar

# Deploy NixOS peers
clan machines update electrum
clan machines update galena
clan machines update scheelite

# Deploy Darwin peers
clan machines update stibnite
clan machines update blackphos
clan machines update rosegold
clan machines update argentum

# Verify zerotier network
zerotier-cli listnetworks
ping <peer-zerotier-ip>
```

## DR-005: CI/CD deployment

### Automated validation requirements

**Requirement**: Validate all configurations in CI before merge

**Process**:
1. Checkout repository
2. Setup Nix with cachix
3. Run `nix flake check`
4. Build all configurations
5. Run static analysis (linting)
6. Report results

**Success criteria**:
- All checks pass
- All configurations build successfully
- No lint errors
- Results reported to PR

**GitHub Actions**:
```yaml
# .github/workflows/check.yml
jobs:
  check:
    steps:
      - uses: actions/checkout@v4
      - uses: cachix/install-nix-action@v25
      - uses: cachix/cachix-action@v14
      - run: nix flake check
      - run: nix build .#darwinConfigurations.<hostname>.system
```

### Cache population requirements

**Requirement**: Push successful builds to cachix for reuse

**Process**:
1. Build derivations in CI
2. Push outputs to cachix
3. Tag with commit SHA or branch

**Success criteria**:
- Build artifacts available in cache
- Local development can fetch from cache
- Reduced rebuild times

**Benefits**:
- Faster local builds
- Consistent binaries across environments
- CI validates what will be deployed

## DR-006: Validation and testing requirements

### Pre-activation validation

**Requirement**: Validate configuration before activation

**Checks**:
- Evaluation succeeds: `nix flake check`
- Build succeeds: `nix build .#<config>`
- Dry-run shows expected changes
- No secrets in nix store
- Configuration differences reviewed

**Process**:
```bash
# 1. Evaluate
nix flake check

# 2. Build
nix build .#darwinConfigurations.<hostname>.system

# 3. Dry-run
darwin-rebuild switch --dry-run --flake .#<hostname>

# 4. Review changes
git diff HEAD

# 5. Deploy
darwin-rebuild switch --flake .#<hostname>
```

### Post-activation validation

**Requirement**: Verify system operational after activation

**Checks**:
- System responsive
- Services running
- Key functionality operational (shell, ssh, development tools)
- No error logs
- Performance acceptable

**Process**:
```bash
# Check services
launchctl list | grep error  # darwin
systemctl --failed  # NixOS

# Test functionality
fish --version
ssh localhost echo "test"
nix develop --command echo "shell works"

# Check logs
log show --predicate 'processImagePath contains "nix"' --last 5m  # darwin
journalctl -xe  # NixOS
```

### Health monitoring requirements

**Requirement**: Monitor system health post-migration (UC-007)

**Duration**: 1-2 weeks per host during migration

**Metrics**:
- System stability (no unexpected reboots)
- Service availability
- Performance (build times, activation speed)
- Error rates (logs)
- User workflows functional

**Process**:
- Daily spot checks of key functionality
- Review logs weekly
- Performance baseline comparison
- Go/no-go decision before next migration

## DR-007: Secrets deployment requirements

### Legacy secrets (sops-nix)

**Requirement**: Deploy manually-managed secrets via sops-nix during activation

**Process**:
1. Secrets defined in secrets/ directory
2. Encrypted with host age keys
3. sops-nix module decrypts during activation
4. Secrets mounted to /run/secrets/
5. Proper permissions applied

**Configuration**:
```nix
sops.secrets."example-secret" = {
  sopsFile = ./secrets/common.yaml;
  owner = "user";
  mode = "0400";
};

# Use in configuration
services.example.passwordFile = config.sops.secrets."example-secret".path;
```

### Generated secrets (clan vars)

**Requirement**: Deploy generated and external secrets via clan vars

**Generated secrets**:
- Defined declaratively as generators
- Generated via `clan vars generate`
- Automatically deployed during activation
- Available at /run/secrets/<generator>.<file>

**External secrets**:
- Remain in sops-nix (for manually managed secrets)
- Hybrid approach supported
- Migration path preserves both methods

**Configuration**:
```nix
# Generated secret
clan.core.vars.generators.example = {
  script = ''
    echo "generated-value" > $out/secret
  '';
  files.secret = { secret = true; };
};

# Use in configuration
services.example.passwordFile = config.clan.core.vars.generators.example.files.secret.path;
```

## DR-008: Platform-specific requirements

### Darwin-specific

**Requirements**:
- darwin-rebuild must have sudo access for activation
- Homebrew installations remain imperative (managed outside Nix)
- LaunchDaemons/LaunchAgents configured via nix-darwin
- System state version compatibility maintained

**Constraints**:
- No system-wide rollback via bootloader (unlike NixOS)
- Activation requires current user session active
- Some system settings require logout/restart

### NixOS-specific

**Requirements**:
- Bootloader configuration updated with each generation
- Systemd units managed via NixOS modules
- Initrd and kernel configured declaratively
- /boot partition writable during activation

**Constraints**:
- Kernel changes require reboot
- Bootloader failures may prevent boot (mitigated by previous entries)
- Remote deployment requires SSH + sudo

### VPS-specific

**Requirements**:
- Remote deployment supported via SSH
- Platform-specific initialization (Hetzner for cinnabar/electrum, GCP for galena/scheelite)
- Network configuration preserved during activation
- SSH access maintained throughout deployment

**Constraints**:
- No physical access for recovery
- Network interruption = loss of access
- Backup strategy critical

**Fleet VPS machines**:
- cinnabar (Hetzner, permanent zerotier controller)
- electrum (Hetzner, peer)
- galena (GCP, peer)
- scheelite (GCP, peer)

## DR-009: Rollback and recovery requirements

### Generation management

**Requirement**: Preserve sufficient generations for rollback

**Configuration**:
```nix
nix.gc = {
  automatic = true;
  options = "--delete-older-than 30d";
};

# Preserve at least 5 generations
boot.loader.systemd-boot.configurationLimit = 10;  # NixOS
```

**Process**:
- Automatic garbage collection after retention period
- Manual cleanup: `nix-collect-garbage --delete-older-than 30d`
- Boot entries preserved (NixOS)

### Emergency recovery

**Requirement**: Recovery procedures for deployment failures

**Darwin recovery**:
```bash
# Method 1: Rollback via darwin-rebuild
darwin-rebuild switch --rollback

# Method 2: Manual activation of previous generation
ls -la /nix/var/nix/profiles/system-*-link
sudo /nix/var/nix/profiles/system-<N>-link/activate

# Method 3: Git revert + rebuild
git log --oneline
git checkout <previous-commit>
darwin-rebuild switch --flake .#<hostname>
```

**NixOS recovery**:
```bash
# Method 1: Rollback
nixos-rebuild switch --rollback

# Method 2: Boot into previous generation
# Reboot and select from bootloader menu

# Method 3: Remote recovery (VPS)
ssh <host> 'sudo /nix/var/nix/profiles/system-<N>-link/bin/switch-to-configuration switch'
```

## DR-010: Environment-specific requirements

### Development environment

**Requirements**:
- Fast iteration (minimal rebuild)
- Local cache enabled
- Dry-run always available
- Rollback tested and working

**Workflow**:
```bash
# Edit → Check → Build → Dry-run → Deploy
vim modules/hosts/<hostname>/default.nix
nix flake check
nix build .#darwinConfigurations.<hostname>.system
darwin-rebuild switch --dry-run --flake .#<hostname>
darwin-rebuild switch --flake .#<hostname>
```

### Production deployment (migration)

**Requirements**:
- Pre-deployment validation complete
- Backup verified
- Rollback procedure documented and tested
- Monitoring enabled
- Stable previous configuration preserved

**Workflow**:
```bash
# Pre-migration checklist
- [ ] CI passing
- [ ] Dry-run reviewed
- [ ] Backup current generation
- [ ] Rollback procedure tested
- [ ] Time allocated for issues

# Deploy
darwin-rebuild switch --flake .#<hostname>

# Post-deployment validation
- [ ] Services operational
- [ ] Key workflows functional
- [ ] No error logs
- [ ] Performance acceptable

# Monitor for 1-2 weeks before next host
```

## References

**Context layer**:
- [Project scope](../context/project-scope/) - Migration strategy
- [Domain model](../context/domain-model/) - Technical architecture

**Requirements**:
- [Usage model](/development/requirements/usage-model/) - Deployment use cases (UC-001, UC-007)
- [Quality requirements](/development/requirements/quality-requirements/) - Reliability, performance
- [System constraints](/development/requirements/system-constraints/) - Platform limitations

**Architecture**:
- [CI philosophy](../../traceability/ci-philosophy/) - Validation approach
- [ADR-0021: Terranix Infrastructure Provisioning](/development/architecture/adrs/0021-terranix-infrastructure-provisioning/) - VPS deployment architecture decisions
- nix-darwin documentation: https://github.com/LnL7/nix-darwin
- NixOS manual: https://nixos.org/manual/nixos/stable/
