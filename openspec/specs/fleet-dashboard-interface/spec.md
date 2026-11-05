# fleet-dashboard-interface Specification

## Purpose

This capability (stratum: `interface`) states the properties at the machine's interface that discharge the `fleet-dashboard` requirements: the `perses-bin` package and its pinned plugins; the loopback listener and the `obs.scientistexperience.net` vhost; the Kanidm client `perses` and its group `perses_users`; Perses' read-only and permission settings; the two global datasources and their secret; provisioning from committed files and the wipe at each start; the credentials; the unit's memory envelope and failure wiring; `perses-lint`, `perses-config` and the container runtime test; and the DNS record.
Trust boundary: Kanidm authenticates people and refuses those outside `perses_users`, whose membership is set in the running Kanidm outside the repository; Perses enforces read-only mode, guest permissions, endpoint patterns and header allow-lists; the telemetry store refuses writes from `perses:ro`; a removed person keeps access for at most 1 h after login; any root process on magnetite can read the credentials; nothing here guarantees that a chart shows correct values, only that the configuration, the gating checks, the container runtime test and the recorded logins behave as stated.

## Requirements

### Requirement: The dashboard service runs the vendor's release with its pinned plugins

The machine SHALL run `perses-bin` as `services.perses.package`, built from the Perses release tarball for its system at the hash the release's checksums file lists, installing `perses`, `percli` and exactly the plugin archives `passthru.plugins` records from the release tag's `scripts/plugin/plugin.yaml`, and SHALL unpack a curated subset of those archives to `/var/lib/perses/plugins`, removed before each start of `perses.service` so that only the curated set is loaded.

**Discharged by**: `checks.x86_64-linux.package-perses-bin`, whose install check compares the installed archives with `passthru.plugins` and whose version check runs `percli version`, and the serving predicate's plugin clause.

#### Scenario: The installed archives differ from the recorded pins

- **WHEN** the package installs an archive whose name or version `passthru.plugins` does not list, or omits one it lists
- **THEN** the package's install check fails

#### Scenario: The curated set is read

- **WHEN** magnetite's configuration is evaluated
- **THEN** `plugin.archive_paths` names exactly the Prometheus, GreptimeDB, TimeSeriesChart, StatChart, GaugeChart, Table and Markdown archives of `perses-bin`, `plugin.path` is `/var/lib/perses/plugins`, and `perses.service`'s `preStart` removes that directory

#### Scenario: The plugin directory is on tmpfs

- **WHEN** magnetite's configuration leaves `plugin.path` under `/run`
- **THEN** magnetite's evaluation fails on the serving predicate, which its mutant shows

### Requirement: The dashboard service listens on loopback behind one vhost

The machine SHALL bind Perses to `127.0.0.1:8095` and SHALL serve it only through the nginx vhost `obs.scientistexperience.net`, with `forceSSL` and `enableACME`, whose location `/` proxies to that listener after setting `x-greptime-auth` to the empty string, whose location `= /metrics` answers 404, and which has no other location.

**Discharged by**: the serving predicate's listener and vhost clauses, asserted on magnetite and mutated in `checks.x86_64-linux.perses-config`, the container runtime test's header, bypass and metrics cases, and the operator's `ss -ltnH` at deployment.

#### Scenario: The strip is removed

- **WHEN** the vhost's `/` location no longer sets `x-greptime-auth` to the empty string
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: Perses listens beyond loopback

- **WHEN** `services.perses.listenAddress` is empty or outside `127.0.0.0/8`
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: The listeners are read after deployment

- **WHEN** the operator runs `ss -ltnH` on magnetite after the deploy
- **THEN** Perses listens on `127.0.0.1:8095` only, and the operator records the output

### Requirement: The identity provider admits only the dashboard group

The machine SHALL declare the Kanidm group stub `perses_users` and an OAuth2 client `perses` whose only scope map is `perses_users`, and SHALL configure Perses with exactly one OIDC provider for that client, PKCE enabled, native login and sign-up disabled, `refresh_token_ttl = "45m"` and `access_token_ttl = "15m"`, so that no session outlasts one hour after its login.

**Discharged by**: the serving predicate's authentication and client clauses with their mutants, resting on world assumptions `A56 — Kanidm refuses an authorization whose scopes no group of the person maps` and `A57 — Dashboard-group membership is kept in the running identity provider`; the operator's recorded refusal and admission at deployment.

