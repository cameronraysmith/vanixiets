## Context

This change builds three agent skills that compose, rather than duplicate, the work-decomposition surfaces already present in this workspace: Linear, beads, OpenSpec plus the superpowers-bridge, the session-* skills, and Claude Code Workflows.
Research surfaced that the single largest duplication hazard is the issue/task layer, where Linear, beads, and OpenSpec tasks.md all compete to own the work-item ledger.

The overriding user decision is an ownership-by-layer spine: Linear and OpenSpec own the work, and beads is demoted to an optional, local, fine-grained execution sublayer that sits below the OpenSpec requirements document.
Linear holds the business "what" and the team-visible status surface (Initiatives, Projects, Cycles, parent issues); the Linear issue body carries only a TL;DR, Deliverables, and Acceptance Criteria, with status and progress in fields and comments, never the body.
OpenSpec plus the superpowers-bridge hold the spec-first change lifecycle, the human-interpretable requirements document, and the within-change task decomposition in tasks.md; OpenSpec is the primary technical owner of the decomposition.
beads is invoked by local agent execution only when a complex task needs finer-grained tracking than the spec should carry, so the spec stays human-interpretable, and it remains load-bearing in Manual mode via the /session-orient → /session-checkpoint loop.

The environment is jj-mode (colocated jujutsu), where worktree-creating tool surfaces are hook-blocked, the Linear MCP is disabled, and linear-cli credentials are nix-managed and immutable, rendered into a read-only (0400) inline credentials.toml (an OS-keyring mode is supported but not in use).
This change is itself built in HIL mode through the superpowers-bridge as a dogfooded correctness test, so any friction discovered while authoring these artifacts is itself evidence about the lifecycle.

## Goals / Non-Goals

**Goals:**

Establish three skills that compose existing surfaces by delegation: a Claude-Code-only state-machine router, an agent-general project-management hub, and an agent-general linear-cli-driven Linear↔OpenSpec sync overlay.
Make the Linear-story↔OpenSpec-change binding the primary cross-reference, stored in the change's proposal.md frontmatter (linear_story_*, linear_team, linear_project) and resolved against the openspec/linear.yaml monorepo registry, and bind technical status roll-up to four forward lifecycle transitions plus a re-queue and two terminal exits.
Specify a minimal per-change sync ledger in proposal.md frontmatter (HIL-only; AFK keeps counter and attempt-log equivalents in its plan file, Manual carries none) as the authoritative current-phase signal and the home of idempotency, the bounded-retries counter, and a best-effort-write attempt log.
Encode the Linear workspace safety gate as the hardest constraint, keyed on confirmed credentials rather than on LINEAR_WORKSPACE.
Give the Linear-canonical board a documented termination guarantee via a bounded-retries policy escalating to the human PM layer.

**Non-Goals:**

