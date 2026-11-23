# Brainstorm: agent session telemetry on stibnite

Decision log, 2026-11-23.
Sources: the operator's decisions D22 and D24 (2026-11-23) in the orchestrator's decision record, the orchestrator's design decisions D25–D30 taken from them, and the read-only survey of this repository and of stibnite made for this change on 2026-11-22 (the priming, `local://telemetry-stibnite-priming.md`, sections 1–11).
It extends `agent-session-telemetry`, whose design D8, D9, D14, D15 and D16 are deployed on magnetite and pyrite (that change's "As deployed", 2026-11-22), and carries out that change's task 7.2, which says a separate change carries stibnite.
Numbers marked [INFERENCE] were computed from estimates or read from source without being run.

## Driver

stibnite is the operator's main workstation.
On it omp logged 621 session-hours in 30 days, 20.7 a day or 0.86 sessions on average at any moment, and Claude Code 10.4 session-hours in 90 days (`agent-session-telemetry` design D15 Volume and D16 Volume; the priming §7).
Today none of that is recorded: the fleet records agent sessions only on the two servers, magnetite and pyrite, where the operator runs fewer of them.
On 2026-11-23 the operator made stibnite the priority (D22) and set its scope (D24): stibnite only, behind the same per-host flags `agentTelemetry` and `langfuse`, so that another Mac is a one-line change; stibnite's agent spans also go to Langfuse Cloud; omp's startup skill-summary requests go to GreptimeDB but not to Langfuse, on every host; the Hobby allowance will be exceeded, and a block would stop Langfuse data for every host, silently on our side.

## What differs on darwin

Seven things separate stibnite from the two NixOS hosts the agent-session collector already runs on.

1. **Port 4318 is taken.** The fleet collector `org.nixos.otelcol` listens on `127.0.0.1:4318`, and its only client is the root `otelcol-process`, which forwards the process memory points to it (`modules/lib/otel-collector-darwin.nix:129,308`; live `netstat` on stibnite, 2026-11-22: `otelcol-contrib` on `127.0.0.1:4318` and `:8888`, nothing on 4319–4322, 8889 or 8890). That receiver feeds `metrics/host`, so an emitter pointed at it today would put Claude Code or omp metrics into `fleet` unfiltered.
2. **launchd has no memory ceiling for our daemons.** There is no cgroup. nix-darwin exposes `setrlimit` keys only; `ResidentSetSize` is advisory by its own description (`nix-darwin/nix-darwin modules/launchd/launchd.nix:492-499`, `man launchd.plist` on stibnite); `Data` bounds `sbrk`, which Go's heap does not use [INFERENCE]. `launchctl print` shows `jetsam memory limit (active) = (unlimited)` for both collectors. Apple's own daemons set `JetsamProperties.JetsamMemoryLimit`; whether launchd honours it in a third-party plist on macOS 26 is unverified. ADR-003 already records it: "launchd cannot enforce a process-tree memory ceiling" (`ADR-003-collection-topology.md:24`).
3. **Sleep, travel and the mesh.** stibnite sleeps 90–130 times a day. Asleep, sessions are suspended and nothing arrives, so sleep costs no queue. Awake off the mesh (travel, a network that blocks ZeroTier) the store path queues and Langfuse, which needs only the internet, keeps receiving. At the NixOS sizes the span queue, 44 MiB, holds about 30 hours of stibnite's average use; a weekend of normal use off the mesh, about 75 MB, would overflow it and lose the oldest 29 MB (the priming §7, [INFERENCE] from the `schema.nix` rates).
4. **No VM test.** No darwin VM runs in CI. Linux can evaluate stibnite's configuration and validate its rendered collector files, but only a live switch shows launchd loading the job, the bind order, the mTLS export over ZeroTier and the real footprint.
5. **Credentials.** sops-nix on darwin writes files that the daemon's account reads directly: no `LoadCredential`, no `restartUnits` (clan throws on it for darwin, `modules/clan/services/otel-collector/flake-module.nix:1961-1962`). The shared `langfuse` var's recipients are magnetite, pyrite and the operator's user key; `flake.lib.sharedVarsObligations` fails a darwin host that deploys a shared secret it cannot decrypt.
6. **One kept-alive list for every Mac.** `schema.launchdKeptAlive` is global, and each darwin host asserts that it equals its own kept-alive allow-listed labels (`modules/darwin/otel-collector-agent.nix:298-301`). Adding the new daemon to it breaks rosegold's and argentum's evaluation; leaving it off leaves the daemon unwatched by `LaunchdJobNotRunning`.
7. **The ingress budget at three hosts.** `otel-collector-config` multiplies the ingress's agent queue minimums by the number of hosts whose row sets `agentTelemetry` (`modules/checks/otel-collector-config.nix:467-469,1014-1026`). At three hosts the events queue needs 2 × 60 × 3 × 133,000 = 47,880,000 B (45.7 MiB) against its 32 MiB, and the span queue 15 × 3 × 240,000 = 10,800,000 B (10.3 MiB) against 8 MiB; the metrics queue needs 12,902,400 B (12.3 MiB) of its 16. The ingress's queues already sum to 508 of the 512 MiB disk budget (`modules/clan/services/otel-collector/README.md:274`). Flipping stibnite's flag fails that check until magnetite's queues are re-budgeted.

## Choices, one per difference

### Q1: How do the agent-session settings reach a darwin daemon? (D26a)

The settings are built inline in the NixOS module under `lib.mkIf agentTelemetry` (`flake-module.nix:731-1404`); their free variables are module-scoped, but only the credential paths and the queue directory are platform-specific (the priming §2).

- **Chosen: a library function of host facts**, `flake.lib.agentSessionCollector`, as `flake.lib.otelCollectorDarwin` already is for the fleet agent. The NixOS module calls it with its `/run/credentials` paths, the darwin fragment with the sops paths. Accepted only if pyrite's and magnetite's evaluated settings and `serviceConfig` hash identically before and after.
- Rejected: a second copy of the settings in the darwin fragment. Two copies of 15 processors and three pipelines would drift, and the store's closed column set would then refuse whatever one copy sends that the other does not.
- Rejected: importing the NixOS module on darwin. It sets systemd options that do not exist there.

### Q2: Who holds 127.0.0.1:4318 on the Mac? (D27)

- **Chosen: move the fleet collector's `otlp` receiver and `otelcol-process`'s exporter to `127.0.0.1:4319`**, and give 4318 to the new daemon. Two endpoint literals change and no pipeline, queue or exporter; `file_storage` keys are exporter names, so no queue moves. 4318 stays the agent-session receiver on every host (ADR-003 item 3), so the emitter module needs no per-platform endpoint. It also removes today's hazard of an emitter feeding `fleet`.
- Rejected: the new daemon owns 4318 and forwards the process points. `otlp/local` would feed a fourth pipeline, breaking the invariant that it feeds only the three agent-session pipelines; `filter/agent-session-service` would drop the points anyway (no `service.name`); and the fleet's process memory would depend on the agent daemon's health, the opposite of D14.
- Rejected: one receiver routing by `service.name`. One heap and one limiter: the load proof of `agent-session-telemetry` D14 showed exactly this losing fleet points.
- Rejected: the daemon on another port. It keeps the fleet configuration literally unchanged, but makes the emitter endpoint per-platform, a second convention, and leaves the hazard.

### Q3: Which account runs the daemon? (D27)

D27 asks to mirror the NixOS agent unit relative to the fleet collector unless the evidence says a dedicated account is needed to keep the Langfuse key from the fleet collector.
On NixOS each collector unit is its own `DynamicUser`, and only `otel-agent-session.service` loads `langfuse-public-key` and `langfuse-secret-key` (`flake-module.nix:1018,2005-2042`): the fleet collector cannot read them.
On darwin, sops-nix files are protected by owner and mode alone. If the daemon ran as `_otelcol`, the Langfuse files would be `_otelcol` 0400 and the fleet collector, the envelope and anything else running as `_otelcol` could read them.

- **Chosen: a dedicated account `_otelagent`** (uid and gid 537, free in the repository and on stibnite, read with `dscl` on 2026-11-23). The Langfuse files are `_otelagent` 0400. The mTLS key, which both collectors present, moves to owner `_otelcol`, group `_otelcert` (gid 538, members `_otelcol` and `_otelagent`), mode 0440, on flagged hosts only. This mirrors NixOS, where both units get the certificate and only the agent unit gets Langfuse's keys.
- Rejected: `_otelcol`. Simplest, and the certificate works unchanged, but the fleet collector's account then holds the Langfuse key, which NixOS deliberately avoids.
- Rejected: a second per-machine certificate for the daemon. It needs a second generator and CA issuance for the same host name, for no gain over a shared group.

### Q4: How large are stibnite's queues? (D28)

The agent-session daemon has its own 512 MiB disk budget (ADR-003's buffering envelope, per collector process).
At average use stibnite sends about 37.3 MB of spans a day (20.7 omp session-hours × 1.8 MB, plus 0.05 MB of Claude Code spans), at most 5.8 MB of metrics and 0.12 MB of events [INFERENCE from `schema.nix`'s per-session-hour estimates; the rates are unmeasured].

- **Chosen**: spans 256 MiB (268,435,456 B ÷ 37.3 MB a day = 7.2 days of average use; 18.6 h at the asserted 240,000 B/min), metrics 52 MiB (9.4 days at average use; 25.4 h at the asserted rate), events 64 MiB (months at average use; 8.4 h at the asserted rate), Langfuse 32 MiB as on NixOS. Sum 404 MiB of 512.
- Rejected: the NixOS sizes. 44 MiB of spans is about 30 h of average use, so a weekend off the mesh overflows.
- Rejected: spans at 340 MiB, the most the budget allows beside the others. A week is the operator's target; the rest is headroom.

### Q5: What bounds the daemon's memory on macOS? (D29)

The NixOS unit's guarantee rests on `MemoryMax = 512M` with no swap and an `OOMScoreAdjust` kill order. Neither exists on darwin.

- **Chosen: process isolation plus the in-process soft bounds plus detection.** A separate process removes the mechanism by which agent traffic cost fleet points in D14 (one heap, one limiter). `GOMEMLIMIT=409MiB` and the 384 MiB `memory_limiter` stay. A footprint clause (the darwin envelope's C5) fails above a stated limit and posts a failure notice. Before stage 2 ships, the Linux load proof is extended to 12 and 16 concurrent senders, since this Mac's own p99 is 12 sessions active per 5 minutes (up to 30), against the 8 the D14 proof used. The C5 limit is set from that proof. Pending the operator's acceptance (design Q2).
- Optional experiment, not a dependency: `JetsamProperties.JetsamMemoryLimit` on the daemon, kept only if `launchctl print` shows it honoured.
- Rejected: `ResidentSetSize`, `Data` or `HardResourceLimits`. Advisory, or irrelevant to Go's heap, or a start-up failure risk.
- Rejected: waiting for a hard ceiling before stibnite records anything. None is known to exist for a third-party daemon.

### Q6: How is the new daemon watched without breaking the other Macs? (D26c)

- **Chosen: the kept-alive expectation becomes per host**, the shared base list plus `org.nixos.otel-agent-session` on rows that set `agentTelemetry`. Each Mac asserts against its own list; `LaunchdJobNotRunning` reads the union, which selects nothing on a Mac that runs no such daemon, because its probe writes only labels its own `launchd.daemons` defines.
- Rejected: enabling every collecting Mac together. Against D24's scope, and Christopher's consent is not recorded.
- Rejected: leaving the daemon off the list. Unwatched.

### Q7: How do the ingress queues fit three hosts? (D26d)

- **Recommended, awaiting the operator (design Q1)**: take bytes from the `fleet` metrics queue, which has 50,790,400 B (48.4 MiB) more than its 24-hour rule needs (400 MiB against 24 × 60 × 256,000 = 368,640,000 B). Events 32 → 46 MiB, spans 8 → 12 MiB, `fleet` 400 → 382 MiB: the sum stays 508 MiB and `fleet` still holds 26.1 h. The orchestrator's 16 MiB from `fleet` is not enough to keep the sum at 508: the two queues need 18 MiB together, because the span queue must be a multiple of 4 MiB (see design D7).
- Alternative: a per-host rate in the host table, so stibnite counts at its own lower rate. More precise, but it adds a field every host row carries and a second rate convention, for a 4 MiB difference.

### Q8: How are skill-summary requests kept out of Langfuse? (D24, D26b)

omp opens a chat span for each oneshot request, sets `omp.gen_ai.oneshot.kind` on it, and the startup skill-description compressor's requests carry `skill_description` (`can1357/oh-my-pi` `packages/agent/src/telemetry.ts:1843-1865`, `packages/coding-agent/src/extensibility/skill-descriptions.ts:131-147`). The span allow-list does not keep that key, so at `filter/langfuse` such a span cannot be told from other chat spans.

- **Chosen, exact**: keep `omp.gen_ai.oneshot.kind` in the span allow-list (a new `agent_span` column through the schema job's `ADD COLUMN IF NOT EXISTS`), drop on the Langfuse branch spans whose value is on a listed set, which holds `skill_description`, and delete the key in `transform/langfuse`. The column also lets GreptimeDB split oneshot cost by kind.
- Revised by the orchestrator on 2026-11-23: the list holds both startup kinds, `skill_description` and `mcp_namespace_hint`, which come from the same compressor at session start and are the same noise; compaction, handoff and the other oneshot kinds are still sent.
- Rejected: drop parentless `chat` spans of `oh-my-pi`. No schema change, but it also drops every other parentless oneshot (MCP namespace hints, possibly job captions and evaluator completions) and relies on `IsRootSpan`, unchecked at 0.155.0.

### Q9: How is a Langfuse quota block seen? (D24, D26e)

At about 155,000 units a month from stibnite alone (621 session-hours × about 250 units), three times Hobby's 50,000, and with magnetite and pyrite on top, the fleet will likely reach the 250,000 units at which Langfuse's server code blocks ingestion for the cycle (enforcement on Cloud unverified, world assumption A205). Every request is then answered 403, which the exporter drops at once and no envelope pages on.

- **Chosen: a non-paging daily rule.** The host collector keeps two series of the agent-session daemon's own telemetry, Langfuse's sent and failed spans, in `fleet`; the evaluator's new rule fires at severity `info` (ntfy priority `low`) when a day's failures outnumber its sends.
- Rejected: paging. A Langfuse outage costs no store data and must not wake anyone (`agent-session-telemetry` D16).
- Rejected: nothing. The block would stay silent until the operator opened Langfuse.

### Q10: Who on stibnite emits, and as whom? (D27, D30)

- The operator's home is `crs58`, and the fleet names the same person `cameron` (`modules/home/users/aliases.nix:18-21`). **Chosen**: the emitter module derives the person through `flake.userAliases`, so crs58's sessions stamp `user.name=cameron`; elsewhere the default is unchanged.
- The omnigent worker `omnigent-cameron` is a standalone home with `osConfig = null` (`modules/darwin/omnigent-host.nix:103-115`), so today its emitter gate is off and its person lookup would throw. **Chosen**: an explicit `agentTelemetry.enable` option, defaulting from `osConfig`, which the darwin worker builder sets from the host's row, with `agentTelemetry.person = worker.owner`.
- Desktop and IDE harnesses that read `~/.claude/settings.json`, the Claude desktop app's local Claude Code sessions and the VS Code extension among them, will export too [INFERENCE]: that is within "all sessions" (D30). Which do is read live after the deploy.

## Staging (D26, D27)

Stage 1 changes only NixOS hosts and deploys to magnetite, then pyrite, before any Mac change: the seam with its identity proof, the oneshot key with its column and Langfuse filter, the per-host kept-alive list, the ingress re-budget, and the non-paging rule.
Stage 2 is the Mac: the port move, the daemon and its account, the credentials with `clan vars fix`, the emitters, the darwin worker, the equality check and the darwin checks, deployed by the operator's `darwin-rebuild switch` at the console.

## Out of scope

Other Macs (the flags make each a one-line change; Christopher's consent is not recorded), Claude's cloud sessions, a self-hosted Langfuse, and a hard memory ceiling on macOS.