#### Scenario: The declaration is read

- **WHEN** magnetite's configuration is evaluated
- **THEN** `perses_users` has no members and `overwriteMembers = false`; the client carries `displayName`, `originLanding` and `imageFile`, and its `originUrl` equals Perses' `redirect_uri`, `https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback`; the provider's issuer is `https://accounts.scientistexperience.net/oauth2/openid/perses`

#### Scenario: A second group is mapped

- **WHEN** the client gains a scope map for any group besides `perses_users`
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: Native login is enabled

- **WHEN** `providers.enable_native` is true or `disable_sign_up` is false in magnetite's configuration
- **THEN** the serving predicate fails, which its mutants show

### Requirement: Readers hold only read permission on a read-only server

The machine SHALL set `security.readonly = true` and `security.enable_auth = true`, and SHALL grant through `security.authorization.provider.native.guest_permissions` only the action `read`, on `Dashboard`, `Project`, `Folder`, `GlobalDatasource`, `Datasource`, `Variable` and `GlobalVariable`.

**Discharged by**: the serving predicate's permission clauses with their mutants and the container runtime test's write cases, resting on world assumption `A58 — Perses 0.55.1 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without depending on the identity provider's answer`.

#### Scenario: A guest permission allows a write

- **WHEN** a guest permission names an action other than `read`
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: A write reaches the running server

- **WHEN** the container runtime test sends `POST`, `PUT` and `DELETE` for a dashboard as a logged-in user
- **THEN** each is refused, and the provisioned set is unchanged

### Requirement: The telemetry store is read only through two global datasources

The machine SHALL provision exactly two GlobalDatasources on `http://127.0.0.1:4000`, one PromQL and one SQL, sharing one GlobalSecret that names the `perses` store account's `passwordFile`, each forcing `x-greptime-db-name: fleet`, forwarding only the caller headers its `allowHeaders` lists, and admitting only anchored `GET` or `POST` query paths, and SHALL set `datasource.proxy.allowed_networks = [ "127.0.0.0/8" ]`.

**Discharged by**: the serving predicate's datasource clauses with their mutants, the lint check's qualification rule and its mutant, and the container runtime test's query, refusal and header cases, resting on world assumptions `A58 — Perses 0.55.1 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without depending on the identity provider's answer` and `A59 — GreptimeDB 1.2.1 reads x-greptime-auth before Authorization`.

#### Scenario: The datasources are read

- **WHEN** the committed resources are read
- **THEN** `greptimedb-promql` is a `PrometheusDatasource` at `http://127.0.0.1:4000/v1/prometheus` admitting only the query, range-query, label, label-values and series paths; `greptimedb-sql` is a `GreptimeDBDatasource` at `http://127.0.0.1:4000` admitting only `POST ^/v1/sql$`; both carry `allowHeaders` listing exactly `Accept`, `Accept-Encoding`, `Content-Type`, `Content-Length`, `User-Agent` and `x-greptime-db-name`, and use the GlobalSecret `greptimedb-perses`, whose `basicAuth.username` is `perses` and which carries no literal password; and no project `Datasource` or `Secret` exists

#### Scenario: A chart reads another database

- **WHEN** a chart reads a database other than `fleet`
- **THEN** its PromQL names the database with `__database__` or its SQL qualifies each table, and the lint check rejects an unqualified SQL table

#### Scenario: A pattern loses its anchor

- **WHEN** an `allowedEndpoints` pattern lacks a leading `^` or a trailing `$`
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: A route outside the patterns is asked for

- **WHEN** the container runtime test requests, with the path sent as written, `/api/v1/admin/tsdb/delete_series`, a path that extends a query path (`/api/v1/admin/tsdb/delete_series/api/v1/series`, `/api/v1/query/../../../../v1/sql`) or a path that prefixes one (`/x/api/v1/query`) through `greptimedb-promql`
- **THEN** Perses answers 403 to each and the telemetry store receives none of them

#### Scenario: A datasource forwards a caller header outside its allow-list

- **WHEN** a GlobalDatasource lacks `allowHeaders` or its list differs from the six headers
- **THEN** the serving predicate fails, which its mutants show

#### Scenario: A caller sends another database name

- **WHEN** the container runtime test sends `x-greptime-db-name: devloop` with a PromQL query through `greptimedb-promql`
- **THEN** the telemetry store receives `x-greptime-db-name: fleet`

