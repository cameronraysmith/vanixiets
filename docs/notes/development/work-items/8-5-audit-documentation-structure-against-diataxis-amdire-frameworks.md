# Story 8.5: Audit Documentation Structure Against Diataxis/AMDiRE Frameworks

Status: drafted

## Story

As a documentation maintainer,
I want to audit the documentation structure against Diataxis and AMDiRE frameworks,
so that I have a prioritized inventory of structural gaps to address in subsequent stories.

## Acceptance Criteria

### Diataxis Framework Audit (AC1-AC4)

1. **Tutorials directory audit**: Verify `tutorials/` directory state, document that it is EMPTY (CRITICAL gap), identify tutorial content needed based on research streams R1-R4 (bootstrap journey, secrets lifecycle, darwin deployment, nixos deployment)
2. **Guides directory audit**: Verify all 7 files in `guides/` are complete and coherent, cross-reference with research stream R10, identify any missing how-to content
3. **Concepts directory audit**: Verify all 4 files in `concepts/` provide adequate understanding-oriented explanations, identify conceptual gaps not covered by existing documents
4. **Reference directory audit**: Verify `reference/` directory has only 1 file (HIGH gap), identify missing reference content (justfile recipes, flake apps, module options, CLI commands)

### AMDiRE Framework Audit (AC5-AC9)

5. **Context documentation audit**: Verify `development/context/` (6 files) reflects current project state post-Epic 7 GCP deployment
6. **Requirements documentation audit**: Verify `development/requirements/` (7 files) aligns with implemented dendritic + clan functionality
7. **Architecture documentation audit**: Verify `development/architecture/` (18 files: 16 ADRs + 2 others) are current and properly cross-referenced
8. **Traceability documentation audit**: Verify `development/traceability/` (2 files only - HIGH gap), identify missing test harness and validation documentation
9. **Operations documentation audit**: Verify `development/operations/` (1 file only - HIGH gap), identify missing runbooks for deployment, rollback, monitoring

### Work Items Structure (AC10)

10. **Work-items directory audit**: Verify `development/work-items/` structure (index + empty subdirs - MEDIUM gap), document current external tracking location

### Output Artifact (AC11-AC12)

11. **Gap inventory created**: Produce comprehensive gap inventory with severity ratings (CRITICAL/HIGH/MEDIUM/LOW) for each identified gap
12. **Priority ranking provided**: Rank gaps by impact on user success and development productivity, providing recommended action order for Stories 8.6, 8.7, 8.8, 8.9, 8.10

## Tasks / Subtasks

### Task 1: Initialize Audit Environment (AC: ALL)

- [ ] Read research document completely: `docs/notes/development/research/documentation-coverage-analysis.md`
- [ ] Verify directory structure matches research document analysis (62 files, 17 directories)
- [ ] Create output file scaffold at `docs/notes/development/work-items/story-8.5-structure-audit-results.md`
- [ ] Document audit methodology: file counts, gap classification criteria, severity ratings

### Task 2: Audit Diataxis Framework - Tutorials (AC: #1)

- [ ] Verify `packages/docs/src/content/docs/tutorials/` directory exists but is empty
- [ ] Cross-reference with research streams R1-R4 for needed tutorial content:
  - [ ] R1: Bootstrap-to-Activation Journey tutorial
  - [ ] R2: Secrets Lifecycle Complete tutorial
  - [ ] R3: Darwin Deployment Pipeline tutorial
  - [ ] R4: NixOS/Cloud Deployment Pipeline tutorial
- [ ] Document gap severity: CRITICAL (new users lack guided learning paths)
- [ ] Record findings in audit results document

### Task 3: Audit Diataxis Framework - Guides (AC: #2)

- [ ] Enumerate all 7 files in `packages/docs/src/content/docs/guides/`:
  - [ ] getting-started.md
  - [ ] host-onboarding.md
  - [ ] home-manager-onboarding.md
  - [ ] adding-custom-packages.md
  - [ ] secrets-management.md
  - [ ] handling-broken-packages.md
  - [ ] mcp-servers-usage.md
