# Sprint Change Proposal: Story Sequencing Adjustment for Test Harness + Dendritic Refactoring

**Date:** 2025-11-05
**Project:** infra
**Epic:** Epic 1 - Architectural Validation + Infrastructure Deployment (Phase 0)
**Change Scope:** Moderate (backlog reorganization, story injection/renumbering)
**Execution Mode:** Incremental (approved changes refined collaboratively)

---

## Section 1: Issue Summary

### Problem Statement

Story 1.2 (architectural evaluation) was completed successfully with Outcome A (Already Compliant - no immediate refactoring needed). During completion, a comprehensive test strategy document was created (docs/notes/development/dendritic-refactor-test-strategy.md) that enables risk-free dendritic refactoring when/if needed.

User has determined that implementing the test harness and executing the dendritic refactoring should happen NOW (during Epic 1) rather than being deferred. This requires injecting two new stories between current 1.5 and 1.6.

### Discovery Context

- **When:** Story 1.2 completion (2025-11-05)
- **How:** Architectural assessment revealed test-clan is pragmatically compliant but has specific non-compliance areas (module discovery, namespace exports, self-composition) that could be addressed
- **Evidence:**
  - Story 1.2 completed with Outcome A documented in work-items/1-2-implement-dendritic-flake-parts-pattern-in-test-clan.md
  - Comprehensive test strategy created at docs/notes/development/dendritic-refactor-test-strategy.md
  - Non-compliance areas identified in docs/notes/development/dendritic-flake-parts-assessment.md
  - Operational VMs from Story 1.5 provide test targets

### Issue Classification

**Type:** Strategic pivot/opportunity identification

**Trigger:** Story 1.2 evaluation revealed opportunity to implement test infrastructure + refactoring during Phase 0 rather than defer to future epic.

---

## Section 2: Impact Analysis

### Epic Impact

**Epic 1 (Architectural Validation + Infrastructure Deployment):**
- **Scope Change:** Expand from 12 stories to 14 stories (+2 injected)
- **Objective Enhancement:** Add "pattern validation" to existing "architectural validation + infrastructure deployment"
- **Timeline Impact:** +2-3 days (~14-18 hours for both new stories)
- **Modifications:**
  - INSERT Story 1.6: Test harness implementation (6-8 hours)
  - INSERT Story 1.7: Dendritic refactoring execution (8-10 hours)
  - RENUMBER Stories 1.6-1.12 → 1.8-1.14

**Other Epics (2-7):**
- **Impact:** Zero direct impact
- **Benefits:** Validated dendritic patterns reduce technical debt, provide proven template for Phase 1+ implementations

### Story Impact

**Current Stories Affected:**
- Story 1.2: Status change from "review" → "done" (evaluation complete)
- Stories 1.6-1.12: Renumber to 1.8-1.14 (shift by +2)

**New Stories Added:**
- Story 1.6: "Implement comprehensive test harness for test-clan infrastructure validation"
  - Dependencies: Story 1.5 (operational VMs)
  - Effort: 6-8 hours
  - Status: Drafted

- Story 1.7: "Execute dendritic flake-parts refactoring in test-clan using test harness"
  - Dependencies: Story 1.6 (test harness operational)
  - Effort: 8-10 hours
  - Status: Drafted

**Story Sequencing:**
- Stories 1.1-1.5: Complete (infrastructure deployed) ✅
- NEW 1.6: Test harness (enables confident refactoring)
- NEW 1.7: Dendritic refactoring (leverages test harness)
- Stories 1.8-1.14: GCP deployment + stability validation (continue as planned)

### Artifact Conflicts

**PRD:** No conflicts (MVP scope unchanged)

**Architecture:** No conflicts (assessment already complete, test strategy provides implementation architecture)

**UI/UX:** N/A (infrastructure project)

**Other Documents:**
- ✅ sprint-status.yaml: Update required (inject stories, renumber, status changes)
- ✅ epics.md: Update required (inject story descriptions, update summary stats)
- ✅ Story files: Create new 1.6 and 1.7 markdown files
- ✅ Comments/references: Update stability gate references in sprint-status.yaml

### Technical Impact

**Code Changes:** None (stories not yet implemented)

**Infrastructure:** No impact on deployed VMs (162.55.175.87, 49.13.140.183) until explicitly updated after Story 1.7 completion

**Deployment:** No deployment changes required

---

## Section 3: Recommended Approach

### Selected Path: Direct Adjustment (Option 1)

**Approach:** Modify existing backlog by injecting two new stories and renumbering subsequent stories within Epic 1.

