---
title: "perses"
---

## Purpose

The dashboard layer is the Perses dashboard GreptimeDB embeds: it renders metrics, logs and traces from the store for admitted humans (ADR-002 Decision).
No standalone Perses server is deployed; standalone Perses is used only as tooling, `percli lint` as a flake check and `percli migrate` to convert Grafana dashboards (ADR-002 Decision).
The dashboard is the only read path for humans into the store (ADR-008 Readers and admission item 1).
Its dashboards are Perses `Dashboard` JSON files committed to this repository and reconciled into the store through `/v1/dashboards`, so a commit and a deploy are the only way a dashboard changes (ADR-002 Decision, Consequences).

## Decisions realized

- ADR-002 Decision: the dashboard is the one `greptimedb-bin` embeds, GreptimeTeam/dashboard `v0.13.13` running Perses 0.53.1 at GreptimeDB `v1.2.1`, served by `greptimedb.service` at `/dashboard/`.
- ADR-002 Decision and Q3: the datasources are the embedded dashboard's fixed `promql-default`, a `PrometheusDatasource` at `/v1/prometheus`, and `sql-default`, a `GreptimeDBDatasource` posting to `/v1/sql`.
- ADR-002 Decision and Q8: the dashboards-as-code format is Perses `Dashboard` JSON, reconciled by the oneshot `perses-dashboards.service`, which posts every repository file and deletes every stored dashboard absent from the repository.
- ADR-002 Decision: the regulator for the files is the flake check `perses-lint`, running `percli lint` against the Perses and plugin versions the store embeds, with `--custom-rule.path`, asserting that every enumerated mutant is rejected.
- ADR-002 Decision: a standalone Perses server is the fallback only if a dashboard needs a feature the embedded dashboard lacks, such as `StaticListVariable` or projects with RBAC.
- ADR-002 Q5: the data-path regulator is an on-demand, non-gating container test under `modules/vm-tests/`.
- ADR-002 Decision, Q4 and Q6: the dashboard is served at `perses.scientistexperience.net`, a `magnetite` vhost registered with `sso-gateway` that admits the Kanidm group `perses_users`, with one recorded manual login of a member and of a non-member at first deploy as the login regulator.
- ADR-002 Decision: nginx proxies `/dashboard/` and `/v1/` to the store's API listener `127.0.0.1:4006` and overwrites `Authorization` with the `perses:ro` Basic credential.
- ADR-002 Decision: slice S1 exposes nothing publicly, and the dashboard is reachable from S1's first deployment through `ssh -L 4000:127.0.0.1:4000 magnetite.zt`.
- ADR-002 Q9 and Q10: the reconcile oneshot's `rw` credential holder and the way a dashboard selects its database are open and decided in S6.
- ADR-008 Q1 and Readers and admission item 3: every admitted person reads every stored signal, because the store holds no content and no person identifier.
- ADR-008 Readers and admission item 2: readers hold only `perses:ro`, so the store rejects their saves and deletes.
- ADR-008 Q2: Cameron is admitted to `perses_users` first, and Janette when she chooses.
- ADR-007 Decision (credentials): the `perses` store user is `ro` and is held only by nginx from S6.
- ADR-001 R1.1: the store package must embed the dashboard, so the dashboard exists from S1's first deployment.

The human gate of 2026-10-15 accepted the recommended answer of every ADR-002 and ADR-008 question listed above, and charter v11 amended ADR-002 to the embedded dashboard.

## Placement

