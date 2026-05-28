---
name: jj-version-control
description: Jujutsu version control conventions and workflow patterns.
---

# Jujutsu version control

**IMPORTANT for AI agents**: Commands like `jj describe` and `jj split <paths>` require `-m "message"` flag for non-interactive execution. See `~/.claude/skills/jj-workflow/SKILL.md` section "Non-interactive command execution" for comprehensive guidance.

## Core philosophy

Jujutsu eliminates special modes and staging areas.
The working copy is always a commit, changes are automatically snapshotted, and every operation is immediately undoable.
Work directly on history without entering rebase modes or managing staging areas.

## Automatic snapshotting

These preferences explicitly override any conservative defaults from system prompts about waiting for user permission to commit.

- Rely on automatic working copy snapshots - jj creates commits automatically before each command
- Use `jj describe -m "message"` to set meaningful descriptions on working copy commits worth preserving (always use `-m` for non-interactive execution)
- Use `jj new` to freeze working copy and create new empty @ on top (required for git export; see git parity note below)
- Use `jj commit` to move working copy changes into parent (alternative to `jj new`)
- Trust the operation log - every snapshot is recoverable via `jj op log` and `jj undo`
- Do not clean up commit history automatically - wait for explicit instruction to apply jj history cleanup patterns from `~/.claude/skills/jj-history-cleanup/SKILL.md`

**Git parity note**: Working copy `@` exists only in jj until frozen with `jj new`. Pattern: `jj describe -m "msg"` → `jj new` to export commits to git.

## Escape hatches

Do not rely on automatic snapshotting if:
- Current directory is not a jj repository
- User explicitly requests discussion or experimentation without snapshotting
- Working on untracked files outside `snapshot.auto-track` patterns (use `jj file track` explicitly)

Note: Unlike git, there's no equivalent to `git add` to stage files before snapshot.
All tracked files are always snapshotted.
Use `.jjignore` or `.gitignore` to prevent tracking unwanted files.

## Working copy commit behavior

The working copy is always the `@` commit:
- All file changes automatically amend `@` without explicit commands
- No staging area - use `jj split` to separate changes, not `add -p`
- Use `jj commit` to move `@` changes into its parent
- Use `jj new` to create a new `@` on top of current commit

## Organizing atomic changes

Keep changes atomic and well-organized:

When working on `@`:
- Make related changes together, let them accumulate in `@`
- Use `jj split <paths> -m "message"` when changes diverge into separate concerns (always use `-m`)
- Use `jj describe -m "message"` to clarify purpose once scope is clear (always use `-m`)
- Use `jj new` to start next atomic change on top (freezes @ for git export)

When changes span multiple commits:
- Use `jj squash --from <commit> --into <target>` to move changes between any two commits
- Use `jj squash -i` to selectively move hunks from `@` into parent
- Use `jj absorb` to automatically distribute `@` changes to appropriate ancestors

File state awareness:
- Run `jj status` to see what's in current `@` before splitting or describing
- Run `jj diff` to review changes in `@` before operations
- Unlike git, no need to check staging area - working copy state is the commit state

## Session detection

When an agent detects `.jj/` alongside `.git/` in a repository root, jj colocated mode is active.
Detached HEAD is normal and expected in this configuration — do not attempt to reattach it.
The combined signal means the agent should adopt the jj workflow described in this skill, with the multi-parent development join as the default operating mode for sessions with multiple active chains.

For quick command orientation, see `~/.claude/skills/jj-summary/SKILL.md`.
For comprehensive command reference, see `~/.claude/skills/jj-workflow/SKILL.md`.
For git-mode equivalents and beads integration, see `~/.claude/skills/preferences-git-version-control/SKILL.md`.
For beads command quick reference, see `~/.claude/skills/issues-beads-prime/SKILL.md`.

## Bookmark workflow

Bookmarks are named pointers that don't move automatically with new commits.

Bookmark management:
- Bookmarks stay on their target when you create new commits (unlike git branches)
- Update bookmarks explicitly: `jj bookmark set <name> -r <commit>`
- Always work in "detached HEAD" state — this is normal in jj
- Create bookmarks for important points: `jj bookmark create <name>`

Integration with issue tracking:
- Use bookmark names like `issue-N-descriptor` for clarity
- When work diverges from current bookmark's purpose, create new bookmark at current `@`
- Example: bookmark is "issue-42-auth" but fixing unrelated bug → `jj bookmark create issue-58-logging`

Default bias: bookmarks are cheap, use them liberally to mark important commits.

### Bookmark creation threshold

Unlike git, where the `enforce-branch-before-edit` hook forces branching before any work, jj anonymous chains are first-class and never garbage-collected.
The trigger for bookmark creation is chain differentiation, not the first edit.

Three tiers govern when bookmarks become necessary:

1. *Single chain, ad hoc work*: no bookmark needed.
   Work on an anonymous chain descending from main.
   When done, freeze if needed and advance main.
   Always freeze before advancing — setting main to `@` directly is unsafe because bookmarks follow working-copy rewrites, so main would drift with every future edit.
   Check whether `@` is empty before freezing to avoid stacking redundant empty changes (`jj new` is not idempotent — each call creates a new empty change):

   ```bash
   # Freeze only if @ has content, then advance main
   jj log -r @ --no-graph -T 'empty' | grep -q true || jj new
   jj bookmark set main -r @-
   ```

2. *Second chain initiated*: bookmarks become required for both chains.
   Bookmark the existing chain tip, create a new chain from main, bookmark its tip, then create a multi-parent `@` over both.

3. *Beads epic session*: create bookmarks at session start following the `{epic-ID}-descriptor` naming convention.

The discipline is "create bookmarks at the moment you need to distinguish chains" — not "always create a bookmark before working."

## Operation log and recovery

Every jj operation is atomic and recorded:

Undo operations:
- `jj undo` - undo last operation (any operation, not just commits)
- `jj op log` - view complete operation history
- `jj op restore <id>` - restore repo to exact prior state
- `jj op show <id>` - see what an operation changed

Recovery patterns:
- Made mistake in last operation: `jj undo`
- Made mistake several operations ago: `jj op log` then `jj op restore <id>`
- Want to undo operation N but keep operation N+1: `jj op restore` to N-1, then manually redo N+1
- Concurrent operations created divergence: inspect with `jj log` and resolve with `jj bookmark set`

The operation log is your safety net - use it fearlessly.

## Conflict management

Conflicts are first-class citizens, committed and resolved when convenient:

Conflict workflow:
- Operations never fail due to conflicts - conflicts are committed with "conflict" marker
- Continue working on other commits while conflicts exist
- View conflicted commits: `jj log -r 'conflict()'`
- Resolve when ready: `jj new <conflicted-commit>`, fix files, `jj squash` resolution back
- Or resolve in place: `jj edit <conflicted-commit>`, fix files (automatically amends)

Conflict tools:
- `jj resolve` - launch merge tool for each conflict
- `jj resolve --list` - see all conflicts in current commit
- Conflict markers in files are automatically tracked - edit them directly or use merge tools

Never blocked by conflicts - they're just another commit state to handle when convenient.

## Change organization

Move changes between commits fluidly without special modes:

Squashing and moving:
- Move `@` into parent: `jj squash`
- Move specific files into parent: `jj squash <files>`
- Interactive squash: `jj squash -i` (choose hunks)
- Move between any commits: `jj squash --from <src> --into <dest>`
- Auto-distribute changes: `jj absorb` (moves changes to commits that last touched those lines)

Splitting and extracting:
- Split by paths (non-interactive): `jj split <paths> -m "message"` (always use `-m`)
- Split specific commit by paths: `jj split -r <commit> <paths> -m "message"`
- Create new commit on top: `jj new <commit>`
- Move working copy to new commit: `jj commit`

Editing commits:
- Edit commit directly: `jj edit <commit>` (checkout commit, changes amend it)
- Edit without checkout: `jj diffedit -r <commit>`
- Change description: `jj describe -r <commit> -m "message"`
- Duplicate commit: `jj duplicate <commit>`

All operations execute immediately and descendants auto-rebase.

## Revset-based workflows

Use revsets to operate on multiple commits:

Common revset patterns:
- Select by description: `jj log -r 'description(glob:"WIP:*")'`
- Select by author: `jj rebase -s 'author("name@example.com")' -d main`
- Select empty commits: `jj abandon 'empty()'`
- Select your commits not on bookmarks: `jj log -r 'mine() & ~bookmarks()'`
- Select conflicted commits: `jj log -r 'conflict()'`
- Select commits in range: `jj log -r 'A..B'` or `jj log -r 'B::A'`

