---
title: "ADR-002: Dashboard layer"
---

## Status

Proposed

## Context

Charter D2 asks for one dashboard layer, its dashboards-as-code format, and datasource reachability against the chosen store.
The human gate of 2026-10-06 named GreptimeDB on `magnetite` backed by Cloudflare R2 as the store, and GreptimeTeam/dashboard "or better" as the dashboard layer, with Perses the leading "or better" candidate.
This ADR assumes the store decision of ADR-001 and the placement of ADR-007: GreptimeDB 1.2.1 standalone on `magnetite`, consumed as `pkgs.greptimedb` from the root pin, listening for HTTP on `127.0.0.1:4000` (ADR-007), with the read-only `perses` user that ADR-007 enumerates among the store users.
This ADR assumes the access model of ADR-008: content exclusion at the collector, one shared read zone of admitted humans, no per-person read partition, and a direct Kanidm OIDC client for the dashboard; the store users, including `perses:ro`, are those enumerated in ADR-007.

The facts that bind this decision are these.
The root pin is lock node `nixpkgs_10` at `NixOS/nixpkgs@ac1faec4`, and it packages Perses 0.54.0, the latest stable upstream release, together with the NixOS module `services.perses` (`research/perses.md` R11, R13; `research/nix-packaging-status.md` R13).
The vendored plugin set at that pin contains the native GreptimeDB plugin at 0.1.0 (`NixOS/nixpkgs@ac1faec4:pkgs/by-name/pe/perses/plugins.nix:34-36`, root node `nixpkgs_10`).
That plugin declares `GreptimeDBDatasource`, `GreptimeDBTimeSeriesQuery`, `GreptimeDBLogQuery` and `GreptimeDBTraceQuery`, the last two of the generic `LogQuery` and `TraceQuery` kinds, so the stock `LogsTable`, `TraceTable` and `TracingGanttChart` panels render them (`perses/plugins@a62049f:greptimedb/package.json:50-77`; `research/perses.md` R5, R6).
Every GreptimeDB query is SQL sent as `POST <datasource url>/v1/sql` through the server-side `HTTPProxy` (`perses/plugins@a62049f:greptimedb/src/model/greptimedb-client.ts:89`; `research/perses.md` R7, R31).
The stock Prometheus plugin also reaches GreptimeDB's PromQL router at `/v1/prometheus` (`research/perses.md` F20), except that the Prometheus `/metadata` route is absent at GreptimeDB 1.1.4 and 1.2.1 (`research/greptimedb.md` R12).
RK7 therefore does not fire for a design that names the GreptimeDB plugin at 0.1.0, with the residual that trace rendering depends on stored column names matching the plugin's heuristics (`research/perses.md` R8 and its Reconciliation section).

The 0.55 line is at `v0.55.0-rc.0` and is not in nixpkgs (`research/perses.md` R1).
It carries five security changes absent from 0.54.0 (`research/telemetry-security-and-tenancy.md` R13 through R18): the proxy stops forwarding the caller's Perses session token (`perses/perses@835dc355`), auth without an encryption key becomes a startup error (`perses/perses@e799e7cb`), secret files are confined to allowed directories (`perses/perses@bb8fd345`), a connect-time network guard denies loopback, link-local and metadata targets by default (`perses/perses@d5cbc44e`), and the SQL proxy runs read-only (`perses/perses@379673eb`).
It also adds `provisioning.enable_watch` and claim-based role assignment, both absent from 0.54.0 (`research/perses.md` R15).

GreptimeTeam/dashboard is a Vue application served by GreptimeDB at `:4000/dashboard` whose "Visualization" section embeds Perses 0.54.0 with the GreptimeDB plugin and stores Perses `Dashboard` JSON in GreptimeDB through `/v1/dashboards` (`research/perses.md` R36 through R38).
That API first appears in GreptimeDB `v1.3.0-alpha.1`, and the UI is compiled only with the `servers/dashboard` Cargo feature, which the nixpkgs derivation does not enable (`research/perses.md` R39, R40; `research/nix-packaging-status.md` R9, R11).
It authenticates with HTTP Basic credentials typed into the browser and persists the password in `localStorage`, with no OIDC, no project model and no RBAC (`research/perses.md` R41).
It has no CLI, no lint, no file provisioning and no read-only mode (`research/perses.md` R44).
At the definition level it is not an alternative to Perses, because both render the same Perses dashboard JSON through the same GreptimeDB plugin (`research/perses.md` R45).

