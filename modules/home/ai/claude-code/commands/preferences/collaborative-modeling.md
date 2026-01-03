# Collaborative modeling

## Purpose

Collaborative modeling techniques translate domain expertise into formal specifications through visual, participatory workshops with domain experts.
This document provides guidance on facilitating EventStorming, Domain Storytelling, and Example Mapping sessions that surface domain structure, business rules, and behavioral patterns before committing to implementation.

The techniques bridge the gap between informal domain knowledge held by subject matter experts and formal algebraic type specifications suitable for implementation.
While domain experts articulate business processes in natural language, facilitators guide discovery toward artifacts that map systematically to sum types, functions, invariants, and workflows in the type system.

## Relationship to other documents

This document provides detailed facilitation techniques for the collaborative modeling referenced in discovery-process.md step 2.
The discovery process establishes when and why to use collaborative modeling in the overall DDD workflow, while this document focuses on how to conduct effective sessions and interpret their outputs.

After completing collaborative modeling sessions, consult these documents for subsequent phases:

*discovery-process.md* provides the eight-step DDD workflow where collaborative modeling appears as step 2, establishing context and showing how modeling artifacts feed into decomposition, strategy, and specification phases.

*strategic-domain-analysis.md* helps classify the sub-domains discovered through collaborative modeling as core, supporting, or generic, determining appropriate investment levels in modeling rigor.

*bounded-context-design.md* documents the context boundaries that often emerge from collaborative modeling sessions, particularly when different groups of domain experts use the same terms with different meanings.

*domain-modeling.md* implements the algebraic structures discovered through collaborative modeling as smart constructors, aggregates, state machines, and workflows in code.

*event-sourcing.md* persists the domain events identified during EventStorming as the system of record, deriving application state from event history.

*railway-oriented-programming.md* composes the validation rules and business constraints discovered through Example Mapping into type-safe error handling pipelines.

## When to use collaborative modeling

Collaborative modeling applies whenever domain understanding needs to move from tacit knowledge in experts' heads to explicit, shared understanding suitable for implementation.
Six scenarios particularly benefit from the techniques described here.

Greenfield domain exploration establishes foundational understanding before writing any code.
Teams starting new projects use EventStorming to discover domain events, commands, and aggregates without bias from existing implementations.
The visual, collaborative nature surfaces assumptions and disagreements early, when changing direction costs nothing.
Participants leave sessions with shared vocabulary and mental models that persist through implementation.

Brownfield domain discovery maps existing systems to understand actual domain structure obscured by technical debt.
Teams run EventStorming on legacy systems to uncover implicit business rules, hidden workflows, and domain boundaries that evolved accidentally rather than by design.
The exercise often reveals misalignment between technical architecture and domain structure, motivating refactoring priorities.
Domain Storytelling particularly helps in brownfield contexts by capturing realistic scenarios that stress-test whether proposed models match actual work.

Requirements clarification for complex features uses Example Mapping to explore edge cases and business rules before implementation.
When product requirements documents leave questions unanswered or stakeholders disagree on expected behavior, Example Mapping systematically surfaces ambiguity through concrete examples.
The rules, examples, and questions structure forces precision without requiring technical terminology.

Cross-team alignment employs collaborative modeling when multiple teams work in related domains and need coordination.
EventStorming sessions spanning organizational boundaries reveal integration points, shared concepts, and areas where teams use the same terms with different meanings.
The context boundaries discovered inform team organization and API contracts.

Knowledge capture preserves expertise by externalizing tacit knowledge held by domain experts before turnover or organizational change.
Running EventStorming or Domain Storytelling sessions creates artifacts documenting how work actually happens, independent of how systems currently implement it.
The visual artifacts persist as onboarding materials and architectural documentation.

Learning DDD applies collaborative modeling techniques to well-understood toy domains as facilitation practice.
Teams new to EventStorming benefit from practicing on domains like lending libraries, conference registration, or shopping carts before applying techniques to critical business domains.
The safe environment allows experimentation with facilitation patterns and mapping from sticky notes to types.

## EventStorming

EventStorming discovers domain structure through collaborative, visual modeling focused on domain events and temporal flow.
Alberto Brandolini developed the technique to enable rapid domain exploration with minimal upfront structure, relying on emergence rather than predetermined formats.

The core insight is that focusing on domain events (facts about what happened in the domain) reveals system structure more effectively than focusing on entities or technical architecture.
Events are non-negotiable historical facts that domain experts readily identify without requiring technical translation.
The temporal sequence of events exposes causality, business processes, and invariants that participants might not articulate when asked directly about structure.

### Session types and purposes

EventStorming manifests in three forms with different scopes, participants, and outputs.

Big Picture EventStorming explores the entire domain to identify major sub-domains, context boundaries, and areas requiring deeper investigation.
The session typically runs 4-8 hours with 15-30 participants representing diverse perspectives across the business.
Facilitators encourage breadth over depth, covering the full temporal scope from initial customer contact through final outcome.
The output is a room-sized timeline showing hundreds of events with initial groupings indicating potential sub-domains, hotspots marking areas of uncertainty or conflict, and external systems identified where processes cross organizational boundaries.

Process Level EventStorming examines a specific sub-domain or business process to understand detailed flow, alternative paths, and business rules.
Sessions run 2-4 hours with 5-12 participants who work directly in the target domain.
Facilitators guide participants to explore happy paths, error cases, compensating actions, and temporal dependencies.
The output is a detailed timeline for the target process showing commands triggering events, policies reacting to events, aggregates enforcing rules, read models providing information for decisions, and business rules captured as constraints on the timeline.

Design Level EventStorming (also called Software Design EventStorming) translates process-level discoveries into software design artifacts suitable for implementation.
Sessions run 2-4 hours with developers and architects, sometimes including domain experts for clarification.
Facilitators help map events to aggregates, identify bounded contexts requiring separate implementations, and design APIs between contexts.
The output is an implementation-ready model with aggregates identified as consistency boundaries, events grouped by aggregate lifecycle, commands mapped to aggregate methods, and integration points between bounded contexts specified.