**Rationale:**
1. Story 1.2 evaluation already complete (Outcome A documented)
2. Test strategy provides clear, low-risk implementation path
3. Test harness (Story 1.6) enables confident refactoring without operational risk
4. Dendritic refactoring (Story 1.7) validates architectural pattern during Phase 0
5. Epic 1 scope expansion logical: infrastructure deployment + pattern validation
6. Benefits Epic 2+: validated patterns reduce future technical debt
7. Operational VMs (Story 1.5) protected by test-driven approach

**Alternatives Considered:**

**Option 2: Potential Rollback**
- Status: Not viable
- Reason: No completed work needs rollback; Story 1.2 completed successfully

**Option 3: PRD MVP Review**
- Status: Not needed
- Reason: MVP scope unchanged; Epic 1 expansion is additive value

### Effort and Timeline Impact

**Additional Effort:**
- Story 1.6 (test harness): 6-8 hours
- Story 1.7 (dendritic refactoring): 8-10 hours
- **Total:** 14-18 hours additional effort

**Timeline Impact:**
- Epic 1 timeline extends by approximately 2-3 days (if working sequentially)
- Zero impact on Epic 2+ timeline
- Benefits: Comprehensive test infrastructure + validated dendritic patterns

### Risk Assessment

**Overall Risk Level:** Low

**Risk Factors:**
1. **Operational VM Safety:** Test harness validates changes before deployment (LOW RISK)
2. **Test Implementation Complexity:** Well-documented strategy with clear steps (LOW RISK)
3. **Refactoring Risk:** Incremental approach with per-step validation (LOW RISK)
4. **Timeline Extension:** Manageable +2-3 days within Phase 0 buffer (LOW RISK)

**Risk Mitigation:**
- Test-driven refactoring approach ensures zero regression
- Git feature branch workflow provides rollback capability
- Operational VMs protected (no deployment until validation complete)
- Incremental validation at each refactoring step

---

## Section 4: Detailed Change Proposals

### Change 1: Update Story 1.2 Status

**File:** `docs/notes/development/sprint-status.yaml`
**Location:** Line 70

**Change:**
```yaml
OLD: 1-2-implement-dendritic-flake-parts-pattern-in-test-clan: review
NEW: 1-2-implement-dendritic-flake-parts-pattern-in-test-clan: done
```

**Justification:** Story 1.2 completed evaluation objective successfully (Outcome A), test strategy documented, acceptance criteria satisfied.

---

### Change 2: Inject Story 1.6 Entry

**File:** `docs/notes/development/sprint-status.yaml`
**Location:** After line 76

**Change:**
```yaml
INSERT: 1-6-implement-comprehensive-test-harness-for-test-clan: drafted
```

**Justification:** New story positioned after infrastructure deployment (Story 1.5) which provides operational VMs as test targets.

---

### Change 3: Inject Story 1.7 Entry

**File:** `docs/notes/development/sprint-status.yaml`
**Location:** After new Story 1.6

**Change:**
```yaml
INSERT: 1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness: drafted
```

**Justification:** New story positioned after Story 1.6 (test harness must be operational before refactoring begins).

---

### Change 4: Renumber Stories 1.6-1.12 → 1.8-1.14

**File:** `docs/notes/development/sprint-status.yaml`
**Location:** Lines 77-84

**Change:**
```yaml
OLD:
  1-6-validate-clan-secrets-vars-on-hetzner: drafted
  # Story 1.7: REQUIRES MANUAL SECRET SETUP...
  1-7-create-gcp-terraform-config-and-host-modules: drafted
  1-8-deploy-gcp-vm-and-validate-multi-cloud: drafted
  1-9-test-multi-machine-coordination: drafted
  1-10-monitor-stability-for-one-week: drafted
  1-11-document-integration-findings-and-patterns: drafted
  1-12-execute-go-no-go-decision-framework: drafted

NEW:
  1-8-validate-clan-secrets-vars-on-hetzner: drafted
  # Story 1.9: REQUIRES MANUAL SECRET SETUP...
  1-9-create-gcp-terraform-config-and-host-modules: drafted
  1-10-deploy-gcp-vm-and-validate-multi-cloud: drafted
  1-11-test-multi-machine-coordination: drafted
  1-12-monitor-stability-for-one-week: drafted
  1-13-document-integration-findings-and-patterns: drafted
  1-14-execute-go-no-go-decision-framework: drafted
```

**Justification:** All stories after new 1.6 and 1.7 shift by +2 to accommodate injected stories.

