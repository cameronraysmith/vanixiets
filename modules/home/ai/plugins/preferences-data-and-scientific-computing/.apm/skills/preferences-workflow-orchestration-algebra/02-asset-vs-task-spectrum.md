# The asset-vs-task spectrum on the Build Systems à la Carte constraint axis

The "asset-based vs task-based" distinction is not a binary; it is a three-point spectrum — Airflow, then Flyte v2, then Dagster — graded by how far each orchestrator separates the *definition* of a computation from its *execution*, which is exactly the free-structure-plus-interpreter split that the Build Systems à la Carte (BSàlC) reading is built on.

## Why a spectrum, not a dichotomy

The convenient slogan is "Dagster names data, the others name computations."
That is true as far as it goes, but it flattens a real gradient.
The load-bearing question BSàlC asks of any system is whether there is a `Tasks f k v` term to point at — a free structure describing dependencies that can be inspected, scheduled, and interpreted *without running the effects* — and an interpreter (`scheduler ∘ rebuilder` over a `Store`) that runs it.
See *01-dagster-categorical-mapping.md* for the Dagster-to-BSàlC mapping in full; this file places Dagster against its two neighbours rather than re-deriving it.

Two orchestrators can both call their unit a "task" and still sit at very different places on this axis.
Airflow fuses definition and effect with no types at the boundary, so there is nothing to read.
Flyte v2 fuses definition and effect *but* enforces strong typed I/O at every boundary, so the fusion is principled even though no static `Tasks` term exists.
Dagster separates the two outright, which is why it alone admits the clean BSàlC reading.
The spectrum is therefore ordered by *separation of term from interpreter*, with a secondary axis of *typing at the boundary* that distinguishes the two fused systems from each other.

## Point 1 — Airflow: fusion without types, no BSàlC reading

Airflow is the negative pole worked in the seed discussion.
Its classic operator is an opaque side-effecting `execute()` method.
The node identity is the operator instance itself: there is no value identity, because an operator does not denote a value, it *performs an effect*.
The edges, declared via `>>` or `set_upstream`, are pure ordering constraints — "run B after A" — carrying no data and no typed contract; XCom is an untyped side channel bolted on, not a wire type.

There is no fetch/store separation: the operator opens its own connections and writes its own outputs inside `execute()`, so the framework never mediates "I need dependency k" as a distinct, interpretable operation.
There is no trace in the BSàlC sense (no recorded `(key, hash-of-deps, result)` for verifying or constructive rebuilding); rerun logic keys on task-instance state, not on value or dependency hashes.

The static/dynamic character is "static skeleton, opaque interior": the DAG topology is declared up front, but each node's behaviour is an arbitrary Python effect with no inspectable dependency structure.
On the BSàlC constraint axis this places Airflow *off the axis entirely*.
The axis classifies `Tasks` terms by the `Applicative`/`Selective`/`Monad` constraint on `f`; Airflow has no `Tasks` term to classify, because *definition and effect are fused and untyped*.
There is no `f`, no callback `fetch :: k -> f v`, nothing to instantiate at `Const` for dependency extraction or at `Identity` for recomputation.
Airflow admits no clean BSàlC reading — not "almost", but genuinely none.

## Point 2 — Flyte v2: typed monadic fusion, an almost-indexed-effect monad

Flyte v2 is a clean-break redesign of v1 and inverts v1's model in the one respect that matters here.
Verified against `~/projects/sciops-workspace/flyte-sdk/src/flyte/`: the v2 public surface is task-centric, and v1's static-DAG vocabulary is gone.
There is no `@workflow`, no `@dynamic`, no `conditional`/`if_`, no `map_task`, no `LaunchPlan`.
Fan-out is `flyte.map` and human-in-the-loop gating is `flyte.new_condition`/`ConditionWebhook`, but neither reintroduces a static DAG — `map` is run-time fan-out parallelism over a task and `new_condition` is an awaited external signal, both runtime helpers within the async task model rather than v1's static branching.
The only authoring decorator is `@env.task` on a `flyte.TaskEnvironment`; a "workflow" is just an `async def` parent task that `await`s child tasks.

The node identity is a *task* — a typed function `(in: LiteralType...) -> (out: LiteralType...)`.
Flyte names computations, not data.
The edges are *runtime data dependencies*: one task `await`s another and receives an eager, materialized, strongly-typed Python value across a serialization boundary.
There is no global declared edge set and no statically materialized pipeline graph; the only compiled artifact per task is its `TypedInterface` (a `VariableMap` of `LiteralType`), not a `Node`/`Binding` graph.
The action tree is *grown at run time* by the controller as the parent process makes calls.