Teams typically start with Big Picture EventStorming to understand the landscape, then run Process Level sessions for priority sub-domains, and finally conduct Design Level sessions for areas being implemented immediately.
The progression provides increasing precision as understanding deepens and implementation approaches.

### Artifact vocabulary and sticky note colors

EventStorming uses colored sticky notes to represent different domain concepts, creating a visual language that participants learn quickly.
While the specific colors are conventional rather than mandatory, consistency within a session matters for comprehension.

Orange sticky notes represent domain events, the fundamental building blocks of EventStorming.
Events are facts about what happened in the domain, written in past tense with the format "Thing Happened" like "Order Placed", "Payment Received", or "Shipment Departed".
Events answer the question "what are the interesting facts about this domain?" and appear chronologically on the timeline from left to right.
Each sticky note captures a single atomic event with sufficient specificity that different participants agree on whether the event occurred.

Blue sticky notes represent commands that trigger events.
Commands are intentions or requests to do something, written in imperative mood like "Place Order", "Submit Payment", or "Cancel Subscription".
Commands precede the events they trigger, connected by proximity or arrows.
Not all events have explicit commands; some events are triggered by policies or external systems.

Yellow sticky notes represent aggregates, the consistency boundaries that enforce business rules and produce events.
Aggregates receive commands, validate business rules, and emit events if validation succeeds.
In early sessions, aggregates might represent entities like "Order" or "Customer", but as understanding deepens they represent specific consistency boundaries like "Shopping Cart" separate from "Order Fulfillment".

Purple sticky notes (or lilac) represent policies, which are automated reactions to events.
Policies have the form "Whenever [event] then [command]" like "Whenever Order Placed, then Reserve Inventory" or "Whenever Payment Failed, then Send Notification".
Policies enable choreography where aggregates react to events without direct coupling to event sources.

Pink sticky notes represent hotspots, which are areas of uncertainty, disagreement, or complexity requiring further investigation.
Participants place pink stickies wherever they have questions, disagree on what happens, or identify complexity that needs unpacking.
Hotspots indicate where to focus follow-up sessions or where to apply techniques like Example Mapping for clarification.

Green sticky notes represent read models, which are projections of domain state needed to make decisions.
Read models answer questions like "What is the customer's current order history?" or "How many items are in stock?" that inform whether commands can proceed.
In event-sourced systems, read models are derived from event streams, but EventStorming captures them even in systems using other persistence patterns.

Lilac or lavender sticky notes represent external systems that produce events or receive commands but whose implementation is outside the domain being modeled.
External systems mark integration boundaries where the domain depends on or influences other contexts.

Red sticky notes sometimes represent business rules or invariants that constrain the domain.
Teams use red stickies to capture rules like "Cannot ship order before payment received" or "Discount cannot exceed 100% of base price" that aggregates must enforce.

The color scheme creates visual patterns that aid comprehension even from a distance.
Clusters of orange events suggest major workflows, lonely blue commands without events indicate missing implementation or unrealistic expectations, and concentrations of pink hotspots reveal where the domain is poorly understood.

### Facilitation patterns

Effective EventStorming facilitation creates an environment where domain experts freely share knowledge while maintaining enough structure to produce actionable outputs.

Opening with structure and rules establishes the environment and expectations.
Facilitators explain the goal (understand the domain through events), introduce the color vocabulary, and emphasize that there are no wrong answers in the exploration phase.
Critical norms include one conversation at a time so everyone can participate, focus on domain terminology not technical implementation, and willingness to place sticky notes even when uncertain.
Starting with a concrete, specific event rather than abstract concepts helps participants understand what constitutes an event.

Exploring chaotic phase encourages divergent thinking where participants rapidly generate events without worrying about organization.
Facilitators provide unlimited sticky notes and wall space, encouraging participants to write events as fast as they think of them.
The goal is breadth and completeness, not accuracy or elegance.
Multiple people writing simultaneously prevents bottlenecks and surfaced different perspectives.
Facilitators intervene minimally, primarily to remind participants to write events in past tense and keep one event per sticky note.

Enforcing timeline structure transforms the chaotic collection of events into a temporal sequence.
Facilitators ask participants to arrange events left to right in chronological order, revealing causality and process flow.
Disagreements about ordering indicate missing events, alternative paths, or parallel processes.
Facilitators encourage discussion when participants disagree, as the disagreement often surfaces important domain knowledge.

Identifying commands and aggregates builds on the event timeline by asking what actions trigger events and what entities enforce rules.
For each cluster of events, facilitators ask "what action causes this event?" (command) and "what thing enforces the rules about whether this can happen?" (aggregate).
Commands without clear triggering events suggest missing UI or API endpoints.
Events without clear aggregates suggest missing domain concepts or overly generic thinking.

Surfacing policies reveals choreography by asking "when this event happens, what else happens automatically?"
Policies represent the reaction cascade that turns events into triggers for downstream behavior.
Facilitators watch for phrases like "whenever", "as soon as", or "when... then" which indicate policy thinking.

Marking hotspots explicitly captures uncertainty by encouraging participants to place pink stickies wherever they lack clarity.
Facilitators normalize uncertainty by placing their own hotspots and framing them as valuable findings rather than failures.
At the end of a session, reviewing hotspots together identifies priorities for follow-up investigation.

Exploring parallel swim lanes separates different perspectives on the same process.
When participants discover that different actors have different views of events or that the domain has multiple states simultaneously, swim lanes provide vertical separation while maintaining temporal alignment.
Actor swim lanes separate what customers experience from what warehouse staff experience.
State swim lanes separate what happens in the cart aggregate from what happens in inventory aggregate.

Dividing into sub-domains emerges when event clusters form natural boundaries with limited interaction.
Facilitators notice when participants talk about events in one area without referencing events in another area, suggesting weak coupling.
Drawing boundaries around clusters and naming the sub-domains explicitly documents the discovered structure.

