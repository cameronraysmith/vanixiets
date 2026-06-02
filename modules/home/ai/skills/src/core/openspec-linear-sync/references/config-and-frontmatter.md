# Config and frontmatter: the two-location binding

This reference defines where the Linear-story-to-OpenSpec-change binding lives, the openspec/linear.yaml schema (including the local sync ledger fields), the Manual-mode binding location, the optional beads traceability map, and the ownership-boundary doctrine.

## The two-location binding with write-before-read ordering

The overlay is the write-owner of the primary cross-reference binding from a Linear story to an OpenSpec change, persisted in two locations: openspec/linear.yaml and the proposal.md `linear_story_*` frontmatter.
At the Backlog to Todo bind, the overlay writes `linear_story_*` into proposal.md frontmatter and writes or updates openspec/linear.yaml at the same bind; the documents map is written at archive.

The proposal.md frontmatter carries these keys, written at the bind:

```yaml
---
linear_story_id:
linear_story_identifier:
linear_story_title:
linear_story_url:
linear_story_state:
linear_team:
linear_project:
---
```

apply READS the `linear_story_*` frontmatter, so the write-before-read ordering is load-bearing: the overlay's bind step must precede any apply read.
When apply reads the frontmatter, the bind step has already written it.

## openspec/linear.yaml schema

openspec/linear.yaml holds the team and project context, an optional label filter, the archive-time documents map, and the D10 local sync ledger fields.

```yaml
team:
  id: "<linear-team-id>"
  key: "<team-key>"
  name: "<team-name>"
project:
  id: "<linear-project-id>"
  name: "<project-name>"
issue_label_filter:
  name: "<optional-label-name>"   # narrows Backlog candidates only; explicit no-label option at setup
archive_documents:
  enabled: true
  title_prefix: "OpenSpec:"
  documents:
    "<capability-name>":
      id: "<linear-document-id-or-slug>"
      url: "<linear-document-url>"
      title: "OpenSpec: <capability-name>"
# D10 local sync ledger fields (the authoritative current-phase signal home):
last_synced_state: "<linear-state-name>"   # for example "In Review"
last_synced_at: "<iso-8601-timestamp>"
review_round: 0                            # bounded-retries counter; default max 3, configurable
max_review_rounds: 3                       # documented configurability note
attempt_log:
  - { at: "<iso-8601>", transition: "<from>-><to>", outcome: "dropped|failed|posted", note: "<short>" }
```

The `review_round` counter increments once per In Review to In Progress crossing, resets to zero on archive, and on exhaustion against `max_review_rounds` triggers the single escalation comment (see references/lifecycle.md).
The `attempt_log` records dropped best-effort writes so a never-attempted transition is distinguishable from a failed one.
The `documents` map is keyed by capability name and stores one entry per capability the change produces, because a single change routinely produces multiple capability specs that each become their own Linear document under the same project.
Each per-capability entry's `id` is the stored-id home that the archive-time UPSERT prefers over a title-match lookup; the UPSERT iterates every capability, reads its stored id first, and on create writes the returned id back into that capability's entry (see references/linear-cli-mapping.md).

## Manual-mode binding location

Manual mode has no proposal.md and therefore no place to hold `linear_story_*` frontmatter, so its Linear binding lives in a beads issue field instead.
The two-location frontmatter-plus-openspec/linear.yaml mechanism is HIL/AFK-only; in Manual mode the beads issue field is the single binding location.

## Optional beads-id traceability map

A beads-id traceability map is optional and applies only when a beads drill-down is actually used or in Manual mode.
It maps a beads issue or epic id to the OpenSpec change id (or, in AFK, to the superpowers plan path) for traceability and is never a second authoritative ledger.
The authoritative task ledger is selected by execution mode (tasks.md in HIL, the plan checkboxes in AFK, the beads loop in Manual); the traceability map only records the cross-reference, it does not own status.
CCPM's branch-name-as-binding convention may key this drill-down case to beads ids, but it is not the primary binding.

## Ownership-boundary doctrine

Linear owns the business "what": the business goal, use cases, personas and workflows, scope, acceptance criteria, and stakeholder-facing status, kept synchronized from the business-facing content in proposal.md.
The repo owns the technical "how": OpenSpec design decisions, tasks, implementation detail, migrations, tests, and code.
Canonical specs under `openspec/specs/` are the single source of truth; the Linear project documents written by the archive-time UPSERT are disposable mirrors, not the canonical source, and are fully replaced from repo canonical spec content at archive time.
Detailed technical design stays out of Linear issue descriptions and comments, and business context stays out of repo design and tasks except where needed to make a technical decision traceable.
