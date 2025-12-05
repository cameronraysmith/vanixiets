---
title: System constraints
sidebar:
  order: 3
---

This document defines grey-box restrictions on system architecture and quality.
Constraints specify what the system cannot do or how it must behave, viewing the system as a grey box (knowing internal structure exists without full implementation details).

## Overview

System constraints define boundaries and limitations imposed by the underlying technologies, platforms, and architectural decisions.
These constraints shape design choices and set expectations for what is achievable.

Constraints are organized by category and include rationale, implications, and mitigation strategies where applicable.

## SC-001: Nix evaluation constraints

### Pure evaluation requirement

**Constraint**: Nix evaluation must be pure (no network access, no ambient system state, deterministic)

**Rationale**: Flakes enforce purity to ensure reproducibility

**Implications**:
- Cannot fetch external resources during evaluation
- Cannot read files outside of flake directory (except via inputs)
- Cannot access environment variables during evaluation
- Time-based evaluation (builtins.currentTime) discouraged

**Exceptions**:
- Flake inputs fetched before evaluation (locked in flake.lock)
- Import-from-derivation (IFD) allows controlled purity breaks (discouraged)

**Mitigation**:
- All external resources declared as flake inputs
- Configuration data embedded in repository
- Build-time operations moved to derivation builders

**References**:
- Nix flakes RFC: https://github.com/NixOS/rfcs/pull/49
- [Context: Constraints](../context/constraints-and-rules/) - C-T01: Nix evaluation purity

### Lazy evaluation characteristics

**Constraint**: Nix evaluation is lazy (values computed only when needed)

**Implications**:
- Evaluation order non-deterministic
- Errors may appear late in evaluation
- Performance depends on what is evaluated, not what is defined
- Circular dependencies not always immediately apparent

**Benefits**:
- Efficient evaluation (unused code paths not evaluated)
- Enables conditional imports
- Supports large module trees

**Mitigation**:
- `nix flake check` forces evaluation of outputs
- Static analysis catches some circular dependencies
- Module system prevents option definition cycles

### Type checking at evaluation time

**Constraint**: Module system type checking occurs during evaluation, not statically

**Implications**:
- Type errors discovered when configuration evaluated
- No compile-time safety (evaluation time is "compile time")
- Type errors may be discovered late in development

**Benefits**:
- Types enforced before build/deployment
- Invalid configurations rejected early
- Better than runtime type errors

**Mitigation**:
- Frequent evaluation during development (`nix flake check`)
- CI validates all configurations
- IDE tooling (nil, nixd) provides type checking during editing

## SC-002: Module system constraints

### Option definition precedence

**Constraint**: Module system resolves option collisions via priority and merging rules

**Priority rules**:
- Default priority: 1000
- Lower number = higher priority
- mkDefault: priority 1000
- mkForce: priority 50
- mkOverride N: priority N

**Implications**:
- Multiple definitions of same option must be compatible
- Incompatible definitions cause evaluation errors
- Priority system can be confusing

**Mitigation**:
- Clear documentation of which modules define which options
- Use mkDefault for module defaults (allows overriding)
- Use mkForce sparingly (only when necessary)
- Prefer composition over forcing

### Type system limitations

**Constraint**: Module system types are structural, not nominal

**Implications**:
- Two structurally identical types are equivalent
- No type aliases with different behavior
- Submodules provide structure but not encapsulation

**Limitations**:
- No parametric polymorphism
- No type-level computation
- No dependent types

**Mitigation**:
- Use submodules for structured configuration
- Document expected types clearly
- Validation functions in assertions

### Import cycles prevention

**Constraint**: Module imports must form a directed acyclic graph (DAG)

**Implications**:
- Module A importing module B importing module A is forbidden
- Circular dependencies must be broken via shared modules
- Import structure must be carefully designed

**Detection**:
- Evaluation fails with infinite recursion error
- Error messages may not clearly indicate cycle

**Mitigation**:
- Dendritic pattern: every file is flake-parts module (no imports between modules)
- Shared configuration via config.flake.modules.* namespace
- Clear module organization by category

## SC-003: Flake constraints

### Input locking requirement

**Constraint**: Flake inputs must be lockable to specific revisions

**Mechanism**: flake.lock records exact revisions, hashes, and metadata

**Implications**:
- Reproducible builds require committed flake.lock
- Updating inputs is explicit operation (`nix flake update`)
- No floating tags or branches (locked to specific commits)

**Benefits**:
- Reproducibility guaranteed
- No surprise dependency updates
- Explicit control over input versions

