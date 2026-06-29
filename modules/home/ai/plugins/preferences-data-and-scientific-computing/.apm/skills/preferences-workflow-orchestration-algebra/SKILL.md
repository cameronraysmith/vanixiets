---
name: preferences-workflow-orchestration-algebra
description: >
  Algebraic and categorical reading of data/pipeline workflow orchestrators (Dagster, Flyte)
  through the Build Systems à la Carte lens, plus the functional-programming and CCV discipline
  for the gaps the orchestrator does not enforce itself. Scoped to data-pipeline orchestration,
  not agent/subagent workflow DAGs. Load when mapping a Dagster asset graph to a free-term /
  store-interpreter structure, choosing between asset-based and task-based orchestrators,
  writing a lawful IO manager, reasoning about static-vs-dynamic dependencies in a pipeline,
  or enforcing type-safe FP discipline on Dagster or Flyte pipelines in Python.
---

# Workflow orchestration algebra

The Dagster asset layer is a thin coat of branding over a free-construction-plus-interpreter pattern, and reading it through Build Systems à la Carte is unusually clean precisely because of that.

## Thesis

Dagster's asset layer admits a Build Systems à la Carte (BSalC) reading exactly to the extent that it is already a free-`Tasks`-plus-store-interpreter system wearing data-engineering vocabulary.
The asset-key dependency graph is a free term — a `Tasks`-like object, a free diagram over the dependency DAG — and the IO manager plus executor is the interpreter that runs that term against a store.
The mapping is tight because Dagster separated *definition* (the asset-key DAG, a declared static term) from *execution* (the IO manager and executor, an algebra over a store), and that definition/execution split is the same free-structure/algebra split BSalC is built on.
Airflow and Flyte are murkier cases precisely because they do not maintain that split as cleanly (see *02-asset-vs-task-spectrum.md*).

The load-bearing rule for using any of this: almost every Dagster construct maps onto *either* the free term *or* the interpreter, and confusing the two is the main source of muddle.
The asset graph, partitions, and data versions live on the free-term side; the IO manager, executor, and resources live on the interpreter side; sensors and schedules live on neither, because they are the impure effect pole bolted on outside BSalC.
Keep that boundary in front of you and the rest of this skill is bookkeeping.

This is not decoration.
The category theory hands you a *proof obligation*: an IO manager is a lawful store algebra only when materialization is a pure function of `(AssetKey, PartitionKey)` and `load ∘ store = id`.
That law is the precise, checkable condition under which Dagster's caching becomes correct in BSalC's sense, and it is the spec for the one component — a custom IO manager, here a Lance-flavored one — you have to write yourself.
The discipline layer in *03-fp-discipline-and-enforcement.md* discharges that obligation and the others Dagster leaves unenforced.

## Build Systems à la Carte in one page

BSalC factors every build system into a `Task` abstraction, a `scheduler ∘ rebuilder` composition, and a constraint that fixes how rich the dependency structure may be.
This is the spine the whole skill maps onto; the per-primitive rationale is deferred to *01-dagster-categorical-mapping.md*.

A single build rule is the newtype `Task c k v = Task { run :: forall f. c f => (k -> f v) -> f v }`, with `Tasks c k v = k -> Maybe (Task c k v)` assigning a rule to each computed key and `Nothing` to each input key.
A task is side-effect-free and isolated from the world: it only says how to compute one value, given a callback `fetch :: k -> f v` that supplies its dependencies' values.
The rank-2 `forall f. c f =>` quantification is load-bearing — the task author does not choose `f`, so one task description runs under many interpreters (extract dependencies under `Const`, recompute under `Identity`, track under `WriterT`).
A `Tasks` value is therefore a *free structure* over a signature of "fetch dependency" operations, and a build system is an *interpreter* — an algebra, a natural transformation — that runs it against a `Store`.
A build is the fixpoint `value(k) = task_k(values of deps(k))`, and every real system is `build = scheduler ∘ rebuilder`: the scheduler decides order (topological, restarting, suspending), the rebuilder decides whether work is needed (dirty bit, verifying traces, constructive traces, deep constructive traces).

