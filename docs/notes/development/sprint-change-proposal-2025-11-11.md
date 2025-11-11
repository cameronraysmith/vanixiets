---
title: "Sprint Change Proposal - Epic 1 Scope Adjustment"
date: 2025-11-11
project: infra
epic: Epic 1 (Phase 0)
status: pending-approval
---

# Sprint Change Proposal: Epic 1 Scope Adjustment for Darwin Migration Rehearsal

## Executive Summary

**Change Trigger:** Epic 1 validation (Stories 1.1-1.7) successfully proved dendritic flake-parts + clan architecture works for nixos VMs. However, infra's production workload consists primarily of nix-darwin machines (4 darwin laptops + 1 nixos VPS). The current plan (Stories 1.8-1.12) focused on GCP deployment, which doesn't address the critical validation gap: proving the architecture works for darwin hosts and documenting the nixos-unified → dendritic + clan transformation pattern.

**Recommended Approach:** Direct Adjustment - Remove GCP-focused Stories 1.8-1.12 and replace with darwin migration rehearsal Stories 1.8-1.10, providing higher strategic value for production refactoring.

**Impact:** Net reduction of ~1 week in Epic 1 duration while dramatically increasing validation quality and confidence for Epic 2+ production refactoring.

**Change Scope:** Minor to Moderate - Documentation updates only, no code changes required yet.

---

## Section 1: Issue Summary

### Problem Statement

Epic 1 validation (Stories 1.1-1.7) successfully proved dendritic flake-parts + clan architecture works for nixos VMs with Hetzner deployment.
However, infra's actual production workload consists primarily of nix-darwin machines (4 darwin laptops + 1 nixos VPS).
To confidently refactor infra from nixos-unified to dendritic + clan, we need to validate the architecture handles nix-darwin hosts, home-manager configurations, and zerotier networking across heterogeneous machines.

### Discovery Context

After completing Stories 1.1-1.7 in test-clan and seeing successful results, we recognized that proceeding with GCP deployment (Stories 1.8-1.12) would validate multi-cloud nixos coordination but wouldn't address the critical gap: proving the architecture works for the darwin machines that comprise 80% of infra's actual fleet.

The key insight: **test-clan should serve as a migration rehearsal environment**, where we convert one real production machine (blackphos) from infra's nixos-unified pattern to test-clan's dendritic + clan pattern, documenting the complete transformation process as a blueprint for Epic 2+ production refactoring.

### Supporting Evidence

- test-clan currently has 2 Hetzner nixos VMs operational (Stories 1.1-1.7 complete)
- infra repo CLAUDE.md documents primary fleet: stibnite, blackphos, argentum, rosegold (all nix-darwin) + cinnabar (nixos VPS)
- Current Epic 1 Stories 1.8-1.12 focus on GCP deployment (multi-cloud nixos validation)
- Epic 2+ plan to migrate darwin hosts, but architecture not yet proven for darwin
- No documented transformation pattern for converting nixos-unified configs to dendritic + clan

---

## Section 2: Impact Analysis

### Epic Impact

**Epic 1 (Current):**
- **Scope modification:** Extend validation from "nixos VMs only" to "nixos VMs + nix-darwin + heterogeneous networking"
- **Strategic shift:** Transform from "infrastructure deployment validation" to "infrastructure deployment + migration pattern rehearsal"
- **Story changes:** Remove Stories 1.8-1.12 (GCP focus), add Stories 1.8-1.10 (darwin migration rehearsal), renumber 1.13-1.14 to 1.11-1.12
- **Timeline impact:** Net reduction of ~1 week (remove 2-3 weeks GCP work, add ~1-2 weeks darwin work)
- **Success criteria expansion:** Must include "darwin migration pattern validated" and "nixos-unified → dendritic + clan transformation documented"

**Epic 2+ (Future):**
- **Dependencies validated:** Darwin migration patterns proven in Epic 1, reducing risk for Epics 3-6
- **Confidence increased:** Migration rehearsal provides concrete patterns for production refactoring
- **Timeline potentially shortened:** Clear transformation pattern may accelerate Epic 3-6 execution

