# beads overview

This reference places beads in the PM model as an optional local fine-grained drill-down sublayer.
It documents where beads fits and how it maps to Linear; the bd CLI and the full beads workflow are the issues-beads skill, which this reference routes to rather than duplicating.
beads is not a second tracker competing with Linear or OpenSpec; it is a sublayer beneath the OpenSpec requirements document.

## The optional drill-down sublayer

beads sits below the OpenSpec requirements document as an optional local fine-grained sublayer.
It is invoked only when a complex task needs finer-grained tracking than the spec should carry, so the spec stays human-interpretable.
It is not the default decomposition owner in HIL or AFK modes; in those modes the OpenSpec tasks.md (HIL) or the plan checkboxes (AFK) own the within-change decomposition, and creating a parallel beads task list there would reintroduce the multi-tracker duplication hazard.
When beads is used as a drill-down, at most map the beads issue id to the OpenSpec change id or the superpowers plan path for traceability; do not mirror the spec's tasks into beads.

## Load-bearing in Manual mode

In Manual mode beads is load-bearing as the authoritative task ledger.
Manual mode has no OpenSpec change and no proposal.md, so the beads issue graph is the work-item ledger, driven through the session loop: /session-orient at the start, work, then /session-checkpoint, with session-advisor reading the beads graph metrics to route between the session skills.
This is the one mode where beads owns the ledger rather than acting as an optional drill-down; the agentic-planning-development-workflow router selects this mode and passes through to /session-orient.

## beads-epic to Linear-parent mapping

A beads epic corresponds to a Linear parent Issue, and the beads sub-issues under it correspond to the technical decomposition.
This is the rollup boundary: Linear holds the coarse parent-issue status and beads holds the local dependency graph and ready-queue, pushed up one-way (see linear-conventions.md).
In Manual mode, which has no proposal.md frontmatter to hold the binding, the Linear-story binding lives in a beads issue field rather than in OpenSpec frontmatter.

## Branch-name-as-binding for the drill-down case

For the beads drill-down case, the binding between the local issue and the work can be carried by the branch name, keyed to the beads id (the repo's branch-naming convention is `ID-descriptor`).
This is the CCPM branch-name-as-binding convention adapted to beads ids; the Linear parent is then derived from the beads epic.
It applies only when a beads drill-down is actually in use; the primary cross-reference for HIL and AFK changes is the per-change Linear-story-to-OpenSpec-change binding (story id and url, `linear_team`, and `linear_project`) stored in that change's proposal.md frontmatter, which openspec-linear-sync owns, while openspec/linear.yaml is the registry the team and project keys resolve against.

## Routing

For all bd commands, the epic and dependency conventions, status management, and the closure policy, use the issues-beads skill (quick reference: issues-beads-prime).
This hub does not restate them.
