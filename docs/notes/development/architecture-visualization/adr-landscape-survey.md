---
title: ADR landscape survey and placement recommendation
status: working-note
source-issue: nix-e3c.1
---

# ADR landscape survey and placement recommendation

## Summary of existing ADR usage in the repo

The repository contains two distinct ADR collections with different conventions.

Formal ADRs in `docs/development/architecture/adrs/` follow the AMDiRE documentation structure defined in `preferences-documentation`.
There are 17 ADRs (numbered 0001 through 0021, with gaps).
These use YAML frontmatter with titles, a categorized index (`index.md`), and a consistent structure of Status, Date, Scope, Related, Context, Decision, Alternatives Considered, Consequences (Positive/Negative/Neutral), Validation Evidence, and References.
Example: ADR-0019 (clan-core orchestration, 323 lines) demonstrates the full-fidelity pattern including detailed alternative evaluations, nuanced positive/negative/neutral consequence analysis, and both internal and external references.
The file naming uses zero-padded numbers with descriptive slugs: `0019-clan-core-orchestration.md`.

Working-note ADRs in `docs/notes/development/kubernetes/decisions/` contain 6 ADRs (ADR-001 through ADR-006).
These use a different naming convention (`ADR-001-local-dev-architecture.md` without zero-padding), lack frontmatter titles, and follow a simpler structure of Status, Context, Decisions (numbered sub-decisions with Context/Decision/Rationale/Alternatives), Consequences (Enabled/Constrained), and Related Decisions.
The structure is more compact and decision-focused, with sub-decisions bundled into a single ADR.

The two sets are not cross-referenced.
The working notes collection aligns with the `docs/notes/` lifecycle documented in `preferences-documentation` (ephemeral, should eventually migrate to formal docs or be discarded).
The formal ADRs live in the AMDiRE `docs/development/architecture/` tree where they belong permanently.

There is no explicit authoring guide governing either convention.
The conventions are implicit in the existing files and diverge between the two locations.

## Summary of AMDiRE documentation structure

The `preferences-documentation` skill (204 lines, single-file) establishes the overall repository documentation structure combining Diataxis (user-facing: tutorials, guides, concepts, reference) with adapted AMDiRE (development: context, requirements, architecture, traceability, work-items).
ADRs are not explicitly mentioned in the structure tree, but they naturally nest under `docs/development/architecture/` as evidenced by the existing `adrs/` subdirectory.
The skill covers:

- Document location and structure conventions
- Document evolution and sharding patterns
- Working notes lifecycle (the `docs/notes/` ephemeral staging area)
- Markdown formatting conventions (frontmatter, heading levels)
- Key principles (traceability, user vs development docs separation)
- Code documentation (docstrings over comments)
- Maintenance practices (immediate, atomic, co-located with code changes)

The skill references AMDiRE (Mendez Fernandez and Penzenstadler, 2015) and related standards (ISO/IEC/IEEE 29148, IEEE 1016) but does not mention Richards/Ford's ADR conventions or provide ADR-specific authoring guidance.
ADRs are mentioned only in the key principles bullet about referencing "ADRs, RFCs, or RFDs in completed work items for full audit trail."

## Multi-file pattern analysis

Seven skills in the repo use multi-file structures.
They fall into two distinct patterns.

### Pattern A: numbered chapters

The SKILL.md serves as a navigation hub with a contents table, core principles summary, and cross-references to related skills.
The numbered chapter files contain the full subject matter, organized by topic.
Each chapter is independently readable.

| Skill | Files | SKILL.md role | Chapter organization |
|-------|-------|---------------|---------------------|
| preferences-rust-development | 14 (SKILL.md + 13 chapters) | Hub with philosophy reconciliations, contents table, references | By topic: domain modeling, error handling, API design, testing, etc. |
| preferences-hypermedia-development | 8 (SKILL.md + 7 chapters) | Hub with paradigm overview, contents table, ecosystem summary | By layer: architecture, SSE, Datastar, CSS, web components, templating, events |
| preferences-scalable-probabilistic-modeling-workflow | 6 (SKILL.md + 5 chapters) | Hub with core principles, relationship to parent skill, section map | By workflow phase: foundations, pre-model, post-model-pre-data, post-model-post-data, iteration |
| preferences-scientific-inquiry-methodology | 6 (SKILL.md + 5 chapters) | Hub with core principles, section map, cross-references | By conceptual layer: foundations, epistemology, methodology, hierarchy, pragmatics |

Pattern A is used when the skill covers a domain large enough to require topical decomposition, where each chapter represents a distinct but related aspect of the domain.
The SKILL.md is always loaded; chapters are loaded on demand.

### Pattern B: named companions

The SKILL.md contains the primary workflow or guidance.
Companion files provide reference material, checklists, scripts, or supplementary content that supports but does not replace the SKILL.md.

| Skill | Files | SKILL.md role | Companion purpose |
|-------|-------|---------------|-------------------|
| scientific-visualization | 2 (SKILL.md + checklist.md) | Full design/review workflow with applicability map | Checklist: 17-section evaluation checklist referenced from the workflow |
| text-to-visual-iteration | 2 (SKILL.md + references) | Complete iteration loop workflow, dispatch table | Toolchains: per-format compilation details, flags, gotchas |
| worktree-sparsity-eval | 4 (SKILL.md + references/ + scripts/) | Procedure with thresholds and decision framework | References: sparse-checkout-patterns.md; Scripts: collect_metrics.sh, update_claude_md.sh |

Pattern B is used when the primary skill is a self-contained workflow or procedure, and companions provide lookup tables, checklists, scripts, or reference details that would bloat the main file without adding to its core narrative.

### When each pattern applies

