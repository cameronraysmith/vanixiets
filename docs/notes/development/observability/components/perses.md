---
title: "perses"
---

## Purpose

Perses is the dashboard layer: it renders metrics, logs and traces from the GreptimeDB store for admitted humans (ADR-002 Decision).
It is the only read path for humans into the store (ADR-008 Readers and admission item 1).
Its dashboards, datasources, secrets and role bindings are plain Perses resource YAML committed to this repository and provisioned from a Nix store path, so a commit and a deploy are the only way a resource changes (ADR-002 Decision, Consequences).

## Decisions realized

- ADR-002 Decision: Perses 0.54.0 from the root nixpkgs pin, lock node `nixpkgs_10` at `NixOS/nixpkgs@ac1faec4`, run through `services.perses` on `magnetite`.
- ADR-002 Decision: two server-side proxied datasources in one Perses project, a `GreptimeDBDatasource` for SQL time series, logs and traces, and a `PrometheusDatasource` at `/v1/prometheus` for PromQL metric panels, both using the `perses:ro` credential against `http://127.0.0.1:4000`.
- ADR-002 Decision and Q8: the dashboards-as-code format is plain Perses resource YAML (`Project`, `Datasource`, `Secret`, `Dashboard`, `Role`, `RoleBinding`), provisioned with `security.readonly: true` so that provisioning is the only write path.
- ADR-002 Decision and Q7: the plugin set is a first-party archive subset of ten vendored plugins wired through `plugin.archive_paths`: `GreptimeDB`, `Prometheus`, `TimeSeriesChart`, `Table`, `StatChart`, `LogsTable`, `TraceTable`, `TracingGanttChart`, `Markdown` and `StaticListVariable`.
- ADR-002 Q3: the Prometheus datasource is kept beside the GreptimeDB datasource.
- ADR-002 Decision: the resource-file regulator is a flake check running `percli` 0.54.0 `lint` with `--plugin.path` pointed at a Nix-extracted directory of exactly the subset and with `--custom-rule.path`, asserting that every enumerated mutant is rejected.
- ADR-002 Q5: the data-path regulator is an on-demand, non-gating NixOS VM test under `modules/vm-tests/`.
- ADR-002 Decision and Q4: authentication is a direct Kanidm OIDC client using the authorization-code flow with PKCE, admitting members of the Kanidm group `perses_users`, with one recorded manual login at first deploy as the OIDC regulator.
- ADR-002 Q6: Perses is served publicly at `perses.scientistexperience.net` through a `magnetite` nginx TLS vhost in front of its loopback listener, behind the direct Kanidm client.
- ADR-002 Q1: 0.54.0 is deployed with compensating configuration, and the upgrade to the 0.55 line is a recorded obligation.
- ADR-002 Q2: GreptimeTeam/dashboard is rejected as the dashboard layer and deferred, not deployed, as an exploration console.
- ADR-008 Q1 and Readers and admission item 3: every admitted person reads every stored signal, because the store holds no content and no person identifier.
- ADR-008 Readers and admission item 2: auth enabled, `guest_permissions` empty, `security.readonly: true`, `security.encryption_key` from a clan vars secret, one project, and RoleBindings naming each admitted person explicitly, because 0.54.0 has no claim-based roles.
- ADR-008 Readers and admission item 1: the direct Kanidm client is a recorded exception to web-verification D11 (`docs/notes/development/web-verification/decisions.md:252`) and to `openspec/changes/sso-gateway/design.md:17`, following `modules/nixos/sso-gateway.nix:291-296`.
- ADR-008 Q2: Cameron is admitted to `perses_users` first, and Janette when she chooses.
- ADR-007 Decision (clan service shape): Perses is a plain NixOS module, `modules/nixos/perses.nix`, imported by `magnetite`, and is not a clan service role; its memory envelope is ADR-002's plugin-subset envelope verbatim.
- ADR-007 Decision (credentials): the `perses` store user is `ro` and is used only by the Perses service.

The human gate of 2026-10-15 accepted the recommended answer of every ADR-002 and ADR-008 question listed above.

## Placement

