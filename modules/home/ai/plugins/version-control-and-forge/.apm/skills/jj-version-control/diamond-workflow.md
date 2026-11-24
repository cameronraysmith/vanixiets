# Diamond workflow: beads epic to jj chain topology

This document is the canonical operational reference for the diamond workflow in this skill tree.
It describes the diamond workflow pattern that connects beads epic issue graphs to jj multi-parent version control, providing the theoretical foundations, beads-to-jj mapping, and mechanical recipe for epic-scoped work.

The companion design note at `docs/notes/development/version-control/epic-to-branch-diamond-workflow.md` is the theoretical foundation with full citations (Winskel event structures, Dilworth's antichain theorem, Lamport's partial order, Beer's VSM, Krycho's effective theory); when the *why* is in question, read the design note.
The sibling `tiered-ceremony.md` is the policy authority for *when* the diamond workflow applies — it answers "should I be using the diamond at all?" before this document answers "how do I run a diamond?".
The sibling `SKILL.md` is the operational entity-level reference for the development join itself (the multi-parent `@`, conflict behavior, edit-route cycle, route-and-extend recipe); when you need the day-to-day mechanics of working in a join, look there.

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
The serialize phase prepares a linear submission chain by rebasing each chain sequentially in dependency order.
For queue-managed GitHub repositories, external publication and landing follow `git-stacked-pr-integration` §Queue authorization and its upstream overrides, including the installation hold.
The queue may land tested batch merge commits; local serialization does not promise a merge-free trunk.

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
6. Before any file edit in wip, run the pre-edit cross-chain file-collision reconnaissance documented at `SKILL.md` §"Pre-edit cross-chain file-collision reconnaissance" to identify which chain (if any) already owns touchpoints on the file under edit, constraining chain selection so the route does not produce a structural conflict at `[merge]` during Phase 4 serialize.
   Develop in wip, routing changes to chains via the edit-route cycle.
   Throughout the develop phase `@` stays the single empty `[wip]` directly atop `[merge]` (invariant (iii)/(vi)); this shared `[wip]` is the stable coordination point that lets multiple concurrent editors write the same integrated surface safely.
   Route every change DOWN from `@` using only `@`-preserving verbs — `jj squash --from @ … --keep-emptied`, `jj absorb`, or `jj split` keeping the wip — and never `jj describe @` into content nor make `@` the subject of `jj rebase` / `--revisions @`, which drift `@` off `[wip]`, remove the surface other actors are concurrently writing, and (in this repo) drag the pushed `wip` deploy bookmark that machines rebuild from.
   The one sanctioned `jj rebase` touching `@` is the destination add/remove-chain form, whose destination is derived from the join's current parents and the trunk (`jj rebase -s <join> -d 'heads((parents(<join>) ~ ::trunk()) | trunk() | <new-chain>)'`) and which keeps `@` an empty child of the rebuilt join; the positional `--insert-before` / `--insert-after` (and the `-A` / `-B` aliases) forms are the prohibited ones.
   See the sibling `SKILL.md` invariant (iii-b) for the canonical statement.
   Each route from `[wip]` to a chain is either an append-route (default: land a new atomic commit on the chain) or an amend-route (fixups against the existing tip).
   The append-route is the default for landing new work:
   ```bash
   # Append-route: land a new atomic commit on <chain>
   jj squash --from @ --insert-after <chain-tip> -m "feat: description" --keep-emptied
   # capture <new-commit-id> from the "Created new commit <id>" line jj prints above
   jj bookmark move <chain> --to <new-commit-id>
   ```
   The `--insert-after` (`-A`) flag is what switches `jj squash` into create-a-new-commit mode (per the EXPERIMENTAL FEATURES doc comment on `SquashArgs` in `cli/src/commands/squash.rs`); without it, `--into <chain-tip>` amends the existing tip in place.
   As of jj 0.43.0, `jj squash --help` documents `-o`, `-A`, and `-B` under a heading of EXPERIMENTAL FEATURES.
   `--keep-emptied` preserves the single shared `[wip]` on top of `[merge]` (invariant (vi)); the bookmark-move is a separate explicit step because jj does not auto-advance a bookmark onto a newly inserted commit.
   Target the new commit's change ID from the `Created new commit <id>` output line, not `@-`: in a multi-parent join, `@-` resolves to the rebuilt `[merge]` (the new commit is one of its parents, not a direct ancestor of `@`), and pointing the bookmark there advances `<chain>` onto `[merge]`.
   See the sibling `SKILL.md` §"Routing to a chain: append vs amend" for the full rationale and the amend-route fixup recipe.

   Path-restriction (`-- <paths>`) can be added to either recipe when multiple streams' hunks coexist in `[wip]` and only one stream's paths should be routed in this operation.

   Fallback patterns, used only when neither route applies cleanly:
   ```bash
   # Auto-route by blame ancestry (fallback when blame is clean and unambiguous):
   jj absorb
   # Amend the existing chain tip in place (fixups only — preserves tip description by omitting -m):
   jj squash --from @ --into <chain-tip> --keep-emptied
   ```

