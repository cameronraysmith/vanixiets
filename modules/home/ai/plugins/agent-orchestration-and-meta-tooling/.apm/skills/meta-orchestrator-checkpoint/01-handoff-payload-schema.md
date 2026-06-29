# Handoff payload schema

Explicit schema for the handoff payload that `/meta-orchestrator-checkpoint` produces and that `/meta-orchestrator-initiate` consumes.
Load when authoring a handoff payload (in checkpoint) or when parsing one (in initiate).

## Format

The payload is a single markdown file with YAML frontmatter.
The frontmatter carries machine-parseable header fields (variant marker, mission slug, timestamps, paths); the body carries narrative content (mission frame, per-pair synthesis, cross-pair synthesis, open threads, calibration data).

Path convention: `${CLAUDE_JOB_DIR}/handoff/meta-orchestrator-payload.md` (primary); `~/.claude/jobs/manual-handoff/meta-orchestrator-payload.md` (fallback).

## Schema

### Frontmatter (required)

```yaml
---
variant: handoff | closure
mission-slug: <kebab-case identifier>
created: <ISO 8601 timestamp>
master-observation-log: <absolute path>
parent-mission: <optional: prior payload path if this is a continuation>
---
```

### Body sections (markdown)

Each section uses a level-2 heading; subsections use level-3.

#### Mission frame

Mission frame summary durable across master replacements:

- Goal / Epic / project framing (one paragraph)
- Addendum: target repos, deliverable shape, success criteria, observation expectations
- Original user directive (verbatim, in a quoted block, for canonical reference)

#### Pair enumeration

One subsection per AC↔WO pair (active, retired, or completed), in order of spawn.

Required per pair:

- *Pair identity*: `team_name`, AC name, WO name
- *Stream*: stream slug, target repo, jj chain lineage
- *Status*: `active` / `retired` / `completed`
- *Session-checkpoint pointer* (retired pairs only): absolute path to the AC's `/session-checkpoint` output; absolute path to the WO's `/session-checkpoint` output (if WO produced one)
- *Deliverables*: commits landed, PRs created or merged (with URLs in closure variant), artifacts shipped via dependency map
- *Surprise observed*: divergence between strategic frame and execution; honest assessment
- *Design decisions captured*: architectural choices, calibration thresholds, conventions established
- *Goal-2 insights*: parameterization candidates, friction patterns, emergent regularities surfaced by this pair

#### Cross-pair synthesis

Mission-level emergent patterns:

- *Emergent friction patterns* that recurred across multiple pairs
- *Cross-stream coordination assessment*: dependency map effectiveness, supersession events, decomposition adjustments
- *Parameterization candidates*: thresholds, defaults, or conventions in the orchestrator skills the mission's experience suggests revising

#### Open threads and in-flight work

(Required in handoff variant; empty or near-empty in closure variant.)

- *Active pairs at checkpoint time*: per-pair current action, in-flight surface-ups, next action
- *Cross-stream dependency map state*: current rows with status (pending / in-flight / delivered); new rows since decomposition
- *Outstanding gate evaluations*: tier-2 elevation candidates pending; decomposition-ratification revisits pending
- *User-side open items*: authorizations / clarifications / deferred decisions awaiting user

#### Calibration data

Parameterization-calibration data from mission execution:

- Mitigations that fired and frequency (of the five turn-ordering mitigations)
- Heuristic threshold outcomes (longevity budget actual vs target; interim-surface-up threshold; ambiguity threshold)
- Stream-novelty assessments vs actuals (per pair)
- Six-point gate rubric fires (which criteria halted)
- AC five-condition surface protocol distribution (which conditions fired)

#### Closure-only sections (closure variant only)

- *Per-stream merged-PR list*: one entry per stream with PR URL, merged-at timestamp, merger
- *Deferred follow-up items*: each with title, rationale for deferral, recommended next-mission entry point

## Variant differences

| Field / Section | Handoff | Closure |
|---|---|---|
| frontmatter `variant` | `handoff` | `closure` |
| Mission frame | Required | Required |
| Pair enumeration | Required (all statuses) | Required (all `retired` or `completed`) |
| Cross-pair synthesis | Required | Required |
| Open threads and in-flight work | Required (load-bearing) | Empty or "none" |
| Calibration data | Required | Required |
| Per-stream merged-PR list | Optional | Required |
| Deferred follow-up items | Optional | Required |

## Embed vs reference for ephemeral artifacts

