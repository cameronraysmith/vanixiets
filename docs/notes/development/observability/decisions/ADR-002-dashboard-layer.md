---
title: "ADR-002: Dashboard layer"
---

## Status

Accepted (human gate, 2026-10-15).
Amended in place under charter v11 (2026-10-16): the dashboard layer moved from a standalone Perses server to the Perses dashboard GreptimeDB embeds, after the premise that GreptimeDB 1.2.1 lacks the dashboards API was found false.

## Context

Charter D2 asks for one dashboard layer, its dashboards-as-code format, and datasource reachability against the chosen store.
The human gate of 2026-10-06 named GreptimeDB on `magnetite` backed by Cloudflare R2 as the store, and GreptimeTeam/dashboard "or better" as the dashboard layer, with Perses the leading "or better" candidate.
This ADR assumes the store decision of ADR-001 and the placement of ADR-007: GreptimeDB 1.2.1 standalone on `magnetite`, consumed as `greptimedb-bin` built from the upstream release tarball (ADR-001 R1.1), listening for HTTP on `127.0.0.1:4000` (ADR-007), with the read-only `perses` user that ADR-007 enumerates among the store users.
This ADR assumes the access model of ADR-008: content exclusion at the collector, and one shared read zone of admitted humans with no per-person read partition.

The facts about the embedded dashboard that bind this decision are these.
GreptimeDB `v1.2.1` embeds GreptimeTeam/dashboard `v0.13.13` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/dashboard/VERSION`), and that release runs Perses 0.53.1 with the Prometheus plugin 0.57.1 and the GreptimeDB plugin `0.1.0-beta.0` (`GreptimeTeam/dashboard@7b4b275a:package.json:59-79`).
Perses 0.54.0 arrives only with dashboard `v0.14.2`, which GreptimeDB `main` embeds and no stable GreptimeDB release does yet (`research/perses.md` R37, R42).
The dashboards API `GET /v1/dashboards`, `POST /v1/dashboards/{name}` and `DELETE /v1/dashboards/{name}` exists at `v1.2.1` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:829-836`, `:1437-1444`; `GreptimeTeam/greptimedb@179ff8e50:src/frontend/src/instance/dashboard.rs`).
It stores each request body verbatim as `definition` in the table `greptime_private.dashboard`, keyed by the dashboard name as its primary-key tag (`GreptimeTeam/greptimedb@179ff8e50:src/frontend/src/instance/dashboard.rs:51-54`); the UI posts `{"content": <dashboard JSON as a string>}` (`GreptimeTeam/dashboard@7b4b275a:src/views/dashboard/perses/index.vue:388`).
`research/perses.md` R39, which says the API is absent from `v1.2.1` and appears only in the `v1.3` prereleases, is superseded by these citations, and this ADR's version before charter v11 rested on R39.
The dashboards API and the UI are compiled only with the `dashboard` Cargo feature (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:959-988`, `:1437`), which upstream release tarballs enable and the nixpkgs derivation does not (`research/nix-packaging-status.md` R9, R10).

The UI is served at `/dashboard/` on the main HTTP listener, and also on a dedicated API listener when `http.enable_api_server = true`, which binds `http.api_server_addr`, `127.0.0.1:4006` by default (`GreptimeTeam/greptimedb@179ff8e50:config/standalone.example.toml:96`, `:99`).
The dedicated listener serves only the `/v1` interfaces and `/dashboard` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http.rs:213-216`).
The UI has no base-path option, and its datasources use root-absolute URLs, so it needs a vhost of its own with `/v1` at the root `[INFERENCE]`.
It declares exactly two datasources, which the user cannot change: `promql-default`, a `PrometheusDatasource` at `/v1/prometheus`, and `sql-default`, a `GreptimeDBDatasource` posting to `/v1/sql` (`GreptimeTeam/dashboard@7b4b275a:src/perses-dashboard/react/DashboardView.tsx:41-97`).
Both send a Basic `Authorization` header and an `x-greptime-db-name` header built from the connection settings the browser keeps in `localStorage` (`GreptimeTeam/dashboard@7b4b275a:src/perses-dashboard/react/DashboardView.tsx:41-97`; `research/perses.md` R41).
Its panels are TimeSeries, Gauge, Stat, Table, Histogram, HeatMap, Markdown, Scatter, Bar, Pie, LogsTable, TraceTable, TracingGantt and TimeSeriesTable, and it registers no `StaticListVariable` (`GreptimeTeam/dashboard@7b4b275a:src/perses-dashboard/react/plugin.ts`).
It imports Perses dashboard JSON but not Grafana JSON; the upstream skill converts a Grafana dashboard with `percli migrate --online` against a standalone Perses server (`GreptimeTeam/dashboard@7b4b275a:skills/greptimedb-perses-dashboard/reference.md:562`).
The store, not the UI, enforces read-only access: saving and deleting a dashboard are write actions (`GreptimeTeam/greptimedb@179ff8e50:src/auth/src/permission.rs:150-152`), and the permission checker installed with the user provider rejects writes from `ro` users, so the `perses:ro` user can view dashboards and cannot save or delete them.
The UI has no OIDC login, no project model and no RBAC of its own (`research/perses.md` R41).