Closing with retrospective and next actions consolidates learning.
Facilitators photograph the board, review hotspots to identify follow-up needs, and schedule Process Level sessions for high-priority areas.
Participants reflect on what they learned, what surprised them, and what questions remain.

### Facilitation anti-patterns

Several common mistakes undermine EventStorming effectiveness by constraining discovery or introducing premature structure.

Starting with entities or data models biases the discovery toward technical implementation rather than domain behavior.
Asking "what are the main entities?" leads to discussion of Customer, Order, Product, which may or may not reflect actual domain boundaries.
Starting with "what are the interesting facts about what happens?" allows boundaries to emerge from behavior.

Allowing technical solution discussion derails discovery into implementation debates that alienate domain experts.
When developers start discussing database schemas, API designs, or technology choices, facilitators intervene to redirect to domain behavior.
The simple rule "no nouns allowed" works surprisingly well for keeping focus on events (verbs).

Facilitating alone as a domain expert creates an impossible dual role where one person must both contribute knowledge and manage group dynamics.
Effective EventStorming requires a dedicated facilitator who maintains structure, mediates conflicts, and ensures equal participation without pushing their own domain interpretations.

Over-structuring the early exploration phase kills the divergent thinking that surfaces unexpected insights.
Facilitators who immediately correct "wrong" events, enforce strict timeline ordering, or demand perfect grammar prevent the chaotic exploration needed to surface tacit knowledge.
Structure comes later after broad exploration completes.

Accepting vague event names allows imprecision that causes problems during implementation.
Events like "Data Updated" or "Process Completed" lack the specificity needed to map to types.
Facilitators push for precision: "What specific data?" "What specific process?" "What does completed mean?"

Ignoring disagreements misses the opportunity to surface domain complexity or alternative perspectives.
When two participants disagree about event ordering or whether something is one event or two, facilitators lean into the disagreement with questions that unpack the different mental models.

Skipping hotspots pretends the domain is fully understood when uncertainty remains.
Facilitators explicitly ask "what are we unsure about?" and "where might this break down?" to surface limitations in current understanding.

### From sticky notes to algebraic types

The informal artifacts produced by EventStorming map systematically to formal type-level specifications suitable for implementation.
This mapping provides the conceptual bridge from collaborative discovery to rigorous specification.

Orange event sticky notes become constructors in a sum type encoding the event algebra for the domain.
An EventStorming timeline showing "Account Opened", "Deposit Made", "Withdrawal Made", "Account Closed" becomes:
```haskell
data AccountEvent
  = AccountOpened AccountOpenedData
  | DepositMade DepositData
  | WithdrawalMade WithdrawalData
  | AccountClosed ClosureReason
```
Each constructor represents one sticky note event, with associated data capturing the information written on or around the sticky.
The chronological sequence of events maps to the temporal ordering of elements in an event stream, which forms a free monoid under concatenation.

Blue command sticky notes become functions that validate business rules and produce events or validation errors.
A command "Open Account" with business rules about minimum deposit and account holder validation becomes:
```haskell
openAccount :: ValidatedAccountRequest -> Validation (NonEmpty AccountEvent)
```
The function signature documents that commands take validated input (enforcing smart constructors), return validation results (errors are explicit), and produce at least one event on success (NonEmpty ensures commands are effectful).
Business rules written in natural language on or near command stickies become predicates in the validation logic or refinement types constraining the input type.

Purple policy sticky notes become event handlers that produce commands in response to events.
A policy "Whenever Deposit Made, Update Balance Projection" becomes:
```haskell
handleDepositMade :: DepositMadeEvent -> List BalanceCommand
```
The List result type captures that policies may produce zero, one, or many commands depending on domain rules.
Choreography emerges naturally as the composition of event producers (aggregates) and event consumers (policies) through pub-sub infrastructure.

Yellow aggregate sticky notes become modules with private state and public APIs that enforce consistency boundaries.
An aggregate "Account" identified during EventStorming becomes a module containing:
- Private `AccountState` type representing current state
- Smart constructors for creating accounts
- Functions for executing commands that return validated events
- A fold function `applyEvent :: AccountEvent -> AccountState -> AccountState` that evolves state
- Exported types and functions constitute the public API

The aggregate's responsibility for enforcing invariants like "balance cannot go negative" becomes predicates in command validation functions or constraints in the state type.

Pink hotspot sticky notes become open questions in specification documents or property-based test scenarios exploring edge cases.
A hotspot "What happens if withdrawal is requested while deposit is processing?" indicates that the model needs to handle concurrent commands, suggesting either:
- Aggregate design that sequences commands
- Event sourcing with optimistic concurrency
- Explicit conflict resolution policy

The hotspot prevents blind implementation of an underspecified domain.

Green read model sticky notes become projections derived from event streams.
A read model "Current Balance" needed to validate withdrawal commands becomes:
```haskell
type BalanceProjection = AccountId -> EventStore -> Balance
balanceProjection accId store =
  store
  |> filterByAggregate accId
  |> foldl applyEventToBalance (Balance 0)
```
The read model is a pure function from event history to current state, ensuring that decision-making uses consistent views.

Red business rule sticky notes become type-level constraints or validation predicates.
A rule "Withdrawal amount must not exceed current balance" becomes either:
- A refinement type `type ValidWithdrawal = { amount : Amount | amount <= balance }`
- A validation predicate in the `makeWithdrawal` command function
- A property-based test checking the invariant holds across all event sequences

Lilac external system sticky notes become integration types with explicit effect handling.
An external system "Payment Processor" that receives payment commands becomes:
```haskell
type PaymentProcessor = PaymentCommand -> AsyncResult PaymentEvent PaymentError
```
The effect type (AsyncResult) makes the asynchrony and failure modes explicit, preventing naive treatment of external dependencies.

The systematic mapping ensures that informal collaborative artifacts translate mechanically into formal specifications without loss of domain understanding.
Teams can validate that the type system accurately reflects EventStorming discoveries by reading type definitions to domain experts using domain terminology.

