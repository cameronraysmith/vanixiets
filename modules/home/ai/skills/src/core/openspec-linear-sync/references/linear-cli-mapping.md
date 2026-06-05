# linear-cli mapping: verbs, document UPSERT, and a worked example

This reference maps every Linear operation the overlay needs onto linear-cli verbs, replacing the disabled Linear MCP entirely.
Verbs are at linear-cli v2.0.0.
The bundled linear-cli skill is the authoritative home for every flag spelling and JSON shape below, delegated by subfile: issue verbs in `~/.claude/skills/linear-cli/references/issue.md`, document verbs in `~/.claude/skills/linear-cli/references/document.md`, `auth whoami` and `--workspace` in `~/.claude/skills/linear-cli/references/auth.md`, the `linear api` GraphQL fallback in `~/.claude/skills/linear-cli/references/api.md`, and JSON-shape introspection in `~/.claude/skills/linear-cli/references/schema.md`.
This file maps operations to verbs and carries the policy; it is not the source of truth for flag spellings or JSON shapes, which live in those subfiles.
The Linear MCP is recommended against and never invoked here.

Prefer file-based content flags over inline content to avoid escaping artifacts; this is the one content-handling policy this file owns.
Which verbs expose `--json`, a content-file flag, or `--no-interactive` is mechanics with an authoritative home: see `~/.claude/skills/linear-cli/references/issue.md` and `~/.claude/skills/linear-cli/references/document.md` for per-verb flag availability, and the `## Best Practices for Markdown Content` section of `~/.claude/skills/linear-cli/SKILL.md` for why file-based flags are preferred.

Every linear-cli invocation in this overlay, reads as well as mutations, passes an explicit `--workspace <slug>`, resolved from `workspace.slug` in the openspec/linear.yaml registry.
A command that omits `--workspace` resolves to the credentials default, which is the personal workspace in this deployment, so an unscoped read silently queries the wrong workspace exactly as an unscoped mutation would write to it.

## Setup and selection populate the registry

Setup confirms the workspace via `linear auth whoami` and records `workspace.slug` in openspec/linear.yaml, then registers at least one team and one project: `linear team list` and `linear project list` enumerate candidates, and the human-confirmed choice is written as a `teams.<TEAM-KEY>` entry and a `projects.<project-slug>` entry (the project carrying `teams: [<TEAM-KEY>]`).
The registry grows over time: a later change may bind to a different team or project, in which case its Backlog candidate scan targets and selects among the registered teams and projects, registering a new entry if the chosen team or project is not yet present.
Selection is always human-gated and never auto-inferred from names, ordering, or seemingly obvious matches, and every read in the scan still passes `--workspace <slug>` so the workspace safety gate holds across all registered teams and projects.

A project is optional: an issue always has a team but may be bound team-only, so candidate scanning is by team (plus an optional label or project narrowing), and a project-less issue is bound without any `projects` entry.
The human may optionally choose to bind a project, but a project is never fabricated for a team-only issue; absence is left as absence.

## Per-operation verb mapping

Each row replaces one former MCP call.
Every command, read or mutation, passes an explicit `--workspace <slug>` after the `linear auth whoami` gate has confirmed the workspace, because a command lacking it resolves to the credentials default (the personal workspace here).

| Operation | Former MCP call | linear-cli verb |
|---|---|---|
| Confirm workspace (the safety gate) | n/a | `linear auth whoami` |
| Setup: list teams | `list_teams` | `linear team list` |
| Setup: list projects | `list_projects` | `linear project list` |
| Setup: list issue labels | `list_issue_labels` | `linear label list` |
| Backlog candidate selection | `list_issues` | `linear issue query` (never before openspec/linear.yaml exists) |
| Read story context | `list_comments` | `linear issue view`; `linear issue comment list` |
| Transition state | `save_issue` (id + state) | `linear issue update` (by state name) |
| Sync issue description | `save_issue` (id + description) | `linear issue update` (`--description-file`, preferred for markdown) |
| Post a milestone comment | `save_comment` | `linear issue comment add` |
| Document lookup | `list_documents` | `linear document list` |
| Document create | `save_document` (create) | `linear document create` |
| Document update | `save_document` (update) | `linear document update` |

