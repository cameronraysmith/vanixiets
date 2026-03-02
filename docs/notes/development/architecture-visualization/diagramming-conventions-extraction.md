---
title: Architecture diagramming conventions extraction
status: working-note
source-issue: nix-e3c.2
---

# Architecture diagramming conventions extraction

Extracted from Richards/Ford *Fundamentals of Software Architecture* chapters 21 and 23, Dilger *Understanding Event Sourcing* chapter 3, and Wlaschin *Domain Modeling Made Functional* chapter 3.

## C4 and zoom hierarchy conventions

### Four-level zoom hierarchy (context, container, component, class/module)

Source: Richards/Ford ch 23 (C4 section); Wlaschin ch 3 (opening architecture discussion)

Structure architectural diagrams at exactly four zoom levels.
Always start at the broadest level and drill down.
The levels are:

1. *Context* — the entire system including user roles and external dependencies.
2. *Container* — deployable units (websites, services, databases). This is the meeting point between operations and architecture.
3. *Component* — major structural building blocks within a container. Richards/Ford call this the level that "most neatly aligns with an architect's view of the system."
4. *Class/Module* — low-level methods, functions, or types. C4 reuses UML-style class diagrams at this level.

Example: when documenting the vanixiets Kubernetes deployment architecture, the Context diagram shows the full system (user machines, Hetzner VPS, ArgoCD, zerotier VPN, external services).
The Container diagram shows individual deployable units (k3s nodes, ArgoCD server, nixidy rendered manifests, sops-secrets-operator).
The Component diagram shows internal structure of a single container (e.g., ArgoCD's repo-server, application-controller, API server).
The Module diagram shows type definitions or Nix module structure within a component.

### Bounded contexts map to C4 containers or components depending on deployment

Source: Wlaschin ch 3

A bounded context can be realized at different C4 levels depending on the deployment strategy chosen.
In a monolith, bounded contexts map to *components* (assemblies, modules with well-defined interfaces).
In a service-oriented or microservice architecture, bounded contexts map to *containers* (separately deployable units).
The mapping choice does not need to be made early; design bounded contexts as decoupled, autonomous units first, then decide their deployment level.
Wlaschin explicitly advises: "build the system as a monolith initially and refactor to decoupled containers only as needed."

### Synthesis note

Richards/Ford present C4 as a diagramming standard with visual conventions.
Wlaschin uses C4 as an architectural vocabulary for organizing functional domain models.
The two perspectives are complementary: Richards/Ford tell you *how to draw* C4 diagrams, Wlaschin tells you *what the levels mean* for code organization and bounded context placement.
An agent skill should integrate both: use C4 levels as the zoom hierarchy, draw them per Richards/Ford conventions, and map domain concepts to levels per Wlaschin's guidance.

## Representational consistency and semantic layers

### Representational consistency

Source: Richards/Ford ch 23 (opening section)

When showing a detail view or drill-down of any part of an architecture, always first show the containing context and the relationship between the detail and the whole, before presenting the detail itself.
Never show a subsystem in isolation without indicating where it lives within the broader architecture.
The pattern is: show the full topology, highlight the region being zoomed into, then show the zoomed view.

Example: before showing the internal structure of the nixidy rendering pipeline, first show the full four-phase architecture diagram (terranix, clan, easykubenix/kluctl, nixidy/ArgoCD) with the nixidy phase highlighted, then drill into the nixidy pipeline's internal components.

### Semantic layers in diagrams

Source: Richards/Ford ch 23 ("Use Layers Semantically, Not Decoratively")

When a diagramming tool supports layers, use them to encode meaning rather than just visual grouping.
Structure layers as follows:

- *Base layer:* architecture topology — containers, databases, dependencies, brokers, core structural elements. Specify communication patterns abstractly (e.g., "synchronous communication") rather than naming protocols.
- *Implementation layer:* technology specifics — database type, protocol names, framework versions.
- *Additional contextual layers:* DDD boundaries, transactional scope, security zones, or any other cross-cutting concern the architect wants to contrast against the topology.

This makes diagrams extensible.
Adding a new perspective (e.g., "which components handle PII?") means adding a layer, not redrawing the diagram.

Example: a vanixiets infrastructure diagram could have a base layer showing machine topology and communication patterns, an implementation layer specifying zerotier for VPN and sops-nix for secrets, and a contextual layer showing trust boundaries (which machines are in the zerotier network vs. public-facing).

## Line, color, label, and key conventions

### Solid lines for synchronous, dotted lines for asynchronous

Source: Richards/Ford ch 23 (Lines section)

This is described as "one of the few general standards in architecture diagrams."
Use solid lines to indicate synchronous communication and dotted lines for asynchronous communication.
Use arrowheads to indicate directionality (one-way or bidirectional).
Lines should be thick enough to be clearly visible.
Different arrowhead styles can indicate different semantics, but must be used consistently throughout a diagram.

### Use color for grouping but never as the sole differentiator

Source: Richards/Ford ch 23 (Color section)

Use color to distinguish artifacts and indicate grouping (e.g., shading services by bounded context).
However, never rely on color alone to convey critical differences because of color vision accessibility concerns.
Pair color with unique iconography or shapes so the distinction remains comprehensible without color.
The street-crossing-light analogy: green/red plus distinct figures for each.

### Label everything, title everything, include keys

Source: Richards/Ford ch 23 (Titles, Labels, Keys sections)

Every element in a diagram must have a title unless it is extremely well-known to the audience.
Every item should be labeled, especially when there is any chance of ambiguity.
If any shapes in the diagram are not self-evident, include a key that clearly defines what each shape represents.
"An easily misinterpreted diagram is worse than no diagram at all."

### Standard shapes vocabulary

Source: Richards/Ford ch 23 (Shapes section)

While no universal standard exists, adopt and apply consistently within an organization:

- Three-dimensional boxes for deployable artifacts
- Rectangles for containers
- Cylinders for databases

Build a stencil library of common components used in the organization for consistency across diagrams.

## Low fidelity first and irrational artifact attachment

### Low fidelity first

Source: Richards/Ford ch 23 (Tools section, Irrational Artifact Attachment section)

Use low-fidelity artifacts (whiteboard sketches, tablet drawings, rough mockups) early in the design process.
Invest in polished diagrams only after the team has iterated sufficiently on the design.
Low-fidelity artifacts are cheap to discard, enabling experimentation and collaborative revision.

For AI agents generating diagrams: produce text-based or minimal diagram-as-code artifacts (D2, Mermaid, PlantUML) as the low-fidelity starting point.
Reserve polished rendering for validated designs.

### Irrational artifact attachment (antipattern)

Source: Richards/Ford ch 23

Recognize and guard against the proportional relationship between time invested in producing an artifact and irrational attachment to that artifact.
A four-hour polished Visio diagram creates more attachment than a two-hour version, independent of its correctness.
The countermeasure is deliberately keeping early artifacts rough and disposable.
When reviewing architecture, evaluate the *content* of a diagram independently of its visual polish.

### Screen mockups as data-focused, deliberately rough

Source: Dilger ch 3 (Screens section)

When creating screen mockups for event models, keep them deliberately minimal.
The purpose is to make data flows concrete and eliminate ambiguity about what data enters and exits the system, not to design the user experience.
Dilger emphasizes: "should we really invest time in designing screens at such an early stage? The answer is yes, but the level of detail should be minimal. The focus isn't on how the screens appear... it's primarily about the data."

Dilger's approach to screen mockups is a domain-specific application of the same principle Richards/Ford identify as "low fidelity first."
Both sources agree that early visual artifacts should be rough to prevent attachment and keep focus on substance.

## ADR structure and lifecycle

### Seven-section ADR structure

Source: Richards/Ford ch 21 (Basic Structure section)

Every ADR should contain these seven sections, kept consistent across all ADRs:

1. *Title* — numbered sequentially, short descriptive phrase removing ambiguity about nature and context. Example: "42. Use of Asynchronous Messaging Between Order and Payment Services."
2. *Status* — one of: Proposed, Accepted, Superseded, or RFC (with deadline). Proposed requires approval from a governance body. Accepted means ready for implementation. Superseded means changed and replaced by another ADR (with cross-references in both directions).
3. *Context* — the forces at play ("What situation is forcing me to make this decision?"). Concisely describes the scenario and alternatives. Documents the area of architecture being decided upon.
4. *Decision* — the decision stated in affirmative commanding voice ("We will use...") plus full justification including both technical and business rationale. Understanding *why* is more important than understanding *how*.
5. *Consequences* — overall impact (positive and negative), trade-off analysis. Forces the architect to evaluate whether negative impacts outweigh benefits.
6. *Compliance* — how the decision will be measured and governed. Manual review or automated fitness function. Specify how the fitness function will be written if automated.
7. *Notes* — metadata: original author, approval date, approved by, superseded date, last modified date, modified by, last modification.

### Commanding voice in decisions

Source: Richards/Ford ch 21 (Decision section)

State decisions in affirmative commanding voice: "We will use asynchronous messaging between services."
Avoid passive or hedging language like "I think... would be the best choice."
The commanding voice makes clear that a decision has been made and what it is.

### Supersession creates a historical trail

Source: Richards/Ford ch 21 (Status section)

When a decision is superseded, mark the old ADR with "Superseded by [new number]" and the new ADR with "Accepted, supersedes [old number]."
This creates a bidirectional link that prevents rediscovery of previously-rejected alternatives.
Only Accepted ADRs can be superseded; Proposed ADRs are modified, not superseded.

### RFC status for collaborative validation

Source: Richards/Ford ch 21 (RFC section)

Use an RFC status with a deadline to gather feedback before finalizing decisions.
After the deadline, analyze comments, make adjustments, and advance to Proposed or Accepted.
This creates a structured collaboration window without indefinite discussion.

### ADR storage considerations

Source: Richards/Ford ch 21 (Storing ADRs section)

For larger organizations, store ADRs in a dedicated shared repository organized by application/common, application/{app-name}, integration, and enterprise.
For smaller projects or teams with full repo access, colocating ADRs with source code is acceptable.

### ADRs as documentation and standards qualification

Source: Richards/Ford ch 21 (ADRs as Documentation, Using ADRs for Standards sections)

Treat ADRs as a primary form of architectural documentation.
The Context section documents the architecture itself, the Decision section documents the rationale, and the Consequences section documents trade-offs.
When establishing standards, use ADRs to qualify whether a standard should exist: if the architect cannot justify it in the Decision section, reconsider whether it should be a standard.

## ADR antipatterns

### Covering Your Assets

Source: Richards/Ford ch 21

This antipattern occurs when decisions are avoided or deferred out of fear of being wrong.
The countermeasure is deciding at the *last responsible moment*: when the cost of deferring exceeds the risk of deciding with incomplete information.
Collaborate with implementation teams to validate assumptions and reduce risk.

For agents: when presenting architectural options, identify where on the cost-risk curve the decision currently sits.
If sufficient information exists, recommend a decision.
If not, identify what information would reduce risk and propose how to gather it.

### Groundhog Day

Source: Richards/Ford ch 21

This antipattern occurs when people endlessly re-discuss a decision because they do not understand *why* it was made.
The cause is insufficient justification, particularly missing business justification.
Every decision must include both technical and business justification.
The four most common business justifications are: cost, time to market, user satisfaction, and strategic positioning.

For agents: when documenting decisions, always include a business justification.
If one cannot be articulated, flag this as a signal to reconsider whether the decision should be made.

### Email-Driven Architecture

Source: Richards/Ford ch 21

This antipattern occurs when decisions are communicated via email bodies rather than linked from a single system of record.
Email creates multiple inconsistent copies, loses details, and makes updates unreliable.
The fix: mention only the nature and context in communications, link to the authoritative record, and notify only directly impacted stakeholders.

For agents: when communicating decisions, always reference the ADR location (file path, wiki URL) rather than inlining the full decision content.

## Event modeling visual patterns

### Four atomic patterns for system description

Source: Dilger ch 3

Any information system can be described using exactly four patterns, each using color-coded sticky notes (blue for commands, orange for events, green for read models, yellow for automation/external):

1. *State Change* (command pattern): a user interaction triggers a command (blue), which executes a business action and produces an event (orange) recording what happened. This is the only way to write data into the system. The visual pattern is: Screen -> Command (blue) -> Event (orange).

2. *State View* (read/query pattern): previously stored events (orange) feed a read model (green), which provides data to a screen or background process. The visual pattern is: Event (orange) -> Read Model (green) -> Screen.

3. *Automation*: a background process (gear symbol) is triggered by an event, timer, or user interaction. It combines a State View (to read data) and a State Change (to write new data) with a gear icon for the process.

4. *Translation*: communication with external systems. An external event enters the system and is either translated into an internal event via a State Change, or directly consumed as a Read Model.

### Information completeness check

Source: Dilger ch 3

For every attribute in a Read Model, verify which event provides that data.
For every attribute in an Event, verify which command provides that data.
If any attribute has no traceable source, the model is incomplete and cannot proceed until the gap is resolved.
This is a formal validation step that prevents false assumptions about data availability.

For agents: when reviewing or generating event models, trace every data attribute through its lifecycle: command -> event -> read model.
Flag any attribute that appears in a downstream element without a corresponding upstream source.

### Given/When/Then and Given/Then for business rules

Source: Dilger ch 3

Define business rules below each pattern in the model using BDD-style specifications.
For State Changes: GIVEN [prior events], WHEN [command], THEN [expected outcome or error].
For Read Models (State Views): GIVEN [prior events], THEN [expected read model state].
These are placed vertically below each pattern so the model reads left-to-right for flow and top-to-bottom for detail.
GWTs translate directly into unit tests.

### Wave structure and left-to-right timeline

Source: Dilger ch 3

Event models are read left-to-right as a timeline.
Processes exhibit a "wave" structure where each action triggers a reaction.
The visual layout should preserve this temporal flow.
Within each vertical slice, detail increases downward (patterns at the top, GWT specifications below).

## Bounded context and trust boundary diagrams

### Trust boundaries at bounded context perimeters

Source: Wlaschin ch 3 (Trust Boundaries and Validation section)

The perimeter of every bounded context is a trust boundary.
Everything inside is trusted and valid; everything outside is untrusted and potentially invalid.
Diagrams must show explicit "gates" at the boundary:

- *Input gate*: validates all incoming data against domain constraints. Also functions as the Anti-Corruption Layer, translating external vocabulary into internal domain vocabulary. If validation fails, the workflow is bypassed and an error is generated.
- *Output gate*: prevents private information from leaking out. Deliberately "loses" information (e.g., stripping credit card numbers) when converting domain objects to DTOs.

For agents: when diagramming bounded contexts, always show input and output gates explicitly.
Label what validation or translation each gate performs.

### Context map with relationship types

Source: Wlaschin ch 3 (Contracts Between Bounded Contexts, A Context Map with Relationships sections)

Context maps should show not just technical connections but the *relationship type* between contexts, which reflects team collaboration patterns:

- *Shared Kernel*: both teams jointly own the contract. Changes require consultation.
- *Customer/Supplier (Consumer-Driven Contract)*: downstream context defines the contract; upstream provides exactly what is needed.
- *Conformist*: downstream accepts upstream's contract and adapts its own model.
- *Anti-Corruption Layer*: an explicit translation layer when the external model is incompatible with the domain. Common with third-party services; helps avoid vendor lock-in.

These are organizational relationships as much as technical ones.
Include relationship type labels on arrows or connections in context maps.

### Workflows as pipe diagrams within bounded contexts

Source: Wlaschin ch 3 (Workflows Within a Bounded Context section)

Represent workflows as "pipes" with input and output.
Input is always command data; output is always a set of events.
Public workflows (triggered from outside) should "stick out" slightly over the bounded context boundary in diagrams to show they are externally accessible.
A workflow is always contained within a single bounded context and never spans multiple contexts end-to-end.

When emitting events for different downstream consumers, create purpose-specific events rather than broadcasting a generic event with all data.

### Event-based decoupled communication between contexts

Source: Wlaschin ch 3 (Communicating Between Bounded Contexts section)

Diagram inter-context communication as: upstream workflow emits event -> event goes to queue/channel -> downstream context listens -> event is translated to a command -> command initiates downstream workflow -> downstream workflow emits its own events.
Neither context is aware of the other; they communicate only through events.
The translation handler (event-to-command) can live at the downstream boundary or in separate infrastructure.

### DTO boundaries in diagrams

Source: Wlaschin ch 3 (Transferring Data Between Bounded Contexts section)

Show the serialization boundary in diagrams where domain objects are converted to DTOs at the output gate, serialized (JSON/XML), transmitted, deserialized at the downstream input gate, and converted back to domain objects.
Domain objects and DTOs are structurally different even when they carry similar information.
The diagram should make visible where this transformation occurs.

### Onion architecture and I/O at the edges

Source: Wlaschin ch 3 (The Onion Architecture, Keep I/O at the Edges sections)

When diagramming internal workflow structure, use concentric layers (onion/hexagonal/clean architecture) with the domain at the center.
All dependencies point inward.
I/O (database, file system, external services) is pushed to the outermost layer and accessed only at the start or end of a workflow.
When stretching a workflow into a horizontal pipe for visualization, I/O should appear at the left (input) and right (output) edges, with pure domain logic in the middle.

## Cross-cutting synthesis

### Reinforcements across sources

Richards/Ford's C4 hierarchy and Wlaschin's C4 vocabulary are directly compatible and complementary.
Richards/Ford provide visual conventions (how to draw the levels), while Wlaschin provides semantic guidance (how bounded contexts map to levels).
An agent skill should present both as a unified framework: use C4 levels as the zoom hierarchy, draw them per Richards/Ford conventions, and map domain concepts to levels per Wlaschin's guidance.

Richards/Ford's representational consistency principle directly supports Wlaschin's context map approach.
When drilling from a context map into a single bounded context's internal workflow, representational consistency requires showing where that context sits in the broader map first.

Dilger's event modeling four patterns and Wlaschin's workflow diagrams describe the same fundamental abstraction (commands in, events out, read models for queries) from different angles.
Dilger provides visual modeling conventions (color-coded stickies, left-to-right timeline, GWT specifications), while Wlaschin provides architectural framing (trust boundaries, DTO serialization, onion architecture).
The two can be layered: use Dilger's visual patterns for the workflow's internal flow, and embed them within Wlaschin's bounded context diagrams showing gates, trust boundaries, and inter-context communication.

Dilger's information completeness check is a concrete verification technique for what Wlaschin describes architecturally: events carry all data downstream contexts need, DTOs are purpose-specific, and no data appears in a read model without a traceable event source.
The completeness check operationalizes the DTO boundary principle.

Richards/Ford's "low fidelity first" principle and Dilger's deliberately rough screen mockups express the same idea applied at different scales.
Richards/Ford address full architecture diagrams, Dilger addresses UI mockups in event models.
Both warn against premature polish.

### Potential tensions

Richards/Ford recommend storing ADRs in a dedicated shared repository separate from application code for larger organizations, while vanixiets already stores ADRs alongside the codebase (in `docs/notes/development/kubernetes/decisions/`).
This is a valid choice for a single-team repository, but the skill should note that cross-cutting decisions (affecting multiple repos) should have a shared location.

Richards/Ford's ADR Compliance section (automated fitness functions) is oriented toward traditional software testing (ArchUnit, NetArchTest).
In a Nix infrastructure context, the equivalent would be `nix flake check`, module system assertions, or CI workflow validations.
The skill should translate this concept to the appropriate tooling.

Wlaschin advises avoiding domain events *within* a bounded context in functional designs (preferring explicit pipeline composition over event handlers), while Dilger's event modeling treats events as the universal building block regardless of whether they cross context boundaries.
This is not a true conflict — Dilger is modeling at the planning/visualization level where events represent persisted state changes, while Wlaschin is making an implementation-level recommendation about how internal workflow composition avoids hidden dependencies from event managers.
The skill should distinguish between events as a modeling/visualization concept (always use) and events as an internal implementation mechanism (prefer explicit composition in functional code).

## Open questions and ambiguities

1. **C4 "Class" level naming for functional architectures.** Wlaschin notes that in a functional architecture, the Class level corresponds to "modules containing a set of low-level methods or functions." Richards/Ford retain the "Class" name from C4. Recommend "Module" as the default term when operating in functional or Nix contexts, with a note that this corresponds to C4's "Class" level.

2. **Automation vs. Translation boundary in event modeling.** Dilger presents automation (internal background process) and translation (external system communication) as distinct patterns, but notes that translation has "some variance in how it is modeled." The boundary between an automation that calls an external API and a translation that processes an external event could be blurry in practice. The skill may need to provide guidance on when each pattern applies, particularly for infrastructure automation scenarios where "external system" and "background process" overlap (e.g., a Nix rebuild triggered by a git push — is that an automation or a translation?).

3. **ADR scope for infrastructure-as-code.** Richards/Ford's ADR structure and antipatterns are written for software architecture decisions. The vanixiets codebase already adapts this to infrastructure decisions (ADR-001, ADR-005). The skill should clarify what constitutes an "architecturally significant" decision in IaC: changes to deployment topology, Nix module composition patterns, secrets management strategy, and network configuration would qualify; individual package additions likely would not.

4. **Event modeling for infrastructure processes.** Dilger's four patterns assume information systems with user-facing screens, commands, and database-backed events. Applying event modeling to infrastructure workflows requires adapting "screens" to operator interfaces (CLIs, dashboards, CI/CD pipelines) and "events" to infrastructure state changes (machine provisioned, secret rotated, deployment completed). The skill should provide this mapping explicitly.

5. **Diagram tool chain.** Richards/Ford recommend learning a diagramming tool deeply. The vanixiets preferences mention D2 diagrams (in the event modeling skill). The skill should specify D2 as the primary diagram-as-code tool and clarify how D2's features map to Richards/Ford's recommendations (D2 supports layers via compositions, has shape libraries, etc.).
