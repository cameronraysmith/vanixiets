# Qlerify Event Modeling methodology analysis

## Purpose

This document analyzes the Qlerify Event Modeling Tool implementation of Adam Dymitruk's 7-step Event Modeling methodology, extracting workflow patterns and UI conventions that enable Claude Code to guide users through Event Modeling sessions.

Source: www.qlerify.com/event-modeling-tool (downloaded 2026-01-05)

## Executive summary

Qlerify implements Event Modeling as a 7-step process with AI-assisted generation and specific UI patterns that differ from traditional EventStorming.
The tool emphasizes actor-based swimlanes, explicit translation/automation patterns, and direct integration with DDD concepts like Bounded Contexts and Aggregate Roots.
Key distinguishing features include Read Model placement before Commands (actor-centric perspective), automated external event handling, and User Story Map integration for release planning.

## The 7-step Event Modeling process in Qlerify

### Step 1: Brainstorming

**Purpose:** Generate initial set of domain events through AI prompts or manual entry.

**Qlerify workflow:**
1. User provides natural language description of workflow or business scenario
2. Click "Generate workflow with AI" in empty workflow canvas
3. AI generates events, swimlanes, commands, read models, aggregate roots based on description
4. Output: Initial event timeline with suggested swimlanes and domain model artifacts

**Key patterns:**
- AI uses Card Type Settings to determine what artifacts to generate:
  - Command card → generates blue Command boxes
  - Aggregate Root card → generates yellow Entity boxes
  - Read Model card → generates green Read Model boxes
  - Given-When-Then card → generates purple GWT scenario boxes
- Domain Model Role dropdown mappings ensure correct semantic tagging
- Generated artifacts include field-level details, not just entity names
- Timeline arrows represent "plausible temporal ordering", not strict causality

**Differences from manual EventStorming:**
- Starts with structured prompt rather than chaotic sticky note phase
- Immediately generates commands and read models alongside events
- Produces field-level schemas during initial generation

### Step 2: The Plot

**Purpose:** Organize events into coherent timeline using swimlanes for actors (not systems).

**Qlerify workflow:**
1. Review generated swimlanes and events
2. Identify swimlanes representing systems/bounded contexts vs actors
3. Create actor swimlanes (Guest, Manager, Automation) as needed
4. Move events to appropriate actor lanes
5. Delete system/bounded context lanes (those belong in Step 6)
6. Validate temporal ordering makes narrative sense

**Key Qlerify convention: Swimlanes = Actors, NOT Systems**

Traditional Event Modeling uses swimlanes for both actors and systems.
Qlerify explicitly reserves swimlanes for actors (roles that perform actions), deferring system boundaries to Bounded Context assignment in Step 6.

Actor types:
- **Human actors:** Guest, Manager, Employee, Administrator
- **Automation actor:** Represents automated processes (timers, triggers, background jobs)
- **External system actors:** Only when external entity initiates action (rare; usually modeled as external events)

**Critical distinction:**
- ✓ Correct: Guest, Manager, Automation swimlanes
- ✗ Incorrect: GPS Device, Payment System, Inventory Service swimlanes

**Timeline arrows semantics:**
- Arrows show "example of how events typically unfold"
- Do NOT mean event A automatically triggers event B
- Do NOT enforce strict sequence (events may occur in different orders)
- Provide narrative flow for understanding, not execution order

### Step 3: The Storyboard

**Purpose:** Create UI mockups via Command data fields to make events tangible.

**Qlerify workflow:**
1. Select an event on timeline
2. Open sidebar → Data Fields tab
3. Switch to Domain Model tab under diagram
4. Inspect Command (blue box) – fields define input form
5. Add/update/remove/reorder fields on Command to design UI mockup
6. Sidebar renders form based on Command schema

**Question to guide design:**
"What does the input form look like when [actor] performs [event action]?"

**Example: Guest Registered Account**
- Command: Register Account
- Fields: Email, Password, Full Name, Phone Number, Address
- Reorder fields to match natural form flow (e.g., Name before Phone)
- Form in sidebar updates to reflect Command structure

**For automated events:**
Imagine a "robot filling out the form and pressing submit button" to identify what data the automation needs.

**Relationship to Event Modeling theory:**
This step bridges abstract events to concrete UX.
The Storyboard answers "how would a user cause this event?" through form design, grounding the model in implementable UI patterns.

### Step 4: Identify Inputs

**Purpose:** Name the command that triggers the event when form is submitted.

**Qlerify workflow:**
1. Review AI-suggested Command name (usually imperative verb phrase)
2. Validate name matches domain language and actor intent
3. Rename if needed to match ubiquitous language
4. Command name appears in blue box on Domain Model diagram

**Naming conventions:**
- Imperative mood: "Register Account", "Book Room", "Add Room"
- Action from actor perspective: "Request Payment" (not "Process Payment Request")
- Domain terminology: Use exact terms from domain experts

**Example:**
- Event: "Account Registered"
- Command: "Register Account"
- Pattern: [Verb] + [Noun] (imperative form of past tense event)

**Minimal step complexity:**
This step is often trivial if AI generated appropriate names.
The value is in validating domain language alignment, not mechanical naming.

### Step 5: Identify Outputs

**Purpose:** Define Read Models (data needed before commands execute).

**Critical Qlerify interpretation:**
Despite name "Identify Outputs", Qlerify treats Read Models as **inputs to decision-making**, not outputs of events.
Read Model = data consumed **before** Command is triggered.
This actor-centric perspective differs from traditional Event Modeling.

**Qlerify workflow:**
1. Select event
2. Open Domain Model tab
3. Review Read Model (green box)
4. Add/update/remove fields defining what information actor needs
5. Ask: "What information does [actor] need to [perform command]?"

**Example: Guest Registered Account**
- Read Model might include: Terms & Conditions, Privacy Policy, Benefits
- Actor needs to review this information before deciding to register
- Read Model represents query results or static content displayed pre-command

**Traditional vs Qlerify perspective:**

Traditional Event Modeling: Read Model = output/view derived from events
Qlerify Event Modeling: Read Model = input/context needed for command

The Qlerify approach centers discussion around single actor's decision-making flow:
1. Actor views Read Model (information gathering)
2. Actor fills out Command form (decision implementation)
3. Event occurs (state change recorded)

