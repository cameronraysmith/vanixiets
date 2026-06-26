# Frozen stack and flake inputs

The stack is frozen by design.
The SKILL.md body carries the compact layer-to-owning-skill map; this file is the verbatim layer-tool-role table plus the key flake inputs and the deliberate exclusions.
The owning-skill routing (which sibling teaches each technique) stays in the SKILL.md compact table; this file does not duplicate it.

## Layer, tool, role

| Layer | Tool | Role |
|---|---|---|
| 1 · Structural source of truth — Proof / Spec tier | Lean 4 | STRUCTURAL source of truth outright (nothing co-claims it); the object S; ADTs incl. exhaustiveness-checked discriminated sums (A+B+C); effect-typed pipeline signatures; elaborator checks sum totality + refinements; modalities are QMADTT; sought fixed points are sheaves |
| 1 · concept reading | QMADTT roles | [concept] a reading, not a compiler — quantitative=erasure(+Rust affine) · coeffects=contract demands · effects=I/O signature · modal/adjoint=structural round trip ◯=R∘L (NOT a codegen functor) |
| 2 · Erasure (QTT) | Erasure boundary (QTT) | quantitative erasure boundary on the L leg |
| 2b · Domain model — Lean-DIRECT, sum-rich in-memory algebra | Python Expression tagged unions (+ beartype + ty/basedpyright) | domain model the transforms pattern-match on; Lean-direct, no intermediate schema language |
| 2b · Domain model — Lean-DIRECT | Rust enums + Result + affine ownership | Rust domain model, Lean-direct |
| 3 · Data / table artifact tier — columnar, product-oriented | TypedTable (vendored LanceModel) | table schema; DATA model product-oriented regardless; may stay a LinkML skeleton + overlay |
| 3 · Data / table artifact tier | Arrow schema = TypedTable.to_arrow_schema() | SINGLE physical oracle |
| 3 · Data / table artifact tier | TypeScript interfaces | structural binding consumed by apps/lakescope web-components |
| 3 · Data / table artifact tier | serde + arrow-rs structs | Rust data-model binding, validated vs Arrow oracle |
| 3 · Data / table artifact tier | ODCS v3.1.0 contracts | per output port; gluing / compatibility conditions on restriction maps |
| 3 · Data / table artifact tier | ODPS v1.0.0 data products | LIVE; output ports → modeling jobs (compute) · lakescope (human) · agents (future); sections over the catalog-site + restriction maps; wraps one bounded context's output, promote at 2+ consumer classes |
| S · LinkML semantic / provenance overlay — ORTHOGONAL | LinkML | ONE framework, semantic axis at full strength; frame-based metamodel (classes/slots/inheritance/mixins); ontology binding class_uri/slot_uri/CURIE-bound enums; curator/biologist-editable surface; earns the axis on mature OBO→OWL/SHACL generators + readable surface, NOT expressiveness |
| S · semantic overlay | OWL / RDF emission | ontology binding output (from LinkML) |
| S · semantic overlay | SHACL + Pandera | dataset refinements (RDF-shape emission) |
| 4 · Compute and data plane | Dagster (single instance) | orchestration |
| 4 · Compute and data plane | DataFusion ingest (datafusion-python) | external → Lance ingest |
| 4 · Compute and data plane | Lance DirectoryNamespace on R2 | single catalog namespace / storage |
| 4 · Compute and data plane | Modal: Python / JAX jobs | compute jobs wrapping core callables |
| 5 · Serving (apps/lakescope) | Axum + DataFusion / Ballista | serves Arrow IPC |
| 5 · Serving (apps/lakescope) | WASM/wgpu plots · Lit · Datastar control plane | dashboard rendering + view/filter/parameter state over SSE |
| Reconstruction + validation (R), realized today | Conformance gates (CI) | approximate R — STRUCTURAL, on the Lean axis: generated-artifact drift · datacontract-cli (ODCS/ODPS) · SHACL/Pandera asset checks · Arrow-oracle match |
| Deferred / optional / future — NOT in the live path | Substrait plan IR | latent capability; real only if you pin plans or go multi-engine |
| Deferred / optional / future | Charon/Aeneas | strict R; future · selective · non-concurrent Rust subset only |
| Deferred / optional / future | CUE | IN RESERVE: the answer IF a polyglot structural contract need ever appears; not a current component; mostly redundant given Arrow physical oracle + Lean upstream |

## Key flake inputs

| Input | Purpose |
|---|---|
| nixpkgs | base; provides `elan` (manages pinned Lean toolchain via `lean-toolchain`) |
| flake-parts · import-tree | dendritic deferred module composition |
| uv2nix · pyproject-nix · pyproject-build-systems | Python from pyproject + uv.lock |
| crate2nix · rust-overlay | Rust (lakescope crates, plot→wasm) incl. wasm32 target |
| nix2container | OCI images (lakescope, dagster, modal) |
| treefmt-nix · git-hooks | unified formatting + pre-commit |
| pkgs-by-name-for-flake-parts | pkgs/by-name discovery (datacontract-cli; charon/aeneas when strict R is switched on) |
| process-compose-flake · services-flake | local dev stack (dagster + lakescope + MinIO) |

## Deliberate exclusions

These are intentional and must not be reintroduced without an explicit decision.

- crane and crane-maturin are not inputs; crate2nix with rust-overlay replaces them.
- elan comes from nixpkgs and reads spec/lean-toolchain; there is no lean4 flake input.
- clan-core, buildbot-nix, and nixidy are infrastructure, out of scope, and not inputs.
- CUE is not an input; it is held in reserve, the answer only if a polyglot structural-contract need ever appears, redundant today given the Arrow physical oracle downstream and Lean upstream.