- [ ] Verify each guide is task-oriented (how-to format)
- [ ] Cross-reference with research stream R10 for completeness
- [ ] Identify any missing how-to guides (compare to justfile recipe groups)
- [ ] Document gap severity: Verify or adjust from initial assessment
- [ ] Record findings in audit results document

### Task 4: Audit Diataxis Framework - Concepts (AC: #3)

- [ ] Enumerate all 4 files in `packages/docs/src/content/docs/concepts/`:
  - [ ] nix-config-architecture.md
  - [ ] dendritic-architecture.md
  - [ ] clan-integration.md
  - [ ] multi-user-patterns.md
- [ ] Verify each concept is understanding-oriented (explains mental model)
- [ ] Cross-reference with research stream R6 for conceptual coverage
- [ ] Identify conceptual gaps (e.g., terranix patterns, overlay architecture)
- [ ] Document gap severity based on findings
- [ ] Record findings in audit results document

### Task 5: Audit Diataxis Framework - Reference (AC: #4)

- [ ] Enumerate files in `packages/docs/src/content/docs/reference/`:
  - [ ] repository-structure.md (only file)
- [ ] Cross-reference with research stream R9 for missing reference content:
  - [ ] Justfile recipe reference (100+ recipes across 10 groups)
  - [ ] Flake apps reference (darwin, os, home, update, activate, activate-home)
  - [ ] Module options reference
  - [ ] CLI command reference
- [ ] Document gap severity: HIGH (users cannot discover available tooling)
- [ ] Record findings in audit results document

### Task 6: Audit AMDiRE Framework - Context (AC: #5)

- [ ] Enumerate all 6 files in `packages/docs/src/content/docs/development/context/`:
  - [ ] index.md
  - [ ] problem-domain.md
  - [ ] stakeholders.md
  - [ ] objectives.md
  - [ ] constraints.md
  - [ ] assumptions.md
- [ ] Cross-reference with research stream R11 for currency
- [ ] Verify context reflects post-Epic 7 state (6 machines, GCP infrastructure, dendritic + clan)
- [ ] Identify outdated or missing context
- [ ] Document gap severity based on findings
- [ ] Record findings in audit results document

### Task 7: Audit AMDiRE Framework - Requirements (AC: #6)

- [ ] Enumerate all 7 files in `packages/docs/src/content/docs/development/requirements/`:
  - [ ] index.md
  - [ ] functional-requirements.md
  - [ ] non-functional-requirements.md
  - [ ] darwin-requirements.md
  - [ ] nixos-requirements.md
  - [ ] secrets-requirements.md
  - [ ] ci-requirements.md
- [ ] Cross-reference with research stream R12 for implementation alignment
- [ ] Verify requirements match implemented dendritic + clan architecture
- [ ] Identify requirements that are outdated or untraced
- [ ] Document gap severity based on findings
- [ ] Record findings in audit results document

### Task 8: Audit AMDiRE Framework - Architecture (AC: #7)

- [ ] Enumerate all 18 files in `packages/docs/src/content/docs/development/architecture/`:
  - [ ] index.md
  - [ ] nixpkgs-hotfixes.md
  - [ ] adrs/index.md
  - [ ] 16 ADR files (adr-0001 through adr-0016)
- [ ] Cross-reference with research stream R13 for ADR currency
- [ ] Verify ADRs reflect post-migration decisions (clan-core, dendritic, GCP)
- [ ] Check ADR cross-references to requirements and code
- [ ] Identify ADRs needing updates or supersession
- [ ] Document gap severity based on findings
- [ ] Record findings in audit results document

### Task 9: Audit AMDiRE Framework - Traceability (AC: #8)

- [ ] Enumerate all 2 files in `packages/docs/src/content/docs/development/traceability/`:
  - [ ] index.md
  - [ ] ci-cd-setup.md
