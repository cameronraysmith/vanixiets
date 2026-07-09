---
name: ingestion-workflow
description: Worked-example runbook for populating reference corpora into cognee datasets via the bulk add-then-cognify path, then querying the graph for grounding context.
---

# ingestion workflow

This runbook walks two real corpora from empty to queryable and shows how to use the resulting graphs as grounding context while writing or reviewing a technical manuscript.
The targets are `engineering-references-v2` (writing and architecture craft) and `modeling-references` (the scientific subject matter), and the intended consumer is `/Users/crs58/projects/hodosome-workspace/hodosome/docs/manuscript/manuscript.qmd`, a paper on stochastic dynamical modeling and inference of gene-regulatory network architecture.

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
Issue many `cognee add <paths...> -d <dataset>` calls to stage all the documents, then a single `cognee cognify -d <dataset> --background` to build the graph over the whole staged set once.
Prefer the long `--background` flag over `-b`: it returns immediately and lets the build run server-side, which is what you want for a corpus-sized job.
This is one build instead of N, no per-document self-improvement, and a clean separation that also lets you re-run cognify later with a different chunker or ontology without re-staging the data.
Run `improve` afterward, once, if you want the enrichment pass.

## scope what you ingest

The two corpora are subtree aggregates of `/doc-to-md` conversions, and each reference directory now holds several representations of the same source rather than a single markdown file.
A reference directory carries the consolidated `<ref>.md` alongside a redundant re-chunked `sections/` (or `chapters/`) tree, README stubs, `_meta.json` sidecars, and the source PDFs.
Adding the directory would double-ingest the chunk duplicates against the consolidated file and sweep in the non-prose, so never stage a reference directory wholesale.
Stage the single resolved consolidated file per reference instead, and ingest that prose alone — never the PDFs, the `sections/` re-chunks, the `_meta.json` sidecars, the README stubs, or git-lfs binaries.

The consolidated file's path shape is not uniform, so resolve it per reference rather than assuming one glob.
It appears as `<ref>/<ref>.md`, as a doubly-nested `<ref>/<ref>/<ref>.md`, or under a renamed or space-bearing stem, and a book-sized reference is staged as its `<ref>-partNN` parts instead (see the size rule below).
Survey before staging so you see exactly which consolidated file each reference resolves to:

```bash
rg --files /Users/crs58/projects/modeling-workspace/modeling-references -g '*.md'
```

Inspect that list and stage only the resolved consolidated file (or the `<ref>-partNN` parts) for each reference, at no more than 30 paths per `add` call.
Exclude everything that is not a consolidated reference: the `sections/` (or `chapters/`) re-chunk trees, top-level `README.md` index files, README stubs, token-count reports, and any `.scripts/` helpers.
Never stage secrets, `.env`, key material, `*.sqlite`, `*.db`, `node_modules`, or build output; none belong in a reference corpus and a careless glob is the usual way they leak in.
When in doubt, narrow the glob and re-run `rg --files` rather than widening it.
`add` is synchronous and content-addressed, so re-adding identical content is a no-op — an interrupted staging run is safe to repeat.

Classify each reference by the byte size of its consolidated text and stage it accordingly.
A reference whose consolidated text is at most 200KB (~200,000 bytes) is a paper: ingest it whole as a single `<ref>` item.
A reference larger than 200KB is a book: part-concat it at chapter boundaries — or, when there is no clean chapter tree, split the consolidated file at line boundaries — into parts of at most 200KB each, named `<ref>-partNN` with contiguous zero-padded numbers.
When splitting a book, drop the table of contents (`00-index.md`, `01-contents.md`), the back-of-book index, and any part-divider stub under 200 bytes, while keeping front-matter, content chapters, glossaries, and appendices.

The `add` lists in the two staging sections below are illustrative snippets, not the ingestion scope.
The real corpora are roughly 90 modeling references and 12 engineering references, each resolved to its consolidated file or its book parts by the survey above.

## stage and build: modeling-references

The `modeling-references` dataset does not exist yet, so create it, then stage the resolved consolidated file per reference, then build once in the background.

