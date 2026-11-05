---
title: "ADR-002: Dashboard layer"
---

## Status

Accepted (human gate, 2026-10-15).
Amended in place under charter v11 (2026-10-16): the dashboard layer moved from a standalone Perses server to the Perses dashboard GreptimeDB embeds, after the premise that GreptimeDB 1.2.1 lacks the dashboards API was found false.
Reversed in place under charter v28 (2026-11-05): the dashboard layer is a standalone Perses 0.55.1 server, packaged from the upstream release as `perses-bin`, logging people in through its own Kanidm client at `obs.scientistexperience.net`; the embedded dashboard stays on loopback as the operator's fallback (CAM-73, `openspec/changes/serve-the-fleet-dashboard/`; #3720, #3721).
The embedded dashboard behind `sso-gateway`, the decision from charter v11 to v27, is recorded under Rejected alternatives.

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
The gateway is declared on `magnetite` but disabled today (`modules/machines/nixos/magnetite/default.nix:163`).

The facts the reversal under charter v28 rests on are these (`openspec/changes/serve-the-fleet-dashboard/design.md` Context; `openspec/changes/serve-the-fleet-dashboard/brainstorm.md` "Grounding evidence").
The Perses `v0.55.1` release tarball holds the statically linked `perses`, with its UI embedded, `percli`, and the 32 plugin archives that `scripts/plugin/plugin.yaml` pins at the tag; 0.55.0 fixes the 0.54.0 advisories and refuses to start with authentication on and no encryption key, closing 0.54.0's hardcoded-key fallback (GHSA-mpfg-6jh9-3jmg), and 0.55.1 adds further security fixes.
Perses has native OIDC login with PKCE on by default (`perses/perses@v0.55.0:pkg/model/api/config/authentication.go:143-156`, `:219-224`), and Kanidm refuses an authorization whose requested scopes no group of the person maps (`kanidm/kanidm@v1.11.2:server/lib/src/idm/oauth2.rs:3473-3502`), so a client whose only scope map is one group admits only that group.
`security.readonly` removes every create, update and delete route on resources, sign-up among them (`perses/perses@v0.55.0:internal/api/core/server.go:63-93`).
The datasource proxy injects the Basic credential from a secret's `passwordFile`, overwrites the configured headers, forwards only the caller headers a datasource's `allowHeaders` lists, and refuses with 403 a path no `allowedEndpoints` pattern matches (`perses/perses@v0.55.0:internal/api/impl/proxy/http/http.go:254-306`).
Provisioning creates and updates and never deletes, and a session refresh issues a new access token without consulting the identity provider (`perses/perses@v0.55.0:internal/api/provisioning/service.go:43-120`, `internal/api/impl/auth/auth.go:167-207`).
At 0.55.1 `percli lint` extracts the archives it finds in a writable `--plugin.path` and then rejects schema and custom-rule mutants while accepting valid files; bare lint still accepts everything (`logs/cam73-evidence/2.4-lint-20261105T003923Z.log`).
The store reads `x-greptime-auth` before `Authorization` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/authorize.rs:310-319`).

## Decision

The dashboard layer is a standalone Perses 0.55.1 server on `magnetite`: `perses.service` from nixpkgs' `services.perses` module, running `pkgs.perses-bin`, the upstream release packaged at `pkgs/by-name/perses-bin` with the plugin archives its tag pins.
It listens on `127.0.0.1:8095` behind one nginx vhost, `obs.scientistexperience.net`, with `forceSSL` and ACME, which sets `x-greptime-auth` to the empty string on every request and answers `/metrics` with 404.
People log in through Perses' own OIDC client `perses` at Kanidm, whose only scope map is the group `perses_users`; native login and sign-up are off, the server runs with `security.readonly`, and a logged-in person holds only `read`.
A session's refresh token lives 45 min and an access token 15 min, so a person removed from `perses_users` loses access within 1 h.
The store is read only through two global datasources, `greptimedb-promql` at `http://127.0.0.1:4000/v1/prometheus` and `greptimedb-sql` at `http://127.0.0.1:4000`, which inject the `perses:ro` credential from the GlobalSecret `greptimedb-perses`, set `x-greptime-db-name: fleet`, forward only a fixed list of caller headers, and admit only anchored read-only query paths.
The dashboards-as-code format is Perses resource JSON committed under `modules/nixos/perses/resources/`, provisioned at each start after the file database and the plugin directory are removed, so the committed files are the only resources the server holds.
The first two views are `fleet-hosts`, selected by `host_name`, and `devloop`, in the project `fleet`.
The Perses dashboard GreptimeDB embeds stays served at `/dashboard/` on the store's loopback listener `127.0.0.1:4000`, on no public vhost, as the operator's fallback through `ssh -L 4000:127.0.0.1:4000 magnetite.zt`.
`sso-gateway` stays disabled, and `openspec/changes/sso-gateway/` stays open.

