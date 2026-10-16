# Brainstorm: stand up GreptimeDB on magnetite (S1, CAM-68)

## Background

Slice S1 of the fleet observability implementation (`docs/notes/development/observability/architecture/reference-architecture.md`, "Implementation sequencing").
Accepted design inputs: ADR-001, ADR-003, ADR-004, ADR-006, ADR-007, ADR-008 and ADR-009 under `docs/notes/development/observability/decisions/`, and the `greptimedb`, `otel-collector` and `host-probes` components.
The brainstorm classified the change as architectural: it introduces a new subsystem whose interfaces S2 to S8 consume.

Inputs gathered for this brainstorm:

- A read of the design corpus against S1, which found eight places where the corpus contradicts itself or is silent (C1 to C8 below).
- A read of the repository patterns S1 reuses: the `golem-binary` shape for upstream binaries, the cognee memory envelope, the omnigraph hardening, the `omnigraph-r2` generator, the `zfs-set-*` oneshots, the `nix-builders` clan service shape, the `nixbot-wiring` and `omnigent-environment` check patterns, and the `vmTests` lane.
- Prior art from four public flakes that run GreptimeDB (survey: `logs/greptimedb-nix-flake-usage-survey-20261016.md`): `quentinmit/isz`, `KiruyaMomochi/nix`, `MathisWellmann/nixos-config` and `ambiso/sensor_monitor`.
- The GreptimeDB v1.2.1 `config/standalone.example.toml`, read at the release tag.

## Channel state at brainstorm time (2026-10-16)

