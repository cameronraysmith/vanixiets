# Delegation

The router is a thin mode-selector that dispatches and never re-implements orient, plan, review, or checkpoint.
It composes existing surfaces by delegation, honoring the standing extend-not-parallel discipline.
This file owns the compose-by-delegation contract, the mode-agnostic In-Review abstract gates, and the explicit statement of what the router does not re-implement.

The per-mode entry criteria and ledgers live in references/execution-modes.md; the board states and gates live in references/board-and-gates.md; the jj isolation guidance lives in references/hil-isolation.md.

## The compose-by-delegation contract

Each execution mode dispatches to its own surface, and the router carries the mode selection only.

AFK hands off to the Claude Code Workflows feature.
The handoff act is the router relinquishing step-by-step control to the Workflows feature, which then drives the unit of work to In Review tracking via its plan checkboxes.

HIL delegates to the opsx and superpowers skills via the superpowers-bridge.
The router does not drive the spec-first lifecycle itself; it dispatches to opsx:* and the superpowers bridge skills and routes on their milestones.

Manual is a pass-through to the session-* loop: /session-orient then /session-plan then /session-review then /session-checkpoint.
The router invokes /session-orient and steps aside; the session-* skills are an in-place Viable System Model state machine the router selects among, not one it duplicates.

## session-advisor is the Manual-path diagnostic engine, referenced not duplicated

In Manual mode the diagnostic that decides which session-* skill to enter is session-advisor.
session-advisor reads beads graph metrics and the stigmergic signal table and recommends a session or beads skill; the router references it as the Manual-path diagnostic engine and does not absorb its heuristics.
The router itself does not read beads graph metrics or the stigmergic signal table, which preserves the no-parallel-surface boundary: there is one routing surface for graph-metric routing (session-advisor) and the router defers to it rather than building a second.
The session-advisor-to-router routing overlap is a deferred follow-up, not resolved here.

## The AFK dispatch target is a bounded open point

The router's AFK behavior is to hand off to the Claude Code Workflows feature and track via its plan checkboxes.
Whether the concrete dispatch target is the Claude Code Workflows feature directly or a named cc-dynamic-workflow is a bounded open point left for confirmation at the apply gate.
The candidate surfaces are the Claude Code Workflows feature itself and a named cc-dynamic-workflow, cross-referencing the ouroboros-loop cc-dynamic-workflow skill as the prior art for a dynamic-workflow dispatch target.

## roborev and documenter are mode-agnostic abstract gates

roborev and documenter are mode-agnostic gate tasks the router presents downstream of all three execution modes, both rejecting into the shared re-queue.
They are abstract gates, not built agents: no fourth agent is introduced for the In-Review sub-gates.

roborev is the code-review point linking out from the superpowers-bridge apply and verify stage.
documenter is documentation authoring plus review linking out from the verify and retrospective stage; its review surface is repo-dependent (apps/handbook/src/content/docs/ for the sciexp monorepo, docs/notes/ plus affected skill and module docs for vanixiets-internal).

Both sub-gates are currently human-steered: a human operating the workflow orchestrator supplies the verdict and the router routes on it.
A future extension point is recorded in references/board-and-gates.md: automation hooks may later trigger code-review or doc-generation tools at the sub-gates, composing into the existing roborev and documenter gates without introducing a fourth agent.
They live here, mode-agnostic, while the per-mode criteria live in references/execution-modes.md, because the sub-gates are presented identically downstream of every mode.

## The router re-implements none of orient, plan, review, or checkpoint

The router re-implements none of the session-* logic.
When any mode reaches a delegated phase, the router dispatches to the existing skill rather than re-implementing it:

session-orient is the strategic-horizon orient; the router dispatches to it and does not assemble session context itself.
session-plan is the tactical-to-operational plan; the router dispatches to it and does not build an execution buffer itself.
session-review is the operational-to-tactical review; the router dispatches to it and does not verify convergence points itself.
session-checkpoint is the all-horizons checkpoint; the router dispatches to it and does not capture session state or produce the handoff narrative itself.

This is the binding form of the no-parallel-surface discipline for this skill: the router selects among existing surfaces and adds only the board spine and the execution-mode fork on top of them.