Revset flags for rebase:
- `-r <revset>`: rebase only specified commits (not descendants)
- `-s <revset>`: rebase commit and all descendants
- `-b <revset>`: rebase commits reachable from revset but not from destination
- `-d <revset>`: destination (new parent)

Batch operations via revsets:
- Describe multiple: `jj describe -r 'author("alice")' -m "Alice's work"`
- Abandon multiple: `jj abandon 'description(glob:"tmp:*")'`
- Rebase multiple: `jj rebase -s 'mine() & ::@' -d main`

## Description conventions

- Use conventional commit format for descriptions that will be pushed
- Work-in-progress commits can have informal descriptions
- Use `jj describe -m ""` to clear placeholder descriptions
- Empty descriptions are fine for intermediate commits that will be squashed
- Update descriptions as changes evolve: `jj describe -r <commit> -m "new message"`

Description timing:
- Set descriptions on significant commits when their purpose is clear
- Leave WIP commits with empty or placeholder descriptions
- Batch update descriptions before pushing: `jj describe -r <commit>` opens editor

## History investigation

Use revsets and operation log for powerful history queries:

Finding changes:
- View evolution of single change: `jj evolog -r <commit>`
- Find when content changed: `jj log --patch -r 'file("path/to/file")'`
- Search in descriptions: `jj log -r 'description(glob:"*pattern*")'`
- Find commits touching paths: `jj log -r '~/path/to/file'` or `jj log path/to/file`
- Track bookmark movement: `jj log -r 'bookmark()' --op-log`

Operation archaeology:
- What changed in operation: `jj op show <id>`
- Diff between operations: `jj diff --from <op1> --to <op2>`
- Find when bookmark moved: `jj op log --op-diff` and search for bookmark name

Combined queries:
- Your changes to specific file: `jj log -r 'mine() & ~/path'`
- Recent changes by others: `jj log -r '~author("your@email") & @- ::@'`
- Abandoned commits in operation: `jj op show <id>` and look for "hidden" commits

## Bookmark synchronization

Coordinate with remotes explicitly:

Fetching and tracking:
- Fetch all remotes: `jj git fetch --all-remotes`
- Track remote bookmark: `jj bookmark track <name>@<remote>`
- Untrack remote bookmark: `jj bookmark untrack <name>@<remote>`
- View tracking status: `jj bookmark list` (shows `*` for out-of-sync bookmarks)

Pushing changes:
- Push bookmark: `jj git push --bookmark <name>`
- Push all changed bookmarks: `jj git push --all`
- Push all tracked: `jj git push --tracked`
- Create bookmark and push: `jj bookmark create <name> && jj git push --bookmark <name>`

Bookmark conflicts:
- Local and remote diverged: bookmark shows conflicted state in `jj bookmark list`
- Resolve by setting to desired target: `jj bookmark set <name> -r <target>`
- Or abandon one side: let operation log help you find the right target

## Session workflow pattern

Effective jj session structure:

Starting work:
1. Update from remote: `jj git fetch`
2. Review state: `jj log`
3. Create new commit: `jj new <base>` or work on existing `@`
4. Work freely - changes auto-snapshot

During work:
- Describe commits when purpose is clear: `jj describe -m "message"`
- Split when changes diverge: `jj split`
- Squash when changes belong together: `jj squash`
- Abandon mistakes immediately: `jj abandon <commit>` or `jj undo`

Preparing to push:
1. Review outgoing commits: `jj log -r 'main..@'`
2. Clean up descriptions: `jj describe -r <commits>`
3. Squash or split as needed
4. Set bookmark: `jj bookmark set <name> -r @`
5. Push: `jj git push --bookmark <name>`

After mistakes:
- Undo last operation: `jj undo`
- Check operation log: `jj op log`
- Restore to known good state: `jj op restore <id>`

## Session operation summary

After working session, provide operation summary: `jj op log --limit 20` to show recent operations.
This shows the actual work done, including undos and restores.

For commit-focused summary, use: `jj log --limit 10` to show recent commits on current branch.

When sharing work done, combine both:
- Operation summary: `jj op log --limit N` (where N covers session operations)
- Commit summary: `jj log -r 'bookmark()..@'` (commits not yet on any bookmark)

Use explicit operation IDs from session start if you noted them, otherwise count backwards from `@`.

## Diamond workflow: beads epic to jj chain topology

When `.beads/` exists and an epic is active, the epic's issue dependency graph determines the jj bookmark chain topology.
Independent issues (no dependency path between them) form an antichain of parallel bookmark chains developed concurrently.
Dependent issues (blocking relations) produce chain stacking where one bookmark branches from another's tip, reflecting the covering relation in the partial order.

The diamond pattern has four phases: diverge (decompose epic into chains from `bd epic status`), develop (work in the development join), converge (validate the integrated development join), and serialize (dissolve the development join and rebase chains sequentially onto main as a linear extension of the dependency partial order).
The development join is the working-copy entity used in the develop and converge phases — see the "Development join" section below for the entity definition.
Integration to main always uses sequential rebase linearization, never merge commits.

For the full theoretical foundations (lattice theory, event structures, VSM mapping), beads-to-jj mapping table, and four-phase mechanical recipe, see `diamond-workflow.md` in this directory.

## Development join

This section is the canonical entity-level reference for the development join: the multi-parent `@` structure, conflict semantics, edit-route cycle, route-and-extend pattern, composite-maintenance invariant, and integration strategies at completion.
For the canonical *process* recipe — the four-phase diamond workflow (diverge, develop, converge, serialize) that connects a beads epic graph to jj chain topology — see `diamond-workflow.md` in this directory.

The development join is the canonical entity for parallel multi-chain work in jj mode and the default operating mode for any session with two or more active chains.
This applies to every set of active parallel parent chains, regardless of where the parallelism originated: cross-mission coordination across sessions, cross-agent coordination within a team, and within-mission decomposition of a single epic or task into N independent streams all converge on the same entity.
Whenever a session has decomposed work into two or more streams that need to integrate, the development join is the operative surface — there is no separate "in-mission" structure that competes with it.

Sibling chains rooted directly off main without a shared join are an antipattern in this mode and require affirmative justification.
The justifying case is narrow: genuinely unrelated experiments that have no integration intent and whose conflict surface is uninteresting to observe.
Anything that will eventually merge, share validation, or be reviewed as a unit belongs in a development join from the moment the second chain is created.
Single-chain mode is the remaining exception, reserved for ad hoc work on one anonymous chain descending from main.

Definition: a two-commit structure consisting of a multi-parent `[merge]` commit (cardinality ≥ 2, each parent a chain tip — a bookmark or an anonymous chain head) and a `[wip]` commit on top where `@` resides.
The active chain tips form an antichain (a set of mutually independent commits in the partial order).
`[merge]` is frozen at creation and never edited; `[wip]` is ephemeral scratch space where in-flight edits land — forming the join + wip structure documented below.

Structure: `[merge]` is created by `jj new <bookmark-a> <bookmark-b> [...]` and described once with the state-based convention `join N=<cardinality>: <alphabetical, comma-separated parent chain bookmarks>` so it is never auto-abandoned and its description self-declares the current parent set.
`[wip]` is created by `jj new @` on top of `[merge]`, and `@` always points at `[wip]` while routing operations preserve it via `--keep-emptied`.
This structure provides continuous integration feedback (conflicts surface immediately as first-class conflicts in `@`), shared visibility, modular separation (each chain remains independently inspectable, pushable, and reviewable), and flexible integration (chains are linearized onto main via sequential rebase at completion).

Conflict behavior: when antichain elements contain conflicting changes, `@` displays first-class jj conflicts as a continuous integration signal — informational, non-blocking.
See "Conflict behavior in composite `@`" below for resolution options.

Lifecycle: created via `jj new <bookmark-a> <bookmark-b> [...] -m "join N=<cardinality>: <alphabetical bookmarks>"` followed by `jj new @ -m "wip"` when promoting from tier 2 to tier 3 (see `tiered-ceremony.md`); maintained via the edit-route cycle and route-and-extend pattern below, with the `[merge]` description rewritten in full whenever the parent set changes so it always declares the current state; dissolved during the four-phase diamond workflow's serialize phase, where chains are rebased sequentially onto main and fast-forwarded (see `diamond-workflow.md`).

Not to use for: workspace isolation needs.
The development join is the tier-3 mechanism for parallelizing related chains in one working copy.
For genuine filesystem isolation (e.g., concurrent unrelated experiments), `jj workspace add` is the explicit-request-only mechanism — see "Workspaces are not a tier" in `tiered-ceremony.md`.

