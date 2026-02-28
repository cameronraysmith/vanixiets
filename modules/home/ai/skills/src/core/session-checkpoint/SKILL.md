---
name: session-checkpoint
description: All-horizons session skill that captures session state, evaluates surprise, propagates context downstream, assesses documentation impact, and produces a handoff narrative sufficient for the next session's /session-orient.
---
# Session checkpoint

Symlink location: `~/.claude/skills/session-checkpoint/SKILL.md`
Slash command: `/session-checkpoint`

Session wind-down protocol that captures state across all planning horizons, evaluates accumulated surprise, propagates discoveries to downstream issues, assesses documentation impact, and produces a self-contained handoff narrative sufficient for the next session to self-direct via `/session-orient`.
This skill operates across all horizons simultaneously: it updates operational state (signal tables, checkpoint context), evaluates tactical feedback (surprise accumulation, replanning thresholds), and captures strategic observations (documentation impact, Cynefin reclassification).

This is the default session wind-down command for repositories with the full stigmergic workflow installed.
For repositories without the full workflow (no session-layer skills, small utility repos, quick fixes), use `/issues-beads-checkpoint` directly.

## Composed skills

This skill orchestrates a higher-level protocol that uses the following skills as components.
Do not duplicate their functionality; delegate to them.

- `/issues-beads-checkpoint` provides the per-issue signal table update, checkpoint-context write, escalation handling, proactive pheromone propagation, buffer depletion checks, graph health verification, and beads commit.
  Delegate all per-issue checkpoint mechanics to this skill.
- `/issues-beads-evolve` provides graph restructuring when checkpoint reveals structural issues (splitting, merging, re-parenting, dependency rewiring).
  Delegate graph restructuring to this skill when step 2 or step 5 reveals the need.
- `/stigmergic-convention` provides the signal table schema, field definitions, read-modify-write protocol, and checkpoint-context format.
  Reference this skill for signal table semantics; do not redefine them here.

Load `/issues-beads-prime` for core beads conventions and command quick reference before running checkpoint commands.

## Protocol

Execute the following nine steps in order.
Steps 1 through 4 operate per-issue via delegation to `/issues-beads-checkpoint`.
Steps 5 through 9 operate at session level, synthesizing across all touched issues.

### Step 1: enumerate all issues touched during the session

Assemble the complete set of issues that participated in this session.
An issue counts as "touched" if any of the following occurred:

- Work was performed on the issue (implementation, exploration, verification).
- The issue's signal table was read or updated during orientation or review.
- The issue was created during this session's planning phase.
- The issue's description or notes were modified as part of pheromone propagation from another issue.

```bash
# Review session activity to identify touched issues
bd activity

# Cross-reference with issues known to have been worked
bd show <id> --json | jq '.[0] | {id, title, status}'
```

The enumeration serves as the scope for steps 2 through 4.
Every issue in this set receives a signal table update and checkpoint-context write.

### Step 2: update signal tables on all touched issues

For each touched issue, delegate the signal table update to `/issues-beads-checkpoint` steps 1-2.

For each issue, assess and update:

*Surprise* based on plan-versus-reality divergence.
Use the calibration scale from `/issues-beads-checkpoint`: 0.0 for no deviation, 0.1-0.3 for minor deviations, 0.4-0.6 for moderate divergence, 0.7-0.9 for major divergence, 1.0 for complete divergence.
Be honest in this assessment; it is the primary metric for downstream calibration and replanning triggers.

*Progress* to reflect current state: exploring, implementing, verifying, or blocked.
Do not leave progress at not-started for any issue that received work.

*Cynefin reclassification* if the implementation experience revealed a different domain than originally assessed.
When cynefin changes, re-derive planning-depth using the default mapping (clear to shallow, complicated to standard, complex to deep, chaotic to probe).
Upward complexity shifts trigger the notification protocol defined in `/issues-beads-checkpoint`.

*Planning-depth* update when cynefin changes or when manual override is warranted based on implementation experience.

### Step 3: write checkpoint context to each touched issue

Delegate to `/issues-beads-checkpoint` step 3.
Each checkpoint context uses replacement semantics: the current state is the sufficient statistic for future planning.
Prior checkpoint contexts are replaced, not appended.

Each checkpoint context must be self-contained, synthesizing current position, approach, and remaining work.
Workers need only the current state to proceed.

