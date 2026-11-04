## Context

This change is slice S6 (CAM-73): admitted people get a browser read path into the telemetry store on magnetite, which today is reached only through `ssh -L 4000:127.0.0.1:4000 magnetite.zt` (PC:22, PC:119; RB:40-48).
A2 chose GreptimeDB's embedded Perses dashboard behind `sso-gateway` (A2:52-63).
On 2026-11-04 the operator reversed that choice for a standalone Perses 0.55.0 with its own Kanidm client (O4), and decided the hostname (O1), the order before CAM-72 (O2, O11), the store account (O3), the package (O5), the session lifetime (O6), the gateway staying off (O7), the refusal test (O8), the Kanidm client (O9) and the server's configuration (O10).
`brainstorm.md` records the evidence, each decision, and the embedded-dashboard option as the rejected alternative.

Citation keys:
OBS is `docs/notes/development/observability/`; A2, A7 and A8 are `OBS/decisions/ADR-002-dashboard-layer.md`, `ADR-007-packaging-placement-and-clan-service.md` and `ADR-008-access-control-and-tenancy.md`; CH is `OBS/charter.md`, PC is `OBS/components/perses.md`, RA is `OBS/architecture/reference-architecture.md` and README is `OBS/README.md`.
MG is `modules/machines/nixos/magnetite/default.nix`, KN is `modules/nixos/kanidm.nix`, GM is `modules/nixos/greptimedb.nix`, CF is `modules/terranix/cloudflare.nix`, OH is `modules/lib/observability-hosts.nix` and RL is `modules/nixos/fleet-alert/rules.nix`.
RB is the runbook `packages/docs/src/content/docs/development/operations/fleet-observability.md`.
P54 is `perses/perses@4c719fc1` (v0.54.0), P55 is `perses/perses@v0.55.0`, GT is `GreptimeTeam/greptimedb@179ff8e50` (v1.2.1), KA is `kanidm/kanidm@v1.11.2`, NP is the root `nixpkgs` node at `3a32588c`.
Repository line numbers are at `origin/main` `674cdf4a7`.

The current state:

- The store is `greptimedb-bin` 1.2.1 on `127.0.0.1:4000`, serving its embedded dashboard at `/dashboard/` on that listener (`pkgs/by-name/greptimedb-bin/package.nix:29`, `:63-64`; GM:278-279).
- The `perses` store account is `ro`, and `perses-password` has no consumer (MG:536-543, MG:636).
- Kanidm serves `accounts.scientistexperience.net`; omnigent and matrix log in through their own clients, each scoped to a `*_users` group stub (KN:205-277).
- `sso-gateway` is off (MG:162) and stays off (O7).
- nginx fronts every `*.scientistexperience.net` name on magnetite with ACME HTTP-01 and `forceSSL`, each name an unproxied `CNAME` (CF:177-216).
- `127.0.0.1:8095` is free on magnetite, while `*:8080`, which `services.perses` defaults to, is taken (`ss -ltnH`, 2026-11-04).
- NP packages Perses 0.54.0 with `services.perses` (`nixos/modules/services/monitoring/perses.nix`), whose unit is `DynamicUser`, `StateDirectory = "perses"`, `WorkingDirectory = /var/lib/perses`, `RuntimeDirectory = "perses"`, `Restart = "on-failure"`, and renders `settings` to `/run/perses/config.yaml` in `preStart` (lines 72-127).

Facts about Perses 0.55.0 that shape the decisions (`brainstorm.md` "What Perses 0.55.0 provides"):

- The release tarball holds `perses`, `percli` and the 32 plugin archives `scripts/plugin/plugin.yaml` pins; the binaries are statically linked.
- Loopback datasources need `datasource.proxy.allowed_networks`; files named by secrets need `security.secret_file_allowed_directories`; authentication needs an encryption key.
- `security.readonly` removes every write route on resources; the datasource proxy injects the secret's Basic credential, overwrites configured headers, and refuses unmatched paths with 403; provisioning never deletes; a session refresh does not consult the IdP.
- `percli lint` discriminates only with each archive extracted into its own directory.

Constraints that shape every decision below:

- Every artifact names an envelope and a regulator shown able to fail (CH:99).
- Each check stays within 0.5 GiB of evaluation, measured with `NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<check>.drvPath` before and after (CH:340-347).
- A relation within one host is a module assertion, not a check clause (CH:312-319, CH:348).
- A credential never appears on a command line, in a unit's environment or in the Nix store.
- magnetite has 30.6 GiB shared with the build service's evaluations, which exhausted it twice (CH:173; world assumption A31).

Stakeholders: the operator, the first member of `perses_users`; Janette, when she chooses (A8 Q2); CAM-72, which follows (O2).

## Goals / Non-Goals

**Goals:**

