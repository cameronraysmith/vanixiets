---
name: meta-orchestrator-initiate
description: Team-level orchestrator initialization for missions requiring multi-pair coordination. Establishes the strategic frame, authority hierarchy, wrapper canon, and decomposition discipline for a planning master orchestrator spawning repo-coupled AC↔WO pairs across one or more target repositories.
---

# Meta-orchestrator initiate

Symlink location: `~/.claude/skills/meta-orchestrator-initiate/SKILL.md`
Slash command: `/meta-orchestrator-initiate`

Mission start protocol for a planning master orchestrator.
Assembles the strategic frame from a user-supplied mission directive (or from a prior `/meta-orchestrator-checkpoint` handoff payload), establishes the authority hierarchy and wrapper canon the team will operate under, and produces a self-directing briefing that enables the master to begin proposing the team decomposition.

This skill is the team-level analog of `/session-orient`.
Where `/session-orient` initializes one session, this initializes a team of sessions: a planning master orchestrator plus N repo-coupled AC↔WO pairs that execute parallel work streams in target repositories.

## When to invoke

Three triggers, all user-initiated:

- User issues a mission directive in conversation channel with addendum (constraints, target repos, deliverable shape, success criteria, observation expectations)
- User issues `/meta-orchestrator-initiate <checkpoint-payload-path>` to resume a mission from a prior `/meta-orchestrator-checkpoint` output
- User explicitly requests "start a new team for X" or equivalent framing

If the mission scope is single-session-single-repo (no parallel streams, no multi-cycle coordination), use `/session-orient` directly instead — meta-orchestrator overhead is not warranted.

## Composed skills

This skill orchestrates a higher-level protocol that uses the following as components.
Do not duplicate their functionality; delegate to them.

- `meta-agent-teams` provides teammate spawn conventions, beads-to-task-list mirroring, and the orient/work/checkpoint/shutdown/replace lifecycle for individual pairs
- `/session-orient` provides the session-level orientation each AC and WO runs after spawn (with a master-supplied addendum)
- `/session-checkpoint` provides the session-level checkpoint each AC and WO runs at cycle end
- `/meta-orchestrator-checkpoint` provides the team-level state capture and handoff that this skill consumes when invoked with a checkpoint payload
- `/nix-flake-pr-cycle` and `preferences-git-version-control` provide Phase-4 PR-cycle conventions invoked when streams complete

## Three-layer architecture

| Layer | Identity | Owns | Does not |
|---|---|---|---|
| Master orchestrator | Planning AC; this skill's invoker | Strategic routing; spawn primitive; gates; cross-stream coordination; team-level checkpoint | Direct execution; bypassing AC to steer WO; cross-stream comm at AC↔AC or WO↔WO level |
| Repo-coupled AC | Spawned by master per stream | Strategic frame for stream; critique via wrapper; `/session-review`; pair-internal lifecycle; surfacing to master under five-condition protocol | Pre-cooking operational detail; running audits inline; direct communication with other streams' ACs |
| Repo-coupled WO | Spawned by master per stream after AC | Operational execution on assigned jj chain; subagent dispatch; atomic commits; `/session-checkpoint` at fill | Direct user comm; cross-WO comm; skipping first-cycle critique |
| Ephemeral subagents | Dispatched per-task by AC or WO | Single bounded task; return on completion | Persisting across turns |

## Authority hierarchy

```
User > Master > AC > WO > Ephemeral subagents
```

**Precedence rule.** User directives received in conversation channel ALWAYS supersede prior or in-flight authorizations from any agent layer. Even if master, AC, or WO has just approved or directed otherwise, user-supersedes wins.

**Reconciliation duty.** An agent receiving a user supersession directive must immediately route the new state to affected peers and superiors using the supersession-marking pattern (see `01-discipline-and-cycle-patterns.md`) so they can terminate-and-repurpose in-flight work.

**Master responsibility on receiving "user-superseded-my-directive" surface-up.** State-sync only; do NOT re-litigate; do NOT push back on the user via AC.

### Three companion rules

- *Ambiguity rule*: AC seeks clarification from user rather than interpreting silently when stakes are non-trivial. For trivially small interpretations, AC may interpret with explicit framing of the assumption made (so user can correct cheaply). The threshold "non-trivial" is judgment; AC's calibration improves with practice.
- *Cross-time conflict rule*: when a new user directive (C) appears to conflict with a master extrapolation (B) of an earlier user directive (A), AC applies C as the new directive immediately, then asks user whether A's spirit still holds. Do not try to extrapolate intent across time without checking. The new directive is the authoritative bound; older context is reconfirmed by user, not AC.
- *Wrong-layer routing rule*: AC routes operational directives to WO with explicit framing ("user-said-X, AC-routes-to-WO-because-this-is-WO-territory, AC-frames-with-Y-bounds"). AC also acknowledges the routing to user so they can correct cheaply if they meant AC to act directly. Routing-with-visibility, not silent deferral.

