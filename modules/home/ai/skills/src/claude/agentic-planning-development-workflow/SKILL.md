---
name: agentic-planning-development-workflow
description: State-machine router across a Linear-canonical board with an AFK/HIL/Manual execution-mode fork. Load when selecting an execution mode for a change, driving the agentic planning-and-development board, or routing a change between board states.
---

# Agentic planning and development workflow

This skill is a thin state-machine router.
It selects an execution mode for a unit of work and routes that unit across a board re-cast onto Linear's canonical states.
It composes existing skills by delegation and re-implements none of their logic.

The two structural elements a reader holds in mind are the board spine and the execution-mode fork.
The board spine is the sequence of states a unit of work passes through; the fork is the per-issue human choice of how the work between two of those states gets executed.

## Quickstart

This is the integrated front door: the one-time initialization, then the per-change quick flow, with the four openspec-linear-sync transitions called out inline.
It is a thin orchestration index that links out to the owning leaves for all mechanics and re-documents none of them.
For the collaborator map naming who owns what, see references/collaborators.md.

### One-time initialization

Run the workspace safety gate first, before any Linear call.
Assert both `LINEAR_API_KEY` and `LINEAR_WORKSPACE` are unset, then `linear auth whoami --workspace <slug>` to confirm the reported workspace is the intended personal-versus-work one, and pass an explicit `--workspace <slug>` on every later call including reads; the gate mechanics live in project-management/references/linear-workspace-safety-gate.md.
As a one-time act, create or extend the openspec/linear.yaml registry with the teams and projects entries for the chosen team and project; then, per change at the Backlog-to-Todo bind, write `linear_story_*` plus `linear_team` and `linear_project` and initialize the D10 sync ledger into that change's proposal.md frontmatter only, referencing the registry's teams and projects entries rather than writing the binding into the registry; the config schema, the one-question setup, and the write-before-read frontmatter binding live in openspec-linear-sync/references/config-and-frontmatter.md.
Orient beads for the Manual-mode drill-down via /session-orient (session-advisor reads the graph metrics and signal table), with the comprehensive command reference in the issues-beads skill.

### Quick flow (HIL)

The spec-first default path; the router frames, the bridge drives, and openspec-linear-sync mirrors phase to Linear state.

```text
/agentic-planning-development-workflow   # front door: place the unit on the board; the human picks HIL at the Todo to In Progress fork
/opsx:ff --schema superpowers-bridge     # all 8 bridge artifacts; proposal.md creation => T1 Backlog to Todo: openspec-linear-sync binds linear_story_* and sets Todo
/opsx:apply                              # implement tasks.md; the first - [x] => T2 Todo to In Progress
/opsx:verify                             # writes verify.md => T3 In Progress to In Review; then roborev then documenter, both human-steered
/opsx:continue                           # the retrospective artifact, inside the In Review window
/opsx:archive                            # readiness then sync then archive then mirror UPSERT => T4 In Review to Done; Done binds to archive
```

The shared re-queue receives a verify.md checked-FAIL `(fail) FAIL` or a rejection at either In-Review sub-gate and routes In Review back to In Progress above the mode fork, under a bounded-retries default of 3; the re-queue and bounded-retries mechanics live in references/board-and-gates.md and the transition mechanics in openspec-linear-sync/references/lifecycle.md.
Catch-up reconciliation fires a single transition straight to the local phase when the local phase and the resolved Linear state disagree by more than one step, rather than walking the intermediate crossings; it is owned by openspec-linear-sync/references/lifecycle.md, with the board side in references/board-and-gates.md.

### Step-by-step note

`/opsx:ff --schema superpowers-bridge` is interchangeable with `/opsx:new --schema superpowers-bridge` then `/opsx:continue` six times.
Use the fast-forward for the one-shot lean and the stepped form when a human checkpoint between artifacts is wanted; the per-mode delegation that makes this an HIL-path choice lives in references/execution-modes.md.

### AFK and Manual variants

AFK hands the unit off to the Claude Code Workflows feature, which drives to In Review without per-step prompting; see references/execution-modes.md and references/delegation.md.
Manual passes through `/session-orient` then `/session-plan` then `/session-review` then `/session-checkpoint`, with the beads issue status driving the four transitions; see references/execution-modes.md and references/delegation.md.

## The board spine

The board is re-cast onto Linear's canonical states so every board state maps one-to-one onto a Linear state with none skipped, which is what makes the whole binding automatable.
Five states are active and two are inert terminals:

Backlog then Todo then In Progress then In Review then Done are the five active states.
Canceled and Duplicate are inert terminals carrying no active work, reachable from any active state exactly like Backlog.

Four forward transitions advance a unit of work, each named by its transition rather than by an ordinal and each firing on exactly one file-anchored condition:

The readiness gate fires Backlog to Todo when proposal.md exists.
The apply gate fires Todo to In Progress on the first tasks.md `- [x]` checkbox.
The In-Review gate fires In Progress to In Review when verify.md exists.
The archive gate fires In Review to Done when the change is archived.

In Review internally decomposes into two ordered human-steered sub-gates, roborev (code review) first and documenter (docs and handbook review) second, whose joint approval is the precondition for the archive gate that fires Done.
A single shared re-queue node receives both sub-gate rejections and a verify.md checked-FAIL, re-queuing into In Progress above the mode fork so a bounced unit re-selects its execution mode.
A bounded-retries policy escalates to the human PM layer on exhaustion, giving the board a documented termination guarantee its structure alone does not provide.
The full state machine, its gates, the sub-gates, the re-queue, the bounded-retries policy, the brainstorm-exists-proposal-pending Backlog window, and a concrete router walkthrough are in references/board-and-gates.md.

## The execution-mode fork

The mode fork sits at the Todo to In Progress boundary.
A human picks the mode per-issue with no automatic Linear-label selection, and all three modes converge on In Review.
The chosen mode fixes the authoritative task ledger for that unit of work for the duration:

AFK hands off to the Claude Code Workflows feature and tracks via its plan checkboxes.
HIL delegates to the opsx and superpowers skills via the superpowers-bridge, where the OpenSpec tasks.md is the authoritative ledger.
Manual is a pass-through to the session-* loop, where the beads /session-orient to /session-checkpoint cycle is the ledger.

A re-queued unit defaults to its original mode unless the human explicitly overrides at the fork, which keeps a single authoritative ledger per unit across re-queues.
Per-mode entry criteria, the authoritative-ledger rule, the no-parallel-beads-task-list constraint in HIL and AFK, and the re-queue-defaults-to-original-mode rule are in references/execution-modes.md.

## The delegation map

The router never re-implements orient, plan, review, or checkpoint, and it does not read beads graph metrics or the stigmergic signal table.
It dispatches each mode to its execution surface and presents the mode-agnostic In-Review sub-gates downstream of all three modes:

| Mode | Delegation target |
|---|---|
| AFK | the Claude Code Workflows feature (handoff act; concrete dispatch target a bounded open point) |
| HIL | opsx:* plus superpowers via the superpowers-bridge |
| Manual | /session-orient then /session-plan then /session-review then /session-checkpoint |

session-advisor is referenced as the Manual-path diagnostic engine, not duplicated; the session-advisor-to-router routing overlap is a deferred follow-up.
roborev and documenter are mode-agnostic human-steered abstract gates, not built agents.
The compose-by-delegation contract, the AFK handoff act and its bounded open dispatch point, the abstract gates, and the explicit statement that the router re-implements none of the session-* logic are in references/delegation.md.

## Isolation under jj mode

The HIL apply phase reaches superpowers:using-git-worktrees, which resolves to a raw git worktree add that is hook-blocked in this jj-mode environment.
The jj diamond development join is the worktree substitute, with the env-gated CLAUDE_JJ_WORKSPACE_ISOLATION jj-workspace hatch as an alternative.
The choice between them is an apply-gate open point and input to a separate jj-policy follow-up; the router bakes in no git worktree add.
Integration is jj-native and user-gated, with no autonomous PR.
The isolation guidance, the apply-gate confirmation, and orchestrator-routed commits onto the chain are in references/hil-isolation.md.

## Contents

| Reference | Purpose |
|---|---|
| references/execution-modes.md | AFK/HIL/Manual entry criteria, the per-mode authoritative ledger, and the re-queue-defaults-to-original-mode rule |
| references/board-and-gates.md | The seven Linear-canonical states, the four forward transitions, the In-Review sub-gates, the shared re-queue, the bounded-retries policy, and the router walkthrough |
| references/hil-isolation.md | The jj diamond development join as the worktree substitute and the CLAUDE_JJ_WORKSPACE_ISOLATION hatch, confirmed at the apply gate |
| references/delegation.md | The compose-by-delegation contract, the abstract In-Review gates, and the statement that the router re-implements none of orient/plan/review/checkpoint |
| references/collaborators.md | The four-collaborator map naming the PM hub, this router, the openspec plus superpowers-bridge flow, and openspec-linear-sync, with the ownership-by-layer one-liner and a pointer back to the front-door quickstart |

## Boundary assertions

The router does not read beads graph metrics or the stigmergic signal table; in Manual mode it passes through to /session-orient, which is where that reading happens via session-advisor.
This boundary preserves the no-parallel-surface discipline: the router selects among existing surfaces and never builds a second routing or task-ledger surface alongside them.
Mode selection is a per-issue human decision and is never mechanized via a Linear label.
