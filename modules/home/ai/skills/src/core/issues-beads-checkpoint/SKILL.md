---
name: issues-beads-checkpoint
description: Session wind-down action to capture learnings into issue graph and prepare for handoff via stigmergic signal tables.
disable-model-invocation: true
---
# Session checkpoint

Symlink location: `~/.claude/skills/issues-beads-checkpoint/SKILL.md`
Slash command: `/issues:beads-checkpoint`

Action prompt for session wind-down.
Write the worker's state back to the DAG so subsequent workers can resume without information loss.
Signal tables are the primary coordination mechanism; all checkpoint state flows through them.

If you need to refactor the issue graph structure during checkpoint (e.g., split epics, merge issues, restructure dependencies), use `/issues:beads-evolve` first, then complete the checkpoint workflow.

## Checkpoint workflow overview

The checkpoint protocol follows seven steps, matching the convention specification's checkpoint write protocol.
Execute them in order for each issue that received active work this session.

1. Read existing signal table from notes
2. Update signal table values (surprise, progress, cynefin if warranted)
3. Write checkpoint context (replacement semantics)
4. Handle escalation if needed
5. Propagate context to downstream issues
6. Verify graph health
7. Commit beads state

## Step 1: Read existing signal table

For each issue that was actively worked on (not just read), read the current notes and parse the signal table.

```bash
# Read current notes — field is ABSENT when unset, not null or empty
NOTES=$(bd show <id> --json | jq -r '.[0].notes // ""')
```

Extract the signal table from between the `<!-- stigmergic-signals -->` and `<!-- /stigmergic-signals -->` delimiters.
If no signal table exists, prepare a new one using defaults from `/stigmergic-convention`: cynefin=complicated, surprise=0.0, progress=not-started, escalation=none, planning-depth=standard.

Also read the issue's description and acceptance criteria to compare expectations against implementation experience.
This comparison informs the surprise assessment in the next step.

## Step 2: Update signal table values

Assess and update each signal field, setting the `Updated` column to today's date for any changed value.

### Surprise assessment

Set the surprise score based on how much the actual work diverged from what the issue description led you to expect.
Be honest in this assessment; it is the primary metric for downstream calibration and replanning triggers.

- 0.0: Work proceeded exactly as described, no deviations.
- 0.1-0.3: Minor deviations. Small details differed but the overall approach was as expected.
- 0.4-0.6: Moderate divergence. Significant unexpected discoveries or approach changes, but the core objective remained the same.
- 0.7-0.9: Major divergence. The work bore limited resemblance to the description. Fundamental assumptions proved incorrect.
- 1.0: Complete divergence. The work bore almost no resemblance to the description.

A reflexive `surprise=0.0` on an issue where work encountered difficulties is misleading pheromone for the next worker.
Conversely, a complicated-domain rewrite of a skill that encounters zero divergence would itself be surprising as a 0.0.

### Progress state

Set the progress field to reflect where the work stands:

- `exploring`: Complex-domain probe phase completed, implementation not yet started.
- `implementing`: Work is in progress but not yet ready for verification.
- `verifying`: Implementation is complete and verification is underway or passed.
- `blocked`: Work cannot proceed due to a dependency, missing information, or external blocker.

Do not leave progress at `not-started` for any issue that received work.

### Cynefin reclassification

If the implementation experience revealed a different domain than originally assessed, update the cynefin field.
When cynefin changes, re-derive planning-depth using the default mapping unless a manual override is warranted.

The cynefin-to-planning-depth mapping: clear to shallow, complicated to standard, complex to deep, chaotic to probe.

### Reconstruct and write

After modifying signal values, reconstruct the full notes content.
The signal table goes at the beginning of the notes field, followed by any checkpoint-context and escalation-context sections.
Write the complete result back:

```bash
bd update <id> --notes "$RECONSTRUCTED_NOTES"
```

The `--notes` flag replaces the entire field.
All sections must be included in the reconstructed content: the signal table, the checkpoint-context section, and the escalation-context section (if any).

