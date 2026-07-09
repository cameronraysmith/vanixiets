---
name: cognee-cli
description: Complete command reference for the cognee CLI wrapper across all fourteen verbs, grouped by the primary 1.0 workflow, lower-level ingest/build path, and management/auxiliary surface.
---

# cognee cli reference

This reference covers all fourteen cognee verbs reachable through the `cognee` wrapper.
The verbs name themselves for memory (remember, recall, forget), but the discipline of this skill repurposes them for reference-corpus indexing: `remember` ingests curated reference documents and builds a knowledge graph, `recall` queries that graph for grounding context, `forget` deletes data, and `improve` enriches the graph.
For choosing a query type with `-t`, see references/search-types.md; for dataset naming and lifecycle rules, see references/datasets.md.

## the wrapper

The `cognee` command on PATH is a thin shell wrapper around upstream `cognee-cli`.
It bakes the hosted SaaS `--api-url` (the CLI has no environment fallback for it) and supplies `--api-key` by reading a sops-nix secret at runtime, so no plaintext key enters the nix store.
Both baked flags precede `"$@"` because the CLI declares them on the top-level parser, ahead of the subcommand token.
The wrapper also sets `LOG_LEVEL=ERROR` and `COGNEE_LOG_FILE=false` to keep output quiet, and forwards every subcommand with no allowlist.
You can override the quiet default per-invocation by prefixing the command with a higher log level to surface more of cognee's logging when troubleshooting a particular task, for example `LOG_LEVEL=INFO cognee --help` (the prefix applies to any subcommand, such as `LOG_LEVEL=INFO cognee recall ...`).
You invoke it bare: `cognee remember ...`, `cognee recall ...`, and so on.

The raw, unwrapped `cognee-cli` is also on PATH as an escape hatch for ad-hoc work.
Reach for it when you need local file-based databases, a different `--api-url`, a `--api-token` Bearer credential, or an explicit `--user-id` rather than the SaaS key-scoped default.

The deployed pin is cognee-nix tag cognee-v112.
Flags can drift between releases, so verify any verb's surface with `cognee <verb> --help` before relying on a flag documented here.

## primary 1.0 workflow

These four verbs are the everyday surface: ingest and build with `remember`, query with `recall`, enrich with `improve`, and delete with `forget`.

`remember` ingests data and builds the graph in one call (it equals `add` plus `cognify` plus a self-improvement pass, with `self_improvement` defaulting on).
It takes a single dataset.

```
cognee remember ./engineering-references/*.md -d engineering-references
cognee remember notes.md -d modeling-references --chunker TextChunker --chunk-size 1024
cognee remember big-corpus/ -d engineering-references -b
```

Flags: `-d/--dataset-name` (single dataset, default `main_dataset` — override it, see references/datasets.md), `--chunker {TextChunker,LangchainChunker,CsvChunker}`, `--chunk-size`, `--chunks-per-batch`, `-b/--background`.

`recall` queries the graph for grounding context and returns a synthesized answer by default.

```
cognee recall "What does the corpus say about hexagonal architecture?" -d engineering-references
cognee recall "summarize the modeling conventions" -d modeling-references -t SUMMARIES -k 5 -f pretty
```

Flags: `-t/--query-type` (default `GRAPH_COMPLETION`; see references/search-types.md for choices), `-d/--datasets` (multiple), `-k/--top-k` (default 10, max 100), `-f/--output-format {json,pretty,simple}` (default `pretty`), `--system-prompt`, and `-s/--session-id`.

Passing several `-d` datasets unions their results: the query runs once per dataset and the answers are concatenated.
Under access control (the likely default) the per-dataset graphs are physically separate, so there is no cross-dataset graph traversal — material that must be reasoned over as one connected corpus has to live in a single dataset, not be split across several.
See references/datasets.md for the dataset-design consequence and references/architecture.md for the mechanism.

Omit `-s` for reference grounding.
Passing `-s <session-id>` routes the query against session conversation cache (the Q&A memory surface) rather than treating the corpus as a clean reference index, which is precisely the session-memory use this skill rejects.
Leave it off so the recall draws only on the indexed reference graph.

`improve` runs an explicit enrichment pass over an existing graph, optionally folding in session feedback.

```
cognee improve -d engineering-references
cognee improve -d modeling-references --feedback-alpha 0.8 -s <session-id>
```

Flags: `-d/--dataset-name` (default `main_dataset`), `--dataset-id`, `--node-name`, `-s/--session-ids`, `--feedback-alpha` (default 0.1), `-b/--background`.

`forget` removes data from the graph at either dataset or single-item granularity.

```
cognee forget --dataset engineering-references
cognee forget --dataset-id <dataset_id> --data-id <data_id>
```

Flags: `--dataset` (dataset name), `--dataset-id` (dataset UUID), `--data-id` (UUID of one data item), `--everything`.
Pass `--dataset` or `--dataset-id` alone to delete a whole dataset, add `--data-id` to that to delete a single item within it, or pass `--everything` to delete all of the user's data.
`--data-id` is the CLI's only per-item deletion path (`delete` has no item-level flag) and it requires `--dataset` or `--dataset-id`, since the item is addressed within a dataset; passing `--data-id` on its own errors.
Recover a `data_id` from `cognee datasets data <dataset_id>`, whose ID column is exactly the per-item UUID that `forget --data-id` consumes.
A targeted `cognee forget --dataset-id <dataset_id> --data-id <data_id>` removes only that one item and leaves the dataset's other items intact.
The README shows `forget --all`, but the real flag is `--everything`; never pass it without explicit instruction (see Hygiene below).

## lower-level ingest/build

Reach for `add` plus `cognify` to decouple ingestion from graph-building.
This is the recommended path for bulk corpus loads: issue many `add` calls to upload documents, then run `cognify` once to build the graph over the accumulated data, or re-process existing data with a different schema without re-uploading.

