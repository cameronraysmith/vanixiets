# Agent session telemetry on stibnite implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** stibnite's Claude Code and omp sessions, crs58's as `cameron` and omnigent-cameron's, reach `agent` and Langfuse through the same agent-session pipelines magnetite and pyrite run, while the Mac's fleet signals are unchanged; and omp's two startup requests (`skill_description`, `mcp_namespace_hint`) stop reaching Langfuse from every host (tasks.md groups 1–14).

**Architecture:** the agent-session settings become `flake.lib.agentSessionCollector`, a pure function of host facts, called by the NixOS agent role (unchanged output, proven by hashes) and by the darwin fragment, which runs it as the launchd daemon `org.nixos.otel-agent-session` under `_otelagent` on `127.0.0.1:4318` after the fleet collector moves to 4319.
Stage 1 (NixOS only) ships the function, the oneshot key and Langfuse filter, the per-host kept-alive list, the ingress queues for three hosts and the Langfuse send-failure rule; stage 2 ships the Mac.

**Tech Stack:** flake-parts with import-tree; NixOS, nix-darwin and home-manager modules; clan vars with sops-nix; `otelcol-contrib` 0.155.0 (`filter`, `transform`, `file_storage`, `basicauth`, OTTL); GreptimeDB 1.2.1 `greptime_trace_v1`; launchd; `pkgs.testers.runNixOSTest`.

**Spec:** `openspec/changes/darwin-agent-session-telemetry/` — `design.md` (D1–D12), `specs/`, `tasks.md`, `brainstorm.md`, `proposal.md`.

## Global Constraints

- Two stacked chains, each commit evaluating, building and passing its checks alone: stage 1 (tasks 1–6), then stage 2 (tasks 8–12); the seam (task 1.2) is the first commit of stage 1 and changes no evaluated value. Edits are made in `@` and routed with `jj squash --into <chain> --use-destination-message --keep-emptied <paths>`.
- Stage 2 does not start until stage 1 is deployed on magnetite and pyrite (task 6.5), the load proof is recorded (task 7.1) and the operator has answered Q2.
- The ingress sizes (task 4.2) wait for the operator's Q1 answer.
- No `clan machines update` of stibnite and no `darwin-rebuild` by an agent: stibnite's switch is the operator's at the console. No `clan vars generate` for `langfuse`: only `clan vars fix stibnite --generator langfuse`.
- x86_64-linux builds on magnetite (`--eval-store auto --store ssh-ng://magnetite.zt`); VM tests on pyrite (`--store ssh-ng://pyrite.vanixiets.internal`); logs under `logs/darwin-ast-*`.
- Every regulator is seen failing on a mutant before it is trusted; each mutant runs only the clause or case it must fail.
- Hosts whose toplevel `drvPath` changes are named per commit with the reason; any other is a finding.

## Grounding: the vendored consumers' argument lists

- The darwin daemon runs `otelcol-contrib --config <file>`, the form the existing `org.nixos.otelcol` daemon uses (`modules/darwin/otel-collector-agent.nix:154-158`); the NixOS unit runs `otelcol-contrib --config=file:<file>` (`modules/clan/services/otel-collector/flake-module.nix:1017`). The pre-deploy probe of stibnite's rendered file is `otelcol-contrib validate --config <file>`, as `checks.x86_64-linux.otel-collector-darwin` runs it on Linux for the fleet files.
- launchd reads `UserName`, `GroupName`, `KeepAlive`, `RunAtLoad`, `ThrottleInterval`, `ProcessType`, `EnvironmentVariables`, `StandardOutPath` and `StandardErrorPath` from the plist nix-darwin writes (`nix-darwin/nix-darwin modules/launchd/launchd.nix`); the probe after the switch is `launchctl print system/org.nixos.otel-agent-session`, whose fields the fleet probe already parses (world assumption A62).
- clan: `clan vars fix <machine> --generator <generator>` adds the machine's age key and re-encrypts with the value unchanged (`docs/notes/development/observability/charter.md:344`).

## Interface contract