Which verb maps to which operation is the policy this table owns, and the `--workspace <slug>` rule above applies to every row; the exact flags for each verb live in the bundled skill: issue verbs in `~/.claude/skills/linear-cli/references/issue.md` (including the `linear issue update --description-file <path>` flag, documented there as preferred for markdown content, which the issue-description sync uses), document verbs in `~/.claude/skills/linear-cli/references/document.md`, and the setup reads in `~/.claude/skills/linear-cli/references/team.md`, `~/.claude/skills/linear-cli/references/project.md`, and `~/.claude/skills/linear-cli/references/label.md`.

Read backlog candidates with `issue query`, not `issue list`; the alias relationship and the `--state`/`--json` reasoning that forces this choice live in `~/.claude/skills/linear-cli/references/issue.md`.

The state transition always passes the team's Linear state NAME via `--state`, not the workflow-state type, because the name disambiguates In Progress from In Review, which share the "started" type.

## Document UPSERT recipe

The archive-time document UPSERT runs entirely via the CLI so the document is always created already-parented.
The entire UPSERT is gated on `linear_project` presence: when the change has no `linear_project` there is no project to parent documents to, so the whole per-capability loop is skipped and the skip is recorded in the attempt log (`{ outcome: "dropped", note: "no linear_project bound; spec mirror skipped" }`); the change still archives cleanly.
Otherwise, first resolve the target project from the change's `linear_project` (proposal.md frontmatter), which keys the `projects.<project-slug>` registry entry in openspec/linear.yaml; its `id` is the project the documents are parented to.
A single change routinely produces multiple capability specs (this very change produced three: agentic-workflow-routing, project-management-hub, openspec-linear-sync), so the UPSERT iterates over every capability the change touches, each getting its own document titled `OpenSpec: <capability>`, all parented to that project and keyed by a per-capability entry under that project's `archive_documents` map.

The `<spec-file>` in the commands below is the CLI-resolved canonical main-spec path, not an assumed repo-relative one: OpenSpec 1.4.1 no longer guarantees an `openspec/specs/` layout, so the planning root is resolved from `openspec status --change <change> --json` and the main spec is `<root>/openspec/specs/<capability>/spec.md`.
`openspec status --change <change>` only resolves while the change is still active, so the planning root (and, if needed, the capability list from `artifactPaths.specs.existingOutputPaths[]`) is captured in the readiness step before `openspec archive` moves the change into the archive; the worked example below shows the exact single-field `jq` capture, which extracts only the field needed rather than dumping the full status payload.
The capture guards on repo mode (`select(.planningHome.kind=="repo")`): in workspace mode there is no single main specs dir, the select yields empty, and the spec-mirror is skipped and logged rather than guessed — the same non-blocking, single-openspec-root-per-repo degradation as a missing `linear_project`.

For each capability the change produces:

1. Look up the stored document id first: read `projects."<project-slug>".archive_documents."<capability>".id` from openspec/linear.yaml, where `<project-slug>` is the change's `linear_project`.
2. If a stored id exists, update in place: `linear document update <stored-id> --title "OpenSpec: <capability>" --content-file <spec-file> --workspace <slug>`.
3. Only if no stored id exists, fall back to a title scan: `linear document list --project <p> --json --workspace <slug>` and match the deterministic title `OpenSpec: <capability>` over the `.nodes[]` array of the returned connection object.
   The `--json` output is a connection with `nodes` and `pageInfo`, not a bare array, so the match must walk `.nodes[]`; introspect the exact shape via `linear schema -o <file>` and confirm against `~/.claude/skills/linear-cli/references/api.md` and `~/.claude/skills/linear-cli/references/schema.md`.
