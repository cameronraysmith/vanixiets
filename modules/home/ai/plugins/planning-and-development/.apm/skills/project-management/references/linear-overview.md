# Linear overview

This reference states the Linear Method ontology that is the hub's spine and the issue-body section markers that govern what crosses to Linear.
It documents the model; it does not issue commands.
For the command verbs see the bundled linear-cli skill; before any mutation read linear-workspace-safety-gate.md.

## The ontology

Work decomposes through four nested levels, with one orthogonal overlay.

An Initiative is cross-project strategy.
It groups several Projects under a single directional intent and exists above any one change-set theme.

A Project is a directional document plus an objective.
It spans Milestones, and it links to the specs that define correctness rather than duplicating them; in this workspace the correctness-defining artifact a Project links to is the OpenSpec change and its requirements document.
A Linear Project corresponds to one OpenSpec change-set theme.

A Milestone is a completion-oriented phase, not a time box.
It leaves the system stable and forward-only when reached, typically gathering a small number of parent issues, and it is explicitly not scheduled by date.
A Milestone corresponds to a completion-oriented phase of the work.

An Issue is the unit of both value and behavior.
It carries a one-sentence deliverable and a bounded set of work items.
A Linear parent Issue corresponds to a beads epic when a beads drill-down is in use; see beads-overview.md for that mapping.

## Cycles as a scheduling overlay

Cycles are time-boxed sprints.
They are an orthogonal scheduling overlay laid across the ontology, not a fifth decomposition level.
An Issue belongs to a Milestone (completion-oriented) and may additionally be scheduled into a Cycle (time-boxed); the two are independent axes.
Do not decompose work into Cycles; decompose into Initiative/Project/Milestone/Issue and use Cycles only to schedule when issues are worked.
For teams that do not run sprints the completion-oriented Milestone model is sufficient on its own and Cycles can be omitted entirely.

## SYNC and NOSYNC section markers

The issue body is partitioned by section markers so that only the portion intended for the team-visible surface crosses to Linear.
Mark the team-facing portion of a body with a `[SYNC]` section marker and the local-only portion with `[NOSYNC]`.
Only the `[SYNC]` portion crosses to Linear; the `[NOSYNC]` portion stays local and is never pushed up.
This keeps the Linear issue body to the human-facing essentials (see linear-conventions.md for the TL;DR/Deliverables/Acceptance convention) while richer local detail remains in the OpenSpec requirements document, beads, or the repo.
The markers are reused by the openspec-linear-sync overlay so its mirroring respects the same boundary; the overlay never copies design.md or tasks.md to Linear regardless.
