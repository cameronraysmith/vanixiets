# Bounded context design

## Purpose

This document provides detailed guidance on designing bounded contexts and mapping their relationships within domain-driven architectures.
Bounded contexts establish explicit boundaries where domain models maintain internal consistency while interfacing with other contexts through well-defined contracts.
This elaborates on steps 5 and 6 of the discovery process outlined in `discovery-process.md`.
It focuses on translating discovered sub-domains into concrete implementation boundaries.
It also addresses how to design the relationships between those boundaries.

The patterns and techniques described here apply whether you are working with modules in a monorepo, services in a distributed system, or components in a modular application.
The underlying principle remains constant.
Contexts define the scope within which a particular model applies consistently.
Context relationships determine how models interact across those boundaries.

## Relationship to other documents

This document elaborates on the bounded context identification and context mapping steps from `discovery-process.md`.
While `discovery-process.md` describes *how* to discover and identify contexts during collaborative modeling, this document describes *what* those contexts are architecturally.
It also describes *how* to design their relationships.

Implementation details for domain models *within* bounded contexts are covered in `domain-modeling.md`, which addresses type design, aggregates, validation, and encapsulation.
Once you have identified context boundaries using the patterns here, consult `domain-modeling.md` to design the internal model structure.

The relationship to `architectural-patterns.md` is that bounded contexts serve as the fundamental architectural unit in domain-driven design.
System-level architectural decisions about modularity, deployment, and integration all reference context boundaries as the primary organizing principle.
A bounded context may be deployed as a standalone service, compiled as a library module, or implemented as a package within a larger application.
The logical boundary remains consistent regardless of deployment topology.

EventStorming and Domain Storytelling sessions documented in *collaborative-modeling.md* reveal linguistic boundaries where the same term carries different meanings and model boundaries where different invariants apply.
These collaborative modeling techniques produce the artifacts that context design formalizes into bounded context canvases and context maps.

## Bounded contexts

### Definition and purpose

A bounded context is an explicit boundary within which a specific domain model applies consistently.
Inside this boundary, terms have precise definitions, rules are coherent, and invariants can be enforced.
The same term may exist in multiple contexts with different meanings.
This is not only acceptable but often desirable.
It reflects the reality that different parts of an organization use language differently to serve different purposes.

The primary purpose of bounded contexts is to prevent model corruption through uncontrolled unification.
When teams attempt to create a single model that serves multiple purposes, they inevitably encounter competing definitions, contradictory rules, and ambiguous terms.
Bounded contexts acknowledge these differences and make boundaries explicit rather than allowing implicit assumptions to create hidden coupling.

Bounded contexts align naturally with team boundaries and module structures.
A context typically maps to the responsibility of a single team or a cohesive subset of a larger team.
This alignment reflects Conway's Law—the observation that system architectures mirror the communication patterns of the organizations that build them.
Rather than fighting this tendency, effective context design embraces it by ensuring context boundaries facilitate clear ownership and minimal coordination overhead.

### Context boundaries

Context boundaries emerge from three overlapping considerations: linguistic boundaries, model boundaries, and team boundaries.

Linguistic boundaries appear when the same term carries different meanings in different parts of the domain.
A "customer" in the sales context may represent a potential buyer with contact information and a sales pipeline stage.
Meanwhile, a "customer" in the billing context represents a payment entity with credit terms and an account balance.
These are not the same concept with different attributes.
They are fundamentally different models that happen to share a name.
Attempting to unify them forces artificial compromises that serve neither purpose well.

Model boundaries appear when different parts of the domain enforce different invariants or implement different business rules.
An order in the shopping context allows modifications, cancellations, and price adjustments as customers build their cart.
An order in the fulfillment context is immutable once picked, tracking physical package states and shipment events.
These different lifecycle models and invariant sets indicate that separate contexts are needed.

Team boundaries appear when responsibility for different capabilities lies with different groups.
If one team handles pricing and promotions while another handles inventory and fulfillment, the organizational boundary suggests a natural context boundary.
Forcing a unified model across these team boundaries creates coordination overhead and slows both teams, while explicit context boundaries allow independent evolution within clear contracts.

### Context versus sub-domain

Sub-domains exist in the problem space—they represent areas of business capability or expertise that exist regardless of how software is implemented.
Sub-domains are discovered through domain analysis and conversations with domain experts.
They reflect how the business organizes knowledge and responsibility.

Bounded contexts exist in the solution space—they represent architectural decisions about how to organize software models and modules.
Contexts are designed based on sub-domains but are not identical to them.
A single sub-domain may be implemented across multiple bounded contexts if different aspects require different modeling approaches or if the sub-domain is large enough to warrant internal boundaries.

The relationship is one of informed design.
Sub-domains guide context identification, but context boundaries are engineering decisions.
These decisions balance model coherence, team structure, integration complexity, and evolution velocity.
You might discover three sub-domains through domain modeling but design four bounded contexts.
This could happen because one sub-domain is large enough to warrant splitting into upstream and downstream contexts with different stability requirements.