### Artifact Conflicts and Required Updates

**1. docs/notes/development/epics.md:**
- Epic 1 goal statement: Expand to include darwin validation and migration rehearsal
- Epic 1 success criteria: Add darwin and transformation pattern validation
- Epic 1 story list: Remove 1.8-1.12, add new 1.8-1.10, renumber 1.13-1.14 to 1.11-1.12
- Story 1.8-1.10: Write complete new story definitions with acceptance criteria
- Story 1.11-1.12: Update references/prerequisites to reflect new numbering
- Summary statistics: Update total story count (36 → 34) and Epic 1 count (14 → 12)

**2. docs/notes/development/sprint-status.yaml:**
- Lines 83-92: Remove story entries 1.8-1.12 (old GCP-focused stories)
- Add new story entries: 1.8 (blackphos migration), 1.9 (VM rename + zerotier), 1.10 (heterogeneous networking)
- Renumber: 1.13→1.11, 1.14→1.12
- Update status comments to reflect new validation scope

**3. docs/notes/development/work-items/:**
- Already deleted: 1-8-validate-clan-secrets-vars-on-hetzner.md and .context.xml (completed by user prior to this workflow)
- No other existing story files to modify (1.9-1.14 not yet created)

**4. No changes required to:**
- infra CLAUDE.md (already documents fleet correctly)
- test-clan repository (code changes happen during story implementation)
- PRD or other strategic documents (no formal PRD exists)

---

## Section 3: Recommended Approach

### Selected Path: Direct Adjustment (Option 1) with Scope Optimization

**Justification:**

**Technical Merit:**
- Completed work (Stories 1.1-1.7) remains valuable and provides foundation
- New stories address actual validation gap (nix-darwin + heterogeneous networking)
- Migration rehearsal approach validates BOTH architecture AND transformation process
- Test harness (Story 1.6) provides regression safety for continued experimentation

**Strategic Value:**
- Converts test-clan from "toy validation environment" to "production migration rehearsal"
- Documents exact transformation pattern: nixos-unified → dendritic + clan
- Provides reusable blueprint for migrating remaining 4 machines in Epic 3-6
- Reduces risk for Epic 2+ by proving all critical patterns in Epic 1

**Timeline Impact:**
- **Removed:** GCP deployment (~1 week), multi-cloud coordination (~3-4 days), 1-week stability monitoring
- **Added:** Blackphos migration (~1-2 weeks including investigation, transformation, validation)
- **Net impact:** ~1 week reduction in Epic 1 duration, higher validation quality

**Risk Assessment:**
- **Low technical risk:** Additive changes, test harness provides safety net
- **High strategic value:** Proves complete pattern before production commitment
- **Acceptable timeline trade:** Slight Epic 1 extension dramatically reduces Epic 2+ risk

**Trade-offs Considered:**
- **Foregone:** Multi-cloud validation (Hetzner + GCP), extended stability monitoring
- **Accepted rationale:** GCP adds complexity without addressing core validation gap; darwin migration rehearsal provides more strategic value than extended nixos stability monitoring

---

## Section 4: Detailed Change Proposals

### Change 1: Update Epic 1 Goal and Strategic Value

**File:** `docs/notes/development/epics.md`
**Section:** Epic 1 header (lines ~36-53)

**Before:**
```markdown
## Epic 1: Architectural Validation + Infrastructure Deployment (Phase 0)

**Goal:** Deploy Hetzner + GCP VMs using clan-infra's proven terranix pattern, with dendritic as optional optimization

**Strategic Value:** Validates complete stack (terraform + clan + infrastructure) on real VMs before darwin migration, following proven patterns from clan-infra, de-risking deployment with real infrastructure experience

**Timeline:** 3-4 weeks (2-3 weeks deployment + 1 week stability validation)

**Success Criteria:**
- Hetzner VM deployed and operational (minimum requirement)
- GCP VM deployed and operational (optimal, can defer if complex)
- Multi-machine coordination working via clan inventory and zerotier
- 1 week stability validation minimum
- Infrastructure patterns documented for Phase 1
- GO/CONDITIONAL GO/NO-GO decision made with explicit rationale
```

