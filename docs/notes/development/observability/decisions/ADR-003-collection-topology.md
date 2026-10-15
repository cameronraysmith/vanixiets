---
title: "ADR-003: Collection topology"
---

## Status

Proposed

## Context

Charter D3 asks for one collection topology: per-host agent versus central gateway, what a nix-darwin host can run, ZeroTier-only versus public ingress, and transport authentication.

The fleet is ten machines: six NixOS (cinnabar, electrum, galena, scheelite, magnetite, pyrite) and four darwin (blackphos, stibnite, rosegold, argentum) (`cameronraysmith/vanixiets@109c67346:modules/clan/inventory/machines.nix`).
Five of the ten are intermittent, and the darwin four have no `deploy.targetHost`, so a pull-only gateway misses them (`research/otel-collector-topology.md` F4, F5).
Three of the darwin machines are other people's primary laptops (`research/otel-collector-topology.md` Questions).

All three candidate agents are in the root pin (`nixpkgs_10` at `ac1faec44836`): `opentelemetry-collector-contrib` 0.155.0, `grafana-alloy` 1.17.1 and `vector` 0.59.0, and all three have `aarch64-darwin` outputs on cache.nixos.org (`research/otel-collector-topology.md` R2, R4).
nix-darwin has no module for any of them, so every candidate needs a first-party `launchd.daemons` unit (`research/otel-collector-topology.md` R5, R6).
On stibnite, a contrib `host_metrics` pipeline measured a peak memory footprint of 88 MB and 392 data points per scrape (`research/otel-collector-topology.md` R10).
launchd cannot enforce a process-tree memory ceiling, so a darwin collector's memory bound must be internal to the process (`research/otel-collector-topology.md` F12, F15).

GreptimeDB serves OTLP only over HTTP at `/v1/otlp/v1/<signal>`, protobuf only, with no OTLP gRPC trace or logs service in any release (`research/greptimedb.md` R4, R5, C2).
No released GreptimeDB accepts bearer tokens; the usable credential is HTTP Basic (`research/otel-collector-topology.md` C1).
GreptimeDB has no server-side client-certificate verification, so mTLS can terminate only in front of it (`research/otel-collector-topology.md` F27, F28; `research/greptimedb.md` R30).
GreptimeDB 1.1.4 and 1.2.1 silently discard OTLP exponential histograms (`research/greptimedb.md` R7).
The open build authenticates but authorizes nothing beyond a per-user `rw`/`ro`/`wo` mode (`research/telemetry-security-and-tenancy.md` R1, R2).

The mesh is one flat trust zone and now includes two unmanaged Android members (`research/otel-collector-topology.md` R18; `research/telemetry-security-and-tenancy.md` F34).
A fleet mTLS CA already exists as the `nix-grpc-ca` clan var, issuing each `nix-builders` member a certificate whose CN is the machine name (`research/otel-collector-topology.md` R20).
nix-grpc-daemon grants the `trusted` role, which is store-root-equivalent on the builder, to any certificate from that CA whose CN names a dispatcher (`cameronraysmith/vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:160-175`).
magnetite has been OOM-killed twice by evaluation overlap (`research/otel-collector-topology.md` R21).

Existing scrape targets on magnetite: gitea at `127.0.0.1:3002/metrics`, niks3 at `127.0.0.1:5752/metrics`, nixbot only through `/run/nixbot/web.sock` behind nginx (`research/fleet-emitter-inventory.md` updated emitter table).
Their public `/metrics` locations now admit only loopback and the ZeroTier /64 (`cameronraysmith/vanixiets@02432c594:modules/lib/nginx-metrics-location.nix`).
nginx `stub_status` is served at `http://127.0.0.1/nginx_status` (`research/fleet-emitter-inventory.md` R14).
zerotierone 1.16.0 serves `localhost:9993/metrics` behind a bearer token in `metricstoken.secret`, and from 1.16.1 metrics default to off unless `allowMetrics` is set (`research/fleet-emitter-inventory.md` R13).
nix-grpc-daemon metrics are off by default, and on magnetite and pyrite the daemon idle-exits after 600 s, resetting its counters (`research/fleet-emitter-inventory.md` R4).