**Management**:
- `nix flake update` updates all inputs
- `nix flake lock --update-input <name>` updates specific input
- Commit flake.lock after updates

### Output schema constraints

**Constraint**: Flake outputs must conform to expected schema

**Required outputs** (for our use case):
- darwinConfigurations.<hostname> (darwin systems)
- nixosConfigurations.<hostname> (NixOS systems)
- packages.<system>.<name> (custom packages)
- devShells.<system>.default (development shells)

**Implications**:
- Output names must follow conventions
- Tools expect specific output paths
- Non-standard outputs may not be discovered

**Extension points**:
- legacyPackages for non-standard package organization
- Custom outputs via flake-parts modules
- apps, checks, overlays, etc. supported

### Purity enforcement

**Constraint**: Flakes enforce pure evaluation by default

**Restrictions**:
- No --impure flag in standard workflows
- No access to NIX_PATH
- No <nixpkgs> imports
- No environment variables during evaluation

**Benefits**:
- Reproducibility enforced at language level
- Clear input/output boundaries
- Predictable evaluation

**Implications for migration**:
- Legacy code using <nixpkgs> must be refactored
- Environment-based configuration must move to explicit inputs
- Impure operations moved to derivation build phase

## SC-004: Platform-specific constraints

### Darwin (macOS) limitations

**System configuration constraints**:
- Not all system settings manageable via nix-darwin
- Some settings require GUI (System Preferences)
- Homebrew installations remain imperative

**Activation constraints**:
- No bootloader integration (unlike NixOS)
- No rollback via boot menu
- Activation requires active user session
- Sudo required for system changes

**State management**:
- LaunchDaemons/LaunchAgents managed declaratively
- Some system state remains imperative
- User preferences not all configurable

**Architecture support**:
- aarch64-darwin (Apple Silicon) primary
- x86_64-darwin (Intel) secondary
- Some packages unavailable or broken on darwin

### NixOS system constraints

**Boot requirements**:
- Bootloader must be configured correctly
- Kernel and initrd generated per-generation
- /boot partition must be writable
- UEFI or legacy boot mode must match hardware

**Systemd integration**:
- All services managed via systemd units
- Non-systemd init not supported
- Service dependencies via systemd directives

**Immutability characteristics**:
- /nix/store immutable
- System configuration in /etc/nixos/ (or flake)
- Runtime state in /var/, /run/

**Platform support**:
- x86_64-linux primary
- aarch64-linux secondary
- Other architectures limited support

### Cross-platform differences

**File system**:
- darwin: case-insensitive (default), HFS+ or APFS
- NixOS: case-sensitive, ext4 or btrfs typical

**User management**:
- darwin: users managed via macOS (declarative via nix-darwin)
- NixOS: users fully declarative via configuration

**Service management**:
- darwin: launchd (LaunchDaemons/LaunchAgents)
- NixOS: systemd (units, targets, timers)

**Package availability**:
- Some packages darwin-only (e.g., Homebrew casks)
- Some packages linux-only (e.g., systemd-specific)
- Cross-platform packages may have different dependencies

## SC-005: Dendritic pattern constraints

### Every file is a module

**Constraint**: All .nix files in modules/ are flake-parts modules

**Implications**:
- No direct imports between module files
- All modules auto-discovered via import-tree
- Module structure dictated by pattern

**Benefits**:
- Zero import boilerplate
- Automatic discovery
- Type-safe cross-references via config.flake.modules.*

**Limitations**:
- Cannot share helper functions across modules via imports
- Shared code must be in lib/ or passed via module system

### Namespace organization

**Constraint**: Modules organized by flake.modules.<class>.<feature> namespace

**Classes**:
- darwin: System-level darwin configuration
- nixos: System-level NixOS configuration
- homeManager: User-level configuration
- flake-parts: Flake-wide configuration (clan, overlays, etc.)

**Implications**:
- Feature name must be unique within class
- Cross-platform features use same name in different classes
- Host imports via config.flake.modules.<class>.<feature>

**Example**:
```nix
# modules/shell/fish.nix defines:
flake.modules.darwin.shell-fish = { ... };
flake.modules.homeManager.shell-fish = { ... };
flake.modules.nixos.shell-fish = { ... };

# Host imports via:
imports = [ config.flake.modules.darwin.shell-fish ];
```

### No specialArgs

**Constraint**: Dendritic pattern eliminates specialArgs for type safety

**Legacy architecture (nixos-unified, deprecated)**: Used specialArgs to pass custom arguments

**Current architecture (dendritic)**: All arguments via module system

