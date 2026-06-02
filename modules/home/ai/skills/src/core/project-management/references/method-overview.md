# Method overview

This reference synthesizes the Linear Method and CCPM principles that govern the hub's conventions.
It is original prose; it does not copy upstream text, and it does not adopt CCPM's `.claude/prds` plus `.claude/epics` filesystem or its bash scripts.
OpenSpec changes plus beads already occupy that decomposition niche; the discipline here is to extend those systems, not to stand up a parallel one.

## The ontology as the spine

The decomposition spine is Initiative greater than Project greater than Milestone greater than Issue.
An Initiative is cross-project strategy; a Project is a directional document plus an objective; a Milestone is a completion-oriented phase that leaves the system stable and forward-only; an Issue is the unit of both value and behavior.
This ontology cleanly partitions the design space and matches the ownership spine, which is why the hub adopts it rather than CCPM's PRD-to-Epic-to-Task chain.
See linear-overview.md for the per-level detail.

## Projects link to the specs that define correctness

A Project links to the specs that define correctness; it does not duplicate them.
In this workspace that correctness-defining artifact is the OpenSpec change and its requirements document.
The Project carries the directional "what" and points at the OpenSpec change for the precise "what is correct"; duplicating the spec content into the Project would create drift between two descriptions of the same correctness contract.
This linking discipline is the synthesis point between the Linear Method (Projects link to PRDs) and this workspace's spec-first lifecycle (OpenSpec owns the requirements document).

## Cycles as an orthogonal overlay

Cycles are time-boxed scheduling overlays, not a decomposition layer.
Decompose into Initiative/Project/Milestone/Issue and use Cycles only to schedule when issues are worked; the two are independent axes.
Where sprints are not run, the completion-oriented Milestone model suffices on its own.

## Issue sizing and estimation

A right-sized issue is roughly three to ten distinct work items, one owner, about one to two weeks.
Estimate at the parent-issue level on an exponential scale (1, 2, 4, 8, 16), with a complexity-times-guidance alternative where exponential points do not fit; do not estimate every leaf.
See linear-conventions.md for the body shape these sized issues carry.

## Triage, backlog, and deferral

Triage is for an item needing a decision before it can be scoped; backlog is for a definite-but-unsequenced item; deferral is a temporary compromise with a recorded return trigger.
Keeping the three distinct prevents a needs-a-decision item from masquerading as merely unsequenced and prevents a deferred item from being lost when its return trigger goes unrecorded.

## SYNC and NOSYNC markers

The issue body is partitioned with `[SYNC]` and `[NOSYNC]` section markers so that only the `[SYNC]` portion crosses to Linear.
This is the Linear Method's section-marker convention reused here so that the team-visible surface stays minimal while richer local detail remains in the OpenSpec requirements document, beads, or the repo.
The openspec-linear-sync overlay respects the same boundary and never copies design.md or tasks.md to Linear.

## What is borrowed from CCPM, and what is not

Borrowed: the branch-name-as-binding convention, applied to the beads drill-down case and keyed to beads ids (see beads-overview.md), and CCPM's discipline of an explicit, files-backed decomposition with bounded task counts per epic.
Not borrowed: the `.claude/prds` plus `.claude/epics` filesystem and the bash-script tooling around it.
The reason is the extend-not-parallel discipline — OpenSpec changes carry the requirements document and within-change tasks.md, and beads carries the local dependency graph, so a third filesystem-backed decomposition store would be a parallel system competing for the same role.
