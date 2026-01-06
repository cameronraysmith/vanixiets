# Event Modeling

## Purpose

Event Modeling is a specification technique that produces detailed system blueprints through a structured 7-step methodology, transforming abstract domain understanding into implementable designs with precise command schemas, read model projections, and behavioral scenarios.
This document covers Adam Dymitruk's Event Modeling methodology as implemented in Qlerify, providing workflow patterns, UI conventions, and algebraic interpretations for Claude Code guidance during Event Modeling sessions.

Event Modeling differs from EventStorming by focusing on specification rather than discovery.
Where EventStorming explores domain structure through chaotic collaborative brainstorming, Event Modeling systematically documents commands, read models, and behavioral scenarios with field-level schemas suitable for code generation and EventCatalog transformation.
EventStorming reveals what events exist and how they relate, while Event Modeling specifies exactly what data each command requires, what information actors need before making decisions, and what scenarios must be tested.

## Relationship to other documents

Event Modeling and EventStorming serve different purposes and can be used independently.
EventStorming excels at rapid collaborative discovery when domain structure is unclear or contested, producing informal artifacts like sticky notes suitable for team alignment.
Event Modeling produces implementation-ready specifications with field-level schemas through its own brainstorming phase (Step 1) plus six subsequent refinement steps.

*collaborative-modeling.md* describes EventStorming as a pure discovery technique.
Teams may use EventStorming for exploration without proceeding to Event Modeling, or start Event Modeling directly without prior EventStorming.
If both techniques have been used, EventStorming artifacts can optionally enrich Event Modeling's brainstorming phase as supplementary input.

*event-catalog-qlerify.md* provides the transformation workflow from Qlerify Event Modeling JSON exports to EventCatalog MDX artifacts with JSON Schema.
Event Modeling sessions produce the source artifacts that this transformation consumes, generating discoverable documentation from implementation specifications.

*event-catalog-tooling.md* documents EventCatalog concepts and algebraic foundations including the Decider pattern, free monoid events, and module algebra services that Event Modeling artifacts map to during transformation.

*discovery-process.md* positions Event Modeling within the DDD workflow.
Event Modeling appears after initial EventStorming (step 2) when teams have identified domain events and aggregates but need detailed specifications before implementation.
The methodology spans steps 2 through 7 of the discovery process, bridging collaborative exploration and formal specification.

*domain-modeling.md* implements the Decider pattern that Event Modeling aggregates map to during code generation.
Commands discovered through Event Modeling become inputs to the `decide` function, events become outputs, and aggregate roots become Decider modules with private state.

*railway-oriented-programming.md* composes validation rules discovered through Given-When-Then scenarios into type-safe error handling pipelines, translating behavioral specifications into Result types and validation chains.

## When to use Event Modeling versus EventStorming

Event Modeling and EventStorming address different needs and can be used independently.

Use EventStorming when domain structure is unclear or contested and you need rapid collaborative discovery.
Multiple stakeholders with different perspectives benefit from chaotic exploration where everyone contributes events simultaneously.
EventStorming surfaces assumptions, disagreements, and hotspots without requiring commitment to implementation details.
The output is informal artifacts like sticky notes suitable for team alignment, context mapping, and sub-domain identification.

Use Event Modeling when you need implementation-ready specifications with field-level schemas.
Event Modeling's 7-step process includes its own discovery phase (Step 1: Brainstorming) that generates events through AI-assisted prompts or collaborative input.
The methodology produces typed command schemas, read model definitions, Given-When-Then scenarios, and bounded context assignments suitable for code generation.
Teams can start Event Modeling from scratch using natural language workflow descriptions without prior discovery work.

Optionally combine both techniques when you want collaborative discovery to inform specification.
If you have run EventStorming sessions, those artifacts can enrich Event Modeling's brainstorming phase.
This is optional enrichment, not a prerequisite.
Event Modeling's brainstorming step is self-sufficient for teams starting fresh.

## Optional: Enriching brainstorming with EventStorming artifacts

If you have previously run EventStorming sessions, those artifacts can optionally enrich Event Modeling's Step 1 brainstorming phase.
This integration pattern is supplementary, not required.
Event Modeling's AI-assisted brainstorming or collaborative input provides complete discovery for teams starting fresh.

Orange event sticky notes are reused as Event Modeling events with field schemas added.
The event name transfers directly while field-level details emerge through storyboarding and domain expert interviews.
Questions to elicit fields include "when this event happens, what facts are worth recording?" and "what information would someone need to understand what occurred?"

Blue command sticky notes are reused as Event Modeling commands with field schemas and validation rules added.
The command name transfers while form fields emerge through the storyboard step.
Questions to elicit fields include "when the actor performs this action, what information must they provide?" and "what validation rules determine whether the command succeeds?"

Purple policy sticky notes transform into automation patterns or translation patterns depending on trigger type.
Policies triggered by scheduled processes or queries become automation patterns with read models as eligibility queries.
Policies triggered by external events become translation patterns with read models as external event payloads.
The "whenever X then Y" structure becomes Given-When-Then scenarios capturing the conditional logic.

Yellow aggregate sticky notes are reused for bounded context assignment in Step 6.
Aggregates identified during EventStorming become aggregate roots in the Event Model, grouped into bounded contexts based on team ownership and deployment boundaries.

