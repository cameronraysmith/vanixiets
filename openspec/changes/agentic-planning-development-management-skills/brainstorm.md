<!--
Raw capture of superpowers:brainstorming output.

This file captures the output of the brainstorming skill verbatim; it does not impose any structure.
The skill's natural output is usually a decision-log format (background -> decision chain Q1-Qn -> design trade-offs),
but the organization may vary depending on the conversation.

design.md is extracted from this file and reorganized into a structured design document.

Do not copy this file's content into design.md -- design.md is an independent, reorganized artifact;
the two are complementary but do not overlap.
-->

# Brainstorm: agentic planning, development, and management skills

## How this record was produced

This brainstorm was conducted as an orchestrator-led research fan-out (ten reader subagents across ten dimensions, consolidated into a durable research note) followed by four rounds of user design decisions and one overriding ownership-model decision.
The decision substance is therefore already complete; this artifact records the conclusions of that completed brainstorming rather than transcribing a fresh live dialogue.
Where the upstream research note's ownership analysis (its dimension 4 and dimension 1 synthesis) reached a beads-centric conclusion that beads owns the authoritative technical issue graph, that conclusion has been superseded by the ownership model recorded below; the stale conclusion is not carried forward.

## Background

We are building three new agent skills, dogfooded as this very OpenSpec change so the build itself exercises the lifecycle it describes.

The first deliverable is agentic-planning-development-workflow, targeting modules/home/ai/skills/src/claude/.
It is a state-machine router across a board re-cast onto Linear's canonical states (Backlog -> Todo -> In Progress -> In Review -> Done, plus the inert Canceled/Duplicate terminals, with roborev and documenter as ordered sub-gates inside In Review) with a three-way Execution-mode fork (AFK, HIL, Manual) at the Todo -> In Progress boundary.
It composes existing skills by delegation and never re-implements them, and it carries jj and workspace isolation guidance for the HIL apply phase.

The second deliverable is project-management, targeting modules/home/ai/skills/src/core/.
It is a human-facing project-management hub with references organized into linear/, github/, beads/, and method/ sub-areas.
The linear sub-area carries the workspace safety gate.

The third deliverable is openspec-linear-sync, targeting modules/home/ai/skills/src/core/.
It is a Linear-to-OpenSpec lifecycle-sync skill adapted substantially (not ported) from the reference openspec-linearized, driven by the linear-cli binary rather than the Linear MCP, which is disabled in this environment, and bound to our vendored eight-artifact superpowers-bridge lifecycle.

The placement choices follow the house nix-discovery convention: src/core flows to all agents, while src/claude is appended only to Claude Code.
The router lands in src/claude because it depends on Claude-Code-only orchestration surfaces (slash-command and Task/subagent dispatch, Claude Code Workflows); the PM hub and the sync skill are agent-general and land in src/core.

## The ownership model is the spine

The overriding user decision is that Linear and OpenSpec own the work, and beads is demoted to an optional, local execution sublayer.
Every other decision in this brainstorm hangs off this spine.

Linear holds the business "what" and the team-visible status surface: Initiatives, Projects, Cycles, and parent issues.
The Linear issue body carries only a TL;DR, Deliverables, and Acceptance Criteria; status and progress live in Linear fields and comments, never in the issue body.

OpenSpec plus the superpowers-bridge hold the spec-first change lifecycle, the human-interpretable requirements document, and the within-change task decomposition in tasks.md.
OpenSpec is the primary technical owner of the decomposition.

beads is demoted to an optional, local, fine-grained execution sublayer that sits below the OpenSpec requirements document.
It is invoked by local agent execution only when a particular complex task needs finer-grained tracking than the spec should carry, so the spec stays human-interpretable.
beads is not the default decomposition owner in HIL or AFK modes.
In Manual mode, where there is no OpenSpec change, beads remains load-bearing via the /session-orient -> /session-checkpoint loop; this is a hard constraint, not a preference.

The primary cross-reference binding is Linear-story to OpenSpec-change, stored in two locations: openspec/linear.yaml and the proposal.md linear_story_* frontmatter.
The beads-ID binding applies only when a beads drill-down is actually used or in Manual mode.

