---
title: "perses"
---

## Purpose

The dashboard layer is a standalone Perses 0.55.1 server on `magnetite`, `perses.service`, serving views of the store's signals to admitted humans at `https://obs.scientistexperience.net/` (ADR-002 Decision, reversed under charter v28).
It logs people in through its own Kanidm client and admits only the group `perses_users` (ADR-008 Readers and admission item 1).
It is the read path for humans into the store, beside the operator's tunnelled fallback to the store's embedded dashboard (ADR-002 Decision).
Its views, datasources and store-credential reference are Perses resource JSON files committed to this repository and provisioned at each start, so a commit and a deploy are the only way a view changes (ADR-002 Decision, Consequences).
The design is `openspec/changes/serve-the-fleet-dashboard/design.md` (CAM-73), landed in #3720 and #3721 and deployed on 2026-11-05.

## Decisions realized

- ADR-002 Decision: the server is the upstream Perses 0.55.1 release, packaged as `pkgs.perses-bin` with the plugin archives `scripts/plugin/plugin.yaml` pins at the tag, run by nixpkgs' `services.perses` module (design D1, D2).
- ADR-002 Decision: it listens on `127.0.0.1:8095` behind one nginx vhost, `obs.scientistexperience.net`, which strips `x-greptime-auth` and answers `/metrics` with 404 (design D2, D3).
- ADR-002 Decision and Q4, Q6: Perses' own OIDC client `perses` at Kanidm, scoped only to `perses_users`, is the only login; native login and sign-up are off; one recorded refusal and one admission at first deploy are the login regulator (design D2, D4).
- ADR-002 Decision: `security.readonly`, and logged-in people hold only `read` (design D2).
- ADR-002 Decision: a refresh token of 45 min and an access token of 15 min, so a removed member loses access within 1 h (design D2).
- ADR-002 Decision, Q3 and Q10: the store is read only through the global datasources `greptimedb-promql` and `greptimedb-sql`, which send `perses:ro` from the GlobalSecret `greptimedb-perses`, fix `x-greptime-db-name: fleet`, forward a fixed header list and admit only anchored read-only paths (design D5).
- ADR-002 Decision and Q8, Q9: the committed files under `modules/nixos/perses/resources/` are the only resources, because each start removes the file database before provisioning; no reconcile oneshot and no store write credential exist (design D7).
- ADR-002 Q7: seven curated plugin archives unpack to disk, not tmpfs (design D6).
- ADR-002 Decision: the store's embedded dashboard stays on loopback as the operator's fallback through `ssh -L 4000:127.0.0.1:4000 magnetite.zt`.
- ADR-008 Q1 and Readers and admission item 3: every admitted person reads every stored signal, because the store holds no content and no person identifier.
- ADR-008 Readers and admission item 2: readers hold only `read` and never the store credential.
- ADR-008 Q2: the operator's account `cameron` joined `perses_users` first, on 2026-11-05, and Janette joins when she chooses.
- ADR-007 Decision (credentials): the `perses` store user is `ro` and is held only by `perses.service`.

The human gate of 2026-10-15 accepted the recommended answer of every ADR-002 and ADR-008 question listed above; charter v11 amended ADR-002 to the embedded dashboard, and charter v28 reversed it to this server, on the operator's decisions of 2026-11-04 and answers of 2026-11-05.

## Placement

- Host: `magnetite` (ADR-002 Decision; ADR-007 Decision).
- Unit: `perses.service`, `DynamicUser` from nixpkgs' module, state in `/var/lib/perses`, ordered after and wanting `kanidm.service` and `greptimedb.service` (design D2, D8).
- Listener: `127.0.0.1:8095`; `*:8080`, the module's default, is taken on `magnetite` (design D2).
- Vhost: `obs.scientistexperience.net`, `forceSSL` with ACME HTTP-01, an unproxied Cloudflare `CNAME` to `magnetite.scientistexperience.net` (design D3; `modules/terranix/cloudflare.nix`).
- Store account: the GreptimeDB user `perses` with mode `ro` (ADR-007 Decision).
- Identity: the Kanidm client `perses` with display name "Observability" and the group `perses_users`, declared with no members and `overwriteMembers = false`, so membership lives in the running Kanidm (design D4; ADR-008 Consequences).
- Resource storage: a file database at `/var/lib/perses/db`, removed before each start; plugins extracted to `/var/lib/perses/plugins`, removed before each start (design D6, D7).
- No worker account and no worker-run process holds the `perses` credential (ADR-008 Readers and admission item 5).