- A member of `perses_users` opens `https://obs.scientistexperience.net/`, logs in through Kanidm, and sees `fleet-hosts` and `devloop` with data; `cameron`, before he joins, is refused by Kanidm.
- No store credential reaches a browser; nothing a reader sends reaches a store route outside the anchored query paths; no reader can create, change or delete a resource.
- The stored resources equal the committed files after every start.
- A removed member loses access within 1 h.
- The dashboard service stays within 256 MiB and reports its failure.
- A2 is reversed, PC rewritten, and every artifact citing the replaced text follows.

**Non-Goals:**

- Serving the embedded dashboard publicly, or disabling it.
- Enabling `sso-gateway` or closing `openspec/changes/sso-gateway/` (O7).
- Collecting CPU or any signal not already stored.
- Log and trace panels, which arrive with S7.
- Darwin panels for stibnite, which CAM-72 adds if its metric names differ.
- Automating the Kanidm login regulator (A2 Q4).
- Per-person read partitions (A8 Q1; CH:198-201).
- Packaging `aarch64-linux` or `x86_64-darwin`.

## Decisions

### Layout

| Path | Change |
|---|---|
| `pkgs/by-name/perses-bin/package.nix` (new) | D1 |
| `pkgs/by-name/perses-bin/update.sh` (new) | D1 |
| `modules/nixos/perses.nix` (new) | `flake.modules.nixos.perses`: `services.perses` (D2, D4, D5, D7), the unit overrides (D8), the vhost (D3), `flake.lib.persesServingFailures` and its assertion (D10), the curated plugin set (D6) |
| `modules/nixos/perses/resources/` (new) | `project.json`, `globalsecret.json`, `globaldatasource-promql.json`, `globaldatasource-sql.json`, `dashboard-fleet-hosts.json`, `dashboard-devloop.json` (D5, D7, D9) |
| `modules/nixos/perses/lint-rules.yaml`, `modules/nixos/perses/mutants/*.json` (new) | D11 |
| `modules/checks/perses-lint.nix`, `modules/checks/perses-config.nix` (new) | D11, D10 |
| `modules/vm-tests/perses-greptimedb.nix` (new) | D12 |
| KN | `perses_users` stub; `systems.oauth2.perses`; generator `kanidm-oauth2-perses` (D4) |
| MG | import; `perses-encryption-key`; `perses-password` gains `restartUnits = [ "perses.service" ]`; holder assertion `perses-password = [ "perses" ]` (D8) |
| OH | magnetite's `notifiedUnits` gains `perses` (D8) |
| CF | `cloudflare_dns_record.obs`, unproxied `CNAME` to `magnetite.scientistexperience.net`, beside `omni` (CF:186-193) |
| A2, A7, A8, PC, RA, README, RB, CH | the amendments in "Implementation surface" |

### Data flow

```
browser ──HTTPS──▶ nginx obs.scientistexperience.net (magnetite, ACME HTTP-01, forceSSL)
   │   proxy_set_header x-greptime-auth "";      = /metrics → 404
   ▼
perses.service 127.0.0.1:8095 (perses-bin 0.55.0, readonly, guest read, native login off)
   │  /login ─▶ 302 https://accounts.scientistexperience.net/ui/oauth2 (client perses, PKCE S256,
   │            scopes openid profile email; Kanidm refuses anyone outside perses_users)
   │  /api/auth/providers/oidc/kanidm/callback ◀─ code; session JWT signed with encryption-key,
   │            refresh token 1 h
   │  /proxy/globaldatasources/greptimedb-promql/api/v1/query_range ──┐
   │  /proxy/globaldatasources/greptimedb-sql/v1/sql ─────────────────┤ allowedEndpoints, anchored
   ▼                                                                    ▼
GreptimeDB 127.0.0.1:4000  ◀── Authorization: Basic perses:<perses-password>, x-greptime-db-name: fleet
```

### Credential flow

| Generator | File | Delivered as | Consumer |
|---|---|---|---|
| `kanidm-oauth2-perses` (new, per machine, in KN) | `secret`, owner `kanidm`, mode `0400`, `restartUnits = [ "kanidm.service" "perses.service" ]`, `printf '%s' "$(openssl rand -hex 32)"` | `basicSecretFile`; `LoadCredential=kanidm-client-secret:<path>` | Kanidm's provisioning; Perses' `client_secret_file` |
| `perses-encryption-key` (new, per machine, in MG) | `key`, mode `0400`, `restartUnits = [ "perses.service" ]`, `printf '%s' "$(openssl rand -hex 16)"`, 32 bytes | `LoadCredential=encryption-key:<path>` | `security.encryption_key_file` |
| `greptimedb-users` (unchanged values) | `perses-password`, gains `restartUnits = [ "perses.service" ]` | `LoadCredential=perses-password:<path>` | the GlobalSecret's `basicAuth.passwordFile` |

