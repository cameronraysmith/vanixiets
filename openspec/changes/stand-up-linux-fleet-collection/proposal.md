---
linear_story_id: CAM-71
linear_story_identifier: CAM-71
linear_story_title: "S4: Extend collection to the Linux fleet over mTLS"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-71/s4-extend-collection-to-the-linux-fleet-over-mtls
linear_story_state: Todo
linear_team: CAM
linear_project: fleet-observability
last_synced_state: Todo
last_synced_at: 2026-10-28T20:35:36Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-10-28T20:35:36Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; description seeded from this proposal" }
---

## Why

Only magnetite reports to the telemetry store, so a full disk, a failing unit or a dead collector on cinnabar or pyrite is found by hand, and the evaluator's rules expect magnetite alone.
S1 to S3 are deployed and S2's close-out task 7.7 is due 2026-10-29, so the ingress and the alert path exist for other hosts to join.
This change issues every NixOS host a certificate from `otel-ca`, opens magnetite's ingress on ZeroTier to certificate holders only, runs the agent role on every in-scope NixOS host, reads pyrite's NVMe health, and regulates delivery with `otel-envelope`, so an always-on host's silence alerts and a laptop's does not.

## What Changes

Decisions tagged `O<n>` were decided by the operator, 2026-10-27; the matching line in `brainstorm.md` carries the same tag.

**Sequencing**
- S4's design and spec deltas start only after S2 is archived; S2's task 7.7 is due 2026-10-29, and the deltas below are written against the main specs that S2's archive produces (M17).

**A certificate authority for collection**
- A shared `otel-ca` and a per-machine `otel-cert`, copied from `nix-grpc-ca` and `nix-grpc-cert`, issue P-256 certificates with CN the machine name, valid 3650 days and rotated on compromise only (D1, O10).
- Every vars step is followed by a check that `ca.crt` and the `ntfy-alerter` token are unchanged.

**The ingress on ZeroTier**
- magnetite's ingress receiver binds `flake.lib.hosts.magnetite.zt` port 4318 with the existing nonlocal bind, requires a client certificate from `otel-ca` at TLS 1.3, and is opened on `zt+` only (D6).
- Agents address the ingress by `flake.lib.hosts.magnetite.zt` rather than `magnetite.zt`, removing the dependency on cinnabar's resolver.
- The ingress keeps its 400 MiB `fleet` queue, and each agent's own queue holds 24 h of its host (D9).

**The agent role on the NixOS fleet**
- All six in-scope NixOS hosts carry the agent role, and the three provisioned hosts, magnetite, cinnabar and pyrite, report at acceptance (D3, O1).
- The agent exports by role: `forward` beside the ingress and mTLS `otlp_http` elsewhere, with ADR-003's 150 MiB limiter, `MemoryMax = 256M` and a persistent queue off magnetite (D2).
- Service scrapes run only where their service runs; NixOS agents gain a filesystem scraper bounded to the host's ZFS mountpoints and a scrape of the collector's own queue and send-failure counters.
- pyrite runs `smartctl_exporter` on `/dev/nvme0`, whose health log `smartctl` read on 2026-10-27.
- Agent hosts ship their deploy records over S2's logs path into `devloop`, and `devloop-reconcile` stays on magnetite (D4, O2).
- Every agent host carries the `observability-notify` template.

**Alerting over the fleet**
- The evaluator's always-on hosts become magnetite and cinnabar and are the single host-absence path, while R3.2 drops its per-host last-seen clause (D5, O3).
- Each rule expects the hosts that produce its signal: the NixOS agent hosts, pyrite for NVMe, and every agent host for filesystems.
- `SystemdUnitFailed` excludes the union of every host's notified units, read from one `flake.lib` list.
- `observability-notify@` instances are excluded from the per-host cap of 40 unit names and bounded by the host's notified units, which magnetite's 44 stored names exceed today (D10, O6).

**Regulators**
- `otel-envelope` on every agent host checks the collector's `up`, queue, send-failure and limiter clauses (R3.2) and the 30-name process bound (R4.2), with crash-loop and long-running cases and a negative control per clause; R8.3 stays with S7.
- R3.1 admits exactly one non-loopback endpoint, the ingress receiver, equal to the registry address and the certificate's IP SAN, and applies its 24 h queue clause per agent host.
- Relations within one host become fragment assertions, and every changed check is measured against the 0.5 GiB budget before and after (D7).

**Deployment**
- Vars first, then cinnabar over its public address, then magnetite, then pyrite with the operator present; rollback in reverse order (D8, O7).

**Decision records amended through a charter version entry**
- From: S1 and S3 to S5 stay metrics-only (CH:360, RA:249); every agent exports to `https://magnetite.zt:4318` (ADR-003 item 7); R3.2 fails on an always-on host's missing last-seen and `RuleSignalMissing` also fires for it (ADR-003 R3.2, ADR-009 item 16); every host stores at most 40 unit names (ADR-004:130); CAM-76 blocks S5 because S5 adds laptops (CH:354, RA:280).
- To: S4 ships deploy records from agent hosts over S2's non-content logs path (O2); agents export to the literal address of `flake.lib.hosts.magnetite.zt` (M20); the evaluator's always-on list is the only host-absence path, and R3.2 keeps its `up`, queue, send-failure and limiter clauses (O3); the 40-name bound excludes `observability-notify@` instances, which are bounded by the host's notified units (O6); S4 proceeds before CAM-76 although pyrite is a laptop, because adding pyrite does not change the ntfy-outage exposure CAM-76 addresses (O8).
- Reason: S2 built the logs path for agents' deploy records, the IP literal matches the certificate and removes a resolver dependency, two absence paths would post twice per silence, the notifier instances pass the allow-list since S3's F2, and CAM-76's reason applies to pyrite while no source makes it block S4.
- Impact: non-breaking; documentation only, with ADR-003 Q15 answered without amendment.

