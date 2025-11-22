# Success Criteria

**Migration success is measured by technical correctness, operational stability, and productivity preservation across the 6-phase progressive rollout:**

## Phase 0 success (test-clan validation + infrastructure deployment) - GO/NO-GO decision gate

- test-clan flake evaluates and builds successfully with dendritic + clan integration
- Dendritic flake-parts pattern proven feasible with clan functionality (no fundamental conflicts discovered)
- Integration patterns documented with confidence in `INTEGRATION-FINDINGS.md` and `PATTERNS.md`
- Go/no-go framework evaluation shows "GO" or "CONDITIONAL GO" with acceptable compromises
- If architectural validation succeeds: proceed to infrastructure deployment using clan-infra's proven terranix pattern (Hetzner VPS + GCP VM)
- Infrastructure validated with minimal services (SSH access, basic connectivity) before Phase 1 production integration
- If NO-GO: fallback to vanilla clan + flake-parts pattern (proven in clan-infra) without dendritic optimization

**Epic 1 GO Decision (2025-11-20):** 7/7 validation criteria PASS, 0 critical/major blockers, all 7 patterns HIGH confidence for production use. Epic 2-6 production migration AUTHORIZED.

**Dependencies SATISFIED:**
- ✅ Dendritic flake-parts + clan patterns (Stories 1.1-1.7)
- ✅ Terraform/terranix infrastructure (Stories 1.4-1.5, Hetzner proven)
- ✅ Zerotier heterogeneous networking (Stories 1.9, 1.12, nixos ↔ darwin coordination)
- ✅ Two-tier secrets architecture (Stories 1.10A, 1.10C, multi-user encryption)
- ✅ Migration transformation patterns (Stories 1.8-1.13, 3,000+ lines documentation)
- ✅ Home-manager Pattern A (Stories 1.8A, 1.10BA, cross-platform proven)
- ✅ Five-layer overlay architecture (Stories 1.10D-1.10DB, all layers validated)

## Phase 1 success (production integration) - Proceed to darwin migration if

- Production services integrated on deployed infrastructure (cinnabar VPS + GCP VM from Phase 0)
- Zerotier controller operational with mesh network coordination across both VMs
- Production-grade hardening applied (srvos modules, firewall rules, security baseline)
- Service deployment patterns validated (zerotier coordination, SSH via mesh network)
- Clan vars deployed correctly to `/run/secrets/` with proper permissions on all infrastructure
- Multi-VM coordination proven (clan inventory managing 2+ machines with different roles)
- Stable for 1-2 weeks minimum with no critical issues before darwin migration

## Phase 2-4 success (darwin hosts: blackphos → rosegold → argentum) - Proceed to next host if

- Host configuration builds and deploys successfully using established patterns from previous phase
- All existing functionality preserved (zero-regression validation: package lists, system services, development workflows identical)
- Clan vars generated and deployed with correct file permissions
- Zerotier peer connects to cinnabar controller and mesh network communication functional
- SSH via zerotier network works (certificate-based authentication)
- Multi-machine coordination validated (services deployed across hosts, vars shared where configured)
- Stable for 1-2 weeks minimum per host before proceeding to next

## Phase 5 success (stibnite primary workstation) - Complete migration if

- All previous phases (2-4) stable for cumulative 4-6 weeks minimum
- stibnite operational with all daily workflows functional (development, communication, system services)
- Productivity maintained or improved compared to pre-migration baseline
- 5-machine zerotier network complete and stable (cinnabar + 4 darwin hosts with full mesh connectivity)
- No critical regressions in functionality or performance
- Stable for 1-2 weeks minimum before cleanup phase

## Overall migration success (ready for Phase 6 cleanup)

- All 5 machines migrated to dendritic + clan with consistent patterns
- No critical regressions in functionality across any host
- Multi-machine coordination operational (clan inventory, vars deployment, service instances)
- Type safety improvements measurable (fewer evaluation errors, clearer error messages from module system type checking)
- Maintainability improved (clearer module organization via dendritic namespace, explicit interfaces via `config.flake.*`)
- Zerotier mesh network stable across all hosts with reliable inter-machine communication
- Ready to remove nixos-unified legacy infrastructure

## Business Metrics

**Development velocity**: Configuration changes execute faster due to clearer module boundaries and explicit interfaces (baseline: current time to add/modify features, target: 20-30% reduction in debugging time)

**Error reduction**: Type checking via module system catches configuration errors at evaluation time rather than deployment (measure: count of runtime configuration errors, target: 50% reduction)

**Maintainability score**: Subjective assessment of ease of understanding and modifying configurations (baseline: current cognitive load, target: "significantly easier to understand module dependencies")

**Migration timeline**: Conservative estimate 15-18 weeks for complete migration with infrastructure deployment and stability gates, aggressive 6-8 weeks if all phases proceed smoothly without issues (extended 2-3 weeks from original estimate due to Phase 0 infrastructure deployment). Epic 1 actual: 3+ weeks (Phase 0 complete). Epic 2 estimate: 2-4 weeks faster due to "rip the band-aid" approach.

**Operational cost**: Infrastructure adds ~€24/month (~$25 USD) Hetzner VPS + ~$5/month GCP e2-micro VM = ~$30 USD/month ongoing operational expense, accepted as cost of always-on infrastructure benefits and migration validation before darwin hosts. Epic 1 outcome: Infrastructure deployed at ~$30/month (cinnabar + electrum VMs).

**Rollback frequency**: Number of times rollback required during migration (target: 0, acceptable: 1-2 for non-primary hosts, unacceptable: rollback of stibnite primary workstation). Epic 1 actual: 0 rollbacks (target met ✅).

---