- Host: `magnetite` (ADR-002 Decision; ADR-007 Decision).
- Unit: `perses.service`, configured through the nixpkgs module `services.perses` (`NixOS/nixpkgs@ac1faec4:nixos/modules/services/monitoring/perses.nix`, root node `nixpkgs_10`).
- Listener: `listenAddress` `127.0.0.1`, fronted by the `magnetite` nginx vhost `perses.scientistexperience.net` with `forceSSL` and `enableACME` (ADR-002 Decision, Implementation surface).
- Plugin extraction: the package extracts the plugin archives into `/run/perses/plugins` on a tmpfs (`NixOS/nixpkgs@ac1faec4:nixos/tests/perses.nix:15-17`, root node `nixpkgs_10`).
- Store account: the GreptimeDB user `perses` with mode `ro` (ADR-007 Decision).
- Identity accounts: the Kanidm group `perses_users`, whose membership lives in the running Kanidm database rather than in the repository, and the Kanidm OAuth2 client `systems.oauth2.perses` (ADR-008 Consequences; ADR-002 Implementation surface).
- No worker account and no worker-run process holds the Perses datasource secret (ADR-008 Readers and admission item 5).

## Interfaces

- Downstream (browsers): HTTPS at `perses.scientistexperience.net`, a public `magnetite` vhost reached through one unproxied Cloudflare `CNAME` to `magnetite.scientistexperience.net` (ADR-002 Decision, Implementation surface).
- Identity provider: Kanidm OIDC, authorization-code flow with PKCE, with `originUrl` `https://perses.scientistexperience.net/api/auth/providers/oidc/kanidm/callback` (`perses/perses@4c719fc1:docs/configuration/configuration.md:261`), `originLanding` `https://perses.scientistexperience.net`, and `scopeMaps.perses_users` (ADR-002 Implementation surface).
- Upstream (store), SQL: the GreptimeDB plugin 0.1.0 sends every query as `POST <datasource url>/v1/sql` through the server-side `HTTPProxy` to `http://127.0.0.1:4000` (`perses/plugins@a62049f:greptimedb/src/model/greptimedb-client.ts:89`; ADR-002 Context).
- Upstream (store), PromQL: the stock Prometheus plugin reaches GreptimeDB's PromQL router at `http://127.0.0.1:4000/v1/prometheus` (ADR-002 Decision).
- Query kinds: `GreptimeDBTimeSeriesQuery`, `GreptimeDBLogQuery` and `GreptimeDBTraceQuery`, the last two of the generic `LogQuery` and `TraceQuery` kinds rendered by the stock `LogsTable`, `TraceTable` and `TracingGanttChart` panels (`perses/plugins@a62049f:greptimedb/package.json:50-77`).
- Proxy path: dashboards query through `/proxy/projects/<project>/datasources/<name>`, and read-only mode removes only the generated resource routes, not the proxy routes (ADR-002 Rationale, Operating envelope; `perses/perses@4c719fc1:internal/api/generate.go:80`).
- Store upstream of Perses: `components/greptimedb.md`.
- Credentials consumed:
  - Store password: the `perses-password` file of the `greptimedb-users` generator of ADR-007, mode `0400`, `restartUnits = [ "perses.service" ]`, referenced by `basicAuth.passwordFile` under the unit's credentials directory (`perses/perses@4c719fc1:pkg/model/api/v1/secret/basic_auth.go:45`; ADR-002 Implementation surface).
  - Encryption key: the `perses-encryption-key` generator of ADR-002, bound through `_secret`.
  - OIDC client secret: the `kanidm-oauth2-perses` generator of ADR-002, shaped like `kanidm-oauth2-omnigent`.
- Known interface limit: GreptimeDB serves no Prometheus `/metadata` route at 1.1.4 or 1.2.1, so the query editor shows no PromQL metric help until the 1.3 line (ADR-002 Consequences).
- Known interface limit: any dashboard reader can send arbitrary SQL to GreptimeDB under the `perses:ro` credential, which ADR-008 accepts because every admitted human is in one read zone and content is excluded at the collector (ADR-002 Consequences).

## Configuration surface

Files to add (ADR-002 Implementation surface):

