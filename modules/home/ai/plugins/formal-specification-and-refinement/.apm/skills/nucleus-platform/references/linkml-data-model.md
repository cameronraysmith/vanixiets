# The LinkML data-model path

This is the concrete shape of the data-model leg: how a hand-authored LinkML schema generates the table bindings, where Nucleus adds its own promotion step, why the data model is factored through LinkML at all, and which omicslake repositories ground the description.
The semantic-axis theory lives in the SKILL.md body and in preferences-data-modeling; this file is the proportionate mechanical detail.

## schema/ to datamodel/ flow

Within the Python realizer package, two coupled subpackages have a strict one-way generation direction.
schema/ holds the hand-authored LinkML schema, a single YAML file (for example schema/schema.yaml) declaring prefixes, imports, classes, slots, and enums; this is the local source of truth for the bindings.
datamodel/ holds generated code, regenerated from that schema and never hand-edited: pydantic v2 BaseModel derivatives (for example datamodel/model.py, emitted by gen-pydantic) and companion plain dataclasses (for example datamodel/dataclasses.py, emitted by gen-project -I python).
The generated header banners and the project README both record the direction ("Auto generated from ... do not hand-edit").

Ingesting an external source means adding our own expected and desired schema for it to schema/schema.yaml — authored manually, following practices inferred from the reference instance, not via the copier mechanism — and then regenerating the datamodel bindings.

## The Nucleus promotion step

Nucleus adds one step of its own, downstream of the LinkML output and not part of LinkML or the reference instance.
Take the gen-pydantic output and promote each table-bearing class from pydantic BaseModel to LanceModel / TypedTable, from which TypedTable.to_arrow_schema() yields the single physical Arrow schema oracle for the data plane.
The promotion re-runs whenever the schema, and therefore datamodel/, is regenerated.

## Why factor the data model through LinkML

The reason to route the table schemas through LinkML rather than Lean-direct-to-pydantic is LinkML's mature generator suite: from one schema it mechanically emits pydantic and dataclasses plus roughly a dozen more bindings (jsonschema, owl, shacl, shex, sqlschema, typescript, protobuf, graphql, jsonld, excel, java, prefixmap).
Most are not needed initially, but on-demand interoperability bindings for free justify the modest Lean-to-YAML projection.
This concretizes the open sum-fidelity-versus-codegen trade toward the table-schemas-stay-LinkML branch.
Keep the Lean-direct generator documented as the alternative and keep the trade flagged open, to be settled against the first real instance; do not prescribe or scaffold the net-new Lean → {TypedTable, Pydantic, TypeScript, Arrow} generator now.

Globally, schema.yaml is authoritative for the bindings locally, but it is itself the [build], LLM-maintained projection downstream of the Lean structural source of truth.
This does not make LinkML a structural source.

## Grounding instances

The flow is grounded in a real instance and its template, both under /Users/crs58/projects/omicslake-workspace.

- test-linkml — the concrete reference instance, a copier-instantiated LinkML project; its src/test_linkml/schema/test_linkml.yaml generates src/test_linkml/datamodel/{test_linkml_pydantic.py, test_linkml.py}, and its project/ tree holds the other twelve generated bindings. We author our schema manually following its inferred practices, not through the copier.
- linkml-project-copier — the copier template whose template/justfile defines the gen-* recipes (gen-python, gen-project, gen-pydantic, gen-doc, and the per-binding recipes) that drive schema-to-datamodel generation.

## Reference repositories

All under /Users/crs58/projects/omicslake-workspace, verified present.
Near the contracts discussion:

- open-data-product-standard — the ODPS specification source.
- open-data-contract-standard — the ODCS specification source.

Near the semantic axis and the data-model path:

- linkml — the LinkML language plus the generator suite that emits all downstream bindings.
- linkml-model — the LinkML metamodel, LinkML authored in LinkML.
- linkml-biolink-model — Biolink, a LinkML-authored schema.
- linkml-cell-annotation-schema — CAS, the LinkML schema that realizes the CL:0000540 semantic-overlay example.
- linkml-information-resource-registry — a LinkML-modeled registry of data sources.
- linkml-registry — an auto-generated registry of LinkML schemas discovered across GitHub.
- test-linkml — the example instance of the copier template (above).
- linkml-project-copier — the template (above).

Note for later: the canonical Nucleus spec currently lives outside this repository and may want a permanent in-repo home; this skill is self-contained and does not link to it.
