### Task 7: The fleet budget

Implements `tasks.md` 7.1–7.6 (design D8, Migration Plan step 9; FII `otel-envelope on the ingress host regulates the fleet budget`; HMC `Series cardinality stays bounded`, `A failed collection or store job notifies a person`; TSI `The collector's configuration bounds what it gathers`, `Credentials exist only as activation-resolved files owned by non-worker users`; FAI `The evaluator queries each rule's database as the regulators' store account`).
This is pull request 3, deployed to magnetite only.
The container fixtures come first and fail because no clause exists (Step 1); the clauses make them fail as intended (Steps 2, 4); the deployed instance is shown able to fail and post by a runtime drop-in (Step 6).
The journald-bytes clause and the `fleet` logs table's `ttl` are not written: they have no input until a later change creates that table (design D8).

**Files:**
- Modify: `modules/lib/otel-envelope.nix` (the `budget` argument and clauses B1–B6), `modules/checks/otel-envelope.nix` (case `budgetOnlyHourly`)
- Modify: `modules/clan/services/otel-collector/flake-module.nix` (the clan ingress role passes `budget` and loads `regulator-password` into `otel-envelope`)
- Modify: `modules/machines/nixos/magnetite/default.nix:660-664` (the holder list)
- Modify: `modules/vm-tests/fleet-ingress.nix` (case `budget`, mutant `renamedTable`)
- Create (git-ignored): `logs/s4-evidence/7.<n>-*.log`, `logs/s4-evidence/7.3-holders.nix`

**Interfaces:**
- Consumes: `flake.lib.otelEnvelope`'s Task 3 contract; `flake.lib.greptimedbSql pkgs { url; user; }` (`modules/lib/greptimedb-envelope.nix:48-60`), which reads `$CREDENTIALS_DIRECTORY/<user>-password`, puts it on curl's stdin, and exits 1 on any answer but 200, on a missing table and on zero rows; `flake.lib.observabilityHosts`'s `notifiedUnits`; SC's `databases`.
- Produces: the hourly clauses `B1 active-series` … `B6 ttl` and `OTEL_ENVELOPE_MAX_UNITS`, `OTEL_ENVELOPE_FORCE_HOURLY`.

- [ ] **Step 1: The budget fixtures, seen failing (tasks.md 7.1)**

Append to `fleet-ingress`'s `cases` the case `budget`, run against the real store as the ingress host's `otel-envelope.service` with a runtime drop-in setting `OTEL_ENVELOPE_FORCE_HOURLY=1`:

| Fixture | Written as `collector` through the ingress | Expected |
|---|---|---|
| clean | nothing beyond the delivery case | exit 0, every `B` line `ok` |
| labelValues | one synthetic gauge `s4_fixture_wide` with 300 values of label `fixture_key` | exit 1, `B2 label-values: FAIL s4_fixture_wide fixture_key 300` |
| processNames | 31 `process_memory_usage_bytes` series for host `budgethost`, distinct `process_executable_name` | exit 1, `B3 per-host: FAIL budgethost process_executable_name 31` |
| notifierOutside | `systemd_unit_state` for host `cinnabar` with `systemd_unit_name="observability-notify@not-listed.service.service"` | exit 1, `B4 notifier-instances: FAIL cinnabar not-listed` |
| ttlAltered | `ALTER DATABASE agent SET 'ttl' = '7d'` as `admin` | exit 1, `B6 ttl: FAIL agent 7d` |
| renamedTable | the envelope built with its unit-state table name replaced by `systemd_unit_state_absent` (`unitMutants.renamedTable`) | exit 1, the clause naming the missing table |

Each fixture is removed (the synthetic series dropped with `DELETE`, the TTL restored) before the next, and the clean run is repeated at the end.
Run on magnetite from the working copy:

```bash
jj st --no-pager >/dev/null
nix build .#vmTests.x86_64-linux.fleet-ingress -L 2>&1 | tee logs/s4-evidence/7.1-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^=== case|FAIL|error'
```

