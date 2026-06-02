# Linear conventions

This reference states how a Linear issue is shaped, how status moves between layers, and how issues are sized and triaged.
For the ontology these issues live in see linear-overview.md; for the command verbs see the bundled linear-cli skill; before any mutation read linear-workspace-safety-gate.md.

## Issue body

The Linear issue body carries only three sections: a TL;DR, the Deliverables, and the Acceptance Criteria.
The TL;DR is a one-sentence statement of what the issue delivers.
The Deliverables enumerate what will exist when the issue is complete.
The Acceptance Criteria state how completeness is judged.

Status and progress never live in the body.
They live in Linear fields (the issue state, assignee, labels, cycle) and in comments.
An issue body that records "in progress" or "blocked on X" or a running checklist of done work is mis-shaped; that information belongs in the state field and in comments.
This keeps the body a stable description of the work rather than a mutable log, and it keeps the team-visible status surface in the fields where Linear renders it.

Use the SYNC/NOSYNC section markers (see linear-overview.md) so only the team-facing `[SYNC]` portion crosses to Linear and richer local detail stays in the OpenSpec requirements document, beads, or the repo.

## One-way status rollup

Status rolls up one way: local is authoritative, and Linear receives a coarse projection pushed up from below.
The detailed "how" lives in the local layer (the OpenSpec tasks.md in HIL, the plan checkboxes in AFK, the beads ledger in Manual), and Linear holds only a coarse parent-issue status.
Pushes are one-way from local to Linear; there is no bidirectional sync that would let a Linear edit overwrite the local ledger.
Because the push is best-effort, Linear is allowed to lag the local state, and the local milestone files remain the source of truth.
The openspec-linear-sync overlay implements this rollup; this reference states the policy, the overlay states the mechanics.

## Sizing and estimation

A right-sized issue is roughly three to ten distinct work items with one owner and about one to two weeks of work.
An issue larger than that should be split; an issue smaller than that is often better folded into a sibling.

Estimate at the parent-issue level on an exponential scale (1, 2, 4, 8, 16) rather than estimating every leaf work item.
A complexity-times-guidance alternative is available where exponential point estimation does not fit the team.
Estimation is for the parent issue as a unit of value; the leaf decomposition is tracked in the authoritative local ledger, not re-estimated in Linear.

## Triage versus backlog versus deferral

These three are distinct states, not synonyms for "not started."
Triage is for an item that needs a decision before it can be scoped at all; it is waiting on a human judgment, not on capacity.
Backlog is for an item that is definite but not yet sequenced; the decision is made, the work is real, it is simply unscheduled.
Deferral is for a temporary compromise with a recorded trigger; something was consciously set aside and there is an explicit condition under which it returns.
Keeping these distinct prevents a needs-a-decision item from silently sitting as if it were merely unsequenced, and prevents a deferred item from being lost because its return trigger was never written down.