This resolves the largest duplication hazard surfaced by the research (the issue/task layer that Linear, beads, and OpenSpec tasks.md all compete to own) by ownership-by-layer rather than by mirroring any layer into another.

## Decision chain

### Q1: which layer owns the authoritative work decomposition?

Resolved by the ownership model above.
Linear and OpenSpec own the work; OpenSpec is the primary technical owner of the within-change decomposition via tasks.md; beads is an optional drill-down sublayer.
This explicitly supersedes the research note's beads-centric conclusion.

### Q2: which way does the Linear-to-OpenSpec sync flow?

The sync direction is business-"what" down, technical status up.
Humans author the goal, use-cases, and acceptance criteria in the Linear issue, and agents read that down as context.
Technical status rolls up from the OpenSpec lifecycle into Linear.
Local stays authoritative for the "how".
All Linear updates are best-effort and non-blocking, so a failed or skipped Linear write never blocks local progress.

### Q3: how is the execution mode selected at the board's third gate?

The human picks the mode per-issue at pickup time.
There is no automatic Linear-label-driven selection.
The router documents the three modes and their entry criteria, and the Linear seam stays a documented but non-mechanized pluggable point.
This deliberately declines the research note's speculative "Linear HIL label feeding a PM-driver node", treating mode selection as a human decision rather than a mechanized one.

### Q4: how does the router relate to the existing /session-* skills?

Build the router fresh and independent, and modify or retire nothing in the existing /session-* skills now.
The router composes by delegation:

- AFK delegates to Claude Code Workflows.
- HIL delegates to opsx:* plus superpowers via the bridge.
- Manual delegates to the existing /session-orient -> /session-plan -> /session-review -> /session-checkpoint loop.

session-advisor stays standalone, and the router references it as the Manual-path diagnostic engine.
The routing-overlap between session-advisor and the router is a deferred follow-up, not resolved in this change.
The router never re-implements orient, plan, review, or checkpoint logic.
This honors the standing extend-not-parallel discipline and the in-skill delegation contracts that session-orient and session-checkpoint already declare.

### Q5: what is the unit of work and the terminal artifact?

The unit of work is a forge-agnostic board.
The terminal artifact is the archived OpenSpec change.
A pull request into the monorepo, including docs/handbook, is one realization of that terminal artifact, consistent with the repo's "fast-forward-merge by default, pull request when warranted" policy.
A bounded-retries policy governs the In-Progress to Review/Document loop, escalating to the human PM layer on exhaustion; this gives the board a documented termination guarantee that its structure alone does not provide.

### Q6: how does the eight-artifact bridge lifecycle bind to Linear state transitions?

Brainstorming continued into a state-machine discussion whose outcome is a unified model re-cast onto Linear's canonical states (Backlog, Todo, In Progress, In Review, Done, plus the inert terminals Canceled and Duplicate), covering every Linear state with none skipped.
The eight-artifact bridge lifecycle binds four forward Linear state transitions for deliverable 3, each firing a short best-effort non-blocking comment:

- Proposal-phase, anchored on proposal.md creation rather than brainstorm.md creation, drives Backlog -> Todo.
- Apply step 1, the first observable build act (the first tasks.md `- [x]`, equivalently using-git-worktrees or the jj-diamond substitute, the first observable VCS act), drives Todo -> In Progress.
- verify.md creation drives In Progress -> In Review; In Review internally contains the roborev (code review) then documenter (docs/handbook review) sub-gates.
- The archive step, openspec archive, drives In Review -> Done.

Beyond the four forward transitions, the shared Feedback re-queue fires In Review -> In Progress on a verify.md Overall Decision of "(fail) FAIL" or a documenter rejection (bounded-retries, escalating to the human PM layer on exhaustion), and two terminal exits reach Canceled (change directory removed without archive) or Duplicate (superseded by another change) from any active state.
Invariants: never Done before archive; status, validate, sync, and edit operations must not move the issue to Done; Canceled and Duplicate are inert terminals.
This supersedes the earlier three-transition framing, which collapsed In Review into Done at archive; verify.md is one of the two PRECHECK-grepped bridge signals, so the In Progress -> In Review transition is the best-grounded of the four.
The sync skill resolves the team's actual Linear workflow state names via linear-cli rather than hardcoding them, and degrades gracefully (a team without an "In Review" state stays In Progress until Done).
The proposal-phase anchor (proposal.md versus brainstorm.md) remains flagged for confirmation in the design artifact.

