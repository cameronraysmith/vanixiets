# cucumber-js

cucumber-js (`@cucumber/cucumber`, 13.x) binds features to support code discovered by glob, and a scenario's state is the `this` of each step — a fresh World instance per scenario.
The example below re-anchors the safeadt ledger narrative in TypeScript; the domain surface is illustrative rather than safeadt's own Python code.

## Minimal feature

By default cucumber-js finds features under `features/**/*.{feature,feature.md}`.

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

A custom World subclass carries per-scenario state, registered once with `setWorldConstructor`; each step is a regular `function` so `this` binds to that World.

```typescript
import { Given, When, Then, setWorldConstructor, World } from '@cucumber/cucumber';
import assert from 'node:assert/strict';

import { decide, type Decision } from '../../src/ledger/decider.js';

class LedgerWorld extends World {
  balance = 0;
  decision: Decision | null = null;
}
setWorldConstructor(LedgerWorld);

Given('an open account with balance {int}', function (this: LedgerWorld, balance: number) {
  this.balance = balance;
});

When('{int} is deposited', function (this: LedgerWorld, amount: number) {
  this.decision = decide({ kind: 'Deposit', amount }, { kind: 'Active', balance: this.balance });
});

When('{int} is withdrawn', function (this: LedgerWorld, amount: number) {
  this.decision = decide({ kind: 'Withdraw', amount }, { kind: 'Active', balance: this.balance });
});

Then('the decision emits a deposit of {int}', function (this: LedgerWorld, amount: number) {
  assert.deepEqual(this.decision, { ok: true, events: [{ kind: 'Deposited', amount }] });
});

Then('the command is rejected as an overdraft', function (this: LedgerWorld) {
  assert.deepEqual(this.decision, { ok: false, error: { kind: 'Overdraft' } });
});
```

## Run

```bash
npx cucumber-js
```

## Runner-unique idioms

The World is the `this` of each step, a fresh instance of the class registered through `setWorldConstructor` and discarded when the scenario concludes even on a retry; use a regular `function` rather than an arrow so `this` binds, or import the `world` handle to reach it from an arrow function.

Match with Cucumber Expressions (`{int}`, `{string}`, `{word}`) or a `RegExp`, and a step body may be synchronous, take a trailing `callback`, or return a `Promise`, with the step ending when the promise settles.

Discovery is glob-driven: features default to `features/**/*.{feature,feature.md}` and support code to `features/**/*.@(js|cjs|mjs)`; override with `paths` and `import` in `cucumber.js` or `cucumber.json`, or a typed config typed against `IConfiguration`, and once any `import` is set the defaults no longer apply.

Hooks come in three scopes: scenario (`Before`/`After`, world bound to `this`, multiple allowed and running in definition then reverse order), suite (`BeforeAll`/`AfterAll`, no world instance), and step (`BeforeStep`/`AfterStep`); any hook may be tag-scoped, for example `Before({ tags: '@req-decide-invariants' }, ...)`.

TypeScript types `this` per step as `function (this: LedgerWorld, amount: number)`, and configuration values reach steps through `this.parameters`, populated by the `worldParameters` option.

Filter scenarios by tag with `--tags '@req-decide-invariants'` when running `npx cucumber-js`.

## Observable outcome here

Each Then binds the `decision` the World holds and deep-equals it against an object literal, an independent oracle rather than a value the production path recomputes.
Assert through the public decider result, never a private World field set as a side effect; the full corpus and its labeled anti-patterns live canonically in `bdd-gherkin-formulation/references/observable-outcome-discipline.md`.
