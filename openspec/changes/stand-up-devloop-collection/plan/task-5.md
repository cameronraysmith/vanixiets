### Task 5: Per-rule database and language, and the burn rule (deploy D5)

Implements `tasks.md` 5.1–5.8 (design D1, D2, D16, D17; plan review F7; FAI `The pull-request queue-wait rule reads devloop through SQL`, `The evaluator queries each rule's database as the regulators' store account`, `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Alerts are posted to fleet-alerts with a title and a severity priority`, `Store errors and silent hosts freeze instance state`; FA `Pull-request builds that wait too long to start reach a person as a warning`, `Each known failure class on a host reaches a person as an alert`, `An unreachable telemetry store or a silent host freezes alerts`; DCI `devloop-ingest shows the collection path and the reconcile able to fail`).
The burn-rule timeline leg is written first, from the `fleet-alerting-interface` scenario `The timeline is replayed`, and built against today's rules and evaluator, where it fails because no rule answers it (RED, 5.1).
Then the regulator of review F7 is written before the code it judges: the reference model `model.py` and the property test `test_transition.py` learn per-database store failures from the spec scenarios, and fail against today's `transition.jq` adapted only to read the new `storeErrors` field as "any failure freezes everything" (RED), after which `transition.jq` freezes only the failing database's instances and raises one `StoreQueryFailing` per failing database (GREEN), with the mutant `allDatabasesFreeze` rejected by the property part.
Then the rule table gains `database`, `language` and `PullRequestQueueWaitBurn` (5.2), the fixture server's refusal controls are rewritten and seen failing against today's server before the server learns `/v1/sql` and `--databases` (5.3), the store-error legs are rewritten and `devloopFailureLeg` is added, and the evaluator learns per-rule routing and per-database collection, after which every leg, the new ones included, passes (GREEN, 5.4).
The two-database leg and its mutant `everyQueryToFleet`, and the fixture side of `allDatabasesFreeze` on `devloopFailureLeg`, come after GREEN, because the behaviour they judge already exists by then; each mutant is its leg's negative control (5.5).
For the burn rule alone `transition.jq` and `model.py` would not change, as design D17 expects: an SQL rule has an `expr`, so `conditions` (`transition.jq:72-77`, `model.py:58-66`) evaluates it from `results`, its one `value` column leaves the instance with no labels, so the host freeze does not apply (`transition.jq:95`) and `title` omits the host, and `for = 3600` fires on the 61st minutely run by `advance` (`transition.jq:108`); they change only for review F7, whose decision is that a failed `devloop` query must not freeze `fleet` alerts.
The `devloop-ingest` case `burnRule` then runs the rule's expression on GreptimeDB 1.2.1 with D1's three loads, each load's "no row" shown non-vacuous by an expression mutant that returns a row on it (5.6).