---

### Change 5: Update Stability Gate References

**File:** `docs/notes/development/sprint-status.yaml`
**Location:** Lines 44, 49

**Change:**
```yaml
OLD:
# - Epic 1 (Story 1.12): GO/CONDITIONAL GO/NO-GO decision...
# - Epic 1 (Story 1.10): Infrastructure stable 1 week minimum...

NEW:
# - Epic 1 (Story 1.14): GO/CONDITIONAL GO/NO-GO decision...
# - Epic 1 (Story 1.12): Infrastructure stable 1 week minimum...
```

**Justification:** Stability gate references must reflect renumbered story IDs for accurate cross-referencing.

---

### Change 6: Update Strategic Decision Comment

**File:** `docs/notes/development/sprint-status.yaml`
**Location:** Lines 64-66

**Change:**
```yaml
OLD:
  # Strategic decision (2025-11-03): Infrastructure-first approach - defer Story 1.2 (dendritic)
  # Rationale: Infrastructure deployment is primary objective, dendritic pattern can be refactored later
  # Flow: 1.1 (complete) → 1.3 (inventory) → 1.4-1.8 (infrastructure) → 1.2 (dendritic if time)

NEW:
  # Strategic decision (2025-11-05): Story 1.2 complete (Outcome A) - implement test harness + dendritic refactoring NOW
  # Rationale: Test strategy enables risk-free refactoring, validates architecture during Phase 0, benefits Epic 2+
  # Flow: 1.1-1.5 (complete) → 1.6 (test harness) → 1.7 (dendritic refactor) → 1.8-1.14 (GCP + validation)
```

**Justification:** Update strategic decision to reflect new approach and story sequence.

---

### Change 7: Create Story 1.6 File

**File:** `docs/notes/development/work-items/1-6-implement-comprehensive-test-harness-for-test-clan.md` (NEW)

**Content:** Comprehensive story markdown for test harness implementation with:
- Full acceptance criteria (6 ACs covering test infrastructure, regression tests, invariant tests, feature tests, integration tests, baseline snapshots)
- Implementation tasks (6 tasks with time estimates)
- Technical notes (test categories, reusability context)
- Definition of done

**Justification:** Story file provides complete implementation guidance based on dendritic-refactor-test-strategy.md.

---

### Change 8: Create Story 1.7 File

**File:** `docs/notes/development/work-items/1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md` (NEW)

**Content:** Comprehensive story markdown for dendritic refactoring with:
- Full acceptance criteria (6 ACs covering regression tests, invariant tests, feature tests, integration tests, refactoring steps, git workflow)
- Implementation tasks (6 tasks following test strategy Phase 2: steps 2.1-2.5 plus validation)
- Technical notes (references dendritic-flake-parts-assessment.md for non-compliance gaps, test strategy for validation)
- Risk mitigation (operational VM protection, git safety, rollback plan)
- Definition of done

**Justification:** Story file addresses specific non-compliance areas from assessment while using test harness for zero-regression validation.

---

### Change 9: Update epics.md

**File:** `docs/notes/development/epics.md`
**Locations:** Lines 184-359 (Epic 1 stories), Line 973 (total stories), Line 977 (Epic 1 count)

**Changes:**
1. INSERT Story 1.6 description after Story 1.5 (line 181)
2. INSERT Story 1.7 description after new Story 1.6
3. RENUMBER Story sections: 1.6→1.8, 1.7→1.9, 1.8→1.10, 1.9→1.11, 1.10→1.12, 1.11→1.13, 1.12→1.14
4. UPDATE prerequisites in renumbered stories
5. UPDATE summary: "Total Stories: 36 stories" (was 34)
6. UPDATE Epic 1 count: "14 stories" (was 12)

**Justification:** Epics.md must stay synchronized with sprint-status.yaml and individual story files.

---

## Section 5: Implementation Handoff

### Change Scope Classification

**Scope:** Moderate - Backlog reorganization, story injection/renumbering

**Complexity:** Medium effort (file edits + story creation)

**Impact:** Epic 1 scope expansion, zero impact on Epic 2+

### Handoff Recipients

**Primary:** Development team (story implementation)

**Supporting:** Product Owner/Scrum Master (backlog management)

**Responsibilities:**

**Development Team:**
1. Implement Story 1.6 (test harness) per acceptance criteria
2. Validate all baseline tests pass before proceeding
3. Implement Story 1.7 (dendritic refactoring) incrementally with test validation
4. Follow git workflow (feature branch, per-step commits)
5. Protect operational VMs (no deployment until validation complete)

