# Diagram compendium

The compendium defines categories of diagrams anchored on the C4 zoom hierarchy, with guidance on when each adds value.
It is normative in the sense that it defines a shared vocabulary and provides structured recommendations.
It is flexible in that it explicitly accounts for project context and leaves room for situated judgment.
The compendium is not a checklist to be completed for every project.
It is a menu from which architects select based on what the project actually needs.

## System context diagram

Operates at C4 level 1.
Shows the entire system, its user roles, and external dependencies.

This diagram adds value at project inception, during stakeholder alignment, and when onboarding new team members.
It establishes the system boundary and makes explicit which actors and external systems interact with the system under consideration.
Skip when the system boundary is obvious and stable.

Prefer D2 with a single composition.
The system context diagram is typically simple enough that semantic layers are unnecessary.

## Container diagram

Operates at C4 level 2.
Shows deployable units and their communication patterns.

This diagram adds value when deployment topology affects architectural decisions, when multiple teams own different containers, or when documenting infrastructure-as-code deployment targets.
It is the meeting point between architecture and operations: the container diagram answers both "what are the major pieces?" and "where do they run?"
Skip for single-container applications where the deployment topology is trivial.

Prefer D2 with semantic layers: a base topology composition showing containers and their communication patterns, plus an implementation details composition showing specific technologies.
Trust boundaries can be added as a contextual layer when relevant.

## Component diagram

Operates at C4 level 3.
Shows major structural building blocks within a container.

This diagram adds value when internal structure is complex enough that developers need a map, when module boundaries correspond to bounded context perimeters, or when documenting a large Nix module tree.
Skip for containers with straightforward internal structure that is navigable from the codebase alone.

Prefer D2.
Use shapes consistently: rectangles for structural components, cylinders for local storage, distinct shapes for external interfaces.

## Module diagram

Operates at C4 level 4 (corresponding to C4's "class" level).
Shows type definitions, function signatures, Nix module option interfaces, or fine-grained structural units within a component.

This diagram adds value when documenting complex type hierarchies, module option dependencies (including `mkIf` condition chains in Nix), or algebraic data type relationships.
Skip for modules with self-documenting interfaces where the code itself serves as adequate documentation.

Prefer D2 for structural views showing module relationships and dependencies.
Prefer TikZ when mathematical type-theory notation is needed to express type-level relationships precisely.

## Deployment topology diagram

Operates across C4 levels 1-2.
Shows the physical or virtual infrastructure: machines, networks, VPNs, cloud regions, and the mapping between containers and their deployment targets.

This diagram adds value for any system with non-trivial deployment topology, for IaC-managed infrastructure, and for documenting where containers run.
It is the meeting point between architecture and operations at the infrastructure level.
Skip only for the simplest deployments (single machine, single container).

Prefer D2 with semantic layers.
The base layer shows machines and network topology.
A contextual layer shows trust boundaries (e.g., which machines are within a zerotier VPN vs. public-facing).
An implementation layer adds specific technologies and configurations.

## Bounded context map

Operates at C4 levels 2-3.
Shows context boundaries with relationship type labels.

This diagram adds value when the system has multiple bounded contexts with inter-context communication, when documenting DDD decomposition, or during strategic domain analysis.
The relationship types (shared kernel, customer/supplier, conformist, anti-corruption layer) are organizational as much as technical, reflecting team collaboration patterns.
Skip for single-context systems.

Prefer D2.
See chapter 05 for the detailed bounded context diagramming patterns.

## Workflow pipe diagram

Operates at C4 level 3.
Shows command-in, event-out workflow structure within a bounded context, with trust boundary gates at the perimeter.

This diagram adds value when documenting domain workflows, when validating data flow completeness, or when the workflow has complex branching.
The trust boundary gates (input validation/ACL, output information filtering) make explicit what enters and leaves the bounded context.
Skip when workflows are simple enough to describe in prose.

Prefer D2, coordinating with event modeling conventions from `preferences-event-modeling` for the internal flow patterns.
See chapter 05 for the relationship between workflow pipes and bounded context boundaries.

## Event model diagram

Operates across C4 levels 2-3.
Shows the full event modeling timeline with actor swimlanes, commands, events, read models, and automation patterns.

This category is fully specified by `preferences-event-modeling` and its D2 conventions.
The compendium provides the cross-reference rather than duplicating the specification.
Event model diagrams add value during system specification, when documenting event-driven architectures, or when tracing data provenance through the system.

## Sequence or interaction diagram

Operates at C4 levels 2-3.
Shows temporal ordering of messages between components or containers.

This diagram adds value when documenting complex multi-step protocols, API call sequences, or distributed system choreography where the order of operations matters.
Skip when the interaction is simple enough to describe with a single D2 edge label or a brief prose description.

Prefer PlantUML for complex sequence semantics where its extensive message type vocabulary (synchronous, asynchronous, return, create, destroy) provides precision.
Prefer D2 for simpler interactions where full sequence diagram notation would be excessive.

## Data flow diagram

Operates at C4 levels 2-4.
Shows how data moves through the system, including transformation points and storage.

This diagram adds value when documenting ETL pipelines, secrets propagation (e.g., sops-nix key distribution across a machine fleet), or configuration data flow through Nix module evaluation.
Skip when data flow follows obvious structural paths that the container or component diagram already makes clear.

Prefer D2.
Data flow diagrams benefit from directional arrows showing the flow direction and labels on each edge describing the data being transferred and any transformation applied.

## Project context guidance

Different project contexts call for different diagram sets.
The following guidance is suggestive, not prescriptive.

For greenfield application projects, start with the system context diagram and container diagram.
Add component diagrams and bounded context maps as the domain model develops.
Event model diagrams are valuable when the system is event-driven.

For brownfield or migration projects, start with the container diagram of the existing system.
Add a second container diagram showing the target state.
Use deployment topology diagrams when the migration involves infrastructure changes.
ADRs (per `preferences-documentation/references/adr-conventions.md`, when available) document each migration decision.

For infrastructure-as-code projects, start with the deployment topology diagram.
Add container diagrams showing the relationship between IaC definitions and deployed infrastructure.
Module diagrams are valuable for documenting Nix module composition patterns.
Data flow diagrams document secrets propagation and configuration evaluation.

For single-component libraries or tools, a module diagram may be the only diagram that adds value.
System context diagrams are unnecessary when the system boundary is obvious.
Resist the urge to produce diagrams that document the trivial.

## See also

- `preferences-event-modeling` for the full event model diagram specification
- `preferences-documentation/references/adr-conventions.md` for ADR authoring conventions that complement architecture diagrams (when available)
- Chapter 01 for C4 level definitions and bounded context placement
- Chapter 06 for infrastructure-specific adaptations of these diagram categories