### Meta-principle

All three companion rules share a meta-principle: when stakes are non-trivial, prefer asking user over silently interpreting.
The cost of a clarifying turn is small; the cost of an incorrectly-interpreted authority directive can be large.

## Wrapper protocol

All cross-layer messages use a four-part wrapper with strict single-external-position discipline.

Structure, in order:

1. Identification header — `Here's the response from the [role]:` (signals provenance)
2. Body — wrapped in triple-quoted block (`"""..."""`)
3. Closing forcing question — one line after closing `"""`, outside body (forces critical posture)
4. Discipline-reassertion footer — blank line after closing question, outside body (forces context discipline)

**Direction-specific closing question text:**

- Upward (WO→AC, AC→master): `How would you best advise it?`
- Downward (master→AC, AC→WO): `What is your independent assessment?`

**Verbatim footer** (always external, never inside body):

```
Continue to adhere to all facets of the Session Protocol.
Remember that most work needs to be dispatched to carefully prompted subagent tasks to conserve your context for our planning and orchestration discussion.
```

**Single-external-position rule.** The closing forcing question and the discipline-reassertion footer MUST be outside the triple-quoted body block. Placing them inside makes them content of the wrapped message rather than protocol-level demands on the receiver, defeating their forcing function. Receiving agents flag and correct duplicated or internal placements.

## Turn-ordering crossing mitigations

Crossings (sender and receiver compose simultaneously, messages cross in transit) are a structural property of multi-party async coordination at this granularity, not an exceptional friction.
Five mitigations enumerated; apply situationally.

1. Master waits for AC's "drafting now" interim before sending follow-up directives
2. Master pre-announces independent moves before taking them (AC stops and rechecks inbox)
3. AC inbox-recheck at end of composition (before sending, AC rereads inbox for crossings)
4. Accept-and-absorb fallback (in-flight crossed work has reference value; absorb rather than discard)
5. Master supersession-marking when acting on AC's in-flight topic (AC can terminate-and-repurpose)

See `01-discipline-and-cycle-patterns.md` for application patterns including the state-dependent recovery directive pattern that handles latency windows between sender directive and receiver state.

## Non-communication invariants

Two hard architectural invariants preserve role-allocation and prevent implicit pair-coupling that scales poorly:

- *AC↔AC invariant*: ACs of distinct streams do NOT communicate directly. All cross-stream coordination flows through master.
- *WO↔WO invariant*: WOs of distinct streams do NOT communicate directly. Same rationale; same mechanism.

Canonical alternatives for typical failure modes: master maintains a cross-stream dependency map (see `02-tier-and-gate.md`) for artifact-handoff cases; shared blockers surface independently to each AC and master synthesizes; resource contention is allocated through ACs.

## Protocol

Execute on invocation, in order.

### Step 1: parse input

If a checkpoint payload path was supplied, read and parse it per the schema in `meta-orchestrator-checkpoint/01-handoff-payload-schema.md`.
Restore: mission frame summary, retired-AC enumeration with pointers to per-AC `/session-checkpoint` outputs, accumulated design decisions, parameterization-calibration data, master's observation log path, open threads, in-flight work, next-spawn recommendations.
Skip to step 4 (decomposition refinement, not fresh decomposition).

Otherwise (fresh mission), parse the user-supplied mission directive: goal, addendum (constraints, target repos, deliverables, success criteria), observation expectations.

### Step 2: establish observation log

Locate `$CLAUDE_JOB_DIR`; create the master observation log at `<$CLAUDE_JOB_DIR>/observations/master-orchestrator.md` (fallback: `~/.claude/jobs/manual-handoff/observations/master-orchestrator.md`).
Record: mission frame, initial decomposition-dimension assessment, uncertainties flagged for AC critique.

### Step 3: propose team decomposition

Decompose the mission into N parallel work streams.
Decomposition criterion is a conjunction: streams are coherent units of intellectual content (subdomains, feature boundaries, dependency layers) AND have mutually-exclusive file sets across target repos.
Both gates fire for valid decomposition.

