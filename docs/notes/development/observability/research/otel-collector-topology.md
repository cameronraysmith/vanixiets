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
