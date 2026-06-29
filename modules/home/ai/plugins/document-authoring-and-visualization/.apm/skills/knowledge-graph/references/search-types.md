---
name: search-types
description: retrieval-mode selection guide for recall and search over a reference-corpus knowledge graph, covering the six SearchType choices and when each grounds a technical-writing or review task
---

# retrieval modes for grounding

`recall` and `search` both take `-t/--query-type` to select how the graph is queried.
The six choices come from `SEARCH_TYPE_CHOICES` in the cognee CLI config: GRAPH_COMPLETION (default), RAG_COMPLETION, CHUNKS, SUMMARIES, CODE, CYPHER.
The mode you pick determines whether you get a synthesized answer, raw passages, an orientation pass over a collection, or a direct structural query.
For grounding a technical document you usually want either GRAPH_COMPLETION (for a synthesized answer that traverses related entities) or CHUNKS (for the exact passages you will cite).

These verbs query whatever you previously ingested with `remember` or `add`+`cognify`; the retrieved context is evidence indexed from your source documents, not authoritative truth.
Verify load-bearing claims against the originals before they go into the manuscript.

## choosing a mode

| mode | returns | reach for it when |
|---|---|---|
| GRAPH_COMPLETION | an LLM answer synthesized from a graph traversal across related entities and their connections | you want a grounded synthesis that pulls together facts spread across several reference documents, e.g. framing a section or sanity-checking a claim against the whole corpus |
| RAG_COMPLETION | a classic chunk-RAG answer: top chunks retrieved by similarity, then an LLM completion over them | you want an answer driven by passage similarity alone, without the graph structure, e.g. a quick lookup where entity relationships do not matter |
| CHUNKS | the raw matching text passages, no LLM synthesis | you need exact source text to quote or cite, or you want to read the evidence yourself before trusting any synthesized answer |
| SUMMARIES | pre-computed summaries of the ingested documents | you are orienting over an unfamiliar collection and want the gist of what it contains before drilling in |
| CODE | code-aware retrieval over a code corpus | the dataset is source code (ingested for code grounding) rather than prose references |
| CYPHER | results of a direct graph query expressed against the underlying graph | you know the graph shape and want a precise structural answer rather than a natural-language synthesis |

For a typical writing-or-review loop over prose references, start with GRAPH_COMPLETION to orient and synthesize, then switch to CHUNKS to pull the exact passages behind any claim you intend to cite.
SUMMARIES is the lightweight first pass when you do not yet know a collection well enough to ask a sharp question.

Whatever mode you pick, passing multiple `-d` datasets applies that mode per dataset and unions the results; under access control there is no cross-dataset traversal, so keep material you need reasoned over together in one dataset (see references/datasets.md).

## explicit type for deterministic grounding

`recall` auto-routes when `-t` is omitted, choosing a mode for you.
`search` requires an explicit `-t` and does not auto-route.
For reproducible grounding, pass `-t` explicitly on both verbs so the retrieval mode is deterministic and your evidence trail is auditable rather than dependent on auto-routing.

## top-k and output format

`-k/--top-k` bounds how many results feed the answer; it defaults to 10 and is capped at 100.
Raise it when a question spans many documents and you want broader coverage; keep it small when you want only the most relevant passages.

`-f/--output-format` accepts json, pretty, or simple.
Use json when you are extracting citations programmatically or piping results into another tool; use pretty or simple for reading at the terminal.

Flags drift across releases (the deployed pin is tag cognee-v112).
Confirm a verb's current flags with `cognee recall --help` or `cognee search --help` before relying on them.
