---
argument-hint: <codebase-path-or-description>
description: Reverse engineer Event Model from existing codebase
---

Reverse engineer the Event Model that "should have existed" for a brownfield codebase.

This command loads all relevant preferences for: Event Modeling (Qlerify 7-step methodology), functional domain modeling (DDD aggregates, Decider pattern), bounded context design (context mapping, ACL), event sourcing (CQRS, event replay, state reconstruction), strategic domain analysis (Core/Supporting/Generic classification), EventCatalog transformation (schema documentation), railway-oriented programming (Result types), and algebraic laws (property-based testing).

## Workflow

### Phase 1: Codebase Analysis

If $ARGUMENTS provided, use that path or description.
Otherwise, ask the user to specify the codebase location or describe the system.

Analyze the codebase to identify:
- Existing domain entities and their state transitions
- API endpoints or UI actions that trigger state changes
- Database schemas and their relationships
- Error handling patterns and validation rules
- Integration points with external systems

### Phase 2: Event Extraction (Reverse Step 1)

Extract implicit domain events from:
- Database writes and state mutations
- Log statements indicating business actions
- Method names suggesting state changes (create, update, delete, approve, reject)
- Audit trails or history tables

Name events in past tense: "OrderPlaced", "PaymentReceived", "UserRegistered"

### Phase 3: Command Identification (Reverse Steps 3-4)

Identify commands from:
- API endpoint handlers
- UI form submissions
- Message queue consumers
- Scheduled job triggers

Map commands to the events they produce.
Identify validation rules as GWT preconditions.

### Phase 4: Read Model Discovery (Reverse Step 5)

Identify read models from:
- Database queries preceding writes
- API responses informing UI state
- Cached or denormalized data structures

### Phase 5: Bounded Context Analysis (Reverse Step 6)

Apply strategic domain analysis to classify:
- Core domains (competitive advantage, high investment)
- Supporting domains (necessary but not differentiating)
- Generic domains (commodity, buy or use standard solutions)

Identify bounded context boundaries from:
- Module/package structure
- Database schema separation
- Team ownership patterns
- Integration points requiring translation

### Phase 6: GWT Scenario Extraction (Reverse Step 7)

Extract Given-When-Then scenarios from:
- Existing test cases
- Validation error messages
- Business rule documentation
- Edge case handling code

### Phase 7: Artifact Generation

Produce:
- Event Model documentation suitable for EventCatalog
- Bounded context map
- Aggregate identification with Decider pattern mapping
- Gap analysis: what's missing vs ideal Event Model

## User Input

$ARGUMENTS