The constraint `c` on `f` is exactly what determines the dependency structure a task can express, along the chain `Functor ⊂ Applicative ⊂ Selective ⊂ Monad`.
`Applicative` means *static dependencies*: the full dependency graph is knowable without computing any value, extracted structurally by running the task in a non-computing applicative (`f = Const [k]`), so it can be topologically sorted ahead of time — Make, Ninja, Buck live here.
`Monad` means *dynamic dependencies*: with `>>=` a task extracts a fetched value and chooses the next dependency from it, so the graph is discoverable only by running against a concrete store — Excel, Shake, Bazel, Nix live here.
`Selective` sits strictly between: all candidate dependencies are statically visible (an over-approximation across all branches), but only the taken branch's effects execute at run time.

A provenance flag carried throughout this skill: the local copy of Mokhov, Mitchell and Peyton Jones, "Build Systems à la Carte" is the ICFP 2018 version, which *predates* Selective functors.
Selective was introduced in the authors' 2019 "Selective Applicative Functors" and folded into the JFP 2020 extended version.
Wherever Selective is invoked — including the `Applicative ⊂ Selective ⊂ Monad` placement above — that material is reconstructed from the follow-on work, not the 2018 text, and is flagged as such at each use.

## The master mapping table

This is the spine of the skill: most Dagster constructs land on the free-term side or the interpreter side of the BSalC split, and each carries an explicit tightness tag.
See *01-dagster-categorical-mapping.md* for the per-row rationale, the exact API symbols, and the worked derivations.

| Dagster primitive | maps to | tightness |
|---|---|---|
| asset graph (`@asset`, `AssetKey`, `deps=`) | the `Tasks` object — a free diagram, a functor from the dependency DAG into the value category, presented relationally by key | tight |
| static vs dynamic assets (`DynamicOut`, `map`/`collect`, `DynamicPartitionsDefinition`) | `Applicative` vs `Monad` — graph knowable before execution vs later deps chosen from computed values | tight (most load-bearing) |
| IO manager (`handle_output`, `load_input`) | the store algebra — the natural transformation from "I need dep `k`" operations into actual store effects | almost (modulo `load ∘ store = id`, address a function of key) |
| partitions (`PartitionsDefinition`, `MultiPartitionsDefinition`, `PartitionMapping`) | an indexed family `{v_p}` — a functor `P → 𝒱`, a fibration of the asset over its partition space; sparse products are presheaves on a sub-poset | tight (categorical upgrade) |
| materialization + `code_version` + `DataVersion` | the constructive/verifying trace — `code_version` plus input data-versions hashing to output, early cutoff by its actual name | tight |
| resources (`ConfigurableResource`) | a reader monad / coalgebra of context | almost (gestural — no laws Dagster checks) |
| asset checks (`@asset_check`) | a refinement `{v : τ ∣ φ(v)}` evaluated post hoc — a runtime contract, not a Σ-type | almost (the proposition exists, the static guarantee does not) |
| sensors / schedules (`@sensor`, `@schedule`, `AutomationCondition`) | the effect pole — a coalgebra `S → (Event, S)`, a stream transducer | almost (deliberately outside BSalC) |
| ops / graphs (`@op`, `@graph`, pre-asset layer) | a morphism in a free symmetric monoidal category — boxes are ops, wires are dependencies, the tensor is parallelism | tight but legacy |

## The honesty discipline

Every mapping above carries one of two tags, and the tag is the most informative thing about it.
A mapping is *tight* when Dagster's construct genuinely is the categorical object (the asset DAG is a free diagram; static-vs-dynamic is Applicative-vs-Monad; partitions are an indexed family; data versions are a trace).
A mapping is *almost* when it holds only modulo a named coherence condition Dagster does not enforce — the IO manager is a store algebra *modulo* `load ∘ store = id`; resources are a reader monad *modulo* a discipline you impose; asset checks are a refinement *modulo* the missing static guarantee.
The *almost* tag spans a range: at its weakest a mapping is *gestural*, a descriptive vibe to discipline yourself with rather than a structure with checkable laws, which is how the resources row is tagged.

The almost is where all the information is.
A tight mapping tells you nothing you have to do; an almost mapping names the exact proof obligation that, once discharged, upgrades a vibe into a correctness guarantee.
The IO-manager law is the canonical example: stating it tightly is what converts "Dagster has caching" into "Dagster's caching is correct in BSalC's sense, given this property of your IO manager."
Never present an almost mapping as tight — the dropped coherence condition is precisely the discipline the user must self-impose, and *03-fp-discipline-and-enforcement.md* is the catalogue of those impositions.