Every file Perses reads lies under `/run/credentials/perses.service/`, the one entry of `security.secret_file_allowed_directories`.

### D1: `perses-bin` packages the 0.55.0 release (O5)

- **Choice**: `stdenv.mkDerivation` named `perses-bin`, version `0.55.0`, `passthru.sources` for `x86_64-linux` (`perses_<v>_linux_amd64.tar.gz`) and `aarch64-darwin` (`perses_<v>_darwin_arm64.tar.gz`), each a `fetchurl` whose hash is the release checksums file's SHA-256 in SRI form; `sourceRoot = "."`; installs `perses` and `percli` to `$out/bin` and `plugins-archive/*.tar.gz` to `$out/share/perses/plugins-archive/`.
  `passthru.plugins` is the attrset of plugin name to version from `scripts/plugin/plugin.yaml` at the tag; an install check asserts each `<Name>-<version>.tar.gz` exists and no other archive does, and `versionCheckHook` runs `percli version`.
  `meta.mainProgram = "perses"`, `sourceProvenance = binaryNativeCode`, platforms from `passthru.sources`; no `autoPatchelfHook`, because both Linux binaries are static.
  `update.sh`, in the shape of `pkgs/by-name/worktrunk-bin/update.sh`, selects the latest `^v[0-9]+\.[0-9]+\.[0-9]+$` release, reads `perses_<v>_checksums.txt` for the two hashes, converts them with `nix hash convert --to sri --hash-algo sha256`, reads `https://raw.githubusercontent.com/perses/perses/v<v>/scripts/plugin/plugin.yaml` and rewrites `passthru.plugins`.
- **Rationale**: NP's 0.54.0 has the advisories 0.55.0 fixes and falls back to a hardcoded key; the tarball carries exactly the pinned plugins, so `plugin.yaml` is both the version record and the install check's oracle, two independently published artifacts of one tag.
- **Boundary**: vendored versus first-party: the binaries and archives are the vendor's; this repository owns the hash and plugin-version record and their refresh.
- **Alternatives considered**: NP's `perses` 0.54.0 with nginx denying the advisory paths, rejected by O5; building 0.55.0 from source with an overridden `vendorHash` and UI build, rejected for a Go and npm build of a UI the tarball already embeds; fetching the newest plugin tags, rejected because the server is tested against the tag's pins.

### D2: The dashboard service runs on loopback through nixpkgs' module (O5, O10)

- **Choice**: `services.perses = { enable = true; package = pkgs.perses-bin; listenAddress = "127.0.0.1"; port = 8095; settings = …; }`.
  `settings.security`: `enable_auth = true`, `readonly = true`, `encryption_key_file = "/run/credentials/perses.service/encryption-key"`, `cookie.secure = true`, `secret_file_allowed_directories = [ "/run/credentials/perses.service" ]`.
  `settings.security.authentication`: `disable_sign_up = true`, `refresh_token_ttl = "1h"`, `providers.enable_native = false`, and one `providers.oidc` entry, `slug_id = "kanidm"`, `name = "Kanidm"`, `client_id = "perses"`, `client_secret_file = "/run/credentials/perses.service/kanidm-client-secret"`, `issuer = "https://accounts.scientistexperience.net/oauth2/openid/perses"`, `redirect_uri = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback"`, `scopes = [ "openid" "profile" "email" ]`.
  `settings.security.authorization.guest_permissions = [ { actions = [ "read" ]; scopes = [ "Dashboard" "Project" "Folder" "GlobalDatasource" "Datasource" "Variable" "GlobalVariable" ]; } ]`.
  `settings.datasource.proxy.allowed_networks = [ "127.0.0.0/8" ]`.
  `settings.database.file = { folder = "/var/lib/perses/db"; extension = "json"; }`.
- **Rationale**: the module already hardens the unit; loopback keeps nginx the only way in; `redirect_uri` is set rather than derived from forwarded headers (`agent://PersesStandalone` §4); the guest permissions are the only grant, so no person has `create` on any datasource and the unsaved proxy is closed (P54:`internal/api/impl/v1/globaldatasource/globaldatasource.go:45`).
- **Boundary**: vendored versus first-party: the module is NP's; the settings are this repository's.
- **Alternatives considered**: a `.zt`-only listener, rejected by O1's public hostname; `_secret` substitution in the module, rejected because it writes the secret's value into `/run/perses/config.yaml` under a `0755` runtime directory.

### D3: One nginx vhost strips `x-greptime-auth` and hides `/metrics` (O10; Q1)

