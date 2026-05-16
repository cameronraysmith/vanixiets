# Diamond workflow: beads epic to jj chain topology

This document is the canonical operational reference for the diamond workflow in this skill tree.
It describes the diamond workflow pattern that connects beads epic issue graphs to jj multi-parent version control, providing the theoretical foundations, beads-to-jj mapping, and mechanical recipe for epic-scoped work.

The companion design note at `docs/notes/development/version-control/epic-to-branch-diamond-workflow.md` is the theoretical foundation with full citations (Winskel event structures, Dilworth's antichain theorem, Lamport's partial order, Beer's VSM, Krycho's effective theory); when the *why* is in question, read the design note.
The sibling `tiered-ceremony.md` is the policy authority for *when* the diamond workflow applies — it answers "should I be using the diamond at all?" before this document answers "how do I run a diamond?".
The sibling `~/.claude/skills/jj-version-control/SKILL.md` is the operational entity-level reference for the development join itself (the multi-parent `@`, conflict behavior, edit-route cycle, route-and-extend recipe); when you need the day-to-day mechanics of working in a join, look there.

## Two-peer ontology: process and entity

The *diamond workflow* names the process — the four phases of diverge, develop, converge, and serialize.
The *development join* names the entity — the multi-parent `@` working copy used during the develop phase.
Not every development join is part of a diamond workflow: a two-bookmark experiment without an epic is still a valid development join.
Every diamond workflow contains exactly one development join.
This is an ontological pair (object plus process), not redundant aliases — the two terms refer to different aspects of the same coordinated workflow.

## The diamond pattern

The workflow has four phases that form a diamond shape: diverge, develop, converge, serialize.

```
                    [main before]
                         |
              /----- [chain A] -----\
             /------ [chain B] ------\
            /------- [chain C] -------\
           /-------- [chain D] --------\
                         |
                [N-way development join]
                   [validate / QA]
                         |
           [sequential rebase to main]
                         |
                    [main after]
```

The diverge phase decomposes the epic into parallel bookmark chains based on issue dependencies.
The develop phase works concurrently across chains using the N-way development join (composite working copy) with the join + wip structure.
The converge phase validates the integrated whole before committing to linearization.
The serialize phase produces the final main history by rebasing each chain sequentially onto main, yielding a purely linear commit history with no merge commits.

## Theoretical foundations

### Lattice theory

The epic forms a bounded lattice.
The bottom element is the starting state (main before work begins).
The top element is the integrated result (the validated development join ready for linearization).
Issues are elements between them, with the dependency graph defining the partial order.

Independent issues (no dependency path between them) form antichains, which are maximal sets of mutually incomparable elements.
These antichains correspond directly to the sets of bookmark chains that can be developed in parallel.

By Dilworth's theorem, the minimum number of sequential chains needed to cover the partial order equals the maximum antichain width.
This gives a lower bound on the number of rebase steps needed to linearize the work.
For the extended lattice-theoretic treatment with full citations, see `docs/notes/development/version-control/epic-to-branch-diamond-workflow.md`.

### Event structures

Winskel's event structures (1986) provide the operational semantics.
An event structure has events (commits), a causal dependency relation (issue dependencies), and a conflict relation (changes that cannot coexist).
A *configuration* is a consistent, causally closed set of events.

The N-way development join is a configuration: a conflict-free set of commits whose dependencies are all satisfied.
The development process moves through the *domain of configurations*, from the empty configuration (main) through partial configurations (individual chains) to the full configuration (the development join).
The linearized commit sequence on main records a path through this domain.

This framing clarifies why the development join is correct during development (it represents a valid configuration for testing) but the sequential rebase linearization is correct for history (it records a linear extension through the configuration domain).
For the extended event-structure exposition with Winskel citation context, see `docs/notes/development/version-control/epic-to-branch-diamond-workflow.md`.

### Concurrency theory

The development of independent issues is genuinely concurrent in Lamport's sense: neither happened-before the other.
The N-way development join is a synchronization point where concurrent work streams are verified to be conflict-free.

A purely linear history imposes a total order on concurrent events, but this is acceptable when the integration sequence respects the dependency partial order.
The linearized rebase history records the dependency-respecting serialization directly.

### Viable System Model mapping

The diamond workflow maps onto the VSM structure referenced in the adaptive planning skill.

