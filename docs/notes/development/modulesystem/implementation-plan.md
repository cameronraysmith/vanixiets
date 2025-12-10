---
title: Algebraic alignment implementation plan
---

# Algebraic alignment implementation plan

This plan implements the terminology migration from "flake-parts" to algebraically-grounded "deferred module" terminology across the vanixiets documentation.

## Executive summary

**Scope**:
- Documentation updates: 21 edits across 2 Tier 1 files
- Configuration changes: None required (100% purity compliance verified)
- New reference documents: 9 files created in docs/notes/development/modulesystem/

**Key outcome**: Documentation will explain WHY the dendritic pattern works (module system primitives) not just HOW to use it (flake-parts conventions).

**Status**: All reference documents complete, ready for Tier 1 documentation edits.

## Artifacts produced

| Phase | File | Purpose | Size |
|-------|------|---------|------|
| 1.1 | primitives.md | Mathematical foundations | 28 KB |
| 1.2 | canonical-urls.md | Reference links | 5 KB |
| 1.3 | flake-parts-abstraction.md | Abstraction analysis | 16 KB |
| 2.1 | doc-terminology-inventory.md | Current state | 21 KB |
| 2.2 | config-pattern-inventory.md | Pattern catalog | 24 KB |
| 3.1 | terminology-glossary.md | Mapping guide | 29 KB |
| 3.2 | algebraic-purity-criteria.md | Quality criteria | 22 KB |
| 4.1 | doc-update-analysis.md | Edit recommendations | 38 KB |
| 4.2 | config-purity-audit.md | Compliance verification | 20 KB |

All files location: `/Users/crs58/projects/nix-workspace/infra/docs/notes/development/modulesystem/`

## Implementation phases

### Phase A: Apply Tier 1 documentation edits (HIGH PRIORITY)

**Target files**:
1. `packages/docs/src/content/docs/concepts/dendritic-architecture.md` (12 edits)
2. `packages/docs/src/content/docs/development/architecture/adrs/0018-dendritic-flake-parts-architecture.md` (9 edits)

**Edit categories**:
- Foundation sections: Add "Understanding the mechanism" and "Module system foundation" sections
- Terminology precision: Update titles, core principles, pattern overviews
- Navigation: Add references to new modulesystem/ documents
- Comparison strengthening: Enhance architectural arguments with algebraic grounding

**Estimated effort**: 21 edits, approximately 2-3 hours (reading, applying, verifying)

**Validation approach**:
1. Build documentation site: `cd packages/docs && npm run build`
2. Verify all links to modulesystem/ docs resolve correctly
3. Review three-tier consistency (intuitive/computational/formal)
4. Ensure practical guidance remains accessible

---

### Phase B: Tier 2 documentation updates (MEDIUM PRIORITY)

**Target files** (from doc-terminology-inventory.md):
- ADR-0020: Clan integration architecture (15 "flake-parts" occurrences)
- ADR-0017: Overlays patterns (8 "flake-parts" occurrences)
- ADR-0019: Clan orchestration (12 "flake-parts" occurrences)
- architecture.md: High-level overview (18 "flake-parts" occurrences)
- architecture-overview.md: Detailed architecture (22 "flake-parts" occurrences)
- glossary.md: Terminology definitions (requires updates matching terminology-glossary.md)

**Approach**: Similar edits to Phase A, scaled appropriately:
- Add module system context to integration explanations
- Update terminology from "flake-parts module" to "deferred module" in conceptual contexts
- Add references to modulesystem/ foundation docs
- Preserve practical flake-parts terminology in usage examples

**Estimated effort**: Approximately 40-50 edits across 6 files, 4-6 hours

---

### Phase C: Cross-references and navigation (LOW PRIORITY)

**Objectives**:
- Add links from practical guides to foundation docs
- Update external references section in concepts docs
- Ensure modulesystem/ docs are discoverable from main documentation

**Specific updates**:
1. Add "See also: Module System Foundations" sections to practical guides
2. Update getting-started.md with one-time link to primitives.md
3. Enhance bootstrap-to-activation.md with module system context
4. Add modulesystem/ to documentation site navigation (if applicable)

**Estimated effort**: 1-2 hours

---

### Phase D: Ongoing maintenance (CONTINUOUS)

