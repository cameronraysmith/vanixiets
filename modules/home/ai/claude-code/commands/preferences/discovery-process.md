# Discovery process

## Purpose

This document describes the discovery and design phases that precede implementation in domain-driven design.
It adapts the DDD Starter Modelling Process for algebraic functional domain modeling, providing a structured approach to understanding business domains and decomposing them into well-bounded components.
The discovery process produces informal artifacts like event storm sticky notes, business model canvases, and context maps that specification phases formalize into type systems and implementation phases realize in code.

Discovery is fundamentally collaborative and visual, involving domain experts, developers, and stakeholders in shared understanding before committing to formal specifications.
The algebraic interpretation provides the conceptual bridge from these informal artifacts to rigorous type-level specifications.

## Relationship to other documents

This document covers the discovery and design phases that produce inputs for several other preference documents.
After completing discovery, consult these documents for detailed guidance on subsequent phases:

*domain-modeling.md* provides implementation patterns for the domain models discovered through this process, including smart constructors, validation, aggregate design, and module algebra patterns.

*event-sourcing.md* describes persistence patterns for the domain events identified during event storming and domain storytelling sessions.

*architectural-patterns.md* covers application structure for organizing the bounded contexts and sub-domains discovered through decomposition.

*collaborative-modeling.md* offers detailed facilitation guidance for EventStorming, Domain Storytelling, and Example Mapping sessions referenced in step 2.

*strategic-domain-analysis.md* provides deeper analysis techniques for the Core/Supporting/Generic classification introduced in step 4.

*bounded-context-design.md* expands on context mapping and Bounded Context Canvas usage from steps 5 and 6.

The discovery process generates artifacts that these documents assume as inputs, creating a coherent workflow from collaborative exploration to formal implementation.

## When to use discovery

The DDD discovery process applies in seven primary scenarios, each with distinct motivations and constraints.

Greenfield projects benefit most from comprehensive discovery because architectural decisions made early compound over time.
Starting with EventStorming and Business Model Canvas work prevents premature commitment to inappropriate boundaries and helps teams avoid building the wrong thing correctly.
The investment in discovery pays dividends by reducing rework and maintaining conceptual integrity as the system grows.

Brownfield migration requires discovery to understand both the existing system and the target domain model.
Teams must map current implementation artifacts to domain concepts, identify where current boundaries conflict with domain boundaries, and plan incremental migration paths.
Discovery in brownfield contexts often reveals that technical boundaries like database schemas or service deployments obscure actual domain structure, requiring careful untangling.

Major program kickoff uses discovery to establish shared understanding across multiple teams before committing significant resources.
When organizations launch initiatives spanning multiple systems, teams, or business units, discovery helps coordinate effort and prevent duplicated work.
The context mapping exercises in steps 5 and 6 become especially valuable for clarifying handoff points and integration contracts.

Learning opportunities exploration applies discovery techniques to existing systems when teams want to improve their understanding without necessarily changing implementation.
Running EventStorming sessions on legacy systems often surfaces hidden domain knowledge, undocumented business rules, and opportunities for improvement.
This scenario emphasizes knowledge capture over immediate action.

Current state assessment uses discovery to create architectural documentation that reflects reality rather than aspiration.
Teams document actual context boundaries, message flows, and team structures to establish a baseline for improvement.
The gap between documented ideal architecture and discovered actual architecture often motivates refactoring priorities.

Team reorganization applies discovery in reverse, using domain boundaries discovered through EventStorming and context mapping to inform how teams should be structured.
Rather than organizing teams around technical layers or historical accident, discovery reveals natural boundaries that minimize coordination overhead and maximize team autonomy.

Practicing and learning DDD uses discovery as a teaching tool, applying the techniques to well-understood domains to build facilitation skills and internalize the approach.
Teams new to DDD benefit from practicing on toy problems before applying techniques to critical business domains.

## The discovery process

### Overview

The DDD Starter Modelling Process comprises eight steps organized into three phases.
Steps 1 through 6 constitute the discovery phase, producing informal collaborative artifacts that capture domain understanding.
Step 7 represents the specification phase, formalizing discovery outputs into precise type systems and architectural decisions.
Step 8 covers implementation, realizing specifications in executable code.