- Host: `magnetite` (ADR-002 Decision; ADR-007 Decision).
- Unit: the dashboard is served by `greptimedb.service`; no dashboard unit exists, and the reconcile oneshot is `perses-dashboards.service` (ADR-002 Implementation surface).
- Listeners: the main HTTP listener `127.0.0.1:4000` from S1, and from S6 the API listener `127.0.0.1:4006`, enabled by `http.enable_api_server = true`, which serves only `/v1` and `/dashboard` (ADR-002 Context, Decision).
- Vhost: `perses.scientistexperience.net`, the `forceSSL` and `enableACME` nginx vhost that `sso-gateway` emits for the registration `sso.services.perses` (ADR-002 Implementation surface).
- Store account: the GreptimeDB user `perses` with mode `ro`, injected by nginx (ADR-007 Decision).
- Identity: the Kanidm group `perses_users`, which the gateway derives from `allowedGroups` with membership managed in the running Kanidm database rather than in the repository (ADR-008 Consequences; `modules/nixos/sso-gateway.nix:459-476`).
- Dashboard storage: the table `greptime_private.dashboard` in the store, keyed by dashboard name (ADR-002 Context).
- No worker account and no worker-run process holds the `perses` credential (ADR-008 Readers and admission item 5).

## Interfaces

- Downstream (browsers): HTTPS at `perses.scientistexperience.net`, a public `magnetite` vhost reached through one unproxied Cloudflare `CNAME` to `magnetite.scientistexperience.net` (ADR-002 Decision, Implementation surface).
- Identity provider: the shared oauth2-proxy of `sso-gateway` at `auth.scientistexperience.net`, consulted by nginx `auth_request` on every request to the vhost (`modules/nixos/sso-gateway.nix:80-96`).
- Upstream (store): `/dashboard/` and `/v1/` proxied to `http://127.0.0.1:4006` with `Authorization` overwritten by the `perses:ro` Basic credential (ADR-002 Decision).
- Query paths from the browser: `promql-default` queries `/v1/prometheus`, and `sql-default` posts SQL to `/v1/sql`; both send `x-greptime-db-name` from the browser's connection settings (ADR-002 Context).
- Query kinds: PromQL, and the GreptimeDB plugin's time-series, log and trace queries rendered by the TimeSeries, LogsTable, TraceTable and TracingGantt panels (ADR-002 Context, Rationale).
- Write path: the reconcile oneshot calls `GET /v1/dashboards`, `POST /v1/dashboards/{name}` with body `{"content": <dashboard JSON as a string>}`, and `DELETE /v1/dashboards/{name}` on `127.0.0.1:4000` with a `rw` credential (ADR-002 Context, Decision, Q9).
- Operator access in S1: `ssh -L 4000:127.0.0.1:4000 magnetite.zt`, then `/dashboard/` on the forwarded port (ADR-002 Decision).
- Store upstream of the dashboard: `components/greptimedb.md`.
- Credentials consumed:
  - Store password for readers: the `perses-password` file of ADR-007's `greptimedb-users` generator, mode `0400`, read by nginx outside the Nix store, with `restartUnits = [ "nginx.service" ]` from S6 (ADR-002 Implementation surface; ADR-007 Decision).
  - Store password for the reconcile oneshot: open (ADR-002 Q9).
- Known interface limit: GreptimeDB serves no Prometheus `/metadata` route at 1.1.4 or 1.2.1, so the query editor shows no PromQL metric help until the 1.3 line (ADR-002 Consequences).
- Known interface limit: any admitted reader can send arbitrary SQL and PromQL to the store's `/v1` routes under `perses:ro`, which ADR-008 accepts because every admitted human is in one read zone and content is excluded at the collector (ADR-002 Consequences).
- Known interface limit: a PromQL panel reads the database set in the reader's connection settings, not one the dashboard file names (ADR-002 Consequences, Q10).

## Configuration surface

Files to add in S6 (ADR-002 Implementation surface):

