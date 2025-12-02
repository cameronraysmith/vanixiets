# Story 8.9: Validate Cross-References and Navigation Discoverability

Status: drafted

## Story

As a documentation user,
I want to easily navigate between related documentation,
so that I can find information without getting lost in disconnected pages.

## Acceptance Criteria

### Link Validation (AC1-AC3)

1. **Zero broken internal links**: All internal links in `packages/docs/src/content/docs/` resolve to valid targets
2. **Automated validation passes**: `just docs-linkcheck` completes with zero failures
3. **Starlight build succeeds**: `bun run build` produces no link-related warnings or errors

### Bidirectional Reference Audit (AC4-AC7)

4. **Guides link to tutorials**: guides/*.md files contain links to relevant tutorials/*.md (reciprocal to Story 8.8's tutorial→guide links)
5. **Concepts link to guides**: concepts/*.md files contain "See also" links to related guides/*.md for practical application
6. **Reference docs link to usage context**: reference/*.md files link to guides demonstrating the referenced tools
7. **Index pages are complete**: All section index.md files enumerate their child documents with descriptions

### Navigation Path Analysis (AC8-AC10)

8. **Homepage persona entry points**: `index.mdx` provides clear entry paths for new users, contributors, and operators
9. **Common tasks within 2 clicks**: Bootstrap, deployment, secrets, and customization are findable within 2 navigation steps from homepage
10. **Sidebar navigation logical**: Starlight sidebar groups docs logically with appropriate ordering

### Story 8.7 Traceability Gaps (AC11-AC13)

11. **Requirements→ADR cross-references added**: Where requirements reference architectural decisions, ADR links are present
12. **ADR→code paths documented**: ADRs reference implementation paths (e.g., `modules/` locations) where applicable
13. **Context→requirements alignment validated**: Context docs (domain-model, project-scope) align with requirements docs

### Fix Implementation (AC14-AC16)

14. **Missing bidirectional links added**: All discovered unidirectional references have reciprocal links added
15. **Index pages updated**: Section index.md files updated with any missing child document references
16. **Navigation gaps addressed**: Homepage and sidebar updated to address any discoverability issues found

## Tasks / Subtasks

### Task 1: Automated Link Validation (AC: #1-3)

- [ ] Run `just docs-linkcheck` and capture output
- [ ] Run `bun run build` in packages/docs and review warnings
- [ ] Document any broken links discovered with file paths and line numbers
- [ ] Create fix list for Task 5 if issues found

### Task 2: Bidirectional Reference Audit (AC: #4-7)

- [ ] Audit tutorials/*.md for links TO guides (Story 8.8 created 15 guide links)
- [ ] Audit guides/*.md for reciprocal links TO tutorials
  - [ ] getting-started.md → bootstrap-to-activation.md
  - [ ] host-onboarding.md → darwin-deployment.md, nixos-deployment.md
  - [ ] secrets-management.md → secrets-setup.md
  - [ ] home-manager-onboarding.md → bootstrap-to-activation.md
- [ ] Audit concepts/*.md for links to related guides/*.md
  - [ ] dendritic-architecture.md → adding-custom-packages.md, handling-broken-packages.md
  - [ ] clan-integration.md → host-onboarding.md, secrets-management.md
  - [ ] multi-user-patterns.md → home-manager-onboarding.md
- [ ] Audit reference/*.md for links to usage guides
  - [ ] justfile-recipes.md → guides showing recipe usage
  - [ ] flake-apps.md → host-onboarding.md (darwin/os apps)
  - [ ] ci-jobs.md → about/contributing/testing.md
- [ ] Verify all section index.md files enumerate children
  - [ ] tutorials/index.md
  - [ ] guides/index.md (if exists, create if missing)
  - [ ] concepts/index.md
  - [ ] reference/index.md
  - [ ] development/index.md subdirectories

### Task 3: Navigation Path Analysis (AC: #8-10)

- [ ] Review index.mdx homepage for persona-based entry points
  - [ ] New user path to tutorials
  - [ ] Operator path to guides
  - [ ] Developer path to reference
  - [ ] Contributor path to about/contributing
- [ ] Test 2-click navigation for common tasks
  - [ ] Bootstrap/getting started: Homepage → tutorials/index → bootstrap-to-activation
  - [ ] Darwin deployment: Homepage → guides → host-onboarding
  - [ ] Secrets setup: Homepage → guides → secrets-management
  - [ ] CLI reference: Homepage → reference → justfile-recipes
- [ ] Review Starlight sidebar configuration in astro.config.mjs
- [ ] Document any navigation gaps for Task 5

### Task 4: Story 8.7 Traceability Gap Assessment (AC: #11-13)

- [ ] Review Story 8.7 audit results (story-8.7-amdire-audit-results.md lines 141-176)
- [ ] Identify cross-reference gaps addressable in this story scope
  - [ ] Requirements → ADR links (partial scope)
  - [ ] ADR → code path references (partial scope)
  - [ ] Context → requirements alignment (validation only, not full rewrite)
- [ ] Document which gaps are IN scope vs OUT of scope
- [ ] Note: Full remediation of 8.7 findings is 18-24h effort (separate work)

### Task 5: Fix Implementation (AC: #14-16)

- [ ] Fix broken links discovered in Task 1
- [ ] Add missing bidirectional links identified in Task 2
  - [ ] Add tutorial references to guides
  - [ ] Add guide references to concepts
  - [ ] Add usage links to reference docs
- [ ] Update section index files if incomplete
- [ ] Create guides/index.md if missing
- [ ] Update homepage entry points if needed
- [ ] Add selected traceability links from Task 4

### Task 6: Re-Validation (AC: #1-3, #14-16)

- [ ] Re-run `just docs-linkcheck` after fixes
- [ ] Re-run `bun run build` after fixes
- [ ] Verify all AC#1-16 with explicit evidence
- [ ] Update story status to review

## Dev Notes

### Validation Tools Available

**Automated link checking:**
- `just docs-linkcheck` - Runs link validation tool (configured in justfile)
- `bun run build` (in packages/docs) - Starlight build validates internal links

**Manual validation:**
- Starlight dev server: `just docs-dev` for visual navigation testing
- Sidebar configuration: `packages/docs/astro.config.mjs`

### Story 8.8 Cross-Reference Baseline

Story 8.8 created 31 cross-references from tutorials to other docs:

| Source Type | Target Type | Count |
|-------------|-------------|-------|
| tutorials/*.md | guides/*.md | 15 |
| tutorials/*.md | concepts/*.md | 12 |
| tutorials/*.md | reference/*.md | 4 |

This story validates these links work AND adds reciprocal links where missing.

[Source: docs/notes/development/work-items/8-8-create-tutorials-for-common-user-workflows.md#Completion-Notes-List]

### Story 8.7 Traceability Gaps (Partial Scope)

Story 8.7 identified traceability gaps requiring 18-24h remediation. This story addresses PARTIAL scope:

**IN SCOPE (cross-reference additions):**
- Add ADR links where requirements reference architecture decisions
- Add code path references to ADRs where implementation is documented
- Validate context→requirements alignment (flag misalignments, don't rewrite)

**OUT OF SCOPE (content rewrites):**
- Full current/target inversion fixes in context docs (4 critical files)
- 8-machine fleet updates across 9 stale files
- New ADR creation (ADR-0017 through ADR-0020)

[Source: docs/notes/development/work-items/story-8.7-amdire-audit-results.md#Traceability-Gaps]

### Bidirectional Linking Strategy

**Pattern for adding reciprocal links:**

1. **Guides referencing tutorials** (new in this story):
```markdown
## See Also

For a learning-oriented introduction, see the [Bootstrap Tutorial](/tutorials/bootstrap-to-activation).
```

2. **Concepts referencing guides** (enhance existing):
```markdown
## Practical Application

To apply these concepts, see:
- [Getting Started Guide](/guides/getting-started)
- [Host Onboarding Guide](/guides/host-onboarding)
```

3. **Reference docs linking to usage** (new in this story):
```markdown
## Usage Examples

For practical examples using these recipes, see:
- [Getting Started Guide](/guides/getting-started) (bootstrap recipes)
- [Host Onboarding Guide](/guides/host-onboarding) (deployment recipes)
```

### Research Stream Coverage

From documentation-coverage-analysis.md:

| Stream | Description | This Story Coverage |
|--------|-------------|---------------------|
| R20 | Cross-Reference Integrity | Primary focus (AC1-7, AC14) |
| R21 | Discoverability and Navigation | Secondary focus (AC8-10, AC15-16) |

[Source: docs/notes/development/research/documentation-coverage-analysis.md (lines 184-186)]

### Project Structure Notes

**Files to validate:**
```
packages/docs/src/content/docs/
├── tutorials/ (5 files from Story 8.8)
├── guides/ (7 files)
├── concepts/ (5 files including index)
├── reference/ (5 files from Story 8.6)
├── development/ (subdirectories with context, requirements, architecture, etc.)
├── about/ (contributing subdirectory)
└── index.mdx (homepage)
```

**Sidebar configuration:**
- `packages/docs/astro.config.mjs` contains Starlight sidebar groups

### Learnings from Previous Story

**From Story 8.8 (Status: review):**

- `bun run build` validates internal links during build
- `just docs-linkcheck` provides dedicated link validation
- 5 tutorial files created with 31 cross-references to validate
- Cross-reference format: `/guides/getting-started` (absolute paths from content root)
- Starlight builds 72 pages in current docs set
- All cross-references use consistent `/section/document` pattern

[Source: docs/notes/development/work-items/8-8-create-tutorials-for-common-user-workflows.md#Dev-Agent-Record]

### References

- [Epic 8: docs/notes/development/epics/epic-8-documentation-alignment.md] (lines 358-387)
- [Research Document: docs/notes/development/research/documentation-coverage-analysis.md] (R20, R21)
- [Story 8.7 Audit: docs/notes/development/work-items/story-8.7-amdire-audit-results.md]
- [Story 8.8 Tutorials: docs/notes/development/work-items/8-8-create-tutorials-for-common-user-workflows.md]

### NFR Coverage

| NFR | Coverage |
|-----|----------|
| NFR-8.9 | Documentation discoverability |

### Estimated Effort

| Task | Estimate | Notes |
|------|----------|-------|
| Task 1 (Link validation) | 0.5-1h | Automated + capture output |
| Task 2 (Bidirectional audit) | 2-3h | Manual review across sections |
| Task 3 (Navigation analysis) | 1-1.5h | Homepage + sidebar review |
| Task 4 (8.7 gap assessment) | 1-1.5h | Scope determination only |
| Task 5 (Fix implementation) | 2-4h | Depends on findings |
| Task 6 (Re-validation) | 0.5-1h | Verification pass |
| **Total** | **7-12 hours** | |

**Effort breakdown by type:**
- Validation effort: 3-5h (automated + manual review)
- Fix effort: 2-4h (depends on validation findings)
- Documentation updates: 1-2h (if needed)

## Dev Agent Record

### Context Reference

<!-- Path(s) to story context XML will be added here by context workflow -->

### Agent Model Used

<!-- To be filled by dev agent -->

### Debug Log References

### Completion Notes List

### File List

## Change Log

**2025-12-02 (Story Drafted):**
- Story file created from Epic 8 Story 8.9 specification
- Incorporated research streams R20, R21 from documentation-coverage-analysis.md
- 16 acceptance criteria mapped to 6 task groups
- Story 8.8 baseline documented (31 cross-references to validate)
- Story 8.7 traceability gaps scoped (partial coverage)
- Bidirectional linking strategy documented
- Previous story learnings incorporated from Story 8.8
- Estimated effort: 7-12 hours
