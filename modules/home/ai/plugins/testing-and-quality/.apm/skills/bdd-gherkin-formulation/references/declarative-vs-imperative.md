# Declarative over imperative

This reference paraphrases the cucumber documentation on writing behavior rather than implementation, on atomic steps, and on the step-definition anti-patterns.
Sources: cucumber's better-gherkin, who-does-what, and anti-patterns pages.
All examples are re-anchored on the account-ledger narrative; no cucumber text is reproduced verbatim.

## Describe behavior, not implementation

A scenario should describe the intended behavior of the system — the what — and leave the how to the bindings beneath it.
The cucumber litmus is a single question to ask of every step: will this wording need to change if the implementation changes?
If the answer is yes, the step has leaked a mechanism, and the behavior it documents did not actually change just because the plumbing did.
Reworking the step to speak in terms of the observable behavior also makes it shorter and easier to follow, so the litmus pays for itself twice.

An imperative rendering of a ledger withdrawal spells out every mechanical move and breaks the moment any of them shift.

```gherkin
# Imperative: brittle, tied to today's mechanics
Given I construct an Active state with balance 100
When I call decide with a Withdraw command carrying 40
And I fold the resulting events with the reconstruct function
Then the returned state object's balance field reads 60
```

A declarative rendering states the intent and survives a change of transport, storage, or internal representation.

```gherkin
# Declarative: states what the ledger does
Given an open account with balance 100
When 40 is withdrawn through the service
Then the balance read through the store is 60
```

The declarative version communicates an idea per step while the exact values and the means of interaction live in the bindings.
The account could move from an in-memory store to a database, or the balance could be read through a different surface, without touching this scenario or the other scenarios that share its steps.

## One thing per Given

Each `Given` should put the system into one well-defined part of its starting state.
When a step contains "and" in the middle, it is usually two preconditions wearing one step, and it should split so each half is independently reusable.

```gherkin
# Conjunction hidden in one step
Given an open account with balance 100 and a clock fixed at a known instant

# Split into atomic steps
Given an open account with balance 100
And a clock fixed at a known instant
```

Cucumber has `And` and `But` for exactly this: successive `Given` or `Then` lines read more fluidly when the second and later ones use `And`.
Consistency matters as much as atomicity — say the same precondition the same way every time, so "an open account with balance 100" is never also written as "an account that has been opened and holds 100", because the two forms fragment the step vocabulary for no gain.

## Conjunction-step anti-pattern

A conjunction step combines several distinct things into one step, which makes it over-specialized and hard to reuse.
The fix is to split the conjunction into separate steps joined by `And`.
When you genuinely want to combine several actions for readability, do it in the binding by extracting a helper the step definition calls, not by fusing the concerns in the Gherkin; the goal is to keep steps atomic while composition happens in code.

## Feature-coupled step definitions

A feature-coupled step definition is one that cannot be reused across features or scenarios because its wording and its binding are named after the feature file they happen to live in rather than the domain concept they express.
This drives an explosion of near-duplicate steps, code duplication, and maintenance cost.
The fix is to organize steps by domain concept and to name step wording and binding files after that concept.
In the ledger example, a step phrased as "an open account with balance 100" is a reusable domain-level precondition that any decider or service scenario can share, whereas a step phrased after a particular feature file — "the account for the withdraw-overdraft feature" — locks itself to one file and cannot travel.

## Observable outcomes

The `Then` step is where behavior-versus-implementation matters most, because a `Then` that reaches into the implementation is both brittle and undocumentary.
An outcome should be observable — something that comes out of the system, such as a returned decision, a reconstructed balance, or a balance read through the store — and not a value buried inside the system, such as a record indexed out of a store's private dictionary.
The full discipline for what a `Then` may assert and against what oracle, with the worked safeadt corpus, is in [`observable-outcome-discipline.md`](observable-outcome-discipline.md).
