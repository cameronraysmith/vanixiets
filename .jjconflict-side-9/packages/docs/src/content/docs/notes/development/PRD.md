---
title: "infra - Product Requirements Document"
---

**Author:** Dev
**Date:** 2025-11-02
**Version:** 1.0

---

## Executive Summary

The nix-config infrastructure migration to dendritic flake-parts pattern with clan-core integration addresses critical architectural limitations in the current nixos-unified implementation across 1 VPS and 4 darwin workstations.
The migration delivers improved type safety through consistent module system usage, clearer organizational patterns via the dendritic `flake.modules.*` namespace, and robust multi-machine coordination capabilities via clan-core's inventory system, vars management, and service instances with roles.

The critical architectural challenge is that no proven examples exist combining dendritic flake-parts with clan patterns.
This necessitates a validation-first approach: Phase 0 validates the architectural combination in a minimal test-clan repository before any infrastructure commitment, de-risking the entire migration by proving feasibility in isolation.
Following validation, Phase 1 deploys the cinnabar VPS as always-on foundation infrastructure with zerotier controller, validating the complete stack (dendritic + clan + terraform + infrastructure) on clan's native platform (NixOS) before touching darwin hosts.
Phases 2-4 progressively migrate darwin workstations (blackphos → rosegold → argentum) with 1-2 week stability gates between each host.
Phase 5 migrates the primary workstation (stibnite) only after 4-6 weeks of proven stability across all other hosts.
Phase 6 removes legacy nixos-unified infrastructure.

### What Makes This Special

**Validation-first de-risking**: Phase 0 validates an untested architectural combination (dendritic + clan) in a disposable test environment before deploying production infrastructure, eliminating the risk of discovering fundamental incompatibilities after VPS commitment.

**Type safety through progressive optimization**: Leverages flake-parts module system to bring compile-time type checking to infrastructure configuration, addressing Nix's lack of native type system while maintaining pragmatism—clan functionality is non-negotiable, dendritic optimization applied where feasible without compromise.

