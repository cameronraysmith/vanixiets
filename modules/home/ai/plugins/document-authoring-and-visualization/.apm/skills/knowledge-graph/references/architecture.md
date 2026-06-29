---
name: knowledge-graph-architecture
description: Engine and design reference for cognee as a knowledge-graph index over reference corpora — the ECL pipeline, engine models, when remember decouples into add plus cognify, the living-graph refinement loop, and backend adapters.
---

# Cognee engine architecture

This is the design reference behind the knowledge-graph skill: what cognee does to a reference corpus and why the everyday verbs behave as they do.
The framing throughout is reference-corpus indexing, not conversational memory.
The verbs are named for memory (remember, recall, improve, forget), but here they ingest curated source documents, query a graph for grounding, and refine that graph — they do not store session state.

## The ECL pipeline

Cognee processes data through an extract, cognify, load pipeline (ECL), the structural replacement for the retrieve step of traditional RAG.
Extraction reads source documents and chunks them; cognify uses an LLM to pull entities and relationships out of those chunks and assemble them into a knowledge graph; load writes the resulting nodes and edges into the graph store and their embeddings into the vector store.
Concretely, an ingest of reference documents flows classify documents, extract chunks, extract graph from data (the LLM step that discovers or fills the schema), summarize, then add data points to the graph and vector backends.
The output is a typed graph of linked entities indexed against the source text, queryable both by graph traversal and by vector similarity.

## Engine models

The graph is built from a small set of conceptual primitives.
A DataPoint is the base class for every graph node — a versioned, metadata-bearing knowledge unit; entities extracted from a reference document become DataPoints.
An Edge is a directed relationship between two nodes, carrying a relationship type (source, target, name).
A Triplet is the (subject, predicate, object) shape that a subject-predicate-object view of the graph exposes, and the unit some retrievers reason over.
When you supply a custom graph model, you define your own DataPoint subclasses (for example Person, Topic, Issue) and the edges between them, constraining extraction to your domain's types rather than letting the LLM discover generic ones.

## remember is add plus cognify plus self-improvement

The cognee 1.0 surface collapses the pipeline into one verb: `remember` equals `add` plus `cognify` plus a self-improvement pass, with `self_improvement` defaulting to true.
One `remember` call ingests the text, extracts entities and relationships into the graph, and refines the graph on that write.
For everyday corpus work `remember` is the single call you need, and `cognify` is rarely invoked directly.

Reach for the lower-level `add` plus `cognify` only to decouple ingestion from graph-building.
The tutorial's "where did cognify go" note names three cases where that decoupling earns its place.
The first is bulk loading: ingest hundreds of documents with many `add` calls, then build the graph once with a single `cognify` rather than rebuilding on every document.
The second is reprocessing: re-extract existing data under a different graph model or schema without re-uploading the source, since `add` already persisted it.
The third is background builds: run the graph-construction step as a background job, decoupled from the latency of ingestion.
Absent one of these, prefer `remember`.

## The living graph

A reference graph is not a one-shot index frozen at ingest time; cognee treats it as a living structure that sharpens with use.
Three mechanisms drive refinement.
Implicit self-improvement runs on every `remember` write (the `self_improvement=True` default), refining the graph as new material lands.
The explicit loop is recall, then feedback, then `improve`, then recall: a recall surfaces grounding, feedback records a judgment of that answer's quality, `improve` (the verb that aliases the lower-level memify pipeline) folds the feedback into the graph by shifting feedback weights on the nodes an answer leaned on, and a later recall with `feedback_influence` lets those weights steer ranking.

Reframed for a reference corpus, this is graph refinement, not memory of a conversation.
The feedback being folded in is a curator's judgment about whether retrieved context was the right grounding for a source-document claim — which nodes and relationships deserve more or less weight when grounding future writing — not a record of what was said in a chat.
Over repeated use the weights re-rank retrieval toward the reference material that consistently grounds well.
This is the discipline that distinguishes the skill's use of these verbs from the session-memory use it rejects: the loop tunes an index over documents, and never captures session transcripts or reasoning traces.

