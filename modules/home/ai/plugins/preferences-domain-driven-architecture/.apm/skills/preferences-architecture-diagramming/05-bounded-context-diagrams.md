# Bounded context diagrams

Patterns for diagramming bounded contexts, drawn primarily from Wlaschin's architectural framing with Dilger's visual patterns for internal workflow representation.
These patterns apply at C4 levels 2-3 and integrate with the visual conventions established in chapter 02.

## Trust boundaries at bounded context perimeters

The perimeter of every bounded context is a trust boundary.
Everything inside the boundary is trusted and valid.
Everything outside is untrusted and potentially invalid.
Diagrams must show explicit gates at the boundary.

The input gate validates all incoming data against domain constraints.
It also functions as the anti-corruption layer, translating external vocabulary into internal domain vocabulary.
If validation fails, the workflow is bypassed and an error is generated.
In diagrams, show the input gate as a distinct element at the boundary with a label describing what validation or translation it performs.

The output gate prevents private information from leaking out.
It deliberately "loses" information (e.g., stripping credit card numbers) when converting domain objects to DTOs for external consumption.
In diagrams, show the output gate as a distinct element at the boundary with a label describing what information filtering it performs.

The gate model applies regardless of deployment strategy.
In a monolith where bounded contexts are components within a single container, the gates exist as module interfaces.
In a microservice architecture where bounded contexts are separate containers, the gates exist as API validation layers.

## Context maps with relationship types

Context maps show not just technical connections between bounded contexts but the relationship type between them.
These relationship types reflect team collaboration patterns as much as technical integration strategies.

*Shared kernel* means both teams jointly own the contract between contexts.
Changes require consultation.
In diagrams, show this as a bidirectional connection with a "shared kernel" label and optionally a shared region where the two context boundaries overlap.

*Customer/supplier* (also called consumer-driven contract) means the downstream context defines the contract and the upstream provides exactly what is needed.
In diagrams, show this as a directed arrow from downstream to upstream with a "customer/supplier" label, indicating that the downstream context drives the contract definition.

*Conformist* means the downstream context accepts the upstream's contract and adapts its own model accordingly.
In diagrams, show this as a directed arrow from upstream to downstream with a "conformist" label.

*Anti-corruption layer* is an explicit translation layer used when the external model is incompatible with the domain.
This is common with third-party services and helps avoid vendor lock-in.
In diagrams, show the ACL as a distinct element between contexts, visually separate from both, with labels describing the translation it performs.

Include relationship type labels on all connections in context maps.
Unlabeled connections between contexts leave the integration strategy ambiguous, which is precisely the information the context map is meant to communicate.

## Workflow pipe diagrams

Represent workflows as pipes with input and output within a bounded context.
Input is always command data.
Output is always a set of events.

Public workflows that are triggered from outside the bounded context should protrude slightly over the context boundary in diagrams.
This visual cue shows that they are externally accessible entry points.
Private workflows that are only triggered internally should be fully contained within the boundary.

A workflow is always contained within a single bounded context.
It never spans multiple contexts end-to-end.
When a business process involves multiple contexts, model it as a chain: the upstream context's workflow emits events, those events trigger a downstream context's workflow via event-based decoupling.

When emitting events for different downstream consumers, create purpose-specific events rather than broadcasting a generic event with all data.
Purpose-specific events make explicit what information each downstream context needs and prevent unintentional coupling through shared event schemas.

## Event-based decoupled communication

Diagram inter-context communication as a chain: the upstream workflow emits an event, the event goes to a queue or channel, the downstream context listens, the event is translated to a command at the downstream boundary, the command initiates the downstream workflow, and the downstream workflow emits its own events.

Neither context is aware of the other.
They communicate only through events.
The translation handler (event-to-command) can live at the downstream boundary or in separate infrastructure.

In diagrams, show the queue or channel as a distinct element between contexts.
Use dotted lines (asynchronous communication) for the event flow per the line conventions in chapter 02.
Label the event on the upstream side and the command on the downstream side to make the translation visible.

## DTO serialization boundaries

Show the serialization boundary where domain objects are converted to DTOs at the output gate.
The sequence is: domain objects are converted to DTOs, DTOs are serialized (JSON, protobuf, or other wire format), serialized data is transmitted, the downstream input gate deserializes, and the deserialized DTOs are converted back to domain objects.

Domain objects and DTOs are structurally different even when they carry similar information.
The diagram should make visible where this transformation occurs.
This is particularly important when debugging data flow issues: the serialization boundary is a common source of information loss, type coercion errors, and versioning conflicts.

## Onion architecture visualization

When diagramming internal workflow structure, use concentric layers (onion/hexagonal/clean architecture) with the domain at the center.
All dependencies point inward.

I/O (database, file system, external services) is pushed to the outermost layer and accessed only at the start or end of a workflow.
The inner layers contain pure domain logic with no side effects.

When stretching a workflow into a horizontal pipe for visualization, I/O should appear at the left (input) and right (output) edges, with pure domain logic in the middle.
This horizontal representation is equivalent to the concentric view but better suited to showing the temporal flow of data through the workflow.

## Integration with event modeling visual patterns

Dilger's event modeling four patterns (state change, state view, automation, translation) and Wlaschin's workflow diagrams describe the same fundamental abstraction from different angles.
Dilger provides visual modeling conventions: color-coded elements, left-to-right timeline, GWT specifications below each pattern.
Wlaschin provides architectural framing: trust boundaries, DTO serialization, onion architecture, input/output gates.

The two can be layered.
Use Dilger's visual patterns (from `preferences-event-modeling`) for the workflow's internal flow.
Embed them within the bounded context diagrams described in this chapter, showing gates, trust boundaries, and inter-context communication as the architectural frame around the event modeling detail.

Dilger's information completeness check is a concrete verification technique for what Wlaschin describes architecturally.
For every attribute in a read model, verify which event provides that data.
For every attribute in an event, verify which command provides that data.
If any attribute has no traceable source, the model is incomplete.
This operationalizes the DTO boundary principle: events carry all data downstream contexts need, and no data appears in a read model without a traceable event source.

## See also

- `preferences-domain-modeling` for bounded context theory, autonomous-units-first design, and the type-driven approach to gates
- `preferences-event-modeling` for event model visual patterns (color palette, swimlane structure, GWT specifications)
- `preferences-bounded-context-design` for context mapping patterns, integration strategies, and ACL design
- Chapter 01 for how bounded contexts map to C4 levels depending on deployment strategy
