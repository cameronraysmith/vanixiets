---
linear_story_id: CAM-73
linear_story_identifier: CAM-73
linear_story_title: "S6: Serve GreptimeDB's embedded Perses dashboard behind Kanidm"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-73/s6-serve-greptimedbs-embedded-perses-dashboard-behind-kanidm
linear_story_state: Done
linear_team: CAM
linear_project: fleet-observability
last_synced_state: Done
last_synced_at: 2026-11-05T14:51:34Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-05T14:51:34Z", transition: "Backlog->Done", outcome: "posted", note: "catch-up at archive: the change was not bound when planned, so no earlier transition fired; the description was corrected to the standalone Perses 0.55.1 at obs. with its own Kanidm OIDC client (ADR-002 Q9 dissolved, Q10 answered); specs synced, satisfaction projection regenerated, the five changed main specs mirrored (fleet-dashboard and fleet-dashboard-interface created, telemetry-store, telemetry-store-interface and world-assumptions updated), and a comment records that CAM-72 may start" }
---

## Why

A person can read the telemetry store only through an SSH tunnel to magnetite's loopback listener, so nobody looks at the fleet's memory, disks or units until an alert fires, and the dev-loop rows in `devloop` have no reader.
The store's embedded dashboard has no login of its own and would expose the store's `/v1/` routes to every admitted browser, while Perses logs people in through Kanidm and reaches the store only through its own proxy.
CAM-76 is done, so this change serves a standalone Perses at `obs.scientistexperience.net` to the Kanidm group `perses_users`, with dashboards committed as code, before CAM-72 adds stibnite to the same panels.

## What Changes

Decisions tagged `O<n>` were made by the operator on 2026-11-04 and are recorded in `brainstorm.md`; `Q<n>` marks a question the operator answered on 2026-11-05 in `design.md` "Open Questions"; the plan review's findings, all applied, are in `logs/cam73-evidence/1.1-plan-review-20261104T235200Z.md`.