**After:**
```markdown
## Epic 1: Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Goal:** Validate dendritic flake-parts + clan architecture for both nixos VMs and nix-darwin hosts, and document nixos-unified → dendritic + clan transformation pattern through blackphos migration rehearsal

**Strategic Value:** Validates complete stack (dendritic + clan + terraform + infrastructure) on real VMs and darwin machines before production refactoring, proves both target architecture AND transformation process, provides reusable migration blueprint for Epic 2+ by rehearsing complete nixos-unified → dendritic + clan conversion

**Timeline:** 3-4 weeks (2 weeks nixos validation complete + 1-2 weeks darwin migration rehearsal)

**Success Criteria:**
- Hetzner VMs deployed and operational (minimum requirement achieved)
- Dendritic flake-parts pattern proven with zero regressions (achieved via Stories 1.6-1.7)
- Nix-darwin machine (blackphos) migrated from infra to test-clan management
- Heterogeneous zerotier network operational (nixos VMs + nix-darwin host)
- Nixos-unified → dendritic + clan transformation pattern documented
- Migration patterns documented for production refactoring in Epic 2+
- GO/CONDITIONAL GO/NO-GO decision made with explicit rationale
```

---

### Change 2: Remove Stories 1.8-1.12 from epics.md

**File:** `docs/notes/development/epics.md`
**Section:** Stories 1.8-1.12 (lines ~236-364)

**Action:** Delete entire section (Stories 1.8-1.12) containing:
- Story 1.8: Initialize clan secrets and test vars deployment on Hetzner
- Story 1.9: Create GCP VM terraform configuration and host modules
- Story 1.10: Deploy GCP VM and validate multi-cloud infrastructure
- Story 1.11: Test multi-machine coordination across Hetzner + GCP
- Story 1.12: Monitor infrastructure stability and extract deployment patterns

**Rationale:** These stories focus on GCP deployment and extended stability monitoring, which don't address the critical validation gap (nix-darwin + transformation pattern). Removing them streamlines Epic 1 to focus on higher-value darwin migration rehearsal.

---

### Change 3: Add New Story 1.8 (Blackphos Migration Rehearsal)

**File:** `docs/notes/development/epics.md`
**Section:** After Story 1.7 (insert at line ~234)

**Content:**
```markdown
### Story 1.8: Migrate blackphos from infra to test-clan management

As a system administrator,
I want to migrate blackphos nix-darwin configuration from infra's nixos-unified pattern to test-clan's dendritic + clan pattern,
So that I can validate the complete transformation process and document the migration pattern for refactoring infra in Epic 2+.

**Acceptance Criteria:**
1. Blackphos configuration migrated from infra to test-clan: Nix-darwin host configuration created in modules/hosts/blackphos/, Home-manager user configuration (crs58) migrated and functional, All existing functionality preserved (packages, services, shell config)
2. Configuration uses dendritic flake-parts pattern: Module imports via config.flake.modules namespace, Proper module organization (darwin base, homeManager, host-specific), Reference clan-core home-manager integration patterns, Reference dendritic flake-parts home-manager usage from examples in CLAUDE.md (clan-infra, qubasa-clan-infra, mic92-clan-dotfiles, dendrix-dendritic-nix, gaetanlepage-dendritic-nix-config)
3. Blackphos added to clan inventory: tags = ["darwin" "workstation" "backup"], machineClass = "darwin"
4. Clan secrets/vars configured for blackphos: Age key for user crs58 added to admins group, SSH host keys generated via clan vars, User secrets configured if needed
5. Configuration builds successfully: `nix build .#darwinConfigurations.blackphos.system`
6. Transformation documented if needed: nixos-unified-to-clan-migration.md created (if valuable) documenting step-by-step conversion process, Module organization patterns (what goes where), Secrets migration approach (sops-nix → clan vars), Common issues and solutions discovered
7. Package list comparison: Pre-migration vs post-migration packages identical (zero-regression validation)

