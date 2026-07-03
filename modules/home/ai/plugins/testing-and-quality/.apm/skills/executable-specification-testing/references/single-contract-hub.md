# The single contract, three engines

This file records the exact integration symbols by which one icontract declaration is consumed three ways.
The shape is a hub, not a pipeline: the three engines each read the same runtime contract metadata independently, and nothing flows from one engine into another.
The unifying substrate is the set of dunders icontract attaches to a function's checker wrapper, and every symbol below is a reader of those dunders.

## The shared substrate: icontract's runtime metadata

The `@require`/`@ensure`/`@snapshot` decorators attach three lists to the checker wrapper and `@invariant` sets a fourth on the class: `__preconditions__` (a disjunctive-normal-form list of conjunctions of `icontract._types.Contract`), `__postcondition_snapshots__`, `__postconditions__`, and, on the class, `__invariants__`.
`find_checker` locates the wrapper by probing for `__preconditions__`/`__postconditions__`.
These four attributes are exactly what both the strategy-inference bridge and the symbolic parser introspect.

- `icontract/icontract/_checkers.py:45-52` — `find_checker` probes `__preconditions__`/`__postconditions__`.
- `icontract/icontract/_checkers.py:869-871` — the `setattr` of the three lists; `1219-1228` — `cls.__invariants__`.
- `icontract/icontract/__init__.py:27-52` — `require`, `snapshot`, `ensure`, `invariant` re-exported from `icontract._decorators`; `Contract`/`Snapshot` from `icontract._types` (line numbers read from an unnumbered `cat`, so treat file+symbol as authoritative and the exact lines as approximate).

## Engine 1: runtime enforcement

icontract itself checks each predicate on every concrete call and raises `ViolationError` on failure.
This is the design-by-contract rung: the predicate is an executable runtime assertion carrying a specification's intent.
No further wiring is needed beyond the decorators.

## Engine 2: strategy inference (icontract-hypothesis)

This bridge reads `__preconditions__` only and builds a concrete Hypothesis `SearchStrategy`; it does *not* invoke CrossHair at all.
Postconditions, snapshots, and class invariants do not shape the inferred strategy — only preconditions do.

- Entry point: `infer_strategy(func, localns, globalns)` calls `icontract._checkers.find_checker(func)`, reads `checker.__preconditions__` as a DNF list-of-conjunctions, and returns a strategy; with several conjunctions it returns `hypothesis.strategies.one_of(...)` (DNF to disjoint strategies), falling back to `_create_strategy_only_from_type_hints` when there is no checker. `icontract-hypothesis/icontract_hypothesis/__init__.py:1230-1403` (checker at 1365, `__preconditions__` at 1372, per-conjunction inference 1391-1398, `one_of` at 1403).
- Drive surface: `test_with_inferred_strategy(func, ...)` calls `infer_strategy`, wraps the target as `wrapped = hypothesis.given(strategy)(execute)`, and invokes `wrapped()` — this is how a decorated function becomes a property test with no hand-written `@given`. `icontract-hypothesis/icontract_hypothesis/__init__.py:1406-1451` (`given` wrap at 1450).
- Bounds-to-strategy bridge: `_infer_min_max_from_preconditions` folds each precondition's `ast.Compare` into tightest inclusive/exclusive min/max; `_make_strategy_with_min_max_for_type` maps `int` to `integers(min,max)` (adjusting for exclusive bounds since `integers()` is inclusive) and `float` to `floats(..., exclude_min/exclude_max)`, keeping `Fraction`/`Decimal` bounds as runtime filters. `icontract-hypothesis/icontract_hypothesis/__init__.py:361-437` and `440-480+`.
- Uninterpretable clauses: `_rewrite_condition_as_filter_on_kwargs` recompiles a non-comparison precondition into a Hypothesis `.filter(...)` over the generated kwargs, raising `NotImplementedError` for the `_ARGS` special argument. This is the "bound could not be inferred, so it became a filter" sharp edge that can slow generation or trip a `FailedHealthCheck`. `icontract-hypothesis/icontract_hypothesis/__init__.py:809-878` (`_ARGS` guard 817-822).

In safeadt this bridge is exercised by `icontract_hypothesis.test_with_inferred_strategy(scaled_rectangle_area)` at `src/safeadt/tests/test_geometry.py:47`.

## Engine 3: symbolic/concolic checking (CrossHair)

CrossHair reads the same dunders through its own parser and evaluates the lambdas on Z3-backed symbolic inputs.
There are two distinct ways to reach it, and they are different integration surfaces.