**VPS-first foundation**: Deploys always-on cloud infrastructure (cinnabar) before darwin hosts, providing stable zerotier controller independent of workstation power state and validating patterns on NixOS (clan's native platform) before tackling darwin-specific integration challenges.

**Progressive validation gates with explicit go/no-go frameworks**: Each phase has measurable success criteria and rollback procedures, with 1-2 week stability windows and host-by-host validation preventing cascading failures.

**Brownfield pragmatism**: Accepts hybrid approaches where pure patterns conflict with clan functionality, documented and justified rather than hidden, prioritizing operational success over architectural orthodoxy.

---

## Project Classification

**Technical Type:** Infrastructure / DevOps / Configuration Management
**Domain:** System Administration / Multi-Machine Orchestration
**Complexity:** High (Level 3 brownfield migration with unproven pattern combination)

This is a Level 3 brownfield infrastructure migration project targeting a 5-machine heterogeneous environment (1 x86_64 NixOS VPS + 4 aarch64 darwin workstations).

The project combines three proven technologies in an unproven configuration:

- Dendritic flake-parts pattern (proven in production: drupol-dendritic-infra)
- Clan-core multi-machine coordination (proven in production: clan-infra)
- Integration of both patterns (unproven, requires Phase 0 validation)

**Brownfield characteristics:**

- Existing nix-config infrastructure actively manages 4 darwin workstations
- Migration must preserve all functionality (zero-regression requirement)
- Cannot disrupt daily productivity on primary workstation (stibnite)
- Must support rollback at any phase if issues discovered
- Progressive per-host migration with stability validation gates

**Complexity drivers:**

- No documented examples combining dendritic + clan patterns
- Darwin + clan integration has limited precedent (some examples exist but not with dendritic)
- VPS deployment involves 8+ simultaneous layers (dendritic, clan, terraform, hetzner, disko, LUKS, zerotier, NixOS)
- Multi-machine coordination across heterogeneous platforms (NixOS + darwin)
- Type safety goals require deep understanding of flake-parts module system
- Secrets migration from sops-nix to clan vars system

### Domain Context

**System administration domain with multi-machine orchestration complexity:**

**Infrastructure management**: Declarative configuration management via Nix for system-level (NixOS/nix-darwin), user-level (home-manager), and multi-machine coordination (clan-core inventory system)

**Secrets management**: Transition from manual sops-nix encryption to declarative clan vars generators with automatic deployment and generation orchestration

**Network topology**: Establish zerotier mesh VPN with always-on VPS controller (cinnabar) and darwin peer nodes for secure inter-machine communication and service coordination

**Cloud provisioning**: Declarative infrastructure-as-code via terraform/terranix for Hetzner Cloud VPS deployment with disko declarative disk partitioning and LUKS encryption

**Type system engineering**: Apply module system type safety to infrastructure configuration, leveraging flake-parts option types to compensate for Nix language's lack of native compile-time type checking

**Migration strategy**: Validation-first approach with progressive rollout, explicit go/no-go decision gates, stability validation windows, and per-host rollback procedures to manage risk of unproven architectural combination

---

## Success Criteria

**Migration success is measured by technical correctness, operational stability, and productivity preservation across the 6-phase progressive rollout:**

### Phase 0 success (test-clan validation) - GO/NO-GO decision gate

- test-clan flake evaluates and builds successfully with dendritic + clan integration
- Dendritic flake-parts pattern proven feasible with clan functionality (no fundamental conflicts discovered)
- Integration patterns documented with confidence in `INTEGRATION-FINDINGS.md` and `PATTERNS.md`
- Go/no-go framework evaluation shows "GO" or "CONDITIONAL GO" with acceptable compromises
- If NO-GO: fallback to vanilla clan + flake-parts pattern (proven in clan-infra) without proceeding to infrastructure deployment

### Phase 1 success (cinnabar VPS) - Proceed to darwin migration if

- Hetzner Cloud VPS deployed and operational with validated patterns from Phase 0
- Complete infrastructure stack proven (dendritic + clan + terraform + infrastructure) on NixOS
- Zerotier controller functional and reachable from local development machine
- SSH access working with certificate-based authentication via zerotier network
- Clan vars deployed correctly to `/run/secrets/` with proper permissions
- Disko declarative partitioning with LUKS encryption operational
- Stable for 1-2 weeks minimum with no critical issues

### Phase 2-4 success (darwin hosts: blackphos → rosegold → argentum) - Proceed to next host if

- Host configuration builds and deploys successfully using established patterns from previous phase
- All existing functionality preserved (zero-regression validation: package lists, system services, development workflows identical)
- Clan vars generated and deployed with correct file permissions
- Zerotier peer connects to cinnabar controller and mesh network communication functional
- SSH via zerotier network works (certificate-based authentication)
- Multi-machine coordination validated (services deployed across hosts, vars shared where configured)
- Stable for 1-2 weeks minimum per host before proceeding to next

### Phase 5 success (stibnite primary workstation) - Complete migration if

- All previous phases (2-4) stable for cumulative 4-6 weeks minimum
- stibnite operational with all daily workflows functional (development, communication, system services)
- Productivity maintained or improved compared to pre-migration baseline
- 5-machine zerotier network complete and stable (cinnabar + 4 darwin hosts with full mesh connectivity)
- No critical regressions in functionality or performance
- Stable for 1-2 weeks minimum before cleanup phase

### Overall migration success (ready for Phase 6 cleanup)

- All 5 machines migrated to dendritic + clan with consistent patterns
- No critical regressions in functionality across any host
- Multi-machine coordination operational (clan inventory, vars deployment, service instances)
- Type safety improvements measurable (fewer evaluation errors, clearer error messages from module system type checking)
- Maintainability improved (clearer module organization via dendritic namespace, explicit interfaces via `config.flake.*`)
- Zerotier mesh network stable across all hosts with reliable inter-machine communication
- Ready to remove nixos-unified legacy infrastructure

### Business Metrics

**Development velocity**: Configuration changes execute faster due to clearer module boundaries and explicit interfaces (baseline: current time to add/modify features, target: 20-30% reduction in debugging time)

**Error reduction**: Type checking via module system catches configuration errors at evaluation time rather than deployment (measure: count of runtime configuration errors, target: 50% reduction)

**Maintainability score**: Subjective assessment of ease of understanding and modifying configurations (baseline: current cognitive load, target: "significantly easier to understand module dependencies")

**Migration timeline**: Conservative estimate 13-15 weeks for complete migration with stability gates, aggressive 4-6 weeks if all phases proceed smoothly without issues

**Operational cost**: Hetzner Cloud VPS adds ~€24/month (~$25 USD) ongoing operational expense, accepted as cost of always-on infrastructure benefits and migration de-risking

**Rollback frequency**: Number of times rollback required during migration (target: 0, acceptable: 1-2 for non-primary hosts, unacceptable: rollback of stibnite primary workstation)

---

## Product Scope

### MVP - Minimum Viable Product

The MVP encompasses the complete 6-phase migration delivering a fully operational dendritic + clan infrastructure across all 5 machines with type safety improvements, multi-machine coordination, and validated architectural patterns.

**Phase 0 - Validation Environment** (test-clan repository, Week 0):

- Minimal flake structure with clan-core + import-tree + flake-parts integration in disposable test repository
- Test NixOS VM configuration using dendritic flake-parts pattern (or validated hybrid if pure dendritic conflicts with clan)
- Clan inventory with single test machine demonstrating inventory evaluation
- Essential clan services (emergency-access, sshd, zerotier) configured via service instances
- Vars generation and deployment validation (test generators, verify deployment to `/run/secrets/`)
- Documentation of integration findings in `INTEGRATION-FINDINGS.md` (what works, what requires compromise)
- Pattern extraction in `PATTERNS.md` (reusable patterns for Phase 1 cinnabar deployment)
- Go/no-go decision framework evaluation (GO/CONDITIONAL GO/NO-GO with explicit criteria)

**Phase 1 - VPS Infrastructure** (cinnabar, Weeks 1-3):

- Terraform/terranix provisioning for Hetzner Cloud CX53 VPS (8 vCPU, 32GB RAM, 240GB NVMe SSD, ~€24/month)
- NixOS configuration using validated patterns from Phase 0 (dendritic + clan or hybrid as determined)
- Disko declarative partitioning with LUKS encryption (automatic disk setup during installation)
- Zerotier controller role (provides stable always-on controller independent of darwin host power state)
- SSH daemon with certificate-based authentication via clan sshd service
- Emergency access configuration via clan emergency-access service (root access recovery)
- Clan vars deployment for VPS secrets (SSH host keys, service credentials)
- Complete infrastructure stack validation (dendritic + clan + terraform + hetzner + disko + LUKS + zerotier + NixOS)

**Phase 2 - First Darwin Host** (blackphos, Weeks 4-5):

- Convert darwin modules to dendritic flake-parts pattern (or validated hybrid from Phase 0) via `flake.modules.darwin.*` namespace
- Clan inventory integration for darwin machine with appropriate tags ("darwin", "workstation")
- Zerotier peer role connecting to cinnabar controller (client configuration for always-on VPN)
- Clan vars deployment for darwin secrets (SSH host keys, user-specific secrets)
- Preserve all existing functionality (zero-regression validation: homebrew, system preferences, development tools, shell configuration)
- Establish darwin patterns for reuse in subsequent hosts (document in migration notes)
- 1-2 week stability validation before proceeding to Phase 3

**Phase 3-4 - Multi-Darwin Validation** (rosegold Weeks 6-7, argentum Weeks 8-9):

- Replicate blackphos patterns for additional darwin hosts (validate pattern reusability with minimal customization)
- Test multi-machine coordination across 3-4 hosts (clan inventory service deployment, vars sharing)
- Zerotier mesh network across all machines (verify full mesh connectivity: all hosts can reach all other hosts)
- Progressive stability validation (1-2 weeks each host, cumulative 4-6 weeks before stibnite)
- Pattern refinement based on multi-host experience

**Phase 5 - Primary Workstation** (stibnite, Weeks 10-12):

- Apply proven patterns to primary daily workstation (only after 4-6 weeks total stability across blackphos, rosegold, argentum)
- Migrate only after explicit pre-migration readiness checklist completion (all previous hosts stable, no outstanding issues, rollback plan documented)
- Preserve all daily workflows and productivity (highest priority: development environment, communication tools, system services)
- Complete 5-machine coordinated infrastructure (cinnabar VPS + 4 darwin workstations with full zerotier mesh)
- Extended validation (1-2 weeks) before declaring migration complete

### Core Infrastructure Components (across all phases)

**Dendritic flake-parts module structure**: Every Nix file is a flake-parts module contributing to `flake.modules.{nixos,darwin,homeManager}.*` namespace with clear interfaces via `config.flake.*` access

**Clan inventory system**: Centralized multi-machine coordination defining all 5 machines with tags (nixos, darwin, workstation, vps, cloud, primary) and machineClass (nixos, darwin) for service deployment targeting

**Clan service instances**: Instance-based service deployment with roles (emergency-access.default for all workstations, users-crs58.default for workstations, users-root.default for cinnabar, zerotier-local with controller role on cinnabar and peer role on all machines, sshd-clan with server role on all and client role on all)

**Vars generators for secrets management**: Declarative secret generation replacing manual sops-nix management (SSH host keys, service passwords, API keys, with automatic deployment to `/run/secrets/` and proper file permissions)

**import-tree auto-discovery**: Automatic module loading eliminating manual imports via recursive directory scanning of `modules/` with flake-parts integration

**Justfile-based CI/CD workflow**: Universal command interface (`just check`, `just build`, `just test`) with local-CI parity (CI executes `nix develop -c just <command>` matching local development)

### Out of Scope for MVP

**Not included in initial migration:**

- UI/frontend work (infrastructure project, no graphical interfaces beyond terminal-based tools)
- Additional VPS infrastructure beyond cinnabar (single VPS sufficient for validation and zerotier controller)
- Migration of all secrets to clan vars (hybrid sops-nix + clan vars acceptable initially for external credentials)
- Complex distributed services beyond basic zerotier networking (no service mesh, no distributed databases, focus on foundation)
- Automated rollback mechanisms (manual rollback procedures documented instead, acceptable for 5-machine scale)
- CI mirror hosts (stibnite-nixos, blackphos-nixos, orb-nixos) - defer to post-migration (current CI sufficient for validation)
- Full terraform state management automation (manual terraform operations acceptable for single VPS)

**Deferred to future phases:**

- Complete elimination of sops-nix (hybrid approach acceptable long-term for external credentials that cannot be generated)
- Advanced clan service instances beyond essentials (borgbackup, monitoring, additional services as future enhancements)
- Automated testing infrastructure for all configurations (manual validation sufficient for MVP, CI expansion post-migration)
- Documentation website or formal user guides (working notes and inline documentation sufficient for personal infrastructure)
- Performance optimization and benchmarking (baseline performance acceptable, optimize only if regressions discovered)
- Cost optimization for VPS infrastructure (CX53 specification acceptable, downgrade only if proven excessive)

### MVP Success Criteria

**Architectural validation (Phase 0)**:

- Dendritic + clan integration proven feasible (GO or CONDITIONAL GO decision, not NO-GO)
- Integration patterns documented with confidence for production deployment
- No fundamental conflicts requiring architectural redesign

**Infrastructure deployment (Phase 1)**:

- cinnabar VPS operational with complete stack validation
- Zerotier controller providing stable always-on VPN mesh foundation
- Patterns proven on NixOS (clan's native platform) before darwin

**Darwin migration (Phases 2-4)**:

- All 3 secondary darwin hosts (blackphos, rosegold, argentum) migrated successfully
- Patterns proven reusable with minimal per-host customization
- Multi-machine coordination operational across heterogeneous platforms

**Primary workstation (Phase 5)**:

- stibnite operational maintaining all daily workflows and productivity
- 5-machine infrastructure complete with proven stability

**Overall success**:

- Zero critical regressions across any host
- Type safety improvements measurable (clearer errors, caught at evaluation time)
- Maintainability improved (clearer organization, explicit interfaces)
- Multi-machine coordination operational
- Ready for legacy cleanup (Phase 6)

---

## Innovation & Novel Patterns

### Architectural Innovation: Dendritic + Clan Integration

**Novel combination**: No documented production examples exist combining the dendritic flake-parts pattern with clan-core multi-machine coordination.
Proven separately (dendritic in drupol-dendritic-infra, clan in clan-infra), but never integrated.

**Innovation hypothesis**: Dendritic's maximize-type-safety approach via consistent `flake.modules.*` namespace usage can be applied to clan's flake-parts integration to improve type safety of multi-machine infrastructure configurations beyond vanilla clan + flake-parts pattern.

**Validation challenge**: Unknown whether dendritic's anti-specialArgs principle conflicts with clan's flakeModules integration pattern (clan-infra uses minimal `specialArgs = { inherit self; }`).

### Validation Approach

**Phase 0 as architectural proof-of-concept**: Create minimal test-clan repository to answer the critical unknown: "How much dendritic optimization is compatible with clan functionality?"

**Known foundation**: Clan works with flake-parts (proven in clan-core, clan-infra), dendritic works with flake-parts (proven in multiple production examples).
**Unknown optimization**: Integration points, acceptable compromises, optimal balance between dendritic purity and clan functionality.

**Three possible outcomes**:

1. **Dendritic-optimized clan** (best case): Full dendritic pattern applicable to clan configurations, maximum type safety achieved
2. **Hybrid approach** (pragmatic): Some dendritic patterns applicable, some compromises necessary (e.g., minimal specialArgs acceptable for framework values), documented and justified deviations
3. **Vanilla clan pattern** (proven alternative): Dendritic optimization provides insufficient benefit or conflicts with clan, fallback to clan-infra pattern (manual imports, proven production pattern)

**Success criteria for innovation**: Any outcome that preserves clan functionality while improving type safety or organizational clarity is a success.
Pure dendritic adoption is not required—pragmatic hybrid approach is equally valid if it delivers maintainability benefits.

### Fallback Strategy

**If fundamental incompatibility discovered in Phase 0**:

- Document specific architectural conflicts in `INTEGRATION-FINDINGS.md`
- Pivot to vanilla clan + flake-parts pattern (proven in clan-infra production infrastructure)
- Proceed to Phase 1 (cinnabar deployment) using proven pattern without dendritic optimization
- Re-evaluate dendritic adoption post-migration as patterns mature

**No-GO decision is acceptable**: Phase 0 exists precisely to discover incompatibilities before infrastructure investment.
Failing fast in test environment is a success, not a failure.

---

## Infrastructure / Configuration Management Specific Requirements

### Declarative Infrastructure

**Infrastructure-as-code via Nix ecosystem**:

- All infrastructure configuration version-controlled in git (nix-config repository on `clan` branch)
- Declarative VPS provisioning via terraform/terranix (Hetzner Cloud API integration)
- Declarative disk partitioning via disko (LUKS encryption, filesystem layouts)
- Declarative system configuration via NixOS (cinnabar) and nix-darwin (workstations)
- Declarative user environment via home-manager (shell, development tools, applications)
- Declarative multi-machine coordination via clan inventory (machines, service instances, roles)
- Declarative secrets management via clan vars generators (automatic generation, encrypted storage, deployment)

**Evaluation and build separation**:

- Configuration evaluation must succeed before deployment (type checking via module system catches errors early)
- Build outputs are deterministic and reproducible (Nix content-addressed store)
- Deployment is atomic (activate new generation or rollback to previous)

**Rollback capability**:

- NixOS/nix-darwin generation rollback (boot menu or `darwin-rebuild switch --rollback`)
- Per-host rollback to nixos-unified configurations (preserved during migration, deleted in Phase 6)
- Terraform state rollback via `terraform destroy` (VPS disposable, redeploy from configuration)
- Git-based configuration rollback (revert commits, rebuild from earlier state)

### Module Organization

**Dendritic flake-parts pattern** (or validated hybrid from Phase 0):

**Flat feature categories** (not nested by platform):

```
modules/
├── base/              # Foundation modules (nix settings, system state)
├── nixos/             # NixOS-specific modules
├── darwin/            # Darwin-specific modules
├── shell/             # Shell tools (fish, starship, direnv)
├── dev/               # Development tools (git, jj, editors)
├── hosts/             # Machine-specific configurations
│   ├── cinnabar/
│   ├── blackphos/
│   ├── rosegold/
│   ├── argentum/
│   └── stibnite/
├── flake-parts/       # Flake-level configuration
│   ├── nixpkgs.nix
│   ├── darwin-machines.nix
│   ├── nixos-machines.nix
│   ├── terranix.nix
│   └── clan.nix
├── terranix/          # Terraform modules
└── users/             # User configurations
```

**Module namespace**: Every module contributes to `flake.modules.{nixos,darwin,homeManager}.*` namespace
**Host composition**: Hosts import modules via `imports = with config.flake.modules; [ darwin.base darwin.system homeManager.shell ];`
**Metadata sharing**: User/system metadata via `config.flake.meta.*` (email, SSH keys, etc.)
**Cross-cutting concerns**: Single module can target multiple systems (e.g., `flake.modules.darwin.shell` + `flake.modules.homeManager.shell`)

### Multi-Machine Coordination

**Clan inventory system**:

**Machine definitions**:

```nix
inventory.machines = {
  cinnabar = {
    tags = [ "nixos" "vps" "cloud" ];
    machineClass = "nixos";
  };
  blackphos = {
    tags = [ "darwin" "workstation" ];
    machineClass = "darwin";
  };
  # ... other hosts
};
```

**Service instances with roles**:

```nix
inventory.instances = {
  zerotier-local = {
    module = { name = "zerotier"; input = "clan-core"; };
    roles.controller.machines.cinnabar = {};
    roles.peer.tags."all" = {};  # All machines are peers
  };
  sshd-clan = {
    module = { name = "sshd"; input = "clan-core"; };
    roles.server.tags."all" = {};
    roles.client.tags."all" = {};
  };
};
```

**Configuration hierarchy**: instance-wide settings → role-wide settings → machine-specific settings
**Tag-based targeting**: Assign services to multiple machines via tags (e.g., `tags."workstation"` targets all darwin hosts)

### Secrets Management

**Clan vars system** (replaces manual sops-nix):

**Generators**: Declarative functions producing secrets (SSH keys, passwords, API keys)
**Storage**: Encrypted per-machine in `sops/machines/<hostname>/secrets/` via age encryption
**Deployment**: Automatic deployment to `/run/secrets/` with proper permissions
**Sharing**: `share = true` for secrets used across multiple machines (e.g., user SSH keys)
**DAG composition**: Dependencies between generators via `dependencies` attribute

**Hybrid approach acceptable**: Keep sops-nix for external credentials (API tokens from providers), use clan vars for generated secrets (SSH host keys, passwords)

**Example generator**:

```nix
clan.core.vars.generators.sshd = {
  script = ''
    ssh-keygen -t ed25519 -f $out/id_ed25519 -N ""
  '';
  files = {
    id_ed25519 = { secret = true; };      # Private key: /run/secrets/sshd.id_ed25519
    "id_ed25519.pub" = { secret = false; }; # Public key: accessible in nix store
  };
};
```

### Network Topology

**Zerotier mesh VPN**:

- **Controller**: cinnabar VPS (always-on, independent of darwin host power state)
- **Peers**: All machines (cinnabar + 4 darwin hosts)
- **Network ID**: Shared across all machines via clan zerotier service configuration
- **Certificate-based SSH**: SSH daemon uses certificates distributed via clan sshd service
- **Full mesh connectivity**: Any machine can reach any other machine via zerotier IP

**Topology rationale**:

- Always-on controller ensures network availability independent of workstation power state
- VPS provides stable public entry point for remote access
- Mesh topology enables direct machine-to-machine communication without routing through controller

### Type Safety

**Module system type checking**:

- All configuration values declared as options with explicit types (`types.bool`, `types.int`, `types.str`, `types.listOf`, `types.attrsOf`)
- Type checking at evaluation time catches errors before deployment
- Clear error messages reference specific options and expected types

**Dendritic optimization** (if feasible per Phase 0):

- Minimize specialArgs pass-through (only framework values: `inputs`, `self`)
- Prefer `config.flake.*` for application/user-defined values (type-checked access)
- Explicit interfaces between modules via option declarations

**Compromise acceptable**: If clan requires extensive specialArgs for flakeModules integration, document rationale and accept deviation from pure dendritic pattern.
Clan functionality is non-negotiable, dendritic optimization applied where feasible.

### CI/CD Integration

**Justfile as universal command interface**:

```justfile
# Evaluation and syntax
check:
  nix flake check

# System configuration builds
verify:
  nix build .#darwinConfigurations.blackphos.system

# Code quality
lint:
  statix check .

# Activation dry-run
activate-darwin host:
  darwin-rebuild switch --flake .#{{host}} --dry-run
```

**Local-CI parity**: CI workflows execute `nix develop -c just <command>` matching local development, ensuring reproducibility and enabling local CI failure reproduction.

---

## Functional Requirements

### FR-1: Architectural Integration (Phase 0 validation)

**FR-1.1**: test-clan repository shall integrate clan-core flakeModules with dendritic flake-parts pattern (or hybrid approach if conflicts discovered)

- Flake shall use `import-tree ./modules` for automatic module discovery
- Clan inventory shall evaluate successfully with test machine definition
- nixosConfiguration shall build for test-vm using dendritic module namespace

**FR-1.2**: Integration findings shall be documented in `INTEGRATION-FINDINGS.md` with:

- List of integration points between dendritic and clan
- Identified conflicts or compromises required
- Acceptable deviations from pure dendritic pattern (if any)
- Rationale for architectural decisions

**FR-1.3**: Reusable patterns shall be extracted to `PATTERNS.md` with:

- Module structure templates for NixOS configurations
- Clan inventory patterns for machine definitions
- Service instance patterns for essential services
- Vars generator patterns for secrets management

**FR-1.4**: Go/no-go decision framework shall evaluate:

- GO: No fundamental conflicts, proceed to Phase 1 with confidence
- CONDITIONAL GO: Minor compromises required, proceed with caution and additional monitoring
- NO-GO: Fundamental incompatibilities, pivot to vanilla clan + flake-parts pattern

**Acceptance criteria**:

- [ ] test-clan flake evaluates without errors (`nix flake check`)
- [ ] test-vm builds successfully (`nix build .#nixosConfigurations.test-vm.config.system.build.toplevel`)
- [ ] Documentation complete with architectural decision rationale
- [ ] Go/no-go decision made with explicit justification

---

### FR-2: VPS Infrastructure Deployment (Phase 1)

**FR-2.1**: Terraform/terranix shall provision Hetzner Cloud CX53 VPS with:

- Declarative terraform configuration via terranix (Nix-based terraform config generation)
- Hetzner Cloud API integration via API token from clan vars
- SSH key provisioning for initial access
- Server specification: 8 vCPU, 32GB RAM, 240GB NVMe SSD, CX53 instance type

**FR-2.2**: NixOS shall be installed on cinnabar via:

- `clan machines install cinnabar` command (automated NixOS installation)
- Disko declarative partitioning with LUKS encryption (automatic disk setup)
- Validated dendritic + clan patterns from Phase 0 (or hybrid as determined)
- Initial system configuration activating all clan services

**FR-2.3**: Zerotier controller shall be operational with:

- Zerotier service configured via clan zerotier service instance (controller role on cinnabar)
- Network ID generated and accessible to all machines
- Controller reachable from local development machine for network management
- Zerotier CLI functional for network administration

**FR-2.4**: SSH access shall be configured with:

- SSH daemon via clan sshd service instance (server role on cinnabar)
- Certificate-based authentication (SSH CA certificates distributed via clan)
- Accessible via zerotier network IP (zerotier VPN mesh)
- Emergency access via clan emergency-access service (root password recovery)

**FR-2.5**: Clan vars shall deploy secrets with:

- SSH host keys generated via clan sshd vars generator
- Service credentials generated as needed
- Secrets deployed to `/run/secrets/` with correct ownership and permissions
- Public keys accessible in nix store, private keys only in `/run/secrets/`

**Acceptance criteria**:

- [ ] Terraform provisions VPS successfully (`nix run .#terraform.terraform -- apply`)
- [ ] NixOS installation completes without errors
- [ ] SSH access functional from local machine (`ssh root@<cinnabar-zerotier-ip>`)
- [ ] Zerotier controller operational (`zerotier-cli info` shows controller status)
- [ ] Clan vars deployed (`ls /run/secrets/` shows expected files)
- [ ] Stable for 1-2 weeks minimum before Phase 2

---

### FR-3: Darwin Host Migration (Phases 2-4)

**FR-3.1**: Darwin modules shall be converted to dendritic pattern with:

- Each darwin module contributing to `flake.modules.darwin.*` namespace
- Home-manager modules contributing to `flake.modules.homeManager.*` namespace
- Host-specific configurations in `modules/hosts/<hostname>/default.nix`
- Imports via `imports = with config.flake.modules; [ darwin.base homeManager.shell ];`

**FR-3.2**: Clan inventory shall define darwin machines with:

- Machine entry for each darwin host (blackphos, rosegold, argentum)
- Tags: `[ "darwin" "workstation" ]` (and `"primary"` for stibnite)
- machineClass: `"darwin"`
- Service instance role assignments (peer for zerotier, server/client for sshd, default for emergency-access and users)

**FR-3.3**: Zerotier peer role shall connect with:

- Peer role configuration via clan zerotier service instance
- Connection to cinnabar controller (always-on VPS zerotier controller)
- Full mesh connectivity (darwin host can reach cinnabar and other darwin hosts)
- Automatic network join on system activation

**FR-3.4**: Clan vars shall generate and deploy darwin secrets with:

- SSH host keys generated for each darwin machine
- User-specific secrets (if configured)
- Secrets deployed to `/run/secrets/` with darwin-compatible permissions
- Home-manager integration for user-level secrets access

**FR-3.5**: Functionality preservation shall be validated with:

- Package comparison: pre-migration vs. post-migration package lists identical
- System services functional: all previously working services operational
- Development workflows intact: editors, languages, tools, shell configuration
- Homebrew integration working (if used): casks, formulae, taps
- System preferences applied: macOS settings via nix-darwin

**FR-3.6**: Multi-machine coordination shall be operational with:

- SSH via zerotier network functional between all hosts
- Clan service instances deployed correctly across machines
- Vars shared appropriately (where `share = true` configured)
- Network latency acceptable for development use (non-critical)

**Acceptance criteria per host**:

- [ ] Host configuration builds (`nix build .#darwinConfigurations.<hostname>.system`)
- [ ] Deployment succeeds (`darwin-rebuild switch --flake .#<hostname>`)
- [ ] All functionality preserved (zero-regression validation)
- [ ] Zerotier peer connected (`zerotier-cli status` shows network membership)
- [ ] SSH via zerotier works (`ssh crs58@<host-zerotier-ip>`)
- [ ] Stable for 1-2 weeks before next host

**Phase sequencing**:

- Phase 2: blackphos (establish patterns)
- Phase 3: rosegold (validate pattern reusability)
- Phase 4: argentum (final validation before stibnite)

---

### FR-4: Primary Workstation Migration (Phase 5)

**FR-4.1**: Pre-migration readiness shall be validated with:

- blackphos stable for 4-6 weeks minimum
- rosegold stable for 2-4 weeks minimum
- argentum stable for 2-4 weeks minimum
- No outstanding critical bugs or issues in patterns
- All workflows tested on other hosts (development environment, tools, system services)
- Full backup of current stibnite configuration created
- Rollback procedure documented and tested
- Low-stakes timing (not before important deadline)

**FR-4.2**: stibnite migration shall apply proven patterns with:

- Configuration in `modules/hosts/stibnite/default.nix` using blackphos patterns
- All daily-use workflows configured: development environment, communication tools, system services, GUI applications
- Enhanced validation before deployment (dry-run, double-check all imports)
- Staged deployment (deploy but don't reboot immediately, test in current session)

**FR-4.3**: Daily workflows shall be validated immediately post-migration:

- Development environment: editors, IDEs, language environments, version control
- Communication tools: if managed via nix (browsers, chat applications)
- System services: essential background services
- Shell configuration: fish, starship, aliases, functions
- Performance: system responsiveness, build times

**FR-4.4**: 5-machine network shall be complete with:

- Zerotier peer role on stibnite connecting to cinnabar controller
- Full mesh connectivity: stibnite can reach all other machines (cinnabar, blackphos, rosegold, argentum)
- SSH via zerotier functional to/from stibnite
- Multi-machine coordination operational (all clan services deployed across 5 machines)

**FR-4.5**: Productivity shall be maintained with:

- No critical regressions in daily workflows
- Performance maintained (build times, system responsiveness)
- All applications and tools functional
- Subjective productivity assessment: maintained or improved

**Acceptance criteria**:

- [ ] Pre-migration checklist 100% complete
- [ ] stibnite configuration builds successfully
- [ ] Deployment succeeds without errors
- [ ] All daily workflows functional (comprehensive validation)
- [ ] 5-machine zerotier network complete
- [ ] Productivity maintained (subjective assessment positive)
- [ ] Stable for 1-2 weeks before Phase 6 cleanup

---

### FR-5: Legacy Cleanup (Phase 6)

**FR-5.1**: nixos-unified infrastructure shall be removed with:

- Delete `configurations/` directory (host-specific nixos-unified configs)
- Remove nixos-unified flake input from `flake.nix`
- Remove nixos-unified flakeModules imports
- Update documentation referencing nixos-unified

**FR-5.2**: Secrets migration completion (if applicable):

- Evaluate remaining sops-nix secrets
- Migrate generated secrets to clan vars (SSH keys, passwords)
- Keep sops-nix for external credentials (API tokens) if hybrid approach chosen
- Remove sops-nix entirely if full migration achieved

**FR-5.3**: Documentation shall be updated with:

- README reflecting dendritic + clan architecture
- Migration experience documented for future reference
- Architectural decisions captured in docs/notes/
- Patterns documented for maintainability

**Acceptance criteria**:

- [ ] nixos-unified completely removed
- [ ] Secrets migration strategy finalized (full or hybrid)
- [ ] Documentation updated and accurate
- [ ] Clean dendritic + clan architecture
- [ ] All 5 machines operational with no legacy dependencies

---

## Non-Functional Requirements

### Performance

**Build times**: Configuration evaluation and build times shall not significantly regress from current nixos-unified setup

- Baseline: Measure current `darwin-rebuild switch` time for each host
- Target: Within 20% of baseline (acceptable: 10 seconds build now → 12 seconds after migration)
- Critical: Primary workstation (stibnite) build times must not impact daily workflow

**System responsiveness**: Darwin hosts shall maintain interactive responsiveness

- No perceptible lag in shell, editor, or GUI applications
- Background services shall not consume excessive CPU/memory
- Zerotier network overhead acceptable (non-critical path for daily work)

**Network latency**: Zerotier mesh network latency shall be acceptable for development use

- Inter-machine SSH latency < 100ms on local network
- WAN latency dependent on internet connection (not critical for daily workflow)
- No requirement for low-latency distributed services (out of scope)

### Security

**Secrets encryption**: All secrets shall be encrypted at rest via age encryption

- Clan vars encrypted in `sops/machines/<hostname>/secrets/`
- Age public keys for admins group and per-machine keys
- Decryption only on target machine during deployment
- Private keys only in `/run/secrets/` with restrictive permissions (mode 0600, root or specific user ownership)

**SSH access**: SSH shall use certificate-based authentication

- SSH CA certificates distributed via clan sshd service
- No password-based authentication (disabled in sshd configuration)
- Zerotier network provides VPN security layer (encrypted mesh)

**VPS security**: cinnabar VPS shall be hardened via:

- srvos hardening modules (server security baseline)
- LUKS full-disk encryption
- Firewall configured via NixOS (allow SSH, zerotier, deny all else)
- Regular security updates via nixpkgs tracking

**Emergency access**: Root access recovery via:

- Clan emergency-access service (password-based recovery)
- Only on workstations (not VPS, to prevent remote access)
- Documented procedure for recovery

### Scalability

**Machine count**: Architecture shall support 5 machines (current requirement)

- Extensible to additional machines without architectural changes
- Clan inventory scales to dozens of machines (proven in clan-infra)
- Zerotier supports up to 100 peers on free tier

**Configuration size**: Module organization shall scale as configuration grows

- Flat feature categories (not nested) prevent deep hierarchies
- Clear namespace (`flake.modules.*`) enables discovery
- import-tree auto-discovery scales to hundreds of modules

**Build parallelism**: Configuration evaluation shall remain performant as machines increase

- Per-host evaluation independent (can build multiple hosts in parallel)
- Shared modules evaluated once, reused across hosts

### Integration

**Terraform integration**: VPS provisioning shall integrate with Hetzner Cloud

- Terranix generates terraform configuration from Nix
- Terraform state tracked (manual management acceptable for MVP)
- Idempotent deployment (re-running terraform safe)

**Home-manager integration**: User environment shall integrate with system configuration

- home-manager modules imported in host configurations
- `home-manager.useGlobalPkgs = true` for consistency
- User-level secrets via clan vars accessible in home-manager

**Homebrew integration** (darwin-specific): macOS package manager shall coexist with nix

- nix-darwin homebrew module configures homebrew casks, formulae, taps
- Declarative homebrew management (brewfile generation)
- Nix-managed and Homebrew-managed packages coexist

**SOPS integration** (if hybrid approach): External secrets shall remain in sops-nix

- sops-nix module imported alongside clan
- Age-based encryption (shared age keys)
- Separate secret paths (`/run/secrets-sops/`) to avoid conflicts with clan vars

---

## Implementation Planning

### Epic Breakdown Required

Requirements must be decomposed into epics and bite-sized stories (200k context limit per story).

**Epic alignment to 6 migration phases**:

**Epic 1: Architectural Validation** (Phase 0)

- Stories: test-clan setup, dendritic + clan integration, pattern extraction, go/no-go decision

**Epic 2: VPS Infrastructure Deployment** (Phase 1)

- Stories: terraform setup, cinnabar provisioning, NixOS installation, zerotier controller, SSH configuration, vars deployment, stability validation

**Epic 3: First Darwin Migration** (Phase 2 - blackphos)

- Stories: module conversion, clan inventory integration, zerotier peer, vars deployment, functionality validation, pattern documentation, stability monitoring

**Epic 4: Multi-Darwin Validation** (Phase 3 - rosegold)

- Stories: pattern application, zerotier peer, multi-machine coordination testing, stability validation

**Epic 5: Third Darwin Host** (Phase 4 - argentum)

- Stories: pattern application, zerotier peer, 4-machine network validation, readiness for stibnite

**Epic 6: Primary Workstation Migration** (Phase 5 - stibnite)

- Stories: readiness validation, migration preparation, deployment, workflow validation, productivity assessment, stability monitoring

**Epic 7: Legacy Cleanup** (Phase 6)

- Stories: nixos-unified removal, secrets migration completion, documentation updates

**Next Step:** Run `workflow create-epics-and-stories` to create the implementation breakdown.

---

## References

- Product Brief: docs/notes/development/bmm-product-brief-infra-2025-11-02.md
- Integration Plan: docs/notes/clan/integration-plan.md
- Migration Assessment: docs/notes/clan/migration-assessment.md
- Technical Context: docs/notes/prompts/clan-migration.md

**Reference Repositories**:

- clan-core: ~/projects/nix-workspace/clan-core/ (modules, CLI, documentation)
- clan-infra: ~/projects/nix-workspace/clan-infra/ (production infrastructure)
- dendritic-flake-parts: ~/projects/nix-workspace/dendritic-flake-parts/ (pattern reference)
- jfly-clan-snow: ~/projects/nix-workspace/jfly-clan-snow/ (darwin + clan example)
- mic92-clan-dotfiles: ~/projects/nix-workspace/mic92-clan-dotfiles/ (comprehensive clan usage)

---

## Next Steps

1. **Epic & Story Breakdown** - Run: `workflow create-epics-and-stories`
2. **Architecture** - Run: `workflow create-architecture` (for technical design decisions)

---

_This PRD captures the essence of infra - a validation-first, type-safety-focused infrastructure migration combining dendritic flake-parts optimization with clan-core multi-machine coordination, prioritizing architectural validation before infrastructure commitment and preserving daily productivity throughout progressive rollout._

_Created through extraction of comprehensive product brief and technical planning documentation into structured requirements format._