**Multiple Read Models:**
Events can have multiple associated Read Models (different information sources).
Events must have exactly one Command.

### Apply Steps 3, 4, 5 to all events

After completing Steps 3-5 for first event, iterate through all events on timeline.
Each event gets Storyboard (Step 3), Input identification (Step 4), Output identification (Step 5).

**Key patterns covered in iteration:**

#### Regular input form pattern
Human actor fills form manually.
Example: Manager Added Room, Guest Booked Room
- Command: Input fields for manual entry
- Read Model: Query results or reference data informing decision

#### External event pattern
Event triggered outside our system boundary (external system, device, third party).

**Qlerify convention for external events:**
1. Delete the Command (no form in our system)
2. Delete the Read Model (no query in our system)
3. Keep the Event (fact happened externally)
4. Keep the Entity/Aggregate Root (receives external data)

**Example: Sent GPS Coordinates**
- External GPS device sends coordinates (black box from our perspective)
- We document Event for reference but don't model internal Command/Read Model
- Detailed modeling happens in **next** event where we receive and process external data

**Rationale:**
External events represent integration boundaries.
We document the fact that external event occurred but don't pretend to model external system's internals.

#### Translation pattern
Event triggered by processing external event data.

**Definition:**
Translation = receive external event → interpret data → conditionally trigger domain event

**Qlerify workflow for Translation:**
1. Read Model represents incoming external event data (not a query)
2. Command represents our domain action if interpretation succeeds
3. GWT scenario describes interpretation logic

**Example: Left Hotel (triggered by GPS Coordinates)**

Read Model:
- Source: Location entity (from Sent GPS Coordinates event)
- Fields: Longitude, Latitude, Timestamp, Guest ID
- Represents incoming data from external event

Command:
- Name: Record Guest Departure
- Fields: Booking Number, Guest ID, Time of Departure
- Represents our domain action

GWT scenario for interpretation logic:
```
Given: Guest opted in for GPS tracking
And: We received GPS coordinates from guest's mobile device
When: GPS coordinates indicate guest left hotel (distance > threshold)
Then: Update booking status to "Guest Left Hotel"
```

**Key characteristics:**
- Read Model is NOT a query – it's the payload from external event
- Logic exists to conditionally trigger event (distance calculation, boundary checks)
- GWT scenario captures conditional logic that EventStorming might miss

**Implementation note:**
Translation requires entity to model external data structure.
In example, "Location" entity captures GPS coordinate schema.
Delete generated Read Model, create new Read Model selecting Location entity, use AI or field selector to populate fields.

#### Automation pattern
Event triggered by background process querying for eligible items.

**Definition:**
Automation = periodic query for items meeting criteria → process matching items → trigger command per item

**Qlerify workflow for Automation:**
1. Read Model represents query returning list of eligible items
2. Mark query filter fields explicitly
3. Command represents action performed on each eligible item
4. GWT scenario describes eligibility criteria and processing logic

**Example: Checked Out Guest**

Read Model:
- Entity: Booking
- Fields: Booking ID, Guest ID, Check-in Date, Check-out Date, Status
- Filter: Check-out Date (mark as filter to indicate query parameter)
- Query: "Retrieve all bookings eligible for checkout"

Command:
- Name: Check Out
- Fields: Booking ID
- Updates booking status to "Checked Out"

GWT scenario:
```
Given: Guest's scheduled check-out date has passed
And: Guest has left hotel (previous event occurred)
When: Automated check-out process runs
Then: Booking status updated to "Checked Out"
Then: Payment processing enabled
```

**Key characteristics:**
- Read Model is query with explicit filter fields (not external data)
- Automation loops over query results, invoking command per item
- Multiple invocations possible (one per matching booking)
- GWT describes when automation runs and eligibility criteria

**Automation with external call variant:**

Some automations involve outgoing external calls.

**Example: Payment Succeeded**

Read Model:
- Query: Payment requests awaiting processing
- Fields: Booking Reference, Total Amount Due, Payment Method

Command (external):
- Invoke external payment service API
- Wait for success response

Command (internal):
- Name: Record Payment Success
- Fields: Booking Number, Guest ID, Amount, Transaction Time, Transaction ID
- Updates booking after external payment succeeds

GWT scenario:
```
Given: Payment requested for booking
When: Amount successfully captured from guest's payment card (external call)
Then: Invoice updated to "Paid" status
```

**Modeling choice:**
Can model as single step (shown above) or two explicit steps:
1. Step 1: Command invoked on external service
2. Step 2: Command storing result in our system

Qlerify example uses single step with GWT clarifying external dependency.

### Step 6: Apply Conway's Law

**Purpose:** Assign Bounded Contexts to Aggregate Roots, establishing autonomous component boundaries.

**Qlerify workflow:**
1. Switch to Domain Model tab (under diagram)
2. Identify Aggregate Roots (yellow Entity boxes)
3. For each Aggregate Root, assign Bounded Context
4. Group related Aggregate Roots into same Bounded Context

**Example from hotel workflow:**
- Bounded Context: **Auth**
  - Aggregate Roots: Guest Account
- Bounded Context: **Inventory**
  - Aggregate Roots: Room, Booking
- Bounded Context: **Payment**
  - Aggregate Roots: Payment
- Bounded Context: **GPS**
  - Aggregate Roots: Guest Location

**Relationship to Conway's Law:**
Bounded Contexts map to team boundaries.
Each context represents independently deployable component owned by dedicated team.
Context boundaries minimize coordination between teams.

**Qlerify visual representation:**
Qlerify shows Bounded Contexts on Domain Model tab, not as swimlanes on timeline.
This differs from traditional Event Modeling where system boundaries appear as vertical slices.

**Rationale for Qlerify approach:**
- Swimlanes = actor perspective (who performs action)
- Bounded Contexts = technical architecture (which system owns aggregate)
- Separating these concerns prevents conflating actor flow with system boundaries

**Impact on EventCatalog transformation:**
Bounded Contexts directly map to EventCatalog services.
Each context becomes service directory containing its Aggregate Roots as entities.

### Step 7: Elaborate Scenarios

**Purpose:** Write Given-When-Then scenarios, prioritize into releases, visualize end-to-end flow per release.

**Qlerify workflow:**

#### Write GWT scenarios