Do not modify or retire any existing /session-* skill, and do not resolve the session-advisor↔router routing overlap (deferred follow-up).
Do not touch the planning-repo contexts/*.md → CLAUDE.md symlink mechanism.
Do not sync this dogfood change to a real Linear story; a real workspace mutation is out of scope.
Do not mechanize execution-mode selection via a Linear label; mode selection stays a per-issue human decision.
Do not build a fourth agent for the In-Review sub-gates; roborev and documenter are abstract gate tasks composed by delegation, not new deliverables.
Do not copy the Linear Method or CCPM text, and do not adopt CCPM's .claude/prds + .claude/epics filesystem or its bash scripts.
Do not resolve the apply-phase jj-versus-worktree reconciliation here; it is confirmed at the apply gate.

## Decisions

### D1: three deliverables with src/core versus src/claude placement

Choice: build three skills with placement following the house nix-discovery convention.
The router lands at `modules/home/ai/skills/src/claude/agentic-planning-development-workflow/` because it depends on Claude-Code-only orchestration surfaces (slash commands, Task/subagent dispatch, Claude Code Workflows); src/claude is appended only to Claude Code.
The PM hub lands at `modules/home/ai/skills/src/core/project-management/` and the sync overlay at `modules/home/ai/skills/src/core/openspec-linear-sync/`; both are agent-general, and src/core flows to all agents.
Each directory is auto-discovered by `readSkillsFrom` in `modules/home/ai/skills/default.nix`; no manual nix registration is needed.

All three reference trees are one level deep, per the agentskills spec ("Keep file references one level deep from SKILL.md", specification.mdx:235) and the house precedent that no existing skill nests references two levels.
The PM hub's four sub-areas (linear, github, beads, method) are expressed as filename prefixes within a single flat references/ directory and presented via a Contents table grouped by prefix, not as nested subdirectories.

The concrete trees:

```
src/claude/agentic-planning-development-workflow/
  SKILL.md                          (the router; lean index + Contents table)
  references/
    execution-modes.md              (AFK/HIL/Manual entry criteria, per-mode authoritative ledger)
    board-and-gates.md              (Linear-canonical states, one gate per forward transition, In-Review sub-gates, re-queue, bounded-retries, router walkthrough)
    hil-isolation.md                (jj diamond development join as worktree substitute; CLAUDE_JJ_WORKSPACE_ISOLATION hatch)
    delegation.md                   (roborev/documenter abstract gates, mode-agnostic; AFK handoff act)
    board-state-machine.mermaid     (stateDiagram-v2 rendering of the board, transitions, mode fork, sub-gates, re-queue, inert terminals)
    codex-review.md                 (the roborev sub-gate binding: inline codex review runbook, diamond-safe range, advisory verdict, panel mode)
    collaborators.md                (the four-collaborator ownership map: PM hub, this router, the opsx+superpowers-bridge flow, openspec-linear-sync)

src/core/project-management/
  SKILL.md                          (human-facing PM hub; lean index + Contents table grouped by prefix)
  references/
    linear-overview.md              (Initiative > Project > Milestone > Issue; Cycles as overlay)
    linear-workspace-safety-gate.md (the hardest constraint; auth whoami gate)
    linear-conventions.md           (issue-body TL;DR/Deliverables/Acceptance; SYNC/NOSYNC markers; sizing)
    github-overview.md              (PR/buildbot/Mergify surface; PR as one realization of terminal artifact)
    beads-overview.md               (optional local drill-down sublayer; Manual-mode task ledger)
    method-overview.md              (synthesized Linear Method + CCPM principles, no copied text)

src/core/openspec-linear-sync/
  SKILL.md                          (linear-cli-driven Linear↔OpenSpec lifecycle overlay; lean index + Contents table)
  references/
    lifecycle.md                    (four forward transitions + re-queue + terminal exits, gates, invariants, archive ordering)
    linear-cli-mapping.md           (per-phase verb mapping; document UPSERT recipe; api fallback; end-to-end worked example)
    config-and-frontmatter.md       (openspec/linear.yaml monorepo registry; proposal.md linear_story_*/linear_team/linear_project + per-change D10 sync ledger)
