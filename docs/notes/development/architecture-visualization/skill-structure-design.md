---
title: Skill structure and format selection framework
status: working-note
source-issue: nix-e3c.3
upstream-inputs:
  - nix-e3c.1 (adr-landscape-survey.md)
  - nix-e3c.2 (diagramming-conventions-extraction.md)
---

# Skill structure and format selection framework

Design specification for the `preferences-architecture-diagramming` skill, synthesizing the ADR landscape survey (nix-e3c.1) and diagramming conventions extraction (nix-e3c.2) into a concrete implementation plan.


## Layered integration architecture

The architecture diagramming skill occupies the semantic middle layer in a three-layer visualization stack.

The bottom layer is `text-to-visual-iteration`, which provides the mechanical compile-inspect-refine loop.
It owns artifact conventions (SVG/PNG/PDF triple output), the post-processing pipeline (svgo, resvg, svg2pdf), the dual-feedback iteration loop (structural SVG inspection plus multimodal bitmap perception), and the toolchain dispatch table mapping source formats to compilers.
This layer is format-agnostic: it handles D2, Mermaid, TikZ, Typst, PlantUML, and Graphviz identically.

The middle layer is `preferences-architecture-diagramming`, which provides the semantic framework for architectural visualization.
It owns the C4 zoom hierarchy and how domain concepts map to zoom levels, the format selection decision tree for choosing among diagramming tools, line/color/label/key conventions from Richards/Ford, the diagram compendium specifying which categories of diagrams add value in which contexts, and the coordination rules for how bounded contexts, event models, trust boundaries, and deployment topologies are visually represented.
This layer tells you *what* to diagram and *how to think about* the diagram's content; it defers to the bottom layer for *how to compile and refine* the artifact.

The top layer is `scientific-visualization`, which provides perceptual and cognitive guidance grounded in Ware (2020) and Schloss (2025).
It owns encoding channel precision hierarchies, colormap selection principles, accessibility auditing (CVD accommodation, grayscale survival), and the 17-section evaluation checklist.
This layer applies when the output serves a scientific purpose (data figures, statistical plots).
It does not apply to most architecture diagrams, but it does apply when architecture diagrams contain quantitative data overlays (e.g., latency heatmaps, throughput charts, cost distributions).

The integration points are:

Between bottom and middle: the diagramming skill references `text-to-visual-iteration` for compilation and refinement of any diagram it specifies.
When a chapter describes a D2 diagram to produce, it concludes with "compile and refine per the text-to-visual-iteration workflow" rather than re-specifying the mechanical steps.
The format selection decision tree in the diagramming skill determines which toolchain row in the bottom layer's dispatch table applies.

Between middle and top: the diagramming skill references `scientific-visualization` only when a diagram contains quantitative data.
Architecture diagrams are predominantly structural (topology, relationships, boundaries) rather than quantitative, so the perceptual layer is advisory rather than routine.
The diagramming skill's color conventions (section on line/color/label) should note that when quantitative data appears in an architecture diagram, the scientific-visualization colormap guidance takes precedence over the architecture color conventions.

Between middle and event modeling: the `preferences-event-modeling` skill contains D2 color conventions (commands blue, events orange, read models green, aggregates yellow, external systems purple, hotspots red) and swimlane patterns for actor lanes.
These are domain-specific applications of the general D2 conventions the diagramming skill will establish.
The diagramming skill establishes the general D2 conventions (shapes vocabulary, layer semantics, line types), and `preferences-event-modeling` extends those conventions for event modeling's specific visual vocabulary.
When nix-1o8.2 eventually extracts the D2 conventions from event modeling into a shared location, the diagramming skill will be the natural home for the general conventions, with event modeling retaining only its domain-specific extensions.


## SKILL.md outline

The SKILL.md serves as the navigation hub following Pattern A conventions observed in `preferences-rust-development` and `preferences-scalable-probabilistic-modeling-workflow`.
It is always loaded when the skill is activated; chapters are loaded on demand.

Estimated total SKILL.md length: 80-110 lines.

