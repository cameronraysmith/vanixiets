# Spawn-prompt template

Spawn-prompt construction discipline for the master orchestrator.
Load when assembling a pair spawn (AC first, then WO with AC-supplied addendum), when calibrating spawn-timing regime per stream, or when recovering from a spawn-prompt failure (WO returns confused about identity or scope).

## Role separation: AC drafts, master inlines and spawns

The master orchestrator holds the spawn primitive (Agent tool with `team_name` and `name`). The repo-coupled AC does not have a spawn primitive in the team mode.

Role separation:

- *AC drafts the structural template* for the WO spawn prompt: which sections must be present, what each section must contain in skeleton form, what variables must be filled.
- *Master inlines content* into the structural template: the actual mission frame, the file paths, the proposal-specific instructions, the surfacing rules customized to this pair.
- *Master spawns* via Agent tool. AC does not round-trip the filled template back to master for review (that would consume an unnecessary AC cycle); master fills and spawns within one turn.

Rationale: preserves AC context budget for cycles ahead while keeping master as the authoritative spawn point. The two responsibilities are mechanically separable because the structural template is invariant across pairs while the content varies per stream.

## Spawn-prompt invariants

Every spawn prompt contains the following sections.
Minimum prompt length is approximately 150 lines; the structural template alone enforces this floor.

1. *Identity.* "You are a repo-coupled <role> for stream <stream-name> in mission <mission-slug>." Role is `AC` or `WO`. Establishes identity unambiguously at the top.
2. *Working directory.* Absolute path to the target repo. Instruction to verify via `pwd` and `cd` if needed as first action.
3. *Wrapper protocol both directions.* Verbatim canonical text (header / body / closing question / footer) with direction-specific closing question text. Single-external-position rule explicit. The pair will use this for all cross-layer messages.
4. *Embedded proposal.* The mission frame, the stream's scope, the deliverable, the success criteria. For ACs: includes the push-back-likelihood note as a three-audience artifact (AC self-calibration, master expectation-setting, WO awareness via this same prompt).
5. *First action.* What the role should do at session start. For ACs: `/session-advisor` then `/session-orient` with master-supplied addendum. For WOs: `/session-orient` with AC-supplied addendum, then audit the target repo's state.
6. *Execution constraints.* What the role is and is not allowed to do. For ACs: critique posture, pullback discipline, no operational pre-cooking. For WOs: subagent-dispatch for in-repo writes, atomic commits, no direct user comm.
7. *Surfacing protocol.* When and how to surface to the next layer up. For ACs: five-condition protocol. For WOs: group-boundary surfaces, exception surfaces, first-cycle calibration.
8. *Observation logging.* Path convention for the role's observation log; what to record; append-only discipline.
9. *Tool discipline.* What tools to use for what (Read for files, Bash for shell, Agent for subagent dispatch, Write/Edit gated by harness; subagent dispatch for in-repo writes).
10. *Bootstrap order.* Numbered sequence of first actions, terminating in "surface initial response/state to <next-layer>".

The spawn-prompt template provides explicit placeholders for each section. ACs fill the structural template; master inlines content; the filled prompt is self-contained at spawn time.

Master routing of multi-stream work into the shared development join uses the append-route for new commits and the amend-route for fixups, both documented in jj-version-control/SKILL.md §"Routing to a chain: append vs amend"; the spawn template does not restate the route mechanics inline.

## Placeholder template

