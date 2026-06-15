# Functional-programming discipline and enforcement

The Dagster asset boundary is strong in identity and weak in data, so the lawfulness that the categorical reading of *01-dagster-categorical-mapping.md* assumes is a proof obligation you discharge in your own code rather than a property the framework checks.

## The discipline gap: identity is typed, data is not

The asset graph is a static relation between `AssetKey`s, and that identity is enforced: a dependency edge is an `AssetKey`-to-`AssetKey` arrow known before any run, matched by parameter name or `deps=`, and the framework refuses to resolve a graph with a dangling key.
This is the strength that makes the free-diagram mapping of *01-dagster-categorical-mapping.md* tight.

The data crossing that boundary is a different matter.
Dagster type enforcement is opt-in, runtime, and per-step: `_type_check_output` runs `do_type_check` against an output's `DagsterType` only when one is present, and an unannotated output defaults to `Any`, which type-checks trivially.
There is no framework-enforced static contract that an upstream output type is a subtype of the downstream input type across the graph.
The transport itself is untyped by signature: `IOManager.handle_output(self, context: OutputContext, obj: Any) -> None` stores an `Any`, and `IOManager.load_input(self, context: InputContext) -> Any` returns an `Any`.

This is exactly where the categorical reading hands you a *proof obligation* rather than a guarantee.
*01-dagster-categorical-mapping.md* rates the IO manager as *almost* a store algebra, lawful only when materialization is a pure function of `(AssetKey, PartitionKey)` and the round trip is identity, because Dagster does not enforce either condition.
The three *almost* mappings of that file — IO manager (lawful only if you make it so), resources (a gestural reader monad), asset checks (a runtime refinement contract, not a static type) — name precisely the places where the structure exists only if you impose it.
This file is the enforceable discipline that closes those gaps: the rule set that turns *almost* into *lawful*, the toolchain that makes each rule checkable, and the worked lawful IO manager that discharges the central obligation.
It does not restate the categorical mapping rationale (*01-dagster-categorical-mapping.md*) or the Airflow-to-Flyte-to-Dagster orchestrator spectrum (*02-asset-vs-task-spectrum.md*); it builds on both.

## The verification backbone: CCV closure operator

The discipline is enforceable only because each rule is paired with an automated regulator, and the regulators compose into a single deterministic command.
This is the compositional continuous verification (CCV) stance, summarized here and developed fully in *compositional-continuous-verification.md*.

The load-bearing primitive is the *operating-envelope-plus-regulator pair*.
An operating envelope is the declared set of conditions under which an artifact is committed to behaving correctly, made first-class as a structured artifact rather than assertions buried in test code, and it declares the coverage bins the regulators must saturate.
A regulator is an automated process that samples the artifact's actual behavior and compares it against the envelope; per the Conant–Ashby theorem (every good regulator must contain a model of the system it regulates) that model must be explicit.
The closure operator is the single composed evaluation of every regulator over the whole repository graph against pinned, content-addressed inputs, realized canonically as `nix flake check` against a pinned flake input, whose deterministic pass or fail operationalizes the question "is the system approximately correct?".

Approximate is precise, not vague: Rice's theorem and Ashby's law of requisite variety make perfect coverage structurally impossible, so the target is that the gap between intended and exercised behavior is visible, bounded, and decreasing.
The pairs compose into one closure operator through a four-property hierarchy, each property strictly stronger than the last.
*Existence* means at least one regulator of a given kind is present.
*Traceability* (breadth) means every artifact requiring regulation has at least one regulator targeting it, so the relation `regulates ⊆ Checks × Artifacts` is surjective onto artifacts-requiring-regulation; untraced code is structurally invisible.
*Adequacy* (depth) means the regulators in each traceability fiber jointly saturate the envelope's declared bins.
*Integrity* (vacuity-detection) means the regulator actually fails when its target is broken, verified by mutation testing: a deliberately broken mutant must kill the regulator.
The chain is that integrity is meaningless without adequacy, adequacy is meaningless without traceability, and traceability is meaningless without existence.
A fourth meta-regulator, the exemption audit, enumerates legitimate exemptions and fails on stale or unowned entries — the first three being traceability, adequacy, and integrity, with existence a baseline property rather than a standalone meta-check.
The meta-regulators for traceability, adequacy, integrity, and the exemption audit are themselves derivations in `checks.<system>` participating in the same parallel evaluation.

