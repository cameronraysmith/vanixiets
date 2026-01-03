# Strategic domain analysis

## Purpose

This document provides detailed analysis techniques for classifying domains and determining appropriate investment levels based on their strategic importance to the business.
It elaborates on step 4 of the discovery process documented in `discovery-process.md`, establishing the foundational strategic context that shapes all subsequent architectural and implementation decisions.

Strategic domain analysis answers three critical questions: which capabilities truly differentiate our business from competitors, which capabilities are necessary but undifferentiating, and which capabilities are commodity solutions we should integrate rather than build.
The classification directly determines investment priorities, team allocation, technology choices, and the level of type-theoretic rigor applied during implementation.

Without strategic classification, development teams apply uniform effort across all domains, wasting sophisticated engineering on commodity problems while under-investing in competitive advantages.
This document provides frameworks for making classification decisions systematically and translating those classifications into concrete technical choices.

## Relationship to other documents

This document extends the strategic classification introduced in step 4 of `discovery-process.md`, providing the analytical frameworks needed to make classification decisions and connect them to implementation strategies.

Once domains are classified, `domain-modeling.md` describes how to apply appropriate rigor levels during the modeling phase, translating strategic importance into type sophistication.
Core domains receive the full dependent types and formal verification treatment, while generic domains use simple algebraic data types and library integrations.

For architectural decisions about context boundaries and integration patterns, `bounded-context-design.md` applies strategic classifications to prioritize which contexts warrant custom development versus integration with external systems.
Core domain contexts receive more autonomy and isolation, while generic domain contexts are designed primarily as adapters to third-party services.

The investment prioritization frameworks in this document inform all technical decisions downstream: from choosing programming languages and type systems to determining testing strategies and team composition.
Strategic classification is not a one-time exercise but an ongoing reassessment as markets evolve and competitive landscapes shift.

Collaborative modeling sessions documented in *collaborative-modeling.md* surface the domain structures and sub-domains through EventStorming and Domain Storytelling that strategic analysis then classifies as core, supporting, or generic.
The domain events, aggregates, and linguistic patterns discovered during collaborative sessions provide the raw material for strategic classification decisions.

## Domain classification

### The strategic classification model

Strategic domain classification divides system capabilities into three categories based on two dimensions: business differentiation and problem complexity.
Business differentiation measures how much a capability contributes to competitive advantage, while problem complexity measures the inherent difficulty of implementing a correct solution.

The three classifications are core domains, supporting sub-domains, and generic sub-domains.
This taxonomy originates in Eric Evans' Domain-Driven Design work and has been refined through decades of enterprise software development to provide a practical framework for investment decisions.

Classification is relative to business strategy and competitive context, not absolute.
What qualifies as a core domain for one organization may be generic for another depending on their market position and strategic goals.
A logistics company treats route optimization as core while a retail company treats it as supporting; a payment processor treats fraud detection as core while an e-commerce company treats it as supporting.

The model deliberately uses "sub-domain" rather than "domain" for supporting and generic classifications to emphasize that core domains receive primary strategic focus.
In a well-designed system, supporting and generic sub-domains exist to enable core domains rather than competing for equal architectural attention.

### Core domains

Core domains represent the highest levels of both business differentiation and problem complexity, requiring custom development to achieve competitive advantage.
These capabilities directly determine market position and business success, embodying unique expertise or innovative approaches that competitors cannot easily replicate.

A core domain must satisfy both differentiation and complexity criteria simultaneously.
High differentiation without complexity suggests purchasing a sophisticated existing solution; high complexity without differentiation suggests over-engineering a commodity problem.
True core domains combine deep domain expertise with genuinely difficult implementation challenges.

Examples include recommendation engines for streaming media platforms where content matching quality directly drives subscriber retention, pricing algorithms for airlines where real-time optimization across millions of seat-route-time combinations determines profitability, and underwriting models for insurance companies where risk assessment accuracy fundamentally defines business viability.
In each case, the capability both differentiates the business and resists commoditization due to inherent complexity.

Core domains warrant maximum investment: senior engineers with deep domain expertise, sophisticated type systems that encode invariants at compile time, extensive property-based testing supplemented with formal verification where feasible, and continuous refinement as business understanding evolves.
Organizations should expect to rebuild core domain implementations multiple times as they learn more about the problem space and competitive requirements change.