## Context relationship patterns

Bounded contexts do not exist in isolation—they collaborate to deliver complete business capabilities.
The patterns described below formalize the types of relationships that can exist between contexts, each with different implications for integration, ownership, and evolution.

These patterns are not prescriptive templates to be rigidly applied.
They are descriptive tools that help teams recognize the relationships that exist (or should exist) between their contexts and reason about the architectural consequences.
Most systems exhibit multiple relationship patterns, and a given context may have different relationship types with different neighbors.

### Symmetric relationships

Symmetric relationships exhibit balanced power dynamics where neither context dominates the other.
Both sides have roughly equal influence over how the relationship evolves, and both sides share responsibility for making the integration succeed.

#### Partnership

Partnership exists when two contexts collaborate closely with shared success criteria.
Teams coordinate development efforts, align releases, and make mutual adjustments to serve shared objectives.
Neither team can succeed independently—both depend on the other's cooperation to deliver value.

This pattern appears when two teams are building complementary capabilities that must evolve in lockstep.
A risk management context and a trading context might form a partnership where risk calculations directly inform trading decisions.
Both teams coordinate feature development to maintain consistency.

From an algebraic perspective, partnership implies shared module ownership or at least bidirectional dependencies where both sides import types and functions from each other.
This tight coupling is acceptable within the partnership because coordination is already happening at the team level.
The software architecture reflects the organizational reality.

Partnerships require high trust, frequent communication, and shared objectives.
They are costly to maintain and should be reserved for situations where the close coordination delivers substantial value.
As contexts mature and interfaces stabilize, partnerships often evolve into customer-supplier relationships with more formalized contracts and less ongoing coordination.

#### Shared Kernel

Shared Kernel represents a subset of the domain model that is shared between two or more contexts.
This shared portion has special status—changes require agreement from all contexts that depend on it, and modifications happen through coordinated effort.

The shared kernel is typically small, covering only the most fundamental and stable concepts that genuinely need identical representations across contexts.
Examples might include core value objects like Money, Currency, or Timestamp that have precise semantics all contexts must respect.

From an algebraic perspective, the shared kernel manifests as a common module containing shared type definitions that multiple contexts import.
This module has explicit governance—changes require review from all dependent contexts, and breaking changes trigger coordinated migration efforts.

Shared kernels introduce coupling and coordination overhead, so they should be kept minimal.
If the shared portion grows large or changes frequently, this signals a problem.
Either the contexts are not sufficiently independent, or the shared kernel should be extracted into a separate context with an explicit integration strategy.

The key distinction from published language is that shared kernel is bidirectional shared ownership, while published language is an upstream-provided standard that downstream contexts consume.

### Asymmetric relationships (upstream/downstream)

Asymmetric relationships have clear upstream and downstream roles.
The upstream context provides capabilities or data that the downstream context consumes.
The power dynamic and influence flow vary depending on the specific pattern.

#### Customer-Supplier

Customer-Supplier formalizes an upstream-downstream relationship.
The downstream team (customer) has significant influence over the upstream team's (supplier's) priorities and development roadmap.
The upstream team is responsive to downstream needs, prioritizes requested features, and may negotiate delivery timelines.
However, the upstream team ultimately controls the implementation.

This pattern appears when the downstream context represents critical business value and the upstream context exists primarily to serve that value.
A reporting context (upstream) serving an analytics context (downstream) might operate in customer-supplier mode.
The analytics team requests new data sources and the reporting team prioritizes those requests based on business impact.

From an algebraic perspective, the downstream context defines interface requirements—the type signatures and effect specifications it needs from upstream.
The upstream context implements those requirements, providing modules or services that satisfy the downstream contracts.
The customer-supplier relationship governs the evolution of those interfaces through negotiation rather than unilateral decision-making.

Effective customer-supplier relationships require clear communication channels, shared roadmaps, and explicit agreements about service levels and support.
The upstream team must balance requests from multiple downstream customers, which may require prioritization frameworks or formal product management processes.

#### Conformist

Conformist describes a downstream context that accepts the upstream model without translation or adaptation.
The upstream team defines the model, and the downstream team conforms to that definition even if it is not ideal for downstream purposes.

This pattern appears when the upstream context is too powerful, too slow-moving, or too expensive to influence.
External APIs, legacy systems, and third-party platforms often force conformist relationships because downstream teams have no ability to negotiate changes.

From an algebraic perspective, conformist contexts directly import upstream types without translation layers.
Upstream changes may break downstream code, requiring reactive adjustments rather than proactive design.
This tight coupling is accepted as a pragmatic trade-off when alternatives are not viable.

The risk of conformist relationships is that upstream models may not serve downstream needs well, leading to awkward code, violated assumptions, or forced workarounds.
Teams in conformist positions should monitor the health of this relationship and consider whether investing in an anti-corruption layer would reduce long-term maintenance costs.

Conformist is often a temporary state—teams may conform initially to ship quickly, then introduce translation layers as the downstream model matures and upstream mismatches become painful.

