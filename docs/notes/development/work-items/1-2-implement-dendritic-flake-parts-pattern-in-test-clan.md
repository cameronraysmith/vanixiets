# Story 1.2: Evaluate and refine dendritic flake-parts architecture in test-clan

Status: ready-for-dev

## Story

As a system administrator,
I want to evaluate test-clan's current architecture against dendritic flake-parts patterns and refine if beneficial,
So that I can ensure the foundation is scalable and maintainable before expanding to GCP and production deployments.

## Context

Story 1.2 was originally deferred (2025-11-03 decision) to prioritize infrastructure deployment (Stories 1.4-1.8).
Now with 2 operational Hetzner VMs deployed and validated, we have sufficient infrastructure maturity to evaluate whether dendritic patterns would improve test-clan's architecture.

**Current State (Post-Story 1.5):**
- test-clan has 2 operational VMs (hetzner-ccx23, hetzner-cx43) with validated stack
- Repository structure: modules/base/, modules/hosts/, modules/flake-parts/, modules/terranix/
- Manual machine imports: `clan.machines.{name}.imports = [ ../hosts/{name} ]` in clan.nix
- Terranix modules exported: `flake.modules.terranix.{base,hetzner}` (clan.nix:8-9)
- specialArgs pattern: `{ inherit inputs; }` (minimal, required for srvos imports per Story 1.4)

**Dendritic Pattern Objectives:**
- Automatic module discovery via import-tree (vs manual imports)
- Namespace-based organization: `config.flake.modules.nixos.{namespace}.{module}`
- Minimal specialArgs (ideally none, or framework-level only like `self`)
- Self-composition: modules import each other via namespace, not direct paths

**Why Now:**
- test-clan mature enough to evaluate (2 VMs, patterns established)
- Simple enough to refactor easily (before GCP adds complexity in Stories 1.7-1.8)
- Story 1.5 demonstrated value of scalable patterns (terraform toggle refactoring)
- Story 1.6 (secrets) and 1.7-1.8 (GCP) should build on validated architecture

**Strategic Impact:**
- Phase 1 (cinnabar) will apply test-clan patterns to production infrastructure
- Architectural decisions now affect Phase 2+ (darwin migration, 5+ machines)
- Better to validate foundation before 1-week stability monitoring (Story 1.10)

## Acceptance Criteria

### AC1: Comprehensive Architectural Assessment

Analyze test-clan structure against dendritic patterns across three dimensions:

1. **Module Discovery:** Does manual import pattern scale to 10+ machines? Is automatic discovery needed?
   - Current: `clan.machines.{name}.imports = [ ../hosts/{name} ]` (manual per-machine)
   - Dendritic: import-tree.walkDir or similar for automatic discovery
   - Evaluate: At 2-4 machines, is manual acceptable? At 10+ machines, does it become unmaintainable?

2. **Module Namespacing:** Are base modules exported and reusable?
   - Current: Only terranix modules exported (clan.nix:8-9)
   - Dendritic: Base modules exported to `flake.modules.nixos.{namespace}.{module}`
   - Evaluate: Can hosts import via `config.flake.modules` instead of relative paths?

3. **specialArgs Usage:** Is `{ inherit inputs; }` compatible with dendritic?
   - Current: `specialArgs = { inherit inputs; }` (clan.nix:19)
   - Story 1.4 rationale: Required for srvos imports in host modules
   - Clan-infra: Uses `{ inherit self; }` (minimal, framework-level)
   - Dendritic ideal: No specialArgs, or framework values only
   - Evaluate: Can dendritic work with inputs in specialArgs? Is this a blocker?

**Validation Method:**
- Cross-reference clan-infra patterns (~/projects/nix-workspace/clan-infra)
- Review dendritic exemplar repositories (dendritic-flake-parts, mightyiam-dendritic-infra, etc.)
- Analyze test-clan modules/ structure for reusability and discoverability
- Document findings in DENDRITIC-NOTES.md or Story 1.2 completion notes

### AC2: Decision Framework Execution

Determine test-clan's dendritic compliance and path forward using decision tree:

**Outcome A: Already Dendritic-Compliant**
- test-clan follows dendritic patterns sufficiently for current scale (2-4 machines)
- Manual imports acceptable for infrastructure repositories with low machine churn
- Namespace exports not critical value-add at current scale
- Decision: Document validation, mark story complete, no refactoring needed

