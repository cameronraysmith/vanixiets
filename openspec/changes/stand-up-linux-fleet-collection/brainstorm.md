# Brainstorm: extend collection to the Linux fleet over mTLS (S4, CAM-71)

## Background

Slice S4 of the fleet observability implementation (`docs/notes/development/observability/architecture/reference-architecture.md:262-264`): `otel-ca`, the mTLS ingress on ZeroTier, the agent role on the other in-scope NixOS hosts, the SMART exporter on pyrite and `otel-envelope`.
It realizes the rest of ADR-003 for NixOS and its metrics in ADR-004, and its components are `otel-collector` and `host-probes` (`components/otel-collector.md`, `components/host-probes.md`).
S4 depends only on S1, and S5 follows S4 because S4 provides the ingress S5's darwin agents report to (RA:278).
Classification under `skill://brainstorming`: architectural, because S4 opens the first non-loopback listener of the observability stack, adds a certificate authority, and adds hosts to collection and alerting whose interfaces S5 to S8 depend on (`openspec/specs/telemetry-store-interface/spec.md:10`; `openspec/specs/fleet-alerting-interface/spec.md:126`).

Abbreviations used below: `OBS` is `docs/notes/development/observability/`, `RA` is `OBS/architecture/reference-architecture.md`, `CH` is `OBS/charter.md`, `ADR-003`, `ADR-004` and `ADR-009` are the records under `OBS/decisions/`, `S1` and `S3` are the archived changes `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/` and `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/`, `S2` is `openspec/changes/stand-up-devloop-collection/`, and `prep` is `logs/s4/brainstorm-prep.md`.
CAM-71's four acceptance criteria are AC1 to AC4, to keep them apart from the world assumptions A1 to A13.

Inputs gathered for this brainstorm:

- `prep`: the design corpus and the hosts read against S4 on 2026-10-27, with contradictions C1 to C6, open decisions D1 to D10, the assets S4 reuses, carried items K1 to K21, mechanical questions M1 to M21 and operator questions O1 to O10.
- Host observations over `ssh <host>.zt` on magnetite, cinnabar and pyrite on 2026-10-27, recorded in `prep` §2.
- The S1 and S3 retrospectives' §6 rules and S2's later-slices rules (`S1/retrospective.md:130-181`; `S3/retrospective.md:140-188`; `S2/design.md:402-403`).

## Status of the decisions

The orchestrator decided M1 to M21 on 2026-10-27 from the specs and the evidence, each as the prep recommends.
The operator decided O1 to O10 on 2026-10-27, each as the prep recommends; each is recorded once below under its decision, in a line beginning `Decision (O<n>, decided by the operator, 2026-10-27)`, and the proposal bullet tagged with the same `O<n>` carries it.

## Sequencing

S4's design and spec deltas start only after S2 is archived, because S2's deltas to `host-metrics-collection`, `telemetry-store-interface`, `fleet-alerting`, `fleet-alerting-interface` and `world-assumptions` are not yet in `openspec/specs/` (`S2/tasks.md:82-99`; prep K19).
S2's task 7.7 is due 2026-10-29, so S4's design starts no earlier than that date (M17).
Only this brainstorm and the proposal are written now.

## Grounding evidence

### What CAM-71 and the decision records ask for

- Deliverables: the `otel-ca` and `otel-cert` generators and the ingress receiver bound to `flake.lib.hosts.magnetite.zt` with the existing nonlocal bind; the agent role on cinnabar, pyrite and the other in-scope NixOS hosts, with host, process, paging and systemd metrics, a loopback node_exporter and `smartctl_exporter` on pyrite; the notifier template on every agent host and the `otel-envelope` regulator (`linear issue view CAM-71`).
- AC1: every in-scope NixOS host reports series distinct by `host.name`.
- AC2: a client without an `otel-ca` certificate is refused by the ingress.
- AC3: pyrite's NVMe SMART data is readable, or ADR-003 is amended.
- AC4: host absence alerts for cinnabar but not for pyrite while it sleeps.
- ADR-003 places the six NixOS machines cinnabar, electrum, galena, scheelite, magnetite and pyrite in scope (ADR-003:80).
- S3 left the filesystem and NVMe rules to S4, because the launchd and `HostProbeStale` rules read darwin series only (CH:331; ADR-009:103, ADR-009:106).