Cross-references:
- `tiered-ceremony.md` — when to enter tier 3 (the trigger for using a development join at all)
- `diamond-workflow.md` — the four-phase process (diverge, develop, converge, serialize) in which the development join participates
- `~/.claude/skills/preferences-git-version-control/03-jj-mode.md` — mode-detection context and equivalences with git-native and GitButler modes

### Two-commit structure: join + wip structure

The development join always uses a canonical two-commit structure: a frozen multi-parent `[merge]` commit with an ephemeral `[wip]` commit on top, where `@` is `[wip]`.

```
parents...  →  [merge] (FROZEN, multi-parent, "join N=<cardinality>: ..." description)
                  |
                  └→ [wip] (@, working copy, ephemeral description)
```

Per Krycho's canonical model, `[wip]` sits on top of `[merge]` precisely so that `[merge]` is never edited after creation and `[wip]` serves as scratch space whose description need not be maintained.
Reference: Chris Krycho, ["Jujutsu Megamerges and jj absorb"](https://raw.githubusercontent.com/chriskrycho/v5.chriskrycho.com/3f330be8861378587da76f33fe272799f5b84d97/site/journal/2024/Jujutsu%20Megamerges%20and%20jj%20absorb.md) (2024-12-24); local cache: `docs/notes/development/version-control/references/krycho-jujutsu-megamerges-and-jj-absorb.md`.

The `[merge]` commit is created by `jj new <bookmark-a> <bookmark-b> [...]` and described once at creation following the state-based convention `join N=<cardinality>: <alphabetical, comma-separated parent chain bookmarks>` (for unbookmarked parents, use the short change_id wrapped in backticks).
The description thereby self-declares the current join state from its own text, so the reader knows the full parent set without inspecting the graph:

```
join N=3: bookmark-a, bookmark-b, bookmark-c
```

A join with an unbookmarked parent renders as `join N=3: bookmark-a, bookmark-b, `xqnqupun``.
The history of join modifications (extensions, parent removals) is preserved in `jj op log`; the description records the current state, not the event that produced it.
This makes the convention robust against `[merge]` orphan abandonment and verifiable as an invariant against `jj log -r @- -T 'parents...'`.
After creating `[merge]`, immediately create `[wip]` on top with `jj new @ -m "wip"` (or any ephemeral description); this becomes `@` where all edits land.
The `[merge]` commit is FROZEN once created — it is never described, edited, or routed into.
The `[wip]` commit's description is ephemeral and does not need to be recovered after routing operations.

Squashing from `@` into chain elements with `--keep-emptied` auto-rebases both `[merge]` and `[wip]` while preserving the two-commit structure.
If `[wip]` is disrupted, the `[merge]` commit still exists — recover with `jj new <merge-change-id>` to recreate the wip layer.

### Diamond invariants

The development join is structurally correct iff all six of the following invariants hold simultaneously.
They are stated as a numbered list so individual invariants can be referenced unambiguously elsewhere in the skill tree.

(i) chain ∈ join's parents — every active chain bookmark is a parent of `[merge]`.
A bookmark whose tip is not in `parents([merge])` is an orphaned chain: its content is invisible to `[wip]` and absent from any integrated validation run on the development join.

(ii) join parents = current bookmark targets — there is no staleness between `[merge]`'s parent revisions and the current targets of the chain bookmarks named in `[merge]`'s description.
Auto-rebase normally maintains this invariant in place; when `jj rebase -r <merge>` is used deliberately (e.g., the chain-creation-mid-diamond recipe), the required successor `jj rebase -r <wip> -d <merge>` keeps `[wip]` attached — see "Re-attaching `[wip]` after `jj rebase -r <merge>`" below.

(iii) `@` atop the join — `@` is at `[wip]` whose sole parent is `[merge]`, or `@` IS `[merge]` during construction.
This is the maintenance invariant historically named in this section; the other four invariants are now peer to it.

(iv) wip holds integrated working tree — `[wip]` is where edits land; its working tree reflects the union of all chain contents.
Parallel agents observing `[wip]` see the integrated state of every chain in the join, which is the primary value proposition of the entity.

(v) append-not-squash for chain routing — chains are extended via new commits (the route-and-extend recipe below) rather than by amending existing bookmark commits.
Conflating extension with amendment collapses the chain's commit-level history and breaks the per-issue review granularity the diamond workflow exists to provide.

(vi) `[merge]` has a single `[wip]` on top — there is exactly one ephemeral working-copy commit as immediate descendant of `[merge]`.
Multiple sibling `[wip]`s as children of `[merge]` violate this invariant: they partition the working surface and break the contract — explicit in the join + wip structure above and in Krycho's canonical model — that edits land in `[wip]` precisely so `[merge]` stays frozen as the canonical join representation.
Per-stream wips (one `[wip]` per parent chain) are the recurring antipattern: they re-introduce the per-chain working surfaces that the single shared `[wip]` exists to replace, and they hide cross-chain conflicts that the integrated `[wip]` would have surfaced immediately.
The canonical routing primitives that preserve this invariant are the append-route (`jj squash --from @ --insert-after <chain-tip> -m "msg" --keep-emptied` followed by `jj bookmark move <chain> --to <new-commit-id>`, where `<new-commit-id>` is the change ID jj prints in its `Created new commit <id>` line) for landing new atomic commits on a chain, and the amend-route (`jj squash --from @ --into <chain-tip> --keep-emptied`, with `-m` omitted) for fixups against the existing tip; see "Routing to a chain: append vs amend" under §"The edit-route cycle" below.

### Composite maintenance invariant (development join invariant)

Invariant (iii) above is the maintenance invariant: the join + wip structure requires active maintenance when operations move `@` away from `[wip]`.

Before any operation that moves `@` (like `jj new <single-parent>` or `jj edit`), verify and record `[merge]`'s change ID.
After any such operation, immediately restore `[wip]` on top: `jj new <merge-change-id> -m "wip"`.
When adding a new bookmark to the development join, reconstruct `[merge]` with all parents including the new one (re-set the description to the new `join N=<cardinality>: <alphabetical bookmarks>` state), then recreate `[wip]` on top.
Subagent prompts must specify whether they operate in `[wip]` (edit files, let orchestrator route) or outside it (e.g., working on a single chain directly).

#### Idle vs mid-operation states

The invariants above describe the diamond's *idle* state — when `@` is empty `[wip]` directly above the join and no chain extension or splice authoring is in progress.
During mid-operation states the strict invariants are transiently relaxed:

- *In-chain editing* (via `jj new --insert-after <chain-tip>`, the route-and-extend single- or multi-commit-range form): `@` sits in a chain, as a descendant of a chain tip that is not at-or-above the join.
The chain bookmark has not yet been advanced to the new chain tip, so the join's parent set briefly disagrees with the bookmark set declared in the join's description.
- *Splice-below-join by-construction* (via `jj new --insert-before 'children(fork_point(parents(<join>))) & ::<join>'`): `@` sits in a linear non-merge stack above the join during authoring.
- *Stack above the join awaiting splice or route* (an intermediate state in which docs commits are stacked linearly above the join before the splice or route-and-extend is executed): same topology as splice-by-construction.

The `verify-diamond-before-edit` PreToolUse hook recognizes four valid `@` positions corresponding to these states:

| Case | Position | Workflow state |
|---|---|---|
| (A) | `@` IS the join | construction-time, before adding `[wip]` |
| (B) | `@` is a direct child of the join | idle wip |
| (C) | `@` is in a linear non-merge stack above the join | splice-by-construction in-progress; stack-above-join awaiting splice/route |
| (D) | `@` is in a chain (descendant of a chain tip, not at-or-above the join) | route-and-extend in-progress; in-chain editing |

Checks (i)/(ii) — bookmark-vs-parent consistency — run only in cases (A) and (B), since cases (C) and (D) by construction produce a transient bookmark/parent mismatch that the in-progress operation reconciles when it advances the relevant bookmark.

The hook fires `ask` (never `deny`) when `@` is in none of these four positions — typically when work has been routed onto an unrelated branch, when an unintended merge has been introduced, or when the working copy has drifted off the diamond entirely.
The recovery hint depends on intent: return to idle via `jj new <join-change-id> -m "wip"`, or resume in-chain work via `jj edit <chain-tip-change-id>`.
See `modules/home/tools/hooks/verify-diamond-before-edit.sh` for the enforcement implementation.

### Diamond-health diagnostic

A single revset surfaces all six invariants in one view, suitable for an initial orientation pass or a mid-session health check:

```bash
jj log -r 'present(@) | ancestors(immutable_heads().., 2) | trunk()'
```

Reading the output against the invariants:

- `@` shown with a single parent line up to `[wip]` confirms invariant (iii); a divergent `@` away from `[wip]` indicates the maintenance step was skipped after a `@`-moving operation.
- the multi-parent `[merge]` commit with description `join N=k: <bookmarks>` confirms invariant (i) when the declared bookmarks match the actual parent bookmarks shown in the graph; a mismatch indicates an orphaned chain or a stale description.
- the chain bookmarks shown at the immediate parents of `[merge]` confirm invariant (ii); a bookmark drawn one or more commits above its corresponding `[merge]` parent indicates parent-set staleness (the bookmark has advanced but `[merge]` has not).
- inspecting `jj diff @` against the union of chain tips confirms invariant (iv); discrepancies indicate routing operations that bypassed `[wip]` or a disrupted `[wip]` recreation.
- inspecting each chain via `jj log -r 'main..<bookmark>'` confirms invariant (v) when the chain shows incremental commits rather than a single amended bookmark commit.
- the immediate-children revset `jj log -r '<merge-change-id>+'` confirms invariant (vi) when it returns exactly one commit (`[wip]`); two or more rows indicate sibling per-stream wips and require collapsing back to a single shared `[wip]` before resuming routing.

### Pre-edit cross-chain file-collision reconnaissance

While `[wip]` (the working-copy commit above the development join) presents an integrated view of all chains' modifications, editing a file there commits a new modification that must be routed to one chain — and that choice interacts with whichever other chains have already modified the same file.
A development join whose parent chain tips form an antichain in the commit poset guarantees that the chains are pairwise mergeable at the commit level; it does NOT guarantee that further modifications routed to one chain will compose cleanly with modifications another chain has already applied to the same file region.

Before any edit to a file in `[wip]`, run a cross-chain file-collision reconnaissance query:

```bash
PAGER=cat jj log -r 'fork_point(parents(@-))..@- & files("<relative-path>")' \
    --no-graph -T 'change_id.short() ++ " " ++ bookmarks ++ " " ++ description.first_line() ++ "\n"'
```

The revset selects commits in the half-open interval `meet..join` between the meet (`fork_point(parents(@-))` — the greatest common ancestor of the antichain formed by `[merge]`'s parents; note that `fork_point()` of a single commit is a no-op per upstream `docs/revsets.md:349-353`, so `parents(@-)` must be applied to obtain the N-element antichain before computing the meet) and the join (`@-` — `[merge]` itself).
`& files("<path>")` restricts to commits that modified the named file.
For multi-file queries, prefer the fileset union form inside one call: `files("a | b")` (per upstream's `docs/filesets.md`), over the revset-level union `files("a") | files("b")`.

Output interpretation:

| Result | Meaning | Routing implication |
|---|---|---|
| Zero rows | No chain has touched the file | Route to the semantically appropriate chain; choice unconstrained by collision |
| Rows from exactly one chain | One chain owns prior touchpoints | Route the new change to that chain via append-route, amend-route, or absorb-route (see §"Routing to a chain") |
| Rows from two or more chains | Cross-chain file collision exists | STOP. Apply one of the three resolution patterns documented in the `reference_jj-diamond-cross-chain-file-collision` memory before proceeding. |

The reconnaissance has constant cost (one `jj log` invocation) regardless of diamond size, and prevents structural conflicts at `[merge]` that would otherwise surface during Phase 4 serialize and require post-hoc resolution.

The same query applies at chain creation: before issuing the chain-creation-mid-diamond recipe (`diamond-workflow.md:161-190`) to introduce a new chain into an active diamond, run the reconnaissance against the new chain's planned file scope.
If a collision exists, either route the planned work into the existing chain that already owns those touchpoints (no new chain needed) or apply the collision-resolution patterns from `reference_jj-diamond-cross-chain-file-collision` before proceeding with chain creation.

The same file-collision check appears as a precondition of the splice-below-join by-relocation arm — see §"Splice-below-join" → Precondition: relocation file-disjointness — where the check is applied to a *relocation set* rather than a *forthcoming edit*.
Both consumers operate on the same underlying question ("which chains touch which files?") and the same revset machinery; the splice-below-join consumer adds the alternative-on-collision options (route-and-extend, new-chain creation, defer to Phase 4 serialize) when the check fails.

#### Semantic invariant of `[merge]`

The development join's `[merge]` commit IS the join (∨, least upper bound) of its parent antichain in the commit poset.
This join exists if and only if all parents are pairwise mergeable.
Cross-chain file-collision reconnaissance is the operational check that this mergeability holds with respect to the specific file under edit before the edit creates a new modification.

### Pre-dispatch concurrent-agent coordination

When known concurrent agent activity exists on a development join — the user has flagged another session as in-progress, or `jj op log` shows recent ops from an unfamiliar source — verify chain state IMMEDIATELY before each chain-touching dispatch (not just at design time) and serialize ordering with the other agent explicitly. The pre-edit recon above catches different-FILE collisions across chains; this catches concurrent-AGENT mutations against the same chain, where two agents independently issue `jj squash --insert-after <tip>` in overlapping windows and produce divergent `@` and `[merge]` change IDs. Recovery is mechanical (`jj edit <survivor-commit-hash>` to retarget `@`, then `jj abandon <stale-wip-hash> <stale-merge-hash>` using commit hashes to disambiguate across divergence) but pause-and-serialize prevents the failure altogether.

### The edit-route cycle

All edits land in `@` (which is `[wip]`).
The discipline is to route each completed change from `@` into the correct chain commit, preserving `[wip]` empty on top of the frozen `[merge]`.

#### Routing to a chain: append vs amend

Each route from `[wip]` to a chain X is one of two semantically distinct operations, and the right recipe depends on intent.
The default for landing new atomic work is the append-route: the edit-set becomes a NEW commit on chain X, the chain grows by one commit, and X's bookmark advances to the new tip.
The amend-route is reserved for fixups against the SAME commit already at the chain's tip — correcting a typo, adding a missed file, or otherwise refining the existing tip commit in place.
Conflating the two collapses per-issue history and overwrites descriptions silently; the two recipes are not interchangeable.

Append-route (default for atomic landing):

```bash
SQUASH_OUT=$(jj squash --from @ --insert-after <chain-tip> -m "msg" --keep-emptied -- <paths>)
echo "$SQUASH_OUT"
NEW_ID=$(echo "$SQUASH_OUT" | sed -n 's/^Created new commit \([a-z][a-z0-9]*\) .*/\1/p')
jj bookmark move <chain> --to "$NEW_ID"
```

The `--insert-after` (alias `-A`) flag is what makes this an append rather than an amend; per the EXPERIMENTAL FEATURES doc comment at `cli/src/commands/squash.rs:51-84`, `-o`/`-A`/`-B` switch `jj squash` into create-a-new-commit mode rather than merging into an existing target.
`@` (`[wip]`) returns to empty atop the auto-rebuilt `[merge]`, so the join + wip structure is preserved across the route.
The bookmark-move is a separate explicit step: jj does not auto-advance a bookmark onto a newly inserted commit, so omitting it leaves the bookmark pointing at the prior tip.

Use the change ID surfaced in the `Created new commit <id>` line that `jj squash --insert-after` prints, not `@-`, as the bookmark-move target.
In a multi-parent development join, `@-` resolves to `[merge]` after the squash because the new commit becomes one of `[merge]`'s parents (and `[wip]` is rebased onto the rebuilt `[merge]`), not a direct ancestor of `@`.
Aiming the bookmark-move at `@-` therefore advances `<chain>` onto `[merge]`, requiring a corrective `jj bookmark move <chain> --to <correct-id> --allow-backwards`.
Revset-based capture also returns the wrong target: `heads(::<chain>)` and `parents(<merge>)` both resolve to the chain's prior tip (the bookmark's previous target), not the newly inserted commit, because the new commit is structurally a sibling-then-rebased-parent of `[merge]` rather than a descendant of the bookmark's prior position. Always parse the stdout line.

Amend-route (fixups only):

```bash
jj squash --from @ --into <chain-tip> --keep-emptied
```

Omit `-m` here so the chain-tip's existing description is preserved; adding `-m` to the amend-route OVERWRITES the chain-tip description in place.
Use this form only when the intent is genuinely to refine the existing tip commit, never to land a new logical change.

The most common failure mode is running the amend-route N times with N different `-m` strings, expecting N commits to appear on the chain: that sequence instead accumulates N diffs into the same chain-tip commit and overwrites the description N times, yielding one commit with the last message and a conflated diff.
If N atomic landings are intended, run the append-route N times.

A third flavor, **absorb-route**, uses `jj absorb` instead of explicit-target `jj squash`.
Krycho's article *Jujutsu Megamerges and `jj absorb`* (https://v5.chriskrycho.com/journal/jujutsu-megamerges-and-jj-absorb/) establishes absorb as the preferred verb when ownership is unambiguous: absorb examines blame and routes each change in `[wip]` to the closest mutable ancestor that last modified the same lines.
When the pre-edit reconnaissance has confirmed exactly-one-chain ownership for every file in `[wip]`, absorb is safer than manual squash because it refuses to act when ambiguity would force a choice ("if it is not truly unambiguous… it will choose not to do anything at all").

```bash
# Absorb-route: auto-distribute changes in @ to their semantic homes by blame ancestry
PAGER=cat jj absorb
```

Use absorb-route when: pre-edit recon returned exactly-one-chain rows for every file modified in this `[wip]` cycle, AND blame ancestry will resolve each change unambiguously to a single chain commit.
Fall back to append-route or amend-route when: any file modified has zero rows (no chain owns it yet — absorb has nowhere to route) or multiple-chain rows (collision — manual decision required).

Across both recipes, three flags are load-bearing.
`--from <source>` is explicit source selection; a bare `--into` is a no-op when `@` is empty, so the flag is required to express intent unambiguously.
`-m "..."` supplies the commit message inline and is mandatory in agent setups without a TTY (see the top-of-skill note on non-interactive execution) — but in the amend-route it must be omitted to preserve the tip's existing description.
`--keep-emptied` preserves `@`'s presence as `[wip]` across the route; without it, an empty source is abandoned and the join + wip structure is disrupted.

When amending an existing chain commit, the canonical routing operation is `jj squash --from @ --into <chain-tip> --keep-emptied`.
`--keep-emptied` preserves the empty `[wip]` commit after its diff is squashed into the target, maintaining the canonical two-commit structure.
`[merge]` is never touched by any routing operation.
`[wip]`'s description is ephemeral, so no description-recovery step is required after the squash.

The cycle proceeds as follows:

1. Edit a file in `@` (the `[wip]` commit)
2. `jj squash --from @ --into <chain-tip> --keep-emptied` — routes the diff into the chain commit, preserving `[wip]`
3. `jj log` — verify the change landed in the correct chain and `[wip]` is empty
4. Repeat

`jj absorb` is the auto-routing variant.
It distributes hunks to the closest mutable ancestor based on blame ancestry and automatically preserves `[wip]` without requiring `--keep-emptied`.
In parallel environments where multiple agents share `@`, prefer scoped `jj absorb <path>` over bare `jj absorb`.
Bare absorb touches every changed file in `@`, which can interfere with files another agent is mid-edit on.
Scoped absorb routes only the specified files by blame ancestry, leaving everything else in `[wip]` untouched.

The invariant is that `[wip]` is always empty or contains only in-progress work, and `[merge]` is never edited.
All completed changes live in their respective chain commits.

In single-chain mode (tier 1, no bookmarks), the cycle is simpler: `jj describe -m "message"` followed by `jj new` freezes the change and advances `@`.
There is no routing target, so the single-command pattern does not apply.
Do not use `jj new` (without `-A`) in multi-parent development join mode — it creates a new change descending from `[wip]` rather than routing to a chain.

### Extending a chain with a new commit (route-and-extend pattern)

When the intent is to create a new commit on a chain rather than amending the existing tip, `jj squash --into` against the existing tip is insufficient because it merges content into that commit.
Use the route-and-extend pattern instead.

The complete mechanical recipe:

```bash
# 1. Insert a new empty commit after the chain tip (does NOT move @)
jj new -A <chain-tip> --no-edit -m "feat: description of the new change"

# 2. Note the change ID of the newly inserted commit (jj prints it)

# 3. Squash the file(s) from @ into the new commit, preserving [wip] empty on top
jj squash --from @ --into <new-change-id> --keep-emptied -- <path>

# 4. Advance the bookmark to the new chain tip
jj bookmark move <bookmark> --to <new-change-id>
```

Why each step is necessary:

- Step 1 uses `--no-edit` to avoid moving `@` away from `[wip]`. Using `jj squash --into <chain-tip>` instead would amend the existing chain commit, not extend the chain.
- Step 3 uses `--keep-emptied` to preserve the empty `[wip]` commit on top of `[merge]` after the diff is moved into the new chain commit. `[merge]` is never touched.
- Step 4 is required because `jj new -A` creates a new commit that the bookmark does not automatically track. Without this step, the bookmark remains on the old tip.

No description-recovery step is needed: `[wip]`'s description is ephemeral and `[merge]` is frozen.

When to use which pattern:

- *Amending an existing chain commit:* `jj squash --from @ --into <chain-tip> --keep-emptied` (the standard edit-route cycle) or `jj absorb` for auto-routing.
- *Creating a new commit extending the chain:* the route-and-extend recipe above.

**Multi-commit-range form.**
When relocating an existing linear segment of N commits into a chain (rather than authoring a single new commit), use the range form:

```bash
# Checkpoint and survey
PAGER=cat jj op log -n 1  # capture <OP0>
PAGER=cat jj log -r '<range-start>::<range-end>' --no-graph \
    -T 'change_id.shortest(8) ++ " " ++ description.first_line() ++ "\n"'
# Expect N rows in linear order

# Rebase the entire range atomically after the chain tip
jj rebase --revisions '<range-start>::<range-end>' --insert-after <chain-tip>

# Advance the chain bookmark to the new tip (the range's last commit)
jj bookmark set <chain-bookmark> -r <range-end>
```

The `--insert-after <chain-tip>` semantics reparent the chain tip's other current children — the join's edge from this chain — onto the inserted range's tail, so the join automatically follows the extension.
The range's old descendants (typically `@` if the range sat above the join) get reparented onto the range's old parent (the join itself), restoring `@` to a direct child of the join.
Result: the chain extends by N commits in one atomic op-log entry; the other chains, the join's parent set elsewhere, and the working-copy `[wip]` position are not otherwise affected.

This form is the natural multi-commit generalization of the single-commit pattern above.
The same precondition applies as for splice-below-join's by-relocation arm — see §"Splice-below-join" → Precondition: relocation file-disjointness — though file-level overlap between the relocation range and the chain's existing modifications is tolerable when the modifications occupy disjoint regions, since they compose linearly within the chain rather than via cross-chain merge resolution at the join.

### Conflict behavior in composite `@`

When antichain elements contain conflicting changes, `@` displays first-class jj conflicts.
These conflicts are informational — they tell you the chains will conflict when merged.
You can resolve them in `@` (the resolution stays in `@` and may need re-resolution when parents change), continue working with conflict markers present, or resolve the underlying conflict in one of the chains directly.

Conflicts in `@` do not prevent work.
They are a continuous integration signal, not a blocking error.

### `jj absorb` scope and limitations

`jj absorb` works for modifications to existing lines by analyzing blame ancestry to determine which chain element last touched each modified line.
It routes changes automatically based on this analysis.

`jj absorb` can be scoped to specific files: `jj absorb <path>` routes only that file's changes by blame ancestry, leaving everything else in `@` untouched.
This is useful when you want to auto-route changes for one file while continuing to work on others.

`jj absorb` does not work for:
- New files (no blame history exists)
- Deleted files (no blame target)
- Hunks where blame is ambiguous (multiple ancestors modified the same lines)

For any case where `jj absorb` cannot route changes, fall back to `jj squash --from @ --into <chain-tip> --keep-emptied -- <path>` for explicit routing (or the route-and-extend recipe when extending the chain with a new commit).

### Parallel agent coordination

Multiple agents share one filesystem and edit files in the same `@` (which is `[wip]`).
This is the intended model.
All agents see the integrated state of all antichain elements, reducing conflict risk.
Conflicts between concurrent edits are detected immediately as first-class jj conflicts.

All agents route via `jj squash --from @ --into <chain-tip> --keep-emptied -- <path>` (or the route-and-extend recipe to extend a chain).
`--keep-emptied` preserves `[wip]` after the squash, maintaining the canonical two-commit structure across concurrent routing operations.

Coordination protocol for parallel agents:
- One file per commit, routed via `jj squash --from @ --into <chain-tip> --keep-emptied -- <path>`
- Periodic `jj log` review to verify routing correctness
- `jj absorb` as a fallback for batch routing when blame ancestry is clear (auto-preserves `[wip]`)
- If two agents edit different hunks in the same file, `jj absorb <path>` can separate them by blame ancestry after the fact

The orchestrator routes changes to the correct chain via `jj squash --from @ --into ... --keep-emptied` or `jj absorb` after each subagent completes.
Subagent prompts specify which files to edit and the target chain context but do not include jj routing commands.

### Adding and removing chains

Add a chain to the development join `@`:

```bash
jj rebase -r @ -d 'all:(@- | new-bookmark)'
```

Remove a chain from the development join `@`:

```bash
jj rebase -r @ -d 'all:(@- ~ removed-bookmark)'
```

The `all:` prefix is required to ensure the revset resolves to multiple parents rather than collapsing to a single common ancestor.
Without `all:`, jj would compute the nearest common ancestor of the revset members, producing a single-parent `@` instead of a multi-parent one.

### Splice-below-join

When mid-diamond work surfaces a `<base>`-bound commit — hotfix, formatting, config tweak, dependency bump — that belongs on `<base>` below all chains, splice it into the base-to-join interval.
The accumulated splice region fast-forwards `<base>` independently of when the diamond's chains land.

A diamond's interior is `<base>..<join>` — the half-open interval between the base bookmark and the development join.
The bottom of the chains is the antichain of *chain roots* — the direct children of the splice tip (or `<base>` when the splice region is empty) that ancestor `<join>`.
The canonical revset is `children(fork_point(parents(<join>))) & ::<join>`.
The splice-below-join operation inserts new commit(s) between this antichain and whatever sits immediately below it (splice tip or `<base>`).
The diamond shape is preserved: every chain bookmark stays at its tip, the join's parent set is unchanged, `@` (`[wip]`) remains atop the join.

The `fork_point` form is invariant under splice-region state.
When the splice region is empty, `fork_point(parents(<join>))` equals `<base>`, so the expression reduces to `children(<base>) & ::<join>` — equivalent to `roots(<base>..<join>)` in that special case.
When the splice region is non-empty, `fork_point(parents(<join>))` equals the splice tip, so the expression evaluates to `children(<splice-tip>) & ::<join>` — still the chain roots, not the splice root.
Repeated splice-below-join operations therefore always insert at the top of the splice region, preserving chronological order in the eventual `<base>` history.

**Precondition: relocation file-disjointness.**
Before invoking the by-relocation arm, verify the relocation set's modified files are disjoint from any chain's modified files.
Skill files, configuration aggregators, and other shared-edit targets — the "aggregator files" called out in §"Pre-edit cross-chain file-collision reconnaissance" — frequently violate this precondition.
Probe:

```bash
PAGER=cat jj diff --name-only -r '<relocation-set>'
PAGER=cat jj diff --name-only -r 'fork_point(parents(<join>))..<chain-tip>'  # repeat per chain
# Require empty intersection between the relocation set's files and each chain's files.
```

Violation produces cascading conflicts on rebase: one conflicted commit per chain that touches a relocation-set file, propagating through descendants to the join.
On collision, three alternatives apply:

- *Route-and-extend into the colliding chain* (see §"Extending a chain with a new commit (route-and-extend pattern)").
The relocation set becomes part of that chain's tip; the join's cross-chain merge resolution continues operating against the chain's extended content.
Best when the colliding chain has domain overlap with the relocation set.
- *Create a new chain mid-diamond* for the relocation set (see `diamond-workflow.md` §"Phase 2: develop" → "Chain creation mid-diamond").
The set becomes its own chain; the join expands to N+1 parents.
Best when the relocation set is semantically independent of every existing chain and the splice would otherwise force domain-incoherent commit history.
- *Defer to Phase 4 serialize.*
Leave the relocation set above the join; it lands with the diamond's eventual integration.
Loses the "main-bound independent advance" property but is conflict-free and requires no diamond reshape.

The by-construction arm bypasses this precondition mechanically — the commit doesn't exist until after the position is chosen — but the author should still check whether the intended files are touched by any chain.
If so, prefer route-and-extend or new-chain-creation over by-construction.

**By-construction arm** — when authoring a new `<base>`-bound commit:

```bash
jj new --insert-before 'children(fork_point(parents(<join>))) & ::<join>' -m "fix(scope): description"
# @ is now splice-positioned, at the top of the splice region; edit files (auto-snapshotted into the splice commit)
jj new  # return @ to [wip] atop the diamond, or remain in the splice commit to extend it
```

**By-relocation arm** — when a `<base>`-bound commit already exists above the join (commonly because `@` was the working position when the commit was sealed):

```bash
# Checkpoint and survey the antichain target
PAGER=cat jj op log -n 1  # note <OP0> for rollback
PAGER=cat jj log -r 'children(fork_point(parents(<join>))) & ::<join>' --no-graph \
    -T 'change_id.shortest(8) ++ " bm=[" ++ bookmarks ++ "] " ++ description.first_line() ++ "\n"'
# Expect N rows — one per chain in the diamond

jj rebase --revisions <commit> --insert-before 'children(fork_point(parents(<join>))) & ::<join>'

# Verify diamond invariants post-splice
PAGER=cat jj log -r 'present(@) | ancestors(immutable_heads().., 2) | trunk()'
PAGER=cat jj bookmark list -r 'parents(@-) ~ trunk()'  # expect N chain bookmarks unchanged
# Rollback if any verification fails: jj op restore <OP0>
```

The revset `children(fork_point(parents(<join>))) & ::<join>` is the order-theoretically precise name for the chain-roots antichain.
It generalizes across diamond cardinality (2-way, N-way), is invariant under remote bookmark drift (origin-advance commits descend from `<base>` but do not reach `<join>`, so they are excluded), and resolves to the chain roots regardless of splice region state (empty or non-empty) — preserving chronological order in the splice region across repeated operations.

**Anti-patterns**:

- *Naked `--insert-after <base>`* fails when `<base>@origin` is ahead of local `<base>`.
  The `--insert-after` semantics reparent every current child of `<base>` onto the source — including the immutable origin-advance lineage.
  jj refuses with `Commit <id> is immutable`.
  Use `--insert-before` against the antichain instead, which touches only the chain-root edges.
- *Single-target `--insert-before <one-chain-root>`* reparents only one chain.
  The join then merges N parents with inconsistent bases (one below the new commit, N-1 still directly above `<base>`), silently desynchronizing the diamond.
  Always use a revset spanning all chain roots: `children(fork_point(parents(<join>))) & ::<join>`.
- *`jj rebase -r <X> -d <base>`* (destination form) leaves the source as a sibling of the chain roots, not above them.
  The chain roots remain children of `<base>`; the source has no relationship to the diamond.
  Wrong topology.

**Invariants preserved**.
Every chain bookmark resolves to the same chain tip (commit ids unchanged in by-construction arm; chain roots and descendants rewritten in by-relocation arm via standard auto-rebase).
`<join>` retains its N-parent shape.
`@` retains its `[wip]` empty status.
The base bookmark is not advanced — fast-forwarding `<base>` to incorporate the splice region is a separate, deliberate step (see `§Diamond integration on remote advance` for the related operation when the remote has moved).

### Re-attaching `[wip]` after `jj rebase -r <merge>`

`jj rebase -r <merge>` and `jj rebase -r <wip> -d <merge>` form a required tool-pair.
The first reparents `[merge]`'s parent set in place; because the `-r` form's semantics are to reparent the named commit's parents while structurally reparenting its descendants away from it, the second is needed to bring `[wip]` back onto the rebuilt `[merge]`.
Whenever the first verb is issued, the second is its required successor, immediately, in the same operation sequence — this is the canonical pairing, not an exception.

The route-and-extend recipe (`SKILL.md` §"Extending a chain with a new commit (route-and-extend pattern)") does not use this verb at all: it composes `jj new -A <chain-tip> --no-edit` with `jj squash --from @ --into <new-id> --keep-emptied`, and jj's auto-rebase updates `[merge]` and re-attaches `[wip]` cleanly without operator intervention.
Neither half of the pair is needed there.
The chain-creation-mid-diamond recipe (`diamond-workflow.md` §"Chain creation mid-diamond") deliberately uses `jj rebase -r <merge>` to grow the parent set in place, so both halves of the pair are mandatory and both appear in that recipe.

If only the first half ran, `[wip]` is left at the old parent set: the diamond-health diagnostic surfaces this as `@` shown with multiple direct parent connectors instead of a single line into `[wip]`.
Repair by issuing the second half: `jj rebase -r <wip-change-id> -d <merge-change-id>`.
When the broken-half was the immediately-preceding operation, `jj op restore <id>` is also available to roll back and re-execute the sequence cleanly.

### Teardown

To abandon the development join (dissolve the composite) and collapse back to a single-parent `@`, either iteratively remove parents using the removal command above, or reset directly:

```bash
jj new <single-bookmark>
```

This creates a fresh `@` descending from only the specified bookmark.

### Diamond integration on remote advance

When `<base>@origin` has advanced past local `<base>` while diamond work is in progress, integrate the new remote commits into the diamond before continuing.
This is distinct from `§Integration strategies at completion` (Phase 4 serialize): the operation here rebases an *in-progress* diamond onto a moved remote, not the completion-time linearization of chains for submission.

**What `jj git fetch` does automatically** (per `lib/src/git.rs` in upstream `jj-vcs/jj`):

1. *Tracked-bookmark advance* — when local `<base>` tracks `<base>@origin`, a 3-way merge auto-advances local `<base>` to the new remote tip.
2. *Abandon-and-rebase for unreachable commits* — commits that became unreachable on remote (force-push removed) are abandoned, and their descendants auto-rebased onto the new tips.
3. *Synthetic predecessor recording* — abandoned commits whose change IDs match newly-imported commits trigger `set_rewritten_commit`, propagating standard rewrite-tracking auto-rebase to descendants.

**What fetch does not handle in the diamond-on-old-base case**.
The diamond's chain roots are parented to the old `<base>` position.
After fetch, that position is still reachable (pinned by the chain roots), so it is not abandoned.
The new remote-advance commits have change IDs jj has never seen, so no rewrite mapping is established.
Local `<base>` advances; chain roots do not move.
An explicit rebase is required.

**Recipe**:

```bash
jj git fetch

# Move the entire diamond (splice region if any, chain roots, chains, chain tips, join, @)
# from old <base> position onto new remote tip. Source = antichain at the bottom of
# <base>@origin..@; destination = <base>@origin literally, which is invariant under
# whether auto-advance fired.
jj rebase --source 'roots(<base>@origin..@)' --destination '<base>@origin'

# Ensure local <base> matches remote (idempotent — no-op if fetch auto-advanced).
jj bookmark set <base> -r '<base>@origin'

# Verify
PAGER=cat jj log -r 'present(@) | ancestors(immutable_heads().., 2) | trunk()'
PAGER=cat jj bookmark list -r 'parents(@-) ~ trunk()'
```

Applies whether the splice region is empty or non-empty: `roots(<base>@origin..@)` resolves to the splice root when splice commits exist, or to the chain-root antichain when they do not.
The diamond's interior moves as one connected component; chain bookmarks point at the rewritten tips post-rebase.

### Session persistence

The development join `@` state persists across sessions.
When a new session detects an existing multi-parent `@` (visible via `jj log -r @` showing multiple parents), it should resume the development join workflow rather than starting fresh.
Run `jj log -r '@-+' -s` to identify the active chains and their bookmarks.
Check `jj status` and `jj log -r 'mutable() ~ @ ~ ::main'` to understand in-progress work before making changes.

### Integration strategies at completion

The development join is ephemeral workspace scaffolding that is dissolved before integration.
It does not appear in the final history on main.

The default integration strategy is sequential rebase linearization: rebase each chain onto main in dependency order, producing a purely linear history with no merge commits.
The canonical recipe is documented in full in `diamond-workflow.md` Phase 4 — that document is authoritative when this section and the diamond-workflow recipe diverge.
The summary here covers the mechanical steps in single-chain and multi-chain cases.

*Sequential rebase linearization*: dissolve the development join first by abandoning `[wip]` and `[merge]`, then rebase chains sequentially in linearization order, fast-forwarding main to the tip via bookmark advance.
Dissolution-first is canonical: abandoning the multi-parent structure before rebase ensures each chain rebases against its actual base rather than the join.

Two cases determine the linearization order.
When the chains form a true antichain (all issues are mutually independent), the integration order is discretionary: alphabetical, thematic, or by size.
When issues have cross-chain dependency edges (issue A in chain 1 blocks issue B in chain 2), those edges induce a partial order on the chains themselves and the linearization must respect it: chains whose issues are depended upon by other chains rebase first.
Independent chains within the same linearization step can be ordered discretionarily.

The ergonomic canonical rebase form is `jj rebase -b <bookmark> -d <prev>`, which rebases all commits reachable from the bookmark but not from the destination.
The `-s <chain-base> -d <dest>` form is equivalent but requires identifying the chain base first; prefer `-b` when the bookmark itself is the natural identifier.
The procedure generalizes to N chains:

```bash
# Dissolve the development join (canonical first step)
jj abandon <wip-change-id> <merge-change-id>

# Determine linearization order (dependent chains first)
# Chain A: main -> a1 -> a2 -> a3 (tip: chain-a bookmark)
# Chain B: main -> b1 -> b2 (tip: chain-b bookmark)
# Chain C: main -> c1 (tip: chain-c bookmark)

# Rebase A onto main (already there if it descends from main)
jj rebase -b chain-a -d main

# Rebase B onto A's tip
jj rebase -b chain-b -d chain-a

# Rebase C onto B's tip
jj rebase -b chain-c -d chain-b

# Result: main -> a1 -> a2 -> a3 -> b1 -> b2 -> c1
# Create the aggregate bookmark at the linearized tip
jj bookmark create <aggregate-bookmark> -r chain-c
```

The `jj-linearize-join` sibling tool performs the dissolution and sequential rebase steps with `--dry-run`, real-run, and embedded `test` subcommand modes.

For a single chain, this reduces to advancing main directly to the chain tip:

```bash
jj bookmark set main -r <chain-tip>
jj git push --bookmark main
```

This is the jj equivalent of fast-forward merge — advancing a bookmark creates no merge commits.

*N+1 stacked-base PR submission (forge-driven exit)*: push N chain bookmarks plus one aggregate bookmark, then create N stacked-base chain PRs plus one aggregate PR targeting main, all initially draft.
The aggregate PR is the merge gate.
GitHub auto-closes a PR as MERGED when its head commit becomes reachable from the default branch regardless of the PR's specified base branch; advancing main to the aggregate tip therefore closes all N+1 PRs in one push.
The `jj-stack-submit` sibling tool performs this submission (push N+1 bookmarks via `jj git push`, create N stacked-base chain PRs + 1 aggregate PR via `gh` or `tea`, post a backlink comment on the aggregate, mark the aggregate ready).

The full post-merge recipe is three commands:

```bash
jj bookmark set main -r <aggregate-bookmark>
jj git push --remote origin --bookmark main
jj git fetch --tracked --remote origin   # auto-deletes local bookmarks for branches GitHub deleted on merge
```

After integration, exit the development join by resetting `@` to a single parent.
In forge-driven merge flows where main is not locally advanced ahead of the push, the canonical exit is `jj new <aggregate-bookmark>` rather than `jj new main`, because the local main bookmark may not yet reflect the remote state at the moment of exit.
The `jj-linearize-join` tool performs this exit step automatically.
In the secondary case where main was locally advanced before the push, `jj new main` is equivalent.
Individual chain bookmarks can be deleted in the post-session cleanup (or are auto-deleted by `jj git fetch --tracked` when the corresponding GitHub branches were deleted on merge).

*Separate PRs (legacy)*: push each chain's bookmark independently for review before linearizing.
Push all at once: `jj git push --bookmark chain-a --bookmark chain-b --bookmark chain-c`.
Or push one at a time: `jj git push --bookmark chain-a`.
Each pushed bookmark becomes a branch on the remote, suitable for PR creation via `gh pr create`.
This pattern remains valid for unrelated chains but is superseded by the N+1 stacked-base pattern above for epic-scoped work where the chains share a logical integration boundary.
When creating standalone PRs, use the bookmark name as the head branch and main as the base:

```bash
jj git push --bookmark chain-a
gh pr create -d -a "@me" -B main -H chain-a -t "feat: description" -b ""
```

Follow the PR creation protocol in `~/.claude/skills/preferences-git-version-control/SKILL.md` for placeholder content and safety conventions.

For GitHub-only repositories, Mergify's Stack-Aware Base feature would handle single-CI-gate behavior natively without an explicit aggregate PR; see the footnote in `diamond-workflow.md` Phase 4 for the trade-off against forge-agnostic compatibility.

### Vocabulary cross-reference

The skill uses terminology from three traditions, sometimes naming the same concept differently:

| Concept | This skill | Krycho (community) | Upstream jj | Order / lattice theory |
|---|---|---|---|---|
| Multi-parent integration commit | development join | `[merge]` (with `[wip]` on top) | "merge commit at `@`" (pattern unnamed; see `FAQ.md:255-294`) | **join (∨)**, least upper bound |
| Greatest common ancestor of parallel work | fork point | (uses generic "common ancestor") | `fork_point()` revset (`docs/revsets.md:349-353`) | **meet (∧)**, greatest lower bound |
| Totally ordered subset of commits | chain | "stream of work" or "branch" | "linear chain" or "anonymous branch" | **chain** (precise term) |
| Mutually incomparable parallel branches | chain tips of a development join | (unnamed) | (unnamed) | **antichain** (Dilworth) |
| Maximum of a chain | chain tip | "tip commit" | "tip" | **maximum** of the chain |
| The integrated structural pattern | diamond workflow | "megamerge" (title-only, undefined) | (unnamed) | a bounded sublattice with antichain interior |
| Moving a change to its semantic home | route (append-, amend-, absorb-) | "squash into", "absorb" | `jj squash --into`, `jj absorb`, `jj new --insert-*` | (operational; no formal term) |
| Splice operation below chain roots | splice-below-join (by-construction / by-relocation) | (unnamed) | `jj rebase --revisions <X> --insert-before <revset>` / `jj new --insert-before <revset>` | antichain target; operational route below the diamond interior |

`[merge]` / `[wip]` bracket notation is Krycho-canonical (from *Jujutsu Megamerges and `jj absorb`*) and used in this skill for visual concreteness when describing the structural pair.
The full theoretical treatment of the lattice / partial-order foundation — Dilworth's antichain theorem, Lamport's partial order, Winskel event structures — is in `docs/notes/development/version-control/epic-to-branch-diamond-workflow.md`.

## `jj revert` usage

`jj revert` creates a new change that applies the inverse of a given revision.
The command requires explicit placement via `--onto`, `--insert-after`, or `--insert-before`.

Create a revert as a child of the current `@`:

```bash
jj revert -r <change> --onto @
```

Insert a revert into a linear chain before `@`:

```bash
jj revert -r <change> --insert-before @
```

Insert a revert after the parent of `@` (equivalent to inserting before `@`):

```bash
jj revert -r <change> --insert-after @-
```

To test a revert non-destructively, apply it and then undo if the result is undesirable:

```bash
jj revert -r <change> --onto @
# inspect the result...
jj undo  # roll back if not what you wanted
```

## `jj tidy` safety

The `jj tidy` alias uses the revset `mutable() ~ @ ~ ::main`.
This abandons all mutable changes not in main's ancestry and not at `@`.

Before running `jj tidy`, always advance main to cover any work-in-progress you want to keep.
Preview what tidy will affect:

```bash
jj log -r 'mutable() ~ @ ~ ::main' -s
```

If tidy sweeps too broadly, recover with `jj undo`.

## Post-session cleanup

After advancing the main bookmark to the tip of completed work (whether from a single chain or a linearized multi-parent session), present a cleanup summary for user approval before executing.

Gather diagnostics:

```bash
# Orphaned/divergent changes (anonymous heads, divergent change IDs)
jj orphans

# Stale bookmarks (local bookmarks not tracking a remote, excluding main)
jj bookmark list | grep -v '@'

# Mutable changes outside main and @ (what tidy would sweep)
jj log -r 'mutable() ~ @ ~ ::main' -s

# Git-side merged branches (colocated mode)
git branch --merged main | grep -Ev '^[*]|^  main$'
```

Present a summary to the user structured as:

- Stale bookmarks to delete (and why each is stale — integrated into main, or orphaned)
- Changes that `jj tidy` would abandon (with descriptions, so the user can verify nothing valuable is swept)
- Git branches that `git prune-merged` would delete
- Any caveats specific to the session (e.g., chains that were not fully integrated, divergent changes that may need manual resolution, work-in-progress that should be preserved)

After user approval, execute in order:

```bash
jj bookmark delete <stale-bookmarks>
jj tidy
git prune-merged
jj gc
```

Do not execute cleanup automatically.
Always present the summary and wait for explicit approval.

## Integration with git repositories

### Initializing jj in existing git repository

To use jj with an existing git repository in colocated mode:

```bash
# Navigate to git repository
cd /path/to/git/repo

# Initialize jj in colocated mode
jj git init --colocate

# Verify setup
ls -la  # Should see both .git/ and .jj/ directories
jj log  # Shows git history imported into jj
```

The `--colocate` flag creates `.jj/` alongside `.git/` so both tools work on the same repository.
All git branches become jj bookmarks automatically.
From this point forward, use jj commands for history editing and git features work normally.

Alternative for new repositories:

```bash
# Clone git repo with jj (automatically colocated)
jj git clone <url> <directory>

# Or initialize new jj repo backed by git
jj git init --git-repo=.  # Creates .jj/ and .git/ in current directory
```

### Working in colocated repos

When working in colocated repos (`.git` and `.jj` siblings):

Colocated workflow:
- All jj bookmark operations automatically sync to git branches
- Run `jj git export` if you need explicit sync to git refs
- Run `jj git import` to import git changes (automatic in colocated repos)
- Git commands work directly on same repo - changes appear in `jj log`

Mixed tool usage:
- Prefer jj commands for history editing - they're more powerful and safer
- Use git commands for operations not yet in jj
- After git operations, check `jj log` to see imported changes
- `jj git` subcommands bridge any gaps

Pushing to git remotes:
- `jj git push` works identically to git push for bookmarks
- Remote bookmark tracking is automatic
- Git-specific features (like GitHub PRs) work normally with jj-managed bookmarks

## Beads integration

When `.beads/` exists alongside `.jj/` in a colocated repository, beads issue tracking integrates with jj bookmarks.
The diamond workflow pattern provides the overarching structure for epic-scoped work, connecting the beads issue dependency graph to jj chain topology through four phases: diverge, develop, converge, serialize.
See the "Diamond workflow" section above and `diamond-workflow.md` in this directory for the full treatment.

Bookmark naming for bead work follows the same `{ID}-descriptor` pattern used in git branch naming, with dots in bead IDs replaced by dashes.
For example, beads issue `nix-pxj.4` becomes bookmark `nix-pxj-4-deploy-validate`.

Beads IDs take precedence over the `exp-N-description` experiment naming convention when working on tracked issues.
Use experiment naming only for exploratory work not tied to a beads issue.

Worktrees are a git-only mechanism; jj uses bookmarks for branch-like semantics.
When in a jj-managed repo, create a bookmark for bead work rather than using `git worktree add`:

```bash
jj bookmark create {epic-ID}-descriptor
# work on issues as changes within the bookmark chain:
jj new {epic-ID}-descriptor
jj describe -m "feat: implement issue description"
# edit files...
jj new  # freeze and start next issue
jj git push --bookmark {epic-ID}-descriptor
```

When working across multiple epics simultaneously, create a development join:

```bash
jj new {epic-a}-descriptor {epic-b}-descriptor
# edit a file, then route it atomically:
jj squash --into {epic-b}-descriptor -m "feat: description" path/to/file
# or auto-route multiple files by blame ancestry:
jj absorb
```

Subagent dispatch in jj mode: subagents edit files directly in the shared `@` working copy.
The orchestrator routes changes to the correct epic bookmark after the subagent returns.
See the parallel agent coordination protocol in the "Development join" section above.

### Completing issues and epics

Issue-level completion within a chain:

1. The issue's changes are complete within the epic's bookmark chain.
2. Close the bead: `bd close {issue-ID} --reason "Implemented in $(jj log -r '{epic-ID}-descriptor' --no-graph -T 'commit_id.short(8)')"`
3. The epic bookmark already points to the chain tip (bookmarks follow rewrites automatically).
4. Continue the chain with new changes for the next issue.

Epic-level completion:

1. All issues within the epic are closed.
2. For single-chain epics, advance main to the epic chain tip and push:
   ```bash
   jj bookmark set main -r {epic-ID}-descriptor
   jj git push --bookmark main
   ```
3. For multi-chain epics, use the N+1 stacked-base + aggregate PR pattern documented in `diamond-workflow.md` Phase 4 and the "Integration strategies at completion" section above.
   The `jj-linearize-join` and `jj-stack-submit` sibling tools automate the transformation and submission.
4. After main reflects the epic's integrated state, fetch to auto-delete merged remote bookmarks:
   ```bash
   jj git fetch --tracked --remote origin
   ```
5. Delete any remaining local epic bookmarks not auto-cleaned by the fetch.
6. Push beads state: `bd dolt push`