**Outcome B: Easy Dendritic Refactoring (< 4 hours)**
- Specific improvements identified: import-tree setup, base module namespace exports, etc.
- Clear implementation path with low risk to operational infrastructure
- Estimated effort: 2-4 hours implementation + validation
- Decision: Execute refactoring NOW before GCP expansion (Stories 1.7-1.8)

**Outcome C: Complex Dendritic Refactoring (> 4 hours)**
- Significant architectural changes required (major specialArgs rework, etc.)
- High risk of breaking operational infrastructure (2 deployed VMs)
- Estimated effort: > 8 hours or uncertain scope
- Decision: Document findings, defer implementation to post-Epic 1 or Phase 1

**Required Documentation:**
- Rationale for chosen outcome (A/B/C) with file:line evidence
- Trade-offs: dendritic purity vs clan/terraform integration pragmatism
- If Outcome B: Define refactoring tasks with time estimates
- If Outcome C: Document blockers and revisit criteria

### AC3: Module Organization Evaluation

Evaluate current module structure for scalability and maintainability:

**Current Structure:**
```
modules/
├── base/           # nix-settings.nix, admins.nix, initrd-networking.nix
├── hosts/          # hetzner-ccx23/, hetzner-cx43/, gcp-vm/
├── flake-parts/    # clan.nix (inventory, terranix integration)
└── terranix/       # base.nix, hetzner.nix
```

**Evaluation Questions:**
1. Are base modules (nix-settings, admins, initrd-networking) reusable across hosts?
2. Can new machines discover and import base modules easily?
3. Is host configuration pattern consistent (default.nix + disko.nix per host)?
4. Does terranix module organization scale to GCP, other providers?
5. Is there clear separation of concerns (base, host-specific, infrastructure)?

**Documentation Required:**
- Reusability assessment: Which modules are truly shared vs host-specific?
- Discoverability: Can developer find relevant modules without deep knowledge?
- Consistency: Do patterns work across Hetzner VMs? Will they work for GCP?
- Maintainability: Adding machine #10 - how many files need updates?

### AC4: specialArgs Compatibility Assessment

Analyze whether `specialArgs = { inherit inputs; }` is compatible with dendritic patterns:

**Story 1.4 Context:**
- Added in clan.nix:19 to fix infinite recursion in module evaluation
- Required for srvos imports: `inputs.srvos.nixosModules.server`
- Clan-infra uses minimal pattern: `{ inherit self; }`
- Question: Is inputs in specialArgs preventing dendritic adoption?

**Evaluation Approach:**
1. Review clan-infra's specialArgs usage in modules/flake-parts/
2. Understand how clan-infra imports srvos without passing inputs via specialArgs
3. Research dendritic pattern requirements: Does dendritic forbid inputs in specialArgs?
4. Determine if alternative exists: Can modules access inputs via flake.inputs namespace?

**Required Documentation:**
- Comparison: test-clan vs clan-infra specialArgs patterns
- Analysis: Why does clan-infra not need inputs in specialArgs?
- Compatibility: Can dendritic work with `{ inherit inputs; }` or is this a blocker?
- Alternative patterns: If blocker, what's the migration path?

### AC5: Validation of Existing Infrastructure

If any refactoring is applied (Outcome B), ensure operational stability:

**Pre-Refactoring Baseline:**
- Both Hetzner VMs operational (hetzner-ccx23: 162.55.175.87, hetzner-cx43: 49.13.140.183)
- nix flake check passes without errors
- Host configurations build successfully: `nix build .#nixosConfigurations.hetzner-ccx23.config.system.build.toplevel`
- Terraform/terranix integration works: `nix build .#terraform`

**Post-Refactoring Validation:**
- nix flake check passes (no new errors introduced)
- All host configurations still build successfully
- Terraform config generation unchanged (byte-for-byte if possible)
- VMs remain operational (SSH access, services running)
- No regression in clan vars, zerotier, or other deployed services

**Testing Strategy:**
- Build all configurations locally before deploying changes
- Use nix store path comparison to verify functional equivalence
- Test selective terraform operations (plan, no apply) to validate terranix integration
- SSH to VMs and verify no service disruptions

**Rollback Plan:**
- Git commit before refactoring for easy revert
- If build failures occur, git revert and document blockers
- If subtle issues found, may need targeted fixes vs full rollback

### AC6: Comprehensive Documentation

Document evaluation findings and architectural decisions:

**DENDRITIC-NOTES.md (or equivalent in Story 1.2 Dev Notes):**
- **Assessment Results:** Outcome A/B/C with detailed rationale
- **Pattern Comparison:** test-clan vs clan-infra vs dendritic exemplars
  - Module discovery mechanisms (manual vs automatic)
  - Namespace export patterns (what's exported, what's not)
  - specialArgs usage (inputs vs self vs none)
- **Trade-offs:** Dendritic purity vs practical clan/terraform integration
  - What would we gain from full dendritic compliance?
  - What would we lose or need to change?
  - Is the juice worth the squeeze at current scale (2-4 machines)?
- **Scalability Analysis:** Projecting to 10+ machines
  - Will manual imports become unmaintainable?
  - Would automatic discovery simplify operations?
  - Are there other pain points unrelated to dendritic?
- **Recommendations for Phase 1 (cinnabar):**
  - Should cinnabar follow current test-clan patterns?
  - Should cinnabar adopt dendritic patterns?
  - Should we revisit dendritic in Epic 2 (darwin migration)?

**Decision Rationale:**
- If Outcome A: Why is current architecture sufficient?
- If Outcome B: Why is refactoring worth doing now?
- If Outcome C: What are the specific blockers? When should we revisit?

**File:Line Evidence:**
- Cite specific files and line numbers from test-clan
- Reference clan-infra patterns with file paths
- Link to dendritic exemplar repositories for comparison

## Tasks / Subtasks

### Task 1: Conduct comprehensive architectural assessment (AC: #1)

- [ ] **1.1: Review test-clan current structure**
  - [ ] Read modules/flake-parts/clan.nix completely (inventory, terranix, machine imports)
  - [ ] Examine base modules: nix-settings.nix, admins.nix, initrd-networking.nix
  - [ ] Analyze host modules: hetzner-ccx23/default.nix, hetzner-cx43/default.nix
  - [ ] Identify module dependencies and import patterns
  - [ ] Document current module discovery mechanism (manual imports at clan.nix:~90+)

- [ ] **1.2: Cross-reference clan-infra patterns**
  - [ ] Read ~/projects/nix-workspace/clan-infra/modules/flake-parts/ structure
  - [ ] Identify machine import patterns in clan-infra
  - [ ] Compare clan-infra specialArgs usage vs test-clan
  - [ ] Note differences: srvos imports, module organization, namespace exports

- [ ] **1.3: Explore dendritic exemplar repositories**
  - [ ] Review dendritic-flake-parts repository structure and patterns
  - [ ] Examine mightyiam-dendritic-infra or similar for real-world usage
  - [ ] Identify core dendritic principles: import-tree, namespaces, composition
  - [ ] Document dendritic requirements that might conflict with clan/terraform

- [ ] **1.4: Evaluate module discovery scalability**
  - [ ] Current: Manual per-machine imports in clan.nix (2 machines = 2 import statements)
  - [ ] Projection: 10 machines = 10 import statements + 10 directories in modules/hosts/
  - [ ] Analysis: Is manual import pattern acceptable or does it become error-prone?
  - [ ] Consider: Does clan's machine inventory reduce need for automatic discovery?

- [ ] **1.5: Evaluate module namespacing value**
  - [ ] Current: Terranix modules exported (clan.nix:8-9), base modules not exported
  - [ ] Question: Would base module namespace exports improve reusability?
  - [ ] Consider: Do hosts benefit from `config.flake.modules.base.nix-settings`?
  - [ ] Alternative: Direct imports `../../base/nix-settings.nix` acceptable at small scale?

- [ ] **1.6: Evaluate specialArgs compatibility**
  - [ ] Current: `specialArgs = { inherit inputs; }` required for srvos imports
  - [ ] Dendritic ideal: No specialArgs or framework-level only (self)
  - [ ] Research: How does clan-infra import srvos without inputs in specialArgs?
  - [ ] Determine: Is inputs in specialArgs a blocker for dendritic adoption?

### Task 2: Execute decision framework and determine outcome (AC: #2)

- [ ] **2.1: Synthesize assessment findings**
  - [ ] Compile results from Task 1 subtasks
  - [ ] Identify strengths of current architecture (what works well)
  - [ ] Identify gaps or pain points (what could be improved)
  - [ ] Consider future scale (Epic 2+ with 5+ darwin machines)