Pink hotspot sticky notes transform into Given-When-Then scenarios that test edge cases and resolve uncertainty.
Each hotspot represents a question or disagreement that becomes a behavioral specification documenting expected behavior.
Converting hotspots to GWT scenarios forces explicit resolution of ambiguity before implementation.

Green read model sticky notes are reused directly if present or added during Step 5 if missing.
EventStorming read models transfer as starting points while Event Modeling adds field-level query definitions.

Lilac external system sticky notes transform into translation pattern read models representing external event payloads.
The external system boundary becomes an integration point where incoming data is interpreted and conditionally triggers domain events.

New information required during Event Modeling that does not exist in EventStorming includes typed field schemas for all commands and events, UI form designs via command field ordering, query definitions for read models, Given-When-Then behavioral scenarios, and bounded context assignments mapping aggregates to team ownership.

Event Modeling Step 1 (Brainstorming) generates events, commands, aggregates, and read models through AI-assisted prompts or collaborative manual entry.
EventStorming artifacts provide optional supplementary input when available, not prerequisite material.

## The 7-step Event Modeling methodology

### Step 1: Brainstorming

Purpose is to generate the initial set of domain events through AI-assisted prompts or manual entry, establishing the temporal backbone of the system specification.

In Qlerify, brainstorming begins with a natural language description of the workflow or business scenario.
The AI generates events in past tense along with suggested commands, read models, aggregate roots, and bounded contexts based on the description.
This differs from EventStorming's chaotic sticky note phase by producing structured artifacts immediately rather than starting with unorganized exploration.

The AI uses Card Type Settings to determine what artifacts to generate.
Command cards produce blue boxes representing imperative actions, Aggregate Root cards produce yellow entity boxes establishing consistency boundaries, Read Model cards produce green boxes showing data needed for decisions, and Given-When-Then cards produce purple scenario boxes specifying behavior.
Domain Model Role mappings ensure correct semantic tagging during generation.

Generated artifacts include field-level details immediately rather than just entity names.
Commands have typed fields representing form inputs, read models have fields representing query results, and aggregate roots have fields representing state properties.
Timeline arrows show plausible temporal ordering that provides narrative flow without enforcing strict causality.

The AI-assisted approach trades EventStorming's tacit knowledge discovery for rapid initial modeling.
Teams gain speed but risk missing domain nuances that emerge only through collaborative exploration with domain experts.
Best practice combines AI generation for initial structure with subsequent domain expert validation workshops.

### Step 2: The Plot

Purpose is to organize events into coherent timeline using swimlanes exclusively for actors rather than systems or bounded contexts.

Qlerify enforces a critical convention that swimlanes represent actors (roles that perform actions), deferring system boundaries to bounded context assignment in Step 6.
This differs from traditional Event Modeling where swimlanes might represent systems, bounded contexts, or teams without strict convention.

Actor types include human actors (Guest, Manager, Employee, Administrator) representing people performing actions, an Automation actor representing automated processes like timers and background jobs, and occasionally external system actors when external entities initiate actions (though most external interactions model as external events rather than external actors).

The workflow involves reviewing generated swimlanes, identifying which represent systems or bounded contexts rather than actors, creating actor-based swimlanes for human and automated roles, moving events to appropriate actor lanes, deleting system-based lanes, and validating that temporal ordering tells a coherent narrative.

Common corrections include replacing "GPS Device" with Automation (if our system triggers GPS reading) or deleting it (if external GPS device), replacing "Payment System" with Automation (if we invoke payment API), and moving "Inventory Service" events to Manager or Automation depending on who triggers the action.

Timeline arrows in Qlerify show example of how events typically unfold rather than meaning event A automatically triggers event B.
Arrows provide narrative comprehension without enforcing strict execution sequence, recognizing that events may occur in different orders depending on business rules.

The actor-exclusive swimlane convention forces separation of "who performs action" (actor perspective) from "which system owns aggregate" (technical architecture).
This prevents conflating organizational structure with runtime architecture, a common anti-pattern in traditional Event Modeling.

### Step 3: The Storyboard

Purpose is to create UI mockups via command data fields, making abstract events tangible by designing the forms actors use to trigger events.

For each event on the timeline, designers switch to the sidebar Data Fields tab and inspect the command (blue box) on the Domain Model diagram.
Fields on the command define the input form structure, representing what information the actor must provide to cause the event.

The guiding question is "What does the input form look like when [actor] performs [event action]?"
This grounds Event Modeling in implementable UX patterns rather than abstract specifications.

Designers add, update, remove, and reorder fields on the command to design the UI mockup.
Field ordering matters for natural form flow, matching how users think about the information (name before phone, email before password).
The sidebar renders a form based on command schema, providing immediate visual feedback on the design.

For automated events, designers imagine "a robot filling out the form and pressing submit button" to identify what data the automation needs.
This mental model clarifies that automation events still have commands with structured data even though no human manually fills the form.

The storyboard step bridges abstract events to concrete UX, answering "how would a user cause this event?" through form design.
This differs from EventStorming where commands remain abstract blue stickies without field-level specifications.

### Step 4: Identify Inputs

Purpose is to name the command that triggers the event when the form is submitted, establishing domain language for imperative actions.