The sharpest form is the *no-leak principle*: for every artifact the regulator ships in the same commit, for every incident the coverage-model update is part of the same resolution, and for every check the demonstration that it can fail is part of its construction.
The planning unit is therefore the artifact-plus-regulator pair, never the artifact alone, so estimation must include regulator wiring.
The agent-side habit that operationalizes this is to enumerate `.#checks` and audit coverage rather than count checks:

```bash
nix eval --json ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem')" \
  --apply builtins.attrNames | jaq -r '.[]'
```

The question is never "how many checks does this repo have?" but "does this set cover everything relevant, or are unchecked components leaking?".

For an orchestrator this maps directly.
Each Dagster asset, job, sensor, and schedule is an artifact needing an envelope — asset checks, freshness policies, type and partition contracts, expected-materialization invariants — and a regulator — `@asset_check` definitions, `dagster definitions validate`, op unit tests, integration runs — all composed under the repository's single `nix flake check` closure operator.

## The enforceable rule set

Dagster supplies asset and op graphs, run orchestration, schedules and sensors, asset checks, and a config and resource system, but it enforces none of the rules below by itself.
Each rule names a discipline the orchestrator does not impose and the regulator that discharges it.

| Rule | Discipline | Verification mechanism |
|---|---|---|
| 1. Domain vocabulary at boundaries | asset I/O and op signatures use `NewType`/Pydantic models, never bare `str`/`float`/`dict` | basedpyright strict (static); `@beartype` on boundary functions (runtime) |
| 2. Parse, do not validate | external data (sources, configs, upstream materializations) becomes a validated domain type via a smart constructor returning `Result` at the asset entry; no downstream re-checking | basedpyright (the type witnesses validity); Pydantic/`@beartype` at the edge; property test that the constructor rejects out-of-envelope input |
| 3. Pipeline state as a discriminated union | multi-stage lineage is state types with `Stage_n -> Result[Stage_{n+1}, Error]`, not bool flags or `Optional` fields; illegal transitions do not typecheck | basedpyright exhaustive `match`; example test that the unrepresentable transition has no constructor |
| 4. Failures as typed values | op/asset logic threads `Result[T, E]` composed by `bind`/`map_error` (the async track uses the `effect.async_result` builder, not method chaining); exceptions reserved for panics; errors classified domain vs infrastructure vs panic | basedpyright on the `Result` type; `@beartype`; classification maps to span-event labels |
| 5. Effects explicit and isolated | resources are passed as explicit dependencies (functional DI); the pure transformation core imports no I/O or telemetry; spans wrap only the pipeline entry | basedpyright effect-in-return-type signatures; architectural review of domain-layer imports; integration test swapping a production interpreter for an in-memory one |
| 6. Algebraic laws of combine/fold/merge | aggregations, partitioned and incremental merges, and replay satisfy associativity and identity (monoid) and the fold-reconstruction laws | Hypothesis property test over the monoid/fold laws; mutation test that a broken `evolve` is killed |
| 7. Every definition has an envelope and a regulator (traceability) | no asset/job/sensor/schedule ships without an asset check, freshness policy, or type contract and a flake check exercising it; a discovered-but-unchecked definition is a leak wired in the same commit | CCV traceability meta-regulator plus the enumerate-and-audit habit on `.#checks`; `dagster definitions validate` as a structural regulator |
| 8. Declared bins are saturated (adequacy) | asset checks cover the declared model (nullability, range, freshness, row-count and schema contracts, and observability-interaction: expected materializations emit expected events and spans) | CCV adequacy meta-regulator; asset-check coverage enumeration |
| 9. Each regulator fails on regression (integrity) | asset checks and op tests are non-vacuous; a drifted threshold, weakened assertion, or always-true freshness policy must be killed | CCV integrity meta-regulator via mutation testing; per-check mutation-kill rate as a measured property |
| 10. Exemptions are owned and current | any skipped asset/op/check is enumerated with an owner and an unexpired timestamp | CCV exemption-audit derivation, failing on stale or unowned entries |
| 11. One deterministic command against pinned inputs | all Dagster validation, op/asset tests, property tests, and integration runs are derivations in `checks.<system>` | the closure operator itself; local pass under pinned `flake.lock` equals CI pass |
| 12. Regulator wiring is part of the planning unit | when an asset's behavior changes its check is added or strengthened in the same commit; decomposition estimates the artifact-plus-regulator pair | process rule, audited by the traceability meta-regulator failing the closure operator when a changed artifact's regulator is absent |