The facts about standalone Perses that bind this decision are these.
The root pin, lock node `nixpkgs_10` at `NixOS/nixpkgs@ac1faec4`, packages Perses and `percli` 0.54.0 with the NixOS module `services.perses` (`research/perses.md` R11, R13; `research/nix-packaging-status.md` R13).
The stock Prometheus plugin reaches GreptimeDB's PromQL router at `/v1/prometheus` (`research/perses.md` F20), except that the Prometheus `/metadata` route is absent at GreptimeDB 1.1.4 and 1.2.1 (`research/greptimedb.md` R12).
`percli lint` is tautologically green without plugin schemas (charter RK8; `research/perses.md` R17, R18).
With `--plugin.path` pointed at the archive directory it fails closed on every input because of the `ArchivePath`/`ArchivePaths` mismatch (`research/perses.md` R19, R20).
With `--plugin.path` pointed at a directory of extracted plugins, or with `--online`, it rejects schema mutants and custom-rule mutants while accepting valid files (`research/perses.md` R21, R22, R24).
A standalone Perses server from the root pin extracts its plugin archives into `/run/perses/plugins` on a tmpfs, 257 MiB for the full vendored set and 84 MiB for a ten-plugin subset (local extraction of `perses.pluginsArchive` from root node `nixpkgs_10`, 2026-10-15).
`magnetite` has 30.6 GiB of RAM and was OOM-killed twice by overlapping evaluations (`cameronraysmith/vanixiets@a8e72d185:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:5`, `:12`), which is charter RK3.

The repository's conventions also bind this decision.
NixOS VM tests live under `modules/vm-tests/` as `vmTests.<system>.<name>`, run on demand, and are outside pull-request gating (`modules/README.md:32`, `:48`, `:86`).
`magnetite` has no `/dev/kvm` but advertises `uid-range` for nspawn container tests (`modules/machines/nixos/magnetite/default.nix:81-93`; `modules/clan/inventory/services/nix-builders.nix:30-43`), and slice S1 adds the first such container test, `vmTests.x86_64-linux.greptimedb-pipeline`, to the same on-demand lane (`openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md:43`).
`vanixiets.net` never hosts authentication, sessions or cookies (web-verification D9, `docs/notes/development/web-verification/decisions.md:124`), while Kanidm-backed services on `magnetite` use `*.scientistexperience.net` names.
The `sso-gateway` module registers a service with no OIDC of its own as a `forceSSL` nginx vhost gated by `auth_request` against the shared oauth2-proxy at `auth.scientistexperience.net`, and derives the Kanidm group stub and scope map from the service's `allowedGroups` (`modules/nixos/sso-gateway.nix:80-96`, `:288-324`, `:459-476`).
Web-verification D11 says UIs hosted on `magnetite` keep `sso-gateway` (`docs/notes/development/web-verification/decisions.md:252`), and the gateway's design names magnetite UIs as its consumers (`openspec/changes/sso-gateway/design.md:3-5`, `:17`).
The gateway is declared on `magnetite` but disabled today (`modules/machines/nixos/magnetite/default.nix:133`).