This document focuses on the discovery phase (steps 1-6) and the transition to specification.
The specification and implementation phases require different skills, tools, and mindsets, though they build directly on discovery outputs.

Discovery progresses from broad business context to fine-grained technical detail, maintaining a consistent focus on domain structure rather than technical implementation.
Each step involves different stakeholders, produces different artifacts, and answers different questions about the domain.

The process is intentionally iterative rather than strictly sequential.
Teams cycle through steps as understanding deepens, particularly repeating steps 2 through 6 as subdomain boundaries become clearer.
The adaptation patterns section describes common variations on the canonical sequence.

### Step 1: Understand the business context

Purpose is to establish the universe of discourse by understanding the business model, competitive landscape, strategic goals, and constraints within which the domain exists.
This step answers why the system matters to the business before exploring what the system does.

Tools include Business Model Canvas for understanding value propositions, customer segments, revenue streams, and cost structures.
Wardley Mapping reveals the evolutionary stage of different capabilities and identifies where to invest in custom development versus commodity solutions.
Impact Mapping connects business goals to user impacts to system features, preventing solutionizing before understanding objectives.
User Story Mapping organizes functionality by user journey and value delivery sequence rather than technical architecture.

Participants should include business leadership to articulate strategic goals, product management to represent customer needs, domain experts to explain current practices, and technical leadership to surface constraints.
Developers benefit from attending even if primarily listening, as business context shapes architectural decisions that arise later.

Outputs include a completed Business Model Canvas documenting the business model, Wardley Maps identifying capability maturity levels, Impact Maps linking goals to potential system features, and User Story Maps showing user journey structure.
These artifacts establish shared vocabulary and frame subsequent discovery work.

Algebraic interpretation treats the business context as defining the universe of discourse for the type system.
Business rules and constraints discovered here become type-level invariants enforced throughout the implementation.
Strategic priorities influence whether to use sophisticated dependent types for core domains or simpler ADTs for supporting domains.
The Business Model Canvas particularly helps identify entities (customer segments, channels, resources) that likely become first-class types and relationships that likely become functions or morphisms between types.

### Step 2: Discover the domain

Purpose is to explore the domain structure by surfacing domain events, commands, policies, and aggregates through collaborative modeling with domain experts.
This step shifts from business strategy to domain behavior, uncovering what actually happens in the domain.

Tools include EventStorming for discovering domain events, commands, policies, and aggregates through visual collaborative modeling.
Domain Storytelling captures realistic scenarios by having domain experts narrate actual work processes while facilitators diagram them.
Example Mapping clarifies business rules by exploring concrete examples organized around rules, examples, and questions.

Participants must include domain experts who perform the work daily, as they hold tacit knowledge often undocumented in formal specifications.
Developers and architects facilitate and ask clarifying questions but resist solutionizing.
Product managers help prioritize which scenarios to explore deeply.
The most effective sessions mix business and technical participants in roughly equal proportions.

Outputs include event storm boards covered in domain events (orange sticky notes), commands that trigger events (blue), policies that react to events (purple), aggregates that enforce consistency (yellow), and hotspots marking uncertainty or conflict (pink).
Domain Storytelling produces annotated diagrams showing actors, actions, and work objects in realistic scenarios.
Example Mapping generates rules with supporting examples and open questions requiring clarification.

Algebraic interpretation views domain events as candidates for sum type variants in the event algebra.
Domain events discovered through EventStorming translate directly to sum type constructors, where each orange sticky becomes a variant in the event ADT.

```haskell
data OrderEvent
  = OrderPlaced { orderId :: OrderId, items :: [Item], placedAt :: DateTime }
  | OrderConfirmed { orderId :: OrderId, confirmedAt :: DateTime }
  | OrderShipped { orderId :: OrderId, trackingNo :: TrackingNumber, shippedAt :: DateTime }
  | OrderDelivered { orderId :: OrderId, deliveredAt :: DateTime, signature :: Signature }
  | OrderCancelled { orderId :: OrderId, reason :: CancellationReason, cancelledAt :: DateTime }
```

These events map to the `Event` type parameter in the Decider pattern: `Decider<Command, Event, State>`.

Commands (blue stickies) become functions returning validated events or errors:

```haskell
placeOrder :: OrderData -> Validation (NonEmpty OrderError) OrderEvent
placeOrder orderData =
  validateItems orderData.items *>
  validateCustomer orderData.customerId *>
  pure (OrderPlaced (newOrderId ()) orderData.items (now ()))

confirmOrder :: OrderId -> Validation (NonEmpty OrderError) OrderEvent
confirmOrder orderId =
  checkOrderExists orderId *>
  checkPaymentReceived orderId *>
  pure (OrderConfirmed orderId (now ()))
```

Commands discovered through EventStorming become inputs to the `decide` function in the Decider pattern: `decide: Command → State → List<Event>`.
The validation logic shown above represents the command handling that occurs within `decide`.
See domain-modeling.md#pattern-5 for translating command/event discoveries to Decider implementations.

Policies (purple stickies) become event handlers producing downstream commands:

```haskell
onOrderPlaced :: OrderEvent -> [Command]
onOrderPlaced (OrderPlaced orderId items _) =
  [ SendConfirmationEmail orderId
  , ReserveInventory items
  , NotifyFulfillment orderId
  ]
onOrderPlaced _ = []
```

Aggregates (yellow stickies) identify consistency boundaries that enforce invariants through encapsulation:

```rust
// Order aggregate module signature
pub mod order {
    pub struct Order(OrderState); // private state

    pub fn place_order(data: OrderData) -> Result<(Order, OrderEvent), OrderError> {
        // smart constructor enforcing invariants
    }

    pub fn apply_event(order: Order, event: OrderEvent) -> Order {
        // event fold function for state evolution
    }
}
```

The free monoid structure of events (append-only, associative) emerges naturally from EventStorming outputs even when participants lack category theory background.
Event streams compose through concatenation, supporting both event sourcing persistence and choreography-style integration.

See `event-sourcing.md#event-discovery` for complete guidance on translating EventStorming artifacts to event types and `domain-modeling.md#smart-constructors-and-validation` for command validation patterns.

### Step 3: Decompose into sub-domains

Purpose is to partition the overall domain into cohesive sub-domains with clear boundaries and minimal coupling.
This step transforms the flat event storm board into a structured architecture by identifying natural seams in the domain.

Tools include Business Capability Modelling to identify stable capabilities that change independently.
Design Heuristics apply patterns like grouping events by aggregate lifecycle, separating read models from write models, and identifying bounded contexts where terms mean different things.
Independent Service Heuristics from team topologies help identify sub-domains that could operate autonomously with clear interfaces.

Participants typically include architects and senior developers to apply decomposition heuristics, domain experts to validate that boundaries respect domain structure, and product managers to ensure boundaries align with roadmap evolution.
This step requires more technical sophistication than step 2, as participants must balance domain purity with pragmatic concerns like deployment, team boundaries, and data ownership.

Outputs include a sub-domain map showing named sub-domains with their responsibilities, relationships between sub-domains indicating dependencies and communication patterns, and updated event storm boards with visual boundaries drawn around related events and aggregates.
Teams often discover that initial aggregate boundaries were too coarse or too fine, requiring iteration.

Algebraic interpretation treats sub-domains as module boundaries in the module algebra.
Sub-domain boundaries become module signatures (interfaces) hiding implementation details, where each sub-domain exports a public API while maintaining freedom to evolve internal structure.
Each bounded context or sub-domain may contain multiple Deciders, with the module signature exposing command-handling and query functions while hiding the internal Decider implementations.

```rust
// Order sub-domain module signature
pub trait OrderService {
    fn place_order(&self, data: OrderData) -> Result<OrderId, OrderError>;
    fn confirm_order(&self, id: OrderId) -> Result<(), OrderError>;
    fn get_order(&self, id: OrderId) -> Result<Order, OrderError>;
    fn cancel_order(&self, id: OrderId, reason: CancellationReason) -> Result<(), OrderError>;
}

// Fulfillment sub-domain module signature
pub trait FulfillmentService {
    fn ship_order(&self, id: OrderId) -> Result<ShipmentId, FulfillmentError>;
    fn track_shipment(&self, id: ShipmentId) -> Result<TrackingInfo, FulfillmentError>;
    fn confirm_delivery(&self, id: ShipmentId, signature: Signature) -> Result<(), FulfillmentError>;
}

// Payment sub-domain module signature
pub trait PaymentService {
    fn authorize_payment(&self, order: OrderId, amount: Money) -> Result<PaymentId, PaymentError>;
    fn capture_payment(&self, payment: PaymentId) -> Result<(), PaymentError>;
    fn refund_payment(&self, payment: PaymentId, amount: Money) -> Result<(), PaymentError>;
}
```