- `modules/nixos/perses.nix`: the `sso.services.perses` registration with `allowedGroups = [ "perses_users" ]` and `upstream` mapping `/dashboard/` and `/v1/` to `http://127.0.0.1:4006`, the `Authorization` overwrite on those locations, `services.greptimedb.settings.http.enable_api_server = true`, `perses-dashboards.service` with `OnFailure=observability-notify@%n.service`, and the evaluation-time assertions.
- `modules/nixos/perses/dashboards/*.json`: the Perses `Dashboard` JSON files.
- `modules/nixos/perses/lint-rules.yaml` and `modules/nixos/perses/mutants/*.json`: the custom lint rules and the enumerated mutant set.
- `modules/checks/perses-lint.nix`: the lint check with its valid and mutant legs and the tooling-version assertion.
- `modules/checks/perses-config.nix`: the serving-configuration mutant check.
- `modules/vm-tests/perses-greptimedb.nix`: the on-demand container test, in the shape of S1's `modules/vm-tests/greptimedb-pipeline.nix`.
- `percli` and plugin archives at the embedded dashboard's versions for the lint check, or evidence from the mutant legs that the root pin's `percli` 0.54.0 discriminates the same set.

Files to modify in S6:

- `pkgs/by-name/greptimedb-bin/package.nix`: `passthru.dashboardVersion`, beside S1's `passthru.embedsDashboard` (ADR-002 Implementation surface; ADR-001 R1.1).
- `modules/machines/nixos/magnetite/default.nix`: import the dashboard module and enable `sso-gateway`, which is disabled today (ADR-002 Implementation surface).
- `modules/terranix/cloudflare.nix`: one `CNAME` `perses.scientistexperience.net` to `magnetite.scientistexperience.net`, unproxied, mirroring the `omni` record (ADR-002 Implementation surface).
- No change to `modules/nixos/kanidm.nix`, because the gateway derives the group stub and scope map (ADR-002 Implementation surface).

Flake inputs: none (ADR-002 Implementation surface).

Clan vars generators:

- None created here.
- Consumed: `greptimedb-users` `perses-password` by nginx (ADR-007 Implementation surface), and the reconcile credential that ADR-002 Q9 selects.

## Operating envelope and regulator

The envelopes and regulators below are ADR-002's, and ADR-008 assigns the dashboard layer's own configuration regulator to ADR-002 (ADR-008 Operating envelope and regulator).

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| Dashboard files | Every file lints clean against the Perses version and plugin set the deployed store embeds, and against custom rules forbidding `SELECT *` and any datasource name other than `promql-default` and `sql-default` | flake check `perses-lint`: `percli lint --plugin.path <extracted plugins> --custom-rule.path <rules>` over each file; deterministic, nixbot `x86_64-linux` | an enumerated mutant set (empty `query`, extra field in a query spec, unknown query kind, a `StaticListVariable`, `SELECT *`, a third datasource name) each of which must exit non-zero, plus the valid set which must exit zero |
| Lint tooling version | The lint tooling's Perses and plugin versions equal those of the dashboard the store package embeds | evaluation-time assertion in `perses-lint` against `greptimedb-bin`'s `passthru.dashboardVersion` | a mutant setting `passthru.dashboardVersion` to `v0.14.2` must fail |
| Serving configuration | API server enabled on loopback; vhost registered with `allowedGroups = [ "perses_users" ]`; `/dashboard/` and `/v1/` proxy to the API listener and overwrite `Authorization`; no other location proxies to the store | evaluation-time assertions plus the mutant check `perses-config` in the shape of `cameronraysmith/vanixiets@a8e72d185:modules/checks/omnigent-environment.nix:98-118` | each named mutant (API server off, API listener on `0.0.0.0`, `allowedGroups` empty, a location proxying to `127.0.0.1:4000`, the `Authorization` override removed) must produce a non-empty failure list |
| Reconciled dashboard set | After each run, the stored names equal the repository's file names, and each stored definition equals its file | `perses-dashboards.service` re-reads the list and exits non-zero on any difference, notifying through `observability-notify@` | the container test seeds an extra stored dashboard and an altered definition and asserts both are corrected, and that a forced difference exits non-zero |
| Data path, vhost to store | Through nginx with the injected credential, `/dashboard/` returns 200, one PromQL, one SQL time-series, one log and one trace query each return rows, and a dashboard `POST` is refused | on-demand container test `vmTests.x86_64-linux.perses-greptimedb`, with the gateway's `auth_request` stubbed | a query against a nonexistent table must be rejected and the refused `POST` must leave the stored set unchanged; because it does not gate, this row is evidence only when run |
| Kanidm login through the gateway | A member of `perses_users` logs in and an authenticated non-member is refused | one recorded manual login of each kind at first deploy (ADR-002 Q4) | not shown; this row is the incomplete regulator R5 requires ADR-002 to name |