### EventStorming examples

Three examples illustrate how EventStorming reveals different domain patterns and maps to algebraic structures.

Example 1 demonstrates order fulfillment process discovery.

A team running Process Level EventStorming for order fulfillment identifies this event timeline:
- Order Placed (customer action)
- Payment Authorized (external payment system)
- Inventory Reserved (warehouse system)
- Shipment Created (fulfillment system)
- Label Printed (shipping integration)
- Package Shipped (warehouse action)
- Tracking Number Assigned (external carrier)
- Delivery Confirmed (carrier notification)
- Order Completed (system closing out order)

Commands triggering events include Place Order, Authorize Payment, Create Shipment.
Policies discovered include "Whenever Payment Authorized, then Reserve Inventory" and "Whenever Package Shipped, then Send Tracking Email".
Aggregates identified are Order (manages order state), Shipment (manages fulfillment state), and Payment (manages payment state).
A key hotspot marks uncertainty about what happens if payment authorization fails after inventory reservation.

The mapping to types produces:
```haskell
data OrderEvent
  = OrderPlaced OrderDetails
  | PaymentAuthorized PaymentId Amount
  | InventoryReserved [StockItem]
  | ShipmentCreated ShipmentId
  | PackageShipped TrackingNumber
  | OrderCompleted

data OrderCommand
  = PlaceOrder ValidatedOrderRequest
  | CancelOrder OrderId Reason

placeOrder :: ValidatedOrderRequest -> Validation (NonEmpty OrderEvent)
```

The hotspot about payment failure reveals the need for compensating events:
```haskell
data OrderEvent
  = ...
  | PaymentFailed Reason
  | InventoryReleased [StockItem]  -- compensating event
```

Example 2 shows scientific data processing workflow.

Big Picture EventStorming for a research data pipeline reveals:
- Sample Collected (field work)
- QC Check Performed (lab processing)
- Assay Completed (lab equipment)
- Results Validated (scientist review)
- Outlier Detected (automated analysis)
- Results Approved (PI signoff)
- Data Published (external repository)

The session identifies two aggregates: Sample (lifecycle from collection through QC) and Dataset (lifecycle from results through publication).
A policy states "Whenever Outlier Detected, then Flag for Review".
A critical hotspot marks disagreement about whether Results Validated and Results Approved are the same thing or separate steps with different actors.

Follow-up Example Mapping clarifies that validation checks technical criteria (format, ranges, completeness) while approval checks scientific interpretation (consistent with hypothesis, appropriate methodology).
This distinction suggests separate events in different aggregates.

The mapping to types separates concerns:
```haskell
-- Sample aggregate
data SampleEvent
  = SampleCollected CollectionMetadata
  | QCCheckPerformed QCResults
  | AssayCompleted AssayData

-- Dataset aggregate
data DatasetEvent
  = ResultsValidated ValidationReport  -- automated
  | ResultsApproved ApprovalSignoff    -- human
  | DataPublished RepositoryId
```

Example 3 illustrates subscription billing flow.

Process Level EventStorming for subscription management discovers:
- Subscription Started
- Trial Period Began
- Trial Converted (or Trial Expired)
- Payment Scheduled
- Payment Succeeded (or Payment Failed)
- Renewal Processed (or Subscription Cancelled)

Commands include Start Subscription, Convert Trial, Cancel Subscription.
A policy states "Whenever Payment Failed, then Retry After 3 Days", revealing eventual consistency concerns.
The aggregate is Subscription, enforcing rules about state transitions.

A hotspot marks uncertainty about what happens if payment keeps failing indefinitely.
Domain experts explain that after 3 failures, the subscription enters "suspended" state where service is restricted but not fully cancelled.

This leads to a state machine type:
```haskell
data SubscriptionState
  = TrialActive TrialEnd
  | ActivePaid NextBilling
  | Suspended PaymentRetry
  | Cancelled CancellationReason

-- State transitions
convertTrial :: TrialActive -> Result ActivePaid ConversionError
suspendForFailure :: ActivePaid -> Suspended
cancelSuspended :: Suspended -> Cancelled
```

The state machine makes illegal transitions impossible by construction, preventing bugs where cancelled subscriptions get billed.

## Domain Storytelling

Domain Storytelling captures realistic domain scenarios by having domain experts narrate actual work processes while facilitators diagram them using a simple pictographic language.
Stefan Hofer and Henning Schwentner developed the technique to complement EventStorming by providing narrative structure and actor perspective often missing from event-focused exploration.

The core insight is that stories reveal domain structure through concrete examples rather than abstract descriptions.
When domain experts describe "how we process a priority customer order", they naturally include actors, sequences, exceptions, and decision points that might not surface in event-centric discussions.
The stories provide test scenarios for validating whether proposed domain models match reality.

### Pictographic language elements

Domain Storytelling uses a minimal visual vocabulary designed for rapid sketching without artistic skill.

Actors are stick figures or icons representing people, systems, or organizations that participate in the domain story.
Common actors include customers, employees in different roles (sales rep, warehouse staff, support agent), and external systems (payment processor, shipping carrier).
Each actor gets a distinct visual representation and appears consistently throughout the story.

Work objects are documents, data, or physical things that actors manipulate during the story.
Examples include orders, invoices, inventory items, customer records, or confirmation emails.
Work objects are drawn as rectangles or simple icons, labeled with their domain name.

Activities are the actions actors perform on work objects, drawn as arrows connecting actor to work object.
The arrow is labeled with a verb phrase describing the action: "places", "updates", "sends", "validates".
The arrow direction shows information flow: actor to work object for creation, work object to actor for reading, work object to work object for transformation.

Sequence numbers on arrows indicate temporal ordering, showing which actions happen first, second, third, and allowing parallel activities to share numbers when order doesn't matter.
Sequence numbers make the timeline explicit without requiring strict left-to-right layout.