Boundaries between sub-domains identify functor boundaries where types and operations change meaning:

```haskell
-- Sales context: Order is a sales agreement
data SalesOrder = SalesOrder
  { salesOrderId :: OrderId
  , customer :: CustomerId
  , items :: [LineItem]
  , totalPrice :: Money
  }

-- Fulfillment context: Order is a picking list
data FulfillmentOrder = FulfillmentOrder
  { fulfillmentOrderId :: OrderId
  , warehouseLocation :: WarehouseId
  , pickingItems :: [PickingItem]
  , shippingAddress :: Address
  }

-- Explicit functor mapping at boundary
toFulfillmentOrder :: SalesOrder -> FulfillmentOrder
toFulfillmentOrder salesOrder = FulfillmentOrder
  { fulfillmentOrderId = salesOrder.salesOrderId
  , warehouseLocation = assignWarehouse salesOrder.items
  , pickingItems = map toPickingItem salesOrder.items
  , shippingAddress = getCustomerAddress salesOrder.customer
  }
```

The module algebra pattern (signature + algebra + interpreter) maps directly to sub-domain decomposition, where signatures define contracts, algebras provide implementations, and interpreters handle different execution contexts (testing, production, simulation).

```haskell
-- Signature: abstract interface
class OrderService m where
  placeOrder :: OrderData -> m (Either OrderError OrderId)
  confirmOrder :: OrderId -> m (Either OrderError ())

-- Algebra: concrete implementation
data OrderServiceImpl = OrderServiceImpl
  { orderRepo :: OrderRepository
  , eventBus :: EventBus
  }

-- Interpreter: run in specific effect context
runOrderService :: OrderServiceImpl -> OrderService m => m a -> IO a
```

The ability to compose modules through functorial relationships depends on discovering boundaries that respect natural domain structure rather than technical convenience.
Sub-domains aligned with business capabilities compose cleanly, while technically-motivated boundaries create coupling.

See `domain-modeling.md#module-algebra-for-domain-services` for detailed patterns on implementing module algebra and `architectural-patterns.md#hexagonal-architecture` for organizing sub-domain modules with ports and adapters.

### Step 4: Strategize domain investment

Purpose is to classify sub-domains as core, supporting, or generic to allocate implementation rigor appropriately.
This step prevents over-engineering generic domains while ensuring core domains receive sufficient investment in modeling quality.

Tools include Core Domain Charts plotting sub-domains on axes of business differentiation and model complexity to identify core domains worthy of sophisticated modeling.
Purpose Alignment Model helps teams articulate why certain domains deserve investment by connecting capabilities to business purpose.
The core domain classification directly influences whether to use dependent types, refined types, or simple ADTs for domain modeling.

Participants should include business leadership to identify strategic differentiators, architects to assess modeling complexity, and product managers to represent customer value perception.
Domain experts help validate whether proposed core domains actually contain sufficient complexity to warrant the classification.

Outputs include a Core Domain Chart with sub-domains plotted and classified, documentation of why specific domains classified as core, and investment guidelines specifying appropriate modeling rigor per classification.
For example, core domains might warrant Idris2 specifications with dependent types, supporting domains use Rust with newtype wrappers, and generic domains use TypeScript with runtime validation.

Algebraic interpretation uses core domain classification to determine type sophistication.
Core domains benefit from the strongest invariants expressible in the type system, potentially including dependent types that prove properties like "invoice totals equal sum of line items" or "shipment addresses match validated addresses in customer system".
Supporting domains use simpler refined types and smart constructors that enforce basic invariants without proof obligations.
Generic domains may use commodity solutions with minimal custom types, relying on integration patterns rather than deep modeling.

### Step 5: Connect sub-domains

Purpose is to understand how sub-domains coordinate by modeling message flows, process choreography, and integration patterns.
This step shifts focus from internal structure of sub-domains to the relationships between them.