- `modules/nixos/perses.nix`: enables `services.perses` on `magnetite` at `127.0.0.1`, sets the security, authentication, authorization, plugin and provisioning settings, binds secrets through `_secret`, declares the `forceSSL` and `enableACME` nginx vhost `perses.scientistexperience.net`, the `perses-encryption-key` generator and the evaluation-time assertions.
- `modules/nixos/perses/resources/project.yaml`, `datasources.yaml`, `secrets.yaml`, `roles.yaml` and `dashboards/*.yaml`: the provisioned Perses resources.
- `modules/nixos/perses/lint-rules.yaml` and `modules/nixos/perses/mutants/*.yaml`: the custom lint rules and the enumerated mutant set.
- `modules/checks/perses-resources.nix`: the lint check with its valid and mutant legs, built from the same subset derivation the service uses.
- `modules/checks/perses-config.nix`: the configuration mutant check.
- `modules/vm-tests/perses-greptimedb.nix`: the NixOS VM test, assigning `perSystem.vmTests` on `x86_64-linux` only with `requiredFeatures.kvm`, in the shape of `modules/vm-tests/zerotier-mss-clamp-runtime.nix:6-10`.

Files to modify:

- `modules/nixos/kanidm.nix`: the group stub `perses_users` with `members = [ ]` and `overwriteMembers = false` beside `omnigent_users`, the `kanidm-oauth2-perses` generator beside `kanidm-oauth2-omnigent`, and `systems.oauth2.perses` beside `systems.oauth2.omnigent` with the `originUrl`, `originLanding` and `scopeMaps.perses_users` above (ADR-002 Implementation surface; ADR-008 Implementation surface).
- `modules/terranix/cloudflare.nix`: one `CNAME` `perses.scientistexperience.net` to `magnetite.scientistexperience.net`, unproxied, mirroring the `omni` record (ADR-002 Implementation surface).
- `modules/machines/nixos/magnetite/default.nix`: import the ADR-002 `perses` module from `flakeModules` (ADR-007 Implementation surface).

Flake inputs: none; Perses, `percli`, the module and the plugin archives come from the root `nixpkgs` input, and the subset reuses the vendored URLs and hashes from `pkgs/by-name/pe/perses/plugins.nix` (ADR-002 Implementation surface).

Clan vars generators:

- `perses-encryption-key`: one secret file of exactly 32 bytes written with `printf '%s'` so no newline is appended, `mode = "0400"`, `restartUnits = [ "perses.service" ]` (ADR-002 Implementation surface).
- `kanidm-oauth2-perses`: the client secret, with one file for Kanidm and one for Perses, each with `restartUnits` naming both units (ADR-002 Implementation surface).
- Consumed, not created here: `greptimedb-users` `perses-password` (ADR-007 Implementation surface).

## Operating envelope and regulator

The envelopes and regulators below are ADR-002's, and ADR-008 assigns Perses' own configuration regulator to ADR-002 (ADR-008 Operating envelope and regulator).

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| Perses resource files | Every file under the resource tree lints clean against the ten-plugin subset at the versions the root pin vendors, and against custom rules forbidding `SELECT *` and any datasource name outside the two declared ones, each rule targeting a scalar | flake check `perses-resources`: `percli lint --plugin.path <extracted subset> --custom-rule.path <rules>` over each file; deterministic, nixbot `x86_64-linux` | an enumerated mutant set built in the same derivation (empty `query`, extra field in a query spec, unknown query kind, `SELECT *`) each of which must exit non-zero, plus the valid set which must exit zero |
| Perses service configuration | `security.enable_auth` true, `authorization.guest_permissions` empty, `security.readonly` true, `security.encryption_key` from a secret, `listenAddress` `127.0.0.1`, `plugin.archive_paths` exactly the subset, no `GlobalRoleBinding` granting `create` or `*` on `Datasource` or `Secret` | evaluation-time assertions in the Perses module, plus the mutant check `perses-config` in the shape of `cameronraysmith/vanixiets@a8e72d185:modules/checks/omnigent-environment.nix:98-118` | each named mutant (auth off, guest read granted, readonly off, key unset, listener `0.0.0.0`, full plugin set) must produce a non-empty failure list, or the check fails with "accepted a policy mutant" |
| Data path, store to panel | One provisioned time-series, log and trace query each returns at least one row through the Perses proxy over loopback with the `ro` credential, a resource `POST` returns 405 or 404, and `/run/perses/plugins` stays at or below 96 MiB | on-demand NixOS VM test `vmTests.x86_64-linux.perses-greptimedb`, outside PR gating, run on a KVM-capable host such as Pyrite: GreptimeDB plus Perses, OTLP samples written with the `wo` credential, queries issued through `/proxy/projects/<project>/datasources/<name>` | the same test issues one query against a nonexistent table and one write through the `ro` credential and asserts both are rejected; because it does not gate, this row is evidence only when run |
| Kanidm OIDC login | Login via Kanidm completes and yields a Perses session holding only the provisioned read role | one recorded manual login at first deploy (ADR-002 Q4) | not shown; this row is the incomplete regulator R5 requires ADR-002 to name |