- [ ] **2.2: Evaluate Outcome A: Already Compliant**
  - [ ] Assess: Does test-clan follow dendritic principles sufficiently?
  - [ ] Consider: At 2-4 machines, is current architecture maintainable?
  - [ ] Evaluate: Would dendritic refactoring add significant value?
  - [ ] Decision criteria: If "no major improvements needed", choose Outcome A

- [ ] **2.3: Evaluate Outcome B: Easy Refactoring**
  - [ ] Identify specific improvements: import-tree setup, namespace exports, etc.
  - [ ] Estimate effort: < 4 hours total (2-4 hours implementation)?
  - [ ] Assess risk: Low risk to operational VMs?
  - [ ] Decision criteria: If "clear path, low risk, < 4 hours", choose Outcome B

- [ ] **2.4: Evaluate Outcome C: Complex Refactoring**
  - [ ] Identify blockers: specialArgs rework, major restructuring, etc.
  - [ ] Estimate effort: > 8 hours or uncertain scope?
  - [ ] Assess risk: High risk of breaking deployed infrastructure?
  - [ ] Decision criteria: If "complex, risky, or > 8 hours", choose Outcome C

- [ ] **2.5: Document decision with rationale**
  - [ ] State chosen outcome: A, B, or C
  - [ ] Provide detailed rationale with file:line evidence
  - [ ] Document trade-offs considered
  - [ ] If Outcome B: List specific refactoring tasks with time estimates
  - [ ] If Outcome C: Document blockers and conditions for revisiting

### Task 3: Perform module organization evaluation (AC: #3)

- [ ] **3.1: Assess base module reusability**
  - [ ] Review modules/base/nix-settings.nix: Used by all machines?
  - [ ] Review modules/base/admins.nix: Shared user configuration?
  - [ ] Review modules/base/initrd-networking.nix: Applicable to all nixos hosts?
  - [ ] Determine: Are these truly shared or machine-specific?

- [ ] **3.2: Assess host configuration consistency**
  - [ ] Compare hetzner-ccx23 vs hetzner-cx43 structure
  - [ ] Verify pattern: default.nix (system config) + disko.nix (storage) per host
  - [ ] Check: Are imports consistent across hosts?
  - [ ] Evaluate: Does pattern extend cleanly to gcp-vm?

- [ ] **3.3: Assess infrastructure module scalability**
  - [ ] Review terranix/hetzner.nix: lib.mapAttrs pattern (Story 1.5 refactoring)
  - [ ] Consider: Adding GCP provider - does terranix/ structure accommodate?
  - [ ] Evaluate: Does terranix module export pattern (clan.nix:8-9) scale?
  - [ ] Plan: Future AWS/other clouds - is organization extensible?

- [ ] **3.4: Project maintenance at 10+ machines**
  - [ ] Simulate: Adding machine #10 - which files need updates?
  - [ ] Count: How many manual edits required? (inventory + imports + host module + terraform def)
  - [ ] Compare: Dendritic automatic discovery - would it reduce manual steps?
  - [ ] Assess: Is current pattern acceptable or does it need improvement?

### Task 4: Analyze specialArgs compatibility (AC: #4)

- [ ] **4.1: Review clan-infra specialArgs pattern**
  - [ ] Read ~/projects/nix-workspace/clan-infra/modules/flake-parts/clan.nix or equivalent
  - [ ] Identify specialArgs configuration in clan-infra
  - [ ] Note: Does clan-infra use `{ inherit self; }` or something else?
  - [ ] Compare: test-clan `{ inherit inputs; }` vs clan-infra pattern

- [ ] **4.2: Understand srvos import mechanism**
  - [ ] Question: How does clan-infra import srvos.nixosModules.server?
  - [ ] Investigate: Does clan-infra access inputs differently?
  - [ ] Research: Can modules access flake inputs via module args instead of specialArgs?
  - [ ] Document: Alternative patterns for accessing external flake inputs

- [ ] **4.3: Evaluate dendritic specialArgs requirements**
  - [ ] Review dendritic exemplar repos for specialArgs usage
  - [ ] Question: Does dendritic forbid inputs in specialArgs?
  - [ ] Question: Is `{ inherit self; }` acceptable in dendritic pattern?
  - [ ] Determine: Is test-clan's `{ inherit inputs; }` a hard blocker?

- [ ] **4.4: Document compatibility assessment**
  - [ ] State: Is inputs in specialArgs compatible with dendritic?
  - [ ] If incompatible: Document migration path to dendritic-compliant pattern
  - [ ] If compatible: Document why it's acceptable or what trade-offs exist
  - [ ] Provide recommendations: Should we change specialArgs or keep current pattern?

