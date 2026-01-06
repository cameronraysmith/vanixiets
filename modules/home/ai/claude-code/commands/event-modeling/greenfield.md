---
argument-hint: <domain-description>
description: Start 7-step Event Modeling from scratch with Qlerify
---

Guide a greenfield Event Modeling session using the 7-step methodology with Qlerify.

This command loads all relevant preferences for: Event Modeling (Qlerify 7-step methodology), functional domain modeling (DDD aggregates, Decider pattern), bounded context design (context mapping), event sourcing (CQRS, state reconstruction), EventCatalog transformation (schema documentation), railway-oriented programming (Result types, validation workflows), and algebraic laws (property-based testing).

## Workflow

### Phase 1: Context Gathering

If no $ARGUMENTS provided, ask the user to describe:
1. The domain or business capability being modeled
2. Primary actors/roles involved
3. Key workflows or processes to capture
4. Any known bounded context boundaries

If $ARGUMENTS provided, use that as the domain description.

### Phase 2: Step 1 Brainstorming

Generate a Qlerify AI prompt for the user based on their domain description.
The prompt should enumerate key events in chronological order and identify actors.

Example format:
```
Model the [domain] workflow. Include the following events:
1. [Event in past tense]
2. [Event in past tense]
...
Actors involved: [Actor1], [Actor2], Automation
```

### Phase 3: Steps 2-7 Guidance

After Step 1 generation, guide the user through:
- Step 2 (The Plot): Verify swimlanes represent actors only, not systems
- Step 3 (Storyboard): Design form fields for each command
- Step 4 (Identify Inputs): Validate command naming matches domain language
- Step 5 (Identify Outputs): Define read models as decision-context information
- Step 6 (Conway's Law): Assign bounded contexts to aggregate roots
- Step 7 (Elaborate Scenarios): Write Given-When-Then for critical behaviors

### Phase 4: Artifacts

Produce or guide toward:
- Qlerify JSON export for EventCatalog transformation
- Bounded context assignments
- GWT scenarios for property-based tests
- Implementation guidance using Decider pattern

## User Input

$ARGUMENTS
