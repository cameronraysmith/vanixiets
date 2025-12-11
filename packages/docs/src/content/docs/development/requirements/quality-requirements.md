---
title: Quality
sidebar:
  order: 6
---

This document defines non-functional requirements covering measurable quality attributes of the system.

## Overview

Quality requirements specify how well the system performs its functions rather than what functions it performs.
Each requirement includes measurement criteria, current state assessment, and target state objectives.

Quality requirements are extracted from [design principles](../../architecture/adrs/0014-design-principles/), [system goals](../context/goals-and-objectives/), and architectural constraints established in the Context layer.

## QR-001: Reproducibility

### Definition

The system must produce identical outputs given identical inputs, ensuring deterministic configuration builds and deployments.

### Rationale

Reproducibility is foundational to system reliability, enabling predictable outcomes, debugging capability, and confidence in configuration changes.
Aligns with G-S01: Reproducible system configurations.

### Measurement criteria

- **Lockfile integrity**: flake.lock freezes all input versions
- **Build determinism**: Same flake.lock produces same system derivation
- **Evaluation purity**: No impure operations during evaluation (no network, no ambient state)
- **Hash verification**: All fetched inputs verified with cryptographic hashes

### Current state

**Achieved**:
- flake.lock pins all input versions with NAR hash verification
- Nix evaluation is pure by default (flakes enforce purity)
- All external resources (patches, tarballs) include hash verification
- Multi-channel nixpkgs maintained with independent locks per channel input

**Limitations**:
- Some darwin system state (Homebrew installations) remains imperative
- Time-based evaluation (builtins.currentTime) avoided but not enforced

### Target state

**Goals**:
- Maintain current reproducibility standards
- Eliminate remaining imperative darwin state where feasible
- Document any intentional exceptions to purity
- Clan vars generation is reproducible (given same prompts, produces same secrets)

**Validation**:
- `nix flake check` succeeds (no evaluation errors)
- Rebuilding with same flake.lock produces identical system
- CI builds match local builds for same inputs

## QR-002: Type safety

### Definition

The system must validate configuration correctness through static type checking at evaluation time, catching errors before deployment.

### Rationale

Type safety prevents runtime configuration errors, enables refactoring confidence, and provides documentation through types.
Aligns with G-S02: Type safety via module system and ADR-0014 principle 3 (Type safety and functional patterns).

### Measurement criteria

- **Module system types**: All options defined with explicit types
- **Evaluation-time checking**: Invalid configurations rejected before build
- **No specialArgs**: Type-safe module imports via config.flake.modules.* (target)
- **Explicit dependencies**: No implicit coupling via specialArgs passthrough

### Current state

**Achieved**:
- Module system type checking operational
- Options defined with types (bool, str, int, attrs, etc.)
- Invalid option values rejected at evaluation time
- Dendritic pattern eliminates specialArgs in new modules
- Cross-module references via config.flake.modules.* namespace

**Limitations**:
- Legacy nixos-unified patterns still use specialArgs (being migrated)
- Some older modules accept untyped attrsets
- Submodule coverage incomplete in legacy code

### Target state

**Goals**:
- Eliminate specialArgs entirely (dendritic pattern enforces this)
- Every file is a module: type-checked via flake-parts
- Cross-module references via config.flake.modules.* (type-safe)
- Increased use of submodules for structured configuration

**Validation**:
- No specialArgs in module signatures
- All imports via config.flake.modules.* namespace
- Type errors caught during nix flake check
- IDE tooling (nil, nixd) provides type-aware completion

## QR-003: Maintainability

### Definition

The system must be understandable, modifiable, and sustainable over time with reasonable effort investment.

### Rationale

Maintainability directly impacts long-term viability and aligns with G-S03: Reduce technical debt and maintenance burden.

### Measurement criteria

- **Cognitive load**: Clear patterns, consistent structure, comprehensive documentation
- **Time to change**: Reasonable effort for common modifications
- **Onboarding**: New contributors can understand architecture
- **Technical debt**: Intentional architecture, not accumulated workarounds
- **Documentation coverage**: All major components documented

### Current state