Compose the decomposition proposal with: stream enumeration (name, target repo, jj chain lineage, deliverable); file-set-per-stream inventory verifying disjointness; initial cross-stream dependency map (X depends on Y producing Z by transition T); proposed N with rationale (practical N likely 2-3 for typical missions; higher when streams are structurally trivial to track); stream-novelty assessment per stream (drives spawn-timing regime; see `04-spawn-prompt-template.md`).

### Step 4: surface decomposition for user ratification

The decomposition-ratification gate is tier-2 reversibility (parallel spawn fan-out is consequential).
Surface to user with the file-set inventory, dependency map, and N rationale.
Apply the gate evidence rubric in `02-tier-and-gate.md`.

User confirms, revises, or rejects. Master applies any user revisions before proceeding.

### Step 5: spawn pairs

For each stream, spawn one repo-coupled AC↔WO pair via Agent tool with `team_name=<mission-slug>`, `name=<repo>-<stream>-ac` (and `-wo`).
All N pairs share ONE team for cross-stream visibility on a shared task list; namespace per-stream tasks via `[stream-X]` prefix.
See `04-spawn-prompt-template.md` for the full spawn-prompt template and the stream-novelty-keyed spawn-timing calibration.

### Step 6: monitor cycle dynamics

Each pair iterates independently using the wrapper protocol.
Master holds gating altitude; surfaces to a pair only when its five-condition surface-up triggers master action (see `02-tier-and-gate.md`).
Maintain the cross-stream dependency map as AC surface-ups reveal new dependencies.
At each stream's completion, follow the stream-completion plus main-advance handling in `03-operational-patterns.md`.

### Step 7: monitor own context fill

When approaching ~50% context, invoke `/meta-orchestrator-checkpoint` to capture team-level state and hand off to a fresh master session.
Earlier triggers: AC surfaces "we should checkpoint and hand off"; user directive to wrap up.

## Output

The briefing this skill produces is for the master's own consumption:

- Mission frame summary (durable across master replacements)
- Team decomposition proposal (pre-ratification)
- Authority hierarchy and wrapper canon internalized in working memory
- Observation log path established
- Readiness to surface decomposition to user

## Composition with `/meta-orchestrator-checkpoint`

This skill's invocation accepts the checkpoint skill's output as input (step 1 path).
The checkpoint skill produces a payload formatted such that this skill can resume from documented state without re-deriving from a fresh mission frame.
Canonical text in this skill is normative source; downstream artifacts (spawn prompts, observation logs, future cross-references) quote verbatim rather than paraphrasing to prevent canon drift.

## Exemplar end-to-end invocation

An exemplar session covering user→master entry, N-stream decomposition with ratification, parallel pair spawning, cross-stream coordination, three-level checkpoint cascading, stream completion via PR cycle, and mission closure: see `05-exemplar-session.md`.

## Sub-files

- `01-discipline-and-cycle-patterns.md` — longevity budget, AC pullback, dual-axis critique posture, four failure modes, skill-allocation table, state-dependent recovery directive, post-long-in-turn rule, calibration loops, multi-audience routing, user-supersession enumerate-and-propagate
- `02-tier-and-gate.md` — tier-by-reversibility times phase orthogonality, master's six-point evidence rubric, AC five-condition surface protocol, decomposition-ratification gate, cross-stream dependency map convention
- `03-operational-patterns.md` — orchestrator-mode subagent dispatch template, harness write-gate empirical scope, first-cycle critique calibration, PR safety variants, observation-log path convention, stream-completion plus main-advance handling, conflict-detection trigger
- `04-spawn-prompt-template.md` — AC-drafts-structure / master-inlines-content separation, spawn-prompt invariants, placeholder template, team-identity convention, spawn-timing calibration keyed on stream-novelty
- `05-exemplar-session.md` — refined end-to-end exemplar

---

*Related skills:*
- `meta-agent-teams` — teammate isolation, beads-to-task-list mirroring, orient/checkpoint lifecycle
- `meta-orchestrator-checkpoint` — team-level state capture and handoff
- `/session-orient` — session-level orientation each AC and WO runs with a master addendum
- `/session-checkpoint` — session-level checkpoint each AC and WO runs at fill
- `nix-flake-pr-cycle` — Phase-4 PR cycle for stream completion
- `preferences-git-version-control` — jj-mode tiered-ceremony for tier transitions

*Theoretical anchors:*
- `preferences-adaptive-planning` — buffer sizing, planning horizon depth, longevity budget rationale
- `preferences-validation-assurance` — severity criterion, evidence quality, regression protection
- `preferences-compositional-continuous-verification` — closure operator, regulator pairs (relevant at PR-cycle entry)