## Decision

The dashboard layer is the Perses dashboard that GreptimeDB embeds, served by `greptimedb.service` on `magnetite` at `/dashboard/`, using its two fixed datasources `promql-default` and `sql-default`.
No standalone Perses server is deployed.
Standalone Perses is kept as tooling only: `percli migrate` with an ephemeral local Perses server converts Grafana community dashboards into Perses JSON, and `percli lint` against the Perses schema version the embedded dashboard runs is a flake check.
A deployed standalone Perses server is the fallback only if a dashboard needs a feature the embedded dashboard lacks, such as `StaticListVariable` or projects with RBAC.

Slice S6 serves the dashboard at `perses.scientistexperience.net`, a `magnetite` vhost registered with `sso-gateway` and admitting the Kanidm group `perses_users`.
nginx proxies `/dashboard/` and `/v1/` on that vhost to the store's API listener at `127.0.0.1:4006`, enabled by `http.enable_api_server = true` in S6, not in S1.
nginx overwrites the `Authorization` header on those locations with the `perses:ro` Basic credential, so no store password reaches the browser.
The dashboards-as-code format is Perses `Dashboard` JSON files committed to this repository and reconciled by a oneshot through `/v1/dashboards`: it posts every file in the repository and deletes every stored dashboard absent from it, using a `rw` store credential whose holder is open (Q9).
Slice S1 exposes nothing new publicly: the dashboard is reachable from the first deployment only through `ssh -L 4000:127.0.0.1:4000 magnetite.zt`.

## Rationale

The embedded dashboard satisfies the three D2 conditions with no service beyond the store.
It renders metrics, logs and traces from GreptimeDB through the PromQL datasource and the GreptimeDB plugin's log and trace queries in the LogsTable, TraceTable and TracingGantt panels, so RK7 stays resolved.
Its definitions are Perses dashboard JSON, the format `percli lint` checks offline and the upstream dashboard skill generates (`research/perses.md` R43, R45).
Its write path is an HTTP API whose writes the store authorizes by user mode, which gives a declarative deployment: the reconcile oneshot is the only `rw` writer, and readers hold `ro`.

The version before charter v11 rejected the embedded dashboard for four reasons, and each has been re-examined.
The premise that it needs a GreptimeDB 1.3 prerelease is false, because `v1.2.1` carries the dashboards API (Context).
The premise that it has no file provisioning overlooked the dashboards API combined with the store's `ro`/`rw` enforcement.
The premise that it stores a password in the browser holds only if the browser authenticates; with nginx injecting the credential, the browser holds none `[INFERENCE]`.
The objection that it has no authorization of its own still holds, and `sso-gateway` supplies admission while the store's user mode supplies read-only enforcement.

The standalone server is not deployed because it costs a second service, a tmpfs of at least 84 MiB on a host already OOM-killed twice (RK3), its own Kanidm client, an encryption key, and an upgrade obligation to the 0.55 line.
It buys capabilities this design does not use: projects and RBAC do not partition reads under ADR-008's shared read zone (charter RK9), and of the ten plugins the earlier decision selected, the embedded dashboard lacks only `StaticListVariable`.
`percli` stays useful without the server, because lint and migrate run on files.