| Kind | Name | Defined in |
|---|---|---|
| Lib | `flake.lib.agentSessionCollector { hostName; ingress ? false; caFile; certFile; keyFile; queueDirectory; queueBytes ? { metrics = 52 MiB; events = 64 MiB; spans = 44 MiB; langfuse = 32 MiB; }; telemetryPort ? 8890; langfuse ? null; }` → `{ settings; queueBytes; limiterMib = 384; goMemLimitMib = 409; ceilingMib = 512; }` | Task 1 |
| Lib | `flake.lib.agentSessionAssertions { settings; goMemLimitMib; ceilingMib ? null; langfuse; handoffQueueBytes; }` → list of `{ assertion; message; }` with no systemd reference | Task 1 |
| Schema | `agentSession.spans.keys."omp.gen_ai.oneshot.kind" = "string"`; `agentSession.langfuse.droppedOneshotKinds = [ "skill_description" "mcp_namespace_hint" ]`; `otelcolAgentSessionKeep = [ "otelcol_exporter_sent_spans" "otelcol_exporter_send_failed_spans" ]` | Tasks 2, 5 |
| Lib | `flake.lib.launchdKeptAlive : hostName → listOf str` | Task 3 |
| Host table | `agentSpanQueueMiB : int`, default 44, stibnite 256; stibnite `agentTelemetry = true`, `langfuse = true`, `notifiedUnits` gains `otel-agent-session-envelope` | Tasks 8–10 |
| Option | darwin `vanixiets.otelCollector.agentTelemetry : bool`, set by the agent role's darwin module from the row | Task 8 |
| Daemon | `launchd.daemons.otel-agent-session` (`_otelagent`, 537) and `launchd.daemons.otel-agent-session-envelope` (`_otelcol`); group `_otelcert` (538) | Task 8 |
| Home | `agentTelemetry.enable : bool` (default from `osConfig`); `agentTelemetry.person` default from `flake.userAliases` | Task 10 |
| Rule | `LangfuseSendFailing` (`info`, `for = "1h"`) | Task 5 |

## Review Focus