### Contradictions found

- C1, deploy records: CH:360 and RA:249 keep S1 and S3 to S5 metrics-only, while S2's design has S4 ship deploy records from every agent host (`S2/design.md:402`), ADR-003 item 4 has every agent tail `/var/log/deploy-record.jsonl` (ADR-003:82), and CAM-71 does not mention deploy records.
- C2, CAM-76 ordering: CH:354 and RA:280 make CAM-76 block S5 because S5 adds laptops, while pyrite is a laptop (`modules/clan/inventory/machines.nix:77-86`) that joins alerting in S4, and no source makes CAM-76 block S4.
- C3, in-scope versus provisioned hosts: electrum, galena and scheelite are `enabled = false` in the terranix tables (`modules/terranix/hetzner.nix:18`; `modules/terranix/gcp.nix:32`, `:40`), so AC1 cannot be observed for them.
- C4, pyrite asleep: pyrite's logind locks on lid close, its last `systemd-suspend` entry across 75 journal boots is 2026-09-09, and world assumption A13 records suspend as unreliable and recoverable only at the machine (`openspec/specs/world-assumptions/spec.md:252-257`), so pyrite goes silent by power-off, reboot or leaving the network.
- C5, filesystem metrics: CAM-71 names no filesystem series, while ADR-009's S4 rules `FilesystemFillingWarn` and `FilesystemFull` read `system_filesystem_usage_bytes` (ADR-009:113-114), which no NixOS agent collects (`modules/clan/services/otel-collector/flake-module.nix:196-207`).
- C6, "service metrics as magnetite": ADR-003 item 6 scopes the gitea, niks3, nixbot and nginx scrapes to magnetite (ADR-003:84), and no record names a service scrape on another NixOS host beyond zerotierone (ADR-003:83).

### What S1 to S3 provide

- The agent fragment `flake.modules.nixos.otel-collector-agent`, with memory, paging, per-process memory without identity attributes above a 64 MiB floor, the systemd allow-list, loopback node_exporter with `zfs` and `vmstat`, and zerotierone metrics (`flake-module.nix:85-338`); both roles run on magnetite only (`modules/clan/inventory/services/otel-collector.nix:11-12`).
- The agent's pipelines export only to `forward`, valid only beside the ingress (`flake-module.nix:269`, `:280`); it scrapes gitea, niks3, nixbot and greptimedb unconditionally (`flake-module.nix:248-251`); its `memory_limiter` is 384 MiB for both roles (`flake-module.nix:67-70`), against ADR-003's 150 MiB and `MemoryMax = 256M` for a non-ingress agent (ADR-003:218); and `file_storage` exists only in the ingress fragment (`flake-module.nix:383-386`).
- The ingress fragment has no network receiver and no TLS, and magnetite listens on loopback only (`flake-module.nix:340-525`; `ss -tlnp` on magnetite).
- S2's `file_log/deploy-record` receiver on magnetite and the ingress's `routing/logs` to the `devloop` tables (`modules/nixos/devloop-collection.nix:978-1027`; `flake-module.nix:466-506`), and the deploy-record snippet on every NixOS machine.
- `observability-notify`, keyed so cinnabar's direct import and the agent role's import merge once (`modules/nixos/observability-notify.nix:124`).
- The evaluator's freeze of a silent host, its `RuleSignalMissing` for an `alwaysOn` host silent for 600 s, and its laptop noise budget `{ stibnite: 3, pyrite: 3 }` (`modules/nixos/fleet-alert/transition.jq:15-20`, `:35`, `:38`, `:96-110`); `alwaysOn = [ "magnetite" ]` and presence selectors expecting magnetite alone (`modules/nixos/fleet-alert/rules.nix:42-45`, `:175`).
- `nix-grpc-ca` and `nix-grpc-cert`, the pattern ADR-003 names for `otel-ca` and `otel-cert` (`modules/clan/services/nix-builders/flake-module.nix:106-146`; ADR-003:287-288).
- `net.ipv6.ip_nonlocal_bind = 1` on magnetite and `flake.lib.hosts.magnetite.zt` (`modules/machines/nixos/magnetite/default.nix:838`; `modules/lib/hosts.nix:7-9`).
- The 0.5 GiB evaluation budget per check, with `checks.otel-collector-config` at 0.450 GiB evaluating magnetite alone (`S2/plan/task-3.md:2066-2068`; `modules/checks/otel-collector-config.nix:22`) and `checks.fleet-alert` at 0.310 GiB.