Rules 1 through 6 are the local FP discipline; rules 7 through 12 are the CCV apparatus those local rules compose into.
The discipline is wasted unless it reduces to one command, and the command is hollow unless the local rules give it something true to check.

## The toolchain

Four layers close four distinct gaps; each rule above cites the layer that discharges it.

*basedpyright (strict static)* enforces that every public function and class carries annotations and that the program type-checks under strict mode.
It is the compile-time guard that makes "illegal states unrepresentable" checkable: discriminated unions narrow under `match`, `Literal` discriminants and `NewType` brands distinguish semantic domains, and `frozen` immutability holds.
It cannot see runtime boundaries where deserialized or untyped external data arrives.

*beartype (runtime)* enforces the annotated signatures at call time exactly at the boundaries basedpyright cannot reach — data crossing process, serialization, and network edges.
Stack `@beartype` outermost so it checks the unwrapped signature, and initialize OpenTelemetry before beartype's import hooks to avoid instrumentation conflicts.

*Expression (dbrattli/Expression)* supplies explicit-effect, railway-oriented composition: `Result[T, E]` with constructors `Ok` and `Error`, plus `Option[T]`; the async track is the `effect.async_result` builder (a generator/`yield`-form effect over an async function), not a method-chained value.
The surface used here is `from expression import Result, Ok, Error`, the methods `.map`, `.bind`, `.map_error`, `.is_ok()`, `.is_error()`, and `pipe(value, f, ...)`.
Errors are values, so the failure track is type-visible and composable: workflows compose via `bind` (dependent, short-circuiting) and `map_error` (widening to a unified error).
Pattern matching follows the library's own tagged-union form, `case Result(tag="ok", ok=value)` and `case Result(tag="error", error=err)`.

*Pydantic and frozen dataclasses* provide smart constructors and immutability — a private constructor plus a public `create(raw) -> Result[T, Error]` that validates once, so downstream code never re-checks.
Hypothesis provides property-based law testing through `@given`, `strategies as st`, `st.builds`, and `st.from_type`, asserting both sides of a law equal across thousands of generated, shrinking inputs.

## Centerpiece: a lawful IO manager

The IO manager is the one component *01-dagster-categorical-mapping.md* rates *almost* a store algebra and the one you must write yourself, so it is where the categorical reading earns its keep.
This worked example is Lance-flavored but generalizes to any content-addressed store: substitute the Lance dataset write and scan for any pure put and get against an address.

### The law, stated precisely

Two coherence conditions turn the IO-manager-as-store-algebra mapping from *almost* into lawful.

The first is *round-trip identity*: for every typed value `x`, `load_input(handle_output(x)) == x`.
Loading what you stored returns what you stored, with no silent coercion, lossy serialization, or `Any`-shaped drift.

The second is *address determinism*: the storage address is a pure function of `(AssetKey, PartitionKey)` alone, `address: (AssetKey, PartitionKey | None) -> StorageURI`, independent of wall-clock time, run id, or environment.
Determinism plus injectivity (distinct keys map to distinct addresses) is what makes materialization a function of the key, which is the precise condition under which Dagster's caching and `DataVersion` early-cutoff become correct in the Build Systems à la Carte sense.

Together these make the IO manager a lawful algebra interpreting the free asset diagram into store effects.

### The implementation

The contrast that matters is typed versus `Any`-typed transport.

```python
# WRONG: Any in, Any out — the round-trip law is unstatable and unchecked.
class LanceIOManagerUntyped(dg.IOManager):
    def handle_output(self, context: dg.OutputContext, obj) -> None:
        write_lance(self._uri(context.asset_key), obj)  # obj: Any

    def load_input(self, context: dg.InputContext):
        return read_lance(self._uri(context.asset_key))  # -> Any
```

