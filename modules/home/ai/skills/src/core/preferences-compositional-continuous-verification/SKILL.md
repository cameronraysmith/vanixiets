---
name: preferences-compositional-continuous-verification
description: >
  Compositional Continuous Verification (CCV) — theoretical anchor for system-level
  approximate correctness via operating-envelope-plus-regulator pairs that compose
  into a single closure operator. Distinct from narrow Continuous Validation
  (Rosenthal–Jones runtime sense). Load when designing flake checks, reasoning about
  coverage and traceability, proposing new regulators, auditing whether a system's
  verification apparatus closes, or framing the agent-side enumerate-and-audit habit
  on `.#checks`.
---

# Compositional continuous verification

## Thesis

<!-- Provenance: close paraphrase from CCV doc §1.3 (lines 41–45); merges the three blockquote paragraphs into one prose paragraph and adds the parenthetical "(construction, integration, and runtime)" enumeration of the artifact lifecycle. -->
> A system is considered approximately correct to the extent that for every artifact it produces, an explicit operating envelope is declared as a first-class artifact, and an automated regulator — itself a first-class artifact — demonstrates by sampling that the produced artifact stays within its declared envelope across the artifact's full lifecycle (construction, integration, and runtime).
> The regulator must contain a model of the artifact it regulates (per Conant–Ashby), must itself be regulated against vacuity (integrity), and must be jointly sufficient with its peers to span every artifact in the system (traceability) and every declared bin within each envelope (adequacy).
> This commitment is operationalized via hermetic, content-addressed, graph-structured regulators that compose into a single closure operator over the system's full build and runtime graph, so that "is the system approximately correct?" reduces to a single command that succeeds or fails deterministically against pinned inputs.

The thesis turns on four load-bearing terms.
An *operating envelope* is the declared set of conditions under which the artifact is committed to behaving correctly, made first-class as a structured artifact rather than left implicit in the regulator's assertions.
A *regulator* is an automated process whose job is to sample the artifact's actual behavior and compare it against the envelope; per the Conant–Ashby theorem every good regulator necessarily contains a model of what "working" means for its target, and CCV asks that the model be explicit rather than silently encoded.
A *closure operator* is the single composed evaluation of every regulator over the whole repository graph against pinned inputs — `nix flake check` in the canonical realization — whose deterministic pass-or-fail outcome is what "the system is approximately correct" reduces to.
*Approximate* is precise rather than vague: Rice's theorem and Ashby's Law of Requisite Variety jointly make perfect coverage structurally impossible, so the discipline targets a state where the gap between intended and exercised behavior is visible, bounded, and decreasing rather than nominally closed.

The operational headline below restates the same commitment in five clauses suitable for quotation by downstream skills.

## Operational headline

<!-- Provenance: operating-envelope/Conant–Ashby framing per the user's working synthesis, derived from CCV doc §1.3 with the closure-operator clause from §5.3 fused in as the final clause; not present verbatim in the doc. -->
> Approximate correctness of a system means: every artifact has a declared operating envelope and an automated regulator that demonstrates the artifact stays inside it; the regulators jointly span the system (traceability) and each envelope (adequacy) and are themselves regulated against vacuity (integrity); and the entire apparatus is hermetic, content-addressed, and graph-composed into a single closure operator whose execution is a single command.

Downstream skills may quote this headline by reference rather than re-stating the full thesis.

## The four-property hierarchy

The structural content of CCV is captured in four properties of the regulator suite, each strictly stronger than the last.

*Existence* says there is at least one regulator in the suite of a given kind.
This is the trivial property measured by enumerating check attributes; it is necessary but says almost nothing on its own, since a repository can have hundreds of checks that exercise a small fraction of the codebase, or a handful of checks that thoroughly exercise everything.
A green CI dashboard tells the agent only that the regulators that exist passed, not that the regulators which should exist do exist; the next three properties are what distinguish a repository whose checks happen to pass from a repository whose verification apparatus actually closes.

*Traceability* says that for every artifact in the system that requires regulation, at least one regulator targets it.
This is the breadth property — the relation `regulates ⊆ Checks × Artifacts` is total over the set of artifacts that require regulation, or equivalently the projection from check-artifact pairs onto artifacts is surjective.
Untraced code is structurally invisible to the verification apparatus, and no quantity of testing of other artifacts can compensate for an artifact that has zero regulators pointing at it.

*Adequacy* says that within each fiber of the traceability relation, the regulators jointly saturate the declared coverage model for their target.
This is the depth property, meaningful only relative to a declared envelope: without an explicit set of bins to cover, the question "is this regulator adequate?" has no answer.
Observability-interaction checks are a kind of bin that artifact envelopes are expected to declare and cover — verifying that a service emits traces with the expected attributes, that an OTel collector pipeline preserves them, and that the deployed dashboard renders against real data are adequacy obligations like any other, and an envelope that omits observability-interaction verification is an adequacy gap rather than a stylistic choice.

