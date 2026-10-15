---
title: Collection topology decision space for the vanixiets fleet
status: research v1
date: 2026-09-18
sources:
  - vanixiets@da74672e5
  - nixos/nixpkgs@85f62611f
  - nix-darwin/nix-darwin@4cff07de
  - GreptimeTeam/greptimedb@20d87cff4
---

# Collection topology decision space for the vanixiets fleet

This artifact lays out the option space for charter D3 and hands D4 a volume figure.
It decides nothing.

## Findings

### Fleet shape

F1.
The inventory is six `x86_64-linux` and four `aarch64-darwin` machines, enumerated in one attrset at `vanixiets@da74672e5:modules/clan/inventory/machines.nix:3-12`.

F2.
Five of the six NixOS hosts carry a `cloud` tag and a `deploy.targetHost` of the form `root@<name>.zt`, so every push path already runs over ZeroTier (`vanixiets@da74672e5:modules/clan/inventory/machines.nix:16-75`).

F3.
`pyrite` is the sixth NixOS host and is tagged `laptop`, with a ZeroTier `deploy.targetHost` like the cloud hosts (`vanixiets@da74672e5:modules/clan/inventory/machines.nix:77-86`).

F4.
The four darwin machines carry no `deploy.targetHost` key at all (`vanixiets@da74672e5:modules/clan/inventory/machines.nix:88-130`), so they are activated locally and cannot be reached by a push-shaped rollout.

F5.
Counting tags rather than assumptions, six of ten machines are `laptop`-tagged and only five are always-on cloud hosts, which makes the intermittent population five of ten rather than two.

F6.
`scheelite` is listed as `deferred` in the machine-check emitter (`vanixiets@da74672e5:modules/checks/machines.nix:6`), so a collector module placed on it would not be build-gated by `nix flake check`.

F7.
Darwin system closures are check-bound as `darwin-<name>`, filtered to the matching system (`vanixiets@da74672e5:modules/checks/machines.nix:21-23,62-68`), so a darwin collector evaluates only on an `aarch64-darwin` builder.

### What a darwin host can run

F8.
At the pinned nix-darwin revision the only monitoring service modules are `netdata`, `prometheus-node-exporter` and `telegraf`; no `opentelemetry-collector`, `vector` or `alloy` module exists (`nix-darwin/nix-darwin@4cff07de:modules/services/monitoring/`).

F9.
The telegraf darwin module expresses exactly two lifecycle keys, `KeepAlive` and `RunAtLoad` (`nix-darwin/nix-darwin@4cff07de:modules/services/monitoring/telegraf.nix:57-67`), which bounds what a hand-written collector daemon can express.

F10.
The repository's own system-daemon shape is `launchd.daemons.<name>` with `UserName`, `RunAtLoad`, `KeepAlive.SuccessfulExit`, `ThrottleInterval`, `ProcessType` and explicit `StandardOutPath` (`vanixiets@da74672e5:modules/darwin/omnigent-host.nix:439-457`).

F11.
Ordering one daemon after another is done by string-concatenating a dependency's command into `system.activationScripts.launchd.text` under `lib.mkBefore` (`vanixiets@da74672e5:modules/darwin/omnigent-host.nix:417,435-438`), which is this repository's existing substitute for a systemd `After=`.

F12.
`NoNewPrivileges` has no launchd analogue, and `MemoryHigh` with `MemoryMax` have no aggregate process-tree equivalent, with `ResidentSetSize` explicitly recorded as not restoring them (`vanixiets@da74672e5:modules/clan/services/omnigent/README.md:80-82`).

F13.
Availability before first login, after logout or reboot, Keychain access and Background Items approval are recorded as runtime checks rather than evaluation guarantees (`vanixiets@da74672e5:modules/clan/services/omnigent/README.md:83`).

F14.
A sleeping laptop is recorded as showing offline and reconnecting on wake, with no network-state load restriction and no disabled restart (`vanixiets@da74672e5:modules/clan/services/omnigent/README.md:75-76`), so a darwin collector keeps running across the offline interval instead of being held off.

F15.
The consequence for D3 is that a darwin collector's resource ceiling is unenforceable at configuration time, so any memory bound must be internal to the collector process rather than supervisory.

### Transport and ingress

F16.
magnetite's firewall opens 22, 80 and 443 publicly and only 8090 on `zt+`, with an in-file note that service modules add further ZeroTier ports (`vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:451-462`).