### Requirement: Committed files are the only source of views and datasources

The machine SHALL provision Perses only from `modules/nixos/perses/resources/`, SHALL remove `/var/lib/perses/db` and `/var/lib/perses/plugins` before each start of `perses.service`, and SHALL restart `perses.service` when a file in that directory changes.

**Discharged by**: the serving predicate's provisioning clause with its mutant and the container runtime test's planted-view case, resting on world assumption `A58 — Perses 0.55.1 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without depending on the identity provider's answer`.

#### Scenario: The wipe is dropped

- **WHEN** `perses.service`'s `preStart` no longer removes `/var/lib/perses/db` or `/var/lib/perses/plugins`
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: A planted view is present at start

- **WHEN** the container runtime test writes a dashboard file into `/var/lib/perses/db` and restarts `perses.service`
- **THEN** the project lists only `fleet-hosts` and `devloop`

### Requirement: The dashboard service's secrets arrive only as credentials

`perses.service` SHALL load its OIDC client secret, its 32-byte encryption key and the `perses` store password through `LoadCredential`, every file Perses reads SHALL lie under `/run/credentials/perses.service/`, the only entry of `security.secret_file_allowed_directories`, and replacing either new secret SHALL restart `perses.service`.

**Discharged by**: the serving predicate's credential clause with its mutants, magnetite's credential-holder assertion, and `telemetry-store-interface` requirement `Credentials exist only as activation-resolved files owned by non-worker users`.

#### Scenario: The credentials are read

- **WHEN** magnetite's configuration is evaluated
- **THEN** `perses.service` loads `kanidm-client-secret` from the generator `kanidm-oauth2-perses`, `encryption-key` from `perses-encryption-key` and `perses-password` from `greptimedb-users`, and both new generators list `perses.service` in `restartUnits`

#### Scenario: A secret file lies outside the credentials directory

- **WHEN** a provider's `client_secret_file`, the `encryption_key_file` or a secret's `passwordFile` names a path outside `/run/credentials/perses.service/`
- **THEN** the serving predicate fails, which its mutant shows

### Requirement: The dashboard service runs inside a memory envelope and hands its failures to the notifier

`perses.service` SHALL set `MemoryHigh = 192M`, `MemoryMax = 256M`, `MemorySwapMax = 0`, `OOMScoreAdjust` above `greptimedb.service`'s, `Restart = "always"` with no start limit, `after` and `wants` `kanidm.service` and `greptimedb.service`, and `OnFailure=observability-notify@%n.service` once, which magnetite's notified units set by listing `perses`.

**Discharged by**: the serving predicate's memory clause with its mutant, magnetite's kill-order assertion, the agent role's notified-unit assertion, and the operator's recorded kill at deployment.

#### Scenario: The ceiling is raised

- **WHEN** `MemoryMax` exceeds 256 MiB or `MemoryHigh` is not below it
- **THEN** the serving predicate fails, which its mutant shows

#### Scenario: The kill order is inverted

- **WHEN** `perses.service`'s `OOMScoreAdjust` is not above `greptimedb.service`'s, or not below the evaluator's
- **THEN** magnetite's evaluation fails on its kill-order assertion

### Requirement: The view files lint clean at the shipped plugins

`checks.x86_64-linux.perses-lint` SHALL run `perses-bin`'s `percli lint` with a writable copy of the curated archive directory as `--plugin.path` and with the repository's custom rules, SHALL require every committed resource to pass and every mutant to fail with its expected message, and SHALL require bare lint to accept one mutant.

**Discharged by**: the check itself, whose valid and bare-lint legs fail if a tooling change alters what lint discriminates.

#### Scenario: The mutant set is read

- **WHEN** `modules/nixos/perses/mutants/` is read
- **THEN** it holds seven dashboards: an empty PromQL query, an extra field in a query spec, an unknown query kind, a `StaticListVariable`, `SELECT *`, an unqualified SQL table and a third datasource name; lint applies custom rules to Dashboards only, so an unanchored endpoint pattern and a literal secret password are the serving predicate's mutants

#### Scenario: A mutant passes

- **WHEN** any mutant exits 0 under the plugin-path invocation, or fails without its expected message
- **THEN** the check fails

#### Scenario: A tooling change makes bare lint discriminate or the archive directory stop loading plugins