The defining question for core domain identification is whether competitors would pay significant money to license your implementation if it were available.
If the answer is yes, you have identified a genuine competitive advantage worth protecting and investing in.

### Supporting sub-domains

Supporting sub-domains provide necessary functionality that enables core domains but does not itself differentiate the business in the market.
These capabilities exhibit moderate complexity and require correct implementation but do not determine competitive position.

Supporting sub-domains often handle essential business operations that every company in an industry must solve: customer relationship management, order processing workflows, inventory tracking systems, or financial reporting.
The business cannot function without these capabilities, but executing them competently only achieves parity with competitors rather than advantage.

The investment level for supporting sub-domains balances correctness requirements against strategic importance.
These domains warrant solid engineering practices, good type discipline with smart constructors and algebraic data types, and standard testing approaches combining property-based and example-based tests.
However, they do not justify dependent types, formal verification, or the most senior engineering talent.

Supporting sub-domains frequently emerge as boundaries between core domains and external systems, translating between the sophisticated models in core domains and the standardized interfaces expected by generic integrations.
An order processing system might sit between a core pricing algorithm and a generic payment provider, ensuring that complex pricing decisions are correctly translated into standard transaction formats.

Organizations should resist the temptation to over-invest in supporting sub-domains by treating them as core domains.
While correctness matters, innovation in supporting sub-domains rarely produces competitive returns.
The appropriate strategy focuses on reliable execution with maintainable implementations rather than cutting-edge techniques or novel approaches.

### Generic sub-domains

Generic sub-domains address problems common across industries where well-established solutions already exist in the market.
These capabilities exhibit low business differentiation because competitors have access to the same commodity solutions.

Classic examples include authentication and authorization systems, email delivery services, payment processing integrations, structured logging frameworks, and monitoring infrastructure.
Every software system needs these capabilities, but implementing them from scratch wastes resources on solved problems.

Generic sub-domains warrant minimal custom development investment.
The default strategy is to integrate existing commercial or open-source solutions rather than building custom implementations.
When custom code is necessary, it should consist primarily of thin adapters that translate between internal domain models and external service interfaces.

The type sophistication appropriate for generic sub-domains focuses on safe integration rather than domain modeling.
Simple product types that wrap library types, interface-based integration patterns that allow swapping providers, and integration tests that verify correct interaction with external systems provide sufficient rigor.

The key strategic decision for generic sub-domains is build versus buy, almost always favoring buy.
Custom development is justified only when integration costs exceed licensing fees or when no suitable existing solution exists for a genuinely novel technical requirement.

Organizations frequently misclassify generic sub-domains as core domains due to familiarity bias or not-invented-here syndrome.
Because developers interact daily with authentication or logging systems, these capabilities feel important and potentially worth custom implementation.
Disciplined strategic analysis reveals that importance to daily operations differs from strategic differentiation.

## Core domain identification

### Core Domain Charts

Core Domain Charts provide a two-axis visualization for domain classification by plotting sub-domains according to complexity and differentiation.
The horizontal axis represents problem complexity ranging from simple to complex, while the vertical axis represents business differentiation ranging from generic to differentiating.

This two-dimensional space creates four quadrants with distinct strategic implications.
The upper-right quadrant contains genuine core domains with high complexity and high differentiation, warranting maximum investment.
The upper-left quadrant contains differentiating but simple capabilities where competitive advantage comes from execution excellence rather than technical sophistication.
The lower-right quadrant contains complex but generic problems where existing solutions should be purchased rather than built.
The lower-left quadrant contains simple generic capabilities that should use standard commodity solutions.

To construct a Core Domain Chart, list all identified sub-domains from the bounded context mapping exercise, then evaluate each along both axes independently.
Differentiation assessment requires business stakeholder input: does this capability attract customers, retain customers, or enable pricing power?
Complexity assessment requires technical stakeholder input: does correct implementation require deep expertise, novel algorithms, or sophisticated coordination?

Plotting sub-domains often reveals surprising classifications.
Teams discover they are investing core domain effort in lower-left quadrant commodity problems, or they find upper-right quadrant competitive advantages being implemented as afterthoughts.
The visual representation facilitates strategic discussions about investment reallocation.

Movement across the chart over time indicates market evolution.
Core domains may drift leftward as complexity decreases due to better tools, or downward as competitors match capabilities.
Generic domains may drift upward if the organization discovers differentiation opportunities, or rightward if requirements grow more sophisticated.

