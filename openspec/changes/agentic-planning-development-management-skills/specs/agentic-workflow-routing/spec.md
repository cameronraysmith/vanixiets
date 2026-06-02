## ADDED Requirements

### Requirement: Unified seven-state Linear-canonical board

The router SHALL drive a single board re-cast onto Linear's canonical states: Backlog, Todo, In Progress, In Review, and Done as the five active states, plus Canceled and Duplicate as inert terminals.
The board SHALL define exactly one transition-firing condition per forward transition, with the four forward transitions named by their transition rather than by an ordinal.

#### Scenario: Readiness gate fires Backlog to Todo on proposal.md
- **WHEN** a change directory acquires a committed proposal.md
- **THEN** the readiness gate fires the Backlog to Todo forward transition

#### Scenario: Brainstorm-only change remains in Backlog
- **WHEN** a change directory has brainstorm.md but no proposal.md
- **THEN** no forward transition fires and the change stays in Backlog, and the router documents this brainstorm-exists-proposal-pending window explicitly

#### Scenario: Apply's first checkbox fires Todo to In Progress
- **WHEN** apply marks the first tasks.md `- [x]` checkbox complete (the grep-detectable anchor that survives the jj worktree substitution, per design D6)
- **THEN** the apply gate fires the Todo to In Progress forward transition

#### Scenario: In-Review gate fires In Progress to In Review on verify.md
- **WHEN** verify.md is created for an in-progress change
- **THEN** the In-Review gate fires the In Progress to In Review forward transition

#### Scenario: Archive gate fires In Review to Done
- **WHEN** the change is archived (openspec archive succeeds)
- **THEN** the archive gate fires the In Review to Done forward transition and Done is reached only after archive

#### Scenario: Canceled and Duplicate are inert terminals reachable from any active state
- **WHEN** a change directory is removed without archive, or a change is superseded by another change
- **THEN** the board moves the issue to Canceled or Duplicate respectively, treating both as inert terminals carrying no active work, reachable from any active state exactly like Backlog

### Requirement: In Review decomposes into two ordered human-steered sub-gates

The In Review state SHALL internally decompose into two ordered sub-gates: roborev (code review) first, then documenter (docs and handbook review) second, with their joint approval the precondition for the archive gate that fires Done.
The current execution model for both sub-gates SHALL be human-steered: a human operating the workflow orchestrator supplies the verdict, and the router presents the gate and routes on that verdict rather than auto-executing review.
roborev SHALL be the code-review point linking out from the superpowers-bridge apply and verify stage, and documenter SHALL be documentation authoring plus review linking out from the verify and retrospective stage.

#### Scenario: roborev approval advances to documenter
- **WHEN** the human supplies an approved verdict at the roborev sub-gate
- **THEN** the router advances to the documenter sub-gate

#### Scenario: documenter pass advances to archive
- **WHEN** the human supplies a passing verdict at the documenter sub-gate
- **THEN** the router proceeds to the archive step, which is the sole anchor that fires Done

#### Scenario: sub-gate rejection routes to the shared re-queue
- **WHEN** the human rejects at either the roborev or the documenter sub-gate
- **THEN** the router routes the issue into the single shared re-queue node

#### Scenario: future automation is an extension point, not a fourth agent
- **WHEN** automation hooks are later added to trigger code-review or doc-generation tools at the sub-gates
- **THEN** they compose into the existing roborev and documenter abstract gates without introducing a fourth agent

### Requirement: Shared re-queue with bounded-retries termination guarantee

The board SHALL provide a single shared re-queue node that receives both sub-gate rejections and re-queues into In Progress above the execution-mode fork, so a bounced issue re-selects its execution mode.
The re-queue SHALL fire on either a verify.md Overall Decision of checked-FAIL (machine-detected) or a human rejection at either sub-gate.
A bounded-retries policy SHALL give the board a documented termination guarantee that its structure alone does not provide: a maximum review-round counter that escalates to the human PM layer on exhaustion.

#### Scenario: re-queue lands above the mode fork
- **WHEN** the shared re-queue node receives a rejection
- **THEN** the issue transitions In Review to In Progress above the mode fork, where it re-selects its execution mode