Tools include Domain Message Flow Modelling to visualize how domain events flow between sub-domains and trigger downstream actions.
BPMN (Business Process Model and Notation) captures orchestrated processes where a central coordinator manages a workflow spanning multiple sub-domains.
Sequence Diagrams show temporal relationships between messages for specific scenarios.
Context Maps (introduced here but elaborated in step 6) begin to show structural relationships between contexts.

Participants typically include architects to design integration patterns, developers from different sub-domain teams to validate feasibility, and domain experts to confirm that technical flows match business process reality.
Product managers help prioritize which flows to optimize for performance or reliability.

Outputs include message flow diagrams showing events flowing between sub-domains with triggering relationships, sequence diagrams for critical scenarios revealing timing dependencies and bottlenecks, and initial context maps showing relationships between bounded contexts.
Teams identify integration patterns like Anti-Corruption Layer, Open Host Service, Published Language, or Shared Kernel.

Algebraic interpretation views message flows as Kleisli composition chains.
Context relationships discovered through message flow modeling become functors mapping types and operations between bounded contexts, where the relationship pattern determines the functor's characteristics.

For Partnership relationships, contexts share types bidirectionally through a shared kernel:

```typescript
// Shared kernel: common types used by both contexts
type CustomerId = string & { readonly __brand: 'CustomerId' };
type Money = { amount: number; currency: Currency };

// Both Order and Billing contexts import and use these types
import { CustomerId, Money } from '@shared/kernel';
```

For Customer-Supplier relationships, the upstream context publishes a stable interface (Open Host Service) that downstream contexts consume:

```rust
// Upstream Payment context publishes stable API
pub mod payment_api {
    pub struct PaymentRequest {
        pub order_id: OrderId,
        pub amount: Money,
        pub method: PaymentMethod,
    }

    pub enum PaymentResult {
        Authorized { payment_id: PaymentId, auth_code: String },
        Declined { reason: DeclineReason },
        Error { error: PaymentError },
    }
}

// Downstream Order context consumes published API directly
use payment_api::{PaymentRequest, PaymentResult};
```

For Anticorruption Layer relationships, the ACL module implements an explicit translation functor protecting the downstream context from upstream changes:

```rust
// External payment gateway types (upstream, outside our control)
struct ExternalPaymentResponse {
    status: String,  // "SUCCESS" | "FAILED" | "PENDING"
    transaction_id: String,
    error_code: Option<i32>,
}

// Domain payment types (downstream, our model)
enum DomainPaymentResult {
    Authorized { payment_id: PaymentId },
    Declined { reason: DeclineReason },
    Pending { tracking_id: TrackingId },
}

// ACL functor: external → domain translation
impl From<ExternalPaymentResponse> for Result<DomainPaymentResult, PaymentError> {
    fn from(external: ExternalPaymentResponse) -> Self {
        match external.status.as_str() {
            "SUCCESS" => Ok(DomainPaymentResult::Authorized {
                payment_id: PaymentId::from(external.transaction_id)
            }),
            "FAILED" => Ok(DomainPaymentResult::Declined {
                reason: map_error_code(external.error_code)
            }),
            "PENDING" => Ok(DomainPaymentResult::Pending {
                tracking_id: TrackingId::from(external.transaction_id)
            }),
            unknown => Err(PaymentError::UnknownStatus(unknown.to_string()))
        }
    }
}
```

Message flow choreography composes through Kleisli arrows in the effect monad:

```haskell
-- Each policy arrow: Event -> Effect [Command]
onOrderPlaced :: OrderPlacedEvent -> IO [Command]
onOrderPlaced event = do
  emailCmd <- generateConfirmationEmail event.orderId
  inventoryCmd <- reserveInventory event.items
  pure [emailCmd, inventoryCmd]

-- Kleisli composition: (>=>) composes effectful arrows
processOrderFlow :: OrderPlacedEvent -> IO [FulfillmentEvent]
processOrderFlow =
  onOrderPlaced >=>
  executeCommands >=>
  onInventoryReserved >=>
  triggerFulfillment

-- Where (>=>) :: (a -> m b) -> (b -> m c) -> (a -> m c)
```

Orchestration flows require explicit effect management through reader-writer-state or free monads:

