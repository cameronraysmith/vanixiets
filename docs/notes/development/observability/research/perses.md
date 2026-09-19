---
title: Perses as dashboard layer — source evidence
status: research v1
date: 2026-09-18
sources:
  - perses/perses@21376aaf
  - perses/perses@2b65a98b
  - GreptimeTeam/greptimedb@20d87cff4
  - NixOS/nixpkgs@85f62611
  - https://perses.dev/plugins/docs/greptimedb/
  - https://github.com/perses/plugins/releases/tag/greptimedb/v0.2.0-beta.5
---

# Perses as dashboard layer — source evidence

## Findings

### Version frame

F1 The local checkout HEAD is `perses/perses@21376aaf` with `VERSION` reading `0.54.0` and tags `v0.55.0-beta.0` and `v0.55.0-beta.1` already cut, while nixpkgs packages 0.53.1 (charter W4), whose commit is `perses/perses@2b65a98b`.
F2 Minor releases are irregular rather than time-boxed: `v0.50.0` 2025-01-15, `v0.51.0` 2025-06-06, `v0.52.0` 2025-09-15, `v0.53.0` 2026-02-26, `v0.53.1` 2026-03-12, `v0.54.0` 2026-07-29 (`git log -1 --format=%ad` per tag).
F3 The packaged 0.53.1 is therefore one minor release and roughly six months behind upstream, and every finding below that depends on the difference is marked.

### Dashboard-as-code model

F4 A dashboard is a plain resource document with `kind`, `metadata`, `spec`, serialisable as JSON or YAML, defined at `perses/perses@21376aaf:pkg/model/api/v1/dashboard.go:26`.
F5 `metadata` carries `createdAt`, `updatedAt` and `version` without `omitempty` (`perses/perses@21376aaf:pkg/model/api/v1/metadata.go:39`), so an API round-trip embeds server-assigned fields in the file and a plain `percli get -o json` export is not a clean version-control artifact.
F6 Two dashboard-as-code SDKs exist in-tree, Go under `perses/perses@21376aaf:go-sdk/` and CUE under `perses/perses@21376aaf:cue/dac-utils/`, and `percli dac build` renders either into `built/` with one dashboard per source file (`perses/perses@21376aaf:docs/dac/getting-started.md:226`).
F7 `dac build` marshals the builder output directly (`perses/perses@21376aaf:go-sdk/exec.go:42`) with no server contact, so definitions are authored, diffed and reviewed without a UI round-trip.
F8 At HEAD the CUE SDK imports `github.com/perses/spec/cue/dashboard` (`perses/perses@21376aaf:cue/dac-utils/dashboard/dashboard.cue:22`), whereas 0.53.1 imports `github.com/perses/perses/cue/model/api/v1/dashboard` (`perses/perses@2b65a98b:cue/dac-utils/dashboard/dashboard.cue:22`); the Go model likewise moved to `github.com/perses/spec v0.3.0-beta.8` (`perses/perses@21376aaf:go.mod:36`), a dependency absent from `perses/perses@2b65a98b:go.mod`.
F9 The HEAD dashboard-as-code guide requires `percli` at least `v0.54.0` and `cue` at least `v0.15.0` (`perses/perses@21376aaf:docs/dac/getting-started.md:10`), so the published guide does not describe the packaged 0.53.1 CLI.
F10 Both CUE builders carry `@experiment(explicitopen)`, so the CUE toolchain must enable that experiment.

### Datasource plugins and GreptimeDB reachability

