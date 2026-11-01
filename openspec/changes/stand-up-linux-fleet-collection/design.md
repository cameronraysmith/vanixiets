## Context

This change is slice S4 of the fleet observability implementation (RA:262-264; Linear CAM-71).
It realizes the rest of ADR-003 for NixOS and its metrics in ADR-004, through the components `otel-collector` and `host-probes`, and it lands the filesystem and NVMe rules that S3 left to S4 (A9 item 16; CH:331).
`brainstorm.md` records the grounding, the contradictions C1 to C6 and the decision chain D1 to D12, with the operator's O1 to O10 and the orchestrator's M1 to M21 of 2026-10-27; this document develops that direction and settles the eleven open points of DI, each named where it is settled and collected in "Design inputs settled" below.
The decision records were amended in place under charter v23 (CH:375-387); the amendments this design adds are listed in "Decision records amended under charter v23".

Citation keys:
A3, A4, A8 and A9 are ADR-003, ADR-004, ADR-008 and ADR-009 under `docs/notes/development/observability/decisions/`, CH is `docs/notes/development/observability/charter.md`, RA is `architecture/reference-architecture.md`, OC is `components/otel-collector.md` and HP is `components/host-probes.md` under the same directory.
GR is `logs/s4/grounding.md`, DI is `logs/s4/design-inputs.md`, BP is `logs/s4/brainstorm-prep.md` and BS is this change's `brainstorm.md`.
S1, S2 and S3 are the archived changes `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/`, `openspec/changes/archive/2026-10-28-stand-up-devloop-collection/` and `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/`; S1-R6, S2-R6 and S3-R6 are their `retrospective.md` §6.
FM is `modules/clan/services/otel-collector/flake-module.nix`, SC is `modules/clan/services/otel-collector/schema.nix`, CC is `modules/checks/otel-collector-config.nix`, RN is `modules/nixos/fleet-alert/rules.nix`, DC is `modules/nixos/devloop-collection.nix` and ON is `modules/nixos/observability-notify.nix`.

The current state:

- Both collector roles run on magnetite only, joined by an in-process `forward` connector; the agent's pipelines export only to `forward`, and the ingress has no network receiver, so magnetite listens on loopback only (FM:262-287, :340-525; BP §2).
- The agent scrapes gitea, niks3, nixbot and greptimedb unconditionally, its `memory_limiter` is 384 MiB for both roles, and `file_storage` exists only in the ingress fragment (FM:67-70, :248-251, :383-386).
- S2's `file_log/deploy-record` receiver runs on magnetite from DC, and every NixOS machine writes `/var/log/deploy-record.jsonl` (DC:978-990; S2 design D9).
- The evaluator's `alwaysOn` is `[ "magnetite" ]`, every presence selector expects magnetite alone, and `SystemdUnitFailed` excludes the evaluating host's notified units only (RN:42-45, :160-162, :175).
- magnetite stores 44 `systemd_unit_name` values, 28 ordinary units and 16 `observability-notify@` instances, against ADR-004's cap of 40, and the configured notified units are 16 on magnetite, 1 on cinnabar and none on pyrite (GR §4).
- Every NixOS host has `services.zerotierone.enable`, and cinnabar's and pyrite's `local.conf` lack `enableMetrics` (`nix eval` of each host's `services.zerotierone.enable`, 2026-10-28; GR §3).
- Every NixOS host's ZFS mountpoints are `/`, `/home` and `/nix`, and magnetite adds `/var/lib/cognee`, `/var/lib/containers`, `/var/lib/docker` and `/var/lib/greptimedb` (`nix eval` of each host's `fileSystems` filtered on `fsType = "zfs"`, 2026-10-28).
- `vars/shared/zerotier-ip-magnetite-zerotier/ip/value` holds `fddb:4344:343b:14b9:399:930f:39db:40d2`, the address clan's ZeroTier service assigned to magnetite, equal today to `flake.lib.hosts.magnetite.zt` (`modules/lib/hosts.nix:7-9`).

Facts the grounding established that shape the decisions (GR §1 to §6):

- `otelcol-contrib validate` 0.155.0 opens no TLS file, so a missing or garbage certificate, key or CA passes validation, and a missing client CA first fails the collector at start (GR §1).
- A full ingress queue and a refusing `memory_limiter` both answer HTTP 503, which the agent retries from its persistent queue across an outage and its own restart; 783 of 783 points arrived, while the ingress counted the same points as refused and enqueue-failed (GR §2).
- The agent's `send_failed` and `enqueue_failed` series appear only after their first increment (GR §2).
- A client without a certificate, with a certificate from another CA, or offering only TLS 1.2 is refused during the handshake (GR §2).
- Adding `enableMetrics` changes `zerotierone.service`'s `ExecStartPre=`, so a switch stops and starts zerotierone on cinnabar and pyrite, and on cinnabar that reruns the controller's `init-zerotier-controller`, `whitelist-controller`, `push-controller-network-config` and `pin-controller-ipv4` hooks (GR §3).
- pyrite's `/dev/nvme0` is `root:root 0600` with no ACL, and the exporter module's udev rule grants `smartctl-exporter-access` only on an `add` event, which a switch does not replay (GR §5).

Constraints that shape every decision below:

- Each check states a 0.5 GiB evaluation budget, measured with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath`; `otel-collector-config` has 0.045 GiB left; attribute names come from static data only; relations within one host are module assertions, paid for by the host's toplevel evaluation (S2-R6; CH:319, CH:348).
- Each new clause names its two independently defined value sources before its mutant is written, and a clause whose two values are rendered from one Nix attribute is a restatement and is not written (S2-R6; S3-R6).
- Every runtime regulator clause gets a negative control on a real store, and `otel-envelope` gets a crash-loop case and a long-running case (S1-R6).
- The `sqlquery` cursor's storage key embeds the query text, so this change leaves the two nixbot queries' text unchanged (S2-R6; S2 design Risks).
- A human step that a later observation depends on is a gated task, which covers the operator's presence at pyrite (S3-R6; O4, O7).

Stakeholders are the operator, who receives the alerts and failure notices and reads the new hosts' series, and slices S5 to S8, which add darwin agents to the same ingress, dashboards, journald logs and the export of `devloop` (Later slices).

## Goals / Non-Goals

**Goals:**

- Every provisioned NixOS host, magnetite, cinnabar and pyrite, stores its host, process, paging, unit, ZFS, OOM, zerotierone and filesystem series in `fleet`, each distinct by `host_name`, and pyrite stores its NVMe health series (AC1, AC3; O1, O9).
- A client without an `otel-ca` certificate is refused by the ingress (AC2).
- cinnabar's silence raises one `RuleSignalMissing`, and pyrite's raises nothing (AC4; O3, O4, O5).
- Every agent host ships its deploy records into `devloop` over S2's logs path (O2).
- `otel-envelope` regulates each agent's delivery (R3.2) and the `fleet` budget (R4.2), with a negative control per clause (M13).
- electrum, galena and scheelite carry the agent role, its certificate and its notifier, and report on first provisioning (O1).

**Non-Goals:**

- darwin agents (S5), dashboards over the new hosts (S6), journald logs on the agents' logs path and R8.3 (S7), and the export of `devloop` rows (S8).
- Detecting a full cinnabar outage, which also stops ntfy (CAM-76; O5).
- Extending `devloop-reconcile` to hosts other than magnetite (O2; S2 design Trade-offs).
- Revocation of a single certificate, which no clan vars generator offers; a compromised key is answered by rotating `otel-ca` (O10).
- Provisioning any cloud host for acceptance (O1).

## Decisions

### Layout

New files:

| Path | Content |
|---|---|
| `modules/lib/observability-hosts.nix` | `flake.lib.observabilityHosts`, one entry per agent host with `collect`, `alwaysOn`, `notifiedUnits` and `smartDevices` (D6) |
| `modules/lib/otel-envelope.nix` | `flake.lib.otelEnvelope pkgs { … }`, the regulator script as a `writeShellApplication` (D7, D8) |
| `modules/checks/otel-envelope.nix` | `checks.x86_64-linux.otel-envelope`, the script's clauses over recorded collector telemetry (D7) |
| `modules/vm-tests/fleet-ingress.nix` | `perSystem.vmTests.fleet-ingress`, an nspawn container test on magnetite (D12) |

Changed files:

| Path | Change |
|---|---|
| FM | the role switch, `file_storage` in the shared core, the agent's mTLS exporters, the ingress receiver `otlp/mesh` and its firewall opening, conditional service scrapes, the filesystem scraper, the self-telemetry scrape, the deploy-record receiver moved from DC, the SMART exporter, the `otel-ca` and `otel-cert` generators, `otel-envelope` and its timer, and the per-host assertions (D1 to D8) |
| SC | `fleetBytesPerMinute`, moved from CC; the self-telemetry keep-list; the filesystem metric; the unit-cap rule excluding `observability-notify@*` (D4, D6, D8) |
| `modules/clan/inventory/services/otel-collector.nix` | `roles.agent.machines` from every host of `flake.lib.observabilityHosts`; the role applies its collection only where `collect` is true (D6) |
| DC | `file_log/deploy-record` and its pipeline removed, the shared helpers exported through `flake.lib.devloopCollection` (D5) |
| RN, `modules/nixos/fleet-alert.nix` | the union exclusion, `alwaysOn` and expected hosts from `flake.lib.observabilityHosts`, and four new rules (D9) |
| CC | the one non-loopback endpoint, the logs-receiver clause, the failure-wiring policy gaining `otel-envelope`, the unit-cap clause moved out (D10) |
| `modules/checks/fleet-alert.nix` | notified units from `flake.lib`, the cinnabar absence leg, the pyrite silence leg, the new rules' legs (D9) |
| `modules/checks/greptimedb-envelope.nix` | R8.2's ownership clause gains `otel-cert`'s key on magnetite, and the credential-holder assertion gains `otel-envelope` (D8) |
| the machine files of magnetite and cinnabar | their notified-unit lists move to `flake.lib.observabilityHosts` (D6) |
| the collector README, the runbook, OC and HP | agent hosts, certificate generation and rotation, the ingress, `otel-envelope` (Migration Plan PR 4) |

Units added on every agent host:

| Unit | User | Role |
|---|---|---|
| `opentelemetry-collector.service` | `DynamicUser` | the agent role; on hosts other than magnetite, `MemoryMax = 256M` and the mTLS exporters |
| `prometheus-node-exporter.service` | nixpkgs' module | loopback node_exporter, as on magnetite |
| `prometheus-smartctl-exporter.service` | nixpkgs' module, `DynamicUser` | only where `smartDevices` is non-empty, pyrite today |
| `otel-envelope.timer`, `otel-envelope.service` | `DynamicUser` | R3.2 every 5 min; on the ingress host also R4.2 hourly, with `LoadCredential=regulator-password` (D7, D8) |
| `observability-notify@.service` | as in S3 | the failure notifier, with the `alerter` token |

### Data flow

```
every agent host                                 magnetite (agent + ingress)
host_metrics memory/paging/filesystem ─┐         otlp/mesh [zt]:4318, TLS 1.3, client CA otel-ca
host_metrics process (64 MiB floor) ───┤             │ (refusal at the handshake without a certificate)
systemd (allow-list) ──────────────────┤             ▼
prometheus: node, zerotierone,         │         metrics/ingress ◀── forward ◀── magnetite's own agent pipelines
  smartctl (pyrite), otelcol :8888,    │         logs/ingress    ◀── forward ◀── magnetite's deploy-record pipeline
  services where they run              │             │ memory_limiter
file_log deploy-record ────────────────┤             ▼
        │ memory_limiter, resource/agent           routing / routing/logs (unchanged)
        │ (host.name, vanixiets.database[, .table])     ▼
        ▼                                          otlp_http/<db>, otlp_http/devloop_<table> ─▶ 127.0.0.1:4000
otlp_http/ingress (metrics, 400 MiB)  ─┐
otlp_http/ingress-logs (logs, 16 MiB) ─┴─▶ https://[flake.lib.hosts.magnetite.zt]:4318
        file_storage queue, retry without limit, client cert otel-cert, ca_file otel-ca

otel-envelope.timer (every 5 min) ─▶ otel-envelope.service
   127.0.0.1:8888 collector telemetry · each declared loopback scrape target
   [ingress host, hourly] greptimedb /v1/sql as regulator (R4.2)
   ─▶ exit non-zero on a breach ─▶ OnFailure=observability-notify@%n.service