| VSM system | Diamond phase | Function |
|---|---|---|
| System 1 | Develop | Implementation work in parallel bookmark chains |
| System 3 | Development join | Internal coordination, conflict detection |
| System 3* | Validate | Audit: manual QA, integration testing on the development join |
| System 4 | Plan / decide | Epic decomposition, linearization-readiness decision |
| System 5 | Linearize to main | The repository's authoritative state |

## Beads-to-jj mapping

| Beads concept | jj concept | Lattice theory |
|---|---|---|
| Epic | Linearized chain group on main | Bounded lattice |
| Issue dependency graph | Chain topology (which bookmarks depend on which) | Partial order |
| Independent issues | Parallel bookmark chains | Antichains |
| Issue blocking relation | Chain stacking (one bookmark branching from another's tip) | Covering relation |
| Epic validation | N-way development join (join + wip structure) | Configuration |
| Integration to main | Sequential rebase linearization | Linear extension |
| Planning horizon | Number of issues per epic before integration | Requisite variety |

## Linearization order: two cases

When the epic's issue dependency graph contains only independent issues, the chains form a true antichain.
Integration order is discretionary: alphabetical, thematic, or by size.

When issues have cross-chain dependency edges (issue A in chain 1 blocks issue B in chain 2), those edges induce a partial order on the chains themselves.
The linearization must be a linear extension of this induced partial order: chains whose issues are depended upon by other chains rebase first.
Independent chains within the same linearization step can be ordered discretionarily.

## Mechanical recipe

### Phase 1: diverge (plan)

1. Survey the epic's issue dependency graph: `bd epic status`.
2. Identify antichains (sets of independent issues) and map each to a bookmark chain.
3. Create bookmarks from main for each chain:
   ```bash
   jj new main
   jj bookmark create {issue-ID}-descriptor
   # repeat for each chain
   ```

### Phase 2: develop

4. Create the N-way development join, describing `[merge]` with the state-based convention `join N=<cardinality>: <alphabetical, comma-separated parent chain bookmarks>`:
   ```bash
   jj new chain-a chain-b chain-c ...
   jj describe -m "join N=3: chain-a, chain-b, chain-c"
   ```
5. Create wip on top:
   ```bash
   jj new
   ```
6. Develop in wip, routing changes to chains via the edit-route cycle.
   Each route from `[wip]` to a chain is either an append-route (default: land a new atomic commit on the chain) or an amend-route (fixups against the existing tip).
   The append-route is the default for landing new work:
   ```bash
   # Append-route: land a new atomic commit on <chain>
   jj squash --from @ --insert-after <chain-tip> -m "feat: description" --keep-emptied
   jj bookmark move <chain> --to @-
   ```
   The `--insert-after` (`-A`) flag is what switches `jj squash` into create-a-new-commit mode (per `cli/src/commands/squash.rs:51-84`); without it, `--into <chain-tip>` amends the existing tip in place.
   `--keep-emptied` preserves the single shared `[wip]` on top of `[merge]` (invariant (vi)); the bookmark-move is a separate explicit step because jj does not auto-advance a bookmark onto a newly inserted commit.
   See `~/.claude/skills/jj-version-control/SKILL.md` §"Routing to a chain: append vs amend" for the full rationale and the amend-route fixup recipe.

   Path-restriction (`-- <paths>`) can be added to either recipe when multiple streams' hunks coexist in `[wip]` and only one stream's paths should be routed in this operation.

   Fallback patterns, used only when neither route applies cleanly:
   ```bash
   # Auto-route by blame ancestry (fallback when blame is clean and unambiguous):
   jj absorb
   # Amend the existing chain tip in place (fixups only — preserves tip description by omitting -m):
   jj squash --from @ --into <chain-tip> --keep-emptied
   ```

#### Gotcha: chain creation mid-diamond

Starting a new chain while the development join already exists (tier 3 is already active) REQUIRES same-operation join re-growth.
Issuing only `jj new main -m "wip(<name>): seed chain"` to begin a new chain produces three failure modes simultaneously:

- the new chain's seed commit is not in `parents([merge])`, violating invariant (i) (chain ∈ join's parents);
- the integrated state at `[wip]` does not reflect the new chain, violating invariant (iv) (wip holds integrated working tree);
- other agents working through `[wip]` silently miss the new chain entirely, treating it as if it does not exist.