**Product Owner/Scrum Master:**
1. Update sprint tracking documents (sprint-status.yaml, epics.md)
2. Create story files (1-6-implement-comprehensive-test-harness-for-test-clan.md, 1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md)
3. Monitor Epic 1 timeline adjustment (+2-3 days)
4. Ensure stakeholder awareness of scope expansion

### Success Criteria

**Story 1.6 (Test Harness):**
- ✅ Test infrastructure operational (nix-unit, test directories, test runner)
- ✅ All regression tests passing with baseline snapshots captured
- ✅ All invariant tests passing (clan-core integration validated)
- ✅ Feature tests implemented and failing as expected
- ✅ Integration tests passing (VMs boot and work)

**Story 1.7 (Dendritic Refactoring):**
- ✅ All refactoring steps completed with test validation
- ✅ ALL tests passing (regression, invariant, feature, integration)
- ✅ Terraform output equivalent to baseline
- ✅ Zero regressions confirmed
- ✅ Git workflow complete (feature branch merged to main)
- ✅ Operational VMs protected

**Document Updates:**
- ✅ sprint-status.yaml updated with all changes
- ✅ epics.md updated with new stories and counts
- ✅ Story files created and committed
- ✅ All references synchronized

### Next Steps

1. **Immediate:** Update sprint-status.yaml (Changes 1-6)
2. **Immediate:** Create story files (Changes 7-8)
3. **Immediate:** Update epics.md (Change 9)
4. **Next Session:** Begin Story 1.6 implementation (test harness)
5. **Following Session:** Begin Story 1.7 implementation (dendritic refactoring)
6. **After Completion:** Continue with Story 1.8 (secrets validation on Hetzner)

---

## Section 6: Approval and Sign-off

### User Approval

**Status:** ✅ APPROVED (2025-11-05)

**Approval Mode:** Incremental - All 9 change proposals reviewed and approved individually

**Approved Changes:**
1. ✅ Story 1.2 status change (review → done)
2. ✅ Inject Story 1.6 entry
3. ✅ Inject Story 1.7 entry
4. ✅ Renumber stories 1.6-1.12 → 1.8-1.14
5. ✅ Update stability gate references
6. ✅ Update strategic decision comment
7. ✅ Create 1-6-implement-comprehensive-test-harness-for-test-clan.md file
8. ✅ Create 1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md file
9. ✅ Update epics.md with new stories

### Implementation Authorization

**Authorization:** User approved all changes for implementation

**Implementation Method:** Scrum Master / Product Owner will execute document updates

**Timeline:** Immediate (documentation updates), then Story 1.6 implementation

---

## Appendix A: Change Summary

### Files Modified

1. `docs/notes/development/sprint-status.yaml`
   - Story 1.2: status change
   - Stories: inject 1.6, 1.7
   - Stories: renumber 1.6-1.12 → 1.8-1.14
   - Comments: update stability gates, strategic decision

2. `docs/notes/development/epics.md`
   - Epic 1: insert Story 1.6, 1.7 descriptions
   - Epic 1: renumber stories 1.6-1.12 → 1.8-1.14
   - Summary: update story counts (12→14, 34→36)

### Files Created

1. `docs/notes/development/work-items/1-6-implement-comprehensive-test-harness-for-test-clan.md`
   - Test harness implementation story
   - 6 acceptance criteria, 6 tasks, technical notes

2. `docs/notes/development/work-items/1-7-execute-dendritic-refactoring-in-test-clan-using-test-harness.md`
   - Dendritic refactoring story
   - 6 acceptance criteria, 6 tasks, risk mitigation, technical notes

### Epic 1 Impact Summary

**Before:** 12 stories, ~3-4 weeks timeline
**After:** 14 stories, ~3.5-4.5 weeks timeline (+2-3 days)

**Story Sequence:**
- 1.1-1.5: Complete (infrastructure deployed) ✅
- **1.6: NEW - Test harness (6-8 hours)**
- **1.7: NEW - Dendritic refactoring (8-10 hours)**
- 1.8-1.14: GCP + stability validation (renumbered from 1.6-1.12)

**Benefits:**
- Comprehensive test infrastructure for ongoing validation
- Validated dendritic patterns for Epic 2+
- Reduced technical debt
- Zero-regression confidence for future changes

---

**Document Version:** 1.0
**Generated:** 2025-11-05
**Workflow:** correct-course (Sprint Change Management)
**Project:** infra (nix-config infrastructure migration)