## Rationale

The standalone server closes the read surface that the embedded dashboard would open.
Behind `sso-gateway`, nginx would have proxied every `/v1/` route of the store to admitted browsers; through Perses' proxy, a browser reaches only the anchored query paths of the two datasources.
Anchoring matters: an unanchored pattern forwards paths that extend or prefix a query path, such as `/x/api/v1/query` and `/api/v1/query/../../../../v1/sql`, to the store, while the anchored patterns refuse them with 403 (the plan review's runtime probe, run 3, repeated at 0.55.1 in `logs/cam73-evidence/2.1-probe-0551-20261105T003405Z.log`).

No store credential reaches a browser, because the proxy injects it from a file under the unit's credentials directory.
Each datasource's `allowHeaders` drops a caller's `x-greptime-auth`, which the store would otherwise read before the injected `Authorization`; nginx's strip covers the same header again for every request that comes through the vhost.

Nobody changes a view except by a committed change, and no unit holds a store write credential for it.
`security.readonly` removes the server's write routes, and the removal of the file database before each start drops anything provisioning did not create, because provisioning never deletes.
The embedded dashboard would have needed a reconcile oneshot holding a `rw` store credential, Q9, and its UI would still have offered saves the store then refused.

Admission needs no gateway: Perses has native OIDC, and Kanidm's scope map on the client is the group gate and draws the apps-portal tile, as for the `omnigent` client (`modules/nixos/kanidm.nix`).
Leaving `sso-gateway` off avoids activating the services already registered with it.

The package is the upstream 0.55.1 release, not nixpkgs' 0.54.0, for the advisories 0.55.0 and 0.55.1 fix and the encryption key 0.55.0 requires.
The release tarball carries exactly the plugin archives its tag's `plugin.yaml` pins, so `plugin.yaml` is both the version record and the install check's oracle, and the lint check runs the same `percli` and archives as the server, so no tooling-version assertion is needed.

The four costs this record named against a standalone server under charter v11 are each answered.
The plugins unpack to disk from a curated set of seven archives, 63 MiB, re-extracted at each start, rather than 257 MiB of tmpfs counted against the unit; the Kanidm client mirrors `omnigent`'s; the encryption key is a clan vars generator; and the upgrade obligation is `pkgs/by-name/perses-bin/update.sh`, run as `nix run .#update-perses-bin`.
The server measured about 72 MiB resident before the design and 64 MB at deployment, under a 256 MiB ceiling.

The hostname is `obs.scientistexperience.net`, the operator's decision of 2026-11-04, amending Q6; the vhost sits behind Kanidm login, which web-verification D9 keeps off `vanixiets.net`.

The embedded dashboard stays on loopback because it costs nothing beyond the store and gives the operator a read path when Perses or Kanidm is down, without any public surface.

## Rejected alternatives

- The embedded dashboard behind `sso-gateway` at `perses.scientistexperience.net`, the decision from charter v11 to v27: nginx would expose every `/v1/` route of the store to admitted browsers under the injected `perses:ro` credential, needed `x-greptime-auth` cleared and a credential include, needed a reconcile oneshot holding a `rw` store credential (Q9), left the database to the browser's connection settings (Q10), and required enabling `sso-gateway`, activating the services already registered with it; superseded under charter v28.
- Standalone Perses 0.54.0 from nixpkgs, with nginx denying the advisory paths: keeps the advisories 0.55.0 fixes and the hardcoded-key fallback.
- Perses 0.55.0: superseded by 0.55.1's security fixes.
- Building Perses from source with an overridden `vendorHash` and a UI build: a Go and npm build of a UI the release tarball already embeds.
- Grafana 13.1.1: packaged with a module, but AGPL under a single corporate sponsor (C3), with no first-party GreptimeDB log or trace datasource evidenced in this corpus and a dashboard JSON format that is not the one GreptimeDB's own tooling emits (`research/store-alternatives.md` F18, F22; `research/perses.md` R43).
- Building `pkgs.greptimedb` with the `dashboard` feature: needs a fixed-output fetch of the dashboard assets and a 34-minute source build, while the release tarball already carries the feature (`research/nix-packaging-status.md` R11, F14; ADR-007).
- Serving the dashboard as a static `build.tar.gz` beside the store: a second artifact to version against the store, for the same UI the store already serves (`research/nix-packaging-status.md` R12).
- Proxying the vhost to the main listener `127.0.0.1:4000`: exposes `/metrics`, `/health` and every other route of the main listener to admitted browsers.
- Readers typing the `perses:ro` password into the UI: persists the password in `localStorage` on every reader's machine (`research/perses.md` R41).
- `sso-gateway` in front of the standalone server: a second login surface when Perses has native OIDC, and enabling the gateway activates the services already registered with it.
- Claim-mapped roles inside Perses: every member gets the same read access, so the Kanidm scope map is enough.
- Dashboards edited in the deployed UI: `security.readonly` removes the write routes, and the file database is removed before each start.
- Project datasources, or one datasource per database: one global pair serves every project with `read` on GlobalDatasource alone, and the database header is fixed per datasource, which v1 needs only for `fleet`.
- `dropHeaders = [ "x-greptime-auth" ]` in place of `allowHeaders`: a list of what passes also stops headers nobody has named yet.
- The file database on the unit's runtime tmpfs, or a deletion oneshot reading the API: the runtime directory also holds `config.yaml` and is `0755`, and a deletion oneshot needs a write credential that `readonly` removes.
- Moving Perses' `/metrics` with `-web.telemetry-path`: leaves it reachable under another path.
- Go or CUE dashboards-as-code SDK: adds a build step whose output is the JSON this ADR commits directly, and the GreptimeDB plugin ships no CUE SDK (`research/perses.md` R10).
- Bare `percli lint`: validates nothing beyond unmarshalling and reports success (charter RK8; `research/perses.md` R17).
- `percli lint --plugin.path <store path>`: lint writes the extracted archives into `--plugin.path`, so it needs a writable copy of the archive directory; at 0.54.0 the archive-directory form failed closed on valid files (`research/perses.md` R19, R20).
- `percli lint --online` as the gating regulator: needs a running Perses server inside the check and excludes `--custom-rule.path` (`research/perses.md` R25).
- MySQL or PostgreSQL wire route to the store: the datasources do not use it, and it adds a second listener on the store (`research/perses.md` R31).

## Consequences

Views change only by commit and deploy: a changed file restarts `perses.service` at activation, and a view created by any other route, or whose file was deleted, is gone at the next start.
No reader can create, change or delete a view, datasource or secret, because `readonly` removes the routes and every logged-in person holds only `read`.
Any admitted reader can still send arbitrary PromQL and SQL reads through the two datasources' query paths under `perses:ro`, which is acceptable only because ADR-008 places every admitted human in one read zone and excludes content at the collector.
There is one project, `fleet`, and no per-person read partition.
A PromQL panel reads `fleet`, which its datasource fixes, unless it adds `{__database__="<db>"}`; an SQL panel qualifies each table with its database, as `"devloop"."ci_build"`, and uses no CTE, because a CTE cannot carry a database; the lint rules require the qualification (Q10).
A person removed from `perses_users` keeps an open session for up to 1 h, because a refresh does not consult Kanidm.
The Perses version is this repository's to move: `update.sh` writes the version, hashes and plugin pins together, and `perses-lint`, `perses-config` and the container test run before an upgrade merges.
Perses exits when Kanidm's OIDC discovery fails at start, so `perses.service` restarts every 10 s with no start limit and waits for `kanidm.service`.
`magnetite` runs a second long-running service, bounded at 256 MiB and killed by the kernel after the evaluator and before the store (`OOMScoreAdjust` 900 > 600 > 500); its failures reach `fleet-alerts` through the notifier, and `SystemdUnitFailed` does not see it, because the collector's unit list does not include it.
The views are unavailable whenever the store is, and their queries count against the store's own memory ceiling (ADR-007).
Grafana community dashboards reach the repository only through `percli migrate --online` against a local Perses server, followed by rewriting their datasources to `greptimedb-promql` and `greptimedb-sql`.
The query editor shows no PromQL metric help until GreptimeDB serves `/metadata`, which first ships in the 1.3 line (`research/greptimedb.md` R12).
Log and trace views arrive with S7, which adds their plugins to the curated set; trace panels depend on GreptimeDB's stored trace columns matching the plugin's names (`research/perses.md` R8).
The embedded dashboard remains the operator's tunnelled fallback, and its datasources still take the database from the browser's connection settings.
`sso-gateway` stays disabled, and `openspec/changes/sso-gateway/` keeps its open tasks.

## Operating envelope and regulator

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| `perses-bin` | The archives installed are exactly `passthru.plugins`; `percli version` reports the package version | install check and `versionCheckHook` in `package-perses-bin` | a `plugins` entry in `sources.json` at another version (`logs/cam73-evidence/2.2-package-20261105T003659Z.log`) |
| Resource files | Every file under `modules/nixos/perses/resources/` lints clean at the shipped plugins, under custom rules forbidding `SELECT *`, an unqualified SQL table and any datasource other than `greptimedb-promql` and `greptimedb-sql` | flake check `perses-lint`: `percli lint --plugin.path <writable copy of the curated archives> --custom-rule.path <rules>` over each file | seven mutants (empty `query`, extra field in a query spec, unknown query kind, a `StaticListVariable`, `SELECT *`, an unqualified table, a third datasource), each rejected with its message, and a leg requiring bare lint to accept the extra-field mutant |
| Serving configuration | `flake.lib.persesServingFailures` returns an empty list: loopback listener; read-only, authenticated, no native login or sign-up, secure cookie, session at most 1 h; one OIDC provider on Kanidm's `perses` issuer; secrets only under the credentials directory; loopback proxy networks; guest `read` only; the two datasources' URLs, header, secret, `allowHeaders` and anchored endpoints; no literal password; the vhost's strip and `/metrics` rule; the client scoped to `perses_users`; plugins on disk, the wipe and the memory ceiling | an assertion in `modules/nixos/perses.nix` over magnetite's values, and the flake check `perses-config` over a literal valid input | one mutant per clause, 47 in all (`logs/cam73-evidence/3.2-config-20261105T011100Z.log`) |
| Credentials | `perses-password` loaded only by `perses.service`; every file Perses reads under its credentials directory, outside the Nix store | magnetite's credential-holder assertion; the predicate's clause 4 | an override adding `perses-password` to a second unit (`logs/cam73-evidence/3.5-identity-20261105T010157Z.log`) |
| Runtime read path | Unauthenticated requests refused; writes answer 405; the provisioned set only, a planted view gone after restart; every committed query answers through its datasource; non-query paths refused with 403; a caller's `x-greptime-auth` does not reach the store; `/metrics` 404 through nginx | on-demand container test `vmTests.x86_64-linux.perses-greptimedb` on magnetite, logging in with a test-only native user; evidence only when run | the same request through a test-only datasource without `allowHeaders` reaches the store as `admin`; a view query replaced by a missing metric fails |
| Unit | Under 256 MiB; a failure notified | `MemoryMax`; `OnFailure` from magnetite's `notifiedUnits` | a `SIGKILL` at acceptance on 2026-11-05 posted `FAILED` the same second, and systemd restarted Perses 11 s later |
| Kanidm login | A member of `perses_users` logs in; a person outside it is refused | one recorded login of each kind at first deploy (Q4) | the refusal itself: on 2026-11-05 Kanidm answered the operator's account with Access Denied before it joined, and admitted it after |
| Evaluation cost | Each new check below 0.5 GiB | `NIX_SHOW_STATS=1` before and after | `perses-lint` 100,656,240 B and `perses-config` 101,300,400 B (`logs/cam73-evidence/3.9-costs-20261105T011226Z.log`) |

The embedded dashboard's half of the store-package envelope, `GET /dashboard/` returning 200 on `127.0.0.1:4000`, stays a case of S1's container test under ADR-001 R1.1.

## Failure prevented

- Standalone server with anchored global datasources: an admitted browser reaching store routes beyond the query paths.
- Injected credential, `allowHeaders` and the nginx strip: a store password in browser storage, or a caller's `x-greptime-auth` replacing the proxy's identity.
- `readonly`, guest `read` and the wipe before each start: a view or datasource changed or planted outside review.
- Kanidm client scoped to `perses_users`: a Kanidm account outside the group reading the store.
- Session lifetime of 1 h: a removed member reading indefinitely.
- Lint check with mutants and the bare-lint leg: a schema-invalid view reaching `magnetite` behind a regulator that reports success on everything (RK8).
- Serving predicate with mutants: an unauthenticated or writable server, an unanchored endpoint, a widened scope map or a listener beyond loopback reaching deployment unnoticed.
- On-demand container test: views that lint clean but render empty because a metric or table name is wrong, when the test is run before deploy.
- Memory ceiling and kill order: the dashboard starving the store or the host, which has been OOM-killed twice (RK3).
- Embedded dashboard kept on loopback: no read path for the operator while Perses or Kanidm is down.

## Implementation surface

This surface belongs to slice S6, landed in #3720 and #3721 (`openspec/changes/serve-the-fleet-dashboard/design.md` Layout).

Files added:
- `pkgs/by-name/perses-bin/package.nix`, `sources.json` and `update.sh`: the 0.55.1 release for `x86_64-linux` and `aarch64-darwin`, with `passthru.plugins` and `passthru.pluginsArchive`; `apps.update-perses-bin` in `modules/apps/updates.nix`.
- `modules/nixos/perses.nix`: `services.perses` on `127.0.0.1:8095`, the `obs.scientistexperience.net` vhost, the unit's credentials, memory ceiling, restart and kill-order settings, the wipe, the curated plugin set, and `flake.lib.persesServingFailures` with its assertion.
- `modules/nixos/perses/resources/`: `project.json`, `globalsecret.json`, `globaldatasource-promql.json`, `globaldatasource-sql.json`, `dashboard-fleet-hosts.json` and `dashboard-devloop.json`.
- `modules/nixos/perses/lint-rules.yaml` and `modules/nixos/perses/mutants/*.json`: the custom lint rules and the mutant set.
- `modules/checks/perses-lint.nix` and `modules/checks/perses-config.nix`: the two flake checks.
- `modules/vm-tests/perses-greptimedb.nix` and its test-only provisioning folder: the on-demand container test.

Files modified:
- `modules/nixos/kanidm.nix`: the group stub `perses_users` with `overwriteMembers = false`, the client `systems.oauth2.perses` with display name "Observability", and the generator `kanidm-oauth2-perses`.
- `modules/machines/nixos/magnetite/default.nix`: imports the module, adds the generator `perses-encryption-key`, gives `perses-password` `restartUnits = [ "perses.service" ]`, names `perses` its only holder, and places `perses` in the kill order; `sso.enable` stays false (`modules/machines/nixos/magnetite/default.nix:163`).
- `modules/lib/observability-hosts.nix`: `perses` among magnetite's notified units.
- `modules/terranix/cloudflare.nix`: one unproxied `CNAME` `obs.scientistexperience.net` to `magnetite.scientistexperience.net`, beside `omni`.

Flake inputs: none.

Clan vars generators:
- `kanidm-oauth2-perses` (the client secret, read by Kanidm's provisioning and by Perses) and `perses-encryption-key` (32 bytes), both per machine on `magnetite`.
- The `perses-password` file of ADR-007's `greptimedb-users` generator is loaded by `perses.service` and restarts it.

## Questions for the human gate

Q1 Perses 0.54.0 or the 0.55 line? Recommended: 0.54.0 from the root pin with an upgrade obligation at 0.55.0 final in nixpkgs.
Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11, because no standalone server is deployed and the Perses version follows the dashboard the store embeds; under charter v28 the standalone server runs Perses 0.55.1 from the upstream release as `perses-bin`, not the root pin's 0.54.0.
Q2 Disposition of GreptimeTeam/dashboard? Recommended at the gate: rejected as the dashboard layer and deferred as an exploration console, on the premise that it required a GreptimeDB 1.3 prerelease and a store password held in browser storage.
Resolution: accepted at the 2026-10-15 gate; amended under charter v11, after both premises were found not to hold: GreptimeDB's embedded dashboard is the dashboard layer, per the Decision; under charter v28 the embedded dashboard is the operator's tunnelled fallback, not the dashboard layer.
Q3 Keep a PromQL datasource beside the GreptimeDB datasource? Recommended: yes.
Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the embedded dashboard fixes both datasources, so the answer holds without configuration; under charter v28 the two global datasources `greptimedb-promql` and `greptimedb-sql` keep it.
Q4 Is one recorded manual Kanidm login at first deploy acceptable as the login regulator? Recommended: yes; the alternative is adding a Kanidm node to the container test, which roughly doubles its cost to sample a path exercised once per login.
Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the login is the gateway's, recorded once for a member and once for a non-member; under charter v28 the login is Perses' own Kanidm client, and on 2026-11-05 Kanidm refused the operator's account with Access Denied before it joined `perses_users` and admitted it after.
Q5 Is an on-demand, non-gating runtime test the right home for the data-path regulator? Recommended: yes, under `modules/vm-tests/` per `modules/README.md:32`, `:86`, with the gating set the lint and configuration checks.
Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the test is an nspawn container test in the lane S1 establishes, rather than a QEMU VM test.
Q6 Public hostname behind Kanidm, or a mesh-only `.zt` vhost? Recommended: public `perses.scientistexperience.net` behind Kanidm.
Resolution: perses.scientistexperience.net behind Kanidm, accepted at the 2026-10-15 gate; under charter v11 Kanidm admits through `sso-gateway`; under charter v28 the operator renamed it `obs.scientistexperience.net`, behind Perses' own Kanidm client, with the group keeping the name `perses_users`.
Q7 Plugin subset of ten? Recommended: yes, at an envelope of 96 MiB.
Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11, because the embedded dashboard compiles its plugins into the store binary and extracts nothing to a tmpfs; under charter v28 seven archives (Prometheus, GreptimeDB, TimeSeriesChart, StatChart, GaugeChart, Table and Markdown) unpack to 63 MiB on disk, inside the unit's 256 MiB ceiling.
Q8 Plain resource YAML as the dashboards-as-code format? Recommended: yes.
Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11 by Perses `Dashboard` JSON reconciled through `/v1/dashboards`, because the embedded dashboard has no resource provisioning; under charter v28 Perses resource JSON provisioned from committed files, with the file database removed before each start.
Q9 Which `rw` store credential does the reconcile oneshot hold? Options: the existing `admin` user, which ADR-007 restricts to the schema and export oneshots; a fifth `rw` user for the oneshot alone; or folding the reconcile into `greptimedb-schema`, which already holds `admin`.
Resolution: dissolved under charter v28: no reconcile oneshot exists, provisioning reads committed files, and no unit gains a store write credential.
Q10 How does a dashboard select among `fleet`, `devloop` and `agent`, given that both datasources take the database from the browser's connection settings? SQL panels can qualify table names with the database; PromQL panels cannot, so options include nginx setting `x-greptime-db-name` per location, restricting PromQL panels to one database, or the standalone-server fallback.
Resolution: answered under charter v28: each datasource's proxy sets `x-greptime-db-name: fleet`, which a reader cannot change; a PromQL panel reading another database adds `{__database__="<db>"}`, and an SQL panel qualifies each table, as `"devloop"."ci_build"`, which the lint rules require.