**Guidelines**:
1. Apply algebraic purity criteria to new module additions (use algebraic-purity-criteria.md checklist)
2. Use terminology glossary for new documentation (use terminology-glossary.md mapping table)
3. Reference primitives.md for mathematical grounding when explaining new patterns
4. Maintain three-tier explanation structure: intuitive → computational → formal

**Review checklist for new modules**:
```markdown
## Module system algebraic purity checklist

- [ ] New module exports use deferred function syntax
- [ ] No strict circular dependencies (build succeeds)
- [ ] Dependencies explicit via imports, not specialArgs (except inputs)
- [ ] Options use specific types (bool, enum, submodule) not generic escape hatches
- [ ] mkForce usage documented with justification comment
```

**Review checklist for new documentation**:
```markdown
## Documentation terminology consistency checklist

- [ ] Conceptual docs explain WHY (module system primitives) before HOW (flake-parts)
- [ ] "Deferred module" used when explaining mechanisms
- [ ] "Flake-parts module" used in practical examples (with foundation link)
- [ ] Three-tier structure maintained (intuitive/computational/formal)
- [ ] References to modulesystem/ docs present for deeper understanding
```

---

## Implementation order and dependencies

### Immediate (Week 1)

**Phase A: Tier 1 documentation edits**

Priority order within Phase A:

1. **Foundation sections** (Edits 4, 13)
   - Add "Understanding the mechanism" to dendritic-architecture.md
   - Add "Module system foundation" to ADR-0018
   - **Why first**: Establishes three-layer model used throughout other edits
   - **No dependencies**: Can be added independently

2. **Terminology precision** (Edits 1-3, 14)
   - Update titles, descriptions, opening statements, pattern overviews
   - **Dependency**: Foundation sections should be in place for context
   - **Impact**: Aligns terminology with algebraic grounding

3. **Mechanism explanations** (Edits 5-11, 15)
   - Update module structure, namespace merging, auto-discovery sections
   - **Dependency**: Foundation sections and terminology updates
   - **Impact**: Clarifies handoff between framework and module system

4. **Comparisons and integration** (Edits 9-11, 16-20)
   - Update nixos-unified comparison, flake-parts comparison, clan integration
   - Update comparison table, alternatives analysis, positive consequences
   - **Dependency**: All previous edits (builds on established terminology)
   - **Impact**: Strengthens architectural arguments with algebraic foundation

5. **Navigation** (Edits 12, 21)
   - Add references to modulesystem/ foundation docs
   - **Dependency**: All documentation edits complete
   - **Impact**: Enables reader navigation to deeper understanding

**Deliverable**: Two updated Tier 1 files with algebraic grounding, verified build

---

### Short-term (Week 2-3)

**Phase B: Tier 2 documentation updates**

Similar structure to Phase A, applied to integration and architecture docs:
- ADR-0020, ADR-0017, ADR-0019 (architectural decisions)
- architecture.md, architecture-overview.md (high-level explanations)
- glossary.md (terminology definitions)

**Deliverable**: Six updated Tier 2 files, consistent terminology across architecture docs

---

### Medium-term (Month 1-2)

**Phase C: Cross-references and navigation**

- Update practical guides with links to foundations
- Enhance getting-started and bootstrap docs with module system context
- Verify all references are discoverable and coherent

**Deliverable**: Complete documentation set with clear navigation paths

---

### Ongoing

**Phase D: Maintenance and consistency**

- Apply purity criteria to new modules (use checklist)
- Use terminology glossary for new docs (use mapping table)
- Review PRs for algebraic consistency

**Deliverable**: Sustained quality and consistency

---

## Detailed edit summary

### File 1: concepts/dendritic-architecture.md

**Purpose**: Primary conceptual explanation of the dendritic pattern

**Current state**: 347 lines, explains WHAT and HOW, missing WHY

**Edits**: 12 changes (numbered 1-12 in doc-update-analysis.md)