```
<!-- checkpoint-context -->
## State estimate (YYYY-MM-DD)

What was done: [specific accomplishments this session]

What was learned: [key insights, unexpected findings, approach changes]

What remains: [concrete next steps for the next worker]

Downstream impact: [what dependent issues should know about]
<!-- /checkpoint-context -->
```

For issues being left incomplete (progress=implementing or progress=blocked), this section is mandatory.
For issues created during planning but not yet started, a brief context note describing the rationale and any dependencies suffices.

### Step 4: evaluate total surprise

Compute the accumulated surprise across all session-touched issues.
This is the session-level surprise evaluation that determines whether the current plan has diverged enough from reality to warrant replanning.

```bash
# For each touched issue, extract surprise from its signal table
bd show <id> --json | jq -r '.[0].notes // ""'
# Parse the signal table between <!-- stigmergic-signals --> delimiters
# Extract the surprise value from the row: | surprise | <value> | <date> |
```

Sum the surprise scores across all session nodes.
Compare the accumulated surprise against the replanning threshold theta.

The replanning threshold is context-dependent.
Complex-domain issues have a lower per-issue threshold because surprise in complex domains has higher downstream impact: a small deviation in a complex subsystem can cascade unpredictably.

Per-issue theta heuristics (consistent with `/session-review`):
- *Clear* domain: theta = 0.5 per issue (high tolerance; clear-domain surprise is usually bounded).
- *Complicated* domain: theta = 0.3 per issue (moderate tolerance).
- *Complex* domain: theta = 0.2 per issue (low tolerance; complex-domain surprise cascades).
- *Chaotic* domain: theta = 0.1 per issue (very low tolerance; any surprise in a stabilization context warrants reassessment).

Compute the effective threshold as the sum of per-issue thetas, where each issue contributes its domain-specific theta value.
If accumulated surprise exceeds this effective threshold, flag for replanning in the handoff narrative (step 8).

The replanning threshold check is also performed within `/issues-beads-checkpoint` at the per-epic level (using a cumulative threshold of 2.0 by default).
The session-level check here provides a complementary perspective: it evaluates surprise across all work performed in the session regardless of epic boundaries, catching cross-epic plan divergence that per-epic checks miss.

### Step 5: assess documentation impact

Determine whether implementation revealed specification inaccuracies or architectural assumption violations.
Flag specific AMDiRE artifacts (architecture decisions, specifications, context documents) for update.

This step connects the session checkpoint to the documentation promotion workflow, which defines the full lifecycle of working notes and specifications.
The assessment produces flags; the actual documentation updates are performed by the worker in a subsequent session or as part of the current session if time permits.

#### Minor inaccuracy (surprise < 0.5)

The specification's tactical-resolution accuracy (plus/minus 1.5x) still holds but specific details are wrong.
Revise the specification in place to reflect implementation reality.
This is a maintenance operation, not a lifecycle transition.
Commit the revision with a message referencing the issues whose implementation revealed the inaccuracy.

Action: flag the specific `docs/development/` artifact and the nature of the inaccuracy.
Note which issues' implementation experience revealed the discrepancy.

#### Major inaccuracy (surprise >= 0.5)

The specification's core assumptions are invalidated by implementation experience.
Its accuracy has dropped below tactical resolution, meaning the document no longer represents committed understanding at plus/minus 1.5x.

Two responses are available, depending on whether the new understanding has already reached tactical resolution.

*Revise in place* when the new understanding is itself stable at tactical resolution.
The implementation revealed a better answer that is committed rather than exploratory.
Update the specification, flag downstream beads issues whose descriptions or acceptance criteria derive from the invalidated content, and propagate the revised understanding via the pheromone propagation in step 6.

*Demote to working note* when the new understanding is still at strategic resolution.
The implementation revealed that the problem is less understood than the specification implied.
This typically coincides with a Cynefin reclassification (complicated to complex, or clear to complicated).
Create a new working note in `docs/notes/` capturing the revised understanding and what probes are needed.
Mark the specification as superseded by adding a `superseded-by:` frontmatter field referencing the working note path.
The superseded specification remains in `docs/development/` as a historical record until the new working note matures to promotion readiness and produces a replacement specification.

Demotion signals a fundamental misunderstanding of the problem domain and typically warrants a replanning cycle.
When demotion occurs, include it as a replanning trigger in the handoff narrative (step 8) alongside the surprise threshold evaluation from step 4.

#### Promotion consideration (reverse case)