1. Select event on timeline
2. Add GWT scenario describing behavior specification
3. GWT structure:
   - **Given:** Preconditions (state requirements)
   - **When:** Trigger (action or condition)
   - **Then:** Postconditions (state changes, events emitted)

**Where GWTs appear:**
- Translation patterns: Describe conditional logic (when to trigger event)
- Automation patterns: Describe eligibility criteria (when to process item)
- Regular patterns: Describe validation rules (when command succeeds/fails)

#### Prioritize scenarios into releases

1. Navigate to User Story Map tab (under workflow diagram)
2. View GWTs lined up under corresponding events
3. Assign GWTs to Release 1, Release 2, etc.
4. Selected GWTs move up into separate horizontal release section
5. Drag & drop to reorder within releases

#### Filter by release for end-to-end view

1. Apply release filter above workflow diagram (e.g., "Release 1")
2. Diagram highlights only events with GWTs in selected release
3. Provides end-to-end flow showing exactly what's planned for iteration

**Value of release filtering:**
- Impact analysis: See how prioritization affects overall workflow
- Stakeholder communication: Visual tool for discussing priorities
- Iterative delivery: Ensure each release delivers coherent user value
- Dependency management: Identify events required for release even if GWT not assigned

**Relationship to User Story Mapping:**
User Story Map tab integrates Event Modeling with Jeff Patton's User Story Mapping technique.
Horizontal rows = releases (iterations over time)
Vertical columns = events in workflow (walking skeleton)
Each GWT = specific scenario for testing/acceptance criteria

### Qlerify-specific AI integration patterns

#### Card Type Settings
Configuration panel determining what AI generates:

**Use AI section:**
Enable/disable AI generation for:
- Command cards (blue)
- Aggregate Root cards (yellow)
- Read Model cards (green)
- Given-When-Then cards (purple)

**Domain Model Role section:**
Map card types to domain model roles:
- Command card type → Command role
- Aggregate Root card type → Aggregate Root role
- Read Model card type → Read Model role
- Given-When-Then card type → Given-When-Then role

**Why this matters:**
Qlerify uses roles to populate domain model diagram correctly.
If mappings incorrect, artifacts appear in wrong swim lanes or wrong colors.

#### AI-generated field details

Unlike manual EventStorming (sticky notes with names only), Qlerify AI generates:
- Field names
- Data types (uuid, timestamp, int, boolean, string, enum)
- Primary keys
- Cardinality (one-to-one, one-to-many, many-to-one, many-to-many)
- Related entities (foreign key references)
- Example data (for enums and validation)

This field-level detail enables:
- Direct UI mockup rendering in sidebar
- Schema export to EventCatalog with JSON Schema
- Code generation (discussed in separate Qlerify articles)

#### Generate workflow with AI

Initial generation from natural language prompt.

**Best practices for prompts:**
- Reference existing Event Modeling examples ("based on Adam Dymitruk's hotel example")
- Enumerate key events explicitly (numbered list)
- Specify actors/roles involved
- Describe workflow end-to-end (from initial trigger to final outcome)
- Include both happy path and exceptional flows

**Expected AI output:**
- Events on timeline with temporal ordering
- Swimlanes (may need correction per Step 2)
- Commands with field definitions
- Read Models with field definitions
- Aggregate Roots / Entities
- Initial GWT scenarios (optional)

**Post-generation refinement:**
AI provides starting point, not final design.
Expect to:
- Reorganize swimlanes (systems → actors)
- Refine field names and types
- Add missing events discovered in review
- Delete over-generated artifacts
- Clarify GWT scenarios with domain experts

#### Generate fields with AI

Field-level generation for specific entities.

**Workflow:**
1. Select Command, Read Model, or Entity
2. Click AI button ("Generate fields with AI" tooltip)
3. AI suggests field names, types, relationships based on entity name and context
4. Review and refine suggestions
5. Use field selector to add/remove fields manually

**When to use:**
- After creating Translation Read Model (generate Location entity fields)
- After creating Automation Read Model (generate Booking query fields)
- When AI's initial generation missed entity details

## How Qlerify Event Modeling differs from Adam Dymitruk's original methodology

### Core alignment

Qlerify faithfully implements the 7-step Event Modeling structure from eventmodeling.org/posts/what-is-event-modeling/.
The step names and purposes match original methodology.

### Key differences

#### 1. Swimlane semantics (Step 2)

**Original Event Modeling:**
Swimlanes can represent actors, systems, bounded contexts, or teams.
No strict convention; use what clarifies the model.

**Qlerify Event Modeling:**
Swimlanes represent **actors only** (Guest, Manager, Automation).
Systems and bounded contexts assigned in Step 6 via Domain Model tab.

**Impact:**
Forces separation of "who performs action" (actor) from "which system owns aggregate" (bounded context).
Prevents conflating organizational structure (teams) with runtime architecture (systems).

#### 2. Read Model perspective (Step 5)

**Original Event Modeling:**
Read Models are outputs – views derived from events for querying.
Focus on "what data does this event make available?"

**Qlerify Event Modeling:**
Read Models are inputs – data needed before commands execute.
Focus on "what information does actor need to decide on command?"

**Impact:**
Actor-centric interpretation emphasizes decision-making flow.
Aligns with "identify outputs" language while inverting temporal perspective.
May confuse those familiar with CQRS "read model = projection" semantics.

#### 3. External event handling

**Original Event Modeling:**
External events often modeled implicitly or via integration swimlanes.

**Qlerify Event Modeling:**
Explicit pattern: delete Command and Read Model, keep Event and Entity.
Forces distinction between external events (black box) and translation events (our processing).

**Impact:**
Makes integration boundaries explicit in model structure.
Clarifies what we own vs what external systems own.

#### 4. Translation and Automation patterns

**Original Event Modeling:**
Translation and Automation mentioned as patterns but not deeply elaborated in 2019 blog post.

**Qlerify Event Modeling:**
Dedicated patterns with specific UI workflows:
- Translation: Read Model = external event data, conditional triggering
- Automation: Read Model = query with filters, looping invocation

**Impact:**
Provides concrete guidance for common but underspecified patterns.
Enables teams to model background processes consistently.

#### 5. GWT integration (Step 7)

**Original Event Modeling:**
GWT scenarios mentioned as elaboration technique.

**Qlerify Event Modeling:**
User Story Map tab integrates GWTs with release planning.
Release filtering provides end-to-end workflow visualization.