- [ ] Cross-reference with research stream R15 for missing content:
  - [ ] Test harness documentation (nix-unit, modules/checks/)
  - [ ] Test case enumeration
  - [ ] Coverage reports
  - [ ] Validation matrices
- [ ] Document gap severity: HIGH (testing approach undocumented)
- [ ] Record findings in audit results document

### Task 10: Audit AMDiRE Framework - Operations (AC: #9)

- [ ] Enumerate files in `packages/docs/src/content/docs/development/operations/`:
  - [ ] troubleshooting-ci-cache.md (only file)
- [ ] Cross-reference with research stream R14 for missing runbooks:
  - [ ] Deployment runbooks (darwin-rebuild, clan machines install)
  - [ ] Rollback procedures
  - [ ] Incident response
  - [ ] Monitoring setup
- [ ] Document gap severity: HIGH (operational procedures undocumented)
- [ ] Record findings in audit results document

### Task 11: Audit Work-Items Structure (AC: #10)

- [ ] Enumerate `packages/docs/src/content/docs/development/work-items/` structure:
  - [ ] index.md
  - [ ] epics/ (empty subdirectory)
  - [ ] stories/ (empty subdirectory)
  - [ ] tasks/ (empty subdirectory)
- [ ] Note current external tracking location: `docs/notes/development/work-items/`
- [ ] Assess whether Starlight site should include work items or link to external location
- [ ] Document gap severity: MEDIUM (structure exists but content external)
- [ ] Record findings in audit results document

### Task 12: Produce Gap Inventory and Priority Ranking (AC: #11-12)

- [ ] Compile all gaps from Tasks 2-11 into structured inventory table:
  ```markdown
  | Gap ID | Directory | Type | Severity | Description | Proposed Fix | Estimated Effort |
  |--------|-----------|------|----------|-------------|--------------|------------------|
  ```
- [ ] Apply severity ratings consistently:
  - CRITICAL: Blocks user success (tutorials empty)
  - HIGH: Significant friction (reference sparse, operations sparse)
  - MEDIUM: Minor friction (work-items external)
  - LOW: Nice-to-have improvements
- [ ] Create priority ranking for subsequent stories:
  - Story 8.6: CLI tooling reference (justfile recipes, flake apps)
  - Story 8.7: AMDiRE development docs audit (context, requirements, ADRs)
  - Story 8.8: Tutorials creation (bootstrap, secrets, darwin, nixos journeys)
  - Story 8.9: Cross-reference validation (link integrity, navigation)
  - Story 8.10: Test harness documentation (CI-local parity)
- [ ] Document recommended execution order with rationale
- [ ] Finalize audit results document

### Task 13: Validate and Complete (AC: ALL)

- [ ] Verify audit results document is complete with all sections
- [ ] Cross-check gap inventory against research document
- [ ] Verify Starlight build: `nix build .#docs` or `bun run build`
- [ ] Commit audit results: `docs(story-8.5): complete documentation structure audit results`
- [ ] Update sprint-status.yaml: story-8-5 = "drafted" → "in-progress" → "review"

## Dev Notes

### Audit Methodology

This is an AUDIT story, not a creation story.
The deliverable is `story-8.5-structure-audit-results.md` containing gap inventory and recommendations, not actual documentation fixes.

**Audit Approach:**
1. Enumerate actual directory contents
2. Compare against framework expectations (Diataxis + AMDiRE)
3. Cross-reference with research streams R8, R9, R10, R14, R15
4. Classify gaps by severity
5. Produce actionable inventory for subsequent stories

### Framework References

**Diataxis Framework (User Documentation):**
- tutorials/ - Learning-oriented (new user experiences)
- guides/ - Task-oriented (accomplishing goals)
- concepts/ - Understanding-oriented (mental models)
- reference/ - Information-oriented (specifications)