*Integrity* says the regulator would actually fail if its target were broken.
This is the vacuity-detection property, operationally checked via mutation testing: deliberately broken versions of the artifact (mutants) must cause the regulator to fail.
A regulator that passes regardless of what its target does — a unit test that asserts nothing, an integration test whose assertions have been silently weakened during flake debugging, an SLO check whose threshold has drifted to a value the system always satisfies — has zero regulatory power despite existing in the suite.
The mutation-kill rate per regulator is a measurable property of the suite rather than a cultural one, and the integrity meta-check is what surfaces vacuity that traceability and adequacy alone cannot see.

> integrity is meaningless without adequacy; adequacy is meaningless without traceability; traceability is meaningless without existence

<!-- Provenance: verbatim from CCV doc §3.3 (line 156). -->

The reverse direction of that chain is the order in which a discipline must achieve the four properties: first ensure regulators exist, then ensure they cover all artifacts, then ensure they cover each artifact's declared envelope, then ensure they actually fail on regression.

Alongside the four properties sits an exemption audit as a fifth wheel preventing silent erosion.
Real repositories accumulate legitimate exemptions — an internal helper exercised transitively by other tests, or a temporary exemption while a check is being authored — and the audit derivation enumerates these, validates that each has an owner and an unexpired timestamp, and fails on stale or unowned entries.
Without this regulator the exemption mechanism becomes a silent drift channel where the apparatus's coverage shrinks over time without anyone noticing.

## The closure operator

`nix flake check` against a pinned flake input is the closure operator.
The command evaluates every derivation listed in `checks.<system>`, builds them in parallel through lazy content-addressed caching, and succeeds if and only if every derivation succeeds.
Buildbot-nix in CI does the same thing via `nix-eval-jobs` for parallel evaluation across a worker pool.

The deterministic pass-or-fail decision against pinned inputs is what operationalizes the thesis question.
The meta-regulators for traceability, adequacy, integrity, and the exemption audit are themselves derivations in `checks.<system>` and participate in the same parallel evaluation as every other regulator; if any of them detects a gap, the closure operator fails with a concrete cause rather than passing while the apparatus silently degrades.
Pinning matters because the closure operator's determinism depends on every input — source revision, dependency lock, system identifier — being content-addressed; "the checks passed" against a floating input is a claim about an unrepeatable evaluation, while "the checks passed against flake.lock at revision X for system Y" is a claim that any other party with the same inputs can reproduce bit-identically.

> `nix flake check` succeeds against a pinned flake input ⟹ every artifact has at least one regulator (traceability), every regulator's declared coverage bins are saturated (adequacy), every regulator actually fails on a mutant (integrity), every exemption is current and owned (exemption audit), and every regulator individually passed (per-check correctness).

<!-- Provenance: verbatim from CCV doc §5.3 (line 294). -->

## Verification is not validation

CCV is the broad compositional discipline this skill anchors; it spans construction-time, integration-time, and runtime regulators under one closure operator.
Continuous Validation in the narrow Rosenthal–Jones sense is the runtime, adversarial, SLO-centered corner of that space as named in the chaos-engineering literature, where "continuous validation" refers specifically to proactive runtime experimentation against operational envelopes.
Existing in-repo "continuous validation" usage in `preferences-production-readiness` and `preferences-nix-ci-cd-integration` refers to the narrow sense and is preserved unchanged in those skills; the two terms are not interchangeable.

Avoid the bare abbreviation "CV" in this skill and in any skill that references it.
Use "CCV" only for the verification (compositional) sense; spell out "Continuous Validation" in full when referencing the narrow Rosenthal–Jones sense.
The abbreviation is ambiguous in the current literature and collapsing it loses the distinction the discipline depends on.
The Boehm verification/validation distinction is upstream of both: verification asks whether the artifact matches its specification, validation asks whether the specification matches the need.
CCV is primarily a verification discipline that acknowledges validation as the upstream feedback channel — production observation updates the coverage model when real usage surfaces bins that were never declared — and the narrow Continuous Validation sense lives inside that feedback channel as the runtime, adversarial corner of CCV's broader scope.

## What this means for an agent session

CCV is the structural commitment behind the agent's local-validation-then-PR workflow.
Running `nix flake check` locally before opening a pull request is not a courtesy to CI; it is the agent exercising the closure operator on the same content-addressed graph that buildbot-nix will exercise downstream, with hash equality guaranteeing that a local pass is a CI pass against the same inputs.
The discipline collapses the build-time/CI-time distinction that ad-hoc pipelines maintain: there is one closure operator, evaluated locally during development and remotely during gating, with no separate CI configuration that could drift from the regulators it nominally runs.
The companion skill `nix-flake-pr-cycle` documents the operational workflow once it lands in a sibling commit.