**Implications**:
- Module signatures: { config, pkgs, lib, ... }
- Cross-module references via config.flake.modules.*
- Type-checked at evaluation time

**Benefits**:
- Type safety enforced
- Explicit dependencies
- Clear module boundaries

## SC-006: Clan-core constraints

### Inventory structure requirements

**Constraint**: Clan inventory must follow expected schema

**Required structure**:
```nix
inventory = {
  machines.<hostname> = {
    tags = [ ... ];
    machineClass = "darwin" | "nixos";
  };
  instances.<name> = {
    module = { name = "..."; input = "..."; };
    roles.<role>.machines.<hostname> = { ... };
    roles.<role>.tags.<tag> = { ... };
  };
};
```

**Implications**:
- Machine names must be valid Nix identifiers
- Tags must be strings
- machineClass must match available classes
- Service module must exist in specified input

**Validation**:
- Clan validates inventory structure at evaluation
- Type errors reported during nix flake check

See [ADR-0019: Clan-Core Orchestration](/development/architecture/adrs/0019-clan-core-orchestration/) for architectural decisions regarding clan integration.

### Vars system constraints

**Generator script requirements**:
- Script must write files to $out/
- Files must be declared in files attribute
- Script must be reproducible (given same prompts)
- Script runs in sandbox (limited environment)

**Secret encryption constraints**:
- Age encryption mandatory for secrets
- Host age keys must exist before vars generation
- Encrypted files stored in sops/machines/<hostname>/secrets/
- Facts (non-secrets) stored in sops/machines/<hostname>/facts/

**Deployment constraints**:
- Secrets deployed to /run/secrets/ during activation
- Paths available via config.clan.core.vars.generators.<name>.files.<file>.path
- Permissions set to 0400 for secrets by default

### Service instance constraints

**Role assignment limitations**:
- Machine can have only one role per instance
- Role assignment via machines or tags, not both
- Tag-based assignment matches all machines with tag

**Configuration hierarchy**:
- Instance-wide → role-wide → machine-specific
- Later overrides earlier
- Must be compatible types for merging

**Module requirements**:
- Service module must be clan-compatible
- Module must define expected roles
- Module must handle configuration hierarchy

## SC-007: Build system constraints

### Nix store immutability

**Constraint**: Files in /nix/store are immutable after creation

**Implications**:
- No in-place updates of packages
- Configuration changes require new store paths
- Disk usage grows with generations (mitigated by garbage collection)

**Benefits**:
- Rollback always possible
- No corruption from partial updates
- Multiple versions coexist

**Management**:
- Garbage collection removes unused store paths
- Hard links deduplicate identical files
- Optimise reduces disk usage via hard links

### Derivation requirements

**Constraint**: Packages built via derivations with declared dependencies

**Requirements**:
- All build inputs declared explicitly
- Build must be reproducible
- No network access during build (except fixed-output derivations)
- Build runs in sandbox

**Implications**:
- Build-time dependencies separate from runtime dependencies
- Cross-compilation requires careful dependency specification
- Binary caches provide pre-built derivations

### Binary cache constraints

**Read-only constraint**: Binary caches are read-only (from user perspective)

**Trust model**:
- Substituters trusted via public keys
- Cachix provides public/private cache hosting
- Untrusted caches require local build

**Performance implications**:
- Cache miss requires local build or fetch from other caches
- Cache hit dramatically faster than building
- Multiple caches checked in order

**Configuration**:
```nix
nix.settings = {
  substituters = [
    "https://cache.nixos.org"
    "https://nix-community.cachix.org"
    "https://infra.cachix.org"  # Project cache
  ];
  trusted-public-keys = [ ... ];
};
```

## SC-008: Secrets management constraints

### Age encryption requirements

**Constraint**: Secrets encrypted with age public keys

**Key management**:
- Each host has age key pair
- Public keys committed to repository
- Private keys stored securely on hosts
- No key escrow (lost private key = lost secrets)

**Implications**:
- Host must have private key to decrypt secrets
- Re-encryption required for key rotation
- Shared secrets require group public keys

**Best practices**:
- Backup age keys securely
- Generate new keys for new hosts
- Rotate keys periodically
- Document key recovery procedure

### Secrets in nix store prohibition

**Constraint**: Secrets must never enter nix store

**Rationale**: Nix store is world-readable

**Mechanisms**:
- sops-nix decrypts at activation time
- Secrets mounted to /run/secrets/ (tmpfs)
- Proper permissions applied (0400 default)
- Configuration references secret paths, not values