```python
# CORRECT: boundary typed via a domain newtype/model; address a pure function.
from typing import NewType
import dagster as dg
from beartype import beartype
from pydantic import BaseModel

StorageURI = NewType("StorageURI", str)


class FeatureFrame(BaseModel):
    model_config = {"frozen": True}
    rows: tuple[tuple[str, float], ...]


@beartype
def address(key: dg.AssetKey, partition: str | None) -> StorageURI:
    suffix = "" if partition is None else f"/partition={partition}"
    return StorageURI(f"lance://catalog/{'/'.join(key.path)}{suffix}")


class LanceIOManager(dg.ConfigurableIOManager):
    base_uri: str

    @beartype
    def handle_output(self, context: dg.OutputContext, obj: FeatureFrame) -> None:
        partition = context.partition_key if context.has_partition_key else None
        write_lance(address(context.asset_key, partition), obj.model_dump())

    @beartype
    def load_input(self, context: dg.InputContext) -> FeatureFrame:
        partition = context.partition_key if context.has_partition_key else None
        return FeatureFrame.model_validate(read_lance(address(context.asset_key, partition)))
```

`dg.ConfigurableIOManager` is the Pydantic-config IO manager; `dg.IOManager` is the plain base.
The boundary methods annotate `obj: FeatureFrame` and a `FeatureFrame` return rather than `Any`, so basedpyright checks the round trip statically and `@beartype` checks it at the serialization edge that basedpyright cannot see.
`OutputContext`/`InputContext` expose `asset_key: AssetKey`, `has_partition_key: bool`, and `partition_key: str`, so `address` is computed purely from identity.
`@beartype` sits outermost on each method per the decorator-stacking rule.

### The property test

The two laws are Hypothesis properties over generated typed values.

```python
from hypothesis import given, strategies as st
import dagster as dg

frames = st.builds(
    FeatureFrame,
    rows=st.lists(st.tuples(st.text(), st.floats(allow_nan=False)), max_size=8).map(tuple),
)


@given(frames)
def test_round_trip_identity(x: FeatureFrame) -> None:
    """load_input ∘ handle_output == id over typed values."""
    out_ctx = build_output_context(asset_key=dg.AssetKey(["features"]))
    in_ctx = build_input_context(asset_key=dg.AssetKey(["features"]))
    mgr = LanceIOManager(base_uri="lance://catalog")
    mgr.handle_output(out_ctx, x)
    assert mgr.load_input(in_ctx) == x


@given(st.lists(st.text(), min_size=1, max_size=4), st.text() | st.none())
def test_address_determinism_and_injectivity(path: list[str], partition: str | None) -> None:
    key = dg.AssetKey(path)
    assert address(key, partition) == address(key, partition)  # deterministic
    assert address(key, partition) != address(dg.AssetKey([*path, "x"]), partition)  # injective


@given(st.lists(st.text(), min_size=1, max_size=4), st.text(), st.text())
def test_distinct_partitions_distinct_address(path: list[str], p: str, q: str) -> None:
    if p == q:
        return
    key = dg.AssetKey(path)
    assert address(key, p) != address(key, q)
```

`build_output_context` and `build_input_context` are Dagster's test-context builders; substitute an in-memory store for `write_lance`/`read_lance` so the round trip runs hermetically.
The round-trip test is the executable form of the coherence condition; the address tests pin determinism and injectivity, the conditions that make materialization a function of the key.

### The runtime regulator

A `@asset_check` makes the same law a runtime regulator against live materializations rather than generated values.

```python
import dagster as dg


@dg.asset_check(asset=dg.AssetKey(["features"]), blocking=True)
def features_round_trips(context: dg.AssetCheckExecutionContext) -> dg.AssetCheckResult:
    mgr = LanceIOManager(base_uri="lance://catalog")
    in_ctx = build_input_context(asset_key=dg.AssetKey(["features"]))
    loaded = mgr.load_input(in_ctx)
    ok = isinstance(loaded, FeatureFrame)
    return dg.AssetCheckResult(
        passed=ok,
        severity=dg.AssetCheckSeverity.ERROR,
        description="loaded materialization is a valid FeatureFrame (round-trip type holds)",
    )
```