F11 Core plugins are not in this repository; they live in `perses/plugins` (`perses/perses@21376aaf:README.md:48`) and are loaded as archives from `plugin.archive_path`, extracted to `plugin.path`, with a generated `plugin-module.json` served at `/api/v1/plugins` (`perses/perses@21376aaf:docs/configuration/load-plugin.md`).
F12 The HEAD default set lists 33 plugins including `GreptimeDB` at `0.2.0-beta.4` (`perses/perses@21376aaf:scripts/plugin/plugin.yaml:15`), `Jaeger`, `OpenSearch`, `Splunk`, `AlertManager`, `LogExplorer` and `ClickHouse`.
F13 The 0.53.1 default set contains none of those six: it has `ClickHouse`, `Loki`, `Prometheus`, `Pyroscope`, `Tempo` and `VictoriaLogs` as its datasources (`perses/perses@2b65a98b:scripts/plugin/plugin.yaml`).
F14 nixpkgs vendors 24 plugin tarballs in `NixOS/nixpkgs@85f62611:pkgs/by-name/pe/perses/plugins.nix`, and GreptimeDB is absent from that list.
F15 That vendored archive is built as `pluginsArchive` (`NixOS/nixpkgs@85f62611:pkgs/by-name/pe/perses/package.nix:19`) but is never copied into the package outputs; it is reachable only through `passthru.pluginsArchive`, so a consumer must set `plugin.archive_path` to it explicitly.
F16 The shipped Prometheus datasource is configured either as `directUrl`, queried from the browser, or as `proxy` of kind `HTTPProxy` with a `url` plus an `allowedEndpoints` allow-list (`perses/perses@21376aaf:dev/data/8-datasource.json:12`).
F17 The endpoint set the Prometheus plugin needs is `/api/v1/labels` POST, `/api/v1/series` POST, `/api/v1/metadata` GET, `/api/v1/query` POST, `/api/v1/query_range` POST and `/api/v1/label/<name>/values` GET (`perses/perses@21376aaf:dev/data/8-datasource.json:17-40`).
F18 GreptimeDB mounts its Prometheus-compatible router under `/v1/prometheus/api/v1` (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:753`).
F19 That router registers `/query` and `/query_range` and `/labels` and `/series` with both POST and GET, `/metadata` and `/label/{label_name}/values` with GET (`GreptimeTeam/greptimedb@20d87cff4:src/servers/src/http.rs:1417-1433`).
F20 The two sets match on path and method for every endpoint the Prometheus plugin uses, so a `PrometheusDatasource` whose proxy `url` is `http://<host>:4000/v1/prometheus` reaches GreptimeDB's PromQL surface with no bespoke plugin; RK2 does not fire for metrics at the packaged 0.53.1.
F21 A native GreptimeDB plugin does exist upstream, and it is SQL-based rather than PromQL-based, issuing `POST /v1/sql` and providing separate time-series, log and trace query plugins (https://perses.dev/plugins/docs/greptimedb/, fetched 2026-09-18; release `greptimedb/v0.2.0-beta.5`, https://github.com/perses/plugins/releases/tag/greptimedb/v0.2.0-beta.5, fetched 2026-09-18).
F22 `perses/plugins` is absent locally, so the GreptimeDB plugin's own source was not read and F21 rests on upstream documentation only.
F23 A third route exists in principle: the server-side `SQLProxy` supports drivers `mysql`, `mariadb` and `postgres` (`perses/perses@2b65a98b:pkg/model/api/v1/datasource/sql/sql.go:26-29`), and GreptimeDB listens on MySQL wire 4002 and PostgreSQL wire 4003 (`GreptimeTeam/greptimedb@20d87cff4:src/cmd/src/standalone.rs:1259-1260`), but which datasource plugin declares `SQLProxy` cannot be determined from this checkout.

### Provisioning, GitOps, read-only

F24 Provisioning loads resources from configured folders at startup and re-injects them on an interval defaulting to one hour (`perses/perses@21376aaf:docs/configuration/provisioning.md`), recursing into subfolders and ignoring unmanaged files.
F25 Provisioning writes through the service manager rather than the HTTP layer (`perses/perses@21376aaf:internal/api/provisioning/provisioning.go:34`), so it is unaffected by the read-only switch.
F26 `security.readonly` deactivates every POST, PUT and DELETE resource route while leaving GET routes intact (`perses/perses@21376aaf:internal/api/generate.go:80`, realised per resource at `perses/perses@21376aaf:internal/api/impl/v1/dashboard/endpoint.go:45`).
F27 F25 and F26 together give a genuine declarative-only mode: provisioned folders are the only write path, and the UI and API cannot mutate resources.
F28 `provisioning.enable_watch` reloads on file change (`perses/perses@21376aaf:pkg/model/api/config/provisioning.go:26`), and it does not exist at 0.53.1, whose `ProvisioningConfig` has only `folders` and `interval` (`perses/perses@2b65a98b:pkg/model/api/config/provisioning.go`).
F29 Perses' own metadata store is either a file tree in JSON or YAML, or SQL over the MySQL driver only (`perses/perses@21376aaf:internal/api/database/database.go:170`); the `pgx` dependency serves datasource proxying, not the metadata store.

### Access control and tenancy

F30 Authentication is native username and password issuing a one-hour JWT, or external OIDC/OAuth with authorization-code, device-code and client-credentials flows, or delegated Kubernetes (`perses/perses@21376aaf:docs/concepts/authentication.md`), and roles can be assigned from token claims.
F31 Authorization is additive-only RBAC with `Role`/`GlobalRole` and `RoleBinding`/`GlobalRoleBinding` and no deny rules, with the project as the scoping unit (`perses/perses@21376aaf:docs/concepts/authorization.md`).
F32 A binding's referenced role is immutable after creation; changing it requires deleting and recreating the binding.
F33 Unauthenticated or unmatched access is governed by `authorization.guest_permissions`, and the dev config grants guests read on every scope (`perses/perses@21376aaf:dev/config.yaml:8-19`).
F34 The datasource proxy checks caller permission before forwarding and injects the datasource secret server-side (`perses/perses@21376aaf:docs/concepts/proxy.md:65`), so credentials never reach the browser when `proxy` is used rather than `directUrl`.
F35 Datasource secrets are stored in the Perses database encrypted with AES-256 under `security.encryption_key`, which must be exactly 32 bytes and may be supplied by `encryption_key_file` (`perses/perses@21376aaf:pkg/model/api/config/security.go:147-154`).
F36 When neither is set, Perses substitutes a hardcoded default key and only logs a warning rather than refusing to start (`perses/perses@21376aaf:pkg/model/api/config/security.go:167-170`).
F37 RBAC roles and bindings are carried in the user's JWT with a cache refreshed on an interval and on role changes, a synchronisation concern that a single instance does not have.

### Signals beyond metrics

F38 Perses is not metrics-only: the development dashboard combines `PrometheusTimeSeriesQuery`, a `LogsTable` panel over `LokiLogQuery` against a `LokiDatasource`, and `TraceTable` and `TracingGanttChart` panels over `TempoTraceQuery` against a `TempoDatasource` (`perses/perses@21376aaf:dev/data/9-dashboard.json:12543,12552,12268,12318,12494`).
F39 The log, trace and profile panel plugins are present in the nixpkgs 0.53.1 set: `LogsTable`, `TraceTable`, `TracingGanttChart`, `FlameChart`, plus `Loki`, `Tempo`, `Pyroscope` and `VictoriaLogs` datasources (`NixOS/nixpkgs@85f62611:pkgs/by-name/pe/perses/plugins.nix`).
F40 Query plugins are datasource-specific rather than generic, `LokiLogQuery` and `TempoTraceQuery` being bound to their datasource kinds, so a panel type being available does not imply it can query an arbitrary store.
F41 Consequently a GreptimeDB-only deployment gets metrics through the Prometheus plugin (F20) but has no path to logs or traces at 0.53.1, because the only log and trace query plugins packaged bind to Loki, Tempo, VictoriaLogs and Pyroscope.

### Embedding

F42 Panels and dashboards embed into a React application through `@perses-dev/components`, `@perses-dev/plugin-system`, `@perses-dev/dashboards` and per-plugin packages (`perses/perses@21376aaf:docs/embedding-panels.md:19-26`).
F43 Those UI libraries have moved out to `perses/shared` (`perses/perses@21376aaf:docs/embedding-panels.md:11`), and React 19 is unsupported, React 18 being pinned in the documented install (`perses/perses@21376aaf:docs/embedding-panels.md:18`).
F44 Embedding requires assembling roughly ten providers by hand, and the document itself states that reducing that surface is still in progress.

### CLI surface for CI validation

F45 `percli` exposes `lint`, `apply`, `get`, `describe`, `delete`, `migrate`, `dac` and `plugin` (`perses/perses@21376aaf:docs/cli.md:23-38`), and `dac` has `build`, `diff`, `preview`, `setup` at 0.53.1 with `watch` added only at HEAD (`git ls-tree v0.53.1 internal/cli/cmd/dac/`).
F46 `percli lint --plugin.path <dir>` unzips plugin archives and loads their CUE schemas locally, then validates dashboard, datasource and variable plugin specs offline (`perses/perses@21376aaf:internal/cli/cmd/lint/lint.go:53-64`).
F47 Custom lint rules are a JSONPath `target` bound to `value` plus a CEL `assertion` and a message, supplied by `--custom-rule.path` offline or read from the server's `dashboard.custom_lint_rules` when `--online` (`perses/perses@21376aaf:docs/configuration/custom-lint-rules.md`).
F48 `percli lint` without `--plugin.path` and without `--online` returns immediately and validates nothing beyond what unmarshalling enforces, yet still prints "your resources look good" (`perses/perses@21376aaf:internal/cli/cmd/lint/lint.go:122`).
F49 The same early return skips custom lint rules, since the rule evaluation sits after it.
F50 That behaviour is identical at 0.53.1 (`perses/perses@2b65a98b:internal/cli/cmd/lint/lint.go:122`), so it is not a HEAD regression.
F51 `percli migrate` converts a Grafana dashboard to the Perses format, offline given `migrate.cue` files per plugin or online against a server (`perses/perses@21376aaf:docs/cli.md:272`).

### Governance

F52 Perses is a CNCF sandbox project (`perses/perses@21376aaf:README.md:19`), not incubating or graduated.
F53 The team is eight people and four of them are affiliated with Amadeus, the others with SAP, Red Hat, Coralogix and Chronosphere (`perses/perses@21376aaf:GOVERNANCE.md:38-47`).
F54 Membership, maintainer promotion, removal and governance changes require a two-thirds majority of a private Google Group, and routine business runs on lazy consensus (`perses/perses@21376aaf:GOVERNANCE.md`).
F55 The roadmap names more datasources, a plugin and dashboard marketplace that has not started, and an alert view under consideration (`perses/perses@21376aaf:ROADMAP.md`).
F56 The code is Apache 2.0 with no second licence file in the tree, so there is no open-core boundary of the kind charter W7 raises for GreptimeDB.

## Bearing on decisions

**D2, dashboard layer.**
The evidence supports Perses on its stated grounds and closes RK2 for metrics: the packaged 0.53.1 reaches GreptimeDB's PromQL surface through the already-vendored Prometheus plugin with a base URL of `/v1/prometheus`, on an exact path-and-method match (F17 through F20), so no plugin has to be written or maintained.
The dashboards-as-code claim also survives inspection: definitions are files, `dac build` is server-free, and diffs are meaningful (F4 through F7).
What would reverse this is the logs-and-traces gap in F41: if D2 requires rendering logs or traces from GreptimeDB rather than only metrics, then 0.53.1 has no query plugin for it, and the design must either adopt the SQL-based GreptimeDB plugin (F21, beta, absent from nixpkgs, and only in the upstream default set from `v0.55.0-beta.0`) or accept metrics-only dashboards.
A second reversal condition is the version skew: if the design depends on `provisioning.enable_watch` (F28), `dac watch` (F45), or the HEAD CUE and Go SDK import paths (F8, F9), then 0.53.1 is not the version to build against and packaging moves onto the critical path.

**D1, store.**
F20 and F41 asymmetrically constrain the store: GreptimeDB's PromQL endpoint is sufficient for the metrics half of the dashboard layer, while its log and trace data would be unreachable from a 0.53.1 Perses.
If D1 keeps all three signals in GreptimeDB, D2 inherits an unrendered-signal problem that is not the store's fault.
This would be reversed by adopting the beta GreptimeDB plugin, which pushes a packaging obligation onto D7.

**D6, lakehouse seam.** Nothing here bears on it, except that the dashboard layer's only hard requirement on the store is a PromQL HTTP surface, so the seam is unconstrained by D2.

**D7, packaging and host placement.**
F14 and F15 are the operative facts: the nixpkgs package does not install plugins into its outputs, so any module must wire `plugin.archive_path` to `perses.pluginsArchive`, and a GreptimeDB plugin would have to be added to a vendored plugin set.
F29 matters for placement: Perses' metadata store is a file tree or MySQL, and `magnetite` runs PostgreSQL, so the file backend is the only zero-new-service option.
Reversed if a Perses release adds a PostgreSQL metadata backend.

**D8, access control and tenancy.**
The evidence is favourable and specific.
`security.readonly` plus provisioning gives a real declarative-only deployment where the fleet cannot mutate dashboards (F27), the proxy is permission-checked and keeps datasource credentials server-side (F34), the project is a usable tenancy unit for separating agent-session telemetry from fleet telemetry (F31), and external OIDC makes the existing Kanidm the identity source (F30).
Two hazards are concrete: `guest_permissions` defaults in the upstream example grant read on every scope (F33), which under W9 would expose prompt-bearing dashboards to anonymous callers; and the encryption key silently falls back to a hardcoded constant (F36), so the design must require `encryption_key_file` from a clan-managed secret.
Reversed only if the fleet needs write access from the UI, which would forfeit F27.

**D4, signal scope.** F40 is the constraint that matters: query plugins are bound to datasource kinds, so signal scope and dashboard layer are coupled and cannot be decided independently.

## Flags

Charter W4 says nixpkgs packages perses 0.53.1, and that is confirmed, but the gap to the local checkout is material in four specific ways rather than cosmetic: no GreptimeDB plugin in the default set (F13) or in the nixpkgs vendored set (F14), no `provisioning.enable_watch` (F28), no `dac watch` (F45), and different CUE and Go SDK import paths because the spec was extracted into `perses/spec` after 0.53.1 (F8).
Any design text that cites perses.dev documentation is describing at least 0.54.0 and should not be read as describing the packaged version.

Upstream documentation claims `percli lint` "is able to validate any data supported by Perses" (`perses/perses@21376aaf:docs/cli.md:257`), and the source contradicts this: without `--plugin.path` or `--online` the command validates nothing beyond unmarshalling and still prints a success message (F48, F49).
A CCV regulator built on bare `percli lint` would be tautologically green on plugin specs and on custom lint rules alike.
The regulator must pass `--plugin.path` pointing at the plugin archive directory, and its operating envelope should state that plugin-spec validation is conditional on that flag.

The README advertises "bringing together all four observability pillars in one place" (`perses/perses@21376aaf:README.md:17`).
That is true of Perses as a project but not of Perses against one store: pillar coverage is per-datasource, and at 0.53.1 no log or trace query plugin exists for GreptimeDB (F41).

The plugin installer downloads from `github.com/perses/perses-plugins` (`perses/perses@21376aaf:scripts/plugin/install_plugin.go:34`) while the README, the dashboard-as-code guide and the nixpkgs-vendored release URLs all use `github.com/perses/plugins`.
One of the two is a redirect and the disagreement is unresolved here; it matters only if a derivation hardcodes a release URL.

`security.encryption_key` falling back to a hardcoded constant with a warning (F36) is a silent-weakening default, reported here because no charter world assumption covers it.

No charter world assumption W1 through W9 is contradicted by these findings.

Absences reported explicitly: `perses/plugins` is absent locally, so the GreptimeDB and Prometheus plugin implementations were not read from source (F22); `perses/spec` and `perses/shared` are likewise absent, so the HEAD dashboard spec and UI libraries were read only through their import sites.

## Questions

Does D2 require rendering logs and traces from the chosen store, or are metrics-only dashboards acceptable for the first deployment?
The answer decides whether the beta SQL-based GreptimeDB plugin enters scope with its packaging cost, or whether the Prometheus-plugin route alone suffices.

Should the design target the packaged 0.53.1 or a newer Perses?
Every difference in F8, F13, F28 and F45 follows from this one choice, and it is a packaging-versus-capability trade that belongs to a human.

Is Kanidm the intended identity provider for Perses via OIDC, and if so, do agent-session dashboards live in a separate Perses project with its own role bindings, or in a separate Perses instance? F31 supports either and the prompt-content hazard in W9 makes the distinction consequential.

Which plugin, if any, declares `SQLProxy`, and would the MySQL or PostgreSQL wire route (F23) be preferable to the PromQL route for dev-loop queries that are analytical rather than time-series? This was not resolvable without the plugins repository.