#### Anti-Corruption Layer

Anti-Corruption Layer (ACL) represents a defensive strategy.
The downstream context explicitly translates the upstream model into terms that fit the downstream domain model.
This translation layer prevents upstream concepts, assumptions, and changes from corrupting the downstream model's integrity.

This pattern appears when the upstream model is incompatible with downstream needs.
The upstream may use different terminology, embody different assumptions, or change frequently in ways that would destabilize downstream logic.
Rather than conforming to an unsuitable model, the downstream team invests in a translation boundary that preserves downstream model coherence.

From an algebraic perspective, the ACL is a functor—a structure-preserving mapping between type systems.
It transforms upstream types into downstream types while preserving semantic relationships.
For example, an upstream `CustomerRecord` with flat attributes might be translated into a downstream `Customer` aggregate with rich behavior and encapsulated invariants.

The ACL boundary is one-way—it translates inbound data from upstream into downstream concepts but does not expose downstream models to upstream.
This isolation allows the downstream context to evolve independently, adapting to upstream changes at the translation boundary without rippling through the entire downstream model.

Effective ACLs require explicit translation functions, validation logic to reject malformed upstream data, and careful attention to semantic preservation.
The layer should not just transform shapes—it should ensure that domain invariants remain intact across the boundary.

Anti-corruption layers add complexity and maintenance cost, so they should be employed when the value of model integrity justifies the investment.
For simple integrations with stable upstreams, conformist approaches may suffice.
For complex domains or volatile upstreams, ACLs provide essential protection.

#### Open Host Service

Open Host Service (OHS) defines an upstream pattern where the upstream context provides a well-defined protocol or API for multiple downstream consumers.
Rather than adapting to each consumer's needs individually, the upstream team defines a public interface optimized for broad usability and maintains it as a stable contract.

This pattern appears when multiple downstream contexts need access to upstream capabilities or data, and maintaining separate integration points for each would create unsustainable overhead.
The upstream team invests in a general-purpose API that serves common needs, and downstream teams adapt to that published interface.

From an algebraic perspective, OHS manifests as published type signatures and versioned interfaces.
The upstream context exposes a module or service with documented contracts, semantic versioning, and backward compatibility guarantees.
Downstream contexts import these published types or call these published endpoints, relying on the stability guarantees.

Effective OHS implementations require careful API design that balances generality with usability.
The interface should be broad enough to serve diverse consumers but focused enough to remain maintainable.
Versioning strategies, deprecation policies, and migration support become critical as the API evolves.

Open Host Service often pairs with Published Language when the upstream team adopts or defines a shared standard for the integration protocol.

#### Published Language

Published Language represents a shared, well-defined language or protocol for integration between contexts.
This may be an industry standard like HTTP, XML, JSON, or Protobuf.
It could be a domain-specific protocol such as SWIFT for financial messaging or HL7 for healthcare.
It might also be an organization-defined schema that multiple contexts adopt.

The key characteristic is that the language is documented, stable, and not owned by a single context.
It serves as a neutral integration layer that multiple parties can implement independently.

From an algebraic perspective, published language appears as shared schema definitions—Protobuf schemas, AsyncAPI specifications, JSON Schema documents—that generate types in multiple contexts.
Each context implements its own adapter between the published language and its internal model, but the schema itself serves as the source of truth for integration contracts.

Published Language reduces coupling by eliminating direct dependencies on any single context's internal model.
Contexts communicate through the shared language, translating to and from their internal representations at the boundary.
This allows each context to evolve internally without affecting others, as long as the published language mappings remain intact.

Effective use of Published Language requires governance of the shared schema.
Changes must be coordinated, versioned, and backward-compatible.
Schema evolution strategies (adding optional fields, deprecating old fields, maintaining version-specific branches) become essential as the system matures.

Published Language is particularly valuable in distributed systems, where contexts are deployed independently and communicate asynchronously through messages or events conforming to the shared schema.

### Non-relationship patterns

Not all contexts need to integrate.
When integration costs exceed benefits, or when contexts serve entirely separate concerns, explicit non-relationship is the appropriate design.

#### Separate Ways

Separate Ways describes contexts that solve similar or related problems independently, without integration.
Each context duplicates concepts, data, or logic rather than sharing a unified model or coordinating through integration.

This pattern appears when integration complexity, performance overhead, or coordination cost outweighs the value of consistency or reuse.
Two contexts might each maintain their own copy of customer data, synchronized through batch processes or not synchronized at all.
This makes sense if real-time consistency is not required and the simplicity of independent operation justifies occasional duplication or divergence.

From an algebraic perspective, Separate Ways means no shared types and independent module hierarchies.
Each context defines its own types, implements its own logic, and makes its own decisions without coordinating with the other context.

The trade-off is simplicity and autonomy versus consistency and resource utilization.
Separate Ways allows rapid independent evolution but accepts duplication and potential inconsistency.
This is often the right choice early in a system's lifecycle when requirements are uncertain and the cost of coordination exceeds the value of integration.