```
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

# Architecture diagramming                              [~5 lines]

  One-paragraph purpose statement: semantic framework for architectural
  visualization, positioned as the middle layer between mechanical
  compilation (text-to-visual-iteration) and perceptual quality
  (scientific-visualization).

## Layer integration                                    [~15 lines]

  Three-layer stack summary: bottom (mechanical), middle (semantic,
  this skill), top (perceptual). Integration points between layers.
  Brief enough that chapters can be loaded independently without
  re-reading this section.

## Sections                                             [~20 lines]

  Contents table mapping chapter files to descriptions, following
  the pattern from preferences-rust-development and
  preferences-scalable-probabilistic-modeling-workflow.

## Core principles                                      [~25 lines]

  5-7 principles distilled from Richards/Ford and Wlaschin:
  - representational consistency (always show containing context)
  - semantic layers over decorative grouping
  - low fidelity first (guard against irrational artifact attachment)
  - label everything, title everything, include keys
  - C4 as shared vocabulary across visual and code organization
  - bounded context perimeters as trust boundaries
  - format selection follows purpose, not preference

## See also                                             [~10 lines]

  Cross-references:
  - text-to-visual-iteration (mechanical layer)
  - scientific-visualization (perceptual layer)
  - preferences-event-modeling (D2 event modeling conventions)
  - preferences-documentation/references/adr-conventions.md (ADR authoring)
  - preferences-domain-modeling (bounded context theory)
```


## Numbered chapter plan

Six chapters organized by topic, following Pattern A.
Each chapter is independently readable and addresses a distinct aspect of architecture diagramming.

### 01-c4-zoom-hierarchy.md (estimated 120-160 lines)

Content scope: the four-level zoom hierarchy (context, container, component, module), what each level contains and who its audience is, how bounded contexts map to C4 levels depending on deployment strategy (monolith vs. services), representational consistency (always show containing context before drilling down), and the synthesis between Richards/Ford visual conventions and Wlaschin semantic guidance.

Includes the C4 level-4 naming resolution: "module" in functional/Nix contexts with a note that it corresponds to C4's "class" level.
Includes guidance on how bounded context placement at the container vs. component level depends on deployment decisions that need not be made early.

Cross-references: `preferences-domain-modeling` for bounded context theory, `preferences-event-modeling` for how event models overlay on C4 levels.

### 02-visual-conventions.md (estimated 100-140 lines)

Content scope: line conventions (solid for synchronous, dotted for asynchronous, arrowheads for directionality), color conventions (grouping, never sole differentiator, accessibility pairing with shapes), labeling requirements (every element titled, every item labeled, keys for non-obvious shapes), standard shapes vocabulary (3D boxes for deployable artifacts, rectangles for containers, cylinders for databases), and semantic layers (base topology layer, implementation layer, contextual layers for cross-cutting concerns).

Includes the stencil library concept: build and maintain a consistent set of shapes for the organization's common components.
Notes that when quantitative data overlays appear, `scientific-visualization` colormap guidance takes precedence.

Cross-references: `scientific-visualization/checklist.md` sections 4, 5, 6 for color-specific perceptual guidance.

### 03-format-selection.md (estimated 100-130 lines)

Content scope: the format selection decision tree (detailed in its own section below), D2 as primary diagram-as-code tool with rationale, how D2 features map to Richards/Ford recommendations, when to use TikZ (publication-quality, mathematical notation), Mermaid (lightweight inline documentation), PlantUML (legacy integration), and Graphviz (graph-theoretic layouts).

Includes the low-fidelity-first principle as it applies to format choice: start with the simplest format that communicates the idea, upgrade to more expressive formats only when the design is validated.
Includes the irrational artifact attachment antipattern and its countermeasure.

Cross-references: `text-to-visual-iteration` toolchain dispatch table for compilation details, `text-to-visual-iteration/references/toolchains.md` for per-format flags and gotchas.

### 04-diagram-compendium.md (estimated 150-200 lines)

Content scope: the normative-but-flexible compendium specification (detailed in its own section below), diagram categories anchored on C4 zoom levels, when-to-use guidance organized by project context (greenfield, brownfield, infrastructure, application), and the relationship between diagrams and ADRs as companion artifacts.

Includes infrastructure-specific adaptations: deployment topology diagrams, Nix module composition diagrams, secrets flow diagrams, network topology with trust boundaries.
Notes the cross-reference to `preferences-documentation/references/adr-conventions.md` for ADR authoring conventions that complement diagrams.

Cross-references: `preferences-event-modeling` for event model diagrams within the compendium, `preferences-documentation/references/adr-conventions.md` for ADR companion guidance.