**Files:**
- Modify: `modules/checks/fleet-alert.nix` (header `1-37`; `checkConfig` `383-400`; `vector` `415-427`; `ruleAnswers` `470-482`; `storeErrorLeg` `553-573`; `storeThawLeg` `607-623`; after `retryLeg` `756-770`; `legs` `772-792`; `runStep` `825`; `runLeg` `829-872`; `runtimeMutants` `880-923`, `noStoreFreeze` `899-900`; `controlResponses` `941-943`; `serverControls` `946-989`; `fixtureRehearsal` `1015-1018`; `noRepostTransition` `1041-1043`; `propertyRehearsal` `1053-1067`)
- Modify: `modules/checks/fleet-alert/fixture_server.py` (whole file, 136 lines today)
- Modify: `modules/nixos/fleet-alert/rules.nix` (header `6`, `25`; `rule` `61-67`; the rule list between `138` and `139`; `StoreQueryFailing`'s summary `143`; `yaml` `187`)
- Modify: `modules/nixos/fleet-alert.nix` (header `5-11`; `database=$(setting database)` `90`; `query` and `collect` `107-187`; the collection call `189-192`; observations `207`, `215`; the closing store-error line `265-267`; the dead-man's observations `419`; `evaluatorConfig` `529`)
- Modify: `modules/nixos/fleet-alert/transition.jq` (header `11-13`; after `66`; `conditions` `68-89`; `frozen` `91-97`; `advance` `106`; `post_for` title `126` and after `128`; `transition` `162`, `171`)
- Modify: `modules/checks/fleet-alert/model.py` (docstring `10-11`; after `48`; `conditions` and `frozen` `51-96`; `advance` `113`; `transition` `187-191`, `200`, `208`, title `214`)
- Modify: `modules/checks/fleet-alert/test_transition.py` (docstring `3-13`; rules `30-55`; `build` `105`; `step_strategy` `151`; the silent test `229`; `unobserved_resolves` `246-269`; two properties after `305`; `__main__` after `316`)
- Modify: `modules/vm-tests/devloop-ingest.nix` (Task 3's file, extended by Task 4: a `burnAlertRule` binding and the `burnRule` case appended to `cases` after `reconcile`)
- Modify: `openspec/changes/stand-up-devloop-collection/tasks.md:60-65` (ticks 5.1–5.6)
- Unchanged, shown by the commit's file list: `modules/checks/fleet-alert/fixtures/series.json`
- Evidence (git-ignored): `logs/s2-evidence/5.*-*.log`

**Interfaces:**
- Consumes (S3): `flake.lib.fleetAlertRules { lib; notifiedUnits; }` returning `{ rules; json; yaml; }` (`modules/nixos/fleet-alert/rules.nix:27-191`); `flake.lib.fleetAlertEvaluator pkgs { ntfySend; transition ? <transition.jq>; }` (`modules/nixos/fleet-alert.nix:62-268`); the check's `let` names `evaluatorRules`, `ruleNamed`, `mutateText`, `checkConfig`, `realConfig`, `realEvaluator`, `vector`, `stepAnswers`, `responsesFile`, `runLeg`, `runtimeMutants`, `oomRuns`, `seriesOn`, `minute`, `both`.
- Consumes (Task 2): the `devloop` database and its `ci_build` table on magnetite, created by `greptimedb-schema` with the allow-list columns `build_id` int64, `created_at`, `started_at`, `finished_at` timestamps, `eval_duration_ms` int64, `status` string, `pr_number` int64, `branch` string, key `build_id`, time index `finished_at`.
- Consumes (Tasks 3 and 4): `vmTests.x86_64-linux.devloop-ingest` at `modules/vm-tests/devloop-ingest.nix`, its `let` list `cases` ending in Task 4's `reconcile`, and the `helpers.py` functions `gsql(query, db="devloop")` (as `regulator`, returns `records.rows`), `admin_sql(query, db="devloop")` and `reset_devloop()`, with the case protocol `=== case <name>` first, `ok: <name>` last and `mutant <name> rejected: <reason>`.
- Consumes (S1): the store account `regulator` (`ro`), whose password the evaluator loads as `regulator-password`.
- Produces: every element of `fleetAlertRules`' `rules` and `json` but `StoreQueryFailing` carries `database` (default `"fleet"`) and `language` (`"promql"`, the default, or `"sql"`); `StoreQueryFailing` has neither, since it has no database of its own (review F7); `PullRequestQueueWaitBurn` is `{ alert = "PullRequestQueueWaitBurn"; database = "devloop"; language = "sql"; expr = <the plan head's expression>; for = "1h"; severity = "warning"; annotations.summary = …; presence = [ ]; attribution = [ ]; }`; `yaml` holds only rules with an `expr` and `language == "promql"`.
- Produces: the evaluator configuration `{ storeUrl, user, queryTimeoutSec, queryDeadlineSec, postDeadlineSec, topic, heartbeatTopic, stateFile, failedLog, rules }`, without `database`; the evaluator queries a `promql` rule as `GET /v1/prometheus/api/v1/query` with `x-greptime-db-name: <database>` and an `sql` rule as `POST /v1/sql?db=<database>` with form field `sql`, presence selectors and attribution queries in their rule's database, and `system_memory_usage_bytes` in `RuleSignalMissing`'s database; a failed query on a database skips that database's remaining queries in the run and leaves the others' running.
- Produces (review F7): observations `{ storeErrors, results, presence, reporting, failedLog, windows?, attribution? }`, `storeErrors` the sorted list of databases that failed in the run (`[]` when all answered), replacing the boolean `storeError` with no alias, written by the evaluator and as `[]` by `fleetAlertDeadman`; in `transition.jq` and `model.py`, an instance carries its rule's `database` (absent on `StoreQueryFailing`; an instance or rule without one is on `fleet`), is store-frozen when that database is in `storeErrors`, and `StoreQueryFailing` is one instance per failing database labelled `{ database = <db>; }`, never frozen, titled `[FIRING] StoreQueryFailing <db>` and `[RESOLVED] StoreQueryFailing <db>` (the database in the host's place, no host), its message carrying `the store did not answer queries on <db>`; `reporting` and `state.hosts` are read and updated only when `RuleSignalMissing`'s database answered; the `transition.jq` helpers `store_errors($observations)`, `database_of($x)`, `store_failed($observations; $database)`, `reporting_database($rules)` and the `model.py` functions `store_errors`, `database_of`, `reporting_database`, `frozen(alert, labels, database, observations)`.
- Produces: the fixture server CLI `fixture_server.py --responses <file> --databases <file> --step-file <file> --port-file <file>`, `--databases` a JSON object from query text to database; a SQL fixture answer `{ "records": { "schema": { "column_schemas": [ { "name", "data_type" } ] }, "rows": [ [ … ] ] } }` replayed as `{ "output": [ { "records": … } ], "execution_time_ms": 0 }`; stdout lines `REQUEST <step> <path> <database or -> <query>`, `UNEXPECTED <step> <query>`, `VIOLATION <text>`.
- Produces: in `checks.x86_64-linux.fleet-alert`, the `let` names `burnRuleLeg`, `devloopFailureLeg`, `twoDatabaseLeg`, `twoDatabaseRules`, `twoDatabaseConfig`, `sqlAnswer`, `queryDatabases`, `controlQuery`, `controlDatabases`, `allDatabasesFreezeTransition`, the runtime mutants `everyQueryToFleet` and `allDatabasesFreeze` (the latter also in the property part), a step field `sqlError` (the HTTP status every SQL rule's answer is replaced with), a leg field `recorded` (lines the server must log exactly once, without the `REQUEST ` prefix), and `checkConfig rulesList` returning `{ file; databases; }`; in `test_transition.py`, `DATABASES`, `FLEET_RULE_NAMES`, `RULE_DATABASE`, the rule `Dev` on `devloop`, and the properties `test_failure_freezes_only_its_database` and `test_store_query_failing_is_keyed_by_database`.
- Produces: the `devloop-ingest` case `burnRule`, last in `cases`, and the `let` binding `burnAlertRule`.

- [ ] **Step 1: Confirm the base**

Run from `$REPO`:

```bash
mkdir -p logs/s2-evidence
pwd
jj git fetch
jj log --no-graph -r 'main@origin' -T 'description.first_line() ++ "\n"'
nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -c '[.[] | .alert]'
nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -c '[.[] | select(has("database") or has("language")) | .alert]'
rg -c 'database' modules/nixos/fleet-alert.nix modules/checks/fleet-alert.nix
```

Expected: `pwd` prints `$REPO`; `main@origin` contains the merge of Task 4's pull request (`devloop-reconcile`); the first `nix eval` prints `["HostMemoryPressure","HostOOMKill","ZfsPoolUnhealthy","SystemdUnitRestartLoop","SystemdUnitFailed","LocalExporterDown","WeeklyPipelineTest","StoreQueryFailing","RuleSignalMissing"]` (read so on 2026-10-21); the second prints `[]`; `rg` prints `modules/nixos/fleet-alert.nix:4` (lines 22, 90, 122, 529) and `modules/checks/fleet-alert.nix:2` (lines 34, 388); if a count differs, read the hits before editing.
If any differs, stop and report to the orchestrator.

- [ ] **Step 2: Record the vendor facts this task relies on**

Run:

```bash
{
  for f in src/servers/src/http/handler.rs src/servers/src/http.rs src/servers/src/http/result/greptime_result_v1.rs src/servers/src/http/result/error_result.rs; do
    echo "=== GreptimeTeam/greptimedb@v1.2.1:$f"
    gh api "repos/GreptimeTeam/greptimedb/contents/$f?ref=v1.2.1" --jq .content | base64 -d > "/tmp/$(basename "$f")"
  done
  sed -n '61,63p;118,131p;140,140p;184,184p' /tmp/handler.rs
  sed -n '291,338p;395,400p;1310,1310p;1320,1320p' /tmp/http.rs
  sed -n '29,38p' /tmp/greptime_result_v1.rs
  sed -n '26,30p;92,95p' /tmp/error_result.rs
  gh api 'repos/GreptimeTeam/greptimedb/contents/src/sql/src/parsers/truncate_parser.rs?ref=v1.2.1' --jq .content | base64 -d | sed -n '24,28p'
  nix eval --impure --raw --expr 'let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux; in "curl ${p.curl.version} jq ${p.jq.version} python ${p.python3.version} prometheus ${p.prometheus.version}\n"'
} 2>&1 | tee logs/s2-evidence/5.0-vendor-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected, as read on 2026-10-21:
- `handler.rs:61-63`: `SqlQuery { db: Option<String>, sql: Option<String>, … }`; `:118-131`: `sql` takes `Query<SqlQuery>` and `Form<SqlQuery>` and sets the schema from `query_params.db.or(form_params.db)`; `:140`: `let sql = query_params.sql.or(form_params.sql);`; `:184`: the default format `GreptimedbV1`.
- `http.rs:291-338`: `ColumnSchema { name, data_type }`, `OutputSchema { column_schemas }`, `HttpRecordsOutput { schema, rows: Vec<Vec<Value>>, total_rows, … }`, so a row is an array in column order; `:395-400`: `GreptimeQueryOutput` is `AffectedRows(usize)` or `Records(HttpRecordsOutput)`, serialized lowercase as `affectedrows` and `records`; `:1310`: `.route("/sql", routing::get(handler::sql).post(handler::sql))`; `:1320`: `"/promql"`, a store path the evaluator does not use.
- `greptime_result_v1.rs:29-38`: `GreptimedbV1Response { output: Vec<GreptimeQueryOutput>, execution_time_ms }`, `output` omitted when empty.
- `error_result.rs:26-30` and `:92-95`: an error is `{ code, error, execution_time_ms }` with a non-200 HTTP status mapped from `code`.
- `truncate_parser.rs:24-28`: `TRUNCATE [TABLE] table_name` parses (used by Step 27).
- `curl 8.22.0 jq 1.8.2 python 3.14.7 prometheus 3.15.0`; curl has had `--url-query` since 7.87.0.
If any line differs, stop and report: Steps 16, 20 and 27 depend on these shapes.

- [ ] **Step 3: Record the evaluation cost before the change**

Run:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath 2>&1 | tee logs/s2-evidence/5.5-eval-cost-before-$(date -u +%Y%m%dT%H%M%SZ).log
jq '{gcTotalBytes: .gc.totalBytes, cpuTime, method: "NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath"}' /tmp/fleet-alert-stats.json | tee -a logs/s2-evidence/5.5-eval-cost-before-*.log
```

Expected: a `/nix/store/…-fleet-alert.drv` path and `gcTotalBytes` near `328149136` (0.306 GiB, design D17, measured 2026-10-21 at S3 review B); Tasks 1 to 4 changed magnetite's configuration, which the check reads, so a figure up to about 0.33 GiB is the new baseline and is recorded as such.

- [ ] **Step 4: Write the burn-rule timeline leg (tasks.md 5.1)**

In `modules/checks/fleet-alert.nix`, insert after line 770 (the `};` closing `retryLeg`):

```nix

      # The fleet-alerting-interface scenario `The timeline is replayed`
      # (stand-up-devloop-collection design D17; tasks.md 5.1): the burn
      # rule's SQL answers one row, value 0.15, on 65 consecutive runs (runs
      # 1-65, indices 0-64), then no row. The expected posts are the spec's:
      # one FIRING at priority default on the 61st run (index 60), nothing on
      # runs 62-65 while the row persists, so a re-posting evaluator fails,
      # and one RESOLVED 5 min after the row disappears, on run 70 (index
      # 69), both titled without a host.
      burnRuleLeg = {
        name = "PullRequestQueueWaitBurn answered 0.15 on 65 runs fires once on the 61st, posts nothing on the 62nd to 65th, and resolves once 5 min after its row disappears";
        steps = map (n: {
          at = minute n;
          series = lib.optionalAttrs (n <= 64) { PullRequestQueueWaitBurn = [ { value = 0.15; } ]; };
        }) (lib.range 0 69);
        expect = [
          "60 [FIRING] PullRequestQueueWaitBurn default"
          "69 [RESOLVED] PullRequestQueueWaitBurn default"
        ];
        messages = [ "value 0.15" ];
      };
```

In the `legs` list, replace today's line 791:

```nix
          retryLeg
```

with:

```nix
          retryLeg
          burnRuleLeg
```

The two compared values are the scenario's posts, literal here, and the posts the evaluator makes from the rule table, the fixture answer and `transition.jq`.
The insertion adds 21 lines after line 770 and one after line 791, so today's lines 771–791 move down by 21 and lines from 792 by 22; later steps quote the text they replace.

- [ ] **Step 5: Show the leg failing (RED, tasks.md 5.1)**

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.fleet-alert.fixtureRehearsal 2>&1 | tee logs/s2-evidence/5.1-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(MISS|ok:|mutant .* rejected|FAIL|PullRequestQueueWaitBurn)'
```

Expected: the build fails; the only `MISS` lines are `MISS PullRequestQueueWaitBurn answered 0.15 on 65 runs …: the alert posts differ from the expected list` and `MISS …: no posted message carries: value 0.15`, with the diff showing `-60 [FIRING] PullRequestQueueWaitBurn default` and `-69 [RESOLVED] PullRequestQueueWaitBurn default`; `ok: fixture server refusals and the concurrency guard` is printed; the five lines `mutant forZero rejected: …`, `mutant noAbsenceFreeze rejected: …`, `mutant noHostsUpdate rejected: …`, `mutant noStateWrite rejected: …`, `mutant noStoreFreeze rejected: …` are printed; the last line is `FAIL: the evaluator failed these legs:` followed by the two misses.
The expected lines carry the run's index, so the scenario's 61st and 70th runs are `60` and `69`.
The leg fails because no rule named `PullRequestQueueWaitBurn` exists, so `stepAnswers` holds no answer for it and the evaluator never queries it; the 16 existing legs pass.

- [ ] **Step 6: Extend the reference model to per-database store failures (review F7; tasks.md 5.1)**

The model is extended from the spec scenarios `The dev-loop database stops answering` (FA) and `Store errors and silent hosts freeze instance state` (FAI) as review F7 decided, not from `transition.jq`: a failed database freezes only the instances whose rule is on it, raises one `StoreQueryFailing` labelled with it, and leaves `reporting` and the hosts' last reports alone unless it is `RuleSignalMissing`'s database.

In `modules/checks/fleet-alert/model.py`, replace lines 10-11:

```python
never, an `info` with no RESOLVED and not counted; a store error freezes
every instance but StoreQueryFailing; a host without
```

with:

```python
never, an `info` with no RESOLVED and not counted; a failed query on a
database freezes every instance whose rule is on that database and raises
one StoreQueryFailing per failing database, labelled `database`, which is
never frozen; `reporting` and the hosts' last reports are read from
RuleSignalMissing's database (stand-up-devloop-collection review F7); a
rule or instance without `database` is on fleet; a host without
```

Insert after line 48 (`INTERNAL = ("StoreQueryFailing", "RuleSignalMissing")`):

```python


def store_errors(observations):
    """The databases whose queries failed in the run."""
    return observations.get("storeErrors") or []


def database_of(entry):
    """A rule's or an instance's database; one without the field is on fleet."""
    return entry.get("database") or "fleet"


def reporting_database(rules):
    """The database system_memory_usage_bytes, and so `reporting`, is read from."""
    return database_of(rule_named(rules, "RuleSignalMissing") or {})
```

Replace lines 51-96, from `def conditions(observations, rules, hosts, now):` to `    return host not in (observations.get("reporting") or [])` closing `frozen`, with:

```python
def conditions(observations, rules, hosts, now):
    errors = store_errors(observations)
    found = []
    failing = rule_named(rules, "StoreQueryFailing")
    if failing is not None:
        found += [(failing, {"database": database}, "1") for database in errors]
    windows = observations.get("windows") or {}
    results = observations.get("results") or {}
    for rule in rules:
        if database_of(rule) in errors:
            continue
        # A rule with an `expr`, or one whose alert has a results entry (a
        # caller's own query, such as the dead-man's AlertEvaluatorSilent).
        if "expr" not in rule and (rule["alert"] in INTERNAL or rule["alert"] not in results):
            continue
        if rule.get("window") is not None and windows.get(rule["alert"]) is not True:
            continue
        for series in results.get(rule["alert"]) or []:
            labels = {k: v for k, v in series["labels"].items() if k != "__name__"}
            found.append((rule, labels, str(series["value"])))
    missing = rule_named(rules, "RuleSignalMissing")
    if missing is not None:
        reporting = observations.get("reporting") or []
        presence = observations.get("presence") or {}
        for rule in rules:
            if database_of(rule) in errors:
                continue
            for selector in rule.get("presence") or []:
                if presence.get(selector["selector"]):
                    continue
                if any(host in reporting for host in selector["expectedHosts"]):
                    found.append((missing, {"rule": rule["alert"], "selector": selector["selector"]}, "0"))
        if reporting_database(rules) not in errors:
            for host in missing.get("alwaysOn") or []:
                if host not in reporting and now - hosts.get(host, now) >= ABSENT_AFTER:
                    found.append(
                        (dict(missing, **{"for": 0}), {"selector": "system_memory_usage_bytes", "host_name": host}, "0")
                    )
    return found


def frozen(alert, labels, database, observations):
    if alert == "StoreQueryFailing":
        return False
    if database in store_errors(observations):
        return True
    if alert == "RuleSignalMissing":
        return False
    host = labels.get("host_name")
    if host is None:
        return False
    return host not in (observations.get("reporting") or [])
```

Replace line 113:

```python
        nxt.update({"severity": rule["severity"], "for": rule["for"], "lastSeen": now, "absenceFrom": now})
```

with:

```python
        nxt.update(
            {
                "severity": rule["severity"],
                "for": rule["for"],
                "database": rule.get("database"),
                "lastSeen": now,
                "absenceFrom": now,
            }
        )
```

Replace lines 187-191:

```python
        if instance is not None:
            alert, labels = instance["alert"], instance["labels"]
        else:
            alert, labels = condition[0]["alert"], condition[1]
        if frozen(alert, labels, observations):
```

with:

```python
        if instance is not None:
            alert, labels, database = instance["alert"], instance["labels"], database_of(instance)
        else:
            alert, labels, database = condition[0]["alert"], condition[1], database_of(condition[0])
        if frozen(alert, labels, database, observations):
```

Replace line 200:

```python
    if not observations["storeError"]:
```

with:

```python
    if reporting_database(rules) not in store_errors(observations):
```

Replace line 208:

```python
        if instance is None or frozen(instance["alert"], instance["labels"], observations):
```

with:

```python
        if instance is None or frozen(instance["alert"], instance["labels"], database_of(instance), observations):
```

Replace line 214:

```python
                    "title": title(kind, instance["alert"], instance["labels"].get("host_name") or ""),
```

with:

```python
                    # StoreQueryFailing names its database where a host would stand.
                    "title": title(
                        kind,
                        instance["alert"],
                        (instance["labels"].get("database") if instance["alert"] == "StoreQueryFailing" else None)
                        or instance["labels"].get("host_name")
                        or "",
                    ),
```

- [ ] **Step 7: Extend the property test with a second database (review F7; tasks.md 5.1)**

The generator spreads rules over `fleet` and `devloop` and draws each run's `storeErrors` from `[]`, `["devloop"]`, `["fleet"]` and `["devloop", "fleet"]`.
The new property `test_failure_freezes_only_its_database` relates two independently defined values: the `fleet` posts of a generated timeline, and the `fleet` posts of the same timeline with `devloop` removed from every run's `storeErrors`; `test_store_query_failing_is_keyed_by_database` relates the `StoreQueryFailing` instances made with the set of per-database ids written here from the spec.
The instance's new `database` field is left out of the compared state projection (`INSTANCE_FIELDS`), so the comparison judges freezing and keying, not the field's presence.

In `modules/checks/fleet-alert/test_transition.py`, replace lines 3-13:

```python
Hypothesis generates timelines of runs: the time step, a store error, the
hosts reporting system_memory_usage_bytes, each rule's firing hosts, and the
index of the first post that fails in that run (the posts before it
succeed, as the evaluator posts in order and stops at a failure). One jq
process folds each whole timeline through transition and mark_posted; the
model does the same; posts and state must be equal at every run. A second
property, written from the timeline alone, holds both to posting a RESOLVED
only after 5 min of absence observed while not frozen. The test
is derandomized, with no example database and no deadline, so it is a pure
function of its source and cannot flake the merge queue.
FLEET_ALERT_JQ_LIB names a directory holding transition.jq.
```

with:

```python
Hypothesis generates timelines of runs: the time step, the databases whose
queries failed (storeErrors, over fleet and devloop), the hosts reporting
system_memory_usage_bytes, each rule's firing hosts, and the index of the
first post that fails in that run (the posts before it succeed, as the
evaluator posts in order and stops at a failure). One jq process folds each
whole timeline through transition and mark_posted; the model does the same;
posts and state must be equal at every run. Further properties, written
from the timeline alone, hold both to posting a RESOLVED only after 5 min
of absence observed while not frozen, to leaving fleet's posts unchanged by
a devloop failure, and to one StoreQueryFailing per failing database
(stand-up-devloop-collection review F7). The test is derandomized, with no
example database and no deadline, so it is a pure function of its source
and cannot flake the merge queue.
FLEET_ALERT_JQ_LIB names a directory holding transition.jq.
```

Replace lines 30-55, from `def rule(alert, seconds, severity):` to `RULE_NAMES = ["Crit", "Warn", "Info"]`, with:

```python
DATABASES = ["fleet", "devloop"]


def rule(alert, seconds, severity, database="fleet"):
    return {
        "alert": alert,
        "database": database,
        "expr": alert.lower(),
        "for": seconds,
        "severity": severity,
        "annotations": {"summary": alert},
        "presence": [],
        "attribution": [],
    }


# Crit, Warn and Info on fleet, Dev on devloop; StoreQueryFailing has no
# database of its own, as in rules.nix.
RULES = [
    rule("Crit", 0, "critical"),
    rule("Warn", 120, "warning"),
    rule("Info", 0, "info"),
    rule("Dev", 60, "critical", "devloop"),
    {
        "alert": "StoreQueryFailing",
        "for": 180,
        "severity": "critical",
        "annotations": {"summary": "store"},
        "presence": [],
        "attribution": [],
    },
]
RULE_NAMES = ["Crit", "Warn", "Info", "Dev"]
FLEET_RULE_NAMES = ["Crit", "Warn", "Info"]
RULE_DATABASE = {r["alert"]: r["database"] for r in RULES if "database" in r}
```

Replace line 105:

```python
                    "storeError": step["storeError"],
```

with:

```python
                    "storeErrors": step["storeErrors"],
```

Replace line 151:

```python
        "storeError": st.sampled_from([False, False, False, False, True]),
```

with:

```python
        "storeErrors": st.sampled_from([[], [], [], [], ["devloop"], ["fleet"], ["devloop", "fleet"]]),
```

Replace line 229:

```python
                    "storeError": False,
```

with:

```python
                    "storeErrors": [],
```

Replace line 237, where `RULES[3]` would now be `Dev`:

```python
    timeline = {"rules": [silent, RULES[3], missing], "steps": steps}
```

with:

```python
    timeline = {"rules": [silent, model.rule_named(RULES, "StoreQueryFailing"), missing], "steps": steps}
```

Replace lines 246-269, from `    Written from the timeline alone (design D11, D15): an instance is frozen on` to the `                ]` closing `seen`, with:

```python
    Written from the timeline alone (design D11, D15; review F7): an instance
    is frozen on a run when its rule's database is in storeErrors or its host
    does not report (StoreQueryFailing never), seen when unfrozen and in the
    results, and absent otherwise; StoreQueryFailing for a database is seen
    exactly when that database failed.
    Absence counts from the run it was last seen on or, after a freeze, from
    the first unfrozen run; a RESOLVED is due once that count reaches
    RESOLVE_AFTER, and stays due, across later freezes, until it is seen.
    """
    candidates = {
        model.instance_id("StoreQueryFailing", {"database": database}): ("StoreQueryFailing", None, database)
        for database in DATABASES
    }
    for alert in RULE_NAMES:
        for host in HOSTS:
            candidates[model.instance_id(alert, {"host_name": host})] = (alert, host, RULE_DATABASE[alert])
    since = dict.fromkeys(candidates)
    due = dict.fromkeys(candidates, False)
    found = []
    for index, (step, planned) in enumerate(zip(timeline["steps"], posts)):
        observations, now = step["observations"], step["now"]
        errors = observations["storeErrors"]
        for iid, (alert, host, database) in candidates.items():
            if alert == "StoreQueryFailing":
                frozen, seen = False, database in errors
            else:
                frozen = database in errors or host not in observations["reporting"]
                seen = not frozen and host in [
                    s["labels"]["host_name"] for s in observations["results"][alert]
                ]
```

Insert after line 305 (the `    )` closing `test_resolve_follows_unfrozen_absence`):

```python


def every_post_succeeds(timeline):
    """The timeline with no failed post, so removing one database's posts cannot shift another's."""
    return {"rules": timeline["rules"], "steps": [dict(step, failAt=None) for step in timeline["steps"]]}


def without_devloop_failures(timeline):
    """The same timeline with devloop removed from every run's storeErrors."""
    steps = []
    for step in timeline["steps"]:
        errors = [database for database in step["observations"]["storeErrors"] if database != "devloop"]
        steps.append(dict(step, observations=dict(step["observations"], storeErrors=errors)))
    return {"rules": timeline["rules"], "steps": steps}


def on_fleet(post):
    alert, entries = json.loads(post["id"])
    return alert in FLEET_RULE_NAMES or (
        alert == "StoreQueryFailing" and entries == [{"key": "database", "value": "fleet"}]
    )


def fleet_posts(result):
    return [[post for post in run if post["kind"] != "budget" and on_fleet(post)] for run in result["posts"]]


# A devloop failure leaves every fleet instance as it is without it (review
# F7): fleet's posts, StoreQueryFailing for fleet among them, are those of
# the same timeline with devloop removed from every run's storeErrors.
@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_failure_freezes_only_its_database(steps):
    timeline = every_post_succeeds(build(steps))
    twin = without_devloop_failures(timeline)
    for name, run in (("transition.jq", run_jq), ("model", run_model)):
        assert fleet_posts(run(timeline)) == fleet_posts(run(twin)), f"{name}: a devloop failure changed fleet's posts"


# StoreQueryFailing is one instance per failing database, labelled with it,
# and its title names that database.
@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_store_query_failing_is_keyed_by_database(steps):
    timeline = build(steps)
    allowed = {model.instance_id("StoreQueryFailing", {"database": database}) for database in DATABASES}
    for name, run in (("transition.jq", run_jq), ("model", run_model)):
        got = run(timeline)
        failing = [
            post
            for posts in got["posts"]
            for post in posts
            if post["kind"] != "budget" and json.loads(post["id"])[0] == "StoreQueryFailing"
        ]
        ids = {post["id"] for post in failing}
        ids |= {iid for iid, inst in got["state"]["instances"].items() if inst["alert"] == "StoreQueryFailing"}
        assert ids <= allowed, f"{name}: StoreQueryFailing instances {sorted(ids - allowed)}"
        titles = [
            post["title"]
            for post in failing
            if not post["title"].endswith(" StoreQueryFailing " + json.loads(post["id"])[1][0]["value"])
        ]
        assert not titles, f"{name}: StoreQueryFailing titles without their database {titles}"
```

Insert after line 316 (the last `print` of `__main__`):

```python
    test_failure_freezes_only_its_database()
    print("ok: a devloop failure leaves fleet's posts as they are without it")
    test_store_query_failing_is_keyed_by_database()
    print("ok: StoreQueryFailing is one instance per failing database, labelled and titled with it")
```

- [ ] **Step 8: Adapt today's `transition.jq` to the new field only (review F7; tasks.md 5.1)**

So that the RED of Step 9 is about the freeze's scope and not the field's name, `transition.jq` reads `storeErrors` with today's meaning, any failure freezing every instance.
In `modules/nixos/fleet-alert/transition.jq`, replace line 69:

```jq
  if $observations.storeError then
```

with:

```jq
  if (($observations.storeErrors // []) | length) > 0 then
```

Replace line 93:

```jq
  elif $observations.storeError then true
```

with:

```jq
  elif (($observations.storeErrors // []) | length) > 0 then true
```

Replace line 171:

```jq
      | if $observations.storeError then .
```

with:

```jq
      | if (($observations.storeErrors // []) | length) > 0 then .
```

- [ ] **Step 9: Show the property part failing (RED, review F7; tasks.md 5.1)**

Run, from `$REPO`, each of the three comparisons on their own with the pinned Python, Hypothesis and jq, then the property part:

```bash
props() {
  nix shell --impure --expr 'let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.${builtins.currentSystem}; in { python = p.python3.withPackages (ps: [ ps.hypothesis ]); jq = p.jq; }' python jq \
    -c env FLEET_ALERT_JQ_LIB="$PWD/modules/nixos/fleet-alert" PYTHONPATH="$PWD/modules/checks/fleet-alert" HOME="$(mktemp -d)" \
    python3 -c "import test_transition as t; t.$1()"
}
{
  for test in test_transition_matches_model test_failure_freezes_only_its_database test_store_query_failing_is_keyed_by_database; do
    echo "=== $test"
    if props "$test"; then echo "PASSED: $test"; else echo "FAILED: $test"; fi
  done
  nix build --no-link -L .#checks.x86_64-linux.fleet-alert.propertyRehearsal
} 2>&1 | tee logs/s2-evidence/5.4-f7-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(=== |PASSED|FAILED|Falsifying|AssertionError|error:)'
```

Expected: `FAILED:` for each of the three, each after a `Falsifying example` and an `AssertionError`: `test_transition_matches_model` on a run where the model and `transition.jq` post or keep different instances (`run <n>: model posts …` or `final state differs`), `test_failure_freezes_only_its_database` with `transition.jq: a devloop failure changed fleet's posts`, and `test_store_query_failing_is_keyed_by_database` with `transition.jq: StoreQueryFailing instances ['["StoreQueryFailing",[]]']`; the `nix build` fails with `error: builder for '…-fleet-alert-property.drv' failed`; no `PASSED:` line.
The model's own side passes each property; the failures are `transition.jq`'s, which still freezes every instance on any failure and keys `StoreQueryFailing` by no label.

- [ ] **Step 10: Freeze only the failing database's instances in `transition.jq` (review F7; tasks.md 5.4)**

In `modules/nixos/fleet-alert/transition.jq`, replace lines 11-13:

```jq
# info instance posts no RESOLVED and is not counted. A store error freezes
# every instance but StoreQueryFailing; a host missing from `reporting`
# (system_memory_usage_bytes) freezes the instances labelled with it.
```

with:

```jq
# info instance posts no RESOLVED and is not counted. A database in
# $observations.storeErrors freezes every instance whose rule is on it (a
# rule or an instance without `database` is on fleet) and raises one
# StoreQueryFailing per failing database, labelled `database` and never
# frozen; `reporting` (system_memory_usage_bytes) and state.hosts come from
# RuleSignalMissing's database, and a host missing from `reporting` freezes
# the instances labelled with it (stand-up-devloop-collection review F7).
```

Insert after line 66 (`def internal_rule($alert): …`):

```jq

def store_errors($observations): $observations.storeErrors // [];
def database_of($x): $x.database // "fleet";
def store_failed($observations; $database): any(store_errors($observations) | .[]; . == $database);
def reporting_database($rules): database_of(rule_named($rules; "RuleSignalMissing") // {});
```

Replace lines 68-89 (`conditions`, as Step 8 left it) with:

```jq
def conditions($observations; $rules; $hosts; $now):
  ( rule_named($rules; "StoreQueryFailing") as $failing
    | if $failing == null then []
      else [ store_errors($observations) | .[] | {rule: $failing, labels: {database: .}, value: "1"} ] end )
  + [ $rules[] | . as $r
      | select(store_failed($observations; database_of($r)) | not)
      | select(has("expr")
               or ((internal_rule($r.alert) | not) and (($observations.results // {}) | has($r.alert))))
      | select(($r.window == null) or ($observations.windows[$r.alert] == true))
      | ($observations.results[$r.alert] // [])[]
      | {rule: $r, labels: (.labels | del(.__name__)), value: (.value | tostring)} ]
  + ( rule_named($rules; "RuleSignalMissing") as $missing
      | if $missing == null then [] else
          [ $rules[] | . as $r
            | select(store_failed($observations; database_of($r)) | not)
            | ($r.presence // [])[]
            | select((($observations.presence[.selector] // []) | length) == 0)
            | select(. as $p | any(($observations.reporting // [])[]; . as $h | any($p.expectedHosts[]; . == $h)))
            | {rule: $missing, labels: {rule: $r.alert, selector: .selector}, value: "0"} ]
          + ( if store_failed($observations; reporting_database($rules)) then [] else
                [ ($missing.alwaysOn // [])[] as $h
                  | select(any(($observations.reporting // [])[]; . == $h) | not)
                  | select($now - ($hosts[$h] // $now) >= absent_after)
                  | {rule: ($missing + {for: 0}), labels: {selector: "system_memory_usage_bytes", host_name: $h}, value: "0"} ]
              end )
        end );
```

Replace lines 91-97 (`frozen`) with:

```jq
def frozen($inst; $observations):
  if $inst.alert == "StoreQueryFailing" then false
  elif store_failed($observations; database_of($inst)) then true
  elif $inst.alert == "RuleSignalMissing" then false
  elif ($inst.labels.host_name // null) == null then false
  else (($inst.labels.host_name) as $h | any(($observations.reporting // [])[]; . == $h) | not)
  end;
```

Replace line 106:

```jq
            value: $cond.value, lastSeen: $now, absenceFrom: $now }
```

with:

```jq
            value: $cond.value, database: $cond.rule.database, lastSeen: $now, absenceFrom: $now }
```

Replace line 126:

```jq
  | { title: title($kind; $inst.alert; $host),
```

with:

```jq
  | { title: title($kind; $inst.alert;
            if $inst.alert == "StoreQueryFailing" then ($inst.labels.database // $host) else $host end),
```

The title's third part is the host for every other instance and the failing database for `StoreQueryFailing`, which has no host; `$host` keeps gating attribution.

Insert after line 128 (`      message: ( [ $inst.summary,`):

```jq
                   (if $inst.alert == "StoreQueryFailing" then "the store did not answer queries on \($inst.labels.database // "?")" else empty end),
```

Replace line 162:

```jq
        | if frozen(($inst // {alert: $cond.rule.alert, labels: $cond.labels}); $observations) then
```

with:

```jq
        | if frozen(($inst // {alert: $cond.rule.alert, labels: $cond.labels, database: $cond.rule.database}); $observations) then
```

Replace line 171 (as Step 8 left it):

```jq
      | if (($observations.storeErrors // []) | length) > 0 then .
```

with:

```jq
      | if store_failed($observations; reporting_database($rules)) then .
```

Line 172 (`        else .hosts += (reduce ($observations.reporting // [])[] as $h ({}; .[$h] = $now)) end`) and line 96 (the host freeze) stay byte-identical, because the `noHostsUpdate` and `noAbsenceFreeze` mutants replace them.

- [ ] **Step 11: Add the `allDatabasesFreeze` mutant to the property part and retarget `noStoreFreeze` (review F7; tasks.md 5.5)**

`allDatabasesFreeze` is the `transition.jq` of Step 10 with the store freeze widened to every instance whenever any database failed, the behaviour before review F7.

In `modules/checks/fleet-alert.nix`, replace (today 1041-1043):

```nix
      noRepostTransition =
        mutantTransition "noRepost" ''>= repost_every then "repost"''
          ''>= repost_every and false then "repost"'';
```

with:

```nix
      noRepostTransition =
        mutantTransition "noRepost" ''>= repost_every then "repost"''
          ''>= repost_every and false then "repost"'';
      # Review F7's negative control: any failed database freezes every
      # instance, as before per-database freezing.
      allDatabasesFreezeTransition =
        mutantTransition "allDatabasesFreeze" "  elif store_failed($observations; database_of($inst)) then true\n"
          "  elif (store_errors($observations) | length) > 0 then true\n";
```

In `propertyRehearsal`, replace (today 1053):

```nix
            meta.description = "D11: transition.jq equals the reference model on derandomized Hypothesis timelines, and the no-re-post mutant is caught";
```

with:

```nix
            meta.description = "D11, review F7: transition.jq equals the reference model on derandomized Hypothesis timelines, a devloop failure leaves fleet's posts alone, and the no-re-post and allDatabasesFreeze mutants are caught";
```

and replace (today 1067):

```nix
            echo "mutant noRepost rejected"
```

with:

```nix
            echo "mutant noRepost rejected"
            if FLEET_ALERT_JQ_LIB=${jqLibOf "allDatabasesFreeze" allDatabasesFreezeTransition} python3 ${./fleet-alert}/test_transition.py > all-databases-freeze.log 2>&1; then
              cat all-databases-freeze.log
              echo "FAIL: the property test accepted the allDatabasesFreeze mutant" >&2
              exit 1
            fi
            cat all-databases-freeze.log
            grep -q 'Falsifying' all-databases-freeze.log
            echo "mutant allDatabasesFreeze rejected"
```

In `runtimeMutants`, replace (today 899-900):

```nix
            mutantTransition "noStoreFreeze" "  elif $observations.storeError then true\n"
              "  elif $observations.storeError then false\n"
```

with:

```nix
            mutantTransition "noStoreFreeze" "  elif store_failed($observations; database_of($inst)) then true\n"
              "  elif store_failed($observations; database_of($inst)) then false\n"
```

Replace header lines 18-20:

```nix
# - propertyRehearsal: fleet-alert/test_transition.py compares transition.jq
#   with the reference model fleet-alert/model.py over derandomized
#   Hypothesis timelines, and must fail on the no-re-post mutant.
```

with:

```nix
# - propertyRehearsal: fleet-alert/test_transition.py compares transition.jq
#   with the reference model fleet-alert/model.py over derandomized
#   Hypothesis timelines over two databases, holds both to leaving fleet's
#   posts unchanged by a devloop failure (stand-up-devloop-collection
#   review F7), and must fail on the no-re-post and allDatabasesFreeze
#   mutants.
```

- [ ] **Step 12: Show the property part passing, both mutants rejected (GREEN, review F7; tasks.md 5.4)**

Run, with `props` as in Step 9:

```bash
{
  for test in test_transition_matches_model test_failure_freezes_only_its_database test_store_query_failing_is_keyed_by_database; do
    echo "=== $test"
    if props "$test"; then echo "PASSED: $test"; else echo "FAILED: $test"; fi
  done
  nix build --no-link -L .#checks.x86_64-linux.fleet-alert.propertyRehearsal
} 2>&1 | tee logs/s2-evidence/5.4-f7-green-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(=== |PASSED|FAILED|ok:|mutant .* rejected|FAIL)|fleet-alert-property> (ok:|mutant)'
```

Expected: `PASSED:` for each of the three; the property part prints its six `ok:` lines, the four of today and `ok: a devloop failure leaves fleet's posts as they are without it` and `ok: StoreQueryFailing is one instance per failing database, labelled and titled with it`, then `mutant noRepost rejected` and `mutant allDatabasesFreeze rejected`, and builds; no `FAILED:` and no `FAIL`.
The two values the new property relates hold as review F7 decided: a `devloop` failure leaves `fleet`'s posts as they are without it, and the mutant that freezes everything on any failure breaks both that property and the model comparison.

- [ ] **Step 13: Give every rule a database and a language, and add the burn rule (tasks.md 5.2)**

In `modules/nixos/fleet-alert/rules.nix`, replace line 6:

```nix
# `yaml`, a Prometheus rules file of the rules with an expression, written as
```

with:

```nix
# `yaml`, a Prometheus rules file of the `promql` rules, written as
```

Insert after line 25 (`# charter v20).`):

```nix
#
# Every rule but StoreQueryFailing carries `database` (default "fleet") and
# `language` ("promql", the default, or "sql"); the evaluator sends a promql
# rule to the PromQL API with x-greptime-db-name and an sql rule as POST
# /v1/sql?db=<database> (stand-up-devloop-collection design D2).
# StoreQueryFailing has no database of its own: transition.jq raises one
# instance per failing database (review F7). RuleSignalMissing's `database`
# is the one the evaluator reads system_memory_usage_bytes from, the
# selector `reporting` comes from. PullRequestQueueWaitBurn (design D1)
# reads devloop's ci_build in SQL, which promtool cannot parse;
# vmTests.x86_64-linux.devloop-ingest's burnRule case runs it on GreptimeDB
# 1.2.1.
```

Replace lines 61-67:

```nix
      rule =
        r:
        {
          presence = [ ];
          attribution = [ ];
        }
        // r;
```

with:

```nix
      rule =
        r:
        {
          presence = [ ];
          attribution = [ ];
        }
        // lib.optionalAttrs (r.alert != "StoreQueryFailing") {
          database = "fleet";
          language = "promql";
        }
        // r;
```

Insert between line 138 (the `}` closing `WeeklyPipelineTest`) and line 139 (the `{` opening `StoreQueryFailing`):

```nix
        {
          alert = "PullRequestQueueWaitBurn";
          database = "devloop";
          language = "sql";
          expr = "SELECT CAST(sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) AS DOUBLE) / count(*) AS value FROM ci_build c JOIN (SELECT build_id, min(finished_at) AS first_finished FROM ci_build GROUP BY build_id) f ON c.build_id = f.build_id AND c.finished_at = f.first_finished WHERE c.pr_number IS NOT NULL AND c.started_at IS NOT NULL AND c.finished_at >= now() - INTERVAL '24 hours' HAVING count(*) >= 10 AND sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) * 10 > count(*)";
          for = "1h";
          severity = "warning";
          annotations.summary = "More than one in ten of the at least 10 pull-request builds whose first attempt finished in the last 24 h waited over an hour to start; the value is that share";
        }
```

Replace line 143 (`StoreQueryFailing`'s summary):

```nix
          annotations.summary = "The telemetry store has not answered the evaluator's queries; every other alert instance is frozen";
```

with:

```nix
          annotations.summary = "The telemetry store has not answered the evaluator's queries on the database named below for 3 min; the alert instances on that database are frozen, and those on other databases are evaluated as usual";
```

Replace line 187:

```nix
            rules = map promRule (builtins.filter (r: r ? expr) rules);
```

with:

```nix
            rules = map promRule (builtins.filter (r: r ? expr && r.language == "promql") rules);
```

`json` (line 182) needs no change: `r // { for = seconds r.for; }` carries `database` and `language`.

- [ ] **Step 14: Verify the rendered rules (tasks.md 5.2)**

Run:

```bash
{
  nix build --no-link -L .#checks.x86_64-linux.fleet-alert.promtoolRehearsal
  nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -c '.[] | select(.alert == "PullRequestQueueWaitBurn") | {database, language, for, severity, presence, attribution}'
  nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -c '[.[] | select(.database != "fleet" or .language != "promql") | .alert], [.[] | select(has("database") and has("language") | not) | .alert]'
  diff <(nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -r '.[] | select(.alert == "PullRequestQueueWaitBurn") | .expr') \
    <(rg -o -r '$1' '`expr` is `(SELECT[^`]+)`' openspec/changes/stand-up-devloop-collection/specs/fleet-alerting-interface/spec.md) && echo "expr equals the spec scenario"
  nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.yaml | jq -c '[.groups[0].rules[].alert]'
} 2>&1 | tee logs/s2-evidence/5.2-rules-$(date -u +%Y%m%dT%H%M%SZ).log | grep -vE '^(warning: Git tree|fleet-alert-promtool> *$)'
```

Expected: the promtool part prints `SUCCESS: 7 rules found` for the rendered file, then promtool's parse error for the malformed file and `mutant malformedExpression rejected`; `{"database":"devloop","language":"sql","for":3600,"severity":"warning","presence":[],"attribution":[]}`; `["PullRequestQueueWaitBurn","StoreQueryFailing"]` and `["StoreQueryFailing"]` (`StoreQueryFailing` has no database of its own, review F7); `expr equals the spec scenario` (the scenario `The rule's expression is rendered`); the YAML's alerts are the seven `HostMemoryPressure` … `WeeklyPipelineTest`, without `PullRequestQueueWaitBurn`.

- [ ] **Step 15: Rewrite the fixture side of the check for SQL, databases and per-database store errors (tasks.md 5.3, 5.5)**

Apply these edits to `modules/checks/fleet-alert.nix`, each located by the text it replaces (today's line numbers, before Step 4's shift, in parentheses).

Replace `serverControls` (today 946-989) whole, from `      serverControls = ''` to its closing `      '';`, with:

```nix
      serverControls = ''
        echo "--- the fixture server refuses other paths, databases and accounts, replays SQL as GreptimeDB does, and detects two open requests"
        control=$(mktemp -d)
        echo 0 > "$control/step"
        python3 ${fixtureServer} --responses ${controlResponses} --databases ${controlDatabases} \
          --step-file "$control/step" --port-file "$control/port" > "$control/server.log" 2>&1 &
        server_pid=$!
        for _ in $(seq 100); do [ -s "$control/port" ] && break; sleep 0.1; done
        [ -s "$control/port" ] || { cat "$control/server.log" >&2; echo "FAIL: the control fixture server did not start" >&2; exit 1; }
        port=$(cat "$control/port")
        query_url="http://127.0.0.1:$port/v1/prometheus/api/v1/query"
        sql_url="http://127.0.0.1:$port/v1/sql"
        sql_arg=${lib.escapeShellArg "sql=${controlQuery}"}
        ask() {
          printf 'user = "%s"\n' "$1" | curl --config - --silent --output /dev/null --write-out '%{http_code}' "''${@:2}" || true
        }
        expect_code() {
          [ "$2" = "$3" ] || { echo "FAIL: fixture server: $1 answered $2, expected $3" >&2; exit 1; }
        }
        good=regulator:${fixturePassword}
        expect_code "the PromQL path" "$(ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 200
        expect_code "the SQL path" "$(ask "$good" --url-query 'db=devloop' --data-urlencode "$sql_arg" "$sql_url")" 200
        expect_code "another path" "$(ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "http://127.0.0.1:$port/v1/promql")" 404
        expect_code "a PromQL query without the database header" "$(ask "$good" --get --data-urlencode 'query=up' "$query_url")" 400
        expect_code "a PromQL query to another database" "$(ask "$good" -H 'x-greptime-db-name: devloop' --get --data-urlencode 'query=up' "$query_url")" 400
        expect_code "an SQL query without db" "$(ask "$good" --data-urlencode "$sql_arg" "$sql_url")" 400
        expect_code "an SQL query to another database" "$(ask "$good" --url-query 'db=fleet' --data-urlencode "$sql_arg" "$sql_url")" 400
        expect_code "another account on the PromQL path" "$(ask perses:${fixturePassword} -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        expect_code "another account on the SQL path" "$(ask perses:${fixturePassword} --url-query 'db=devloop' --data-urlencode "$sql_arg" "$sql_url")" 401
        expect_code "a wrong password" "$(ask regulator:wrong -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        printf 'user = "%s"\n' "$good" | curl --config - --silent --url-query 'db=devloop' --data-urlencode "$sql_arg" "$sql_url" > "$control/sql.json"
        jq -e '(.output | length) == 1 and (.output[0].records.schema.column_schemas | map(.name)) == ["value"] and .output[0].records.rows == []' "$control/sql.json" > /dev/null \
          || { cat "$control/sql.json" >&2; echo "FAIL: fixture server: the SQL answer is not GreptimeDB's output[0].records shape" >&2; exit 1; }
        python3 -c 'import socket, sys, time; s = socket.create_connection(("127.0.0.1", int(sys.argv[1]))); time.sleep(10)' "$port" &
        holder=$!
        sleep 1
        ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url" > /dev/null
        for _ in $(seq 50); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.1; done
        if kill -0 "$server_pid" 2>/dev/null; then
          kill "$server_pid" "$holder" 2>/dev/null || true
          echo "FAIL: the fixture server kept serving with two requests open" >&2
          exit 1
        fi
        server_status=0
        wait "$server_pid" || server_status=$?
        server_pid=
        kill "$holder" 2>/dev/null || true
        if [ "$server_status" = 0 ] || ! grep -q '^VIOLATION two requests open at once' "$control/server.log"; then
          cat "$control/server.log" >&2
          echo "FAIL: the fixture server did not record two open requests" >&2
          exit 1
        fi
        echo "ok: fixture server refusals, the SQL answer shape and the concurrency guard"
      '';
```

Replace `controlResponses` (today 941-943):

```nix
      controlResponses = pkgs.writeText "fleet-alert-control-responses.json" (
        builtins.toJSON { "0".up = vector t0 [ ]; }
      );
```

with:

```nix
      controlQuery = "SELECT 1 AS value";
      controlResponses = pkgs.writeText "fleet-alert-control-responses.json" (
        builtins.toJSON {
          "0" = {
            up = vector t0 [ ];
            "${controlQuery}" = sqlAnswer [ ];
          };
        }
      );
      controlDatabases = pkgs.writeText "fleet-alert-control-databases.json" (
        builtins.toJSON {
          up = "fleet";
          "${controlQuery}" = "devloop";
        }
      );
```

In `runLeg`, replace (today 847):

```nix
          python3 ${fixtureServer} --responses ${responsesFile leg} \
```

with:

```nix
          python3 ${fixtureServer} --responses ${responsesFile leg} --databases ${config.databases} \
```

and replace (today 854):

```nix
              '.storeUrl = $url | .stateFile = $state | .failedLog = $failed' ${config} > "$leg_dir/config.json"
```

with:

```nix
              '.storeUrl = $url | .stateFile = $state | .failedLog = $failed' ${config.file} > "$leg_dir/config.json"
```

In `legs`, replace the line Step 4 added:

```nix
          burnRuleLeg
```

with:

```nix
          burnRuleLeg
          devloopFailureLeg
```

In `runStep`, replace (today 825):

```nix
              || miss "${leg.name}: run ${i} queried again after a failed query"
```

with:

```nix
              || miss "${leg.name}: run ${i} did not send exactly ${toString step.requests} queries, the first of each database, which then failed"
```

Replace `storeThawLeg` (today 607-623), from `      storeThawLeg = {` to its closing `      };`, with the leg below, and insert `devloopFailureLeg` after it:

```nix
      storeThawLeg = {
        name = "HostOOMKill last seen before 7 runs of store error resolves 5 min after the store answers again, not on its first answer";
        steps =
          map oomRuns (lib.range 0 2)
          ++ map (n: {
            at = minute n;
            error = 503;
            requests = 2;
          }) (lib.range 3 9)
          ++ map (n: { at = minute n; }) (lib.range 10 16);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "6 [FIRING] StoreQueryFailing devloop high"
          "6 [FIRING] StoreQueryFailing fleet high"
          "14 [RESOLVED] StoreQueryFailing devloop high"
          "14 [RESOLVED] StoreQueryFailing fleet high"
          "15 [RESOLVED] HostOOMKill magnetite high"
        ];
      };

      # Review F7 (FA scenario `The dev-loop database stops answering`): the
      # burn rule's SQL answers 500 on runs 1 to 6 while fleet answers.
      # HostOOMKill, seen on run 0 only, resolves 5 min later on run 5,
      # inside the devloop failure; StoreQueryFailing for devloop, first
      # raised on run 1, fires on run 4 after its 3 min, names devloop, and
      # resolves 5 min after run 6, its last failing run.
      devloopFailureLeg = {
        name = "a devloop failure raises StoreQueryFailing for devloop after 3 min while HostOOMKill on fleet fires and resolves as usual";
        steps = [
          (oomRuns 0)
        ]
        ++ map (n: {
          at = minute n;
          sqlError = 500;
        }) (lib.range 1 6)
        ++ map (n: { at = minute n; }) (lib.range 7 11);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "4 [FIRING] StoreQueryFailing devloop high"
          "5 [RESOLVED] HostOOMKill magnetite high"
          "11 [RESOLVED] StoreQueryFailing devloop high"
        ];
        messages = [ "the store did not answer queries on devloop" ];
      };
```

Replace `storeErrorLeg` (today 553-573), from `      storeErrorLeg = {` to its closing `      };`, with:

```nix
      # Every answer of runs 1 to 8 is an error, so the first query of each
      # database fails and its other queries are skipped: two requests per
      # run, and one StoreQueryFailing for each of fleet and devloop.
      storeErrorLeg = {
        name = "a store error on fleet and devloop freezes a firing HostOOMKill, raises one StoreQueryFailing per database after 3 min, heartbeats, and resumes";
        steps = [
          {
            at = minute 0;
            series.HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          error = 503;
          requests = 2;
        }) (lib.range 1 8)
        ++ map (n: { at = minute n; }) (lib.range 9 14);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "4 [FIRING] StoreQueryFailing devloop high"
          "4 [FIRING] StoreQueryFailing fleet high"
          "13 [RESOLVED] StoreQueryFailing devloop high"
          "13 [RESOLVED] StoreQueryFailing fleet high"
          "14 [RESOLVED] HostOOMKill magnetite high"
        ];
        messages = [
          "the store did not answer queries on fleet"
          "the store did not answer queries on devloop"
        ];
      };
```

The two values these legs relate are the expected posts, written here from the FA and FAI scenarios as review F7 decided, and the posts the evaluator makes from the rule table, the fixture answers and `transition.jq`.

Replace `ruleAnswers` (today 470-482):

```nix
          ruleAnswers = lib.listToAttrs (
            map (
              r:
              lib.nameValuePair r.expr (
                vector step.at (
                  map (labels: {
                    metric = labels;
                    value = "1";
                  }) (series.${r.alert} or [ ])
                )
              )
            ) (builtins.filter (r: r ? expr) evaluatorRules)
          );
```

with:

```nix
          # A PromQL rule's series are label sets, each answered with value
          # "1"; an SQL rule's are rows, each { value = <number>; }, and a
          # step's `sqlError` replaces every SQL rule's answer with that HTTP
          # status.
          ruleAnswers = lib.listToAttrs (
            map (
              r:
              lib.nameValuePair r.expr (
                if r.language == "sql" then
                  if step ? sqlError then { status = step.sqlError; } else sqlAnswer (series.${r.alert} or [ ])
                else
                  vector step.at (
                    map (labels: {
                      metric = labels;
                      value = "1";
                    }) (series.${r.alert} or [ ])
                  )
              )
            ) (builtins.filter (r: r ? expr) evaluatorRules)
          );
```

Insert after `vector`'s closing `      };` (today 427):

```nix

      # An SQL answer in GreptimeDB 1.2.1's records shape
      # (GreptimeTeam/greptimedb@v1.2.1 src/servers/src/http.rs:291-338): the
      # column `value` and one array per row; no row keeps the schema, as
      # HttpRecordsOutput::try_new does for an empty result (:365-375).
      sqlAnswer = rows: {
        records = {
          schema.column_schemas = [
            {
              name = "value";
              data_type = "Float64";
            }
          ];
          rows = map (row: [ row.value ]) rows;
        };
      };
```

Replace `checkConfig` and `realConfig` (today 383-400):

```nix
      checkConfig =
        rulesList:
        pkgs.writeText "fleet-alert-check-config.json" (
          builtins.toJSON {
            storeUrl = "http://127.0.0.1:1";
            database = "fleet";
            user = "regulator";
            queryTimeoutSec = 10;
            queryDeadlineSec = 30;
            postDeadlineSec = 35;
            topic = "fleet-alerts";
            heartbeatTopic = "fleet-heartbeat";
            stateFile = "/nonexistent/state.json";
            failedLog = "/nonexistent/failed.log";
            rules = rulesList;
          }
        );
      realConfig = checkConfig evaluatorRules;
```

with:

```nix
      # The evaluator's configuration for a rule list, and the database each
      # query of that list belongs to, which the fixture server enforces.
      checkConfig = rulesList: {
        file = pkgs.writeText "fleet-alert-check-config.json" (
          builtins.toJSON {
            storeUrl = "http://127.0.0.1:1";
            database = "fleet";
            user = "regulator";
            queryTimeoutSec = 10;
            queryDeadlineSec = 30;
            postDeadlineSec = 35;
            topic = "fleet-alerts";
            heartbeatTopic = "fleet-heartbeat";
            stateFile = "/nonexistent/state.json";
            failedLog = "/nonexistent/failed.log";
            rules = rulesList;
          }
        );
        databases = queryDatabases rulesList;
      };
      realConfig = checkConfig evaluatorRules;

      # The database of every query the evaluator may send, read from each
      # rule's declared `database` (stand-up-devloop-collection design D2,
      # D17): its expression, presence selectors and attribution queries in
      # its own, and the reporting selector system_memory_usage_bytes in
      # RuleSignalMissing's. The fixture server answers 400 to a query sent
      # to any other database, so the evaluator's routing is judged against
      # the rule table.
      queryDatabases =
        rulesList:
        let
          missing =
            lib.findFirst (r: r.alert == "RuleSignalMissing") (throw "fleet-alert check: no RuleSignalMissing rule")
              rulesList;
          pairs = [
            {
              query = "count by (host_name) (system_memory_usage_bytes)";
              inherit (missing) database;
            }
          ]
          ++ lib.concatMap (
            r:
            lib.optional (r ? expr) {
              query = r.expr;
              inherit (r) database;
            }
            ++ map (p: {
              query = "count by (host_name) (${p.selector})";
              inherit (r) database;
            }) r.presence
            ++ lib.concatMap (
              a:
              map (host: {
                query = builtins.replaceStrings [ "<host>" ] [ host ] a.query;
                inherit (r) database;
              }) both
            ) r.attribution
          ) rulesList;
          byQuery = lib.mapAttrs (_: ps: lib.unique (map (p: p.database) ps)) (lib.groupBy (p: p.query) pairs);
          conflicting = lib.filterAttrs (_: ds: builtins.length ds > 1) byQuery;
        in
        assert lib.assertMsg (
          conflicting == { }
        ) "fleet-alert check: queries declared in two databases: ${builtins.toJSON conflicting}";
        pkgs.writeText "fleet-alert-databases.json" (builtins.toJSON (lib.mapAttrs (_: builtins.head) byQuery));
```

`database = "fleet";` stays in `file` until Step 19, because today's evaluator still reads it.
The two values the server relates are the database each rule declares in `rules.nix`, read here into `--databases`, and the database the evaluator's request carries, read by the server from the header or `db`.

- [ ] **Step 16: Show the refusal controls failing against today's server (RED, tasks.md 5.3)**

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.fleet-alert.fixtureRehearsal 2>&1 | tee logs/s2-evidence/5.3-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(unrecognized arguments|FAIL|ok:)'
```

Expected: the build fails at the controls with `fixture_server.py: error: unrecognized arguments: --databases …` from the server log, then `FAIL: the control fixture server did not start`; no `ok:` line.

- [ ] **Step 17: Write the fixture server (tasks.md 5.3)**

Replace `modules/checks/fleet-alert/fixture_server.py` whole with:

```python
"""Loopback stand-in for GreptimeDB's PromQL instant-query and SQL APIs.

checks.x86_64-linux.fleet-alert runs the evaluator against this server
(S3 design D19, S2 design D17; fleet-alerting-interface "The evaluator
queries each rule's database as the regulators' store account"). It serves
GET and POST /v1/prometheus/api/v1/query, the query in `query` and the
database in the `x-greptime-db-name` header, and GET and POST /v1/sql, the
query in `sql` and the database in `db` (GreptimeTeam/greptimedb@v1.2.1
src/servers/src/http/handler.rs:118-140), from responses[<step>][<query>],
where <step> is the content of --step-file, read per request. A PromQL
answer is a Prometheus JSON body. An SQL answer is {"records": {"schema":
..., "rows": ...}}, replayed as {"output": [{"records": ...}],
"execution_time_ms": 0} (src/servers/src/http/result/
greptime_result_v1.rs:29-38, src/servers/src/http.rs:291-338, 395-400).
{"status": <code>} is an error on either path. --databases maps each query
to the database its rule declares.

Every request on either path is recorded as REQUEST <step> <path>
<database or -> <query> before it is judged. It answers 404 to any other
path, 401 to any account but `regulator` with the fixture password, and
400 to a query sent to a database other than its own. A query with no
declared database, no answer, or an answer of the other path's kind gets
500 and an UNEXPECTED line. If two connections are ever open at once it
prints a VIOLATION line and exits 1, so a leg fails if the evaluator
queries concurrently (S3 design D13). Everything it records is a line on
stdout: REQUEST, UNEXPECTED, VIOLATION.
"""

import argparse
import base64
import binascii
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

PROMQL_PATH = "/v1/prometheus/api/v1/query"
SQL_PATH = "/v1/sql"
FIXTURE_USER = "regulator"
# The same value checks.x86_64-linux.fleet-alert writes to the fixture
# credentials' regulator-password.
FIXTURE_PASSWORD = "00112233445566778899aabbccddeeff"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--responses", required=True)
    parser.add_argument("--databases", required=True)
    parser.add_argument("--step-file", required=True)
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    with open(args.responses) as f:
        responses = json.load(f)
    with open(args.databases) as f:
        databases = json.load(f)

    lock = threading.Lock()
    connections = {"open": 0}

    def record(line):
        print(line, flush=True)

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        # Counted from accept, so a client holding a connection without
        # sending counts as one open request.
        def process_request(self, request, client_address):
            with lock:
                connections["open"] += 1
                if connections["open"] > 1:
                    record("VIOLATION two requests open at once")
                    os._exit(1)
            super().process_request(request, client_address)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.counted = True

        # Released before the answer is sent, so the evaluator's next query,
        # which starts only after it has read this answer, never overlaps.
        def release(self):
            if self.counted:
                self.counted = False
                with lock:
                    connections["open"] -= 1

        def finish(self):
            try:
                super().finish()
            finally:
                self.release()

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.release()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def credentials(self):
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Basic "):
                return None
            try:
                user, _, password = base64.b64decode(auth[6:]).decode().partition(":")
            except (binascii.Error, UnicodeDecodeError):
                return None
            return user, password

        def answer(self):
            url = urlsplit(self.path)
            form = parse_qs(url.query)
            if self.command == "POST":
                length = int(self.headers.get("Content-Length") or 0)
                form.update(parse_qs(self.rfile.read(length).decode()))
            if url.path == PROMQL_PATH:
                query = form.get("query", [""])[0]
                database = self.headers.get("x-greptime-db-name")
            elif url.path == SQL_PATH:
                query = form.get("sql", [""])[0]
                database = form.get("db", [None])[0]
            else:
                return self.reply(404, {"status": "error", "error": "not found"})
            with open(args.step_file) as f:
                step = f.read().strip()
            record(f"REQUEST {step} {url.path} {database or '-'} {query}")
            if self.credentials() != (FIXTURE_USER, FIXTURE_PASSWORD):
                return self.reply(401, {"status": "error", "error": "unauthorized"})
            declared = databases.get(query)
            if declared is None:
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "no database is declared for this query"})
            if database != declared:
                return self.reply(400, {"status": "error", "error": f"this query belongs to {declared}"})
            body = responses.get(step, {}).get(query)
            if body is None:
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "no fixture for this query"})
            if set(body) == {"status"} and isinstance(body["status"], int):
                return self.reply(body["status"], {"status": "error", "errorType": "fixture", "error": "replayed error"})
            if (url.path == SQL_PATH) != (set(body) == {"records"}):
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "the fixture answers the other path"})
            if url.path == SQL_PATH:
                return self.reply(200, {"output": [body], "execution_time_ms": 0})
            return self.reply(200, body)

        do_GET = answer
        do_POST = answer

        def log_message(self, *args):
            pass

    server = Server(("127.0.0.1", 0), Handler)
    with open(args.port_file, "w") as f:
        f.write(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
```

- [ ] **Step 18: Show the refusal controls passing (GREEN for 5.3)**

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.fleet-alert.fixtureRehearsal 2>&1 | tee logs/s2-evidence/5.3-refusals-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(ok: fixture server|FAIL: fixture server|HTTP 400 for query)' | sort | uniq -c
```

Expected: `ok: fixture server refusals, the SQL answer shape and the concurrency guard` once, which follows the 200 on both paths, the 404 for `/v1/promql`, the 400 for each path (header absent, header `devloop`, `db` absent, `db=fleet`) and the 401 on both paths; no `FAIL: fixture server` line.
The build still fails after the controls, by design: today's evaluator sends the burn rule's SQL to the PromQL path with `x-greptime-db-name: fleet`, the server answers 400 because `--databases` declares it `devloop`, every run becomes a store error, and the evaluator writes the boolean `storeError` that Step 10's `transition.jq` no longer reads, so the log holds many `fleet-alert: HTTP 400 for query: SELECT CAST(…` lines and every leg misses until Step 19.

- [ ] **Step 19: Route each query by its rule's database and language, and collect per database (tasks.md 5.4; review F7)**

In `modules/nixos/fleet-alert.nix`, replace lines 5-11:

```nix
# reads its configuration from the JSON at FLEET_ALERT_CONFIG, queries the
# store's PromQL API one query at a time as `regulator` (password from
# $CREDENTIALS_DIRECTORY/regulator-password, passed to curl on stdin, as
# modules/lib/greptimedb-envelope.nix does), each with --max-time
# queryTimeoutSec, and ends the query phase at the first failed query or at
# queryDeadlineSec: a store error, which transition.jq turns into a freeze
# and, after 3 min, StoreQueryFailing. It reads the notifier's failed.log,
```

with:

```nix
# reads its configuration from the JSON at FLEET_ALERT_CONFIG and queries
# the store one query at a time as `regulator`, each rule in its own
# `database` and `language` (stand-up-devloop-collection design D2): PromQL
# to /v1/prometheus/api/v1/query with x-greptime-db-name, SQL as POST
# /v1/sql?db=<database> with the form field sql (password from
# $CREDENTIALS_DIRECTORY/regulator-password, passed to curl on stdin, as
# modules/lib/greptimedb-envelope.nix does), each with --max-time
# queryTimeoutSec. A failed query, or the passing of queryDeadlineSec, ends
# querying of that database for the run while other databases' queries
# continue (review F7); the failed databases reach transition.jq as
# storeErrors, which freezes the instances on them and, after 3 min, raises
# one StoreQueryFailing per database. It reads the notifier's failed.log,
```

Replace line 90:

```nix
        database=$(setting database)
```

with:

```nix
        # system_memory_usage_bytes, which `reporting` reads, is queried in
        # RuleSignalMissing's database; the run fails without exactly one.
        reporting_database=$(jq -er '[.rules[] | select(.alert == "RuleSignalMissing") | .database]
          | if length == 1 then .[0] else error("the rules must list RuleSignalMissing exactly once") end' "$config")
```

Replace lines 107-187, from the comment line starting `        # One instant query;` to the `        }` closing `collect`, with:

```nix
        # One query of a rule's language in a rule's database: promql as an
        # instant query with x-greptime-db-name, sql as POST
        # /v1/sql?db=<database> with the form field sql. The answer lands in
        # $work/body as a Prometheus vector: an SQL answer must be 200 with
        # exactly one output holding records with a `value` column, and each
        # row becomes one result with that column as its value and every
        # other column as a label (GreptimeTeam/greptimedb@v1.2.1
        # src/servers/src/http.rs:291-338, 395-400). Fails on a transport
        # error, a timeout, any other status or body, or when the query
        # deadline has passed; ask_store below turns a failure into the
        # failure of the query's database for the run.
        query() {
          local language=$1 database=$2 expr=$3
          local remaining status
          local -a request
          remaining=$((query_deadline - SECONDS))
          if [ "$remaining" -le 0 ]; then
            echo "fleet-alert: query deadline of ''${query_deadline}s reached" >&2
            return 1
          fi
          if [ "$remaining" -gt "$query_timeout" ]; then
            remaining=$query_timeout
          fi
          case "$language" in
            promql)
              request=(--header "x-greptime-db-name: $database" --get --data-urlencode "query=$expr"
                "$store_url/v1/prometheus/api/v1/query")
              ;;
            sql)
              request=(--url-query "db=$database" --data-urlencode "sql=$expr" "$store_url/v1/sql")
              ;;
            *)
              printf 'fleet-alert: unknown query language %s for: %s\n' "$language" "$expr" >&2
              return 1
              ;;
          esac
          if ! status=$(printf 'user = "%s:%s"\n' "$user" "$(< "$credentials/regulator-password")" \
            | curl --config - --silent --show-error --max-time "$remaining" \
                --output "$work/answer" --write-out '%{http_code}' "''${request[@]}"); then
            printf 'fleet-alert: query failed: %s\n' "$expr" >&2
            return 1
          fi
          if [ "$status" != 200 ]; then
            printf 'fleet-alert: HTTP %s for query: %s\n' "$status" "$expr" >&2
            return 1
          fi
          if [ "$language" = sql ]; then
            if ! jq -e '(.output | length) == 1 and (.output[0] | has("records"))
                and any(.output[0].records.schema.column_schemas[]; .name == "value")' "$work/answer" > /dev/null; then
              printf 'fleet-alert: no single records answer with a value column for query: %s\n' "$expr" >&2
              return 1
            fi
            jq '.output[0].records as $records
              | [$records.schema.column_schemas[].name] as $columns
              | {status: "success", data: {resultType: "vector", result: [$records.rows[]
                  | [$columns, .] | transpose | map({key: .[0], value: .[1]}) | from_entries
                  | {metric: (del(.value) | map_values(tostring)), value: [null, (.value | tostring)]}]}}' \
              "$work/answer" > "$work/body"
          else
            mv -f "$work/answer" "$work/body"
          fi
          if ! jq -e '.status == "success" and .data.resultType == "vector"' "$work/body" > /dev/null; then
            printf 'fleet-alert: HTTP %s for query: %s\n' "$status" "$expr" >&2
            return 1
          fi
        }

        # Databases whose queries failed this run, each followed by a space
        # (review F7); names come from the rule table and hold no space.
        failed_databases=""

        # ask_store LANGUAGE DATABASE EXPR: query EXPR unless DATABASE has
        # already failed this run. A failed query marks DATABASE failed, so
        # its remaining rule, presence and attribution queries are skipped
        # while other databases' queries continue; once the query deadline
        # has passed every query fails, so a database not reached by then
        # counts as failed.
        ask_store() {
          if [[ " $failed_databases" == *" $2 "* ]]; then
            return 1
          fi
          if ! query "$1" "$2" "$3"; then
            failed_databases+="$2 "
            printf 'fleet-alert: the store did not answer queries on %s; its instances are frozen this run\n' "$2" >&2
            return 1
          fi
        }

        # Presence selectors, each in the database of the rule naming it, and
        # system_memory_usage_bytes, what `reporting` reads, in
        # RuleSignalMissing's; then rule expressions, each in its rule's
        # database and language; then attribution, in the attributing rule's
        # database, for the hosts in the results of rules that name
        # attribution queries. A query whose database has failed is skipped
        # and records nothing.
        collect() {
          local presence selector database language rule alert expr window inside host attr name label attr_query
          while IFS= read -r presence; do
            selector=$(jq -r .selector <<< "$presence")
            database=$(jq -r .database <<< "$presence")
            if ask_store promql "$database" "count by (host_name) ($selector)"; then
              jq -c --arg selector "$selector" \
                '{selector: $selector, hosts: [.data.result[].metric.host_name // empty]}' \
                "$work/body" >> "$work/presence.jsonl"
            fi
          done < <(jq -c --arg reporting "$reporting_database" \
            '[{selector: "system_memory_usage_bytes", database: $reporting}]
              + [.rules[] | .database as $database | .presence[]? | {selector, database: $database}]
              | unique | .[]' "$config")

          while IFS= read -r rule; do
            alert=$(jq -r .alert <<< "$rule")
            expr=$(jq -r .expr <<< "$rule")
            database=$(jq -r .database <<< "$rule")
            language=$(jq -r .language <<< "$rule")
            window=$(jq -c '.window // empty' <<< "$rule")
            if [ -n "$window" ]; then
              inside=$(TZ=$(jq -r .zone <<< "$window") jq -n -L "$jqlib" \
                --argjson window "$window" --argjson now "$now" \
                'include "transition"; in_window($window; $now)')
              jq -nc --arg alert "$alert" --argjson inside "$inside" \
                '{alert: $alert, inside: $inside}' >> "$work/windows.jsonl"
              if [ "$inside" != true ]; then
                continue
              fi
            fi
            if ask_store "$language" "$database" "$expr"; then
              jq -c --arg alert "$alert" \
                '{alert: $alert, result: [.data.result[] | {labels: .metric, value: .value[1]}]}' \
                "$work/body" >> "$work/results.jsonl"
            fi
          done < <(jq -c '.rules[] | select(has("expr"))' "$config")

          while IFS= read -r host; do
            if ! [[ "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
              printf 'fleet-alert: no attribution for host label %q\n' "$host" >&2
              continue
            fi
            while IFS= read -r attr; do
              name=$(jq -r .name <<< "$attr")
              label=$(jq -r '.label // ""' <<< "$attr")
              attr_query=$(jq -r .query <<< "$attr")
              database=$(jq -r .database <<< "$attr")
              if ask_store promql "$database" "''${attr_query//<host>/$host}"; then
                jq -c --arg host "$host" --arg name "$name" --arg label "$label" \
                  '{host: $host, name: $name, label: $label, result: .data.result}' \
                  "$work/body" >> "$work/attribution.jsonl"
              fi
            done < <(jq -c '[.rules[] | .database as $database | .attribution[]? | . + {database: $database}] | unique | .[]' "$config")
          done < <(jq -r --slurpfile results "$work/results.jsonl" '
            [.rules[] | select((.attribution // []) | length > 0) | .alert] as $attributed
            | [$results[] | select(.alert as $a | any($attributed[]; . == $a)) | .result[].labels.host_name // empty]
            | unique | .[]' "$config")
        }
```

Delete line 529 (inside `evaluatorConfig`):

```nix
            database = "fleet";
```

Replace lines 189-192:

```nix
        store_error=false
        if ! collect; then
          store_error=true
        fi
```

with:

```nix
        # As before review F7, a command other than a query failing inside
        # collect does not end the run; a failed query marks its database.
        collect || true
        store_errors=$(jq -cn --arg failed "$failed_databases" '$failed | split(" ") | map(select(. != "")) | unique')
```

Replace line 207:

```nix
        jq -n --argjson storeError "$store_error" \
```

with:

```nix
        jq -n --argjson storeErrors "$store_errors" \
```

Replace line 215:

```nix
            storeError: $storeError,
```

with:

```nix
            storeErrors: $storeErrors,
```

Replace lines 265-267:

```nix
        if [ "$store_error" = true ]; then
          echo "fleet-alert: the store did not answer; instances are frozen" >&2
        fi
```

with:

```nix
        if [ "$store_errors" != '[]' ]; then
          printf 'fleet-alert: the store did not answer queries on %s; the instances on them are frozen\n' \
            "$(jq -r 'join(", ")' <<< "$store_errors")" >&2
        fi
```

In `fleetAlertDeadman`, replace line 419:

```nix
          storeError: false,
```

with:

```nix
          storeErrors: [],
```

In `modules/checks/fleet-alert.nix`, delete the line `            database = "fleet";` inside `checkConfig`'s `file` (today line 388; Step 15 kept it there).

- [ ] **Step 20: Show every leg passing, the burn and devloop-failure legs included (GREEN, tasks.md 5.1, 5.4; review F7)**

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.fleet-alert.fixtureRehearsal 2>&1 | tee logs/s2-evidence/5.4-fixtures-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(--- |MISS|ok:|mutant .* rejected|FAIL)'
```

Expected: one `--- ` line per leg, 18 legs (the 16 existing, `storeErrorLeg` and `storeThawLeg` as Step 15 rewrote them, `PullRequestQueueWaitBurn answered 0.15 on 65 runs fires once on the 61st, posts nothing on the 62nd to 65th, and resolves once 5 min after its row disappears` and `a devloop failure raises StoreQueryFailing for devloop after 3 min while HostOOMKill on fleet fires and resolves as usual`); no `MISS` and no `FAIL`; `ok: fixture server refusals, the SQL answer shape and the concurrency guard`; the five existing `mutant … rejected` lines of Step 5, `noStoreFreeze` on its retargeted text; `ok: every leg passed`.
The devloop-failure leg's posts are `0 [FIRING] HostOOMKill magnetite high`, `4 [FIRING] StoreQueryFailing devloop high`, `5 [RESOLVED] HostOOMKill magnetite high` and `11 [RESOLVED] StoreQueryFailing devloop high`, and a FIRING message carries `the store did not answer queries on devloop`.
Within a run the posts follow the sorted instance ids, so `StoreQueryFailing devloop` precedes `StoreQueryFailing fleet` in `storeErrorLeg` and `storeThawLeg`.
The burn leg's posts equal `60 [FIRING] PullRequestQueueWaitBurn default` and `69 [RESOLVED] PullRequestQueueWaitBurn default` (the scenario's 61st and 70th runs), with nothing on indices 61 to 64 while the row persists, so the title carries no host, and its FIRING message carries `value 0.15`.

Then verify the delivered evaluator configuration on magnetite (build):

```bash
out=$(nix build --no-link --print-out-paths --impure --expr 'let f = builtins.getFlake (toString ./.); c = f.nixosConfigurations.magnetite; in c.pkgs.runCommand "fleet-alert-config-delivered" { } "cp ${c.config.systemd.services.fleet-alert.environment.FLEET_ALERT_CONFIG} $out"')
jq -c '[has("database"), [.rules[] | select(.database != "fleet" or .language != "promql") | {alert, database, language, for}]]' "$out" 2>&1 | tee logs/s2-evidence/5.4-magnetite-config-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `[false,[{"alert":"PullRequestQueueWaitBurn","database":"devloop","language":"sql","for":3600},{"alert":"StoreQueryFailing","database":null,"language":null,"for":180}]]`.

- [ ] **Step 21: Add the two-database leg and the `everyQueryToFleet` and `allDatabasesFreeze` fixture mutants (tasks.md 5.5; review F7)**

The clause relates two independently defined values: the database each rule declares in `modules/nixos/fleet-alert/rules.nix`, with the spec scenario's literals `fleet` and `devloop` beside it in the leg, and the database the evaluator's request carries, recorded by the fixture server.
The mutant `everyQueryToFleet` is the evaluator with `database=fleet` forced in `query`, which must fail the leg.
The fixture mutant `allDatabasesFreeze` is the evaluator over Step 11's `allDatabasesFreezeTransition`, which must fail `devloopFailureLeg`: the two values that leg relates are the posts the FA scenario `The dev-loop database stops answering` expects, written in the leg, and the posts the evaluator makes.

In `modules/checks/fleet-alert.nix`, insert after the `};` closing `burnRuleLeg` (Step 4):

```nix

      # Design D17's two-database leg (tasks.md 5.5): one PromQL rule on fleet
      # and the burn rule on devloop in one run. The server records each
      # request's path and database; the leg requires exactly one PromQL
      # request for HostOOMKill's expression on fleet and one /v1/sql request
      # for the burn rule's on devloop, the spec scenario's databases.
      twoDatabaseRules = builtins.filter (
        r:
        builtins.elem r.alert [
          "HostOOMKill"
          "PullRequestQueueWaitBurn"
          "StoreQueryFailing"
          "RuleSignalMissing"
        ]
      ) evaluatorRules;
      twoDatabaseConfig = checkConfig twoDatabaseRules;
      twoDatabaseLeg = {
        name = "one run queries HostOOMKill on fleet through PromQL and PullRequestQueueWaitBurn on devloop through SQL";
        steps = [
          {
            at = minute 0;
            series = {
              HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
              PullRequestQueueWaitBurn = [ { value = 0.15; } ];
            };
          }
        ];
        expect = [ "0 [FIRING] HostOOMKill magnetite high" ];
        recorded = [
          "0 /v1/prometheus/api/v1/query fleet ${(ruleNamed "HostOOMKill").expr}"
          "0 /v1/sql devloop ${(ruleNamed "PullRequestQueueWaitBurn").expr}"
        ];
      };
```

In `runLeg`, replace (today 862-864):

```nix
          if grep -E '^(VIOLATION|UNEXPECTED) ' "$leg_dir/server.log" >&2; then
            miss ${lib.escapeShellArg "${leg.name}: the fixture server recorded a violation or an unexpected query"}
          fi
```

with:

```nix
          if grep -E '^(VIOLATION|UNEXPECTED) ' "$leg_dir/server.log" >&2; then
            miss ${lib.escapeShellArg "${leg.name}: the fixture server recorded a violation or an unexpected query"}
          fi
          ${lib.concatMapStrings (line: ''
            [ "$(grep -cxF -- ${lib.escapeShellArg "REQUEST ${line}"} "$leg_dir/server.log")" = 1 ] \
              || miss ${lib.escapeShellArg "${leg.name}: the server did not record exactly one: REQUEST ${line}"}
          '') (leg.recorded or [ ])}
```

In `runtimeMutants`, replace the two closing lines (today 922-923):

```nix
        };
      };
```

that end `noHostsUpdate` and the attrset with:

```nix
        };
        everyQueryToFleet = {
          evaluator = realEvaluator.overrideAttrs (old: {
            text =
              mutateText "everyQueryToFleet" "local language=$1 database=$2 expr=$3"
                "local language=$1 database=fleet expr=$3"
                old.text;
          });
          config = twoDatabaseConfig;
          legs = [ twoDatabaseLeg ];
        };
        allDatabasesFreeze = {
          evaluator = evaluatorWith allDatabasesFreezeTransition;
          config = realConfig;
          legs = [ devloopFailureLeg ];
        };
      };
```

In `fixtureRehearsal`, replace (today 1015-1018):

```nix
            ${lib.concatMapStrings (runLeg {
              evaluator = lib.getExe realEvaluator;
              config = realConfig;
            }) legs}
```

with:

```nix
            ${lib.concatMapStrings (runLeg {
              evaluator = lib.getExe realEvaluator;
              config = realConfig;
            }) legs}
            ${runLeg {
              evaluator = lib.getExe realEvaluator;
              config = twoDatabaseConfig;
            } twoDatabaseLeg}
```

Replace header lines 1-2:

```nix
# checks.x86_64-linux.fleet-alert: regulator R9.2 (ADR-009 R9.2; design D10,
# D11, D13-D16, D19; tasks.md 4.5, 4.6).
```

with:

```nix
# checks.x86_64-linux.fleet-alert: regulator R9.2 (ADR-009 R9.2; design D10,
# D11, D13-D16, D19; tasks.md 4.5, 4.6; stand-up-devloop-collection design
# D17, tasks.md 5.1, 5.3-5.5).
```

Replace header lines 10-17:

```nix
#   fleet-alert/fixture_server.py, which replays canned answers to the
#   store's PromQL API per run. A leg is a timeline of runs at
#   FLEET_ALERT_NOW. Every run must record one heartbeat at priority min and
#   post only with NTFY_TOKEN_FILE naming the fixture credential, and the
#   alert posts of the leg must equal its list. The five runtime mutants
#   (no state write, `for` 0, no store freeze, no absence freeze, and no
#   update of when each host last reported) must each produce a non-empty
#   failure list.
```

with:

```nix
#   fleet-alert/fixture_server.py, which replays canned answers to the
#   store's PromQL and SQL APIs per run and answers 400 to a query sent to
#   any database but the one its rule declares. A leg is a timeline of runs
#   at FLEET_ALERT_NOW. Every run must record one heartbeat at priority min
#   and post only with NTFY_TOKEN_FILE naming the fixture credential, and
#   the alert posts of the leg must equal its list; the two-database leg
#   also requires the server to record each rule's query once on its path
#   and database. The seven runtime mutants (no state write, `for` 0, no
#   store freeze, no absence freeze, no update of when each host last
#   reported, every query sent to fleet, and every instance frozen when any
#   database fails) must each produce a non-empty failure list; the store
#   freezes only the instances of the database that failed (review F7).
```

Insert after header line 37 (`# here with the full-match semantics PromQL uses for `!~`.`):

```nix
# Nor can it run SQL: vmTests.x86_64-linux.devloop-ingest's burnRule case
# runs PullRequestQueueWaitBurn's query on GreptimeDB 1.2.1 (design D1, D16).
```

- [ ] **Step 22: Build the whole check, every mutant rejected, and measure its cost (tasks.md 5.5)**

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.fleet-alert 2>&1 | tee logs/s2-evidence/5.5-check-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(SUCCESS|ok:|mutant .* rejected|MISS|FAIL|Falsifying)'
```

Expected: `SUCCESS: 7 rules found` and `mutant malformedExpression rejected` (promtool part); `ok: fixture server refusals, the SQL answer shape and the concurrency guard`; seven runtime mutant lines in this order: `mutant allDatabasesFreeze rejected: a devloop failure raises StoreQueryFailing for devloop after 3 min while HostOOMKill on fleet fires and resolves as usual: the alert posts differ from the expected list`, `mutant everyQueryToFleet rejected: one run queries HostOOMKill on fleet through PromQL and PullRequestQueueWaitBurn on devloop through SQL: the server did not record exactly one: REQUEST 0 /v1/sql devloop SELECT CAST(…`, then `mutant forZero rejected: …`, `mutant noAbsenceFreeze rejected: …`, `mutant noHostsUpdate rejected: …`, `mutant noStateWrite rejected: …`, `mutant noStoreFreeze rejected: …`; `ok: every leg passed` (19 legs: the 18 of Step 20 and the two-database leg); the property part's six `ok:` lines of Step 12, its `Falsifying` examples, `mutant noRepost rejected` and `mutant allDatabasesFreeze rejected`; the dead-man's `ok:` lines, `ok: the probe mutant is rejected` and `ok: dead-man relations hold and 3 mutants are rejected`, the dead-man now writing `storeErrors: []`; no `MISS` from the real evaluator and no `FAIL`.
The property part changed with `transition.jq`, `model.py` and `test_transition.py` for review F7 (Steps 6 to 11), and its four earlier properties still pass, as Step 12 showed.

Run:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath 2>&1 | tee logs/s2-evidence/5.5-eval-cost-after-$(date -u +%Y%m%dT%H%M%SZ).log
jq '{gcTotalBytes: .gc.totalBytes, cpuTime, method: "NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath"}' /tmp/fleet-alert-stats.json | tee -a logs/s2-evidence/5.5-eval-cost-after-*.log
```

Expected: `gcTotalBytes` below `536870912` (0.5 GiB) and within about 0.02 GiB of Step 3's figure (design D17's estimate, `[INFERENCE]` until this step); record both figures, the difference and the method together.
If the figure is above 0.5 GiB, stop and report.

- [ ] **Step 23: Run the neighbouring checks and the configurations of magnetite and cinnabar**

Run: `nix build --no-link .#checks.x86_64-linux.otel-collector-config .#checks.x86_64-linux.greptimedb-envelope .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.nixos-cinnabar 2>&1 | tee logs/s2-evidence/5.5-neighbours-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 3`
Expected: all four build; magnetite's configuration changes only in `fleet-alert-config.json`, the evaluator script and the `transition.jq` it carries, and cinnabar's only in the dead-man script and its `transition.jq`, which write and read `storeErrors`.

- [ ] **Step 24: Add the burn-rule case to `devloop-ingest` (tasks.md 5.6)**

The case loads `ci_build` directly as `admin`, after `reset_devloop()` and with the collector stopped, rather than through nixbot fixtures and the collector: the rule judges whatever rows the store holds, the collection path is already the subject of Task 3's cases, and direct loads make each of the three counts exact and immediate, with no 60 s poll, no cursor and no ingest timestamps to arrange inside the 24 h window.
Because the collector is stopped, the case sends nothing through an exporter, so the `send_failed` assertion of the Global Constraints does not apply to it.
Each "no row" is shown non-vacuous: every filter and boundary of the expression has a mutant, the expression with that filter removed or that bound loosened, which must return a row on the load built to need it.

In `modules/vm-tests/devloop-ingest.nix`, in the `let` that defines `cases` (Task 3), add directly before `cases =`:

```nix
            # The burn rule as fleet-alert's evaluator sends it (design D1,
            # D16); the notified units shape only SystemdUnitFailed.
            burnAlertRule =
              lib.findFirst (r: r.alert == "PullRequestQueueWaitBurn")
                (throw "devloop-ingest: no PullRequestQueueWaitBurn rule")
                (self.lib.fleetAlertRules {
                  inherit lib;
                  notifiedUnits = [ ];
                }).rules;
            burnRule = ''
              print("=== case burnRule", flush=True)
              import datetime

              BURN_EXPR = json.loads(${builtins.toJSON (builtins.toJSON burnAlertRule.expr)})
              BURN_DB = ${builtins.toJSON burnAlertRule.database}
              assert ${builtins.toJSON burnAlertRule.language} == "sql", "PullRequestQueueWaitBurn is not an SQL rule"
              assert BURN_DB == "devloop", BURN_DB

              # ci_build holds exactly the rows each load writes as admin.
              reset_devloop()
              store.succeed("systemctl stop opentelemetry-collector.service")
              BURN_NOW = int(store.succeed("date -u +%s").strip())


              def burn_time(epoch):
                  return datetime.datetime.fromtimestamp(epoch, datetime.timezone.utc).strftime("%Y-%m-%dT%H:%M:%SZ")


              def burn_row(build_id, pr_number, wait_minutes, finished_hours_ago=2):
                  """A build finished finished_hours_ago h ago, started 5 min before,
                  created wait_minutes before it started; None never started."""
                  finished = BURN_NOW - finished_hours_ago * 3600
                  if wait_minutes is None:
                      created, started, status = finished - 600, "NULL", "cancelled"
                  else:
                      started_at = finished - 300
                      created = started_at - wait_minutes * 60
                      started, status = "'" + burn_time(started_at) + "'", "success"
                  pr = "NULL" if pr_number is None else str(pr_number)
                  branch = "main" if pr_number is None else f"pr-{pr_number}"
                  return (
                      f"({build_id}, '{burn_time(created)}', {started}, '{burn_time(finished)}', "
                      f"1000, '{status}', {pr}, '{branch}')"
                  )


              def burn_prs(first, slow, fast):
                  """slow pull-request builds that waited 90 min, then fast ones that waited 45,
                  close enough to the hour that a 30 min threshold counts them as slow."""
                  return [burn_row(first + i, 100 + first + i, 90) for i in range(slow)] + [
                      burn_row(first + slow + i, 100 + first + slow + i, 45) for i in range(fast)
                  ]


              def burn_restarted(build_id, pr_number):
                  """A pull-request build restarted after a fast first attempt: nixbot's
                  restart keeps created_at and resets started_at and finished_at
                  (Mic92/nixbot@d020013fa nixbot/nixbot/db_gen/maintenance.py:96-123),
                  so the second row's wait is over an hour."""
                  created = BURN_NOW - 4 * 3600
                  branch = f"pr-{pr_number}"
                  return [
                      f"({build_id}, '{burn_time(created)}', '{burn_time(created + 600)}', "
                      f"'{burn_time(created + 900)}', 1000, 'failure', {pr_number}, '{branch}')",
                      f"({build_id}, '{burn_time(created)}', '{burn_time(created + 5400)}', "
                      f"'{burn_time(created + 5700)}', 1000, 'success', {pr_number}, '{branch}')",
                  ]


              def burn_load(rows):
                  admin_sql('TRUNCATE TABLE "ci_build"', db=BURN_DB)
                  admin_sql(
                      'INSERT INTO "ci_build" ("build_id", "created_at", "started_at", "finished_at", '
                      '"eval_duration_ms", "status", "pr_number", "branch") VALUES ' + ", ".join(rows),
                      db=BURN_DB,
                  )
                  stored = gsql('SELECT count(*) FROM "ci_build"', db=BURN_DB)
                  assert stored == [[len(rows)]], (stored, len(rows))


              def burn_mutant(name, old, new):
                  assert old in BURN_EXPR, f"mutant {name} found nothing to replace"
                  return BURN_EXPR.replace(old, new)


              BURN_MUTANTS = {
                  "noPullRequestFilter": burn_mutant("noPullRequestFilter", "c.pr_number IS NOT NULL AND ", ""),
                  "noStartedFilter": burn_mutant("noStartedFilter", "c.started_at IS NOT NULL AND ", ""),
                  "minimumNine": burn_mutant("minimumNine", "count(*) >= 10", "count(*) >= 9"),
                  "noWindow": burn_mutant("noWindow", " AND c.finished_at >= now() - INTERVAL '24 hours'", ""),
                  "shareAtLeastATenth": burn_mutant("shareAtLeastATenth", "* 10 > count(*)", "* 10 >= count(*)"),
                  "everyAttempt": burn_mutant("everyAttempt", " AND c.finished_at = f.first_finished", ""),
                  "thresholdHalfHour": burn_mutant("thresholdHalfHour", "INTERVAL '1 hour'", "INTERVAL '30 minutes'"),
              }


              def burn_mutants_reject(load, names):
                  for name in names:
                      got = gsql(BURN_MUTANTS[name], db=BURN_DB)
                      assert len(got) == 1, f"mutant {name} accepted on {load}: {got}"
                      print(f"mutant {name} rejected: {load} gave {got}", flush=True)


              # 10 pull-request builds of which 2 waited over an hour: one row, 0.2,
              # in a column named value, which the evaluator requires.
              burn_load(burn_prs(1, 2, 8))
              rows = gsql(BURN_EXPR, db=BURN_DB)
              print(f"load 1: 10 builds, 2 waited over an hour: {rows}", flush=True)
              assert len(rows) == 1 and abs(rows[0][0] - 0.2) < 1e-9, rows
              named = gsql(f'SELECT "value" FROM ({BURN_EXPR}) AS burn', db=BURN_DB)
              assert named == rows, (named, rows)

              # 9 of which 2 did, beside a slow build with no pull request and a
              # pull-request build that never started: no row.
              burn_load(burn_prs(11, 2, 7) + [burn_row(20, None, 90), burn_row(21, 121, None)])
              rows = gsql(BURN_EXPR, db=BURN_DB)
              print(f"load 2: 9 builds, 2 waited over an hour: {rows}", flush=True)
              assert rows == [], rows
              burn_mutants_reject("load 2", ["noPullRequestFilter", "noStartedFilter", "minimumNine"])

              # 10 of which 1 did, the tenth a build restarted after a fast first
              # attempt whose second attempt waited over an hour, beside a slow
              # pull-request build that finished 25 h ago: no row.
              burn_load(burn_prs(31, 1, 8) + burn_restarted(40, 140) + [burn_row(50, 150, 90, finished_hours_ago=25)])
              rows = gsql(BURN_EXPR, db=BURN_DB)
              print(f"load 3: 10 builds, 1 waited over an hour, 1 restarted: {rows}", flush=True)
              assert rows == [], rows
              burn_mutants_reject("load 3", ["noWindow", "shareAtLeastATenth", "everyAttempt", "thresholdHalfHour"])

              # Leave the store as every earlier case does: tables reset and the
              # collector running.
              reset_devloop()
              collector_restart()
              print("ok: burnRule", flush=True)
            '';
```

In the `cases` list, add `burnRule` as the last element, after `reconcile` (Task 4).
The Python holds no `''` and no `${` of its own, so the Nix string ends only where shown.
Each mutant's row follows from its load: on load 2, without the pull-request filter 10 rows qualify with 3 slow, without the started filter 10 with 2 slow, and with a minimum of 9 the 9 rows with 2 slow give a share above a tenth; on load 3, without the window 11 first attempts qualify with 2 slow, with `>=` the 10 first attempts with 1 slow reach exactly a tenth, counting every attempt (`everyAttempt`) gives 11 rows with 2 slow, so the restarted build's second row would fire the rule, and a 30 min threshold (`thresholdHalfHour`, which replaces both occurrences of `INTERVAL '1 hour'`) counts the eight 45 min builds as slow, 9 of 10, while the restarted build's 10 min first attempt stays fast.
`burn_mutant` replaces every occurrence of its text; each other mutant's text occurs once in the expression.
The restarted build's two rows share `build_id` and differ in `finished_at`, the time index, so the store keeps both (`logs/s2/spike-dedup.md:15`); `burn_load`'s stored count of 12 rows on load 3 confirms it.
`[INFERENCE]` GreptimeDB 1.2.1 accepts `AS value` as a column alias, `HAVING` without `GROUP BY`, `c.started_at > c.created_at + INTERVAL '1 hour'` and the join on the first attempt per `build_id` (design D1, review F1); Step 27 confirms all four, and the wrapped `SELECT "value"` confirms the column name.

- [ ] **Step 25: Evaluate the container test**

Run:

```bash
nix eval --raw .#vmTests.x86_64-linux.devloop-ingest.drvPath 2>&1 | tee logs/s2-evidence/5.6-eval-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: a `/nix/store/…-vm-test-run-devloop-ingest.drv` path; an evaluation error naming `burnAlertRule` or the Nix string means Step 24's text was altered.

- [ ] **Step 26: Tick 5.1–5.5, format and commit**

In `openspec/changes/stand-up-devloop-collection/tasks.md`, with the edit tool, change only the leading `- [ ]` of lines 60 to 64 (items 5.1 to 5.5) to `- [x]`: 5.1 covers the burn-rule leg and review F7's two-database property with its RED (Steps 4 to 9), 5.2 the rules (Steps 13 and 14), 5.3 the fixture server (Steps 15 to 18), 5.4 the per-database `transition.jq` and evaluator (Steps 10, 12, 19 and 20), and 5.5 `devloopFailureLeg`, `allDatabasesFreeze` and the two-database leg (Steps 11, 15, 21 and 22).
Run: `rg -n '^- \[x\] 5\.[1-5] ' openspec/changes/stand-up-devloop-collection/tasks.md`
Expected: exactly five lines, 60 to 64.

Run:

```bash
nix fmt -- modules/nixos/fleet-alert.nix modules/nixos/fleet-alert/rules.nix modules/nixos/fleet-alert/transition.jq modules/checks/fleet-alert.nix modules/checks/fleet-alert/fixture_server.py modules/checks/fleet-alert/model.py modules/checks/fleet-alert/test_transition.py modules/vm-tests/devloop-ingest.nix 2>&1 | tee logs/s2-evidence/5.7-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
nix fmt -- --fail-on-change 2>&1 | tee -a logs/s2-evidence/5.7-fmt-*.log
```

Expected: both exit 0.
If the first reformatted a file, rerun Step 22's build and expect the same lines.

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(fleet-alert): per-rule database and language, SQL rules and the dev-loop burn rule'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(fleet-alert): per-rule database and language")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/nixos/fleet-alert.nix \
  modules/nixos/fleet-alert/rules.nix \
  modules/nixos/fleet-alert/transition.jq \
  modules/checks/fleet-alert.nix \
  modules/checks/fleet-alert/fixture_server.py \
  modules/checks/fleet-alert/model.py \
  modules/checks/fleet-alert/test_transition.py \
  modules/vm-tests/devloop-ingest.nix \
  openspec/changes/stand-up-devloop-collection/tasks.md
jj diff --name-only -r "$change"
echo "$change" > logs/s2-evidence/5.7-change-id.txt
```

Expected: the last command lists exactly `modules/checks/fleet-alert.nix`, `modules/checks/fleet-alert/fixture_server.py`, `modules/checks/fleet-alert/model.py`, `modules/checks/fleet-alert/test_transition.py`, `modules/nixos/fleet-alert.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/nixos/fleet-alert/transition.jq`, `modules/vm-tests/devloop-ingest.nix` and `openspec/changes/stand-up-devloop-collection/tasks.md`; `fixtures/series.json` is absent.
If `jj diff -r @ -- openspec/changes/stand-up-devloop-collection/tasks.md` showed hunks other than the five ticks before the squash, squash that file with `--interactive` and select only the ticks.

- [ ] **Step 27: Run `devloop-ingest` on the committed change (tasks.md 5.6)**

Run from stibnite, which routes the build to magnetite, the only builder advertising `uid-range` (`modules/README.md:56-62`):

```bash
change=$(cat logs/s2-evidence/5.7-change-id.txt)
rev=$(jj log --no-graph -r "$change" -T commit_id)
nix eval --raw "git+file://$PWD?rev=$rev#vmTests.x86_64-linux.devloop-ingest.drvPath" | tee logs/s2-evidence/5.6-drv-$(date -u +%Y%m%dT%H%M%SZ).log
nix build --no-link -L "git+file://$PWD?rev=$rev#vmTests.x86_64-linux.devloop-ingest" 2>&1 | tee logs/s2-evidence/5.6-devloop-ingest-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(=== case|ok: |mutant .* rejected|load [123]:|Traceback|Error)'
```

Expected: `=== case` and `ok:` lines for `firstStart`, `noAutoCreate`, `overlap`, `tableShape`, `switch`, `documentedQueries` and `reconcile`, each with its mutant lines as Tasks 3 and 4 list them; then `=== case burnRule`, `load 1: 10 builds, 2 waited over an hour: [[0.2]]`, `load 2: 9 builds, 2 waited over an hour: []`, the three lines `mutant noPullRequestFilter rejected: load 2 gave [[0.3]]`, `mutant noStartedFilter rejected: load 2 gave [[0.2]]`, `mutant minimumNine rejected: load 2 gave [[0.2222222222222222]]`, `load 3: 10 builds, 1 waited over an hour, 1 restarted: []`, the four lines `mutant noWindow rejected: load 3 gave [[0.18181818181818182]]`, `mutant shareAtLeastATenth rejected: load 3 gave [[0.1]]`, `mutant everyAttempt rejected: load 3 gave [[0.18181818181818182]]`, `mutant thresholdHalfHour rejected: load 3 gave [[0.9]]`, `ok: burnRule`; no `Traceback`; the build succeeds.
`[INFERENCE]` the trailing digits of the quotients are as Python prints the IEEE doubles; GreptimeDB's JSON may print them differently, which changes no assertion, since the case compares load 1 within `1e-9` and the mutants only by row count.
`[INFERENCE]` the colocated repository exports the jj commit to git, so `git+file://…?rev=` resolves it; if it does not, run `jj git export` first, which writes only git refs.
A failure in `burnRule` with a parse error on `value`, `HAVING`, `INTERVAL` or the first-attempt `JOIN` refutes design D1's assumption: stop and report, since the rule, the leg's expectation and the spec scenario `The rule's expression is rendered` change together.

- [ ] **Step 28: Tick 5.6 into the same change**

In `openspec/changes/stand-up-devloop-collection/tasks.md`, with the edit tool, change only the leading `- [ ]` of line 65 (item 5.6) to `- [x]`.
Run:

```bash
change=$(cat logs/s2-evidence/5.7-change-id.txt)
jj squash --from @ --into "$change" -- openspec/changes/stand-up-devloop-collection/tasks.md
nix eval --raw "git+file://$PWD?rev=$(jj log --no-graph -r "$change" -T commit_id)#vmTests.x86_64-linux.devloop-ingest.drvPath"
rg -n '^- \[x\] 5\.[1-6] ' openspec/changes/stand-up-devloop-collection/tasks.md
```

Expected: the `drvPath` equals the one in `logs/s2-evidence/5.6-drv-*.log`, so the tested derivation is the pull request's; `rg` prints six lines, 60 to 65.
The orchestrator rebases the development join, pushes, opens the pull request with `logs/s2-evidence/5.6-devloop-ingest-<ts>.log` named in its description, and enqueues it.

- [ ] **Step 29: Pull request merged (tasks.md 5.7)**

The orchestrator's pull request shows nixbot green, including `checks.x86_64-linux.fleet-alert` and `nixos-magnetite`, and merges through the queue; the orchestrator ticks 5.7.
Verify: `jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(fleet-alert): per-rule database and language")' -T 'commit_id.shortest(12)'` prints one commit.
If the merge queue rebased the change onto a `main` that changed any path `devloop-ingest` reads, rerun Step 27 against the merged commit before deploy D5 and record it beside the first log.

- [ ] **Step 30: Gate before deploy D5**

Task 7's 7.5 has passed after D4: a hand start of `devloop-reconcile.service` passed, the forced failure posted one `FAILED` and its `RESOLVED`, and the timer's first scheduled run passed, so `devloop` holds the reconciled `ci_build` the burn rule reads.
Run: `ls logs/s2-evidence/7.5-*.log && rg -n '7\.5' openspec/changes/stand-up-devloop-collection/verify.md`
Expected: the 7.5 evidence files exist and `verify.md`'s 7.5 entry records the pass; if not, stop, because a missing or empty `ci_build` either makes every run a `devloop` store error (`StoreQueryFailing` for `devloop`, freezing the burn rule) or silences the rule.

- [ ] **Step 31: Deploy D5 (tasks.md 5.8)**

Run: `logs/s2-evidence/s2-deploy.sh magnetite D5 2>&1 | tee logs/s2-evidence/5.8-deploy-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: the script prints nixbot's `Queue is empty`, deploys magnetite from a fresh worktree of `origin/main` at Step 29's merge, and appends `D5_START` and `D5_END` to `logs/s2-evidence/window.env`; no other machine is deployed.
Verify: Task 7's 7.6 passes: the evaluator's first runs succeed having queried `fleet` and `devloop` as `regulator`, the duration of one run's 16 queries (15 PromQL on `fleet`, one SQL on `devloop`, the count computed from the rendered rule JSON as the unique presence selectors plus the expressions of rules not gated by a window) is recorded, and the burn rule's hand run over the seven days before D5 is recorded against design D1's expectation; the orchestrator then ticks 5.8.
If the evaluator fails on its first runs, `sudo journalctl -u fleet-alert` names the failed query and its database; roll back by deploying magnetite from the previous `main@origin` commit through the same script, after which a `PullRequestQueueWaitBurn` instance or a per-database `StoreQueryFailing` instance left in `/var/lib/fleet-alert/state.json` resolves 5 min later as an absent instance would, since the earlier `transition.jq` reads no `storeErrors` and raises `StoreQueryFailing` with no label.
At the first run after D5, a `StoreQueryFailing` instance the earlier evaluator left with no label is likewise absent and resolves 5 min later, posting `[RESOLVED] StoreQueryFailing` with no database, since its labels hold none, if its FIRING had been posted.

#### Notes for Task 5

1. `system_memory_usage_bytes`, the selector `reporting` reads, belongs to no rule's presence list alone, so the evaluator queries it in `RuleSignalMissing`'s `database`, a rule field like every other, and fails the run if the rules do not list `RuleSignalMissing` exactly once; the check's `queryDatabases` reads the same declaration.
2. The evaluator accepts an SQL answer only with a `value` column, a condition the spec's "exactly one `records` result" implies but does not state; label values from other columns are rendered with `tostring`, so a NULL label is `"null"`.
3. The fixture server now records `REQUEST` before judging a request, so a refused request is visible in the log, and the two-database leg's mutant is rejected on the recorded database before the posts are compared.
4. Review F7 changes `transition.jq`, `model.py` and `test_transition.py`, which design D17 did not expect; the regulator is written first (Steps 6 and 7) and shown failing against `transition.jq` adapted only to the field name (Steps 8 and 9) before the per-database change (Step 10), as S3-R6 asks.
5. `tasks.md` carries review F7 as S2Plan mapped it: 5.1 holds the two-database property of `model.py` and `test_transition.py` with its RED (Steps 6 to 9), 5.4 the per-database evaluator and `transition.jq` (Steps 10, 12 and 19), and 5.5 `devloopFailureLeg` and `allDatabasesFreeze` (Steps 11, 15 and 21); Step 26 ticks them on that mapping.
6. `StoreQueryFailing` carries no `database` or `language`, so "every rule carries `database` and `language`" holds for every rule but it; the contract row `Rule fields` says every rule.

---

