# Implementation Planning

## Epic Breakdown Required

Requirements must be decomposed into epics and bite-sized stories (200k context limit per story).

**Epic alignment to 5 migration phases** (Epic 3 consolidated into Epic 2):

**Epic 1: Architectural Validation + Infrastructure Deployment** (Phase 0) - **COMPLETE**

- Stories: test-clan setup, dendritic + clan integration, pattern extraction, go/no-go decision, infrastructure deployment (Hetzner VPS), multi-machine coordination validation
- Status: 21/22 stories completed (95.5%), 1 deferred (Story 1.11 - homeHosts unnecessary)
- Outcome: GO decision rendered 2025-11-20, all 7 patterns HIGH confidence

**Epic 2: Infrastructure Architecture Migration** (Phase 1)

- Stories: home-manager foundation migration, blackphos config migration, stibnite config migration, cinnabar + electrum config migration, rosegold + argentum config creation
- Migration Strategy: "Rip the band-aid" approach - `clan-01` branch with wholesale nix config replacement
- Four Phases: (1) Home-Manager Foundation, (2) Active Darwin Workstations, (3) VPS Config Migration, (4) Future Machines

**Epic 3: Rosegold Deployment** (Phase 2, formerly Epic 4)

- Stories: rosegold deployment using proven patterns from Epic 2
- Note: blackphos migration complete in Epic 2 Phase 2

**Epic 4: Argentum Deployment** (Phase 3, formerly Epic 5)

- Stories: argentum deployment using proven patterns from Epic 2-3

**Epic 5: Stibnite Extended Validation** (Phase 4, formerly Epic 6) - **CONDITIONAL**

- Stories: stibnite configuration validation, extended stability testing
- Only execute if Epic 2 Phase 2 shows instability requiring additional validation

**Epic 6: Legacy Cleanup** (Phase 5, formerly Epic 7)

- Stories: nixos-unified removal, secrets migration completion, documentation updates

**Epic 7: GCP Multi-Node Infrastructure** (Post-MVP Phase 6)

- Stories: Terranix GCP provider configuration, CPU-only togglable node, GPU-capable togglable node, clan integration and zerotier mesh
- Primary business objective: GCP contract obligations, GPU availability
- Pattern: Replicate `modules/terranix/hetzner.nix` for GCP provider
- Depends on: Epic 6 complete

**Epic 8: Documentation Alignment** (Post-MVP Phase 7)

- Stories: Audit existing docs, update architecture/patterns docs, update host onboarding guides, update secrets management docs
- Comprehensive Starlight docs site update
- Zero references to deprecated nixos-unified architecture
- Depends on: Epic 7 complete (document what exists)

**Epic 9: Branch Consolidation and Release** (Post-MVP Phase 8)

- Stories: Create bookmark tags, validate CI/CD, merge clan-01 to main
- Semantic versioning release with changelog
- Full history preservation (no force-push)
- Depends on: Epic 8 complete (docs accurate before merge)

**Next Step:** Run `workflow create-epics-and-stories` to create the implementation breakdown.

---