As the system matures, Separate Ways relationships may evolve into explicit integrations if consistency becomes valuable or if one context emerges as the authoritative source for shared data.
The key is to make the non-relationship explicit rather than allowing implicit assumptions about integration that never materializes.

## The Bounded Context Canvas

The Bounded Context Canvas provides a structured template for documenting the essential characteristics of a bounded context.
It captures the context's purpose, responsibilities, language, and integration points in a single artifact.
This artifact serves as a reference for both the team owning the context and the teams integrating with it.

The canvas complements code and architecture diagrams.
It articulates the conceptual model and responsibilities in human language.
Meanwhile, code embodies the precise implementation and diagrams show the structural relationships.

### Canvas sections

The canvas comprises nine sections, each addressing a distinct aspect of the bounded context's design.

*Name*: The explicit identifier for the bounded context, ideally reflecting the ubiquitous language of the domain.
This name should be meaningful to both technical teams and domain experts.
Avoid generic labels like "service" or "module" in favor of domain-specific terms like "Order Fulfillment" or "Pricing Engine."

*Description*: A concise explanation of the context's purpose and scope.
This section should answer "What does this context do?" and "What responsibilities does it own?" in 2-3 sentences.
The description helps orient newcomers and serves as a touchstone for scope decisions—features that do not fit the description likely belong in a different context.

*Strategic Classification*: The context's role in the overall system architecture, typically categorized as Core Domain, Supporting Subdomain, or Generic Subdomain.
Core domains represent the primary business differentiators where the organization competes.
Supporting subdomains provide necessary capabilities but are not differentiators.
Generic subdomains solve common problems with commodity solutions.
This classification guides investment decisions—core domains receive custom development and deep modeling, while generic subdomains may be satisfied with third-party solutions.

*Domain Language*: The key terms and concepts that define the ubiquitous language within this context.
This section should list the most important domain entities, value objects, and terms, along with brief definitions.
The goal is to make the linguistic boundary explicit—these terms have specific meanings within this context that may differ from their usage in other contexts.

*Business Decisions*: The critical business rules and policies that this context enforces.
These are the invariants that must hold true, the calculations that must be correct, and the workflows that must be coordinated.
Documenting business decisions clarifies the context's value and helps identify integration points where other contexts depend on these decisions.

*Model Traits*: The architectural characteristics of the domain model.
This includes whether it is read-heavy or write-heavy, whether it requires strong consistency or can tolerate eventual consistency, and whether it is transaction-oriented or event-driven.
These traits inform implementation choices and integration strategies.

*Inbound Communication*: The integration patterns and protocols through which other contexts interact with this context.
This section documents the upstream role—what services, APIs, events, or data this context provides to others.
For each inbound integration, note the pattern (Open Host Service, Published Language, etc.) and the consumer contexts.

*Outbound Communication*: The integration patterns and protocols through which this context depends on other contexts.
This section documents the downstream role—what external capabilities or data this context consumes.
For each outbound integration, note the pattern (Anti-Corruption Layer, Conformist, etc.) and the supplier context.

*Ubiquitous Language*: The comprehensive glossary of terms used within the context, with precise definitions.
This expands on the Domain Language section with more detailed explanations, examples, and edge cases.
The ubiquitous language should be maintained collaboratively by developers and domain experts, evolving as understanding deepens.

### Completing the canvas

The canvas is not a form to be filled out once and filed away—it is a living document that evolves with the context.
Initial completion happens during context identification in the discovery process, but the canvas should be revisited regularly as the model matures and integration patterns emerge.

Start with the Name and Description to establish the context's identity and scope.
These sections ground the rest of the canvas and provide a reference point for scope decisions.

Complete Strategic Classification early to guide investment decisions.
If the context is a core domain, expect to invest in rich modeling and custom implementation.
If it is a generic subdomain, consider adopting existing solutions before building custom models.

Document Domain Language and Ubiquitous Language collaboratively with domain experts.
These sections capture the linguistic boundary and should use the actual terms that domain experts use, not developer abstractions.

Business Decisions and Model Traits emerge from deeper domain modeling and should be documented as they become clear.
These sections may be sparse initially and grow over time as the team implements use cases and discovers invariants.

Inbound and Outbound Communication sections are completed as integration patterns are designed.
These sections should reference the specific patterns from the context relationship patterns section above, making the integration strategy explicit.

Validation criteria for a completed canvas include consistency, clarity, and actionability.
All sections should tell a coherent story.
Someone unfamiliar with the context should be able to understand its purpose and responsibilities.
The canvas should provide enough detail to guide design decisions and integration work.

### From canvas to module signature

The canvas provides the conceptual foundation for translating bounded context design into concrete module architecture.
Each section of the canvas informs specific aspects of the module's public API and internal structure.

The Name becomes the module name in the codebase, maintaining linguistic consistency between conceptual models and implementation.

The Domain Language section translates directly to type exports—the core entities, value objects, and aggregates are defined as types in the module's public interface.
These types form the vocabulary through which other modules interact with this context.