`percli lint` is tautologically green without plugin schemas (charter RK8; `research/perses.md` R17, R18).
With `--plugin.path` pointed at the archive directory it fails closed on every input because of the `ArchivePath`/`ArchivePaths` mismatch (`research/perses.md` R19, R20).
With `--plugin.path` pointed at a directory of extracted plugins, or with `--online`, it rejects schema mutants and custom-rule mutants while accepting valid files (`research/perses.md` R21, R22, R24).

The nixpkgs package extracts every vendored plugin archive into `/run/perses/plugins` on a tmpfs, about 260 MiB at 0.54.0 (`NixOS/nixpkgs@ac1faec4:nixos/tests/perses.nix:15-17`, root node `nixpkgs_10`).
Extracting the 30 vendored archives of the root pin measured 257 MiB, and the ten-plugin subset named below measured 84 MiB, each plugin between 2 MiB and 11 MiB (local extraction of `perses.pluginsArchive` from root node `nixpkgs_10`, 2026-10-15).
`plugin.enabled` filters plugins at load time only; `UnzipArchives` extracts every archive found under `archive_paths` regardless (`perses/perses@4c719fc1:internal/api/plugin/plugin.go:72`, `perses/perses@4c719fc1:internal/api/plugin/plugin.go:283-296`).
`magnetite` has 30.6 GiB of RAM and was OOM-killed twice by overlapping evaluations (`cameronraysmith/vanixiets@a8e72d185:docs/notes/development/incidents/2026-10-01-magnetite-concurrent-eval-oom.md:5`, `:12`), which is charter RK3.

## Decision

The dashboard layer is Perses 0.54.0 from the root nixpkgs pin, run through `services.perses` on `magnetite`, with the GreptimeDB plugin 0.1.0 as its primary datasource.
Two datasources, both proxied server-side with the `perses:ro` credential to `http://127.0.0.1:4000`, are declared in one Perses project: a `GreptimeDBDatasource` for SQL time series, logs and traces, and a `PrometheusDatasource` at `/v1/prometheus` for PromQL metric panels.
The dashboards-as-code format is plain Perses resource YAML (`Project`, `Datasource`, `Secret`, `Dashboard`, `Role`, `RoleBinding`) committed to this repository and provisioned from a Nix store path, with `security.readonly: true` so that provisioning is the only write path.
The plugin set is a first-party archive subset of ten vendored plugins wired through `plugin.archive_paths`: `GreptimeDB`, `Prometheus`, `TimeSeriesChart`, `Table`, `StatChart`, `LogsTable`, `TraceTable`, `TracingGanttChart`, `Markdown` and `StaticListVariable`.
The regulator for the resource files is a flake check that runs `percli` 0.54.0 `lint` with `--plugin.path` pointed at a Nix-extracted directory of exactly that subset and with `--custom-rule.path`, and that also asserts every enumerated mutant is rejected.
Authentication is a direct Kanidm OIDC client using the authorization-code flow with PKCE, which is on by default at 0.54.0.
GreptimeTeam/dashboard is rejected as the dashboard layer and deferred, not deployed, as an exploration console.
The upgrade to the 0.55 line is a recorded obligation, triggered when Perses 0.55.0 final reaches the root pin.

## Rationale