## Interfaces

- Downstream (browsers): HTTPS at `obs.scientistexperience.net`; nginx proxies `/` to `http://127.0.0.1:8095` with `proxy_set_header x-greptime-auth ""`, and `= /metrics` returns 404 (design D3).
- Identity provider: Kanidm at `accounts.scientistexperience.net`, issuer `https://accounts.scientistexperience.net/oauth2/openid/perses`, redirect `https://obs.scientistexperience.net/api/auth/providers/oidc/kanidm/callback`, scopes `openid`, `profile` and `email`, PKCE S256; Kanidm refuses a person whose groups do not include `perses_users` with Access Denied (design D2, D4).
- Upstream (store), PromQL: `greptimedb-promql`, `default = true`, at `http://127.0.0.1:4000/v1/prometheus`, `allowedEndpoints` `POST ^/api/v1/(query|query_range|labels|series)$` and `GET ^/api/v1/(label/[A-Za-z_][A-Za-z0-9_]*/values|labels|series|query|query_range)$` (design D5).
- Upstream (store), SQL: `greptimedb-sql` at `http://127.0.0.1:4000`, `allowedEndpoints` `POST ^/v1/sql$` (design D5).
- Both datasources: secret `greptimedb-perses`, header `x-greptime-db-name: fleet`, `allowHeaders` exactly `Accept`, `Accept-Encoding`, `Content-Type`, `Content-Length`, `User-Agent` and `x-greptime-db-name`; `datasource.proxy.allowed_networks = [ "127.0.0.0/8" ]` (design D5).
- Database selection: a PromQL panel reading another database adds `{__database__="<db>"}`; an SQL panel qualifies each table, as `"devloop"."ci_build"`, and uses no CTE (ADR-002 Q10).
- Views: `fleet-hosts`, selected by the variable `host_name`, over memory and ARC pressure, swap, top processes, OOM kills, ZFS file systems, pools, ARC, failed and restarting units, exporters and NVMe; `devloop`, in SQL, over queue wait, formation to landing, build outcomes and deploys; both in the project `fleet` (design D9).
- Operator fallback: `ssh -L 4000:127.0.0.1:4000 magnetite.zt`, then `/dashboard/` on the forwarded port, signed in as `perses` (ADR-002 Decision).
- Store upstream of the dashboard: `components/greptimedb.md`.
- Credentials consumed, each through `LoadCredential` under `/run/credentials/perses.service/`, the sole entry of `security.secret_file_allowed_directories`:
  - `kanidm-client-secret`, from the generator `kanidm-oauth2-perses`, as `client_secret_file`.
  - `encryption-key`, from the generator `perses-encryption-key`, 32 bytes, as `security.encryption_key_file`.
  - `perses-password`, from ADR-007's `greptimedb-users`, as the GlobalSecret's `basicAuth.passwordFile`, with `restartUnits = [ "perses.service" ]`.
- Known interface limit: GreptimeDB serves no Prometheus `/metadata` route at 1.2.1, so the query editor shows no PromQL metric help until the 1.3 line (ADR-002 Consequences).
- Known interface limit: any admitted reader can send arbitrary PromQL and SQL reads through the two datasources' query paths under `perses:ro`, which ADR-008 accepts because every admitted human is in one read zone and content is excluded at the collector (ADR-002 Consequences).
- Known interface limit: `perses` is not in the collector's `systemdUnits`, so `SystemdUnitFailed` and the `fleet-hosts` units panels do not show it (design D8).

## Configuration surface

Files added in S6 (ADR-002 Implementation surface):

