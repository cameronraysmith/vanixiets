## Context

The agent-session collector runs on magnetite and pyrite as `otel-agent-session.service` (`agent-session-telemetry` design D14, deployed 2026-11-22 at bd95469f): `otlp/local` on `127.0.0.1:4318` feeds `metrics/agent-session`, `logs/agent-session` and `traces/agent-session`, which keep the allow-listed, capped and masked session data and export it over mTLS to the ingress and, where the host-table row sets `langfuse`, to Langfuse Cloud (D15, D16).
Its settings are built inline in the NixOS agent role (`modules/clan/services/otel-collector/flake-module.nix:731-1404`).

stibnite collects fleet signals since `stand-up-darwin-collection` (2026-11-08): `org.nixos.otelcol` as `_otelcol` (uid 536) with `otlp` on `127.0.0.1:4318`, fed only by the root `org.nixos.otelcol-process`; the probe, node_exporter and `org.nixos.otel-envelope` beside it (`modules/darwin/otel-collector-agent.nix:149-251`, `modules/lib/otel-collector-darwin.nix`).
No harness on stibnite exports: its `observabilityHosts` row sets neither flag, the darwin fragment declares no `vanixiets.otelCollector.agentTelemetry`, and `checks.x86_64-linux.agent-telemetry-emitters` requires stibnite's crs58 home to carry no telemetry keys (`modules/checks/agent-telemetry-emitters.nix:85-89`).

The operator's decisions D22 and D24 (2026-11-23) make stibnite the priority and fix its scope; the orchestrator's D25–D30 fix the design's direction; brainstorm.md records the options weighed.
Stakeholders: the operator (decides, deploys stibnite at the console, reads), the group (every store reader and every member of the Langfuse project reads stibnite's sessions, under the consent of world assumptions A189 and A206).

## Goals / Non-Goals

**Goals:**
- Every Claude Code and omp session that crs58 runs on stibnite, recorded as `cameron`, and every session of the omnigent worker `omnigent-cameron`, reaches `agent` exactly as a pyrite session does, and its spans reach Langfuse.
- The agent pipelines on stibnite are the same function as on the NixOS hosts, proven by an equality check, so no allow-list, cut or mask can differ.
- The Mac's fleet signals, process memory included, keep arriving, and agent load on the Mac costs agent data only.
- stibnite's queues hold a week of average use off the mesh.
- omp's two startup requests (`skill_description`, `mcp_namespace_hint`) no longer reach Langfuse from any host, and a Langfuse quota block reaches a person without paging.
- Another Mac becomes a one-line host-table change, apart from consent and a recipient for the `langfuse` var.

**Non-Goals:**
- rosegold, argentum and blackphos; Christopher's consent is not recorded (A189 names the group's consent as stated on 2026-11-22; for Christopher it is unknown).
- Claude's cloud sessions; a self-hosted Langfuse; a hard memory ceiling on macOS.
- Changing what is collected: the allow-lists, cuts and masks are `agent-session-telemetry`'s and stay as deployed.

## Decisions

Each decision names its source in the orchestrator's record and the boundary it sits on where it touches vendored-versus-first-party (launchd, sops-nix, the contrib collector, omp, Langfuse) or source-versus-delivered (Nix source against the activated plist, file or running configuration).

### D1: The agent-session settings become one function of host facts (D26a)
- **Choice**: `flake.lib.agentSessionCollector` in a new `modules/lib/agent-session-collector.nix`, the pattern of `flake.lib.otelCollectorDarwin`:
  `{ hostName, ingress ? false, caFile, certFile, keyFile, queueDirectory, queueBytes ? <the NixOS sizes>, telemetryPort ? 8890, langfuse ? null /* { publicKeyFile; secretKeyFile; } */ } → { settings; queueBytes; limiterMib = 384; goMemLimitMib = 409; ceilingMib = 512; }`,
  paired with `flake.lib.agentSessionAssertions { settings, goMemLimitMib, ceilingMib ? null, langfuse, handoffQueueBytes }`, which returns the settings-only assertions with no reference to systemd. The NixOS module passes `/run/credentials/otel-agent-session.service/*` and its `unit.*` numbers; the darwin fragment passes the sops paths, `/var/lib/otel-agent-session/queue` and no ceiling. Everything platform-specific (unit, hardening, `LoadCredential`, `restartUnits`, launchd keys) stays in the callers.
- **Acceptance**: sha256 of `nix eval --json` of pyrite's and magnetite's `services.opentelemetry-collector.settings`, `vanixiets.otelCollector.agentSessionSettings` and both units' `serviceConfig` is the same before and after the extraction commit, the method of `agent-session-telemetry` task 10.1; every other host's toplevel `drvPath` is unchanged.
- **Rationale**: the only free variables that differ by platform are the credential paths and the queue directory (the priming §2); a second copy would drift, and the store's closed column set (A198) would refuse whatever one copy sends that the other does not.
- **Boundary**: first-party source; the delivered configuration is compared by hash on NixOS and by the equality check (D12) on darwin.
- **Alternatives**: a second copy in the darwin fragment; importing the NixOS module on darwin (it sets systemd options darwin lacks). Both rejected in brainstorm Q1.