```haskell
-- Orchestrator maintains state through effect stack
type OrderOrchestrator a = ReaderT Config (StateT OrderState (ExceptT OrchestratorError IO)) a

orchestrateOrder :: OrderData -> OrderOrchestrator OrderCompleted
orchestrateOrder orderData = do
  orderId <- placeOrder orderData
  paymentResult <- authorizePayment orderId
  case paymentResult of
    Authorized -> do
      reserveInventory orderId
      scheduleShipment orderId
      pure (OrderCompleted orderId)
    Declined reason ->
      throwError (PaymentDeclined reason)
```

See `bounded-context-design.md#category-theoretic-view-of-context-relationships` for detailed analysis of how Context Map patterns map to categorical structures and `event-sourcing.md#choreography-vs-orchestration` for choosing between choreography and orchestration styles.

### Step 6: Organize teams and contexts

Purpose is to align team structure with domain boundaries and document bounded context relationships through context mapping.
This step recognizes Conway's Law by ensuring organizational structure supports rather than fights domain structure.

Tools include Team Topologies to classify teams as stream-aligned (owning business domains), enabling (providing expertise), complicated subsystem (managing technical complexity), or platform (providing infrastructure).
Context Maps document relationships between bounded contexts using patterns like Partnership, Shared Kernel, Customer-Supplier, Conformist, Anti-Corruption Layer, Open Host Service, Published Language, and Separate Ways.
Bounded Context Canvas provides a structured template for documenting each context's purpose, domain language, responsibilities, and integration contracts.
Dynamic Reteaming techniques help transition from current team structure to target structure without disrupting delivery.

Participants should include engineering leadership to make organizational design decisions, architects to validate that team boundaries match context boundaries, domain experts to ensure teams have necessary expertise, and individual contributors to surface collaboration patterns and pain points in current structure.

Outputs include an organizational design showing teams mapped to bounded contexts, context maps documenting all relationships between contexts with explicitly chosen patterns, Bounded Context Canvases for each context documenting its contract, and a transition plan for evolving team structure if needed.
Teams explicitly decide for each relationship whether to invest in maintaining alignment (Partnership), protect downstream contexts (Anti-Corruption Layer), or accept upstream influence (Conformist).

Algebraic interpretation aligns team boundaries with module algebra boundaries.
Each team owns a module (signature plus algebra) and exports a public API (the signature) while maintaining freedom to change internal implementation (the algebra).
Context Map patterns become type system relationships: Shared Kernel means shared types, Anti-Corruption Layer means explicit functor translations, Open Host Service means published type definitions, Conformist means accepting upstream type definitions.
Team Topologies map to dependency directions in the type system: stream-aligned teams own domain types, platform teams own effect types (IO, logging, metrics), enabling teams provide generic abstractions (lenses, traversals).

## Adaptation patterns

The canonical eight-step sequence represents an ideal that teams adapt to context, constraints, and maturity.
Six common adaptation patterns address different starting points and organizational realities.

Starting with collaborative modelling applies when teams already understand the business context but need to discover domain structure.
Skip or abbreviate step 1, beginning with EventStorming or Domain Storytelling in step 2.
This pattern works well when working within an established product with clear business models but undertaking significant new feature development.
The risk is missing strategic context that would influence domain boundaries, so validate that business goals are actually well-understood before skipping step 1.

Starting by assessing IT landscape applies in brownfield contexts where existing systems constrain design options.
Teams first document current system boundaries, data flows, and integration points, then use discovery to reveal how current architecture aligns or conflicts with domain structure.
This pattern helps teams understand the gap between as-is and to-be architecture, informing migration planning.
The risk is anchoring too heavily on current technical boundaries, so facilitate EventStorming without reference to existing systems before comparing to current state.

Coding before confirming architecture allows teams to experiment with implementations in parallel with discovery.
After step 2 or 3, teams spike implementations to validate that discovered boundaries work technically.
This pattern prevents the surprise of discovering that beautiful domain models cannot satisfy performance, scalability, or integration requirements.
The risk is teams falling in love with spike implementations and resisting architectural insights from later discovery steps.