Annotations capture business rules, questions, or variations discovered during storytelling.
Small sticky notes attached to the diagram preserve insights without interrupting story flow.

The pictographic language deliberately stays simple to keep focus on domain content rather than diagram aesthetics.
Anyone can draw stick figures and arrows, removing barriers to participation.

### Story recording patterns

Effective Domain Storytelling follows patterns that maximize domain learning while maintaining engagement.

Selecting the right stories balances representativeness and manageability.
Facilitators ask domain experts for typical scenarios that exercise important business rules, edge cases that reveal exception handling, and end-to-end flows that span multiple actors or systems.
Good stories have clear starting triggers and definite ending conditions.

Recording stories live during narration maintains pace and creates shared understanding.
Facilitators sketch directly on whiteboards or digital tools while domain experts narrate, speaking steps aloud: "First, the customer places an order on the website. Then, the system validates the order against inventory."
The live recording allows immediate feedback when the diagram misrepresents what the expert said.

Replaying recorded stories validates understanding by having the facilitator narrate back to domain experts using only the diagram.
If the facilitator can tell the complete story from the diagram alone, it captures sufficient information.
Gaps or ambiguities indicate missing elements.

Comparing variants explores how stories differ in different circumstances.
After recording a "normal" order process, facilitators ask "what's different for priority customers?" or "what happens if payment fails?"
Recording variants highlights where business rules create branches and where different actors or systems get involved.

Annotating domain rules inline captures the "why" behind actions.
When a domain expert says "we always check inventory before confirming the order", facilitators annotate the check activity with "rule: no overselling" to document the business constraint.

Connecting to EventStorming artifacts creates traceability between narrative and event models.
After recording stories, teams map activities to commands and events discovered in EventStorming.
Activities without corresponding events suggest missing elements in the event model.
Events without story coverage suggest either abstraction or events that don't appear in primary workflows.

### Extracting bounded contexts from stories

Domain stories reveal context boundaries through the language actors use and the work objects they manipulate.

Noticing terminology shifts identifies potential context boundaries.
When the same physical artifact has different names depending on which actor handles it (sales team calls it "proposal", legal team calls it "contract", fulfillment calls it "work order"), the terminology shift suggests crossing context boundaries.
Each context has its own language for domain concepts.

Identifying work object transformations shows context transitions.
When an activity fundamentally changes what the work object represents (unvalidated order becomes validated order, raw data becomes calibrated data, draft becomes published document), the transformation often crosses an aggregate or context boundary.

Observing actor isolation reveals autonomous contexts.
When certain actors work exclusively with certain work objects and rarely interact with actors in other parts of the story, the isolation suggests bounded contexts that could operate independently with clear interfaces.

Surfacing external system boundaries makes integration points explicit.
Activities where work objects cross system boundaries (order sent to payment processor, shipping label retrieved from carrier API) indicate where the domain must adapt external protocols.
These become candidates for anti-corruption layers or open host services in the context map.

### Complementing EventStorming with narrative flow

Domain Storytelling and EventStorming surface different aspects of domain structure, making them complementary rather than alternative techniques.

EventStorming excels at breadth, rapidly covering the entire domain landscape and identifying all events across all workflows.
The technique naturally discovers parallel processes, policies that trigger automatically, and the temporal ordering of events.
However, EventStorming can feel abstract to domain experts unfamiliar with event thinking.

Domain Storytelling excels at depth, exploring specific scenarios in concrete detail with explicit actors and decision points.
The technique grounds discussion in realistic examples that domain experts recognize from daily work.
However, Domain Storytelling can miss global patterns, policies, and events that span multiple stories.

Using both techniques together provides comprehensive coverage.
A typical workflow starts with Big Picture EventStorming to map the landscape, then uses Domain Storytelling to explore specific scenarios in priority areas, then returns to Process Level EventStorming to generalize from stories to complete event flows.

Mapping story activities to events validates event models against reality.
Each activity in a domain story should correspond to either a command triggering events or a read model query providing information for decisions.
Activities without event model counterparts suggest gaps.

Mapping events to story coverage validates events represent real workflows.
Events that never appear in any domain story might represent edge cases requiring separate stories, or might be speculative events that won't actually occur.

## Example Mapping

Example Mapping systematically explores business rules by organizing concrete examples around rules, examples, and questions in a structured conversation format.
Matt Wynne developed the technique as a refinement practice for Behavior-Driven Development, but it applies equally to domain modeling for surfacing and clarifying constraints.

The core insight is that business rules become precise through examples that illustrate when the rule applies, when it doesn't apply, and what happens at the boundaries.
Abstract rule statements like "premium customers get discounts" hide ambiguity about what makes a customer premium, which products qualify for discounts, and how discounts combine.
Concrete examples like "customer who spent $10,000 last year orders $500 item, receives 10% discount" expose edge cases and interpretation questions.

### Rules, examples, questions structure

Example Mapping uses color-coded index cards to organize the conversation.

Yellow cards represent the user story or feature being explored, written as a brief description of the capability like "Apply customer tier discounts to orders".
One yellow card anchors the session, preventing scope creep into unrelated features.

Blue cards represent business rules that govern the feature, written as conditional statements.
Example rules: "Premium customers receive 10% discount", "Discounts don't apply to sale items", "Multiple discounts don't stack".
Each rule gets its own blue card placed under the yellow story card.

Green cards represent concrete examples illustrating when and how rules apply.
Examples use specific values: "Customer tier: Premium, Order amount: $100, Discount: $10", "Customer tier: Standard, Order amount: $100, Discount: $0".
Green cards are placed under the blue rule they illustrate, with multiple examples per rule showing different cases.

Red cards represent questions that arise during the discussion, capturing uncertainty or disagreement.
Questions like "How do we determine customer tier?", "What happens if tier changes during checkout?", "Do employees count as premium customers?" park issues for follow-up without blocking the session.
Red cards attach to whichever rule or example triggered the question.

