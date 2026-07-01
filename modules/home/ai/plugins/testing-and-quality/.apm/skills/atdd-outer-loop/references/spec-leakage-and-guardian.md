# The independent spec-leakage audit

A scenario earns its place as a specification only if it describes what the system does as an external observable, in the domain's own language.
The moment a step names a class, a table, an endpoint, or a data structure, the scenario stops documenting behavior and starts mirroring structure, at which point it breaks whenever the structure is refactored even though the behavior is unchanged, and it can no longer be read by a stakeholder who does not know the code.
The leakage audit is the gate that keeps scenarios on the observable side of that line.

## Why the audit is independent

The audit runs as a fresh agent whose identity differs from the scenario's author.
An author re-reading their own specs carries the implementation they were thinking about while writing, so leakage that reads as obvious to a fresh reader reads as natural domain language to the author.
This is the same verification-independence principle the loop applies to code review (see `references/handoff-as-gate.md`): the reviewer is not the writer.
Dispatch of the fresh auditing agent defers to `subagent-driven-development`.

## The four-bucket taxonomy

The audit flags any `Given`, `When`, or `Then` step that names the machine, sorted into four buckets so the finding is specific.

Code references name the program's own parts: class, function, method, and variable names, module names, and file paths.
Infrastructure references name the storage and transport layer: database tables and columns, SQL and queries, API endpoints, HTTP verbs and status codes, queue names, and cache keys.
Framework references name a library's vocabulary: controller, service, repository, middleware, reducer, resolver, hook, provider, store, and the ORM terms model, migration, and relation.
Technical-implementation references name the how beneath the behavior: data structures, algorithms, wire protocols, and internal events or signals.

## Re-anchored examples on the ledger

The following pairs show leakage and its domain-language repair on the ledger narrative — open, deposit, withdraw, close, balance, overdraft.

```gherkin
# code + infrastructure leakage
Given the LedgerService has an empty EventStore
When handle() is called with a Deposit command
Then store.streams[account] contains a Deposited row

# domain language
Given a new account with no history
When 50 is deposited
Then the balance is 50
```

```gherkin
# technical leakage — the internal error predicate, not the observable rejection
When a withdrawal of 200 is attempted
Then decision.is_error() is True

# domain language — the rejection and its reason are the observable outcome
When 200 is withdrawn from an account holding 50
Then the withdrawal is rejected for overdraft
```

The second pair also illustrates a subtler failure the audit catches: a step that asserts a generic internal error flag hides which domain rule fired, so an overdraft rejection and a closed-account rejection become indistinguishable at the specification level.
Naming the reason — overdraft, non-positive amount, operation on a closed account — restores the observable content the flag threw away.

## The audit is read-only and educative

The audit proposes rewrites and reports findings; it does not edit the specs, because the specs are the human's contract and only the human approves a change to them.
When a step's status is genuinely ambiguous, the audit flags it with its reasoning and lets the human decide rather than silently rewriting.
Judgment applies at one edge: a term that genuinely is the domain is not leakage.
In a database administration tool "table" and "query" are the ubiquitous language; in a ledger "balance" and "overdraft" are the domain, not internal state.
The test is whether a stakeholder in that domain would use the word to describe the behavior, not whether the word also appears in the code.

## Relationship to the loop

This audit is P3 of the outer loop (`references/outer-loop-workflow.md`) and its gate is a clean return or a rewrite-and-re-audit.
It is upstream of and distinct from the observable-outcome gate: leakage is about the vocabulary a step uses, while the observable-outcome gate is about whether a `Then` asserts an outcome or a recomputed mechanism.
A step can be free of named-machine leakage and still fail the observable-outcome gate by asserting a tautology; both gates must hold.
The observable-outcome corpus is owned by `bdd-gherkin-formulation` at `references/observable-outcome-discipline.md`.
