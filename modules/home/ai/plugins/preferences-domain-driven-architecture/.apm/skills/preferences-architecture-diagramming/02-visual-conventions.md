# Visual conventions

Visual conventions for architecture diagrams drawn from Richards/Ford's standardized practices.
These conventions apply across all C4 zoom levels and all diagram categories in the compendium (chapter 04).

## Line conventions

Solid lines indicate synchronous communication.
Dotted lines indicate asynchronous communication.
Richards/Ford describe this as "one of the few general standards in architecture diagrams."

Use arrowheads to indicate directionality.
One-way arrows show request/response or event flow direction.
Bidirectional arrows show mutual communication.
Different arrowhead styles can indicate different semantics (e.g., open arrowhead for dependency, filled for data flow), but the meaning must be consistent throughout a diagram and documented in the key.

Lines should be thick enough to be clearly visible when rendered at the target display size.
When multiple lines connect the same pair of elements, label each line to distinguish its purpose.

## Color conventions

Use color to distinguish artifacts and indicate grouping.
Color is effective for showing which services belong to the same bounded context, which components share a deployment target, or which elements participate in a particular workflow.

Never rely on color alone to convey critical differences.
Color vision deficiency affects approximately 8% of males and 0.5% of females.
Pair every color distinction with a secondary cue: unique iconography, shapes, line patterns, or labels.
Richards/Ford use the street-crossing-light analogy: green and red are paired with distinct figures so the distinction remains comprehensible without color.

When a diagram contains quantitative data overlays (latency heatmaps, throughput distributions, cost breakdowns), the architecture color conventions yield to `scientific-visualization` colormap guidance.
Sequential and diverging colormaps from that skill are perceptually optimized in ways that arbitrary architecture palette choices are not.

## D2 color convention boundary

General D2 color conventions for architecture diagrams belong in this skill.
Event-modeling-specific D2 color conventions (commands blue, events orange, read models green, aggregates yellow, external systems purple, hotspots red) and the actor swimlane pattern remain in `preferences-event-modeling` as domain-specific extensions.

When producing architecture diagrams in D2 that are not event models, use color for semantic grouping appropriate to the diagram's purpose (bounded contexts, deployment zones, trust levels) rather than the event modeling palette.
When producing event model diagrams, follow the `preferences-event-modeling` color conventions.

## Labeling requirements

Every element in a diagram must have a title unless it is extremely well-known to the audience.
Every item should be labeled, especially when there is any chance of ambiguity.
If any shapes in the diagram are not self-evident, include a key that clearly defines what each shape represents.

Richards/Ford emphasize that "an easily misinterpreted diagram is worse than no diagram at all."
The cost of adding a label is negligible; the cost of a misinterpretation can be significant.

Labels should describe the element's purpose or identity, not its implementation.
At the container level, label containers by what they do ("order processing service") rather than by their technology ("Spring Boot app").
Implementation details belong on the implementation semantic layer (see below).

## Standard shapes vocabulary

While no universal standard exists for architecture diagram shapes, adopt and apply consistently within an organization.
Richards/Ford recommend the following baseline vocabulary:

Three-dimensional boxes represent deployable artifacts (executables, containers, VMs).
The 3D effect visually distinguishes them from logical groupings.

Rectangles represent containers in the general sense: services, applications, bounded contexts.
These are the primary structural elements at C4 levels 2 and 3.

Cylinders represent databases and persistent storage.
This convention is nearly universal across diagramming traditions.

Build a stencil library of common components used in the organization for consistency across diagrams.
In D2, this maps to shape libraries and custom icon imports that can be shared across diagram files.
Maintaining a stencil library prevents the gradual divergence that occurs when each diagram author invents shapes independently.

## Semantic layers

When a diagramming tool supports layers, use them to encode meaning rather than merely to organize visual elements.
Richards/Ford call this "use layers semantically, not decoratively."

The base layer contains architecture topology: containers, databases, dependencies, brokers, and core structural elements.
Specify communication patterns abstractly at this layer (e.g., "synchronous communication") rather than naming protocols.

The implementation layer adds technology specifics: database engine, protocol names, framework versions, language choices.
This layer answers "how is it built?" while the base layer answers "what is the structure?"

Additional contextual layers add cross-cutting concerns: DDD boundaries, transactional scope, security zones, trust boundaries, compliance regions.
Each contextual layer provides a different analytical perspective on the same topology.

This makes diagrams extensible.
Adding a new perspective (e.g., "which components handle PII?") means adding a layer, not redrawing the diagram.
In D2, layers map to compositions: named scopes that can be rendered independently or overlaid.
A base composition for topology, an implementation composition for technology specifics, and additional compositions for trust boundaries or domain concerns.

## Low fidelity first

Use low-fidelity artifacts early in the design process.
Invest in polished diagrams only after the team has iterated sufficiently on the design.
Low-fidelity artifacts are cheap to discard, enabling experimentation and collaborative revision.

For AI agents generating diagrams, produce text-based or minimal diagram-as-code artifacts (D2, Mermaid) as the low-fidelity starting point.
Reserve polished rendering for validated designs.
This guards against *irrational artifact attachment*, the proportional relationship between time invested in producing an artifact and irrational attachment to that artifact.
A four-hour polished diagram creates more attachment than a two-hour version, independent of its correctness.

When reviewing architecture, evaluate the content of a diagram independently of its visual polish.
The countermeasure is deliberately keeping early artifacts rough and disposable.

## See also

- `scientific-visualization/checklist.md` sections 4, 5, 6 for color-specific perceptual guidance when quantitative data appears
- `preferences-event-modeling` for the event modeling D2 color palette and swimlane pattern
- Chapter 03 for format selection criteria that determine which tool produces these visual conventions
