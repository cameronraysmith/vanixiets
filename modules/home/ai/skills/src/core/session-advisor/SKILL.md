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

## Decision inputs

Run the following diagnostic commands to gather routing inputs.
All complete in seconds.

1. `bd status` -- total open issues, ready/blocked counts, overall graph shape.
2. `bd epic status` -- epic child counts (detect 0/0 children containment antipattern).
3. `bd dep cycles` -- cycle count (must be zero for healthy graph).
4. `bd stale` -- issues with no activity beyond their age threshold.
5. `bv --robot-triage` (optional) -- structured data including signal table presence per issue, used to estimate signal table coverage.

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

1. Run diagnostic commands in order: `bd status`, `bd epic status`, `bd dep cycles`, `bd stale`, optionally `bv --robot-triage`.
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