### Purpose Alignment Model

The Purpose Alignment Model connects domain capabilities to overall business purpose through three layers: strategic capabilities that directly advance business purpose, execution capabilities that deliver strategic capabilities, and compliance capabilities that satisfy mandatory requirements.

Strategic capabilities map directly to the organization's reason for existing and competitive positioning.
For a streaming media company, content recommendation is strategic; for a logistics company, route optimization is strategic; for a financial services company, risk modeling is strategic.
These capabilities appear in marketing materials, customer conversations, and competitive analyses.

Execution capabilities enable strategic capabilities without appearing in customer-facing messaging.
The streaming media company needs subscription management to monetize recommendations, the logistics company needs driver scheduling to execute optimized routes, the financial services company needs transaction processing to apply risk models.
Customers care about outcomes, not execution mechanics.

Compliance capabilities satisfy regulatory, security, or industry standard requirements without advancing business purpose.
Every financial services company must implement anti-money-laundering checks, every healthcare company must implement HIPAA controls, every payment processor must implement PCI-DSS requirements.
These capabilities represent cost of doing business rather than differentiation opportunities.

The Purpose Alignment Model clarifies why capabilities exist and what success looks like for each.
Strategic capabilities succeed by increasing competitive advantage, execution capabilities succeed by reducing cost and increasing reliability, and compliance capabilities succeed by minimizing audit burden and regulatory risk.

Mapping the Purpose Alignment Model onto Core Domain Charts reveals that strategic capabilities concentrate in the upper-right quadrant as core domains, execution capabilities distribute across supporting sub-domains, and compliance capabilities cluster in the lower-left as generic sub-domains using standard frameworks.

### Wardley Mapping for domain analysis

Wardley Mapping provides an evolution-aware perspective on domain classification by charting capabilities along a value chain from user-visible needs to underlying components, with each component positioned according to its evolutionary stage.

The evolution axis ranges from genesis through custom-built and product to commodity, reflecting how capabilities mature from novel innovations to standardized solutions over time.
Genesis-stage capabilities represent genuinely new approaches where best practices have not yet emerged.
Custom-built capabilities have established patterns but require implementation.
Product-stage capabilities have commercial or open-source solutions available.
Commodity-stage capabilities have become infrastructure utilities.

For domain analysis, Wardley Maps reveal which capabilities are candidates for core domain investment based on their evolutionary position and strategic importance.
Capabilities high in the value chain closer to user needs that remain in genesis or custom-built stages represent core domain opportunities.
Capabilities that have evolved to product or commodity stages should not receive core domain investment regardless of their value chain position.

Movement patterns on Wardley Maps indicate strategic opportunities and threats.
A core domain capability showing movement toward commodity stages suggests competitors are catching up, requiring innovation to maintain differentiation.
A generic capability showing unexpected movement toward genesis suggests market disruption creating new differentiation opportunities.

The intersection of Wardley Mapping with Core Domain Charts provides temporal context for classification decisions.
A capability in the upper-right quadrant today may drift toward lower-right as it commoditizes, changing investment strategy from custom development to integration.
Strategic planning requires monitoring evolutionary trajectories rather than assuming static classifications.

### Decision heuristics

Several practical heuristics help teams make classification decisions when analytical frameworks produce ambiguous results.

The competitor payment test asks whether competitors would pay significant license fees to use your implementation if it were available as a product.
If yes, the capability represents a core domain; if no, it is supporting or generic.
This heuristic cuts through rationalization about importance by focusing on external validation of value.

The domain expertise test asks whether correct implementation requires deep knowledge of a specialized field beyond general software engineering.
Core domains typically require hiring domain experts or training engineers in domain knowledge.
Generic domains can be implemented by competent generalist engineers following documentation.

The off-the-shelf availability test asks whether commercially or open-source solutions exist that satisfy requirements with minimal customization.
If multiple viable options exist, the capability is generic regardless of its importance to operations.
If no suitable options exist after thorough market research, the capability may be core or supporting.

The strategic pivot test asks whether this capability would survive if the business strategy changed significantly.
Core domains are tightly coupled to specific strategies and would change or disappear if strategy shifts.
Generic domains persist across strategies because they address universal requirements.