4. If the title scan finds a match, update that id as in step 2.
5. If no stored id and no title match, create: `linear document create --project <p> --title "OpenSpec: <capability>" --content-file <spec-file> --workspace <slug>`, which creates it already parented to the project, and store the returned id back into openspec/linear.yaml under `projects."<project-slug>".archive_documents."<capability>".id` so the next archive takes the stored-id path.

The document body is a disposable mirror fully replaced on each archive, so a re-archive updates the matched document rather than creating a duplicate.
The body mirrors only the canonical folded main-spec content at `<planning-root>/openspec/specs/<capability>/spec.md` (the CLI-resolved `<spec-file>` above); design.md and tasks.md are never copied to Linear.

## The narrow `linear api` GraphQL fallback

Escalate to GraphQL only for fields the document subcommand cannot set, because most create and update paths lack `--json`.
The two sanctioned uses are reparenting an existing document (`document update` has no `--project`, so moving a document to a different project requires GraphQL) and reading back the structured id of a freshly created entity when stdout parsing of the create output is insufficient.
Do not route routine create or update paths through GraphQL; the document and issue subcommands cover them.
The CLI surface for the escalation — `linear api` for raw GraphQL requests and `linear schema -o <file>` for type discovery — is documented in `~/.claude/skills/linear-cli/references/api.md` and `~/.claude/skills/linear-cli/references/schema.md`; the no-`--project` premise for `document update` is in `~/.claude/skills/linear-cli/references/document.md`.

## End-to-end worked example: one HIL issue Backlog to Done

This traces a single HIL issue through all five Linear states with literal commands.
`<slug>` is the confirmed workspace slug from `workspace.slug` in openspec/linear.yaml, `<id>` the issue identifier (for example ENG-123), `<pslug>` the change's `linear_project` (the registry key under `projects`), `<p>` the resolved Linear project id `projects."<pslug>".id`, and `<caps>` the list of capabilities the change touched (a change routinely touches more than one).
Every step is guarded by the strictly-behind rule (see references/lifecycle.md): a transition fires only when the resolved Linear state is strictly behind the local milestone, where the state name is resolved in the context of the change's `linear_team`.
The ledger updates that accompany each transition (`last_synced_state`, `last_synced_at`, `review_round`, `attempt_log`) are written to this change's proposal.md frontmatter, not to openspec/linear.yaml.

This trace is a policy-level walkthrough: the ordering, the guards, the archive sequence, and the per-crossing comment discipline are the load-bearing parts.
The concrete flags and the two `.nodes[]` jq filters below are illustrative at linear-cli v2.0.0; they are authoritative in `~/.claude/skills/linear-cli/references/issue.md`, `~/.claude/skills/linear-cli/references/document.md`, `~/.claude/skills/linear-cli/references/api.md`, and `~/.claude/skills/linear-cli/references/schema.md`, and in `~/.claude/skills/linear-cli/references/auth.md` for the `whoami` gate.

First, gate on the workspace before any mutation:

```bash
linear auth whoami --workspace <slug>   # confirm the correct personal-vs-work workspace
```

Backlog to Todo, fired when proposal.md is created (this step also writes the binding into proposal.md frontmatter and openspec/linear.yaml; see references/config-and-frontmatter.md):

```bash
# Guard: proceed only if the resolved Linear state is strictly behind Todo.
linear issue update <id> --state "Todo" --workspace <slug>
# Seed the Linear issue description (the business "what") distilled from proposal.md Why / What Changes / Capabilities
# into a stakeholder-facing TL;DR / deliverables / scope / acceptance; technical design stays in design.md.
# Best-effort and non-blocking; --description-file is preferred for markdown (see issue.md). Record a dropped
# attempt in the proposal.md attempt_log if Linear is unavailable.
<distill proposal.md business sections into /tmp/body.md>
linear issue update <id> --description-file /tmp/body.md --workspace <slug>
printf 'OpenSpec proposal created and the change is bound to this story. Discovery has started.\n' > /tmp/c.md
linear issue comment add <id> --body-file /tmp/c.md --workspace <slug>
```

