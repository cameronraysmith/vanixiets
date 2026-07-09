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

Name datasets with lowercase-kebab subject names that describe the corpus: `engineering-references-v2`, `modeling-references`.
The name should read as the thing it contains, not as the verb you used to populate it and not as a session or agent identity.
Avoid the framing-laden defaults that the underlying API offers, in particular `main_dataset` (the verb default) and anything shaped like `claude_sessions`.
Those names invite the memory-store misuse this skill rejects: a dataset called `main_dataset` carries no signal about what reference material it grounds, and a dataset named for a session implies it holds conversation state rather than curated references.
Always pass an explicit subject name rather than accepting the default.

## create vs reuse

The default is co-location: when you want connected reasoning across documents, put them in the same dataset.
The reason is mechanical rather than stylistic.
Within a dataset, cognee builds one connected cross-document graph in which the same entity mentioned in different documents collapses into a single shared node accumulating edges from every document, and that cross-document linking is the core value over plain retrieval.
Across datasets that linkage is severed: access control is on for this tenant, so each dataset lives in a physically separate graph, no edge can span datasets, and a multi-dataset recall only unions per-dataset results rather than reasoning across them (see the next section for the mechanics).
So a new dataset is not a free clean boundary; it is a hard wall that forecloses cross-corpus grounding.

Reuse or co-locate when you want a future query to consider the documents together as one connected body of evidence: add the material to the same dataset and re-run the build or enrichment pass so it joins the existing graph.
Create a separate dataset when you want genuine isolation rather than connection — independent retrieval scoping, distinct permissioning, or two genuinely unrelated bodies of material.
Separating unrelated domains also avoids spurious entity collisions, since two corpora that happen to share an entity name would otherwise merge those mentions into one node (see the resolution caveat below).
When you are unsure whether two bodies should reason together, prefer co-locating them: a shared graph keeps them linked and could later be sliced only through the raw API (see the `node_set` caveat below), whereas separate datasets cannot be relinked after the fact.

## sharing within and across datasets

A dataset is the boundary of connected reasoning, so it pays to understand exactly what links and what does not.

Within one dataset the documents form a single connected graph.
Entity nodes are keyed by a deterministic identifier derived from the normalized entity name and written so that the same name resolves to one shared node, which means an entity mentioned across several co-located documents accumulates edges from all of them.
Resolution is exact normalized-name matching by default — lowercasing, spaces to underscores, apostrophes stripped — with no fuzzy or semantic merge unless you configure an ontology.
Consistent terminology across documents therefore improves linking directly: near-synonyms and inconsistent spellings stay as separate nodes, and an ontology strengthens linking by mapping variants onto shared concepts.
See [architecture.md](architecture.md) for the underlying node-identity and merge mechanism.

Across datasets, behavior is governed by access control (`ENABLE_BACKEND_ACCESS_CONTROL`), which is confirmed on for this tenant; both the default LanceDB vector store and Ladybug graph store support it.
Each owner-and-dataset pair therefore gets a physically separate graph and vector database: no edge can span datasets, cross-dataset entity resolution is impossible, and a multi-dataset recall (passing `-d` more than once) runs each dataset in its own isolated store and concatenates the results with no cross-dataset traversal or re-ranking.
Were access control off, all datasets would instead resolve to one shared global graph where entities and edges merge and link freely, and the dataset label would stop scoping retrieval because the retriever would read the whole shared graph regardless of which dataset you name — but that is counterfactual here.

The practical upshot is that separate datasets queried together give you unioned per-corpus evidence, not connected cross-corpus reasoning; to get cross-domain graph linking you must co-locate the material in one dataset.
Subdividing within a co-located dataset would in principle use `node_set` to tag a slice of one dataset's graph and scope retrieval to it, but `node_set` is inert through the cognee CLI wrapper: there is no add, cognify, or recall flag for it, and it is reachable only through the raw REST API or `CogneeApiClient`.
Through the CLI, therefore, a co-located dataset is always queried whole; see the "Dataset partitioning and entity resolution" section of [architecture.md](architecture.md) for how `node_set` scopes a slice when you drop to the raw API.

Worked example: the `engineering-references-v2` and `modeling-references` corpora.
Co-locate them in one dataset if you want connected reasoning that grounds engineering claims in modeling material and vice versa, accepting that the two domains share one graph and that same-named entities will merge.
Keep them as two datasets if they are independent libraries you query on their own, accepting that any cross-querying is union-only and that an entity appearing in both will not be linked across them.

Access control is confirmed on for this tenant, so every dataset is a physically isolated graph and cross-dataset linking is unavailable; treat each dataset as a hard boundary rather than something to probe before relying on isolation.

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
