# Epic-to-branch diamond workflow

Design notes for a workflow bridge connecting beads epic/issue graphs to jj multi-parent version control, grounded in lattice theory, event structures, and the Viable System Model.

## Motivation

Session 2026-03-28 surfaced a structural gap: the existing skills cover beads issue management, jj multi-parent mechanics, and adaptive planning independently, but nothing connects them into a unified workflow for planning, executing, and integrating epic-scoped work.

The immediate trigger was the question of whether to preserve N-way merge structure or linearize when integrating to main.
The deeper question is how the issue dependency graph should *drive* the version control topology from planning through integration.

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
                  [N-way composite]
                  [validate / QA]
                         |
           [sequential rebase to main]
                         |
                    [main after]
```

The diverge phase decomposes the epic into parallel bookmark chains based on issue dependencies.
The develop phase works concurrently across chains using the jj multi-parent composite (merge + wip pattern).
The converge phase validates the integrated whole before committing to merge.
The serialize phase produces the final main history by rebasing each chain sequentially onto main, yielding a purely linear commit history.

## Theoretical foundations

### Lattice theory

The epic forms a bounded lattice.
The bottom element is the starting state (main before work begins).
The top element is the integrated result (the validated composite ready for merge).
Issues are elements between them, with the dependency graph defining the partial order.

Independent issues (no dependency path between them) form antichains, which are maximal sets of mutually incomparable elements.
These antichains correspond directly to the sets of bookmark chains that can be developed in parallel.

By Dilworth's theorem, the minimum number of sequential chains needed to cover the partial order equals the maximum antichain width.
This gives a lower bound on the number of rebase steps needed to linearize the work.

### Event structures

Winskel's event structures (1986) provide the operational semantics.
An event structure has events (commits), a causal dependency relation (issue dependencies), and a conflict relation (changes that cannot coexist).
A *configuration* is a consistent, causally closed set of events.

The N-way composite working copy is a configuration: a conflict-free set of commits whose dependencies are all satisfied.
The development process moves through the *domain of configurations*, from the empty configuration (main) through partial configurations (individual chains) to the full configuration (the composite).
The linearized commit sequence on main records a path through this domain.

This framing clarifies why the N-way merge is correct during development (it represents a valid configuration for testing) but the sequential rebase linearization is correct for history (it records the path through the configuration domain).

### Concurrency theory

The development of independent issues is genuinely concurrent in Lamport's sense: neither happened-before the other.
The N-way composite is a synchronization point where concurrent work streams are verified to be conflict-free.

A purely linear history imposes a total order on concurrent events, but this is acceptable when the integration sequence is chosen to respect the dependency partial order.
The linearized rebase history records the dependency-respecting serialization directly: `git log` shows every atomic commit in the order they were integrated.

The planning question "which issues can be developed in parallel?" is equivalent to finding antichains in the dependency graph.
The integration question "in what order do we merge to main?" is a chain decomposition of the partial order.

### Viable System Model mapping

The diamond workflow maps onto the VSM structure already referenced in the adaptive planning skill.

| VSM system | Diamond phase | Function |
|---|---|---|
| System 1 | Develop | Implementation work in parallel bookmark chains |
| System 3 | Composite | Internal coordination via N-way merge, conflict detection |
| System 3* | Validate | Audit: manual QA, integration testing on the composite |
| System 4 | Plan / decide | Adaptation: epic decomposition, merge-readiness decision |
| System 5 | Merge to main | Identity: the repository's authoritative state |

The planning horizon question ("how much work to batch before merging") maps to the requisite variety principle: the composite must have enough integrated changes to be meaningfully testable, but not so much that integration risk is unmanageable.
This is the MPC receding-horizon planning from the adaptive planning skill applied to version control.

## Mapping from beads to jj

| Beads concept | jj concept | Lattice theory |
|---|---|---|
| Epic | Linearized chain group on main | Bounded lattice |
| Issue dependency graph | Chain topology (which bookmarks depend on which) | Partial order |
| Independent issues | Parallel bookmark chains | Antichains |
| Issue blocking relation | Chain stacking (one bookmark branching from another's tip) | Covering relation |
| Epic validation | N-way composite working copy (merge + wip) | Configuration |
| Merge to main | Sequential rebase linearization | Chain decomposition |
| Planning horizon | Number of issues per epic before integration | Requisite variety |

## Integration strategy: sequential rebase linearization

During development, the N-way merge serves as a workspace for concurrent editing and integration testing.
When the epic is validated, the N-way merge is dissolved and the chains are rebased sequentially onto main, producing a purely linear history with no merge commits.

The integration sequence proceeds as follows.
First, abandon the development join (the merge commit and wip commit that formed the composite working copy).
Then rebase each chain onto main in dependency order: chains whose issues are depended upon by other chains rebase first.
When chains are fully independent, ordering is discretionary (alphabetical, thematic, or by size).
Each chain's atomic commits land directly on the mainline, preserving the granular development history without merge-commit wrappers.
After all chains are rebased, fast-forward main to the linearized tip.

Push the linearized branch for CI validation via PR, then advance main locally after CI passes.

The resulting history is fully linear.
`git log` on main shows every atomic commit in integration order, which is the narrative.

## Mechanical recipe

### Plan phase

1. `bd epic status` to survey the issue dependency graph.
2. Identify antichains (sets of independent issues) and map them to bookmark chains.
3. Create bookmarks from main for each chain: `jj new main` per chain.

### Develop phase

4. Create the N-way composite: `jj new chain-a chain-b chain-c ...`
5. Describe the merge with a numbered manifest: `jj describe -m "merge 1: description\n- chain-a\n- chain-b\n..."`
6. Create wip on top: `jj new`
7. Develop in wip, routing changes to chains via `jj squash --into <target> -u -- <path>` or `jj absorb`.

### Validate phase

8. The composite working copy represents the full integration.
9. Run tests, manual QA, and integration validation against the composite.
10. Fix issues by editing in wip and routing fixes to the appropriate chain.

### Integrate phase

11. Dissolve the composite (abandon the merge and wip commits).
12. For each chain, in dependency order:
    ```
    jj rebase -s <chain-base> -d main
    jj bookmark set main -r <chain-tip>
    ```
13. Push the linearized branch for CI validation via PR, then advance main locally after CI passes.

## Open questions

These items need further design work.

How should the PR description format be standardized for linearized epic integrations?
The relationship between chain ordering in the PR, beads issue/epic IDs, and the conventional commit messages on the atomic commits needs to be defined.

How should cross-chain dependencies (issue A in chain 1 blocks issue B in chain 2) be handled during the develop phase?
The current approach is chain stacking (chain 2 branches from chain 1's tip), but this creates serial dependencies that may be avoidable.

Should the integration order be encoded in the beads graph (e.g., as a `merge-order` attribute on the epic) or derived at integration time from the dependency structure?

How does this interact with CI?
The composite is the natural CI target during development, but CI on the linearized branch is needed before advancing main.

What is the optimal planning horizon (number of issues per epic)?
The adaptive planning skill's MPC framework suggests this depends on the volatility of requirements and the cost of integration, but concrete heuristics for this codebase would be valuable.

## References

- Winskel, G. (1986). "Event structures." Advances in Petri Nets.
- Davey, B. A. and Priestley, H. A. (2002). "Introduction to Lattices and Order." Cambridge University Press.
- Lamport, L. (1978). "Time, Clocks, and the Ordering of Events in a Distributed System."
- Beer, S. (1972). "Brain of the Firm." Allen Lane.
- Dilworth, R. P. (1950). "A Decomposition Theorem for Partially Ordered Sets."
- Krycho, C. (2024). "Jujutsu Megamerges and jj absorb."
- Bird, C. et al. (2009). "Does Distributed Development Affect Software Quality?"