**Impact:**
Connects Event Modeling to agile delivery practices (iterations, walking skeleton).
Enables impact analysis for prioritization decisions.

#### 6. AI-assisted generation

**Original Event Modeling:**
Manual collaborative workshop with sticky notes.

**Qlerify Event Modeling:**
AI generates initial model from natural language prompt.
Human refinement replaces chaotic exploration phase.

**Impact:**
Dramatically faster initial modeling (minutes vs hours).
Trade-off: May miss tacit knowledge surfaced in collaborative discovery.
Best used with subsequent domain expert validation workshops.

## Relationship between Event Modeling artifacts and code generation

Qlerify's Event Modeling produces artifacts suitable for code generation (covered in separate "AI Generated Code" article per footer links).

### Artifacts used for code generation

**Domain Model elements:**
- Events (orange): Generate event type definitions (ADTs, classes)
- Commands (blue): Generate command handler signatures and validation functions
- Aggregate Roots (yellow): Generate aggregate modules with Decider pattern (decide/evolve)
- Read Models (green): Generate query interfaces and projection implementations
- Bounded Contexts: Generate module boundaries and service interfaces

**Schema definitions:**
- Field names → property/attribute names in generated code
- Data types (uuid, timestamp, int, string, enum) → language-specific type mappings
- Primary keys → identifier fields in entity structs
- Cardinality (one-to-many, many-to-many) → relationship modeling (foreign keys, join tables)
- Related entities → type references and associations

**GWT scenarios:**
- Generate test cases (property-based tests, example-based tests)
- Document validation rules referenced in command handlers
- Define acceptance criteria for CI/CD pipelines

### Code generation patterns (inferred from Event Modeling structure)

**Event types:**
Each Event on timeline becomes sum type variant or class definition.
```haskell
data HotelEvent
  = AccountRegistered { accountId :: UUID, email :: Email, ... }
  | RoomAdded { roomId :: UUID, roomNumber :: Int, ... }
  | RoomBooked { bookingId :: UUID, guestId :: UUID, ... }
  | RoomPrepared { roomId :: UUID, ... }
  | GuestCheckedIn { bookingId :: UUID, ... }
  | GPSCoordinatesSent { location :: Location, ... }
  | GuestLeftHotel { bookingId :: UUID, departureTime :: Timestamp }
  | GuestCheckedOut { bookingId :: UUID, ... }
  | PaymentRequested { paymentId :: UUID, amount :: Money, ... }
  | PaymentSucceeded { paymentId :: UUID, transactionId :: String, ... }
```

**Command handlers:**
Each Command becomes function signature with validation.
```rust
pub fn register_account(cmd: RegisterAccountCommand) -> Result<AccountRegistered, AccountError> {
    validate_email(&cmd.email)?;
    validate_password_strength(&cmd.password)?;
    // Business logic from GWT scenarios
    Ok(AccountRegistered {
        account_id: Uuid::new_v4(),
        email: cmd.email,
        full_name: cmd.full_name,
        ...
    })
}
```

**Aggregate modules (Decider pattern):**
Each Aggregate Root becomes module with private state.
```rust
pub mod booking {
    struct BookingState { /* private */ }

    // Command → Event (decide function)
    pub fn book_room(cmd: BookRoomCommand, state: Option<BookingState>)
        -> Result<Vec<BookingEvent>, BookingError>
    {
        // Validation from GWT scenarios and Read Model requirements
    }

    // Event → State (evolve function)
    fn apply_event(state: BookingState, event: BookingEvent) -> BookingState {
        match event {
            BookingEvent::RoomBooked { .. } => { /* state transition */ },
            BookingEvent::GuestCheckedIn { .. } => { /* state transition */ },
            ...
        }
    }
}
```

**Read Model queries:**
Each Read Model becomes query interface.
```typescript
interface BookingQuery {
  getAvailableRooms(checkIn: Date, checkOut: Date): Promise<Room[]>;
  getBookingsByCheckoutDate(date: Date): Promise<Booking[]>;
}
```

**Translation functions:**
Translation pattern generates conditional event handler.
```rust
pub fn handle_gps_coordinates(location: Location, bookings: &[Booking])
    -> Option<GuestLeftHotel>
{
    // GWT logic: "when GPS coordinates indicate guest left hotel"
    if location.distance_from_hotel() > HOTEL_BOUNDARY_METERS {
        if let Some(booking) = find_active_booking(location.guest_id, bookings) {
            return Some(GuestLeftHotel {
                booking_id: booking.id,
                departure_time: location.timestamp,
            });
        }
    }
    None
}
```

**Automation processes:**
Automation pattern generates background job.
```rust
pub async fn checkout_automation(booking_repo: &BookingRepository) {
    // GWT logic: "when scheduled check-out date has passed and guest left hotel"
    let eligible_bookings = booking_repo
        .find_by_checkout_date(today())
        .filter(|b| b.guest_left);

    for booking in eligible_bookings {
        checkout_command(booking.id).await;
    }
}
```

### Code generation workflow

**Step 1:** Complete Event Modeling through Step 6 (Bounded Contexts assigned)

**Step 2:** Optionally complete Domain Model (specify all Entities in detail)
- Define entity relationships fully
- Add business rule constraints
- Validate schema completeness

**Step 3:** Generate code skeleton via Qlerify AI code generation feature
- Select target language (Rust, TypeScript, etc.)
- Choose architectural pattern (event sourcing, CQRS, hexagonal)
- Generate boilerplate module structure

**Step 4:** Refine generated code with business logic
- Implement validation rules from GWT scenarios
- Add error handling (railway-oriented programming patterns)
- Implement state machine logic from aggregate state transitions

**Relationship to event-catalog-qlerify.md transformation:**

Event Modeling artifacts (as JSON export) can follow two paths:

**Path 1: Code generation**
Event Model → Qlerify AI code gen → Skeleton implementation → Manual refinement

**Path 2: EventCatalog documentation**
Event Model → JSON export → Transformation queries (jaq/duckdb) → EventCatalog MDX + JSON Schema

Both paths use same source artifacts but serve different purposes:
- Code generation: Executable implementation
- EventCatalog: Team-facing documentation and discovery

## Process workflow for Claude Code to guide Event Modeling sessions

### Pre-session setup