The workflow involves reviewing AI-suggested command names (usually imperative verb phrases), validating names match domain language and actor intent, and renaming if needed to align with ubiquitous language.

Naming conventions follow imperative mood (Register Account, Book Room, Add Room), express action from actor perspective (Request Payment not Process Payment Request), and use exact terms from domain experts rather than developer abstractions.

The pattern typically converts past tense events to imperative commands.
Event "Account Registered" becomes command "Register Account", following [Verb] + [Noun] structure.

This step is often trivial if AI generated appropriate names initially.
The value lies in validating domain language alignment rather than mechanical naming, ensuring that command names match how domain experts articulate intentions.

### Step 5: Identify Outputs

Purpose is to define read models representing data needed before commands execute, documenting what information actors consult when making decisions.

Qlerify interprets "outputs" counterintuitively as inputs to decision-making rather than outputs of events.
Read Model represents data consumed before command is triggered, adopting an actor-centric perspective where "output" means "what the system outputs for the actor to view" rather than "what events output."

The workflow involves selecting an event, reviewing the read model (green box) on the Domain Model diagram, and asking "What information does [actor] need to [perform command]?"
Fields added to read models define what information gets displayed to the actor before decision-making.

For Guest Registered Account, the read model might include Terms and Conditions, Privacy Policy, and Benefits that the guest reviews before deciding to register.
For Guest Booked Room, the read model shows available rooms, prices, and amenities informing the booking decision.
For Manager Added Room, the read model displays room catalog and room type definitions as reference data.

Traditional Event Modeling treats read models as outputs or views derived from events (CQRS projections), while Qlerify treats read models as inputs or context needed for commands.
The Qlerify approach centers discussion around a single actor's decision-making flow: actor views read model (information gathering), actor fills out command form (decision implementation), event occurs (state change recorded).

Events can have multiple associated read models (different information sources consulted before deciding) but must have exactly one command (the singular action that triggers the event).

### Applying Steps 3-5 to all events

After completing the storyboard, input identification, and output identification for the first event, iterate through all events on the timeline.
Each event receives systematic treatment through the three steps.

#### Regular input form pattern

Human actor fills form manually with no special processing logic.

The command has input fields for manual entry representing the data the actor provides.
The read model shows query results or reference data informing the actor's decision.
Examples include Manager Added Room and Guest Booked Room.

#### External event pattern

Event triggered outside system boundary by external systems, devices, or third parties.

Qlerify convention deletes the command (no form in our system), deletes the read model (no query in our system), keeps the event (fact happened externally), and keeps the entity/aggregate root (receives external data).

For example, Sent GPS Coordinates represents an external GPS device sending coordinates.
We document the event for reference but don't model internal command/read model since we don't control the external system.
Detailed modeling happens in the next event where we receive and process the external data.

The rationale is that external events represent integration boundaries.
We document that external events occurred but don't pretend to model external system internals.

#### Translation pattern

Event triggered by processing external event data through interpretation logic that conditionally produces domain events.

Translation means receive external event, interpret data according to business rules, and conditionally trigger domain event if interpretation succeeds.

The read model represents incoming external event data (not a query).
The command represents our domain action if interpretation succeeds.
The GWT scenario describes the interpretation logic that determines whether to trigger the event.

For example, Left Hotel triggered by GPS Coordinates uses a read model sourced from the Location entity (from Sent GPS Coordinates event) with fields Longitude, Latitude, Timestamp, Guest ID representing the incoming data payload.
The command Record Guest Departure has fields Booking Number, Guest ID, Time of Departure representing the domain action.
The GWT scenario specifies: "Given: Guest opted in for GPS tracking. And: We received GPS coordinates from guest's mobile device. When: GPS coordinates indicate guest left hotel (distance greater than threshold). Then: Update booking status to 'Guest Left Hotel'."

Key characteristics include read model as external event payload rather than query result, conditional triggering where event may or may not fire depending on interpretation logic, GWT scenario capturing distance calculation or boundary checks, and entity requirement to model the external data structure.

Implementation generates conditional event handler functions that return `Option<Event>` or `Result<Event, Error>` depending on whether interpretation criteria are met.

#### Automation pattern

Event triggered by background process querying for eligible items and processing each matching result.

Automation means periodic query for items meeting criteria, process matching items, and trigger command per item.

The read model represents query returning list of eligible items with filter fields explicitly marked.
The command represents action performed on each eligible item from the query.
The GWT scenario describes eligibility criteria and processing logic.

For example, Checked Out Guest uses a read model querying the Booking entity with fields Booking ID, Guest ID, Check-in Date, Check-out Date, Status where Check-out Date is marked as filter indicating query parameter.
The query semantic is "find all bookings where check-out date equals today and status equals guest-left."
The command Check Out has field Booking ID, updating booking status to "Checked Out."
The GWT scenario specifies: "Given: Guest's scheduled check-out date has passed. And: Guest has left hotel. When: Automated check-out process runs. Then: Booking status updated to 'Checked Out'. Then: Payment processing enabled."

Key characteristics include read model as query with explicit filter fields (not external data), looping invocation where command runs once per query result, scheduled trigger through cron job or background worker, and state-based eligibility described in GWT scenarios.

Automation with external call variant includes read models querying items needing external processing (payment requests, email notifications), commands invoking external service APIs, optional second commands recording external call results in our system, and GWT scenarios including external call success conditions.