### Found while preparing

- pyrite's NVMe health log is readable: `smartctl -j -H -A /dev/nvme0` exits 0 as root on its `APPLE SSD AP0512J`, which answers ADR-003 Q15 at the device; the exporter's own read under its module's capabilities is still an acceptance observation (prep §2).
- magnetite stores 44 distinct `systemd_unit_name` values against ADR-004's per-host bound of 40, because 16 `observability-notify@` instances pass the allow-list entry added by S3's review F2 (`modules/clan/services/otel-collector/schema.nix:38-40`; ADR-004:130; prep K8).
- R3.1's `isLoopback` admits only loopback endpoints, so an ingress receiver on magnetite's ZeroTier address fails it as written (`modules/checks/otel-collector-config.nix:49-52`).
- cinnabar's and pyrite's zerotierone `local.conf` lack `enableMetrics`, so the agent role changes both hosts' zerotierone configuration (`flake-module.nix:313-316`).
- The collector's own telemetry on `127.0.0.1:8888` is not scraped, so R3.2's queue and refusal clauses have no input yet (prep §2, store query `count by (job) (up)`).

## Decision chain

### D1. Trust root, issuance and rotation (O10)

Options: ADR-003's shared `otel-ca` and per-machine `otel-cert` copied from `nix-grpc-ca` and `nix-grpc-cert`, with 3650-day validity; the same with a one-year validity, forcing a yearly fleet-wide redeploy that a silent or unprovisioned host misses; an online step-ca, which adds a long-running service that intermittent hosts cannot renew against and which ADR-003 Q2 already rejected (ADR-003:295-296).

Decision (O10, decided by the operator, 2026-10-27): 3650-day certificates, rotated on compromise only, matching `nix-grpc-ca`.

- `otel-ca` and `otel-cert` are copied from `nix-grpc-ca` and `nix-grpc-cert`, including `validation.subjectAltNames`, with P-256 keys and CN the machine name (M4).
- Agent certificates carry `extendedKeyUsage=clientAuth`; magnetite's carries `serverAuth,clientAuth` with `IP:<flake.lib.hosts.magnetite.zt>` and `DNS:magnetite.zt` SANs.
- The CN is not bound to the stamped `host.name`, an accepted ADR-003 consequence (ADR-003:192).
- After every vars step, `ca.crt`'s hash and the `ntfy-alerter` token's hash are checked unchanged, because S3 once regenerated a shared token with `clan vars generate` (M5; `S3/retrospective.md:146-148`).
- The runbook gains CA rotation on compromise.

### D2. The agent collector's shape per host

Decision (orchestrator, from charter v15 and ADR-003): one agent fragment whose exporter is chosen by role, `forward` beside the ingress and `otlp_http/ingress` with TLS, a `file_storage` queue and unbounded retries elsewhere (M1; CH:310; `S1/design.md:248`).