The Business Decisions section guides the design of public functions and methods—the operations that enforce invariants, implement workflows, and coordinate state changes.
These functions should have signatures that make business rules explicit through types, encoding constraints that prevent invalid operations.

The Model Traits section informs effect signatures.
This determines whether operations are synchronous or asynchronous, whether they require transactions or can be eventually consistent, and whether they are idempotent or stateful.
A read-heavy model might expose query functions with caching semantics.
A write-heavy model might expose command functions with transaction guarantees.

The Inbound Communication section defines the module's public API—the functions, types, and protocols exposed to consumers.
If the context provides an Open Host Service, this API is designed for broad usability and maintained with backward compatibility.
If the context is in a Partnership, the API might be more specialized and evolve through coordination.

The Outbound Communication section defines the module's dependencies—what it imports from other modules or external services.
If the context uses an Anti-Corruption Layer, these imports are wrapped in translation functions that convert external types to internal types.
If the context is a Conformist, external types might be used directly.

The translation from canvas to module signature is not mechanical—it requires judgment and design skill.
The canvas provides the conceptual boundaries and responsibilities; the module signature provides the precise contracts and implementations.
Both artifacts should tell a consistent story about what the context does and how it integrates with the larger system.

## Context mapping

Context maps visualize the relationships between bounded contexts, making integration patterns explicit and revealing system-level structure.
A context map shows each bounded context as a node and each integration relationship as an edge, with annotations indicating the pattern (Partnership, Customer-Supplier, etc.) and the direction of dependency.

### Creating context maps

Creating a context map begins with listing all identified bounded contexts from the discovery process.
Each context is represented as a labeled box or node.
Positioning reflects organizational structure or domain relationships.
Contexts owned by the same team might be grouped, and contexts in the same subdomain might be clustered.

Next, identify all integration points between contexts.
For each pair of contexts that interact, draw an edge and annotate it with the relationship pattern.
Use directional arrows for asymmetric relationships like Customer-Supplier, Conformist, and Anti-Corruption Layer.
Use undirected connections or bidirectional arrows for symmetric relationships like Partnership and Shared Kernel.

Include additional annotations that clarify the integration mechanism.
This might be REST APIs, message queues, shared databases, or batch files.
These annotations make the technical implementation visible alongside the conceptual pattern.

The resulting map should be comprehensible at a glance while providing enough detail to guide architectural decisions.
A good context map answers questions like "Which contexts depend on this one?", "What happens if this context changes?", and "Where are our integration bottlenecks?"

Visualization techniques vary based on audience and purpose.
A whiteboard sketch suffices for collaborative design sessions.
A diagram tool like Mermaid, PlantUML, or Excalidraw provides versioned artifacts that can be checked into source control.
For complex systems, specialized tools like Context Mapper provide structured notation and validation rules.

The key is to keep the map current—an outdated context map misleads rather than informs.
Integrate map updates into design reviews, sprint retrospectives, or architecture decision records.

### Reading context maps

Reading a context map reveals both explicit integration patterns and implicit system properties.

Start by identifying the contexts with the most inbound connections—these are critical integration points where changes have broad impact.
A context with many downstream consumers operating in Customer-Supplier mode is a bottleneck that requires careful roadmap management and stable interfaces.

Look for conformist relationships, especially multiple conformist relationships pointing to the same upstream context.
This pattern suggests tight coupling and fragility—if the upstream context changes, all downstream conformists must react.
Consider whether some of these conformists should invest in anti-corruption layers to reduce coupling.

Identify cycles in the dependency graph.
While not inherently problematic, cyclic dependencies often indicate that context boundaries are not optimal.
A cycle might suggest that two contexts should be merged, that responsibilities should be redistributed, or that an event-driven integration pattern could break the cycle.

Look for long chains of dependencies—A depends on B, which depends on C, which depends on D.
Long chains create fragility because failures propagate and changes ripple.
Consider whether intermediate contexts could be eliminated or whether data replication could shorten the chain.

Notice asymmetries—a context that is always upstream (providing services to others) has different operational requirements than a context that is always downstream (consuming services).
Upstream contexts need stability, backward compatibility, and clear versioning.
Downstream contexts need resilience, fallback strategies, and translation layers.

Pay attention to the absence of relationships.
Contexts that have no connections to other contexts may be candidates for extraction into separate services or libraries.
Contexts that should be connected but are not indicate missing integration work or duplication.

### Maintaining context maps

Context maps require active maintenance to remain useful.
Integrate map updates into regular development workflows rather than treating them as periodic documentation efforts.

Trigger map updates when:
- A new bounded context is identified and implemented
- An integration pattern changes (Conformist upgraded to Anti-Corruption Layer, Partnership dissolved into Customer-Supplier)
- A context is split, merged, or retired
- Team ownership of a context changes
- New integration points are established

Assign ownership of the context map to a role with system-level visibility—a lead architect, technical lead, or designated team responsible for cross-cutting concerns.
This owner ensures the map stays current and facilitates discussions when changes are proposed.