## Decision

Run `opentelemetry-collector-contrib` 0.155.0 from the root nixpkgs pin as one per-host agent on every in-scope host, and give magnetite's agent the additional ingress role as the only holder of a store credential.

1. Every in-scope host runs one agent: the NixOS `services.opentelemetry-collector` module with `package = pkgs.opentelemetry-collector-contrib`, and on darwin a first-party `launchd.daemons.otelcol` running as a dedicated `_otelcol` user, wrapped behind `/bin/wait4path /nix/store` and `KeepAlive`, after the `nix-builders` precedent (`research/otel-collector-topology.md` R6).
2. In scope initially: the six NixOS machines and stibnite; blackphos, rosegold and argentum join only after their primary users consent (Q3).
3. Each agent listens for local emitters on `127.0.0.1:4318` (OTLP/HTTP) only; that receiver is wired into the traces and metrics pipelines and into no logs pipeline, so OTLP log records are rejected (see ADR-008).
4. Each agent collects `host_metrics` at a 60 s interval; NixOS agents also read `journald` restricted to the unit allow-list of ADR-004, and every agent tails `/var/log/deploy-record.jsonl` with the `filelog` receiver for the deploy record of ADR-005.
5. Each NixOS agent scrapes zerotierone at `localhost:9993/metrics` with the token delivered by `LoadCredential`, and `allowMetrics = true` is set explicitly in zerotierone's `localConf` so an upgrade past 1.16.0 does not silently stop the emitter.
6. magnetite's agent also scrapes gitea at `127.0.0.1:3002`, niks3 at `127.0.0.1:5752`, nixbot through a new loopback-only nginx server on `127.0.0.1:9180` that proxies `/metrics` to `/run/nixbot/web.sock`, and nginx through the `nginx` receiver at `http://127.0.0.1/nginx_status`; it also hosts the on-host PostgreSQL reader of ADR-005.
7. Every agent applies the redaction stages of ADR-008 and the signal allow-list of ADR-004 before any exporter, stamps `host.name` and a routing attribute naming the target database, and exports with `otlp_http` to `https://magnetite.zt:4318` presenting a client certificate.
8. Every agent's exporter uses a `sending_queue` backed by the `file_storage` extension, and every pipeline begins with `memory_limiter`.
9. magnetite's agent carries the ingress role: a second OTLP/HTTP receiver bound to magnetite's ZeroTier address on port 4318, opened on `zt+` only, requiring client certificates from the `otel-ca` CA through `tls.client_ca_file` (`open-telemetry/opentelemetry-collector@41da2fbd7:config/configtls/README.md:147`).
10. The ingress routes by the database attribute with the `routing` connector to one `otlp_http` exporter per GreptimeDB database, each with endpoint `http://127.0.0.1:4000/v1/otlp`, the header `x-greptime-db-name`, and the `basicauth` extension's `client_auth` reading the `collector` password, a write-only (`wo`) store user (`research/greptimedb.md` R26, R27; ADR-007).
11. The ingress metrics pipeline applies the `transform` function `convert_exponential_histogram_to_histogram` while the store is below 1.3.0 (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:processor/transformprocessor/README.md:475-479`; ADR-001).
12. Agent-to-ingress authentication uses a new clan-vars CA, `otel-ca`, and per-machine `otel-cert`, not `nix-grpc-ca`.
13. Transport is ZeroTier only; no public ingress exists, and nothing except magnetite's ingress listens beyond loopback.
14. nix-grpc-daemon metrics and macOS unified logging are not collected in this decision (Q6, Q7).

## Rationale

Per-host agents are required, because a gateway cannot pull from five intermittent hosts or push-unreachable darwin machines, and because redaction must run on the emitting host under a system account no worker controls (`research/telemetry-security-and-tenancy.md` refresh, Bearing on D8 and D3).
Direct export from every agent to the store would put a store password on every host, including laptops belonging to other people, against a store that cannot authorize per database (`research/otel-collector-topology.md` reconciliation).
Making magnetite's own agent the ingress gives one store credential, on the host that already runs the store, without a second collector process or a second host in the delivery path.
The store then binds loopback only, so its query surface is never on the mesh for ingest purposes, which matches ADR-007.
mTLS at the ingress is the authentication that composes in clan vars: the ingress needs only the public CA certificate, whereas per-host Basic credentials would require aggregating every machine's secret into one htpasswd file on magnetite.
A separate CA is required because a certificate from `nix-grpc-ca` with CN equal to a dispatcher's machine name is a trusted remote-build credential, so a collector-readable copy of such a key would widen who holds store-root-equivalent build authority.
`otelcol-contrib` is chosen over vector and grafana-alloy because it alone carries `redaction`, `transform` with the exponential-histogram conversion, `basicauth`, `file_storage`, `journald`, `filelog` and `sqlquery` in one binary, and because the NixOS module validates generated configuration with `otelcol validate` by default (`research/otel-collector-topology.md` R7, C7).
The contrib distribution, not the core default, is required for `basicauth`, `file_storage`, `journald` and `redaction` (`research/otel-collector-topology.md` C7).
ZeroTier-only transport reuses the existing `zt+` firewall idiom and the cognee no-public-bind predicate, whereas the only public ingress shape, `sso-gateway`, is redirect-based and disabled (`research/otel-collector-topology.md` F18, F21; `research/telemetry-security-and-tenancy.md` F18).
The 88 MB measured footprint is not disqualifying for a darwin agent (`research/otel-collector-topology.md` R10).

## Rejected alternatives

- Central gateway only, scraping hosts: misses intermittent and push-unreachable darwin hosts and cannot redact before data leaves the host.
- Direct export from every agent to the store: a store password on up to ten hosts against a store that authorizes nothing per database.
- Separate gateway collector on cinnabar: adds a hop and makes cinnabar a precondition for ingest while the store on magnetite remains the single point anyway.
- Separate gateway process on magnetite beside the agent: a second unit on a memory-constrained host with no failure prevented that the agent's ingress role does not already prevent.
- `grafana-alloy` 1.17.1: Loki-shaped journald path, no build-time config validation in its NixOS module, and a second configuration language for the same OTel components.
- `vector` 0.59.0: no GreptimeDB trace sink, no macOS log source, no exponential-histogram conversion, and no fail-closed attribute allow-list primitive equivalent to `redaction`.
- Core `otelcol` distribution: lacks `basicauth`, `file_storage`, `journald` and `redaction`.
- Public OTLP ingress: no off-mesh emitter is in scope and the existing public gateway cannot serve OTLP clients.
- Bearer-token authentication to the store: no released GreptimeDB accepts it.
- HTTP Basic from agents to the ingress: needs every machine's secret aggregated on magnetite.
- Reusing `nix-grpc-ca` for telemetry: a dispatcher-CN certificate from that CA is a trusted build credential.
- Prometheus `node_exporter` plus pull scraping: pull fails on intermittent hosts and adds a second agent per host.
- OTLP gRPC export: GreptimeDB serves no OTLP gRPC traces or logs.

## Consequences

Every in-scope host gains one long-running collector, and darwin hosts gain a first-party launchd unit and a dedicated user.
magnetite's collector becomes a dependency of all ingest; while magnetite is down, agents buffer to disk and replay.
Agents on other hosts never hold a store credential; a compromised host can write telemetry as any host through the ingress, because the ingress does not bind certificate CN to the stamped `host.name`.
Local emitters on a host reach the agent over unauthenticated loopback, so any local UID can inject telemetry attributed to that host, and person attribution is emitter-claimed rather than enforced (see ADR-008).
The Android mesh members cannot write, because they hold no `otel-ca` certificate.
The `.zt` name `magnetite.zt` depends on cinnabar's dnsmasq (`research/otel-collector-topology.md` R19); agents queue while resolution fails.
nixbot's metrics need a new loopback nginx server block, which is a change to `modules/nixos/nixbot.nix`.
The darwin agent's configuration is check-bound only through nixbot's best-effort darwin checks (`research/otel-collector-topology.md` C5), so the configuration validation check below evaluates the darwin configuration text on `x86_64-linux` to make it gating.
The `routing` connector, `sqlquery`, `journald` and `redaction` for logs are alpha components (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:connector/routingconnector/metadata.yaml`, `:receiver/journaldreceiver/metadata.yaml:9`, `:processor/redactionprocessor/metadata.yaml:13-14`).
nixpkgs' collector lags upstream by eight minor releases (`research/otel-collector-topology.md` R3); this decision accepts the pinned 0.155.0 (Q8).