| Edit | Type | Line(s) | Summary |
|------|------|---------|---------|
| 1 | Frontmatter | 2-3 | Update title/description from "flake-parts" to algebraic terms |
| 2 | Opening | 6 | Ground in module system primitives before framework |
| 3 | Core principle | 22-25 | Explain fixpoint enables cross-cutting concerns |
| 4 | **New section** | After 25 | Add "Understanding the mechanism" three-layer model |
| 5 | Section header | 58 | Add "composition" to module structure header |
| 6 | Namespace merge | 88-94 | Credit deferredModule monoid, not import-tree magic |
| 7 | Auto-discovery | 153 | Clarify import-tree feeds module system imports |
| 8 | **Addition** | After 174 | Explain handoff: discovery → evalModules → fixpoint |
| 9 | Comparison | 220-224 | Highlight compositional difference (deferred modules) |
| 10 | vs flake-parts | 226-228 | Both use same primitives, dendritic adds conventions |
| 11 | Clan integration | 236-240 | Explain integration via shared module system |
| 12 | **New section** | After 337 | Add "Module system foundations" references |

**Impact**: Readers understand WHY dendritic works (module system) and HOW to use it (flake-parts)

---

### File 2: development/architecture/adrs/0018-dendritic-flake-parts-architecture.md

**Purpose**: Architectural decision record explaining pattern adoption

**Current state**: 323 lines, explains WHAT decision and alternatives, lacks foundational WHY

**Edits**: 9 changes (numbered 13-21 in doc-update-analysis.md)

| Edit | Type | Line(s) | Summary |
|------|------|---------|---------|
| 13 | **New section** | After 47 | Add "Module system foundation" (algebraic argument) |
| 14 | Pattern overview | 49-52 | Add type information, evaluation context |
| 15 | Namespace exports | 88-106 | Explain deferredModule deferred evaluation semantics |
| 16 | Comparison table | 166 | Add rows for module type, composition mechanism |
| 17 | Alternative 1 | After 183 | Strengthen nixos-unified argument (lacks deferred modules) |
| 18 | Alternative 2 | After 192 | Clarify raw flake-parts uses same primitives |
| 19 | Alternative 3 | After 207 | Distinguish primitives (shared) from conventions (flake-parts) |
| 20 | Positive consequences | 210-216 | Lead with compositional semantics (algebraic structure) |
| 21 | **New section** | After 313 | Add "Module system foundations" references |

**Impact**: ADR explains WHY pattern was chosen with algebraic grounding, not just organizational convenience

---

## Validation checklist

Before considering Phase A complete:

### Build verification
- [ ] Documentation site builds without errors: `cd packages/docs && npm run build`
- [ ] No broken links to modulesystem/ docs
- [ ] All internal cross-references resolve correctly

### Content quality
- [ ] Three-tier explanations present in both Tier 1 docs (intuitive/computational/formal references)
- [ ] Foundation sections (Edits 4, 13) establish module system grounding
- [ ] Terminology consistent with glossary (deferred module, fixpoint, evalModules)
- [ ] Practical guidance clarity not regressed (examples still clear)

### Navigation
- [ ] Links to primitives.md work (Edits 4, 12, 13, 21)
- [ ] Links to flake-parts-abstraction.md work (Edits 4, 12, 21)
- [ ] Links to terminology-glossary.md work (Edits 12, 21)
- [ ] External references section updated

### Comprehension paths (simulate reader journeys)
- [ ] **New user**: Can understand WHAT, HOW, and WHY from dendritic-architecture.md
- [ ] **Maintainer**: Can evaluate architectural decisions from ADR-0018 with algebraic foundation
- [ ] **Interested reader**: Can navigate to deeper understanding via modulesystem/ links
- [ ] **Practical user**: Can still follow examples without understanding category theory

---

## Success criteria

### Knowledge transfer goals

1. **Reader can understand WHY dendritic pattern works**
   - Module system primitives (deferredModule, evalModules, fixpoint)
   - Algebraic structure (monoid composition, least fixpoint)
   - Compositional properties (namespace merging, cross-cutting concerns)

2. **Reader can learn HOW to use it**
   - Flake-parts conventions (perSystem, flake.modules namespace)
   - Dendritic organization (auto-discovery, aspect-oriented structure)
   - Practical examples (adding modules, configuring machines)

3. **Interested reader can go deeper**
   - Three-tier explanations (intuitive → computational → formal)
   - References to canonical sources (nix.dev, nixpkgs source)
   - Navigation to modulesystem/ foundation docs

4. **Practical guides remain accessible**
   - No requirement to understand fixpoint semantics to use pattern
   - Examples use familiar flake-parts terminology
   - Foundation links available but not blocking

