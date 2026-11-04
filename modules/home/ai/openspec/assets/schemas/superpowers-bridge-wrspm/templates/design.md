## Context

<!--
Background, current state, constraints, stakeholders.
brainstorm.md records the exploration process (alternatives + selected direction);
this document takes up the selected direction and develops the full technical design.
-->

## Goals / Non-Goals

**Goals:**
<!-- What this design aims to achieve -->

**Non-Goals:**
<!-- What is explicitly out of scope -->

## Decisions

<!--
The single source of truth for all technical decisions.
brainstorm.md's Agreed Approach records "which path was chosen";
this section records "how each fork along that path was decided".

Suggested structure for each decision:
### D1: <decision title>
- **Choice**: <the approach adopted>
- **Rationale**: <why it was chosen this way>
- **Alternatives considered**: <rejected option + reason for rejection>
-->

## Risks / Trade-offs

<!--
Known risks and trade-offs.
Format: [Risk] <description> → Mitigation: <mitigation measure>
[Trade-off] <trade-off description> → reason for acceptance
-->

## Migration Plan

<!--
Deployment order, rollback strategy, acceptance criteria.
When a change edits shared data that another host's closure reads (a host table, an inventory row, a shared list),
that host's behaviour changes only when it deploys, so list it in the deployment order and say so in the runbook;
otherwise the change takes effect at some later deploy made for unrelated reasons.
If this change does not involve a deployment change (pure package addition, no endpoint / DB change),
you may write "N/A — this change does not involve a deployment change".
-->

## Open Questions

<!-- Outstanding decisions or unknowns to resolve -->
