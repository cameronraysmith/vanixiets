---
name: preferences-architecture-diagramming
description: >
  Architecture diagramming framework based on C4 zoom hierarchy with
  Richards/Ford visual conventions, Wlaschin bounded context mapping,
  and Dilger event modeling patterns. Covers format selection (D2, TikZ,
  Mermaid, PlantUML), diagram compendium specification, and integration
  with text-to-visual-iteration and scientific-visualization skills.
  Load when creating architecture diagrams, selecting diagramming tools,
  applying C4 levels to system documentation, or deciding which diagrams
  a project needs.
---

# Architecture diagramming

Semantic framework for architectural visualization, positioned as the middle layer between the mechanical compilation workflow (`text-to-visual-iteration`) and the perceptual quality guidance (`scientific-visualization`).
This skill specifies what to diagram, how to think about diagram content, and which format to use.
It defers to the mechanical layer for how to compile and refine the output artifact.

## Layer integration

This skill occupies the middle of a three-layer visualization stack.

The bottom layer is `text-to-visual-iteration`, which provides the compile-inspect-refine loop, artifact conventions (SVG/PNG/PDF triple output), the post-processing pipeline (svgo, resvg, svg2pdf), and the toolchain dispatch table.
When a chapter specifies a diagram to produce, conclude with "compile and refine per the text-to-visual-iteration workflow" rather than re-specifying mechanical steps.
The format selection decision tree in this skill determines which toolchain row in the bottom layer's dispatch table applies.

The top layer is `scientific-visualization`, which provides perceptual and cognitive guidance grounded in Ware (2020) and Schloss (2025).
Most architecture diagrams are structural rather than quantitative, so this layer is advisory rather than routine.
When a diagram contains quantitative data overlays (latency heatmaps, throughput charts, cost distributions), the scientific-visualization colormap guidance takes precedence over the architecture color conventions.

## Sections

| File | Contents |
|------|----------|
| [01-c4-zoom-hierarchy.md](01-c4-zoom-hierarchy.md) | Four-level zoom hierarchy, bounded context placement, representational consistency, C4 level-4 "module" naming |
| [02-visual-conventions.md](02-visual-conventions.md) | Line, color, label, key conventions from Richards/Ford; shapes vocabulary; semantic layers; stencil libraries |
| [03-format-selection.md](03-format-selection.md) | Format selection decision tree, D2 as primary tool, TikZ/Mermaid/PlantUML/Graphviz selection criteria, escalation paths |
| [04-diagram-compendium.md](04-diagram-compendium.md) | Normative-but-flexible compendium of diagram categories anchored on C4 levels, project context guidance |
| [05-bounded-context-diagrams.md](05-bounded-context-diagrams.md) | Trust boundaries, context maps, workflow pipes, event-based decoupling, DTO boundaries, onion architecture |
| [06-infrastructure-adaptations.md](06-infrastructure-adaptations.md) | IaC adaptations of C4, event modeling for infrastructure processes, automation/translation boundary, ADR scope thresholds |

## Core principles

Architectural diagrams serve communication, not decoration.
The following principles, distilled from Richards/Ford and Wlaschin, govern all diagram production.

Representational consistency requires always showing the containing context before drilling into detail.
Never present a subsystem in isolation without indicating where it lives within the broader architecture.

Semantic layers over decorative grouping means using layers to encode meaning (topology, implementation, cross-cutting concerns) rather than merely organizing visual elements.
Adding a new perspective means adding a layer, not redrawing the diagram.

Low fidelity first guards against irrational artifact attachment.
Produce text-based or minimal diagram-as-code artifacts as the starting point.
Reserve polished rendering for validated designs.

Label everything, title everything, include keys.
Every element in a diagram must have a title.
Every item should be labeled.
If any shapes are not self-evident, include a key.

C4 as shared vocabulary means using the four zoom levels (context, container, component, module) as the standard hierarchy for both visual diagrams and code organization.

Bounded context perimeters are trust boundaries.
Everything inside is trusted and valid; everything outside is untrusted and potentially invalid.
Diagrams must show explicit input and output gates at the boundary.

Format selection follows purpose, not preference.
The decision tree in chapter 03 determines the appropriate format based on the diagram's purpose, audience, and available toolchain.

## See also

- `text-to-visual-iteration` -- mechanical compilation and refinement layer
- `scientific-visualization` -- perceptual quality and colormap guidance for quantitative overlays
- `preferences-event-modeling` -- D2 event modeling conventions (domain-specific extensions of the general D2 conventions here)
- `preferences-documentation/references/adr-conventions.md` -- ADR authoring conventions that complement architecture diagrams (when available)
- `preferences-domain-modeling` -- bounded context theory and functional domain patterns
- `preferences-bounded-context-design` -- context mapping patterns and integration strategies