Repeating steps 2-6 before step 7 recognizes that initial decomposition attempts often need refinement.
After a first pass through to step 6, teams cycle back to step 2 with refined understanding to dig deeper into specific sub-domains.
This pattern particularly helps when initial EventStorming reveals that the domain is larger or more complex than anticipated.
The iteration allows progressive refinement where each pass answers different questions.

Organizing teams before designing contexts applies when organizational constraints are immovable in the near term.
Teams map contexts to existing team boundaries rather than defining ideal boundaries first.
This pattern acknowledges that team reorganization may be infeasible politically or practically, so architecture must work within constraints.
The risk is creating awkward domain boundaries that increase coordination overhead, so document the compromises and revisit when organizational flexibility increases.

Blending definition and coding eliminates the hard boundary between discovery and implementation by specifying types in executable languages as discovery proceeds.
After each EventStorming session, teams immediately encode discovered events as ADTs, commands as functions, and aggregates as modules.
This pattern provides rapid feedback on whether domain concepts compose well and surfaces modeling questions that guide next discovery sessions.
The risk is premature commitment to structures before understanding stabilizes, so use languages with good refactoring support and expect significant churn.

## From discovery to specification

Discovery produces informal artifacts optimized for collaboration and iteration, while specification produces formal artifacts suitable for implementation and verification.
The transition from discovery to specification formalizes domain understanding into type systems that make illegal states unrepresentable.

EventStorming events become variants in sum types encoding the domain event algebra.
An event storm board showing "Order Placed", "Order Paid", "Order Shipped", "Order Cancelled" becomes `data OrderEvent = OrderPlaced OrderPlacedData | OrderPaid OrderPaidData | OrderShipped ShippedData | OrderCancelled CancellationReason`.
The chronological sequence of sticky notes maps to the append-only, associative structure of the event stream.
Event metadata captured on sticky notes (timestamp, user, correlation ID) becomes fields in event wrapper types.

Commands become functions that validate business rules and produce events or validation errors.
A blue sticky note "Place Order" with attached business rules becomes a function `placeOrder : ValidatedOrderRequest -> Validation (NonEmpty OrderEvent)`.
The validation monad captures the potential for rule violations, while NonEmpty ensures that successful commands produce at least one event.
Business rules written in natural language on sticky notes become predicates in the validation logic or refinement types constraining input.

Policies become event handlers that produce commands in response to events.
A purple sticky note "When Order Placed, Send Confirmation Email" becomes a function `handleOrderPlaced : OrderPlacedEvent -> List EmailCommand`.
The List result type captures that policies may produce zero, one, or many commands.
Choreography emerges naturally as the composition of event producers and event consumers through pub-sub infrastructure.

Aggregates become modules with private state and public APIs that enforce consistency boundaries.
A yellow sticky note "Order" with attached events and commands becomes a module with a private `OrderState` type, smart constructors for creating orders, functions for executing commands that return validated events, and a fold function applying events to evolve state.
The functor or monad structure of aggregates supports composition while maintaining encapsulation.

Sub-domains discovered in step 3 become module boundaries in the codebase.
Each sub-domain gets a top-level module directory containing its types, functions, and internal implementation details.
Public APIs exported from subdomain modules use types and functions from the domain signature, while internal implementation uses concrete algebras.
The module system enforces that cross-subdomain dependencies only occur through public APIs.

Core domain classification from step 4 determines type sophistication.
Core domains use dependent types or refinement types to encode complex invariants, supporting domains use smart constructors and runtime validation, generic domains use simple product and sum types with minimal custom validation.
For example, a core pricing domain might use dependent types proving that discounts never exceed 100% and total price equals base price minus discount, while a generic notification domain uses simple records with minimal validation.

Message flows from step 5 become function compositions in Kleisli categories.
Each arrow in a message flow diagram becomes a function `A -> Effect B` where Effect encodes the relevant computational context (Maybe for partial functions, Either for error handling, IO for side effects, List for nondeterminism).
Composing arrows through monadic bind produces pipelines that sequence effectful operations while tracking effect types.

Context maps from step 6 become anti-corruption layer implementations.
Each relationship pattern in the context map dictates an integration approach: Shared Kernel means shared type definitions imported as dependencies, Anti-Corruption Layer means explicit translation functions between type systems, Conformist means accepting upstream types directly, Open Host Service means publishing stable type definitions.
The functorial mappings preserve semantics while allowing different contexts to maintain their own domain language.