Store the context map in version control alongside architecture decision records and system documentation.
This allows tracking of how context relationships evolve over time and provides historical context for current architectural states.

Use the map as a reference during design reviews, helping teams evaluate whether proposed integrations align with existing patterns or introduce new coupling.
The map makes trade-offs visible—adding a new dependency is not just a technical change but an architectural decision with system-wide implications.

## Translation to module architecture

Bounded contexts provide the conceptual foundation for module architecture.
The translation from context boundaries to module boundaries is direct.
Each bounded context maps to a module with a well-defined public interface and encapsulated implementation.
Depending on the technology stack, this might be a package, namespace, or service.

### Contexts as modules

A bounded context becomes a module by defining an explicit boundary between public and private elements.
The public interface exposes types and functions that represent the context's contract with the outside world—the operations other contexts may perform and the data structures they may interact with.
The private implementation contains the internal domain model, validation logic, persistence details, and business rules that should not be exposed to other contexts.

The module's public API is carefully designed to reflect the ubiquitous language of the context.
Type names, function names, and parameter labels use domain terminology, making the code self-documenting and maintaining consistency with the domain model.

For example, a "Pricing" bounded context might expose a module with a public API including:

- Types: `Product`, `PriceCalculation`, `Discount`, `PricingRule`
- Functions: `calculatePrice(product, quantity, customer)`, `applyDiscount(calculation, discount)`, `validatePricingRule(rule)`

The internal implementation might include additional types like `PriceCache`, `DiscountEngine`, or `RuleEvaluator`.
These are not exposed because they are implementation details rather than domain concepts other contexts need to understand.

The module boundary enforces the bounded context boundary—code outside the context cannot directly access internal types or bypass validation logic.
This encapsulation preserves model integrity and allows the internal implementation to evolve without breaking external consumers.

### Anti-corruption layers as functors

When a bounded context consumes capabilities from an upstream context with an incompatible model, an anti-corruption layer serves as a translation boundary.
From an algebraic perspective, this translation layer is a functor—a structure-preserving map between type systems.

A functor `F: A -> B` transforms types from system A into types from system B while preserving relationships between those types.
If system A has types `UserRecord` and `OrderRecord` with a relationship "orders belong to users," the functor must produce types in system B that preserve that relationship.
This holds true even if the representation differs.

In practice, this means the ACL implements explicit translation functions for each upstream type that the downstream context consumes:

```
# Upstream types (external system)
UpstreamCustomer = { id: string, name: string, address: string }

# Downstream types (our domain model)
CustomerId = newtype CustomerId(UUID)
CustomerName = newtype CustomerName(string) where length > 0
Address = { street: string, city: string, postalCode: PostalCode }
Customer = { id: CustomerId, name: CustomerName, address: Address }

# ACL translation function (functor)
translateCustomer: UpstreamCustomer -> Either[ValidationError, Customer]
translateCustomer(upstream) =
  CustomerId.parse(upstream.id)
    .flatMap(id =>
      CustomerName.parse(upstream.name)
        .flatMap(name =>
          Address.parse(upstream.address)
            .map(address => Customer(id, name, address))
        )
    )
```

The translation function validates incoming data, constructs domain types with enforced invariants, and either succeeds with a valid downstream model or fails with explicit errors.
This ensures that invalid upstream data never corrupts the downstream model's integrity.

The functor property—preserving structure—means that relationships between upstream types translate to corresponding relationships between downstream types.
If the upstream system has a one-to-many relationship between customers and orders, the translation layer preserves that relationship in downstream terms.

Anti-corruption layers as functors provide a formal foundation for reasoning about translation correctness.
If the translation preserves all relevant relationships and enforces all downstream invariants, the downstream context can evolve independently of upstream changes.
It can adapt the translation layer without modifying the internal model.

### Shared kernel as shared dependencies

When two bounded contexts adopt a shared kernel pattern, the shared model manifests as a shared module containing type definitions and core logic that both contexts import.

This shared module has special status—it is a dependency of multiple contexts, and changes must be carefully coordinated.
Breaking changes in the shared kernel propagate to all dependent contexts, requiring synchronized updates.

From an algebraic perspective, the shared kernel module exports types that are imported directly by multiple contexts:

```
# Shared kernel module
Money = { amount: Decimal, currency: Currency }
Currency = enum { USD, EUR, GBP, ... }

# Context A imports and uses Money
import { Money, Currency } from "shared-kernel"
PriceQuote = { product: ProductId, price: Money }

# Context B also imports and uses Money
import { Money, Currency } from "shared-kernel"
InvoiceLineItem = { description: string, amount: Money }
```

Both contexts use the exact same `Money` type with identical semantics.
If the shared kernel changes how `Money` is represented—adding precision requirements, changing the decimal type, or extending the currency enum—both contexts must adapt.