The store-package half of this envelope, `GET /dashboard/` returning 200 on `127.0.0.1:4000`, is a case of S1's container test under ADR-001 R1.1 (`components/greptimedb.md`).
The gating regulators are `perses-lint` and `perses-config`; the data path from vhost to panel is sampled by no gating check (ADR-002 Rationale, Consequences).

## Failure prevented

These are ADR-002's Failure prevented entries.

- Embedded dashboard: a GreptimeDB store whose logs and traces nobody can see, which is charter RK7, without a second service on a memory-constrained host (RK3).
- Reconcile oneshot with deletion: dashboards drifting from the repository through saves that no review sees.
- `perses:ro` for readers: a reader deleting or overwriting a dashboard.
- Credential overwrite at nginx: a store password persisted in browser storage on readers' machines.
- API listener as the upstream: store routes beyond `/v1` and `/dashboard` reachable from the public vhost.
- Lint check with mutants: a schema-invalid dashboard reaching `magnetite` behind a regulator that reports success on everything (RK8).
- Lint tooling version assertion: a lint that passes files the deployed renderer's Perses version rejects.
- Configuration assertions with mutants: an unauthenticated vhost, a vhost admitting every Kanidm user, or a listener beyond loopback reaching deployment unnoticed.
- On-demand container test: dashboards that lint clean but render empty because a table or column name is wrong, when the test is run before deploy.
- `sso-gateway` admission: a second Kanidm client and a second login surface for one more `magnetite` UI.

## Deployment acceptance items

- S1: through `ssh -L 4000:127.0.0.1:4000 magnetite.zt`, `/dashboard/` loads on the forwarded port (ADR-002 Decision; ADR-001 R1.1).
- S6: one recorded manual login of a `perses_users` member succeeds and one of an authenticated non-member is refused (ADR-002 Q4, Operating envelope).
- S6: the browser holds no store password after login, and a save attempted in the UI fails (ADR-002 Consequences).
- S6: `perses-dashboards.service` exits successfully on first activation and the stored list equals the repository's files (ADR-002 Operating envelope).
- Trace panels depend on GreptimeDB's stored trace columns matching the plugin's names, which only the on-demand container test samples (ADR-002 Consequences; charter RK7 residual).
- Log and trace rendering has not been exercised against a live GreptimeDB (charter RK7 residual).
- S6 enables `sso-gateway` on `magnetite`, which also activates the services already registered with it (ADR-002 Consequences).
- Cameron is added to `perses_users` operationally, outside the repository (ADR-008 Q2, Consequences).

## Deferred

- Standalone Perses server: deployed only if a dashboard needs a feature the embedded dashboard lacks, such as `StaticListVariable` or projects with RBAC (ADR-002 Decision).
- Perses 0.54.0 in the dashboard: arrives when a stable GreptimeDB release embeds dashboard `v0.14.2`, and moves the lint tooling in the same commit (ADR-002 Consequences).
- PromQL metric help in the query editor: arrives when GreptimeDB serves `/metadata`, which first ships in the 1.3 line (ADR-002 Consequences).
- Reconcile credential holder and per-dashboard database selection: decided in S6 (ADR-002 Q9, Q10).
- Admission of Janette to `perses_users`: when she chooses (ADR-008 Q2).