```

### Design inputs settled

| DI point | Settled by | Outcome |
|---|---|---|
| 1, ADR-004's arithmetic and notifier instances | D8 | 6,154 estimated series against 8,000; the budget holds |
| 2, where `otel-envelope` runs | D7, D8 | on every agent host for R3.2 from local inputs; R4.2 in the ingress host's instance; ADR-003 R3.2 and OC are amended |
| 3, cloud hosts and the always-on list | D9 | the list is magnetite and cinnabar; a cloud host provisioned on demand is not added |
| 4, R3.2's stopped-agent acceptance | D7 | kept: the host's own `otel-envelope` fails on its silent collector |
| 5, back-pressure is not loss | D7 | `otlp/mesh` refusals and the store exporters' enqueue failures are back-pressure; loss is counted elsewhere |
| 6, missing series as zero | D7 | a loss counter absent from the telemetry reads as zero; absent telemetry fails the run |
| 7, TLS file guard | D11 | no assertion; a missing file fails the collector at start, which the notifier and `otel-envelope` report, with a container-test control |
| 8, zerotierone restart and the controller rerun | D13 | expected on every host but magnetite; cinnabar deployed over its public address with a controller check |
| 9, pyrite NVMe through the udev `add` event | D4, D13 | the exporter grants its own ACL before start, so no reboot or re-trigger is needed |
| 10, evaluation-cost baselines | D10 | each changed check is estimated below and measured before and after |
| 11, unit budget counts | D6, D8 | 28 notified units fleet-wide after S4: magnetite 17, cinnabar 3, every other host 2 |

### D1: The collection CA and its certificates

- **Choice**: two clan vars generators in FM's agent role, copied from `nix-grpc-ca` and `nix-grpc-cert` (`modules/clan/services/nix-builders/flake-module.nix:106-146`).
  - `otel-ca`: `share = true`, `files."ca.key".deploy = false`, `files."ca.crt".secret = false`, a P-256 key and a self-signed certificate with `CN=otel-ca`, `basicConstraints=critical,CA:TRUE`, `keyUsage=critical,keyCertSign,cRLSign`, 3650 days.
  - `otel-cert`: per machine, `dependencies = [ "otel-ca" ]`, files `key.pem` (secret, deployed) and `cert.pem` (`secret = false`), a P-256 key, `CN=<machine>`, `keyUsage=critical,digitalSignature`, 3650 days, signed by `otel-ca`.
  - Agents carry `extendedKeyUsage=clientAuth` and no SAN; the ingress host carries `serverAuth,clientAuth` with `subjectAltName=IP:<flake.lib.hosts.magnetite.zt>,DNS:magnetite.zt`.
  - `validation.subjectAltNames` is the joined SAN string, and `validation.extendedKeyUsage` the usage string, so a change of either regenerates the certificate.
  - `otel-cert`'s two files carry `restartUnits = [ "opentelemetry-collector.service" ]` on a host whose `collect` is true, because `LoadCredential` snapshots at start (OC:69); `ca.crt` needs none, because it reaches the collector as a store path, whose change restarts it with the configuration.
- **Rationale**: ADR-003 Q2 settled a separate CA, and O10 settled 3650-day validity with rotation on compromise only, because a shorter validity forces a fleet-wide redeploy that a sleeping laptop or an unprovisioned host misses.
  The CN is not bound to the stamped `host.name`, an accepted ADR-003 consequence (A3 Consequences).
  The usage enters `validation` because the ingress host's certificate differs from the agents' only by role, and a host moved into the ingress role would otherwise keep a client-only certificate.
- **Boundary**: first-party generators over vendored openssl; the certificate as issued, not the script, is what R3.1 reads (D10).
- **Regulation**: after every vars step the plan records the sha256 of `vars/shared/otel-ca/ca.crt/value` and of the decrypted `ntfy-alerter` token value, never printed, before and after, and stops on a change (M5; S3-R6); the token is hashed by value because adding a reader re-encrypts its file, so the encrypted file's hash changes by design.
  Readers are added to a shared var only with `CLAN_NO_COMMIT=1 clan vars fix <host> --generator <name>`; `otel-ca` is created once, as the missing dependency of magnetite's `otel-cert`, when no `otel-ca` value exists to overwrite.
- **Alternatives considered**: one-year certificates and an online step-ca (BS D1); reusing `nix-grpc-ca`, rejected by ADR-003 Q2 because a dispatcher-CN certificate from it is a trusted build credential.

### D2: One agent fragment with a role switch

- **Choice**: `collectorCore` gains the option `vanixiets.otelCollector.ingress`, a boolean that the ingress fragment sets, and the `file_storage` extension at `/var/lib/opentelemetry-collector/queue`, moved from the ingress fragment so both roles share it.
  On a host where the switch is false, the agent fragment sets:
  - `memory_limiter` to `limit_mib = 150` and `spike_limit_mib = 30`, `MemoryMax = "256M"`, and no `OOMScoreAdjust`;
  - `otlp_http/ingress` for metrics and `otlp_http/ingress-logs` for logs, each with `endpoint = "https://[${flake.lib.hosts.magnetite.zt}]:4318"`, `tls` with `ca_file` the `otel-ca` certificate as a store path, `cert_file` and `key_file` under `/run/credentials/opentelemetry-collector.service/`, `min_version = "1.3"`, a `file_storage` queue with the `bytes` sizer of 400 MiB and 16 MiB, and `retry_on_failure` with `max_elapsed_time = "0s"`;
  - the agent's pipelines ending in those exporters instead of `forward`.
  On the ingress host the agent's pipelines keep ending in `forward`, and the limiter stays 384 MiB under `MemoryMax = 512M` with `OOMScoreAdjust = 300`.
- **Rationale**: one exporter carries one queue per signal, so two exporters keep the metrics queue at 24 h of collection while the two queues stay under 512 MiB together (A3 envelope, buffering).
  The 400 MiB queue holds 24 h at the 256,000 bytes a minute R3.1 assumes, and about 3.6 days at the 76,538 bytes a minute magnetite measured with its service endpoints (S1 `verify.md:453`); an agent without those endpoints is assumed to send less `[INFERENCE]`, which the first-deploy capture measures (Migration Plan step 2).
  Deploy records are under 1 KiB a line, so 16 MiB holds a host's whole history many times over.
  magnetite keeps `forward`, because its own agent exporting to its own receiver would add a TLS hop, a second queue and a client key on the memory-constrained store host (BS D2).
- **Regulation**: on a host where the switch is false, the agent fragment asserts that each of its two exporters' queues is in `file_storage` with the `bytes` sizer and unlimited retry, that the metrics queue is at least `24 * 60 * flake.lib.otelCollectorSchema.fleetBytesPerMinute`, that the queues sum to less than 512 MiB, and that the limiter is below `MemoryMax`; the queue literals and the rate assumption are defined independently, in FM and SC, and an `extendModules` override of cinnabar's configuration with a 64 MiB metrics queue shows the assertion failing (M21).
- **Boundary**: first-party configuration of the vendored collector.
- **Alternatives considered**: magnetite exporting over mTLS to itself, and a separate `agent-remote` fragment (BS D2); one exporter for both signals, rejected because its two queues would sum to 800 MiB at the metrics size.

### D3: The ingress receiver on ZeroTier

- **Choice**: the ingress fragment adds `receivers."otlp/mesh".protocols.http` with `endpoint = "[${flake.lib.hosts.magnetite.zt}]:4318"` and `tls` with `cert_file` and `key_file` from `otel-cert`, `client_ca_file` the `otel-ca` certificate as a store path, and `min_version = "1.3"`; no gRPC protocol.
  `otlp/mesh` is a receiver of `metrics/ingress` and, where the devloop routes exist, of `logs/ingress`, beside `forward`.
  The clan ingress role loads `otel-cert` and `otel-key` through `LoadCredential` and opens TCP 4318 on `networking.firewall.interfaces."zt+"` only; magnetite's existing `net.ipv6.ip_nonlocal_bind = 1` lets the bind succeed before zerotierone has the address (A3 item 9).
- **Rationale**: ADR-003 item 9 fixes the address, the client CA and the `zt+` opening; TLS 1.3 refuses TLS 1.2 clients at the handshake (GR §2).
  The agents' endpoint is the same IP literal, which matches the certificate's IP SAN and removes the dependency on cinnabar's dnsmasq (M20; CH:377).
  The ingress pipelines need no new route, because `routing` and `routing/logs` already route on the attributes every agent stamps (S2 design D4).
  The two Android members and stibnite reach the handshake and are refused (A3 Consequences).
- **Boundary**: vendored TLS in the collector's `configtls`; the refusal is observed in the container test and from stibnite at acceptance, not at evaluation.
- **Alternatives considered**: an nftables source list of fleet members and `[::]:4318` (BS D6).

### D4: What every agent gathers

- **Choice**: the agent fragment adds, on every agent host:
  - gitea, niks3, nixbot and greptimedb scrapes only under `lib.mkIf` of `services.gitea.enable`, `services.niks3.enable`, `services.nixbot.enable` and `services.greptimedb.enable`, so on magnetite the rendered targets are unchanged (M2);
  - `host_metrics/memory` gains the `filesystem` scraper with `include_mount_points = { match_type = "strict"; mount_points = <the host's ZFS mountpoints>; }`, the mountpoints read from the host's own `fileSystems` filtered on `fsType = "zfs"`, with only `system.filesystem.usage` enabled (M11);
  - a scrape job `otelcol` of `127.0.0.1:8888` whose `metric_relabel_configs` keep `otelcol_exporter_queue_size`, `otelcol_exporter_queue_capacity`, `otelcol_exporter_send_failed_metric_points`, `otelcol_exporter_send_failed_log_records`, `otelcol_exporter_enqueue_failed_metric_points`, `otelcol_exporter_enqueue_failed_log_records`, `otelcol_receiver_refused_metric_points` and `otelcol_receiver_refused_log_records`, from SC, and drop the label `service_instance_id` (M12);
  - where `flake.lib.observabilityHosts.<host>.smartDevices` is non-empty, `services.prometheus.exporters.smartctl` on `127.0.0.1:9633` with those devices, `openFirewall = false`, `MemoryMax = "64M"`, a scrape job `smartctl` with SC's smartctl keep-list, and `ExecStartPre = "+setfacl -m g:smartctl-exporter-access:rw <device>"` for each device (M10); the agent's existing assertion that node_exporter keeps its firewall closed covers this exporter too, because a host file can set `openFirewall`.
- **Rationale**: an unconditional service scrape on a host without the service is a permanently down target, which `LocalExporterDown` and `otel-envelope` would report (M2).
  The ZFS mountpoints are 3 on every host but magnetite and 7 on magnetite (Context), and a strict list keeps container runtime mounts under `/var/lib/docker` out, which a filesystem-type filter would admit `[INFERENCE]` (BP D2).
  `service_instance_id` changes at every collector start, so without the drop a crash-looping collector would mint series per start, the failure A4's process-identifier ban exists for.
  The stored self-telemetry is the after-the-fact record of each host's queue and refusals for the operator and S6, while `otel-envelope` reads the live endpoint, because a host's stored self-telemetry waits in the very queue it measures (D7).
  The ACL step makes the exporter's read independent of when udev last saw an `add` event for the device: the module's udev rule grants the same ACL only on `add`, and a switch replays none (DI 9; GR §5).
- **Boundary**: vendored versus first-party; the ACL step duplicates the nixpkgs module's udev action as a first-party unit setting, and a nixpkgs change to the group name breaks it at the exporter's start, which `LocalExporterDown` and `otel-envelope` report.
- **Regulation**: none at evaluation for the mountpoints: the list is read from the host's own `fileSystems` in one place, so an assertion comparing the scraper's list with `fileSystems` would restate the line that sets it (S2-R6); the strict match type is what keeps container mounts out, and each host's evaluated list is recorded at the plan's evaluation step.
  The SMART read is an acceptance observation on pyrite (M10).

### D5: Deploy records from every agent host

- **Choice**: `file_log/deploy-record`, its `logs/devloop-deploy_record` pipeline and its `resource/devloop-deploy_record` stamp move from DC into the agent fragment, with the receiver's id and settings unchanged, so magnetite's stored offset carries over; the shared `keepAttributes`, `dropBody` and file path are exported through `flake.lib.devloopCollection`, and the keep-list stays rendered from `devloop.tables.deploy_record`.
  The pipeline ends in `forward` on the ingress host and in `otlp_http/ingress-logs` elsewhere.
  The two `sqlquery` receivers and the `journald/gitea-mq` receiver stay in DC unchanged, query text included.
- **Rationale**: O2 ships deploy records over S2's path; `routing/logs` routes on `vanixiets.database = devloop` and `vanixiets.table = deploy_record`, which the stamp sets (S2 design Later slices).
  `start_at: beginning` ships each host's file once on its first start (S2 design D9).
  Leaving the query text untouched keeps the cursors' storage keys, so no re-backfill of about 200,000 rows occurs (S2-R6).
  `devloop-reconcile` keeps comparing magnetite alone (O2).
- **Regulation**: R3.1's logs clauses keep holding on magnetite (D10); at each agent host's first deploy the operator compares the line count of its `/var/log/deploy-record.jsonl` with its `deploy_record` rows (S2-R6), and a difference is a finding.
- **Later slices**: S5 adds the darwin agents' deploy records through the same pipeline.

### D6: One host table, and per-host relations as assertions

- **Choice**: `flake.lib.observabilityHosts`, in `modules/lib/observability-hosts.nix`, maps each agent host to `{ collect; alwaysOn; notifiedUnits; smartDevices; }`:

| Host | `collect` in pull request 1 | `alwaysOn` | `notifiedUnits` | `smartDevices` |
|---|---|---|---|---|
| magnetite | true | true | its 16 units of GR §4, `opentelemetry-collector` among them, and `otel-envelope` | none |
| cinnabar | false, true from its own pull request before its deploy | true | `fleet-deadman`, `opentelemetry-collector`, `otel-envelope` | none |
| pyrite | false, true from its own pull request before its deploy | false | `opentelemetry-collector`, `otel-envelope` | `/dev/nvme0` |
| electrum, galena, scheelite | true (unprovisioned, so nothing deploys them) | false | `opentelemetry-collector`, `otel-envelope` | none |

  The inventory's `roles.agent.machines` is generated from its names; on every one of them the clan agent role declares the `otel-ca`, `otel-cert` and `ntfy-alerter` generators, so the vars step covers all six hosts at once, and only where `collect` is true does it import the agent fragment and set `services.observability-notify.units` from `notifiedUnits` and `tokenFile` from the `ntfy-alerter` generator.
  `collect` is static data, so it selects the role's imports without evaluating the host; a host whose `collect` is false carries none of the agent's units, settings or `zerotierone` change, so a routine deploy of it from `main` changes nothing it runs, and its pull request setting `collect = true` lands immediately before its watched deploy (D13).
  magnetite's list in its machine file is removed; cinnabar's `fleet-alert.nix` kept its own `[ "fleet-deadman" ]` only while cinnabar's `collect` was false, a branch tasks.md 12.10 removes.
  Setting the flag changes two closures: the host's own, and magnetite's, because the evaluator takes its expected and always-on hosts from `flake.lib.observabilityHosts` in magnetite's configuration (`modules/nixos/fleet-alert/rules.nix:21-27`).
  The host's watched deploy is therefore followed by a deploy of magnetite, and until that deploy the evaluator neither expects the host's signals nor reports its silence; pyrite deployed at 05:59Z on 2026-11-01 and was expected only from magnetite's 06:28:35Z deploy (`review.md` F5).
  The plain fragments stay free of the table, so container tests import them without it.
- **Rationale**: the hosts and RN read one list, so the evaluator's exclusion is the fleet-wide union without evaluating any other host inside magnetite's toplevel (M9).
  The 28 notified units are the bound on stored notifier instances (DI 11; O6).
  `flake.lib` is `lazyAttrsOf raw`, so the table lives in one file (`modules/lib/hosts.nix:1-4`).
- **Regulation**, each an assertion in the agent fragment on every agent host that collects, shown failing once by an `extendModules` override of one host (cinnabar and pyrite evaluated in a scratch tree where their `collect` is true):
  - every notified unit is a service of the host with an `ExecStart`, and `opentelemetry-collector` and `otel-envelope` are notified; the two values are the table and the host's evaluated services (override: notify `zfs-set-root-typo-quota` on cinnabar);
  - at most 40 of the host's services, `observability-notify@` excluded, match SC's allow-list; the two values are the host's services and SC's patterns (override: 41 matching services on pyrite);
  - an `omnigent-host-<owner>` service has an alias in `ownerAliases`, the clause CC held for magnetite alone, now on every host; the two values are the host's services and SC's aliases (override: an `omnigent-host-nobody` service on cinnabar).
  R3.1's policy clause on magnetite keeps failing for an unlisted `greptimedb*`, `devloop-*`, `zfs-*` or collector unit, and gains `otel-envelope` (D10).
- **Alternatives considered**: keeping per-module additions to the option and asserting equality with the table, rejected as two hand-kept lists; evaluating other hosts' options in RN, rejected for adding each host's evaluation to magnetite's toplevel (BS D5).

### D7: `otel-envelope` on every agent host: R3.2 from local inputs

- **Choice**: every agent host runs `otel-envelope.service`, a oneshot from `flake.lib.otelEnvelope`, `DynamicUser`, `StateDirectory = "otel-envelope"`, `MemoryMax = "64M"`, `TimeoutStartSec = "4min"`, with `LoadCredential` of zerotierone's metrics token where zerotierone runs, started by `otel-envelope.timer` at `OnCalendar = "*:0/5 UTC"`, and notified through the table (D6).
  Each run reads `http://127.0.0.1:8888/metrics` and fails on:
  - C1, collector down: the endpoint did not answer within 10 s on this run and the previous one;
  - C2, target down: a declared scrape target, rendered from the collector's evaluated `prometheus*` scrape configurations, did not answer `GET` with 200 within 10 s on this run and the previous one;
  - C3, queue near full: any exporter's `otelcol_exporter_queue_size` reached 90% of its `otelcol_exporter_queue_capacity`;
  - C4, loss: since the previous run, `otelcol_exporter_send_failed_*` increased on any exporter, or `otelcol_receiver_refused_*` increased on any receiver other than `otlp/mesh`, or, on a host without the ingress role, `otelcol_exporter_enqueue_failed_*` increased.
  On the ingress host, `otelcol_receiver_refused_*{receiver="otlp/mesh"}` and the store exporters' `otelcol_exporter_enqueue_failed_*` are back-pressure, not loss: they fail nothing on their own, and a full store queue fails C3.
  A loss counter absent from the telemetry reads as 0, while a run that obtains no telemetry fails C1; a counter below its recorded value is a collector restart, and the run takes the current value as the increase.
  Each run records the counters and the down flags in `/var/lib/otel-envelope/state`, one line per series; a run that obtains no telemetry carries the previous counter lines forward, so one missed read does not turn the next run's cumulative counters into a false increase.
- **Rationale**: a host's stored self-telemetry is held in the queue it measures, so a regulator reading the store sees an agent's queue only after it drains and the ingress's queue only once the store is back; the local endpoint answers while the export path is down (DI 2).
  The proposal places the regulator on every agent host, while ADR-003 R3.2 and OC place it on magnetite querying the store; the local reading is why the proposal's side holds and ADR-003 R3.2, its implementation surface and OC are amended (charter v23).
  A full ingress queue and a refusing limiter answer 503 and the agent's queue keeps the points, so the ingress counts back-pressure as refusals and enqueue failures that lose nothing; points from magnetite's own scrapers have no retry, so their refusal is loss (DI 5; GR §2).
  An agent's `send_failed` and `enqueue_failed` series appear only after their first increment (DI 6; GR §2).
  Two consecutive runs absorb a deploy's restart of the collector or an exporter, about a minute, inside one 5-minute period.
  With the last-seen clause gone, the stopped-agent acceptance stays: the stopped host's own `otel-envelope` fails C1 within two runs, and an always-on host's silence also raises `RuleSignalMissing`, so a stopped collector on cinnabar posts the envelope's `FAILED` naming the cause and the evaluator's alert naming the silence, while a powered-off or disconnected host posts the evaluator's alert alone (DI 4; O3, O5).
  A laptop offline for less than about 21 h fails nothing, because its queue holds the interval, sleep stops the timer, and no clause reads freshness; freshness of an always-on host is the evaluator's `RuleSignalMissing` (A9 item 16).
- **Boundary**: vendored versus first-party; the metric names are the collector's at 0.155.0, read live on magnetite on 2026-10-29: `otelcol_exporter_queue_capacity` exists with a `data_type` label, and the counters carry no `_total` suffix.
- **Regulation**: `checks.x86_64-linux.otel-envelope` renders the script from `flake.lib.otelEnvelope` with the root pin's `pkgs` and runs it against a stub endpoint serving recorded telemetry: a healthy agent passes; a missing `send_failed` series passes; a full agent queue fails C3; an `enqueue_failed` increase fails C4 on an agent and passes on the ingress; an `otlp/mesh` refusal on the ingress passes; a `host_metrics/memory` refusal on the ingress fails C4; a counter reset after a recorded value passes, and a reset followed by a new failure fails (crash-loop case); a missed telemetry read between two identical readings passes; a target down on one run passes and on two fails C2; 3 consecutive runs with growing counters and a target that answers after 15 s end each within `TimeoutStartSec` and fail C2 from the second (long-running case).
  Mutants of the script, each of which must fail one of those cases: C4 counting `otlp/mesh` refusals as loss, a missing counter treated as failure, a reset treated as a negative increase, C2 without its two-run rule, and a missed read that does not carry the counters forward.
  On a real store, `vmTests.x86_64-linux.fleet-ingress` runs the unit itself, so every binary it calls is in its `runtimeInputs` (S2-R6), and gives each clause its negative control (D12).
  At acceptance, stopping cinnabar's collector, and later cinnabar's `prometheus-node-exporter`, each fail cinnabar's `otel-envelope` within 10 min and post a `FAILED` naming `otel-envelope.service` and cinnabar (A3 R3.2; OC:158-159).
- **Alternatives considered**: one regulator on magnetite querying stored self-telemetry, ADR-003's text, rejected for the queue blindness above; reading `up` from the store, rejected for the same reason and because an agent's `up` series travel through its own queue; a C5 on collector restarts, rejected because `opentelemetry-collector` is a notified unit and `SystemdUnitRestartLoop` reads restarts.

### D8: R4.2 on the ingress host, and ADR-004's arithmetic

- **Choice**: the ingress host's `otel-envelope` also holds `LoadCredential=regulator-password`, and its runs that start at minute 0 of each hour query the store as `regulator` through `/v1/sql`, a handful of queries in all: active series as one `count(DISTINCT __tsid)` over `greptime_physical_table`, label values as one query with a `count(DISTINCT <tag>)` per tag column of that table, broken down by metric only for a column above 200, and each other clause as one query, failing when:
  - `fleet` holds more than 8,000 active series in the last hour;
  - a label key of a metric carries more than 200 distinct values in the last hour, `process_executable_name`, `systemd_unit_name` and `launchd_label` excepted;
  - a host carries more than 30 `process_executable_name` values, more than 40 `systemd_unit_name` values not beginning `observability-notify@`, or more than 30 `launchd_label` values;
  - a host stores an `observability-notify@<unit>.service.service` instance whose `<unit>` is not in that host's `notifiedUnits`;
  - `devloop` holds more than 100,000 rows with a time index in the last 24 h;
  - a database's `ttl` differs from SC's `databases`.
  Each query treats an empty result or a missing table as a failure of its clause, as `greptimedb-envelope` does; the journald-bytes clause and the `fleet` logs table's `ttl` have no input until S7 creates that table, and land with it.
  R8.2's credential-holder assertion on magnetite admits `otel-envelope` as the fourth `regulator-password` holder.
- **Rationale**: R4.2 reads every host's stored series and needs the store credential, which only the ingress host holds (A3 Rationale), so R4.2 runs in one instance; the per-host process bound the proposal names is one of its clauses (M13).
  The cardinality queries scan an hour of `fleet`, so they run hourly rather than every 5 minutes; one physical-table count took 83 ms on 2026-10-29, and the plan times every budget query on magnetite, read-only, before the pull request that adds them.
- **ADR-004's arithmetic under O6** (DI 1, DI 11):
  - Per NixOS host ADR-004 counts 409 series, 360 of them for at most 40 units at 9 series each, and 419 on pyrite with SMART, 2,464 for six hosts (A4 Rationale).
  - Notifier instances add up to 9 series per notified unit: 28 units after S4 add at most 252.
  - The filesystem scraper adds 3 series per mountpoint, `used`, `free` and `reserved`: 7 on magnetite and 3 on each other host give 66.
  - The self-telemetry keep-list adds at most 50 series on magnetite, with seven store exporters and thirteen receivers, and at most 20 on each other host, 150 in all `[INFERENCE: counted from the rendered exporters and receivers]`.
  - The estimate becomes 3,000 + 2,464 + 222 + 252 + 66 + 150 = 6,154 series against the budget of 8,000, leaving 1,846; the 8,000 budget holds.
  - `systemd_unit_name`'s fleet-wide bound becomes the sum over NixOS agent hosts of 40 plus that host's notified units, 240 + 28 = 268, and the 30-name process bound is unchanged.
- **Regulation**: in `fleet-ingress`, on the real store, each clause fails on its fixture: 300 values of one label on a synthetic metric (A4 R4.2), 31 process names on one host, a notifier instance for a unit outside the host's list, a database whose `ttl` was altered, and a renamed table for the empty-result rule.
  At magnetite's deploy, a runtime drop-in setting `OTEL_ENVELOPE_MAX_UNITS=27` fails the unit-name clause against magnetite's 29 ordinary units and posts one `FAILED`, and removing it posts its `RESOLVED`.

### D9: Alerting over the fleet

- **Choice**: RN reads `flake.lib.observabilityHosts` instead of a `notifiedUnits` argument:
  - `SystemdUnitFailed` excludes the union of every host's `notifiedUnits` (M9);
  - `RuleSignalMissing.alwaysOn` is the hosts whose `alwaysOn` and `collect` are true, magnetite and cinnabar once cinnabar collects (O3);
  - expected hosts are every host whose `collect` is true for the memory, OOM, ZFS, unit, `LocalExporterDown`, `WeeklyPipelineTest` and filesystem rules, and those of them with `smartDevices` for the NVMe rules, so a host is expected only once it collects (M8);
  - the rule set gains A9's `FilesystemFillingWarn` (above 0.85, 15 min, warning), `FilesystemFull` (above 0.95, 5 min, critical), `NvmeCriticalWarning` (`smartctl_device_critical_warning_total != 0`, 0, critical) and `NvmeWearHigh` (`smartctl_device_percentage_used_total > 90`, 1 h, warning), with presence selectors `system_filesystem_usage_bytes`, `smartctl_device_critical_warning_total` and `smartctl_device_percentage_used_total`; the exporter declares both SMART fields counters, and the store names an OTLP Sum with `_total` (charter v25).
  `transition.jq` and `model.py` are unchanged, because `alwaysOn` and the expected hosts are data its existing rules read.
- **Rationale**: one absence path posts once per silence (O3; S3 review F1); pyrite stays out of `alwaysOn` in every option (BS D5).
  electrum, galena and scheelite are not always-on: they exist only while provisioned on demand, and their teardown is normal, so their silence raises nothing; one joins the list only by an edit of the table when it becomes permanently provisioned (DI 3; A9 item 16; RA:86).
  A pyrite that reports memory but no SMART raises `RuleSignalMissing` within 30 min (A9 Initial rule set).
  The run's queries become 22 PromQL on `fleet`, 12 presence selectors and 10 expressions outside the weekly window, plus the SQL rule, still one at a time.
- **Regulation**: `checks.x86_64-linux.fleet-alert` gains a leg in which cinnabar is silent for 40 min while magnetite reports, expecting one `[FIRING] RuleSignalMissing cinnabar` and its `[RESOLVED]`, a leg in which pyrite is silent with a firing instance, expecting no post, a leg firing each new rule from replayed series, and a leg in which the `SystemdUnitFailed` exclusion is read from two hosts' lists.
  Before the rules pull request merges, `FilesystemFillingWarn`, `FilesystemFull`, the NVMe rules and cinnabar's absence rule are replayed with `query_range` over `fleet`'s stored history for magnetite, cinnabar and pyrite, and each would-be firing is recorded with its cause (S2-R6; M14).
- **Alternatives considered**: deriving `alwaysOn` from the terranix `enabled` flags, rejected because a host provisioned for an hour would page when destroyed.

### D10: R3.1 and evaluation cost

- **Choice**: CC changes as follows.
  - Endpoints: the receivers', exporters' and scrape targets' endpoints are loopback except exactly one, `receivers."otlp/mesh".protocols.http.endpoint`, whose address must equal `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`, the address clan's ZeroTier service assigned.
  - Logs: the clause that no `logs/*` pipeline takes the local OTLP receiver admits `otlp/mesh` and no other `otlp` receiver.
  - Failure wiring: the policy gains `otel-envelope`.
  - Unit cap and owner aliases: removed from CC, now agent assertions on every host (D6).
  - New mutants: `[::]:4318` on `otlp/mesh`, a second receiver on magnetite's ZeroTier address, and a ZeroTier address file naming another address.
- **Rationale**: comparing the endpoint with `flake.lib.hosts.magnetite.zt` would compare two renderings of one attribute (S2-R6); the address ZeroTier assigned is defined independently of the registry, and the nonlocal bind would otherwise hide a mistyped registry address, since the receiver binds an address the host does not carry.
  The certificate's IP SAN is not compared: it is rendered from the same registry attribute at issue time, so the comparison would catch only a stale certificate after a registry edit, which clan's `validation.subjectAltNames` already regenerates.
  The validation override clause is unchanged, because validation opens no TLS file (DI 7; GR §1).
- **Evaluation cost**, each measured with the method in Constraints before and after its task, and a figure over 0.5 GiB stops the task (S2-R6):

| Check | Before | Estimate after | Source of the change |
|---|---|---|---|
| `otel-collector-config` | 488,430,112 B, 0.455 GiB (GR §6) | 0.455 to 0.475 GiB `[INFERENCE]` | one file read and a string comparison; magnetite's settings grow by four receivers; the cap and alias clauses leave |
| `fleet-alert` | 339,763,552 B, 0.316 GiB, at `7f0df3740` on stibnite, 2026-10-28 | 0.30 to 0.34 GiB `[INFERENCE]` | notified units from `flake.lib` instead of magnetite's option; four legs |
| `greptimedb-envelope` | 399,845,120 B, 0.372 GiB, at `7f0df3740` on stibnite, 2026-10-28 | under 0.38 GiB `[INFERENCE]` | one more generator file in R8.2's ownership clause |
| `otel-envelope`, new | none | 0.12 to 0.2 GiB `[INFERENCE]` | the script from `flake.lib` and the root pin's `pkgs`, no NixOS configuration, the class of `package-ntfy-send-test-token-transport` at 0.118 GiB (S2 design D14) |

  If `otel-collector-config` exceeds 0.5 GiB, the first remedy is to read magnetite's `services` only through the failure-wiring clause's names, the second to move the endpoint clause into its own check reading the receiver endpoint, the two vars files and nothing else.
  The machine toplevels of cinnabar (2.438 GiB) and pyrite (2.838 GiB) grow with the agent role and are outside the budget (S2 `plan/task-1.md:176`); scheelite's has no machine check (`modules/README.md:60`), so its agent is evaluated only when the plan evaluates it once.

### D11: The certificate files are guarded at runtime

- **Choice**: no evaluation-time clause guards the certificate, key and CA paths; a missing or unreadable file fails the collector's start, which posts a `FAILED` naming `opentelemetry-collector.service` from the host and fails `otel-envelope`'s C1 two runs later.
- **Rationale**: validation opens no TLS file, so build-time validation cannot catch a wrong path (DI 7; GR §1).
  An assertion comparing the configured paths with the `LoadCredential` entries would compare two renderings of the same binding in the clan role, a restatement (S2-R6).
  The CA is a store path, so only the per-host key and certificate can go missing, and clan's vars upload fails a deploy whose secret was never generated.
- **Regulation**: `fleet-ingress` starts an ingress whose `client_ca_file` names an absent file and requires the collector to fail with `failed to load client CA` and the notifier to log one `FAILED` (GR §2 phase G); each deploy step records `systemctl is-active opentelemetry-collector` on the host after the switch.

### D12: `fleet-ingress`

- **Choice**: `vmTests.x86_64-linux.fleet-ingress`, an nspawn container test following `greptimedb-pipeline`, run on demand on magnetite, with certificates generated at test build: a node holding the ingress role, the store and its schema job, with `otlp/mesh` on a loopback address, and a second collector unit running the agent role's rendered non-ingress configuration against it `[INFERENCE: one node with two collector units, as the spike ran on magnetite; a two-node topology if the container driver offers one]`.
  Cases:
  - Refusal: a client without a certificate, with a rogue CA's certificate, and with TLS 1.2 at most is refused at the handshake (AC2).
  - Delivery: the agent's metrics reach `fleet` with its `host_name` and its deploy records reach `devloop.deploy_record`, and every exporter's `send_failed` count is zero after first start (S1-R6).
  - Back-pressure: with the ingress's store exporter queue at two requests and the store stopped, then the limiter refusing, the agent's queue grows and drains, every scraped point arrives, and both hosts' `otel-envelope` pass (GR §2).
  - Loss controls, one per clause: the collector stopped (C1), node_exporter stopped (C2), the agent's queue at 1 MiB with the ingress down (C3, then C4 on enqueue failures), and the ingress limiter refusing its own scrapes (C4).
  - Crash loop: the agent collector killed four times in 10 min, and its `otel-envelope` passes whenever no point was lost.
  - Long running: `otel-envelope` over 10 runs on accumulated counters stays under its timeout and its state file stays at one line per series.
  - R4.2: D8's fixtures.
  - TLS file: D11's absent client CA.
- **Rationale**: the mTLS path, the back-pressure accounting and the envelope's runtime clauses depend on running collectors and a real store, which no sandbox check provides; VM tests need `/dev/kvm`, which only pyrite has (A9 Test-lane evidence), while nspawn runs on magnetite.
- **Boundary**: the container's loopback addresses stand in for the ZeroTier address; the real address and refusal are observed at acceptance.

### D13: Deploy order, the zerotierone restart and pyrite's SMART read

- **Choice**: the vars step runs first, then cinnabar, then magnetite, then pyrite, and rollback runs in reverse (O7).
  - The vars step generates `otel-ca`, then `otel-cert` for each of the six hosts, and adds pyrite, electrum, galena and scheelite as `ntfy-alerter` readers with `CLAN_NO_COMMIT=1 clan vars fix <host> --generator ntfy-alerter`, checking both hashes after each step (D1); pull request 1 carries them, and on cinnabar and pyrite, whose `collect` is false, they are only uploaded secret files that no unit reads.
  - cinnabar's deploy is preceded by its own pull request setting its `collect` to true, and pyrite's by its own; each lands immediately before that host's watched deploy, so no routine deploy from `main` applies the agent role to either host earlier (D6).
  - cinnabar is deployed with `--target-host root@49.13.68.78`; before the switch the operator records `zerotier-cli info`, `zerotier-cli listnetworks` and the sha256 of each file under `/var/lib/zerotier-one/controller.d/network/`, and after it requires the same network list, `ONLINE`, unchanged controller files, and magnetite answering `ping -6` on its ZeroTier address from cinnabar.
  - magnetite's deploy brings the ingress receiver; cinnabar's agent, which queued since its own deploy, drains, and the queue's size at the moment magnetite's receiver comes up, divided by the minutes since cinnabar's deploy, is cinnabar's measured rate (D2); if a routine deploy of magnetite from `main` brought the receiver first, cinnabar never queues, and the rate is recorded as not measured with the reason.
  - pyrite is deployed from the machine or its LAN address with the operator present, and the SMART read is observed after the switch without a reboot, because the exporter grants its own ACL (D4).
- **Rationale**: the switch stops and starts zerotierone on every host but magnetite, and on cinnabar that reruns the controller's setup hooks, so a session carried over ZeroTier drops and the `.zt` resolver pauses (DI 8; GR §3).
  The evaluator's heartbeat to cinnabar may miss one post inside the dead-man's 10-minute window (A9 item 9).
  A failed boot or network on pyrite cannot be recovered remotely, so its deploy and the O4 offline test are gated on the operator's presence (O4, O7; S3-R6).
- **Alternatives considered**: leaving `enableMetrics` off on cinnabar and pyrite, rejected by A3 item 5, which sets it explicitly so an upgrade past 1.16.0 keeps the signal; `udevadm trigger --action=add` on pyrite's NVMe device after the switch, rejected because it reruns every `add` rule for the device on a host that cannot be recovered remotely; a reboot of pyrite, rejected as a second gated step the ACL step makes unnecessary.

### Spec deltas beyond the proposal's list

The specs touch these requirements beyond the proposal's list, each a consequence of a decision above:

- `host-metrics-collection` `magnetite contributes its own signals to the telemetry store` is renamed `Each agent host contributes its own signals to the telemetry store` (O1).
- `host-metrics-collection` `A failed collection or store job notifies a person` names the collector and `otel-envelope` on every agent host (D6, D7), and `Stored unit names carry no owner's name` moves its alias regulator to every agent host (D6).
- `telemetry-store-interface` `Scrape targets are reached on loopback` adds the conditional service scrapes, the collector's own telemetry and SMART (D4), `Credentials exist only as activation-resolved files owned by non-worker users` admits `otel-envelope` as a `regulator-password` holder and names `otel-cert`'s key (D1, D8), and `Omnigent unit names are stored under aliases` moves its regulator from CC to the agent assertion (D6).
- `fleet-alerting-interface` `The evaluator queries each rule's database as the regulators' store account` counts the run's queries anew (D9).
- `devloop-collection-interface` `magnetite's collector ships its own deploy records` is renamed `Each agent host's collector ships its own deploy records`, and `Dev-loop sources are stamped and routed to their table` and the trust-boundary requirement follow (D5).
- `devloop-collection` `Every dev-loop event is recorded once and kept for a year` and `A gap in the dev-loop history reaches a person within a day` state the other hosts' deploys and the reconcile's one-host sample (O2).

The `world-assumptions` delta modifies A13 (O4), adds A50 to A52, the next free numbers after A49, and copies main's designation table whole, adding `agent host`, `ingress`, `collection certificate`, `provisioned host`, `laptop`, `file system`, `disk health`, `back-pressure`, `notifier instance` and a second sense of `identifier`, the collector-start one.
A13's longer sentences move into an **Evidence** paragraph, and the designation requirement's list of two-sense terms into a scenario, so each body stays under 500 characters with its claims unchanged; every main row survives (`LC_ALL=C comm -23` of the sorted row lists is empty).

### Decision records amended under charter v23

The orchestrator records these in the charter's v23 entry with this design; each is an amendment in place, and none changes a decision of O1 to O10 or M1 to M21.

- A3 R3.2, its implementation surface and OC:36, :83, :122: `otel-envelope` runs on every agent host and reads its own collector's telemetry and declared targets; its R4.2 clauses run in the ingress host's instance as `regulator` (D7, D8).
- A3 R3.1: the endpoint clause compares the receiver with the address ZeroTier assigned, not with the registry, and not with `otel-cert`'s IP SAN, which is rendered from the registry and which clan regenerates when the registry changes (D10).
- A3 item 19 and HP: the smartctl exporter grants its own device ACL before start (D4).
- A4 Rationale: the arithmetic of D8, 6,154 series against 8,000, and the fleet-wide unit-name bound of 268; R4.2's journald-bytes clause and the logs table's `ttl` land with S7.
- HP:88: R3.2's `up` clause probes the declared targets on the host itself.
- R8.3 (ADR-008) stays in the ingress host's `otel-envelope` instance, the only one holding a store credential (D8).

### Later slices

| Slice | Touches | Rule it must keep |
|---|---|---|
| S5 | darwin agents export to `otlp/mesh` and ship deploy records | each darwin host gets an `otel-cert` with `clientAuth` and a row in `flake.lib.observabilityHosts`; stibnite's `alwaysOn` stays false; R3.1 validates the darwin configurations; the 24 h queue relation becomes a darwin module assertion |
| S5 | `HostProbeStale` and the launchd rules | their expected hosts come from the table; R4.2's `launchd_label` clause gains input |
| S6 | dashboards over the new hosts | they read the stored self-telemetry as history, never as a regulator's input |
| S7 | journald on the agents' logs path | a new `routing/logs` item per table; content stages precede it; R4.2 gains its journald-bytes and logs-`ttl` clauses; `otlp/mesh` stays the only `otlp` receiver of a logs pipeline until the local receiver's ADR-008 stages exist |
| S8 | exports `devloop.deploy_record` | the rows of every agent host are exported, keyed by `host` |
| CAM-76 | the ntfy-outage watch | a full cinnabar outage is reported from outside cinnabar |

## Risks / Trade-offs

- [Risk] A lost or stolen key, most likely a laptop's, stays valid until `otel-ca` is rotated, and any certificate holder can write series under any `host_name`. → Mitigation: the runbook's rotation on compromise regenerates `otel-ca` and every `otel-cert` and redeploys every host; the trust boundary of `fleet-ingress-interface` states it (O10).
- [Risk] cinnabar's switch restarts zerotierone and reruns the controller's setup, which could leave the mesh's network configuration changed. → Mitigation: D13's before-and-after comparison of the controller files and network list, the public-address deploy, and rollback over the same address.
- [Risk] A stopped collector on an always-on host posts two messages, the envelope's `FAILED` and the evaluator's `RuleSignalMissing`. → Accepted: they name the cause and the silence, while a powered-off or disconnected host posts one (D7).
- [Risk] A laptop offline for more than about 21 h fills its queue past 90%, and its first run back online fails C3, which counts against pyrite's budget of 3. → Accepted: it reports a real or imminent loss; a laptop's notices while offline are lost, because the notifier does not retry (S2-R6 low).
- [Risk] At six hosts of magnetite's rate the ingress's 400 MiB `fleet` queue holds about 13 h of a store outage. → Mitigation: a full ingress queue answers 503 and each agent's own queue holds its 24 h (GR §2; M21); magnetite's own scrapes are the points lost first, which C4 reports.
- [Risk] The `otelcol` self-telemetry names change with a collector bump. → Mitigation: A52 records the behaviour relied on; the envelope treats absent telemetry as C1's failure and absent loss counters as zero, and C3 takes every exporter name the collector's configuration declares and, when the telemetry answers, fails any exporter missing either queue series, so a renamed queue metric fails C3 on the first run, which the check's `queueSizeAbsent` case and `queueSeriesOptional` mutant show before merge.
  As merged until tasks.md 12.2, C3 iterated only over the size series it found and passed when none existed (`review.md` F2).
- [Risk] `otel-collector-config` exceeds 0.5 GiB. → Mitigation: D10's two remedies, in order.
- [Risk] The nixpkgs smartctl module renames `smartctl-exporter-access`, and the ACL step fails the exporter's start. → Mitigation: the exporter's start failure fails `otel-envelope`'s C2 and `LocalExporterDown`, and `NvmeCriticalWarning`'s presence selector raises `RuleSignalMissing` for pyrite within 30 min.
- [Risk] A deploy-record line shipped from another host is lost, and no daily comparison sees it, because `devloop-reconcile` samples magnetite alone. → Accepted (O2); each host's first deploy compares its file with its rows (D5).
- [Risk] Hourly R4.2 queries over `fleet` add load to the store on the host with the OOM history. → Mitigation: the first runs' durations and the store's memory are recorded at deploy, and the envelope's `MemoryMax` bounds its own share.
- [Trade-off] electrum, galena and scheelite are configured but unobserved, and their silence never alerts. → Accepted (O1; DI 3).
- [Trade-off] No certificate revocation and 3650-day validity. → Accepted (O10).

## Migration Plan

The change lands as four pull requests, merged in order:

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | `flake.lib.observabilityHosts` with `collect` true for magnetite, electrum, galena and scheelite and false for cinnabar and pyrite; the generators and their vars; the role switch, exporters, ingress receiver, scrapes, filesystem, self-telemetry and SMART; the deploy-record move; `otel-envelope` with R3.2; the per-host assertions; CC's changes; RN's union; `otel-envelope` and `fleet-ingress`, the latter run on magnetite before merge; then one small pull request each setting cinnabar's and pyrite's `collect` to true, immediately before that host's deploy | vars, cinnabar, magnetite, pyrite (D13) |
| 2 | the four rules, `alwaysOn` from the table, the expected hosts and their fixture legs, after the replay of D9 | magnetite |
| 3 | R4.2 in the ingress host's `otel-envelope` and its holder entry | magnetite |
| 4 | the collector README, the runbook, OC and HP: agent hosts, certificate generation and rotation, the ingress, `otel-envelope` | none |

1. Before pull request 1's deploy, each verification command block runs once against cinnabar, magnetite and pyrite as a rehearsal, read-only, with its interpreter named, and the rehearsal log is kept with the plan review (S2-R6).
2. After cinnabar's deploy, cinnabar's agent queues to disk; D13's ZeroTier comparison passes, and the queue's growth is recorded until magnetite's deploy.
3. After magnetite's deploy, `ss -tlnH` on magnetite shows `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` and no other non-loopback collector listener; cinnabar's queue drains to zero; `count by (host_name) (system_memory_usage_bytes)` returns magnetite and cinnabar; a `curl` from stibnite without a certificate is refused at the handshake (AC2); cinnabar's and magnetite's `deploy_record` rows equal their files' line counts.
4. With the operator at pyrite, pyrite is deployed; its series appear, `smartctl_device_critical_warning_total{host_name="pyrite"}` is stored (AC3), and its deploy records match its file; this completes AC1 for the provisioned hosts.
5. Over the following 24 h, captured on magnetite, every `otel-envelope` passes; each host's stored unit names, process names and notifier instances are counted against D8's bounds.
6. Pull request 2 is replayed over the stored history (D9), merged and deployed; within 30 min no `RuleSignalMissing` fires.
7. AC4: the operator stops cinnabar's collector while ntfy runs and receives `[FIRING] RuleSignalMissing cinnabar` and the envelope's `FAILED` within 10 min, then starts it and receives both `RESOLVED`; with the operator at pyrite, pyrite is taken offline for 20 min and no alert names pyrite (O4, O5).
8. R3.2's other control: the operator stops cinnabar's `prometheus-node-exporter` and receives `FAILED otel-envelope.service on cinnabar` within 10 min, and `[FIRING] LocalExporterDown cinnabar` after its 10 min `for` if the stop lasts that long, then starts it and receives their `RESOLVED`.
9. After pull request 3's deploy, D8's drop-in control posts one `FAILED` and one `RESOLVED`, and the first hourly run's duration is recorded.

Rollback reverses the order: pull request 3's revert stops R4.2; pull request 2's restores magnetite as the only always-on and expected host; pull request 1 is undone by setting pyrite's and cinnabar's `collect` back to false and deploying each, pyrite with the operator present and cinnabar over its public address, each agent's queue left on disk, then by reverting pull request 1 with `vars/` kept and deploying magnetite; the vars stay committed and unused.

## Open Questions

None.