#### Chain creation mid-diamond

Starting a new chain while the development join already exists (tier 3 is already active) REQUIRES same-operation join re-growth.
Issuing only `jj new main -m "wip(<name>): seed chain"` to begin a new chain produces three failure modes simultaneously:

- the new chain's seed commit is not in `parents([merge])`, violating invariant (i) (chain ∈ join's parents);
- the integrated state at `[wip]` does not reflect the new chain, violating invariant (iv) (wip holds integrated working tree);
- other agents working through `[wip]` silently miss the new chain entirely, treating it as if it does not exist.

The correct sequence creates the seed commit AND grows `[merge]` to include it in one operation sequence:

```bash
# 1. Seed the new chain from the trunk without moving @
jj new --no-edit 'trunk()' -m "<type>(<scope>): <subject>"

# 2. Bookmark the seed commit so it is addressable
jj bookmark create <name> -r <seed-change-id>

# 3. Add the new chain to [merge]'s parents; -s carries [wip] and anything above it
jj rebase -s <merge-change-id> -d '(parents(<merge-change-id>) ~ ::trunk()) | <name>'

# 4. Rewrite [merge]'s description with the new full set (announce it first when the join is shared)
jj describe <merge-change-id> -m "join N=k+1: <alphabetical bookmarks including <name>>"
```

Step 3 derives the destination from `[merge]`'s current parents rather than listing them, so a chain another session added since you last read the graph stays in the join; see `SKILL.md` §"Adding and removing chains".
After step 4, run the diamond-health diagnostic from the sibling `SKILL.md` as a sanity check on the executed recipe.

### Phase 3: converge (validate)

The converge phase occurs *at* a planning-DAG convergence point in the sense used by `preferences-adaptive-planning` and `session-review` — the diamond's converge phase and the planning DAG's topological convergence node refer to the same shape of synchronization point in the workflow.

7. The development join working copy represents the full integration.
8. Run tests, manual QA, and integration validation against the development join.
9. Fix issues by editing in wip and routing fixes to the appropriate chain.
10. Close beads issues as they pass validation: `bd close {issue-ID} --reason "Implemented in $(jj log -r '{chain-bookmark}' --no-graph -T 'commit_id.short(8)')"`.

The CCV closure operator (see `preferences-compositional-continuous-verification` §"What this means for an agent session") is invariant under the choice of `@`-position in the development join.
The wip `@` of a development join and the linearized aggregate tip produced by Phase 4 are hash-equal under the content-addressed graph: the same set of file trees, the same set of derivation closures, the same set of check outputs.
Running `just check-fast` before or after linearization provides equivalent local feedback when the relevant inputs match.
CI supplies feedback on published changes; queue-managed authorization follows `git-stacked-pr-integration` §Queue authorization rather than an all-buildbot-checks integration gate.

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
13. Set an aggregate bookmark at the linearized tip as a local ref for handoff:
    ```bash
    jj bookmark create <aggregate-bookmark> -r <linearized-tip>
    ```
14. Return the verified linearized chain ref and evidence to the publisher; workers do not publish or land.
    For queue-managed GitHub repositories, the publisher follows `git-stacked-pr-integration` §Queue authorization and §Fleet upstream overrides to publish the registered stack and authorize its intended head.
    The local aggregate bookmark does not require an extra aggregate PR or define a second merge gate.
15. Hand landing to the queue asynchronously under the owner; do not wait or push the default branch.
16. Exit local linearization to a single-parent working copy with `jj new <aggregate-bookmark>`.
    The `jj-linearize-join` tool performs that local exit automatically, without waiting for remote landing.
    During later work, fetch the actual remote result before proposing cleanup; do not assume it equals the original aggregate tip.
17. Push beads state:
    ```bash
    bd dolt push
    ```

### Partial Phase 4: subset submission with continued development