**Prerequisites:** Story 1.7 (dendritic refactoring complete)

**Estimated Effort:** 6-8 hours (investigation + transformation + documentation)

**Risk Level:** Medium (converting real production machine, but not deploying yet)

**Strategic Value:** Provides concrete migration pattern for refactoring all 4 other machines in infra during Epic 2+

---
```

---

### Change 4: Add New Story 1.9 (Rename VMs and Establish Zerotier)

**File:** `docs/notes/development/epics.md`
**Section:** After Story 1.8 (new)

**Content:**
```markdown
### Story 1.9: Rename Hetzner VMs to cinnabar/electrum and establish zerotier network

As a system administrator,
I want to rename the test Hetzner VMs to their intended production names (cinnabar and electrum) and establish a zerotier network between them,
So that the test-clan infrastructure mirrors the production topology that will be deployed in Epic 2+.

**Acceptance Criteria:**
1. VMs renamed in test-clan configuration: hetzner-vm → cinnabar (primary VPS), test-vm → electrum (secondary test VM)
2. Clan inventory updated: Machine definitions reflect new names (cinnabar, electrum), Tags and roles preserved from original configuration
3. Zerotier network established: Cinnabar configured as zerotier controller, Electrum configured as zerotier peer, Network ID documented for future machine additions
4. Network connectivity validated: Bidirectional ping between cinnabar and electrum via zerotier IPs, SSH via zerotier works in both directions, Network latency acceptable for coordination
5. Configuration rebuilds successful: Both VMs rebuild with new names without errors, Clan vars regenerated for renamed machines if needed
6. Test harness updated: Tests reference new machine names (cinnabar, electrum), All regression tests passing after rename
7. Documentation updated: README or relevant docs reflect cinnabar/electrum as test infrastructure names

**Prerequisites:** Story 1.8 (blackphos configuration migrated)

**Estimated Effort:** 2-3 hours

**Risk Level:** Low (rename operation, zerotier already working from Story 1.5)

**Note:** This prepares test-clan to mirror production topology where cinnabar and electrum will be migrated from test-clan to infra during the production refactoring.

---
```

---

### Change 5: Add New Story 1.10 (Integrate Blackphos into Zerotier)

**File:** `docs/notes/development/epics.md`
**Section:** After Story 1.9 (new)

**Content:**
```markdown
### Story 1.10: Integrate blackphos into test-clan zerotier network

As a system administrator,
I want to integrate the blackphos nix-darwin machine into the test-clan zerotier network with cinnabar and electrum,
So that I can validate heterogeneous networking (nixos ↔ nix-darwin) and prove multi-platform coordination before production refactoring.

**Acceptance Criteria:**
1. Blackphos zerotier peer configuration: Zerotier service configured on blackphos (investigate nix-darwin zerotier module or homebrew workaround), Blackphos joins zerotier network as peer (cinnabar remains controller), Zerotier configuration uses nix-native approach where possible
2. Blackphos deployed to physical hardware: Configuration deployed to actual blackphos laptop: `darwin-rebuild switch --flake .#blackphos`, Deployment succeeds without errors, All existing functionality validated post-deployment
3. Heterogeneous network validated: 3-machine zerotier network operational (cinnabar + electrum + blackphos), Blackphos can ping both cinnabar and electrum via zerotier IPs, Both nixos VMs can ping blackphos via zerotier IP
4. Cross-platform SSH validated: SSH from blackphos to cinnabar/electrum works, SSH from cinnabar/electrum to blackphos works, Certificate-based authentication functional across platforms
5. Clan vars deployed correctly on blackphos: /run/secrets/ populated with proper permissions (darwin-compatible), SSH host keys functional, User secrets accessible
6. Zero-regression validation: All blackphos daily workflows functional, Development environment intact, No performance degradation
7. Zerotier workarounds documented: If nix-darwin zerotier module unavailable, document approach used (homebrew, custom module, etc.), Note any platform-specific issues encountered

