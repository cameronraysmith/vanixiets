---
name: nucleus-platform
description: >
  Thin router for the Nucleus pattern: a spec-anchored, approximately-verifiable data-modeling and
  computational-science monorepo where Lean 4 holds the structural source of truth outright and a
  round trip of instantiation-then-reconstruction drives structural drift toward zero. Names the
  Nucleus instance of each pattern and the few Nucleus-only rules, then delegates the how to owning
  sibling skills. Load when standing up a new Nucleus-pattern repo; orienting or operating an existing
  instance (which directory holds what, the down-L-back-up-R build order); placing a component in a
  maturity tier or deciding a promotion trigger; applying the ODPS scope rule; authoring or maintaining
  the Lean-to-LinkML skeleton projection for table schemas; wiring the Nucleus module layout; upholding
  the Arrow single-physical-oracle invariant; or choosing the deliberate frozen-stack exclusions. Does
  not fire as a generic build-a-data-platform skill nor as agent/subagent orchestration. Depends on
  preferences-theoretical-foundations and refinement-driven-development for the structural and refinement
  axis; pairs with preferences-data-modeling and preferences-bounded-context-design for the data and
  contract layers.
---

# Nucleus platform

Nucleus is a spec-anchored, approximately-verifiable data-modeling and computational-science monorepo pattern.
Lean 4 holds the structural source of truth outright, and the platform's central operation instantiates that spec into a polyglot stack, reconstructs the spec from those realizations, and validates that the round trip is an approximate identity.
This skill is a thin router: it names the Nucleus instance of each general pattern and the handful of Nucleus-only rules, then delegates the how to the owning sibling skill by bare name.
It restates nothing those siblings teach.