- **Choice**: `services.nginx.virtualHosts."obs.scientistexperience.net" = { forceSSL = true; enableACME = true; locations."/" = { proxyPass = "http://127.0.0.1:8095"; extraConfig = ''proxy_set_header x-greptime-auth "";''; }; locations."= /metrics".return = "404"; }`.
- **Rationale**: the store reads `x-greptime-auth` before `Authorization` (GT:`src/servers/src/http/authorize.rs:310-319`) and Perses passes it through, so a reader's header could replace the proxy's identity or break a panel; nginx drops a header set to the empty string.
  Perses serves its own metrics at `/metrics` on the same listener; nothing scrapes them, and they are not among the advisories 0.55.0 fixes, which O5 excludes from nginx rules.
- **Alternatives considered**: moving the metrics path with `-web.telemetry-path`, which leaves it reachable; no rule, which publishes Perses' internal counters to anyone `[INFERENCE: the handler is unauthenticated]`.

### D4: Kanidm logs people in through a client of its own (O8, O9)

- **Choice**: in KN, `groups.perses_users = { members = [ ]; overwriteMembers = false; }` beside `omnigent_users` (KN:222-225), and `systems.oauth2.perses = { displayName = "Observability"; originUrl = "https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback"; originLanding = "https://obs.scientistexperience.net/"; imageFile = <pinned Perses logo fetchurl>; preferShortUsername = true; scopeMaps.perses_users = [ "openid" "profile" "email" ]; basicSecretFile = <kanidm-oauth2-perses secret>; }`, mirroring KN:259-277; the generator mirrors `kanidm-oauth2-omnigent` (KN:123-152) without the `env` file.
- **Rationale**: Kanidm refuses an authorization whose scopes are outside the person's scope maps (KA:`server/lib/src/idm/oauth2.rs:3473-3502`), so the scope map is the group gate, and the same fields draw the apps-portal tile (KA:`server/lib/src/idm/applinks.rs:6-69`).
- **Boundary**: vendored versus first-party: Kanidm's provisioning and refusal are upstream; the client declaration is this repository's.
- **Alternatives considered**: `sso-gateway`, rejected by O7; claim-mapped roles inside Perses, unnecessary because every member gets the same read access.

### D5: The store is reached only through two global datasources (O3, O10)

- **Choice**: `globalsecret.json`: GlobalSecret `greptimedb-perses` with `basicAuth = { username = "perses"; passwordFile = "/run/credentials/perses.service/perses-password"; }`.
  `globaldatasource-promql.json`: GlobalDatasource `greptimedb-promql`, `default = true`, plugin `PrometheusDatasource`, `proxy.kind = "HTTPProxy"`, `proxy.spec.url = "http://127.0.0.1:4000/v1/prometheus"`, `secret = "greptimedb-perses"`, `headers = { "x-greptime-db-name" = "fleet"; }`, `allowedEndpoints`: `POST ^/api/v1/(query|query_range|labels|series)$` and `GET ^/api/v1/(label/[^/]+/values|labels|series|query|query_range)$`.
  `globaldatasource-sql.json`: GlobalDatasource `greptimedb-sql`, plugin `GreptimeDBDatasource`, `proxy.spec.url = "http://127.0.0.1:4000"`, the same secret and header, `allowedEndpoints`: `POST ^/v1/sql$`.
- **Rationale**: the proxy injects the Basic credential from the file, so no person's browser holds it; anchoring closes paths such as `/api/v1/admin/tsdb/delete_series` and `/query/../../../sql`, which an unanchored pattern let through to the 403 test (`agent://PersesStandalone` §2); GreptimeDB registers these query routes (GT:`src/servers/src/http.rs:1340-1360`); `perses:ro` makes the store refuse any write that reaches `/v1/sql` (A2:32).
- **Database selection (A2 Q10)**: the proxy overwrites `x-greptime-db-name: fleet`; a PromQL panel reading another database adds `{__database__="<db>"}`, and an SQL panel qualifies each table, `"devloop"."ci_build"`; the lint rules require the qualification.
- **Alternatives considered**: project datasources, rejected because one global pair serves every project and needs only `read` on GlobalDatasource; a separate datasource per database, rejected because the header is fixed per datasource and v1 needs only `fleet` for PromQL.

### D6: Plugins unpack to disk from a curated set (O10)

- **Choice**: `settings.plugin = { path = "/var/lib/perses/plugins"; archive_paths = [ curated ]; }`, where `curated` is a `linkFarm` of the archives Prometheus, GreptimeDB, TimeSeriesChart, StatChart, GaugeChart, Table and Markdown from `perses-bin`'s `plugins-archive`, chosen by `passthru.plugins`.
- **Rationale**: the default unpacks every archive to `/run/perses/plugins`, about 257 MiB of tmpfs counted against the unit's memory (`agent://PersesStandalone` §1, §5); the seven unpack to 63 MiB on disk.
- **Alternatives considered**: all 32 archives on disk, harmless for memory but loading plugins no view uses.