**Achieved**:
- Multi-channel stable fallbacks enable surgical fixes (preserves maintainability)
- ADRs document architectural decisions with rationale
- Clear separation: overlays vs modules vs hosts
- Atomic commits per file reduce review complexity

**Limitations**:
- Two architectures in parallel during migration (being resolved)
- Legacy nixos-unified patterns documented but marked for migration
- Legacy modules being incrementally refactored to dendritic pattern

### Target state

**Goals**:
- Single architecture (dendritic + clan) after migration
- Every pattern documented with examples
- AMDiRE documentation complete (Context, Requirements, Traceability)
- Clear migration path preserved in documentation even after completion
- Regular cleanup passes (ADR-0014 principle 4: Bias toward removal)

**Validation**:
- Documentation review time: <30 minutes to understand component
- Common changes: <1 hour from understanding to deployed
- Technical debt inventory maintained in docs/notes/
- No unexplained workarounds or magic patterns

## QR-004: Modularity

### Definition

The system must enable feature composition and reuse across platforms and hosts with clear boundaries and minimal coupling.

### Rationale

Modularity supports scalability, testing, and flexibility.
Aligns with G-S04: Modular architecture for scalability and ADR-0014 principle 1 (Framework independence).

### Measurement criteria

- **Composability**: Features combine without conflicts
- **Cross-platform reuse**: Single module definition for multiple platforms
- **Clear boundaries**: Modules expose typed interfaces
- **Minimal coupling**: Modules depend on abstractions, not implementations
- **Independent testing**: Modules testable in isolation

### Current state

**Achieved**:
- Module system provides composition mechanism
- Platform-specific modules organized separately
- Cross-platform sharing via home-manager
- Dendritic pattern enables single-file cross-cutting concerns
- Explicit module boundaries via flake.modules.* namespace
- Clan service instances enable multi-host feature coordination

**Limitations**:
- Legacy modules still use specialArgs coupling (being migrated)
- Some host-specific overrides remain scattered in nixos-unified code

### Target state

**Goals**:
- Eliminate all specialArgs (complete migration to dendritic pattern)
- Every module composed via typed flake.modules.* imports
- Features composable without inheritance patterns
- Clan services fully integrated across 8-machine fleet
- Cross-cutting concerns maintainable in single files

**Validation**:
- Feature module spans darwin + nixos + home-manager in single file
- Adding new host: <10 lines of configuration
- Zero specialArgs in any module signature
- Module dependency graph remains acyclic and shallow

## QR-005: Security

### Definition

The system must protect secrets, follow security best practices, and provide secure communication channels.

### Rationale

Security is non-negotiable for production infrastructure.
Aligns with G-S05: Secrets management via clan vars and G-S06: Overlay networking.

### Measurement criteria

- **Secrets encryption**: All secrets encrypted at rest
- **Key management**: Age keys secured, rotatable
- **Least privilege**: Services run with minimal permissions
- **Secure communication**: Encrypted channels for inter-host traffic
- **No secrets in store**: Secrets never committed to nix store
- **Audit trail**: Secret changes tracked in version control (encrypted)

### Current state

**Achieved**:
- sops-nix encrypts secrets with age
- Secrets deployed to /run/secrets/ with correct permissions
- Secrets not in nix store (sops integration)
- Git tracks encrypted secrets (version control maintained)

**Limitations**:
- Manual secret generation (error-prone)
- Secret rotation requires manual intervention
- No automatic key distribution
- No secure inter-host communication (yet)

### Target state

**Goals**:
- Declarative secret generation via clan vars
- Automatic encryption with host age keys
- Shared secrets for service instances (controlled via share = true)
- Zerotier provides encrypted overlay network
- Secret rotation via regeneration and redeployment
- Age keys managed per-host, backed up securely

**Validation**:
- `rg "password|token|key" --type nix` finds only references, not values
- All secrets in sops/ directory encrypted
- Zerotier network operational with encryption
- Secret regeneration tested and documented
- Age keys not committed to repository

## QR-006: Performance

### Definition

The system must provide acceptable build times, activation speeds, and development shell startup without unnecessary overhead.

### Rationale