Perses 0.54.0 is the only candidate that satisfies all three D2 conditions at the root pin without packaging work: it renders metrics, logs and traces from GreptimeDB (`research/perses.md` R5, R6, R12), its definitions are files that a server-free regulator can discriminate (`research/perses.md` R21), and it has a module whose freeform `settings` and `_secret` credential substitution cover every configuration value this ADR needs (`research/perses.md` R13).
The GreptimeDB plugin is the primary datasource because it is the only packaged path to logs and traces, and because the plugin's history between 0.1.0 and `0.2.0-rc.0` shows framework changes only, so staying on 0.1.0 forgoes no query semantics (`research/perses.md` R9).
The Prometheus datasource is retained because the fleet's existing emitters are Prometheus `/metrics` endpoints (charter W3), PromQL expresses counter rates over them directly, and GreptimeDB serves PromQL on every path the plugin uses except `/metadata`, whose absence degrades only the query editor's metric help (`research/perses.md` F17 through F20; `research/greptimedb.md` R12).
Plain resource YAML is the as-code format because it is what the server, the provisioning loader, `percli lint` and the GreptimeTeam dashboard skill all consume directly (`research/perses.md` F4, F24; R43), so it adds no build step between the reviewed file and the deployed resource.
The Go SDK is not chosen because it adds a Go module and a `dac build` step whose only output is the same YAML, and the CUE SDK is not chosen because the GreptimeDB plugin ships no CUE SDK (`research/perses.md` R10).
`security.readonly: true` with Nix-store provisioning gives a declarative-only deployment: provisioning writes through the service manager and is unaffected by the switch, while every resource POST, PUT and DELETE route is removed (`research/perses.md` F25 through F27; `perses/perses@4c719fc1:internal/api/generate.go:80`).
The proxy routes are not resource routes, so read-only mode does not stop dashboards from querying (`perses/perses@4c719fc1:internal/api/generate.go:80`, which gates only the generated resource endpoints).

Perses 0.54.0 is chosen over the 0.55 line because each of the five 0.55 security changes is either compensated by this configuration or does not apply to it.
The session-token forward does not reach GreptimeDB in the `Authorization` header, because the datasource `Secret` carries `basicAuth` and `setupAuthentication` calls `SetBasicAuth`, which replaces that header (`perses/perses@4c719fc1:internal/api/impl/proxy/proxy.go:369-375`); whether the session cookies are also forwarded is not established, and their only receiver is the loopback GreptimeDB on the same host `[INFERENCE]`.
The default encryption key is excluded by setting `security.encryption_key` from a clan vars secret and asserting it at evaluation time, which is the requirement 0.55 enforces at startup (`research/telemetry-security-and-tenancy.md` C4).
Secret-file exfiltration and arbitrary proxy targets both require creating a `Secret` or a `Datasource`, which read-only mode removes for every caller, and no role binding grants `create` on either scope (`research/perses.md` R30; `research/telemetry-security-and-tenancy.md` R12).
The SQL proxy fix does not apply, because no plugin declares `SQLProxy` and the GreptimeDB plugin uses `HTTPProxy` (`research/perses.md` R31).
`provisioning.enable_watch` buys nothing under Nix, because the provisioning folder is a store path inside the generated configuration file passed on `ExecStart`, so any dashboard change changes the unit and restarts it on activation (`NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/perses.nix:81-85`, root node `nixpkgs_10`).
Claim-based roles would remove two explicit role bindings, but they snapshot claims at login and do not revoke on group removal until the refresh chain ends (`research/perses.md` R35), which is not an improvement for a two-person read zone.
The 0.55 network guard denies the loopback target this ADR uses, so adopting it requires `datasource.proxy.allowed_hosts` naming the store address and `allowed_networks` containing `127.0.0.1/32` only (`research/perses.md` R32; `research/telemetry-security-and-tenancy.md` R17).
Adopting 0.55 now would mean a first-party override of a release candidate, its npm and Go vendor hashes, and a re-vendored plugin set at `0.2.0-rc.0`, which is packaging work on the critical path for no capability this design uses.

The plugin subset exists because extraction is all-or-nothing per archive directory and `plugin.enabled` does not reduce it, so the only lever on the tmpfs footprint is which archives `archive_paths` names (`perses/perses@4c719fc1:internal/api/plugin/plugin.go:72`).
The same subset feeds the lint regulator, so the plugins the server loads and the schemas the check validates against cannot drift apart.

The regulator is offline lint over an extracted directory rather than `--online`, because the offline form runs inside `nix flake check` on nixbot's `x86_64-linux` builders with no running server, and because `--online` and `--custom-rule.path` are mutually exclusive, which would move the custom rules into server configuration (`research/perses.md` R25).
Offline lint does not parse SQL, check table existence or check datasource existence (`research/perses.md` R26), so a NixOS VM test samples the data path that lint cannot.

GreptimeTeam/dashboard is rejected as the dashboard layer because it fails every D2 and D8 condition this ADR depends on: no as-code path, no regulator surface, Basic credentials stored in the browser, and no authorization of its own over an allow-all store (`research/perses.md` R41, R44; charter RK9).
It is deferred rather than rejected outright as an exploration console, because it is actively maintained and offers SQL, PromQL, log and trace exploration that Perses' explore view only partly covers (`research/perses.md` R42, R46).
Deploying it would need GreptimeDB at or above `v1.3.0-alpha.1` built with `servers/dashboard` from pre-fetched assets, or a separately served `build.tar.gz`, plus a read-capable store credential held in a browser (`research/nix-packaging-status.md` R11, R12), and ADR-001 deploys neither that version nor that feature.

