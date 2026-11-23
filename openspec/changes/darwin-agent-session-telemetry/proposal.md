---
linear_story_id: CAM-121
linear_story_identifier: CAM-121
linear_story_title: "Record stibnite's agent sessions in the telemetry store and Langfuse"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-121/record-stibnites-agent-sessions-in-the-telemetry-store-and-langfuse
linear_story_state: Todo
linear_team: CAM
linear_project: pi-agent-environment
last_synced_state: Todo
last_synced_at: "2026-11-23T01:52:00Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-23T01:52:00Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-121 created in Todo in project d7d743a19249 (Agent environment), no label, with description seeded from proposal.md's Why and What Changes; related to CAM-120 (agent-session-telemetry, whose task 7.2 this carries out) and CAM-90 (per-host kept-alive labels, which design D6 resolves); state, project and relations confirmed by read-only view" }
---

## Why

stibnite is the operator's main workstation: omp ran 621 session-hours there in 30 days, while the fleet records agent sessions only on the two servers, magnetite and pyrite. None of stibnite's sessions reach the telemetry store or Langfuse. The operator made stibnite the priority on 2026-11-23 and set its scope: stibnite only, behind the per-host flags, so another Mac is a one-line change later; its spans go to Langfuse too; omp's startup skill-summary requests stop going to Langfuse from every host. On a Mac the collector port is taken, launchd sets no memory ceiling, the laptop leaves the mesh, and no VM test runs, so this needs its own design.

## What Changes

**Stage 1, NixOS only (magnetite, then pyrite)**
- The agent-session collector's settings become one function of host facts; magnetite's and pyrite's evaluated collectors are unchanged by it, byte for byte.
- omp's oneshot kind is stored as a span column; Langfuse no longer receives omp's two startup requests (`skill_description`, `mcp_namespace_hint`), on any host; compaction, handoff and other oneshot requests are still sent.
- Each Mac's kept-alive launchd expectation follows its own host-table row.
- The ingress's agent event and span queues grow for three agent-telemetry hosts, taken from the `fleet` queue's surplus (the operator's decision, design Q1).
- A Langfuse send-failure rule posts at low priority when a day's failures outnumber its sends.

**Stage 2, stibnite**
- From: the fleet collector holds `127.0.0.1:4318` for the root process scraper; no harness on stibnite exports.
- To: the fleet collector and the process scraper use `127.0.0.1:4319`; a new launchd daemon, under its own account, runs the same agent-session pipelines on 4318, exporting to the ingress over mTLS and to Langfuse; crs58's sessions, as `cameron`, and the omnigent worker's sessions export.
- Impact: non-breaking; the fleet collector reloads once at the switch.
- stibnite's span queue holds about a week of average use off the mesh.
- No hard memory ceiling: process isolation, the Go memory limit, the limiter and a footprint notice, with the load proof extended to 12 and 16 concurrent senders first (the operator's acceptance, design Q2).

**The operator does one thing**: the console deploy of stibnite (`darwin-rebuild switch`). Everything else, magnetite's and pyrite's deploys and the `clan vars fix` re-encryption included, is done by agents.

**Non-goals**: rosegold, argentum and any other Mac (a one-line change each later); Claude's cloud sessions; a self-hosted Langfuse; a hard memory ceiling on macOS.

## Capabilities

### New Capabilities

None.

### Modified Capabilities

- `agent-session-telemetry` (stratum: behavioral): stibnite becomes an agent-telemetry host; its outage hold is a week of average use; on a host without a memory ceiling an overload costs memory headroom and is reported; Langfuse is not sent omp's startup requests; a Langfuse block reaches a person without paging; a darwin host's own series keep arriving.
- `agent-session-telemetry-interface` (stratum: interface): the settings function and its equality check; the darwin daemon, its port, account, credentials, queues and footprint clause; the emitters' explicit enable and person; the Langfuse oneshot filter; the ingress queues at three hosts; the Langfuse send-failure series. Trust boundary: these properties reach as far as evaluation on Linux, `otelcol-contrib validate`, the VM tests and the live reads after the console deploy; nothing here bounds a Mac's memory, and nothing proves which harnesses on a Mac read the settings.
- `fleet-alerting-interface` (stratum: interface): `LaunchdJobNotRunning`'s kept-alive labels follow each host's row; a new `info` rule reads Langfuse's sent and failed spans. Trust boundary: the rule sees only what the host collector scraped while the host was awake and on the mesh.
- `world-assumptions` (stratum: world): A209–A212 (launchd's absent ceiling, stibnite's concurrency and volume, omp's oneshot spans, the per-host rates behind the ingress budget); the designation `agent-telemetry host` gains stibnite.

## Impact

- Code: `modules/lib/agent-session-collector.nix` (new), `modules/clan/services/otel-collector/{flake-module.nix,schema.nix,README.md}`, `modules/lib/{observability-hosts.nix,otel-collector-darwin.nix}`, `modules/darwin/otel-collector-agent.nix`, `modules/home/ai/{agent-telemetry.nix,omnigent/worker.nix}`, `modules/darwin/omnigent-host.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/checks/{otel-collector-config,otel-collector-darwin,otel-envelope,agent-telemetry-emitters,fleet-alert}.nix`, `modules/vm-tests/fleet-ingress*`.
- Secrets: `vars/shared/langfuse/*/machines/stibnite` (recipient added, value unchanged).
- Hosts: magnetite and pyrite (stage 1, then magnetite again for the stage 2 rule union), stibnite (stage 2).
- ADRs: ADR-003, ADR-004 and ADR-008 lines listed in design D11, applied after ratification.
- Store: one new `agent_span` column; no table, database or retention change.