### D7: Committed files are the only source of resources (O10)

- **Choice**: `settings.provisioning.folders = [ ./perses/resources ]`; `systemd.services.perses.preStart = lib.mkBefore "rm -rf /var/lib/perses/db"`, so each start begins from an empty file database and provisioning recreates exactly the committed resources; `restartTriggers` on the resources directory, so a changed file restarts the service at activation.
  The Project is `fleet`; both dashboards are in it.
- **Rationale**: provisioning creates and updates and never deletes (P54:`internal/api/provisioning/provisioning.go:73-121`); the database holds only provisioned resources and user records upserted at each login (P54:`internal/api/impl/auth/service.go:94-128`), so the wipe loses nothing.
- **Alternatives considered**: the database on the `RuntimeDirectory` tmpfs, rejected because the module's runtime directory also holds `config.yaml` and is `0755`; a deletion oneshot reading the API, rejected because it needs a write credential that `readonly` removes.

### D8: The unit's envelope, ordering and failure wiring (O10; Q2)

- **Choice**: `systemd.services.perses`: `after` and `wants` `kanidm.service` and `greptimedb.service`; `serviceConfig = { LoadCredential = [ "kanidm-client-secret:<path>" "encryption-key:<path>" "perses-password:<path>" ]; MemoryHigh = "192M"; MemoryMax = "256M"; MemorySwapMax = 0; Restart = "always"; RestartSec = "10s"; OOMScoreAdjust = 600; }`; `unitConfig.StartLimitIntervalSec = 0`; `onFailure = [ "observability-notify@%n.service" ]` and `perses` in magnetite's `notifiedUnits` (OH), so `SystemdUnitFailed` does not report it twice.
  MG's holder assertion sets `perses-password = [ "perses" ]` (MG:636).
- **Rationale**: Perses exits when OIDC discovery fails at start (`agent://PersesStandalone` §4), so it waits for Kanidm and keeps retrying; about 72 MiB resident was measured (§5); `OOMScoreAdjust = 600`, above the store's 500 (GM:340), makes the kernel kill the dashboard before the store under host exhaustion.
- **Alternatives considered**: `Restart = "on-failure"` with the default start limit, which leaves the unit failed after five quick failures while Kanidm restarts.

### D9: Two views in v1

- **Choice**:
  - `fleet-hosts`, variable `host_name` (`PrometheusLabelValuesVariable` over `system_memory_usage_bytes`, all by default):
    - memory: available and used, and HostMemoryPressure's ratio counting the ARC above `c_min` (RL:98);
    - swap: `system_paging_usage_bytes{state="used"}` over the total;
    - processes: `topk(5, process_memory_usage_bytes)` per host;
    - OOM kills: `increase(node_vmstat_oom_kill[10m])`;
    - file systems: RL:53's ratio per `mountpoint`;
    - pools: `node_zfs_zpool_state == 1` by `zpool` and `state`;
    - ARC: `node_zfs_arc_size` against `node_zfs_arc_c_min` and `node_zfs_arc_c_max`, and the hit ratio from `_hits` and `_misses`;
    - units: `systemd_unit_state{systemd_unit_active_state="failed"} == 1` and `increase(systemd_service_restarts_total[15m])`;
    - exporters: `up{job=~"node|smartctl"}`;
    - NVMe: `smartctl_device_critical_warning_total` and `smartctl_device_percentage_used_total`.
  - `devloop`, `GreptimeDBTimeSeriesQuery` over `greptimedb-sql`, every table qualified: queue wait p50, p90 and p99 as three queries from `queueWait` (`modules/nixos/devloop-collection.nix:314-326`); formation to landing from `formationToLand` (`:299-308`); build outcomes from `buildOutcome`; deploys per host from `deploy_record` with a constant numeric column.
- **Rationale**: each PromQL expression is one an alert rule already runs against the store, and each SQL query is one `vmTests.x86_64-linux.devloop-ingest` already runs on GreptimeDB 1.2.1 (`modules/vm-tests/devloop-ingest.nix:450-463`); the plugin charts only the first numeric column of a result without a time column and drops rows with no number (`agent://PersesStandalone` §1).
- **Alternatives considered**: one view per host, which multiplies files as hosts join.

### D10: Serving configuration is one predicate, asserted and mutated