F17.
Per-service `zt+` openings already exist for buildbot on 9989 (`vanixiets@da74672e5:modules/nixos/buildbot.nix:217`) and cognee on 9270 (`vanixiets@da74672e5:modules/nixos/cognee.nix:258`), so a mesh-only OTLP port is the established idiom rather than a new pattern.

F18.
cognee is the precedent for mesh-only ingest carrying a build-time no-public-bind assertion over a ZeroTier-prefix predicate (`vanixiets@da74672e5:modules/nixos/cognee.nix:26-27,172-186`), and that predicate is reusable verbatim as a collector regulator.

F19.
That assertion is load-bearing rather than decorative because `net.ipv6.ip_nonlocal_bind` is set to 1 on magnetite (`vanixiets@da74672e5:modules/machines/nixos/magnetite/default.nix:437`), which makes a wrong public bind silent.

F20.
Public ingress also has an existing shape: `sso-gateway` registers a `forceSSL` plus `enableACME` vhost behind one shared oauth2-proxy keyed by kanidm groups (`vanixiets@da74672e5:modules/nixos/sso-gateway.nix:288-306,500`).

F21.
That gateway is a browser-redirect flow whose only non-redirect path is a fast 401 for `/api` locations (`vanixiets@da74672e5:modules/nixos/sso-gateway.nix:150-154`), which fits a dashboard but not an OTLP client that cannot follow an OIDC redirect.

F22.
ZeroTier path MTU forces a fleet-wide MSS clamp to 1300 on both `zt+` directions (`vanixiets@da74672e5:modules/nixos/zerotier-mss-clamp.nix:9-10`), so mesh OTLP pays more packets per payload than a public 1500-byte path would.

F23.
Darwin ZeroTier membership is external to clan and is carried as four static `allowedIps` entries on the controller (`vanixiets@da74672e5:modules/clan/inventory/services/zerotier.nix:15-22`), so darwin mesh reachability is manual configuration rather than a fleet-managed property.

F24.
GreptimeDB serves OTLP over HTTP at `/v1/otlp/v1/metrics`, `/v1/otlp/v1/traces` and `/v1/otlp/v1/logs` (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:769,1486-1494`).

F25.
Over gRPC it registers only an OTel-Arrow metrics service (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/grpc/builder.rs:91,181`), and no standard OTLP gRPC trace or logs service is registered anywhere in `src/`, so `otlphttp` is the required exporter for traces and logs.

F26.
Its HTTP authorization accepts Basic credentials and an opaque or JWT Bearer token (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/authorize.rs:83-86,294-342`), so bearer auth needs no additional component.

F27.
Server-side client-certificate verification is unimplemented: `with_client_cert_verifier` is a TODO and the TLS mode type is documented as applying to MySQL and Postgres startup (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/tls.rs:31,176`).

F28.
Therefore mTLS for OTLP can only be terminated in front of the store, by nginx or by a gateway collector, and never by the store itself.

### Buffering and delivery

F29.
The NixOS collector module runs under `DynamicUser` but does allocate `StateDirectory` and `WorkingDirectory` (`nixos/nixpkgs@85f62611f:nixos/modules/services/monitoring/opentelemetry-collector.nix:86-97`), so a persistent sending queue has a durable home without overriding the module.

F30.
That module's package default is `opentelemetry-collector`, the core distribution, not contrib (`nixos/nixpkgs@85f62611f:nixos/modules/services/monitoring/opentelemetry-collector.nix:42`), and the contrib distribution is a sibling attribute in the same release set (`nixos/nixpkgs@85f62611f:pkgs/tools/misc/opentelemetry-collector/releases.nix:153-172`), so a persistent-queue extension requires an explicit package override.

F31.
Both alternatives allocate state the same way, `StateDirectory = "vector"` (`nixos/nixpkgs@85f62611f:nixos/modules/services/logging/vector.nix:78-80`) and `StateDirectory = "alloy"` (`nixos/nixpkgs@85f62611f:nixos/modules/services/monitoring/alloy.nix:84,93`), so disk buffering is equally available across candidates on NixOS.

F32.
No equivalent exists on darwin, since no module allocates anything; a buffer directory, its mode and its owner must be declared by whatever module we write.

### Distribution