### Task 5: Implement refactoring if Outcome B (AC: #5)

**Note:** Only execute Task 5 if decision framework (Task 2) results in Outcome B.

- [ ] **5.1: Create git checkpoint before refactoring**
  - [ ] Commit any uncommitted work
  - [ ] Create tag: `pre-dendritic-refactoring-story-1.2`
  - [ ] Note commit hash for rollback if needed

- [ ] **5.2: Execute identified refactoring tasks**
  - [ ] (Tasks depend on specific improvements identified in Task 2)
  - [ ] Example: Setup import-tree for automatic module discovery
  - [ ] Example: Export base modules to flake.modules.nixos.base namespace
  - [ ] Example: Refactor host modules to use config.flake.modules imports
  - [ ] Example: Adjust specialArgs if migration path identified

- [ ] **5.3: Validate nix flake check passes**
  - [ ] Run: `nix flake check` (in test-clan repository)
  - [ ] Verify: No new errors introduced
  - [ ] If failures: Debug and fix, or rollback and document blockers

- [ ] **5.4: Validate host configurations build**
  - [ ] Build: `nix build .#nixosConfigurations.hetzner-ccx23.config.system.build.toplevel`
  - [ ] Build: `nix build .#nixosConfigurations.hetzner-cx43.config.system.build.toplevel`
  - [ ] Build: `nix build .#nixosConfigurations.gcp-vm.config.system.build.toplevel` (if applicable)
  - [ ] Verify: All configurations build without errors

- [ ] **5.5: Validate terraform/terranix integration**
  - [ ] Build: `nix build .#terraform`
  - [ ] Compare: nix store path vs previous build (functional equivalence)
  - [ ] Test: Enter nix develop shell, run `terraform plan` (dry-run validation)
  - [ ] Verify: No unexpected changes to terraform resources

- [ ] **5.6: Validate operational VMs remain stable**
  - [ ] SSH: `ssh root@162.55.175.87` (hetzner-ccx23)
  - [ ] SSH: `ssh root@49.13.140.183` (hetzner-cx43)
  - [ ] Verify: All services operational (zerotier, sshd, etc.)
  - [ ] Note: Refactoring should not require VM reconfiguration (local changes only)

- [ ] **5.7: Commit refactoring with detailed message**
  - [ ] Commit message: "refactor(story-1.2): apply dendritic pattern to test-clan"
  - [ ] Body: Detail specific changes made and rationale
  - [ ] Reference: Story 1.2 acceptance criteria met

### Task 6: Create comprehensive documentation (AC: #6)

- [ ] **6.1: Create or update DENDRITIC-NOTES.md**
  - [ ] Location: docs/notes/development/DENDRITIC-NOTES.md or similar
  - [ ] Section: Assessment Results (Outcome A/B/C with rationale)
  - [ ] Section: Pattern Comparison (test-clan vs clan-infra vs dendritic)
  - [ ] Section: Trade-offs (what we gain/lose with dendritic)
  - [ ] Section: Scalability Analysis (projecting to 10+ machines)
  - [ ] Section: Recommendations for Phase 1 (cinnabar patterns)

- [ ] **6.2: Document decision rationale**
  - [ ] If Outcome A: Why current architecture is sufficient
  - [ ] If Outcome B: Why refactoring was beneficial (changes made, validation)
  - [ ] If Outcome C: Specific blockers and revisit conditions
  - [ ] Include: File:line citations from test-clan, clan-infra, dendritic exemplars

- [ ] **6.3: Capture architectural learnings**
  - [ ] What worked: Current test-clan patterns that are solid
  - [ ] What didn't: Pain points or limitations discovered
  - [ ] Future considerations: Epic 2+ (darwin), Epic 7+ (other machines)
  - [ ] Pattern recommendations: Should Phase 1 follow same patterns?

- [ ] **6.4: Update Story 1.2 Dev Agent Record**
  - [ ] Completion Notes: Summary of evaluation and outcome
  - [ ] File List: Documents created/modified (DENDRITIC-NOTES.md, refactored modules)
  - [ ] Learnings: Key insights for future stories
  - [ ] References: Links to clan-infra, dendritic repos examined

## Dev Notes

### Strategic Context

**Why Story 1.2 Was Deferred (2025-11-03):**