## Key constraints recorded for design

The workspace safety gate is the hardest constraint and lives in deliverable 2's linear sub-area and in deliverable 3.
Never propose a Linear mutation until the correct personal-versus-work workspace is confirmed via `linear auth whoami`, optionally `linear auth whoami --workspace <slug>`.
Every mutation passes an explicit `--workspace <slug>` or relies on the confirmed credentials.toml `default` key.
Do not key the gate on LINEAR_WORKSPACE: that variable is a web/app URL slug, is env-overridable, and the credential precedence makes it the wrong lever.
Never run mutating `linear auth` commands, because the credentials are nix-managed and immutable.

Drive Linear exclusively through linear-cli and recommend against the Linear MCP.
Compose the bundled linear-cli skill (a single skill directory with sixteen reference subfiles) for the verbs; the sync skill carries only link and sync policy.
Because linear-cli lacks `--json` on most create/update paths, the sync skill captures entity ids via stdout parsing or a follow-up view, and routes only document reparenting and structured id read-back to the `linear api` GraphQL fallback.

Do not modify or replace the planning-repo contexts/*.md -> CLAUDE.md symlink mechanism; it is explicitly out of scope.

Extend and compose existing skills; do not create parallel protocol surfaces, per the standing extend-not-parallel feedback.

Synthesize from the Linear Method and CCPM references; do not copy their text.
Adopt the Linear Method ontology (Initiative > Project > Milestone > Issue, with Cycles as an orthogonal scheduling overlay) as the PM hub's spine, but assign clear ownership per layer rather than mirroring decomposition across tools.

The apply phase has a known incompatibility with jj mode.
superpowers:using-git-worktrees resolves to a raw `git worktree add` that is hook-blocked here; subagent-driven-development auto-commits; finishing-a-development-branch opens a PR.
The reconciliation is the jj diamond development join as the worktree substitute, or the CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch, to be confirmed at the apply gate.
This is recorded as an open design point, not resolved here.

This change is itself being built in HIL mode through the superpowers-bridge as a dogfooded correctness test, so any friction discovered while authoring these artifacts is itself evidence about the lifecycle.

## Design trade-offs and open points carried to design

The proposal-phase anchor for the Linear Backlog -> Todo transition (proposal.md creation versus brainstorm.md creation) is a trade-off between binding earlier (more Linear visibility, but a transition fires before the change has a committed proposal) and binding at proposal.md (a more substantive milestone, the recommended option).

The earlier-unresolved question of whether In Review should be its own Linear state has been resolved in favor of a dedicated In Review transition anchored on verify.md, superseding the three-transition framing that collapsed In Review into Done at archive.
verify.md is one of the two PRECHECK-grepped bridge signals, so the In Progress -> In Review transition is the best-grounded of the four forward transitions.

The jj-versus-worktree reconciliation at the apply gate (diamond development join versus the env-gated jj-workspace hatch) is deferred to confirmation at the apply gate.

The session-advisor-versus-router routing overlap is a deferred follow-up by explicit decision in Q4.

## Open questions for the orchestrator

These were surfaced by the research note and are not resolved by the user's decisions above; they are returned rather than silently resolved.

First, the chain bookmark name (agentic-planning-development-management-skills) differs from deliverable 1's skill name (agentic-planning-development-workflow).
The research note frames the bookmark as the VCS routing target and the skill name as the deliverable, so this is presumably intentional, but it should be confirmed that the OpenSpec change name (which matches the bookmark) is meant to stay distinct from the router skill's directory name.

Second, the recommended proposal-phase anchor for the Backlog -> Todo transition is stated two ways in the inputs: the dispatch brief recommends proposal.md creation, while the research note's dimension 1 recommends binding Linear Started to brainstorm.md creation.
The brief is treated as authoritative here (proposal.md), but the contradiction should be resolved explicitly in design.

Third, the design brief lists a method/ sub-area under deliverable 2, whereas the research note's framing of the PM hub listed linear/, github/, beads/, and only "possibly" method/.
This artifact records method/ as in-scope per the brief; confirm that method/ is a committed sub-area rather than optional.
