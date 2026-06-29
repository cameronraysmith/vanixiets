# Maturity tiers and promotion triggers

Every Nucleus component carries one of four tags.
The legend is verbatim; the per-tier examples are the canonical placements and the triggers are the organized reading of the per-item annotations, faithful to the architecture.

Legend: [realized] off-the-shelf or near-term · [build] bespoke, owed · [deferred] optional / future, parked with a trigger · [concept] framing, not enforced by any compiler.

## [realized] — off-the-shelf or near-term

Examples:

- modules/checks/drift.nix — committed structural bindings == regenerated (Lean-direct generator)
- modules/checks/arrow-oracle.nix — rust structs match TypedTable.to_arrow_schema()
- modules/checks/contracts.nix — linkml-lint + datacontract-cli (validates BOTH ODCS and ODPS)
- modules/checks/integration.nix — end-to-end: spec → contracts → pipeline → apps
- pkgs/by-name/datacontract-cli/ — ODCS/ODPS validation CLI

Trigger: the starting tier for tools that exist off-the-shelf or are near-term.
The realized conformance gates collectively compute the currently-approximate structural holonomy — the components of η that are equivalences to tolerance.

## [build] — bespoke, owed

Examples:

- spec/Spec/Projection/ — Lean → LinkML SKELETON projection (LLM-maintained correspondence, NOT a deterministic functor)
- modules/checks/conformance.nix — property-based: the LinkML overlay accepts exactly the serializations the model emits + round-trips them (SEMANTIC axis, distinct from R)
- the net-new Lean → {TypedTable, Pydantic, TypeScript, Arrow} generator (does not exist today; an open trade)

Trigger: bespoke work owed.
The Lean-direct multi-target generator's sum-fidelity-versus-codegen-cost is an OPEN decision, settled against the first real domain instance, not in the abstract; until then keep the Lean-to-LinkML projection plus mechanical LinkML-and-below bindings, and keep the Lean-direct generator documented as the alternative.

## [deferred] — optional / future, parked with a trigger

Examples:

- modules/checks/substrait.nix — golden plan snapshots; wired only if plans pinned / multi-engine
- modules/checks/refinement.nix — strict R: Charon/Aeneas, non-concurrent Rust subset (proofs in spec/Spec/Refinement)
- spec/Spec/Refinement/ — proofs that Aeneas-extracted Rust realizers refine S
- pkgs/by-name/charon/ — Rust → LLBC extractor
- pkgs/by-name/aeneas/ — LLBC → Lean translator
- Substrait plan IR; CUE (in reserve)

Triggers, each explicit: Substrait becomes real only if you pin plans or go multi-engine; Charon/Aeneas strict R switches on selectively where the language permits (a non-concurrent Rust subset) and is proved later; CUE becomes the answer only if a polyglot structural-contract need appears.

## [concept] — framing, not enforced by any compiler

Examples:

- QMADTT roles — a reading, not a compiler (quantitative=erasure(+Rust affine) · coeffects=contract demands · effects=I/O signature · modal/adjoint=structural round trip ◯=R∘L)
- Contract layer as sheaf sections — a data product (contracts/odps/) is a section over the catalog-as-site; each output port is a restriction map to a consumer; the contracts/odcs/ contract on that port is the compatibility (gluing) condition the consumer agrees to. Interpretive only — the contract mechanics are owned by preferences-bounded-context-design.

Trigger: none.
It is an interpretive reading layered over the enforced tiers with no promotion mechanism.