The spatial organization provides instant visual feedback about understanding.
Rules with many examples and few questions are well-understood and ready for implementation.
Rules with many red question cards need clarification before implementation.
Proliferating rules and examples indicate the feature might be too large for a single story.

### Connecting examples to property-based tests

The concrete examples from Example Mapping translate directly into property-based tests that verify implementations maintain discovered invariants.

Example-based test cases come directly from green cards.
Each green card becomes a test assertion:
```python
def test_premium_customer_discount():
    customer = Customer(tier=Tier.PREMIUM)
    order = Order(amount=Money(100))
    discounted = applyDiscount(customer, order)
    assert discounted.amount == Money(90)
```

The collection of examples for a rule suggests properties that should hold universally.
If examples show "Premium gets 10% off", "Premium ordering $50 gets $5 off", "Premium ordering $200 gets $20 off", the property is:
```python
@given(st.decimals(min_value=0))
def test_premium_discount_is_ten_percent(order_amount):
    customer = Customer(tier=Tier.PREMIUM)
    order = Order(amount=Money(order_amount))
    discounted = applyDiscount(customer, order)
    expected = Money(order_amount * Decimal('0.9'))
    assert discounted.amount == expected
```

Boundary examples identify inputs to test at edges.
If examples explore "$0 orders", "$0.01 orders", and "maximum $10,000 order limit", property tests focus on these boundaries:
```python
@example(Decimal('0'))
@example(Decimal('0.01'))
@example(Decimal('10000'))
@given(st.decimals(min_value=0, max_value=10000))
def test_discount_handles_boundaries(amount):
    ...
```

Multiple interacting rules suggest properties about rule composition.
If examples show that "premium discount" and "promotional code" rules interact, property tests verify the composition:
```python
@given(st.decimals(min_value=0), st.booleans(), st.booleans())
def test_discounts_compose_correctly(amount, is_premium, has_promo):
    # Property: final price never exceeds original price
    # Property: discounts don't stack (only best applies)
    ...
```

Red question cards become test scenarios pending clarification.
A question "What if customer tier changes during checkout?" becomes:
```python
@pytest.mark.skip(reason="Business rule unclear, see Example Mapping question #3")
def test_tier_change_during_checkout():
    ...
```

The test sits in the codebase as documentation of the gap, preventing accidental implementation of undefined behavior.

### Driving out edge cases before implementation

Example Mapping systematically surfaces edge cases through structured exploration of rule boundaries and interactions.

Exploring boundary values examines what happens at minimum, maximum, and zero values.
For a rule "orders over $100 qualify for free shipping", facilitators ask for examples at $99, $100, $100.01, $0, and maximum order size.
Boundary exploration often reveals that rules stated as simple thresholds actually have exceptions or special handling.

Testing negative cases confirms understanding by asking what happens when rules don't apply.
For "premium customers get discounts", facilitators ask for examples with standard customers, guest customers, and employees to verify different tiers are handled.

Combining multiple rules explores interactions and potential conflicts.
When rules include "premium discount 10%", "promotional code 15%", and "bulk discount 5%", facilitators ask "what happens when multiple apply?" and "which takes precedence?"
The examples often reveal that rules as stated are incomplete or contradictory.

Varying temporal aspects explores how time affects rules.
Rules about subscriptions, trials, renewals, or expirations need examples showing what happens before, during, and after relevant time windows.
Questions about "what if X happens while Y is processing?" surface concurrency concerns.

Questioning exceptional conditions asks about failures, errors, and recovery.
For "charge customer card", facilitators ask for examples when payment fails, card is expired, or charge is declined.
The examples reveal compensating actions and error handling that command functions must implement.

Exploring actor variations asks how rules differ by actor or context.
A rule that applies to customers might have variants for employees, partners, or automated systems.
The variations might indicate need for separate aggregates or policies.

## Working with domain experts

Domain experts hold tacit knowledge about business processes, constraints, edge cases, and the reasoning behind rules that written documentation rarely captures.
Effective collaboration with domain experts determines whether collaborative modeling surfaces this knowledge or merely confirms what developers already assumed.

### Ubiquitous language development

Ubiquitous language is the shared vocabulary that domain experts and developers use to describe the domain without translation.
The language emerges from collaborative modeling rather than being imposed upfront.

Capturing domain terminology exactly as experts use it preserves semantic richness and prevents misinterpretation.
When domain experts say "consignment" rather than "inventory held for sale", using their term ensures that discussions reference the same concept with all its implicit constraints.
Developers who translate to familiar technical terms lose the domain-specific meanings embedded in expert vocabulary.

Testing understanding by using domain terms in context verifies that developers comprehend not just definitions but usage.
After hearing a domain expert mention "settlement", developers might say "so when we settle the trade, we..." and let the expert correct misunderstanding.
If developers can narrate domain scenarios using only domain terms and experts recognize the description, ubiquitous language is working.

Noticing when experts disagree about terms reveals context boundaries or underspecified concepts.
When the sales expert calls something a "lead" and the fulfillment expert calls the same thing an "order", either the experts are talking about different stages of a lifecycle, or they work in different bounded contexts with different languages.
The disagreement is valuable information about domain structure.

Recording terms in a glossary preserves decisions but the glossary emerges from modeling sessions rather than being created upfront.
After each EventStorming or Domain Storytelling session, facilitators add newly discovered terms with definitions in the experts' words.
The glossary evolves as understanding deepens.

Refining terms when understanding improves maintains language precision as the model matures.
Initial EventStorming might identify an event "Order Processed", but deeper exploration reveals this actually means "Order Validated", "Order Allocated", or "Order Shipped" depending on context.
Refining terminology makes the model more precise without invalidating earlier work.

### Translating domain concepts to algebraic terms

Domain experts think in terms of business processes, entities, rules, and workflows, not types, functors, and monads.
Effective translation preserves domain semantics while enabling formal specification.