The correct sequence creates the seed commit AND grows `[merge]` to include it in one operation pair:

```bash
# 1. Seed the new chain from main
jj new main -m "wip(<name>): seed chain"

# 2. Bookmark the seed commit so it is addressable
jj bookmark create <name> -r @

# 3. Reparent [merge] to include the new chain alongside existing chains
jj rebase -r <merge-change-id> -d <existing-chain-a> -d <existing-chain-b> -d <name>

# 4. Rewrite [merge]'s description with the new full set
jj describe <merge-change-id> -m "join N=k+1: <alphabetical bookmarks including <name>>"
```

After step 4, run the diamond-health diagnostic from `~/.claude/skills/jj-version-control/SKILL.md` to verify all five invariants hold before resuming edits in `[wip]`.

### Phase 3: converge (validate)

The converge phase occurs *at* a planning-DAG convergence point in the sense used by `~/.claude/skills/preferences-adaptive-planning/SKILL.md` and `~/.claude/skills/session-review/SKILL.md` — the diamond's converge phase and the planning DAG's topological convergence node refer to the same shape of synchronization point in the workflow.

7. The development join working copy represents the full integration.
8. Run tests, manual QA, and integration validation against the development join.
9. Fix issues by editing in wip and routing fixes to the appropriate chain.
10. Close beads issues as they pass validation: `bd close {issue-ID} --reason "Implemented in $(jj log -r '{chain-bookmark}' --no-graph -T 'commit_id.short(8)')"`.

The CCV closure operator (see `preferences-compositional-continuous-verification` §"What this means for an agent session") is invariant under the choice of `@`-position in the development join.
The wip `@` of a development join and the linearized aggregate tip produced by Phase 4 are hash-equal under the content-addressed graph: the same set of file trees, the same set of derivation closures, the same set of check outputs.
Running `just check-fast` on the wip `@` and running it on the post-linearization aggregate tip exercise the same closure operator against the same inputs and return the same pass-or-fail decision modulo parallel scheduling order.
Local validation may therefore be performed either before or after the Phase 4 linearization without affecting the closure-operator semantics.
Buildbot-nix re-runs the closure operator authoritatively at PR-CI time and is the integration-decision authority regardless of where local validation occurred.

### Phase 4: serialize (integrate)

The serialize phase first abandons the ephemeral scaffolding, then rebases each chain sequentially onto main in linearization order to produce a purely linear history.
Dissolution-first is canonical: abandoning `[wip]` and `[merge]` removes the multi-parent structure so the subsequent rebases operate on each chain's actual base rather than on the join.

11. Abandon the development join and wip commits (they are ephemeral scaffolding):
    ```bash
    jj abandon <join-change-id> <wip-change-id>
    ```
12. Rebase each chain onto main in linearization order (see "Linearization order: two cases" above).
    The ergonomic canonical form is `jj rebase -b <bookmark> -d <prev>`, which rebases all commits reachable from the bookmark but not from the destination; the `-s <chain-base>` form is equivalent but requires explicitly identifying the chain base first.
    ```bash
    # For each chain, in dependency order:
    jj rebase -b <chain-bookmark> -d <prev-tip-or-main>
    ```
13. Set an aggregate bookmark at the linearized tip — this is the merge gate for the forge-driven exit:
    ```bash
    jj bookmark create <aggregate-bookmark> -r <linearized-tip>
    ```
14. Push the N chain bookmarks plus the aggregate bookmark atomically.
    Then create N stacked-base chain PRs plus one aggregate PR targeting main, all initially draft.
    The `jj-stack-submit` sibling tool automates this Phase A submission (push N+1 bookmarks, create N stacked-base PRs + 1 aggregate PR via `gh` or `tea`, optionally backlink and mark ready):
    ```bash
    jj git push --remote origin --bookmark chain-a --bookmark chain-b --bookmark chain-c --bookmark <aggregate-bookmark>
    # Then via jj-stack-submit, or by hand:
    gh pr create -d -B main -H chain-a -t "..." -b ""
    gh pr create -d -B chain-a -H chain-b -t "..." -b ""
    gh pr create -d -B chain-b -H chain-c -t "..." -b ""
    gh pr create -d -B main -H <aggregate-bookmark> -t "..." -b ""  # aggregate
    ```
    The aggregate PR is the merge gate.
    Chain PRs use stacked bases (each pointing at the prior chain bookmark) so the forge renders the dependency structure, but the chain PRs are not individually merged.