The static/dynamic character is therefore fully dynamic.
Inside a task context, awaiting a child does not run it inline — it routes to `get_controller().submit(...)`, which enqueues a new action on the backend and suspends the coroutine until the result returns; outside a task context the same call falls through to `forward()` and runs as plain Python.
The primary submission verb for an async child is its ordinary `__call__` (`await child(x)`); `child.aio(x)` is the same controller-submission path exposed as a migration affordance for invoking a *sync* task from an async parent, so both submit but `aio` is the migration-oriented variant rather than the only entry point.
Every v1 `@dynamic` is now simply the default behaviour of any `async` task with loops and branches.

The typed-I/O property is the discriminating feature against Airflow.
Data crossing a boundary is converted by the `TypeEngine` and per-type `TypeTransformer`s to protobuf `Literal` values typed by `LiteralType`, and type assertions fire at conversion time.
Crucially these are *eagerly materialized typed values* moving across boundaries, validated against declared `LiteralType`s — not symbolic edges in a dependency graph.
Caching is per-task on code-version plus typed-input hashes (`Cache` with `"auto"`/`"override"`/`"disable"`, the default `FunctionBodyPolicy` hashing the function source body), not a persisted named data asset with its own materialization identity.

On the BSàlC constraint axis Flyte v2 is the *fully monadic extreme*: a later dependency's identity can depend in an unbounded way on a fetched value, because control flow is ordinary Python.
But unlike Airflow it is *typed and lawful at the boundary*, so the monadic fusion is principled rather than opaque.
The seed digest frames this as: Flyte v2 models orchestration as typed effectful functions composed by an async host program — *close to* an indexed-effect monad in Python, where awaited controller submission (the `__call__`/`aio` path) is the bind, the controller is the effect interpreter, and `LiteralType` is the index (Kleisli arrows over a typed action category).

This reading is aspirational, not an asserted fact, and the honest qualification matters.
Flyte v2 was not built as an indexed monad and proves no monad laws; the correspondence is a lens, not a theorem.
Two caveats sharpen the "almost".
First, the BSàlC constraint axis classifies *static `Tasks` terms*; Flyte v2 has no static term at all, so it inhabits the monadic *end* of the axis only in the sense that its dynamism is maximal — there is no applicative fragment to extract via `Const`, because the dependency set is never knowable before execution.
Second, v1 told the opposite story: a v1 `@workflow` ran once at registration over `Promise` placeholders to emit a static `Node`/`Binding` DAG — an applicative-flavoured term much closer to Dagster — and v2 deliberately inverted this to pure-Python runtime growth.
So the indexed-effect-monad reading is "almost / aspirational": the typing is real and the bind-shaped composition is real, but the lawful indexed-monad structure is a discipline a careful author can *impose*, not one Flyte checks.

## Point 3 — Dagster: a free term plus an interpreter, the one clean BSàlC reading

Dagster's asset layer is the positive pole, and it is the only one of the three that admits the clean BSàlC reading, because it *separates definition from execution outright*.
The node identity is an *asset* — a named, persisted, versioned datum, addressed by a global `dg.AssetKey`, whose `@dg.asset` function materializes it.
The asset graph is the `Tasks` term itself: a free diagram, a functor from the dependency poset into the value category, presented relationally by key rather than lambda-bound.

The edges are *declared key-to-key dependencies* (`deps=`, `AssetIn`, asset keys), resolvable by the framework before and independent of execution.
Values are not in-band wire edges: an asset's value is a *side effect of materialization to a store* via an IO manager, and a downstream asset either receives the loaded value or merely depends on the key.
This is the fetch/store separation BSàlC requires — the IO manager is the `fetch`/store side of the interpreter, the natural transformation from "I need dependency k" into actual store effects.

The static/dynamic character is genuinely mixed and maps cleanly onto the constraint axis.
A purely declared asset graph is the *applicative* fragment: the full dependency graph is knowable before any value is computed, extractable the way BSàlC instantiates `f = Const [k]`.
Dynamic outputs (`dg.DynamicOut`, `map`/`collect`) and run-time partition or sensor-driven structure are the *monadic* fragment, where a produced value chooses the next dependency.
This is the most load-bearing mapping in the whole framework — static-vs-dynamic *is* `Applicative` vs `Monad` — and it is precisely the classification the constraint axis exists to make, which is why Dagster is the only one of the three the axis can read.

The typed-I/O property is weaker than Flyte's by design and in a different place.
Dagster's `dg.DagsterType` (and pydantic config) check *materialized contents*, not an in-process wire contract between futures; the value lives in a store, so typing is a refinement on what was persisted rather than a transformer firing at a serialization boundary.
This is the right trade for the asset orientation: the contract is on the stored datum's identity, which is what enables lineage, freshness, and trace.

