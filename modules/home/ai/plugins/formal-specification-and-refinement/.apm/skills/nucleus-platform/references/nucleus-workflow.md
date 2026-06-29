# Nucleus operator diagram

The operator ◯ = R ∘ L drawn out.

The diagram's single source is the sibling file [nucleus-workflow.mermaid](./nucleus-workflow.mermaid); it is not duplicated here.
This wrapper supplies only the surrounding context for reading it.

Stroke convention: solid = realized/near-term · dashed = to build / overlay join · dotted/muted = deferred/optional/future.

The structural spine runs straight down the Lean axis: ROLES frames LEAN, LEAN instantiates L into the erasure boundary, and the domain algebra descends Lean-direct into the Python and Rust realizers before the table-schema and Arrow-oracle artifacts and the compute, data-plane, and serving tiers below them.
What makes the picture a closed operator rather than a one-way pipeline is the set of closure edges back up to LEAN: the conformance gates reconstruct-and-validate R on the structural Lean axis (CI "reconstruct + validate R · structural Lean axis" → LEAN), the serving layer feeds structural respec back (DASH "respec" → LEAN), and strict-R re-derives the spec from the Aeneas-extracted realizers (AEN "strict R: re-derive spec" → LEAN).
Those returning edges are the R leg; together with L they draw ◯ as a closed loop, and the residual gap on that loop is the holonomy.
LinkML sits off the spine as the orthogonal semantic overlay, joined into the structural axis only at the table-schema layer (LINKML → TT) and otherwise never on the round trip.