- **Choice**: `flake.lib.persesServingFailures { settings; listenAddress; port; unit; vhost; client; resources; }` returns a list of failure strings, one per clause:
  1. listener in `127.0.0.0/8`, port not 8080;
  2. `readonly`, `enable_auth`, `enable_native = false`, `disable_sign_up`, `refresh_token_ttl = "1h"`, `cookie.secure`;
  3. exactly one OIDC provider, its issuer `…/oauth2/openid/perses`, its `redirect_uri` on `obs.` equal to the client's `originUrl`, PKCE not disabled;
  4. `encryption_key_file`, `client_secret_file` and every secret's `passwordFile` under `/run/credentials/perses.service/`, which is the sole entry of `secret_file_allowed_directories`, and each named by the unit's `LoadCredential`;
  5. `allowed_networks` exactly `[ "127.0.0.0/8" ]`;
  6. guest permissions only `read`;
  7. every GlobalDatasource's URL on `http://127.0.0.1:4000`, its header `x-greptime-db-name = "fleet"`, its secret `greptimedb-perses`, and every `allowedEndpoints` pattern beginning `^` and ending `$` with method `GET` or `POST`;
  8. no secret carries a literal `password`, and no resource is a project `Datasource` or `Secret`;
  9. the vhost `forceSSL` and `enableACME`, `/` proxying to the listener with the `x-greptime-auth` strip, `= /metrics` returning 404, and no other location;
  10. the client's scope maps exactly `perses_users`;
  11. `MemoryMax` at most 256 MiB and `MemoryHigh` below it.
  `modules/nixos/perses.nix` asserts the list is empty over magnetite's own values; `checks.x86_64-linux.perses-config` evaluates the predicate over a literal valid input and over one mutant per clause, failing with "accepted a serving mutant", in the shape of `modules/checks/omnigent-environment.nix:98-118`.
- **Rationale**: the check builds no NixOS configuration, so it costs a fraction of 0.5 GiB, while the assertion pays its cost in magnetite's evaluation, which CI already performs (CH:348); the literal valid input and the mutants are written independently of the module, so the check compares two independently defined values.
- **Alternatives considered**: mutants built by `extendModules` over magnetite, rejected because magnetite's toplevel costs about 2.61 GiB (CH:319).

### D11: `perses-lint` at 0.55.0

- **Choice**: the check extracts each curated archive into `plugins/<Name>/` and runs `percli lint -f <file> --plugin.path plugins --custom-rule.path lint-rules.yaml` over every file in `modules/nixos/perses/resources/`, requiring exit 0, and over each file in `modules/nixos/perses/mutants/`, requiring exit non-zero.
  Mutants: an empty PromQL `query`; an extra field in a query spec; an unknown query kind; a `StaticListVariable`, absent from the curated set; `SELECT *`; an unqualified SQL table; a datasource other than `greptimedb-promql` and `greptimedb-sql`; an `allowedEndpoints` pattern without anchors; a secret with a literal `password`.
  A further leg runs the valid set with `--plugin.path` at the archive directory and requires failure, and bare lint over one mutant and requires success, so a tooling change that alters either known behaviour fails the check.
- **Rationale**: the probe of 2026-11-04 showed exactly these three behaviours at 0.55.0 (`brainstorm.md` "What `percli lint` 0.55.0 discriminates"); `percli` and the archives come from the same `perses-bin` the server runs, so no version assertion is needed.
- **Alternatives considered**: `--online` against a running server, which excludes `--custom-rule.path` (CH:192-196; A2:107).

### D12: The container test

- **Choice**: `vmTests.x86_64-linux.perses-greptimedb`, on demand, nspawn on magnetite, in the shape of `modules/vm-tests/greptimedb-pipeline.nix`: GreptimeDB with its four accounts and OTLP samples written as `collector`, Perses from `modules/nixos/perses.nix`, and nginx on plain HTTP with the module's locations; no Kanidm, so the test overrides only `providers` (native login on, one test user created through sign-up) and asserts the predicate of D10 holds for every other clause.
  Cases: an unauthenticated `GET /api/v1/projects` answers 401; the provisioned set lists exactly `fleet-hosts` and `devloop` in `fleet`, and a dashboard file planted in `/var/lib/perses/db` is gone after a restart; a `POST`, `PUT` and `DELETE` on a dashboard answer 404 or 405 under `readonly`; through `greptimedb-promql`, `query_range` over `fleet` and the label values of `host_name` return data; through `greptimedb-sql`, a qualified `devloop` query returns rows and an `INSERT` is refused by the store; `/api/v1/admin/tsdb/delete_series` and `/query/../../../sql` through the proxy answer 403; a request carrying `x-greptime-auth: Basic <admin>` through nginx reaches the store as `perses` (an `INSERT` still refused); `/metrics` through nginx answers 404.
  Negative control: the same `x-greptime-auth` request sent to Perses directly, bypassing nginx, reaches the store as `admin`, showing the strip is what protects it.
- **Rationale**: the test exercises the vendored server with the configuration magnetite runs; Kanidm's refusal is observed at deployment (O8).

