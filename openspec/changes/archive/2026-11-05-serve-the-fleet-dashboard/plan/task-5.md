### Task 5: Container test, vars and pull request 2

Implements `tasks.md` 3.7–3.9 (design D12).
Pull request 2.

**Files:**
- Create: `modules/vm-tests/perses-greptimedb.nix`; `modules/vm-tests/perses-greptimedb/user-tester.json` and `modules/vm-tests/perses-greptimedb/globaldatasource-sql-open.json`, the test-only provisioning folder
- Create (operator): `vars/per-machine/magnetite/kanidm-oauth2-perses/`, `vars/per-machine/magnetite/perses-encryption-key/`

**Interfaces:**
- Consumes: `flake.modules.nixos.perses`, `pkgs.perses-bin`, magnetite's `greptimedb-users` generator and databases (Tasks 2–4).
- Produces: the on-demand evidence for FD and FDI's runtime scenarios; the generated vars that let magnetite's configuration resolve every credential path.

**Grounding:**
- The shape is `modules/vm-tests/greptimedb-pipeline.nix`: one nspawn container on a builder advertising `uid-range` (magnetite), `nodePkgs` with `self.overlays.default`, databases and the users generator read from `self.nixosConfigurations.magnetite.config`, so the four store accounts and their modes are magnetite's.
- Perses' API, read from `perses/perses@v0.55.0:internal/api/` and exercised by the plan review's probe: `GET /api/v1/projects`, `GET /api/v1/projects/fleet/dashboards`, `POST /api/v1/projects/fleet/dashboards`, `PUT|DELETE /api/v1/projects/fleet/dashboards/<name>` (405 under `readonly`), `/proxy/globaldatasources/<name>/<path>`, native login `POST /api/auth/providers/native/login` with `{"login":…,"password":…}`; sign-up `POST /api/v1/users` is registered only when neither `readonly` nor `disable_sign_up` is set (`internal/api/impl/v1/user/endpoint.go`; probe 2a: 405), and provisioning accepts `User` (`internal/api/provisioning/service.go:214`; probe 2b: a provisioned user logs in with 200).
- The store reads `x-greptime-auth` before `Authorization` (`GreptimeTeam/greptimedb@179ff8e50:src/servers/src/http/authorize.rs:310-319`).
- Without `--path-as-is`, curl rewrites `/query/../../../sql` before sending it (probe 9b: 405, not 403); with every anchor stripped, `/api/v1/query/../../../../v1/sql`, `/x/api/v1/query` and `/api/v1/admin/tsdb/delete_series/api/v1/series` reach the store, and `/api/v1/admin/tsdb/delete_series` does not (probe run 3).
- A datasource with `allowHeaders` forwards no `x-greptime-auth`; one without forwards it unchanged (probe runs 2 and 10).

- [ ] **Step 1: The test (tasks.md 3.7)**

`modules/vm-tests/perses-greptimedb.nix` defines `vmTests.x86_64-linux.perses-greptimedb`: one container importing `flake.modules.nixos.perses`, GreptimeDB as magnetite configures it, and nginx serving the vhost on port 80 without TLS (`forceSSL` and `enableACME` overridden to false in the test only); the generators' files are replaced by fixed test files under `/run/secrets-test/`; `security.authentication.providers` is overridden to `{ enable_native = true; oidc = [ ]; }`; and `provisioning.folders` gains `modules/vm-tests/perses-greptimedb/`, holding `{"kind":"User","metadata":{"name":"tester"},"spec":{"nativeProvider":{"password":"<test password>"}}}` and `greptimedb-sql-open`, a copy of `globaldatasource-sql.json` without `allowHeaders`.
`disable_sign_up` stays true, because `readonly` removes the sign-up route whatever it is set to.
The test asserts `persesServingFailures` of the container's values, with `resources` read from `modules/nixos/perses/resources/` only, returns exactly the failures those overrides explain (native login, provider count, TLS), so every other clause holds in the test as on magnetite.

The script, after `greptimedb-schema`, OTLP points into `fleet` covering every metric the `fleet-hosts` expressions read, and rows into each `devloop` table the `devloop` view reads, written as `collector`:

1. `curl -s -o /dev/null -w '%{http_code}' http://localhost/api/v1/projects` is `401`.
2. `POST /api/auth/providers/native/login` with `{"login":"tester","password":"<test password>"}` answers 200; keep the cookie jar.
3. `GET /api/v1/projects/fleet/dashboards` names exactly `devloop` and `fleet-hosts`.
4. Write `/var/lib/perses/db/dashboards/fleet/planted.json`, `systemctl restart perses`, and step 3 holds again.
5. `POST`, `PUT` and `DELETE` on `/api/v1/projects/fleet/dashboards/fleet-hosts` each answer 404 or 405, and step 3 holds.
6. `POST /proxy/globaldatasources/greptimedb-promql/api/v1/query_range` with `query=system_memory_usage_bytes` returns at least one series with `host_name`; `GET …/api/v1/label/host_name/values` returns the test host.
7. The same query with `-H 'x-greptime-db-name: devloop'` still returns the `fleet` series.
8. `POST /proxy/globaldatasources/greptimedb-sql/v1/sql` with `sql=SELECT count(*) FROM "devloop"."ci_build"` returns the row count written; with `sql=INSERT INTO "devloop"."ci_build" …` the store answers an error naming permission, and the count is unchanged.
9. With `curl --path-as-is`, `POST …/greptimedb-promql/api/v1/admin/tsdb/delete_series`, `…/api/v1/query/../../../../v1/sql`, `…/x/api/v1/query` and `…/api/v1/admin/tsdb/delete_series/api/v1/series` each answer 403, and none of them reaches the store.
10. Through nginx, step 8's `INSERT` with `-H 'x-greptime-auth: Basic <base64 admin:password>'` is still refused, and the error or the store's access log shows user `perses`.
11. Step 10 sent to `http://127.0.0.1:8095` directly, through `greptimedb-sql`, is refused the same way: `allowHeaders` drops the header without nginx.
12. Negative control: step 11 through `greptimedb-sql-open` succeeds as `admin`, so `allowHeaders` is what protects the store from a caller that bypasses nginx; the same request through nginx and `greptimedb-sql-open` is refused as `perses`, so the strip works on its own; delete the inserted row afterwards with `admin`.
13. `curl -s -o /dev/null -w '%{http_code}' http://localhost/metrics` is `404`, and `http://127.0.0.1:8095/metrics` is `200`.
14. The views case: for each `.spec.panels[].spec.queries[].spec.plugin.spec` of `dashboard-*.json`, replace `$host_name` with `.*` and post its `query` through its `datasource.name`'s proxy (`api/v1/query` for PromQL, `v1/sql` for SQL); each answers `status: success`, and each PromQL query returns a non-empty result.
    The same case over a copy of `dashboard-fleet-hosts.json` with one query replaced by `system_memory_usage_bytes_nope` fails, printed as `views case rejects the mutant view query`.

Run on magnetite:

```bash
ssh magnetite.zt 'bash -c "cd ~/projects/vanixiets && git fetch origin && git checkout --detach <pr2-head> && nix build .#vmTests.x86_64-linux.perses-greptimedb -L"' 2>&1 \
  | tee logs/cam73-evidence/3.7-container-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: every step prints `ok:`; step 12 prints `bypass reached the store as admin`; step 14 prints its mutant line; the build succeeds.
If step 12 does not reach the store as `admin`, `allowHeaders` is not what protects the store and design D5 is re-examined before merge.

- [ ] **Step 2: Vars (tasks.md 3.8)**

Gated, the operator, in `$REPO`:

```bash
clan vars generate magnetite --generator kanidm-oauth2-perses
clan vars generate magnetite --generator perses-encryption-key
```

The agent then records, without printing any value:

```bash
L=logs/cam73-evidence/3.8-vars-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
git status --porcelain vars/ | tee -a "$L"
git diff --stat main@origin -- vars/per-machine/magnetite/greptimedb-users | tee -a "$L"
clan vars check magnetite 2>&1 | tee -a "$L"
```

Expected: only the two new directories; no change under `greptimedb-users`; the check passes.

- [ ] **Step 3: Pull request 2 (tasks.md 3.9)**

```bash
L=logs/cam73-evidence/3.9-pr-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath | tee -a "$L"
for c in perses-lint perses-config nixos-magnetite; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c-stats.json \
    nix eval --option eval-cache false --raw .#.checks.x86_64-linux.$c.drvPath >/dev/null
  echo "$c $(jq -r '[.gc.totalBytes, .cpuTime] | @tsv' /tmp/$c-stats.json)" | tee -a "$L"
done
nix fmt 2>&1 | tee -a "$L"; nix fmt -- --fail-on-change
```

Commit with the vars; open the pull request titled "Serve a Perses dashboard behind Kanidm at obs.scientistexperience.net", its body naming the predicate's mutants, the container test's result and the costs.

Expected: magnetite's toplevel evaluates; `perses-lint` and `perses-config` below 536,870,912 B; `nixos-magnetite`'s figure beside 1.2's; nixbot green.