## Rejected alternatives

- GreptimeTeam/dashboard as the dashboard layer: no dashboards-as-code, lint or provisioning, store password in browser `localStorage`, no RBAC or OIDC, and absent from the nixpkgs GreptimeDB build (`research/perses.md` R40, R41, R44).
- Perses 0.55 line now: release candidate absent from nixpkgs whose security changes this configuration compensates, at the cost of first-party packaging on the critical path (Rationale above).
- Grafana 13.1.1: packaged with a module, but AGPL under a single corporate sponsor (C3), with no first-party GreptimeDB log or trace datasource evidenced in this corpus and a dashboard JSON format that is not the one GreptimeDB's own tooling emits (`research/store-alternatives.md` F18, F22; `research/perses.md` R43).
- Prometheus datasource only: no path to logs or traces from GreptimeDB, which re-fires RK7 (`research/perses.md` F41, C1).
- GreptimeDB datasource only: forces PromQL-native counter-rate panels over the fleet's Prometheus endpoints into hand-written SQL for no saving in credentials or hosts.
- Go dashboards-as-code SDK: adds a Go module and a build step whose output is the YAML this ADR commits directly.
- CUE dashboards-as-code SDK: the GreptimeDB plugin ships no CUE SDK, and the CUE builders require the `explicitopen` experiment (`research/perses.md` R10, F10).
- Dashboards authored in the UI and exported: exports embed server-assigned metadata and bypass review (`research/perses.md` F5).
- Bare `percli lint`: validates nothing beyond unmarshalling and reports success (charter RK8; `research/perses.md` R17).
- `percli lint --plugin.path <archive directory>`: fails closed on valid files, so it does not discriminate (`research/perses.md` R19, R20).
- `percli lint --online` as the gating regulator: needs a running server inside the check and excludes `--custom-rule.path` (`research/perses.md` R25).
- Full vendored plugin set on `magnetite`: 257 MiB of tmpfs against 84 MiB for the subset, under RK3.
- `plugin.enabled` as the footprint lever: it filters loading only, after every archive is extracted (`perses/perses@4c719fc1:internal/api/plugin/plugin.go:283-296`).
- `sso-gateway` in front of Perses: double-gates a service with native OIDC and disables the RBAC that gates the datasource proxy (`research/telemetry-security-and-tenancy.md` F16, F19, F20).
- Browser `directUrl` datasources: expose the store credential and the store endpoint to the browser (`research/perses.md` F16, F34).
- MySQL or PostgreSQL wire route through `SQLProxy`: no plugin declares it, and it adds a second listener on the store (`research/perses.md` R31).

## Consequences

Dashboards change only by commit and deploy; nobody, including the operator, edits a dashboard in the UI.
A dashboard edit restarts `perses.service` on activation, which re-extracts the 84 MiB plugin subset.
Role bindings must name the two admitted users explicitly, because claim-based roles do not exist at 0.54.0 (`research/perses.md` R15).
A role binding's role is immutable after creation (`research/perses.md` F32), so changing a provisioned binding's role requires renaming the binding resource.
No Perses user holds `create` on `Datasource` or `Secret`, so ad hoc datasources are impossible by design.
Any dashboard reader can send arbitrary SQL to GreptimeDB under the `perses:ro` credential (`research/perses.md` R29), which is acceptable only because ADR-008 places every admitted human in one read zone and excludes content at the collector.
The query editor shows no PromQL metric help until GreptimeDB serves `/metadata`, which first ships in the 1.3 line (`research/greptimedb.md` R12).
Trace panels depend on GreptimeDB's stored trace columns matching the plugin's names, which the VM test samples and which a store upgrade that changes the trace pipeline can break (`research/perses.md` R8).
OIDC against Kanidm has not been exercised live; PKCE is on by default and the OIDC client adopts the provider's advertised signing algorithms, so ES256 tokens are expected to verify `[INFERENCE]` (`research/perses.md` R34).
The 0.55 upgrade will require `datasource.proxy.allowed_hosts` and a `/32` loopback entry in `allowed_networks`, an extension of `secret_file_allowed_directories` to the credentials directory, and the GreptimeDB plugin at `0.2.0` or later.