If the issue had no prior signal table, create one at the beginning of the notes field using defaults for any values not being set by this checkpoint, and append any pre-existing notes content after the closing delimiter.

## Step 3: Write checkpoint context

Write a `<!-- checkpoint-context -->` section in the notes describing the current state.
This section uses replacement semantics: if a prior checkpoint-context exists, replace it entirely with the new content.

Each checkpoint context must be self-contained.
It synthesizes the current position, approach, and remaining work rather than referencing prior checkpoints.
Workers need only the current state to proceed.
Trajectory data is available through git history of `.beads/issues.jsonl` via `chore(beads): checkpoint <id>` commits.

```
<!-- checkpoint-context -->
## State estimate (YYYY-MM-DD)

What was done: [specific accomplishments this session]

What was learned: [key insights, unexpected findings, approach changes]

What remains: [concrete next steps for the next worker]

Downstream impact: [what dependent issues should know about]
<!-- /checkpoint-context -->
```

The state estimate must be sufficient for the next worker to orient without advisory input.
If the issue is being left incomplete (progress=implementing or progress=blocked), this section is mandatory.

## Step 4: Handle escalation

If the worker encountered genuine ambiguity that cannot be resolved from DAG context, create an escalation.

Set `escalation` to `pending` in the signal table.
Write the question in an `<!-- escalation-context -->` section.
The question must be precise enough for the human to answer without the worker's full context.
Reference specific alternatives and explain why the DAG does not contain enough information to choose.

```
<!-- escalation-context -->
## Pending (YYYY-MM-DD)
[Specific question with alternatives and rationale]
<!-- /escalation-context -->
```

If an escalation-context section already exists (from a prior resolved escalation), append the new question with a date separator to preserve the decision audit trail.

After setting the escalation, move on to other work rather than blocking.
Escalation is orthogonal to progress; the issue remains in whatever progress state it was in.

If no escalation is needed, skip this step.
Do not modify an existing resolved escalation unless new ambiguity has arisen.

## Step 5: Propagate context to downstream issues

Check whether context discovered during work affects dependent issues.
If the worker learned something that changes assumptions for downstream work, update those issues' descriptions or notes to reflect the new understanding.

This is proactive pheromone propagation: rather than waiting for the next worker to discover discrepancies, the current worker corrects the trail.

```bash
# Check what depends on this issue
bd dep tree <id> --direction up
```

For each downstream issue affected by a discovery, update its notes or description:

```bash
bd update <downstream-id> --description "Updated: <incorporate discovery that affects this issue>"
```

Common propagation scenarios include an interface or API changing from what the downstream issue expects, a prerequisite proving harder than expected and changing the downstream scope, an assumption in the downstream description being invalidated, or a technical constraint being discovered that the downstream worker needs to know.

## Step 6: Verify graph health

Before committing, verify graph integrity:

```bash
# Must be zero — cycles corrupt the graph
bd dep cycles

# Check for structural issues
bd lint

# Confirm ready queue makes sense
bd ready | head -5
```

If cycles are detected, identify and break them:

```bash
bd dep cycles --verbose
bd dep remove <upstream> <downstream>
```

### Parent-child integrity scan

For each issue worked on, verify its relationship to its parent epic.
Run `bd show <id> --json` and confirm that the dependency linking it to its epic uses type `parent-child`.
If it uses `child-of`, `parent`, `blocks`, or any other type for what should be containment, fix it:

```bash
bd dep remove <child-id> <epic-id>
bd dep add <child-id> <epic-id> --type parent-child
```

For each active epic, verify that `bd epic status <epic-id>` shows the expected child count.
If the count is zero or lower than expected, investigate for mistyped containment dependencies.

When creating issues during checkpoint (discovered work, follow-ups), always specify the parent epic:

```bash
# Preferred: parent at creation time
bd create "Discovered: ..." -t bug -p 2 --parent <relevant-epic-id>
bd dep add <new-id> <current-id> --type discovered-from

# If parent was omitted at creation, add it explicitly
bd dep add <new-id> <relevant-epic-id> --type parent-child
```