Performance impacts developer productivity and system responsiveness.
Aligns with G-S07: Efficient operations.

### Measurement criteria

- **Build times**: Incremental builds complete in reasonable time
- **Activation speed**: System activation completes without excessive delays
- **Shell startup**: Development shell loads within seconds
- **Evaluation time**: Configuration evaluation completes quickly
- **Cache effectiveness**: Binary cache provides high hit rate

### Current state

**Achieved**:
- Cachix provides binary caching (reduces build times)
- Incremental builds only rebuild changed dependencies
- Multi-channel overlays add minimal evaluation overhead
- direnv caches development shell evaluation

**Limitations**:
- Initial builds without cache are slow (inherent to Nix)
- Some large packages (LLVM, GHC) require significant time
- Evaluation time increases with module count

### Target state

**Goals**:
- Maintain or improve current performance
- Cache effectiveness >80% (CI and local development)
- Evaluation time <10 seconds for typical configuration
- Shell startup <5 seconds (with direnv caching)
- darwin-rebuild switch <2 minutes (with cache hits)

**Validation**:
- Measure build times before/after changes
- Profile evaluation time: nix eval --profile .#darwinConfigurations.<hostname>.config.system.build.toplevel
- Monitor cache hit rates in CI
- Development shell startup time measured

## QR-007: Reliability

### Definition

The system must support safe configuration changes with rollback capability, validation before activation, and error recovery mechanisms.

### Rationale

Reliability ensures system availability and reduces downtime risk.
Aligns with G-S07: Efficient operations and migration risk management.

### Measurement criteria

- **Rollback capability**: Previous generations preserved and accessible
- **Validation**: Dry-run capability before activation
- **Error recovery**: Clear procedures for failure scenarios
- **System stability**: No unexpected reboots or service failures
- **Generation management**: Automatic cleanup of old generations

### Current state

**Achieved**:
- darwin-rebuild/nixos-rebuild preserve generations
- Rollback via --rollback flag or manual activation
- Dry-run validation available
- System activation atomic (all-or-nothing)

**Limitations**:
- No automated validation before activation
- Rollback procedure not well-documented
- Generation cleanup manual
- No health checks post-activation

### Target state

**Goals**:
- Automated dry-run in CI before merge
- Rollback procedure documented and tested per host
- Health check validation post-activation
- Automatic generation cleanup (keep last N)
- Per-host stability monitoring during migration (1-2 week validation)

**Validation**:
- Rollback tested on all hosts
- CI blocks merges on build failure
- Post-activation validation scripts
- Generation management automated via nix.gc configuration

## QR-008: Template duality

### Definition

The system must function both as a working deployment and as a forkable template for others.

### Rationale

Supports ADR-0014 principle 2 (Template duality): forces us to use what we build and provides value to others.

### Measurement criteria

- **Generic naming**: Package and component names purpose-based, not host-specific
- **Separation of concerns**: Template content vs deployment-specific content
- **Documentation completeness**: Template usage and customization documented
- **Example clarity**: Working examples demonstrate patterns
- **Customization points**: Clear hooks for template users

### Current state

**Achieved**:
- Package naming follows purpose (infra, docs, not host-specific)
- AMDiRE documentation being completed (Context, Requirements)
- Repository structured for template use
- Notes/ directory for deployment-specific content (excluded from build)

**Limitations**:
- Migration in progress (template aspect not polished yet)
- Some host-specific assumptions in current configuration
- Template documentation incomplete

### Target state

**Goals**:
- Post-migration: clean, forkable architecture
- Complete template documentation (how to fork, customize)
- Example configurations for common scenarios
- Deployment-specific details in notes/ or environment variables
- Repository useful to others without exposing secrets

**Validation**:
- Test fork scenario (fresh clone, customize, deploy)
- Documentation review by external party
- No secrets in repository (all generated or external)
- Generic patterns work for multiple deployment scenarios

## Quality attribute relationships

### Reinforcing relationships

- **Reproducibility ↔ Type safety**: Both reduce runtime errors
- **Type safety ↔ Maintainability**: Types document intent, enable refactoring
- **Modularity ↔ Maintainability**: Clear boundaries reduce cognitive load
- **Security ↔ Reliability**: Secure systems are more stable
- **Performance ↔ Reliability**: Fast feedback loops enable safe iteration