The customer conversation test asks whether customers mention this capability when explaining why they chose your solution over competitors.
Core domains appear in customer testimonials and case studies.
Generic domains remain invisible to customers even when they function perfectly.

Applying multiple heuristics to the same capability triangulates classification decisions.
Disagreement between heuristics indicates boundary cases requiring deeper analysis or stakeholder discussion.

## Investment prioritization

### Type sophistication by classification

Strategic classification directly determines the level of type-theoretic rigor applied during implementation, translating business strategy into concrete technical choices.

Core domains warrant the most sophisticated type systems available in the chosen implementation language.
Dependent types that encode domain invariants at the type level prevent entire classes of bugs through compile-time verification.
Refinement types that attach logical predicates to base types ensure values satisfy domain constraints.
Phantom types that track state transitions at compile time eliminate illegal state transitions.
Generalized algebraic data types that support indexed type families model complex domain relationships with precision.

For core domains in languages supporting full dependent types like Idris2 or Agda, specifications can be written as types with implementations carrying proofs of correctness.
In less sophisticated type systems, smart constructors combined with modules that hide representation types approximate these guarantees at runtime rather than compile time.

Supporting sub-domains warrant solid type discipline using features available in mainstream typed languages.
Smart constructors that validate invariants before construction ensure domain values maintain consistency.
Newtype wrappers that prevent mixing incompatible primitive types catch common errors.
Discriminated unions or algebraic data types that make illegal states unrepresentable eliminate defensive checks.
Parameterized types that track relationships between entities enable compiler-checked consistency.

The implementation patterns documented in `domain-modeling.md` for smart constructors, algebraic data types, and railway-oriented error handling provide appropriate rigor for supporting sub-domains without requiring dependent types.

Generic sub-domains warrant minimal type sophistication, focusing on safe integration with external systems rather than elaborate domain modeling.
Simple product types that combine fields into records provide sufficient structure.
Thin wrappers around library types from integrated services maintain type safety at boundaries.
Interface or trait-based polymorphism that allows swapping implementations enables testing and provider changes.

The validation strategy varies similarly by classification.
Core domains implement validation as compile-time proofs where possible, falling back to comprehensive runtime validation with property-based tests that verify invariants hold across generated inputs.
Supporting sub-domains implement runtime validation in smart constructors with property-based tests supplemented by example-based tests for edge cases.
Generic domains defer validation to integrated libraries, verifying only that integration adapters correctly translate between internal and external representations.

Testing strategies scale with domain importance.
Core domains combine property-based testing with formal verification where feasible, explicitly modeling domain laws as properties and proving implementations satisfy them.
Supporting sub-domains use property-based testing for invariants plus example-based testing for specific scenarios, achieving high confidence without proof overhead.
Generic domains focus on integration testing that verifies correct interaction with external services, treating the external system as the source of truth for correctness.

| Classification | Type Approach | Validation | Testing |
|---------------|---------------|------------|---------|
| Core | Dependent types, refinement types, indexed families | Compile-time proofs preferred, comprehensive runtime checks | Property-based tests as executable specifications, formal verification for critical paths |
| Supporting | Smart constructors, newtypes, discriminated unions | Runtime validation in constructors, invariant maintenance | Property-based tests for invariants, example-based tests for scenarios |
| Generic | Simple product types, library type wrappers, interface polymorphism | Library-provided validation, adapter translation checks | Integration tests verifying external interaction, contract tests for provider APIs |

### Build vs buy vs outsource

Strategic classification determines the default sourcing strategy for domain capabilities.

Core domains default to custom build with full ownership of implementation.
The competitive advantage depends on maintaining control over the capability and continuously refining it as business understanding evolves.
Licensing third-party solutions for core domains creates vendor dependency for strategic capabilities, allowing vendors to commoditize your differentiation or extract monopoly rents.

The build decision for core domains implies accepting significant upfront investment and ongoing maintenance costs in exchange for strategic control.
Organizations should expect to iterate core domain implementations multiple times, treating initial versions as learning exercises rather than final solutions.

Supporting sub-domains favor build when integration costs exceed implementation costs, and favor buy when the reverse holds.
The decision hinges on whether the capability requires specialized domain knowledge that already exists in the organization versus generic engineering patterns that vendors have standardized.