### D2: The fleet collector moves to 4319; the agent daemon takes 4318 (D27)
- **Choice**: `modules/lib/otel-collector-darwin.nix` sets the fleet agent's `otlp` receiver and `otelcol-process`'s `otlp_http/agent` exporter to `127.0.0.1:4319` (`:129`, `:308`); `checks.x86_64-linux.otel-collector-darwin`'s `processNoListenerNoCredential` clause follows (`:180`), and a new clause requires that no fleet receiver is on 4318. The new daemon's `otlp/local` is on `127.0.0.1:4318`, as on every agent-telemetry host. The fragment's loopback assertion covers both.
- **Rationale**: two literals, no pipeline, queue or exporter touched; `file_storage` keys are exporter names, so no queue moves; 4318 stays the emitter endpoint everywhere (ADR-003 item 3), so `modules/home/ai/agent-telemetry.nix` needs no per-platform endpoint; and an emitter can no longer feed `fleet` through `metrics/host` (`otlpFeedsHostOnly`).
- **Cost**: one reload of `otelcol` and `otelcol-process` at the switch; `otelcol-process`'s in-memory queue can lose at most one batch of process points [INFERENCE].
- **Bind order at the switch**: launchd reloads changed plists in no order we control. If the agent daemon starts before `otelcol` releases 4318, its bind fails and `KeepAlive` restarts it after `ThrottleInterval` (5 s); emitters lose at most that interval (omp keeps 64 spans and retries for 5 s, A196).
- **Boundary**: first-party configuration of the vendored collector; delivered state is read with `lsof -iTCP -sTCP:LISTEN` after the switch.
- **Alternatives**: rejected in brainstorm Q2.

### D3: The launchd daemon `org.nixos.otel-agent-session` under `_otelagent` (D27)
- **Choice**: on darwin rows that set `agentTelemetry`, the fragment declares `vanixiets.otelCollector.agentTelemetry` and a daemon:
  - `UserName`/`GroupName` `_otelagent` (uid and gid 537), `KeepAlive`, `RunAtLoad`, `ThrottleInterval = 5`, `ProcessType = "Standard"`, as the omnigent daemons (`modules/darwin/omnigent-host.nix:487`);
  - `/bin/wait4path` on the client key and both Langfuse files, then `exec otelcol-contrib --config <agentSessionCollector settings>`;
  - `GOMEMLIMIT=409MiB`; the 384 MiB limiter is in the settings;
  - `OTEL_CERT_SHA256` and `LANGFUSE_VAR_SHA256` in `EnvironmentVariables`, so a reissued certificate or a re-encrypted Langfuse var reloads the job (D5);
  - telemetry on `127.0.0.1:8890`, queue in `/var/lib/otel-agent-session/queue`, log in `/var/log/otel-agent-session/`, created by the activation pre-step as `_otelagent` 0700, as `/var/lib/opentelemetry-collector` is;
  - the agent role declares `_otelagent` in `users.knownUsers` and `users.knownGroups`, and group `_otelcert` (gid 538) with members `_otelcol` and `_otelagent`.
- **Account**: dedicated, because D27's condition holds. On NixOS each collector is its own `DynamicUser` and only `otel-agent-session.service` loads the Langfuse keys (`flake-module.nix:1018,2005-2042`), so the fleet collector cannot read them. On darwin sops-nix files are protected by owner and mode alone; under `_otelcol` the fleet collector and the envelope would hold the Langfuse key. The mTLS key both present becomes `_otelcol:_otelcert` 0440 on flagged rows only; rosegold and argentum keep `_otelcol:_otelcol` 0400.
- **Envelope**: `org.nixos.otel-agent-session-envelope`, `StartInterval = 300` as `_otelcol` (it reads only `127.0.0.1:8890` and the ntfy token, which is `_otelcol` 0400), under `flake.lib.observabilityNotifyRun`, running `flake.lib.otelEnvelope` with the daemon's targets and exporters, `sendFailedExempt = [ "otlp_http/langfuse" ]`, and `darwinMemory.limits."org.nixos.otel-agent-session"` (D4). stibnite's row lists `otel-agent-session-envelope` in `notifiedUnits`, so `LaunchdJobFailed` leaves its failures to its own notice.
- **Rationale**: the shape of the existing `otelcol` daemon and of NixOS's split; the envelope as on NixOS (`flake-module.nix:1040-1065`).
- **Boundary**: vendored launchd and sops-nix, configured from first-party source; the account, modes and loaded job are read live after the switch (`launchctl print system/org.nixos.otel-agent-session`, `stat -f '%Su:%Sg %Lp'`).
- **Alternatives**: `_otelcol`; a second per-machine certificate. Rejected in brainstorm Q3.