## Operating envelope and regulator

Envelope, agent on a non-ingress host: `memory_limiter` at 150 MiB with a 30 MiB spike allowance; on NixOS additionally `MemoryMax = 256M`; on darwin the internal limiter is the only bound.
Envelope, ingress on magnetite: `memory_limiter` at 384 MiB, `MemoryMax = 512M`, and `OOMScoreAdjust = 300`.
Under host memory exhaustion the kernel selects the store (`OOMScoreAdjust = 500`, ADR-007) first and the ingress collector second, so the collector survives the store's death and queues, while still dying before PostgreSQL, nix-daemon and every other service at a score of 0 or lower.
Envelope, buffering: each agent's `file_storage` queue absorbs at least 24 h of that host's output and stays below 512 MiB on disk.
Envelope, freshness: every in-scope host that is online delivers host metrics to the store within 5 min of collection.
Envelope, exposure: no collector listener binds outside loopback except the ingress receiver on magnetite's ZeroTier address.

Regulator R3.1, deterministic, build time: a flake check `checks.x86_64-linux.otel-collector-config` runs `otelcol-contrib validate` over the generated configuration of every agent, darwin included, and asserts with the cognee predicate (`cameronraysmith/vanixiets@109c67346:modules/nixos/cognee.nix:26-27`) that every receiver endpoint is loopback or ZeroTier-prefixed.
It is shown able to fail by two mutants run at acceptance: an unknown component key, and a receiver endpoint of `0.0.0.0:4318`.
The NixOS module's own `otelcol validate` remains in force for NixOS hosts (`research/otel-collector-topology.md` R7).

