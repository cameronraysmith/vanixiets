# Verification report: agent-session-telemetry (Linear CAM-120)

Close-out on 2026-11-22, after #4143–#4153 merged and magnetite and pyrite deployed main bd95469f.
The change stays open: the operator items below are unfinished, so it is not archived.

## 1. What was verified, and how

**Evaluation and build checks** (each with mutants seen failing in its log):
- `otel-collector-config`: the agent-session pipelines' stage order and key lists against `schema.nix`, the exporters and their headers, the queue holds, the hand-off cap, the span tables' DDL and ALTERs, the masks, the `details` strip and its withholding, the Langfuse path; mutants from task 2.5 onwards (`localFeedsDevloop` … `toolResultNotWithheld`, `handoffUncapped`, `nonStringSpanValueKept`, `langfuseEndpointElsewhere`; logs named in tasks 2.5, 9.3, 10.3, 11.1, 11.2, 11.9, 11.11, 11.15, 11.16, 12.2).
- `otel-envelope`: the `agent` series budget (2,000 series, 200 values) and the `sendFailedExempt` cases (tasks 2.6, 10.3, 12.2).
- `agent-telemetry-emitters`, `omnigent-worker-capabilities`, `omnigent-acp-spawn-env`, `claude-sandbox-session-secrets` (tasks 3.5, 9.4, 11.4).
- The agent role's assertions seen failing on `extendModules` overrides (tasks 2.4, 10.2); `otelcol validate` at 0.155.0 of both hosts' agent-session configurations (tasks 11.2, 11.15, 12.1).
- Identity: pyrite's shared collector hashes as at aaaed2a5 (settings `70fead21…`, serviceConfig `43f95ef9…`), and only magnetite's and pyrite's toplevels change (tasks 10.1, 11.13).

**VM tests on pyrite** against GreptimeDB 1.2.1 and otelcol-contrib 0.155.0:
- `fleet-ingress` with the canaries `agentSession` and `agentSpans` (admitted content found by `matches_term`; raw bodies, `gen_ai.input.messages`, account identifiers, links and unlisted keys absent from every string column of every database; credentials assembled at run time masked; `details` stripped; 64 KiB cut), `handoffCap`, `schemaOrder` and `langfuse` (a stand-in sink); all fourteen cases pass (`logs/maskfin-vmtest-fleet-ingress-full-20261122-164843.log`, `logs/r1fix-vmtest-r1fix-20261122-175451.log`).
- Uncommitted VM mutants each failing their case: tasks 4.3, 9.5, 10.4, 11.5, 11.9–11.12, 11.14, 12.5.
- `devloop-ingest` and `greptimedb-pipeline` after the port move (task 4.2).

**Load proofs**: the split load harness ran each host's evaluated configuration over eleven scenarios; zero fleet points refused and zero host-collector restarts on both hosts, the agent unit never restarted (design D14; `logs/collector-isolation-load-split-*-20261122-110726.log`); the two heaviest scenarios rerun with D15's tool results (`logs/d15-load-split-*-20261122-140112.log`).

**Reviews**: `CollectorChainReview`, `telemetry-d15-review` (follow-ups 1–7), `LangfuseChainReview` (R1 and follow-ups); each finding is fixed or recorded (design D15, "As deployed").

**Live deploys and sessions** (design "As deployed"; tasks 5.1, 5.3, 10.7, 12.6):

| Deploy | magnetite | pyrite | Logs |
|---|---|---|---|
| #4144 aaaed2a5 | 09:35:49–09:36:39Z | not changed | `logs/magnetite-4144-*` |
| #4145/#4146 25bd7ea2 | 11:48:50–11:49:37Z | 12:04:00–12:06:13Z | `logs/agent-telemetry-*` |
| #4148/#4149 72f782b8 | 18:27:18–18:28:10Z | 18:42:35–18:43:49Z | `logs/agent-split-*` |
| #4150 2c7ee83f | 20:09:19–20:10:15Z | held | `logs/d15-magnetite-*` |
| #4151–#4153 bd95469f | 23:08:04–23:08:48Z | 23:20:09–23:21:20Z | `logs/r1-*` |

None was rolled back. Each watch read fleet and devloop ingest, every queue, export failures and the collectors' memory; the only alert, `otel-envelope` FAILED and RESOLVED at 20:15/20:20Z, was finding F11.

Store queries as `regulator` after the last deploy (`logs/telemetry-closeout-queries-20261122-185434.log`):

```sql
SELECT span_name, "resource_attributes.host.name", timestamp FROM agent_span
  WHERE matches_term("span_attributes.last_user_message", 'R1-OMP-pyrite-232135');
-- chat claude-opus-5-5 | pyrite
SELECT ... WHERE matches_term("span_attributes.gen_ai.tool.call.result", 'R1-OMP-pyrite-232135');
-- execute_tool bash | pyrite
SELECT ... WHERE matches_term("span_attributes.gen_ai.tool.call.result", 'R1-CLAUDE-magnetite-230920');
-- claude_code.tool | magnetite
SELECT count(*), sum(CASE WHEN success = false THEN 1 ELSE 0 END) FROM session_event WHERE event_name = 'tool_result';
-- 3 | 0
```