Custom implementations of supporting sub-domains make sense when they tightly integrate with multiple core domains, when organizational processes have unique requirements that prevent using standard solutions, or when total cost of ownership for commercial solutions exceeds internal development costs over multi-year horizons.

Purchased solutions for supporting sub-domains make sense when vendors offer mature products with established user bases, when the capability requires specialized expertise the organization lacks and does not want to build, or when implementation complexity exceeds the apparent problem scope due to edge cases and requirements that only emerge at scale.

Generic sub-domains default to buy or integrate with strong presumption against custom builds.
Building authentication, payment processing, or logging infrastructure from scratch wastes engineering resources on solved problems while introducing security and reliability risks from unproven implementations.

The rare exceptions where custom implementations of generic sub-domains are justified include situations where no existing solution supports required deployment constraints such as air-gapped environments or specialized hardware, where integration costs legitimately exceed implementation costs due to extreme scale or unusual requirements, or where regulatory requirements mandate custom implementations with specific certifications.

Outsource strategies apply primarily to supporting and generic sub-domains when capabilities are necessary but not differentiating, and when external specialists can deliver better results than internal teams.
Outsourcing transfers both implementation and often operational responsibility to vendors, appropriate when capabilities are stable with well-defined requirements.

The key risk in sourcing decisions is vendor lock-in where switching costs create dependency.
For core domains, vendor lock-in is unacceptable because it surrenders strategic control.
For supporting sub-domains, vendor lock-in is acceptable if mitigated by standard interfaces or if switching costs remain lower than ongoing implementation costs.
For generic sub-domains, vendor lock-in is acceptable because multiple vendors typically compete in commodity markets.

### Team allocation

Strategic classification determines team composition and talent allocation across domains.

Core domains receive the most experienced engineers with deep domain expertise.
These teams should include both senior technical talent capable of implementing sophisticated type systems and domain experts who understand the business problem deeply enough to identify meaningful invariants worth encoding.

The career development path for core domain engineers emphasizes growing both technical sophistication and domain knowledge.
Organizations should expect to invest in training engineers on domain concepts and providing time for experimentation with advanced techniques.

Rotating engineers through core domains spreads knowledge and prevents key-person dependencies, but rotation should be gradual enough that domain expertise accumulates rather than constantly draining away.

Supporting sub-domains receive mixed teams combining mid-level engineers who execute reliably with senior oversight.
The technical challenges in supporting sub-domains emphasize good engineering discipline rather than cutting-edge techniques, making them appropriate for developing engineer skills without requiring the most senior talent.

Pairing less experienced engineers with senior mentors in supporting sub-domains provides training ground for core domain work while maintaining quality standards.

Generic sub-domains receive integration specialists and junior engineers supervised by more senior engineers.
The primary skill for generic domains is understanding how to integrate external systems reliably rather than implementing sophisticated domain logic.

Organizations should avoid the pattern where generic sub-domains receive insufficient attention and accumulate technical debt.
While these capabilities do not warrant sophisticated custom development, they require competent integration engineering to prevent operational problems.

Deliberately allocating junior engineers to generic sub-domains as learning environments makes sense when combined with clear architectural boundaries that prevent integration complexity from leaking into other domains.

The team allocation strategy should align with investment priorities: roughly 60-70% of senior engineering time on core domains, 20-30% on supporting sub-domains providing oversight and handling complex integration points, and 10-20% on generic sub-domains ensuring reliable operation and mentoring junior engineers.

## Rigor level to type sophistication mapping

### Core domain type patterns

Core domains warrant maximum type-level precision, encoding as many domain invariants as possible in types that the compiler can verify.

Dependent types that treat types as first-class values enable specifications where types depend on runtime values.
A vector type parameterized by length allows functions that concatenate vectors to prove at compile time that the result has the correct length.
A state machine type parameterized by current state allows functions that transition states to prove at compile time that only legal transitions occur.

For core domains in languages like Idris2 or Agda, entire business rules can be encoded as dependent types with implementations carrying proofs.
A pricing engine might have types that prove calculated prices respect margin requirements, discount policies, and regulatory constraints, with the type checker rejecting any implementation that could violate these rules.

Refinement types that attach logical predicates to base types provide similar guarantees in languages like Liquid Haskell or F*.
A refined integer type representing prices might carry the predicate that values are always positive and do not exceed maximum price limits, with the type checker proving all operations preserve these properties.

