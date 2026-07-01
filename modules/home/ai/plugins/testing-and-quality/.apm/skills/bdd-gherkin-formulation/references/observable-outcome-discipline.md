# The observable-outcome discipline

This is the canonical statement of the discipline for the whole two-layer BDD group, and the canonical home of the safeadt teaching corpus.
Other skills state the one-line litmus and point here; only this file carries the full corpus.
The exemplars are drawn from the user's own safeadt project and cited to its source test tree at `src/safeadt/tests/` (not the `.venv` mirror).

## The two rules

A `Then` earns its place only when it checks an observable outcome against an expectation the production code did not compute.
That resolves into two rules.

The first rule is to assert against an independent literal oracle and never re-derive the expected value through the production path.
The expected result is a value the author writes down — `Ok([Deposited(50)])`, `Error(Overdraft())`, `Active(60)`, the number `60` — not a value obtained by calling the function under test a second time or reconstructing it with the same computation the production path performs.

The second rule is to assert through the public, observable surface and never inspect private state behind a protocol.
The outcome read by the `Then` must be something the system exposes — a returned decision, a reconstructed balance, a balance read through the store's public projection — not a field indexed out of a store's internal dictionary or a timestamp read off a private envelope.

## The two litmus tests

The independent-oracle test: would this `Then` still fail if the production path were subtly wrong?
If the expected value was produced by the very code under test, the answer is no, and the assertion only confirms that the code equals itself.

The public-surface test: does this `Then` read only what the system exposes through its public surface?
If it reaches behind a protocol into private state, it couples the living document to an implementation detail and stops documenting behavior.

## Positive exemplars

The decider asserts an emission against an independent literal.

```python
assert decision == Ok([Deposited(amount)])   # test_ledger_decider_steps.py:84
```

The scenario deposits 50 into an open account with balance 100, and the `Then` compares the decision against the literal `Ok([Deposited(50)])`.
The expected event list is written by the author, not recomputed by calling `decide` again, so the assertion fails if the decider emits the wrong event or wraps it in `Error`.

The decider asserts a rejection against an independent domain-reason literal.

```python
assert decision == Error(Overdraft())          # test_ledger_decider_steps.py:99
assert decision == Error(NonPositiveAmount())   # test_ledger_decider_steps.py:103
```

The expected error is a specific domain reason, so the assertion fails if the decider rejects for the wrong invariant or accepts; it names which invariant fired rather than merely that something failed.

The reconstruction asserts a balance against an independent literal.

```python
assert reconstructed == Active(balance)   # test_ledger_decider_steps.py:136-137
```

Given an event history of an opening, a deposit of 100, and a withdrawal of 40, the `Then` asserts the reconstructed state equals the literal `Active(60)`.
The author computed 60 by hand from the narrative; the fold is not re-run to produce the expected value.

The service asserts a balance read through the public surface.

```python
assert balance_of(store, _STREAM) == 60   # test_ledger_service_steps.py:73
```

The balance is obtained through the public projection `balance_of` over the store — the same read-through surface the feature documents — and compared against the literal `60`, satisfying both rules at once: an independent oracle and the public surface.

Geometry is a positive exemplar with a caveat.

```python
assert math.isclose(area_value, math.pi * radius**2)   # test_geometry_steps.py:64
```

The oracle recomputes the same closed form, pi times the radius squared, that the production `area` path uses, so the two agree by construction on the formula; this is only weakly independent.
It still catches a wrong radius, a wrong operation, or a boundary-type error, but it does not pin the numeric value the way a hand-written literal would.
Prefer a literal expected area where one is available, and use the recomputed closed form only when no independent literal is practical, knowing it is the weaker oracle.

## Negative exemplars

Each of these produces a green scenario that proves nothing, and each is a labeled anti-pattern with a route to where the check actually belongs.

The tautological grade oracle asserts a value against the constructor that produced it.

```python
# effect = grade_of(handle).effect
assert effect == EffectGrade.of(EffectAtom.Read, EffectAtom.Append)   # test_grades_steps.py:39-40
```

`EffectGrade.of(Read, Append)` is the identical constructor the `@graded` decorator stored on `handle`, so the `Then` compares the value against the very thing that was put there; on an unenforced grade this is `x == x`.
Route: this is a claim about an algebra, not an observable behavior — move it to a property or law test (preferences-algebraic-laws), or make the grade enforced so that violating it becomes observable.

The private-state inspection reaches behind the `EventStore` protocol.

```python
envelopes = store.streams[_STREAM]                                    # test_ledger_service_steps.py:88
assert [envelope.occurred_at for envelope in envelopes] == [_INSTANT]  # test_ledger_service_steps.py:89
```

It indexes the store's private `streams` dictionary and reads each envelope's `occurred_at` field, coupling the scenario to an implementation detail a domain expert never sees.
Route: assert through the public surface — read the stamped instant through whatever the store exposes publicly — so the scenario documents behavior rather than storage layout.

The import smoke test wears Gherkin clothing.

```python
try:
    import icontract_hypothesis   # test_shim_steps.py:24
except AttributeError:            # test_shim_steps.py:25
    return None
```

The `When` swallows the very `AttributeError` the shim exists to prevent and returns `None`, while the `Given` ("the shim has run") establishes no meaningful domain state, so the scenario is an import smoke test dressed as behavior with a vacuous precondition.
Route: keep the import check as a plain regression or smoke test; it is a real check, but it is not an example of a business rule and does not belong in a `.feature`.

The reason-hiding weak assertion confirms only that something failed.

```python
assert decision.is_error()   # test_ledger_decider_steps.py:119
assert result.is_error()     # test_ledger_service_steps.py:78
```

`is_error()` does not say which domain reason fired, so a decider that rejected for the wrong invariant would still pass; and the overdraft rule is never exercised end to end at the service surface — only the decider sees it.
Route: name the instance and assert the domain reason, and add a scenario that drives an overdrawing withdrawal through the service so the rejection is observed at the public surface.

## The Scenario Outline trap at scale

The independent-oracle rule extends to `Scenario Outline` `Examples` columns.
An expected column whose values are computed by the production path is the tautology trap at scale, because every row then asserts that the code equals itself; fill the expected column with independently chosen literals so each row is a genuine check.

## Corrective techniques

Three moves recur when repairing a weak `Then`.
Name the instance: replace a bare `is_error()` or a generic success check with a comparison against the specific domain literal, such as `Error(Overdraft())`, so the assertion says which outcome occurred.
Prefer an observable `Then` over an internal predicate: read the outcome through the system's public surface rather than a private field, so the scenario stays a document of behavior.
Exercise the rule at the surface it is claimed for: if a rule like overdraft rejection is only ever seen inside the decider, add a scenario that drives it through the service, so the acceptance criterion is proven where a user would encounter it.