```bash
cognee datasets create modeling-references

cognee add \
  /Users/crs58/projects/modeling-workspace/modeling-references/herbach-2017-mechanistic-grn-inference/herbach-2017-mechanistic-grn-inference.md \
  /Users/crs58/projects/modeling-workspace/modeling-references/ventre-2023-one-model-fits-all/ventre-2023-one-model-fits-all.md \
  /Users/crs58/projects/modeling-workspace/modeling-references/gorin-2022-rna-velocity-unraveled/gorin-2022-rna-velocity-unraveled.md \
  -d modeling-references

cognee add \
  /Users/crs58/projects/modeling-workspace/modeling-references/cao-2020-analytical-stochastic-gene-expression/cao-2020-analytical-stochastic-gene-expression.md \
  /Users/crs58/projects/modeling-workspace/modeling-references/ion-2021-tensor-train-cme/ion-2021-tensor-train-cme.md \
  -d modeling-references

cognee cognify -d modeling-references --background
```

Each staged path is the reference's single resolved consolidated file, not the reference directory, and a book-sized reference is staged as its `<ref>-partNN` parts instead.
Group the `add` calls however is convenient (up to 30 paths each); what matters is that every staged path lands in the same dataset and that `cognify` runs once over the whole set.
Confirm the build finished before querying with `cognee datasets status <UUID>`, where `<UUID>` is the dataset's UUID rather than its name (see the verification section below).

## stage and build: engineering-references-v2

The `engineering-references-v2` dataset is already populated — 12 distinct references / 50 items, `DATASET_PROCESSING_COMPLETED` — so this section documents the shape of that load rather than a step to re-run.
The plain `engineering-references` name was abandoned: it held a failed giant-concat representation that was re-coalesced into `engineering-references-v2`, which is why the `-v2` suffix is load-bearing and the unsuffixed name should not be reused.
To extend it, stage the resolved consolidated file per reference (or its `<ref>-partNN` parts) into the existing dataset and re-run cognify.

```bash
cognee add \
  /Users/crs58/projects/planning-workspace/engineering-references/domain-modeling-made-functional/domain-modeling-made-functional.md \
  /Users/crs58/projects/planning-workspace/engineering-references/fundamentals-of-software-architecture/fundamentals-of-software-architecture.md \
  /Users/crs58/projects/planning-workspace/engineering-references/majors-2022-observability-engineering/majors-2022-observability-engineering.md \
  -d engineering-references-v2

cognee cognify -d engineering-references-v2 --background
```

Keep the two corpora in separate datasets: they are distinct bodies of material, queried in isolation for different purposes, and a new dataset is the default bias when material is a distinct body.

## verify population before querying

After kicking off a background build, confirm it finished and that every expected item actually landed.
First poll the build state, then enumerate the dataset's items:

```bash
cognee datasets status <UUID>
cognee datasets data <UUID>
```

Both `datasets status` and `datasets data` require the dataset UUID, not the name: passing the name returns an HTTP 422 `uuid_parsing` error, whereas `add` and `cognify` accept the name directly.
Resolve the UUID once with `cognee datasets list`, then reuse it for both subcommands.
`datasets data` has no pagination flags and returns the full item set in one call.
Read that full listing and confirm each expected `<ref>` (or `<ref>-partNN`) item is present, re-reading until the count is stable: a read taken mid-build can show a truncated subset, so a single read is not proof of completeness.

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
  -d engineering-references-v2 -f pretty
```

For a tighter passage-level lookup rather than graph-completion synthesis, use `search` with a chunk retrieval type:

```bash
cognee search \
  "chemical master equation analytical distribution transcriptional bursting" \
  -t CHUNKS -d modeling-references -k 5 -f pretty
```

Use `recall`/`search` against `modeling-references` for the manuscript's scientific claims and against `engineering-references-v2` for how it is written and structured.
Extend either corpus later with more `add` calls followed by a single re-run of `cognify`, and run `improve` when you want an enrichment pass over the accumulated graph.