The traceability audit habit is the agent-side instantiation of the breadth property, and this skill is the canonical source for the enumeration commands.

```bash
nix eval --json ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem')" --apply builtins.attrNames | jaq -r '.[]' | wc -l
nix eval --json ".#checks.$(nix eval --impure --raw --expr 'builtins.currentSystem')" --apply builtins.attrNames | jaq -r '.[]'
```

These enumerate `currentSystem` only; multi-platform coverage across the fleet's systems is buildbot-nix's domain in CI, and `preferences-nix-checks-architecture` documents the multi-system audit form.

The question on running these is not "how many checks does this repo have?" but "does this check set cover everything relevant in this repo, or are unchecked components leaking?"
Proposing to refactor, add, update, or remove flake checks along the way is a structural obligation toward traceability rather than a welcome side-quest; an agent that discovers an unchecked artifact while doing other work and declines to wire its regulator is silently allowing the apparatus to shrink.

When an artifact's behavior changes in a commit, the regulator either already covers the change or must be added, updated, or strengthened in the same commit.

> for every artifact, the regulator is part of the same commit; for every incident, the coverage-model update is part of the same resolution; for every check, the demonstration that it can fail is part of its construction.

<!-- Provenance: verbatim from CCV doc §7.7 (line 462). -->

This is the no-leak principle in its sharpest form, and it is the structural source from which the enumerate-and-audit habit derives.
The meta-checks, mutation testing, SLO declarations, and deliverable taxonomy are scaffolding that makes the principle mechanically enforceable; the principle itself is what an agent enacts every time it touches an artifact.

## What this skill does not cover

The meta-check derivations — traceability, adequacy, integrity, and exemption-audit — live flake-side as Nix expressions and are out of scope for agent-skill codification.
Their design, the structured manifest declaring per-package deliverables and required check kinds, the coverage-model schema, and the mutation-testing sampling strategy are all flake-level engineering documented in the CCV reference proper.
This skill provides the theoretical anchor and the agent-side habit; the flake-side machinery is a separate concern that `preferences-nix-checks-architecture` covers from the construction side.

Per-package manifests, per-artifact coverage profiles, and the incident-to-check feedback loop are documented in the CCV doc proper at `~/projects/sciexp/planning/docs/notes/development/continuous-verification/compositional-continuous-verification.md`; their adoption into the vanixiets flake is a deferred epic to be tracked separately when the prerequisites land.

## Forward hooks

Two design threads remain open.

Planning-unit decomposition under CCV obligates regulator-aware planning: the planning unit is the artifact-plus-regulator pair (per §7.7's no-leak principle), not the artifact alone, which means that issue decomposition and task estimation should account for the regulator wiring as part of the unit of work rather than as a follow-up.
Integration of CCV's no-leak principle into `preferences-adaptive-planning` is a deferred design question for a future session.

Observability checks as first-class CCV regulators is the second open thread; the build-time observability-contract regulator pattern (bring up a local OTel collector and trace store under process-compose, drive synthetic traffic through the application, assert the expected spans appear in the backend's query API) is documented in the CCV reference and will be integrated into `preferences-observability-engineering` after its sibling-commit pass lands.
The "process-compose (or analog)" phrasing in that pattern intentionally generalizes across peer regulator kinds: process-compose realizes application-composition envelopes, nspawn-based clan tests realize service-on-NixOS envelopes where the deployed system is itself NixOS, and full NixOS VM tests realize NixOS-module-plus-kernel envelopes.
The choice among these three is an envelope choice — the same observability contract (or any other integration-level assertion) can be discharged by any of the three regulator kinds depending on what the artifact's deployment target actually is.
See `preferences-nix-checks-architecture` §"Choosing among integration regulators" for the escalation rules.

## Cross-references

- `preferences-nix-checks-architecture` — flake-side check taxonomy and meta-check derivation patterns
- `preferences-nix-ci-cd-integration` — buildbot-nix as the closure-operator executor in CI
- `preferences-validation-assurance` — Mayo's severity criterion and mutation-based integrity evidence as the assurance side of CCV's integrity property
- `preferences-observability-engineering` — observability checks as first-class CCV regulators
- `preferences-production-readiness` — narrow Continuous Validation (Rosenthal–Jones) under CCV's broader discipline
- `preferences-scientific-inquiry-methodology` — Peircean pragmatism grounding for the four-property hierarchy
- `nix-flake-pr-cycle` — operational workflow exercising the closure operator (sibling commit)