### Operating envelope and regulator

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| `perses-bin` | the archives installed are exactly `passthru.plugins`; `percli version` reports the package version | install check and `versionCheckHook` in `package-perses-bin` | an archive removed from the install phase; a `passthru.plugins` entry at another version |
| Resource files | lint clean at the shipped plugins, under the custom rules | `checks.x86_64-linux.perses-lint` | the mutants of D11; the archive-directory and bare-lint legs |
| Serving configuration | D10's list empty | magnetite assertion; `checks.x86_64-linux.perses-config` | one mutant per clause |
| Credentials | `perses-password` loaded only by `perses`; every file under the credentials directory, outside the Nix store | MG's holder assertion; D10 clause 4 | `extendModules` overrides at implementation: a second holder; a `writeText` path |
| Runtime | D12's cases | `vmTests.x86_64-linux.perses-greptimedb`, on demand, evidence only when run | the bypass negative control; the planted dashboard |
| Unit | under 256 MiB; a failure notified | `MemoryMax`; `OnFailure`; R7.2's host view | a forced `systemctl kill` at acceptance, its notice recorded |
| Login | `cameron` refused before joining, admitted after | recorded observations (O8; A2 Q4) | the refusal itself |
| Evaluation cost | each new check below 0.5 GiB | `NIX_SHOW_STATS=1` before and after | a figure above 0.5 GiB stops the task |

### Spec deltas

- `fleet-dashboard` (new, `behavioral`): `An admitted person views the fleet's signals and the dev-loop history by host`; `A person outside the dashboard group is refused`; `A person removed from the dashboard group loses access within an hour`; `Nobody changes the views except by a committed change`; `No store credential reaches a person, and the dashboard service only reads`; `The dashboard service stays inside its memory envelope and its failures reach a person`.
- `fleet-dashboard-interface` (new, `interface`): `The dashboard service runs the vendor's release with its pinned plugins`; `The dashboard service listens on loopback behind one vhost`; `The identity provider admits only the dashboard group`; `Readers hold only read permission on a read-only server`; `The telemetry store is read only through two global datasources`; `Committed files are the only source of views and datasources`; `The dashboard service's secrets arrive only as credentials`; `The dashboard service runs inside a memory envelope and hands its failures to the notifier`; `The view files lint clean at the shipped plugins`; `The serving configuration is judged by one predicate`; `The container runtime test exercises the read path`; `The dashboard hostname resolves to magnetite`; `This capability states its own trust boundary`.
- `telemetry-store`: MODIFIED `The telemetry store runs a stable vendor release that serves its dashboard`, whose reader becomes the operator on magnetite or tunnelled to the loopback listener, with a scenario that the embedded dashboard is not on the public vhost.
- `telemetry-store-interface`: MODIFIED `Credentials exist only as activation-resolved files owned by non-worker users`, admitting `perses` for `perses-password` and restarting it on rotation.
- `world-assumptions`: MODIFIED `Grounded vocabulary for behavioral requirements`, copying main's table and adding `dashboard service`, `view`, `chart`, `dashboard group`, `admitted person`, `identity provider` and `browser`; ADDED `A56 — Kanidm refuses an authorization whose scopes no group of the person maps`, `A57 — Dashboard-group membership is kept in the running identity provider`, `A58 — Perses 0.55.0 removes its write routes in read-only mode, proxies with the stored credential and fixed headers, and refreshes a session without the identity provider`, `A59 — GreptimeDB 1.2.1 reads x-greptime-auth before Authorization` and `A60 — magnetite is reachable on public TCP port 80 for HTTP-01`.

### Implementation surface: artifacts amended

Under charter v28 (CH:9 is v27), each an amendment in place:

- A2: Status gains the reversal; Decision (:52-63), Rationale (:65-91) and Consequences (:110-124) are rewritten for the standalone server; the embedded dashboard and A at large move to Rejected alternatives (:93-108), where the standalone-server entries (:95-96) are removed; Operating envelope (:126-137), Failure prevented (:139-150) and Implementation surface (:152-176) follow this design; Q6's resolution (:191) records `obs.`; Q9 (:196-197) is dissolved; Q10 (:198-199) is answered by D5; Q1, Q2, Q7 and Q8's resolutions note the reversal.
- A7:76-78 and A7:181: `perses-password` is loaded by `perses.service` and restarts it; `perses` is used only by the dashboard service.
- A8:89-91 and :130-131: readers log in to Perses through its Kanidm client; the dashboard service holds `perses:ro`; nginx restarts no longer follow store rotation, `perses.service` does.
- PC: rewritten from this design.
- RA:42, :85, :113, :124-127, :194, :216-222, :270-272 and :280: the standalone server, `perses-bin`, the files and checks, and S6 before S5.
- README:37 keeps its record of the 2026-10-15 gate; a new line under the charter-version summary records v28.
- RB:40-48, :346, :583-584 and :876: the vhost first, the tunnel kept as the operator's fallback with the embedded dashboard, `kanidm group add-members perses_users <account>`, and S6 done.
- CH: v28 entry; CH:262 stays as the 2026-10-15 record.
- `traceability/satisfaction.md` is regenerated wholesale at archive.