In one breath: Lean is the structural source of truth; the domain algebra goes Lean-direct to Expression unions and Rust enums; table schemas may stay a LinkML skeleton with an orthogonal semantic overlay; Arrow is the single physical oracle; the directory layout is the operator ◯ = R ∘ L written out, and modules/checks/*.nix is the approximate R that measures structural holonomy.

## When to use, when not

This skill fires for Nucleus-specific decisions.
Standing up a new instance; orienting in an existing one (which directory holds what, the build order); placing a component in a maturity tier and reading its promotion trigger; the ODPS scope rule; authoring or maintaining the Lean-to-LinkML skeleton projection; wiring the module layout; the Arrow single-oracle invariant; and the deliberate frozen-stack exclusions all belong here.

It does not fire for the general technique behind any of those steps; delegate the how to the bare-named sibling that owns it:

- generic dendritic, import-tree, or pkgs-by-name authoring → preferences-nix-development
- check-derivation design and the eight-category taxonomy → preferences-nix-checks-architecture
- closure-operator and holonomy framing, the no-leak discipline → preferences-compositional-continuous-verification
- the strict Lean-to-Rust round trip via Charon and Aeneas → refinement-driven-development
- the capability-interface and effect-handler ideal, and keeping a Lean spec beside a non-Rust implementation → preferences-theoretical-foundations
- Dagster asset graphs and the lawful Lance IO manager → preferences-workflow-orchestration-algebra
- Arrow interchange and scientific data contracts → preferences-data-modeling
- ODCS/ODPS as Published-Language boundary theory → preferences-bounded-context-design
- per-claim severity and confidence → preferences-validation-assurance
- CI execution and niks3-on-R2 → preferences-nix-ci-cd-integration

This skill must not fire as a generic build-a-data-platform skill, nor as agent or subagent orchestration.

## The operator and the maturity tiers

The central operation is ◯ = R ∘ L.
L (the forward instantiation leg, named Descent) lowers the spec into a polyglot data-engineering, modeling, and web-application stack.
R reconstructs the spec from those realizations and validates approximate identity.
An artifact is verified exactly when it is a fixed point of ◯, that is, when the unit η_S : S → R(L(S)) is an equivalence to tolerance.
The residual failure of η_S to be an equivalence is the holonomy, the structural drift the platform measures and drives down; progress is the monotone decrease of that residual, each step carrying an interpretable certificate.
The name is mathematical, not biological: ◯ is a Lawvere-Tierney nucleus, an idempotent, inflationary, meet-preserving modality whose fixed points are sheaves, and Descent, the forward leg L, is Grothendieck descent, the gluing the conformance gates enforce.
The closure-operator and no-leak framing behind this lives in preferences-compositional-continuous-verification.

Every component carries one of four maturity tags: [realized] for off-the-shelf or near-term, [build] for bespoke work owed, [deferred] for optional or future work parked with an explicit trigger, and [concept] for an interpretive framing not enforced by any compiler.
The verbatim tier table with examples and promotion triggers is in references/maturity-tiers.md.

## The two epistemically distinct bridges

Nucleus runs two bridges off the Lean spec that mechanize on different timelines, and the skill must keep them separate.

The realization bridge takes Lean to realizers: realizers inhabit the typed propositions of the spec, synthesized and then witnessed by test or proof.
This is gated approximately today by CI and proved strictly later where the language permits.
Its strict form, strict-R, is the [deferred] Lean-to-Rust round trip over a non-concurrent Rust subset via Charon and Aeneas; that round trip is owned entirely by refinement-driven-development.

The translation bridge takes the Lean data model to a LinkML skeleton: it is [build], LLM-maintained, and curation joins it, so it is never a witnessed deterministic functor.
Below LinkML, by contrast, the LinkML-schema-to-bindings leg (pydantic, dataclasses, and more) is mechanical and drift-checkable via LinkML tooling.

## The structural axis and the semantic overlay

Nucleus has two orthogonal axes that meet only at the artifacts, never inside one type system: Lean carries the structural and refinement axis, and LinkML carries the semantic-binding and external-provenance axis.
Lean owns the structural source of truth outright; nothing co-claims it.
Never describe LinkML as the logical or structural source of truth.

The demotion that this axis correction encodes is precise: domain algebra is Lean-direct, while table schemas may stay LinkML.
This domain-vs-data split is the Nucleus instance of the lowering-path bifurcation owned by preferences-data-modeling: the domain-direct path is the sum-rich domain algebra, and the schema-factored path is the product-oriented table schemas.
The domain model is sum-rich, an exhaustiveness-checked in-memory algebra that the transforms pattern-match on, so it goes Lean-direct to Expression tagged unions and Rust enums with no intermediate schema language.
The data model is the columnar Lance and Arrow table schemas, product-oriented regardless of the domain's sums, so at the table level the expressiveness gap closes and the schema may remain a LinkML skeleton plus ontology overlay, curator-editable.
This is a demotion of LinkML from the domain spine, not its removal from the structural path entirely.

Semantic identity is data that no type system carries.
Whether a slot's range is CL:0000540, which CURIE an enum value binds, how a local term maps to an external vocabulary: none of this is a projection of anything in Lean, so it is curated and joined in at the LinkML layer.
The semantic and provenance overlay is one framework, LinkML, at full strength: ontology binding via class_uri, slot_uri, and CURIE-bound enums; OWL, SHACL, and RDF emission; and a curator- and biologist-editable surface.
LinkML's broader ontology and semantic facilities, including cross-ontology mapping provenance, are realized per-schema rather than as separate tools, grounded in the linkml and linkml-biolink-model reference repos under /Users/crs58/projects/omicslake-workspace.

The join of the axes is projection-plus-overlay: the [build] projection emits a LinkML skeleton from the Lean data model, and curator-authored ontology bindings are merged onto it as a mixin.
A property-based conformance test closes the join: the published LinkML schema must accept exactly the serializations the algebraic model emits and round-trip them.
No single artifact masquerades as serving both axes.
Crucially, the round trip ◯ = R ∘ L is purely structural and acts only on the Lean axis; the semantic overlay is orthogonal and is not part of the round trip.
Holonomy therefore measures structural drift only and never validates semantic bindings, which get the separate property-based conformance test (modules/checks/conformance.nix).

The LinkML data-model path is proportionate here and detailed in references/linkml-data-model.md.
In short: within the Python realizer package, a hand-authored schema/ LinkML schema is the local source, and a generated datamodel/ holds pydantic and dataclass bindings regenerated from it and never hand-edited; Nucleus adds one promotion step of its own, pydantic to LanceModel/TypedTable, from which TypedTable.to_arrow_schema() yields the single physical Arrow oracle.
Factoring the data model through LinkML buys LinkML's mature generator suite (pydantic, dataclasses, and roughly a dozen more bindings on demand), which is the justification for the modest Lean-to-YAML projection.
The alternative, a net-new Lean-direct generator to {TypedTable, Pydantic, TypeScript, Arrow}, is the documented other branch of an open sum-fidelity-versus-codegen trade; settle it against the first real domain instance, and do not scaffold the Lean-direct generator now.
The Arrow interchange and data-contract techniques are owned by preferences-data-modeling; the boundary theory for ODCS and ODPS is owned by preferences-bounded-context-design.

## Frozen stack and deliberate exclusions

The stack is frozen.
The compact map below routes each layer to its Nucleus instance and the sibling that owns the technique; the verbatim layer-tool-role table and the key flake inputs are in references/frozen-stack.md.

| Layer | Nucleus instance | Owning skill |
|---|---|---|
| Structural source of truth (spec) | Lean 4 | preferences-theoretical-foundations |
| Domain model (Lean-direct) | Expression tagged unions, Rust enums | preferences-domain-modeling, preferences-algebraic-data-types |
| Data / table model | TypedTable → Arrow oracle | preferences-data-modeling |
| Semantic / provenance overlay | LinkML | preferences-data-modeling |
| Contracts (ports, products) | ODCS v3.1.0, ODPS v1.0.0 | preferences-bounded-context-design |
| Compute and data plane | Dagster, DataFusion, Lance on R2, Modal | preferences-workflow-orchestration-algebra |
| Serving | lakescope (Axum, DataFusion/Ballista, WASM/wgpu, Lit, Datastar) | apps realizer |
| Reconstruction (R) | modules/checks/*.nix | preferences-nix-checks-architecture |
| Build and CI | uv2nix, crate2nix, niks3-on-R2 | preferences-nix-development, preferences-nix-ci-cd-integration |

The deliberate exclusions are load-bearing and must not be silently reintroduced: crate2nix with rust-overlay rather than crane or crane-maturin; elan from nixpkgs rather than a lean4 flake input; clan-core, buildbot-nix, and nixidy are infrastructure and are not flake inputs; CUE is held in reserve, the answer only if a polyglot structural-contract need ever appears, redundant today given Arrow downstream and Lean upstream.

## Standing up an instance

The project template is deferred until a first instance is witnessed, so today step one is by-hand; once an instance exists, extract a template from it.
The invocation flow runs down the L leg and back up the R leg, delegating each step:

1. Scaffold the dendritic flake-parts root with import-tree and pre-wire the frozen inputs → preferences-nix-development.
2. Author the Lean spec S: Model ADTs, the abstract Effects signature (read, scan, commit), and the Pipeline morphisms; gate it with a #print axioms check → preferences-theoretical-foundations and preferences-domain-modeling.
3. Build and maintain the [build] Lean-to-LinkML skeleton projection for table schemas only; this is LLM-maintained and makes no functor claim.
4. Generate datamodel bindings via LinkML and add the promotion step to TypedTable; treat LinkML as the logical contract for the data model with the ontology overlay as a mixin, derive the Arrow oracle, and place ODCS and ODPS contracts under the two-or-more-consumer rule → preferences-data-modeling and preferences-bounded-context-design.
5. Inhabit the realizers: the pipeline uv workspace and the apps/lakescope crate → preferences-workflow-orchestration-algebra for the Dagster assets and the lawful Lance IO manager.
6. Wire R as modules/checks/*.nix, import-tree-discovered, computing the approximate holonomy → preferences-nix-checks-architecture and preferences-compositional-continuous-verification, with refinement-driven-development for strict-R when it is switched on.
7. Stand up the local stack and CI: process-compose, just check-fast, niks3-on-R2 → preferences-nix-ci-cd-integration.

Carry the contract, not a worked Lean metaprogram skeleton: the default deliverable is the Lean-to-LinkML skeleton for table schemas, width-pin carrying, the ontology overlay as a mixin, the property-based conformance test, and the promotion to TypedTable then Arrow.

## Operating the round trip

The directory layout is the operator written out, so the build order is the tree order, down the L leg and back up the R leg; the verbatim tree is in references/directory-tree.md; the operator drawn out as a diagram is in references/nucleus-workflow.md.
Down L: spec/ (the object S) → contracts/ (Lean-direct structural bindings plus the orthogonal LinkML overlay joined as a mixin, with the Arrow oracle derived once) → pipeline/ (compute and data realizers) → apps/ (serving realizers).
Back up R: modules/checks/*.nix reconstruct and validate S, computing the structural holonomy; the realized gates are the components of η that are equivalences to tolerance.

Three operating disciplines are Nucleus-specific.
The spec is gated by a #print axioms check so no realized obligation rests on an unintended axiom.
I/O appears in the spec only as an abstract effect signature (Spec/Effects), with handlers living in the pipeline and apps realizers, never as a concrete effect in the spec.
Keep the no-leak discipline: structural and semantic concerns stay on their own axes, and no artifact serves both; the framing is owned by preferences-compositional-continuous-verification.

## Maturity-tier decisions and promotion triggers

When placing or promoting a component, read references/maturity-tiers.md and apply the Nucleus triggers.
The realized conformance gates collectively compute the currently-approximate structural holonomy.
The Lean-direct multi-target generator's sum-fidelity-versus-codegen-cost is an open [build] decision settled against the first real domain instance, not in the abstract.
Substrait becomes real only if plans are pinned or the system goes multi-engine; strict-R via Charon and Aeneas switches on selectively where the language permits and is proved later; CUE becomes the answer only if a polyglot structural-contract need appears.
The [concept] tier (the QMADTT roles) is an interpretive reading with no promotion mechanism.

## Key invariants

- Lean 4 holds the structural source of truth outright; never call LinkML the structural or logical source of truth.
- Two orthogonal axes: Lean for structure and refinement, LinkML for semantic binding and external provenance; they meet only at the artifacts.
- Domain algebra is Lean-direct (Expression unions, Rust enums); table schemas may stay a LinkML skeleton plus overlay.
- The Lean-to-LinkML projection is [build] and never a deterministic functor; the LinkML-and-below bindings are mechanical and drift-checkable.
- The join is projection-plus-overlay (skeleton plus mixin) gated by a property-based conformance test, distinct from the round trip.
- ◯ = R ∘ L is purely structural; holonomy is a structural metric and does not validate semantic bindings.
- Arrow, via TypedTable.to_arrow_schema(), is the single physical oracle.
- ODPS is live: wrap one bounded context's output, promote at two-or-more consumer classes or a cross-context consumer.
- The project is Nucleus; Descent survives only as the name of the forward leg L; the diagram file is nucleus-workflow.mermaid.
- Deliberate exclusions: crate2nix and rust-overlay (not crane/crane-maturin), elan from nixpkgs (not a lean4 flake input), clan-core/buildbot-nix/nixidy not inputs, CUE in reserve.

## References

| Reference | Open it for |
|---|---|
| [references/directory-tree.md](references/directory-tree.md) | The verbatim Nucleus directory tree, the operator written out as build order. |
| [references/frozen-stack.md](references/frozen-stack.md) | The verbatim layer-tool-role frozen-stack table, key flake inputs, and exclusions. |
| [references/maturity-tiers.md](references/maturity-tiers.md) | The four-tier table with examples and the Nucleus promotion triggers. |
| [references/nucleus-workflow.md](references/nucleus-workflow.md) | The operator diagram (the round trip drawn out) and how to read it; links to the mermaid source. |
| [references/linkml-data-model.md](references/linkml-data-model.md) | The schema/-to-datamodel/ flow, the TypedTable promotion, the open codegen trade, and the omicslake reference repos. |

## See also

preferences-theoretical-foundations, refinement-driven-development, preferences-workflow-orchestration-algebra, preferences-compositional-continuous-verification, preferences-nix-checks-architecture, preferences-nix-development, preferences-data-modeling, preferences-architectural-patterns, preferences-computational-system-taxonomy, preferences-validation-assurance, preferences-bounded-context-design, preferences-nix-ci-cd-integration.