Regulator R3.2, runtime: a systemd timer `otel-envelope` on magnetite queries the store each 5 min, as the read-only `regulator` store user of ADR-007, for per-host last-seen time of host metrics, and for the collectors' own `otelcol_exporter_queue_size`, `otelcol_exporter_send_failed_*` and `memory_limiter` refusal counters, and fails the unit when any declared bound is breached.
It is shown able to fail at acceptance by stopping one online host's agent and observing the unit fail within 10 min.

Failure notification, owned by this record for every regulator and oneshot unit of the observability decisions: `otel-envelope` (this record), `devloop-reconcile` (ADR-005), and `greptimedb-envelope`, `greptimedb-export` and `greptimedb-schema` (ADR-007) each set `OnFailure=` to a shared notifier unit `observability-notify@%n.service` that posts the failed unit's name and host to the existing ntfy on cinnabar (Q9).
No unit-state signal is written to the store; the notifier is the only path from a failed regulator to a human.
It is shown able to fail at acceptance by the R3.2 stopped-agent test producing a ntfy message naming `otel-envelope.service`.

## Failure prevented

- Per-host agent: telemetry from intermittent and darwin hosts that no pull reaches is lost, and content leaves the host before redaction.
- Ingress role on magnetite's agent: a store password on every host, and a mesh-reachable store listener that unmanaged mesh members can probe.
- mTLS with `otel-ca`: an unmanaged mesh member or a host outside the fleet writes into the store.
- Separate CA: a telemetry key becomes a trusted remote-build credential on the builders.
- Loopback-only local receiver with no logs pipeline: a worker's ungated OTLP log records reach the store.
- `file_storage` queue: data is lost while magnetite is down or OOM-killed, or while a laptop is offline.
- `memory_limiter`, `MemoryMax` and `OOMScoreAdjust`: the collector contributes to a magnetite OOM, dies before the store and so stops queueing, or survives ahead of PostgreSQL (`research/otel-collector-topology.md` R21).
- Exponential-histogram transform: histogram data is silently discarded by GreptimeDB below 1.3.0.
- Explicit `allowMetrics`: an upgrade past zerotierone 1.16.0 silently removes the mesh-health signal.
- Loopback nginx block for nixbot: nixbot's metrics have no scrape path, because its public location denies magnetite's public address.
- R3.1: a configuration that does not parse or that binds publicly ships to a host, including a darwin host whose check is non-gating.
- R3.2 and the notifier: a host silently stops delivering, queues grow until data is dropped, or any observability regulator or oneshot fails, with nobody told.