- The seam changes nothing it should not: every hash of task 1.1 equal at task 1.2.
- A stibnite copy drifting from pyrite's: `agentSessionEqualsPyrite` normalises only host names, credential and queue paths and queue sizes.
- The Langfuse key readable by `_otelcol` on stibnite: the fragment's owner and mode assertion.
- The span hand-off batch tracking the ingress's span queue (`queueBytes.agent_span / 4`) after the re-budget.
- A startup-request span with children in a later omp: the cases in `agentSpans` use root leaves only (A211's violation condition).

---

## Task 1: The settings function (stage 1)

**Files:** Create `modules/lib/agent-session-collector.nix`; Modify `modules/clan/services/otel-collector/flake-module.nix`.

- [ ] **Step 1:** Record the twelve hashes and ten `drvPath`s of tasks.md 1.1 to `logs/darwin-ast-identity-before-<ts>.log`.
- [ ] **Step 2:** Move the body of `agentSessionSettings` (`flake-module.nix:731-1404`) into the function, its free variables becoming the signature's arguments; move the settings-only assertions (`:893-993`) into `agentSessionAssertions`, the `MemoryMax`/`Environment` clause taking numbers.
- [ ] **Step 3:** Call both from the NixOS agent role with `/run/credentials/otel-agent-session.service/*`, `/var/lib/otel-agent-session/queue` and the unit's numbers.
- [ ] **Step 4:** Re-record and `diff` against Step 1: empty. Commit.

## Task 2: Oneshot kind and the Langfuse filter (stage 1)

**Files:** Modify `schema.nix`, `modules/lib/agent-session-collector.nix`, `modules/checks/otel-collector-config.nix`, `modules/vm-tests/fleet-ingress.nix`, `modules/vm-tests/fleet-ingress/helpers.py`.

- [ ] **Step 1:** Add the key and `droppedOneshotKinds`; `nix eval --raw` of magnetite's `services.greptimedb.tables.agent` shows the `ADD COLUMN IF NOT EXISTS` for it.
- [ ] **Step 2:** Write the mutants `langfuseOneshotConditionDropped` and `langfuseOneshotKeyKept` and see them fail before the clause exists in its final form.
- [ ] **Step 3:** `filter/langfuse` condition matching `span.attributes["omp.gen_ai.oneshot.kind"]` against each value of the list (`skill_description`, `mcp_namespace_hint`) and `delete_key(span.attributes, "omp.gen_ai.oneshot.kind")` in `transform/langfuse`.
- [ ] **Step 4:** `otelcol-contrib validate --config` on both hosts' rendered agent-session files at 0.155.0.
- [ ] **Step 5:** `agentSpans`/`langfuse`: `skill_description` and `mcp_namespace_hint` root `chat` spans and a `compaction_summary` span; run the full test on pyrite; then the uncommitted mutants `langfuseOneshotKept` and `oneshotKeySent`.

## Task 3: Per-host kept-alive (stage 1)

**Files:** Create the function beside `schema.nix`'s list (`modules/clan/services/otel-collector/schema.nix` or `modules/lib/observability-hosts.nix`); Modify `modules/darwin/otel-collector-agent.nix`, `modules/nixos/fleet-alert/rules.nix`.

- [ ] **Step 1:** The function and the fragment's assertion over it.
- [ ] **Step 2:** The rule's union; `nix eval` of magnetite's rendered rules and the three Macs' `drvPath`s unchanged.
- [ ] **Step 3:** The rosegold `extendModules` mutant fails with the fragment's message.

## Task 4: Ingress queues (stage 1, after Q1)

**Files:** Modify `flake-module.nix` (`queueBytes` and its comment), `modules/checks/otel-collector-config.nix`, `modules/clan/services/otel-collector/README.md`.

- [ ] **Step 1:** Mutant `agentQueueShortThreeHosts` (three flagged rows, today's sizes) fails the agent-queue clause.
- [ ] **Step 2:** Apply the answered sizes; the check passes; `nix eval` of the sum.
- [ ] **Step 3:** `handoffCap` on pyrite at the new span queue.

## Task 5: Langfuse send-failure rule (stage 1)

**Files:** Modify `schema.nix`, `flake-module.nix` (the scrape job), `modules/nixos/fleet-alert/rules.nix`, `modules/checks/otel-collector-config.nix`, `modules/checks/fleet-alert.nix` and its fixtures.

- [ ] **Step 1:** The keep-list mutant and the `fleet-alert` legs and severity mutant, seen failing first.
- [ ] **Step 2:** The scrape job on `langfuse` hosts; the identity diff names it alone for pyrite.
- [ ] **Step 3:** The rule; `promtool check rules`; both legs.

## Task 6: Publish and deploy stage 1

- [ ] **Step 1:** Build every check of tasks.md 6.1 and the full `fleet-ingress` once.
- [ ] **Step 2:** Publish; after merge, tasks.md 6.2–6.5 in order, each with its log.

## Task 7: Load proof (before stage 2)

- [ ] **Step 1:** Extend the harness's plan with 12 and 16 senders and a variant of pyrite's unit with `MemoryMax`/`MemorySwapMax` removed; run on pyrite.
- [ ] **Step 2:** The backlog case at a 256 MiB span queue.
- [ ] **Step 3:** Record the table in design D4 and set C5's limit.

## Task 8: The port and the daemon (stage 2)

**Files:** Modify `modules/lib/otel-collector-darwin.nix`, `modules/darwin/otel-collector-agent.nix`, `flake-module.nix` (darwin module: accounts, group, key mode), `modules/checks/otel-collector-darwin.nix`, `modules/lib/otel-envelope.nix` if C5 needs a third label, `modules/checks/otel-envelope.nix`, `schema.nix` (`launchdLabels`, `darwinFleetExecutables`), `modules/lib/observability-hosts.nix`.

- [ ] **Step 1:** Mutants first: fleet `otlp` on 4318, daemon as `_otelcol`, Langfuse files readable by `_otelcol`, C5 ±1 MiB.
- [ ] **Step 2:** The 4319 move and the check's literal.
- [ ] **Step 3:** Accounts, group, the daemon and its envelope, the activation pre-step, the assertions.
- [ ] **Step 4:** Evaluate `darwinConfigurations.stibnite.config.assertions` and the daemons on Linux; every mutant fails.

## Task 9: Credentials (stage 2)

- [ ] **Step 1:** The shared generator function; magnetite's and pyrite's generator unchanged by evaluation.
- [ ] **Step 2:** stibnite's flag and `clan vars fix stibnite --generator langfuse` in the same commit; `clan vars check stibnite`; `cmp -s` against magnetite's value.

## Task 10: Emitters, worker, equality (stage 2)

**Files:** Modify `modules/home/ai/agent-telemetry.nix`, `modules/home/ai/omnigent/worker.nix`, `modules/darwin/omnigent-host.nix`, `modules/checks/agent-telemetry-emitters.nix`, `modules/checks/otel-collector-darwin.nix`, `modules/lib/otel-collector-darwin.nix` (the 8890 scrape).

- [ ] **Step 1:** Mutants: alias lookup dropped, `stibniteProcessorDropped`.
- [ ] **Step 2:** `enable` and the person default; the worker builder's two settings; `mkDefault` in `worker.nix`.
- [ ] **Step 3:** The equality clause and Linux `otelcol-contrib validate --config` of stibnite's agent-session file.
- [ ] **Step 4:** The omnigent and sandbox checks of tasks.md 10.4.

## Task 11–12: Publish, the operator's switch, live verification

- [ ] **Step 1:** The toplevel diff log; publish.
- [ ] **Step 2:** Deploy magnetite; ask the operator for stibnite's switch; the 15-minute watch of tasks.md 11.2.
- [ ] **Step 3:** tasks.md 12.1–12.5, each with its log.

## Task 13–14: Closing

- [ ] **Step 1:** Present design D11's lines; apply after ratification.
- [ ] **Step 2:** README and the host table's comment.
- [ ] **Step 3:** `agent-session-telemetry` 7.2 and CAM-90; the week-later integration record; archive after `agent-session-telemetry`.
