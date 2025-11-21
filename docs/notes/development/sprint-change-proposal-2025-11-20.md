# Sprint Change Proposal - Epic 2 Re-Scoping

**Date:** 2025-11-20
**Project:** infra - Infrastructure Architecture Migration
**Change Scope:** MODERATE - Epic realignment affecting Epic 2-7, requires backlog reorganization
**Proposal Status:** APPROVED

---

## Executive Summary

Epic 2's original scope ("VPS Infrastructure Foundation - deploy cinnabar VPS") is obsolete because Epic 1 over-delivered on Phase 0 validation. Infrastructure is already deployed (cinnabar + electrum VMs operational), blackphos already migrated with full feature parity, and all 7 architectural patterns proven at HIGH confidence. Epic 2 should apply validated test-clan patterns to production infra repository using "rip the band-aid" approach, not redeploy infrastructure.

**Recommended Approach:** Epic Realignment with Strategic Consolidation (11-15 hours effort, LOW risk)

**Key Changes:**
1. **Epic 2:** Redefine from "Deploy cinnabar VPS" → "Architecture Migration (test-clan → infra)" with 4 phases, 12-15 stories
2. **Epic 3:** Consolidate into Epic 2 Phase 2 (blackphos work complete in Epic 1)
3. **Epic 4-7:** Renumber to Epic 3-6 and update dependencies
4. **Strategy:** "Rip the band-aid" approach (`cp` files from test-clan → infra on `clan-01` branch)

**MVP Impact:** ✅ MORE ACHIEVABLE - Potentially 2-4 weeks faster than original estimate

**Handoff:** Product Owner (John) + Scrum Master (Bob) lead, Architect (Winston) supporting

---

## Section 1: Issue Summary

### Problem Statement

Epic 2's original scope ("VPS Infrastructure Foundation - deploy cinnabar VPS") is obsolete because Epic 1 over-delivered on Phase 0 validation scope.

Epic 1 was scoped to validate the dendritic+clan architecture in a minimal test-clan repository. However, Epic 1 results show:

- **Infrastructure already deployed:** cinnabar + electrum VMs operational on Hetzner (Stories 1.5, 1.9)
  - Cinnabar IP: 49.13.68.78 (sprint-status.yaml:129)
  - LUKS encryption, zerotier controller, production-ready
- **Blackphos already migrated:** Full feature parity achieved (270 packages preserved, Stories 1.8, 1.12)
  - Physical deployment complete on hardware
  - Zerotier peer connected, SSH validated
- **All 7 patterns proven at HIGH confidence:** dendritic, clan, terraform, sops-nix, zerotier, Pattern A, overlays
  - Epic 1 retrospective lines 242-357 document validation
- **Comprehensive documentation created:** 3,000+ lines of guides, patterns, migration checklists (Story 1.13)

Epic 2's current 6 stories (2.1-2.6) assume deploying new infrastructure, but Stories 2.2-2.6 are now obsolete (infrastructure deployment complete). The actual Epic 2 work should be **applying validated test-clan patterns to production infra repository**, not redeploying infrastructure that already exists.

### Context - When/How Discovered

**Discovered:** Epic 1 retrospective (2025-11-20, `docs/notes/development/epic-1-retro-2025-11-20.md`)

**Retrospective Action Item #2** (lines 468-477): Explicitly calls for "Execute Course-Correction Workflow for Epic 2 Re-Scoping" with ~4 hours investment to detail the "rip the band-aid" approach.

### Evidence