The API listener on `127.0.0.1:4006` is the upstream rather than `127.0.0.1:4000`, because it serves only `/v1` and `/dashboard` (Context), so the public vhost cannot reach `/metrics`, `/health` or any other route of the main listener.
`sso-gateway` admits readers, rather than a direct Kanidm client, because the embedded dashboard has no OIDC login, and the gateway module directs services without OIDC to register with it (`modules/nixos/sso-gateway.nix:288-298`); this follows web-verification D11 rather than excepting it.
nginx overwrites `Authorization` rather than letting each reader type the `perses:ro` password into the UI, because a typed password would persist in `localStorage` on every reader's machine (`research/perses.md` R41).
The hostname stays `perses.scientistexperience.net`, accepted at the 2026-10-15 gate as Q6, because nothing in the change of dashboard host bears on the name: the vhost still sits behind a Kanidm-backed login, which D9 keeps off `vanixiets.net`.

Reconciling through `/v1/dashboards` is the as-code path because the API stores the posted body verbatim (Context), so the reviewed file is the stored definition.
The oneshot deletes dashboards absent from the repository because the API has no bulk replace, and a dashboard saved under any `rw` credential outside the repository would otherwise persist.
The lint check runs against the embedded Perses version rather than the root pin's 0.54.0, because the embedded dashboard parses the stored JSON with Perses 0.53.1 and its plugin versions, and a lint against other schemas could accept a file the deployed renderer rejects or the reverse `[INFERENCE]`.

The dashboard is reachable over an SSH tunnel from S1 because the release tarball serves it on the loopback listener S1 already configures, so S1 can use it for its own read-back checks without any public surface.

## Rejected alternatives

- Standalone Perses 0.54.0 server, the decision before charter v11: a second service with an 84 MiB tmpfs under RK3, its own Kanidm client and encryption key, and an upgrade obligation, for projects and RBAC that ADR-008's shared read zone does not use; kept as the fallback named in the Decision.
- Perses 0.55 line as a standalone server: a release candidate absent from nixpkgs, with the same costs as the standalone server.
- Grafana 13.1.1: packaged with a module, but AGPL under a single corporate sponsor (C3), with no first-party GreptimeDB log or trace datasource evidenced in this corpus and a dashboard JSON format that is not the one GreptimeDB's own tooling emits (`research/store-alternatives.md` F18, F22; `research/perses.md` R43).
- Building `pkgs.greptimedb` with the `dashboard` feature: needs a fixed-output fetch of the dashboard assets and a 34-minute source build, while the release tarball already carries the feature (`research/nix-packaging-status.md` R11, F14; ADR-007).
- Serving the dashboard as a static `build.tar.gz` beside the store: a second artifact to version against the store, for the same UI the store already serves (`research/nix-packaging-status.md` R12).
- Proxying the vhost to the main listener `127.0.0.1:4000`: exposes `/metrics`, `/health` and every other route of the main listener to admitted browsers.
- Readers typing the `perses:ro` password into the UI: persists the password in `localStorage` on every reader's machine (`research/perses.md` R41).
- A direct Kanidm OIDC client: the embedded dashboard has no OIDC login to use it.
- Dashboards edited in the deployed UI: `perses:ro` cannot save, a save under a `rw` credential bypasses review, and the reconcile oneshot deletes or overwrites it.
- Go or CUE dashboards-as-code SDK: adds a build step whose output is the JSON this ADR commits directly, and the GreptimeDB plugin ships no CUE SDK (`research/perses.md` R10).
- Bare `percli lint`: validates nothing beyond unmarshalling and reports success (charter RK8; `research/perses.md` R17).
- `percli lint --plugin.path <archive directory>`: fails closed on valid files, so it does not discriminate (`research/perses.md` R19, R20).
- `percli lint --online` as the gating regulator: needs a running Perses server inside the check and excludes `--custom-rule.path` (`research/perses.md` R25).
- MySQL or PostgreSQL wire route to the store: the embedded datasources do not use it, and it adds a second listener on the store (`research/perses.md` R31).

## Consequences