- Non-ingress agents run the 150 MiB limiter, `MemoryMax = 256M` and their own `file_storage` queue under 512 MiB (M3; ADR-003:218, ADR-003:222).
- The gitea, niks3, nixbot and greptimedb scrapes are gated on those services being enabled, and CAM-71's "service metrics as magnetite" reads as zerotierone plus magnetite's existing scrapes (M2).
- NixOS agents gain a `filesystem` scraper bounded by a strict include list of the host's evaluated ZFS dataset mountpoints, which the S4 filesystem rules need (M11; C5).
- The collector's own `127.0.0.1:8888` telemetry is scraped with a keep-list of queue, send-failure and refusal counters, as input to R3.2 (M12; ADR-003:237).
- Rejected: magnetite's own agent exporting over mTLS to its own receiver, which adds a TLS hop, a second queue and a client key on the memory-constrained store host; and a separate `agent-remote` fragment, which duplicates pipelines `schema.nix` keeps single-sourced.

### D3. Hosts in scope now (O1)

Options: cinnabar and pyrite only; all six NixOS hosts in the role, with runtime acceptance on the provisioned three; all six plus provisioning electrum for the acceptance window.

Decision (O1, decided by the operator, 2026-10-27): all six NixOS hosts join the agent role, and AC1 is observed on the provisioned three, magnetite, cinnabar and pyrite.

- electrum, galena and scheelite carry the agent, its certificate and its notifier in their configurations and report on first provisioning.
- scheelite has no machine check (`modules/README.md:60`), so its agent is not evaluated by CI.

### D4. What the agents ship (O2)

Options: host metrics only, as CH:360 reads; host metrics plus deploy records over S2's logs path; that plus extending `devloop-reconcile` to other hosts, which needs a remote read no design provides.

Decision (O2, decided by the operator, 2026-10-27): agent hosts ship deploy records in S4 over S2's logs path, which clarifies CH:360's "metrics-only", and `devloop-reconcile` stays on magnetite.

- `file_log/deploy-record` moves from `devloop-collection.nix` into the agent role with S2's keep-list, ending in the agent's exporter, and the ingress gains a logs pipeline from the mTLS receiver into the unchanged `routing/logs` (`S2/design.md:193`, `:402`).
- Agents stamp `vanixiets.database = devloop` and `vanixiets.table = deploy_record` (prep K7).
- The local OTLP receiver still feeds no logs pipeline (ADR-003:81), and `start_at: beginning` ships each host's history once (`S2/design.md:282`).
- The one-host sampling of `devloop-reconcile` stays the accepted trade-off (`S2/design.md:423`).

### D5. Host absence and the sleeping laptop (O3, O4, O5)

Options: both paths as ADR-009 item 16 is written, R3.2's per-host last-seen clause and `RuleSignalMissing` with `alwaysOn = [ magnetite cinnabar ]`, posting twice per silence; one path through the evaluator, with `alwaysOn` gaining cinnabar and R3.2 dropping its last-seen clause; one path through R3.2, leaving magnetite's own silence to `otel-envelope` on magnetite.

Decision (O3, decided by the operator, 2026-10-27): the evaluator's `alwaysOn` is the single host-absence path, and R3.2 drops its per-host last-seen clause while keeping its `up`, queue, send-failure and limiter clauses; ADR-003 R3.2 and ADR-009 item 16 are amended.

- S3's review proposed this (`S3/review.md:69`, F1), and S3's retrospective requires that it be decided with R3.2 (`S3/retrospective.md:166-168`; prep K14).
- `alwaysOn` is magnetite and cinnabar; pyrite stays out of it in every option.
- Expected hosts per rule are the NixOS agent hosts for the ZFS, OOM, memory, unit and `LocalExporterDown` rules, pyrite for the NVMe rules, and every agent host for the filesystem rules (M8; ADR-009:103).
- A pyrite that reports memory but no SMART raises `RuleSignalMissing` within 30 min (ADR-009:134).
- The `SystemdUnitFailed` exclusion becomes the union of every host's notified units, sourced from one `flake.lib` list that the hosts and `rules.nix` both read, rather than from other hosts' evaluation (M9; `rules.nix:14-17`).

