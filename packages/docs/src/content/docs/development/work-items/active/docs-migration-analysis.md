---
title: Documentation Migration Analysis
---

# Documentation migration analysis

Comprehensive review of ~/projects/nix-workspace/infra/docs/notes/ markdown files for factoring into the Diataxis+AMDiRE documentation structure at ~/projects/nix-workspace/infra/packages/docs/src/content/docs.

## Analysis summary

**Total files**: 43 markdown files
**Recommendation**: Keep 28 (65%), discard 15 (35%)
**Primary destinations**: guides/ (12), development/ (11), concepts/ (3), reference/ (2)
**Proposed additions**: docs/development/decisions/ for ADR-style architecture decisions

## Categorization

### Keep and migrate (28 files)

#### Architecture and design rationale

**Target**: `docs/development/architecture/` (existing) or new `docs/development/decisions/` (ADR-style)

1. **claude-code-multi-profile-system.md** → `development/decisions/0001-claude-code-multi-profile-system.md`
   - Status: Implemented 2025-10-15
   - High value: complete implementation doc with rationale, verification commands, future enhancements
   - Format: ADR-style (context, decision, consequences, implementation)
   - Refactor: Add ADR header (date, status: accepted/implemented)

2. **justfile-design-principles.md** → `development/decisions/0002-justfile-generic-over-specific.md`
   - Design principles with examples and enforcement
   - High value: prevents future anti-patterns
   - Refactor: Add ADR header, perhaps split examples to concepts/

3. **overlay-patterns.md** → `development/decisions/0003-overlay-composition-patterns.md`
   - Overlay structuring patterns
   - Keep for team alignment

#### Development guides (user-facing)

**Target**: `docs/guides/` (user-facing task-oriented)

4. **mcp-servers-guide.md** → `guides/mcp-servers-usage.md`
   - Already well-structured for users
   - Direct migration, no refactoring needed

5. **onboarding.md** → `guides/host-onboarding.md`
   - Comprehensive host onboarding procedure
   - High value operational guide
   - Direct migration

6. **home-manager-only-onboarding.md** → `guides/home-manager-onboarding.md`
   - Specialized onboarding variant
   - Keep for users who need home-manager-only setup

7. **nixpkgs-bisect-guide.md** → `guides/nixpkgs-bisect.md`
   - Troubleshooting workflow
   - Direct migration

8. **preview-version-usage.md** → `guides/semantic-release-preview.md`
   - Usage guide for preview versions
   - Direct migration

9. **multi-arch-container-builds.md** → `guides/multi-arch-containers.md`
   - Container build procedures
   - Refactor: May combine with other container docs

10. **colima-container-management.md** → `guides/container-runtime-setup.md`
    - Container runtime setup
    - Refactor: Combine with multi-arch if overlapping

11. **netbird-ssh-darwin-implementation.md** → `guides/netbird-ssh-setup.md`
    - Network setup guide
    - Refactor: Generalize title if applicable to more than just darwin

12. **test-nix-darwin-builds.md** → `guides/testing-nix-darwin.md`
    - Testing procedures
    - Direct migration

#### Development workflows and processes

**Target**: `docs/development/traceability/` or new `docs/development/workflows/`

13. **end-to-end-workflow.md** → `development/workflows/secrets-management.md`
    - Comprehensive secrets workflow
    - High value: operational reference
    - Refactor: Add index with quick navigation

14. **dual-remote-workflow.md** → `development/workflows/git-dual-remote.md`
    - Git workflow for dual remotes
    - Keep for team reference

15. **ci-testing-strategy.md** → `development/traceability/ci-philosophy.md`
    - CI testing philosophy and rationale
    - High value: explains "why" behind CI design
    - Direct migration

16. **semantic-release-preview-version.md** → `development/workflows/semantic-release.md`
    - Release workflow
    - Direct migration

#### Strategic planning and migration docs

**Target**: `docs/development/work-items/completed/` or new `docs/development/planning/`

17. **clan-integration/00-integration-plan.md** → `development/planning/clan-integration-plan.md`
    - Comprehensive migration plan
    - High value: strategic reference even after completion
    - Refactor: Add status updates as implementation progresses

18. **clan-integration/01-phase-0-validation.md** → `development/planning/clan-phase-0-validation.md`
19. **clan-integration/02-phase-1-vps-deployment.md** → `development/planning/clan-phase-1-vps.md`
20. **clan-integration/03-phase-2-blackphos-guide.md** → `development/planning/clan-phase-2-blackphos.md`
21. **clan-integration/04-migration-assessment.md** → `development/planning/clan-migration-assessment.md`
22. **clan-integration/README.md** → `development/planning/clan-integration-index.md`
   - All clan docs: valuable planning/implementation reference
   - Keep even after implementation for historical context and decision rationale