## Operating envelope and regulator

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| Perses resource files | Every file under the resource tree lints clean against the ten-plugin subset at the versions the root pin vendors, and against custom rules forbidding `SELECT *` and any datasource name outside the two declared ones, each rule targeting a scalar (`research/perses.md` R23) | flake check `perses-resources`: `percli lint --plugin.path <extracted subset> --custom-rule.path <rules>` over each file; deterministic, nixbot `x86_64-linux` | an enumerated mutant set built in the same derivation (empty `query`, extra field in a query spec, unknown query kind, `SELECT *`) each of which must exit non-zero, plus the valid set which must exit zero, so both the tautological pass of RK8 and the fail-closed archive form of R19 turn the check red |
| Perses service configuration | `security.enable_auth` true, `authorization.guest_permissions` empty, `security.readonly` true, `security.encryption_key` from a secret, `listenAddress` `127.0.0.1`, `plugin.archive_paths` exactly the subset, no `GlobalRoleBinding` granting `create` or `*` on `Datasource` or `Secret` | evaluation-time assertions in the Perses module, plus a mutant check in the shape of `cameronraysmith/vanixiets@a8e72d185:modules/checks/omnigent-environment.nix:98-118` | each named mutant (auth off, guest read granted, readonly off, key unset, listener `0.0.0.0`, full plugin set) must produce a non-empty failure list, or the check fails with "accepted a policy mutant" |
| Data path, store to panel | One provisioned time-series, log and trace query each returns at least one row through the Perses proxy over loopback with the `ro` credential, a resource `POST` returns 405 or 404, and `/run/perses/plugins` stays at or below 96 MiB | NixOS VM test `perses-greptimedb` on `x86_64-linux`: GreptimeDB plus Perses, OTLP samples written with the `wo` credential, queries issued through `/proxy/projects/<project>/datasources/<name>` | the same test issues one query against a nonexistent table and one write through the `ro` credential and asserts both are rejected, so a probe that cannot see failures turns the test red |
| Kanidm OIDC login | Login via Kanidm completes and yields a Perses session holding only the provisioned read role | one recorded manual login at first deploy, carried as Q4 because no automated regulator over a live Kanidm exists in this repository | not shown; this row is the incomplete regulator R5 requires this ADR to name |

The 96 MiB bound is the measured 84 MiB subset plus headroom for plugin patch releases; a plugin added to the subset must raise the bound in the same commit.

## Failure prevented

- Perses itself: a GreptimeDB store whose logs and traces nobody can see, which is charter RK7.
- GreptimeDB plugin: the same RK7 failure for logs and traces, which the Prometheus plugin alone leaves open.
- Prometheus datasource: fleet counter panels whose rates are hand-written in SQL and silently wrong across counter resets `[INFERENCE]`.
- Committed resource YAML with read-only provisioning: dashboards and datasources drifting from the repository through UI edits that no review sees.
- Plugin subset: 173 MiB of avoidable tmpfs on a host already OOM-killed twice (RK3).
- Lint check with mutants: a schema-invalid dashboard reaching `magnetite` behind a regulator that reports success on everything (RK8).
- Configuration assertions with mutants: guests reading every project, a default encryption key, or a listener beyond loopback reaching deployment unnoticed (`research/perses.md` R33, F36).
- VM test: dashboards that lint clean but render empty because a table or column name is wrong (`research/perses.md` R8, R26).
- Direct Kanidm client: a second identity store, and the shared-secret blast radius of the gateway (`research/telemetry-security-and-tenancy.md` F17).
- Not deploying GreptimeTeam/dashboard: a store password persisted in browser storage on laptops (`research/perses.md` R41).

## Implementation surface