Implementation generates background jobs that query repositories, filter results by eligibility criteria, loop over matches invoking commands, and handle external API calls with proper error recovery.

### Step 6: Apply Conway's Law

Purpose is to assign bounded contexts to aggregate roots, establishing autonomous component boundaries that align with team ownership.

The workflow shifts from actor flow (swimlanes) to system architecture (bounded contexts).
Designers switch to the Domain Model tab, identify aggregate roots (yellow entity boxes), and assign bounded context for each aggregate root by grouping related aggregates into the same context.

For example, a hotel workflow might have Auth bounded context containing Guest Account aggregate root, Inventory bounded context containing Room and Booking aggregate roots, Payment bounded context containing Payment aggregate root, and GPS bounded context containing Guest Location aggregate root.

Conway's Law states that system architecture mirrors communication structure.
Bounded contexts map to team boundaries where each context represents an independently deployable component owned by a dedicated team.
Context boundaries minimize coordination between teams by establishing clear interfaces.

Qlerify shows bounded contexts on the Domain Model tab rather than as swimlanes on the timeline.
This differs from traditional Event Modeling where system boundaries might appear as vertical slices through the flow diagram.
The Qlerify approach separates swimlanes (actor perspective: who performs action) from bounded contexts (technical architecture: which system owns aggregate).

This separation prevents conflating actor flow with system boundaries, a common source of confusion when the same visual element represents both user journeys and deployment units.

The bounded context assignments directly map to EventCatalog services during transformation.
Each context becomes a service directory containing its aggregate roots as entities.

### Step 7: Elaborate Scenarios

Purpose is to write Given-When-Then scenarios, prioritize scenarios into releases, and visualize end-to-end flow per release through filtering.

#### Writing GWT scenarios

GWT scenarios specify behavior through structured format.
Given clauses state preconditions (required state before event), When clauses identify triggers (action or condition causing event), and Then clauses specify postconditions (state changes and events emitted).

GWT scenarios appear in three contexts.
Translation patterns use GWT to describe conditional logic determining when to trigger events.
Automation patterns use GWT to describe eligibility criteria determining when to process items.
Regular patterns use GWT to describe validation rules determining when commands succeed or fail.

For translation, a GWT might specify: "Given: Guest opted in for GPS tracking. And: We received GPS coordinates. When: Coordinates indicate guest left hotel. Then: Booking status updated."
For automation, a GWT might specify: "Given: Guest's check-out date has passed. And: Guest has left hotel. When: Automated process runs. Then: Booking status updated to 'Checked Out'."
For validation, a GWT might specify: "Given: Guest has valid account. And: Room is available. When: Guest submits booking. Then: Room status updated to 'Reserved'."

#### Prioritizing into releases

The User Story Map tab shows GWTs lined up under corresponding events.
Teams assign GWTs to Release 1, Release 2, and subsequent releases by dragging scenarios into horizontal release sections.
Selected GWTs move up into the release row and can be reordered within releases through drag and drop.

#### Filtering by release

Applying a release filter above the workflow diagram highlights only events with GWTs in the selected release.
This provides an end-to-end view showing exactly what functionality delivers in the iteration.

The filtered view supports impact analysis by showing how prioritization affects overall workflow, stakeholder communication by providing visual tool for discussing priorities, iterative delivery by ensuring each release delivers coherent user value, and dependency management by identifying events required for release even if GWT not explicitly assigned.

The integration with User Story Mapping connects Event Modeling to Jeff Patton's technique.
Horizontal rows represent releases (iterations over time), vertical columns represent events in workflow (walking skeleton), and each GWT represents a specific scenario for testing and acceptance criteria.

## Qlerify AI integration

### Card Type Settings

Card Type Settings configuration determines what AI generates during brainstorming.

The Use AI section enables or disables AI generation for command cards (blue), aggregate root cards (yellow), read model cards (green), and given-when-then cards (purple).

The Domain Model Role section maps card types to domain model roles ensuring command card type maps to command role, aggregate root card type maps to aggregate root role, read model card type maps to read model role, and given-when-then card type maps to given-when-then role.

Correct mappings are critical because Qlerify uses roles to populate domain model diagrams correctly.
Incorrect mappings cause artifacts to appear in wrong swim lanes or wrong colors.

### AI-generated field details

Unlike manual EventStorming where sticky notes carry only names, Qlerify AI generates field names, data types (uuid, timestamp, int, boolean, string, enum), primary keys, cardinality (one-to-one, one-to-many, many-to-one, many-to-many), related entities (foreign key references), and example data for enums and validation.

Field-level detail enables direct UI mockup rendering in the sidebar, schema export to EventCatalog with JSON Schema, and code generation with typed signatures.

### Workflow generation

Initial generation starts from natural language prompt.