Dashboards change only by commit and deploy; the reconcile oneshot overwrites or deletes any dashboard that differs from the repository.
The UI may still show edit controls to `perses:ro` readers, because the client decides that independently of the store, but every save fails at the store `[INFERENCE]`.
Any admitted reader can send arbitrary SQL and PromQL from the browser to the store's `/v1` routes under `perses:ro`, which is acceptable only because ADR-008 places every admitted human in one read zone and excludes content at the collector.
There is one global dashboard list, with no projects and no per-dashboard permissions.
Dashboards cannot use `StaticListVariable`; a dashboard that needs it triggers the standalone-server fallback or is rewritten with the variables the embedded dashboard registers.
The Perses version follows the store: 0.53.1 at GreptimeDB `v1.2.1`, and 0.54.0 once a stable GreptimeDB release embeds dashboard `v0.14.2`; each store upgrade that changes the embedded dashboard version must move the lint tooling in the same commit.
The datasources take the database from the `x-greptime-db-name` header the browser sends, so a PromQL panel reads the database set in the reader's connection settings rather than one the dashboard file names (Q10).
Grafana community dashboards reach the repository only through `percli migrate --online` against a local Perses server, followed by rewriting their datasources to `promql-default` and `sql-default`.
The query editor shows no PromQL metric help until GreptimeDB serves `/metadata`, which first ships in the 1.3 line (`research/greptimedb.md` R12).
Trace panels depend on GreptimeDB's stored trace columns matching the plugin's names (`research/perses.md` R8).
The dashboard is unavailable whenever the store is, and dashboard queries count against the store's own memory ceiling (ADR-007).
S6 must enable `sso-gateway` on `magnetite`, which is disabled today (Context), and the gateway then also admits the services already registered with it.
Kanidm login is exercised only through the gateway, so the OIDC path is the gateway's, already in use by its other consumers rather than new to this ADR.

## Operating envelope and regulator

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| Dashboard files | Every file under the dashboard tree lints clean against the Perses version and plugin set the deployed store embeds, and against custom rules forbidding `SELECT *` and any datasource name other than `promql-default` and `sql-default`, each rule targeting a scalar (`research/perses.md` R23) | flake check `perses-lint`: `percli lint --plugin.path <extracted plugins> --custom-rule.path <rules>` over each file, with `percli` and the plugins at the versions `greptimedb-bin`'s embedded dashboard pins; deterministic, nixbot `x86_64-linux` | an enumerated mutant set built in the same derivation (empty `query`, extra field in a query spec, unknown query kind, a `StaticListVariable`, `SELECT *`, a third datasource name) each of which must exit non-zero, plus the valid set which must exit zero, so both the tautological pass of RK8 and the fail-closed archive form of R19 turn the check red |
| Lint tooling version | The Perses and plugin versions the lint check uses equal those of the dashboard version the store package embeds | evaluation-time assertion in `perses-lint` comparing its tooling versions against the store package's `passthru.dashboardVersion` | a mutant that sets `passthru.dashboardVersion` to `v0.14.2` must fail the assertion |
| Serving configuration | `http.enable_api_server` true with `http.api_server_addr` in `127.0.0.0/8`; the vhost registered with `sso-gateway` with `allowedGroups = [ "perses_users" ]`; its `/dashboard/` and `/v1/` locations proxy to the API listener and overwrite `Authorization`; no other location proxies to the store | evaluation-time assertions in the dashboard module, plus the mutant check `perses-config` in the shape of `cameronraysmith/vanixiets@a8e72d185:modules/checks/omnigent-environment.nix:98-118` | each named mutant (API server off, API listener on `0.0.0.0`, `allowedGroups` empty, a location proxying to `127.0.0.1:4000`, the `Authorization` override removed) must produce a non-empty failure list, or the check fails with "accepted a policy mutant" |
| Reconciled dashboard set | After each run, the names `GET /v1/dashboards` returns equal the repository's file names, and each stored definition equals its file | the reconcile oneshot `perses-dashboards.service` re-reads the list after writing and exits non-zero on any difference, with `OnFailure=observability-notify@%n.service` | the on-demand container test below seeds one extra stored dashboard and one altered definition and asserts the oneshot removes and rewrites them, and that a run whose re-read is forced to differ exits non-zero |
| Data path, vhost to store | Through nginx with the injected credential, `/dashboard/` returns 200, one PromQL, one SQL time-series, one log and one trace query each return at least one row, and a `POST /v1/dashboards/<name>` is refused | on-demand container test `vmTests.x86_64-linux.perses-greptimedb` in the lane S1 establishes, with the gateway's `auth_request` stubbed: GreptimeDB plus nginx, OTLP samples written with the `wo` credential | the same test issues one query against a nonexistent table and asserts it is rejected, and asserts the refused `POST` leaves the stored set unchanged; because it does not gate, this row is evidence only when run |
| Kanidm login through the gateway | Login completes for a member of `perses_users` and is refused for an authenticated non-member | one recorded manual login of each kind at first deploy, carried as Q4 because no automated regulator over a live Kanidm exists in this repository | not shown; this row is the incomplete regulator R5 requires this ADR to name |