Expected: the test fails in case `budget` at `labelValues`, because the envelope has no budget clause and exits 0 (RED).

- [ ] **Step 2: The budget clauses (tasks.md 7.2)**

Extend `flake.lib.otelEnvelope` with `budget = { storeUrl; notifiedUnits; databases; } or null`; when non-null and the run's minute is `00` (`OTEL_ENVELOPE_MINUTE`, defaulting to `$(date -u +%M)`, so the check can set it; the timer fires at `*:0/5`) or `OTEL_ENVELOPE_FORCE_HOURLY=1`, it runs these clauses through `greptimedbSql { url = storeUrl; user = "regulator"; }`, a handful of queries in all, each query's failure (non-200, missing table, zero rows) failing its own clause:

| Clause | Query over the last hour of `fleet` (unless stated) | Fails when |
|---|---|---|
| `B1 active-series` | one query: `SELECT count(DISTINCT __tsid) FROM greptime_physical_table WHERE greptime_timestamp > now() - INTERVAL '1 hour'` | above 8,000 |
| `B2 label-values` | one query over `greptime_physical_table` with a `count(DISTINCT <tag>)` for each of its tag columns other than `process_executable_name`, `systemd_unit_name` and `launchd_label`; only for a column above 200 a second query groups it by `__table_id` and maps the ids to metric names through `information_schema.tables`, to name the metric | a column above 200 within one metric |
| `B3 per-host` | per `host_name`: distinct `process_executable_name` in `process_memory_usage_bytes`; distinct `systemd_unit_name NOT LIKE 'observability-notify@%'` over `systemd_unit_state` and `systemd_service_restarts_total`; distinct `launchd_label` where that table exists | above 30, above `OTEL_ENVELOPE_MAX_UNITS` (default 40), above 30 |
| `B4 notifier-instances` | per `host_name`, distinct `systemd_unit_name LIKE 'observability-notify@%'` | an instance `observability-notify@<u>.service.service` whose `<u>` is not in `notifiedUnits.<host>` |
| `B5 devloop-rows` | `devloop`: the sum of `count(*)` over its four tables with time index in the last 24 h | above 100,000 |
| `B6 ttl` | `information_schema` database options for each of `databases` | a `ttl` other than SC's |