Governance of the shared kernel is critical.
Changes should require approval from all dependent contexts, and semantic versioning should be enforced rigorously.
Breaking changes should be rare and accompanied by migration guides or automated refactoring tools.

The shared kernel should be kept minimal—only truly fundamental and stable concepts should be shared.
If the kernel grows large or changes frequently, it indicates a problem.
Either the contexts are not sufficiently independent, or the shared concepts should be extracted into a separate bounded context with formal integration patterns.

For example, if many contexts need `Money`, consider creating a "Financial Primitives" bounded context.
This context would provide an Open Host Service exposing `Money` as a published type.
This makes the dependency explicit and allows the Financial Primitives context to evolve with appropriate governance and versioning.

## Team alignment

Bounded contexts and team structures influence each other—context boundaries should align with team responsibilities to minimize coordination overhead, and team communication patterns will inevitably shape how contexts integrate.

### Conway's Law implications

Conway's Law observes that organizations design systems that mirror their communication structures.
If two teams communicate frequently and closely, the software components they build will have tight integration.
If two teams rarely communicate, the components will have loose coupling or no integration at all.

This is not a failure or anti-pattern—it is a fundamental property of how organizations produce software.
Fighting Conway's Law by imposing architectural boundaries that contradict team structures creates friction, coordination overhead, and eventual architectural erosion as teams work around boundaries that impede collaboration.

Effective context design acknowledges Conway's Law and uses it deliberately.
Context boundaries should align with team boundaries so that each team owns one or a few closely related contexts.
This alignment allows teams to evolve their contexts independently, making local decisions without requiring coordination with other teams.

When organizational structure changes—teams merge, split, or shift responsibilities—context boundaries may need to adjust.
A context owned by a single team might split when that team grows and specializes.
Two contexts owned by different teams might merge when those teams consolidate.

The architectural goal is not to create an ideal structure that teams must conform to.
Instead, the goal is to create boundaries that facilitate the organization's actual communication patterns while preserving model integrity.

### Team topologies and contexts

Team Topologies, a framework for organizing software teams, defines four fundamental team types: stream-aligned teams, platform teams, enabling teams, and complicated-subsystem teams.
Bounded contexts align naturally with this framework.

Stream-aligned teams deliver value streams—end-to-end capabilities that serve customer or business needs.
These teams typically own one or more bounded contexts that encapsulate complete business capabilities.
A "Customer Onboarding" stream-aligned team might own an "Onboarding" context, a "Customer Profile" context, and collaborate with platform teams for infrastructure concerns.

Platform teams provide internal services that reduce cognitive load for stream-aligned teams.
These teams often own bounded contexts that provide cross-cutting capabilities—authentication, observability, data storage—through Open Host Service patterns.
Stream-aligned teams consume these platform services rather than building their own implementations.

Enabling teams help stream-aligned teams adopt new technologies or practices.
They typically do not own bounded contexts directly but may help stream-aligned teams design context boundaries, implement integration patterns, or refactor existing contexts as understanding deepens.

Complicated-subsystem teams own contexts with high technical complexity—machine learning models, optimization engines, specialized algorithms.
These contexts are bounded not just by domain language but by technical expertise, requiring specialists to maintain correctness and performance.

Aligning bounded contexts with team topologies ensures that context boundaries support team autonomy.
Stream-aligned teams can evolve their contexts to deliver value without waiting for other teams.
Platform teams can evolve their contexts to improve internal services without disrupting stream-aligned work.

### Communication protocols

The relationship patterns between bounded contexts imply communication patterns between teams.

Partnership relationships require frequent, bidirectional communication—regular joint planning, design discussions, and coordinated releases.
Teams in partnership arrangements might share communication channels, hold joint retrospectives, or co-locate to facilitate collaboration.

Customer-Supplier relationships require structured communication—regular roadmap reviews, feature requests, prioritization discussions.
The customer team articulates needs, and the supplier team commits to delivery timelines.
This communication is more formal than partnership but still collaborative.

Conformist relationships have minimal communication—the downstream team consumes what the upstream team provides without negotiation.
Communication happens primarily through documentation, API specifications, and support channels when issues arise.

Anti-Corruption Layer relationships also involve minimal direct communication, but the downstream team invests more effort in understanding upstream models to build effective translation layers.
Communication might involve clarifying upstream semantics or requesting documentation, but the upstream team is not obligated to accommodate downstream needs.

Open Host Service relationships shift communication to documentation and community support.
The upstream team publishes API documentation, migration guides, and versioning policies.
Downstream teams communicate through issue trackers, forums, or support tickets rather than direct team-to-team collaboration.

Separate Ways relationships involve no direct communication—teams operate independently and make decisions without coordinating.

Effective context design makes these communication protocols explicit, setting team expectations about how much coordination is required and what communication channels should be used.

## Anti-patterns

Several common anti-patterns undermine effective bounded context design, leading to model corruption, tight coupling, or organizational dysfunction.