Phantom types that encode state information without runtime representation enable compile-time tracking of entities through workflows.
An order type parameterized by phantom state types can transition from Draft to Submitted to Approved to Fulfilled, with functions typed to only accept orders in appropriate states and return orders in new states, making it impossible to fulfill a draft order or submit an already-submitted order.

Generalized algebraic data types that allow constructor return types to vary enable indexed type families representing complex relationships.
A syntax tree for a domain-specific language might use GADTs to ensure type-correct expressions at compile time, with the type system preventing construction of ill-typed terms.

The practical application in core domains involves identifying the most critical invariants that violations would cause business damage, then selecting type system features that can encode and verify those invariants.
Not every business rule needs dependent type encoding, but the rules that determine correctness of core domain logic warrant maximum rigor.

### Supporting domain type patterns

Supporting sub-domains use type patterns available in mainstream typed languages, emphasizing practical correctness over theoretical sophistication.

Smart constructors that validate invariants before allowing value creation ensure domain objects maintain consistency.
A customer email type might expose only a smart constructor that validates email format, making it impossible to construct invalid emails.
The constructor returns a Result or Option type, forcing callers to handle validation failure.

Newtype wrappers that create distinct types from primitives prevent mixing incompatible values.
Wrapping customer IDs, order IDs, and product IDs in separate newtype wrappers makes it a type error to pass a customer ID where an order ID is expected, even though both are represented as integers at runtime.

Discriminated unions or algebraic data types that enumerate all possible variants make illegal states unrepresentable.
An order status type represented as an ADT with variants Draft, Submitted, Approved, Fulfilled prevents the existence of orders in impossible states like "SubmittedButNotDraft" that string-based status flags allow.

Parameterized types that track relationships between entities enable compiler-verified consistency.
An OrderLine type parameterized by the Order type it belongs to prevents mixing order lines from different orders, with the type system ensuring aggregation operations only combine lines from the same order.

The implementation patterns from `domain-modeling.md` provide detailed guidance on these techniques, with supporting sub-domains applying them systematically to maintain correctness without requiring dependent types.

### Generic domain type patterns

Generic sub-domains use simple types focused on safe integration rather than sophisticated domain modeling.

Simple product types that combine fields into records provide sufficient structure for representing data from external systems.
A payment transaction type might be a record containing transaction ID, amount, currency, and timestamp, with structure mirroring the payment provider's API response.

Thin wrappers around library types from integrated services maintain type safety while delegating behavior to external implementations.
An authentication token type wraps the token type from the authentication library, exposing only the operations needed by application code and hiding library-specific details.

Interface or trait-based polymorphism that defines contracts for external services enables swapping implementations for testing and provider changes.
A payment processor interface defines charge and refund operations, with implementations for different providers conforming to the same contract, allowing the application to remain agnostic about which provider is configured.

The goal in generic sub-domains is not to model the domain deeply but to create clean boundaries between application code and external dependencies.
Types serve primarily as adapters translating between internal representations and external formats.

## Evolution and reclassification

### Domain evolution patterns

Domain classifications change over time as markets evolve, technology advances, and competitive dynamics shift.

The core-to-supporting evolution pattern occurs when capabilities that once differentiated businesses become expected baseline features.
Online shopping carts provided competitive advantage in early e-commerce but became supporting sub-domains once every retailer offered them.
The implication for systems is that investment levels should decrease over time as domains commoditize, shifting engineering resources toward new differentiators.

The supporting-to-generic evolution pattern occurs when third-party solutions emerge for previously custom-built capabilities.
Customer relationship management evolved from supporting sub-domains requiring custom development to generic sub-domains served by vendors like Salesforce.
Organizations should monitor supporting sub-domains for vendor solutions that could reduce implementation burden.

The generic-to-supporting evolution pattern occurs rarely when organizations discover differentiation opportunities in commodity capabilities.
A retailer might discover that customizing email delivery to optimize send times based on customer behavior creates measurable conversion improvements, elevating email from generic integration to supporting sub-domain worth custom development.

The supporting-to-core evolution pattern occurs when capabilities become strategic differentiators.
A logistics company might elevate route optimization from supporting to core as they develop novel algorithms that provide measurable competitive advantage.

Understanding evolution patterns helps organizations anticipate investment shifts and avoid misallocating resources to yesterday's competitive advantages or tomorrow's commodity solutions.

