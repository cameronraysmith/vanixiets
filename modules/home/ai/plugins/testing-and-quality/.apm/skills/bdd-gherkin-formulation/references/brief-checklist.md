# BRIEF and the formulation checklist

This reference expands the BRIEF framework, the seven-point formulation checklist, the review loop, and the common-mistakes table.
The material is adapted from yaks (MIT, see [`../NOTICE-yaks.md`](../NOTICE-yaks.md)), de-branded and re-anchored on the account-ledger narrative: an account is opened, deposited into, withdrawn from, and closed; it exposes a balance; it rejects an overdraft.

## BRIEF, property by property

BRIEF is a six-property review pass over a single scenario.

Business language asks whether a domain expert would recognize the wording.
A scenario phrased in the vocabulary of the store's internal dictionary or the test framework fails; one phrased as "an open account with balance 100" passes.

Real data asks whether the values are vivid and concrete rather than placeholders.
"balance 100", "a deposit of 50", "a withdrawal of 40" tell a story; "amount-a", "user1", "test account" tell none.

Intention revealing asks whether the step says what happens rather than the click-by-click how.
"When 50 is withdrawn" reveals intent; a sequence of navigate-type-press steps reveals mechanism.

Essential asks whether every line serves the rule under test.
Setup that configures a clock for a scenario about overdraft rejection is incidental and should move to a `Background` or drop out.

Focused asks whether the scenario proves exactly one rule, so it fails only when that rule breaks.
A scenario that both opens an account and asserts an overdraft is testing two rules and should split.

Brief asks whether it fits in about five lines.
A scenario that sprawls past that is one a stakeholder skips, and it is usually smuggling in more than one rule.

## The seven-point checklist

Run these seven questions over each scenario before considering it done.

First, is the Rule a crisp business rule rather than a mechanism?
"Rejecting the withdraw path in the decider" is a mechanism; "A withdrawal that exceeds the balance is rejected as an overdraft" is a rule.

Second, does the Example name add information beyond the Rule?
Do not restate the rule in the scenario heading; name the specific instance, as in "Withdrawing 150 against a balance of 100 overdraws".

Third, is the data real and vivid, carrying one consistent narrative?
Pick the ledger story and run it through the whole feature, reusing the same account, the same balances, and the same deposit and withdrawal amounts across scenarios so the feature reads as a coherent document, introducing a new entity only when a rule demands it.

```gherkin
# Weak: each scenario invents unrelated data
Given a widget priced 9.99
Given a shipment of 3 crates
Given a user named alice

# Strong: one ledger story runs through the feature
Given an open account with balance 100
Given an event history of an opening, a deposit of 100, and a withdrawal of 40
Given a clock fixed at a known instant
```

Fourth, is every line essential?
Remove setup that does not serve the rule, and collapse round-trips where you can, setting state before the action rather than in a separate preparatory cycle.

Fifth, does the scenario prove exactly one rule?
If an example tests two rules, split it; if several examples under one rule all test the same thing, merge them.

Sixth, are cross-cutting concerns inline?
An assertion about a persisted event or a logged effect belongs as an additional `Then` on the scenario that triggers it, not as its own `Rule:` section.

Seventh, does an assertion on exact output use a doc string with precise expected text?
A loose "should include" check is vague; a doc string pins the exact expected output.

## The review loop for an existing feature

Reviewing a feature file is a fixed sequence.
Read each Rule in turn and ask what business rule it states.
Apply BRIEF to each Example beneath it.
Look for duplicate examples across rules, and for rules broad enough that they should split into focused rules.
Confirm the ledger narrative runs consistently throughout.
Check that setup is minimal, with genuinely incidental `Given` steps pushed into a `Background`.
The one question driving the whole pass is: what rule does this scenario prove?
If the answer is unclear, reformulate the scenario or take it back to discovery.

## Common mistakes

These are the craft-level faults and their fixes.
The mistakes that produce a green scenario proving nothing — tautological oracles, private-state inspection, vacuous smoke tests, and reason-hiding assertions — are documented with their exact assertions and citations in [`observable-outcome-discipline.md`](observable-outcome-discipline.md).

| Mistake | Fix |
|---|---|
| Rule describes a mechanism | State the business rule |
| Test-label data ("amount-a", "account-1") | Use vivid, consistent ledger data |
| Each scenario uses unrelated data | Carry the one ledger story through the whole feature |
| Example name restates the Rule | Name the specific instance |
| Several rules under one `Rule:` | Break into focused rules |
| One broad rule with many examples | Check whether each example illustrates a different rule |
| Separate `Rule:` for a logging or persistence assertion | Add it as an extra `Then` on the existing scenario |
| Unnecessary round-trips in setup | Collapse steps; set state before the action |
| Assertion on output without exact expected text | Use a doc string with the precise expected output |