Best practices for prompts include referencing existing Event Modeling examples (based on Adam Dymitruk's hotel example), enumerating key events explicitly in numbered lists, specifying actors and roles involved, describing workflow end-to-end from initial trigger to final outcome, and including both happy path and exceptional flows.

Expected AI output includes events on timeline with temporal ordering, swimlanes requiring correction per Step 2, commands with field definitions, read models with field definitions, aggregate roots and entities, and optional initial GWT scenarios.

Post-generation refinement is expected.
AI provides starting point rather than final design.
Teams reorganize swimlanes from systems to actors, refine field names and types, add missing events discovered in review, delete over-generated artifacts, and clarify GWT scenarios with domain experts.

### Field generation

Field-level generation for specific entities uses the AI button with "Generate fields with AI" tooltip.
AI suggests field names, types, and relationships based on entity name and context.
Teams review and refine suggestions using the field selector to add or remove fields manually.

Use cases include generating Location entity fields after creating translation read model, generating Booking query fields after creating automation read model, and filling in details when AI's initial generation missed entity complexity.

## Mapping Event Modeling artifacts to algebraic types

Event Modeling artifacts map systematically to formal type-level specifications suitable for implementation, preserving algebraic structure discovered during specification.

### Events as free monoid elements

Events discovered through Event Modeling become constructors in a sum type encoding the event algebra for the domain.
A timeline showing Account Registered, Room Added, Room Booked, Guest Checked In becomes:

```haskell
data HotelEvent
  = AccountRegistered { accountId :: UUID, email :: Email, fullName :: Text }
  | RoomAdded { roomId :: UUID, roomNumber :: Int, roomType :: RoomType }
  | RoomBooked { bookingId :: UUID, guestId :: UUID, roomId :: UUID, checkIn :: Date, checkOut :: Date }
  | GuestCheckedIn { bookingId :: UUID, checkinTime :: DateTime }
  | GuestCheckedOut { bookingId :: UUID, checkoutTime :: DateTime }
  | PaymentSucceeded { paymentId :: UUID, bookingId :: UUID, amount :: Money, transactionId :: Text }
```

Each constructor represents one event on the timeline with associated data capturing field-level details specified during Event Modeling.
The chronological sequence of events maps to temporal ordering in event streams, which form a free monoid under concatenation (append-only, associative, identity element is empty stream).

Events map directly to the `Event` type parameter in the Decider pattern from domain-modeling.md.

### Commands as validated functions

Commands discovered through Event Modeling become functions that validate business rules and produce events or validation errors.
A command Register Account with field-level schema becomes:

```haskell
data RegisterAccountCommand = RegisterAccountCommand
  { email :: Email
  , password :: Password
  , fullName :: Text
  , phoneNumber :: PhoneNumber
  , address :: Address
  }

registerAccount :: RegisterAccountCommand -> Validation (NonEmpty AccountError) AccountRegistered
registerAccount cmd =
  validateEmail cmd.email *>
  validatePasswordStrength cmd.password *>
  pure (AccountRegistered (newAccountId ()) cmd.email cmd.fullName)
```

The function signature documents that commands take validated input (enforcing smart constructors), return validation results (errors are explicit), and produce events on success.
Business rules from GWT scenarios become predicates in validation logic or refinement types constraining input types.

Commands map to inputs to the `decide` function in the Decider pattern: `decide: Command → State → List<Event>`.

### Read models as projections

Read models become query interfaces derived from event streams or reference data sources.
A read model for available rooms becomes:

```haskell
data AvailableRoomsQuery = AvailableRoomsQuery
  { checkInDate :: Date
  , checkOutDate :: Date
  , roomType :: Maybe RoomType
  }

data RoomAvailability = RoomAvailability
  { roomId :: UUID
  , roomNumber :: Int
  , roomType :: RoomType
  , pricePerNight :: Money
  , amenities :: [Amenity]
  }

type AvailableRoomsProjection = AvailableRoomsQuery -> EventStore -> [RoomAvailability]
```

The read model is a pure function from event history and query parameters to current view, ensuring decision-making uses consistent projections.

### Aggregate roots as Decider modules

Aggregate roots identified during Event Modeling become modules with private state and public APIs enforcing consistency boundaries.
An aggregate root Booking becomes:

```rust
pub mod booking {
    struct BookingState { /* private */ }

    // decide: Command → State → Result<Vec<Event>, Error>
    pub fn book_room(cmd: BookRoomCommand, state: Option<BookingState>)
        -> Result<Vec<BookingEvent>, BookingError>
    {
        // Validation from GWT scenarios
        if !is_room_available(&cmd.room_id, &cmd.check_in, &cmd.check_out) {
            return Err(BookingError::RoomNotAvailable);
        }

        Ok(vec![
            BookingEvent::RoomBooked {
                booking_id: generate_booking_id(),
                room_id: cmd.room_id,
                guest_id: cmd.guest_id,
                check_in: cmd.check_in,
                check_out: cmd.check_out,
            }
        ])
    }

    // evolve: State → Event → State
    fn apply_event(state: BookingState, event: BookingEvent) -> BookingState {
        match event {
            BookingEvent::RoomBooked { .. } => { /* state transition */ },
            BookingEvent::GuestCheckedIn { .. } => { /* state transition */ },
            BookingEvent::GuestCheckedOut { .. } => { /* state transition */ },
        }
    }
}
```

The aggregate's responsibility for enforcing invariants becomes predicates in command validation functions or constraints in state types.
Aggregates map directly to the `State` type and `evolve` function in the Decider pattern where `evolve: State → Event → State` represents state transition logic.

### Translation functions as conditional handlers

Translation pattern events generate conditional event handlers that return optional events.
A translation from GPS coordinates to Guest Left Hotel becomes:

```rust
pub fn handle_gps_coordinates(location: Location, bookings: &[Booking])
    -> Option<GuestLeftHotel>
{
    // GWT logic: "when GPS coordinates indicate guest left hotel"
    if location.distance_from_hotel() > HOTEL_BOUNDARY_METERS {
        if let Some(booking) = find_active_booking(location.guest_id, bookings) {
            return Some(GuestLeftHotel {
                booking_id: booking.id,
                guest_id: location.guest_id,
                departure_time: location.timestamp,
            });
        }
    }
    None
}
```

The conditional logic from GWT scenarios maps directly to pattern matching and guard clauses in the implementation.

### Automation processes as background jobs

Automation pattern events generate background jobs querying for eligible items and processing each match.
An automation for checking out guests becomes:

```rust
pub async fn checkout_automation(booking_repo: &BookingRepository) {
    // GWT logic: "when scheduled check-out date has passed and guest left hotel"
    let eligible_bookings = booking_repo
        .find_by_checkout_date(today())
        .await
        .into_iter()
        .filter(|b| b.guest_left);

    for booking in eligible_bookings {
        match checkout_command(booking.id).await {
            Ok(_) => log::info!("Checked out booking {}", booking.id),
            Err(e) => log::error!("Failed to checkout booking {}: {}", booking.id, e),
        }
    }
}
```

The query logic and eligibility criteria from GWT scenarios become repository filters and conditional processing.

### GWT scenarios as property tests

Given-When-Then scenarios translate to property-based tests verifying implementations maintain discovered invariants.

Example-based tests come directly from concrete scenarios:

```python
def test_guest_left_hotel_on_gps_coordinates():
    # Given: Guest opted in for GPS tracking
    guest = Guest(id=guest_id, gps_tracking_enabled=True)
    booking = Booking(guest_id=guest_id, status=BookingStatus.CHECKED_IN)

    # When: GPS coordinates indicate guest left hotel
    location = Location(
        guest_id=guest_id,
        latitude=distant_latitude,
        longitude=distant_longitude,
        timestamp=now()
    )

    # Then: Booking status updated to "Guest Left"
    event = handle_gps_coordinates(location, [booking])
    assert event is not None
    assert event.booking_id == booking.id
```

Property-based tests generalize from examples:

```python
@given(
    st.floats(min_value=HOTEL_BOUNDARY_METERS + 1),
    st.datetimes()
)
def test_gps_coordinates_beyond_boundary_trigger_departure(distance, timestamp):
    location = Location(
        guest_id=test_guest_id,
        latitude=compute_lat_at_distance(distance),
        longitude=compute_lon_at_distance(distance),
        timestamp=timestamp
    )
    booking = Booking(guest_id=test_guest_id, status=BookingStatus.CHECKED_IN)

    event = handle_gps_coordinates(location, [booking])

    # Property: coordinates beyond boundary always trigger departure event
    assert event is not None
```

The collection of GWT scenarios suggests properties that should hold universally, guiding property test generation.

## Translation and automation pattern details

Translation and automation patterns represent common but underspecified patterns in traditional Event Modeling, receiving explicit treatment in Qlerify.

### Translation pattern mechanics

Translation handles the boundary between external events and domain events through interpretation logic.

External events originate outside system control from GPS devices, third-party APIs, or external services.
We receive raw data payloads without controlling format or timing.
Translation events occur when we interpret external data and decide whether to emit domain events.

The read model in translation represents the incoming external event payload structure.
This is not a query against our database but the schema of data we receive.
The command represents the domain action we take if interpretation succeeds according to business rules.

The GWT scenario captures the interpretation logic that might fail or succeed.
Given clauses establish preconditions like opt-in flags or system state.
When clauses describe the interpretation rule like distance calculations or threshold checks.
Then clauses specify what domain event fires when interpretation succeeds.

Implementation requires an entity modeling the external data structure so read models can reference it.
For GPS coordinates, a Location entity captures latitude, longitude, timestamp, and guest ID.
The read model selects this entity and populates fields representing the payload schema.

### Automation pattern mechanics

Automation handles periodic or triggered background processing of eligible items.

Automation events fire when background processes query for items meeting criteria and process each match.
The trigger might be a scheduled cron job, a queue processor, or a periodic batch operation.

The read model in automation represents the query selecting eligible items with explicit filter fields.
Filter fields are marked to indicate they are query parameters rather than result fields.
The query semantic is always "find all items where conditions are met."

The command represents the action performed on each eligible item returned by the query.
The command typically operates on a single item identifier extracted from query results, processing items one at a time in a loop.

The GWT scenario describes eligibility criteria in Given clauses, trigger conditions in When clauses, and resulting state changes in Then clauses.
Multiple Then clauses capture cascading effects like enabling subsequent processing.

Implementation generates background jobs that execute queries against repositories, filter results by eligibility criteria using predicates from GWT scenarios, loop over matches invoking commands with error handling, and track processing state to avoid duplicate processing.

Automation with external calls adds complexity where the automation invokes external services.
The read model still queries eligible items, but the command includes or triggers external API calls.
GWT scenarios include external call success conditions as When clauses, documenting that domain events fire only after external processing succeeds.

### Distinguishing translation from automation

Translation processes individual external events as they arrive, interpreting each payload to determine whether to emit domain events.
Automation processes batches of eligible items on schedule or trigger, querying for matches and processing each.

Translation read models represent external payloads, while automation read models represent internal queries.
Translation logic is conditional (event may or may not fire), while automation logic is iterative (loop over eligible items).
Translation handles integration boundaries, while automation handles scheduled processing.

Both patterns require GWT scenarios to capture business logic that simple command-event relationships miss, ensuring that conditional triggering and eligibility criteria are explicit in specifications.

## D2 diagram artifacts

D2 diagrams should be generated alongside or as part of Event Modeling sessions, providing text-based, version-controllable representations of visual models.
D2 output complements Qlerify JSON exports during EventCatalog transformation, allowing diagram-as-code workflows that integrate with documentation pipelines and git-based change tracking.

### Color conventions for Event Modeling elements

D2 diagrams follow Event Modeling color conventions to maintain visual consistency with Qlerify UI and traditional sticky note colors:

```d2
# Event Modeling color conventions in D2
Commands: {
  style.fill: "#3498db"  # blue
}
Events: {
  style.fill: "#e67e22"  # orange
}
Read Models: {
  style.fill: "#2ecc71"  # green
}
Aggregates: {
  style.fill: "#f1c40f"  # yellow
}
External Systems: {
  style.fill: "#9b59b6"  # purple
}
Hotspots: {
  style.fill: "#e74c3c"  # red
}
```

These colors map directly to Qlerify card types and traditional Event Modeling sticky notes, ensuring diagrams generated from JSON exports or created directly by LLMs maintain visual alignment with collaborative session artifacts.

### Swimlane pattern for actor lanes

D2 containers represent actor swimlanes following the actor-exclusive convention from Step 2:

```d2
direction: right

guest: "Guest" {
  style.fill: "#f5f5f5"

  view_rooms: "View Available Rooms" {
    style.fill: "#2ecc71"  # read model
  }

  book_room: "Book Room" {
    style.fill: "#3498db"  # command
  }

  room_booked: "Room Booked" {
    style.fill: "#e67e22"  # event
  }

  view_rooms -> book_room: "user input"
  book_room -> room_booked: "triggers"
}

manager: "Manager" {
  style.fill: "#f5f5f5"

  view_catalog: "View Room Catalog" {
    style.fill: "#2ecc71"
  }

  add_room: "Add Room" {
    style.fill: "#3498db"
  }

  room_added: "Room Added" {
    style.fill: "#e67e22"
  }

  view_catalog -> add_room
  add_room -> room_added
}

automation: "Automation" {
  style.fill: "#f0f0f0"

  query_overdue: "Query Overdue Bookings" {
    style.fill: "#2ecc71"
  }

  check_out: "Check Out" {
    style.fill: "#3498db"
  }

  checked_out: "Guest Checked Out" {
    style.fill: "#e67e22"
  }

  query_overdue -> check_out: "per result"
  check_out -> checked_out
}
```

Containers group artifacts by actor rather than by system or bounded context, deferring system boundaries to bounded context diagrams.
The `direction: right` layout matches temporal left-to-right flow convention in Event Modeling timelines.

### Per-step diagram output

Each Event Modeling step produces specific D2 artifacts or refinements:

Step 1 (Brainstorming) generates initial event timeline in D2 with temporal ordering arrows.
AI-generated events appear as orange boxes arranged left-to-right with optional temporal connections showing narrative flow.
Commands, read models, and aggregate roots may be generated simultaneously depending on AI capabilities.

Step 2 (The Plot) organizes events into actor swimlanes using D2 containers.
System-based lanes are reorganized into actor-based containers (Guest, Manager, Automation) with events moved to appropriate containers and temporal arrows adjusted to reflect actor perspective.

Step 3 (The Storyboard) adds or refines command field schemas in D2 node labels or separate field tables.
Commands gain field lists representing form structure, allowing UX mockup generation from D2 source.

Step 4 (Identify Inputs) validates command names in D2 node labels.
Command nodes are renamed to match domain language using imperative mood.

Step 5 (Identify Outputs) adds read model nodes and field schemas to D2 diagrams.
Read models appear as green boxes connected to commands via "informs decision" or similar labeled edges.

Step 6 (Apply Conway's Law) produces separate bounded context diagrams showing aggregate groupings.
A second D2 diagram shows aggregate roots (yellow boxes) grouped into bounded context containers with context boundaries clearly marked.

Step 7 (Elaborate Scenarios) adds GWT annotations to event nodes or produces separate scenario diagrams.
GWT scenarios appear as purple boxes connected to events or as structured text annotations on event nodes.

### Integration with Qlerify and EventCatalog workflow

D2 diagrams integrate with Qlerify and EventCatalog transformation workflows:

D2 diagrams can be generated from Qlerify JSON exports through transformation scripts that map Qlerify card types to D2 color conventions, swimlanes to D2 containers, and timeline arrows to D2 edges.

LLMs can create D2 diagrams directly during facilitation sessions when Qlerify is unavailable or when diagram-as-code workflow is preferred, generating actor swimlanes and artifact nodes from natural language descriptions.

D2 diagrams serve as input for EventCatalog MDX generation alongside Qlerify JSON, allowing visual documentation to be generated from version-controlled diagram source rather than requiring screenshot exports.

D2 source enables diff-based review of Event Model changes through git commits, making architectural evolution visible through text diffs rather than requiring visual comparison tools.

## Process workflow for Claude Code guidance

### Pre-session setup

Verify environment by confirming user is logged into Qlerify app, opening blank workflow, validating Card Type Settings have Use AI enabled for Command, Aggregate Root, Read Model, and Given-When-Then, validating Domain Model Role mappings are correct, and optionally selecting preferred LLM model in AI tab.

Gather context by asking user to describe business scenario or workflow, identifying key actors and roles involved, confirming scope (single bounded context versus multi-context flow), and referencing existing documentation or examples if available.

When diagram-as-code workflow is preferred, prepare D2 diagram generation by confirming actor swimlanes are understood, establishing color conventions for Event Modeling elements, and optionally initializing git repository for version-controlled diagram evolution.

### Guided Step 1: Brainstorming

Provide prompt template asking user to describe workflow including primary actors and roles, key state-changing events in chronological order, any external systems involved, and success and failure scenarios.

Execute by having user paste prompt into "Generate workflow with AI," clicking "Generate workflow" with default options, waiting for AI generation to complete, and reviewing initial output with user.

Review with checklist confirming all major events are represented, events are in logical chronological order, swimlanes make sense even if needing reorganization, and missing events discovered during review are noted.

### Guided Step 2: The Plot

Ask key question "Do swimlanes represent actors (people/roles) or systems/bounded contexts?"

Identify actors by listing human actors (Guest, Manager, Employee, Administrator), identifying automated processes to group into Automation actor, and verifying external entities truly initiate actions (rare, usually external events instead).

Reorganize swimlanes by creating actor swimlanes if needed for each system/BC lane, moving events to actor-based swimlanes, and deleting system-based swimlanes.

Validate timeline flow by asking "Reading left to right, does this tell the story of how work flows through your system?"

### Guided Steps 3-5: Iterate through events

For each event, complete storyboard (Step 3) by asking "What does the input form look like when [actor] performs [event action]?" and refining command fields for natural form flow.

Complete input identification (Step 4) by validating command name matches domain language and follows imperative form.

Complete output identification (Step 5) by asking "What information does [actor] need to see/know before deciding to [perform command]?" and clarifying read model perspective shift.

### Pattern-specific guidance

For external events, guide deletion of command and read model while keeping event and entity to document external integration boundary.

For translation events, guide creation of read model selecting external entity, command representing domain action, and GWT describing conditional interpretation logic.

For automation events, guide creation of read model as query with filter fields, command operating on each eligible item, and GWT describing eligibility criteria.

### Guided Step 6: Apply Conway's Law

Shift focus from actor flow (swimlanes) to system architecture (bounded contexts).

Review aggregate roots on Domain Model tab and ask "Which aggregates would naturally be owned/managed by the same team?"

Assign bounded context for each aggregate root, grouping related aggregates (Room and Booking into Inventory, Guest Account into Auth, Payment into Payment).

Validate that each bounded context represents an autonomous component a single team could own.

### Guided Step 7: Elaborate Scenarios

Write GWT scenarios for events based on type: validation rules for regular events, conditional logic for translation events, eligibility criteria for automation events.

Prioritize scenarios into releases by asking "What's the minimal set of scenarios needed for first usable release?" and assigning critical GWTs to Release 1.

Filter by release to validate end-to-end coherence, checking for orphaned events without paths from start.

### Session wrap-up

Export artifacts including workflow as JSON for EventCatalog transformation, workflow as PDF or image for documentation, and User Story Map view per release for sprint planning.

Coach next steps including validating with domain experts especially GWT scenarios and translation logic, completing Domain Model if code generation desired, transforming to EventCatalog for team documentation, generating code skeleton via Qlerify AI code gen if applicable, and implementing business logic using GWT scenarios as test cases.

## See also

*collaborative-modeling.md* provides facilitation techniques for EventStorming and Domain Storytelling that precede Event Modeling in the discovery workflow, surfacing domain events and bounded contexts before systematic specification.

*event-catalog-qlerify.md* documents the transformation workflow from Qlerify JSON exports to EventCatalog MDX artifacts with JSON Schema, consuming the specifications produced by Event Modeling sessions.

*event-catalog-tooling.md* describes EventCatalog concepts and algebraic documentation patterns including Decider pattern implementation and free monoid event streams that Event Modeling artifacts map to.

*discovery-process.md* positions Event Modeling within the DDD 8-step workflow, showing how Event Modeling appears in steps 2-7 after initial EventStorming establishes domain landscape.

*domain-modeling.md* implements the Decider pattern and smart constructors that realize Event Modeling specifications as executable code with type-safe aggregates.

*railway-oriented-programming.md* composes validation rules from GWT scenarios into Result types and error handling pipelines, translating behavioral specifications into type-safe implementations.

*schema-versioning.md* provides evolution strategies when extending JSON Schemas generated from Event Modeling beyond initial field-level specifications.

Adam Dymitruk's Event Modeling methodology: https://eventmodeling.org/posts/what-is-event-modeling/

Qlerify Event Modeling Tool: https://www.qlerify.com/event-modeling-tool