23. **nix-rosetta-builder/implementation-plan.md** → `development/planning/nix-rosetta-builder-plan.md`
24. **nix-rosetta-builder/bootstrap-caching-analysis.md** → `development/planning/nix-rosetta-caching.md`
    - Implementation planning docs
    - Keep for reference

25. **mcp/auggie-gpt-mcp-sops-integration-plan.md** → `development/planning/mcp-sops-integration.md`
    - Integration planning
    - Refactor: Consolidate the three MCP integration plan docs into one

#### Incident response and operational procedures

**Target**: `docs/development/workflows/` or new `docs/development/operations/`

26. **nixpkgs-incident-response.md** → `development/operations/nixpkgs-incident-response.md`
    - Systematic incident response workflow
    - High value: operational playbook
    - Direct migration

27. **nixpkgs-hotfixes.md** → `development/operations/nixpkgs-hotfixes.md`
    - Hotfix procedures
    - Keep with incident response

28. **sops-migration-summary.md** → `development/operations/sops-migration-summary.md`
    - Migration summary and procedures
    - Keep for historical context

### Discard (15 files)

#### Ephemeral session notes

1. **clan-integration/session.md**
   - Interactive prompt for Claude Code
   - Not documentation, discard
   - Alternative: Extract any unique insights to clan plan docs before discarding

#### Point-in-time analysis (historic value questionable)

2. **ci/ci-run-18500875303-analysis.md**
3. **ci/ci-run-18500875303-summary.md**
   - Specific to one CI run
   - Learnings captured in ci-resolution-summary.md
   - Discard after verifying no unique insights

4. **ci/cachix-push-pin-failure-analysis.md**
   - Deep technical analysis
   - May have value for troubleshooting
   - **Decision point**: Keep only if cachix race conditions are recurring issue, otherwise extract key insights to ci-resolution-summary and discard

5. **ci/ci-resolution-summary.md**
   - Final decision document (remove bws)
   - **Decision point**: Has some value as "lessons learned", but mostly historic
   - Recommendation: Extract "lessons learned" section to a more general troubleshooting guide, then discard

#### Overly specific implementation notes

6. **ci/landrun-aarch64-issue.md**
7. **ci/local-category-testing.md**
8. **ci/justfile-activation-redesign.md**
   - Likely superseded by ci-testing-strategy.md
   - Verify ci-testing-strategy.md has all the valuable content, then discard

#### Package-specific troubleshooting

9. **nvim-treesitter/lazyvim-compatibility-fix.md**
10. **nvim-treesitter/lazyvim-optimization-analysis.md**
    - Very specific to one package/config
    - Likely ephemeral unless recurring issue
    - Discard

#### Completed migrations

11. **ccstatusline-migration-plan.md**
    - Completed work, historic value only
    - Discard unless implementation has unique patterns worth preserving

#### Redundant integration docs

12. **integration/implementation-summary.md**
    - Verify not duplicate of something else
    - Likely redundant, discard

#### Duplicate MCP plans