### 05-bounded-context-diagrams.md (estimated 120-160 lines)

Content scope: trust boundaries at bounded context perimeters (input gates for validation/ACL, output gates for information filtering), context maps with relationship type labels (shared kernel, customer/supplier, conformist, anti-corruption layer), workflow pipe diagrams within bounded contexts (command input, event output, public workflows protruding over boundary), event-based decoupled communication between contexts, DTO serialization boundaries, and onion architecture visualization (concentric layers, I/O at edges).

Includes the synthesis of Wlaschin's architectural framing with Dilger's visual patterns: use event modeling visual conventions for workflow internal flow, embed them within bounded context diagrams showing gates and trust boundaries.

Cross-references: `preferences-domain-modeling` for bounded context theory, `preferences-event-modeling` for event model visual patterns, `preferences-bounded-context-design` for context mapping patterns.

### 06-infrastructure-adaptations.md (estimated 100-140 lines)

Content scope: adaptations of software architecture diagramming conventions for infrastructure-as-code contexts.
This chapter resolves the infrastructure-specific open questions from nix-e3c.2: event modeling for infrastructure processes (mapping screens to CLIs/dashboards/CI pipelines, events to infrastructure state changes), the automation-vs-translation boundary for infrastructure scenarios, and ADR scope thresholds for IaC decisions.

Includes the four-phase architecture example (terranix, clan, easykubenix/kluctl, nixidy/ArgoCD) as a concrete illustration of how C4 levels apply to infrastructure.
Notes that Nix module composition diagrams at the module (C4 level-4) level show module option interfaces, `mkIf` condition dependencies, and import trees.

Cross-references: `preferences-nix-development` for Nix-specific patterns, the Kubernetes architecture documentation in `docs/notes/development/kubernetes/`.


## Format selection decision tree

The decision tree selects a diagramming format based on three factors: the diagram's purpose, its intended audience and distribution medium, and the available toolchain.

### Primary selection: purpose determines the default

D2 is the primary diagram-as-code tool for architecture diagrams.
It supports native SVG output, semantic layers via compositions, shape libraries for stencil consistency, and `direction: right` or `direction: down` layout control.
D2's `--layout elk` option provides the hierarchical layout that C4 diagrams require.
D2 compositions map directly to Richards/Ford's recommendation to use layers semantically: a base composition for topology, an implementation composition for technology specifics, and additional compositions for cross-cutting concerns.
D2 is the default choice for any architecture diagram unless a specific reason favors another format.

TikZ/PGF (via LaTeX) is the choice when the diagram requires mathematical notation, precise coordinate control, or integration with academic publications.
TikZ produces publication-quality output and supports arbitrary LaTeX typesetting within diagram elements.
The tradeoff is significantly higher authoring cost and a heavier compilation pipeline (LaTeX to PDF to SVG via dvisvgm or pdf2svg).
Use TikZ when the diagram will appear in a paper, thesis, or technical report where LaTeX is already the authoring medium.

Typst/CeTZ is an emerging alternative to TikZ with faster compilation and a more ergonomic language.
Consider it when the project already uses Typst for document authoring or when TikZ's compilation overhead is problematic.
It does not yet have the ecosystem depth of TikZ.

Mermaid is the choice for lightweight diagrams embedded in markdown documentation.
GitHub, GitLab, and many documentation platforms render Mermaid inline.
Mermaid's layout control is limited compared to D2, making it unsuitable for diagrams where precise positioning matters.
Use Mermaid for quick-reference diagrams in README files or inline documentation where the diagram is ancillary to prose.

PlantUML is a legacy choice.
It remains relevant when integrating with existing PlantUML-based documentation pipelines or when team members are already proficient with it.
For new work, prefer D2 unless PlantUML offers a specific diagram type (e.g., sequence diagrams with extensive message semantics) that D2 does not yet support well.

Graphviz is the choice for graph-theoretic diagrams where automatic layout of complex node-edge relationships is the primary concern.
Graphviz excels at large dependency graphs, call graphs, and state machines where manual layout would be impractical.
Its styling capabilities are limited compared to D2.

### Decision table

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

### Escalation path

When a diagram starts as a quick Mermaid sketch in documentation and later needs more precise layout or semantic layers, migrate to D2.
When a D2 diagram needs mathematical typesetting, either embed LaTeX fragments in D2 labels (limited support) or migrate to TikZ for that specific diagram.
Format migration is a normal part of the low-fidelity-first workflow: early diagrams should be in the simplest format that communicates the idea, and migration to a more expressive format is an investment made only after the design is validated.