Decision (O4, decided by the operator, 2026-10-27): AC4's pyrite half is demonstrated by taking pyrite offline, wifi off or powered off with the operator present, rather than by suspending it, because pyrite no longer suspends and A13 makes suspend risky (C4).

Decision (O5, decided by the operator, 2026-10-27): AC4's cinnabar half is demonstrated by stopping cinnabar's collector while ntfy runs, and detection of a full cinnabar outage, which also stops ntfy, stays with CAM-76 (RA:182-183).

### D6. Ingress exposure over ZeroTier

Decision (orchestrator, from ADR-003 item 9): the receiver binds `[${flake.lib.hosts.magnetite.zt}]:4318` with the existing nonlocal bind, `tls.client_ca_file` from `otel-ca` and `min_version: "1.3"`, and TCP 4318 opens on `zt+` only (ADR-003:87).

- The two Android members and stibnite reach the handshake and are refused for lacking a certificate (ADR-003:194).
- The agents' endpoint is built from `flake.lib.hosts.magnetite.zt`, not `magnetite.zt`, which removes the dependency on cinnabar's dnsmasq and matches the certificate's IP SAN; ADR-003 item 7 is amended in place (M20; ADR-003:85, ADR-003:195).
- R3.1 admits exactly one non-loopback endpoint, the ingress receiver, equal to the registry address and the certificate's IP SAN, with a `0.0.0.0:4318` mutant (M6; ADR-003:230, ADR-003:234).
- Rejected: an nftables source list of fleet members, a second address list guarding against nothing mTLS does not; and `[::]:4318`, outside ADR-003's exposure envelope (ADR-003:224).

### D7. Evaluation cost under the 0.5 GiB budget

Decision (orchestrator, from charter v16 and v19): relations within one host become assertions in the agent and ingress fragments, paid for by each host's toplevel evaluation, and `checks.otel-collector-config` keeps magnetite's clauses plus relations whose two values come from `flake.lib` (M7; CH:319, CH:348).

