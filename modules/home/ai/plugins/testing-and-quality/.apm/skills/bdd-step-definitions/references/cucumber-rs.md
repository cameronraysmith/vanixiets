# cucumber-rs

cucumber-rs (crate `cucumber`, 0.23.x, Rust 1.88+) is a fully native runner with no external test process: a scenario's state is a `#[derive(cucumber::World)]` struct, steps are attribute-tagged functions, and the runner is your own async binary.
The example below re-anchors the safeadt ledger narrative in Rust; the domain surface is illustrative rather than safeadt's own Python code.

## Minimal feature

```gherkin
Feature: Ledger decider lifecycle and invariant rejections

  Scenario: Depositing into an open account emits a deposit event
    Given an open account with balance 100
    When 50 is deposited
    Then the decision emits a deposit of 50

  Scenario: Withdrawing more than the balance is rejected as an overdraft
    Given an open account with balance 100
    When 150 is withdrawn
    Then the command is rejected as an overdraft
```

## Minimal step definitions

The World carries the balance set by the Given and the decision produced by the When, and each Then asserts that decision against a hand-written literal.

```rust
use cucumber::{World, given, then, when};

use crate::ledger::{Command, Event, LedgerError, State, decide};

#[derive(Debug, Default, cucumber::World)]
struct LedgerWorld {
    balance: i64,
    decision: Option<Result<Vec<Event>, LedgerError>>,
}

#[given(expr = "an open account with balance {int}")]
fn open_account(w: &mut LedgerWorld, balance: i64) {
    w.balance = balance;
}

#[when(expr = "{int} is deposited")]
fn deposit(w: &mut LedgerWorld, amount: i64) {
    w.decision = Some(decide(Command::Deposit(amount), State::Active(w.balance)));
}

#[when(expr = "{int} is withdrawn")]
fn withdraw(w: &mut LedgerWorld, amount: i64) {
    w.decision = Some(decide(Command::Withdraw(amount), State::Active(w.balance)));
}

#[then(expr = "the decision emits a deposit of {int}")]
fn emits_deposit(w: &mut LedgerWorld, amount: i64) {
    assert_eq!(w.decision.as_ref().unwrap(), &Ok(vec![Event::Deposited(amount)]));
}

#[then("the command is rejected as an overdraft")]
fn rejected_overdraft(w: &mut LedgerWorld) {
    assert_eq!(w.decision.as_ref().unwrap(), &Err(LedgerError::Overdraft));
}

#[tokio::main]
async fn main() {
    LedgerWorld::run("tests/features/ledger").await;
}
```

The runner is a normal integration test declared without the default harness so Cucumber prints its own output.

```toml
[[test]]
name = "ledger"
harness = false  # let Cucumber print instead of libtest
```

## Run

```bash
cargo test --test ledger
```

## Runner-unique idioms

The World is a `#[derive(cucumber::World)]` struct, default-constructed fresh for each scenario and threaded into every step as `&mut World`; carry the observed decision on it and assert against a literal in the Then rather than recomputing `decide`.

Match with `#[given(expr = "...")]` Cucumber Expressions (`{int}`, `{word}`, `{string}`) and drop to `#[when(regex = r"^...$")]` for precision, anchoring the regex with `^..$` so growing step sets do not interfere; capture typed values through any `FromStr` argument or a reusable `#[derive(Parameter)]` type instead of parsing strings by hand.

The runner is your own binary: an async `main` (here `#[tokio::main]`) calling `World::run(<features-dir>)`, registered as a `[[test]]` with `harness = false`, and step functions may themselves be `async` and `.await`.

`World::cucumber().before(...).after(...).run_and_exit(...)` is the builder for scenario hooks and tag or name filters, but only one `before` and one `after` may be registered, and the book warns to prefer a Gherkin `Background` over a `Before` so setup stays visible in the `.feature` and low-level hooks are reserved for things like starting a browser.

Tags filter through the builder or the CLI `--tags`, and the `output-json`, `output-junit`, and `libtest` cargo features emit machine-readable reports for CI wiring.

## Observable outcome here

Each Then binds the `Result` the World holds and compares it to a literal (`Ok(vec![Event::Deposited(50)])`, `Err(LedgerError::Overdraft)`), an independent oracle.
Assert through the public decider surface, never through a private World field mutated as a side effect; the full corpus and its labeled anti-patterns live canonically in `bdd-gherkin-formulation/references/observable-outcome-discipline.md`.
