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

## Day-later scans

Task 8.1's account-identifier scan and task 11.7's credential-shape scan count from pyrite's deploy of bd95469f (#4151–#4153), finished 2026-11-22T23:21:20Z.
The final run started at 2026-11-23T23:22:30Z, after the mark, over exactly the window [2026-11-22T23:21:20Z, 2026-11-23T23:21:20Z), as `regulator` through `obs-query sql agent` (`logs/day-later-scans-rerun-20261123T232230.log`, exit 0; the script is `logs/day-later-scan-rerun.py` on stibnite).
Every hit was then read with value-free queries (lengths, character classes, surrounding key names, span and conversation) in `logs/day-later-classify-20261123T233618.log`.
An early run on 2026-11-23 at 20:15–20:28Z over every row, including the 2026-11-22 rows before the window (`logs/day-later-scans-20261123T201542.log`), found the same classes; besides them it found only finding F10's two pre-fix rows (magnetite, 2026-11-22T20:12:44 and 20:12:51Z, `encodedBlobPattern`, `AwAAAA` 132 and 152), whose decoded bytes hold the dummy `ghp_` and 36 `a`s and no other credential shape.
Earliness hid nothing already stored: the `agent` ttl is 30 days, a query reads rows not yet flushed, compaction rewrites no value, and no daily job writes to `agent`.

Rows in the window, by table, host and user (human + worker, worker meaning `harness_host` `omnigent`):

| Host, user | `session_event` | `agent_span` | metric rows |
|---|---|---|---|
| magnetite, cameron | 1 + 1 | 17 + 1 | 8 |
| magnetite, janettesmith | 1 + 1 | 1 + 1 | 4 |
| pyrite, cameron | 8 + 6 | 98 + 9 | 31 |
| pyrite, janettesmith | 2 + 3 | 2 + 3 | 10 |
| stibnite, cameron | 10 + 3 | 4,101 + 3 | 14,331 |
| total | 36 | 4,235 | 14,384 |

stibnite's rows begin at 2026-11-23T09:02:25Z, so the window covers about 14 h 19 min of stibnite, cameron only; janettesmith has no stibnite row; `agent_span_operations` and `agent_span_services` hold no row in the window.
The orchestrating session and its subagents, exporting from stibnite since about 18:06Z, account for 4,059 of stibnite's 4,101 human spans (26 conversations; the orchestrator's own, `01a0aabc-d42f-…`, 528 spans from 18:07 to 23:21Z) and 14,287 of its 14,331 metric rows; the scans' hits on stibnite are mostly these sessions reading this change's patterns, hashes and logs.

Columns: no column of `agent` is named after an account identifier, a raw API body, `gen_ai.input.messages`, a system prompt or `details` (`regexp_like(lower(column_name), 'email|organi|account|body|input\.messages|system|instruction|details|oauth|credential|secret|password')` over `information_schema.columns`: no row); `span_events` and `span_links` hold `[]` in every row.
Account identifiers: the email address, organisation id and account id of the signed-in Claude account (one account across the seven `.claude.json` files on magnetite, pyrite and stibnite) appear in no row of any column of any table, content columns included.
`'@'` outside the content columns appears only in `agent_span.scope_name`, 4,199 rows in the run, all holding the package name `@oh-my-pi/pi-agent-core`.

Credential shapes, counted per table, column and pattern, every hit read as host, row time, first six characters and length:

| Pattern | Hits in the window (rows) | Reading |
|---|---|---|
| the collector's 17 `credentialPatterns`, one alternation | none | |
| the collector's `encodedBlobPattern` | none | |
| `sk-[A-Za-z0-9_-]{16,}` | output.messages 4, tool.call.arguments 2, tool.call.result 6, last_user_message 1 | `sk-adm` 29 (`risk-admin-dashboard-components`, the masking sessions' kept word), `sk-r1-` 29 and `sk-che` 24, lowercase kebab words |
| `(?:sk\|rk\|pk)_(?:live\|test\|prod)_[A-Za-z0-9]{8,}` | output.messages 3, tool.call.arguments 2, tool.call.result 3, last_user_message 1 | `sk_tes` 21 (`task_test_configuration`) |
| `AGE-SECRET-KEY` | output.messages 7, tool.call.arguments 4, tool.call.result 2, `span_status_message` 1, all stibnite | the 14-character name followed by prose or punctuation; in the tool result and status message it is followed by `-1[QPZR`, the collector's own mask regex read from `schema.nix`; `AGE-SECRET-KEY-1` and 20 key characters: none |
| key=value secret | tool.call.result 7, output.messages 2, all stibnite | read by character class, no value a credential: a key and a lowercase word (two rows), a key and an identifier followed by the next line's number, a key and a hyphenated word, a key assigned a function call, two keys followed by a `${…}` Nix interpolation; in output.messages a key assigned a function call and a key assigned a `<placeholder>` |
| `gh[pousr]_…`, `github_pat_…`, `xox[abprs]-…`, `AKIA`/`ASIA…`, `AIza…`, JWT, `BEGIN … PRIVATE KEY`, `age1…`, bearer | none | |
| email shape | last_user_message 1; tool.call.result 20; all stibnite | see below |
| `[A-Za-z0-9+]{40,}={0,2}` | tool.call.result 191, output.messages 46, tool.call.arguments 45, `span_status_message` 6 | 40-hex commit ids (97, 44, 43, 3), 64-hex sha256 (26, 0, 0, 1), Nix and npm `sha256-`/`sha512-` hashes (25, 2, 2, 1), jj Change-Ids (9), cache public keys (3), one other hex length; the 31 others are 40-hex ids after an escaped newline, a Nix base32 store hash, SRI hashes cut at a `/`, a Cloudflare report-URL parameter, a `googleusercontent.com` image path, and one 71-character fragment of omp's base64 `details.trace.syntax` in a `grep` over an omp session file, whose decoded bytes hold no credential text |
| `[0-9a-fA-F]{40,}` | tool.call.result 162, output.messages 44, tool.call.arguments 43, `span_status_message` 4 | commit ids and sha256 hashes as above |
| `\*\*\*\*` | 29 rows on pyrite and stibnite | masked values |

No unmasked credential and no account identifier was found.

Email shapes: the one in `last_user_message` (stibnite, 20:33:19Z, conversation `01a0aabc-d42f-…`, 27 characters) is the operator's commit email (`jj config get user.email`), pasted into a prompt with a jj log; it is not the signed-in account's address.
Of the 20 in tool results, 10 are the same commit email in printed jj or git output, one is a `git@` remote, two are placeholders and seven are other addresses printed by tools; none is an account's address.
The requirement `No account identifier leaves a host` read, at the scan: "No account identifier SHALL leave a host in an agent session's data, and the only person identifier stored SHALL be the session's user name."
Its scenario and task 8.1's check cover the identifiers the harness attaches as telemetry attributes (`user.email`, `organization.id`, account ids), and world-assumptions defines an account identifier as one a model provider assigns; the commit email is not one, so the first clause holds.
The second clause, read literally, was not met: content columns hold person identifiers (the commit email and other addresses), which decision D15 stores as session content.
On 2026-11-23 the operator narrowed the second clause and added no email mask: outside the content columns the only person identifier stored is the session's user name, and text a person types or a tool prints is session content, stored as written within the 64 KiB cut and the credential masking (design D15, "Person identifiers in content").
Against the narrowed requirement the scan's results pass: no account identifier in any column, content columns included, and `'@'` outside the content columns only in `scope_name`'s package name.

Searchability on stibnite (task 8.1's form; stibnite's enablement is task 7.2's change): a fresh human session `omp --model haiku -p 'Reply with the single word ok. Marker DLSMARK202542z'` (20:25:42–20:25:45Z) was found at 20:26Z by `matches_term("span_attributes.last_user_message", 'DLSMARK202542z')` as `chat claude-haiku-4-5`, stibnite, cameron, no `harness_host`.
Every worker `user_prompt` on magnetite and stibnite is omnigent's `/model` (magnetite 17:06:43Z, cameron and janettesmith; stibnite 16:01:14, 17:58:33 and 20:12:04Z, cameron), stamped with host, person and `harness_host` `omnigent` and found by `matches_term(prompt, 'model')`; the only worker prompt with a distinctive word is pyrite's `HH-CLAUDE-WORKER-pyrite-102947` (2026-11-23T10:30:51Z, cameron), so no worker session with a distinctive prompt has run on magnetite or stibnite.

## Deployed versions against A188–A195 (task 6.1)

Read on 2026-11-24 at 02:19Z (`logs/closeout-cam120-versions-20261123-211911.log`): each human and worker home's `claude` and `omp` on magnetite and pyrite, magnetite's `greptimedb.service`, the `omnigent-host-cameron` unit on both servers, stibnite's own binaries, and the `service_version` the store holds for the last day.

| Assumption | Version it names | Deployed | Result |
|---|---|---|---|
| A188, A192, A193 (GreptimeDB) | 1.2.1 | `greptimedb-bin-1.2.1` on magnetite | equal |
| A189 (consent) | none | none | not a software version |
| A190 (Claude Code) | 2.1.330 | 2.1.330 in every home on magnetite, pyrite and stibnite; `session_event.service_version` 2.1.330 on all three hosts | equal |
| A191 (omp) | as packaged on 2026-11-22 (18.13.2 on stibnite on 2026-11-23) | 19.1.1 in every home on all three hosts | differs; re-read below |
| A194 (loopback receivers) | none | none | not a software version |
| A195 (omnigent) | 0.23.0 | `omnigent-0.23.0` on magnetite, pyrite and stibnite | equal |

A191 re-read at omp 19.1.1 (`git diff v18.13.2 v19.1.1` of `docs/environment-variables.md`, `packages/agent/src/telemetry.ts`, `packages/coding-agent/src/telemetry-export.ts` and `telemetry-export-otlp.ts` in `can1357/oh-my-pi`): the `OTEL_*` entries of `~/.omp/agent/.env` are now read through a private map, `$otelEnv`, instead of the process environment, and are put in `process.env` only while the exporters are built; each signal is still enabled only by its own endpoint (or the common one) and its exporter variable; content capture still reads `OTEL_INSTRUMENTATION_GENAI_CAPTURE_MESSAGE_CONTENT`, now through `$otelEnv`.
None of the violations A191 names is observed: stibnite's omp 19.1.1 sessions export spans stamped `user.name` `cameron` from the `.env` (5,628 spans in the last 6 hours), `session_event` holds no `oh-my-pi` row, so `OTEL_LOGS_EXPORTER=none` still holds, and `omp_agent_tool_calls_total` carries no session-id label.
A side effect of the change is that the `OTEL_*` values no longer reach the programs omp launches.

## 2. Open items and owners

| Item | Owner | What is missing |
|---|---|---|
| 5.2, 8.1 worker half | operator, or a later task | a session through Janette's worker (and cameron's) on magnetite, found by its word with `user_name` `janettesmith` |
| 8.1 person identifiers in content | closed 2026-11-23 by the operator's decision | none: the requirement `No account identifier leaves a host` narrowed to "outside the content columns, the only person identifier stored is the session's user name"; text a person types or a tool prints is stored as written; no email mask ("Day-later scans", email shapes) |
| 5.4 | closed 2026-11-23, dropped by the operator (decision record D21) | none: the agent rates are read from the store after a week instead of stopping the store |
| 6.1 | closed 2026-11-24 | none: "Deployed versions against A188–A195" above; omp differs (19.1.1) and A191 was re-read |
| 6.2 | closed 2026-11-24 | none: magnetite's 01:00Z and 02:00Z budget runs pass with `agent.greptime_physical_table` present, so B1 counted `agent` (`logs/closeout-cam120-remote-20261123-211005.log`) |
| 7.2 | closed 2026-11-24 | none: `darwin-agent-session-telemetry` (CAM-121) is merged, deployed on stibnite, and its task 12.1 passed (`logs/c121-12.1-cache-20261124T032509Z.log`) |
| 9.7 | watch | no failed-Bash `tool_result` row exists yet (3 rows, none failed, none with `error`); read the first one's `error` |
| 10.8 | operator, or a later deploy task | remove pyrite's orphan `/var/lib/private/opentelemetry-collector/queue/exporter_otlp_http_ingress-agent_logs` |
| 12.7 | operator | review Langfuse and decide keep, sample, upgrade, self-host or flag off; record it in design D16 |
| ADR-003 span queue 15 min | closed 2026-11-23 | none: accepted by the operator (decision record D21) and recorded in ADR-003 |

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