- Extending the check to every agent host would exceed 0.5 GiB from its 0.05 GiB margin `[INFERENCE]`.
- Every changed check is measured before and after with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` (prep K13).
- An `otel-envelope` fixture check, if any, renders its script from `flake.lib` without evaluating a `nixosConfiguration`.
- Whether `otelcol-contrib validate` opens the TLS files is tested first; if it does, `validateConfigOverrides` and R3.1's override clause widen in one edit (M16; `modules/clan/services/otel-collector/README.md:178-179`).

### D8. Deploy order (O7)

Options: vars, then cinnabar, then magnetite, then pyrite; magnetite first, which shows cinnabar silent until its deploy; magnetite twice around the agents.

Decision (O7, decided by the operator, 2026-10-27): vars first, then cinnabar via `root@49.13.68.78`, then magnetite, then pyrite from the machine or its LAN address with the operator present; rollback runs in reverse order.

- cinnabar's agent queues to disk until magnetite's deploy brings the receiver, rules and `otel-envelope`, so neither `RuleSignalMissing` nor R3.2 sees a gap.
- The vars step adds pyrite and every other new agent host as `ntfy-alerter` readers with `CLAN_NO_COMMIT=1 clan vars fix <host> --generator ntfy-alerter` (prep K11).
- The agent role's zerotierone change restarts zerotierone on cinnabar and pyrite `[INFERENCE]`, so cinnabar is deployed over its public address and may miss one evaluator heartbeat inside the dead-man's 10 min window (ADR-009:78).
- pyrite's deploy and the O4 offline test run only with the operator physically present at pyrite, because its deploy likely restarts zerotierone and a failed boot or network on pyrite cannot be recovered remotely.

### D9. The ingress queue when the fleet reports

Decision (orchestrator, from ADR-003:222): the ingress keeps its 400 MiB `fleet` queue, agent queues are the second tier, R3.1's 24 h clause applies per agent host, and the ingress's full-queue rejection is observed in the pipeline container test (M21).

- At six hosts of magnetite's rate the ingress queue holds about 13 h `[INFERENCE: 400 MiB / (6 x 76,538 B/min)]`.
- That a full ingress queue returns a retryable error to agents is unverified `[INFERENCE]`.

### D10. The unit cap and the notifier instances (O6)

Options: count the cap over units other than `observability-notify@*` and bound the instances by the host's notified units; raise the cap, which grows with every notified unit; drop the instances from the allow-list, reverting S3's F2.

Decision (O6, decided by the operator, 2026-10-27): `observability-notify@*` instances are excluded from the 40-unit cap and bounded by the host's notified units, amending ADR-004.

### D11. CAM-76 ordering (O8)

Decision (O8, decided by the operator, 2026-10-27): S4 proceeds before CAM-76, because adding pyrite does not change the ntfy-outage exposure CAM-76 addresses; the reasoning is recorded against C2 in the charter entry.

### D12. CAM-71's deliverables (O9)

Decision (O9, decided by the operator, 2026-10-27): CAM-71's deliverables gain the filesystem scraper and drop "the same host and service metrics as magnetite" (C5, C6).

### Mechanical decisions not placed above

Each was decided by the orchestrator on 2026-10-27 as the prep recommends.

- M10: pyrite's `smartctl_exporter` reads `/dev/nvme0` and ADR-003 is not amended for SMART; the exporter's own read is confirmed at acceptance.
- M13: `otel-envelope` ships R3.2 and R4.2, and R8.3 is left to S7 (RA:271-272).
- M14: the filesystem and NVMe rule expressions are measured against live series on each new host before merge (CH:337).
- M15: long evidence captures run on cinnabar or magnetite, not pyrite (`S3/retrospective.md:180`).
- M17: S2 is archived before S4's specs are written.
- M18: S4's delta removes "slice S4" from `telemetry-store-interface` (`openspec/specs/telemetry-store-interface/spec.md:284`).
- M19: `otel-envelope`'s plan includes a crash-loop case and a long-running case (`S1/retrospective.md:172-174`).

## Rules adopted from the S1 to S3 retrospectives

- Every runtime envelope clause of `otel-envelope` gets a negative control on a real store (`S1/retrospective.md:152-154`).
- Each new check or assertion clause names its two independently defined value sources before its mutant is written (`S3/retrospective.md:158-160`).
- A new state rule in `transition.jq` lands with a fixture timeline from a spec scenario before the reference model changes (`S3/retrospective.md:142-144`).
- A human step that a later observation depends on is a gated task, which covers the operator's presence at pyrite's deploy and its silence test (`S3/retrospective.md:150-152`).
- Format and lint run before every commit step (`S1/retrospective.md:156-158`).
- The collector README and the runbook gain the agent hosts, certificate generation and rotation, and the ingress (`S1/retrospective.md:160-162`).
- R3.1's mutant set and R3.2's acceptance (a stopped agent, a stopped node_exporter, and an ntfy message naming `otel-envelope.service`) are deployment acceptance items (`components/otel-collector.md:155-165`; `components/host-probes.md:104-112`).
- The design lists the later slices touching S4's objects and the rule each keeps: S5's darwin agents on the same ingress, S6's dashboards over the new hosts, S7's journald on the agents' logs path, and S8's export of deploy-record rows (`S1/retrospective.md:168-170`).

## Left for design

- The `otel-envelope` script's clauses, thresholds, timer and the fixtures of its crash-loop and long-running cases.
- The shape of the `flake.lib` notified-units list and of the per-host filesystem include list.
- The agent's role switch and how its envelope and scrapes are made conditional.
- The R3.1 clauses for the non-loopback endpoint and the per-agent 24 h queue, with their value sources and mutants.
- The cost figures of every changed check, before and after.
