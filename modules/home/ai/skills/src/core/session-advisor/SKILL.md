---
name: session-advisor
description: Lightweight routing advisor that reads beads graph metrics and recommends which workflow skill to invoke.
---
# Session advisor

Symlink location: `~/.claude/skills/session-advisor/SKILL.md`
Slash command: `/session-advisor`

Lightweight routing skill that reads beads graph metrics and recommends which session or beads skill to invoke next.
Prevents misrouting where orient runs against empty or structurally broken graphs, wasting tokens on diagnostics that cannot produce useful results.
Runs diagnostic commands, evaluates heuristics, presents a recommendation with reasoning.
Does not invoke the recommended skill itself.

## Theoretical grounding

This skill is one component of a lifecycle that co-optimizes planning time against execution time.
The underlying model: planning depth has an optimal finite value where marginal yield from one additional planned step equals marginal accuracy loss and planning cost.
This optimum *decreases* as agent execution capacity increases — more agents demand shallower, faster planning cycles to avoid starving them on stale plans.
Model Predictive Control provides the structural answer: plan over a finite prediction horizon, commit only to a shorter control horizon of items dispatched to agents, then re-observe actual codebase state and replan from scratch.
Cynefin domain classification makes planning depth per-item rather than global: clear-domain work (known patterns) is planned far ahead at low cost, while complex-domain work (emergent behavior) is planned only as probes whose outcomes inform the next cycle.
The Viable System Model maps this to an organizational lifecycle where each session skill implements a specific regulatory function: System 4 (orient), System 3 (plan), System 1 (implement), System 3* (review), System 5 (checkpoint).
Stigmergic coordination binds it together — agents orient by reading structured signal tables on the issue DAG rather than receiving centralized briefings, achieving near-optimal throughput via local sensing and acting.
Queue economics calibrates the pipeline: buffer sizing via Little's Law, agent utilization at 70-85% (not 100%, due to queueing instability), and batch sizing via the U-curve between planning overhead and plan staleness.

This skill functions as the algedonic channel — the fast-path signal that bypasses normal hierarchical routing when structural anomalies require immediate attention.
Its routing heuristics are simplified versions of the replanning decision rule: graph health metrics (cycles, empty epics, abnormal ready ratios) determine which regulatory function should activate next.
When no anomaly is detected, routing defaults to the normal lifecycle entry point.

This lifecycle is subject to its own standards.
When patterns suggest the framework itself is producing poor outcomes — systematic surprise across multiple issues, recurring ambiguity in acceptance criteria, Cynefin classifications that consistently shift during implementation, validation that stalls because infrastructure doesn't support the prescribed methodology, or requirements that decompose cleanly but don't compose into a working system — the agent's obligation is to pause execution and surface the observation rather than pressing on within a framework it perceives as inadequate.
The plan is a tool for achieving outcomes; when the tool is counterproductive, the agent's duty is to say so.
See `preferences-validation-assurance` for the full set of double-loop learning triggers and the reflexive severity framework.

For the full theoretical derivation including the R_plan(d) formulation, buffer sizing heuristic, and validation gate placement theory, see `preferences-adaptive-planning`.

## Decision inputs

Run the following diagnostic commands to gather routing inputs.
All complete in seconds.

1. `bd status` -- total open issues, ready/blocked counts, overall graph shape.
2. `bd epic status` -- epic child counts (detect 0/0 children containment antipattern).
3. `bd dep cycles` -- cycle count (must be zero for healthy graph).
4. `bd stale` -- issues with no activity beyond their age threshold.
5. `bd list --json` or `bd show <id> --json` (optional) -- structured data for estimating signal table coverage by inspecting notes fields per issue.

## Routing logic

Rules are evaluated in priority order.
First match wins.

1. **No beads initialized** (no `.beads/` directory): recommend `/issues-beads-init`.
   Rationale: beads is not set up in this repository.

2. **Empty graph** (0 open issues, or all issues closed): recommend `/session-plan`.
   Rationale: graph is empty or fully closed. Populate the issue graph before orienting.

3. **Cycles detected** (cycle count > 0): recommend `/issues-beads-audit` then `/issues-beads-evolve`.
   Rationale: dependency cycles break topological ordering. Fix structure before any workflow skill can operate correctly.

4. **Containment antipattern** (any epic showing 0 children in `bd epic status` that is known to contain issues): recommend `/issues-beads-audit` then `/issues-beads-evolve`.
   Rationale: parent-child relationships likely wired as blocks instead of parent-child type.

5. **Abnormally high ready ratio** (>70% ready on graphs with 50+ issues): recommend `/issues-beads-audit`.
   Rationale: ready/blocked ratio is abnormally high for a graph of this size. Likely indicates missing dependency wiring.

6. **Zero signal table coverage** (0% signal tables on a graph with 10+ issues): recommend seeding signal tables on priority issues before `/session-orient`.
   Rationale: no signal tables found. Orient calibrates by cynefin and planning-depth signals; without them, orient cannot produce a calibrated briefing.

7. **Convergence point** (blocking dependencies on a node are all closed, or user indicates convergence): recommend `/session-review`.
   Rationale: convergence point detected. Integration verification is warranted before proceeding.

8. **Post-work** (user indicates finishing a session, or context budget approaching limits): recommend `/session-checkpoint`.
   Rationale: session wind-down. Capture state and produce handoff narrative.

9. **Healthy graph with signal tables** (no structural issues, signal tables present): recommend `/session-orient`.
   Rationale: graph is healthy and has signal table coverage. Normal orient flow.

## Execution protocol

1. Run diagnostic commands in order: `bd status`, `bd epic status`, `bd dep cycles`, `bd stale`.
2. Parse outputs and evaluate heuristics in the priority order above.
3. Present the recommendation:
   - The recommended skill as a slash command.
   - The reasoning: which heuristic triggered and why.
   - Any pre-conditions or preparation steps (e.g., "run audit first, then evolve").
   - What the user should expect from the recommended skill.
4. Stop. Do not invoke the recommended skill.

## Interaction with other skills

Session-advisor is typically invoked:

- At the very start of a session, before orient, to determine the right entry point.
- When the user is unsure which workflow phase they should be in.
- By the orchestrator when spawning new teammates to determine their first action.

This skill reads output from `bd` CLI commands.
It does not compose other skills directly -- it recommends them.

## Edge cases

If beads is not initialized (no `.beads/` directory), recommend `/issues-beads-init`.

If the graph has issues but all are closed, recommend `/session-plan` (same as empty active graph).

When multiple heuristics trigger, the priority order resolves the ambiguity: first match wins.
The output should note additional concerns below the primary recommendation when relevant.
