# jj mode

Working branch isolation recipes for jj mode.
jj provides a development join (multi-parent working copy) that achieves the same simultaneous multi-branch editing as GitButler's applied-branches model.
All bookmarks coexist in a single working tree — no worktrees are needed.

## Creating a multi-parent working copy

Create a development join with multiple parent bookmarks:

```bash
jj new bookmark-a bookmark-b bookmark-c
```

The resulting `@` is a development join whose working tree merges all parent bookmarks.
Edits made in `@` can be routed (route elements to their chain) to any chain.

## Change routing

Route changes from the development join `@` to the appropriate chain:

```bash
# Manual: squash specific changes into a named chain element
jj squash --into <parent-bookmark> -u -- <path>

# Automatic: distribute changes based on blame ancestry
jj absorb
```

The `-u` (`--use-destination-message`) flag prevents the description merge editor from opening and preserves the target chain element's existing description.
`jj absorb` analyzes which ancestor last touched each modified line and routes changes automatically.
Use `jj squash --into` when changes belong to a specific chain element that blame cannot determine.

## Adding and removing parents

Modify the set of chains in the development join:

```bash
# Add a chain
jj rebase -r @ -d 'all:(@- | new-bookmark)'

# Remove a chain
jj rebase -r @ -d 'all:(@- ~ removed-bookmark)'
```

The `all:` prefix ensures the revset resolves to multiple parents rather than a single ancestor.

## Auto-rebase behavior

When a chain advances (via commits on that bookmark from another workspace or collaborator), jj automatically rebases `@` onto the updated parents.
This keeps the development join current without manual intervention.

## Epic and issue mapping

Bookmarks correspond to epics or independent work streams.
Changes within each bookmark's chain correspond to issues.
This mapping parallels the git-native worktree model and the GitButler stack model, but without filesystem separation.

Create a bookmark per active epic following the standard naming convention:

```bash
jj bookmark create {epic-ID}-descriptor
```

Build changes as a chain descending from each bookmark.
Each change in the chain corresponds to an issue within the epic:

```bash
# Start work on an issue within the epic
jj new {epic-ID}-descriptor
jj describe -m "feat: implement issue description"
# edit files...
jj new  # freeze and start next issue
```

When working across multiple epics simultaneously, create a development join over the active epic bookmarks:

```bash
jj new {epic-a}-descriptor {epic-b}-descriptor
```

Route changes from the development join `@` to the appropriate chain:

```bash
# Automatic: distribute changes by blame ancestry
jj absorb

# Manual: route specific changes to a named epic chain
jj squash --into {epic-b}-descriptor -u -- <path>
```

## Subagent dispatch in jj mode

In jj mode, subagents do not create bookmarks or worktrees.
All agents — including parallel agents — edit files directly in the shared `@` working copy.
The orchestrator routes changes to the correct chain via `jj absorb` or `jj squash --into <target> -u -- <path>` after each subagent completes.

When working in the development join, use a join + wip structure (two-commit pattern).
The development join integrates all parent bookmarks and has a description to prevent auto-abandonment.
The wip commit (`@`) sits on top for active edits.
`jj absorb` and `jj squash --into <target> -u -- <path>` route changes from wip to chains without disrupting the development join.

Coordination protocol: atomic one-file changes, periodic `jj log` review, prompt routing to keep `@` clean.
Subagent dispatch prompts specify which files to edit and the target chain context but do not include jj routing commands.
See the parallel agent coordination protocol in `~/.claude/skills/jj-version-control/SKILL.md` for the full model.

## Completing issues and epics

When an issue is complete, close the bead:

```bash
bd close {issue-ID} --reason "Implemented in $(jj log -r '{epic-ID}-descriptor' --no-graph -T 'commit_id.short(8)')"
```

To merge a completed epic to main, advance the main bookmark:

```bash
jj new
jj bookmark set main -r @-
jj git push --bookmark main
jj bookmark delete {epic-ID}-descriptor
```

## No direnv initialization needed

jj development joins operate in a single working tree, so the repository root's direnv environment applies to all chains.

## GitButler equivalence mapping

| GitButler | jj development join |
|---|---|
| Applied branches | Chains in development join `@` |
| `gitbutler/workspace` commit | Development join `@` commit |
| `but commit --changes` | `jj squash --into <target> -u -- <path>` or `jj absorb` |
| `but unapply` | Remove chain from join via `jj rebase -r @ -d 'all:(@- ~ bookmark)'` |
| `but apply` | Add chain to join via `jj rebase -r @ -d 'all:(@- | bookmark)'` |
| Branch stacks | Bookmark chains (linear descendant sequences) |
| `but move` (cross-stack) | `jj squash --from <src> --into <dst>` |

## Diamond workflow

When `.beads/` exists and an epic is active, the epic's issue dependency graph determines the jj bookmark chain topology.
Independent issues form an antichain of parallel bookmark chains.
Dependent issues produce chain stacking (one bookmark branching from another's tip), reflecting the covering relation in the issue partial order.

The diamond pattern proceeds through four phases.
The diverge phase decomposes the epic into bookmark chains based on `bd epic status`.
The develop phase creates an N-way development join (composite working copy) over all active chains using the join + wip structure, enabling concurrent development with continuous integration feedback.
The converge phase validates the integrated development join via testing and QA.
The serialize phase dissolves the development join and rebases each chain sequentially onto main as a linear extension of the dependency partial order, producing purely linear history with no merge commits.

The pattern generalizes conceptually beyond jj (GitButler's applied-branches model and git-native worktrees achieve analogous isolation), but the mechanical implementation leverages jj's multi-parent working copy.
For the full treatment including theoretical foundations, beads-to-jj mapping, and mechanical recipe, see `~/.claude/skills/jj-version-control/diamond-workflow.md`.

## See also

- [`SKILL.md`](SKILL.md) — top-level git version control principles and policy
- [`01-git-native-mode.md`](01-git-native-mode.md) — git-native mode isolation recipes
- [`02-gitbutler-mode.md`](02-gitbutler-mode.md) — GitButler mode isolation recipes