Detect working notes that reached tactical resolution as a side effect of implementation.
When a session produces understanding in `docs/notes/` that answers "what are we building?" rather than "what are we learning?", flag the working note for promotion consideration.

The single promotion test across all Cynefin domains: does the working note contain tactical-resolution understanding (plus/minus 1.5x accuracy, committed rather than exploratory) for the information required by its target `docs/development/` location?

Cynefin modulates how quickly working notes reach promotion readiness:
- *Clear*: promote quickly; the specification is knowable from first principles or established patterns.
- *Complicated*: promote after expert analysis is complete and conclusions are stable enough to drive planning.
- *Complex*: promote late; only after a stable pattern has emerged from multiple probes and the content answers "what are we building?" rather than "what did we learn?"
- *Chaotic*: stabilize first; promotion happens after reclassification into a different domain, using that domain's criteria.

Promotion is an advisory flag, not a gate.
Promotion happens in a subsequent session if the worker confirms readiness.
Include flagged candidates in the handoff narrative (step 8).

### Step 6: propagate discoveries to downstream issues

For each finding that changes assumptions for downstream work, update those issues' descriptions or notes to reflect the new understanding.
This is proactive pheromone propagation: correcting the trail rather than waiting for the next worker to discover the discrepancy.

Delegate per-issue propagation mechanics to `/issues-beads-checkpoint` step 5.

```bash
# Check what depends on each touched issue
bd dep tree <id> --direction up
```

For each downstream issue affected by a discovery:

```bash
bd update <downstream-id> --description "Updated: <incorporate discovery that affects this issue>"
```

Common propagation scenarios include interface or API changes from what the downstream issue expects, prerequisites proving harder than expected and changing downstream scope, assumptions in the downstream description being invalidated, and technical constraints discovered that the downstream worker needs to know.

#### Cross-repo pheromone propagation

When issues in the current repo reference external repo issues, propagate checkpoint context to those external issues.
Cross-repo references use the format `see {prefix}-{id} in {repo}` as defined in the cross-project coordination protocol.

For each touched issue, scan its description and notes for cross-repo references.
When a discovery affects an externally referenced issue:

1. Check whether the referenced repository is accessible on the local filesystem.

```bash
# Attempt to locate the referenced repo
fd -t d '^{repo-name}$' ~/projects
```

2. If accessible, write checkpoint context to the external issue's notes.
   This is the same proactive pheromone propagation described above, extended across repository boundaries.
   The worker performing the checkpoint has access to both repos via the filesystem and can update notes in either.

```bash
# From the external repo's working directory
cd ~/projects/{path-to-repo}
bd show <referenced-id> --json | jq -r '.[0].notes // ""'
# Update notes with propagated context
bd update <referenced-id> --notes "$UPDATED_NOTES_WITH_PROPAGATED_CONTEXT"
```

3. If the external repo is not accessible on the local filesystem, note the propagation as pending in the handoff narrative (step 8).
   Include the cross-reference identifier, the repo name, and a summary of what context should be propagated when access becomes available.

Cross-repo propagation also applies to closure-reason signaling: when closing an issue whose results affect an external repo issue, include the cross-reference in the closure reason so that external workers can trace the dependency when they orient.

### Step 7: verify graph health

Run structural integrity checks to ensure no corruption was introduced during the session.
Delegate to `/issues-beads-checkpoint` step 7 for the mechanics.

```bash
# Cycle detection — must be zero
bd dep cycles

# Structural lint
bd lint

# Ready queue sanity check
bd ready | head -5
```

If cycles are detected, resolve them before proceeding.
If lint warnings appear, address structural issues.
These checks are performed inline rather than delegating to `/issues-beads-audit` because they are a single step within the checkpoint protocol rather than a standalone maintenance activity.

### Step 8: produce handoff narrative

Synthesize a self-contained handoff narrative sufficient for the next session to self-direct via `/session-orient`.
The narrative captures what happened, what was surprising, what the next session should focus on, and what alerts require attention.

The handoff narrative has the following sections.

*Accomplishments*: what was completed this session.
For each closed issue, summarize the deliverable and verification results.
For issues left in progress, summarize current state and remaining work.

*Surprises*: findings that diverged from expectations.
For each issue with surprise >= 0.3, describe the nature of the divergence and its implications.
Group by impact: local surprises (affecting only the issue itself), propagated surprises (affecting downstream issues), and cross-repo surprises (affecting issues in other repositories).