The runtime half of the store package envelope, `GET /dashboard/` returning 200 on `127.0.0.1:4000`, is a case of S1's container test under ADR-001 R1.1.

## Failure prevented

- Embedded dashboard: a GreptimeDB store whose logs and traces nobody can see, which is charter RK7, without a second service on a memory-constrained host (RK3).
- Reconcile oneshot with deletion: dashboards drifting from the repository through saves that no review sees.
- `perses:ro` for readers: a reader deleting or overwriting a dashboard, because the store rejects the write.
- Credential overwrite at nginx: a store password persisted in browser storage on readers' machines (`research/perses.md` R41).
- API listener as the upstream: store routes beyond `/v1` and `/dashboard` reachable from the public vhost.
- Lint check with mutants: a schema-invalid dashboard reaching `magnetite` behind a regulator that reports success on everything (RK8).
- Lint tooling version assertion: a lint that passes files the deployed renderer's Perses version rejects.
- Configuration assertions with mutants: an unauthenticated vhost, a vhost admitting every Kanidm user, or a listener beyond loopback reaching deployment unnoticed.
- On-demand container test: dashboards that lint clean but render empty because a table or column name is wrong, when the test is run before deploy (`research/perses.md` R8, R26).
- `sso-gateway` admission: a second Kanidm client and a second login surface for one more `magnetite` UI.

## Implementation surface

This surface belongs to slice S6 except where it names S1.

Files to add:
- `modules/nixos/perses.nix`: registers `sso.services.perses` with `domain = "perses.scientistexperience.net"`, `allowedGroups = [ "perses_users" ]` and `upstream` mapping `/dashboard/` and `/v1/` to `http://127.0.0.1:4006`; adds the `Authorization` overwrite to those two locations from the `perses-password` file, read by nginx outside the Nix store; sets `services.greptimedb.settings.http.enable_api_server = true`; defines `perses-dashboards.service`, ordered after `greptimedb.service` and triggered on activation when the dashboard tree changes, with `OnFailure=observability-notify@%n.service`; and declares the evaluation-time assertions above.
- `modules/nixos/perses/dashboards/*.json`: the Perses `Dashboard` JSON files.
- `modules/nixos/perses/lint-rules.yaml` and `modules/nixos/perses/mutants/*.json`: the custom lint rules and the enumerated mutant set.
- `modules/checks/perses-lint.nix`: the lint check with its valid and mutant legs and the tooling-version assertion.
- `modules/checks/perses-config.nix`: the serving-configuration mutant check.
- `modules/vm-tests/perses-greptimedb.nix`: the on-demand container test, assigning `perSystem.vmTests` on `x86_64-linux`, in the shape of S1's `modules/vm-tests/greptimedb-pipeline.nix`.
- `percli` and plugin archives at the embedded dashboard's versions, for the lint check; the root pin carries `percli` 0.54.0, so the check either packages 0.53.1 or shows by its mutant legs that the root pin's tooling discriminates the same set.