**Packaging**
- `pkgs/by-name/perses-bin` packages Perses 0.55.1, released 2026-11-02 with security fixes beyond 0.55.0's, from the upstream release tarballs for `x86_64-linux` and `aarch64-darwin`, hashed from the release's checksums file: `perses` with its UI, `percli`, and the plugin archives at the versions the `v0.55.1` tag pins in `scripts/plugin/plugin.yaml` (O5; the plan review's F8).
- `update.sh` follows `greptimedb-bin` and `worktrunk-bin`: it discovers the latest semver release, takes both hashes from the checksums file and the pinned plugin versions from the tag's `plugin.yaml`, and writes all of them to `sources.json` with one `jq` call; `apps.update-perses-bin` runs it.

**The dashboard service**
- nixpkgs' `services.perses` runs `perses-bin` on `127.0.0.1:8095`, with `security.readonly`, native login and sign-up off, read-only guest permissions for every logged-in person, sessions lasting at most 1 h (a 45 min refresh token and a 15 min access token), the file database and the plugin directory wiped before each start, plugins unpacked to disk from a curated set, `MemoryHigh = 192M` and `MemoryMax = 256M`, ordered after `kanidm.service` and `greptimedb.service`, restarting, and reporting failure through `observability-notify@` (O4, O6, O10).
- nginx serves `obs.scientistexperience.net` with ACME, proxies to Perses, strips `x-greptime-auth`, and answers `/metrics` with 404 (O1, O10, Q1).
- The GreptimeDB embedded dashboard stays on the store's loopback listener as the operator's tunnelled fallback (O4).

**Login**
- A Kanidm client `systems.oauth2.perses`, mirroring omnigent's, with its apps-portal tile and `scopeMaps.perses_users`, and the group stub `perses_users`; Kanidm refuses anyone outside the group (O8, O9).
- `sso-gateway` stays off, and `openspec/changes/sso-gateway/` stays open (O7).

**The store read path**
- One GlobalSecret holds the `perses` store account with `basicAuth.passwordFile` from `LoadCredential`; two GlobalDatasources, PromQL at `http://127.0.0.1:4000/v1/prometheus` and SQL at `http://127.0.0.1:4000`, carry anchored read-only `allowedEndpoints`, an `allowHeaders` list that drops every other caller header, `x-greptime-auth` among them, and the header `x-greptime-db-name: fleet` (O3, O10).
- `datasource.proxy.allowed_networks = [ "127.0.0.0/8" ]` and `security.secret_file_allowed_directories` limited to the unit's credentials directory (O5).

**Dashboards as code**
- `fleet-hosts`, selected by `host_name`, and `devloop`, in SQL, are provisioned from committed files with the Project, the GlobalSecret and the GlobalDatasources; the wipe before start makes the files the only source (O10).

**Secrets**
- New generators `kanidm-oauth2-perses` and `perses-encryption-key` (32 bytes); `perses-password` gains `restartUnits = [ "perses.service" ]`, and magnetite's holder assertion admits `perses` for it (O9, O10).

**Regulators**
- `checks.x86_64-linux.perses-lint`: `percli` 0.55.1 with a writable copy of the curated archive directory and custom rules, over every committed resource and seven mutants, each with its expected message.
- `checks.x86_64-linux.perses-config`: a predicate over the rendered settings, nginx locations and resources, with mutants, building no NixOS configuration; magnetite asserts the same predicate.
- `vmTests.x86_64-linux.perses-greptimedb`, on demand: writes refused, routes that extend or prefix a query path refused with 403 through the proxy, `x-greptime-auth` dropped by the allow-list and stripped by nginx, every committed view's query run against the store, unauthenticated requests refused, and the provisioned set exact.
- At deployment: `cameron`'s refusal before he joins `perses_users`, his admission after, rendered data, and a refused write, recorded.

**DNS**
- One unproxied `CNAME` `obs.scientistexperience.net` to `magnetite.scientistexperience.net`, beside `omni`.

**Decision records amended through a charter version entry (v28)**
- From: the dashboard layer is the embedded dashboard behind `sso-gateway` at `perses.scientistexperience.net`, a standalone server is the fallback only, and Q9 and Q10 are open (A2:52-63, :85, :93-108, :157-169, :190-199); readers hold `perses:ro` only through nginx (A8:89-91; A7:76-78); S6 may run in any order after S1 (RA:280).
- To: the dashboard layer is a standalone Perses 0.55.1 at `obs.scientistexperience.net` with its own Kanidm client, reading through its datasource proxy with `perses:ro`; the embedded dashboard is the operator's loopback fallback; Q9 dissolves and Q10 is answered by the proxy's header and per-panel qualification; S6 precedes S5.
- Reason: the embedded dashboard has no login and needs the store's `/v1/` exposed through a proxy, while Perses 0.55.1 logs in natively, removes write routes, and confines the store to anchored query paths (`brainstorm.md` D4).
- Impact: non-breaking for running services; documentation, with `components/perses.md` rewritten and ADR-007, ADR-008, the reference architecture, the README and the runbook following.

## Capabilities

### New Capabilities
- `fleet-dashboard` (stratum: `behavioral`): an admitted person views the fleet's signals and the dev-loop history by host; a person outside the dashboard group is refused, and one removed loses access within an hour; nobody changes the views except by a committed change; no store credential reaches a person; the dashboard service's failures reach a person, and it stays inside a memory envelope.
- `fleet-dashboard-interface` (stratum: `interface`): the package and its pinned plugins, the listener and the vhost, the Kanidm client and its group, the server's security settings, the datasources and their secret, provisioning and the wipe, the credentials, the unit's envelope and failure wiring, `perses-lint`, `perses-config`, the container test, and the DNS record.
  Trust boundary: Kanidm is trusted to authenticate a person and to refuse one outside `perses_users`, whose membership is set in the running Kanidm outside the repository; Perses is trusted to enforce `readonly`, guest permissions, the proxy's endpoint patterns and its header allow-lists; the store is trusted to refuse writes from `perses:ro`; a removed person keeps access until the last access token expires, at most 1 h after login; any root process on magnetite can read the credentials; nothing here guarantees that a chart shows correct numbers end to end, only that the configuration, the gating checks, the container test and the recorded logins behave as stated.

### Modified Capabilities
- `telemetry-store` (stratum: `behavioral`): `The telemetry store runs a stable vendor release that serves its dashboard` keeps the embedded dashboard served on loopback only, as the operator's tunnelled fallback, and no longer names it the fleet's reader path.
- `telemetry-store-interface` (stratum: `interface`): `Credentials exist only as activation-resolved files owned by non-worker users` admits `perses` as the only holder of `perses-password` and restarts it when that password is replaced.
- `world-assumptions` (stratum: `world`): new assumptions, numbered from A56 because the active `watch-the-alert-path-externally` change takes A53 to A55: Kanidm refuses a person none of whose groups maps a requested scope (A56); dashboard-group membership is managed in the running Kanidm (A57); Perses 0.55.1's read-only mode, proxy and session refresh behave as stated (A58); the store reads `x-greptime-auth` before `Authorization` (A59); magnetite is reachable on public TCP 80 for HTTP-01 (A60); the designation table gains `dashboard service`, `view`, `chart`, `dashboard group`, `admitted person`, `identity provider` and `browser`.

## Impact

- New: `pkgs/by-name/perses-bin/{package.nix,sources.json,update.sh}`, `modules/nixos/perses.nix`, `modules/nixos/perses/resources/*.json`, `modules/nixos/perses/lint-rules.yaml`, `modules/nixos/perses/mutants/*.json`, `modules/checks/perses-lint.nix`, `modules/checks/perses-config.nix`, `modules/vm-tests/perses-greptimedb.nix` and its provisioning folder `modules/vm-tests/perses-greptimedb/`.
- Changed: `modules/apps/updates.nix` (`apps.update-perses-bin`), `modules/nixos/kanidm.nix` (the client, the group stub, the generator), `modules/machines/nixos/magnetite/default.nix` (the import, `perses-encryption-key`, `perses-password`'s restart, the holder and kill-order assertions), `modules/lib/observability-hosts.nix` (magnetite's notified units), `modules/terranix/cloudflare.nix`.
- Unchanged: `modules/nixos/sso-gateway.nix`, `modules/nixos/greptimedb.nix`, `pkgs/by-name/greptimedb-bin/`, and `greptimedb-users`' passwords.
- New secrets: `vars/per-machine/magnetite/kanidm-oauth2-perses/` and `vars/per-machine/magnetite/perses-encryption-key/`.
- Documentation: the charter entry and amendments above, `components/perses.md` rewritten, the runbook's dashboard section, and `traceability/satisfaction.md` regenerated at archive.
- Deployment: one terraform apply, two `clan vars generate` runs, one magnetite deploy restarting `kanidm.service` and starting `perses.service`, and the operator's recorded refusal and admission.
- Residual risk: a removed person keeps access for up to 1 h; an admitted person can run any read query the anchored endpoints admit, which loads the store inside its memory envelope; the login regulator is a recorded observation.