1. **Infrastructure deployed:** sprint-status.yaml line 129 shows cinnabar IP: 49.13.68.78 (Story 1.10A deployment successful)
2. **Blackphos migrated:** Epic 1 retrospective lines 94-96 (Story 1.12 physical deployment successful, raquel's 270 packages functional)
3. **Patterns validated:** Epic 1 retrospective lines 242-357 (7/7 patterns HIGH confidence, all Epic 2-6 ready)
4. **Documentation complete:** Epic 1 retrospective lines 137-144 (Story 1.13 created 3,000+ lines)
5. **PRD alignment:** PRD functional-requirements.md lines 7-56 describe Phase 0 as including infrastructure deployment, not Phase 1

### Type of Issue

- **Primary:** Misunderstanding of original requirements (Epic 2 file diverged from PRD intent)
- **Secondary:** Strategic pivot (Epic 1 over-delivered, enabling faster execution path)

---

## Section 2: Impact Analysis

### Epic Impact

**Epic 2 (Current):** "VPS Infrastructure Foundation (Phase 1 - cinnabar)"
- **Impact:** Complete redefinition required
- **Current state:** 6 stories (2.1-2.6), most obsolete (Stories 2.2-2.6 assume deploying new infrastructure)
- **New scope:** "Infrastructure Architecture Migration (Apply test-clan patterns to infra)"
- **New structure:** 4 phases across 12-15 stories

**New Epic 2 Structure:**

**Phase 1: Home-Manager Migration Foundation** (3-4 stories)
- Migrate home-manager config to dendritic+clan pattern
- Affects ALL hosts (foundation layer)
- Include LazyVim-module → lazyvim-nix migration

**Phase 2: Active Darwin Workstations - blackphos + stibnite** (4-5 stories)
- Migrate blackphos config in infra to match test-clan version
- Migrate stibnite config (apply architecture, preserve differences)
- Activate both from infra (blackphos switches: test-clan → infra)
- Cleanup: Remove unused configs (blackphos-nixos, stibnite-nixos, rosegold-old)

**Phase 3: VPS Migration - cinnabar + electrum** (2-3 stories)
- Migrate cinnabar + electrum configs from test-clan → infra
- **Note:** Already deployed and operational - just config migration

**Phase 4: Future Machines - rosegold + argentum** (3-4 stories)
- Create rosegold configuration in infra
- Create argentum configuration in infra

**Epic 3:** "First Darwin Migration (Phase 2 - blackphos)"
- **Impact:** Obsolete - work complete in Epic 1
- **Action:** Merge into revised Epic 2 Phase 2

**Epic 4-7:** Minor updates
- **Impact:** Renumber (Epic 4 → 3, Epic 5 → 4, Epic 6 → 5, Epic 7 → 6)
- **Action:** Update dependencies to reference revised Epic 2

### Artifact Impact

**PRD:**
- ✅ **No changes needed** - PRD already correct
- Epic 2 file was misaligned with PRD, not the reverse

**Architecture:**
- ✅ **Minor enhancement updates** (not conflict resolution):
  - Update ADR-002 (ZFS → LUKS based on Story 1.5 findings)
  - Update darwin-networking-options.md (mark Option 1 as validated)
  - Update epic-to-architecture-mapping.md (reflect revised epic structure)

**Documentation:**
- ⚠️ **Updates required:**
  - Epic files (epics/epic-2.md through epic-7.md)
  - Sprint status (sprint-status.yaml)
  - README (if it references epic structure)

**CI/CD and infra-specific components:**
- ⚠️ **Preservation required:**
  - GitHub Actions workflows
  - TypeScript monorepo
  - Cloudflare deployment setup
  - Early Epic 2 story needed: "Identify infra-specific components to preserve"

**Test artifacts:**
- ✅ **Migration opportunity:**
  - Test harness from Story 1.6 (18 tests) should migrate to infra
  - Include in revised Epic 2 scope

---

## Section 3: Recommended Approach

### Approach: "Epic Realignment with Strategic Consolidation"

**Type:** Hybrid (Option 3 foundation + Option 1 execution)

**Decision:**
- Align epic structure with PRD (which was always correct)
- Honor Epic 1 retrospective recommendations (lines 360-456)
- Consolidate redundant epics (Epic 3 obsolete, merge into Epic 2)
- Apply "rip the band-aid" migration strategy

### Rationale

**Why this approach:**

1. **Celebrates Epic 1 success** - Epic 1 over-delivered (60-80h investment yielded infrastructure + patterns + docs)
2. **Aligns with PRD** - PRD always described Phase 0 = infrastructure deployment, Phase 1 = production integration
3. **Honors empirical evidence** - Epic 1 proved all 7 patterns work (HIGH confidence), would be wasteful not to apply immediately
4. **Faster to production** - "Rip the band-aid" approach (`cp` files from test-clan → infra) faster than file-by-file LLM processing
5. **Lower risk** - Git branch safety net (`clan-01` branch), proven patterns, comprehensive documentation

### Trade-offs Considered

| Factor | Option 1 (Direct Adjustment) | Option 2 (Rollback) | **Hybrid (SELECTED)** |
|--------|------------------------------|---------------------|----------------------|
| Effort | 7-10h | 68-92h | **11-15h** |
| Risk | MEDIUM | CRITICAL | **LOW** |
| Morale | Neutral | Catastrophic | **POSITIVE** |
| Sustainability | Suboptimal (messy epic structure) | N/A (destroys work) | **EXCELLENT** |
| Timeline impact | +1-2 weeks saved | -4-6 weeks wasted | **+2-4 weeks saved** |

### Why Alternatives Rejected

- **Option 1 (Direct Adjustment) alone:** Creates incoherent epic structure, doesn't honor Epic 1 learnings
- **Option 2 (Rollback):** Pure waste (68-92h destruction), zero benefit, catastrophic morale impact
- **Option 3 (MVP Review) alone:** Insufficient - needs execution plan (provided by Option 1 elements)

### Implementation Effort Breakdown

- Epic 2 redefinition: 6-8 hours (complete rewrite, 4 phases, 12-15 stories)
- Epic 3 consolidation: 1 hour (document merge rationale)
- Epic 4-7 renumbering: 2-3 hours (update dependencies, story IDs)
- Documentation updates: 2-3 hours (sprint-status.yaml, architecture notes)
- **Total:** 11-15 hours

### Long-term Benefits

- Epic structure matches PRD intent (clearer for future reference)
- "Rip the band-aid" pattern reusable for other migrations
- Institutional knowledge preserved (Epic 1 docs remain authoritative)
- Team morale boost (success celebrated, not second-guessed)

---

## Section 4: Detailed Change Proposals

### Change Proposal #1: Epic 2 Complete Redefinition

**File:** `docs/notes/development/epics/epic-2-vps-infrastructure-foundation-phase-1-cinnabar.md`
**Type:** Complete file replacement
**Status:** ✅ APPROVED

**Action:** Create new file `epic-2-infrastructure-architecture-migration.md` with 4-phase structure (12-15 stories), rename old file to `.OBSOLETE`

**New Structure:**
- Goal: Migrate infra repository from nixos-unified to dendritic+clan architecture
- Strategy: "Rip the Band-Aid" - `cp` files from test-clan → infra on `clan-01` branch
- Phase 1: Home-Manager Migration Foundation (Stories 2.1-2.4)
- Phase 2: Active Darwin Workstations (Stories 2.5-2.8)
- Phase 3: VPS Migration (Stories 2.9-2.10)
- Phase 4: Future Machines (Stories 2.11-2.13)

---

### Change Proposal #2: Epic 3 Consolidation Notice

**File:** `docs/notes/development/epics/epic-3-first-darwin-migration-phase-2-blackphos.md`
**Type:** Replace with consolidation notice
**Status:** ✅ APPROVED

**Action:** Replace content with consolidation notice documenting Epic 1 completion of blackphos work

**Key Content:**
- Status: CONSOLIDATED INTO EPIC 2 PHASE 2
- Rationale: Epic 1 Stories 1.8, 1.8A, 1.10BA-1.10E, 1.12 completed all blackphos work
- Original scope achieved (270 packages preserved, zerotier validated)
- Remaining work: Epic 2 Phase 2 Stories 2.5, 2.7 (config migration to infra)

---

### Change Proposal #3: Epic 4 Renumbering to Epic 3

**File:** `epic-4-multi-darwin-validation-phase-3-rosegold.md` → `epic-3-multi-darwin-validation-phase-3-rosegold.md`
**Type:** File rename + content updates
**Status:** ✅ APPROVED

**Action:** Rename file, update epic number to 3, update dependencies (now depends on Epic 2)

**Story renumbering:**
- Story 4.1 → Story 3.1: Deploy rosegold and validate functionality
- Story 4.2 → Story 3.2: Validate multi-darwin coordination

---

### Change Proposal #4: Epic 5 Renumbering to Epic 4

**File:** `epic-5-third-darwin-host-phase-4-argentum.md` → `epic-4-third-darwin-host-phase-4-argentum.md`
**Type:** File rename + content updates
**Status:** ✅ APPROVED

**Action:** Rename file, update epic number to 4, update dependencies (now depends on Epic 3)

**Story renumbering:**
- Story 5.1 → Story 4.1: Deploy argentum and validate functionality
- Story 5.2 → Story 4.2: Validate 4-machine network and assess stibnite readiness

---

### Change Proposal #5: Epic 6 Renumbering to Epic 5 (OPTIONAL)

**File:** `epic-6-primary-workstation-migration-phase-5-stibnite.md` → `epic-5-primary-workstation-validation-phase-5-stibnite.md`
**Type:** File rename + content updates (mark as OPTIONAL)
**Status:** ✅ APPROVED (Option A - OPTIONAL epic)

**Action:** Rename file, update epic number to 5, mark as CONDITIONAL/OPTIONAL

**Rationale:** Stibnite config migration complete in Epic 2 Phase 2 (Stories 2.6-2.7), this epic only needed if extended validation period desired

**Story renumbering:**
- Story 6.1-6.3 → Story 5.1: Extended stibnite stability validation [OPTIONAL]

**Decision Point:** Evaluate at Epic 4 completion whether Epic 5 execution needed

---

### Change Proposal #6: Epic 7 Renumbering to Epic 6

**File:** `epic-7-legacy-cleanup-phase-6.md` → `epic-6-legacy-cleanup-phase-6.md`
**Type:** File rename + content updates
**Status:** ✅ APPROVED

**Action:** Rename file, update epic number to 6, update dependencies (now depends on Epic 4 + Epic 5 if executed)

**Story renumbering:**
- Story 7.1 → Story 6.1: Remove nixos-unified infrastructure
- Story 7.2 → Story 6.2: Finalize secrets migration strategy
- Story 7.3 → Story 6.3: Update documentation and finalize migration

---

### Change Proposal #7: Sprint Status YAML Updates

**File:** `docs/notes/development/sprint-status.yaml`
**Type:** Multiple inline edits (7 edit groups)
**Status:** ✅ APPROVED

**Actions:**
1. Update Epic 2 description and story structure (Phase 1-4, Stories 2.1-2.13)
2. Mark Epic 3 as "consolidated"
3. Renumber Epic 4 → Epic 3 (Stories 4.1-4.2 → 3.1-3.2)
4. Renumber Epic 5 → Epic 4 (Stories 5.1-5.2 → 4.1-4.2)
5. Renumber Epic 6 → Epic 5 OPTIONAL (Story 6.1-6.3 → 5.1)
6. Renumber Epic 7 → Epic 6 (Stories 7.1-7.3 → 6.1-6.3)
7. Add course-correction metadata and dependencies

---

### Change Proposal #8: Architecture Documentation Updates

**Files:** 3 architecture documents
**Type:** Minor enhancement updates
**Status:** ✅ APPROVED

**8A: ADR-002 Update** (`architecture/architecture-decision-records-adrs.md`)
- Update: "Use ZFS Unencrypted" → "Use LUKS Encryption (ZFS Encryption Problematic)"
- Evidence: Story 1.5 discovered ZFS encryption bug, LUKS proven reliable

**8B: Darwin Networking Validation** (`architecture/darwin-networking-options.md`)
- Add: Epic 1 Validation Results section
- Content: Story 1.12 validated Option 1 (Homebrew Zerotier), status VALIDATED for production

**8C: Epic Mapping Update** (`architecture/epic-to-architecture-mapping.md`)
- Replace: Complete section with revised epic structure (Epic 1 complete, Epic 2 redefined, Epic 3-6 renumbered)
- Add: Architecture coverage summary with validation status

---

## Section 5: Implementation Handoff

### Change Scope Classification

**MODERATE**

**Rationale:**
- Not "Minor" - affects multiple epics (2-7), requires 11-15h effort
- Not "Major" - no fundamental replan, PRD unchanged, patterns proven
- **Moderate** - Epic realignment + story drafting, backlog reorganization needed

### Handoff Recipients

**Primary: Product Owner (John) / Scrum Master (Bob)**

**Responsibilities:**

1. **Epic 2 Redefinition** (John lead, Bob support) - 6-8 hours
   - Rewrite epic-2.md with revised scope (4 phases)
   - Define 12-15 new stories across phases
   - Establish phase boundaries and dependencies

2. **Epic 3 Consolidation** (Bob lead) - 1 hour
   - Document why Epic 3 merged into Epic 2
   - Update epic-3.md with consolidation notice

3. **Epic 4-7 Renumbering** (Bob lead) - 2-3 hours
   - Rename files (epic-4 → epic-3, etc.)
   - Update internal references and dependencies
   - Update sprint-status.yaml with new epic numbering

4. **Backlog Reorganization** (John lead, Bob support) - 2 hours
   - Update sprint-status.yaml with Epic 2 new story IDs
   - Ensure Epic 2 stories in correct sequence
   - Mark Epic 3 stories as obsolete/merged

**Secondary: Solution Architect (Winston)**

**Responsibilities:**

1. **Architecture Documentation Review** (Action Item #1) - 2-3 hours
   - Verify all Epic 1 patterns documented in architecture/
   - Update ADR-002 (ZFS → LUKS)
   - Update darwin-networking-options.md (Option 1 validated)
   - Update epic-to-architecture-mapping.md

2. **Technical Guidance** - 1-2 hours
   - Review Epic 2 story definitions for technical accuracy
   - Ensure "rip the band-aid" approach properly specified
   - Validate file mapping (test-clan → infra)

**Tertiary: Development Team (Amelia)**

**Responsibilities:**

1. **Await Epic 2 Story Drafting**
   - No action until Epic 2 Phase 1 stories drafted
   - Prepare for "rip the band-aid" execution approach
   - Review test-clan patterns documentation

2. **Early Epic 2 Stories** (when drafted)
   - Story 2.1: "Identify infra-specific components to preserve"
   - Story 2.2: "Stibnite vs blackphos configuration diff analysis"

### Handoff Timeline

- **Week 1:** PO/SM epic restructuring + Architect docs review (parallel)
- **Week 2:** PO/SM story drafting + Architect technical review
- **Week 3+:** Dev team Epic 2 execution begins

### Success Criteria

- ✅ Epic 2 redefined with clear 4-phase structure
- ✅ 12-15 stories drafted with acceptance criteria
- ✅ Epic 3 consolidation documented
- ✅ Epic 4-7 renumbered with updated dependencies
- ✅ Architecture docs updated with Epic 1 patterns
- ✅ Sprint-status.yaml reflects new epic structure
- ✅ "Rip the band-aid" approach clearly specified in stories
- ✅ Handoff to dev team smooth (clear story definitions, no ambiguity)

---

## Section 6: PRD MVP Impact and Action Plan

### PRD MVP Impact

**Is MVP affected?** ✅ NO - MVP more achievable, potentially faster

**PRD MVP remains:**
> "Complete 6-phase migration delivering fully operational dendritic + clan infrastructure across all 5 machines with type safety improvements, multi-machine coordination, and validated architectural patterns"

**Impact Assessment:**

**Positive impacts:**
1. **Timeline acceleration:** Original estimate 15-18 weeks, "Rip the band-aid" could save 2-4 weeks
2. **Lower risk:** Proven patterns reduce implementation uncertainty
3. **Higher confidence:** 7/7 patterns HIGH confidence, zero critical blockers

**Neutral impacts:**
1. **Scope unchanged:** Still migrating 5 machines (cinnabar, electrum, blackphos, stibnite, rosegold, argentum)
2. **Work volume similar:** Epic 2-6 still ~200+ hours

**No negative impacts identified**

### High-Level Action Plan

**Phase 1: Epic Restructuring** (Week 1, 11-15 hours)
- Task 1.1: Redefine Epic 2 with 4 phases (6-8h) - PO/SM
- Task 1.2: Document Epic 3 consolidation rationale (1h) - SM
- Task 1.3: Renumber Epic 4-7 and update dependencies (2-3h) - SM
- Task 1.4: Update sprint-status.yaml and architecture docs (2-3h) - SM + Architect

**Phase 2: Epic 2 Story Drafting** (Week 2, 8-12 hours)
- Task 2.1: Draft Epic 2 Phase 1 stories (home-manager foundation, 3-4 stories) - PO
- Task 2.2: Draft Epic 2 Phase 2 stories (blackphos + stibnite, 4-5 stories) - PO
- Task 2.3: Draft Epic 2 Phase 3 stories (cinnabar + electrum config migration, 2-3 stories) - PO
- Task 2.4: Draft Epic 2 Phase 4 stories (rosegold + argentum creation, 3-4 stories) - PO

**Phase 3: Epic 2 Execution** (Weeks 3-6, 80-120 hours)
- Execute 12-15 stories across 4 phases
- Apply "rip the band-aid" approach (`cp` from test-clan → infra on `clan-01` branch)
- Validate at each phase boundary

**Dependencies:**
- ✅ Epic 1 complete (all dependencies satisfied)
- ⚠️ Architecture docs review (Action Item #1, before Epic 2 starts)
- ⚠️ Course-correction complete (this workflow, Action Item #2)

**Major Milestones:**
1. Week 1: Epic restructuring complete
2. Week 2: Epic 2 stories drafted
3. Week 3-4: Epic 2 Phase 1-2 complete (home-manager + darwin workstations)
4. Week 5: Epic 2 Phase 3 complete (VPS config migration)
5. Week 6: Epic 2 Phase 4 complete (future machines)
6. Week 7+: Epic 3-6 (rosegold, argentum deployment + validation)

---

## Appendices

### Appendix A: Epic 1 Retrospective Key Findings

**Reference:** `docs/notes/development/epic-1-retro-2025-11-20.md`

**Epic 1 Delivery Metrics:**
- Completed: 21/22 stories (95.5%)
- Deferred: 1 story (Story 1.11 - evidence-based deferral)
- Duration: 3+ weeks
- Investment: 60-80 hours
- Blockers: 0 CRITICAL, 0 MAJOR, 1 MINOR (zerotier darwin homebrew dependency with workaround)

**Epic 1 Quality Metrics:**
- Pattern Confidence: 7/7 patterns HIGH confidence
- Test Coverage: 18 tests passing (zero regressions)
- Documentation: 3,000+ lines (guides, architecture patterns, migration checklists)
- GO Decision Criteria: 7/7 PASS (100% validation success)

**Epic 1 Key Learnings:**
1. Story 1.10 scope explosion (1 → 9 stories) - Pre-migration configuration audit prevents scope surprise
2. Zero-regression principle maintained across all 21 stories - Test-driven migration reduces risk
3. Opportunistic improvements during migration - LazyVim-nix, catppuccin-nix, nix-ai-tools, two-tier secrets
4. "Rip the band-aid" philosophy - Fast and pragmatic > slow and careful

### Appendix B: "Rip the Band-Aid" Migration Strategy

**Approach:**
1. Create fresh git branch `clan-01` in infra repository
2. Use `cp` command to copy relevant files from test-clan → infra (filesystem operations, not LLM processing)
3. Only THEN modify/refactor additional files as needed

**Preserve from infra:**
- GitHub Actions CI/CD workflows
- TypeScript monorepo (docs website at docs.cameronraysmith.com)
- Cloudflare deployment setup

**Replace from test-clan:**
- All nix configurations (flake.nix, modules/, hosts/, home-manager/)

**Philosophy:**
- Don't get bogged down reading/mutating every file individually
- Take modular "replace" approach
- Trust git branch/diff/history to catch anything clobbered
- Fast and pragmatic > slow and careful
- Epic 1 was discovery/validation, Epic 2 is application of proven patterns

**Safety Net:**
- Git branch isolation (`clan-01`)
- Can abandon branch if issues discovered
- Original configurations preserved in git history
- Rollback to infra main branch if needed

### Appendix C: Reference Documents

**Epic 1 Outputs:**
- Epic 1 retrospective: `docs/notes/development/epic-1-retro-2025-11-20.md`
- Test-clan patterns: `~/projects/nix-workspace/test-clan/docs/guides/`
- Test-clan architecture: `~/projects/nix-workspace/test-clan/docs/notes/development/test-clan-validated-architecture.md`

**PRD:**
- PRD index: `docs/notes/development/PRD/index.md`
- Functional requirements: `docs/notes/development/PRD/functional-requirements.md`
- Success criteria: `docs/notes/development/PRD/success-criteria.md`

**Architecture:**
- Architecture index: `docs/notes/development/architecture/index.md`
- Architectural decisions: `docs/notes/development/architecture/architectural-decisions.md`
- ADRs: `docs/notes/development/architecture/architecture-decision-records-adrs.md`

**Epics:**
- Epics index: `docs/notes/development/epics/index.md`
- Epic 2 (current): `docs/notes/development/epics/epic-2-vps-infrastructure-foundation-phase-1-cinnabar.md`
- Sprint status: `docs/notes/development/sprint-status.yaml`

---

## Approval Record

**Date:** 2025-11-20
**Approved By:** Dev (Primary Stakeholder)
**Approval Status:** APPROVED
**Next Steps:** Execute handoff plan (Week 1: Epic restructuring, Week 2: Story drafting)

**Course-Correction Workflow Execution:**
- Workflow: `/bmad:bmm:workflows:correct-course`
- Duration: ~4 hours (as estimated in Epic 1 retrospective Action Item #2)
- Outcome: Sprint Change Proposal complete and approved

---

**Document Status:** FINAL
**Last Updated:** 2025-11-20
**Next Review:** Epic 2 Phase 1 completion
