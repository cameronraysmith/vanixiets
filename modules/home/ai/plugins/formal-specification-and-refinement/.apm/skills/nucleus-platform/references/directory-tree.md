# Nucleus directory tree

The directory layout is the operator ◯ = R ∘ L written out: build order is tree order, down the L leg (spec → contracts → pipeline → apps) and back up the R leg (modules/checks).
This tree is the verbatim Nucleus monorepo architecture; treat it as the structural reference when scaffolding or orienting.

```
nucleus/
├── flake.nix                  (nix) flake-parts + import-tree ./modules (dendritic, deferred)
├── flake.lock                 single shared lockfile
├── .envrc
├── README.md
│
├── modules/                   (nix) flake-parts modules — import-tree target (incl. modules/checks/*.nix = R)
├── lib/                       (nix) plain Nix expressions (import / callPackage), NOT modules
├── pkgs/by-name/              (nix) custom derivations the language ecosystems don't cover
│
├── spec/                      the object S — Lean 4 spec + skeleton projection (seeds overlay) + refinement proofs
├── contracts/                 Lean-direct structural bindings + Arrow oracle + LinkML semantic overlay + ODCS ports + ODPS products
├── pipeline/                  realizers (compute/data) — uv workspace: science core + orchestration
└── apps/                      realizers (serving) — deployable web applications
    ├── lakescope/             ironstar instance (Axum + DataFusion/Ballista + Datastar + Lit + echarts + wgpu + Open Props + CUBE CSS)
    └── docs/                  docs site (optional — not required by the workflow)

modules/
├── systems.nix
├── flake-parts.nix            external flake-parts module imports
├── formatting.nix             treefmt: nixfmt · ruff · rustfmt · biome · yamlfmt (LinkML/ODCS/ODPS) · lean
├── dev-shell.nix              per-language + unified devShells
├── packages.nix               output registry
├── containers.nix             nix2container: lakescope · dagster · modal job images
├── process-compose.nix        local stack: dagster · lakescope · MinIO (R2 emulation)
├── components.nix             manifest: explicit imports of component flake-module.nix files
│
├── lean.nix                   elan (from nixpkgs) reads spec/lean-toolchain; lake builds
├── python.nix                 uv2nix workspace — discovers pipeline/ members + contracts/typedtable
├── rust.nix                   crate2nix + rust-overlay (+ wasm32 target) — apps/lakescope crates, contracts/generated/rust
├── typescript.nix             bun — apps/lakescope web-components, apps/docs
│
├── checks/                    R — reconstruction + validation (import-tree discovered)
│   ├── drift.nix              [realized] committed structural bindings == regenerated (Lean-direct generator)
│   ├── arrow-oracle.nix       [realized] rust structs match TypedTable.to_arrow_schema()
│   ├── conformance.nix        [build] property-based: LinkML overlay accepts exactly the serializations the model emits + round-trips them (SEMANTIC axis — distinct from R)
│   ├── contracts.nix          [realized] linkml-lint + datacontract-cli (validates BOTH ODCS and ODPS)
│   ├── integration.nix        [realized] end-to-end: spec → contracts → pipeline → apps
│   ├── substrait.nix          [deferred] golden plan snapshots — wired only if plans pinned / multi-engine
│   └── refinement.nix         [deferred] strict R: Charon/Aeneas, non-concurrent Rust subset (proofs in spec/Spec/Refinement)
└── lib/
    └── default.nix            flake.lib = { lanceNamespaceUri (R2), identities, ... }

lib/
├── caches.nix                 binary cache substituters/keys (plain data attrset)
└── ...                        callPackage utilities that are not modules

pkgs/by-name/
├── charon/                    [deferred] Rust → LLBC extractor (strict-R toolchain)
├── aeneas/                    [deferred] LLBC → Lean translator (strict-R toolchain)
└── datacontract-cli/          [realized] ODCS/ODPS validation CLI (pin if not packaged)

spec/
├── flake-module.nix           elan/lake build · projection exe
├── lean-toolchain             pinned toolchain (managed by elan)
├── lakefile.toml
├── Spec.lean
└── Spec/
    ├── Model/                 ADTs / refinement types — the domain-model objects (Lean-direct → Expression/Rust enums)
    ├── Effects/               algebraic-effect signature (read · scan · commit); handlers in pipeline/ + apps/
    ├── Pipeline/              typed morphisms ingest ⨟ transform ⨟ write (bodies = sorry = deferred obligations)
    ├── Refinement/            [deferred] proofs that Aeneas-extracted Rust realizers refine S (strict R)
    └── Projection/            [build] projection: Lean → LinkML SKELETON → seeds contracts/linkml/ overlay
                               NOW: LLM-maintained correspondence · NOT a deterministic functor (curation joins it)

contracts/
├── flake-module.nix           codegen derivation (checks registered in modules/checks/)
├── linkml/                    LinkML schemas = SEMANTIC OVERLAY (ontology bindings; curator-editable) — not the structural source
├── odcs/                      ODCS v3.1.0 contracts — one per output port (gluing conditions)
├── odps/                      ODPS v1.0.0 data products — sections + restriction maps (ports)
│                              scope rule: wrap at 2+ consumer classes OR a cross-context consumer
├── templates/                 Jinja2 overrides for the data-model path that retains LinkML skeleton → TypedTable subclasses (width pins)
├── typedtable/                vendored LanceModel base — pyarrow + pydantic only, no lancedb (uv member)
└── generated/                 codegen outputs, git-tracked, regenerated by flake-module
    ├── arrow/                 materialized TypedTable.to_arrow_schema() — SINGLE physical oracle
    ├── python/                domain → Expression unions (Lean-direct); data → Pydantic/TypedTable → consumed by pipeline/
    ├── rust/                  domain → enums (Lean-direct); data → serde + arrow-rs (validated vs oracle) → consumed by apps/lakescope
    ├── typescript/            interfaces                                   → consumed by apps/lakescope web-components
    ├── shacl/                 [overlay] dataset-level semantic shapes (from LinkML)
    └── owl/                   [overlay] ontology binding (RDF/OWL) (from LinkML)

pipeline/
├── flake-module.nix           process-compose service · Modal deploy app · container
├── pyproject.toml             [tool.uv.workspace] members = ["core", "orchestration"]
├── uv.lock
│
├── core/                      science library (the hodosome expansion) — reusable, orchestration-free
│   ├── pyproject.toml         jax · expression · beartype · contracts(generated python); dependency-groups.eda (dev only)
│   └── src/core/
│       ├── transforms/        pure transforms = bodies of Spec/Pipeline (Expression-typed realizers)
│       ├── simulate/          JAX simulation
│       ├── train/             JAX training
│       ├── infer/             inference
│       └── effects/           interpreters/handlers for Spec/Effects (Expression + beartype)
│
└── orchestration/             glue — depends on core
    ├── pyproject.toml         dagster · datafusion · pylance · core
    └── src/orchestration/
        ├── assets/            Dagster assets + asset checks (SHACL/Pandera) — local R, per asset
        ├── ingest/            DataFusion (datafusion-python) external → Lance
        ├── jobs/              Modal entrypoints wrapping core callables; per-job dependency extras → minimal closures
        └── catalog/           pylance: open the single Lance DirectoryNamespace on R2

apps/
├── lakescope/                 ironstar instance — full-stack data web app (human consumer port)
│   ├── flake-module.nix       crate2nix (server + wasm) · bun bundle · container
│   ├── Cargo.toml             Rust workspace
│   ├── crates/
│   │   ├── lakescope/         Axum binary (serves Arrow IPC)
│   │   ├── lakescope-query/   DataFusion/Ballista over Lance; [deferred] Substrait plan emission
│   │   ├── lakescope-catalog/ lance Rust crate: open same namespace
│   │   └── lakescope-plot/    Rust → WASM: wgpu/WebGPU plot kernels (consume Arrow IPC)
│   ├── web-components/        TS: Lit + Datastar + echarts; Open Props + CUBE CSS; embeds the wasm plot module
│   │   ├── package.json
│   │   └── src/
│   └── e2e/                   Playwright
│
└── docs/                      docs site (optional; Astro or similar) — not required by the workflow
    ├── flake-module.nix
    └── src/
```