On the BSàlC constraint axis Dagster *spans* the axis (applicative for the declared graph, monadic for the dynamic fragment) rather than occupying one end, and — uniquely — admits the clean reading: there is a `Tasks` object to point at, an interpreter to run it, and a trace to make rebuilding minimal with early cutoff.
See *01-dagster-categorical-mapping.md* for the per-primitive mapping and *03-fp-discipline-and-enforcement.md* for the lawful IO-manager proof obligation that makes the interpreter side honest.

## The spectrum at a glance

| Orchestrator | Node identity | Edge meaning | Static / dynamic | BSàlC constraint placement | Typed I/O | Clean BSàlC reading? |
|---|---|---|---|---|---|---|
| Airflow | Operator instance (opaque `execute()`), no value identity | Ordering constraint (`>>`), no data, no contract | Static skeleton, opaque interior | Off the axis — no `Tasks` term, definition and effect fused | None (untyped XCom side channel) | No (none, not "almost") |
| Flyte v2 | Task = typed function `(LiteralType...) -> (LiteralType...)` | Runtime data dependency; eager typed value passed across a boundary | Fully dynamic; action tree grown at run time by the controller | Monadic extreme, but no static term to extract | Strong — `TypeEngine`/`TypeTransformer`/`Literal`/`LiteralType` at every boundary | Almost / aspirational (indexed-effect monad: `aio` ~ bind, controller ~ interpreter, `LiteralType` ~ index) |
| Dagster (asset) | Asset = named persisted versioned datum (`dg.AssetKey`) | Declared key-to-key dependency; value is a store side effect, not an edge | Spans the axis: declared graph applicative, `dg.DynamicOut`/partitions monadic | Applicative (static graph) ↔ Monad (dynamic outputs) | On materialized contents (`dg.DagsterType`), not a wire contract | Yes — free `Tasks` term + IO-manager/executor interpreter |

## The lesson

The free-structure-plus-interpreter *split* is what enables the algebraic (BSàlC) reading; fusing definition and execution collapses it.
Dagster keeps the split — the asset graph is a free term, the IO manager and executor are the interpreter — so the constraint axis can classify it and the trace machinery can make it minimal.
Airflow and Flyte v2 both fuse the two, and both lose the static `Tasks` term as a result.

But fusion is not one thing, and the difference between the two fused systems is the difference between *no theory* and *a different theory*.
Airflow fuses *without types*: there is nothing principled to recover, no boundary contract, no value identity — it is off the axis.
Flyte v2 fuses *with types*: the monadic, runtime-grown action tree is lawful at every boundary, and it almost reads as an indexed effect monad in Python.
That "almost" is where the information is: typed fusion is still principled — a coherent indexed-effect discipline a careful author can hold themselves to — it is simply a different mathematics than the free-applicative-or-monad-term-plus-store-interpreter mathematics that Dagster wears on its sleeve.

A note on provenance for the constraint vocabulary used above.
The `Applicative ⊂ Selective ⊂ Monad` chain is invoked here through `Applicative` and `Monad` only; the intermediate `Selective` point (static visibility of all candidate dependencies with selective execution of one branch's effects) is the natural home for a conditional, statically-extractable orchestrator, but Mokhov, Mitchell and Peyton Jones, "Build Systems à la Carte" (ICFP 2018, `~/projects/planning-workspace/engineering-references/mokhov-2018-build-systems-a-la-carte/`) predates `Selective`, which was added in their 2019 "Selective Applicative Functors" and folded into the JFP 2020 extended version.
None of the three orchestrators here sits cleanly at the `Selective` point, so the omission does not affect the spectrum; flag it only when invoking `Selective` directly.

## Cross-references

- *01-dagster-categorical-mapping.md* — the per-primitive Dagster-to-BSàlC mapping (asset graph as `Tasks` term, IO manager as interpreter, partitions as indexed family); referenced rather than restated here.
- *03-fp-discipline-and-enforcement.md* — the lawful IO-manager example and the proof obligation that materialization is a pure function of `(AssetKey, PartitionKey)`, which makes Dagster's interpreter side honest.
- preferences-theoretical-foundations, its internal-language reference — free structures, functors, indexed/fibered families, and the categorical vocabulary the spectrum leans on.
- preferences-algebraic-laws — the law-as-specification stance behind "almost / aspirational" versus "lawful"; the indexed-monad reading of Flyte v2 is the former, not the latter.
- Mokhov, Mitchell, Peyton Jones, "Build Systems à la Carte" (ICFP 2018), `~/projects/planning-workspace/engineering-references/mokhov-2018-build-systems-a-la-carte/sections/`.
