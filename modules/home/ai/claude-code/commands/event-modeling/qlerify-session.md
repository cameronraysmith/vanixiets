---
argument-hint: [step-number]
description: Guide interactive Qlerify session with browser integration
---

Guide an interactive Event Modeling session with Qlerify open in the browser.

This command loads all relevant preferences for: Event Modeling (Qlerify 7-step methodology), functional domain modeling (DDD aggregates), bounded context design, event sourcing (CQRS), and EventCatalog transformation.

This command assumes the user has Qlerify open in Chrome and claude-in-chrome MCP is available for browser interaction.

## Prerequisites

1. Qlerify workflow open in Chrome browser tab
2. Claude-in-chrome extension connected
3. User logged into Qlerify with appropriate workspace access

## Workflow

### Initial Context

Use `mcp__claude-in-chrome__tabs_context_mcp` to find the Qlerify tab.
Take a screenshot to understand current workflow state.
Identify which step of the 7-step process the user is currently on.

### Step-Specific Guidance

If $ARGUMENTS specifies a step number (1-7), focus on that step.
Otherwise, assess current state and recommend next actions.

**Step 1 - Brainstorming**:
- Review generated events for completeness
- Suggest missing events based on workflow gaps
- Validate event naming (past tense)

**Step 2 - The Plot**:
- Verify swimlanes represent actors (Guest, Manager, Automation), not systems
- Check temporal ordering tells coherent narrative
- Identify events that should be moved between lanes

**Step 3 - Storyboard**:
- Review command field schemas
- Suggest field ordering for natural form flow
- Identify missing required fields

**Step 4 - Identify Inputs**:
- Validate command naming matches ubiquitous language
- Check imperative mood (RegisterAccount not AccountRegistration)

**Step 5 - Identify Outputs**:
- Review read model definitions
- Ensure read models show information needed for decision-making
- Identify missing read models

**Step 6 - Conway's Law**:
- Review bounded context assignments
- Suggest context groupings based on aggregate relationships
- Identify potential context boundary issues

**Step 7 - Elaborate Scenarios**:
- Review GWT scenarios for coverage
- Suggest missing edge case scenarios
- Validate Given-When-Then structure

### Interactive Actions

Use browser automation to:
- Navigate between workflow views (User Story Map, Domain Model, Entities)
- Take screenshots at each step for documentation
- Read current state from accessibility tree

## User Input

$ARGUMENTS