Original epic strategy prioritized infrastructure deployment over architectural refinement.
Rationale: Get VMs operational first, optimize patterns later if needed.
This was correct - Story 1.4 established foundation, Story 1.5 validated complete stack.

**Why Story 1.2 Is Relevant Now (2025-11-05):**

1. **Maturity:** test-clan has 2 operational VMs, patterns are established and validated
2. **Simplicity:** At 2 machines, refactoring is low-risk; at 10+ machines, much harder
3. **Proof of Value:** Story 1.5 terraform toggle refactoring (O(N) → O(1)) demonstrated value of scalable patterns
4. **Timing:** Before GCP expansion (Stories 1.7-1.8), validate foundation is sound
5. **Phase 1 Impact:** Decisions now affect cinnabar production deployment patterns

**Strategic Questions:**

- Is test-clan's architecture scalable to 10+ machines? (Epic 2+ with darwin fleet)
- Would dendritic patterns simplify GCP module organization? (Stories 1.7-1.8)
- Should Phase 1 (cinnabar) adopt different patterns than test-clan?
- Are there pain points unrelated to dendritic that need addressing?

### Learnings from Previous Stories

**From Story 1.1 (Status: done):**
- test-clan repository prepared with flake-parts, terranix, clan-core, disko, srvos
- Foundation structure: modules/base/, modules/hosts/, modules/flake-parts/, modules/terranix/
- Basic flake.nix organization established

**From Story 1.3 (Status: done):**
- Clan inventory pattern: tag-based service targeting (tags."all", tags."nixos")
- Machine imports: `clan.machines.{name}.imports = [ ../hosts/{name} ]`
- Service instances: emergency-access, users-root, zerotier (controller + peers), tor

**From Story 1.4 (Status: done - APPROVED):**
- **Critical Finding:** `specialArgs = { inherit inputs; }` required for srvos imports
- Rationale documented: "minimal specialArgs" ideal but inputs needed for module system
- Deviation from clan-infra noted: clan-infra uses minimal pattern
- Question for Story 1.2: How does clan-infra import srvos without inputs in specialArgs?

**From Story 1.5 (Status: done - APPROVED):**
- **Key Learning:** Scalable patterns provide significant value even at small scale
- Terraform toggle refactored: Manual O(N) chaining → Declarative O(1) lib.mapAttrs
- Validation: Byte-for-byte identical output, scales to N machines with +5 lines per machine
- Pattern established: Declarative definitions + functional generation
- Architectural patterns documented: UEFI/BIOS boot overrides, complete machine lifecycle

**From Story 1.5 Senior Developer Review:**
- Architecture: "Implementation follows clan-infra proven patterns closely"
- Code quality: "Excellent - configuration files clean, well-commented, follow patterns"
- Documentation: "Comprehensive documentation captures learnings and decision rationale"
- Recommendation: Continue following clan-infra patterns, with documented deviations

### Cross-References to Dendritic Exemplars

**Dendritic Repositories to Review:**

1. **dendritic-flake-parts** (~/projects/nix-workspace/dendritic-flake-parts/)
   - Core dendritic patterns demonstration repository
   - Focus: import-tree usage, module namespace exports

2. **mightyiam-dendritic-infra** (~/projects/nix-workspace/mightyiam-dendritic-infra/)
   - Real-world dendritic infrastructure example
   - Focus: Multi-machine organization, practical patterns

3. **gaetanlepage-dendritic-nix-config** (~/projects/nix-workspace/gaetanlepage-dendritic-nix-config/)
   - Another dendritic configuration example
   - Focus: Personal configuration patterns (may differ from infrastructure)

4. **clan-infra** (~/projects/nix-workspace/clan-infra/)
   - Production-ready clan infrastructure (10+ machines)
   - Focus: Proven clan patterns, specialArgs usage, machine organization
   - Question: Does clan-infra use dendritic patterns? Or different approach?

**Key Comparison Points:**

- Module discovery: Automatic (import-tree) vs manual (explicit imports)
- Module namespacing: `config.flake.modules.*` vs relative path imports
- specialArgs: `{ inherit self; }` vs `{ inherit inputs; }` vs none
- Machine organization: Automatic discovery vs inventory-based (clan pattern)
- Scalability: Adding machine #10 - steps required in each approach

### Expected Evaluation Methodology

**Step 1: Understand Current State (1-2 hours)**
- Read all test-clan modules completely
- Map module dependencies and import patterns
- Document current organization clearly

