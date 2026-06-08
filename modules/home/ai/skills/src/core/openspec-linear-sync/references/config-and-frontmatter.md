# Config and frontmatter: the two-location binding

This reference defines where the Linear-story-to-OpenSpec-change binding lives, the openspec/linear.yaml monorepo registry schema, the per-change D10 sync ledger that now lives in proposal.md frontmatter, the Manual-mode binding location, the optional beads traceability map, and the ownership-boundary doctrine.

## The two-location binding with write-before-read ordering

The overlay is the write-owner of the primary cross-reference binding from a Linear story to an OpenSpec change, persisted across two locations at two altitudes.
openspec/linear.yaml is the monorepo-level registry: the workspace, a normalized teams registry, a normalized projects registry (with each project's archive documents), and shared defaults.
The proposal.md frontmatter is the per-change altitude: it carries the `linear_story_*` binding plus the per-change D10 local sync ledger.
A single repository's OpenSpec changes routinely bind to issues across many Linear teams and projects, and several changes run in parallel, so the per-issue ledger cannot live in a single flat top-level block in linear.yaml; it lives per change in that change's proposal.md frontmatter.

At the Backlog to Todo bind, the overlay writes the `linear_story_*` binding and initializes the D10 ledger into proposal.md frontmatter, and writes or updates the registry entries in openspec/linear.yaml for the chosen team and project at the same bind; each project's archive-documents entries are written at archive.

An issue always has a team but a project is optional, mirroring Linear's own cardinality, so `linear_team` is required in the binding and `linear_project` is optional and omitted entirely when the issue has no Linear project.
A project-less change is a fully supported terminal state, not a gap to close: it runs the full Backlog-to-Done lifecycle on the team board (states are team-scoped to `linear_team`) and archives cleanly, with only the archive-time Project Document mirror skipped because Linear Project Documents live under a project.
The registry `projects` map holds entries only for changes that have a project, so no placeholder project is ever fabricated; absence is represented as absence, and a project later assigned in Linear can set `linear_project`, add the project to the registry, and let the next archive populate its documents.

The proposal.md frontmatter carries these keys, written at the bind:

```yaml
---
linear_story_id:
linear_story_identifier:
linear_story_title:
linear_story_url:
linear_story_state:
linear_team:            # required; references teams.<TEAM-KEY> in openspec/linear.yaml
linear_project:         # optional (Option<slug>); omit entirely when the issue has no Linear project — references projects.<project-slug> in openspec/linear.yaml
# D10 local sync ledger (per change; the authoritative current-phase signal home):
last_synced_state:      # resolved in the context of linear_team (Linear workflow states are team-scoped)
last_synced_at:
review_round: 0         # bounded-retries counter; default max from linear.yaml defaults.max_review_rounds
max_review_rounds:      # optional per-change override of the linear.yaml default
attempt_log:
  - { at: "<iso-8601>", transition: "<from>-><to>", outcome: "dropped|failed|posted", note: "<short>" }
---
```

apply READS the `linear_story_*` binding and the D10 ledger from this frontmatter, so the write-before-read ordering is load-bearing: the overlay's bind step must precede any apply read.
When apply reads the frontmatter, the bind step has already written it.
`last_synced_state` and every transition target are resolved against the change's `linear_team`, because Linear workflow states are defined per team.

The `review_round` counter increments once per In Review to In Progress crossing, resets to zero on archive, and on exhaustion against `max_review_rounds` triggers the single escalation comment (see references/lifecycle.md); its default ceiling is `defaults.max_review_rounds` in openspec/linear.yaml, which a change may override via its own frontmatter `max_review_rounds`.
The `attempt_log` records dropped best-effort writes so a never-attempted transition is distinguishable from a failed one, and it is per change in this frontmatter.

## openspec/linear.yaml schema: the monorepo registry

openspec/linear.yaml is the monorepo-level registry: the workspace identity that drives the safety gate, shared defaults, a normalized teams registry, and a normalized projects registry where each project owns its archive documents.
It holds only what is invariant across the repository's changes; the per-issue binding and the per-change D10 ledger live in each change's proposal.md frontmatter (above).
The registry grows over time as new teams and projects are referenced; it is open for extension but models exactly what the overlay reads and writes — workspace, teams, projects, and per-project documents — and deliberately omits initiatives, cycles, milestones, labels-as-objects, sub-issues, and assignees.
The registry also assumes a single openspec/ root per repository; like the omitted object types, this is an extension point rather than a hard limit.

```yaml
workspace:
  slug: "<workspace-slug>"          # drives `linear --workspace` and the safety gate
  id: "<optional-workspace-id>"
defaults:
  archive_documents:
    enabled: true
    title_prefix: "OpenSpec:"
  max_review_rounds: 3              # default; a change may override in its frontmatter
  issue_label_filter:
    name: "<optional-default-label>"   # narrows Backlog candidates only; explicit no-label option at setup
teams:                              # normalized registry; keyed by Linear team key; grows over time
  "<TEAM-KEY>":
    id: "<linear-team-id>"
    name: "<team-name>"
projects:                          # normalized registry; keyed by a stable local slug; grows over time
  "<project-slug>":
    id: "<linear-project-id>"
    name: "<project-name>"
    teams: ["<TEAM-KEY>"]          # Linear projects can be shared across teams (many-to-many)
    archive_documents:             # documents belong to the project (Linear-faithful)
      "<capability-name>":
        id: "<linear-document-id-or-slug>"
        url: "<linear-document-url>"
        title: "OpenSpec: <capability-name>"
```

Teams and projects are sibling registries.
A project references its teams by key via `teams: [..]`, honoring Linear's many-to-many relationship between projects and teams; team identity is never nested under a project.
The project slug and team key are stable local identifiers, assigned once and never renamed, and are decoupled from Linear's mutable project and team display names because the registry value carries the immutable Linear id; a per-change `linear_project` or `linear_team` reference therefore stays valid even if the Linear project or team is renamed.
The `defaults.archive_documents` block carries only `enabled` and `title_prefix`; the per-capability document entries belong under each project's own `archive_documents`, because a Linear project owns its documents.
Each per-capability entry's `id` is the stored-id home that the archive-time UPSERT prefers over a title-match lookup; the UPSERT resolves the change's project from `linear_project`, iterates every capability, reads its stored id first, and on create writes the returned id back under that project's capability entry (see references/linear-cli-mapping.md).
A single change routinely produces multiple capability specs that each become their own Linear document under the same project, so each project's `archive_documents` map holds one entry per capability the change produces.

## Backward compatibility and migration

A legacy single-team/single-project openspec/linear.yaml — with top-level `team:` and `project:` blocks plus the flat top-level ledger fields (`last_synced_state`, `last_synced_at`, `review_round`, `max_review_rounds`, `attempt_log`) and a top-level `archive_documents.documents` map — is read as a one-entry registry.
The top-level `team:` becomes a single `teams` entry, the top-level `project:` becomes a single `projects` entry with `teams: [<that team>]` and the old `archive_documents` nested under it, and `defaults.max_review_rounds` and `defaults.issue_label_filter` adopt the legacy top-level values.
The flat top-level ledger fields belong to the single active change and migrate into that change's proposal.md frontmatter as its D10 ledger.

## Manual-mode binding location

Manual mode has no proposal.md and therefore no place to hold `linear_story_*` frontmatter, so its Linear binding lives in a beads issue field instead.
If team or project context is needed in Manual mode, it is recorded in that same beads field; the registry still resolves the team and project ids.
The two-location frontmatter-plus-openspec/linear.yaml mechanism is HIL-only, because only HIL authors an OpenSpec proposal.md to hold linear_story_* frontmatter; in AFK the binding home is the AFK plan file's own metadata (the Workflows or superpowers plan file is the proposal-equivalent), and in Manual mode the beads issue field is the single binding location.

The D10 sync ledger is HIL-only as well: only HIL has a proposal.md to hold it, so AFK and Manual carry no proposal.md-frontmatter ledger.
AFK's bounded-retries counter and attempt-log equivalents, where the AFK arm tracks them at all, live in the AFK plan file's metadata rather than in proposal.md frontmatter; wiring that AFK ledger home end-to-end is a separate future change.
The human is the regulator there, and lifecycle status is managed directly via the beads loop — the authoritative task ledger in Manual mode — and Linear.
Only the binding, plus optional team and project context, lives in the beads field; there is no `review_round` counter and no `attempt_log` in Manual mode.

## Optional beads-id traceability map

A beads-id traceability map is optional and applies only when a beads drill-down is actually used or in Manual mode.
It maps a beads issue or epic id to the OpenSpec change id (or, in AFK, to the superpowers plan path) for traceability and is never a second authoritative ledger.
The authoritative task ledger is selected by execution mode (tasks.md in HIL, the plan checkboxes in AFK, the beads loop in Manual); the traceability map only records the cross-reference, it does not own status.
CCPM's branch-name-as-binding convention may key this drill-down case to beads ids, but it is not the primary binding.

## Ownership-boundary doctrine

Linear owns the business "what": the business goal, use cases, personas and workflows, scope, acceptance criteria, and stakeholder-facing status, kept synchronized from the business-facing content in proposal.md.
This synchronization is operationalized at the Backlog to Todo bind, where the overlay seeds the Linear issue description with a stakeholder-facing TL;DR, deliverables, scope, and acceptance distilled from proposal.md's Why and What Changes, and is refreshed idempotently by the later sync and edit operations (see references/lifecycle.md and references/linear-cli-mapping.md).
The issue description therefore carries the business "what" only; the detailed technical design stays out of the issue body, per the keep-out boundary below.
The repo owns the technical "how": OpenSpec design decisions, tasks, implementation detail, migrations, tests, and code.
Canonical specs under `openspec/specs/` are the single source of truth; the Linear project documents written by the archive-time UPSERT are disposable mirrors, not the canonical source, and are fully replaced from repo canonical spec content at archive time.
Detailed technical design stays out of Linear issue descriptions and comments, and business context stays out of repo design and tasks except where needed to make a technical decision traceable.