Files to add:
- `modules/nixos/perses.nix`: enables `services.perses` on `magnetite` at `127.0.0.1`, sets the security, authentication, authorization, plugin and provisioning settings above, binds secrets through `_secret`, declares the nginx TLS vhost, the clan vars generators below, and the evaluation-time assertions; placement and clan-service wrapping follow ADR-007.
- `modules/nixos/perses/resources/project.yaml`, `datasources.yaml`, `secrets.yaml`, `roles.yaml` and `dashboards/*.yaml`: the provisioned Perses resources; `secrets.yaml` references the store password by `basicAuth.passwordFile` under the unit's credentials directory (`perses/perses@4c719fc1:pkg/model/api/v1/secret/basic_auth.go:45`).
- `modules/nixos/perses/lint-rules.yaml` and `modules/nixos/perses/mutants/*.yaml`: the custom lint rules and the enumerated mutant set.
- `modules/checks/perses-resources.nix`: the lint check with its valid and mutant legs, built from the same subset derivation the service uses.
- `modules/checks/perses-config.nix`: the configuration mutant check.
- `modules/checks/perses-greptimedb-vm.nix`: the NixOS VM test, `x86_64-linux` only.

Files to modify:
- `modules/nixos/kanidm.nix`: add `systems.oauth2.perses` beside `systems.oauth2.omnigent` (`cameronraysmith/vanixiets@a8e72d185:modules/nixos/kanidm.nix:259-277`), with `originUrl` ending in `/api/auth/providers/oidc/kanidm/callback` (`perses/perses@4c719fc1:docs/configuration/configuration.md:261`) and the scope map for the admission group ADR-008 names.
- `modules/terranix/cloudflare.nix`: one `CNAME` for the dashboard hostname to `magnetite.scientistexperience.net`, mirroring the `omni` record.
- `modules/machines/nixos/magnetite/default.nix`: import the Perses module, if ADR-007 places it as a plain NixOS module rather than a clan service role.

Flake inputs: none; Perses, `percli`, the module and the plugin archives all come from the root `nixpkgs` input, and the subset reuses the vendored URLs and hashes from `pkgs/by-name/pe/perses/plugins.nix`.

Clan vars generators:
- `perses-encryption-key`: one secret file of exactly 32 bytes written with `printf '%s'` so no newline is appended, `mode = "0400"`, `restartUnits = [ "perses.service" ]` (`research/telemetry-security-and-tenancy.md` F40, F41).
- `kanidm-oauth2-perses`: the client secret, shaped like `kanidm-oauth2-omnigent` with one file for Kanidm and one for Perses, each with `restartUnits` naming both units (`cameronraysmith/vanixiets@a8e72d185:modules/nixos/kanidm.nix:123-152`).
- The store password is consumed from the `greptimedb-users` generator's `perses-password` file that ADR-007 declares; this ADR adds no generator for it.

## Questions for the human gate

Q1 Perses 0.54.0 or the 0.55 line? Recommended: 0.54.0 from the root pin with the compensating configuration above and an upgrade obligation at 0.55.0 final in nixpkgs; choosing 0.55 now means a first-party override of a release candidate, a re-vendored plugin set, and an explicit loopback allowance.
Q2 Disposition of GreptimeTeam/dashboard? Recommended: rejected as the dashboard layer and deferred as an exploration console, not deployed; deploying it now requires a GreptimeDB 1.3 prerelease built with `servers/dashboard` and a store password held in browser storage.
Q3 Keep the Prometheus datasource beside the GreptimeDB datasource? Recommended: yes; dropping it removes one plugin (11 MiB) and moves every fleet counter panel into SQL.
Q4 Is one recorded manual Kanidm login at first deploy acceptable as the OIDC regulator? Recommended: yes; the alternative is adding a Kanidm node to the VM test, which roughly doubles its cost to sample a path exercised once per login.
Q5 Is a NixOS VM test on `x86_64-linux` acceptable inside the closure operator? Recommended: yes, because it is the only regulator that samples SQL validity and trace column names; without it, a lint-clean dashboard can render empty unnoticed.
Q6 Public TLS hostname behind Kanidm, or mesh-only? Recommended: public hostname behind the Kanidm client, mirroring `omni.scientistexperience.net`, consistent with ADR-008; mesh-only removes the public surface but needs a certificate path for a mesh-only name that no vhost in this repository has today.
Q7 Plugin subset of ten? Recommended: yes, at an envelope of 96 MiB; the full vendored set costs 257 MiB of tmpfs on `magnetite` under RK3 and adds panel types no dashboard uses.
Q8 Plain resource YAML as the dashboards-as-code format? Recommended: yes; the Go SDK adds a Go module and a build step, and the CUE SDK has no GreptimeDB support.