Files to modify:
- `pkgs/by-name/greptimedb-bin/package.nix`: add `passthru.dashboardVersion`, beside the `passthru.embedsDashboard` that S1 sets for ADR-001 R1.1.
- `modules/machines/nixos/magnetite/default.nix`: import the dashboard module and enable `sso-gateway` (`modules/machines/nixos/magnetite/default.nix:133`).
- `modules/terranix/cloudflare.nix`: one `CNAME` `perses.scientistexperience.net` to `magnetite.scientistexperience.net`, unproxied, mirroring the `omni` record (`modules/terranix/cloudflare.nix:186-193`).
- No change to `modules/nixos/kanidm.nix`: the gateway derives the `perses_users` group stub with `overwriteMembers = false` and its scope map from `allowedGroups` (`modules/nixos/sso-gateway.nix:459-476`).

Flake inputs: none.

Clan vars generators:
- None added by this ADR.
- The `perses-password` file of ADR-007's `greptimedb-users` generator is consumed by nginx from S6, with `restartUnits = [ "nginx.service" ]`.
- The reconcile oneshot's `rw` credential comes from whichever holder Q9 selects.

## Questions for the human gate

Q1 Perses 0.54.0 or the 0.55 line? Recommended: 0.54.0 from the root pin with an upgrade obligation at 0.55.0 final in nixpkgs.
Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11, because no standalone server is deployed and the Perses version follows the dashboard the store embeds.
Q2 Disposition of GreptimeTeam/dashboard? Recommended at the gate: rejected as the dashboard layer and deferred as an exploration console, on the premise that it required a GreptimeDB 1.3 prerelease and a store password held in browser storage.
Resolution: accepted at the 2026-10-15 gate; amended under charter v11, after both premises were found not to hold: GreptimeDB's embedded dashboard is the dashboard layer, per the Decision.
Q3 Keep a PromQL datasource beside the GreptimeDB datasource? Recommended: yes.
Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the embedded dashboard fixes both datasources, so the answer holds without configuration.
Q4 Is one recorded manual Kanidm login at first deploy acceptable as the login regulator? Recommended: yes; the alternative is adding a Kanidm node to the container test, which roughly doubles its cost to sample a path exercised once per login.
Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the login is the gateway's, recorded once for a member and once for a non-member.
Q5 Is an on-demand, non-gating runtime test the right home for the data-path regulator? Recommended: yes, under `modules/vm-tests/` per `modules/README.md:32`, `:86`, with the gating set the lint and configuration checks.
Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the test is an nspawn container test in the lane S1 establishes, rather than a QEMU VM test.
Q6 Public hostname behind Kanidm, or a mesh-only `.zt` vhost? Recommended: public `perses.scientistexperience.net` behind Kanidm.
Resolution: perses.scientistexperience.net behind Kanidm, accepted at the 2026-10-15 gate; under charter v11 Kanidm admits through `sso-gateway`.
Q7 Plugin subset of ten? Recommended: yes, at an envelope of 96 MiB.
Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11, because the embedded dashboard compiles its plugins into the store binary and extracts nothing to a tmpfs.
Q8 Plain resource YAML as the dashboards-as-code format? Recommended: yes.
Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11 by Perses `Dashboard` JSON reconciled through `/v1/dashboards`, because the embedded dashboard has no resource provisioning.
Q9 Which `rw` store credential does the reconcile oneshot hold? Options: the existing `admin` user, which ADR-007 restricts to the schema and export oneshots; a fifth `rw` user for the oneshot alone; or folding the reconcile into `greptimedb-schema`, which already holds `admin`.
Resolution: open, decided in S6.
Q10 How does a dashboard select among `fleet`, `devloop` and `agent`, given that both datasources take the database from the browser's connection settings? SQL panels can qualify table names with the database; PromQL panels cannot, so options include nginx setting `x-greptime-db-name` per location, restricting PromQL panels to one database, or the standalone-server fallback.
Resolution: open, decided in S6.