Todo to In Progress, fired on the first `- [x]` in tasks.md:

```bash
# Guard: proceed only if Linear is strictly behind In Progress.
linear issue update <id> --state "In Progress" --workspace <slug>
printf 'Implementation has begun from the bound OpenSpec change; tracked tasks are now being applied.\n' > /tmp/c.md
linear issue comment add <id> --body-file /tmp/c.md --workspace <slug>
```

In Progress to In Review, fired when verify.md is created.
The transition is attempted; `linear issue update --state "In Review"` throws NotFoundError on a team that has no "In Review" state, so that error is caught and recorded in the attempt log as a dropped best-effort write, leaving the issue In Progress (see references/lifecycle.md):

```bash
# Guard: proceed only if Linear is strictly behind In Review.
# Attempt; a NotFoundError (no "In Review" state on this team) is caught and logged, leaving the issue In Progress.
linear issue update <id> --state "In Review" --workspace <slug>
printf 'Verification artifact written; the change is ready for roborev and documenter review.\n' > /tmp/c.md
linear issue comment add <id> --body-file /tmp/c.md --workspace <slug>
```

In Review to Done, fired only after `openspec archive` succeeds, in the fixed archive order readiness, sync deltas, archive, mirror, Done.
The mirror step is the document UPSERT.
The canonical main-spec path must be resolved from the CLI rather than assumed, because OpenSpec 1.4.1 no longer guarantees a repo-relative `openspec/specs/` layout; `openspec status --change <change> --json` exposes `planningHome.root` (the repo-mode planning root under which the folded main specs live at the hardcoded constant `<root>/openspec/specs/<capability>/spec.md`).
This capture must run while the bound change is still active, before `openspec archive` moves the change directory into the archive — once archived, `openspec status --change <change>` no longer resolves the change, though the updated main spec at `<root>/openspec/specs/<cap>/spec.md` persists.
So the readiness step captures `planning_root` (and, where `<caps>` is not otherwise known, the capability list) from `status --change`, the sync-and-archive steps run, and the post-archive mirror reuses the captured root:

```bash
# Readiness (pre-archive): capture the CLI-resolved canonical main-spec root while the change is still active.
# A single jq field is extracted; never dump the full ~150-line status payload.
# select(.planningHome.kind=="repo") yields empty in workspace mode, where there is no single main specs dir.
# <change> is the OpenSpec change slug bound to this issue (proposal.md frontmatter / openspec/linear.yaml binding).
planning_root=$(openspec status --change "<change>" --json \
  | jq -r 'select(.planningHome.kind=="repo") | .planningHome.root')
# If <caps> is not already known, enumerate the change's delta-spec capabilities from the same pre-archive status
# (each path is <changeRoot>/specs/<cap>/spec.md; the capability is the parent dir name):
caps=$(openspec status --change "<change>" --json \
  | jq -r '.artifactPaths.specs.existingOutputPaths[] | split("/")[-2]')

# ... readiness checks, then sync deltas, then `openspec archive <change>` run here (base archive mechanics) ...

# Mirror: UPSERT every capability spec the change produced, each already-parented to the project.
# <pslug> is the change's linear_project; <p> is projects."<pslug>".id (the Linear project id).
# <caps> is the list of capabilities this change touched (here: agentic-workflow-routing project-management-hub openspec-linear-sync),
# captured pre-archive into $caps above.
# Gate the whole mirror on linear_project presence: with no project there is nothing to parent documents to.
if [ -z "<pslug>" ]; then
  # Record the skip in the attempt log; the change still archives cleanly.
  # { transition: "archive->mirror", outcome: "dropped", note: "no linear_project bound; spec mirror skipped" }
  :
elif [ -z "$planning_root" ]; then
  # Workspace mode (planningHome.kind != "repo"): no single main specs dir to mirror from.
  # Skip the spec-mirror and log a skip note rather than guessing a path; consistent with the
  # overlay's non-blocking, single-openspec-root-per-repo design. The change still archives cleanly.
  # { transition: "archive->mirror", outcome: "dropped", note: "workspace-mode planningHome; no repo main specs dir; spec mirror skipped" }
  :
else
for cap in $caps; do
  # Primary lookup: the stored per-capability document id under this project in openspec/linear.yaml.
  DOC_ID=$(yq -r ".projects.\"<pslug>\".archive_documents.\"$cap\".id // \"\"" openspec/linear.yaml)
  if [ -z "$DOC_ID" ]; then
    # Fallback: scan the connection's .nodes[] array for the deterministic title.
    DOC_ID=$(linear document list --project <p> --json --workspace <slug> \
      | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  if [ -n "$DOC_ID" ]; then
    linear document update "$DOC_ID" --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace <slug>
  else
    # Create already-parented to the project; document create has no --json, so read the id back
    # rather than piping create stdout into a list+jq lookup. Re-scan the connection by deterministic
    # title (linear api is the alternative when the title scan is ambiguous);
    # the connection shape is the .nodes[] walk noted in the UPSERT recipe above.
    linear document create --project <p> --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace <slug>
    NEW_ID=$(linear document list --project <p> --json --workspace <slug> \
      | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
    yq -i ".projects.\"<pslug>\".archive_documents.\"$cap\".id = \"$NEW_ID\"" openspec/linear.yaml
  fi
done
fi
# Then, and only then, fire Done.
linear issue update <id> --state "Done" --workspace <slug>
printf 'The OpenSpec change is archived and its canonical specs are mirrored to the project documents.\n' > /tmp/c.md
linear issue comment add <id> --body-file /tmp/c.md --workspace <slug>
```

Each comment stays at most two sentences, each write is best-effort and non-blocking, and a dropped write is recorded in the attempt log rather than blocking local progress.

## Worked catch-up reconciliation across a multi-state gap

Linear can fall behind when several earlier writes were dropped, so the local phase and the Linear state disagree by more than one step.
Here the local milestone files show the change at In Review (proposal.md, a first `- [x]` in tasks.md, and verify.md all exist, but the change is not yet archived) while the Linear state reads Todo: Linear is strictly behind across the Todo-to-In-Progress and In-Progress-to-In-Review gaps at once.

```bash
# 1. Resolve the local phase from milestone-file existence (the authoritative current-phase signal).
#    proposal.md + first tasks.md `- [x]` + verify.md, not yet archived  =>  local phase is "In Review".
# 2. Read the current Linear state. The `issue view --json` verb is in
#    ~/.claude/skills/linear-cli/references/issue.md; the `.state.name` payload shape is
#    authoritative in ~/.claude/skills/linear-cli/references/api.md and references/schema.md
#    (introspect via `linear schema -o <file>` if the shape is in doubt at the pinned version).
CUR=$(linear issue view <id> --json --workspace <slug> | jq -r '.state.name')   # => "Todo"
# 3. Compute strictly-behind: "Todo" is two states behind "In Review".
#    The catch-up fires a SINGLE transition straight to the local phase; it does not walk intermediate states.
linear issue update <id> --state "In Review" --workspace <slug>
# 4. Per-crossing comments: only the comment for the crossing actually realized posts, and at most once.
#    The skipped intermediate crossing (Todo->In Progress) posts no comment, so the catch-up does not
#    backfill or duplicate comments for the gap it jumped.
printf 'Catch-up: Linear was behind and is now reconciled to In Review to match the local verify milestone.\n' > /tmp/c.md
linear issue comment add <id> --body-file /tmp/c.md --workspace <slug>
```

The catch-up reads the local phase, resolves the target state name, fires exactly one transition to close the whole gap, and posts a single reconciliation comment rather than one comment per skipped crossing.