`AssetCheckResult` carries `passed: bool`, `severity: AssetCheckSeverity` (`WARN` or `ERROR`), `metadata`, and `description`; `blocking=True` with `ERROR` severity stops downstream assets when the law fails.
This check is the envelope's regulator for the round-trip law on a live asset, where the Hypothesis test is its regulator over the type's whole input space.

To close the CCV loop, wrap the property tests and `dagster definitions validate` as derivations under `checks.<system>` so `nix flake check` evaluates them against the pinned `flake.lock`.
The asset check becomes the runtime regulator inside a Dagster run, and the nix-wrapped property test becomes the build-time regulator inside the closure operator; both ship in the same commit as `LanceIOManager` per the no-leak principle, and the traceability meta-regulator fails the closure operator if the IO manager changes without its regulator.

## Monoid and fold laws for incremental and partitioned re-materialization

Backfills, out-of-order partition fills, and incremental merges are correct only when the combining operation is a monoid and replay is a fold, because associativity and identity are the algebraic licence for re-grouping work without changing the result.

The fold-reconstruction laws are `fold(evolve, s0, []) == s0`, `fold(evolve, s0, [e]) == evolve(s0, e)`, and `fold(evolve, s0, es1 ++ es2) == fold(evolve, fold(evolve, s0, es1), es2)`.
The third is the fold-over-concatenation law, which holds exactly when the underlying combine is associative, and it is what licenses checkpointing and incremental reconstruction: a partition processed now and a partition processed later compose to the same materialization as processing them together.
When the partition-merge operation is additionally a commutative monoid, out-of-order fills produce the same result as in-order fills, which is the algebraic justification for a backfill that lands partitions in arbitrary order.
This is the same fold/replay law family that *event-sourcing.md* uses for state reconstruction; the partition-merge here is the orchestrator instance of the event-fold there.

A Hypothesis sketch asserts the monoid laws over the merge directly; `merge`, `EMPTY`, and `PartitionMerge` stand for the project's actual partition-merge operation, its identity element, and its carrier type, so this block is a template rather than copy-pasteable code.

```python
from hypothesis import given, strategies as st

partials = st.builds(PartitionMerge, ...)  # st.builds over the merge's carrier type


@given(partials, partials, partials)
def test_merge_associative(a, b, c) -> None:
    assert merge(merge(a, b), c) == merge(a, merge(b, c))


@given(partials)
def test_merge_identity(a) -> None:
    assert merge(EMPTY, a) == a and merge(a, EMPTY) == a


@given(partials, partials)
def test_merge_commutative(a, b) -> None:
    assert merge(a, b) == merge(b, a)  # licenses out-of-order partition fills
```

A passing associativity and identity pair is rule 6's regulator; an integrity mutation that breaks `merge`'s associativity must be killed by this test.
See *algebraic-laws.md* for the full law catalogue and the parametricity argument that some of these laws are guaranteed by the signature and need no test.

## Cross-references

- *domain-modeling.md* — smart constructors as the initial algebra, parse-don't-validate, making illegal states unrepresentable, and the Decider as the pure algebraic core.
- *railway-oriented-programming.md* — `Result`/`Ok`/`Error` composition by `bind`/`map_error`, the failure track, and domain-vs-infrastructure-vs-panic error classification.
- *algebraic-laws.md* — the law catalogue (semigroup, monoid, functor, applicative, monad, fold) and property-based verification with Hypothesis.
- *python-development.md* — the basedpyright/beartype/Expression toolchain, decorator-stacking order, and telemetry-at-boundaries discipline.
- *compositional-continuous-verification.md* — the operating-envelope-plus-regulator pair, the existence/traceability/adequacy/integrity hierarchy, the no-leak principle, and the `.#checks` enumerate-and-audit habit.
- *event-sourcing.md* — the fold/replay reconstruction laws that license incremental and partitioned re-materialization.
- *01-dagster-categorical-mapping.md* — the categorical mapping whose *almost* gaps this file closes.
- *02-asset-vs-task-spectrum.md* — the orchestrator spectrum this discipline applies within.
