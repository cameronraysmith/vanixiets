# Format selection

The format selection decision tree determines which diagramming tool to use based on three factors: the diagram's purpose, its intended audience and distribution medium, and the available toolchain.
This chapter establishes the decision framework; the `text-to-visual-iteration` skill provides compilation details for each format.

## D2 as primary tool

D2 is the primary diagram-as-code tool for architecture diagrams.
It is the default choice unless a specific reason favors another format.

D2's features map directly to the visual conventions established in chapter 02.
Compositions implement semantic layers: a base composition for topology, an implementation composition for technology specifics, and additional compositions for cross-cutting concerns like trust boundaries.
Shape libraries and custom icon imports support the stencil library concept for organizational consistency across diagrams.
Node and edge labeling is a first-class feature with support for multi-line labels, tooltips, and structured node content, satisfying the "label everything" principle.
Arrow styles (directional, bidirectional) and line styles (solid, dashed, dotted) implement the synchronous/asynchronous line convention.

D2 produces native SVG output, integrating directly with the `text-to-visual-iteration` post-processing pipeline.
The `--layout elk` option provides hierarchical graph layout suited to C4 diagrams.
The `direction: right` and `direction: down` keywords control primary layout orientation.

The existing D2 conventions in `preferences-event-modeling` (color palette, swimlane pattern, per-step output) demonstrate D2's suitability for structured architecture diagrams.
This skill generalizes D2 from event modeling to all architecture diagram categories.
General D2 conventions (shapes, layers, line styles, color accessibility) are self-contained in this skill.
Event-modeling-specific conventions (the six-color sticky note palette, actor swimlane pattern) remain in `preferences-event-modeling` as domain-specific extensions.
When nix-1o8.2 extracts D2 conventions from event modeling, the general conventions belong here and the domain-specific conventions remain there.

## Alternative formats

TikZ/PGF (via LaTeX) is the choice when the diagram requires mathematical notation, precise coordinate control, or integration with academic publications.
TikZ produces publication-quality output and supports arbitrary LaTeX typesetting within diagram elements.
The tradeoff is significantly higher authoring cost and a heavier compilation pipeline (LaTeX to PDF to SVG via dvisvgm or pdf2svg).
Use TikZ when the diagram will appear in a paper, thesis, or technical report where LaTeX is already the authoring medium.

Typst/CeTZ is an emerging alternative to TikZ with faster compilation and a more ergonomic language.
Consider it when the project already uses Typst for document authoring or when TikZ's compilation overhead is problematic.
It does not yet have the ecosystem depth of TikZ.

Mermaid is the choice for lightweight diagrams embedded in markdown documentation.
GitHub, GitLab, and many documentation platforms render Mermaid inline without requiring a build step.
Mermaid's layout control is limited compared to D2, making it unsuitable for diagrams where precise positioning matters.
Use Mermaid for quick-reference diagrams in README files or inline documentation where the diagram is ancillary to prose.

PlantUML is a legacy choice that remains relevant when integrating with existing PlantUML-based documentation pipelines or when team members are already proficient with it.
For new work, prefer D2 unless PlantUML offers a specific diagram type (e.g., sequence diagrams with extensive message semantics) that D2 does not yet support well.

Graphviz is the choice for graph-theoretic diagrams where automatic layout of complex node-edge relationships is the primary concern.
Graphviz excels at large dependency graphs, call graphs, and state machines where manual layout would be impractical.
Its styling capabilities are limited compared to D2.

The decision table is not exhaustive.
If additional formats emerge (e.g., Excalidraw's text format, Pikchr), evaluate them against the same factors before adoption.

## Decision table

| Factor | D2 | TikZ/PGF | Typst/CeTZ | Mermaid | PlantUML | Graphviz |
|---|---|---|---|---|---|---|
| Architecture (C4, deployment) | primary | | | | | |
| Mathematical notation | | primary | secondary | | | |
| Inline markdown docs | | | | primary | | |
| Existing PlantUML pipeline | | | | | primary | |
| Large graph auto-layout | | | | | | primary |
| Event modeling swimlanes | primary | | | | | |
| Academic publication | | primary | secondary | | | |
| Nix module dependencies | primary | | | | | secondary |
| Quick whiteboard sketch | primary | | | secondary | | |
| Sequence diagrams | secondary | | | secondary | primary | |

"Primary" means this format is the recommended first choice for the given factor.
"Secondary" means this format is a viable alternative when specific constraints favor it.
Empty cells mean the format is not recommended for that factor.

## Escalation path

Format migration is a normal part of the low-fidelity-first workflow.
Early diagrams should use the simplest format that communicates the idea.
Migration to a more expressive format is an investment made only after the design is validated.

When a diagram starts as a quick Mermaid sketch in documentation and later needs more precise layout or semantic layers, migrate to D2.
When a D2 diagram needs mathematical typesetting, either embed LaTeX fragments in D2 labels (limited support) or migrate to TikZ for that specific diagram.

The escalation path runs from lower expressiveness to higher expressiveness: Mermaid to D2 to TikZ.
Moving in the opposite direction (simplifying) is also valid when a complex format's capabilities are not being used.

## See also

- `text-to-visual-iteration` toolchain dispatch table for per-format compilation commands
- `text-to-visual-iteration/references/toolchains.md` for per-format flags and gotchas
- Chapter 02 for the visual conventions that all formats must implement