Describing types as "categories of things" grounds abstractions in domain language.
Rather than explaining sum types categorically, facilitators say "there are several kinds of customers: retail, wholesale, and government, and each kind has different information".
The domain expert recognizes this as obvious and the type follows naturally:
```haskell
data CustomerType = Retail RetailData | Wholesale WholesaleData | Government GovData
```

Describing smart constructors as "validation rules" connects to domain expert concerns about data quality.
Rather than explaining constructor privacy, facilitators say "we want to check that email addresses are valid when they're entered, not every time we use them".
Domain experts recognize this as good practice and the smart constructor emerges:
```haskell
createEmail :: String -> Result Email ValidationError
```

Describing state machines as "lifecycles" uses terminology domain experts already employ.
When experts say "orders go through several stages: draft, submitted, confirmed, shipped, delivered", they're describing states.
Facilitators ask "can an order go from draft straight to shipped?" and experts say "no", revealing the state machine structure.

Describing aggregates as "things that must be updated together" emphasizes consistency concerns domain experts understand.
Rather than explaining transactional boundaries, facilitators say "if we change the customer's address, do we need to update anything else at the same time?"
Experts identify related data like "default shipping address" and "billing address", revealing the aggregate boundary.

Describing events as "facts worth remembering" emphasizes history and audit.
Domain experts readily identify facts like "order was placed at 2PM", "payment was authorized for $100", or "shipment departed warehouse #3".
These facts naturally map to event types without requiring technical translation.

### When to introduce type theory concepts

Type theory concepts have different accessibility and payoff ratios.
Some concepts like sum types and validation are intuitive enough to introduce early, while others like functors and monads add little value to conversations with domain experts.

Introduce early when concepts directly solve domain problems.

Sum types (this OR that) address domain variation naturally.
When domain experts say "a payment is either a credit card or a bank transfer", the sum type is obvious:
```haskell
data Payment = CreditCard CardData | BankTransfer TransferData
```

Product types (this AND that) capture compound information.
When experts list "we need customer name, email, and shipping address", the product type follows:
```haskell
data Customer = Customer { name :: Name, email :: Email, address :: Address }
```

Validation and errors resonate with domain quality concerns.
Experts care about preventing bad data, so explaining that types can enforce rules gains buy-in.

State machines match mental models of lifecycles experts already hold.
Diagrams showing state transitions use familiar flowchart notation.

Keep implicit when concepts serve implementation without domain value.

Functors, monads, and category theory abstractions help developers structure code but mean nothing to domain experts.
Developers use these concepts during Design Level EventStorming and implementation without exposing them in domain conversations.

Effects and IO distinction matters to developers for purity and testing but domain experts care about what happens, not how it's encoded.
Commands that "save to database" or "call external API" are effects, but calling them effects adds no clarity.

Module algebras and signatures formalize boundaries developers maintain but experts describe as "this is the ordering system, that's the shipping system".
The technical machinery supports the intuitive separation without requiring explicit explanation.

The general rule is that type theory concepts should either directly solve a problem the domain expert articulated or remain invisible.
Using sophisticated type systems to implement simple domain concepts is valuable, but explaining the type theory to domain experts is not.

### Remote vs in-person facilitation

Collaborative modeling adapts to remote settings with appropriate tool choices and facilitation adjustments.

Remote EventStorming uses virtual whiteboard tools like Miro, Mural, or FigJam that support unlimited sticky notes, colors, spatial arrangement, and simultaneous editing.
Facilitators create templates with color legends and example events to orient participants.
Breakout sessions work well for initial chaotic exploration, with groups reconvening to share and integrate their event timelines.

Remote Domain Storytelling benefits from screen sharing where one facilitator draws while another navigates the conversation.
Recording sessions for later review helps capture details missed during live diagramming.
Digital tools like Lucidchart or Excalidraw provide the pictographic elements.

Remote Example Mapping translates well to tools like Miro or simple shared documents.
Color-coded cards become color-coded sticky notes or text boxes.
The structured turn-taking of Example Mapping actually works better remotely than other techniques because conversation doesn't fragment.

In-person sessions provide better peripheral awareness of who's engaged, who's confused, and who's trying to speak.
The physical board creates a shared artifact everyone can reference by pointing.
Energy and improvisation flow more naturally in person.

Hybrid sessions require extra facilitation attention to ensure remote participants have equal voice.
A dedicated facilitator monitors remote participants for raised hands or chat messages while another facilitates the room.
The physical board needs a camera providing clear view to remote participants.
Remote participants need explicit invitation to contribute since they can't naturally interject.

Choose modality based on participant distribution, domain complexity, and relationship maturity.
Distributed teams with no alternative use remote effectively with good tools and practices.
Sensitive domains where subtle disagreement matters benefit from in-person nuance.
Teams with established relationships and trust can work effectively remotely, while teams building relationships benefit from in-person investment.

## Artifact management

Collaborative modeling produces valuable artifacts that must persist beyond the workshop to inform implementation and onboarding.

### Digitizing physical artifacts

Physical EventStorming boards and Domain Storytelling diagrams require digitization for durability and sharing.

Photographing boards captures the spatial layout and annotations that might be lost in transcription.
Take photos from multiple angles and distances, capturing both overview and detail.
Photograph hotspots and annotations clearly enough that text is readable.
Date and label photos with the domain area explored.

Transcribing to digital tools like Miro or Lucidchart preserves the visual structure in editable form.
Transcription shortly after sessions (within 24 hours) captures details remembered by participants but not written explicitly.
Digital versions support search, linking, and evolution as understanding changes.

Creating narrative summaries documents the reasoning behind artifacts.
For EventStorming, summarize the main workflows discovered, hotspots requiring follow-up, aggregates identified, and context boundaries proposed.
For Domain Storytelling, write out the stories in text form supplementing the diagrams.
Narratives provide context for future team members reading artifacts months later.

Linking to source materials connects artifacts to business context.
Reference the business capability, product roadmap item, or strategic goal that motivated the session.
Link to Example Mapping outputs, acceptance criteria, or other related artifacts.