## Diagram compendium specification

The compendium defines categories of diagrams anchored on the C4 zoom hierarchy, with guidance on when each adds value.
It is normative in the sense that it defines a shared vocabulary and provides structured recommendations; it is flexible in that it explicitly accounts for project context and leaves room for situated judgment.
The compendium is not a checklist to be completed for every project.
It is a menu from which architects select based on what the project actually needs.

### Category structure

Each compendium category specifies: a name, the C4 level(s) it typically operates at, a one-sentence description, a "when it adds value" condition, a "when to skip" condition, and format guidance.

### Categories

*System context diagram* operates at C4 level 1.
Shows the entire system, its user roles, and external dependencies.
Adds value at project inception, during stakeholder alignment, and when onboarding new team members.
Skip when the system boundary is obvious and stable.
Prefer D2 with a single composition.

*Container diagram* operates at C4 level 2.
Shows deployable units and their communication patterns.
Adds value when deployment topology affects architectural decisions, when multiple teams own different containers, or when documenting infrastructure-as-code deployment targets.
Skip for single-container applications.
Prefer D2 with semantic layers: base topology composition plus implementation details composition.

*Component diagram* operates at C4 level 3.
Shows major structural building blocks within a container.
Adds value when internal structure is complex enough that developers need a map, when module boundaries correspond to bounded context perimeters, or when documenting a large Nix module tree.
Skip for containers with straightforward internal structure.
Prefer D2.

*Module diagram* operates at C4 level 4.
Shows type definitions, function signatures, Nix module option interfaces, or class-level structure.
Adds value when documenting complex type hierarchies, module option dependencies (including `mkIf` condition chains), or algebraic data type relationships.
Skip for modules with self-documenting interfaces.
Prefer D2 for structural views; TikZ for mathematical type-theory notation.

*Deployment topology diagram* operates across C4 levels 1-2.
Shows the physical or virtual infrastructure: machines, networks, VPNs, cloud regions.
Adds value for any system with non-trivial deployment topology, for IaC-managed infrastructure, and for documenting the mapping between containers and their deployment targets.
This is the meeting point between architecture and operations.
Prefer D2 with semantic layers showing trust boundaries as a contextual layer.

*Bounded context map* operates at C4 levels 2-3.
Shows context boundaries with relationship type labels (shared kernel, customer/supplier, conformist, anti-corruption layer).
Adds value when the system has multiple bounded contexts with inter-context communication, when documenting DDD decomposition, or during strategic domain analysis.
Skip for single-context systems.
Prefer D2.

*Workflow pipe diagram* operates at C4 level 3.
Shows command-in, event-out workflow structure within a bounded context, with trust boundary gates.
Adds value when documenting domain workflows, when validating data flow completeness, or when the workflow has complex branching.
Skip when workflows are simple enough to describe in prose.
Prefer D2, coordinating with event modeling conventions from `preferences-event-modeling`.

*Event model diagram* operates across C4 levels 2-3.
Shows the full event modeling timeline with actor swimlanes, commands, events, read models, and automation patterns.
Adds value during system specification (Event Modeling steps 1-7), when documenting event-driven architectures, or when tracing data provenance.
This category is fully specified by `preferences-event-modeling` and its D2 conventions; the compendium provides the cross-reference rather than duplicating the specification.

*Sequence or interaction diagram* operates at C4 levels 2-3.
Shows temporal ordering of messages between components or containers.
Adds value when documenting complex multi-step protocols, API call sequences, or distributed system choreography.
Skip when the interaction is simple enough for a single D2 edge label.
Prefer PlantUML for complex sequence semantics; D2 for simpler interactions.

*Data flow diagram* operates at C4 levels 2-4.
Shows how data moves through the system, including transformation points and storage.
Adds value when documenting ETL pipelines, secrets propagation (e.g., sops-nix key distribution), or configuration data flow through Nix module evaluation.
Skip when data flow follows obvious structural paths.
Prefer D2.

### Project context guidance

Different project contexts call for different diagram sets.
The following guidance is suggestive, not prescriptive.