**Environment verification:**
1. Confirm user logged into Qlerify app
2. Open blank workflow
3. Validate Card Type Settings:
   - Use AI: Command, Aggregate Root, Read Model, Given-When-Then enabled
   - Domain Model Role mappings: Command→Command, Aggregate Root→Aggregate Root, Read Model→Read Model, GWT→GWT
4. Optional: Select preferred LLM model (AI tab)

**Context gathering:**
1. Ask user to describe business scenario or workflow
2. Identify key actors/roles involved
3. Confirm scope (single bounded context vs multi-context flow)
4. Reference existing documentation or examples if available

### Guided Step 1: Brainstorming

**Prompt template for user:**
```
Describe your workflow for Event Modeling. Include:
1. Primary actors/roles (Guest, Manager, Admin, etc.)
2. Key state-changing events in chronological order
3. Any external systems involved
4. Success and failure scenarios

Example format:
"The workflow is for [domain]. It enables [actors] to [capabilities] while allowing [other actors] to [other capabilities]. Include the following steps: 1) [event], 2) [event], ..."
```

**Execution:**
1. Have user paste prompt into "Generate workflow with AI"
2. Click "Generate workflow" with default options
3. Wait for AI generation to complete
4. Review initial output with user

**Review checklist:**
- [ ] All major events represented?
- [ ] Events in logical chronological order?
- [ ] Swimlanes make sense (even if need reorganization)?
- [ ] Missing events discovered during review?

### Guided Step 2: The Plot

**Key question:** "Do swimlanes represent actors (people/roles) or systems/bounded contexts?"

**Actor identification:**
1. List human actors: Guest, Manager, Employee, Administrator, etc.
2. Identify automated processes → group into "Automation" actor
3. Verify external entities truly initiate actions (rare; usually external events instead)

**Swimlane reorganization:**
1. For each generated swimlane representing system/BC:
   - Create corresponding actor swimlane if needed
   - Move events to actor-based swimlane
   - Delete system-based swimlane
2. Validate timeline flow tells coherent story

**Common fixes:**
- GPS Device → Automation (if our system triggers GPS reading) or delete (if external GPS device)
- Payment System → Automation (if we invoke payment API)
- Inventory Service → move events to Manager or Automation depending on who triggers

**Timeline validation:**
Ask user: "Reading left to right, does this tell the story of how work flows through your system?"

### Guided Step 3: The Storyboard

**For each event (iterate through timeline):**

1. Select event
2. Open sidebar → Data Fields
3. Switch to Domain Model tab under diagram
4. Guide user through question: "What does the input form look like when [actor] performs [event action]?"

**Field refinement prompts:**
- "What information does [actor] need to provide?"
- "Are these fields in logical order for a user interface?"
- "Any required vs optional fields?"
- "Any fields that should be dropdowns or selections rather than free text?"

**Actions:**
- Add missing fields to Command
- Reorder fields for natural form flow (drag icon)
- Remove over-generated fields
- Update field types if AI guessed wrong

**For automated events:**
Guide: "If a robot were filling out this form, what data would it need? That's what should appear in the Command fields."

### Guided Step 4: Identify Inputs

**For each event:**

1. Review Command name suggested by AI
2. Ask: "Does this name match how your domain experts talk about this action?"
3. Validate imperative form: "Register Account" not "Account Registration"
4. Rename if domain language differs

**Common domain language checks:**
- Technical jargon vs business terms: "Persist Entity" → "Save Customer Details"
- Generic vs specific: "Update Record" → "Approve Order"
- Passive vs active: "Room Addition" → "Add Room"

### Guided Step 5: Identify Outputs

**For each event:**

1. Review Read Model (green box)
2. Ask: "What information does [actor] need to see/know before deciding to [perform command]?"
3. Guide user through perspective shift: "Read Model is what's displayed to actor before they submit the form"

**Examples to clarify:**
- Guest registering account: Terms & Conditions, Privacy Policy (static content)
- Guest booking room: Available rooms list, prices, amenities (query results)
- Manager adding room: Room catalog, room type definitions (reference data)

**Field refinement:**
- Add fields representing information displayed
- Remove fields that are outputs of command (those go in Event)
- Validate field types (query results vs static content vs reference data)

**Multiple Read Models:**
Guide: "Are there different information sources the actor consults? Each becomes a separate Read Model."

### Iteration: Apply Steps 3, 4, 5 to all events

**Pacing strategy:**
1. Complete Steps 3-5 for 2-3 "normal" events together with user
2. Identify pattern categories:
   - Regular input forms (human actor)
   - External events
   - Translations
   - Automations
3. Guide user through examples of each pattern category
4. Have user complete remaining similar events independently with Claude Code available for questions

### Guided pattern: External events

**Identification:**
Ask: "Is this event triggered by a system you don't control (GPS device, third-party API, external service)?"

**If yes:**
1. Guide: "For external events, we delete Command and Read Model because we don't model the external system's internals"
2. Keep Event (fact that external thing happened)
3. Keep Entity/Aggregate (receives external data)
4. Document entity fields to capture external event payload

**Next event check:**
Guide: "The NEXT event after external event is usually a Translation. Let's model that carefully."

### Guided pattern: Translation

**Identification:**
Ask: "Does this event process data from the previous external event and conditionally trigger based on interpretation?"

**If yes:**
1. Read Model represents incoming external event data:
   - Delete generated Read Model
   - Create new Read Model
   - Select Entity corresponding to external event (e.g., Location from GPS)
   - Use AI or field selector to populate fields
2. Command represents our domain action if interpretation succeeds
3. Add GWT scenario describing conditional logic:

**GWT template for Translation:**
```
Given: [Precondition, e.g., guest opted in for GPS tracking]
And: [External event received, e.g., we received GPS coordinates]
When: [Interpretation logic, e.g., coordinates indicate guest left hotel]
Then: [Domain event triggered, e.g., booking status updated to "Guest Left"]
```

**Validation:**
Guide: "Translation has logic that decides IF to trigger event. GWT should capture that decision logic."

### Guided pattern: Automation

**Identification:**
Ask: "Is this event triggered by background process checking for eligible items to process?"

**If yes:**
1. Read Model represents query for eligible items:
   - Select entity being queried (e.g., Booking)
   - Use field selector to choose relevant fields
   - Mark filter fields explicitly (e.g., Check-out Date)
   - Verify query describes "find all items where [condition]"