- `pkgs/by-name/perses-bin/package.nix`, `sources.json` and `update.sh`: the release for `x86_64-linux` and `aarch64-darwin`, `null` elsewhere; `passthru.plugins` and `passthru.pluginsArchive`; an install check comparing the installed archives with `passthru.plugins`, and `versionCheckHook` (design D1).
- `apps.update-perses-bin` in `modules/apps/updates.nix`: runs `update.sh`, which writes the version, both hashes and the plugin pins with one `jq` call and fails on a partial update (design D1).
- `modules/nixos/perses.nix`: `flake.modules.nixos.perses` with `services.perses`, the vhost, the unit overrides, the curated plugin set `flake.lib.persesCuratedArchives`, and `flake.lib.persesServingFailures` with the assertion that its list is empty (design D2 to D8, D10).
- `modules/nixos/perses/resources/`: `project.json`, `globalsecret.json`, `globaldatasource-promql.json`, `globaldatasource-sql.json`, `dashboard-fleet-hosts.json` and `dashboard-devloop.json` (design D5, D7, D9).
- `modules/nixos/perses/lint-rules.yaml` and `modules/nixos/perses/mutants/*.json`: the custom lint rules and the mutants (design D11).
- `modules/checks/perses-lint.nix` and `modules/checks/perses-config.nix` (design D10, D11).
- `modules/vm-tests/perses-greptimedb.nix` and its test-only provisioning folder (design D12).

Files modified in S6:

- `modules/nixos/kanidm.nix`: `groups.perses_users`, `systems.oauth2.perses` and the generator `kanidm-oauth2-perses` (design D4).
- `modules/machines/nixos/magnetite/default.nix`: the import, the three `LoadCredential` entries, the generator `perses-encryption-key`, `restartUnits = [ "perses.service" ]` on `perses-password`, `perses-password = [ "perses" ]` in the credential-holder assertion, and `perses` in the kill-order assertion, 900 > 600 > 500 (design D8).
- `modules/lib/observability-hosts.nix`: `perses` among magnetite's `notifiedUnits` (design D8).
- `modules/terranix/cloudflare.nix`: `cloudflare_dns_record.obs` (design Layout).

Unit settings: `MemoryHigh = "192M"`, `MemoryMax = "256M"`, `MemorySwapMax = 0`, `Restart = "always"`, `RestartSec = "10s"`, `StartLimitIntervalSec = 0`, `OOMScoreAdjust = 600`; `preStart` begins with `rm -rf /var/lib/perses/db /var/lib/perses/plugins`; `restartTriggers` on the resources directory (design D7, D8).

Flake inputs: none.

Clan vars generators: `kanidm-oauth2-perses` and `perses-encryption-key`, per machine on `magnetite`; consumed, not created: `greptimedb-users` `perses-password`.

## Operating envelope and regulator

The envelopes and regulators below are ADR-002's, and ADR-008 assigns the dashboard layer's own configuration regulator to ADR-002 (ADR-008 Operating envelope and regulator).

| Artifact | Envelope | Regulator | Shown able to fail by |
|---|---|---|---|
| `perses-bin` | The archives installed are exactly `passthru.plugins`; `percli version` reports the package version | install check and `versionCheckHook` in `package-perses-bin` | `plugins.Prometheus` set to `0.59.0` in `sources.json` failed the build (`logs/cam73-evidence/2.2-package-20261105T003659Z.log`) |
| Resource files | Lint clean at the shipped plugins under the custom rules | `checks.x86_64-linux.perses-lint`: `percli lint --plugin.path <writable copy of the curated archives> --custom-rule.path lint-rules.yaml` over each resource file | seven mutants, each rejected with its message, and the bare-lint leg accepting the extra-field mutant (`logs/cam73-evidence/2.4-lint-20261105T003923Z.log`) |
| Serving configuration | `flake.lib.persesServingFailures` returns an empty list over its eleven clauses | the assertion in `modules/nixos/perses.nix` on magnetite's values; `checks.x86_64-linux.perses-config` over a literal valid input | 47 mutants, each rejected by its own clause (`logs/cam73-evidence/3.2-config-20261105T011100Z.log`); `extendModules` overrides removing the strip and setting `refresh_token_ttl = "24h"` failed magnetite's assertion (`3.4-assertions-20261105T010114Z.log`) |
| Credentials | `perses-password` loaded only by `perses.service`; every file Perses reads under its credentials directory, outside the Nix store | magnetite's credential-holder assertion; the predicate's clause 4 | an override adding `perses-password` to `fleet-alert.service` (`3.5-identity-20261105T010157Z.log`) |
| Kill order | evaluator 900 > `perses` 600 > `greptimedb` 500 | magnetite's kill-order assertion | `OOMScoreAdjust = 400` on `perses.service` (`3.5-identity-20261105T010157Z.log`) |
| Runtime read path | design D12's cases: 401 without a session, 405 on writes, only the provisioned set, every committed query answered, 403 on non-query paths, no caller `x-greptime-auth` reaching the store, `/metrics` 404 through nginx | `vmTests.x86_64-linux.perses-greptimedb`, on demand on magnetite, with a test-only native user; evidence only when run | the bypass control through `greptimedb-sql-open`, without `allowHeaders`, reached the store as `admin`; a view query replaced by a missing metric failed (`3.7-container-20261105T011614Z.log`) |
| Unit | Under 256 MiB; a failure notified | `MemoryMax`; `OnFailure` from `notifiedUnits` | on 2026-11-05 a `SIGKILL` posted `FAILED perses.service on magnetite` the same second, and systemd restarted Perses 11 s later (`4.5-kill-20261105T140642Z.log`) |
| Login | A member of `perses_users` admitted, a person outside it refused | recorded observations at first deploy (ADR-002 Q4) | on 2026-11-05 Kanidm answered the operator's account with Access Denied while the group had no members; after `kanidm group add-members perses_users cameron` and a fresh login, both views showed data (`4.3-4.4-operator-20261105T140642Z.log`) |
| Evaluation cost | Each new check below 0.5 GiB | `NIX_SHOW_STATS=1` before and after | `perses-lint` 100,656,240 B, `perses-config` 101,300,400 B (`3.9-costs-20261105T011226Z.log`) |

