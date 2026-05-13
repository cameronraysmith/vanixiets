# Tier and gate

Gate discipline for the orchestration lifecycle.
Load when evaluating a gate transition (tier elevation, decomposition ratification, stream completion), when AC is considering whether to surface to master, or when master is composing the cross-stream dependency map.

## Tier-by-reversibility times phase orthogonality

Tier and phase are orthogonal axes.
Tier names action reversibility; phase names workflow position.
Stakeholder gates align with tier transitions, not phase transitions.

*Tier-by-reversibility axis:*

- *Tier 1*: anonymous jj `@` chain. Fully reversible (no remote impact, no public visibility). Default operating tier for WO implementation work.
- *Tier 2*: bookmarked branch with draft PR pushed. Semi-reversible (public-visible but title-and-body amendable; remote can be deleted-and-recreated cheaply). Entered at stream-completion readiness.
- *Tier 3*: merged to main. Irreversible (revert is a new commit, not undo). Entered at user authorization of PR-cycle completion.

*Phase axis:*

- *Phase 1*: planning (decomposition, mission frame, strategic alignment)
- *Phase 2*: implementation (commits land on tier-1 chain)
- *Phase 3*: review (audit, verification, gap closure)
- *Phase 4*: integration (PR cycle, buildbot, ready transition, merge)

*Orthogonality:* Phase 2 produces tier-1 commits; Phase 4 PR-cycle entry crosses tier-1 to tier-2; merge crosses tier-2 to tier-3. Phase determines what work is happening; tier determines who must authorize the next action.

| | Phase 1 (planning) | Phase 2 (implementation) | Phase 3 (review) | Phase 4 (integration) |
|---|---|---|---|---|
| Tier 1 | AC-internal | AC-internal | AC-internal | (transitions out) |
| Tier 2 | (not applicable) | (not applicable) | (not applicable) | Master-may-gate, may surface to user |
| Tier 3 | (not applicable) | (not applicable) | (not applicable) | User-gated always |

## Master's six-point evidence rubric

Master's pre-set evidence rubric for evaluating tier-2 elevation readiness when AC surfaces a stream-completion proposal.
All six must pass for elevation to proceed:

1. *Implementation matches proposal.* The shipped artifact aligns with the design captured at Phase-1 decomposition (no scope creep, no silent removal).
2. *No orphaned cross-references.* Internal references between files resolve; sub-file pointers exist; canonical text matches its declared source.
3. *Reader path coherent.* The artifact's intended reader can traverse from entry point (CLAUDE.md, SKILL.md, or equivalent) to the substantive content without dead ends or undocumented assumptions.
4. *Risk flags closed.* Risks surfaced during Phase 3 review are all closed cleanly (resolved, not deferred).
5. *AC concurrence.* The AC explicitly concurs that PR-cycle entry is the right next step (not another iteration round, not a re-decomposition).
6. *Tier-1 chain intact for elevation.* The jj chain bookmarked for elevation is clean (no in-flight edits, no pending atomic commits, `@` is empty).

Failing any of the six halts elevation pending remediation. Master surfaces the failing items back to AC for resolution rather than waiving them.

## AC five-condition surface protocol

The AC binds itself to a five-condition protocol for surfacing to master.
Surfacing outside these conditions is forbidden discipline.
This is the AC's analog of the master's spawn-decision discipline: it prevents the AC from flooding the master with every status update.

The AC surfaces to master if and only if at least one condition holds:

1. *WO surface-up requires master input.* The WO has surfaced a question, blocker, or proposal that exceeds AC's adjudication authority and needs master coordination.
2. *Phase transition.* The pair is transitioning between phases (e.g., Phase 1 to Phase 2 spawn, Phase 3 to Phase 4 PR cycle).
3. *Tier-2 escalation.* The stream is ready for tier-2 elevation (push, draft PR creation).
4. *WO replacement request.* The WO has invoked `/session-checkpoint` and AC is requesting master spawn a replacement.
5. *Genuine master-bound emergence.* AC has identified a strategic concern, scope expansion candidate, or cross-stream coordination need that only master can resolve.

Routine status updates, internal WO-AC adjudication, and within-cycle critique iterations stay within the pair.

## Decomposition-ratification gate

Tier-2 reversibility gate (parallel spawn fan-out is consequential; master cannot un-spawn without cost).
Master's decomposition proposal surfaces to user with the following evidence:

- *Stream enumeration* with name, target repo, jj chain lineage, and deliverable per stream
- *File-set-per-stream inventory* — explicit list of files each stream will create or modify, verified disjoint across streams before surfacing
- *Cross-stream dependency map* (see below) — initial population at decomposition time
- *Proposed N with rationale* — practical N likely 2-3 for typical missions; higher when streams are structurally trivial to track; user cognitive ceiling is the operative bound
- *Stream-novelty assessment per stream* — drives spawn-timing regime (see `04-spawn-prompt-template.md`)
- *Pass criterion*: file-set inventory verified disjoint across all streams

User confirms, revises, or rejects. Master applies user revisions before any spawn. Proactive file-set verification at this gate is the canonical mitigation for the stream-collision failure mode that would otherwise emerge at integration time.

## Cross-stream dependency map convention

Master maintains an explicit dependency map across the mission lifecycle.
The map is populated at decomposition time and updated as AC surface-ups reveal new dependencies.

Schema (markdown table, in the master's observation log under a dedicated section):

| Source stream | Target stream | Artifact | Transition point | Status |
|---|---|---|---|---|
| stream-X | stream-Y | interface module Foo | end of Phase 2 | pending / in-flight / delivered |

The map answers: "for stream-Y to proceed past transition T, what must stream-X have produced by then?"

*Lifecycle operations:*

- *Populate at decomposition*: master derives initial dependencies from the proposal and records them.
- *Update on surface-up*: when an AC surface-up reveals a previously-unmapped dependency, master adds a row before responding.
- *Resolve at delivery*: when a source stream delivers the named artifact, master marks the row delivered and surfaces availability to the target stream's AC.
- *Replan on conflict*: if a dependency cannot be satisfied (source stream descopes the artifact, target stream changes requirements), master surfaces to user for re-decomposition rather than silently relaxing the dependency.

The map is the canonical alternative to direct AC-to-AC cross-stream communication for the artifact-handoff failure mode. The non-communication invariant in `meta-orchestrator-initiate/SKILL.md` holds; the dependency map plus master-routed coordination is what replaces direct comm.