`add` ingests data without building the graph.

```
cognee add ./engineering-references/a.md -d engineering-references
cognee add ./engineering-references/b.md -d engineering-references
```

Flags: `-d/--dataset-name`.
Each `add` reports its ingested items inline, and every item carries a content-addressed `data_id` (a uuid5 over the item's content) at `data_ingestion_info[].data_id` in the response.
Because the id is content-addressed, re-adding byte-identical content is a no-op that returns the same `data_id`, while changed content yields a new `data_id` and leaves the prior item in place until it is forgotten.
That `data_id` is what `forget --data-id` targets for a single-item delete, and it can also be recovered later from `cognee datasets data <dataset_id>`.

`cognify` transforms the ingested data into the knowledge graph, over one or more datasets at once.

```
cognee cognify -d engineering-references
cognee cognify -d engineering-references -d modeling-references --chunker TextChunker -b
```

Flags: `-d/--datasets` (multiple), `--chunker {TextChunker,LangchainChunker,CsvChunker}`, `--ontology-file`, `--chunk-size`, `--chunks-per-batch`, `-b/--background`.

`search` queries the graph without any session surface (it is session-free; there is no `-s` flag).

```
cognee search "What grounding does the corpus offer on event sourcing?" -d engineering-references
cognee search "list the relevant chunks" -t CHUNKS -d modeling-references -k 8 -f json
```

Flags: `-t/--query-type` (see references/search-types.md), `-d/--datasets` (multiple), `-k/--top-k`, `-f/--output-format {json,pretty,simple}`, `--system-prompt`.
Use `search` rather than `recall` when you want graph grounding with no session involvement at all; `recall` with `-s` omitted is equivalent for the grounding case, while `recall` exposes the optional session path that `search` lacks.

`memify` runs the memory-enrichment pipeline that `improve` aliases.

```
cognee memify -d engineering-references
```

It is the lower-level entry point to the same enrichment `improve` wraps; prefer `improve` unless you need the underlying pipeline directly.

## management and auxiliary

`datasets` manages dataset lifecycle.

```
cognee datasets list
cognee datasets create engineering-references
cognee datasets status <dataset_id>
cognee datasets data <dataset_id>
cognee datasets graph <dataset_id>
cognee datasets delete <dataset_id>
```

Subcommands: `list`, `create`, `data`, `status`, `graph`, `delete`.
Only `create` takes a dataset name; `data`, `status`, `graph`, and `delete` take a dataset UUID (`dataset_id`), not a name, so obtain the id with `cognee datasets list` first and pass it in place of `<dataset_id>`.
`status` accepts one or more ids; `graph` takes `-o/--output` to write the JSON export to a file; `delete` takes `-f/--force` to skip confirmation.
`data` lists a dataset's items as rows with an ID column (the per-item `data_id` UUID), a Name column (the source filename), and Type and Created columns, so it is how you map a source filename back to the `data_id` that a targeted `forget --data-id` needs.
Under the wrapped SaaS surface the Type and Created columns come back empty and no content-hash column is exposed, so an item's content-addressed identity is visible only through its `data_id`.
See references/datasets.md for naming and when to create versus reuse.

`config` manages configuration settings.

```
cognee config get
cognee config list
cognee config set <key> <value>
cognee config unset <key>
cognee config reset
```

Subcommands: `get`, `set`, `list`, `unset`, `reset`.
`set` takes a `key value` pair; `list` enumerates the available configuration keys; both `unset` and `reset` accept `-f/--force` to skip the confirmation prompt.

`delete` removes a dataset's data.

```
cognee delete -d engineering-references
cognee delete -d engineering-references -f
cognee delete --all
```

Flags: `-d/--dataset-name`, `--all`, `-f/--force`.
`delete` operates at dataset granularity only — a named dataset, or every dataset with `--all` — and has no per-item flag; single-item removal lives under `forget --data-id` instead.
`--all` deletes all data across every dataset and requires confirmation; treat it with the same caution as `forget --everything` and never pass it without explicit instruction (see Hygiene below).

`serve` connects to a cognee instance, cloud or local.

```
cognee serve
```

`sessions` views conversation sessions and Q&A history.
It is a subcommand group: a bare `cognee sessions` errors with "No action specified", so invoke the `get` action.

```
cognee sessions get [<session_id>] [-n N] [-f {pretty,json}]
```

The positional `session_id` is optional (defaulting to the current `--user-id` scope); `-n/--last-n` returns only the last N entries, and `-f/--format` selects `pretty` (default) or `json`.

`feedback` adds or removes feedback on session Q&A entries, feeding the `improve` feedback loop.
It is a subcommand group with `add` and `delete`, each taking positional `session_id` and `qa_id`.

```
cognee feedback add <session_id> <qa_id> -t "useful answer" -s 1
cognee feedback delete <session_id> <qa_id>
```

`add` attaches feedback and requires at least one of `-t/--text` or `-s/--score` (an integer); `delete` clears feedback from the entry.

`sessions` and `feedback` together form the session-Q&A surface.
They are the conversation-memory side of cognee and are not the reference-grounding focus of this skill.
They are documented here for completeness; the feedback path is relevant only when deliberately steering `improve` with rated answers, not for indexing or querying reference corpora.

## hygiene

Never ingest secrets, `.env` files, API keys, `*.sqlite` or `*.db` databases, `node_modules`, or build output into any dataset; inspect candidate material with `rg --files` first to see what would be swept in.
Confirm with the operator before any `delete` or `forget`.
Never pass `forget --everything` without explicit instruction.
When in doubt about a verb's current flags under the cognee-v112 pin, run `cognee <verb> --help` to verify before relying on it.