2. Command represents action performed on each eligible item
3. Add GWT scenario describing eligibility criteria:

**GWT template for Automation:**
```
Given: [Background state, e.g., guest's check-out date has passed]
And: [Additional precondition, e.g., guest left hotel]
When: [Automation trigger, e.g., automated checkout process runs]
Then: [Domain event per eligible item, e.g., booking status updated]
```

**Automation with external call:**
Guide: "If automation calls external service (payment gateway, email service), include success condition in GWT and optionally model as two steps (external call, then result storage)."

### Guided Step 6: Apply Conway's Law

**Transition:**
Guide: "Now we shift from actor flow (swimlanes) to system architecture (bounded contexts)."

1. Switch to Domain Model tab under diagram
2. Review Aggregate Roots (yellow Entity boxes)
3. Ask: "Which of these Aggregate Roots would naturally be owned/managed by the same team?"

**Bounded Context identification prompts:**
- "Which aggregates share business rules or need to be updated together?"
- "Which aggregates could be deployed and scaled independently?"
- "Which aggregates represent distinct business capabilities?"

**Assignment workflow:**
1. For each Aggregate Root, assign Bounded Context
2. Group related aggregates (e.g., Room + Booking → Inventory)
3. Separate unrelated capabilities (e.g., Guest Account → Auth, Payment → Payment)

**Validation:**
Guide: "Each Bounded Context should represent an autonomous component a single team could own. Too many contexts = over-fragmentation. Too few = tight coupling."

**Common contexts from examples:**
- Auth: User accounts, permissions, authentication
- Inventory: Rooms, bookings, availability
- Payment: Transactions, invoices, billing
- External integrations: GPS, third-party APIs (if we own integration layer)

### Guided Step 7: Elaborate Scenarios

**GWT writing for remaining events:**

1. Navigate to User Story Map tab
2. For each event without GWT:
   - Select event
   - Add GWT scenario via sidebar or end-of-page button
   - Guide template based on event type:
     - Regular: Validation rules (when command succeeds/fails)
     - Translation: Conditional logic (when to trigger event)
     - Automation: Eligibility criteria (when to process item)

**GWT structure coaching:**
- **Given:** Preconditions – state of system before event
- **When:** Trigger – action or condition that causes event
- **Then:** Postconditions – state changes and events emitted

**Release planning:**

1. Ask: "What's the minimal set of scenarios needed for first usable release?"
2. Assign critical GWTs to Release 1
3. Identify dependencies: "If we include this GWT, what other events must work?"
4. Assign secondary features to Release 2+
5. Use drag & drop to reorder within releases

**End-to-end validation:**

1. Apply Release 1 filter above workflow diagram
2. Review highlighted events: "Does this represent coherent end-to-end workflow?"
3. Check for orphaned events (no path from start to this event)
4. Add GWTs for dependency events even if minimal scenarios

**Stakeholder review:**
Guide: "The filtered view is excellent for showing stakeholders exactly what Release 1 delivers. Walk them through the timeline left to right, explaining each highlighted event."

### Session wrap-up

**Artifact export:**
1. Export workflow as JSON (for EventCatalog transformation)
2. Export workflow as PDF or image (for documentation)
3. Save User Story Map view per release (for sprint planning)

**Next steps coaching:**
1. Validate with domain experts (especially GWT scenarios and translation logic)
2. Complete Domain Model if code generation desired (entity relationships, constraints)
3. Transform to EventCatalog for team documentation (see event-catalog-qlerify.md)
4. Generate code skeleton via Qlerify AI code gen (if applicable)
5. Implement business logic in code using GWT scenarios as test cases

**Common follow-up questions:**

Q: "Do I need to complete all 7 steps in one session?"
A: No, Steps 1-2 can be initial brainstorming (30-60min), Steps 3-5 detailed modeling (1-2 hours spread over days), Step 6 architecture discussion (30min with architects), Step 7 scenario elaboration (ongoing as team refines understanding).

Q: "What if domain experts disagree during Step 5 about Read Model?"
A: Disagreement often reveals context boundary. Different actors in different contexts may need different Read Models for same Command. Consider splitting into separate events in different Bounded Contexts.

Q: "Should every event have a GWT scenario?"
A: Not necessarily. Trivial events (CRUD with no business rules) may not need GWT. Complex events, automations, and translations benefit most from GWT clarification.

Q: "Can I change the model after code generation?"
A: Event Model is source of truth. If you change model, regenerate code skeleton or manually sync changes. Version control both model (JSON export) and generated code to track evolution.

## Questions and answers

### Q1: How does Qlerify's Event Modeling differ from or extend Adam Dymitruk's original methodology?