The Hypothesis-backend surface leaves the `@given` test source unchanged and swaps the primitive provider.
hypothesis-crosshair's setup hook registers a string path (not the class, so `import hypothesis` stays cheap) into Hypothesis's provider registry, and `@settings(backend="crosshair")` resolves it lazily.

- `hypothesis-crosshair/hypothesis_crosshair_provider/__init__.py:4-21` — `_hypothesis_setup_hook` sets `AVAILABLE_PROVIDERS["crosshair"] = "hypothesis_crosshair_provider.crosshair_provider.CrossHairPrimitiveProvider"`, with a version fallback import (relocated in HypothesisWorks/hypothesis PR #4254) at 9-16.
- `hypothesis-crosshair/pyproject.toml` — the `[project.entry-points.hypothesis]` block (`_ = "hypothesis_crosshair_provider:_hypothesis_setup_hook"`) is what runs the hook on `import hypothesis`.
- `hypothesis/hypothesis/src/hypothesis/entry_points.py:22-31` — the loader that enumerates `group="hypothesis"` entry points, short-circuiting on `HYPOTHESIS_NO_PLUGINS`.
- `hypothesis/hypothesis/src/hypothesis/internal/conjecture/providers.py:130-133` — the `AVAILABLE_PROVIDERS` registry; the `PrimitiveProvider` ABC at 401.
- `hypothesis/hypothesis/src/hypothesis/internal/conjecture/engine.py:189-198` — `_get_provider(backend)` looks up `AVAILABLE_PROVIDERS[backend]`, imports the dotted path, and instantiates it; this is the exact point `backend="crosshair"` becomes a live provider.
- `hypothesis-crosshair/hypothesis_crosshair_provider/crosshair_provider.py:74-77` — `class CrossHairPrimitiveProvider(PrimitiveProvider)` with `avoid_realization = True`; `166-201` — `per_test_case_context_manager` drives a fresh CrossHair `StateSpace` per example and signals back by raising `BackendCannotProceed("verified"/"exhausted"/"discard_test_case")`.

The standalone-CLI surface parses the same contracts directly.
CrossHair's `IcontractParser` is the symmetric introspector to icontract-hypothesis: `get_fn_conditions` calls `find_checker`, unwraps `__wrapped__`, and reads `__preconditions__` as a DNF disjunction, `__postcondition_snapshots__` to build the `OLD` mapping, `__postconditions__` for post checks, and `cls.__invariants__` for class invariants.

- `CrossHair/crosshair/condition_parser.py:732-881` — `IcontractParser` (`find_checker` 748, unwrap loop 750-755, `__preconditions__` DNF 770-811, snapshots to `Old` 813-822, postconditions 835-846, `__invariants__` 864).
- `CrossHair/crosshair/condition_parser.py:1208-1232` — `_PARSER_MAP` and the `condition_parser(analysis_kinds)` factory that builds a `CompositeConditionParser`; `558-590` — the first-parser-wins loop. `crosshair/options.py:223-226` — the default `analysis_kind` is `(PEP316, icontract, deal)`.

safeadt reaches CrossHair both ways: `@settings(backend="crosshair", deadline=None, max_examples=20)` at `src/safeadt/tests/test_geometry.py:24`, and the `crosshair check src/safeadt/geometry.py --analysis_kind=icontract` recipe in its `justfile`.

## deal as a peer contract dialect

deal is a second Python design-by-contract dialect that CrossHair supports through a peer parser, so the "multiple spec dialects, one engine" property holds beyond icontract.
`deal.pre`/`deal.post`/`deal.ensure`/`deal.inv`/`deal.raises`/`deal.has` are the decorator surface; CrossHair's `DealParser` enumerates `deal.introspection.get_contracts(fn)` and dispatches on `Pre`/`Post`/`Ensure`/`Raises`/`Has`/`ValidatedContract`.

- `CrossHair/crosshair/condition_parser.py:896-1000` — `DealParser` (contract validation 897-907, `get_contracts` 952, dispatch 975-983).
- `deal/deal/__init__.py:18-20` and `deal/introspection/__init__.py:25-27` — the decorator and introspection surfaces.

Two deal sharp edges worth knowing before choosing it over icontract for a CrossHair run: `DealParser.get_class_invariants` returns `[]` unconditionally, so `@deal.inv(...)` is silently dropped under CrossHair symbolic analysis even though icontract's `@invariant` is honored (`condition_parser.py:1002-1003` vs `863-881`); and a deal `Has` side-effect marker in `{"write","network","stdin","syscall"}` aborts analysis of that function (`condition_parser.py:884-893` and `964-970`).
safeadt deliberately keeps icontract as the source of truth and treats deal as the documented peer rather than the primary.