*Documentation impact flags*: artifacts flagged for update in step 5.
Organize by response type: minor inaccuracies (revise in place), major inaccuracies (revise or demote), and promotion candidates (working notes that reached tactical resolution).
For demotions, note the Cynefin reclassification that motivated the demotion.

*Replanning alerts*: conditions that warrant re-invocation of `/session-plan`.
Include alerts when accumulated surprise exceeds theta (from step 4), when documentation was demoted (from step 5), or when any other replanning trigger fired during the session.

*Buffer depletion alerts*: report buffer status from the per-epic check delegated to `/issues-beads-checkpoint` step 6.
If any epic has unclosed children but zero ready issues, flag it prominently so the next session prioritizes unblocking.

*Cross-repo propagation status*: report on cross-repo pheromone propagation from step 6.
Distinguish between completed propagations (external repos accessed and updated) and pending propagations (external repos inaccessible, context not yet delivered).
For pending propagations, include enough detail for the next session to complete them.

*Next session focus*: recommended starting point for the next session.
Identify the highest-priority ready issue or the most impactful unblocking action.
When replanning was triggered, recommend starting the next session with `/session-plan` rather than jumping to implementation.

```
Session summary:

Completed:
- <issue-id>: <brief description of what was implemented and verified>

In progress:
- <issue-id>: <current state, what remains>

Surprises (accumulated: <total> / threshold: <theta>):
- <issue-id> (surprise=<value>): <nature of divergence and implications>

Documentation impact:
- [revise] <docs/development/path>: <what is inaccurate and which issues revealed it>
- [demote] <docs/development/path>: <what was invalidated, new working note location>
- [promote?] <docs/notes/path>: <what reached tactical resolution>

Replanning: {needed | not needed}
- {reason if needed}

Buffer status:
- <epic-id>: <ready>/<total> ready ({healthy | depleted})

Cross-repo propagation:
- [done] <prefix>-<id> in <repo>: <what was propagated>
- [pending] <prefix>-<id> in <repo>: <what needs propagation, why inaccessible>

Next session:
- Recommended: <issue-id> (<rationale>)
- Alternative entry points: <issue-id>, <issue-id>
- Phase recommendation: {/session-plan | implement | /session-orient discovery mode}
```

### Step 9: push beads state

Delegate to `/issues-beads-checkpoint` step 8.

Push beads state to the dolt remote for backup:

```bash
bd dolt commit -m "checkpoint: <session-summary>"
bd dolt push
```

The commit message should reference the primary issues checkpointed.
For multi-issue sessions, summarize by category rather than listing every issue.

## Cynefin modulation within checkpoint

Cynefin classification modulates how deeply this skill executes, not whether the worker enters the checkpoint phase.

| Cynefin domain | Checkpoint behavior |
|---|---|
| Clear | Brief: state capture, minimal narrative. Surprise is expected to be low; flag if unexpectedly high. |
| Complicated | Standard: full signal table update, complete handoff narrative with dependency analysis. |
| Complex | Detailed: exploration findings, discovery propagation, explicit documentation of what probes revealed and what remains unknown. |
| Chaotic | Immediate: act-sense-respond observations captured promptly. Focus on what intervention was attempted and whether stabilization occurred. |

## Typical next steps

After checkpoint completes, the session ends.
The next session starts with `/session-orient`, which reads the handoff narrative, signal tables, and checkpoint contexts produced by this skill.

When replanning was triggered (surprise exceeded theta or documentation was demoted), the handoff narrative recommends that the next session begin with `/session-orient` followed by `/session-plan` before resuming implementation.

---

*Composed skills (delegate, do not duplicate):*
- `/issues-beads-checkpoint` -- per-issue signal table update, checkpoint-context write, escalation handling, pheromone propagation, buffer depletion check, graph health verification, beads commit
- `/issues-beads-evolve` -- graph restructuring when checkpoint reveals structural issues
- `/stigmergic-convention` -- signal table schema, field definitions, read-modify-write protocol

*Related skills:*
- `/session-orient` -- strategic horizon session start, consumes the handoff narrative produced here
- `/session-plan` -- tactical-to-operational decomposition, invoked when replanning is triggered
- `/session-review` -- convergence-point validation, uses compatible theta heuristics
- `/issues-beads-prime` -- core beads conventions and command quick reference

*Theoretical foundations:*
- `preferences-adaptive-planning` for the surprise threshold derivation, replanning decision rule, documentation impact theory, and the fan-in normalization refinement
