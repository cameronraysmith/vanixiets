# The outer loop, phase by phase

The outer loop is eight phases, each of which defers its craft to an owner skill and then closes on a gate that the next phase's entry re-checks.
The gates are the load-bearing part: a phase is done only when its exit criterion holds against evidence, and no phase trusts a prior phase's claim of completion in place of the gate.
The automation legs bind native `.feature` runners directly, so there is no intermediate representation to regenerate and no gitignored generated-test tree — the `.feature` files and their step definitions are committed source.

## P1 — discover acceptance criteria

Acceptance criteria are decisions about which behaviors must work, stated in domain language, and they precede any Gherkin.
Separating this divergent discovery from the convergent encoding in P2 is what keeps implementation language out of the specification, because the moment of deciding what must be true is kept distinct from the moment of fixing how it is worded.
Facilitation defers to `preferences-collaborative-modeling`; the passes worth covering are the happy path, the edge and boundary and concurrency cases, the error and security cases, and the cross-cutting concerns of audit, idempotency, and data lifecycle.

Gate: every acceptance criterion maps to at least one scenario slated for P2, and no criterion is left without a witness.

## P2 — formalize as scenarios

Each criterion becomes a scenario in the ubiquitous language.
Authoring — the declarative-versus-imperative choice, one-thing-per-`Given`, the avoidance of conjunction steps, the shape of a Scenario Outline — defers to `bdd-gherkin-formulation`.
The scenarios speak the domain's terms (for the ledger: open, deposit, withdraw, close, balance, overdraft) and never the machine's.

Gate: the observable-outcome gate holds for every `Then` (see the SKILL body and `bdd-gherkin-formulation` at `references/observable-outcome-discipline.md`), and each scenario is a single behavior rather than several chained by `And ... When ... And ... When`.

## P3 — independent spec-leakage audit

A fresh agent whose identity differs from the author reviews the scenarios for anything that names the machine, along the four-bucket taxonomy in `references/spec-leakage-and-guardian.md`.
The audit is read-only and proposes rewrites; the human decides.

Gate: the audit returns clean, or the flagged steps are rewritten to domain language and re-audited.

## P4 — bind and run the RED gate

Step definitions bind each scenario's step text to the running system through the language's native runner, deferring to `bdd-step-definitions`.
For pytest-bdd this means step modules that resolve their `.feature` files as importable package resources and call into the system under test; for the JVM, Ruby, Rust, and JavaScript runners it means the equivalent native glue.
The suite is then run and must fail.

Gate: the acceptance suite runs and fails for the right reason — the behavior does not exist yet.
A scenario that passes before implementation is either redundant with existing behavior or not wired to the system, and both are defects in the specification or the binding, not license to proceed.

## P5 — implement with the inner two-stream loop

Implementation proceeds under the inner red-green-refactor loop of `test-driven-development`, with two streams constraining the work: the unit stream fixes internal correctness, the acceptance stream fixes external behavior.
A tight loop may run an impact-selected subset of scenarios for speed, but the subset never substitutes for the full run that P6 gates on.

Gate: no separate gate; P5 runs until P6's gate can pass.

## P6 — the GREEN gate

Both streams go green together on a full run.
A full acceptance run, not an impact-selected subset, is the gate, because an impact selection can hide a scenario that a change silently broke elsewhere.

Gate: the complete acceptance suite and the unit suite both pass.

## P7 — refine

The implementation is cleaned up under the project's design constraints without changing observable behavior, so the acceptance suite stays green throughout the refinement.
Refinement that changes an observable outcome is a new behavior and returns to P1, not a refactor.

Gate: the acceptance suite remains green and the refinement introduced no observable change.

## P8 — verify and the optional mutation firewall

A verifier whose `agent_id` differs from the implementer's and the refiner's confirms the work against its exit criteria (see `references/handoff-as-gate.md`).
The optional mutation firewall then checks that the suites actually catch regressions rather than merely executing the code, deferring severity and adequacy judgments to `preferences-validation-assurance` (see `references/two-stream-and-mutation-firewall.md`).

Gate: verification independence holds, the exit criteria are asserted with evidence, and any mutation run's survivors are triaged rather than ignored.

## Traceability across the phases

Each scenario carries a tag naming the capability it belongs to and a tag naming the requirement it witnesses, and a traceability table maps each in-scope behavioral requirement to at least one witnessing scenario.
This is what lets a failing run report the owning requirement and the failing scenario name rather than only a stack trace, and it is what lets P1's coverage gate be checked mechanically rather than by inspection.
The `safeadt` behavioral-acceptance specification carries this convention as `@<spec>` and `@req-<slug>` tags plus a requirement-to-scenario table, and it is a workable template for the tagging discipline.