*Big Ball of Mud*: Failing to establish context boundaries at all, allowing a single undifferentiated model to accumulate competing definitions, contradictory rules, and tangled dependencies.
This anti-pattern emerges from attempting to unify everything into a single model rather than accepting that different parts of the domain require different models.
The solution is to identify linguistic and model boundaries and introduce explicit contexts with translation layers.

*Unclear boundaries*: Defining contexts with vague or overlapping responsibilities, making it unclear where features should be implemented or which team should own a capability.
This creates duplication, missed responsibilities, and coordination overhead as teams negotiate ownership.
The solution is to make context boundaries explicit using tools like the Bounded Context Canvas and to document responsibilities clearly.

*Over-integration*: Creating tight coupling between contexts that should be loosely integrated.
This often happens by sharing databases, exposing internal implementation details, or using synchronous communication where asynchronous would suffice.
This anti-pattern reduces autonomy, increases coordination overhead, and makes independent evolution difficult.
The solution is to prefer asynchronous integration, use anti-corruption layers to isolate models, and respect context boundaries by interacting only through public APIs.

*Under-integration*: Failing to integrate contexts that should collaborate, leading to duplication, inconsistency, or manual coordination where automation would provide value.
This often happens when teams follow Separate Ways by default rather than deliberately choosing non-integration.
The solution is to evaluate integration opportunities based on value, implementing lightweight integration patterns when benefits exceed costs.

*Ignoring Conway's Law*: Imposing context boundaries that contradict team structures, creating friction and coordination overhead.
Teams forced to collaborate across rigid boundaries either ignore the boundaries (causing model corruption) or spend excessive time coordinating (slowing delivery).
The solution is to align context boundaries with team boundaries or adjust team structures to match desired context boundaries.

*Shared database as integration*: Using a shared database as the primary integration mechanism between contexts rather than explicit APIs or messaging.
This creates hidden coupling, makes context boundaries implicit rather than explicit, and prevents independent evolution.
The solution is to give each context its own database and integrate through explicit contracts.

*Premature shared kernel*: Sharing code or models between contexts before understanding whether the concepts are genuinely identical or merely similar.
This premature unification creates coupling and forces compromises when the concepts diverge.
The solution is to default to separate models and only introduce shared kernels when concepts are proven stable and truly identical.

*Neglecting translation layers*: Conforming to upstream models that are incompatible with downstream needs rather than investing in anti-corruption layers.
This allows upstream assumptions to corrupt downstream models, making the downstream context fragile and difficult to evolve.
The solution is to recognize when upstream models are unsuitable and introduce translation layers that preserve downstream model integrity.

## Category-theoretic view of context relationships

Context relationships can be formalized as functors between categories, providing precise semantics for integration patterns.
This perspective clarifies what each relationship pattern preserves and what it may transform.

### Contexts as categories

Each bounded context forms a category where:
- Objects are domain types (entities, value objects, aggregates)
- Morphisms are domain operations (functions between types)
- Composition is function composition
- Identity is the identity function on each type

The ubiquitous language defines the objects and morphisms within each context.

### Context mappings as functors

A mapping between contexts is a functor: a structure-preserving transformation.

```
F: ContextA → ContextB

F maps:
- Types in A to types in B
- Operations in A to operations in B
- Preserves composition: F(g ∘ f) = F(g) ∘ F(f)
- Preserves identity: F(id_A) = id_{F(A)}
```

### Relationship patterns as functor types

| Pattern | Functor Characteristics |
|---------|------------------------|
| Shared Kernel | Isomorphism (bidirectional, structure-preserving) |
| Conformist | Faithful functor (downstream adopts upstream types exactly) |
| Anticorruption Layer | Composition of functors (translate through intermediate category) |
| Open Host Service | Functor from internal to published language |
| Published Language | The target category of an Open Host Service functor |

### Anticorruption layer as functor composition

The ACL is a composition of two functors:
1. Translation functor: External → ACL internal representation
2. Adaptation functor: ACL internal → Domain types

```
External Context ──F──→ ACL Layer ──G──→ Domain Context

Total mapping: G ∘ F
```

This composition isolates the domain from external changes.
If the external context changes, only F needs updating; G remains stable.

### Natural transformations for polymorphic mappings

When multiple contexts share a common structure, natural transformations provide polymorphic mappings.

```haskell
-- Natural transformation between context functors
type ContextMapping f g = forall a. f a -> g a
```

This ensures the mapping behaves uniformly across all types in the source context.

See `theoretical-foundations.md` for the formal definitions of functors and natural transformations.
See `domain-modeling.md#module-algebra-for-domain-services` for how modules implement these categorical structures.

## See also

- `discovery-process.md`: Process for discovering and identifying bounded contexts through collaborative modeling
- `domain-modeling.md`: Implementation patterns for domain models within bounded contexts
- `architectural-patterns.md`: System-level architectural patterns that leverage bounded contexts
- `event-sourcing.md`: Event-driven integration patterns between bounded contexts
- `distributed-systems.md`: Deployment and operational considerations for distributed bounded contexts
- `change-management.md`: Managing evolution of context boundaries and relationships over time
