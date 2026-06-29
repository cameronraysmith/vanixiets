# Execution modes

The execution-mode fork sits at the Todo to In Progress board boundary.
A human picks one of three modes per-issue with no automatic Linear-label selection, and all three modes converge on In Review.
The choice fixes the authoritative task ledger for that unit of work for its duration, which is how the router avoids the issue/task duplication hazard: only one ledger is authoritative per mode, and no layer is mirrored into another.

This file owns the per-mode entry criteria and the authoritative-ledger rule.
The mode-agnostic delegation contract, the In-Review sub-gates, and the AFK handoff act live in references/delegation.md; the board states and re-queue mechanics live in references/board-and-gates.md.

## AFK

Hand off to the Claude Code Workflows feature for away-from-keyboard bulk execution.
The handoff act is the router relinquishing step-by-step control to the Workflows feature, which then drives the unit of work to In Review without per-step human prompting.

Authoritative ledger: the workflow or superpowers plan checkboxes.
Whatever plan the Workflows feature executes against carries its own checkbox task tracking, and those checkboxes are the single source of truth for task completion in AFK mode.

Do not create a parallel beads task list in AFK.
At most, map the beads issue id to the superpowers plan path for traceability; the plan checkboxes remain authoritative and the beads id is a reference, not a second ledger.

Entry criteria: the unit of work is well-scoped enough to run unattended, the human accepts that step-by-step intervention is deferred to the In-Review gates, and a workflow or plan with checkboxes exists or will be produced by the handoff.

The concrete AFK dispatch target is a bounded open point recorded in references/delegation.md: whether the router hands off to the Claude Code Workflows feature directly or to a named cc-dynamic-workflow (cross-referencing the ouroboros-loop cc-dynamic-workflow skill) is left for confirmation at the apply gate.
AFK is therefore not yet end-to-end drivable: both the dispatch target and the verify-equivalent firing signal that fires the In-Review gate are confirmed at the apply gate, so an operator selecting AFK confirms those at the gate rather than expecting a turnkey runnable path.

## HIL

Delegate to the opsx and superpowers skills via the superpowers-bridge for human-in-the-loop spec-first development.
The human stays in the loop across the bridge lifecycle, supplying decisions at brainstorm, proposal, and apply boundaries.

Authoritative ledger: the OpenSpec tasks.md.
The within-change decomposition lives in tasks.md, and its `- [x]` checkboxes are the single source of truth for task completion in HIL mode; the first checked checkbox is also the file-anchored signal the apply gate reads.

Do not create a parallel beads task list in HIL.
At most, map the beads issue id to the OpenSpec change id for traceability; tasks.md remains authoritative and the beads id is a reference, not a second ledger.
beads may still be invoked for a finer-grained drill-down when a complex task needs tracking the spec should not carry, but that drill-down does not displace tasks.md as the authoritative ledger.

Entry criteria: the unit of work warrants a documented spec-first change, the human will stay in the loop through the bridge, and an OpenSpec change directory exists or will be created at the proposal phase.

## Manual

Pass through to the session-* loop for a human-driven series of coding-agent sessions.
The router relinquishes to /session-orient and does not itself read beads graph metrics or the stigmergic signal table; that reading happens inside the session-* skills via session-advisor.

Authoritative ledger: the beads /session-orient to /session-checkpoint loop.
beads is the task tracker in Manual mode, and the orient-to-checkpoint cycle over the beads issue DAG is the single source of truth for task completion.

Entry criteria: there is no OpenSpec change and no away-from-keyboard plan, the work is exploratory or session-shaped rather than spec-shaped, and beads is initialized for the repository.
In Manual mode there is no proposal.md to hold linear_story_* frontmatter, so any Linear binding lives in a beads issue field rather than in frontmatter.

## Re-queue defaults to the original mode

When a bounced unit re-enters the mode fork through the shared re-queue (In Review to In Progress, above the fork), it defaults to its original mode unless the human explicitly overrides at the fork.
Defaulting to the original mode keeps a single authoritative ledger per unit across re-queues: an issue started AFK with plan checkboxes authoritative, bounced, then silently re-picked HIL with tasks.md authoritative would have two ledgers with no reconciliation rule.

If the human does override the mode on re-queue, the cost is an explicit ledger hand-off the human accepts, recorded in the attempt log as the new authoritative ledger for the unit going forward.
A bounced unit is recognized as resuming rather than starting fresh by the combination of In Progress state with a verify.md checked-FAIL or a recorded sub-gate rejection in the attempt log, so the router resumes deterministically rather than re-running from scratch.
That deterministic resume-detection is the HIL and AFK realization (verify.md or the attempt log); Manual mode has neither, so a bounced Manual unit's resume is recognized from the beads issue status at the last session-checkpoint and is human-judged.