**Step 2: Cross-Reference Patterns (1-2 hours)**
- Examine clan-infra for proven clan patterns
- Review dendritic exemplars for pure dendritic approach
- Identify differences and similarities

**Step 3: Evaluate Against Criteria (1 hour)**
- Module discovery scalability assessment
- Module namespacing value assessment
- specialArgs compatibility assessment
- Document findings with file:line evidence

**Step 4: Make Decision (30 minutes)**
- Synthesize findings into Outcome A/B/C
- Document rationale clearly
- If Outcome B: Define specific refactoring tasks

**Step 5: Implement or Document (2-4 hours if Outcome B, 30 min if A/C)**
- Outcome A: Document validation, mark complete
- Outcome B: Execute refactoring, validate infrastructure
- Outcome C: Document blockers and deferral rationale

**Total Estimated Time:** 4-8 hours depending on outcome

### Time Budget and Constraints

**Acceptable Time Investment:**
- Evaluation/validation: 2-4 hours (reading, analysis, documentation)
- Easy refactoring: 2-4 hours additional (implementation + validation)
- Total acceptable: 4-8 hours maximum
- If exceeds 8 hours: Stop, document as Outcome C, defer to post-Epic 1

**Risk Management:**
- Low risk: Evaluation and documentation only (Outcome A or C)
- Medium risk: Refactoring with validation (Outcome B)
- High risk: Major architectural changes (automatically becomes Outcome C - defer)

**Zero-Regression Mandate:**
- Does NOT apply to test-clan (Phase 0 test infrastructure)
- BUT: Should not break operational VMs without good reason
- Rollback plan: Git commit before changes, revert if issues found

**Story 1.6 Dependency:**
- Story 1.6 (secrets validation) should proceed regardless of Story 1.2 outcome
- If Story 1.2 refactoring in progress, Story 1.6 can wait or work in parallel branch
- Coordination: If refactoring changes affect Story 1.6, document integration approach

### Decision Framework Details

**Outcome A Indicators:**
- Current patterns work well for current scale (2-4 machines)
- Dendritic would add complexity without clear benefit
- Manual imports are maintainable at infrastructure repository scale
- clan inventory pattern reduces need for automatic module discovery
- specialArgs pattern is pragmatic and works
- Code is clean, documented, maintainable as-is

**Outcome B Indicators:**
- Specific improvements identified that add clear value
- Low risk to operational infrastructure (local changes, well-tested)
- Refactoring can be completed in 2-4 hours with confidence
- Changes simplify future work (GCP, darwin, other machines)
- Base module reusability would improve with namespace exports
- Story 1.5 pattern (scalable functional generation) applies here too

**Outcome C Indicators:**
- Major changes required: specialArgs rework, import mechanism overhaul
- Uncertain scope: Can't estimate effort with confidence
- High risk: Could break operational VMs or complicate deployment
- Blockers: Fundamental conflicts between clan patterns and dendritic requirements
- Better timing: Post-Epic 1 retrospective or Phase 1 planning would be more appropriate
- Trade-offs unclear: Not obvious that dendritic provides value for infrastructure repositories

### Architecture Patterns to Evaluate

**Current test-clan Patterns:**
1. Manual machine imports in clan.nix: `imports = [ ../hosts/{name} ]`
2. Terranix module exports: `flake.modules.terranix.{base,hetzner}`
3. specialArgs with inputs: `{ inherit inputs; }` for srvos access
4. Host structure: default.nix + disko.nix per machine
5. Base modules: Shared but not exported to namespace
6. Tag-based service targeting: roles.controller.machines vs roles.peer.tags."all"

**Dendritic Pattern Expectations:**
1. Automatic module discovery: import-tree.walkDir finds modules
2. Namespace exports: `flake.modules.nixos.base.nix-settings`
3. Minimal specialArgs: `{ inherit self; }` or none
4. Self-composition: Modules import via config.flake.modules, not relative paths
5. Declarative organization: Clear namespacing (base, hosts, lib, etc.)

**clan-infra Patterns (to be verified):**
1. Machine organization: ? (need to examine)
2. specialArgs usage: ? (Story 1.4 noted "minimal", need specifics)
3. Module exports: ? (do they export to namespace?)
4. Srvos imports: ? (how do they access inputs.srvos without inputs in specialArgs?)
5. Scale validation: 10+ machines in production, patterns proven