F33.
The `alloy` attribute at the pinned nixpkgs is the AlloyTools relational modeling language at version 5.1.0, a JRE-wrapped jar described as a "Language & tool for relational models" (`nixos/nixpkgs@85f62611f:pkgs/development/tools/alloy/default.nix:51,61,73`).

F34.
Grafana Alloy is a different attribute, `grafana-alloy` at 1.17.1 (`nixos/nixpkgs@85f62611f:pkgs/by-name/gr/grafana-alloy/package.nix:22-23`), and `services.alloy.package` defaults to it rather than to `alloy` (`nixos/nixpkgs@85f62611f:nixos/modules/services/monitoring/alloy.nix:21`).

F35.
The collector release set is at 0.155.0 and builds three distributions, `otelcol`, `otelcol-contrib` and `otelcol-otlp` (`nixos/nixpkgs@85f62611f:pkgs/tools/misc/opentelemetry-collector/releases.nix:18,153-172`).

F36.
vector is 0.57.0 with `platforms = all` and no `badPlatforms`, skipping one `aarch64-darwin` test against upstream issue 23813 (`nixos/nixpkgs@85f62611f:pkgs/by-name/ve/vector/package.nix:31,131,169`).

F37.
grafana-alloy is `platforms = unix` (`nixos/nixpkgs@85f62611f:pkgs/by-name/gr/grafana-alloy/package.nix:155`), so all three candidates are in-platform on darwin and platform support does not separate them.

F38.
Nor does darwin module cost separate them, since none of the three has a nix-darwin module (F8).

### Volume and cardinality

F39.
magnetite is a 16-vCPU guest with 30.6 GiB RAM, 20 GiB available at measurement, a 30 GiB zram device, `zroot/root/nix` at 62.8G compressed under a 250G quota with 187G available, and a 304G pool at 24% allocated (`vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:192-194`).

F40.
That quota exists because `/nix` once consumed the entire pool, and the same commit added dataset reservations in response (`vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:206`), so a telemetry store needs its own quota-bearing dataset rather than shared space.

F41.
Estimated, not measured: default host-metric scrapers yield roughly 250 to 350 active series per host, with magnetite's 16 vCPU contributing about 130 by itself, giving roughly 3,000 fleet-wide series and about 50 datapoints per second at a 60-second interval.

F42.
Dev-loop signal volume is bounded by measured service rates: 117 checks per evaluation (`vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:138`) against a measured ceiling of about twenty evaluations per hour (`:81`) gives roughly 2,340 check outcomes per hour and under 60,000 per day.

F43.
The cardinality hazard is therefore not volume but unbounded label domains, since check name is closed at 117 and machine at ten, whereas pull-request number, commit hash, build id and store path each grow without bound; pull-request numbers past 2908 are already in the record (`vanixiets@da74672e5:docs/notes/development/incidents/2026-09-02-nixbot-eval-throughput-magnetite-storage-audit.md:84`).

## Bearing on decisions

**D3, collection topology.**
The evidence points to per-host agent plus one gateway rather than either alone, for a reason specific to this fleet rather than a general preference.
A gateway alone cannot work because five of ten hosts are intermittent (F5) and a scrape-style pull would simply miss them, while the darwin four are not even push-reachable (F4).
Per-host agents alone would require every host to hold store credentials and to reach the store directly, which multiplies the credential surface by ten and puts the mTLS-termination problem (F28) on ten hosts instead of one.
What would reverse the two-tier reading is a measurement showing the agent tier's memory cost is unacceptable on the darwin laptops given F15's unenforceable ceiling; the reversal would then be a direct-export topology with bearer tokens and no gateway.
On ingress, the mesh-only option is nearly free because the idiom, the firewall pattern and a reusable build-time invariant all already exist (F17, F18, F19), whereas the public path's existing gateway is redirect-shaped and unusable by OTLP clients without new work (F21).
What would force public ingress is a machine that must emit while off the mesh, and F23 makes darwin mesh membership manual rather than guaranteed, so that case is live rather than hypothetical.
On authentication, bearer is available at the store today and mTLS is not (F26, F27), so mTLS is a choice to build and operate a CA, not a choice to turn on a flag.

**D1, store.**
F25 constrains the store leg of the topology: any collector talking to GreptimeDB for traces or logs must use the HTTP exporter, so a topology assuming OTLP gRPC end to end is wrong at the last hop.
This would reverse if a later GreptimeDB revision registers the standard OTLP gRPC trace and logs services.