15. After buildbot passes on the aggregate, mark it ready and merge it (Mergify fast-forward).
    GitHub auto-closes a PR as MERGED when its head commit becomes reachable from the default branch, regardless of the PR's specified base branch.
    Advancing main to the aggregate tip therefore closes all N chain PRs and the aggregate PR in one push.
    The full post-merge recipe is three commands:
    ```bash
    jj bookmark set main -r <aggregate-bookmark>
    jj git push --remote origin --bookmark main
    jj git fetch --tracked --remote origin   # auto-deletes local bookmarks for branches GitHub deleted on merge
    ```
16. After main is advanced, exit the development join by resetting `@` to a single parent.
    In the forge-driven flow described here, main is advanced remotely first and the local advance happens via the push above; the canonical exit is therefore `jj new <aggregate-bookmark>` rather than `jj new main`, because the local main bookmark may not yet reflect the remote state at the moment of exit.
    The `jj-linearize-join` sibling tool performs this `jj new <aggregate>` step automatically.
17. Push beads state:
    ```bash
    bd dolt push
    ```

The `jj-linearize-join` sibling tool performs steps 11–13 (the diamond-workflow → linearized-chain transformation) with `--dry-run`, real-run, and embedded `test` subcommand modes.
The `jj-stack-submit` sibling tool performs step 14 (Phase A submission) — push N+1 bookmarks, create N stacked-base chain PRs + 1 aggregate PR via `gh` or `tea`, post a backlink comment on the aggregate, and mark the aggregate ready.

For GitHub-only repositories, Mergify's Stack-Aware Base feature (see `mergify-docs/src/content/docs/merge-queue/stacks.mdx` §"Stack-Aware Base") would handle single-CI-gate behavior natively without an explicit aggregate PR, eliminating the cosmetic shared-head-SHA warning Mergify emits on stacked PRs.
Mergify Stacks is GitHub-only and breaks Gitea compatibility, so the forge-agnostic N+1 design is the primary recipe here; Stack-Aware Base is a footnote for repositories that will never run on Gitea.

## Open questions

How should the PR description format be standardized for linearized epic integrations?

How should cross-chain dependencies be handled during the develop phase when chain stacking creates serial dependencies that may be avoidable?

Should the integration order be encoded in the beads graph or derived at integration time from the dependency structure?

What is the optimal planning horizon (number of issues per epic)?
The adaptive planning skill's MPC framework suggests this depends on requirement volatility and integration cost.

## References

- Winskel, G. (1986). "Event structures." Advances in Petri Nets.
- Davey, B. A. and Priestley, H. A. (2002). "Introduction to Lattices and Order." Cambridge University Press.
- Lamport, L. (1978). "Time, Clocks, and the Ordering of Events in a Distributed System."
- Beer, S. (1972). "Brain of the Firm." Allen Lane.
- Dilworth, R. P. (1950). "A Decomposition Theorem for Partially Ordered Sets."
- Krycho, C. (2024). ["Jujutsu Megamerges and jj absorb."](https://raw.githubusercontent.com/chriskrycho/v5.chriskrycho.com/3f330be8861378587da76f33fe272799f5b84d97/site/journal/2024/Jujutsu%20Megamerges%20and%20jj%20absorb.md) Pinned to commit 3f330be. Local cache: `docs/notes/development/version-control/references/krycho-jujutsu-megamerges-and-jj-absorb.md`.

### See also

- `docs/notes/development/version-control/epic-to-branch-diamond-workflow.md` — the ratified design note containing the working-document version of the citations above, with motivation, design history, and open questions in their original context.
- `tiered-ceremony.md` (sibling) — the policy authority establishing when the diamond workflow applies (tier 3 of the three-tier ceremony model); read this before deciding to run a diamond.
- `~/.claude/skills/jj-version-control/SKILL.md` (sibling) — the operational entity-level reference for the development join (multi-parent `@`, conflict behavior, edit-route cycle, route-and-extend recipe, composite maintenance invariant).
- `~/.claude/skills/preferences-adaptive-planning/SKILL.md` and `~/.claude/skills/session-review/SKILL.md` — the planning-DAG convergence-point semantics that align with the diamond's converge phase.
