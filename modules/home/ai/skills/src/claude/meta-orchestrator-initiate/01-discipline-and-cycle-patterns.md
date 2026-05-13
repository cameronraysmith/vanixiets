# Discipline and cycle patterns

Patterns the master enacts and AC instantiates across pair cycles.
Load when configuring a new pair's discipline, when calibrating critique posture, or when handling cycle-boundary friction (replacement, supersession, in-flight crossings).

## Longevity budget heuristic

Target: AC consumes approximately 15-20% of its context window per WO cycle.
This budget supports 4-5 WO cycles before AC itself requires replacement via `/session-checkpoint`.

The budget derives from the observation that a single AC cycle includes: ingest of WO surface-up, dispatch of critique-supporting subagents (if any), composition of critique via wrapper, master coordination on gate transitions.
A cycle costing more than 25% truncates AC's effective lifespan; a cycle costing less than 10% suggests AC is either pre-cooking operational detail or not engaging at the architectural depth the wrapper forcing-function demands.

Calibration signals:

- AC budget overrun (more than 25%): AC is doing WO work. Apply pullback discipline below.
- AC budget under-run (less than 10%): AC is rubber-stamping. Apply dual-axis critique-posture test below.

## AC pullback discipline

After spawning the WO, the AC operates at oversight altitude.
Three anti-patterns to recognize and refuse:

- *Pre-cooking operational detail for the WO.* The WO independently produces operational detail from AC's strategic frame. If AC is drafting tables, enumerations, or checklists for the WO, the AC has descended into WO territory.
- *Drafting deliverable content the WO will produce.* AC may sketch shape; AC must not author deliverable content. The WO authors; AC critiques.
- *Running audits inline.* Audits dispatch to subagents (Explore for read-only sweeps, code-reviewer for adversarial review). AC consumes the audit return and routes findings; AC does not run grep/read sweeps in its own context.

Self-check before composing a response: "Does this content preserve my context budget for 4 or more cycles?"
If no, the response is over-cooked; trim to strategic framing and let the WO produce specifics.

## Dual-axis critique posture

WO surface-ups invite two distinct push-back axes; AC must engage both to satisfy the wrapper's forcing function.

- *Execution-precision push-back.* Requires AC to read implementation files at line-precision. Targets: specific commit boundaries, exact line content, verbatim text matches, file path references.
- *Architectural push-back.* Requires AC to read conceptual space. Targets: design topic-to-file assignments, regulator coverage, structural decisions, composition relationships.

Both axes must surface in every substantive critique. If only one fires, AC's posture has failed.

### Four failure modes

WO surface-up critiques have four characteristic failure modes; AC's mitigation prompt-back patterns address each.

1. *No refinements surfaced.* AC pushed back on nothing. Pure stenographer mode; the wrapper failed. AC prompt-back: "Surface at least one refinement under each axis (precision and architectural) before this round closes."
2. *Precision-only push-back.* AC read files but did not reason architecturally. AC prompt-back: "Surface architectural concerns: which design decisions, regulator placements, or composition relationships warrant push-back?"
3. *Architectural-only push-back.* AC reasoned architecturally but did not read files at line-precision. AC prompt-back: "Surface execution-precision concerns: which specific line content, boundary, or verbatim text warrants push-back?"
4. *Fails to address open acceptance criteria.* AC engaged both axes but skipped one or more of the criteria the cycle was supposed to close. AC prompt-back: "Address each open criterion explicitly before this round closes."

The prompt-back patterns ARE the AC's calibration loop on its own posture.

## Skill allocation per role (situational)

Soft guide; defer to task shape.

| Skill | Owner | When |
|---|---|---|
| `/session-advisor` | AC | At spawn, before strategic framing |
| `/session-orient` | Both (dual-use) | AC reorients on master directive; AC produces addendum for WO; WO runs with AC addendum |
| `/session-plan` | Situational | If beads-graph-seeding applies; may not apply to all tasks |
| `/session-review` | AC | Convergence audit (System 3-star posture) |
| `/session-checkpoint` | Owning role | Whichever role is checkpointing (master, AC, or WO) |

The wrapper-forced critique rule is the load-bearing role-preservation mechanism, not skill allocation.
Skill allocation is a soft guide that depends on task shape (beads-seeded epic vs single-unit refactor vs cross-cutting investigation).

