# Collaborators

The integrated front door is assembled from four collaborators across three skills.
This file names each one and what it owns; the front-door quickstart that walks the per-change flow lives at the top of the router's SKILL.md.

## The four collaborators

project-management is the human-facing project-management hub.
It owns the Linear Method ontology, the cross-layer conventions, and the workspace safety gate (the LINEAR_API_KEY and LINEAR_WORKSPACE asserts plus the `linear auth whoami --workspace <slug>` identity confirmation).
It documents the model and mutates no tracker.

agentic-planning-development-workflow is this router.
It owns the board spine, the execution-mode fork at the Todo to In Progress boundary, and the delegation map; it composes the other collaborators and re-implements none of their logic.

The openspec plus superpowers-bridge flow is the spec-first change lifecycle that the HIL mode delegates to.
It runs through the opsx:* and openspec-*-change skills plus superpowers:*, and it owns the eight bridge artifacts and the OpenSpec tasks.md authoritative ledger.

openspec-linear-sync is the linear-cli-driven Linear-to-OpenSpec lifecycle sync overlay.
It binds one Linear story to one OpenSpec change and mirrors each lifecycle phase to a Linear state through the four forward transitions and the archive-time document upsert.

## Ownership by layer

Linear and OpenSpec own the authoritative layers: Linear owns the business "what" with coarse parent status pushed up one-way, and OpenSpec plus the superpowers-bridge own the spec-first lifecycle and the within-change tasks.md ledger.
beads is an optional drill-down, not the default decomposition owner in the HIL or AFK paths; it is the authoritative ledger only in the Manual path.