- `nixpkgs-unstable` (`319e4ceb`) and `nixos-unstable` (`55bfb4d7`) both carry `greptimedb` 1.1.4; 1.2.1 is on nixpkgs master only.
- The root pin (`ac1faec4`) carries 1.1.4.
- The pending root-pin update (#3434) is held on Hydra's `atuin.aarch64-darwin`, independently of GreptimeDB.

The root-pin route to 1.2.1 is therefore unavailable, the channel-delay case ADR-001 Q1 and ADR-007 Q2 accepted `greptimedb-bin` for.
Q8 later found a reason that outlasts the delay: the nixpkgs build omits the embedded dashboard.

## Decision chain

### Q1. How is GreptimeDB 1.2.1 packaged? (C1)

Decision: `pkgs/by-name/greptimedb-bin`, an upstream-binary package in the house shape (`golem-binary`): a per-system `fetchurl` of `greptime-linux-amd64-v1.2.1.tar.gz` (sha256 `062d5beb13de4991c4fec201b2e5071518bf4ca8f0d52947eba757a74c2a5420`), `autoPatchelfHook` with `stdenv.cc.cc.lib`, `versionCheckHook`, `sourceProvenance = [ binaryNativeCode ]`, an `update.sh` and an `apps.update-greptimedb-bin` entry.

- Prior art confirms the shape: `KiruyaMomochi/nix` ships the same tarball with `autoPatchelfHook` and `cc.cc.lib` only; `quentinmit/isz` and Kiruya's source builds both need nightly Rust, a patched-in git dependency and hand-fed dashboard assets, so nixpkgs will keep lagging releases.
- The upstream tarball is built with the `servers/dashboard` feature and embeds the web dashboard; the nixpkgs build omits it.
  Since Q8 makes that dashboard the fleet's dashboard layer, `greptimedb-bin` is the intended package, not a channel-delay stopgap, and its `update.sh` tracks stable upstream releases.
- R1.1 as accepted requires `pkgs.greptimedb` and forbids a first-party derivation.
  It is amended in place (charter v11): the store package must be a stable release (semver, no prerelease) and must serve the embedded dashboard, and `pkgs.greptimedb` is acceptable only if it carries the dashboard.
  The cutover assertion first drafted here, which failed evaluation once `pkgs.greptimedb` at the pin reached the deployed version, is replaced, because it would have moved the store to a build without the dashboard.
- The amended R1.1 is checked twice: at evaluation, an assertion on `passthru.embedsDashboard = true` on the package, with a mutant package lacking the attribute; at runtime, a container-test case that `GET /dashboard/` on `127.0.0.1:4000` returns 200.
- S1 exposes nothing new: the dashboard is served on the loopback HTTP listener and reached from a workstation over `ssh -L 4000:127.0.0.1:4000 magnetite.zt` from the first deployment.

### Q2. Shape of magnetite's collector (C7, C3)

Options: O1, both ADR-003 roles on magnetite in one collector process with the failure notifier moved into S1; O2, both roles with the notifier left in S3; O3, ingress only, with magnetite's receivers inside it.

Decision: O1, chosen by the human.

- The NixOS module allows one collector per host, so the `agent` and `ingress` role fragments merge into one configuration, and the agent pipelines reach the ingress pipelines through a `forward` connector inside the process rather than over the network.
- S4 then only adds `otel-ca`, the mTLS ZeroTier receiver on the ingress fragment and the agent role on other hosts; nothing S1 deploys is restructured.
- The `observability-notify@` template, which ADR-003 places in the `agent` role, arrives with S1, so S1's own units carry `OnFailure=` from their first deployment and R7.2 needs no alerting component, as ADR-007 assumes.
- Cost: S1 grows by the notifier and its ntfy access, and the reference architecture's sequencing moves the notifier from S3 to S1 (charter v11).

### Q3. Which regulators does S1 own? (C4, C5, D3, D7)

Decision: every regulator whose subject S1 deploys.

- Evaluation-time: R1.1 (amended), R1.2, R1.4, R6.4's storage clause, R7.1 with its seven mutants, R3.1 for magnetite's collector configuration, and R8.2 for credential ownership and the loopback bind.
- `greptimedb-envelope`, hourly: R6.2, R6.3, R6.4's readiness probe, R7.2, R7.3 and R7.4.
- Deferred to S8: R6.1 and R6.4's export-location clause, because the export does not exist before S8 and R6.1 fails on an empty partition.

### Q4. Logs table (C6)

Decision: S1 creates no logs table; S1 to S5 carry no logs pipeline, and the 14-day logs retention is set by S7 when it creates the table.

### Q5. Scrape targets (D5, D6)

Decision: ADR-003's magnetite set, plus GreptimeDB itself.

- gitea at `127.0.0.1:3002`, niks3 at `127.0.0.1:5752`.
- nixbot through a new loopback nginx server on `127.0.0.1:9180` proxying `/metrics` to `/run/nixbot/web.sock`, as ADR-003 decides; nixbot listens only on that socket.
- nginx `stub_status`, zerotierone metrics, node_exporter on `127.0.0.1:9100`.
- GreptimeDB's own `/metrics` on `127.0.0.1:4000`, which `quentinmit/isz` scrapes.

### Q6. R2 endpoint (D9)

Decision: reuse the account endpoint the `omnigraph-r2` generator already uses (`modules/machines/nixos/magnetite/default.nix:402`); no new variable.

### Q7. How is S1 tested at runtime? (D8)

The human required that KVM-dependent NixOS tests dispatch to pyrite, the fleet's only bare-metal Linux host, and asked which modern NixOS testing approaches are useful here.

Approaches available at the root pin (`nixos/lib/testing/`):

- `pkgs.testers.runNixOSTest` with QEMU `nodes`, which need `kvm` and `nixos-test` and therefore route only to pyrite; `qemu.forceAccel` fails rather than falling back to emulation.
- systemd-nspawn `containers` (`driver-configuration.nix:68-71`), which need `uid-range` and `nixos-test` but no KVM; magnetite advertises both (`modules/clan/inventory/services/nix-builders.nix:38-41`) with `auto-allocate-uids` enabled.
- `sshBackdoor.enable` with `.driverInteractive` for debugging.

Decision, selecting by what each claim actually needs:

- Evaluation-time regulators cover the envelope, listeners, users file, telemetry, storage stanza and collector configuration.
- A container test, built on magnetite, covers the service pipeline: readiness, the schema oneshot's TTL, the auth matrix, OTLP ingest through the routing connector, a PromQL read back, and the systemd receiver reaching D-Bus under `DynamicUser`.
- A QEMU VM test on pyrite covers only the OOM kill order (evaluator 900, store 500, collector 300), because it needs a kernel of its own; in a container the OOM killer is the host's.
- ZFS quota and reservation enforcement, the zram paging series, R7.2's deliberate failure and R2 itself are confirmed on magnetite at deployment and recorded in `verify.md`.
- Both runtime tests live in the on-demand `vmTests` lane, not in `checks`; the human accepted this, because nixbot evaluates every check attribute on every pull request and a flaky container test would block the queue.

### Q8. Dashboard layer

The human directed that the fleet use GreptimeDB's built-in dashboard, keeping as much of its configuration as possible in Perses form, and fall back to a standalone Perses server only to reuse the Grafana dashboard library.

Evidence, read at the v1.2.1 tag and in the dashboard repository:

- GreptimeDB v1.2.1 embeds dashboard v0.13.13 (`src/servers/dashboard/VERSION`), which runs Perses 0.53.1 with prometheus-plugin 0.57.1 and `@perses-dev/greptimedb-plugin`; Perses 0.54.0 arrives with dashboard v0.14.2 on GreptimeDB main.
- `/v1/dashboards` (`GET`, `POST /{name}`, `DELETE /{name}`) exists in v1.2.1 (`src/servers/src/http.rs:829-836,1437-1444`; `src/frontend/src/instance/dashboard.rs`), storing each definition verbatim in `greptime_private.dashboard` keyed by name.
  ADR-002:29, :99, :185 and research R39 say it first appears in v1.3.0-alpha.1; that premise is wrong.
- The UI is served at `/dashboard/` on port 4000, and on 4006 when `http.enable_api_server = true`, which serves only `/v1` and `/dashboard`.
  Its datasources are fixed: PromQL at `/v1/prometheus` and SQL at `/v1/sql`.
  It has no base-path option, so a public route needs a vhost of its own.
- It has no Grafana import; the path is `percli migrate --online` against an upstream Perses server.
  It has no StaticListVariable.
  Its panels are TimeSeries, Gauge, Stat, Table, Histogram, HeatMap, Markdown, Scatter, Bar, Pie, LogsTable, TraceTable, TracingGantt and TimeSeriesTable.
- Saving and deleting a dashboard are write actions, rejected for `:ro` users (`auth/src/permission.rs:150-152`), so `perses:ro` can view but not save.
- The upstream release tarball is built with the `servers/dashboard` feature; the nixpkgs build omits it.

Decision: the dashboard layer is GreptimeDB's embedded Perses dashboard, and no standalone Perses server is deployed.
Standalone Perses remains tooling only: `percli migrate`, against an ephemeral local Perses server, converts Grafana community dashboards, and `percli lint` against the matching Perses schema version is a check.
A deployed standalone Perses server is the fallback only if a needed feature is missing, such as StaticListVariable or RBAC with projects.

Consequences for S1:

- `greptimedb-bin` is the intended package because it embeds the dashboard, and R1.1 is amended as Q1 records.
- The container test gains the `/dashboard/` case, and the evaluation-time R1.1 check gains the `passthru.embedsDashboard` mutant.
- `http.enable_api_server` stays off in S1; the dashboard is reached over `ssh -L 4000:127.0.0.1:4000 magnetite.zt`.

S6 carries the rest: a vhost behind the existing sso-gateway (`modules/nixos/sso-gateway.nix`) for the Kanidm group `perses_users`, with nginx proxying to the 4006 API listener and overwriting `Authorization` with the `perses:ro` credential; dashboards as Perses JSON files in the repository, reconciled through `/v1/dashboards` by a oneshot holding an `rw` credential; and a `percli lint` check.
Which unit holds that reconcile credential is an open question for S6.

## Prior-art findings adopted

- F1: `CREATE DATABASE IF NOT EXISTS ... WITH (ttl=...)` is a no-op on an existing database, so a changed TTL would never apply; the schema oneshot follows each create with `ALTER DATABASE ... SET 'ttl'=...`, and the envelope flags tables carrying their own TTL, which overrides the database's.
- F2: the static users file requires exactly one `=` per line and silently skips malformed lines; passwords are hex, and a regulator asserts exactly four valid lines.
- F3: a query that returns no rows must fail its regulator, never pass; `MathisWellmann/nixos-config`'s `GreptimeDBDown` alert queries a job that does not exist and can never fire. Every envelope query treats an empty result or a missing table as failure, with a mutant that renames the queried table.
- F4 (superseded by P3 below): the nixpkgs collector module validates its configuration at build time, before `/run/credentials` exists; `validateConfigOverrides` (present at the pin) substitutes placeholder `basicauth` credentials, as `KiruyaMomochi/nix` does.
- F5: v1.2.1 has no `[grpc] enable`, only `bind_addr`; gRPC binds `127.0.0.1:4001` and an assertion checks it. ADR-007's "gRPC disabled" is amended in charter v11.
- F6: `logging.dir = ""` keeps logs in the journal only; `storage.data_home` is set to the dataset mount, because the WAL and caches stay local with object storage; `[runtime] global_rt_size` and `compact_rt_size` are set explicitly with a lower `CPUWeight`, because unbounded worker pools starved GreptimeDB's own health handler on a 192-core node in `MathisWellmann/nixos-config`.
- F7: the store has no readiness notification; the schema oneshot and the tests poll `GET /health` before sending SQL.
- F9: PromQL reads select the database with the `x-greptime-db-name` header; S1's end-to-end query uses it, and S3 and S6 inherit it.
- F11: `user_provider` is a valid top-level TOML key in standalone mode (`src/cmd/src/standalone.rs:354,472`); it stays in the TOML, and the container test's negative-auth case proves enforcement.

## Amendments carried by this change (charter v11)

- ADR-002: the dashboard layer is GreptimeDB's embedded Perses dashboard, with its wrong v1.3.0-alpha.1 premise corrected; standalone Perses is kept as tooling and as the fallback (Q8).
- R1.1 and the "no `pkgs/by-name` entry" lines of ADR-001, ADR-007 and the `greptimedb` component: the store package must be a stable release and must serve the embedded dashboard, which makes `greptimedb-bin` the intended package; `pkgs.greptimedb` is acceptable only if it carries the dashboard.
- ADR-007: gRPC bound to loopback rather than disabled.
- Reference architecture sequencing: the `observability-notify@` template moves from S3 to S1.

## Resolved after the decision chain

- ntfy on cinnabar has no authentication (`modules/machines/nixos/cinnabar/ntfy.nix`); access is ZeroTier membership through `ntfy.zt`, so the S1 notifier holds no credential. ADR-009's `alerter` user arrives with S3, and if S3 turns on access control it must give the notifier a credential in the same change.
- `ntfy-send` is packaged only inside a home-manager module (`modules/home/tools/commands/system/ntfy-send.nix`). It moves to `pkgs/by-name/ntfy-send`, consumed by both the home-manager command and the notifier, so there is one sender rather than a second curl wrapper.
- magnetite has 16 vCPUs. `[runtime]` thread counts and `CPUWeight` are set in design against that count and the cognee precedent.

## Decisions during planning

Writing `plan.md` against the pinned sources corrected the decisions below; they are labelled P1 to P13 to keep them apart from the corpus findings C1 to C8 above.
Charter v12 records the ones that amend a decision record.

- P1, R7.4: credential freshness compares hashes, not times.
  sops-nix rewrites every secret, with a new mtime, on each activation, while `restartUnits` restarts only on a changed value, so "store start later than users-file mtime" fails after any deployment (plan Task 4).
  `greptimedb-users` gains a public file `users-sha256` (`secret = false`; a sha256 of 256-bit hex passwords leaks nothing usable), `greptimedb.service` writes the sha256 of `$CREDENTIALS_DIRECTORY/users` to `/run/greptimedb/loaded-users.sha256` (`0444`) in an `ExecStartPre`, and the envelope fails when the two differ or either file is missing.
- P2, auth matrix: GreptimeDB v1.2.1 answers missing or wrong credentials with 401 and a permission-mode violation with 403 (`src/servers/src/error.rs:959-966`; upstream's `tests-integration/tests/http.rs:241-305` asserts a `wo` read is `FORBIDDEN`).
  The matrix is: no credential 401, wrong password 401, `collector:wo` read 403, `collector:wo` write 200, `perses:ro` read 200, `perses:ro` write 403, `regulator:ro` read 200, `admin` read and write 200.
- P3, collector credentials: `basicauth` reads the password through `client_auth.password_file`, whose `Validate` does not open the file (`extension/basicauthextension/config.go:36,50-60` at contrib v0.155.0), so build-time validation needs no placeholder.
  The one `validateConfigOverrides` entry removes the `authorization` of the `prometheus/zerotier` receiver's scrape job, because the prometheus receiver's `Validate` stats `credentials_file` (`receiver/prometheusreceiver/config.go:211-231`); R3.1 asserts the override touches nothing else.
  This supersedes F4.
- P4, zerotierone: the `local.conf` key is `enableMetrics` (`ZeroTierOne@899352e3 service/OneService.cpp:3292`), not `allowMetrics`; the `agent` role sets `services.zerotierone.localConf.settings.enableMetrics = true`.
- P5, process-name bound: no collector stage at contrib 0.155.0 caps the number of distinct process names.
  S1 asserts the 64 MiB filter and `process.maxNames = 30` in `schema.nix` at evaluation, and records the observed distinct-name count at deployment (plan Task 6, tasks 8.5); the runtime regulator arrives with S4's `otel-envelope` (ADR-004 R4.2).
- P6, owner aliases: S1's systemd allow-list includes `omnigent-host-*.service`, so ADR-003 item 17's owner-to-alias transform lands in S1 with `flake.lib.otelCollectorSchema.ownerAliases = { cameron = "owner-1"; janettesmith = "owner-2"; }`, the two owners magnetite runs today.
  R3.1 asserts every evaluated `omnigent-host-<owner>` unit has an alias, with a missing-owner mutant, and the container test asserts the stored `systemd_unit_name` is the alias and that no stored value contains the owner.
- P7, module seams: `schema.nix` is a flake-parts module defining `flake.lib.otelCollectorSchema`, because import-tree imports every `.nix` file under `modules/`; the plain NixOS modules `flake.modules.nixos.otel-collector-agent` and `flake.modules.nixos.otel-collector-ingress` back the clan roles; `services.observability-notify.units`, unit names without `.service`, is the notifier seam, so `greptimedb.nix` never references the notifier; and magnetite's `greptimedbDataset` binding is the single source of the dataset's name, mountpoint, quota and reservation, with a check that `disko.nix` declares the same values.
- P8, collector queues: `sizer: bytes`, 400 MiB for `fleet` and 48 MiB each for `devloop` and `agent`, in one `file_storage` directory (`exporter/exporterhelper/README.md`).
  R3.1 asserts the sum is below 512 MiB and that `fleet` holds at least 24 h at an explicit, unmeasured `fleetBytesPerMinute = 256000`; plan Task 6 measures the real rate.
- P9, store configuration: `event_recorder.event_types = [ ]`, and `prefilter_result_cache_size = "32MB"` pinned with the other caches, because its default is 1/32 of host memory up to 128 MB; R7.1 asserts it.
- P10, R7.2 across restarts: `memory.events` and `memory.peak` restart from zero with each invocation, so the envelope keeps its baseline keyed by `InvocationID`.
  A new invocation fails the run if the journal for `greptimedb.service` since the baseline holds `MESSAGE_ID=fe6faa94e7774663a0da52717891d8ef`, which systemd 261.3 logs as "The kernel OOM killer killed some processes in this unit." (`src/core/cgroup.c:3099-3102`), or if `NRestarts` rose; the envelope runs unprivileged with `SupplementaryGroups = systemd-journal`.
  R7.3 reads used space, quota and reservation.
- P11, `ntfy-send`: the package lives at `pkgs/by-name/ntfy-send`, and the home-manager module moves to `modules/home/tools/ntfy-send.nix`, following the convention in `modules/home/tools/repo-sync.nix:1-3` that modules installing a by-name package live in `modules/home/tools/`; S3 consumes this package and builds no `ntfy-send` of its own.
- P12, `greptimedb-bin` platforms: the package exists on `x86_64-linux` only and is `null` elsewhere, after the `radicle-desktop` precedent; `apps.<system>.update-greptimedb-bin` exists on every system and runs the update script directly, because updates are run from stibnite.
- P13, OOM-order test: only `greptimedb.service` is asserted to end with result `oom-kill`, because a unit whose only process is the victim may record `signal` instead (`src/core/service.c:4513-4545`); all three units are asserted to log systemd's OOM-kill message, and the kernel's victim lines must carry `,global_oom,` (Linux v6.18 `mm/oom_kill.c:447-457`), which a cgroup-limit OOM does not.
