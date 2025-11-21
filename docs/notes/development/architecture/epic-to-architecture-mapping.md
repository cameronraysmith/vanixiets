# Epic to Architecture Mapping

**Sprint Change**: Epic 2-6 restructured per sprint change proposal (2025-11-20)

## Epic-to-Architecture Mapping (Updated 2025-11-20)

### Epic 1: Architectural Validation (Phase 0) - COMPLETE

**Status**: ✅ DONE (2025-11-20)

**Architecture Coverage**:
- Dendritic flake-parts pattern (HIGH confidence)
- Clan-core inventory + service instances (HIGH confidence)
- Terraform/terranix infrastructure (HIGH confidence)
- Sops-nix secrets (two-tier architecture, HIGH confidence)
- Zerotier heterogeneous networking (HIGH confidence)
- Home-manager Pattern A (dendritic aggregates, HIGH confidence)
- Five-layer overlay architecture (HIGH confidence)

**Validation**: 21/22 stories complete, 7/7 patterns HIGH confidence, 0 critical/major blockers

---

### Epic 2: Infrastructure Architecture Migration (Phase 1-4) - CONTEXTED

**Status**: Contexted (ready for Phase 1 story drafting)
**Stories**: 13 stories across 4 phases (2.1-2.13)

**Architecture Coverage**:
- **Phase 1 (Home-Manager Foundation)**: Pattern A migration, secrets (two-tier sops-nix)
- **Phase 2 (Darwin Workstations)**: Blackphos + stibnite config migration, zerotier darwin
- **Phase 3 (VPS Migration)**: Cinnabar + electrum config migration (infrastructure already deployed)
- **Phase 4 (Future Machines)**: Rosegold + argentum config creation, test harness migration

**Architectural Patterns Applied**:
- Dendritic flake-parts (all phases)
- Clan-core inventory (all machines)
- Sops-nix two-tier secrets (Phase 1, 2)
- Zerotier darwin integration (Phase 2, 4)
- Home-manager Pattern A (Phase 1, 2, 4)
- Five-layer overlays (Phase 1)
- Test harness (Phase 4)

**Dependencies**: Epic 1 complete (all patterns validated)

---

### Epic 3: Multi-Darwin Validation (Phase 2 - rosegold) - BACKLOG

**Status**: Backlog
**Stories**: 3 stories (3.1-3.3)
**Note**: Original "Epic 3 - First Darwin Migration (blackphos)" consolidated - work complete in Epic 1

**Architecture Coverage**:
- Darwin deployment (rosegold, janettesmith user)
- Multi-darwin coordination validation (3 darwin workstations)
- Zerotier mesh VPN validation

**Architectural Patterns Applied**:
- Dendritic + clan (rosegold config created in Epic 2 Phase 4)
- Zerotier darwin (validated in Epic 1, reused)
- Multi-machine coordination

**Dependencies**: Epic 2 complete (rosegold config exists)

---

### Epic 4: Third Darwin Host (Phase 3 - argentum) - BACKLOG

**Status**: Backlog
**Stories**: 2 stories (4.1-4.2)

**Architecture Coverage**:
- Darwin deployment (argentum, christophersmith user)
- 4-machine network validation
- Full fleet coordination (2 VPS + 4 darwin)

**Architectural Patterns Applied**:
- Dendritic + clan (argentum config created in Epic 2 Phase 4)
- Zerotier darwin (validated in Epic 1, reused)
- Heterogeneous fleet management

**Dependencies**: Epic 3 complete (rosegold stable)

---

### Epic 5: Primary Workstation Validation (Phase 4 - stibnite) - OPTIONAL

**Status**: OPTIONAL (evaluate at Epic 4 completion)
**Stories**: 1 story (5.1 - consolidated from 3 stories)
**Execution Criteria**: Execute only if Epic 2 Phase 2 deployment shows instability

**Architecture Coverage**:
- Extended stability validation (stibnite monitoring)
- Primary workstation operational validation (crs58 workflow)

**Architectural Patterns Applied**:
- Validation-only (no new patterns, monitoring existing deployment)

**Dependencies**: Epic 2 Phase 2 (stibnite migrated), Epic 4 (full fleet operational)

**Decision Point**: If stibnite stable 2+ weeks post-Epic 2, skip Epic 5 and proceed to Epic 6

---

### Epic 6: Legacy Cleanup (Phase 5) - BACKLOG

**Status**: Backlog
**Stories**: 3 stories (6.1-6.3)

**Architecture Coverage**:
- Nixos-unified infrastructure removal
- Secrets migration finalization
- Documentation updates

**Architectural Patterns Applied**:
- Cleanup and deprecation (no new patterns)
- Documentation consolidation

**Dependencies**: Epic 4 + Epic 5 (if executed)

---

## Architecture Coverage Summary

**Patterns Validated (Epic 1)**:
1. ✅ Dendritic flake-parts - HIGH confidence
2. ✅ Clan-core inventory + services - HIGH confidence
3. ✅ Terraform/terranix - HIGH confidence
4. ✅ Sops-nix two-tier secrets - HIGH confidence
5. ✅ Zerotier heterogeneous networking - HIGH confidence
6. ✅ Home-manager Pattern A - HIGH confidence
7. ✅ Five-layer overlays - HIGH confidence

**Patterns Applied (Epic 2-6)**:
- Epic 2: ALL 7 patterns (application to production infra)
- Epic 3-4: Dendritic + clan + zerotier darwin (deployment)
- Epic 5: Validation-only (no new patterns)
- Epic 6: Cleanup (deprecation of nixos-unified)

**Architecture Maturity**: All patterns proven in Epic 1, Epic 2+ is application/deployment