```
You are a repo-coupled <ROLE> for stream <STREAM-NAME> in mission <MISSION-SLUG>.

# Working directory

Your target repo is <ABSOLUTE-PATH-TO-REPO>. Confirm via `pwd`; `cd` if needed.

# Wrapper protocol

All cross-layer messages use the four-part wrapper with strict single-external-position discipline. (Verbatim canonical text inlined here, from meta-orchestrator-initiate SKILL.md.)

Direction-specific closing question text:
- Upward: How would you best advise it?
- Downward: What is your independent assessment?

Footer text (always external):
- (Two-line Session Protocol reminder, verbatim.)

# Mission frame

<MISSION-FRAME-NARRATIVE>

# Stream scope

<STREAM-SCOPE-NARRATIVE>

# Deliverable and success criteria

<DELIVERABLE-AND-SUCCESS-NARRATIVE>

# Push-back-likelihood note (for AC role) / Awareness note (for WO role)

<RANK-ORDERED-LIST-OF-EXPECTED-PUSH-BACK-POINTS-WITH-REASONING>

# First action

<ROLE-SPECIFIC-BOOTSTRAP-SEQUENCE>

# Execution constraints

<ROLE-SPECIFIC-CONSTRAINTS>

# Surfacing protocol

<ROLE-SPECIFIC-SURFACE-CONDITIONS>

# Observation logging

Your observation log: ${CLAUDE_JOB_DIR}/observations/<ROLE-OBS-LOG>.md (fallback ~/.claude/jobs/manual-handoff/observations/<ROLE-OBS-LOG>.md). Append-only. Record: friction points, parameterization candidates, calibration data, decisions, unexpected state.

# Tool discipline

<ROLE-SPECIFIC-TOOL-DISCIPLINE>

# Bootstrap order

1. ...
2. ...
N. Surface initial response/state to <NEXT-LAYER-UP>.
```

## Team-identity convention

Per the `meta-agent-teams` skill: teams correspond 1:1 with shared task lists.

For N-stream missions:

- *One team per mission.* All N pairs share a single team named `<mission-slug>` (e.g., `vanixiets-vcs-refactor`). The shared task list is the cross-stream coordination substrate.
- *Pair naming.* `<repo>-<stream>-ac` and `<repo>-<stream>-wo` (e.g., `vanixiets-ac`, `vanixiets-wo` for a single-stream mission; `ironstar-todo-ac`, `ironstar-todo-wo`, `ironstar-analytics-ac`, `ironstar-analytics-wo` for a two-stream mission in ironstar).
- *Task namespacing.* Pair-internal tasks created in the shared task list are subject-prefixed with `[stream-X]` so cross-stream visibility is preserved while pair scope remains identifiable.

Master's cross-stream coordination tasks (dependency-map maintenance, cross-stream artifact handoff tracking, mission-level checkpoint reminders) live in the shared list without a stream prefix.

For N-stream missions, all streams' chains parent into one development join with a single `[wip]` commit on top; sibling chains directly off main are out of scope absent affirmative justification at the decomposition-ratification gate.
See jj-version-control/SKILL.md §"Development join" for the entity definition.

Every editor on that join — each WO, each dispatched subagent — writes the same empty `[wip]` at `@`, which is the shared coordination surface that makes the concurrent streams safe by construction.
Keep `@` empty and route completed content downward into the owning chain; never `jj describe @` into content and never relocate `@` with a positional `jj rebase -r @`, either of which dissolves the surface the other streams are concurrently writing.
See jj-version-control/SKILL.md invariant (iii-b)/(vi) for the canonical statement and the editor-safe routing-down command templates.

## Spawn-timing calibration: keyed on stream-novelty

Stream-novelty is the load-bearing axis for spawn-timing choice, not speed.
Master self-assesses stream-novelty before spawning each pair.

Two regimes:

- *High-novelty regime.* Master has NOT internalized a re-usable strategic frame for this kind of stream. AC-drafts-structure-first is mandatory. Master inlines content into AC's structural template, then spawns WO. AC drafts strategic frame from scratch for the pair.
- *Low-novelty regime.* Master HAS internalized a re-usable strategic frame for this kind of stream (e.g., "apply convention X across these 5 repos" where convention X is well-understood). Master may pre-spawn WO from a master-held template. AC ratifies post-spawn and may push back if novelty was undercounted.

Novelty assessment (explicit master self-check before choosing path):

- *Do I have a re-usable template for this stream?* If yes, low-novelty path eligible. If no, high-novelty path is the only safe choice.
- *Is the strategic frame fully internalized?* If yes, low-novelty path eligible. If no, AC's strategic-frame drafting is the load-bearing step that cannot be skipped.

Failsafe: AC's post-spawn ratification in the low-novelty regime catches under-counted novelty. If AC pushes back ("this stream is higher-novelty than the template assumed"), master switches the pair to the high-novelty path retroactively (AC drafts revised strategic frame; master applies as orient addendum to the already-spawned WO via wrapper).

The calibration is keyed on the master's internalization state, not the apparent stream complexity. A "simple" stream the master has not done before is still high-novelty; a "complex" stream that fits a template the master has used three times is low-novelty.