The tag columns of `greptime_physical_table` come from `information_schema.columns` with `semantic_type = 'TAG'` (61 on 2026-10-29, read as `regulator`); a column with 200 or fewer distinct values across all metrics has 200 or fewer within any one, so the screen loses nothing; a table missing from a query whose input should exist fails its clause, while `launchd_label`'s table, which no host writes until darwin agents exist, is skipped only when `information_schema.tables` lists no such table, and the run prints `B3 per-host: launchd_label table absent` in that case.
Task 1 Step 3 timed these queries on magnetite; their sum is the expected runtime of an hourly run and must stay well inside `TimeoutStartSec`.
Add `pkgs.jq` and the `greptimedbSql` package to `runtimeInputs`, and to `otel-envelope`'s check the case `budgetOnlyHourly`: with `budget` set and a store URL on a closed port, a run with `OTEL_ENVELOPE_MINUTE=05` exits by R3.2's clauses alone, and one with `OTEL_ENVELOPE_MINUTE=00` exits 1 on B1's unreachable store, whatever the build's wall clock.
In the clan ingress role pass `budget = { storeUrl = "http://127.0.0.1:4000"; notifiedUnits = lib.mapAttrs (_: h: h.notifiedUnits) flakeLib.observabilityHosts; databases = schema.databases; }` through a fragment option `vanixiets.otelCollector.envelopeBudget` (default `null`, consumed by the unit of Task 3 Step 3), and `systemd.services.otel-envelope.serviceConfig.LoadCredential = [ "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}" ];` with `after = [ "greptimedb.service" ]` and no `wants`.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-envelope -L 2>&1 | tee logs/s4-evidence/7.2-check-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(ok|mutant|FAIL)'
```

Expected: 15 `ok:` lines and the five mutants rejected; cost recorded below 536,870,912.

- [ ] **Step 3: The fourth credential holder (tasks.md 7.3)**

In `modules/machines/nixos/magnetite/default.nix:660-664`, the list becomes `[ "devloop-reconcile" "fleet-alert" "greptimedb-envelope" "otel-envelope" ]`, sorted, and its comment names the four holders.
Create `logs/s4-evidence/7.3-holders.nix`, magnetite extended with `systemd.services.nix-daemon.serviceConfig.LoadCredential = [ "regulator-password:<the same path>" ]`.
Run:

```bash
L=logs/s4-evidence/7.3-holders-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath 2>&1 | tee "$L"; echo
nix eval --impure --raw --expr '(import ./logs/s4-evidence/7.3-holders.nix (builtins.getFlake (toString ./.))).fifthHolder' 2>&1 | grep -o 'regulator-password[^.]*' | head -n 1 | tee -a "$L"
```

Expected: a drvPath, then the holder assertion's message naming `nix-daemon` (negative control).

- [ ] **Step 4: The container test passes, and the pull request (tasks.md 7.4)**

```bash
nix build .#vmTests.x86_64-linux.fleet-ingress -L 2>&1 | tee logs/s4-evidence/7.4-fleet-ingress-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^=== case|B[1-6] |FAIL'
```

Expected: eight `=== case` lines; in `budget`, each fixture fails exactly its clause as tabled in Step 1 and the clean runs pass.
Run `nix fmt` and `nix fmt -- --fail-on-change`; commit with a plain message, for example "Check the store's series and row budget every hour on magnetite"; open pull request 3 with the same kind of title, its body stating in words the container run (commit, host, date, and that each budget fixture failed its clause) rather than a log path.
Expected: nixbot green, including `otel-envelope` and `nixos-magnetite`.

- [ ] **Step 5: Deploy magnetite (tasks.md 7.5)**

In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty`:

```bash
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.

- [ ] **Step 6: The drop-in control and the first hourly run (tasks.md 7.6)**

rehearse: magnetite (in the rehearsal, the `install`, `start` and `rm` commands are echoed):

```bash
L=logs/s4-evidence/7.6-dropin-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee "$L"
set -uo pipefail
d=/run/systemd/system/otel-envelope.service.d
sudo install -d "$d"
printf '[Service]\nEnvironment=OTEL_ENVELOPE_MAX_UNITS=27\nEnvironment=OTEL_ENVELOPE_FORCE_HOURLY=1\n' | sudo tee "$d/zz-max-units.conf" >/dev/null
sudo systemctl daemon-reload
sudo systemctl start otel-envelope; rc=$?; echo "rc=$rc"
sudo journalctl -u otel-envelope -o cat -n 30 | grep -E '^otel-envelope: B'
sleep 60; sudo tail -n 2 /var/lib/observability-notify/failed.log
sudo rm "$d/zz-max-units.conf"; sudo systemctl daemon-reload
sudo systemctl start otel-envelope; rc=$?; echo "rc=$rc"
EOS
```

Expected: the first start `rc=1` (the job failed) with `B3 per-host: FAIL magnetite systemd_unit_name 28` or the current count above 27; one `failed.log` line for `otel-envelope.service`; the operator receives `FAILED otel-envelope.service on magnetite` on `fleet-alerts`; the second start `rc=0` and a `RESOLVED` post.
At the next full hour, record the scheduled run's duration (`systemctl show otel-envelope -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic`) and the store's `MemoryCurrent` before and during it (`systemctl show greptimedb -p MemoryCurrent`), appended to `$L` (design D8's `[INFERENCE]` about the scan's cost).