### Version controlling discoveries

Domain understanding evolves as teams learn more, so artifact versioning tracks how understanding changes.

Storing artifacts in git alongside code treats domain understanding as a versioned artifact.
Markdown files with embedded diagrams or links to tools like Excalidraw work well.
Commit messages document what changed: "refined Order aggregate after discovering payment reversal scenario".

Tagging artifacts by date and team creates chronological record.
File naming like `2025-01-order-fulfillment-eventstorming.md` or tags in frontmatter support discovery.

Updating artifacts when implementation reveals gaps maintains alignment between model and reality.
When developers discover during implementation that the event model missed a scenario, update the EventStorming artifacts to reflect the discovery.
The updated artifacts guide future features in the same domain.

Archiving superseded models preserves history without cluttering current understanding.
When a bounded context refactoring fundamentally changes the model, archive the old artifacts with context about why they changed.

### Connecting to specification pipeline

Collaborative modeling artifacts feed into formal specification and implementation through systematic mapping.

Creating issues or stories from hotspots ensures that uncertainty gets addressed.
Each pink hotspot sticky becomes a backlog item for clarification through Example Mapping, prototyping, or expert consultation.
Link the issue back to the EventStorming artifact showing where the hotspot appeared.

Generating type stubs from events and commands scaffolds implementation.
After EventStorming, generate skeleton code with types for events, commands, and aggregates even before business logic.
The skeleton makes the domain model concrete and invites developer feedback on feasibility.

Writing property tests from Example Mapping examples embeds domain rules in automated verification.
As shown in the Example Mapping section, translate concrete examples to property-based tests before implementation.

Maintaining traceability from artifact to code enables impact analysis.
When a domain expert explains that a business rule changed, traceability helps find which events, commands, types, and tests need updating.
Comments or documentation linking code to specific EventStorming sessions or Domain Storytelling diagrams provide the connection.

## Anti-patterns

Several common mistakes undermine collaborative modeling by constraining participation, introducing bias, or losing valuable insights.

### Jumping to implementation too early

Treating collaborative modeling as a brief prelude before "real work" of coding begins misses the value of deep domain exploration.

Developers who start coding during or immediately after EventStorming don't give understanding time to stabilize.
Domain models refined through multiple sessions are substantially different from models captured in the first session.
The instinct to "make progress" through code fights against the insight development that collaborative modeling enables.

Scheduling single two-hour sessions for complex domains produces superficial understanding.
Big Picture EventStorming for an entire domain requires at least four hours with diverse participants.
Process Level EventStorming for specific sub-domains benefits from multiple sessions as questions from earlier sessions get answered.

Effective collaborative modeling schedules exploration time proportional to domain complexity and strategic importance.
Core domains warrant days of modeling across weeks, allowing reflection and knowledge synthesis between sessions.
Supporting domains might need only one session.
The investment in understanding prevents expensive rework from misunderstood requirements.

### Ignoring domain expert terminology

Translating domain expert language into developer-familiar terms discards semantic richness and introduces bugs.

Developers who hear "consignment inventory" but write code about "inventory type B" lose the connection to domain knowledge.
When domain experts later reference consignment rules, developers must reverse-translate to find the relevant code.
The friction accumulates over time as the codebase diverges from domain language.

Imposing technical terminology on domain experts creates barriers to participation.
When developers talk about "entities", "value objects", or "aggregates" without grounding in domain concepts, experts disengage.
The session becomes a developer exercise rather than collaborative discovery.

Effective ubiquitous language uses domain terms consistently in code, conversation, tests, and documentation.
If domain experts say "settlement", the code has `Settlement` types and `settle()` functions, not `ProcessTransaction` or `FinalizePayment`.
Developers learn domain vocabulary and use it natively.

### Over-abstracting during discovery

Introducing technical patterns or abstractions during exploration phase constrains creative discovery and biases toward familiar solutions.

Developers who immediately categorize domain events as CRUD operations (Created, Updated, Deleted) miss the rich domain semantics.
"Order Placed" is not "Order Created" because it captures the customer's action and intent, while Created suggests technical record creation.
The semantic distinction matters for understanding business processes.

Facilitators who enforce technical patterns like "all aggregates must have a root entity" during initial EventStorming impose structure before understanding emerges.
Let participants identify natural consistency boundaries, then map to aggregate pattern, not vice versa.

Discussing database schemas, API designs, or deployment architectures during domain discovery derails conversation and alienates domain experts.
These decisions follow from domain understanding rather than preceding it.

Effective facilitation delays pattern-matching and abstraction until after exploratory phase completes.
Let participants identify "things that enforce rules" before naming them aggregates.
Let events emerge before organizing into bounded contexts.
The patterns become visible retrospectively rather than imposed prospectively.

## See also

*discovery-process.md* provides the overall DDD workflow where collaborative modeling appears as step 2, showing how modeling feeds into decomposition, strategy, context mapping, and specification phases.

*strategic-domain-analysis.md* classifies the sub-domains discovered through collaborative modeling as core, supporting, or generic to determine appropriate investment in modeling rigor and type sophistication.

*bounded-context-design.md* documents the context boundaries and integration patterns that emerge from collaborative modeling, particularly when terminology shifts indicate separate bounded contexts.

*domain-modeling.md* implements the structures discovered through collaborative modeling as smart constructors, aggregates, state machines, and workflows using algebraic types and functional composition.

*event-sourcing.md* persists the domain events identified during EventStorming as the authoritative system of record, deriving application state through event replay and projections.

*railway-oriented-programming.md* composes the validation rules and business constraints discovered through Example Mapping into type-safe error handling pipelines using Result and Validation types.

*algebraic-data-types.md* formalizes the sum types, product types, and refinement types that encode the events, commands, and invariants discovered during collaborative modeling.

*theoretical-foundations.md* provides the categorical underpinnings of the algebraic interpretations described throughout this document, connecting domain artifacts to concepts like free monoids, functors, and Kleisli categories.
