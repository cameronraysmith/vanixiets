## Why

Work decomposition is scattered across Linear, beads, OpenSpec plus superpowers, the session-* skills, and Claude Code Workflows with no skill that composes them without duplicating the work-item layer.
No skill binds a Linear story to its OpenSpec change, and the disabled Linear MCP leaves the linear-cli path undocumented for sync.
The result is ad hoc, duplicative tracking and no path for technical status to roll up to a team-visible surface.

## What Changes

This change introduces three agent skills, dogfooded as this very OpenSpec change so the build exercises the lifecycle it describes.
It establishes an ownership-by-layer model in which Linear and OpenSpec own the work and beads is demoted to an optional local execution sublayer, resolving the issue/task duplication hazard without mirroring any layer into another.

**Work-decomposition ownership**
- From: Linear, beads, and OpenSpec tasks.md each implicitly competing to own the work-item ledger, mirrored ad hoc.
- To: ownership-by-layer with a mode-conditioned task ledger (HIL → tasks.md, AFK → workflow/superpowers plan checkboxes, Manual → beads), and a single primary binding from Linear story to OpenSpec change.
- Reason: eliminate the largest duplication hazard surfaced by research.
- Impact: non-breaking; existing session-* and beads skills are unchanged and composed by delegation.

**Linear ↔ OpenSpec sync surface**
- From: no documented binding between a Linear story and an OpenSpec change; the only sync prior art (openspec-linearized) assumes the disabled Linear MCP.
- To: a linear-cli-driven overlay binding four forward lifecycle transitions (plus a re-queue and the Canceled/Duplicate terminals) to the eight-artifact superpowers-bridge, with a workspace safety gate and best-effort non-blocking writes.
- Reason: make technical status roll up to Linear safely without the MCP.
- Impact: non-breaking; additive overlay on existing OpenSpec and opsx skills.

This dogfood change is not itself synced to a Linear story; the Linear sync is the deliverable being built, not exercised on itself, and a real workspace mutation is out of scope.

## Capabilities

### New Capabilities
- `agentic-workflow-routing`: a state-machine router skill across a Linear-canonical board (Backlog → Todo → In Progress → In Review → Done, plus the inert Canceled/Duplicate terminals, with roborev and documenter as ordered sub-gates inside In Review) and an AFK/HIL/Manual execution-mode fork, composing existing skills by delegation and carrying jj and workspace isolation guidance for the HIL apply phase; lands in `modules/home/ai/skills/src/claude/`.
- `project-management-hub`: a human-facing project-management hub skill with a single flat `references/` directory whose four sub-areas (linear, github, beads, method) are expressed as filename prefixes and presented via a Contents table, synthesizing the Linear Method and CCPM ontology and carrying the Linear workspace safety gate; lands in `modules/home/ai/skills/src/core/`.
- `openspec-linear-sync`: a linear-cli-driven Linear-to-OpenSpec lifecycle-sync overlay skill, adapted (not ported) from openspec-linearized, binding four forward Linear state transitions (plus a re-queue and the Canceled/Duplicate terminals) to the eight-artifact superpowers-bridge with two-location story↔change linkage and archive-time spec mirroring; lands in `modules/home/ai/skills/src/core/`.

### Modified Capabilities
<!-- None. The three deliverables are additive new skills; existing skills are composed by delegation, not modified. -->

## Impact

New skill directories under `modules/home/ai/skills/src/claude/agentic-planning-development-workflow/` (router), `modules/home/ai/skills/src/core/project-management/` (hub), and `modules/home/ai/skills/src/core/openspec-linear-sync/` (sync overlay).
The skills tree is auto-discovered by `modules/home/ai/skills/default.nix` (`readSkillsFrom`), so no manual nix registration is required; src/core flows to all agents and src/claude is appended only to Claude Code.
Composes the bundled `linear-cli` skill and the vendored superpowers-bridge OpenSpec schema; depends on linear-cli credentials rendered immutable into a read-only (0400) inline credentials.toml (an OS-keyring mode is supported but not in use) and `openspec/linear.yaml` plus proposal frontmatter for the story↔change link.
No code paths, APIs, deployed services, or the contexts/*.md → CLAUDE.md symlink are touched.
