# pytest-bdd

pytest-bdd is a pytest plugin rather than a standalone runner, so step definitions are ordinary pytest test modules and everything composes with the rest of the suite.
This reference is grounded in the safeadt behavioral-acceptance layer (`src/safeadt/tests/`), the positive model for the group; the snippets are trimmed from that suite, not invented.

## Minimal feature

The feature is the formulated Gherkin, tagged with one `@<spec>` capability tag and a `@req-<slug>` requirement tag per scenario.

```gherkin
@ledger-decider
Feature: Ledger decider lifecycle and invariant rejections

  @req-decide-invariants
  Scenario: Depositing into an open account emits a deposit event
    Given an open account with balance 100
    When 50 is deposited
    Then the decision succeeds emitting a deposit of 50

  @req-decide-invariants
  Scenario: Withdrawing more than the balance is rejected as an overdraft
    Given an open account with balance 100
    When 150 is withdrawn
    Then the command is rejected as an overdraft
    And no events are emitted
```

## Minimal step definitions

The module binds the feature with `scenarios(...)` and defines the steps beneath it.
State never lives in a global: a step publishes its result by returning it under `target_fixture=`, and a downstream step requests that fixture by parameter name.

```python
from importlib.resources import files

from expression import Error, Ok, Result
from pytest_bdd import given, parsers, scenarios, then, when

from safeadt.ledger.decider import LedgerError, Overdraft, decide
from safeadt.ledger.model import Active, Deposit, Deposited, Event, State, Withdraw

scenarios(str(files("safeadt.tests.features") / "ledger" / "decider.feature"))


@given(parsers.parse("an open account with balance {balance:d}"), target_fixture="account_state")
def open_account_with_balance(balance: int) -> State:
    return Active(balance)


@when(parsers.parse("{amount:d} is deposited"), target_fixture="decision")
def deposit_amount(amount: int, account_state: State) -> Result[list[Event], LedgerError]:
    return decide(Deposit(amount), account_state)


@when(parsers.parse("{amount:d} is withdrawn"), target_fixture="decision")
def withdraw_amount(amount: int, account_state: State) -> Result[list[Event], LedgerError]:
    return decide(Withdraw(amount), account_state)


@then(parsers.parse("the decision succeeds emitting a deposit of {amount:d}"))
def emits_deposited(amount: int, decision: Result[list[Event], LedgerError]) -> None:
    assert decision == Ok([Deposited(amount)])


@then("the command is rejected as an overdraft")
def rejected_overdraft(decision: Result[list[Event], LedgerError]) -> None:
    assert decision == Error(Overdraft())


@then("no events are emitted")
def no_events_emitted(decision: Result[list[Event], LedgerError]) -> None:
    assert decision.is_error()
```

## Run

pytest-bdd needs no separate runner; collect the module like any other test.

```bash
pytest src/safeadt/tests/test_ledger_decider_steps.py
```

## Runner-unique idioms

There is no World object; state flows through pytest fixtures, and `target_fixture="decision"` publishes a step's return under the `decision` fixture so the Then can request it by name, one fresh function-scoped graph per scenario.

`scenarios(...)` binds a feature file to the module's steps; resolve the path through `importlib.resources.files("safeadt.tests.features")` so it works identically from an editable checkout and from an installed wheel, and so a co-located traceability guard resolves the same files the steps do.

`parsers.parse("{amount:d}")` gives typed capture, where `:d` yields an `int` argument; `parsers.re(...)` and `parsers.cfparse(...)` are the escape hatches, and a bare string such as `"no events are emitted"` is an exact match.

Gherkin tags become pytest marks, so register them or a strict warning filter fails the run: safeadt registers each tag in the packaged `conftest.py` via `pytest_configure` calling `config.addinivalue_line("markers", ...)`, which keeps `filterwarnings = ["error"]` from turning an unregistered mark into a `PytestUnknownMarkWarning` failure, and lets `pytest -m req-decide-invariants` select by requirement.

`pytest --generate-missing <feature>` scaffolds step stubs for any unbound step — the unbound-step half of the traceability guard — while the coverage half is a plain test module (`test_traceability.py`) that resolves the shipped features through `importlib.resources` and asserts every scenario carries one `@<spec>` tag plus a known `@req-<slug>` tag and every in-scope requirement is witnessed.

## Observable outcome here

Each Then binds the returned `Result` — the public decider surface — and asserts it against a hand-written literal (`Ok([Deposited(50)])`, `Error(Overdraft())`), an independent oracle that never recomputes `decide(...)`.
The full corpus of positive oracles and the labeled anti-patterns (the grade tautology, the clock private-state pierce, the shim smoke test, the weak `is_error()` that hides the domain reason) lives canonically in `bdd-gherkin-formulation/references/observable-outcome-discipline.md`.
