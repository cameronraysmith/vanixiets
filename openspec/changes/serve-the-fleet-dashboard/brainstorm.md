# Brainstorm: serve the fleet dashboard behind Kanidm (CAM-73, slice S6)

## Background

Slice S6 (CAM-73) gives people a browser read path into the telemetry store on magnetite.
Today the store is reached only through `ssh -L 4000:127.0.0.1:4000 magnetite.zt` (`docs/notes/development/observability/components/perses.md:22`, `:119`).
ADR-002 chose GreptimeDB's embedded Perses dashboard behind `sso-gateway` and left Q9 and Q10 open for this slice (`docs/notes/development/observability/decisions/ADR-002-dashboard-layer.md:52-63`, `:196-199`).
The first draft of this change followed that choice.
On 2026-11-04 the operator reversed it: a standalone Perses server logs people in through its own Kanidm client, and the embedded dashboard stays on loopback as the operator's tunnelled fallback.
Classification under `skill://brainstorming`: architectural, because it adds the fleet's first public read surface onto the store and a second long-running service beside it on a memory-constrained host.

Abbreviations used below:
`OBS` is `docs/notes/development/observability/`.
`A2` is `OBS/decisions/ADR-002-dashboard-layer.md`, `A7` is `OBS/decisions/ADR-007-packaging-placement-and-clan-service.md` and `A8` is `OBS/decisions/ADR-008-access-control-and-tenancy.md`.
`PC` is `OBS/components/perses.md`, `CH` is `OBS/charter.md` and `RA` is `OBS/architecture/reference-architecture.md`.
`MG` is `modules/machines/nixos/magnetite/default.nix`, `KN` is `modules/nixos/kanidm.nix`, `SG` is `modules/nixos/sso-gateway.nix` and `GM` is `modules/nixos/greptimedb.nix`.
`P54` is `perses/perses@4c719fc1` (v0.54.0), `P55` is `perses/perses@v0.55.0` (commit `bfaf3ce26d8b36397efb41ce185197a6e22f28b1`, the one `percli version` reports), `GT` is `GreptimeTeam/greptimedb@179ff8e50` (v1.2.1), `KA` is `kanidm/kanidm@v1.11.2`, and `NP` is the root `nixpkgs` node `nixpkgs_10` at `3a32588c117116d2bf0edc33915981398fab2b00`.

Inputs gathered for this brainstorm, 2026-11-04:

- The decision records, component and charter: A2, A7:74-79, A8:89-91, PC, RA:124-127 and :270-272, CH up to v27.
- The fleet's identity and serving configuration: KN, MG:150-201, SG, `modules/nixos/omnigent.nix`, `modules/terranix/cloudflare.nix:175-216`.
- Two research reports read in full, `agent://DashboardSso` (SSO for each option, the portal tile, the refusal-test account) and `agent://PersesStandalone` (feasibility of standalone Perses with native OIDC), whose upstream citations are carried below.
- The Perses `v0.55.0` release: its assets and checksums file, the `linux_amd64` and `darwin_arm64` tarballs, `scripts/plugin/plugin.yaml` and the configuration model under `pkg/model/api/config/`.
- Read-only probes: magnetite's listening sockets by `ss -ltnH`, magnetite's configuration evaluated at NP, and `percli lint` from the `darwin_arm64` tarball run against hand-written fixtures.

## Status of the decisions

The operator's decisions are recorded once below, each in a line beginning `Decision (O<n>, decided by the operator, 2026-11-04)`.
O1 to O3 came before the first draft; O4 to O11 came with the reversal.
New questions this rewrite raises are listed in `design.md` "Open Questions" with a recommendation.

## Grounding evidence

### Why the embedded dashboard needs a proxy and Perses does not