## What 02 and 03 add

*02-asset-vs-task-spectrum.md* develops the asset-vs-task contrast as a three-point spectrum along the BSalC constraint axis rather than a binary.
Airflow's classic operator is an opaque side-effecting `execute()` with no value identity and no fetch/store separation, so there is no `Tasks` object to point at — definition and effect are fused.
Flyte v2 inverts its own v1 model: it has no statically compiled pipeline graph at all, growing a runtime action tree by ordinary `async` Python control flow, which is honestly monadic-by-construction (closer to an indexed-effect monad than to a declared static term).
Dagster sits at the static-declared-DAG-over-persisted-data end, which is why its BSalC reading is the cleanest of the three.
The spectrum reads Airflow → Flyte v2 → Dagster as decreasing fusion of definition and execution and increasing recoverability of the free-term/interpreter split.

*03-fp-discipline-and-enforcement.md* closes the almost-gaps with type-safe functional-programming discipline and CCV regulators.
It is anchored by a fully worked lawful IO-manager example (Lance-flavored but generalizable) that discharges the `load ∘ store = id` proof obligation, and it threads the twelve enforceable rules — domain-vocabulary boundaries, parse-don't-validate, discriminated-union pipeline state, typed-failure-track errors, effects-at-boundaries, algebraic laws on combine/fold logic, and the CCV traceability/adequacy/integrity chain — onto the constructs Dagster leaves unguarded.
The connective tissue is that every almost in the mapping table corresponds to one or more enforceable rules in 03.

## Complementarity with the sibling Dagster skills

Three skills cover Dagster work and they do not overlap; route by what the question is *about*.

| Skill | Owns | Use for |
|---|---|---|
| `dagster-expert` | operational APIs, the `dg` CLI, decorator recipes, integrations | creating projects, adding definitions, debugging, looking up exact CLI/API syntax |
| `dignified-python` | imperative, LBYL-leaning production Python style (general-purpose, not Dagster-specific) | code quality, import structure, exception handling, version-targeted idioms |
| this skill | the algebra, the BSalC mapping, and the FP-law discipline closing the almost-gaps | mapping a primitive to its categorical object, choosing asset-vs-task, writing a lawful IO manager, enforcing type-safe FP laws on a pipeline |

The boundary is clean: this skill names the *law and structure*, `dagster-expert` holds the *API*, `dignified-python` holds the *imperative style*.
When this skill needs an operational API it defers to `dagster-expert` by reference rather than restating symbols; both Dagster skills live under `/Users/crs58/projects/omicslake-workspace/dagster-skills/skills/`.

## Contents

| File | Read when |
|---|---|
| [01-dagster-categorical-mapping.md](01-dagster-categorical-mapping.md) | you need the per-primitive rationale, exact API symbols, and the derivation behind each row of the mapping table |
| [02-asset-vs-task-spectrum.md](02-asset-vs-task-spectrum.md) | choosing between asset-based and task-based orchestrators, or placing Airflow / Flyte v2 / Dagster on the constraint axis |
| [03-fp-discipline-and-enforcement.md](03-fp-discipline-and-enforcement.md) | enforcing FP-law discipline on a pipeline, writing a lawful IO manager, or wiring CCV regulators onto Dagster definitions |

## Cross-references

- `preferences-theoretical-foundations` — free structures, functors, natural transformations, and the categorical vocabulary the mapping table draws on
- `preferences-algebraic-laws` — functor/monad/monoid laws and Hypothesis property tests that verify the combine/fold obligations in 03
- `preferences-compositional-continuous-verification` — the operating-envelope-plus-regulator closure operator that 03 wires onto each Dagster definition
- `preferences-domain-modeling` — smart constructors, parse-don't-validate, and making illegal states unrepresentable, applied at op/asset boundaries
- `preferences-railway-oriented-programming` — `Result`/`AsyncResult` composition for the typed-failure-track rule
- `preferences-python-development` — basedpyright, beartype, and Expression as the static/runtime/effect-explicit toolchain enforcing the rules
- `preferences-event-sourcing` — the fold/replay reconstruction laws licensing incremental and partitioned re-materialization