### Later slices

| Slice | Touches | Rule it must keep |
|---|---|---|
| S5 (CAM-72) | stibnite's series | views select by `host_name`; a darwin metric with another name gets its own committed chart, linted |
| S7 (CAM-74) | logs and traces | a LogsTable or TraceTable view adds its plugin to the curated set and qualifies its database |
| a Perses upgrade | `perses-bin` | `update.sh` rewrites hashes and plugin pins together; `perses-lint`'s known-behaviour legs and the container test run before merge |

## Risks / Trade-offs

- [Risk] Adding the client restarts `kanidm.service`, interrupting logins to `accounts.`, `omni.` and matrix for the restart. → Mitigation: deploy at a quiet time; a login to `omni.` is observed after the deploy.
- [Risk] Perses fails to start while Kanidm restarts. → Mitigation: D8's `Restart = "always"` with no start limit; the deploy observation waits for `perses.service` active.
- [Risk] A removed member keeps access for up to 1 h (O6). → Accepted.
- [Risk] A reader's heavy query loads the store. → R7.2 notifies on throttling or OOM (CH:301-302); A8's single read zone accepts it.
- [Risk] The GreptimeDB plugin 0.2.0 renders a query differently from 0.1.0. → The container test runs the `devloop` queries; the browser observation at deploy records each chart.
- [Risk] HTTP-01 issuance fails for `obs.` at first deploy. → The record is applied and resolving before deploy.
- [Risk] A Perses upgrade changes lint behaviour or a configuration key. → D11's known-behaviour legs and D10's predicate fail first.
- [Trade-off] A second long-running service on magnetite, bounded at 256 MiB and killed before the store.
- [Trade-off] The login regulator is a recorded observation (A2 Q4).

## Migration Plan

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | `perses-bin` and `update.sh`; `perses-lint` with its rules, mutants and known-behaviour legs over a valid fixture | none |
| 2 | `modules/nixos/perses.nix` and its resources, the Kanidm client and generator, `perses-encryption-key`, the holder and notified-unit changes, the `obs` record, `perses-config`, the container test, the generated vars | terraform, then magnetite |
| 3 | the charter v28 entry and the amendments | none |

1. Gated, the operator: apply the `obs` record with `just terraform…`; `dig +short obs.scientistexperience.net` returns `magnetite.scientistexperience.net`.
2. Gated, the operator: `clan vars generate magnetite --generator kanidm-oauth2-perses` and `--generator perses-encryption-key`; `vars/per-machine/magnetite/greptimedb-users/` is unchanged and `clan vars check magnetite` passes.
3. Run `vmTests.x86_64-linux.perses-greptimedb` on magnetite and record the result.
4. Deploy magnetite from pull request 2.
   Verified by: `systemctl is-active perses` prints `active`; `ss -ltnH` shows `127.0.0.1:8095` and no other Perses listener; `curl -sI https://obs.scientistexperience.net/api/v1/projects` without a session answers 401; `kanidm system oauth2 get perses` shows the client; a login to `omni.` succeeds; every alert and notice since the deploy started is read and explained.
5. Gated, the operator (O8): log in as `cameron` before he joins and record Kanidm's Access Denied; run `kanidm group add-members perses_users cameron`; log out and in; record the admission, both views with data, the browser's storage holding no store password, and a write refused.
6. Negative control: `systemctl kill -s KILL perses` on magnetite; record the `FAILED perses on magnetite` notice and the restart.
7. Measure each new check's evaluation cost and magnetite's toplevel, before and after.
8. Pull request 3 merges.

Rollback: remove the import from magnetite and deploy; the client and group stay in Kanidm (provisioning does not remove, KN:201) and can be removed by hand; the record and vars stay committed and unused.

## Open Questions

Each carries a recommendation; the operator's earlier answers are O1 to O11 in `brainstorm.md`.

1. Q1, `/metrics` on the vhost: answer 404 at nginx? Recommended: yes (D3); it is not an advisory rule, and nothing scrapes Perses' metrics.
2. Q2, `OOMScoreAdjust = 600` for `perses.service`, so the kernel kills the dashboard before the store (500)? Recommended: yes (D8).
3. Q3, the container test logs in with a test-only native user instead of a Kanidm node, with every other setting held to the predicate? Recommended: yes (D12); Kanidm's refusal is O8's recorded observation.
4. Q4, the Kanidm tile's display name: "Observability"? Recommended: yes, matching `obs.`; any name works.