### When to reclassify

Reclassification triggers include market changes where customer expectations shift, technology shifts where new tools or platforms emerge, strategic pivots where business focus changes, and competitive response where competitors match or exceed capabilities.

Market changes that raise baseline expectations convert core domains to supporting sub-domains.
When all competitors offer similar recommendation engines, recommendation quality alone no longer differentiates, requiring innovation in new areas to regain advantage.

Technology shifts that introduce better tools or platforms may commoditize previously complex custom implementations.
The emergence of machine learning platforms reduced barriers to implementing recommendation engines, converting core domains to supporting sub-domains for some organizations.

Strategic pivots that change business model or target market alter which capabilities differentiate.
A company shifting from direct sales to marketplace model reclassifies vendor management from supporting to core while reclassifying inventory management from core to supporting.

Competitive response that matches capabilities forces reclassification from core to supporting.
If competitors successfully replicate a differentiating feature, it no longer provides advantage and should receive reduced investment in favor of new innovations.

Organizations should review domain classifications quarterly as part of strategic planning, explicitly examining which domains have shifted classification and what investment changes are warranted.

### Migration considerations

Reclassification requires migration between implementation approaches, either increasing rigor when generic or supporting domains become core, or decreasing rigor when core or supporting domains become generic.

Increasing rigor from generic to supporting involves introducing proper domain modeling with smart constructors and algebraic data types where thin wrappers previously sufficed.
The migration creates explicit value types with validation, replacing primitive types and external library types with domain-specific abstractions.

Increasing rigor from supporting to core involves introducing sophisticated type system features like dependent types or refinement types where smart constructors previously sufficed.
This migration often requires changing implementation languages or frameworks to access advanced type systems, representing significant investment justified only for genuine competitive advantages.

Decreasing rigor from core to supporting involves simplifying type-level proofs to runtime validation while maintaining correctness guarantees.
The migration preserves domain invariants but shifts enforcement from compile time to runtime, trading some verification strength for reduced implementation complexity.

Decreasing rigor from supporting to generic involves replacing custom implementations with third-party integrations.
This migration requires careful transition planning to preserve data and ensure external solutions actually satisfy requirements that custom implementations addressed.

All migrations should preserve correctness properties through the transition, either by maintaining dual implementations during cutover or by comprehensive testing that verifies new implementations satisfy existing invariants.

## Anti-patterns

Several common anti-patterns indicate misapplication of strategic domain analysis.

The "everything is core" syndrome treats all domains as equally important and worthy of maximum investment.
This pattern emerges from engineer enthusiasm for sophisticated techniques or stakeholder inability to prioritize capabilities.
The result is resource exhaustion where nothing receives sufficient investment because effort spreads too thin across too many domains.

Organizations exhibiting this pattern should force-rank capabilities by asking which they would fund if budget only allowed investing in one, then two, then three, revealing true priorities.

The premature commoditization pattern classifies capabilities as generic before thoroughly examining differentiation potential.
This pattern emerges from engineer preference for integrating existing solutions over custom development, or from bias toward minimizing implementation effort.
The result is missed competitive opportunities where modest additional investment could create meaningful differentiation.

Organizations should challenge generic classifications by asking whether competitors all use the same solution, and if not, why some competitors choose custom implementations.

The strategic context ignorance pattern applies classification frameworks mechanically without understanding business strategy or competitive positioning.
Capabilities are classified based on abstract principles rather than specific market context, producing theoretically correct but strategically irrelevant categorizations.

Domain analysis without business strategy input produces classifications disconnected from actual competitive advantage.

The classification without action pattern performs thorough domain analysis but fails to translate classifications into different investment levels, team allocations, or technical approaches.
After careful analysis correctly identifies core, supporting, and generic domains, all domains continue receiving uniform treatment.

The value of classification comes from differentiated investment, not categorization itself.
Organizations should audit whether core domains actually receive more resources, better engineers, and sophisticated technology than generic domains.

## See also

- `discovery-process.md` - overall methodology with domain classification as step 4
- `domain-modeling.md` - type sophistication patterns referenced by classification
- `bounded-context-design.md` - context boundary decisions informed by classification
- `architectural-patterns.md` - integration patterns varying by domain importance
- `railway-oriented-programming.md` - error handling rigor aligned with domain classification