- **WHEN** a `perses-bin` upgrade makes bare lint reject the chosen mutant, or stops `percli lint` extracting the archives in `--plugin.path`, so a valid file fails
- **THEN** the check fails, and the upgrade re-examines which invocation discriminates

### Requirement: The serving configuration is judged by one predicate

`flake.lib.persesServingFailures` SHALL return a failure for each violated clause of this capability's listener, vhost, authentication, client, permission, datasource, credential, provisioning, plugin and memory requirements; magnetite SHALL assert it returns none; and `checks.x86_64-linux.perses-config` SHALL judge it without evaluating any NixOS configuration, within 0.5 GiB of evaluation.

**Discharged by**: the check and its mutants, and its evaluation cost recorded before and after.

#### Scenario: The check runs

- **WHEN** `checks.x86_64-linux.perses-config` is built
- **THEN** the predicate returns no failure for a literal valid input and at least one for each of one mutant per clause

#### Scenario: A mutant is accepted

- **WHEN** the predicate returns no failure for a mutant
- **THEN** the check fails with "accepted a serving mutant"

### Requirement: The container runtime test exercises the read path

`vmTests.x86_64-linux.perses-greptimedb` SHALL run GreptimeDB, Perses from the magnetite module and nginx with the module's locations, overriding only Perses' authentication providers to a test-only native login and adding a test-only provisioning folder that holds one native user and one datasource without `allowHeaders`, and SHALL fail unless every case and the negative control below behave as stated.

**Discharged by**: the test, run on demand on magnetite before deployment; it does not gate, so it is evidence only when run.

#### Scenario: The test is run before deployment

- **WHEN** the test runs on magnetite before the deploy
- **THEN** an unauthenticated request is answered 401; the provisioned user logs in; the provisioned set is exact after a planted view and a restart; dashboard writes are refused; PromQL and SQL reads through the two datasources return data; every committed view's query succeeds and each PromQL query returns series, and a mutant view query fails the case; an `INSERT` through `greptimedb-sql` is refused by the telemetry store; the four out-of-pattern routes, sent as written, are answered 403; `x-greptime-auth` carrying the administrative credential reaches the telemetry store as `perses`, through nginx and sent directly to Perses; `/metrics` through nginx is answered 404; and the result is recorded

#### Scenario: The allow-list is bypassed

- **WHEN** the test sends the same `x-greptime-auth` request directly to Perses through the test datasource without `allowHeaders`
- **THEN** the telemetry store sees `admin`, which shows the allow-list is what protects it; through nginx the same request reaches it as `perses`, which shows the strip works on its own

### Requirement: The dashboard hostname resolves to magnetite

The machine's DNS declaration SHALL contain one unproxied `CNAME` `obs.scientistexperience.net` to `magnetite.scientistexperience.net`.

**Discharged by**: the operator's `dig +short obs.scientistexperience.net` before deployment and the certificate issued at deployment, resting on world assumption `A60 — magnetite is reachable on public TCP port 80 for HTTP-01`.

#### Scenario: The record is applied

- **WHEN** the operator applies the DNS declaration and queries the name
- **THEN** it resolves to `magnetite.scientistexperience.net`, and the operator records it

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described as an end-to-end guarantee that a chart shows correct values or that only members of `perses_users` can ever read.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: A guarantee about who is admitted is sought

- **WHEN** someone asks whether these properties guarantee that only members of `perses_users` read the dashboard service
- **THEN** the answer is no: Kanidm authenticates people and refuses non-members, membership is set in the running Kanidm outside the repository, and a removed member keeps access until the last access token issued from the refresh token expires, at most 1 h after login: 45 min of refresh token and 15 min of access token

#### Scenario: A guarantee about the server's enforcement is sought

- **WHEN** someone asks whether these properties guarantee that no reader can write or reach other store routes
- **THEN** the answer is no: Perses enforces read-only mode, guest permissions, endpoint patterns and header allow-lists, the telemetry store refuses writes from `perses:ro`, and this machine only configures them and tests them in the container runtime test

#### Scenario: A guarantee about the credentials is sought

- **WHEN** someone asks whether the store credential and the client secret are confined to Perses
- **THEN** the answer is no: any root process on magnetite can read them

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether a chart's values are correct
- **THEN** the answer is no: each committed view's query runs in the container runtime test against stored samples, and nothing here compares a rendered chart with the stored series