**Questions to Answer:**
- Does clan inventory + manual imports scale acceptably?
- Is dendritic automatic discovery compatible with clan's machine inventory?
- Can modules access flake inputs without inputs in specialArgs?
- Is there a hybrid approach: clan patterns + dendritic organization?

### Success Criteria

**Minimum Success (All Outcomes):**
- Comprehensive evaluation documented with file:line evidence
- Decision made (Outcome A/B/C) with clear rationale
- Trade-offs understood: dendritic purity vs clan pragmatism
- Recommendations provided for Phase 1 (cinnabar)
- Story 1.2 marked complete with architectural assessment

**Additional Success for Outcome B:**
- Refactoring implemented successfully
- All validation checks pass (nix flake check, builds, terraform, VMs stable)
- Improvements documented: what changed, why, what benefits
- Patterns ready for Stories 1.7-1.8 (GCP deployment)

**Documentation Success:**
- DENDRITIC-NOTES.md or equivalent comprehensive document
- Clear guidance for future developers
- Reusable patterns identified and documented
- Pain points acknowledged with mitigation strategies

### References

- [Prerequisite: docs/notes/development/work-items/1-1-prepare-existing-test-clan-repository-for-validation.md]
- [Context: docs/notes/development/work-items/1-4-create-hetzner-terraform-config-and-host-modules.md#specialArgs-pattern]
- [Context: docs/notes/development/work-items/1-5-deploy-hetzner-vm-and-validate-stack.md#terraform-toggle-refactoring]
- [Reference: ~/projects/nix-workspace/clan-infra/ - Proven clan patterns]
- [Reference: ~/projects/nix-workspace/dendritic-flake-parts/ - Dendritic core patterns]
- [Reference: ~/projects/nix-workspace/mightyiam-dendritic-infra/ - Real-world dendritic example]
- [Source: docs/notes/development/epic-1-infrastructure-restructure-proposal.md#Story-1.2]
- [Source: docs/notes/development/decisions/2025-11-03-defer-dendritic-pattern.md]

## Dev Agent Record

### Context Reference

<!-- Path to story context XML will be added here by story-context workflow -->

### Agent Model Used

<!-- Agent model name and version will be added during story execution -->

### Debug Log References

<!-- Links to debug logs will be added during story execution -->

### Completion Notes List

<!-- Completion notes will be added during story execution -->

### File List

<!-- Files created/modified will be documented during story execution -->

## Change Log

**2025-11-05 (Story Update - Post-Story 1.5 Reevaluation):**
- Story 1.2 reevaluated based on infrastructure maturity after Story 1.5 completion
- Status changed: deferred → ready-for-dev (time to evaluate before GCP expansion)
- Complete rewrite of acceptance criteria to reflect evaluation-focused approach:
  - Original ACs: Implementation-focused (add import-tree, create base module, etc.)
  - Updated ACs: Evaluation-focused (assess patterns, execute decision framework, document)
  - Decision tree added: Outcome A (compliant), B (easy refactor), C (defer)
- Added comprehensive context from Stories 1.1-1.5:
  - Story 1.4: specialArgs rationale documented
  - Story 1.5: Scalable pattern value demonstrated (terraform toggle refactoring)
  - Current state: 2 operational VMs, proven patterns, clean architecture
- Updated tasks section with detailed evaluation methodology:
  - Task 1: Comprehensive architectural assessment (6 subtasks)
  - Task 2: Decision framework execution (5 subtasks)
  - Task 3: Module organization evaluation (4 subtasks)
  - Task 4: specialArgs compatibility analysis (4 subtasks)
  - Task 5: Optional refactoring if Outcome B (7 subtasks)
  - Task 6: Comprehensive documentation (4 subtasks)
- Added extensive Dev Notes section:
  - Strategic context: Why deferred, why now, why matters
  - Learnings from Stories 1.1-1.5 with key findings
  - Cross-references to dendritic exemplar repositories
  - Expected evaluation methodology with time estimates
  - Time budget constraints (4-8 hours maximum)
  - Decision framework details (indicators for each outcome)
  - Architecture patterns to evaluate (current, dendritic, clan-infra)
  - Success criteria for each outcome path
- Estimated effort: 4-8 hours (2-4 evaluation + 0-4 implementation based on outcome)
- Risk level: Low-Medium (evaluation low risk, refactoring medium risk if complex)
- All updates maintain consistency with Stories 1.4-1.5 approved patterns
- Story ready for evaluation now before Stories 1.7-1.8 (GCP deployment)