13. **mcp/auggie-mcp-sops-integration-plan.md**
14. **mcp/claude-mcp-sops-integration-plan.md**
    - Keep only one consolidated version (see keep #25)
    - Discard duplicates after consolidation

#### System-specific

15. **unified-crypto-infrastructure-implementation.md**
    - Very detailed implementation doc
    - **Decision point**: If this is still in use, keep in development/architecture/
    - If superseded by end-to-end-workflow.md, discard after extracting unique content

## Proposed directory structure enhancements

Current Starlight docs structure:
```
docs/
├── guides/              # Existing
├── reference/           # Existing
└── index.mdx            # Existing
```

Proposed additions to match Diataxis+AMDiRE:

```
docs/
├── guides/              # Task-oriented how-tos (USER-FACING)
│   ├── existing files...
│   ├── mcp-servers-usage.md
│   ├── host-onboarding.md
│   ├── home-manager-onboarding.md
│   ├── nixpkgs-bisect.md
│   ├── semantic-release-preview.md
│   ├── multi-arch-containers.md
│   ├── container-runtime-setup.md
│   ├── netbird-ssh-setup.md
│   └── testing-nix-darwin.md
│
├── concepts/            # NEW: Understanding-oriented explanations
│   └── [future: extract conceptual content from design docs]
│
├── reference/           # Information-oriented reference
│   ├── existing files...
│   └── [API docs, configuration schemas]
│
├── about/               # NEW: Contributing, conduct, development links
│   └── index.md
│
└── development/         # AMDiRE development documentation
    ├── index.md         # Development overview and navigation
    │
    ├── decisions/       # NEW: Architecture Decision Records (ADR)
    │   ├── index.md
    │   ├── 0001-claude-code-multi-profile-system.md
    │   ├── 0002-justfile-generic-over-specific.md
    │   └── 0003-overlay-composition-patterns.md
    │
    ├── workflows/       # NEW: Development workflows and processes
    │   ├── index.md
    │   ├── secrets-management.md
    │   ├── git-dual-remote.md
    │   └── semantic-release.md
    │
    ├── operations/      # NEW: Operational procedures and incident response
    │   ├── index.md
    │   ├── nixpkgs-incident-response.md
    │   ├── nixpkgs-hotfixes.md
    │   └── sops-migration-summary.md
    │
    ├── planning/        # NEW: Strategic planning and migration docs
    │   ├── index.md
    │   ├── clan-integration-index.md
    │   ├── clan-integration-plan.md
    │   ├── clan-phase-0-validation.md
    │   ├── clan-phase-1-vps.md
    │   ├── clan-phase-2-blackphos.md
    │   ├── clan-migration-assessment.md
    │   ├── nix-rosetta-builder-plan.md
    │   ├── nix-rosetta-caching.md
    │   └── mcp-sops-integration.md
    │
    ├── architecture/    # EXISTING: System design and components
    │   ├── index.md
    │   └── architecture.md  # (existing)
    │
    ├── traceability/    # NEW: Requirements traceability
    │   ├── index.md
    │   ├── testing.md   # (existing from guides/)
    │   └── ci-philosophy.md
    │
    └── work-items/      # EXISTING: Implementation tracking
        ├── index.md
        ├── active/
        │   └── docs-migration-analysis.md  # (this document)
        ├── completed/
        └── backlog/
```

## Refactoring needs

### High priority

1. **ADR format standardization**: Add ADR headers to all files in development/decisions/
   ```markdown
   # ADR-NNNN: Title

   Status: [proposed|accepted|deprecated|superseded]
   Date: YYYY-MM-DD
   Deciders: [list]

   ## Context
   ## Decision
   ## Consequences
   ## Implementation
   ```

2. **MCP integration consolidation**: Merge 3 MCP integration plan files into one coherent document

3. **CI docs consolidation**: Verify ci-testing-strategy.md captures all valuable content from ci-resolution-summary and specific run analyses

4. **Container docs**: Consider merging multi-arch-containers.md and container-runtime-setup.md if overlapping

### Medium priority

5. **Index files**: Create index.md for each new subdirectory with navigation and overview

6. **Cross-references**: Update internal links after migration

7. **Extract concepts**: Identify conceptual content that could move to concepts/ directory

### Low priority

8. **Consolidate secrets docs**: end-to-end-workflow.md, sops-migration-summary.md, and unified-crypto might have redundancy

## Migration verification checklist

Before discarding any file:
- [ ] Verify no unique insights lost
- [ ] Check for cross-references from other docs
- [ ] Confirm superseded content captured elsewhere
- [ ] Git history preserved (files remain in git history even after deletion)

After migration:
- [ ] All internal links updated
- [ ] Index files created for new directories
- [ ] Starlight navigation updated in astro.config.mjs
- [ ] CI/CD references updated if applicable
- [ ] README.md updated to point to new structure

## Questions for clarification

1. **decisions/ vs architecture/**: Should ADR-style docs go in a new decisions/ directory or integrate into existing architecture/?

2. **planning/ retention policy**: Keep planning docs indefinitely or move to completed/ after implementation?

3. **Cachix analysis**: Is cachix race condition a recurring issue? If yes, keep the analysis; if no, extract insights and discard.

4. **Secrets docs redundancy**: Should we consolidate end-to-end-workflow.md, sops-migration-summary.md, and unified-crypto-infrastructure-implementation.md?

5. **concepts/ directory**: Should we create this now (empty but structured) or defer until we have content to populate it?

6. **Session notes policy**: clan-integration/session.md is a Claude Code prompt template - keep somewhere else (like .claude/commands/) or discard entirely?

## Implementation approach

Recommended sequence:

### Phase 1: Prepare structure
1. Create new subdirectories in docs/development/
2. Create index.md files with navigation
3. Update Starlight config

### Phase 2: Migrate high-value docs
1. Guides (12 files) - highest user impact
2. Decisions (3 files) - architectural reference
3. Planning (10 files) - strategic context

### Phase 3: Consolidate and refactor
1. Merge duplicate MCP docs
2. Verify CI doc consolidation
3. Add ADR headers to decisions
4. Create cross-references

### Phase 4: Clean up
1. Verify no unique insights in discard candidates
2. Delete 15 ephemeral/redundant files
3. Update all cross-references
4. Delete old docs/notes/ directory

### Phase 5: Validation
1. Build Starlight docs site
2. Verify all links work
3. Review navigation UX
4. Get team feedback

## Timeline estimate

- Phase 1: 1 hour (structure)
- Phase 2: 2-3 hours (migration)
- Phase 3: 2-3 hours (refactoring)
- Phase 4: 1 hour (cleanup)
- Phase 5: 1 hour (validation)

**Total: 7-9 hours** of focused work, can be done incrementally over 2-3 sessions.