**Prerequisites:** Story 1.9 (VMs renamed, zerotier network established)

**Estimated Effort:** 4-6 hours (includes zerotier darwin integration investigation)

**Risk Level:** Medium-High (deploying to real physical machine, zerotier darwin support uncertain)

**Strategic Value:** Proves heterogeneous networking (nixos ↔ nix-darwin) works, validates complete multi-platform coordination pattern for production fleet

**Note:** This story may require investigating zerotier-one installation on nix-darwin. Options include: native nix-darwin module (if available), custom clan service for darwin based on nixos zerotier service, homebrew-based installation managed via nix-darwin.

---
```

---

### Change 6: Renumber Story 1.13 → 1.11 and Update Content

**File:** `docs/notes/development/epics.md`
**Section:** Story 1.13 (lines ~366-384)

**Before:**
```markdown
### Story 1.13: Document integration findings and architectural decisions

As a system administrator,
I want to document all integration findings and architectural decisions from Phase 0,
So that I have comprehensive reference for Phase 1 and beyond.

**Acceptance Criteria:**
1. INTEGRATION-FINDINGS.md created documenting: Terraform/terranix + clan integration (how it works, gotchas), Dendritic pattern evaluation (if attempted in Story 1.2), Acceptable deviations from pure patterns (specialArgs, module organization), Hetzner deployment experience (easy, hard, surprises), GCP deployment experience (comparison to Hetzner, challenges), Multi-cloud coordination findings (what works, what doesn't), Zerotier mesh networking across clouds (latency, reliability)
2. ARCHITECTURAL-DECISIONS.md created with: Why terraform/terranix for infrastructure provisioning, Why LUKS encryption (security requirement), Why zerotier mesh (always-on coordination, VPN), Clan inventory patterns chosen, Service instance patterns (roles, targeting), Secrets management strategy (clan vars vs sops-nix)
3. Confidence level assessed for each pattern: proven, needs-testing, uncertain
4. Recommendations for Phase 1 cinnabar deployment
5. Known limitations documented (GCP complexity, cost, alternatives)

**Prerequisites:** Story 1.12 (stability validated, patterns extracted)

**Estimated Effort:** 2-4 hours

**Risk Level:** Low (documentation only)
```

**After:**
```markdown
### Story 1.11: Document integration findings and architectural decisions

As a system administrator,
I want to document all integration findings and architectural decisions from Phase 0,
So that I have comprehensive reference for production refactoring in Epic 2+.

**Acceptance Criteria:**
1. Integration findings documented (in existing docs or new docs as appropriate): Terraform/terranix + clan integration (how it works, gotchas), Dendritic flake-parts pattern evaluation (proven via Stories 1.6-1.7), Nix-darwin + clan integration patterns (learned from Story 1.8), Home-manager integration approach with dendritic + clan, Heterogeneous zerotier networking (nixos ↔ nix-darwin from Story 1.10), Nixos-unified → dendritic + clan transformation process (from Story 1.8)
2. Architectural decisions documented (in existing docs or new docs as appropriate): Why dendritic flake-parts + clan combination, Why terraform/terranix for infrastructure provisioning, Why zerotier mesh (always-on coordination, VPN), Clan inventory patterns chosen, Service instance patterns (roles, targeting), Secrets management strategy (clan vars vs sops-nix), Home-manager integration approach
3. Confidence level assessed for each pattern: proven, needs-testing, uncertain
4. Recommendations for production refactoring: Specific steps to refactor infra from nixos-unified to dendritic + clan, Machine migration sequence and approach, Risk mitigation strategies based on test-clan learnings
5. Known limitations documented: Darwin-specific challenges, Platform-specific workarounds (if any), Areas requiring additional investigation

**Prerequisites:** Story 1.10 (blackphos integrated, heterogeneous networking validated)

**Estimated Effort:** 3-4 hours

**Risk Level:** Low (documentation only)

**Strategic Value:** Provides comprehensive blueprint for Epic 2+ production refactoring based on complete validation (nixos + nix-darwin + transformation pattern)
```

---

### Change 7: Renumber Story 1.14 → 1.12 and Update Decision Criteria

**File:** `docs/notes/development/epics.md`
**Section:** Story 1.14 (lines ~386-411)

**Before:**
```markdown
### Story 1.14: Execute go/no-go decision framework for Phase 1

As a system administrator,
I want to evaluate Phase 0 results against go/no-go criteria,
So that I can make an informed decision about proceeding to Phase 1 (cinnabar production deployment).

**Acceptance Criteria:**
1. GO-NO-GO-DECISION.md created with decision framework evaluation: Infrastructure deployment success (Hetzner + GCP operational: PASS/FAIL), Stability validation (1 week stable: PASS/FAIL), Multi-machine coordination (clan inventory + zerotier working: PASS/FAIL), Terraform/terranix integration (proven pattern: PASS/FAIL), Secrets management (clan vars working: PASS/FAIL), Cost acceptability (~$15-20/month for 2 VMs: ACCEPTABLE/EXCESSIVE), Pattern confidence (reusable for Phase 1: HIGH/MEDIUM/LOW)
2. Blockers identified (if any): Critical: must resolve before Phase 1, Major: can work around but risky, Minor: document and monitor
3. Decision rendered: **GO**: All criteria passed, high confidence, proceed to Phase 1 cinnabar; **CONDITIONAL GO**: Some issues but manageable, proceed with caution; **NO-GO**: Critical blockers, resolve or pivot strategy
4. If GO/CONDITIONAL GO: Phase 1 cinnabar deployment plan confirmed, Patterns ready to apply to production infrastructure, Test VMs can be destroyed (or kept for experimentation)
5. If NO-GO: Alternative approaches documented, Issues requiring resolution identified, Timeline for retry or pivot strategy
6. Next steps clearly defined based on decision outcome

**Prerequisites:** Story 1.13 (findings documented)

**Estimated Effort:** 1-2 hours

**Risk Level:** Low (decision only)

**Decision Criteria - GO if:** Both VMs deployed successfully, 1 week stability achieved, Multi-machine coordination working, Patterns documented with confidence, Cost acceptable for production use

**Decision Criteria - CONDITIONAL GO if:** Minor issues discovered but workarounds available, GCP more complex than expected but Hetzner solid, Dendritic pattern skipped (acceptable, not required), Stability good but < 1 week (6+ days acceptable)

**Decision Criteria - NO-GO if:** Critical deployment failures, Stability issues (crashes, service failures), Excessive cost or complexity, Patterns not reusable for production
```

**After:**
```markdown
### Story 1.12: Execute go/no-go decision framework for production refactoring

As a system administrator,
I want to evaluate Phase 0 results against go/no-go criteria,
So that I can make an informed decision about proceeding to production refactoring in Epic 2+.

**Acceptance Criteria:**
1. Decision framework evaluation documented (go-no-go-decision.md or integrated into existing docs): Infrastructure deployment success (Hetzner VMs operational: PASS/FAIL), Dendritic flake-parts pattern validated (Stories 1.6-1.7: PASS/FAIL), Nix-darwin + clan integration proven (Story 1.8: PASS/FAIL), Heterogeneous networking validated (nixos ↔ darwin zerotier: PASS/FAIL), Transformation pattern documented (nixos-unified → dendritic + clan: PASS/FAIL), Home-manager integration proven (PASS/FAIL), Pattern confidence (reusable for production refactoring: HIGH/MEDIUM/LOW)
2. Blockers identified (if any): Critical: must resolve before production refactoring, Major: can work around but risky, Minor: document and monitor
3. Decision rendered: **GO**: All criteria passed, high confidence, proceed to Epic 2+ production refactoring; **CONDITIONAL GO**: Some issues but manageable, proceed with specific cautions documented; **NO-GO**: Critical blockers, resolve or pivot strategy
4. If GO/CONDITIONAL GO: Production refactoring plan confirmed for Epic 2+, Migration pattern ready to apply to infra repository, Test-clan cinnabar/electrum configurations ready to migrate into infra, Blackphos can be reverted to infra management or kept in test-clan as ongoing validation
5. If NO-GO: Alternative approaches documented, Issues requiring resolution identified, Timeline for retry or pivot strategy, Specific validation gaps that need addressing
6. Next steps clearly defined based on decision outcome

**Prerequisites:** Story 1.11 (findings documented)

**Estimated Effort:** 1-2 hours

**Risk Level:** Low (decision only)

**Decision Criteria - GO if:** Hetzner VMs deployed and operational, Dendritic flake-parts pattern proven with zero regressions, Blackphos successfully migrated from nixos-unified to dendritic + clan, Heterogeneous zerotier network operational (nixos + darwin), Transformation pattern documented and reusable, High confidence in applying patterns to production

**Decision Criteria - CONDITIONAL GO if:** Minor platform-specific issues discovered but workarounds documented, Some manual steps required but acceptable, Partial automation acceptable with documented procedures, Medium-high confidence in production refactoring

**Decision Criteria - NO-GO if:** Critical failures in darwin integration, Transformation pattern unclear or too complex, Heterogeneous networking unreliable, Patterns not reusable for production, Major gaps in validation coverage
```

---

### Change 8: Update sprint-status.yaml Story Tracking

**File:** `docs/notes/development/sprint-status.yaml`
**Section:** Epic 1 story tracking (lines ~83-92)

**Before:**
```yaml
  # Story 1.8: READY-FOR-DEV - Story context generated (2025-11-07) with comprehensive test-clan analysis
  # Focus: validation/documentation, enhance TC-007, create secrets-management.md, add justfile recipes
  1-8-validate-clan-secrets-vars-on-hetzner: ready-for-dev
  # Story 1.9: REQUIRES MANUAL SECRET SETUP - agent must pause for user to configure GCP service account JSON
  1-9-create-gcp-terraform-config-and-host-modules: drafted
  1-10-deploy-gcp-vm-and-validate-multi-cloud: drafted
  1-11-test-multi-machine-coordination: drafted
  1-12-monitor-stability-for-one-week: drafted
  1-13-document-integration-findings-and-patterns: drafted
  1-14-execute-go-no-go-decision-framework: drafted
```

**After:**
```yaml
  # Story 1.8: Migration rehearsal - convert blackphos from infra nixos-unified to test-clan dendritic + clan
  # Strategic: Documents transformation pattern for production refactoring in Epic 2+
  1-8-migrate-blackphos-from-infra-to-test-clan: backlog
  # Story 1.9: Rename test VMs to production names (cinnabar/electrum) and establish zerotier network
  1-9-rename-vms-cinnabar-electrum-establish-zerotier: backlog
  # Story 1.10: Integrate blackphos (nix-darwin) into zerotier network with cinnabar/electrum (nixos)
  # Validates heterogeneous networking across platforms
  1-10-integrate-blackphos-into-zerotier-network: backlog
  # Story 1.11: Document complete findings including darwin validation and transformation patterns
  1-11-document-integration-findings-and-patterns: backlog
  # Story 1.12: GO/NO-GO decision based on expanded validation (nixos + darwin + transformation)
  1-12-execute-go-no-go-decision-framework: backlog
```

---

### Change 9: Update Summary Statistics

**File:** `docs/notes/development/epics.md`
**Section:** Summary Statistics (lines ~1022-1036)

**Before:**
```markdown
## Summary Statistics

**Total Epics:** 7 (aligned to 6 migration phases + cleanup)

**Total Stories:** 36 stories across all epics

**Story Distribution:**
- Epic 1 (Phase 0 - Infrastructure Deployment): 14 stories
- Epic 2 (Phase 1 - cinnabar): 6 stories
- Epic 3 (Phase 2 - blackphos): 5 stories
- Epic 4 (Phase 3 - rosegold): 3 stories
- Epic 5 (Phase 4 - argentum): 2 stories
- Epic 6 (Phase 5 - stibnite): 3 stories
- Epic 7 (Phase 6 - cleanup): 3 stories
```

**After:**
```markdown
## Summary Statistics

**Total Epics:** 7 (aligned to 6 migration phases + cleanup)

**Total Stories:** 34 stories across all epics

**Story Distribution:**
- Epic 1 (Phase 0 - Architectural Validation + Migration Pattern Rehearsal): 12 stories
- Epic 2 (Phase 1 - cinnabar): 6 stories
- Epic 3 (Phase 2 - blackphos): 5 stories
- Epic 4 (Phase 3 - rosegold): 3 stories
- Epic 5 (Phase 4 - argentum): 2 stories
- Epic 6 (Phase 5 - stibnite): 3 stories
- Epic 7 (Phase 6 - cleanup): 3 stories
```

---

## Section 5: Implementation Handoff

### Change Scope Classification

**Minor to Moderate**

**Rationale:**
- Changes confined to Epic 1 documentation and story definitions
- No fundamental architecture changes required
- No impacts to Epic 2+ beyond improved confidence
- Implementation by same development team (user + AI agent)

### Handoff Recipients and Responsibilities

**Primary: Development Team (user + AI agent)**

**Responsibilities:**
1. Review and approve Sprint Change Proposal
2. Execute artifact updates (epics.md, sprint-status.yaml)
3. Draft new Stories 1.8-1.10 with complete acceptance criteria (already included in this proposal)
4. Implement Stories 1.8-1.10 sequentially in test-clan repository
5. Update Story 1.12 (go/no-go) to reflect expanded validation scope (already included in this proposal)

**Secondary: None** (no PO/SM/PM involvement needed for documentation adjustments)

### Success Criteria

- All artifact updates completed with no regressions
- New Stories 1.8-1.10 fully defined with testable acceptance criteria (✓ complete in this proposal)
- Epic 1 validation scope clearly expanded to include darwin migration rehearsal
- Stories 1.8-1.10 implemented successfully (verified via test harness)
- Go/no-go decision (Story 1.12) reflects complete validation (nixos + darwin + transformation patterns)

### Next Steps

**Immediate (after approval):**
1. Apply all 9 change proposals to epics.md
2. Apply change proposal 8 to sprint-status.yaml
3. Commit changes with message: "docs(epic-1): adjust scope for darwin migration rehearsal"

**Subsequent (story implementation):**
1. Begin Story 1.8: Migrate blackphos from infra to test-clan
2. Complete Story 1.9: Rename VMs and establish zerotier
3. Complete Story 1.10: Integrate blackphos into zerotier network
4. Complete Story 1.11: Document integration findings
5. Complete Story 1.12: Execute go/no-go decision

---

## Section 6: Approval

**Status:** Pending user approval

**Approval Required:** Yes

**Questions for User:**
1. Do you approve this Sprint Change Proposal for implementation?
2. Are there any aspects that need revision or clarification?
3. Should we proceed with applying all changes to epics.md and sprint-status.yaml?

**Approval Options:**
- **Approve [yes]:** Proceed with implementing all proposed changes
- **Revise [revise]:** Provide specific feedback on what needs adjustment
- **Reject [no]:** Explain concerns and alternative approach

---

**Generated:** 2025-11-11
**Workflow:** correct-course (Sprint Change Management)
**Change Trigger:** Epic 1 Stories 1.1-1.7 complete, darwin validation gap identified
**Proposed By:** Development team (AI agent)
**Awaiting Approval From:** User (crs58)