### Tension relationships

- **Type safety ⚡ Performance**: More checking adds evaluation overhead (minimal in practice)
- **Security ⚡ Maintainability**: Encryption can obscure configuration (managed via declarative generators)
- **Modularity ⚡ Performance**: More modules increase evaluation time (acceptable trade-off)
- **Template duality ⚡ Specificity**: Generic patterns may not optimize for specific use case (balance via configuration)

## Quality assurance strategies

### Static validation

- Type checking via module system (QR-002)
- Linting via statix, deadnix, nixfmt (QR-003)
- Evaluation validation via nix flake check (QR-001, QR-002)
- Documentation review (QR-003, QR-008)

### Dynamic validation

- Build testing in CI (QR-001, QR-006)
- Dry-run before activation (QR-007)
- Post-activation health checks (QR-007)
- Performance profiling (QR-006)

### Continuous improvement

- Regular documentation reviews (QR-003)
- Technical debt tracking in notes/ (QR-003)
- Cache hit rate monitoring (QR-006)
- Security audit of secrets management (QR-005)
- Cleanup passes per ADR-0014 principle 4 (QR-003, QR-008)

## Measurement approach

Fleet configuration: 4 darwin machines (stibnite, blackphos, rosegold, argentum) and 4 nixos machines (cinnabar, electrum, galena, scheelite).

### Reproducibility metrics

```bash
# Verify identical builds across fleet
# Darwin: stibnite, blackphos, rosegold, argentum
# NixOS: cinnabar, electrum, galena, scheelite
nix build .#darwinConfigurations.<hostname>.system
hash1=$(nix path-info .#darwinConfigurations.<hostname>.system)
nix flake update --commit-lock-file
nix build .#darwinConfigurations.<hostname>.system
hash2=$(nix path-info .#darwinConfigurations.<hostname>.system)
# Should match if flake.lock unchanged

# Check evaluation purity
nix flake check --no-allow-import-from-derivation
```

### Type safety metrics

```bash
# Count modules without specialArgs
rg "^[^#]*\{ config, pkgs, lib.*\}" modules/ -c
# Target: 100% of modules

# Verify no specialArgs usage
rg "specialArgs" modules/ flake.nix
# Target: 0 results after migration
```

### Maintainability metrics

```bash
# Documentation coverage
fd -e md docs/development | wc -l
# Target: All major components documented

# Technical debt inventory
fd -e md docs/notes/ | wc -l
# Track over time, aim to decrease
```

### Performance metrics

```bash
# Evaluation time
time nix eval .#darwinConfigurations.<hostname>.config.system.build.toplevel --no-eval-cache
# Target: <10 seconds

# Build time (without cache)
time nix build .#darwinConfigurations.<hostname>.system --rebuild
# Track trend over time

# Shell startup time
time nix develop --command echo "loaded"
# Target: <5 seconds with direnv cache
```

### Security metrics

```bash
# Verify no secrets in nix store
nix path-info --all | xargs nix-store --query --tree | rg "password|token|secret"
# Target: 0 results (only paths, not values)

# Check secrets encryption
fd -e yaml sops/ -x file {} | rg "ASCII text"
# Target: 0 results (all binary/encrypted)
```

## References

**Context layer**:
- [Goals and objectives](../context/goals-and-objectives/) - System goals G-S01 through G-S08
- [Constraints and rules](../context/constraints-and-rules/) - Architectural restrictions

**Requirements**:
- [Usage model](/development/requirements/usage-model/) - Use cases supporting quality attributes
- [Functional hierarchy](/development/requirements/functional-hierarchy/) - Functions organized by quality

**Architecture**:
- [ADR-0014: Design principles](../../architecture/adrs/0014-design-principles/) - Framework independence, type safety, template duality, bias toward removal
- [Handling broken packages](/guides/handling-broken-packages) - Multi-channel stable fallback implementation
- [CI philosophy](../../traceability/ci-philosophy/) - Continuous integration approach
