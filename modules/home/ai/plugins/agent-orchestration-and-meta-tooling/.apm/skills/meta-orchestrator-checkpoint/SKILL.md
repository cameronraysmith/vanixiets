---
name: meta-orchestrator-checkpoint
description: Team-level checkpoint and handoff for missions coordinated through the master orchestrator pattern. Captures cross-cycle accumulated state across the master plus retired ACs and their WO cycles, producing a handoff payload that the next master session can resume via /meta-orchestrator-initiate. Two variants: handoff (mid-mission) and closure (mission completion).
---

# Meta-orchestrator checkpoint

Symlink location: `~/.claude/skills/meta-orchestrator-checkpoint/SKILL.md`
Slash command: `/meta-orchestrator-checkpoint`

Team-level state capture and handoff for the planning master orchestrator.
Captures cross-cycle accumulated state across the master, retired ACs and their respective WO cycles, parameterization calibration data, and any in-flight work, producing a handoff payload that a fresh master session can consume via `/meta-orchestrator-initiate` to resume the mission.

This skill is the team-level analog of `/session-checkpoint`.
Where `/session-checkpoint` captures one session's state for handoff to the same role's replacement, this captures the master's team-level state for handoff to a fresh master session.

## Scope distinction from `/session-checkpoint`

Two checkpoint scopes exist; do not conflate.

- *`/session-checkpoint`* — session-level scope; each AC and WO runs this at cycle end to capture its own session state and produce a handoff payload for its same-role replacement. Invoked when the AC or WO approaches its own context fill. Owned by whichever role is checkpointing.
- *`/meta-orchestrator-checkpoint`* — team-level scope; master runs this at mission-level pause points to capture team-level state across the master plus retired ACs and their WO cycles. Invoked when the master approaches its own context fill or at mission natural pause points. Owned by master.

The two compose: master's `/meta-orchestrator-checkpoint` payload includes pointers to each retired AC's `/session-checkpoint` output rather than duplicating their content.

## When to invoke

Three triggers with response patterns:

- *Master self-detection of context fill (~50%).* Master invokes `/meta-orchestrator-checkpoint` immediately; does not spawn new pairs; completes the checkpoint and surfaces handoff narrative to user before context exhaustion.
- *AC surfaces "we should checkpoint and hand off" via wrapper.* Master assesses: is the mission at a natural pause? Is master also near fill? If both yes, checkpoint. If only AC near fill (mission ongoing, master has budget), replace AC instead via the AC's `/session-checkpoint` output as orient addendum for a new AC; do not invoke team-level checkpoint.
- *User directive to wrap up* ("we need to circle back" / "checkpoint the mission state" / explicit `/meta-orchestrator-checkpoint` slash invocation). Takes priority over any in-flight spawning; master halts new spawns and proceeds to checkpoint.

In all three cases, the invocation can be either handoff variant (mid-mission, mission continues in a fresh master session) or closure variant (mission complete, no further master session needed). Master determines variant from the trigger and state.

## Composed skills

- `/meta-orchestrator-initiate` — accepts this skill's output as input (payload path); the new master session resumes from documented state rather than re-deriving from a fresh mission frame
- `/session-checkpoint` — each retired AC runs this; this skill's payload references their outputs by path
- `meta-agent-teams` — shared task list and teammate lifecycle remain authoritative through the checkpoint and across master handoff

## Protocol

Execute the following seven steps in order.

### Step 1: enumerate spawned AC↔WO pairs and current status

Assemble the complete set of AC↔WO pairs spawned across the mission lifetime, including pairs that have already been retired and replaced.

For each pair, record:

- Pair identity (`team_name`, AC name, WO name)
- Stream name and target repo
- Current status: active / retired / completed
- For retired pairs: pointer to the retiring AC's `/session-checkpoint` output path
- For active pairs: current phase and most-recent surface-up state

The enumeration is the scope for steps 2 and 3.

### Step 2: per-pair synthesis

For each pair (active or retired), synthesize:

- *Deliverables produced.* What this pair produced — commits landed, PRs created or merged, artifacts shipped to other streams via the dependency map.
- *Surprise observed.* Where this pair's execution diverged from the strategic frame the AC drafted at spawn time. Honest assessment; do not soften.
- *Design decisions captured.* Decisions the pair made that warrant preservation across master handoff (architectural choices, calibration thresholds adopted, conventions established).
- *Goal-2 insights.* Insights this pair surfaced about the orchestration pattern itself (parameterization candidates, friction patterns, emergent regularities). These feed back into the orchestrator skills' future refinement.

Per-pair synthesis is the input to step 3's cross-pair synthesis.

### Step 3: cross-pair synthesis

Synthesize across all pairs to identify mission-level emergent patterns:

- *Emergent friction patterns.* Friction that recurred across multiple pairs (e.g., a wrapper-protocol detail that needed clarification more than once; a recurring failure mode in cross-stream coordination).
- *Cross-stream coordination assessment.* How well the dependency map served the mission; what dependencies emerged that decomposition did not anticipate; what supersession events fired and how they were handled.
- *Parameterization candidates.* Thresholds, defaults, or conventions in the orchestrator skills that the mission's experience suggests should be revised. Capture as candidates, not refinements — refinement is a separate workflow.

