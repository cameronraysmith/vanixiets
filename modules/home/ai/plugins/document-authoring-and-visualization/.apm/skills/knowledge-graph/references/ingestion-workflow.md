---
name: ingestion-workflow
description: Worked-example runbook for populating reference corpora into cognee datasets via the bulk add-then-cognify path, then querying the graph for grounding context.
---

# ingestion workflow

This runbook walks two real corpora from empty to queryable and shows how to use the resulting graphs as grounding context while writing or reviewing a technical manuscript.
The targets are `engineering-references` (writing and architecture craft) and `modeling-references` (the scientific subject matter), and the intended consumer is `/Users/crs58/projects/hodosome-workspace/hodosome/docs/manuscript/manuscript.qmd`, a paper on stochastic dynamical modeling and inference of gene-regulatory network architecture.

Throughout, ingestion means indexing curated reference documents, not capturing session state.
The verbs are named for memory but used for reference-corpus indexing; the discipline is in what you ingest and why you query.
All commands use the quiet `cognee` wrapper and match the flags documented in `cognee-cli.md`.
The deployed pin is `cognee-v112`; verify any verb's flags with `cognee <verb> --help` before a large run.

## why bulk add-then-cognify, not per-doc remember

`remember` is the everyday verb: it runs add, then cognify, then self-improvement in one shot per call.
That is the right tool for a handful of documents or for incrementally extending a dataset.
For a large corpus it is the wrong shape.
Each `remember` triggers a graph build and a self-improvement pass, so ingesting dozens of references one at a time rebuilds the graph dozens of times and pays the self-improvement cost on every call.

The lower-level path decouples ingest from build.
Issue many `cognee add <paths...> -d <dataset>` calls to stage all the documents, then a single `cognee cognify -d <dataset> -b` to build the graph over the whole staged set once.
The `-b/--background` flag returns immediately and lets the build run server-side, which is what you want for a corpus-sized job.
This is one build instead of N, no per-document self-improvement, and a clean separation that also lets you re-run cognify later with a different chunker or ontology without re-staging the data.
Run `improve` afterward, once, if you want the enrichment pass.

## scope what you ingest

The two corpora are subtree aggregates of `/doc-to-md` conversions: each subdirectory holds modular markdown sections alongside source PDFs and token-count files.
The READMEs list the references whose full markdown is what gets ingested; ingest the markdown, never the PDFs or git-lfs binaries.

Survey before staging so you ingest prose and nothing else:

```bash
rg --files /Users/crs58/projects/modeling-workspace/modeling-references -g '*.md'
```

Inspect that list and exclude anything that is not a reference section: top-level `README.md` index files, token-count reports, and any `.scripts/` helpers.
Never stage secrets, `.env`, key material, `*.sqlite`, `*.db`, `node_modules`, or build output; none belong in a reference corpus and a careless glob is the usual way they leak in.
When in doubt, narrow the glob and re-run `rg --files` rather than widening it.

## stage and build: modeling-references

The `modeling-references` dataset does not exist yet, so create it, then stage the reference markdown, then build once in the background.

```bash
cognee datasets create modeling-references

cognee add \
  /Users/crs58/projects/modeling-workspace/modeling-references/herbach-2017-mechanistic-grn-inference \
  /Users/crs58/projects/modeling-workspace/modeling-references/ventre-2023-one-model-fits-all \
  /Users/crs58/projects/modeling-workspace/modeling-references/gorin-2022-rna-velocity-unraveled \
  -d modeling-references

cognee add \
  /Users/crs58/projects/modeling-workspace/modeling-references/cao-2020-analytical-stochastic-gene-expression \
  /Users/crs58/projects/modeling-workspace/modeling-references/ion-2021-tensor-train-cme \
  -d modeling-references

cognee cognify -d modeling-references -b
```

Group the `add` calls however is convenient; what matters is that every staged path lands in the same dataset and that `cognify` runs once over the whole set.
Use `cognee datasets status modeling-references` to confirm the build finished before querying.

## stage and build: engineering-references

The `engineering-references` dataset is already created but unpopulated, so skip the create step and stage straight into it.

```bash
cognee add \
  /Users/crs58/projects/planning-workspace/engineering-references/domain-modeling-made-functional \
  /Users/crs58/projects/planning-workspace/engineering-references/fundamentals-of-software-architecture \
  /Users/crs58/projects/planning-workspace/engineering-references/majors-2022-observability-engineering \
  -d engineering-references

cognee cognify -d engineering-references -b
```

Keep the two corpora in separate datasets: they are distinct bodies of material, queried in isolation for different purposes, and a new dataset is the default bias when material is a distinct body.

## query for grounding

Once both graphs are built, query them for grounding context before drafting or reviewing a manuscript section.
Retrieved context is evidence indexed from the source documents; verify any load-bearing claim against the originals before it goes into the manuscript.
Omit any session flag — these are graph-grounding queries, not chat-history lookups.

Ground a methods section against the modeling corpus:

```bash
cognee recall \
  "How do mechanistic stochastic models infer gene-regulatory network structure from single-cell data?" \
  -d modeling-references -f pretty
```

Ground writing and architecture craft against the engineering corpus:

```bash
cognee recall \
  "What makes a domain model express invariants through types rather than runtime checks?" \
  -d engineering-references -f pretty
```

For a tighter passage-level lookup rather than graph-completion synthesis, use `search` with a chunk retrieval type:

```bash
cognee search \
  "chemical master equation analytical distribution transcriptional bursting" \
  -t CHUNKS -d modeling-references -k 5 -f pretty
```

Use `recall`/`search` against `modeling-references` for the manuscript's scientific claims and against `engineering-references` for how it is written and structured.
Extend either corpus later with more `add` calls followed by a single re-run of `cognify`, and run `improve` when you want an enrichment pass over the accumulated graph.