```

Each SKILL.md is committed to the lean-index plus Contents-table form mirroring preferences-git-version-control, kept under roughly 350 lines, with operational detail pushed to the references leaves.
The subfile cuts follow progressive disclosure: the router splits along the axes a reader needs in sequence (which mode, what the board does, how isolation works under jj, what the shared gates are), the hub splits along the four PM sub-areas a human consults independently, and the sync overlay splits along the binding's mechanics (lifecycle invariants, the CLI verb surface, the persisted state).

The three SKILL.md descriptions carry explicit "Load when" triggers in house frontmatter form, written for keyword non-overlap as a skill-quality discipline:

- router: "State-machine router across a Linear-canonical board with an AFK/HIL/Manual execution-mode fork. Load when selecting an execution mode for a change, driving the agentic planning-and-development board, or routing a change between board states." Keywords avoid the session-advisor routing vocabulary (it owns beads-graph-metric routing), the issues-beads vocabulary (issue tracking), and the linear-cli skill vocabulary (Linear verbs).
- PM hub: "Human-facing project-management hub for the Linear Method ontology, conventions, and the workspace safety gate. Load when reasoning about project/issue structure, Linear conventions, or how OpenSpec, beads, and GitHub relate as PM layers." Keywords avoid routing and avoid raw Linear CLI verbs.
- sync overlay: "linear-cli-driven Linear↔OpenSpec lifecycle sync. Load when binding a Linear story to an OpenSpec change, mirroring lifecycle phase to Linear state, or running the archive-time document upsert." Keywords avoid project-management ontology and avoid mode-routing.

Trigger non-collision against session-advisor (routing), issues-beads (issue tracking), and the bundled linear-cli skill (Linear verbs) is a self-imposed, human-adjudicated skill-quality gate with no machine enforcement.
The bridge's verify check 6 is the `docs/superpowers/specs/*.md` output-routing leak detector (it passes trivially here because this change writes no such files); it does not enforce SKILL.md "Load when" trigger non-overlap.
The trigger-comparison verdict is recorded explicitly as a verification step in tasks.md so a reviewer sees the comparison was performed.

Rationale: the three-way split matches the ownership spine (router orchestrates, hub documents the human-facing model, overlay binds Linear to OpenSpec) and the placement convention keeps the router's Claude-Code dependency from leaking to other agents.
Alternatives considered: a single combined skill (rejected — conflates orchestration with documentation and forces src/claude placement on agent-general content); folding the router into session-advisor (rejected — that is the deferred follow-up, and a premature merge would entangle two routing surfaces); two-level reference nesting for the hub's sub-areas (rejected — against the agentskills spec and without house precedent).

### D2: ownership-by-layer with a mode-conditioned task ledger

Choice: assign one owner per layer and select the authoritative task ledger by execution mode.
Linear owns the business "what" and coarse parent-issue status; OpenSpec tasks.md owns the within-change decomposition; beads owns the local dependency graph and the Manual-mode task ledger.
In HIL the OpenSpec tasks.md is the authoritative task ledger; in AFK the workflow/superpowers plan checkboxes are authoritative; in Manual the beads /session-orient → /session-checkpoint loop is the ledger.
Do not create a parallel beads task list in HIL or AFK; at most map the beads issue id to the OpenSpec change id or superpowers plan path for traceability.

A concrete per-mode cross-reference mapping pins the binding locations:

| Execution mode | Linear story id | OpenSpec change id | beads issue/epic id | superpowers plan path |
|---|---|---|---|---|
| HIL | proposal.md `linear_story_*`/`linear_team`/`linear_project` frontmatter (resolved against the linear.yaml registry) | the change dir name | optional traceability map in beads field | n/a (tasks.md is the ledger) |
| AFK | proposal.md `linear_story_*`/`linear_team`/`linear_project` frontmatter (resolved against the linear.yaml registry) | the change dir name | optional traceability map in beads field | the workflow/superpowers plan file (checkboxes authoritative) |
| Manual | a beads issue field (no proposal.md to hold frontmatter) | n/a (no OpenSpec change) | the beads issue/epic (authoritative ledger) | n/a |

Manual mode has no proposal.md and therefore no place to hold `linear_story_*` frontmatter, so its Linear binding lives in a beads issue field; the proposal.md-frontmatter binding plus the per-change D10 ledger are HIL-only because only HIL authors a proposal.md to hold them — AFK's binding and counter equivalents live in its plan file's metadata, and Manual's binding lives in the beads issue field — while the linear.yaml registry stays a shared monorepo index resolved across all modes.

Rationale: resolves the issue/task duplication hazard by ownership rather than by mirroring any layer into another.
Alternatives considered: beads as the single atomic-task owner with Linear holding only coarse status (the research note's beads-centric recommendation, explicitly superseded by the ownership model); bidirectional Linear↔local sync (rejected — Linear writes are best-effort and non-blocking, local stays authoritative for the "how").

### D3: primary binding is Linear story ↔ OpenSpec change, in proposal.md frontmatter resolved against the registry

Choice: the primary cross-reference binding is Linear-story to OpenSpec-change, persisted in the proposal.md frontmatter as `linear_story_*` plus `linear_team` and `linear_project` (the binding keys read by apply).
The sync skill is the write-owner of this binding: at the Backlog → Todo bind it writes `linear_story_*`, `linear_team`, and `linear_project` into proposal.md frontmatter and resolves the chosen team and project against the openspec/linear.yaml monorepo registry (workspace, defaults, teams, projects) rather than writing the binding into it.
The registry holds no per-issue binding and no flat documents map; per-project archive documents are UPSERTed into projects.<slug>.archive_documents.<capability> at archive, with <slug> resolved from `linear_project`.
apply READS the frontmatter, so write-before-read ordering is load-bearing and the sync skill's bind step must precede any apply read.
The beads-id binding applies only when a beads drill-down is actually used or in Manual mode.

`linear_project` is `Option<slug>`: `linear_team` is required (an issue always has a team) but a project is optional, mirroring Linear.
A project-less change is a fully supported terminal state, not a degraded one: the full Backlog → Done lifecycle runs on the team board (states are team-scoped, so the lifecycle is project-independent), and the change archives cleanly with no project ever bound.
When no project is bound the `linear_project` key is omitted from frontmatter and no `projects` registry entry is created; a placeholder project or registry entry is explicitly rejected so the registry never carries fabricated structure.
The archive-time spec-document mirror is gated on `linear_project` presence: when absent, the UPSERT is skipped and recorded as a dropped best-effort write in the attempt_log (the same graceful-degradation path as Linear being unavailable), and the canonical `openspec/specs/` stay the source of truth.

Rationale: a stable, agent-readable frontmatter link survives across the lifecycle and lets apply read the bound story without re-querying Linear, while the registry stays a normalized monorepo index that many concurrent changes across different teams and projects resolve against.
Alternatives considered: a branch-name-as-binding convention keyed to beads ids (CCPM prior art; rejected as the primary binding because Linear and OpenSpec own the work, though it remains available for the beads drill-down case).

### D4: router composes by delegation, never re-implements

Choice: the router is a thin mode-selector that dispatches and never re-implements orient, plan, review, or checkpoint.
AFK hands off to the Claude Code Workflows feature and tracks via its plan checkboxes; HIL delegates to opsx:* plus superpowers via the bridge; Manual is a pass-through to /session-orient → /session-plan → /session-review → /session-checkpoint.
session-advisor stays standalone and the router references it as the Manual-path diagnostic engine; the session-advisor↔router routing overlap is a deferred follow-up.

In Manual mode the router is a pass-through to /session-orient, which routes via session-advisor and the stigmergic signal table; the router itself does not read beads graph metrics or the signal table, preserving the no-parallel-surface boundary.

roborev and documenter are mode-agnostic gate tasks the router presents downstream of all three execution modes, both rejecting into the shared re-queue (see D5); they are abstract gates, not built agents, and live in references/delegation.md because they are mode-agnostic while the modes are per-mode (references/execution-modes.md).

Rationale: honors the standing extend-not-parallel discipline and the in-skill delegation contracts that session-orient and session-checkpoint already declare; the session skills are an in-place Viable System Model state machine the router must select among, not duplicate.
Alternatives considered: absorbing session-advisor's graph-metric heuristics into the router now (deferred — a separate advisory skill alongside the router risks a parallel routing surface, but resolving it is out of scope for this change).

### D5: the Linear-canonical board, its gates, and the bounded-retries termination policy

Choice: a forge-agnostic board re-cast onto Linear's canonical states (Backlog → Todo → In Progress → In Review → Done, plus the inert terminals Canceled and Duplicate) with exactly one transition-firing condition per forward transition.
The draft board's Ready unifies into Todo, and the draft board's Review and Document both unify into the single In Review state, with roborev and documenter as the two ordered sub-gates inside In Review (roborev for code review first, then documenter for docs/handbook review).

The unified model has four forward transitions, each named by its transition rather than by an ordinal:

- The readiness gate fires Backlog → Todo when proposal.md exists.
- The human execution-mode fork sits at the Todo → In Progress boundary: the human picks the mode per-issue (AFK/HIL/Manual) with no automatic Linear-label selection, and all three modes converge on In Review.
- The In-Review gate fires In Progress → In Review when verify.md exists.
- The archive gate fires In Review → Done when the change is archived.

Inside In Review the roborev sub-gate runs first (approved → documenter sub-gate, changes needed → re-queue) and the documenter sub-gate runs second (passes → proceed to archive, fails → re-queue); the archive step is the sole anchor that fires Done, consistent with D6's "never Done before archive."
The current execution model for both sub-gates is human-steered: a human operating the workflow orchestrator drives code review (roborev) and doc authoring/review (documenter) at each gate and supplies the verdict; the router presents the gate and routes on that verdict, it does not auto-execute review.
roborev is the code-review point linking out from the superpowers-bridge apply/verify stage; documenter is documentation authoring plus review linking out from the verify/retrospective stage.
A future extension point is recorded: automation hooks to trigger the right tools at each gate (code-review automation for roborev; doc-gen/review automation for documenter), without introducing a fourth agent.

A single shared re-queue node receives both sub-gate rejections and re-queues into In Progress above the mode fork (In Review → In Progress), so a bounced issue re-selects its execution mode.
The re-queue fires on either a verify.md Overall Decision of "(fail) FAIL" (machine-detected) or a human rejection at either sub-gate.
A bounded-retries policy (a max review-round counter with escalation to the human PM layer on exhaustion, specified in D10) gives the board a documented termination guarantee that its structure alone does not provide.
This counter-backed guarantee holds for the modes whose ledger carries the counter (HIL, and AFK where the plan file backs it); in Manual mode the human is the regulator and termination is human-judged at session-checkpoint, the fairness-assumption path named in the Rationale below rather than the counter-backed one.
Canceled and Duplicate are inert terminals reachable from any active state (a change directory removed without archive, or a change superseded by another), carrying no active work, exactly like Backlog.

The model stated once: four forward transitions, each with one transition-firing condition, with In Review internally decomposed into two ordered sub-gates whose joint approval is the precondition for archive (which fires Done).
The gate/sub-gate vocabulary is uniform across D4, D5, and D6: forward transitions are "gates" and roborev/documenter are "sub-gates."

Rationale: termination toward Done is not guaranteed by the board structure; it holds only under a fairness assumption or a bounded-retries policy.
Re-casting onto Linear's canonical states means every board state maps one-to-one onto a Linear state with none skipped, which is what makes the whole binding automatable.
The unit of work is still the forge-agnostic board and the terminal artifact is still the archived OpenSpec change; a pull request into the monorepo (including docs/handbook) is one realization of that terminal artifact, consistent with the repo's fast-forward-merge-by-default, PR-when-warranted policy.
A change with brainstorm.md but no proposal.md is still Backlog (no transition fires); board-and-gates.md states this so the brainstorm-exists-proposal-pending window is explicit.
Alternatives considered: a mechanized Linear-HIL-label feeding a PM-driver node at the execution-mode fork (rejected per Q3 — mode selection is a human decision, and the Linear seam stays a documented but non-mechanized pluggable point).

### D6: the eight-artifact bridge binds four forward Linear transitions, a re-queue, and two terminal exits

Choice: bind the eight-artifact superpowers-bridge lifecycle to Linear's canonical states via four forward transitions, the shared re-queue, and the two terminal exits, covering every Linear state with none skipped.
The four forward transitions each fire a short (≤ 2 sentence) Linear comment and are each best-effort and non-blocking:

- Proposal-phase, anchored on proposal.md creation rather than brainstorm.md creation, drives Backlog → Todo.
- Apply's first observable build act drives Todo → In Progress; the authoritative anchor is the first tasks.md `- [x]` because it is grep-detectable and survives the jj worktree substitution. using-git-worktrees and the jj-diamond act are fallback heuristics only.
- verify.md creation drives In Progress → In Review.
- The archive step (openspec archive succeeding) drives In Review → Done.

The re-queue In Review → In Progress fires on a verify.md Overall Decision of "(fail) FAIL" or a sub-gate human rejection; it is the board's shared re-queue node, governed by the bounded-retries policy with escalation to the human PM layer on exhaustion.
The two terminal exits to Canceled (a change directory removed without archive) and Duplicate (a change superseded by another) are reachable from any active state and are best-effort and human-driven.

The four forward anchors are all observable file milestones (proposal.md, the first tasks.md `- [x]`, verify.md, the archived change directory), which is why the whole binding is automatable and best-effort.
The In Progress → In Review transition anchored on verify.md is the best-grounded of the four, because verify.md is one of the two signals machine-enforced in the bridge PRECHECKs.

Every transition resolves and passes the team's Linear state NAME (e.g. "In Review") via linear-cli, never the workflow-state type, because In Progress and In Review both carry workflow-state type "started" in the live workspace (verified), so keying on type would conflate the two.
references/lifecycle.md and linear-cli-mapping.md make the name-resolution rule explicit and keep the graceful-degradation branch for teams lacking an In Review state (the change stays In Progress until Done).

Invariants: never Done before archive; status, validate, sync, and edit operations must never move the issue to Done; Canceled and Duplicate are inert terminals like Backlog (no active work).
Comments stay short (≤ 2 sentences); the archive ordering is readiness → sync deltas → archive → mirror → Done.
Done binds to archive, not to the step6 PR, because the PR diff already contains the complete archived cycle and archive precedes the PR.

Rationale: only two grepped signals are machine-enforced in the bridge PRECHECKs (the tasks.md completed-checkbox count and the verify.md checked-FAIL presence), so transition detection leans on those substantive milestones rather than conventional tokens, and verify.md doubles as the In Review anchor.
The proposal.md anchor is the more substantive milestone than brainstorm.md (a transition firing before the change has a committed proposal is weaker visibility for little gain).
Alternatives considered: anchoring the Backlog → Todo transition on brainstorm.md creation (the research note's dimension-1 recommendation; rejected per the brief in favor of proposal.md); collapsing In Review into Done at archive and firing only three forward transitions (rejected — verify.md is a substantive, PRECHECK-grepped milestone that maps cleanly onto Linear's In Review state, so skipping it would leave a Linear state uncovered for no gain).

### D7: drive Linear exclusively through linear-cli, with a document UPSERT and a narrow api fallback

Choice: drive every Linear operation through the linear-cli binary and recommend against the Linear MCP (disabled in this environment).
Compose the bundled linear-cli skill for the verbs; the sync skill carries only link and sync policy.
Because linear-cli lacks `--json` on most create/update paths, capture entity ids via stdout parsing or a follow-up view, and force non-interactive automation (`issue create --no-interactive`, all required flags present, file-based content flags over inline).

The archive-time document UPSERT runs entirely via the CLI: `linear document list --project <p> --json` to find the document by the deterministic title `OpenSpec: <capability>`, then `linear document update <id> --title <t> --content-file <f>` if matched, else `linear document create --project <p> --title <t> --content-file <f>` so the document is always created already-parented.
Reserve `linear api` (GraphQL, with `linear schema -o <file>` for type discovery) only for fields the document subcommand cannot set: reparenting an existing document (document update has no --project) and reading back the structured id of a freshly created entity.
The document body is a disposable mirror fully replaced on each archive, so re-archives update rather than duplicate.

The linear-cli composition target is contributed via crs58's `aiSkills.extraSkillDirs` (user-scoped), while the sync skill lands in src/core (all agents); a src/core sync skill that another user loads would reference a linear-cli skill present only for crs58.
This is accepted because crs58 is the only operator.
The composition target is a single linear-cli/ skill directory with sixteen reference subfiles, not the per-verb subdir count the stale nix comment implies.

Rationale: linear-cli is the only viable Linear surface here, and the document subcommand covers the UPSERT path without GraphQL except for reparenting and structured id read-back.
Keep, from openspec-linearized: the ownership boundary, one-question setup with an explicit no-label option, never auto-select a Backlog candidate, archive-time-only mirroring, best-effort non-blocking writes after setup, and never copying design.md or tasks.md to Linear.
Drop: the dollar-skill syntax, the codex-only agents/openai.yaml manifest, and the MCP dependency block.
Alternatives considered: the Linear MCP (rejected — disabled in this environment); relying on `--json` for create/update (rejected — unavailable on those paths).

### D8: the Linear workspace safety gate, keyed on confirmed credentials

Choice: never propose a Linear mutation until the correct personal-versus-work workspace is confirmed via `linear auth whoami` (optionally `linear auth whoami --workspace <slug>`).
Every mutation passes an explicit `--workspace <slug>` or relies on the confirmed `credentials.toml` `default` key.
Do not key the gate on LINEAR_WORKSPACE, and never run mutating `linear auth` commands.

Rationale: the linear-cli credential precedence has five tiers — `LINEAR_API_KEY`/`api_key` (tier 1) > project-config `api_key` (tier 2) > `--workspace` flag → credentials lookup (tier 3) > `LINEAR_WORKSPACE` via `getOption("workspace")` → credentials lookup (tier 4) > `credentials.toml` default (tier 5).
LINEAR_WORKSPACE resolves at tier 4, above the credentials default but below `--workspace` and `LINEAR_API_KEY`; it is the wrong lever because it is env-overridable and silently outranked by `--workspace`/`api_key`, not because it is below the default.
The safe gate keys on `linear auth whoami` plus an explicit `--workspace`.
Credentials are nix-managed and immutable, rendered into a read-only (0400) inline credentials.toml (an OS-keyring mode is supported but not in use), so a mutating `linear auth` would be both ineffective and dangerous.
Alternatives considered: keying on LINEAR_WORKSPACE or on a project `.linear.toml` workspace config (rejected — both are env-overridable and silently outranked by `--workspace`/`LINEAR_API_KEY`).

### D9: synthesize Linear Method and CCPM; do not copy

Choice: adopt the Linear Method ontology (Initiative > Project > Milestone > Issue, with Cycles as an orthogonal scheduling overlay) as the PM hub's spine, synthesizing from the rawr-ai Linear Method package and the CCPM references rather than copying their text.
method-overview.md is a committed PM-hub sub-area (not optional) and must cover the Initiative > Project > Milestone > Issue ontology, Cycles-as-overlay, issue sizing and estimation, triage/backlog/deferral, and the SYNC/NOSYNC section markers.
Reuse Linear Method's SYNC/NOSYNC section markers so only the [SYNC] portion crosses to Linear, and borrow CCPM's branch-name-as-binding convention for the beads drill-down case.

Rationale: the ontology cleanly partitions the design space and matches the ownership spine; copying text would create maintenance drift and license entanglement.
Alternatives considered: adopting CCPM's .claude/prds + .claude/epics filesystem and bash scripts (rejected — OpenSpec changes plus beads already occupy that niche; extend, do not create parallel systems).

### D10: the local sync ledger as authoritative current-phase signal and idempotency home

Choice: specify a minimal per-change sync ledger, persisted as fields in the change's proposal.md frontmatter, recording `last_synced_state`, `last_synced_at`, a `review_round` counter, and a short `attempt_log`, with an optional per-change `max_review_rounds` override.
This single mechanism closes detection, idempotency, the bounded-retries counter, and observability.
The proposal.md-frontmatter ledger is HIL-only: only HIL authors a proposal.md to hold it, AFK tracks its bounded-retries-counter and attempt-log equivalents in its plan file's metadata, and Manual mode carries no such ledger — its lifecycle status is human-managed via the beads loop and Linear, with only the binding in a beads field.
openspec/linear.yaml is reserved for the monorepo registry (workspace, defaults, teams, projects, per-project archive documents) and holds no per-issue binding and no ledger, because a single repository's changes bind to issues across many Linear teams and projects with several changes running in parallel, so the ledger cannot live in one flat top-level block.

Authoritative current-phase signal: local milestone-file existence (proposal.md / first tasks.md `- [x]` / verify.md / the archived change directory) is the authoritative current-phase signal.
The Linear state is a best-effort projection; a catch-up reconciliation step computes local phase from the milestone files, reads the Linear state, and if they disagree fires the catch-up transition rather than assuming Linear is current.

Idempotency: each transition fires only when the resolved Linear state is strictly behind the local milestone (a no-op if already at or past the target), and each milestone comment posts at most once per crossing.
apply is routinely re-invoked (the workflow re-runs apply and verify), so idempotency is what prevents re-runs from re-firing transitions and spamming the team-visible comment surface; the openspec-linearized guarded form ("if the issue is in Todo, transition it to In Progress") is the primitive this generalizes.

Bounded-retries counter: stored as `review_round` in the change's proposal.md frontmatter (Linear writes are best-effort, so the counter must live locally), with its default ceiling in openspec/linear.yaml `defaults.max_review_rounds` (recommended default 3) which a change may override via its own frontmatter `max_review_rounds`.
It increments once per re-queue (one per In Review → In Progress crossing), resets when the change archives (forward progress past In Review), and on exhaustion the mechanical escalation action is to post a single escalation comment to the human PM layer and stop firing automatic re-queues, leaving the issue parked for human decision.

Attempt log: the ledger records dropped best-effort writes so the system can distinguish a never-attempted transition from a failed one, and a human can see that Linear is stale; the only other transition record is the Linear comment, which is exactly the surface that fails under the best-effort write model.

Rationale: detection, idempotency, the counter home, and observability all bottom out in the same missing primitive, so a single bridge-adjacent ledger designed once and referenced by lifecycle.md, board-and-gates.md, and config-and-frontmatter.md is the highest-leverage specification addition.
Alternatives considered: keying detection on the Linear state directly (rejected — best-effort writes make Linear drift by design, so it cannot be authoritative); storing the counter in Linear (rejected — Linear writes are best-effort and may be dropped, so the termination guarantee would be unsound).

### D11: re-queue resume and mid-lifecycle mode hand-off

Choice: a bounced issue is recognized as resuming, not starting fresh, by the combination of In Progress state with a verify.md "(fail) FAIL" or a recorded sub-gate rejection in the ledger's attempt log.
The rejection feedback is read from verify.md (machine-detected fail) or the ledger entry the router wrote at the human rejection.
The re-selected mode defaults to the original mode across re-queues unless the human explicitly overrides at the mode fork; keeping the original mode avoids the two-authoritative-ledger problem (an issue started AFK with plan checkboxes authoritative, bounced, then re-picked HIL with tasks.md authoritative, would have two ledgers with no reconciliation rule).
If the human does override the mode on re-queue, the cost is an explicit ledger hand-off the human accepts, noted in the attempt log.

Rationale: re-entry detection and feedback location must be operational, not just structural, so the router can resume deterministically; defaulting to the original mode keeps a single authoritative ledger per issue across re-queues.
Alternatives considered: free mode re-selection on every re-queue (rejected — produces ambiguous dual-ledger state with no reconciliation rule).

## Risks / Trade-offs

[Risk] The apply phase has a known jj incompatibility: superpowers:using-git-worktrees resolves to a raw `git worktree add` that is hook-blocked here, subagent-driven-development auto-commits, and finishing-a-development-branch opens a PR. → Mitigation: record reconciliation options as an open design point confirmed at the apply gate — the jj diamond development join as the worktree substitute, or the env-gated CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch via the skill's native-tool branch. This is input to deliverable 1's references/hil-isolation.md and to the separate jj-policy follow-up; it is not resolved in this change.

[Risk] Tri-store divergence: Linear, beads, and OpenSpec tasks.md can drift out of sync. → Mitigation: ownership-by-layer plus a mode-gated task ledger (D2) means only one ledger is authoritative per mode, and Linear holds only coarse status pushed up one-way; no layer is mirrored into another.

[Risk] Linear drifts from local under best-effort writes. → Mitigation: the local sync ledger (D10) makes local milestone-file existence authoritative, records dropped writes in the attempt log, and reconciles via the catch-up transition rather than trusting the Linear state.

[Risk] Parallel-protocol-surface creep: the router could re-implement orient/plan/review/checkpoint or a second routing surface alongside session-advisor. → Mitigation: the router's composition-by-delegation contract (D4) forbids re-implementation, the Manual path is a pass-through to /session-orient, session-advisor stays standalone, and the routing overlap is an explicit deferred follow-up.

[Risk] linear-cli create/update paths lack `--json`, so entity-id capture is fragile. → Mitigation: capture ids via stdout parsing or a follow-up `view --json`, force `--no-interactive` with all required flags, and route structured id read-back to `linear api`.

[Trade-off] In Review fires at verify.md and Done fires at archive, both preserved as distinct transitions. → Accepted: verify.md is a PRECHECK-grepped milestone that maps cleanly onto Linear's In Review state, and archive remains the terminal artifact firing Done, so every Linear state is covered with none skipped.

[Trade-off] Building the router fresh rather than refactoring session-advisor into it now. → Accepted to keep this change scoped and honor extend-not-parallel; the overlap resolution is deferred.

[Trade-off] The In-Review sub-gates are human-steered abstract gates rather than built agents. → Accepted: composing by delegation honors the three-deliverable scope and avoids a fourth agent; automation hooks are recorded as a future extension point.

## Migration Plan

This change adds three skill directories and is delivered through the jj diamond development join, not a deployment change to any running service.
Deploy order: author the three SKILL.md files and their references/ subfiles; the skills tree is auto-discovered by `readSkillsFrom`, so the only nix verification is building the target host home-manager or darwin activation package and confirming each new skill resolves under the claude/factory/hermes/agents skills directories after switch.
No endpoint, database, or schema change is involved; the contexts/*.md → CLAUDE.md symlink is untouched.
Rollback is removal of the three directories (the auto-discovery drops them with no manual deregistration) and a re-switch.

Acceptance: the three skills resolve in the activation package; the router delegates without re-implementing and is a pass-through to /session-orient in Manual mode; the sync overlay's workspace safety gate refuses any mutation before `linear auth whoami` confirmation; each SKILL.md is in lean-index plus Contents-table form under roughly 350 lines with detail in references leaves; the three "Load when" triggers are verified mutually non-overlapping against session-advisor, issues-beads, and the bundled linear-cli skill; and the dogfood lifecycle reaches archive without authoring linear_story_* frontmatter (since this change is not synced to a real story).

Tasks foreshadow (deliverables the upcoming tasks.md must enumerate):

- The openspec-linear-sync skill must include one end-to-end worked example in linear-cli-mapping.md: a HIL issue traced Backlog → Todo → In Progress → In Review → Done with literal linear-cli commands at each transition — the `linear auth whoami` gate, the guarded transition (fire only when strictly behind), the ≤ 2-sentence comment, and the archive-time document UPSERT — plus a router walkthrough in the router's board-and-gates.md.
- This change also corrects the stale comment at `modules/home/users/crs58/default.nix` (currently `# Inject linear-cli's bundled skills (38 linear-*/SKILL.md subdirs)`) to describe a single linear-cli/ skill directory with sixteen reference subfiles.

## Open Questions

The apply-gate jj-versus-worktree reconciliation (diamond development join versus the CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch) is deferred to confirmation at the apply gate and is input to a separate jj-policy follow-up.

The session-advisor↔router routing overlap is a deferred follow-up by explicit decision; it is not resolved here.

The AFK delegation dispatch surface is recorded as a bounded open question: the router's AFK behavior is "hand off to the Claude Code Workflows feature and track via its plan checkboxes," but whether the concrete dispatch target is the Claude Code Workflows feature directly or a named cc-dynamic-workflow (cross-referencing the ouroboros-loop cc-dynamic-workflow skill) is left open for the apply gate.

The OpenSpec change name (agentic-planning-development-management-skills) intentionally differs from deliverable 1's router skill directory name (agentic-planning-development-workflow); confirm the change name and the router skill name are meant to stay distinct.
The three naming axes are deliberately distinct and each axis is internally self-consistent: the spec capability name `agentic-workflow-routing` (spec-dir == proposal-capability), the router skill-dir-plus-frontmatter name `agentic-planning-development-workflow` (skill-dir == frontmatter-name), and the change name `agentic-planning-development-management-skills`; likewise the PM-hub capability `project-management-hub` versus its skill-dir-plus-frontmatter name `project-management`, so a capability name need not correspond to any file or directory.
