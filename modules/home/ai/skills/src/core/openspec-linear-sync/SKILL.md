---
name: openspec-linear-sync
description: "linear-cli-driven Linear-to-OpenSpec lifecycle sync overlay that binds one Linear story to one OpenSpec change, mirrors lifecycle phase to Linear state, and runs the archive-time document upsert. Load when binding a Linear story to an OpenSpec change, mirroring lifecycle phase to Linear state, or running the archive-time document upsert."
---

# OpenSpec-Linear sync overlay

This overlay binds a single Linear story to a single OpenSpec change and projects the change's lifecycle phase onto the team-visible Linear board.
It is a thin link-and-sync policy layer over the OpenSpec change lifecycle: OpenSpec and the superpowers-bridge own the spec-first "how", Linear owns the business "what" and the stakeholder status surface, and `openspec/specs/` is the single source of truth.
The overlay never replaces any OpenSpec skill; layer it around the base `openspec-*` and `opsx:*` skills for normal artifact generation, task execution, and archive mechanics.

The overlay drives every Linear operation through the linear-cli binary and composes the bundled linear-cli skill for the verbs.
It recommends against the Linear MCP, which is disabled in this environment, and gracefully no-ops when linear-cli or its credentials are absent.
If `openspec/linear.yaml` is missing outside proposal setup, the Linear hook no-ops and normal OpenSpec work continues unblocked.

## Dependencies and degradation

This overlay depends on the bundled linear-cli skill (the single `linear-cli/` skill directory with its reference subfiles) for every Linear verb.
The linear-cli skill is contributed user-scoped for crs58 only; this overlay lands in `src/core` and so reaches all agents, but a non-crs58 agent that loads it would reference a linear-cli skill that is not present, which is accepted because crs58 is the only operator.

The overlay recommends against the Linear MCP and never invokes it, because the MCP is disabled in this environment.
Every Linear write after setup is best-effort and non-blocking: a failed or skipped write never blocks local progress, and the dropped write is recorded in the attempt log (see references/lifecycle.md).
When linear-cli is not on PATH, no `credentials.toml` default is configured, or `linear auth whoami` cannot confirm the workspace, the overlay logs the condition to the attempt log and continues local OpenSpec work, attempting no mutation.

## Setup and selection invariants

Setup asks a single question that selects the team and project context and offers an explicit no-label option, never inferring or auto-selecting a team, project, or label from names, ordering, or seemingly obvious matches.
The overlay never auto-selects a Backlog candidate: a candidate that could be inferred is still deferred to the human.
Spec content is mirrored to Linear only at archive time; no design.md or tasks.md content is ever copied to Linear.

The Linear workspace safety gate is the hardest constraint and is owned by the project-management hub's `linear-workspace-safety-gate.md`: never propose a mutation until `linear auth whoami` confirms the correct personal-versus-work workspace, key the gate on confirmed credentials rather than on LINEAR_WORKSPACE, pass an explicit `--workspace <slug>` (or rely on the confirmed `credentials.toml` default) on every mutation, and never run a mutating `linear auth` command.

## Contents

| Reference | Read it for |
|---|---|
| references/lifecycle.md | The four forward transitions, the In Review re-queue, the Canceled/Duplicate terminals, the invariants, the local sync ledger (idempotency, the strictly-behind rule, state-by-name resolution, graceful degradation, the bounded-retries counter, the attempt log), and the re-queue resume reconciliation. |
| references/linear-cli-mapping.md | The per-operation linear-cli verb mapping that replaces every MCP call, the archive-time document UPSERT recipe, the narrow `linear api` GraphQL fallback, and a full end-to-end worked example tracing one HIL issue Backlog to Done with literal commands. |
| references/config-and-frontmatter.md | The two-location story-to-change binding (openspec/linear.yaml store plus proposal.md `linear_story_*` frontmatter) with write-before-read ordering, the openspec/linear.yaml schema, the Manual-mode beads-field binding, the optional beads-id traceability map, and the ownership-boundary doctrine. |

## Phase summary

The overlay binds the eight-artifact superpowers-bridge lifecycle to Linear's canonical states via four forward transitions, a shared re-queue, and two terminal exits, covering every Linear state with none skipped.
proposal.md creation drives Backlog to Todo and writes the binding; the first checked tasks.md checkbox drives Todo to In Progress; verify.md creation drives In Progress to In Review; the successful archive step drives In Review to Done and runs the document UPSERT.
The In Review to In Progress re-queue fires on a verify.md checked-FAIL Overall Decision or a human sub-gate rejection, governed by a bounded-retries policy that escalates to the human PM layer on exhaustion; Canceled and Duplicate are inert terminals reachable from any active state.
The full transition table, gate firing conditions, ordering, and invariants live in references/lifecycle.md.
