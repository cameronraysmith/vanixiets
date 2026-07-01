# The fix/defect loop

Repairing a defect runs the outer loop in miniature, with one non-negotiable ordering: the reproduction comes before the fix.
The reproduction is written first, confirmed to fail on the current code, and only then repaired, so the test witnesses the defect rather than merely accompanying its fix.

## Regression-spec-first

On a reported defect, write the scenario or unit test that reproduces it and run it against the unmodified code to confirm it is RED.
A reproduction that passes before the fix witnesses nothing: it does not exercise the defect, and it will keep passing whether or not the defect is ever repaired, so it gives false assurance.
Confirming RED on the current code proves the reproduction actually reaches the broken behavior, which is the whole value of writing it first.
Only after the reproduction is RED does the fix proceed, and it is the smallest change that turns the reproduction GREEN without breaking the existing suites.
The reproduction then stays in the suite permanently as a regression witness, so the defect cannot silently return.

## Route the reproduction to the right modality

The reproduction is subject to the same Gate 1 routing as any other proposition (`references/is-bdd-the-right-tool.md`).
A defect in observable domain behavior is reproduced as a scenario at the public surface.
A defect that is really a dependency-compatibility break — a shim that stopped importing, an upstream API that changed shape — is reproduced as a regression or smoke test, not as a scenario, because dressing an import check in Gherkin yields a vacuous `Given` and a `Then` that swallows the very error it should surface, which is a witness of nothing.
A defect that violates a universal law is reproduced as a property or law test through `preferences-algebraic-laws`, since a single scenario under-constrains a proposition quantified over all inputs.

## Severity and adequacy defer out

Whether a defect's reproduction is severe enough to gate a release, how strong its evidence is, and whether the surrounding suite is now adequate against the class of defect it belongs to are judgments owned by `preferences-validation-assurance`.
A reproduction that fails under plausible incorrect implementations is a severe test; a reproduction that pins only the one input that was reported may leave the defect class open, and closing the class rather than the instance is the adequacy question that validation-assurance owns.

## Relationship to the loop

The fix/defect loop is the outer loop entered from a defect rather than from a feature: the reproduction is the specification, RED-before-fix is the RED gate, the smallest fix is the implementation, and the retained reproduction is the permanent witness.
It reuses the same routing gate, the same RED-before-GREEN discipline, and the same deferral of severity that the full loop uses in `references/outer-loop-workflow.md`.