For greenfield application projects, start with the system context diagram and container diagram.
Add component diagrams and bounded context maps as the domain model develops.
Event model diagrams are valuable when the system is event-driven.

For brownfield or migration projects, start with the container diagram of the existing system.
Add a second container diagram showing the target state.
Use deployment topology diagrams when the migration involves infrastructure changes.
ADRs (per `preferences-documentation/references/adr-conventions.md`) document each migration decision.

For infrastructure-as-code projects, start with the deployment topology diagram.
Add container diagrams showing the relationship between IaC definitions and deployed infrastructure.
Module diagrams are valuable for documenting Nix module composition patterns.
Data flow diagrams document secrets propagation and configuration evaluation.

For single-component libraries or tools, a module diagram may be the only diagram that adds value.
System context diagrams are unnecessary when the system boundary is obvious.


## Resolution of open questions

### C4 level-4 naming

The recommended term is "module" when operating in functional programming or Nix contexts.
C4 originally calls this level "class" because it targets object-oriented codebases where the finest-grained architectural unit is a class with methods.
In functional architectures, the corresponding unit is a module containing functions and type definitions.
In Nix, it is a module with option declarations and `config` definitions.
The skill should use "module" as the default term throughout, with a parenthetical note on first use: "module (corresponding to C4's class level)" to maintain traceability to the C4 source material.
This is consistent with how Wlaschin describes the level as "modules containing a set of low-level methods or functions."

### Automation vs. translation boundary

Dilger defines automation as an internal background process and translation as communication with an external system, but acknowledges variance in how translation is modeled.
In infrastructure contexts, the distinction blurs because many operations involve both internal orchestration and external system interaction simultaneously.

The resolution is to classify based on *trust boundary crossing*.
If the process crosses a bounded context perimeter or interacts with a system outside the trust boundary, it is a translation, even if it is automated.
If the process operates entirely within a single bounded context using only trusted internal state, it is an automation.