The 96 MiB bound is the measured 84 MiB subset plus headroom for plugin patch releases, and a plugin added to the subset must raise the bound in the same commit (ADR-002 Operating envelope and regulator).
ADR-007 adopts this plugin-subset envelope verbatim as Perses' memory envelope on `magnetite` (ADR-007 Decision).
The gating regulators are `perses-resources` and `perses-config`; the data path from store to panel is sampled by no gating check (ADR-002 Rationale, Consequences).

## Failure prevented

These are ADR-002's Failure prevented entries.

- Perses itself: a GreptimeDB store whose logs and traces nobody can see, which is charter RK7.
- GreptimeDB plugin: the same RK7 failure for logs and traces, which the Prometheus plugin alone leaves open.
- Prometheus datasource: fleet counter panels whose rates are hand-written in SQL and silently wrong across counter resets `[INFERENCE]`.
- Committed resource YAML with read-only provisioning: dashboards and datasources drifting from the repository through UI edits that no review sees.
- Plugin subset: 173 MiB of avoidable tmpfs on a host already OOM-killed twice (RK3).
- Lint check with mutants: a schema-invalid dashboard reaching `magnetite` behind a regulator that reports success on everything (RK8).
- Configuration assertions with mutants: guests reading every project, a default encryption key, or a listener beyond loopback reaching deployment unnoticed.
- On-demand VM test: dashboards that lint clean but render empty because a table or column name is wrong, when the test is run before deploy.
- Direct Kanidm client: a second identity store, and the shared-secret blast radius of the gateway.
- Not deploying GreptimeTeam/dashboard: a store password persisted in browser storage on laptops.

## Deployment acceptance items

- One recorded manual Kanidm login at first deploy completes and yields a session holding only the provisioned read role (ADR-002 Q4, Operating envelope).
- OIDC against Kanidm has not been exercised live; ES256 tokens are expected to verify because the OIDC client adopts the provider's advertised signing algorithms `[INFERENCE]` (ADR-002 Consequences).
- Trace panels depend on GreptimeDB's stored trace columns matching the plugin's names, which only the on-demand VM test samples (ADR-002 Consequences; charter RK7 residual).
- Log and trace rendering has not been exercised against a live GreptimeDB (charter RK7 residual).
- Whether Perses 0.54.0 forwards the reader's session cookies on proxy requests is not established; the session token does not reach the store in the `Authorization` header, because the datasource's `basicAuth` makes `SetBasicAuth` replace that header (`perses/perses@4c719fc1:internal/api/impl/proxy/proxy.go:369-375`; ADR-002 Rationale; ADR-008 Consequences).
- `/run/perses/plugins` holds at or below 96 MiB on `magnetite` (ADR-002 Operating envelope).
- A dashboard edit restarts `perses.service` on activation, which re-extracts the 84 MiB plugin subset (ADR-002 Consequences).
- Cameron is added to `perses_users` operationally, outside the repository (ADR-008 Q2, Consequences).

## Deferred

- Perses 0.55 line: triggered when Perses 0.55.0 final reaches the root pin (ADR-002 Decision, Q1).
  The upgrade requires `datasource.proxy.allowed_hosts` naming the store address, `allowed_networks` containing `127.0.0.1/32` only, an extension of `secret_file_allowed_directories` to the credentials directory, and the GreptimeDB plugin at `0.2.0` or later (ADR-002 Consequences, Rationale).
- Claim-based role assignment: absent from 0.54.0 and present in the 0.55 line, so role bindings name each admitted person explicitly until the upgrade (ADR-002 Context, Consequences).
- GreptimeTeam/dashboard as an exploration console: deferred, not deployed (ADR-002 Q2).
  Deploying it would need GreptimeDB at or above `v1.3.0-alpha.1` built with `servers/dashboard` from pre-fetched assets, or a separately served `build.tar.gz`, plus a read-capable store credential held in a browser (ADR-002 Rationale).
- PromQL metric help in the query editor: arrives when GreptimeDB serves `/metadata`, which first ships in the 1.3 line (ADR-002 Consequences).
- Admission of Janette to `perses_users`: when she chooses (ADR-008 Q2).