## Backend adapters

Cognee writes through three interchangeable categories of backend, each behind an interface so the pipeline stays backend-agnostic.
The graph store holds the knowledge graph of DataPoints and Edges; the default is Ladybug, with Neo4j, Neptune, and Postgres as alternatives via `GraphDBInterface`.
The vector store holds embeddings for semantic retrieval; the default is LanceDB, with pgvector, ChromaDB, Qdrant, Weaviate, and Milvus available via `VectorDBInterface`.
The relational store holds dataset and data metadata and pipeline state; the default is SQLite, with PostgreSQL as the alternative.
For the wrapped SaaS surface these backends are managed server-side; the relevance here is conceptual, since a recall draws on both graph traversal and vector similarity over the same ingested corpus.

## Dataset partitioning and entity resolution

This subsection is the mechanism behind the dataset guidance in references/datasets.md: why one coherent corpus belongs in one dataset, and what a dataset boundary actually is at the engine level.

Within a dataset, the graph connects across documents by construction.
Each extracted entity's node id is a deterministic hash (a uuid5) of its normalized name, and the graph adapter upserts every node with a merge keyed on that id.
So two documents that mention the same entity resolve to the same node id and collapse into a single node carrying both documents' edges, rather than two disconnected duplicates.
The practical consequence is that ingesting a coherent body of material into one dataset yields one connected cross-document graph that a traversal can walk end to end — which is exactly why the grounding quality of GRAPH_COMPLETION depends on keeping related material together.

The resolution is name-exact, not semantic.
Normalization lowercases the name, turns spaces into underscores, and strips apostrophes, and that is the whole of the default matching: entities whose normalized names differ — synonyms, abbreviations, alternate spellings — stay separate nodes even when they denote the same thing.
Grounding the extraction in an ontology is the supported way to merge across surface forms; absent one, expect exact-name collapse and nothing more, and phrase corpora accordingly.

A dataset boundary is a runtime storage decision, not a property of the schema.
It is governed by the access-control mode, which defaults on when the configured providers support it (the LanceDB and pgvector vector backends, the Ladybug, Kuzu, FalkorDB, and Postgres graph backends).
With access control on, each (owner, dataset) pair gets its own physically separate graph and vector database, and no edge ever spans two datasets — the cross-document merge above operates strictly within one dataset's store.
With access control off, every dataset shares one global graph and datasets degrade to labels on nodes within it.
Either way the dataset is the unit a query is scoped to; the mode only decides whether that scoping is enforced by physical isolation or by filtering one shared graph.

Retrievers are dataset-unaware.
A retriever projects whatever single graph and vector database the async context has bound it to, with no dataset filter of its own — it sees one store and walks it.
Multi-dataset query under access control therefore is not a single traversal over a merged graph: the search layer runs the chosen retriever once per dataset, each in its own isolated database context, and concatenates the per-dataset results into one union.
There is no cross-dataset edge traversal and no cross-dataset re-ranking, and this holds uniformly across GRAPH_COMPLETION, RAG_COMPLETION, CHUNKS, and SUMMARIES.
The design implication is direct: connected cross-corpus reasoning requires the material to live in one dataset, because spreading it across datasets gives you a union of separate answers rather than a graph that reasons over the whole.

Within a single dataset, node_set is a finer-grained tag rather than a boundary.
It marks a slice of one dataset's graph so a query can be scoped to that subgroup, and it is set through the Python API rather than the CLI verbs documented here.
It is not a separate database and not a cross-dataset mechanism; it subdivides one dataset's graph, where dataset partitioning separates whole graphs.

## Grounding discipline

The graph is an index over source documents, not an authority in its own right.
Retrieved context is evidence indexed from the originals, and an LLM extraction or completion step sits between the source text and any recall answer — extraction can drop nuance, conflate entities, or hallucinate a relationship.
Treat recall output as a pointer back into the reference corpus, not as a citable fact.
Verify load-bearing claims against the source documents before they become assertions in a manuscript or review.
