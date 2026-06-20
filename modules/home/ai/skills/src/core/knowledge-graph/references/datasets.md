---
name: knowledge-graph-datasets
description: Dataset conventions for the knowledge-graph reference-corpus engine — one dataset per coherent reference collection, naming, create-vs-reuse heuristic, lifecycle, inspection, and ingest hygiene.
---

# dataset conventions

A dataset is the unit of organization for a reference corpus.
Everything you ingest lands in a named dataset, the graph is built within it, and every query is scoped to one or more datasets.
Choosing dataset boundaries well is the main lever you have over how clean and how queryable the resulting graph is, so treat dataset design as a deliberate step rather than an afterthought.
This file is engine-neutral on intent and defers exact command flags to [cognee-cli.md](cognee-cli.md); verify any verb's flags with `cognee <verb> --help` before relying on them.

## one dataset per coherent reference collection

A dataset should hold one coherent body of reference material that you expect to query as a unit.
The engineering references are a coherent body; the modeling references are another; a single manuscript's cited sources might be a third.
Keep distinct bodies in distinct datasets so that a query against one is not diluted by entities and relationships extracted from unrelated material.
Mixing unrelated corpora into a single dataset produces a graph whose grounding context for any given question is noisier than it needs to be, because retrieval has a larger and less relevant surface to draw from.

## naming

Name datasets with lowercase-kebab subject names that describe the corpus: `engineering-references`, `modeling-references`.
The name should read as the thing it contains, not as the verb you used to populate it and not as a session or agent identity.
Avoid the framing-laden defaults that the underlying API offers, in particular `main_dataset` (the verb default) and anything shaped like `claude_sessions`.
Those names invite the memory-store misuse this skill rejects: a dataset called `main_dataset` carries no signal about what reference material it grounds, and a dataset named for a session implies it holds conversation state rather than curated references.
Always pass an explicit subject name rather than accepting the default.

## create vs reuse

The heuristic mirrors the git-branch rule: when in doubt, create a new dataset.
New datasets are cheap, and a clean boundary between two bodies of reference material is worth far more than the minor convenience of having fewer of them; a tangled graph spanning unrelated corpora is expensive to query well and awkward to prune.

Create a new dataset when the material is a distinct body that you will query in isolation — a different subject, a different manuscript's sources, a corpus you want to scope recall to on its own.
Reuse an existing dataset when you are extending the same coherent collection: add more reference documents to it and re-run the build or enrichment pass so the new material joins the existing graph.
The test is whether a future query would want these documents considered together as one body of evidence; if yes, they belong in the same dataset, and if you are unsure, the bias toward a new dataset keeps boundaries clean.

## lifecycle

A dataset moves through ingest, query, and enrichment.
For everyday work the ingest step is a single `remember` call per document, which ingests the reference material and builds the graph in one operation.
For bulk corpus loads — many documents where you want to ingest first and build once — decouple the steps: issue repeated `add` calls to load the documents, then a single `cognify` over the dataset to build the graph.
The decoupled path is the right tool when you are loading a large corpus, re-processing existing material with a different schema, or running the build as a background job; otherwise prefer the single `remember` call.

Once the graph exists you query it with `recall` (the everyday verb) or `search` (the lower-level, session-free verb) to pull grounding context, scoping the query to the relevant dataset or datasets.
Over time you sharpen the graph with `improve`, which runs an explicit enrichment pass over the dataset.
The full shape is: `remember` (everyday) or `add` then `cognify` (bulk) → `recall` or `search` → `improve`.

## inspecting datasets

Before ingesting into or querying a dataset, check its state.
The `datasets` verb exposes the relevant views: `datasets list` shows which datasets exist, `datasets status` reports a dataset's processing state, and `datasets graph` lets you inspect the built graph.
Use these to confirm a dataset is populated before you trust a recall against it, and to confirm a dataset exists (and which name it has) before adding more material to it.
Exact subcommands and flags are in [cognee-cli.md](cognee-cli.md).

## ingest hygiene

What you ingest defines the discipline of this skill, so guard the ingest boundary carefully.
Ingest only curated reference documents.
Never ingest secrets, `.env` files, key material, database files (`*.sqlite`, `*.db`), `node_modules`, or build output; these carry no reference value, pollute the graph, and in the case of secrets and keys would expose sensitive material to the platform.

Inspect what you are about to ingest first.
Run `rg --files` over the candidate path to see exactly which files would be swept in, and exclude anything that is not curated reference material before issuing the ingest call.
This matters most when pointing the ingest at a directory rather than a single file, where it is easy to pull in incidental artifacts alongside the intended documents.

Deletion is destructive and irreversible against the platform.
Confirm the exact target before any delete, and never delete an entire dataset's contents wholesale without explicit instruction to do so.
The delete and forget verbs and their scope flags are documented in [cognee-cli.md](cognee-cli.md).