#### Scenario: verify.md checked-FAIL triggers the re-queue
- **WHEN** verify.md records an Overall Decision of checked-FAIL
- **THEN** the re-queue fires by machine detection

#### Scenario: bounded retries escalate on exhaustion
- **WHEN** the review-round counter reaches its maximum
- **THEN** the board escalates to the human PM layer and stops firing automatic re-queues, parking the issue for human decision

### Requirement: AFK, HIL, and Manual execution-mode fork at the Todo to In Progress boundary

The router SHALL place a three-way execution-mode fork (AFK, HIL, Manual) at the Todo to In Progress boundary, where a human picks the mode per-issue with no automatic Linear-label selection, and all three modes converge on In Review.
Each mode SHALL declare its entry criteria and its per-mode authoritative task ledger: HIL uses OpenSpec tasks.md, AFK uses the workflow or superpowers plan checkboxes, and Manual uses the beads /session-orient to /session-checkpoint loop.

#### Scenario: human selects the mode per-issue
- **WHEN** an issue reaches the Todo to In Progress boundary
- **THEN** the router presents the AFK, HIL, and Manual modes and the human selects one per-issue, with no Linear label mechanizing the choice

#### Scenario: mode selection picks the authoritative ledger
- **WHEN** a mode is selected
- **THEN** the authoritative task ledger is fixed for that issue (HIL to tasks.md, AFK to plan checkboxes, Manual to the beads loop), and no parallel beads task list is created in HIL or AFK

#### Scenario: re-queued issue defaults to its original mode
- **WHEN** a bounced issue re-enters the mode fork through the shared re-queue
- **THEN** it defaults to its original mode unless the human explicitly overrides, and any override is recorded as an explicit ledger hand-off in the attempt log

### Requirement: Compose by delegation, never re-implement

The router SHALL be a thin mode-selector that dispatches and never re-implements orient, plan, review, or checkpoint.
AFK SHALL hand off to the Claude Code Workflows feature and track via its plan checkboxes; HIL SHALL delegate to the opsx and superpowers skills via the bridge; Manual SHALL be a pass-through to /session-orient, /session-plan, /session-review, and /session-checkpoint.
The router SHALL reference session-advisor as the Manual-path diagnostic engine without duplicating it, and the router itself SHALL NOT read beads graph metrics or the stigmergic signal table.

#### Scenario: Manual mode passes through to session-orient
- **WHEN** Manual mode is selected
- **THEN** the router passes through to /session-orient, which routes via session-advisor and the stigmergic signal table, and the router does not read beads metrics or the signal table itself

#### Scenario: router references session-advisor without absorbing it
- **WHEN** the router needs the Manual-path diagnostic
- **THEN** it references the standalone session-advisor skill, and the session-advisor-to-router routing overlap remains a deferred follow-up not resolved here

#### Scenario: router does not re-implement the session skills
- **WHEN** any mode reaches a delegated phase (orient, plan, review, checkpoint)
- **THEN** the router dispatches to the existing skill rather than re-implementing its logic, honoring the extend-not-parallel discipline

### Requirement: HIL apply-phase jj and worktree isolation guidance

The router SHALL carry jj and workspace isolation guidance for the HIL apply phase, because superpowers:using-git-worktrees resolves to a raw git worktree add that is hook-blocked in this jj-mode environment.
The guidance SHALL record the reconciliation as an open design point confirmed at the apply gate, naming the jj diamond development join as the worktree substitute and the env-gated CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch as alternatives, and SHALL NOT bake in a git worktree add.

#### Scenario: worktree creation is hook-blocked under jj mode
- **WHEN** the HIL apply phase reaches superpowers:using-git-worktrees
- **THEN** the router directs the reader to the jj diamond development join or the CLAUDE_JJ_WORKSPACE_ISOLATION hatch rather than assuming git worktree add succeeds

#### Scenario: reconciliation is deferred to the apply gate
- **WHEN** the isolation mechanism must be chosen for an apply phase
- **THEN** the choice between the diamond development join and the jj-workspace hatch is confirmed at the apply gate and is input to a separate jj-policy follow-up
