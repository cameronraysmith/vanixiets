# Product Scope

## MVP - Minimum Viable Product

The MVP encompasses the complete 6-phase migration delivering a fully operational dendritic + clan infrastructure across all 5 machines with type safety improvements, multi-machine coordination, and validated architectural patterns.

**Phase 0 - Validation Environment + Infrastructure Deployment** (test-clan repository + real infrastructure, Weeks 0-2):

**Architectural validation (Week 0)**:
- Minimal flake structure with clan-core + import-tree + flake-parts integration in disposable test repository
- Test NixOS VM configuration using dendritic flake-parts pattern (or validated hybrid if pure dendritic conflicts with clan)
- Clan inventory with single test machine demonstrating inventory evaluation
- Essential clan services (emergency-access, sshd, zerotier) configured via service instances
- Vars generation and deployment validation (test generators, verify deployment to `/run/secrets/`)
- Documentation of integration findings in `INTEGRATION-FINDINGS.md` (what works, what requires compromise)
- Pattern extraction in `PATTERNS.md` (reusable patterns for infrastructure deployment)
- Go/no-go decision framework evaluation (GO/CONDITIONAL GO/NO-GO with explicit criteria)

**Infrastructure deployment (Weeks 1-2, if architectural validation succeeds)**:
- Adopt clan-infra's proven terranix pattern for multi-cloud infrastructure deployment
- Deploy Hetzner Cloud CX53 VPS (cinnabar) using validated patterns from test-clan
- Deploy GCP e2-micro VM (orb-nixos) for multi-cloud validation
- Minimal service configuration: SSH access, zerotier mesh network coordination between VMs
- Disko declarative partitioning with LUKS encryption on both VMs
- Validate multi-machine clan inventory coordination across heterogeneous cloud providers
- Terraform state management via encrypted backend (S3 or GCS)
- Infrastructure validated and stable before Phase 1 production integration

**Epic 1 Over-Delivery:** Infrastructure deployment completed in Phase 0 (cinnabar IP 49.13.68.78, electrum deployed and operational). Original PRD correctly planned infrastructure deployment in Phase 0; Epic 1 delivered as designed.

**Phase 1 - Production Integration** (cinnabar + orb-nixos, Weeks 3-5):

- Production services integrated on deployed infrastructure from Phase 0
- Zerotier controller operational on cinnabar with mesh network coordination to orb-nixos
- Production-grade hardening via srvos modules (security baseline for both VMs)
- SSH daemon with certificate-based authentication via clan sshd service on both machines
- Emergency access configuration via clan emergency-access service (root access recovery)
- Clan vars deployment for production secrets (SSH host keys, service credentials, API tokens)
- Firewall rules configured via NixOS (zerotier mesh access, deny external except SSH)
- Service deployment patterns validated (zerotier coordination, SSH via mesh, multi-VM clan inventory)
- Infrastructure stable and production-ready before darwin migration

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

## Core Infrastructure Components (across all phases)

**Dendritic flake-parts module structure**: Every Nix file is a flake-parts module contributing to `flake.modules.{nixos,darwin,homeManager}.*` namespace with clear interfaces via `config.flake.*` access

**Clan inventory system**: Centralized multi-machine coordination defining all 5 machines with tags (nixos, darwin, workstation, vps, cloud, primary) and machineClass (nixos, darwin) for service deployment targeting

**Clan service instances**: Instance-based service deployment with roles (emergency-access.default for all workstations, users-crs58.default for workstations, users-root.default for cinnabar, zerotier-local with controller role on cinnabar and peer role on all machines, sshd-clan with server role on all and client role on all)

**Vars generators for secrets management**: Declarative secret generation replacing manual sops-nix management (SSH host keys, service passwords, API keys, with automatic deployment to `/run/secrets/` and proper file permissions)

**import-tree auto-discovery**: Automatic module loading eliminating manual imports via recursive directory scanning of `modules/` with flake-parts integration

**Justfile-based CI/CD workflow**: Universal command interface (`just check`, `just build`, `just test`) with local-CI parity (CI executes `nix develop -c just <command>` matching local development)

## Out of Scope for MVP

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
- Type-safe homeHosts abstraction (Story 1.11 deferred based on Epic 1 empirical evidence - Pattern A proven sufficient at scale)

## MVP Success Criteria

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

## Post-MVP Expansion Phases

Upon MVP completion (Epics 1-6), the following expansion phases extend the infrastructure:

**Phase 6 - GCP Multi-Cloud Infrastructure** (Epic 7):

- Deploy togglable CPU-only and GPU-capable nodes on GCP via terranix
- Primary business objective: GCP contract obligations, GPU availability for ML workloads
- Proven patterns: Apply terranix patterns validated on Hetzner (cinnabar, electrum)
- Cost management via enabled/disabled toggle (disabled nodes incur zero cost)
- Clan inventory integration with zerotier mesh

**Phase 7 - Documentation Alignment** (Epic 8):

- Comprehensive Starlight docs site update (packages/docs/src/content/docs/)
- Architecture documentation reflecting dendritic + clan patterns
- Host onboarding guides for darwin vs nixos deployment paths
- Secrets management documentation for two-tier pattern
- Zero references to deprecated nixos-unified architecture

**Phase 8 - Branch Consolidation and Release** (Epic 9):

- Bookmark tags at branch boundaries (docs, clan, clan-01)
- CI/CD workflow validation on clan-01
- Merge clan-01 to main with full history preservation
- Semantic versioning release with changelog
- Dependency: docs accurate before merge (Epic 8 complete)

**Post-MVP success criteria**:

- GCP nodes operational with toggleable provisioning
- Documentation accurate and aligned with implemented architecture
- clan-01 merged to main with clean release

---