### D4: Memory on macOS: isolation, soft bounds and a footprint notice, no ceiling (D29; pending Q2)
- **Choice**: the guarantee on darwin is:
  - process isolation from the fleet collector: its own heap, limiter, queue directory, receiver and telemetry port, which removes the shared-heap mechanism by which agent spans cost fleet points in D14 (`agent-session-telemetry` design D14 Problem);
  - `GOMEMLIMIT=409MiB` and the 384 MiB limiter, soft bounds as on NixOS: the garbage collector works harder past the first, and the limiter refuses data past the second, checked every second;
  - a C5 footprint clause in the daemon's envelope, failing and posting `FAILED otel-agent-session-envelope on stibnite` above its limit.
  It does not hold a kernel-enforced 512M ceiling or a kill order: launchd offers none for this daemon (A209). A runaway daemon would push the Mac into memory compression and swap before C5, run every 5 minutes while awake, notices.
- **C5 limit**: set from the extended load proof (D12): the smallest multiple of 64 MiB at or above the largest resident size the agent process reached at 16 senders with no ceiling, and not below 512 MiB; 640 MiB until the proof runs [INFERENCE: the D14 cgroup peaks were 451–480 MiB at eight senders, and darwin's footprint adds about 44 MiB of load-time pages, `modules/darwin/otel-collector-agent.nix:115-124`].
- **Load proof, before stage 2 ships**: the split load harness of `agent-session-telemetry` task 10.5 (out of tree; its runs are `logs/collector-isolation-load-split-*-20261122-110726.log`) runs pyrite's evaluated agent-session unit at 12 and 16 concurrent senders over its p99, max and 64-span-burst scenarios, twice: as deployed (`MemoryMax = 512M`) and with `MemoryMax` and `MemorySwapMax` removed, the darwin case. A third run fills a 256 MiB span queue with the ingress unreachable, then restores it, to show that a full stibnite-sized queue does not raise the resident size [INFERENCE that it does not: `file_storage` reads items from disk as consumers take them]. Recorded per scenario: fleet points refused (must be 0), host collector restarts (0), agent unit restarts, agent spans refused, heap and resident peak.
- **Optional experiment**: `JetsamProperties = { JetsamMemoryLimit = <C5 limit + 128 MiB>; }` on the daemon, kept only if `launchctl print` then shows `jetsam memory limit (active)` at that value; otherwise removed. Not a dependency.
- **Rationale**: no enforcement exists to configure (A209); this Mac's p99 is 12 sessions active per 5 minutes, up to 30 (A210), above the eight the D14 proof used.
- **Boundary**: vendored launchd, the Go runtime and the collector's limiter; first-party envelope. The load proof runs on Linux, so it shows the process's own memory behaviour, not macOS's compressor.
- **Alternatives**: rejected in brainstorm Q5.

### D5: Credentials on darwin: the shared `langfuse` var gains stibnite (D27)
- **Choice**:
  - The `langfuse` generator's definition moves into a function shared by the NixOS and darwin modules, like `otelGenerators` (`flake-module.nix:1872-1927`): clan compares a shared generator's files, prompts and script across machines and ignores owner, group and mode (`:1868-1871`). `files.*.restartUnits` stays NixOS-only (clan throws on it on darwin, `:1961-1962`).
  - On darwin rows that set `langfuse`, both files are `_otelagent:_otelagent` 0400 with `neededFor = "services"`, read by path through `basicauth/langfuse`'s `username_file` and `password_file`.
  - stibnite becomes a recipient with `clan vars fix stibnite --generator langfuse`, which adds its age key and re-encrypts with the value unchanged (`docs/notes/development/observability/charter.md:344`); `generate` would regenerate it and is not used. The recipient files under `vars/shared/langfuse/*/machines/stibnite` land in the same commit as the flag, because `flake.lib.sharedVarsObligations` fails stibnite's evaluation without them (`modules/lib/shared-vars-recipients.nix:136-147,173-191`).
  - Reload on rotation: `LANGFUSE_VAR_SHA256 = builtins.hashFile "sha256" <vars/shared/langfuse/secret-key/secret>`, the hash of the encrypted file, never the value; it also changes on any re-encryption, which only reloads the job [INFERENCE].
- **Rationale**: the darwin precedent (the client key and the ntfy token are sops files read by their account, `flake-module.nix:2061-2065,2089-2094`); least privilege as on NixOS (D3).
- **Boundary**: vendored clan vars and sops-nix; the delivered file's owner and mode and `cmp -s` of `clan vars get stibnite langfuse/<file>` against the magnetite value are read after the switch.

### D6: The kept-alive expectation follows each host's row (D26c)
- **Choice**: `flake.lib.launchdKeptAlive hostName` returns `schema.launchdKeptAlive`, unchanged and now the base list every Mac shares, plus `org.nixos.otel-agent-session` when the row sets `agentTelemetry`. The fragment's assertion compares each Mac against its own list. `LaunchdJobNotRunning` renders `<kept-alive labels>` from the union over darwin rows, which selects nothing on a Mac that does not run the daemon, because each probe writes only the allow-listed labels its own `launchd.daemons` defines (ADR-004 `:130`). `schema.launchdLabels` gains `org.nixos.otel-agent-session` and `org.nixos.otel-agent-session-envelope`; `process.darwinFleetExecutables` gains `"org.nixos.otel-agent-session" = "otelcol-contrib"`, so the fragment's one-glob-per-daemon assertion holds and `otelcol-process` keeps the daemon's memory series below the darwin floor.
- **Stage 1 effect**: none rendered: stage 1 adds the function and moves the assertion onto it, and no row's list changes until stibnite's flag is set, so the rule and every Mac's assertion are as today. The `launchdLabels` and `darwinFleetExecutables` additions land with the daemon in stage 2, since they change every Mac's probe input.
- **Rationale**: a global list breaks rosegold and argentum or leaves the daemon unwatched (brainstorm Q6); this also resolves Linear CAM-90, which asked for exactly this before a second darwin agent host.
- **Boundary**: first-party; delivered when magnetite (the rule) and each Mac (its assertion and probe) deploy.

### D7: Queues: stibnite's for a week off the mesh, the ingress's for three hosts (D28, D26d; ingress pending Q1)

stibnite's agent-session daemon, under its own 512 MiB disk budget (ADR-003 `:237`). Rates assumed by `schema.nix` (`:256-273`): metrics 35,840 B/min, events 133,000 B/min, spans 240,000 B/min, each eight sessions' worth; per session-hour 1.8 MB of omp spans, 0.45 MB of Claude Code spans, 1.0 MB of Claude Code events and at most 268,800 B of metrics. stibnite's average (A210): 20.7 omp and 0.116 Claude Code session-hours a day.

| Exporter | Queue | Average use per day | Holds at average use | Holds at the assumed rate (asserted minimum) |
|---|---|---|---|---|
| `otlp_http/ingress-metrics` | 52 MiB = 54,525,952 B | 20.8 × 268,800 = 5.6 MB | 9.7 days | 25.4 h (24 h) |
| `otlp_http/ingress-agent` (events) | 64 MiB = 67,108,864 B | 0.116 × 1.0 MB = 0.12 MB | about 19 months | 8.4 h (8 h) |
| `otlp_http/ingress-traces` (spans) | 256 MiB = 268,435,456 B | 20.7 × 1.8 MB + 0.116 × 0.45 MB = 37.3 MB | 7.2 days | 18.6 h (3 h) |
| `otlp_http/langfuse` | 32 MiB | as spans, while the internet is reachable | drains in minutes; drops after 5 min of failure (D16) | twice a 5 min window |
| Sum | 404 MiB | | | < 512 MiB |

The span queue is the only one sized differently from NixOS: a host-table field `agentSpanQueueMiB` (default 44, stibnite 256), which the equality check (D12) ignores. Asleep, sessions are suspended and nothing arrives, so only awake time off the mesh consumes queue; a week at average use is 261 MB (249 MiB). All figures are [INFERENCE] from the assumed rates; task 5.4 of `agent-session-telemetry` (measure them) was dropped by the operator's D21 in favour of reading them from the store after a week.

The ingress on magnetite, while the store is down. `otel-collector-config` requires each agent queue to hold its minimum for every host whose row sets `agentTelemetry` (`modules/checks/otel-collector-config.nix:467-469,1014-1026`); the ten store queues sum to 508 MiB of 512 (`modules/clan/services/otel-collector/flake-module.nix:63-78`, README `:274`). That 508 is the queues' disk budget, not the ingress process's memory.

| Exporter | Now | Needed at 3 hosts | Recommended (Q1) | Holds at 3 hosts |
|---|---|---|---|---|
| `otlp_http/fleet` | 400 MiB | 24 × 60 × 256,000 = 368,640,000 B (351.6 MiB) | 382 MiB = 400,556,032 B | 26.1 h |
| `otlp_http/agent` (metrics) | 16 MiB | 2 × 60 × 3 × 35,840 = 12,902,400 B (12.3 MiB) | 16 MiB | 2.6 h |
| `otlp_http/agent_session_event` | 32 MiB | 2 × 60 × 3 × 133,000 = 47,880,000 B (45.7 MiB) | 46 MiB = 48,234,496 B | 2.0 h |
| `otlp_http/agent_span` | 8 MiB | 15 × 3 × 240,000 = 10,800,000 B (10.3 MiB) | 12 MiB = 12,582,912 B | 17.5 min |
| `devloop` and its five tables | 52 MiB | unchanged | 52 MiB | unchanged |
| Sum | 508 MiB | | 508 MiB | < 512 MiB |

- `fleet` has 50,790,400 B (48.4 MiB) more than its rule needs; the recommendation takes 18 MiB of it. The span queue is 12 MiB rather than the 11 that would suffice because the agent-session collectors' span hand-off batches to `queueBytes.agent_span / 4` (`flake-module.nix:805,989`): 3 MiB is a whole number, 2.75 MiB would also pass. The orchestrator's 16 MiB from `fleet` alone would leave the sum at 509 MiB (11 MiB spans) or 510 MiB (12 MiB), still below 512; 18 MiB keeps it at 508.
- The hand-off batch on magnetite's and pyrite's agent-session collectors grows from 2 MiB to 3 MiB with it, so `fleet-ingress`'s `handoffCap` case is rerun.
- **Boundary**: first-party; the delivered queues are read from `otelcol_exporter_queue_capacity` on magnetite's `127.0.0.1:8888` after the deploy.

### D8: omp's oneshot kind is stored, and its startup requests stay out of Langfuse (D24, D26b)
- **Choice**: `schema.nix`'s `agentSession.spans.keys` gains `"omp.gen_ai.oneshot.kind" = "string"`, so `agent_span` gains `span_attributes.omp.gen_ai.oneshot.kind` through the schema job's existing `ADD COLUMN IF NOT EXISTS` (`agent-session-telemetry` design D15 Schema; A204). `schema.nix`'s `agentSession.langfuse.droppedOneshotKinds = [ "skill_description" "mcp_namespace_hint" ]`; `filter/langfuse` drops a span whose `omp.gen_ai.oneshot.kind` is on that list, beside its existing `span.name` condition; `transform/langfuse` deletes the key from every span it sends.
- **Scope (the orchestrator, 2026-11-23)**: both startup requests, which come from the same compressor at session start and carry `skill_description` and `mcp_namespace_hint` (A211), are the same noise. Every other oneshot kind (compaction, handoff, branch summary, job caption, image, evaluator completion) is still sent; D26b's wording, "drops spans that carry it", would have dropped those too.
- **Orphans**: none. omp opens such a span around one completion and closes it; the only span factories are in `packages/agent/src/telemetry.ts`, so it is a leaf, and a startup request starts outside any run, so it is also the root and the whole trace (A211). Langfuse saves one trace and one observation, 2 units, per request [INFERENCE].
- **Order**: magnetite deploys first, so its schema job adds the column before any agent-session collector keeps the key (`auto_create_table=false` refuses unknown columns with HTTP 400, A198); on magnetite the unit already `Wants=` and is `After=` the schema job (`agent-session-telemetry` design D15, F11).
- **Boundary**: vendored omp's span shape and the contrib filter; first-party allow-list; the delivered column is read with `SHOW CREATE TABLE agent_span`.
- **Alternatives**: rejected in brainstorm Q8.

### D9: A Langfuse block reaches a person, at low priority (D24, D26e)
- **Choice**: on hosts whose row sets `langfuse`, the host collector gains a scrape job `otelcol-agent-session` of `127.0.0.1:8890` (on darwin in `flake.lib.otelCollectorDarwin`, on NixOS in the agent role), keeping only `otelcol_exporter_sent_spans` and `otelcol_exporter_send_failed_spans` with `exporter="otlp_http/langfuse"` and dropping `service_instance_id`, a keep-list `schema.otelcolAgentSessionKeep` separate from `otelcolKeep`, so no other host's scrape changes. `modules/nixos/fleet-alert/rules.nix` gains `LangfuseSendFailing`, severity `info` (ntfy priority `low`, ADR-009 item 10), `for = "1h"`: per host, `increase(otelcol_exporter_send_failed_spans{exporter="otlp_http/langfuse"}[1d]) > increase(otelcol_exporter_sent_spans{exporter="otlp_http/langfuse"}[1d])`, with no presence selector, so a sleeping Mac raises nothing.
- **Why**: Langfuse answers a quota block with 403, which the exporter drops at once and `otel-agent-session-envelope` deliberately does not count (`sendFailedExempt`, `agent-session-telemetry` design D16). stibnite alone is estimated at about 155,000 units a month (621 session-hours × about 250 units, `local://telemetry-d16-priming.md` §4), 3.1 times Hobby's 50,000; with magnetite and pyrite the fleet likely passes the 250,000 at which Langfuse's server code blocks ingestion for the cycle, which would stop Langfuse data for every host (A205, enforcement on Cloud unverified). D8's saving is 2 units per startup request and does not change that.
- **Cost**: two series per Langfuse host in `fleet` (about 6), inside ADR-004's budget. It ends pyrite's shared collector being byte-identical to its configuration before agent telemetry (aaaed2a5, `agent-session-telemetry` design D14): it gains one loopback scrape of two series, and nothing else. The standing guard against agent load reaching it is not that identity but `otel-collector-config`'s clause that the shared collector has no agent-session pipeline (mutants `metricsBackInShared` and `spansBackInShared`).
- **Boundary**: vendored collector self-telemetry names at 0.155.0 (no `_total` suffix, `schema.nix:139-142`); first-party rule; the delivered rule is shown by the evaluator's fixture legs and the stored series by `obs-query`.
- **Alternatives**: paging; an envelope clause (it would page through the notifier); nothing. Rejected in brainstorm Q9.

### D10: Emitters on stibnite: crs58 as `cameron`, and the darwin worker (D27, D30)
- **Choice**:
  - `modules/home/ai/agent-telemetry.nix` gains `agentTelemetry.enable` (default `osConfig != null && osConfig.vanixiets.otelCollector.agentTelemetry or false`, today's gate), and `agentTelemetry.person` defaults to the `flake.userAliases` key whose value is the home's user name, else the user name: on stibnite crs58 stamps `cameron`; on NixOS cameron stays `cameron` (`modules/home/users/aliases.nix:18-21`).
  - The darwin worker builder (`modules/darwin/omnigent-host.nix:103-115`) passes `agentTelemetry.enable = flake.lib.observabilityHosts.<host>.agentTelemetry` and `agentTelemetry.person = worker.owner` beside `vcs.author`; `modules/home/ai/omnigent/worker.nix`'s derived person becomes `lib.mkDefault`, so a worker home with `osConfig = null` no longer forces the lookup.
  - Endpoint and gates are `agent-session-telemetry`'s as deployed (its design D2, D15); the module needs no darwin branch.
- **Harnesses**: terminal and herdr panes as crs58 (`claude`, `omp`), omp ACP children (A191), and omnigent-cameron's sessions export. The Claude desktop app's local Claude Code sessions and the VS Code Claude Code extension run the bundled CLI, which applies user-settings `env` (A190), so they likely export [INFERENCE]; Zed's ACP Claude adapter is uncertain; `claude --cloud`, the desktop chat, Codex, Antigravity and the `claude-glm`/`claude-cerebras` wrappers do not. Which do is read live after the deploy (D30); whatever exports is bounded by the collector's allow-lists.
- **Boundary**: source-versus-delivered: verified on the activated `~/.claude/settings.json` and `~/.omp/agent/.env` of crs58 and omnigent-cameron, and by evaluating both homes on Linux.

### D11: ADR amendments (listed here; applied after the operator ratifies them)
- ADR-003 `:85` (item 3). From: "On NixOS hosts whose host-table row sets `agentTelemetry`, that receiver, `otlp/local`, is held by a second collector process, `otel-agent-session.service`, …" To: "On hosts whose host-table row sets `agentTelemetry`, that receiver, `otlp/local`, is held by a second collector process, `otel-agent-session.service` on NixOS and the launchd daemon `org.nixos.otel-agent-session` under `_otelagent` on darwin, …"; the rest of the line unchanged.
- ADR-003 `:113` (item 22). "The agent's `otlp` receiver on `127.0.0.1:4318`" becomes "The agent's `otlp` receiver on `127.0.0.1:4319`", with "(moved from 4318 by `darwin-agent-session-telemetry`, so that 4318 is the agent-session receiver on every host)".
- ADR-003 `:236`. Append: "On darwin, where launchd enforces no memory ceiling (`:24`), the agent-session collector runs as its own process under `_otelagent` with the same limiter and `GOMEMLIMIT` and no ceiling, and R3.2's `C5` fails above a physical footprint of <the D4 limit> MiB; its growth costs agent telemetry and the host's memory headroom, never fleet points."
- ADR-003 `:237`. Append: "On stibnite the agent-session collector's span queue absorbs about a week of the host's average agent spans while the mesh is unreachable."
- ADR-003 `:255`. "the two darwin collectors above" becomes "the darwin collectors above, `org.nixos.otel-agent-session` judged by its own envelope job `org.nixos.otel-agent-session-envelope`", adding its limit.
- ADR-003 `:120` (item 26). Append: "On hosts whose row sets `langfuse`, a second job `otelcol-agent-session` reads the agent-session collector at `127.0.0.1:8890` and keeps only Langfuse's sent and failed span counters."
- ADR-004 `:73`. "magnetite and pyrite" becomes "magnetite, pyrite and stibnite".
- ADR-004 `:130`. The launchd allow-list gains `org.nixos.otel-agent-session` and `org.nixos.otel-agent-session-envelope`; add "the kept-alive expectation is the base list plus `org.nixos.otel-agent-session` on rows that set `agentTelemetry`".
- ADR-008 `:54`. "the same filtered, capped and masked agent spans" becomes "the same filtered, capped and masked agent spans, less omp's startup requests (`skill_description`, `mcp_namespace_hint`)".
- ADR-008 `:61` (item 4). "NixOS `DynamicUser` or darwin `_otelcol`" becomes "NixOS `DynamicUser` or darwin `_otelcol`, and `_otelagent` for the darwin agent-session collector", and "as `0400` files owned by that account" gains ", the client key shared as `0440` with group `_otelcert` where both darwin collectors run".
- ADR-009 rule table, after `:143`. Add a row: "`LangfuseSendFailing` | `increase(otelcol_exporter_send_failed_spans{exporter="otlp_http/langfuse"}[1d]) > increase(otelcol_exporter_sent_spans{exporter="otlp_http/langfuse"}[1d])` | failures above sends over a day | 1 h | info | Langfuse blocks or refuses the fleet's spans and nobody notices, because its failed sends page no one".
- ADR-009 `:135`. Append: "`<kept-alive labels>` is the union of every darwin row's kept-alive list".

### D12: Verification
**What Linux proves (no darwin VM runs)**:
- **Identity of the seam (D1)**: the hashes of D1's acceptance, before and after, and unchanged toplevels of every host but those named per commit.
- **Equality of the pipelines (D27)**: a clause `agentSessionEqualsPyrite` in `checks.x86_64-linux.otel-collector-darwin` evaluates `darwinConfigurations.stibnite.config.vanixiets.otelCollector.agentSessionSettings` (the same Linux-side evaluation the check already makes, `modules/checks/otel-collector-darwin.nix:93-105`), normalises `host.name` values, TLS `cert_file`/`key_file`, the `basicauth` file paths, `file_storage.directory` and queue sizes, and requires equality with pyrite's settings normalised the same way. Mutant `stibniteProcessorDropped` (one processor removed from stibnite's copy) fails it.
- **Validation**: Linux `otelcol-contrib validate` over stibnite's rendered agent-session file, as the check already does for the fleet files (README `:457`).
- **Darwin assertions**, forced on Linux by evaluating `darwinConfigurations.stibnite.config.assertions`, each seen failing under an `extendModules` mutant: the daemon's exporters queue in `file_storage` by bytes with unlimited retry and hold 24 h, 8 h and 3 h at the assumed rates; its queues sum below 512 MiB; limiter < `GOMEMLIMIT`; every receiver, telemetry listener and exporter on loopback but the two ingress exporters and Langfuse; no fleet receiver on 4318; the daemon runs as `_otelagent` and the Langfuse files are its, 0400; the key is `_otelcert` 0440; the envelope is in `notifiedUnits`; the per-host kept-alive equality; one fleet-executable glob per daemon.
- **Emitters**: `agent-telemetry-emitters` moves stibnite's crs58 home to the flagged set with `user.name=cameron`, adds omnigent-cameron's standalone home with `user.name=cameron`, keeps rosegold and argentum unflagged; a mutant that drops the alias derivation fails it naming `crs58`.
- **VM tests on pyrite**: `fleet-ingress`'s `agentSpans` and `langfuse` cases gain `skill_description` and `mcp_namespace_hint` root spans (stored with their column, not received by the Langfuse sink) and a `compaction_summary` span (received, without the key); the uncommitted mutants `langfuseOneshotKept` and `oneshotKeySent` fail their case; `handoffCap` reruns at the 12 MiB span queue; the full test passes.
- **Checks**: `otel-collector-config` (ingress queues at three hosts with mutant `agentQueueShortThreeHosts`), `otel-envelope` (the darwin agent variant with C5 for `org.nixos.otel-agent-session`, cases at the limit ±1 MiB), `fleet-alert` (legs `langfuseBlocked`, `langfuseHealthy`, `agentSessionKeptAlive` on stibnite, `rosegoldNoAgentSession`).
- **Load proof**: D4's runs at 12 and 16 senders; acceptance: zero fleet points refused, zero host-collector restarts, and the agent process's resident peak recorded per scenario.

**What only the live Mac proves, after the operator's deploy**:
- launchd loads `org.nixos.otel-agent-session` as `_otelagent`, and it reads the sops files; `lsof -iTCP -sTCP:LISTEN -P` shows 4318 held by it and 4319 by `otelcol`;
- the daemon's mTLS export over ZeroTier: `otelcol_exporter_sent_*` rising on `127.0.0.1:8890`, queues draining to 0;
- a real omp session and a real Claude Code session, each with a unique word in its prompt, found in GreptimeDB (`obs-query sql agent` with `matches_term` on `span_attributes.last_user_message` and on `session_event.prompt`) with `host_name` `stibnite` and `user_name` `cameron`, and the same traces in Langfuse (`langfuse-query`), the startup-request spans absent from Langfuse and present in `agent_span`;
- `fleet` still receiving stibnite's `process_memory_usage_bytes` through 4319 at the same per-minute count as the hour before;
- the footprint under real use (C5's readings) and, if tried, whether `JetsamMemoryLimit` is honoured;
- queue drain after a wake off the mesh;
- which desktop and IDE harnesses export (D10).

## Risks / Trade-offs

- [Risk] No memory ceiling: a runaway daemon at this Mac's concurrency (p99 12, up to 30) causes Mac-wide memory pressure before C5 notices, every 5 minutes while awake. → Process isolation protects fleet signals; the soft bounds hold the steady state; the load proof at 12 and 16 measures the peaks first; the operator accepts or refuses (Q2).
- [Risk] The ingress re-budget lands late: stibnite's flag fails `otel-collector-config` until magnetite's queues fit three hosts. → Stage 1 ships it first; the check makes the order mechanical.
- [Risk] Langfuse quota: about 155,000 units a month from stibnite alone; a block stops Langfuse for every host. → Accepted by the operator (D24); D9 makes it visible at low priority within a day and an hour.
- [Risk] Off-mesh beyond a week of average use, or a heavy week, overflows the span queue and drops the oldest spans. → The queue's drop counters show it; the store still gets the newest week.
- [Risk] Bind race at the switch between `otelcol` releasing 4318 and the daemon taking it. → `KeepAlive` with `ThrottleInterval = 5` retries; emitters lose seconds.
- [Risk] Harnesses outside the repository's management (the desktop app, the IDE extension) export with a different Claude Code build's keys. → The allow-lists bound what leaves the host (`agent-session-telemetry` requirement `Only allow-listed session content leaves a host`).
- [Risk] The derived person mis-stamps a home whose name is an alias value of someone else. → Only `cameron = "crs58"` exists; `agent-telemetry-emitters` pins the stamped names of every evaluated home.
- [Trade-off] Without a darwin VM, only the live switch shows launchd, the sops files and the bind order. → The equality check makes everything above launchd the code pyrite runs; the operator's console deploy is watched with a stated rollback.
- [Trade-off] stibnite's agent queues can take up to 404 MiB of its disk. → Under the 512 MiB budget ADR-003 sets per collector process.

## Migration Plan

The host table, `schema.nix` and the shared `langfuse` var are data that several closures read, so each host's behaviour changes only when it deploys; every host whose toplevel changes is named below and checked against the identity log.

**Stage 1 (NixOS; agents deploy)**
1. Commit the seam (D1) alone; record the identity hashes.
2. Commit D8 (oneshot key, column, Langfuse filter), D6 (per-host kept-alive, no rendered change) and D9 (scrape and rule), with their checks, the VM cases and mutants; these deploy without waiting for Q1. D7's ingress re-budget is a commit of its own at the top of stage 1, and its magnetite deploy waits for the operator's Q1 answer; it must be deployed before stage 2 flips stibnite's flag, which the queue check enforces.
3. Publish (the operator's approval of the pull request).
4. Deploy magnetite: before, read every ingress queue's `otelcol_exporter_queue_size` on `127.0.0.1:8888` and expect 0 for those that shrink (`fleet` 400 → 382); after, the schema job's `ADD COLUMN` for the oneshot column, then the 15-minute watch of `agent-session-telemetry` task 5.1 (ingest per database against the hour before, queue sizes and send failures, the collector's memory, every `fleet-alerts` post since the deploy with its cause).
5. Deploy pyrite with the same watch; its agent unit's span hand-off is now 3 MiB.
6. Verify: an omp session's two startup-request spans on pyrite are in `agent_span` with their kinds and absent from Langfuse; `otelcol_exporter_sent_spans{exporter="otlp_http/langfuse"}` is stored in `fleet` for both hosts.
- **Rollback, stage 1**: pyrite first, then magnetite, each to its previous revision after its queues read 0. The oneshot column stays (the schema job only adds), harmless to an older collector that does not send the key; the rule and scrape go with the revision.

**Stage 2 (stibnite; the operator deploys)**
1. The load proof (D4) at 12 and 16 senders; set the C5 limit from it.
2. Commit the port move (D2), the daemon, account, envelope and assertions (D3, D4), the credentials with the `clan vars fix` recipient files (D5), stibnite's flags `agentTelemetry` and `langfuse` and `agentSpanQueueMiB = 256` (D7), the emitters and the darwin worker (D10), the equality and darwin checks (D12).
3. Publish (the operator's approval).
4. Deploy magnetite: its `LaunchdJobNotRunning` and `LaunchdJobFailed` render from the new union and notified units; nothing else on magnetite changes. pyrite's toplevel must not change; if the identity log shows it does, the reason is recorded before deploying it. rosegold's and argentum's toplevels change only by the probe's allow-list input (D6), which selects no new label there; they pick it up at their next deploy, with no effect.
5. The operator runs `darwin-rebuild switch` on stibnite at the console.
6. Watch for 15 minutes, as `agent-session-telemetry` task 5.3: `launchctl print system/org.nixos.otel-agent-session` (running, `_otelagent`), `lsof` for 4318 and 4319, `curl -s 127.0.0.1:8890/metrics` for queue sizes and sent counts, `fleet`'s process series from stibnite, every `fleet-alerts` post since the switch with its cause; then the live checks of D12.
- **Rollback, stage 2**: the operator switches stibnite to its previous generation (`darwin-rebuild switch --rollback`); the fleet collector returns to 4318 at its reload and the daemon is unloaded; `/var/lib/otel-agent-session` and `/var/log/otel-agent-session` are left orphaned and removed by hand; the recipient files can stay. magnetite's stage 2 change is harmless and stays.

## Open Questions

- **Q1, the ingress queue re-budget (recommended, awaiting the operator)**: `fleet` 400 → 382 MiB (still 26.1 h against its 24-hour rule), `agent_session_event` 32 → 46 MiB, `agent_span` 8 → 12 MiB, `agent` unchanged at 16 MiB; the sum stays 508 MiB (D7). The agent-session collectors' span hand-off batch, a quarter of `agent_span`, becomes 3 MiB on magnetite and pyrite. The figures the question was first put with need two corrections: the 508 of 512 MiB is the ingress's queue budget on disk, not its process memory; and 16 MiB from `fleet` covers the need only if the sum rises to 509 or 510 MiB, still under 512. The alternative is a per-host rate in the host table. Only magnetite's deploy of the re-budget waits for the answer; the rest of stage 1 does not.
- **Q2, no hard memory ceiling on macOS (recommended, awaiting the operator)**: accept that on stibnite the agent-session daemon has no enforced ceiling, under D29's conditions: process isolation from the fleet collector, `GOMEMLIMIT` 409 MiB and the 384 MiB limiter, the C5 footprint notice at the D4 limit, and the load proof at 12 and 16 senders recorded before stage 2 ships. `JetsamMemoryLimit` is tried as an experiment and kept only if shown honoured.
- The C5 limit's final value, from the load proof (D4).
- Which desktop and IDE harnesses export, read after the deploy (D10).