**D4, signal scope and budget.**
F41 through F43 give the budget its shape: roughly 3,000 metric series and under 60,000 dev-loop events per day is small against F39's headroom, so the binding constraint is cardinality policy rather than bytes.
A single unbounded label in the dev-loop schema reverses that conclusion entirely.

**D7, packaging and placement.**
F8 is the decisive packaging fact: a first-party darwin module is unavoidable for every candidate, so the distribution choice should be made on NixOS-side and pipeline grounds and not on packaging cost.
F6 and F7 bear on the regulator: a collector on scheelite is ungated, and a darwin collector is only gated on a darwin builder.

**D8, access control.**
F28 places the mTLS boundary at nginx or at the gateway collector, which makes the gateway the natural place for any redaction of W9 prompt content, because it is the one hop every emitter traverses.
This reverses if the redaction must happen before the payload leaves the emitting host, in which case the per-host agent carries the processor and the gateway becomes optional.

## Flags

Charter W6 misidentifies a package.
`alloy` at the pinned nixpkgs is the AlloyTools relational modeling language, and 5.1.0 is its version (F33), not Grafana Alloy's.
Grafana Alloy is `grafana-alloy` at 1.17.1 (F34).
Any D3 or D7 text written against W6 as stated would specify a Java formal-methods tool as a telemetry agent.

The assignment's premise that "two hosts are intermittent" understates the fleet.
Six of ten machines are `laptop`-tagged and five are plausibly intermittent (F5).

GreptimeDB's OTLP support is narrower than "OpenTelemetry-native" framing implies.
The HTTP surface is complete for all three signals (F24), but the gRPC surface carries only OTel-Arrow metrics (F25), and server-side mTLS client verification is an unimplemented TODO in source (F27).
Prefer the source reading over any upstream page claiming OTLP gRPC ingest.

The storage audit's check accounting is incomplete on one axis.
It enumerates five NixOS toplevels and six home activations for `x86_64-linux`, but darwin system closures are also check-bound (F7); the 117 figure is the `x86_64-linux` attribute set, not the whole check surface.
This does not change F42, which only needs the count nixbot actually evaluates.

Absence reported explicitly: no `opentelemetry-collector`, `vector` or `alloy` service module exists in nix-darwin at the pinned revision, and no OTLP-shaped port is open anywhere in the current firewall configuration.

## Questions

Vector's OTLP source coverage across traces, metrics and logs at 0.57.0 was not verified from source, because no vector checkout is present locally and the nixpkgs derivation does not enumerate sources; this is the single criterion that could eliminate vector outright and it should be settled before D3 is written.

Journald and log volume on the five always-on hosts is unmeasured, and the storage audit's own boundary forbade host contact, so the log leg of the D4 budget rests on no measurement at all.

Three of the four darwin machines are described as other people's primary laptops, for `raquel`, `janettesmith` and `christophersmith` (`vanixiets@da74672e5:modules/clan/inventory/machines.nix:96,118,129`).
Whether those machines are in scope as telemetry subjects at all is a consent question under W9 and is not inferable from the inventory.

Whether the gateway collector may be co-resident on magnetite, given W2 and F40's history of a dataset consuming the pool, or must sit on cinnabar, needs the store placement decision from D1 before D3 can answer it.

## Refresh (2026-10-15)

Sources for this section: `vanixiets@109c67346`; the root nixpkgs input is now the `flake.lock` node `nixpkgs_10`, a tarball at rev `ac1faec44836` (`nixos-26.11pre1086968.ac1faec44836`), cited as `nixos/nixpkgs@ac1faec44836`; nixpkgs `master` at `8d71b6f9b2c0` was compared and differs from the pin in none of the facts below; `nix-darwin/nix-darwin@4cff07de`, which is still the upstream `master` head and the pinned revision; `GreptimeTeam/greptimedb@4859e57e0` (main), `@16e9abe4a` (v1.1.4) and `@179ff8e50` (v1.2.1); `vectordotdev/vector@a3231c76b` (v0.59.0); `open-telemetry/opentelemetry-collector-contrib@aaf5045a2` and `open-telemetry/opentelemetry-collector@41da2fbd7` (both v0.155.0); `grafana/alloy@76a2e2af7` (v1.17.1).

### What changed

R1.
The root nixpkgs pin moved from `85f62611f` (node `nixpkgs_9`) to `ac1faec44836` (node `nixpkgs_10`), so every `nixos/nixpkgs@85f62611f` citation above is one pin behind.