## Implementation surface

- Add `modules/clan/services/otel-collector/flake-module.nix`: clan service `otel-collector` with roles `agent` and `ingress`, a `nixosModule` and a `darwinModule` per role, the `zt+` firewall opening for 4318 on the ingress, and the generators below (shape per ADR-007).
- Add `modules/clan/inventory/services/otel-collector.nix`: one instance, `agent` on cinnabar, electrum, galena, scheelite, magnetite, pyrite and stibnite, `ingress` on magnetite.
- Add `modules/checks/otel-collector-config.nix`: regulator R3.1.
- Add the `otel-envelope` service and timer to the `ingress` role's NixOS module: regulator R3.2.
- Add the `observability-notify@` template unit to the `ingress` role's NixOS module, and `OnFailure=observability-notify@%n.service` on `otel-envelope`; ADR-005 and ADR-007 set the same `OnFailure=` on their units.
- Modify `modules/nixos/nixbot.nix`: a loopback-only nginx server on `127.0.0.1:9180` proxying `/metrics` to the nixbot socket.
- Modify `modules/clan/inventory/services/zerotier.nix` or the zerotier NixOS configuration it applies: `services.zerotierone.localConf.settings.allowMetrics = true`.
- No flake input is added; `opentelemetry-collector-contrib` comes from the root `nixpkgs` input.
- Clan vars generator `otel-ca`: `share = true`, `files."ca.key".deploy = false`, `files."ca.crt".secret = false`, openssl P-256 self-signed CA, after `nix-grpc-ca` (`cameronraysmith/vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:106-120`).
- Clan vars generator `otel-cert`: per machine, depends on `otel-ca`, CN the machine name, `extendedKeyUsage=clientAuth` on agents and additionally `serverAuth` with the ZeroTier address as IP SAN and `magnetite.zt` as DNS SAN on magnetite, key owned by `_otelcol` on darwin and consumed by `LoadCredential` on NixOS.
- Consumed, not created here: the `collector-password` and `regulator-password` files of ADR-007's `greptimedb-users` generator, read by the ingress and by `otel-envelope` through `LoadCredential` (the ingress through a `${file:...}` reference).

## Questions for the human gate

1. Q1: Is the ingress role on magnetite's agent acceptable rather than a separate gateway? Recommended: yes; the alternative adds a process or a host to every delivery path.
2. Q2: Reuse `nix-grpc-ca` or mint `otel-ca`? Recommended: mint `otel-ca`; reuse makes a telemetry key a trusted remote-build credential for dispatcher CNs.
3. Q3: Are blackphos, rosegold and argentum telemetry subjects? Recommended: no until each primary user consents; the alternative collects host data from other people's laptops without consent.
4. Q4: Are the Android ZeroTier members telemetry subjects? Recommended: no, they are refused by mTLS; the alternative needs a certificate path for unmanaged devices.
5. Q5: Is a darwin agent acceptable while nixbot's darwin checks are non-gating? Recommended: yes, with R3.1 validating darwin configuration on `x86_64-linux`; the alternative requires a gating darwin builder first.
6. Q6: Enable nix-grpc-daemon `metricsListen` and disable its idle exit? Recommended: no; its per-RPC logfmt line already reaches journald, and the alternative keeps an idle daemon resident on magnetite.
7. Q7: Collect macOS unified logging with the alpha `macos_unified_logging` receiver? Recommended: no in this decision; the alternative ships an alpha receiver over a log stream with no content allow-list.
8. Q8: Accept the pinned collector 0.155.0 against upstream 0.163.0? Recommended: yes, take upgrades through pin bumps; the alternative carries an override derivation.
9. Q9: How does a failed regulator or oneshot unit notify a human? Recommended: `OnFailure=observability-notify@%n.service` on `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope`, `greptimedb-export` and `greptimedb-schema`, posting to the existing ntfy on cinnabar; the alternative leaves those failures visible only in `systemctl --failed`.