Applying this to the example of a Nix rebuild triggered by a git push: the git push is an external event crossing a trust boundary (from the developer's workstation into the CI/CD system), so the initial event receipt is a translation.
The CI/CD system's decision to trigger `nixos-rebuild` based on the received event is an automation operating within the CI/CD bounded context.
The `nixos-rebuild` command targeting a remote machine crosses another trust boundary (CI/CD to target machine), making it another translation.

This trust-boundary-based classification maps cleanly to Wlaschin's input/output gate model: translations pass through gates, automations do not.

### ADR scope threshold for IaC

In infrastructure-as-code contexts, an architecturally significant decision is one that constrains future infrastructure choices in ways that are costly to reverse.
The following categories qualify:

Deployment topology changes (e.g., moving from managed Kubernetes to self-hosted k3s) qualify because they affect the container diagram and constrain which operational patterns are available.
Nix module composition patterns (e.g., adopting deferred module composition, choosing between import-tree and manual imports) qualify because they affect how configuration is organized and composed across the fleet.
Secrets management strategy (e.g., choosing sops-nix over age-based encryption, selecting key distribution topology) qualifies because it affects trust boundaries and has security implications.
Network configuration decisions (e.g., zerotier VPN topology, trust zone boundaries) qualify because they constrain inter-machine communication patterns.
Orchestration tool selection (e.g., choosing clan-core, selecting ArgoCD over Flux) qualifies because it determines the operational workflow for the entire fleet.

Individual package additions, user configuration changes, home-manager module selections, and routine maintenance operations do not qualify.
The threshold is cost-of-reversal: if changing the decision later requires modifying multiple machines, restructuring module imports, or re-provisioning infrastructure, it merits an ADR.

### Event modeling for infrastructure processes

When applying event modeling to infrastructure workflows, the following mapping adapts Dilger's patterns:

"Screens" become operator interfaces: terminal CLIs (e.g., `clan machines update`, `kubectl apply`), web dashboards (ArgoCD UI, Grafana), CI/CD pipeline views (GitHub Actions), and monitoring alerts (ntfy push notifications).
The purpose remains the same as in application event modeling: these are the surfaces through which actors observe system state and initiate commands.

"Events" become infrastructure state changes: machine provisioned, secret rotated, deployment completed, certificate renewed, configuration applied, health check passed/failed.
These are the persisted facts about what happened to the infrastructure.

"Commands" become operator actions or automated triggers: provision machine, rotate secret, deploy configuration, update flake input, rebuild system.

"Read models" become operational views: fleet status dashboard, deployment history log, secret expiration calendar, module dependency graph.

"Actors" include human operators (the `cameron` user), automated systems (CI/CD, cron jobs, systemd timers), and external services (GitHub webhooks, DNS propagators, certificate authorities).

The four Dilger patterns apply directly with this mapping: state change (operator issues command, infrastructure event is recorded), state view (events feed operational dashboards), automation (systemd timer triggers secret rotation), translation (GitHub webhook triggers CI/CD pipeline).

### D2 as primary diagram-as-code tool

D2 is recommended as the primary tool based on the following feature mapping to Richards/Ford's recommendations:

Richards/Ford recommend semantic layers.
D2 implements this via compositions (named scopes that can be rendered independently or overlaid), allowing a base topology composition, an implementation details composition, and contextual compositions for trust boundaries or DDD concerns.

Richards/Ford recommend a consistent shapes vocabulary with stencil libraries.
D2 supports shape libraries and custom icon imports, allowing the organization to define a standard set of shapes for its common components and reuse them across diagrams.

Richards/Ford recommend labeling everything.
D2's node and edge labeling is a first-class feature with support for multi-line labels, tooltips, and structured node content.

Richards/Ford recommend showing directionality and communication type.
D2 supports arrow styles (directional, bidirectional), line styles (solid, dashed, dotted), and labels on edges, mapping directly to the synchronous/asynchronous line convention.

D2 produces native SVG output, integrating directly with the `text-to-visual-iteration` post-processing pipeline (svgo, resvg, svg2pdf).
The `--layout elk` option provides the hierarchical graph layout that C4 diagrams require.

The existing D2 conventions in `preferences-event-modeling` (color palette, swimlane pattern, per-step output) demonstrate D2's suitability for structured architecture diagrams.
The diagramming skill generalizes these conventions from event modeling to all architecture diagram categories.


## Discovered questions and concerns

1. The `preferences-event-modeling` skill contains substantial D2 convention content (color palette, swimlane patterns, per-step diagram output, integration with Qlerify/EventCatalog workflow) that overlaps with the general D2 conventions the diagramming skill will establish.
The nix-e3c epic description mentions nix-1o8.2 as the future task to extract D2 conventions from event modeling.
The diagramming skill should be written so that the general D2 conventions (shapes, layers, line styles, color accessibility) are self-contained, and the event-modeling-specific conventions (the six-color sticky note palette, actor swimlane pattern) remain in `preferences-event-modeling` as domain-specific extensions.
When nix-1o8.2 executes, it should extract only the *general* D2 conventions into the diagramming skill and leave the *event-modeling-specific* conventions in place.
This boundary needs to be clearly documented to prevent nix-1o8.2 from over-extracting.

2. The chapter plan produces an estimated total of 690-930 lines across 6 chapters plus the SKILL.md hub (80-110 lines), for a total of 770-1040 lines.
This exceeds the 800-line soft guidance threshold from preferences-style-and-conventions when viewed as a single unit, but each individual chapter is well under 200 lines and independently readable.
The Pattern A structure mitigates the total size concern because only the SKILL.md hub is loaded by default; chapters are loaded on demand.
The per-chapter sizes are comparable to the `preferences-rust-development` chapters.

3. The format selection decision tree currently covers six formats.
If additional formats emerge (e.g., Excalidraw's text format, Pikchr), the decision table will grow.
The table structure accommodates growth without restructuring, but the prose descriptions should note that the table is not exhaustive and new formats should be evaluated against the same factors before adoption.

4. The compendium specification mentions "ADRs as companion artifacts to architecture diagrams" with a cross-reference to `preferences-documentation/references/adr-conventions.md`.
That companion file does not yet exist; it will be created by nix-e3c.5.
The cross-reference is forward-looking and should use conditional language ("when available, reference...") until nix-e3c.5 completes.

5. The `preferences-documentation` SKILL.md currently has no mention of ADR conventions or a `references/` subdirectory.
The nix-e3c.1 survey recommends adding a brief cross-reference section (~5-10 lines) pointing to `references/adr-conventions.md`.
This modification to `preferences-documentation` is part of nix-e3c.5's scope, not this design document's.
However, the implementation task for the diagramming skill chapters (nix-e3c.4) should be aware that the ADR cross-reference target may not exist yet.
