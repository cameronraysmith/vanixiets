---
name: knowledge-graph
description: Index curated reference corpora into a searchable knowledge graph via the cognee engine, then query it to ground technical writing, review, and analysis. Use when ingesting reference documents into named datasets or retrieving grounding context for tasks like drafting or reviewing a manuscript. A reference-knowledge index, explicitly not agent session memory.
---

# Knowledge graph for reference grounding

## Mental model

Treat cognee as a searchable, semantically-indexed reference library built over a corpus you curate by hand.
You ingest chosen reference documents into named datasets, build a knowledge graph across them, and query that graph for grounding context when writing or reviewing sophisticated technical material.
The 1.0 API verbs are named for memory (remember, recall, improve, forget), but here they index and query a reference corpus, not session state.
Despite the names, remember ingests reference docs and builds the graph, recall queries it for grounding, improve enriches it, and forget deletes data.
The discipline lives in what you ingest (curated references) and why you query (grounding), not in avoiding the verb names.
This engine has zero relation to AI-agent session memory: it does not store conversations, reasoning traces, or chat history.
Throughout this skill and its references, retrieved context is evidence indexed from source documents, and load-bearing claims must be verified against the originals.

## When to use, when not

Reach for this skill when you are populating a reference dataset or pulling grounding context for a task such as drafting or reviewing `manuscript.qmd`.
Do not use it as session memory.
Three anti-patterns to reject: asking cognee to "store this conversation so it remembers next session"; auto-capturing tool calls or reasoning traces into a dataset; and using `recall -s <session-id>` to fetch prior chat history.
Those are the memory use we explicitly do not adopt; the session-Q&A surface (`sessions`, `feedback`) exists but is not the reference-grounding focus.

## Core lifecycle

The everyday path uses `remember` (ingest plus build plus self-improvement) then `recall`.
For bulk corpus loads, decouple ingest from build: many `add` calls, then one `cognify`, then `search`.
The wrapper is invoked bare as `cognee` and targets the SaaS platform; verify a verb's flags with `cognee <verb> --help` (deployed pin is tag `cognee-v112`).

```bash
# everyday: ingest references and build the graph, then query for grounding
cognee remember ./refs/*.md -d engineering-references
cognee recall "what does the corpus say about X" -d engineering-references

# bulk: decouple ingest from build, then query
cognee add ./refs/part-a.md -d modeling-references
cognee add ./refs/part-b.md -d modeling-references
cognee cognify -d modeling-references
cognee search "grounding question" -d modeling-references
```

## References

| Reference | Covers |
|---|---|
| references/cognee-cli.md | running cognee — all 14 verbs, flags, raw cognee-cli escape hatch |
| references/datasets.md | dataset naming and boundaries, lifecycle, hygiene |
| references/search-types.md | choosing a recall/search retrieval mode (-t) |
| references/ingestion-workflow.md | populating engineering-references / modeling-references end-to-end |
| references/architecture.md | ECL pipeline, engine model, remember = add + cognify + self-improvement, when to decouple |