## State-dependent recovery directive

A coordination-under-uncertainty pattern distinct from the cross-time conflict rule.

When a sender issues a directive that may race the receiver's execution state, the sender enumerates possible receiver states with corresponding actions ordered cheapest to most-expensive recovery.
The receiver picks the first matching state.
Asymmetric: only the receiver selects.

Canonical four-case example (user-bookmark-correction supersession context):

- (a) you've already routed the corrected bookmark name to WO; no action needed
- (b) you routed the original bookmark name; WO has not yet acted; pass the correction in time
- (c) you routed the original bookmark name; WO has created the bookmark; halt before push, delete-and-recreate with corrected name (cheap, no remote impact)
- (d) you routed the original bookmark name; WO has pushed; ask user for guidance on delete-and-recreate vs proceed-as-named

Why this works: enumeration covers an axis of receiver-state uncertainty; each case names the state precondition and corresponding action; ordering minimizes total round-trips compared to a request-state-then-direct-action protocol; receiver-side selection avoids sender re-roundtrip.

Distinguished from the cross-time conflict rule in `meta-orchestrator-initiate/SKILL.md`: cross-time is authority-precedence reconciliation across user directives over time (A then master(B) then C); state-dependent recovery is message-passing-latency mitigation within a single coordination episode.

## Post-long-in-turn-operation interim rule

After any in-turn operation expected to exceed approximately 60 seconds or produce a deliverable exceeding approximately 300 words, the agent sends an interim surface-up before going idle.
Turn boundaries in agent teams are message-driven; an agent cannot self-trigger its own next turn after expensive in-turn work completes.
The interim ("audit complete, composing proposal now") triggers a follow-up turn so the agent can continue without master-side nudge.

Below the 60-second / 300-word threshold, single-message responses are appropriate.

## Calibration loops

Multiple judgment thresholds in this skill are feedback-loop-calibrated, not static:

- *Interim-surface-up threshold* (~60s / ~300 words): adjust if interim signals are noisy (compose-time predictions consistently off) or if downstream turn ordering breaks.
- *Ambiguity-rule threshold* (within companion rule): adjust based on user-feedback signals. User correcting interpretation indicates threshold was too lax (ask sooner). User expressing impatience with clarification indicates threshold was too strict (interpret with framing).
- *Longevity budget* (15-20% per cycle): adjust if AC cycles consistently underrun (suggests AC is rubber-stamping) or overrun (suggests AC is doing WO work).
- *Decomposition N* (typical 2-3): adjust based on user cognitive ceiling (user is the conversation-channel shuttle).

Each threshold has explicit feedback signals; the skill encodes the calibration loop, not the static value.

## Multi-audience artifact routing

Design property: single artifacts produced by AC or master can serve multiple coordination audiences simultaneously when intentionally composed for it.

Canonical example: AC's rank-ordered push-back-likelihood note for an upcoming WO surface-up serves three audiences in one composition:

1. AC's own self-calibration target for WO critique
2. Master's expectation-setting for AC critique posture
3. WO's awareness of where AC expects strongest read

The master embeds the note in the WO's spawn prompt visible to WO; AC retains for critique calibration on WO's first surface-up.

Apply this design property when composing strategic-frame artifacts: ask "who reads this besides the immediate recipient?" and structure accordingly.

## User-supersession in N greater than 1 missions: enumerate-affected-streams and propagate

When user supersession lands during parallel execution (N greater than 1 streams active), master applies the precedence rule plus an enumeration step.

1. Identify which streams are affected (one specific stream / a subset / all streams / a cross-stream decomposition decision).
2. Master surfaces supersession-marking to each affected pair via wrapper, so each pair can terminate-and-repurpose in-flight work.
3. The state-dependent recovery pattern (above) applies at each downstream propagation hop because each pair has independent execution state at the moment of propagation.
4. Master synchronizes the cross-stream dependency map if the supersession invalidates prior dependencies.
5. Master surfaces a consolidated state-sync to user after propagation completes (no re-litigation; state-sync only).

Unaffected pairs continue their cycles unmolested.
The N greater than 1 case differs from N equal to 1 only in step 1 (enumeration) and step 4 (dependency map sync); the underlying precedence rule and reconciliation duty are identical.