**Linear story corrected**
- CAM-71's AC1 becomes every provisioned in-scope NixOS host (O1).
- Its AC4 for pyrite becomes silence by going offline or powering off with the operator present, since pyrite no longer suspends (O4), and for cinnabar a stopped collector while ntfy runs, with a full cinnabar outage left to CAM-76 (O5).
- Its deliverables gain the filesystem scraper and deploy records and drop "the same host and service metrics as magnetite" (O2, O9).

## Capabilities

### New Capabilities
- `fleet-ingress-interface` (stratum: `interface`): the properties at the machine's interface that let a host other than magnetite deliver to the store — `otel-ca`, each `otel-cert`, their key usages, SANs and validity; the ingress receiver's address, port, TLS version and client CA, and the firewall opening; the agent's exporter by role, its endpoint, queue, retries and memory envelope; and `otel-envelope`'s clauses, inputs and notification.
  Trust boundary: any holder of an `otel-ca` certificate is trusted to write, and a certificate's CN is not bound to the `host.name` its agent stamps; the CA key is trusted to stay in the encrypted repository vars; ZeroTier is trusted to deliver packets between members and nothing more; certificates have no revocation, so a lost key stays valid until the CA is rotated; nothing here guarantees that a series reaches the store end to end, only that each stage's configuration, the gating checks, the container test and `otel-envelope` behave as stated.

### Modified Capabilities
- `host-metrics-collection` (stratum: `behavioral`): `magnetite contributes its own signals to the telemetry store` widens to every provisioned in-scope NixOS host, with filesystem fill and, on pyrite, NVMe health; `Series cardinality stays bounded` counts unit names without the notifier instances; `Collection survives a telemetry store restart without losing the queued interval` holds for each agent host's queue.
- `telemetry-store-interface` (stratum: `interface`): `Listeners are bound to loopback only` admits the one ingress receiver on ZeroTier; `Ingest is OTLP over HTTP with a database header` admits mTLS ingest from agents, including deploy-record rows (O2); `The collector's configuration bounds what it gathers` applies per agent host, adds the filesystem scraper, drops "slice S4" and moves the process bound to `otel-envelope`; `The telemetry store and the collector run inside a declared envelope` adds the non-ingress agent's envelope; `Failure notices are posted to one topic` adds `otel-envelope.service` on every agent host.
- `fleet-alerting` (stratum: `behavioral`): `Each known failure class on a host reaches a person as an alert` covers every reporting NixOS host, filesystem fill and pyrite's NVMe health; `A missing signal is itself reported` reports an always-on host's silence and never a laptop's.
- `fleet-alerting-interface` (stratum: `interface`): `An always-on host's silence is reported` lists magnetite and cinnabar as the only absence path (O3); `Each rule's presence selector is watched` takes per-rule expected hosts; the rule-rendering requirement reads the notified-units union from one `flake.lib` list.
- `devloop-collection` (stratum: `behavioral`) and `devloop-collection-interface` (stratum: `interface`), as archived by S2: deploys on every agent host are recorded through the agent's logs path, and the reconcile still samples magnetite alone (O2).
- `world-assumptions` (stratum: `world`): A13 records that pyrite no longer suspends and falls silent by power-off, reboot or leaving the network (O4); new assumptions record electrum, galena and scheelite as unprovisioned (O1) and pyrite's NVMe controller answering the health log at the pinned smartmontools; the designation table gains agent host, always-on host, ingress and collection certificate.

`telemetry-store`'s `Only the collector writes and only named readers read` is unchanged, because magnetite's ingress remains the store's only writer.

## Impact

- New: the `otel-ca` and `otel-cert` generators, the `otel-envelope` unit and timer, and the `smartctl_exporter` configuration on pyrite.
- Changed: `modules/clan/services/otel-collector/flake-module.nix` (role switch, receiver, TLS, conditional scrapes, filesystem scraper, self-telemetry scrape), `schema.nix` (filesystem series, unit cap), `modules/clan/inventory/services/otel-collector.nix` (agent hosts), `modules/nixos/devloop-collection.nix` (deploy-record receiver moved to the agent, O2), `modules/nixos/fleet-alert/rules.nix` and `transition.jq` fixtures (always-on hosts, expected hosts, union), `modules/lib/hosts.nix` or a sibling (notified units), `modules/checks/otel-collector-config.nix` and `modules/checks/fleet-alert.nix`, and the machine files of magnetite, cinnabar and pyrite.
- Documentation: the charter version entry carrying the amendments to CH:354, CH:360, RA:249, RA:280, ADR-003 item 7 and R3.2, ADR-004:130 and ADR-009 item 16; the `otel-collector` and `host-probes` components; the collector README and the runbook (agent hosts, certificate generation and rotation, the ingress).
- New secrets: `otel-ca` (shared, key not deployed) and one `otel-cert` per NixOS host; pyrite and the unprovisioned hosts become `ntfy-alerter` readers.
- Deployment: `clan vars` steps with hash checks, then `clan machines update` for cinnabar, magnetite and pyrite in that order; zerotierone restarts on cinnabar and pyrite.
- Residual risk: certificates cannot be revoked short of rotating the CA; a full cinnabar outage stops ntfy and is unreported until CAM-76; electrum, galena and scheelite are configured but unobserved until provisioned.
- Out of scope, each in a later item: darwin agents on stibnite and the laptops (S5), dashboards over the new hosts (S6), journald logs on the agents' logs path (S7), the export of deploy-record rows (S8), and ntfy-outage detection (CAM-76).