Pattern A suits domains with multiple equally-important topics that together form a comprehensive guide.
Pattern B suits procedural skills where the SKILL.md contains the workflow and companions are support material.
The key discriminator is whether the companions are *chapters in a story* (Pattern A) or *appendices to a procedure* (Pattern B).

## Cohesion analysis

The question is where ADR authoring conventions belong relative to three candidate locations: subfolder within `preferences-documentation`, standalone skill, or subfolder within the new `preferences-architecture-diagramming` skill.

**ADR conventions vs documentation (preferences-documentation).**
ADR authoring conventions are fundamentally about documentation authoring: they specify the structure, status lifecycle, voice conventions, business justification requirements, antipatterns, and storage location for a specific documentation artifact type.
This places them squarely within the responsibility of `preferences-documentation`, which already governs document structure, formatting, maintenance, and location conventions.
The AMDiRE framework positions ADRs under `docs/development/architecture/` — the same structure that `preferences-documentation` defines and manages.
ADRs are a specialization of the documentation concern, not a separate concern.
Cohesion is high.

**ADR conventions vs architecture diagramming (preferences-architecture-diagramming).**
The nix-e3c.4 description mentions "ADRs as companion artifacts to architecture diagrams" and nix-e3c.5 describes ADR conventions as "cross-reference to diagramming skill."
The relationship between ADRs and architecture diagrams is cross-reference, not containment.
Diagrams visualize architectural decisions; ADRs document the reasoning behind them.
These are complementary perspectives on the same architectural artifact, not the same activity.
The diagramming skill covers C4 zoom hierarchy, format selection, line/color/label conventions — all visual representation concerns.
ADR conventions cover written structure, status lifecycle, antipatterns — all textual documentation concerns.
Cohesion is low: they serve different modalities (visual vs textual) applied to the same subject (architecture).

**ADR conventions as standalone skill.**
ADR conventions are too narrow to justify a standalone skill.
The nix-e3c.5 description estimates the content: ADR structure (title, status, context, decision, consequences, compliance, notes), status lifecycle, commanding voice, business justification, three antipatterns, storage conventions, and cross-references.
This is approximately 80-150 lines of content — well below the threshold where a standalone skill provides value over a section or companion file within an existing skill.

## Placement recommendation

Place ADR authoring conventions as a companion file within `preferences-documentation` using Pattern B.

The recommended structure is:

```
preferences-documentation/
├── SKILL.md              (existing, ~204 lines — add brief ADR section pointer)
└── references/
    └── adr-conventions.md  (new, ~100-150 lines — ADR authoring conventions)
```

### Rationale

1. *Cohesion.* ADR conventions are a specialization of the documentation concern. The `preferences-documentation` skill already defines the AMDiRE directory structure where ADRs live, references ADRs in its key principles, and governs the maintenance practices that apply to ADR files. Adding ADR conventions here extends an existing responsibility rather than fragmenting it.

2. *Pattern precedent.* Pattern B (named companions) is the correct fit. The SKILL.md is a self-contained guide to documentation practices; the ADR conventions file is supplementary reference material that would bloat the main file without contributing to its core narrative. This mirrors how `scientific-visualization` uses `checklist.md` or `text-to-visual-iteration` uses `references/toolchains.md` — the companion provides lookup/reference detail for a specific sub-concern.

3. *Current capacity.* `preferences-documentation` is currently 204 lines (single-file, well below the 500-line soft guidance threshold). Adding a brief cross-reference section (~5-10 lines) pointing to `references/adr-conventions.md` keeps the main file focused while making the ADR conventions discoverable.

4. *Cross-references work both directions.* The `preferences-architecture-diagramming` skill can cross-reference `preferences-documentation/references/adr-conventions.md` as a companion artifact guide, establishing the ADR-diagram relationship without co-locating unrelated concerns. Similarly, `adr-conventions.md` can reference the diagramming skill for visual companion patterns.

5. *Nix packaging compatibility.* The `readSkillsFrom` function in `skills/default.nix` maps each skill subdirectory to its path. Claude Code then reads files within that directory, including subdirectories. The existing `text-to-visual-iteration/references/` and `worktree-sparsity-eval/references/` patterns confirm that `references/` subdirectories are already functional in the packaging pipeline.

6. *Avoids premature splitting.* Creating a standalone skill or adding to the diagramming skill would fragment a cohesive documentation concern. The `preferences-documentation` skill is currently small enough that adding a companion file represents natural growth rather than overloading.

## Open questions

1. **Working-note ADR migration.** The 6 ADRs in `docs/notes/development/kubernetes/decisions/` use a different convention from the 17 formal ADRs in `docs/development/architecture/adrs/`. Should the ADR conventions being authored prescribe a single canonical format, and should there be a migration task to bring the working-note ADRs into the formal structure? This is out of scope for nix-e3c.5 but worth noting as a follow-up.

2. **Naming the companion directory.** The existing multi-file skills use both `references/` (text-to-visual-iteration, worktree-sparsity-eval) and flat companion files (scientific-visualization's `checklist.md`). Recommend `references/` for consistency with the majority pattern and to leave room for future companion files (e.g., if RFC/RFD conventions are later added alongside ADR conventions).

3. **CLAUDE.md skill index entry.** The `preferences-documentation` entry in the CLAUDE.md skill index currently reads "documentation: /Users/crs58/.claude/skills/preferences-documentation/SKILL.md". No update is needed since the skill directory path does not change and the CLAUDE.md entry points to SKILL.md which will cross-reference the companion. However, the trigger description might benefit from adding "ADR" as a keyword to improve routing.

4. **Richards/Ford source availability.** The nix-e3c.5 description references "Richards/Ford fundamentals-of-software-architecture ch 21" as the source for ADR conventions. This book is available at `~/projects/planning-workspace/engineering-references`. The implementing task (nix-e3c.5) will need access to this material.
