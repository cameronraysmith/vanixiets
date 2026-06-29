# C4 zoom hierarchy

The C4 model structures architectural diagrams at four zoom levels.
Each level addresses a different audience and reveals a different grain of detail.
Always start at the broadest level and drill down; never present a lower level without first establishing its containing context.

## The four levels

Level 1, context, shows the entire system including user roles and external dependencies.
This is the highest-altitude view, answering "what does this system do and who uses it?"
The audience is broad: stakeholders, new team members, anyone needing orientation.

Level 2, container, shows deployable units and their communication patterns.
Containers are independently deployable artifacts: websites, services, databases, message brokers, file systems.
Richards/Ford identify this as the meeting point between operations and architecture, where deployment topology becomes visible.
The audience is architects, operators, and developers working across deployment boundaries.

Level 3, component, shows major structural building blocks within a single container.
Richards/Ford describe this as the level that "most neatly aligns with an architect's view of the system."
Components are the organizational units that developers navigate daily: modules with well-defined interfaces, bounded context implementations, service layers.
The audience is developers working within a container.

Level 4, module (corresponding to C4's "class" level), shows type definitions, function signatures, Nix module option interfaces, or fine-grained structural units within a component.
C4 originally names this level "class" because it targets object-oriented codebases where the finest-grained unit is a class with methods.
In functional architectures, the corresponding unit is a module containing functions and type definitions.
In Nix, it is a module with option declarations and `config` definitions.
This skill uses "module" as the default term throughout.

## Bounded context placement

Bounded contexts can map to different C4 levels depending on deployment strategy.
This mapping does not need to be decided early.

In a monolith, bounded contexts typically map to components (level 3).
They are assemblies or modules with well-defined interfaces within a single deployable unit.
The bounded context boundary exists in code organization but not in deployment topology.

In a service-oriented or microservice architecture, bounded contexts map to containers (level 2).
Each context becomes a separately deployable unit with its own data store and API surface.
The bounded context boundary is visible in both code organization and deployment topology.

Wlaschin advises designing bounded contexts as decoupled, autonomous units first, then deciding their deployment level.
The recommendation is to build the system as a monolith initially and refactor to decoupled containers only as needed.
Diagrams should reflect the current deployment reality while noting where context boundaries exist regardless of deployment choice.

When documenting a system where bounded contexts span multiple C4 levels (some deployed as separate containers, others still components within a monolith), use the container diagram to show the deployment boundary and the component diagram to show context boundaries within each container.
Annotate contexts that are candidates for extraction to highlight the deployment decision that remains open.

## Representational consistency

When showing a detail view or drill-down of any part of an architecture, always first show the containing context and the relationship between the detail and the whole.
The pattern is: show the full topology, highlight the region being zoomed into, then show the zoomed view.

This principle applies across all four C4 levels.
Before showing the internal component structure of a container, show the container diagram with that container highlighted.
Before showing module-level detail of a component, show the component diagram with that component highlighted.

Representational consistency also applies to bounded context maps.
When drilling from a context map into a single bounded context's internal workflow, show where that context sits in the broader map before presenting its internal structure.

## Synthesis of visual and semantic guidance

Richards/Ford provide the visual conventions for how to draw C4 diagrams: standard shapes (3D boxes for deployable artifacts, rectangles for containers, cylinders for databases), line conventions (solid for synchronous, dotted for asynchronous), and labeling requirements (title everything, label everything, include keys).
These conventions are detailed in chapter 02.

Wlaschin provides the semantic guidance for what C4 levels mean for code organization: how bounded contexts map to levels, how workflows sit within contexts, how trust boundaries align with context perimeters.
These patterns are detailed in chapter 05.

The two perspectives are complementary.
Use C4 levels as the zoom hierarchy, draw them per Richards/Ford conventions, and map domain concepts to levels per Wlaschin's guidance.
Neither perspective alone is sufficient: diagrams drawn without semantic grounding are structurally correct but meaningless, while domain models without visual conventions are well-reasoned but uncommunicable.

## See also

- `preferences-domain-modeling` for bounded context theory and the autonomous-units-first design principle
- `preferences-event-modeling` for how event models overlay on C4 levels
- Chapter 02 for the visual conventions applied at each C4 level
- Chapter 05 for bounded context diagramming patterns
