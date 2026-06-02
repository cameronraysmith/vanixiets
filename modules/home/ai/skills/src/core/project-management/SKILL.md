---
name: project-management
description: Human-facing project-management hub for the Linear Method ontology, conventions, and the workspace safety gate. Load when reasoning about project/issue structure, Linear conventions, or how OpenSpec, beads, and GitHub relate as PM layers.
---

# Project management hub

This is the human-facing hub for how work is structured across the layers in this workspace.
It documents the project-management model, conventions, and constraints; it does not itself mutate any tracker.
Three other skills do the mechanical work and this hub routes to them by name rather than re-implementing them: the bundled linear-cli skill for raw Linear verbs, issues-beads for the local issue graph, and openspec-linear-sync for binding a Linear story to an OpenSpec change.

The spine of the model is the Linear Method ontology.
Work decomposes as Initiative greater than Project greater than Milestone greater than Issue, and Cycles sit orthogonally as a time-boxed scheduling overlay rather than as a decomposition layer.
An Initiative is cross-project strategy; a Project is a directional document plus an objective that links to (but does not duplicate) the specs that define correctness; a Milestone is a completion-oriented phase that leaves the system stable and forward-only; an Issue is the unit of both value and behavior.

The hub partitions into four sub-areas, each a separate concern a human consults independently.
Linear holds the business "what" and the team-visible status surface, and carries the hardest constraint in this whole hub: the workspace safety gate.
GitHub holds the pull-request, buildbot, and Mergify surface where a change's terminal artifact lands as one realization of the archived OpenSpec change.
beads is an optional local fine-grained drill-down sublayer below the OpenSpec requirements document, load-bearing only in Manual mode.
The method sub-area synthesizes the Linear Method and CCPM principles into the conventions that govern all of the above.

## Ownership spine

The single largest hazard in a multi-tracker workspace is having Linear, beads, and the OpenSpec tasks.md all compete to own the work-item ledger.
This hub resolves that by ownership-by-layer, not by mirroring one layer into another.
Linear owns the business "what" and coarse parent-issue status, pushed up one-way (local authoritative, Linear is a coarse projection).
OpenSpec plus the superpowers-bridge own the spec-first change lifecycle, the human-interpretable requirements document, and the within-change task decomposition in tasks.md.
beads owns the local dependency graph and is invoked for finer-grained tracking only when a complex task needs it; it is not the default decomposition owner.
The mode-conditioned task ledger (which layer is authoritative depends on execution mode) is the router's concern; see the agentic-planning-development-workflow skill for that selection, and openspec-linear-sync for the Linear binding.

## Contents

Read the workspace safety gate before proposing any Linear mutation.

### Linear

| File | Description |
|------|-------------|
| [references/linear-overview.md](references/linear-overview.md) | The Initiative > Project > Milestone > Issue ontology, Cycles as a scheduling overlay, and the SYNC/NOSYNC issue-body section markers |
| [references/linear-workspace-safety-gate.md](references/linear-workspace-safety-gate.md) | The hardest constraint: never mutate Linear until the workspace is confirmed via `linear auth whoami`; the five-tier credential precedence and why LINEAR_WORKSPACE is the wrong lever |
| [references/linear-conventions.md](references/linear-conventions.md) | Issue body = TL;DR + Deliverables + Acceptance Criteria only; status in fields/comments; one-way status rollup; sizing; triage versus backlog versus deferral |

### GitHub

| File | Description |
|------|-------------|
| [references/github-overview.md](references/github-overview.md) | The PR, buildbot, and Mergify surface; the monorepo PR (including docs/handbook) as one realization of the archived-OpenSpec-change terminal artifact |

### beads

| File | Description |
|------|-------------|
| [references/beads-overview.md](references/beads-overview.md) | beads as the optional local fine-grained drill-down sublayer; load-bearing in Manual mode; the beads-epic↔Linear-parent mapping and the branch-name-as-binding convention; routes to issues-beads |

### Method

| File | Description |
|------|-------------|
| [references/method-overview.md](references/method-overview.md) | Synthesized Linear Method + CCPM principles: the ontology, Cycles-as-overlay, sizing and estimation, triage/backlog/deferral, SYNC/NOSYNC markers, and projects linking to (not duplicating) the specs that define correctness |

## Related skills

This hub composes existing surfaces and never re-implements them.
For raw Linear command verbs invoke the bundled linear-cli skill.
For the local issue graph and the bd CLI consult issues-beads.
For binding a Linear story to an OpenSpec change and mirroring lifecycle phase to Linear state, use openspec-linear-sync.
For selecting an execution mode and driving the board between states, use the agentic-planning-development-workflow router.