Do not rely on `blocks` relationships for containment.
An issue connected to an epic via `blocks` is a sequencing constraint, not containment, and will not appear in `bd epic status` child counts.

### Signal table validity scan

For each issue that was actively worked on, verify its signal table reflects actual work state rather than stale defaults.

An issue that received implementation work but still shows `progress=not-started` indicates an incomplete checkpoint.
A `surprise=0.0` on an issue where work encountered difficulties is misleading pheromone.
If cynefin classification changed during work, verify the signal table reflects it and that planning-depth was re-derived.

For issues being left incomplete (progress=implementing or progress=blocked), verify that a checkpoint-context section exists with a self-contained state estimate.

## Step 7: Commit beads state

Execute the commit sequence:

```bash
# Validate beads database integrity
bd hooks run pre-commit

# Stage the database file
git add .beads/issues.jsonl

# Commit with descriptive message
git commit -m "chore(beads): checkpoint <id>"
```

The commit message should reference the specific issue being checkpointed.
For multi-issue checkpoints, name the primary issues or summarize by category.

## Run wind-down diagnostics

After completing the per-issue checkpoint steps above, run session-level diagnostics to verify overall state.

```bash
# Current state (compare to session start)
bd status

# What changed this session
bd activity

# Epic progress change
bd epic status
```

For structured session summary:

```bash
# Create repo-specific temp file
REPO=$(basename "$(git rev-parse --show-toplevel)")
SUMMARY=$(mktemp "/tmp/bd-${REPO}-checkpoint.XXXXXX.json")
bv --robot-triage > "$SUMMARY"

# Session-relevant extractions
jq '.triage.quick_ref' "$SUMMARY"                    # current counts
jq '.triage.project_health.graph_metrics' "$SUMMARY"  # health metrics
jq '.triage.stale_alerts' "$SUMMARY"                  # attention needed

# Clean up when done
rm "$SUMMARY"
```

## Scale-aware session summary

Determine session scope by counting issues touched:

```bash
# Count issues modified this session (from activity feed)
bd activity | grep -E "^[->!+]" | wc -l
```

Tailor summary depth to session scope.

Small sessions (1-3 issues touched): full detail on each change with complete before/after state, full descriptions for modified issues, complete dependency changes with rationale.

Medium sessions (4-10 issues touched): summary table of changes by category (closed with completion notes, updated with what changed, created with traceability, dependency additions/removals), highlight key closures and discoveries.

Large sessions (10+ issues touched): epic-level aggregation of changes, statistics only ("8 closed, 3 created, 12 dependencies modified"), only critical highlights (blockers discovered, scope corrections, priority changes), per-epic progress deltas ("Domain layer: 42% to 58%, +5 closed").

## Reflect

Consider what was learned this session that the issue graph does not yet reflect.

Scope changes: Was the work larger or smaller than the issue described? Did implementation reveal unanticipated complexity? Should the issue description be updated to reflect actual scope?

Discovered work: Were bugs found during implementation? Was technical debt identified that should be tracked? Are there follow-up enhancements worth capturing?

Dependency corrections: Were any listed blockers not actually blocking? Were hidden prerequisites discovered? Can work that was assumed sequential actually proceed in parallel?

Priority shifts: Did this work reveal that other issues are more or less critical than assigned? Were any P3 items actually critical blockers? Were any P1 items actually low-impact?

## Priority recalibration

If reflection revealed priority mismatches, update before committing:

```bash
# Issue proved more critical than marked
bd update <id> --priority 1

# Issue proved less critical than marked
bd update <id> --priority 3

# Add context for the change
bd comments add <id> "Priority adjusted: discovered this blocks X during implementation"
```

## Capture

For each learning identified in the reflection, execute the appropriate update.

Scope and understanding changes:

```bash
bd update <issue-id> --description "Revised: <what changed and why>"
```

Discovered issues:

```bash
# Create with traceability and epic parentage
bd create "<title>" -t <bug|task|feature> -p <priority> --parent <relevant-epic-id>
bd dep add <new-id> <current-issue-id> --type discovered-from
```