**Validation**:
```bash
# This should find no secrets
nix-store --query --tree $(nix eval --raw .#darwinConfigurations.<hostname>.config.system.build.toplevel) | rg "password|secret|token"
```

### Hybrid secrets management (active design)

**Constraint**: Both sops-nix and clan vars operate simultaneously by design

**Architecture**: Hybrid approach divides responsibility by secret type

**Division of responsibility**:
- Clan vars: Generated secrets (SSH host keys, service credentials)
- Sops-nix: External secrets (API tokens, cloud credentials, user keys)

**Coexistence requirements**:
- Both systems operational simultaneously
- No conflicts in secret paths
- Clear documentation of which system manages which secrets
- Explicit ownership per secret type

## SC-009: Network and connectivity constraints

### Overlay network requirements

**Constraint**: Zerotier requires controller always-on

**Architecture**:
- Controller on VPS (cinnabar) - persistent
- Peers on darwin workstations - intermittent
- Network survives peer restarts
- Controller unavailability blocks new joins

**Implications**:
- VPS must be deployed first (Phase 1)
- Peers can join/leave dynamically
- Network configuration centralized on controller

**Connectivity constraints**:
- Peers need internet access to reach controller
- NAT traversal handled by zerotier
- Firewall must allow zerotier traffic (UDP 9993)

### SSH requirements (for remote deployment)

**Constraint**: Remote NixOS deployment requires SSH + sudo access

**Prerequisites**:
- SSH key authentication configured
- User has sudo privileges
- SSH connection stable during deployment
- Nix installed on target host

**Risk mitigation**:
- Test deployment in VPS snapshot first
- Keep existing generation accessible
- Preserve SSH configuration during activation
- Use separate session for monitoring

## SC-010: Historical migration constraints (completed)

### Phased migration execution (completed November 2024)

**Historical constraint**: Migration proceeded host-by-host with stability validation

**Completed phases**:
0. Validation in test-clan environment
1. VPS foundation deployment - cinnabar, electrum, galena, scheelite
2-5. Darwin host migrations - stibnite, blackphos, rosegold, argentum
6. Architecture cleanup - nixos-unified deprecated

**Risk mitigation approach**:
- Each host stabilized 1-2 weeks before next migration
- Primary workstation (stibnite) migrated last in sequence
- Rollback procedures tested and validated per host
- Total migration duration: approximately 6 months

**Legacy reference only**: This section documents the completed migration constraints for historical context and future large-scale changes.

### Current architecture (post-migration)

**Architecture**: Dendritic flake-parts + clan is the active framework

**Deprecated**: nixos-unified removed from active use (November 2024)

**Machine fleet** (8 total):
- Darwin hosts (4): stibnite, blackphos, rosegold, argentum
- NixOS hosts (4): cinnabar (permanent VPS), electrum, galena, scheelite (ephemeral VPS)

**Module organization**:
- All modules follow dendritic pattern (every file is flake-parts module)
- Clan inventory manages multi-machine coordination
- No architectural coexistence - single unified system

## Constraint traceability

### To quality requirements

- SC-001, SC-003: Support QR-001 (Reproducibility)
- SC-002, SC-005: Support QR-002 (Type safety)
- SC-004, SC-008: Support QR-005 (Security)
- SC-007: Support QR-006 (Performance), QR-007 (Reliability)
- SC-009: Support QR-005 (Security - encrypted communication)
- SC-010: Support QR-007 (Reliability - risk management)

### To system goals

- SC-001, SC-003: Align with G-S01 (Reproducible configurations)
- SC-002, SC-005: Align with G-S02 (Type safety)
- SC-005: Align with G-S04 (Modular architecture)
- SC-006: Align with G-U02, G-U03 (Multi-host, secrets)
- SC-010: Align with G-S03 (Reduce technical debt)

## References

**Context layer**:
- [Constraints and rules](../context/constraints-and-rules/) - High-level constraints
- [Domain model](../context/domain-model/) - Technical architecture

**Requirements**:
- [Quality requirements](/development/requirements/quality-requirements/) - Quality attributes shaped by constraints
- [Deployment requirements](/development/requirements/deployment-requirements/) - Operational constraints

**Architecture**:
- ADRs - Architectural decisions within constraints
- [Handling broken packages](/guides/handling-broken-packages) - Working within build system constraints

**External**:
- Nix manual: https://nixos.org/manual/nix/stable/
- NixOS module system: https://nixos.org/manual/nixos/stable/index.html#sec-writing-modules
- Nix flakes RFC: https://github.com/NixOS/rfcs/pull/49