**AMDiRE Framework (Development Documentation):**
- development/context/ - Problem domain, stakeholders, objectives
- development/requirements/ - Functional and non-functional requirements
- development/architecture/ - Design decisions and ADRs
- development/traceability/ - Test framework, validation
- development/work-items/ - Implementation tracking

### Research Streams Scope

From `docs/notes/development/research/documentation-coverage-analysis.md`:

| Stream | Scope | Relevance to Story 8.5 |
|--------|-------|------------------------|
| R8 | Tutorials Structure Design | Diataxis tutorials/ audit |
| R9 | Reference Documentation Gaps | Diataxis reference/ audit |
| R10 | Guides Completeness Audit | Diataxis guides/ audit |
| R14 | Operations Runbook Assessment | AMDiRE operations/ audit |
| R15 | Traceability Enhancement | AMDiRE traceability/ audit |

### Expected Gap Summary (From Research)

| Directory | Expected State | Gap Severity |
|-----------|----------------|--------------|
| tutorials/ | EXISTS but EMPTY | CRITICAL |
| reference/ | 1 file only | HIGH |
| development/operations/ | 1 file only | HIGH |
| development/traceability/ | 2 files only | HIGH |
| development/work-items/ | Index + empty subdirs | MEDIUM |
| guides/ | 7 files | Verify completeness |
| concepts/ | 4 files | Verify coverage |
| development/context/ | 6 files | Verify currency |
| development/requirements/ | 7 files | Verify alignment |
| development/architecture/ | 18 files | Verify currency |

### Project Structure Notes

**Audit Target:** `packages/docs/src/content/docs/`

**Output Artifact:** `docs/notes/development/work-items/story-8.5-structure-audit-results.md`

**Sprint Status File:** `docs/notes/development/sprint-status.yaml`

### Learnings from Previous Story

**From Story 8.4 (Status: review)**

- **Verification pattern**: Use `rg` commands to verify deprecated patterns removed
- **Starlight validation**: Build validation confirms doc changes don't break site
- **Atomic commits**: One commit per logical deliverable
- **Cross-references**: Link to related docs, document relationships
- **Platform awareness**: Document darwin vs NixOS differences where relevant

[Source: docs/notes/development/work-items/8-4-update-secrets-management-documentation.md#Dev-Agent-Record]

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md#Story-8.5]
- [Research Document: docs/notes/development/research/documentation-coverage-analysis.md]
- [Story 8.1 Audit (Content): docs/notes/development/work-items/story-8.1-audit-results.md]
- [Story 8.4 Secrets Docs: docs/notes/development/work-items/8-4-update-secrets-management-documentation.md]
- [Starlight Docs: packages/docs/src/content/docs/]

### Constraints

1. **Audit only** - Produce gap inventory, not fixes
2. **Framework alignment** - Use Diataxis + AMDiRE terminology consistently
3. **Research-backed** - All gaps should reference research streams
4. **Actionable output** - Gap inventory must enable Stories 8.6-8.10 execution
5. **Severity-based prioritization** - Rank gaps by user impact

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.5 | Framework compliance audit |
| NFR-8.1 | Zero deprecated references (verify maintained) |

### Estimated Effort

**3-4 hours** (audit and documentation)

- Task 1 (initialize): 0.25h
- Tasks 2-5 (Diataxis audit): 1h
- Tasks 6-10 (AMDiRE audit): 1h
- Tasks 11-12 (gap inventory): 1h
- Task 13 (validation): 0.5h

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

{{agent_model_name_version}}

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-12-02 (Story Drafted)**:
- Story file created from Epic 8 Story 8.5 specification
- Incorporated research document `documentation-coverage-analysis.md` as primary scope reference
- 12 acceptance criteria mapped to 13 task groups
- Research streams R8, R9, R10, R14, R15 documented as scope
- Expected gap summary included from research document analysis
- Learnings from Story 8.4 incorporated
- Output artifact: `story-8.5-structure-audit-results.md`
- Estimated effort: 3-4 hours