### Step 4: open threads and in-flight work

Capture the state of unfinished work:

- *Active pairs at checkpoint time.* What each is currently doing, what surface-up is in flight, what their next action should be.
- *Cross-stream dependency map state.* Current rows with status (pending / in-flight / delivered); any rows added since decomposition.
- *Outstanding gate evaluations.* Any tier-2 elevation candidates pending master review; any decomposition-ratification revisits pending.
- *User-side open items.* Anything master is waiting for from the user (authorization, clarification, deferred decision).

In the closure variant, this section is empty or near-empty by construction; in the handoff variant, this is the load-bearing section for the next master session's resumption.

### Step 5: calibration data

Record parameterization-calibration data from the mission's execution:

- *Which mitigations fired.* Of the five turn-ordering crossing mitigations, which fired and how often; which were not exercised.
- *Which heuristic thresholds proved correct vs needed adjustment.* Longevity budget actual usage; interim-surface-up threshold; ambiguity threshold calibration outcomes.
- *Stream-novelty assessments vs actuals.* For each pair: was the master's novelty self-assessment correct? Did AC have to push back on under-counted novelty?
- *Six-point gate rubric fires.* How many gate evaluations halted on which criterion.
- *AC five-condition surface protocol distribution.* Which conditions fired most often; which never fired.

This data feeds future skill-codification cycles (the second-order goal-2 work).

### Step 6: format the handoff payload

Apply the schema in `01-handoff-payload-schema.md` to produce the structured payload.
The schema is identical for both variants; closure variant simply leaves the in-flight-work fields empty and adds a per-stream merged-PR list and deferred follow-up items.

Payload fields (canonical schema; see sub-file for details):

- Mission frame summary
- Master observation log path
- Pair enumeration with retired-pair `/session-checkpoint` pointers
- Per-pair synthesis output (step 2)
- Cross-pair synthesis (step 3)
- Open threads and in-flight work (step 4)
- Calibration data (step 5)
- Variant marker (`handoff` or `closure`)
- For `closure` variant: per-stream merged-PR list + deferred follow-up items with rationale

Write the payload to `${CLAUDE_JOB_DIR}/handoff/meta-orchestrator-payload.md` (fallback `~/.claude/jobs/manual-handoff/meta-orchestrator-payload.md`).

### Step 7: continuation prompt (handoff variant only)

For the handoff variant, draft the continuation prompt the user will send to the fresh master session:

```
/meta-orchestrator-initiate <payload-path>
```

Plus a brief narrative wrapper for the user: what the mission is, where it stands, what the fresh master should expect to find in the payload, what the next action is.

For the closure variant, this step is replaced by the closure summary surface to user: per-stream PRs merged, accumulated design notes, calibration data summary, deferred follow-ups. No continuation prompt; the mission is closed.

## Output

This skill produces:

- The structured handoff payload at the specified path
- A surface to user containing: variant marker, payload path, continuation prompt (handoff) or closure summary (closure)

The user routes the payload path to the fresh master session (handoff) or files the closure summary (closure).

## Composition with `/meta-orchestrator-initiate`

This skill's output feeds the next `/meta-orchestrator-initiate` invocation.
The initiate skill's step 1 parses the payload and restores: mission frame, retired-AC enumeration with pointers, accumulated design decisions, parameterization-calibration data, master's observation log path, open threads, in-flight work, next-spawn recommendations.

Canonical text in `/meta-orchestrator-initiate` is the normative source for protocol items (wrapper canon, precedence rule, etc.); this skill does not redefine them. The handoff payload references but does not duplicate canonical text.

## Variants: handoff vs closure

The two variants share the schema; they differ in which fields are populated and what is surfaced to user.

| Field | Handoff variant | Closure variant |
|---|---|---|
| Mission frame | Required | Required |
| Pair enumeration with retired-pointer paths | Required | Required (all pairs retired) |
| Per-pair synthesis | Required | Required |
| Cross-pair synthesis | Required | Required |
| Open threads and in-flight work | Required (load-bearing for resumption) | Empty or near-empty |
| Calibration data | Required | Required |
| Variant marker | `handoff` | `closure` |
| Per-stream merged-PR list | Optional | Required |
| Deferred follow-up items | Optional | Required (with rationale for each deferral) |
| Continuation prompt | Required | Not applicable (no resumption) |

Determination of variant: closure if all streams have integrated to main and no open work remains; handoff otherwise.

## Sub-files

- `01-handoff-payload-schema.md` — explicit schema for the handoff payload with field definitions, variant differences, and a worked example

---

*Related skills:*
- `/meta-orchestrator-initiate` — team-level orchestrator initialization; consumes this skill's output
- `meta-agent-teams` — teammate isolation, beads-to-task-list mirroring, orient/checkpoint lifecycle
- `/session-checkpoint` — session-level checkpoint each AC and WO runs at cycle end; this skill references their outputs

*Theoretical anchors:*
- `preferences-adaptive-planning` — surprise threshold derivation; replanning decision rule; the handoff narrative's load-bearing role in the receding-horizon cycle
- `preferences-validation-assurance` — confidence promotion rules; evidence quality dimensions applied to mission-level state capture