**Core similarities:**
- 7-step structure (Brainstorming → Plot → Storyboard → Identify Inputs → Identify Outputs → Conway's Law → Elaborate Scenarios)
- Event-driven focus (domain events as primary artifacts)
- Separation of concerns (actor flow vs system architecture)
- GWT scenarios for behavior specification

**Key Qlerify extensions:**

1. **Actor-exclusive swimlanes:** Qlerify enforces swimlanes = actors only, deferring system/bounded context modeling to Step 6 Domain Model tab. Original Event Modeling allows swimlanes for actors, systems, or teams without strict convention.

2. **Read Model as input perspective:** Qlerify inverts traditional "Read Model = output/projection" to "Read Model = input needed for decision". Actor-centric interpretation aligns with "what does user see before submitting form?" rather than CQRS query semantics.

3. **Explicit external event pattern:** Delete Command and Read Model, keep Event and Entity for external events. Makes integration boundaries explicit in model structure.

4. **Detailed Translation and Automation patterns:** Dedicated UI workflows with specific Read Model interpretations (external data vs query with filters). Original Event Modeling mentions patterns but lacks detailed guidance.

5. **User Story Map integration:** Release planning and filtering in Step 7 connects Event Modeling to agile delivery (iterations, impact analysis). Original methodology focuses on GWT elaboration without release management tooling.

6. **AI-assisted generation:** Natural language prompt → full model with field-level schemas in minutes. Original methodology assumes manual collaborative workshop. Trade-off: speed vs tacit knowledge discovery.

### Q2: What are the key Qlerify UI/workflow patterns for each of the 7 steps?

**Step 1 - Brainstorming:**
- UI: "Generate workflow with AI" dialog with prompt textarea
- Workflow: Paste description → Generate → Review output
- Key pattern: AI generates events, commands, read models, aggregates from single prompt
- Configuration dependency: Card Type Settings must map roles correctly

**Step 2 - The Plot:**
- UI: Swimlane headers with delete icon on hover, drag-and-drop for event movement
- Workflow: Create actor lanes → Move events → Delete system lanes → Validate timeline narrative
- Key pattern: Arrows show "plausible timeline" not strict causality
- Convention: Swimlanes = actors (Guest, Manager, Automation), NOT systems

**Step 3 - The Storyboard:**
- UI: Sidebar with Data Fields tab, Domain Model tab showing Command (blue box), form rendering
- Workflow: Select event → Review Command → Add/remove/reorder fields → Sidebar updates form mockup
- Key pattern: Command schema drives UI form rendering
- Question prompt: "What does input form look like when [actor] performs [action]?"

**Step 4 - Identify Inputs:**
- UI: Command name field in blue box on Domain Model diagram
- Workflow: Review AI suggestion → Rename to match domain language → Validate imperative form
- Key pattern: Minimal step, often trivial if AI named well
- Validation: Does name match ubiquitous language?

**Step 5 - Identify Outputs:**
- UI: Read Model (green box) on Domain Model diagram, field editor
- Workflow: Select event → Ask what actor needs to know → Add/remove fields on Read Model
- Key pattern: Read Model as INPUT (data needed before command), not output
- Multiple Read Models: Events can have multiple Read Models, exactly one Command

**Steps 3-5 iteration - Pattern-specific workflows:**

*Regular input form:*
- Command = manual entry fields
- Read Model = query results or reference data

*External event:*
- Delete Command and Read Model (bin icon on hover)
- Keep Event and Entity
- Document external payload in Entity fields

*Translation:*
- Delete generated Read Model → Create new → Select external Entity → Populate fields
- Command = domain action triggered if interpretation succeeds
- Add GWT describing conditional logic

*Automation:*
- Read Model = query selecting Entity with filter fields marked
- Command = action per eligible item
- Add GWT describing eligibility criteria

*Automation with external call:*
- Read Model = query for items needing processing
- Command (implicit external) + Command (internal result storage)
- GWT describes external call success condition

**Step 6 - Apply Conway's Law:**
- UI: Domain Model tab, Bounded Context dropdown per Aggregate Root
- Workflow: Review Aggregates → Assign Bounded Contexts → Group related Aggregates
- Key pattern: Bounded Contexts separate from swimlanes (different concern)
- Validation: Each context = autonomous component for single team

**Step 7 - Elaborate Scenarios:**
- UI: User Story Map tab showing GWTs under events, release assignment, drag-and-drop reordering
- Workflow: Write GWTs → Assign to releases → Filter by release → Validate end-to-end
- Key pattern: Release filtering highlights subset of timeline for iteration planning
- GWT structure: Given (preconditions) When (trigger) Then (postconditions)

### Q3: How do Translation and Automation patterns work in Qlerify?

**Translation pattern:**

*Definition:* Receive external event → interpret data → conditionally trigger domain event

*Qlerify workflow:*
1. **Previous event is external:** Sent GPS Coordinates (black box, no Command/Read Model)
2. **Translation event:** Left Hotel
   - Read Model: NOT a query, represents incoming external event data
     - Delete generated Read Model
     - Create new Read Model selecting Entity from external event (e.g., Location)
     - Fields: Longitude, Latitude, Timestamp, Guest ID
   - Command: Domain action if interpretation succeeds
     - Fields: Booking Number, Guest ID, Time of Departure
   - GWT scenario: Describes interpretation logic
     - Given: Guest opted in for GPS tracking
     - And: We received GPS coordinates
     - When: Coordinates indicate guest left hotel (conditional logic!)
     - Then: Booking status updated to "Guest Left Hotel"

*Key characteristics:*
- Read Model source: External event payload (not query result)
- Conditional triggering: GWT captures when event triggers vs when it doesn't
- Translation logic: Distance calculation, boundary checks, threshold evaluation
- Entity requirement: Need entity to model external data structure

*Implementation implication:*
Translation generates conditional event handler function:
```rust
fn handle_gps_coordinates(location: Location) -> Option<GuestLeftHotel> {
    if location.distance_from_hotel() > THRESHOLD {
        Some(GuestLeftHotel { ... })
    } else {
        None
    }
}
```

**Automation pattern:**

*Definition:* Periodic query for eligible items → process matching items → trigger command per item

*Qlerify workflow:*
1. **Automation event:** Checked Out Guest
   - Read Model: Query returning list of eligible items
     - Select Entity (e.g., Booking)
     - Use field selector to choose relevant fields
     - Mark filter fields (e.g., Check-out Date) to indicate query parameters
     - Query semantic: "Find all bookings where check-out date = today AND status = guest-left"
   - Command: Action performed on each eligible item
     - Fields: Booking ID (identifier from query result)
   - GWT scenario: Describes eligibility criteria and processing
     - Given: Guest's scheduled check-out date has passed
     - And: Guest has left hotel
     - When: Automated check-out process runs (scheduled trigger)
     - Then: Booking status updated to "Checked Out"

*Key characteristics:*
- Read Model source: Query with explicit filter fields
- Looping invocation: Command invoked once per query result
- Scheduled trigger: Automation runs periodically (cron job, background worker)
- State-based eligibility: GWT describes what makes item eligible for processing

*Automation with external call variant:*
- Read Model: Query for items needing external processing (e.g., payment requests)
- Command (external): Invoke external service API
- Command (internal): Record external call result in our system
- GWT: Includes external call success condition

Example: Payment Succeeded
- Read Model: Payment requests (Booking Reference, Amount Due, Payment Method)
- GWT:
  - Given: Payment requested for booking
  - When: Amount successfully captured from payment card (external call)
  - Then: Invoice updated to "Paid" status

*Implementation implication:*
Automation generates background job:
```rust
async fn checkout_automation(repo: &BookingRepository) {
    let eligible = repo.find_by_checkout_date(today()).filter(|b| b.guest_left);
    for booking in eligible {
        checkout_command(booking.id).await;
    }
}
```

**Translation vs Automation comparison:**

| Aspect | Translation | Automation |
|--------|-------------|------------|
| Trigger | External event | Scheduled job |
| Read Model | External event payload | Query with filters |
| Invocation | Once per external event | Once per eligible item |
| Conditional | Event may/may not trigger | Item may/may not be eligible |
| GWT focus | Interpretation logic | Eligibility criteria |
| Example | GPS coordinates → Left hotel | Checkout date passed → Checked out |

### Q4: What's the relationship between Event Modeling artifacts and code generation?

**Artifacts → Code mapping:**

| Event Modeling Artifact | Generated Code Construct |
|------------------------|--------------------------|
| Event (orange) | Sum type variant or event class |
| Command (blue) | Command handler function signature + validation |
| Aggregate Root (yellow) | Aggregate module with Decider pattern (decide/evolve) |
| Read Model (green) | Query interface or projection implementation |
| Bounded Context | Module boundary, service interface |
| GWT scenario | Test case (property-based or example-based) |
| Field schema | Type definitions (structs, classes, interfaces) |

**Schema details → Type system:**

| Qlerify Field Metadata | Code Representation |
|-----------------------|---------------------|
| Field name | Property/attribute name |
| Data type (uuid, timestamp, int, string, enum) | Language-specific type (Uuid, DateTime, i32, String, enum) |
| Primary key | Identifier field, required in constructors |
| Cardinality (one-to-many, etc.) | Relationship modeling (Vec, foreign key, join table) |
| Related entity | Type reference, association |
| Example data | Test fixtures, enum variants |

**Code generation workflow:**

1. **Complete Event Modeling:** Finish Steps 1-6 (Bounded Contexts assigned)
2. **Optional: Complete Domain Model:** Specify all entity relationships, constraints, business rules
3. **Generate code skeleton:** Qlerify AI code gen feature
   - Select target language (Rust, TypeScript, Haskell, etc.)
   - Choose architecture (event sourcing, CQRS, hexagonal)
   - Generate module structure, type definitions, function stubs
4. **Implement business logic:** Fill in validation, state transitions, GWT scenarios as tests

**Generated code patterns (inferred from Event Modeling):**

*Event types:*
```haskell
data HotelEvent
  = AccountRegistered { accountId :: UUID, email :: Email }
  | RoomAdded { roomId :: UUID, roomNumber :: Int }
  | ... (one variant per Event on timeline)
```

*Command handlers:*
```rust
pub fn register_account(cmd: RegisterAccountCommand)
    -> Result<AccountRegistered, AccountError>
{
    validate_email(&cmd.email)?; // From GWT scenarios
    validate_password_strength(&cmd.password)?;
    Ok(AccountRegistered { ... })
}
```

*Aggregates (Decider pattern):*
```rust
pub mod booking {
    struct BookingState { /* private */ }

    // decide: Command → State → Events
    pub fn book_room(cmd: BookRoomCommand, state: Option<BookingState>)
        -> Result<Vec<BookingEvent>, BookingError>

    // evolve: State → Event → State
    fn apply_event(state: BookingState, event: BookingEvent) -> BookingState
}
```

*Translation functions:*
```rust
// Conditional event handler from Translation pattern
pub fn handle_gps_coordinates(location: Location) -> Option<GuestLeftHotel> {
    if location.distance_from_hotel() > THRESHOLD {
        Some(GuestLeftHotel { ... })
    } else {
        None
    }
}
```

*Automation processes:*
```rust
// Background job from Automation pattern
pub async fn checkout_automation(repo: &BookingRepository) {
    let eligible = repo.find_by_checkout_date(today()).filter(|b| b.guest_left);
    for booking in eligible {
        checkout_command(booking.id).await;
    }
}
```

**Two paths from Event Model:**

*Path 1 - Code generation:*
Event Model → Qlerify AI code gen → Skeleton implementation → Manual refinement
Purpose: Executable system

*Path 2 - EventCatalog documentation:*
Event Model → JSON export → Transformation (jaq/duckdb) → EventCatalog MDX + JSON Schema
Purpose: Team-facing documentation and discovery

**Why both paths matter:**
- Code generation accelerates implementation (skeleton → working system)
- EventCatalog preserves domain understanding (documentation → onboarding, discovery)
- Event Model is single source of truth for both

**Code generation trade-offs:**

*Benefits:*
- Rapid skeleton generation (hours to implement basic structure)
- Consistent patterns (all aggregates use Decider pattern)
- Type safety from Day 1 (compiler checks contracts)
- Test scaffolding from GWT scenarios

*Limitations:*
- Business logic still requires manual implementation
- Generated code requires language expertise to refine
- Over-generated code may need cleanup
- Architectural choices (event sourcing vs CRUD) constrain options

**Best practice workflow:**

1. Event Model first (don't prematurely commit to code structure)
2. Validate with domain experts (especially GWT scenarios and translations)
3. Export to EventCatalog for documentation (team reference)
4. Generate code skeleton when ready to implement
5. Iterate Event Model as understanding evolves (regenerate or manually sync code)
6. Version control both Event Model JSON and generated code

## See also

**Local preference documents:**
- `/Users/crs58/.claude/commands/preferences/event-catalog-qlerify.md` - Transformation workflow from Qlerify JSON export to EventCatalog
- `/Users/crs58/.claude/commands/preferences/collaborative-modeling.md` - EventStorming, Domain Storytelling, Example Mapping facilitation
- `/Users/crs58/.claude/commands/preferences/event-catalog-tooling.md` - EventCatalog usage and algebraic documentation patterns
- `/Users/crs58/.claude/commands/preferences/event-sourcing.md` - Event persistence and Decider pattern implementation
- `/Users/crs58/.claude/commands/preferences/discovery-process.md` - DDD 8-step discovery workflow (Event Modeling appears in Step 2-7)

**Qlerify documentation (downloaded):**
- `/Users/crs58/Downloads/www.qlerify.com_event-modeling-tool.2026-01-05T20_38_22.375Z.md` - Source for this analysis
- `/Users/crs58/Downloads/qlerify-data-ingestion-automation.json` - Example Qlerify JSON export structure

**EventCatalog source repositories:**
- `~/projects/lakescope-workspace/eventcatalog` - EventCatalog core source
- `~/projects/lakescope-workspace/eventcatalog-mcp-server` - MCP server for catalog queries

**Original Event Modeling reference:**
- https://eventmodeling.org/posts/what-is-event-modeling/ (Adam Dymitruk's 2019 blog post)
