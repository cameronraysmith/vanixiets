# Exemplar session

Refined end-to-end exemplar of a mission run through the master-orchestrator pattern.
Load when first invoking `/meta-orchestrator-initiate` and needing the multi-pair coordination shape concretely, or when reasoning about a particular phase transition or failure mode in context.

The exemplar uses an illustrative two-stream mission (parallel work in two repos) to show N greater than 1 behaviors. Single-stream missions are the degenerate case.

## Phase 0: mission entry

User issues a mission directive in conversation channel to the planning master orchestrator:

- Goal / Epic / project framing (what is the mission)
- Addendum: target repos, deliverable shape, success criteria, observation expectations
- Optional: checkpoint payload path (resuming a prior mission)

Master receives the directive and invokes `/meta-orchestrator-initiate`.

## Phase 1: strategic frame establishment and decomposition

Master executes the seven-step protocol from `SKILL.md`:

1. Parse input (fresh mission or checkpoint resume)
2. Establish master observation log at `${CLAUDE_JOB_DIR}/observations/master-orchestrator.md`
3. Propose team decomposition into N streams

Master's decomposition applies the conjunction criterion:

- Each stream is a coherent unit of intellectual content (subdomain, feature boundary, or dependency layer)
- Each stream has a mutually-exclusive file set (verified disjoint across streams before surfacing)

For our illustrative example: N=2. Stream-α targets repo-A (modifies `src/foo.rs` and `src/bar.rs`); stream-β targets repo-B (modifies `lib/baz.py` and `tests/test_baz.py`). File sets are disjoint by virtue of different repos; would also be disjoint if both targeted the same repo since file paths do not overlap.

Master populates the initial cross-stream dependency map. For our example: stream-β depends on stream-α producing the wire-protocol header definition by end of Phase 2.

Master self-assesses stream-novelty for each:

- Stream-α: high-novelty (master has not done this kind of refactor in repo-A before)
- Stream-β: low-novelty (master has a template for this convention rollout from prior missions)

## Phase 2: decomposition-ratification gate (tier-2 reversibility)

Master surfaces decomposition proposal to user with:

- Stream enumeration (name, target repo, jj chain plan, deliverable)
- File-set-per-stream inventory verifying disjointness
- Cross-stream dependency map (initial)
- Proposed N=2 with rationale
- Stream-novelty assessment per stream

User confirms, revises, or rejects. In our example: user confirms.

## Phase 3: pair spawning

For each stream, master spawns the AC↔WO pair using Agent tool with `team_name` and `name`. One team for the whole mission; tasks namespace via stream prefix.

Stream-α (high-novelty path):

1. Master spawns `repo-A-α-ac` via Agent tool
2. AC bootstraps: `/session-advisor` then `/session-orient` with master-supplied addendum; produces three-audience push-back-likelihood note
3. AC drafts structural template for WO spawn prompt
4. Master inlines content into AC's template and spawns `repo-A-α-wo` via Agent tool
5. WO bootstraps: `/session-orient` with AC-supplied addendum; audits target repo state; claims its jj chain

Stream-β (low-novelty path):

1. Master pre-spawns `repo-B-β-ac` and `repo-B-β-wo` from a master-held template (master self-checked: re-usable template exists, strategic frame fully internalized)
2. AC ratifies post-spawn; would push back if novelty was undercounted (in this run, accepts)
3. Both bootstrap normally

## Phase 4: parallel cycle dynamics

Each pair iterates independently using the wrapper protocol.

Pair-internal cycle: WO surfaces at group boundaries via wrapper (closing question "How would you best advise it?"); AC critiques via dual-axis push-back (execution-precision and architectural); WO incorporates and progresses.

Master holds gating altitude. Master surfaces to a pair only when its five-condition surface-up triggers master action.

In our example, mid-execution:

- Stream-α AC surfaces under condition 1 (WO needs master input): wire-protocol header design has two viable approaches, AC adjudication cost exceeds available signal, escalating to master for tiebreak. Master adjudicates; routes resolution back to AC; AC routes to WO.
- Stream-β proceeds without master involvement.

Master maintains the cross-stream dependency map as AC surface-ups reveal new dependencies (during stream-α's protocol discussion, master records the deliverable specification for stream-β's awareness).

## Phase 5: cross-stream coordination

When stream-α completes the wire-protocol header (a dependency map entry), master:

1. Marks the dependency map row `delivered`
2. Surfaces availability to stream-β's AC via wrapper
3. Stream-β's AC routes to its WO with the new artifact

AC↔AC direct comm does not occur. WO↔WO direct comm does not occur. Master is the sole cross-stream coordinator.

If, alternatively, stream-α could not produce the artifact (descope), master surfaces to user for re-decomposition rather than silently relaxing the dependency.

## Phase 6: three-level checkpoint cascade

Three checkpoint scopes operate at different layers:

- *WO context fill.* WO invokes `/session-checkpoint` for its own session. AC requests master replace WO. Master spawns new WO with retired WO's checkpoint as `/session-orient` addendum.
- *AC context fill.* AC invokes `/session-checkpoint` for its own session. AC surfaces handoff narrative to master via wrapper. Master spawns new AC with the AC's checkpoint payload as orient addendum. The new AC reorients on the stream and retains accumulated calibration.
- *Master context fill.* Master invokes `/meta-orchestrator-checkpoint` (team-level scope, distinct from session-level checkpoints) and surfaces handoff narrative to user. Fresh master session invokes `/meta-orchestrator-initiate` with the checkpoint payload to resume.

Each layer's checkpoint feeds the next-layer-up's reorient at handoff time.

## Phase 7: stream completion via PR cycle (tier-2 elevation)

When a stream reaches integration-readiness:

1. WO completes its chain; verification passes; commits are clean atomic units
2. AC runs `/session-review` (System 3-star convergence audit)
3. AC compiles evidence against the six-point evidence rubric (D2 match / no orphans / reader path coherent / risk flags closed / AC concurrence / tier-1 chain intact for elevation)
4. AC surfaces tier-2 elevation proposal to master under condition 3 of the five-condition protocol
5. Master surfaces to user with: validation evidence, proposed PR title, bookmark name, body protocol variant (title-plus-comment default or title-only opt-out)
6. On user authorization: WO bookmarks the chain, pushes, creates draft PR, monitors buildbot, transitions to ready, executes Mergify FF auto-merge per repo conventions

Streams may complete independently. Non-conflicting completions merge as ready (FF + jj auto-rebase handles late streams cleanly).

In our example: stream-β completes first; merges to main. Stream-α auto-rebases on next jj operation; completes shortly after; merges to main.

## Phase 8: mission closure

When all N streams have integrated, master invokes `/meta-orchestrator-checkpoint` in closure-variant mode.

Closure summary (subset of handoff schema; see `meta-orchestrator-checkpoint/01-handoff-payload-schema.md`):

- Per-stream merged PR with URL
- Accumulated goal-2 design notes (insights this mission surfaced about the orchestration pattern itself)
- Parameterization-calibration data (which heuristics needed tuning; which thresholds proved correct)
- Deferred follow-up items with rationale for deferral

Master surfaces closure summary to user. Mission closes.

## Failure modes the architecture handles

- *Pair stall.* WO hits an unresolvable blocker (e.g., external service unavailable). AC surfaces under condition 1 of the five-condition protocol. Master rebalances (other streams continue) or escalates to user for unblock.
- *Stream collision discovered at integration.* File sets that were verified disjoint at decomposition turn out to conflict at integration (e.g., due to a discovered shared dependency). The conflict-detection trigger fires (failed clean rebase onto current main). Master halts the conflicting stream's elevation; surfaces to user for sequencing decision; integrates per user's chosen order.
- *Wrong-layer routing.* User issues an operational directive directly to master (in the conversation channel) when it should have been routed to a stream's AC. Master applies the wrong-layer routing companion rule: routes to AC with explicit framing ("user-said-X, master-routes-to-stream-α-AC-because-this-is-operational-territory, with bounds Y"). Master acknowledges the routing to the user so they can correct cheaply if they meant master to act directly.
- *User supersession in N greater than 1.* User changes their mind mid-mission. Master applies precedence rule plus enumerate-affected-streams procedure from `01-discipline-and-cycle-patterns.md`. Master surfaces supersession-marking to each affected pair; unaffected pairs continue; master synchronizes dependency map; master surfaces consolidated state-sync to user.

## Cycle and phase recap

The exemplar covers a typical mission shape. Real missions vary in N, stream-novelty distribution, and depth of cross-stream dependency. The skill's protocol absorbs the variation; the exemplar shows the load-bearing transitions concretely.

Single-stream missions (N=1) are the degenerate case: skip cross-stream coordination steps; everything else applies identically.