Dependency corrections:

```bash
# Remove false dependencies
bd dep remove <not-actually-blocking> <issue-id>

# Add discovered dependencies
bd dep add <actual-blocker> <issue-id>
```

Completed work:

```bash
# Close and see what was unblocked
bd close <issue-id> --reason "Implemented in commit $(git rev-parse --short HEAD). <notable learnings>" --suggest-next
```

## Unblock chain visibility

When closing issues, show the cascade effect:

```bash
# See what completing this unblocked
bd close <id> --reason "..." --suggest-next

# Show full unblock chain
bd dep tree <closed-id> --direction up
```

Extract structured unblock data:

```bash
bd dep tree <closed-id> --direction up --json | jq '{
  direct: [.children[] | .id],
  direct_count: [.children[]] | length,
  total_downstream: [.. | .id? // empty] | unique | length
}'
```

Present the cascade: "Closing nix-50f.2 unblocked 3 issues (nix-50f.1, nix-l2a.2, nix-l2a.5). These 3 issues unblock 7 more downstream. Total downstream impact: 10 issues now closer to ready."

## Epic impact aggregation

For medium and large sessions, show epic-level progress change:

```bash
bd epic status
```

Present as progress deltas: "Domain layer: 42% to 58% (closed 5 issues). Infrastructure: 20% to 35% (closed 3 issues, created 2). Frontend: unchanged (0 issues touched)."

## Handoff

Prepare for the next session to pick up cleanly.

If work is complete:

```bash
# Close and immediately see what was unblocked
bd close <issue-id> --reason "Implemented in..." --suggest-next

# Check if any epics are ready for human review (epic closure is human-only)
bd epic close-eligible --dry-run
```

Review unblocked issues and check whether their descriptions need updating given what was learned.

If work is incomplete, ensure the checkpoint-context section written in step 3 is self-contained.
The signal table's progress field should be `implementing` or `blocked` as appropriate.
Use `bd update <id> --claim` to atomically claim an issue when resuming work in a future session.

## Narrative handoff synthesis

Produce a prose summary for the next session:

```
Session summary:

Completed:
- <issue-id>: <brief description of what was implemented>

Discovered:
- <issue-id>: <why this was created, what triggered discovery>

Learned:
- <key insight that changed understanding>
- <assumption that proved incorrect>

Next:
- Recommended starting point: <issue-id> (<why this is the logical next step>)
- Alternative entry points: <issue-id>, <issue-id>

Warnings:
- <blockers discovered but not resolved>
- <scope risks identified>
```

This mirrors beads-orient's synthesis section but for session end.
The next session can use this summary plus `/issues:beads-orient` to quickly resume.

## Verify next work is discoverable

Before ending the session, ensure the next agent can pick up cleanly via `/issues:beads-orient`.

```bash
# Quick check of top recommendation
bv --robot-triage | jq '.triage.quick_ref'

# Or minimal: just the top pick
bv --robot-next

# Review its description
bd show <top-recommendation-id>
```

If the description is stale or incomplete based on what was learned this session:

```bash
bd update <top-recommendation-id> --description "Updated: <incorporate session learnings that affect this issue>"
```

The issue graph becomes the handoff.
When descriptions are accurate and signal tables reflect actual state, `/issues:beads-orient` in the next session will find actionable, up-to-date work.

## Summary for user

Provide the user a summary scaled to session scope.

Small sessions: full detail with issues closed (completion notes), updated (what changed), created (traceability), dependencies modified (rationale), unblock cascade (what is now ready).

Medium sessions: category summary with counts, key items named, epic progress deltas, next session recommendation.

Large sessions: executive summary with statistics, epic progress deltas, only critical items, next session recommendation with rationale.

The next session can run `/issues:beads-orient` to see the updated project state.

---

*Reference docs (read only if deeper patterns needed):*
- `/stigmergic-convention` -- signal table schema, field definitions, and update protocol
- `/issues:beads-evolve` -- comprehensive adaptation patterns
- `/issues:beads` -- comprehensive reference for all beads workflows and commands