Evidence files are under `logs/cam73-evidence/`, which is git-ignored; `openspec/changes/serve-the-fleet-dashboard/tasks.md` records each result.
The gating regulators are `package-perses-bin`, `perses-lint`, `perses-config` and magnetite's assertions; the runtime read path is sampled by the on-demand container test, which does not gate.

## Failure prevented

- Anchored global datasources: an admitted browser reaching store routes beyond the query paths.
- Injected credential, `allowHeaders` and the nginx strip: a store password in browser storage, or a caller's `x-greptime-auth` replacing the proxy's identity.
- `readonly`, guest `read` and the wipe before each start: a view or datasource changed or planted outside review.
- Kanidm client scoped to `perses_users`: a Kanidm account outside the group reading the store.
- Session lifetime of 1 h: a removed member reading indefinitely.
- Lint check with mutants and the bare-lint leg: a schema-invalid view reaching `magnetite` behind a regulator that reports success on everything (RK8).
- Serving predicate with mutants: an unauthenticated or writable server, an unanchored endpoint, a widened scope map or a listener beyond loopback reaching deployment unnoticed.
- Container test: views that lint clean but render empty because a metric or table name is wrong, when run before deploy.
- Memory ceiling and kill order: the dashboard starving the store or the host (RK3).
- `update.sh`'s all-or-nothing check: a version moved without its hashes or plugin pins.

## Deployment acceptance items

Observed on 2026-11-05 after magnetite's deploy from `8a00ca70f` (`openspec/changes/serve-the-fleet-dashboard/tasks.md` group 4):

- `perses.service` active, listening only on `127.0.0.1:8095`, using about 64 MB.
- Without a session, `/api/v1/projects` answers 401 and `/metrics` 404; the login redirects to Kanidm with `code_challenge_method=S256`; the certificate is Let's Encrypt's.
- With `perses_users` empty, Kanidm refused the operator's account with Access Denied; after `kanidm group add-members perses_users cameron` and a fresh login, `fleet-hosts` and `devloop` showed collected data.
- A `SIGKILL` posted the failure notice the same second, and systemd restarted Perses 11 s later.

Not yet observed:

- Log and trace rendering, which arrives with S7's views (charter RK7 residual).
- stibnite's series in `fleet-hosts`, which arrive with S5 (CAM-72).

## Deferred

- Log and trace views: S7 adds their plugins to the curated set and qualifies their database (design "Later slices").
- Darwin panels for stibnite: CAM-72 adds a committed chart for any darwin metric whose name differs (design "Later slices").
- Perses upgrades: `nix run .#update-perses-bin`, then `perses-lint`, `perses-config` and the container test before merging.
- PromQL metric help in the query editor: arrives when GreptimeDB serves `/metadata`, which first ships in the 1.3 line (ADR-002 Consequences).
- Admission of Janette to `perses_users`: when she chooses (ADR-008 Q2).
- Automating the Kanidm login regulator, and per-person read partitions: not adopted (ADR-002 Q4; ADR-008 Q1).