- GreptimeDB OSS 1.2.1 accepts only the static and watch-file user providers (`GT:src/auth/src/common.rs:54-74`), and its HTTP layer accepts only Basic credentials (`GT:src/servers/src/http/authorize.rs:270-292`); bearer support arrives in 1.3.0 as a hook the OSS providers do not implement (GreptimeTeam/greptimedb PR #8719).
- The store reads `x-greptime-auth` before `Authorization` (`GT:src/servers/src/http/authorize.rs:310-319`), and authentication applies only under `/v1/` (`:336-346`).
- Dashboard `0.13.13` has no login flow; its datasources always send Basic credentials from the browser's settings (`GreptimeTeam/dashboard@7b4b275a:src/perses-dashboard/react/DashboardView.tsx:41-91`).
- Perses has native OIDC login: `security.authentication.providers.oidc[]` with `client_secret_file`, `issuer`, `redirect_uri`, `scopes` and PKCE on by default (`P55:pkg/model/api/config/authentication.go:143-156`, `:219-224`; `P54:internal/api/impl/auth/oidc.go:88-143`).
- Perses does not map IdP groups; Kanidm refuses an authorization whose requested scopes are not in the person's scope maps with Access Denied (`KA:server/lib/src/idm/oauth2.rs:3473-3502`), so a client whose only scope map is `perses_users` admits only that group.
- Kanidm signs ES256, which Perses' verifier accepts (`KA:server/lib/src/idm/oauth2.rs:918-941`; `zitadel/oidc@v3.48.1:pkg/oidc/verifier.go:211-219`); a local Perses pointed at the live `omnigent` issuer passed discovery and redirected with `code_challenge_method=S256` (`agent://PersesStandalone` §4).

### What Perses 0.55.0 provides

- The release ships `perses` (UI embedded) and `percli` as statically linked binaries, `config.yaml`, and `plugins-archive/` with 32 archives, in tarballs listed with SHA-256 in `perses_0.55.0_checksums.txt` (`linux_amd64` `d7c55bd2…f72054`, `darwin_arm64` `78857f02…10fda94`).
- The plugin versions the tag pins are in `P55:scripts/plugin/plugin.yaml`, which `scripts/plugin/install_plugin.go` reads to fetch `https://github.com/perses/perses-plugins/releases/download/<name>/v<version>/<Name>-<version>.tar.gz`; the tarball's archives are exactly that list, among them Prometheus `0.59.0`, GreptimeDB `0.2.0`, TimeSeriesChart `0.14.0`, StatChart `0.15.0`, GaugeChart `0.14.0`, Table `0.14.0`, Markdown `0.13.0`, StaticListVariable `0.10.0` and DatasourceVariable `0.7.0`.
- Seven archives (Prometheus, GreptimeDB, TimeSeriesChart, StatChart, GaugeChart, Table, Markdown) unpack to 63 MiB.
- `percli version` prints `version: 0.55.0` and exits 0 with no server; `perses` has no version flag.
- 0.55.0 requires `datasource.proxy.allowed_networks` to reach loopback, because loopback is denied by default (`P55:pkg/model/api/config/datasource.go:200-226`), and rejects every file a secret names unless its directory is in `security.secret_file_allowed_directories` (`P55:pkg/model/api/config/security.go:165-170`).
- 0.55.0 refuses to start with authentication on and no encryption key (`P55:pkg/model/api/config/security.go:173-177`), closing the hardcoded-key fallback of 0.54.0 (GHSA-mpfg-6jh9-3jmg).
- 0.55.0 fixes the 0.54.0 advisories `agent://PersesStandalone` lists (GHSA-2wxp-jhwc-h2ff, GHSA-63qw-3pm6-j4f3, GHSA-phr8-237x-w7mj and others).
- Its configuration keys used below: `security.readonly`, `security.enable_auth`, `security.encryption_key_file`, `security.cookie.secure` (`security.go:128-170`); `security.authentication.{access_token_ttl,refresh_token_ttl,disable_sign_up,providers.enable_native,providers.oidc}` (`authentication.go:262-300`); `security.authorization.guest_permissions` (`authorization.go:79`, `:103`); `database.file.{folder,extension}` (`database.go:45-47`); `provisioning.{folders,interval}` (`provisioning.go:21-26`); `plugin.{path,archive_paths}` (`plugin.go:41-48`); `datasource.proxy.allowed_networks` (`datasource.go:218`).
- `security.readonly` removes every create, update and delete route on resources (`P55:internal/api/core/server.go:63-93`); `guest_permissions` gives each logged-in user the listed permissions (`P54:internal/api/authorization/native/native.go:216-219`).
- The datasource proxy sets Basic auth from the secret's `passwordFile`, overwrites configured headers, refuses a path no `allowedEndpoints` pattern matches with 403, and matches patterns unanchored (`P54:internal/api/impl/proxy/proxy.go:213-234`, `:280-290`, `:346-376`); it passes the caller's `x-greptime-auth` through (stub probe, `agent://PersesStandalone` §2).
- Provisioning creates and updates and never deletes (`P54:internal/api/provisioning/provisioning.go:73-121`).
- A session refresh does not consult the IdP, so a person removed from the group keeps access until the refresh token expires (`P54:internal/api/impl/auth/auth.go:163-193`).
- `perses -h` shows the web listener also serves `-web.telemetry-path`, default `/metrics`.

### What `percli lint` 0.55.0 discriminates

Probe on 2026-11-04 with the release's `darwin_arm64` `percli` and three fixtures, a minimal dashboard with one `PrometheusTimeSeriesQuery`, the same with an extra field `bogus` in the query spec, and the same with the query kind `NopeQuery`:

- Without `--plugin.path`, all three exit 0 with "your resources look good", so bare lint is still tautological (CH:192-196).
- With `--plugin.path` at the archive directory, the valid fixture fails with "variable schemas are not loaded", so that form fails closed.
- With `--plugin.path` at a directory holding each archive extracted into its own subdirectory, the valid fixture exits 0, the extra field exits 1 with "spec.bogus: field not allowed", and the unknown kind exits 1 with "schema not found for plugin NopeQuery".
- Extracting several archives into one directory overwrites their shared top-level files and fails closed.

### magnetite as it stands

- `127.0.0.1:8080` is not free: `*:8080` is listening, and so are `127.0.0.1:{3478,4000,4001,5349,5432,5752,6767,8008,8092,8443,8888,9100,9180}` and `*:3002`, among others (`ss -ltnH`, 2026-11-04); no module in `modules/` mentions 8095.
- nginx with ACME HTTP-01 and `forceSSL` fronts every `*.scientistexperience.net` service, each an unproxied `CNAME` to magnetite (`modules/terranix/cloudflare.nix:177-216`; `security.acme.defaults.dnsProvider` evaluates to `null`).
- Native Kanidm clients: `systems.oauth2.omnigent` with `displayName`, `originUrl`, `originLanding`, `imageFile`, `preferShortUsername`, `scopeMaps.omnigent_users` and `basicSecretFile` (KN:259-277), its group stub `omnigent_users = { members = [ ]; overwriteMembers = false; }` (KN:222-225), and its generator `kanidm-oauth2-omnigent` (KN:123-152).
- A client with `displayName`, one `originLanding` and a scope map over the person's groups draws a Kanidm apps-portal tile (`KA:server/lib/src/idm/applinks.rs:6-69`), as omnigent's does.
- `greptimedb-users` writes `perses-password`, mode `0400`, with no consumer (MG:518-546, MG:636); the store is `greptimedb-bin` 1.2.1 on `127.0.0.1:4000` (`pkgs/by-name/greptimedb-bin/package.nix:29`; GM:278-279).
- `sso-gateway` is off (MG:162) and its change `openspec/changes/sso-gateway/` has open tasks; with cognee off it registers nothing (MG:181-183).
- clan regenerates a generator only when a file is missing, a secret's recipients need fixing, or its `validation` hash changes (`clan-core@dbae21013:pkgs/clan-cli/clan_lib/vars/check.py:110-135`), so adding `restartUnits` to `perses-password` does not rotate the store passwords `[INFERENCE]`.

### What the panels read

- Every fleet series carries `host_name` (`openspec/specs/host-metrics-collection/spec.md:61-63`).
- Memory, swap and per-process memory (`modules/nixos/fleet-alert/rules.nix:60`, `:70`, `:98`); ZFS file systems (`:53`); pools, ARC and OOM kills (`modules/clan/services/otel-collector/schema.nix:61-71`); NVMe on pyrite (`rules.nix:147`, `:155`); units (`:163`, `:171`); exporter health (`:179`).
- CPU is not collected (`modules/clan/services/otel-collector/flake-module.nix:338-346`, `:386`, `:398`; ADR-004:90).
- `devloop`'s `queueWait`, `formationToLand` and `buildOutcome` are SQL already run against GreptimeDB 1.2.1 by `vmTests.x86_64-linux.devloop-ingest` (`modules/nixos/devloop-collection.nix:299-326`; `modules/vm-tests/devloop-ingest.nix:450-463`); SQL qualifies a table with its database as `"devloop"."ci_build"` (`devloop-collection.nix:645-647`).
- The GreptimeDB plugin `0.2.0` charts only the first numeric column of a result without a time column and drops rows with no numeric value (`agent://PersesStandalone` §1, read at plugin `0.1.0`) `[INFERENCE: unchanged at 0.2.0]`.

## Decision chain

### D1. Hostname and group (O1)

Decision (O1, decided by the operator, 2026-11-04): the dashboard is served at `obs.scientistexperience.net`, not A2's `perses.scientistexperience.net`; the Kanidm group keeps the name `perses_users`; A2 is amended.

### D2. Ordering (O2)

Decision (O2, decided by the operator, 2026-11-04): CAM-73 runs after CAM-76 and before CAM-72; panels select by `host_name`, so stibnite's series appear once CAM-72 lands.
CAM-76 is done (CH:397-398); RA:280 lets S6 follow S1 in any order, and the docs pull request records the order before CAM-72.

### D3. Read-only store access (O3)

Decision (O3, decided by the operator, 2026-11-04): the dashboard reads the store only through the existing `perses-password` of magnetite's `greptimedb-users`; no store account is added.

### D4. Standalone Perses with native Kanidm OIDC, reversing ADR-002 (O4)

Options:
- A. The embedded dashboard behind `sso-gateway`: oauth2-proxy and its `auth.` vhost, nginx injecting `perses:ro` into `/dashboard/` and `/v1/`, the API listener `127.0.0.1:4006`, and a reconcile oneshot holding `admin`.
- B. A standalone Perses server on loopback behind one nginx vhost, its own Kanidm client scoped to `perses_users`, the store reached only through Perses' datasource proxy with anchored read-only endpoints, and dashboards provisioned from committed files.

Decision (O4, decided by the operator, 2026-11-04): B; the embedded dashboard stays served on loopback only, as the operator's SSH-tunnel fallback, and the `telemetry-store` reader-path requirement is modified to say so rather than the dashboard being disabled.

- A exposes every `/v1/` route of the store to admitted browsers; B exposes none, only the proxy's anchored query paths.
- A needs `x-greptime-auth` cleared and a credential include; B needs `x-greptime-auth` stripped in front of Perses, because Perses passes it through.
- A's dashboards need a reconcile holding `admin`; B's need provisioning plus a wipe, with no store write credential.
- A's UI still offers saves the store refuses; B's server has no write routes under `security.readonly`.
- A adds `oauth2-proxy-kanidm`; B adds `perses`, about 72 MiB resident in `agent://PersesStandalone` §5's measurement, bounded at 256 MiB.
- A closes `openspec/changes/sso-gateway/`'s tasks; B leaves them open.
- A2 rejected the standalone server for its tmpfs of plugins, its Kanidm client, its encryption key and an upgrade obligation (A2:78); B moves plugins to disk, mirrors omnigent's client, keeps the key in clan vars, and takes the upgrade obligation through `update.sh`.

### D5. Packaging: `perses-bin` 0.55.0 from the release (O5)

Decision (O5, decided by the operator, 2026-11-04): `pkgs/by-name/perses-bin` at 0.55.0 from the upstream tarballs for `x86_64-linux` and `aarch64-darwin`, hashed from the release's checksums file, installing `perses`, `percli` and the plugin archives at the versions `scripts/plugin/plugin.yaml` pins at the tag, with an `update.sh` in the style of `greptimedb-bin` and `worktrunk-bin`; nixpkgs' `services.perses` runs it with `package = perses-bin`; 0.55.0's `allowed_networks` and `secret_file_allowed_directories` are set; no nginx rule is added for the advisories 0.55.0 fixes.

- NP carries 0.54.0, which has the advisories and the hardcoded-key fallback.
- The tarball carries exactly the pinned plugin archives, so the package needs no second fetch.

### D6. Session lifetime (O6)

Decision (O6, decided by the operator, 2026-11-04): `refresh_token_ttl` is 1 h, so a person removed from `perses_users` loses access within an hour.

### D7. The gateway stays off (O7)

Decision (O7, decided by the operator, 2026-11-04): `sso-gateway` stays disabled on magnetite, and `openspec/changes/sso-gateway/` stays open, unchanged by this change.

### D8. The refusal test (O8)

Decision (O8, decided by the operator, 2026-11-04): the refusal is shown with `cameron` before `kanidm group add-members perses_users cameron`, then a logout and login shows the admission; the expected refusal is Kanidm's Access Denied from the scope map.

- The repository provisions no person (KN:196-278); `admin` and `idm_admin` are not used, so neither password enters a browser (`agent://DashboardSso` Q12).

### D9. The Kanidm client and its tile (O9)

Decision (O9, decided by the operator, 2026-11-04): `systems.oauth2.perses` mirrors `systems.oauth2.omnigent` (KN:259-277), with `displayName`, `originLanding` and `imageFile`, from which the apps-portal tile comes, `scopeMaps.perses_users`, and a `perses_users` group stub; the generators are `kanidm-oauth2-perses` and `perses-encryption-key` (32 bytes).

### D10. The server's configuration (O10)

Decision (O10, decided by the operator, 2026-11-04):
- The store credential is a GlobalSecret with `basicAuth.passwordFile` read through `LoadCredential`, and the holder assertion admits `perses` for `perses-password`.
- Two GlobalDatasources, Prometheus to `http://127.0.0.1:4000/v1/prometheus` and GreptimeDB SQL to `http://127.0.0.1:4000`, each with anchored read-only `allowedEndpoints` and the header `x-greptime-db-name: fleet`.
- nginx in front strips `x-greptime-auth`.
- `security.readonly = true`, `enable_native = false`, `disable_sign_up = true`, and guest read permissions.
- Perses listens on `127.0.0.1` on a free port, since 8080 is taken.
- `plugin.path` on disk, with a curated archive set.
- Provisioning from committed files, with a wipe before each start so the files are the only source.
- `MemoryHigh = 192M`, `MemoryMax = 256M`, ordered after and wanting `kanidm.service` and `greptimedb.service`, with restart.

### D11. Sequencing and records (O11)

Decision (O11, decided by the operator, 2026-11-04): CAM-73 precedes CAM-72, recorded in the charter and the reference architecture by the docs pull request, together with ADR-002's reversal and hostname amendment and a rewrite of `components/perses.md`.

### D12. Port (derived)

`127.0.0.1:8095`: not in `ss -ltnH` on magnetite and named by no module.

### D13. Database selection (ADR-002 Q10, derived from O10)

Each datasource's proxy overwrites `x-greptime-db-name: fleet`, so a reader cannot change it; a PromQL panel reading another database adds `{__database__="<db>"}` (GreptimeDB 1.2 PromQL documentation, "Cross-database query"), and an SQL panel qualifies each table, `"devloop"."ci_build"`.
v1's PromQL panels all read `fleet`, and its `devloop` panels are SQL.

### D14. Reconcile credential (ADR-002 Q9, dissolved by O4)

No reconcile oneshot exists; provisioning reads committed files, and no unit gains `admin-password`.

### D15. The panel set (derived; unchanged from the first draft)

`fleet-hosts`, selected by `host_name`, over memory and ARC pressure, swap, top processes, OOM kills, ZFS file systems, pools, ARC, units, exporters and NVMe; `devloop`, in SQL, over queue wait, formation to landing, build outcomes and deploys.
No CPU panel, because CPU is not collected.

### D16. `/metrics` on the public vhost (new; put to the operator)

Perses serves its own Prometheus metrics at `/metrics` on the listener nginx fronts.
Recommendation: nginx answers `location = /metrics` with 404, since nothing scrapes it and it is not one of the advisories 0.55.0 fixes; the alternative moves it with `-web.telemetry-path`, which leaves it reachable under another path.

## Envelopes and regulators

Every artifact names an envelope and a regulator shown able to fail (CH:99), and each check stays within 0.5 GiB of evaluation (CH:340-347).

- The package: its install check runs `percli version`; `update.sh` reads the checksums file and the tag's `plugin.yaml`.
- Dashboard and resource files: `perses-lint` at 0.55.0 with each archive extracted into its own directory, with custom rules and mutants, its discrimination shown by the probe above.
- Serving configuration: a predicate over the rendered settings, asserted on magnetite and judged by `perses-config` with mutants, building no NixOS configuration.
- Secrets: assertions that every file Perses reads lies under its credentials directory and outside the Nix store, and the holder assertion admitting `perses` for `perses-password`.
- Runtime: the container test proves refused writes and admin routes through the proxy, the stripped header, refused unauthenticated requests and the provisioned set; `OnFailure` reports a failed `perses.service`.
- Login: recorded observations of the refusal and the admission at deployment, which ADR-002 Q4 accepted as the login regulator.

## Rules adopted from earlier retrospectives

- A relation within one host is a module assertion, not a check clause (CH:312-319, CH:348).
- Each check states its evaluation cost against 0.5 GiB, before and after (CH:340-347).
- A credential never appears on a command line, in a unit's environment or in the Nix store.
- A human step that a later observation depends on is a gated task.
- Every runtime regulator gets a negative control at acceptance.
- A probe of a vendored tool runs the consumer's exact arguments: the lint probe above used the flags `perses-lint` will pass.