### Quality metrics

1. **Terminology consistency**: 90%+ of conceptual explanations use algebraic terms with framework context
2. **Navigation completeness**: All Tier 1 docs link to modulesystem/ foundations
3. **Build success**: Documentation site builds without errors or warnings
4. **Comprehension paths**: All four reader journeys work (verified manually)

---

## Recommendations

### Immediate actions (this sprint)

1. **Apply Phase A edits to Tier 1 docs**
   - Priority: Foundation sections (Edits 4, 13)
   - Then: Terminology precision (Edits 1-3, 14)
   - Then: Mechanism explanations (Edits 5-11, 15)
   - Then: Comparisons (Edits 9-11, 16-20)
   - Finally: Navigation (Edits 12, 21)

2. **Validate with build and review**
   - Build documentation site
   - Verify links and cross-references
   - Review for clarity and consistency
   - Test comprehension paths

### Short-term actions (next sprint)

1. **Apply Phase B to integration docs**
   - ADR-0020 (clan integration)
   - ADR-0017 (overlays)
   - ADR-0019 (clan orchestration)
   - architecture.md and architecture-overview.md
   - glossary.md

2. **Review and iterate**
   - Gather feedback on Tier 1 changes
   - Adjust approach if needed
   - Ensure consistency across doc tiers

### Ongoing practices

1. **Use glossary as reference for new documentation**
   - Context-specific usage guide (conceptual vs practical vs code)
   - Quick reference mapping table (current term → algebraic term)
   - Recommended text patterns

2. **Apply purity criteria to new modules**
   - Review checklist in algebraic-purity-criteria.md
   - Validation approach (static analysis, build testing)
   - Severity levels (HIGH/MEDIUM/LOW priorities)

3. **Consider publishing primitives.md as community resource**
   - Three-tier explanations useful beyond this project
   - Fills gap in nix.dev module system documentation
   - Could contribute to nixpkgs documentation efforts

---

## Risk assessment

### Risk 1: Breaking practical guidance clarity