## Algebraic interpretation summary

This table maps discovery artifacts to their algebraic interpretations, providing a reference for moving from informal to formal specifications.

| Discovery Artifact | Algebraic Interpretation |
|-------------------|-------------------------|
| Business Model Canvas | Universe of discourse defining types; business rules become type-level invariants |
| Wardley Map | Informs type sophistication by capability maturity; commodity = simple types, custom = rich types |
| Domain events (orange) | Sum type variants in event algebra; free monoid structure (append-only, associative) |
| Commands (blue) | Functions `ValidatedInput -> Validation (NonEmpty Event)` producing validated events |
| Policies (purple) | Event handlers `Event -> List Command` enabling choreography through composition |
| Aggregates (yellow) | Consistency boundary modules; functors or monads encapsulating state transitions |
| Sub-domains | Module boundaries; signatures (public API) + algebras (implementations) + interpreters |
| Core/Supporting/Generic | Type sophistication levels: dependent types / refinement types / simple ADTs |
| Message flows | Kleisli composition `A -> Effect B` chains in reader-writer-state or free monads |
| Context maps | Functor mappings between type systems; ACL = explicit translation, Shared Kernel = shared types |
| Team boundaries | Module ownership; team owns signature (contract) and algebra (implementation) |
| Bounded contexts | Separate type universes; context boundaries require explicit functorial translation |

The table emphasizes that every informal artifact discovered collaboratively has a formal algebraic counterpart suitable for specification.
This systematic mapping ensures discovery insights survive translation into implementation without loss of domain understanding.

## Anti-patterns

Several common mistakes undermine the discovery process by rushing to solutions or excluding critical perspectives.

Skipping discovery to jump straight to code trades short-term velocity for long-term rework.
Teams that begin coding without EventStorming or Business Model Canvas work often build the wrong abstractions, creating technical debt that compounds as the system grows.
The perceived time savings disappears when teams spend months refactoring inappropriate boundaries.
Even experienced teams benefit from explicit discovery because tacit domain knowledge rarely transfers completely through tribal knowledge.

Solo discovery by a single architect or developer misses the collaborative knowledge creation that makes discovery valuable.
Domain experts hold tacit knowledge about edge cases, historical context, and business rules that written documentation rarely captures.
Developers working alone tend to anchor on technical patterns rather than domain structure.
The real value of EventStorming comes not from the sticky notes but from the conversations that produce them.

One-time discovery treats domain understanding as a phase that completes rather than a continuous activity.
Domains evolve as businesses change, markets shift, and regulations update.
Teams that run EventStorming once at project inception find their domain models diverge from reality over time.
Schedule regular discovery sessions (quarterly or after major feature releases) to maintain model fidelity.

Discovery without documentation loses hard-won insights when team members leave or memories fade.
Taking photos of event storm boards without summarizing insights provides insufficient context for future reference.
Translate informal artifacts into documented architecture decision records, updated context maps, and annotated diagrams that persist beyond the workshop.

Over-formalizing too early undermines the exploratory nature of discovery by committing to structures before understanding stabilizes.
Encoding events as types immediately after the first EventStorming session discourages the refinement and reorganization natural to learning.
Maintain informal artifacts through several iterations before formalizing to allow understanding to stabilize.
Use spike implementations for validation without committing to production use.

## See also

*domain-modeling.md* for implementation patterns including smart constructors, validation, aggregate design, and module algebra that realize the structures discovered here.

*event-sourcing.md* for persistence patterns that capture the domain events identified during EventStorming as the system of record.

*collaborative-modeling.md* for detailed facilitation techniques for EventStorming, Domain Storytelling, and Example Mapping referenced in step 2.

*architectural-patterns.md* for application structure organizing the bounded contexts and sub-domains discovered through decomposition.

*bounded-context-design.md* for expanded guidance on context mapping patterns and Bounded Context Canvas usage from steps 5 and 6.

*strategic-domain-analysis.md* for deeper analysis of core domain identification and investment prioritization from step 4.

*railway-oriented-programming.md* for validation and error handling patterns that implement the command validation discovered in EventStorming.

*algebraic-data-types.md* for type construction techniques that formalize the events, commands, and aggregates discovered collaboratively.