When an epic produces an integration-ready subset of chains while others are still in active development, the diamond can submit the ready subset and keep the rest as a smaller diamond above the linearized aggregate.
This is useful when forge review cycles for the ready subset are long enough that holding the entire epic-join until every chain is ready would stall the unsubmitted chains.

The `jj-linearize-join --keep-remaining` flag implements this partial Phase 4.
After the subset is linearized and the aggregate bookmark is created, each remaining chain is rebased onto the aggregate tip (`jj rebase -b <chain> -d <aggregate>`), then a new `[merge]` is constructed with parents `{aggregate, remaining_chains...}` and a fresh `[wip]` is created on top.
The reconstructed join's description follows the same `join N=k: <alphabetical bookmarks>` convention; the aggregate participates as a parent bookmark.

Invariant restoration after partial Phase 4:
- Invariant (i) (chain ∈ join's parents): the aggregate and every remaining chain are parents of the new `[merge]`; the previously submitted chains are not, by design — they exit the diamond via the forge merge.
- Invariant (ii) (parent set matches description): the new description names exactly the post-rebase parent bookmarks.
- Invariant (iii) (`@` atop join), (iv) (wip integrated), (vi) (single `[wip]`): restored by the trailing `jj new -m "wip"`.
- Invariant (v) (append-not-squash): preserved by `jj rebase -b`, which rebases the chain's commit graph rather than collapsing it.

The remaining chains continue developing above the local linearized tip while the submitted work is reviewed or queued.
When later work observes remote completion, fetch the actual target and reconcile under `SKILL.md` §Diamond integration on remote advance.
The queue can land a batch SHA different from the submitted tip, so do not advance `main` to the local aggregate as a post-landing shortcut.

Recipe:

```bash
jj-linearize-join --order c1,c2 --aggregate-bookmark agg-subset --keep-remaining
# auto-derives remaining = parents(@-) \ {main, c1, c2}
# OR
jj-linearize-join --order c1,c2 --aggregate-bookmark agg-subset --keep-remaining c3,c4
# explicit remaining set
```

After returning the subset ref for publication through `git-stacked-pr-integration` §Queue authorization, continue developing in the reconstructed `[wip]`.

The `jj-linearize-join` sibling tool performs steps 11–13 (the diamond-workflow → linearized-chain transformation) with `--dry-run`, real-run, and embedded `test` subcommand modes.
External stack publication for queue-managed GitHub repositories follows the policy owner instead of `jj-stack-submit`.
The generic N+1 aggregate recipe and Mergify Stack-Aware Base feature (`mergify-docs/src/content/docs/merge-queue/stacks.mdx` §Stack-Aware Base) belong outside this protocol.
They do not replace the registered-stack handoff in `git-stacked-pr-integration` §Queue authorization.

### Mid-diamond main-bound work and remote-drift integration

Two related operations arise during the develop phase when work surfaces that does not belong to any chain.

Invariant for every operation in this section: `@` is and stays the empty `[wip]` directly above the join.
Never `jj describe @` into a content commit and never make `@` the subject of `jj rebase` / `--revisions @` (nor the positional `--insert-before` / `--insert-after` / `-A` / `-B` forms); the by-relocation arm below relocates a SEPARATE, already-sealed non-wip commit, and `<X>` is never `@`/`[wip]`.
Drifting `@` below the join removes the shared `[wip]` that concurrent editors write to — the stable coordination point that makes N concurrent editors safe by construction — and, in this repo, drags the pushed `wip` deploy bookmark below the join, from which machines rebuild.
Route content that is still live in `@` DOWN with `jj squash --from @ … --keep-emptied`, which leaves `@` empty atop the join; only relocate already-sealed separate commits.
See the sibling `SKILL.md` invariant (iii-b) for the canonical statement.

**Splice-below-join** handles `<base>`-bound commits — hotfixes, formatting, config tweaks, dependency bumps — that should land on `<base>` before the diamond's chains.
Two arms: *by-construction* (author the commit directly in the splice position with `jj new --insert-before 'children(fork_point(parents(<join>))) & ::<join>'`) and *by-relocation* (move an EXISTING, SEPARATE, already-sealed NON-wip commit `<X>` — `<X>` MUST NOT be `@`/`[wip]` — from above the join into the splice region with `jj rebase --revisions <X> --insert-before 'children(fork_point(parents(<join>))) & ::<join>'`).
Never `jj describe @` then `jj rebase --revisions @ --insert-before <splice-target>`: that drifts `@` off `[wip]`, opens a transient window with NO `[wip]` on the join (catastrophic under concurrency), and (in this repo) drags the pushed `wip` deploy bookmark below the join.
When the change is still live in `@`, route it down with `jj squash --from @ --insert-before 'children(fork_point(parents(<join>))) & ::<join>' -m "fix(scope): description" --keep-emptied -- <paths>` instead, which leaves `@` empty atop the join.
The accumulated splice region can be submitted independently of the diamond's chains through `git-stacked-pr-integration` §Queue authorization for queue-managed repositories.
See the sibling `SKILL.md` §"Splice-below-join" for the full recipe, anti-patterns (naked `--insert-after <base>`, single-target `--insert-before <one-root>`, `jj rebase -r <X> -d <base>` destination form), and verification.

**Diamond integration on remote advance** handles the case where `<base>@origin` advances during diamond work — typically because a collaborator merged to remote, or a dependency-update bot pushed.
The recipe rebases the entire diamond (splice region if any, chain roots, chains, chain tips, join, `@`) onto the new remote tip in one operation, after `jj git fetch`.
This is distinct from Phase 4 serialize: it preserves the diamond shape rather than linearizing it.
See the sibling `SKILL.md` §"Diamond integration on remote advance" for the recipe, the breakdown of what `jj git fetch` handles automatically versus the diamond-on-old-base gap requiring explicit rebase, and verification.

Both operations target the same topological location — commits between `<base>` and the antichain `children(fork_point(parents(<join>))) & ::<join>`.
Splice-below-join inserts new commits there during diamond work; diamond integration on remote advance moves the entire diamond above a new `<base>` position, carrying the splice region (if any) with it.
The patterns compose: a diamond with accumulated splice commits can be integrated onto an advanced remote in one rebase, then return the ready splice ref for external authorization under the same owner.

## Concurrent sessions on one join

`SKILL.md` §"Coordinating concurrent sessions on one join" states the rules.
This section holds the commands behind them, the landing sequence, what a separate workspace gives up, and the omp mechanism.

### Reading the shared state

The join's parent set is a registry of chains that no session writes directly, and every harness can read it:

```bash
# Chains the join carries.
jj --ignore-working-copy log --no-graph -r 'parents(<join>) ~ ::trunk()' \
  -T 'change_id.short(8) ++ " " ++ description.first_line() ++ "\n"'
# Paths a chain already touches.
jj --ignore-working-copy diff --name-only --from 'trunk()' --to <chain>
# Strays: undescribed mutable commits, and any child of the join besides @.
jj --ignore-working-copy log -r 'mutable() & description(exact:"")'
jj --ignore-working-copy log -r 'children(<join>)'
```

Which session owns which chain, and which paths a session is about to edit, are not in the graph.
The join's description looks like a place to record them, and it is not sound as one.
It is a single string that every session would rewrite.
Two sessions describing the join in overlapping operations each rewrite the same commit, and jj merges the concurrent operations by keeping both rewrites, which leaves the join a divergent change (jj `docs/technical/concurrency.md` §"Merging divergent operations"; `docs/guides/divergence.md`).
Tools that regenerate the description from the parent set overwrite whatever a session added, and tools that parse its `join N=` first line break when it holds anything else.
Bookmarks on chain heads avoid the shared string, since concurrent moves of different bookmarks merge without conflict, but they record no paths and are one `jj git push` away from publication.
The `stigmergic-convention` signal tables live on beads issues and an agent-team task list belongs to one harness, so neither records the chains of a join.
No neutral registry for ownership and reservations is sound yet: read the parent set and the chains' diffs from jj, and carry ownership and reservations over whatever channel the sessions share.

### Landing while another session shares the join

A landing that moves the trunk leaves your other chains on the old trunk, and such a chain can conflict in the join with the content that just landed.
Finish the landing before announcing it:

```bash
jj git fetch
# Rebase each of your remaining chains onto the new trunk.
jj rebase -s 'roots(trunk()..<own-chain-b>) | roots(trunk()..<own-chain-c>)' -d 'trunk()'
# Rebuild the join; parents now on the trunk drop out, and the trunk stays a parent
# while no remaining chain contains it.
jj rebase -s <join> -d 'heads((parents(<join>) ~ ::trunk()) | trunk())'
```

When the forge rewrote the landed commits, their local copies are not ancestors of the trunk, so remove that chain with the remove form in `SKILL.md` §"Adding and removing chains".
Then confirm the other session's chains are still parents of the join and announce the landing as done.

### Sessions in a separate jj workspace

A separate jj workspace is warranted only when a separate tree is itself the point (`SKILL.md` §"Worktree interop").
Its `@` is not under the join, so its chains are not merged into the shared working copy and an incompatibility with them surfaces at landing rather than at the keyboard.
It also sits in a different directory, so harness features scoped to the directory, such as omp's cross-instance messaging below, do not connect it to the sessions in the primary.
What remains is the shared commit graph and operation log: both sides see each other's commits with the commands above, `jj workspace list` names the workspace, and its working-copy commit is not a stray to abandon.
Announce the workspace, its base and the paths it edits through the operator or any other channel, and add its chain to the join with the parents-derived form when it should integrate with the rest.

### omp: cross-instance messaging (other harnesses skip this subsection)

omp lets its interactive sessions in one directory read and message each other.
Each statement below is from omp's source (`packages/coding-agent/src`, omp 19.1.1) unless marked as observed; the mechanism was added in omp 19.0.0.

- Setting: `task.crossInstance`, default `false` (`task/settings.ts`), turned on in every participating session; it takes effect in a running session.
- Who joins: the main session of an interactive `omp` process, and through it that process's subagents (`main.ts`, `bindAgentMesh` only when interactive).
  `omp -p` and `omp acp` never join: with the setting on, `agent://peers` reports no other instances, reading `agent://<pid>` fails, and sends to a pid fail, because the mesh is never bound (`irc/mesh.ts` `agentMesh()`; `internal-urls/agent-protocol.ts`).
  An omp session driven over ACP, for example by omnigent, therefore neither sees nor is seen by interactive sessions, whatever directory it runs in; an ACP client also typically gives it its own workspace.
  Participation would need an upstream change that binds the mesh per ACP session; the mesh is one per process, while an ACP server holds several sessions with their own directories, and no setting does it.
- Room: the realpath of the directory omp started in (`daemon/client.ts` `canonicalProjectDir`); nothing maps a subdirectory, a second clone, a git worktree or a jj workspace back to the repository, so each is a separate room (not tested).
  The room is a unit of a per-user daemon, so another account cannot join.
- List: read `agent://peers`, which prints `- agent://<pid> (<status>)` per peer, with the note `This instance: <pid>`; it shows no titles, directories or subagent ids.
- Read: `agent://<pid>` shows a peer's yields and latest assistant text, not its tool calls, and `agent://<pid>/<SubagentName>` a peer subagent's output; reading never disturbs the peer (observed).
  `history://` does not resolve peers.
- Message: write to `agent://<pid>` or `agent://<pid>/<SubagentName>`.
  A busy peer gets it at its next step boundary and an idle one is woken into a new turn (`session/irc-bridge.ts`); the sender sees `Delivered to <pid>.` and the recipient must write back for there to be a reply (observed).
- Notes: append `?progress` (`agent://<pid>?progress`).
  A note does not interrupt a busy peer and does not count against the budget, but an idle peer is still woken by it (`session/irc-bridge.ts`).
- Budget: a session accepts at most 20 messages from one peer in 10 minutes, notes excluded (`irc/mesh.ts` `WAKE_BUDGET`).
- Limits: pids change when a session restarts, so read `agent://peers` again after any restart; the TUI lists no peers; incoming text is marked as from an agent, never the user (rule 8).
  Messaging informs and enforces nothing; the join keeps its parents only while each session follows the rules.

Templates, with `<pid>` the peer's pid from `agent://peers`:

```text
# Start of session, to agent://<pid>
Session <own-pid> on this join. I own chains <change-id> (<subject>) and <change-id> (<subject>).
I will edit <paths>. Reply with your chains and any paths you have reserved.

# Before and after a landing, to agent://<pid>?progress
Landing <change-id> now: publish, then fetch and restack the join. Hold join rebuilds until I say done.
Landed <change-id>. My remaining chains are on the new trunk and the join is rebuilt; your chains <change-ids> are still parents.

# Reserve and release paths, to agent://<pid>
Reserving <paths> while a subagent edits them for <change-id>; please stay out of them until I release.
Released <paths>; the edit is routed into <change-id>.
```

Evidence for this subsection: the source reading above, plus one afternoon of two interactive sessions on one join that used listing, reading, notes and messages as described.

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
- `SKILL.md` (sibling) — the operational entity-level reference for the development join (multi-parent `@`, conflict behavior, edit-route cycle, route-and-extend recipe, composite maintenance invariant).
- `preferences-adaptive-planning` and `session-review` — the planning-DAG convergence-point semantics that align with the diamond's converge phase.