R2.
At the current pin, `opentelemetry-collector` and `opentelemetry-collector-contrib` are 0.155.0 (`nixos/nixpkgs@ac1faec44836:pkgs/tools/misc/opentelemetry-collector/releases.nix:18`), `grafana-alloy` is 1.17.1 (`nixos/nixpkgs@ac1faec44836:pkgs/by-name/gr/grafana-alloy/package.nix:23`), and `vector` is 0.59.0 (`nixos/nixpkgs@ac1faec44836:pkgs/by-name/ve/vector/package.nix:31`).

R3.
nixpkgs lags upstream for two of the three candidates.
Upstream collector-contrib is at v0.163.0, published 2026-10-14, while 0.155.0 was published 2026-06-24 (https://github.com/open-telemetry/opentelemetry-collector-contrib/releases, fetched 2026-10-15).
Upstream Alloy is at v1.20.1, published 2026-09-28 (`grafana/alloy@95e12cf89`; https://github.com/grafana/alloy/releases, fetched 2026-10-15).
Upstream vector's latest release is v0.59.0, published 2026-10-06, which nixpkgs already carries (https://github.com/vectordotdev/vector/releases, fetched 2026-10-15).
The only open nixpkgs pull request touching the collector set is the builder bump to 0.156.0, opened 2026-07-07 (https://github.com/NixOS/nixpkgs/pull/539210, fetched 2026-10-15), and no open pull request bumps `grafana-alloy`.

R4.
All three candidates evaluate on `aarch64-darwin` at the pin with `meta.broken = false` and the system inside `meta.platforms`, and the `aarch64-darwin` outputs of `otelcol-contrib-0.155.0`, `vector-0.59.0` and `grafana-alloy-1.17.1` are all present on `cache.nixos.org` (narinfo HTTP 200 on 2026-10-15), so all three have been built for `aarch64-darwin` by Hydra.
The same holds for their `x86_64-linux` outputs.

R5.
nix-darwin `master` has not moved since `4cff07de` (2026-08-16); `modules/services/monitoring/` still contains only `netdata.nix`, `prometheus-node-exporter.nix` and `telegraf.nix`, and no nix-darwin pull request, open or closed, has `alloy`, `opentelemetry` or `vector` in its title (GitHub search, fetched 2026-10-15).

R6.
The darwin service recipe is therefore still first-party `launchd.daemons`, and the repository now has a second, closer precedent for it.
The `nix-builders` clan service runs `nix-grpc-daemon` on the darwin builders as a launchd daemon that binds the ZeroTier address, wraps `ProgramArguments` behind `/bin/wait4path /nix/store` because launchd can start a daemon before the store volume is mounted and never retry, and lets `KeepAlive` retry until the ZeroTier address exists after boot (`vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:10-16,348-383`).
That service also proves that a clan service can carry a `darwinModule` to stibnite, rosegold and argentum (`vanixiets@109c67346:modules/clan/inventory/services/nix-builders.nix:69-89`), so a collector does not need a bespoke darwin wiring path.

R7.
The NixOS collector module gained build-time config validation between the two pins: configs generated from `settings` are now run through `otelcol validate` by default (`nixos/nixpkgs@d8561c243b2f`), and `validateConfigOverrides` passes `--set` overrides so that configs using `${file:...}` or `${env:...}` confmap providers still validate, with the bearer-token extension as the documented example (`nixos/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/opentelemetry-collector.nix:31-36,69-83`).
That is a free deterministic regulator for collector configuration on NixOS hosts, which neither the vector nor the alloy module provides in the same form; vector has a `validateConfig` option (`nixos/nixpkgs@ac1faec44836:nixos/modules/services/logging/vector.nix:33`) and alloy has none.

R8.
Secret delivery differs by module.
`services.alloy.environmentFile` exists (`nixos/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/alloy.nix:51`), whereas the collector and vector modules expose no environment-file option, so a store credential reaches the collector through a `${file:...}` provider or a systemd override.

R9.
Component type names in the collector were renamed to snake_case with deprecated aliases: the HTTP exporter is now `otlp_http` with `otlphttp` kept as an alias since v0.144.0 (`open-telemetry/opentelemetry-collector@41da2fbd7:CHANGELOG.md:456,467`), and the nixpkgs `otelcol-contrib` 0.155.0 binary lists `otlp_http`, `otlp_grpc` and `host_metrics` while logging `"hostmetrics" alias is deprecated; use "host_metrics" instead` when the old name is used (observed by running `otelcol-contrib components` and a `host_metrics` pipeline on 2026-10-15).
Extension names were not renamed in 0.155.0: the binary lists `basicauth`, `bearertokenauth`, `headers_setter` and `file_storage`.

R10.
Host metrics work on darwin from the nixpkgs contrib build.
On stibnite, a `host_metrics` pipeline with the cpu, memory, load, filesystem, network and disk scrapers produced 17 metrics and 392 data points per scrape, at a peak resident set of 170 MB and a peak memory footprint of 88 MB over a 20-second run (measured 2026-10-15, one run, `/usr/bin/time -l`).

R11.
On NixOS, journald collection is supported by all three candidates through the `systemd-journal` supplementary group: the collector module adds it unconditionally (`nixos/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/opentelemetry-collector.nix:122-125`), alloy adds it unconditionally (`nixos/nixpkgs@ac1faec44836:nixos/modules/services/monitoring/alloy.nix:86-89`), and vector adds it behind `journaldAccess` (`nixos/nixpkgs@ac1faec44836:nixos/modules/services/logging/vector.nix:16,84`).
The collector's `journald` receiver shells out to `journalctl`, resolved from `PATH` by default (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/input/journald/config_all.go:23`, `:pkg/stanza/operator/input/journald/config_linux.go:204`), and NixOS puts `systemd` on every unit's default `PATH` (`nixos/nixpkgs@ac1faec44836:nixos/lib/systemd-lib.nix:700-707`), so no override is needed.
The receiver defaults to `start_at: end` (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/input/journald/config_all.go:21`), so journal history before the first start is not shipped unless configured.
Alloy's journald path is the Loki-shaped `loki.source.journal` component (`grafana/alloy@76a2e2af7:internal/component/loki/source/journal`), and the collector also ships a `syslog` receiver.

R12.
On darwin, the collector's `journald` receiver refuses to start (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:pkg/stanza/operator/input/journald/config_nonlinux.go:17`), and the only darwin-native log source among the three candidate builds is the collector's `macos_unified_logging` receiver, which is at alpha stability in the nixpkgs 0.155.0 build (observed via `otelcol-contrib components`).
`vector list` on the nixpkgs 0.59.0 build shows no macOS unified-logging source.

R13.
The open question about vector's OTLP coverage is settled.
Vector's `opentelemetry` source registers the standard OTLP gRPC logs, metrics and trace services (`vectordotdev/vector@a3231c76b:src/sources/opentelemetry/config.rs:45-47,342-360`) and serves `/v1/<signal>` over HTTP (`vectordotdev/vector@a3231c76b:src/sources/opentelemetry/http.rs:226-227`).
Its `opentelemetry` sink has only an HTTP protocol variant (`vectordotdev/vector@a3231c76b:src/sinks/opentelemetry/mod.rs:28-30`).
Vector also ships native `greptimedb_logs` and `greptimedb_metrics` sinks, the former writing HTTP to `/v1/events/logs` (`vectordotdev/vector@a3231c76b:src/sinks/greptimedb/logs/http_request_builder.rs:135`) and the latter writing GreptimeDB's own gRPC insert API (`vectordotdev/vector@a3231c76b:src/sinks/greptimedb/metrics/mod.rs:1`), and has no GreptimeDB trace sink.
Both native sinks are in the nixpkgs build, which uses vector's default feature set (`vectordotdev/vector@a3231c76b:Cargo.toml:578,603`), as `vector list` on that build confirms.

R14.
GreptimeDB's OTLP surface is unchanged in shape on main: HTTP routes `/v1/metrics`, `/v1/traces` and `/v1/logs` nested under `/v1/otlp` (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http.rs:773-774,1536-1538`), and the gRPC server registers only the OTel-Arrow metrics service (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/grpc/builder.rs:94,193`).
No standard OTLP gRPC trace or logs service exists in `src/` at v1.1.4, v1.2.1 or main.
The exporter is therefore the collector's `otlp_http` with `endpoint` set to the store's HTTP port plus `/v1/otlp`, to which the exporter appends `/v1/<signal>`.
Routing headers are optional: `x-greptime-db-name` selects the database, `x-greptime-log-table-name` and `x-greptime-trace-table-name` override the default tables `opentelemetry_logs` and `opentelemetry_traces`, and `x-greptime-pipeline-name` selects an ingest pipeline (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http/header.rs:45,56,59,61`; `:src/servers/src/http/otlp.rs:161,227`; `:src/common/catalog/src/consts.rs:223`).

R15.
The nixpkgs `greptimedb` attribute is now in the root pin at 1.1.4 (`nixos/nixpkgs@ac1faec44836:pkgs/by-name/gr/greptimedb/package.nix:15`), against an upstream latest stable of v1.2.1 (2026-09-16) and a v1.3.0-beta.2 pre-release.

R16.
buildbot is disabled, not deleted: its module is gated behind `vanixiets.buildbot.enable`, which keeps generated vars, its PostgreSQL database and its CNAME while off (`vanixiets@109c67346:modules/nixos/buildbot.nix:17-20,36-38`).
nixbot and gitea-mq are now magnetite services (`vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:37-38,51-52`).
nixbot binds no TCP port and serves only a UNIX socket behind nginx (`vanixiets@109c67346:modules/nixos/nixbot.nix:18-20`), and its `/metrics` route is unauthenticated (`Mic92/nixbot@3c432d593:nixbot/nixbot/web/metrics.py:177`).
gitea-mq listens on loopback 8092 behind a public nginx vhost (`vanixiets@109c67346:modules/nixos/gitea-mq.nix:44-45,110`) and exposes neither Prometheus metrics nor OpenTelemetry instrumentation (`Mic92/gitea-mq@9bad60d8f:.golangci.yml:14`), so its only signal is its journal on magnetite.

R17.
nixbot now builds `checks.aarch64-darwin` through the darwin builders on a best-effort basis, with `ignoreFailure` on every darwin check (`vanixiets@109c67346:modules/clan/inventory/services/nix-builders.nix:5-8`; `vanixiets@109c67346:modules/checks/nixbot-best-effort-darwin.nix`).

R18.
The ZeroTier network now admits two Android members, pixel7 and pixel11, as external static entries alongside the four darwin machines (`vanixiets@109c67346:modules/clan/inventory/services/zerotier.nix:16-23`), so being on `zt+` no longer implies being a fleet machine under configuration management.

R19.
`.zt` names now resolve on both platforms: darwin through `/etc/resolver/zt` and NixOS through a `~zt` routing domain, both pointing at cinnabar (`vanixiets@109c67346:modules/system/zt-dns.nix:11-27`), and magnetite itself resolves `.zt` names through cinnabar since `vanixiets@d2ce1b390`.
An agent can therefore address a gateway as `magnetite.zt` on every fleet machine, at the cost of a dependency on cinnabar's dnsmasq.

R20.
A fleet mTLS CA now exists: the `nix-builders` service issues every member a certificate from the shared `nix-grpc-ca` clan var, with the machine name as CN and both serverAuth and clientAuth usages (`vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:18-22`).

R21.
magnetite's memory pressure has been confirmed by incident: an overlap of nixbot's evaluation with a remote evaluation OOM-killed the host twice, on 2026-09-27 and 2026-10-01, which led to a host-wide evaluation lock and memory-pressure guards (`vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:459-465`), and nixbot's evaluator peaks at 31.4 GiB of swap (`vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:444-447`).

### Corrections

C1 supersedes F26 and the D3 sentence "bearer is available at the store today".
No released GreptimeDB accepts bearer tokens.
At v1.1.4, the version nixpkgs packages, HTTP authorization parses only the `basic` scheme (`GreptimeTeam/greptimedb@16e9abe4a:src/servers/src/http/authorize.rs:237-238`), and v1.2.1 contains no bearer code either.
The bearer branch exists only from v1.3.0-alpha.1 onward (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http/authorize.rs:83-87`), and even there it calls `UserProvider::authenticate_bearer_token`, whose default implementation fails with an unsupported-method error (`GreptimeTeam/greptimedb@4859e57e0:src/auth/src/user_provider.rs:90-95`) and which neither in-tree provider, `static_user_provider` nor `watch_file_user_provider`, overrides.
The F26 reading was taken from a test that mocks a `Bearer` header (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http/authorize.rs:796`), not from a working provider.
The usable store credential for collectors is HTTP Basic, sent through the collector's `basicauth` extension or a static `Authorization` header.

C2 supersedes F36 and charter W6's vector version.
vector at the root pin is 0.59.0, not 0.57.0 (R2).

C3 supersedes F17's use of buildbot as the live precedent for a `zt+` port.
Port 9989 is opened only when `vanixiets.buildbot.enable` is set, which it is not (R16); the live `zt+` precedents are cognee 9270 (`vanixiets@109c67346:modules/nixos/cognee.nix:258`), omnigraph 8090 (`vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:493-494`) and nix-grpc-daemon 50051 (`vanixiets@109c67346:modules/clan/services/nix-builders/flake-module.nix:345`).
F19's sysctl now sits at `vanixiets@109c67346:modules/machines/nixos/magnetite/default.nix:471`.

C4 supersedes the D3 sentence "mTLS is a choice to build and operate a CA, not a choice to turn on a flag".
The fleet already operates a clan-vars CA with per-machine clientAuth certificates on every darwin builder and every NixOS member of `nix-builders` (R20), so the CA cost is paid; what remains is the choice whether to reuse that CA or mint a second one.

C5 supersedes F7's implication that darwin collector configuration is gated only by an `aarch64-darwin` builder someone runs by hand.
nixbot now evaluates and builds darwin checks, but each carries `ignoreFailure` (R17), so a broken darwin collector module produces a notice rather than a failed check.

C6 supersedes F23's count of four static ZeroTier members.
There are six, two of them Android phones (R18).

C7 extends F30, which named only the persistent queue as a reason to override the core default package.
The `journald` receiver and the `basicauth` and `file_storage` extensions are contrib-only, so the store credential (C1) and the NixOS log leg (R11) also require `services.opentelemetry-collector.package = pkgs.opentelemetry-collector-contrib`; `host_metrics` alone is in both distributions (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/hostmetricsreceiver/README.md`).

C8 supersedes the first Questions entry above, which said vector's OTLP coverage could eliminate it outright.
Vector ingests OTLP for all three signals (R13), so it is not eliminated on that criterion; it remains weaker than the collector for traces into GreptimeDB because its only trace egress is the generic HTTP `opentelemetry` sink.

### Reconciliation with W6 and the original topology reading

W6 holds for `opentelemetry-collector-contrib` 0.155.0 and `grafana-alloy` 1.17.1 and is wrong for vector, which is 0.59.0 at the current pin (C2); W6 should also name the root node as `nixpkgs_10` at `ac1faec44836` (R1).
The two-tier reading in D3 is strengthened rather than reversed.
Because the store accepts only Basic credentials and does not authorize per user (charter RK9), direct export would place a store password on every host, including laptops belonging to other people, whereas a gateway holds one credential.
Because mesh membership now includes unmanaged Android devices (R18), a `zt+`-only gateway port still needs client authentication, and the existing fleet CA makes mTLS from agent to gateway available at low cost (C4).
The agent tier's darwin memory cost is now measured at roughly 90 MB footprint for host metrics alone (R10), which is the measurement D3 named as the possible reversal and does not by itself look disqualifying.
Gateway placement on magnetite is now riskier than when F39 was written, since the host has had two OOM kills from evaluation overlap (R21); the gateway's own memory ceiling would have to be enforced by a `memory_limiter` processor and a systemd `MemoryMax`, and its failure mode under OOM is loss of the in-memory queue unless `file_storage` backs it.
With buildbot disabled, magnetite runs one less evaluator, but nixbot carries the same evaluation load.

### Questions

Should the store leg use HTTP Basic over mesh TLS against GreptimeDB 1.1.4 or 1.2.1, or should the design wait for a release containing the bearer path, which still needs a user provider no open build ships?

Should agent-to-gateway mTLS reuse the `nix-grpc-ca` clan var, which would make every builder certificate also a telemetry credential, or use a separate CA?

Is the nixpkgs collector lag of eight minor versions acceptable, or should the fleet carry an override to a newer release, given that the pinned `opentelemetry-collector-builder` is also 0.155.0 and so does not by itself close the gap?

Is macOS log collection in scope, given that the only candidate source is an alpha-stability receiver (R12)?

Are the Android ZeroTier members telemetry subjects, or only devices the gateway must refuse?

Is a darwin collector acceptable when its check failures are non-gating (C5), or does D7 require a gating darwin builder?

Can the gateway sit on magnetite given R21, or must it move to cinnabar, which would make cinnabar's availability a precondition for both name resolution (R19) and telemetry ingress?