**Likelihood**: LOW
**Impact**: HIGH (users can't understand how to use pattern)
**Mitigation**:
- Preserve HOW explanations alongside WHY foundations
- Use three-tier structure (intuitive first, formal last)
- Keep examples using familiar flake-parts terminology
- Test comprehension paths to verify accessibility

### Risk 2: Overwhelming readers with mathematical formalism

**Likelihood**: LOW
**Impact**: MEDIUM (documentation seems intimidating)
**Mitigation**:
- Foundation sections provide intuitive explanations first
- Formal characterizations relegated to reference docs (primitives.md)
- Clear separation between "what you need to know to use this" vs "why it works"
- Links to deeper understanding optional, not required

### Risk 3: Maintaining terminology consistency

**Likelihood**: MEDIUM
**Impact**: MEDIUM (confusion from mixed terminology)
**Mitigation**:
- Use terminology-glossary.md as reference for all new docs
- Review checklist includes terminology consistency
- Grep patterns in validation approach detect inconsistencies
- Phase D maintenance includes consistency reviews

### Risk 4: Link rot to modulesystem/ docs

**Likelihood**: LOW
**Impact**: MEDIUM (broken navigation to foundations)
**Mitigation**:
- All modulesystem/ docs already created and committed
- Build validation checks link integrity
- Documentation site build will catch broken links
- Internal docs unlikely to move (not external dependencies)

---

## Configuration changes required

**None.**

The configuration purity audit (config-purity-audit.md) verified 100% compliance with algebraic purity criteria:

1. ✓ **Deferred module purity**: All 10 sampled modules use proper function exports
2. ✓ **Fixpoint safety**: No circular dependencies, build succeeds
3. ✓ **Explicit imports**: specialArgs limited to standard patterns (inputs, flake)
4. ✓ **Option type correctness**: All options use appropriate specific types
5. ✓ **Merge semantics awareness**: mkForce usage is intentional and documented

The existing configuration already follows algebraic best practices.
This documentation migration requires no code changes, only documentation updates to explain the algebraic foundation that the code already embodies.

---

## Appendix A: Three-tier explanation pattern

All foundation documents use this structure for key concepts:

### Tier 1: Intuitive explanation

**Audience**: All readers, including beginners
**Goal**: Conceptual understanding without formal prerequisites
**Example**: "A deferred module waits to be evaluated until the final configuration is known."

### Tier 2: Computational explanation

**Audience**: Developers implementing patterns
**Goal**: How it works in Nix (function calls, data structures, evaluation order)
**Example**: "The module system collects all deferred modules into an imports list, then computes a fixpoint..."

### Tier 3: Formal characterization

**Audience**: Readers seeking deep understanding, contributors to module system
**Goal**: Mathematical foundations, category theory, type theory
**Example**: "A deferred module is a morphism in the Kleisli category $\mathbf{Kl}(T)$ where $T$ is the reader monad..."

**Application in edits**: Foundation sections (Edits 4, 13) use Tier 1-2, link to primitives.md for Tier 3

---

## Appendix B: File size and scope

### Reference documents (203 KB total)

1. primitives.md: 28 KB (mathematical foundations)
2. canonical-urls.md: 5 KB (reference links)
3. flake-parts-abstraction.md: 16 KB (abstraction analysis)
4. doc-terminology-inventory.md: 21 KB (current state analysis)
5. config-pattern-inventory.md: 24 KB (pattern catalog)
6. terminology-glossary.md: 29 KB (mapping guide)
7. algebraic-purity-criteria.md: 22 KB (quality criteria)
8. doc-update-analysis.md: 38 KB (edit recommendations)
9. config-purity-audit.md: 20 KB (compliance verification)

### Target documentation files

**Tier 1 (Phase A)**:
1. dendritic-architecture.md: 347 lines, 12 edits
2. ADR-0018: 323 lines, 9 edits

**Tier 2 (Phase B)**:
3. ADR-0020: ~250 lines, ~8 edits (estimated)
4. ADR-0017: ~200 lines, ~6 edits (estimated)
5. ADR-0019: ~280 lines, ~9 edits (estimated)
6. architecture.md: ~400 lines, ~12 edits (estimated)
7. architecture-overview.md: ~500 lines, ~15 edits (estimated)
8. glossary.md: ~150 lines, complete rewrite based on terminology-glossary.md

**Total estimated edits**: 21 (Phase A) + 50 (Phase B) + navigation (Phase C) = ~75 edits

---

## Appendix C: Quick reference for implementers

### When to use "deferred module" vs "flake-parts module"

From terminology-glossary.md Quick reference mapping:

| Context | Use | Example |
|---------|-----|---------|
| Explaining why patterns work | "deferred module" | "The pattern works because deferred modules form a monoid" |
| Explaining underlying mechanism | "deferred module composition" | "Namespace merging is deferredModule monoid composition" |
| Practical instructions | "flake-parts module" | "Create a new flake-parts module in modules/services/" |
| Framework features | "perSystem", "flake.modules namespace" | "Use perSystem for per-architecture evaluation" |

### When to link to foundation docs

**Always link** (first mention in document):
- Conceptual explanations introducing module system concepts
- Architectural decisions relying on compositional properties
- Integration explanations showing shared foundations

**Optional link** (reader benefit):
- Practical guides (one-time reference for interested readers)
- Examples (comment with link to deeper explanation)

**Never link** (wrong context):
- Operational guides (focus on tasks, not theory)
- Reference documentation (assume reader knows foundations)

### Verification commands

```bash
# Build documentation
cd /Users/crs58/projects/nix-workspace/infra/packages/docs
npm run build

# Check link integrity
rg '\[.*\]\(/notes/development/modulesystem/' packages/docs/src/content/docs/

# Verify terminology consistency
rg "deferred module" packages/docs/src/content/docs/concepts/
rg "flake-parts module" packages/docs/src/content/docs/concepts/
```

---

## Summary

This plan implements algebraic alignment by adding module system foundations to Tier 1 conceptual documentation (21 edits across 2 files), with clear validation criteria, risk mitigation, and ongoing maintenance guidelines.

**Key outcomes**:
- Documentation explains WHY (module system primitives) and HOW (flake-parts conventions)
- Three-tier structure enables readers to choose their depth
- Configuration requires no changes (already 100% algebraically pure)
- Foundation documents support ongoing consistency and quality

**Next action**: Apply Phase A edits to dendritic-architecture.md and ADR-0018, starting with foundation sections (Edits 4, 13).