Pointers to artifacts under `${CLAUDE_JOB_DIR}` — per-AC `/session-checkpoint` outputs, observation logs, spawn prompts, in-flight surface-up drafts — are best-effort references rather than durable storage, because that directory is ephemeral and silently swept between sessions.
Canonical content that the next master needs to act on MUST be embedded verbatim in the payload body, not only referenced by path: ratified design decisions, mission-frame summaries and addendum, in-flight surface-up text the resuming master must respond to, and any open-thread artifact whose loss would erase meaning rather than convenience.
Rule of thumb: if losing the referenced file between checkpoint and resumption would lose meaning the next master needs to reconstruct, embed it; if losing the file would only sacrifice convenience or audit trail, a reference suffices.

## Worked example (handoff variant, abbreviated)

```markdown
---
variant: handoff
mission-slug: ironstar-analytics-rollout
created: 2026-05-13T16:30:00-07:00
master-observation-log: /Users/example/.claude/jobs/abc123/observations/master-orchestrator.md
---

## Mission frame

Roll out the analytics dashboard scaffold to ironstar with two parallel streams: data-pipeline integration in stream-α (lakescope queries via async-duckdb) and presentation-layer in stream-β (echarts + vega-lite via datastar-rust hypermedia). Success criteria: end-to-end render of one chart from omicslakehouse SCOO data; both streams' PRs merged to main.

User directive verbatim: "Get the analytics scaffold rendering one real chart from SCOO data; two parallel streams, integrate independently as ready."

## Pair enumeration

### ironstar-analytics-α

- team_name: ironstar-analytics-rollout
- AC: ironstar-α-ac, WO: ironstar-α-wo
- Stream: data-pipeline, repo /Users/example/projects/ironstar, jj chain stream-alpha
- Status: retired
- AC checkpoint: /Users/example/.claude/jobs/abc123/observations/ironstar-α-ac-checkpoint.md
- WO checkpoint: /Users/example/.claude/jobs/abc123/observations/ironstar-α-wo-checkpoint.md
- Deliverables: 12 commits; async-duckdb integration shipping query API to stream-β via dependency map
- Surprise: 0.4 — async-duckdb caching pattern needed redesign mid-stream; recovered via discovery-mode checkpoint
- Design decisions: cache layer is per-query-hash rather than per-table; query-builder DSL adopted
- Goal-2 insights: stream-novelty assessment was correct (high-novelty); first-cycle calibration caught a return-contract gap

### ironstar-analytics-β

- (analogous structure)
- Status: active
- Current action: implementing echarts integration; awaiting stream-α's query API contract finalization

## Cross-pair synthesis

Friction pattern: dependency map updated twice mid-mission as stream-β surfaced new artifact needs; both updates handled cleanly via master-routed coordination.

Cross-stream coordination assessment: dependency map served well; one supersession event (user revised success criteria to include vega-lite as second renderer); enumerate-and-propagate procedure fired across both streams.

Parameterization candidates: spawn-prompt template's WO bootstrap section may want explicit dependency-map-aware first-action phrasing.

## Open threads and in-flight work

- Active pair: ironstar-analytics-β; current surface-up pending master response on echarts vs vega-lite renderer priority
- Dependency map: row "stream-α query API contract finalization" in-flight; expected delivery by 2026-05-14
- Outstanding gate evaluations: stream-α tier-2 elevation pending after dependency map row delivers
- User-side open items: renderer priority adjudication (echarts vs vega-lite as primary)

## Calibration data

- Mitigations fired: master-supersession-marking (1×); accept-and-absorb (2×); AC inbox-recheck (every cycle, AC reports)
- Longevity budget: ironstar-α-ac used ~18% per cycle (within 15-20% target); ironstar-β-ac used ~22% (slightly over)
- Stream-novelty: ironstar-α correctly assessed high-novelty; ironstar-β initially low-novelty, AC pushed back, switched to high-novelty path
- Six-point gate: zero fires (no tier-2 elevations completed yet)
- AC five-condition: condition 1 (WO needs master input) fired 3×; condition 5 (master-bound emergence) fired 1×; others zero
```

## Parser notes

When `/meta-orchestrator-initiate` parses a payload at step 1:

1. Read frontmatter; if `variant: closure`, the mission is complete and re-invocation is unexpected — surface to user for confirmation
2. Restore mission frame summary, master observation log path, retired-AC enumeration with pointers
3. Restore accumulated design decisions and goal-2 insights into master's working memory
4. Restore parameterization-calibration data (carry forward to inform calibration decisions in the resumed mission)
5. Read open threads and in-flight work; identify the in-flight surface-up to respond to first
6. Skip to step 4 of `/meta-orchestrator-initiate` protocol (decomposition refinement, not fresh decomposition) unless the mission frame itself has shifted (user supersession during checkpoint window)

Writer (checkpoint) and parser (initiate) must agree on the schema; this file is the normative definition.