Human sessions (task 8.1's human half): cameron's Claude Code sessions `TELEMETRY-pyrite`, `SPLIT-magnetite-182836`, `SPLIT-pyrite-184405`, `R1-CLAUDE-magnetite-230920` and `R1-CLAUDE-pyrite-232135`, and omp sessions `R1-OMP-magnetite-231051` and `R1-OMP-pyrite-232135`, each found within minutes of the session with its host and `user_name` `cameron`. In every deploy's new rows `'@'` appears only in `agent_span.scope_name`, the package name `@oh-my-pi/pi-agent-core`.

Masking on real hosts: both hosts' masking sessions (traces `5fdd0a5a…`, `91ad92d0…`) stored both dummy keys as `****`, no key prefix and no `details` in any string column, and `task_test_configuration` and `risk-admin-dashboard-components` unmasked.

Langfuse: the agent unit sent 17 of 18 spans on magnetite and 41 of 42 on pyrite (the unsent one each is `claude_code.tool.blocked_on_user`), with no send or enqueue failure; the orchestrator read five real traces back from `/api/public/v2/observations` with HTTP 200 (design "As deployed").

## 2. Open items and owners

| Item | Owner | What is missing |
|---|---|---|
| 5.2, 8.1 worker half | operator, or a later task | a session through Janette's worker (and cameron's) on magnetite, found by its word with `user_name` `janettesmith` |
| 8.1 day-later scan | later task | after 2026-11-23T23:21Z: no `agent` column named after an account identifier or raw API body; no value outside the content columns equal to an account's email or organisation id |
| 11.7 | later task | the credential-shape scan over a day's rows, after 2026-11-23T23:21Z |
| 5.4 | operator's decision | stopping `greptimedb.service` on magnetite for ten minutes to measure the agent rates; the rates in use are estimates checked by the load measurements |
| 6.1 | later task | the deployed GreptimeDB, Claude Code, omp and omnigent versions recorded here and compared with A188–A195 |
| 6.2 | later task | the journal of an :00 `otel-envelope` run on magnetite showing B1 over `agent` (the 5-minute runs' `B0 budget-run: ok` implies the 20:00Z budget run passed) |
| 7.2 | operator | stibnite, in a separate change |
| 9.7 | watch | no failed-Bash `tool_result` row exists yet (3 rows, none failed, none with `error`); read the first one's `error` |
| 10.8 | operator, or a later deploy task | remove pyrite's orphan `/var/lib/private/opentelemetry-collector/queue/exporter_otlp_http_ingress-agent_logs` |
| 12.7 | operator | review Langfuse and decide keep, sample, upgrade, self-host or flag off; record it in design D16 |
| ADR-003 span queue 15 min | operator | review of the figure the orchestrator accepted on 2026-11-22 |

Langfuse traces to look up (task 12.7):

| Session | Trace id | Session / conversation id |
|---|---|---|
| magnetite omp | `d69afc1b6e31940c889078bf257873f7` | `01a20586-d6fc-7595-98c0-5d53f7365f8e` |
| magnetite omp, first attempt (holds the deployer's script text in its prompt, masked) | `0cdd3fcc64081c06b9b8f1565c7ef594` | `01a20585-7ac1-7017-b19e-1779a1c64c65` |
| magnetite omp masking | `5fdd0a5a90470625dda522167aa5909c` | `01a20585-b67d-73da-b49d-9b49993a25bc` |
| magnetite Claude Code | `7e305f6dd173cf1cfba9113b99e0ad76` | `3cfbd628-c78b-4d2c-b6ac-8356c39e9d8d` |
| pyrite omp | `50b5e8efa491f013dd315fee4648550b` | `01a20590-ad55-7171-a267-2e15cc9981f8` |
| pyrite omp masking | `91ad92d0bb4308b0c5340052a354febb` | `01a20590-c222-73c4-935f-b59dbcf6542a` |
| pyrite Claude Code | `edfcbcf293f201e84c7109e2e9790db6` | `27241aac-4d87-4443-81a7-c7fe32ffe816` |

## 3. Follow-ups not done

- A non-paging daily rule over `otelcol_exporter_send_failed_spans{exporter="otlp_http/langfuse"}` on the agent unit, so a Langfuse block (403 at the Hobby limit) or outage is noticed (design D16, Alerting).
- stibnite (task 7.2).
- omp cost double-count: whether omp's `gen_ai.usage.input_tokens` already include its cached tokens, which would make Langfuse's cost for omp generations count cached input twice.
- `fleet-ingress`'s `lossControls` case can fail when the hourly budget run lands during another case's deliberate store outage and its failure carries over; a rerun passes. A timing weakness in the test, recorded during this change (finding F2) and not fixed.

## 4. Structural validation

`openspec validate agent-session-telemetry --strict`: "Change 'agent-session-telemetry' is valid", exit 0; `prek` over the changed files (gitleaks, treefmt): passed (`logs/telemetry-closeout-gates-20261122-190218.log`). No docs check covers `docs/notes/development/observability/decisions/` (the docs site's lint and link check read `packages/docs` only), so none was run for the ADR edits.
