# Diamond workflow: beads epic to jj chain topology

This document describes the diamond workflow pattern that connects beads epic issue graphs to jj multi-parent version control.
It provides the theoretical foundations, beads-to-jj mapping, and mechanical recipe for epic-scoped work.
For the operational patterns (edit-route cycle, conflict behavior, parallel agent coordination), see SKILL.md in this directory.

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

### Event structures

Winskel's event structures (1986) provide the operational semantics.
An event structure has events (commits), a causal dependency relation (issue dependencies), and a conflict relation (changes that cannot coexist).
A *configuration* is a consistent, causally closed set of events.

The N-way development join is a configuration: a conflict-free set of commits whose dependencies are all satisfied.
The development process moves through the *domain of configurations*, from the empty configuration (main) through partial configurations (individual chains) to the full configuration (the development join).
The linearized commit sequence on main records a path through this domain.

This framing clarifies why the development join is correct during development (it represents a valid configuration for testing) but the sequential rebase linearization is correct for history (it records a linear extension through the configuration domain).

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

4. Create the N-way development join:
   ```bash
   jj new chain-a chain-b chain-c ...
   jj describe -m "merge 1: epic description
   - chain-a
   - chain-b
   - chain-c"
   ```
5. Create wip on top:
   ```bash
   jj new
   ```
6. Develop in wip, routing changes to chains via the edit-route cycle:
   ```bash
   # edit a file, then route atomically:
   jj squash --into <chain> -m "feat: description" path/to/file
   # or auto-route by blame ancestry:
   jj absorb
   ```

### Phase 3: converge (validate)

7. The development join working copy represents the full integration.
8. Run tests, manual QA, and integration validation against the development join.
9. Fix issues by editing in wip and routing fixes to the appropriate chain.
10. Close beads issues as they pass validation: `bd close {issue-ID} --reason "Implemented in $(jj log -r '{chain-bookmark}' --no-graph -T 'commit_id.short(8)')"`.

### Phase 4: serialize (integrate)

11. Abandon the development join and wip commits (they are ephemeral scaffolding):
    ```bash
    jj abandon <merge-change-id> <wip-change-id>
    ```
12. Rebase each chain onto main in linearization order (see "Linearization order: two cases" above):
    ```bash
    # For each chain, in dependency order:
    jj rebase -s <chain-base> -d main
    jj bookmark set main -r <chain-tip>
    ```
13. Push the linearized main for CI validation via PR, then advance main locally after CI passes:
    ```bash
    jj git push --bookmark main
    ```
14. Delete chain bookmarks and push beads state:
    ```bash
    jj bookmark delete chain-a chain-b chain-c
    bd dolt push
    ```

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
- Krycho, C. (2024). "Jujutsu Megamerges and jj absorb."
