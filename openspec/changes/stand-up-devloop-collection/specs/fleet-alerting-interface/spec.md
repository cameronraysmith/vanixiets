## ADDED Requirements

### Requirement: The pull-request queue-wait rule reads devloop through SQL

The rule table SHALL hold `PullRequestQueueWaitBurn`, `database = "devloop"`, `language = "sql"`, `for = "1h"`, severity `warning`, with no presence selector, whose `expr` returns one row with a `value` column, the share of first-attempt pull-request `ci_build` rows that started and finished in the last 24 hours whose `started_at` is over an hour after `created_at`, only when there are at least 10 such rows and that share exceeds one in ten.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s burn-rule timeline leg, taken from the `fleet-alerting` scenario `More than one in ten pull-request builds waited over an hour`; `vmTests.x86_64-linux.devloop-ingest`'s burn-rule case, which runs this query on GreptimeDB 1.2.1; the operator's hand run over the week before deploy.

#### Scenario: The rule's expression is rendered

- **WHEN** the rule table is rendered
- **THEN** `PullRequestQueueWaitBurn`'s `expr` is `SELECT CAST(sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) AS DOUBLE) / count(*) AS value FROM ci_build c JOIN (SELECT build_id, min(finished_at) AS first_finished FROM ci_build GROUP BY build_id) f ON c.build_id = f.build_id AND c.finished_at = f.first_finished WHERE c.pr_number IS NOT NULL AND c.started_at IS NOT NULL AND c.finished_at >= now() - INTERVAL '24 hours' HAVING count(*) >= 10 AND sum(CASE WHEN c.started_at > c.created_at + INTERVAL '1 hour' THEN 1 ELSE 0 END) * 10 > count(*)`

#### Scenario: The timeline is replayed

- **WHEN** the fixture server answers the rule's SQL with one row `value = 0.15` on 65 consecutive runs and then with no row for 5 min
- **THEN** the evaluator posts one `[FIRING] PullRequestQueueWaitBurn` at priority `default` on the 61st run, nothing on runs 62 to 65 while the row persists, and one `[RESOLVED] PullRequestQueueWaitBurn` 5 min after the row disappears

#### Scenario: A build is run again

- **WHEN** `ci_build` holds two rows for one `build_id`, the second a rerun with a later `finished_at`
- **THEN** only the row with the smallest `finished_at` for that `build_id`, its first attempt, counts toward the share

#### Scenario: The query runs on the real store

- **WHEN** `devloop-ingest` loads `ci_build` with 10 pull-request builds of which 2 waited over an hour, then 9 of which 2 did, then 10 of which 1 did with an eleventh row that reruns one of the fast builds after an hour
- **THEN** the query returns one row the first time and none the other two, because the rerun row is not its build's first attempt

## MODIFIED Requirements

### Requirement: The evaluator queries each rule's database as the regulators' store account

The machine SHALL run on magnetite `fleet-alert.service`, a oneshot with `DynamicUser = true` and `StateDirectory = "fleet-alert"` that `fleet-alert.timer` starts every 60 s, issuing each rule's query as `regulator`, whose password it loads through `LoadCredential`, one query at a time with a 10 s timeout per query: a rule whose `language` is `promql` as an instant query to `http://127.0.0.1:4000/v1/prometheus/api/v1/query` with `x-greptime-db-name: <database>`, and a rule whose `language` is `sql` as `POST http://127.0.0.1:4000/v1/sql?db=<database>`, accepting a 200 whose body holds exactly one `records` result, each of whose rows is one result with its `value` column as the value and its other columns as labels.
A failed or timed-out query, SQL or PromQL, SHALL end the querying of its rule's database for that run, and queries on other databases SHALL continue inside the run's query deadline.

**Discharged by**: magnetite's credential-holder assertion (R8.2), which admits `fleet-alert` and `devloop-reconcile` as `regulator-password` holders; `checks.x86_64-linux.fleet-alert`, whose fixture server refuses any other path, any database other than the rule's, or any other credential, records each request's path and database, and fails a leg if two queries are ever open at once, with its two-database leg and its mutant that sends every rule to `fleet`; and the operator's recorded first run on magnetite.

#### Scenario: A second unit loads the regulators' password

- **WHEN** magnetite's configuration loads `regulator-password` into a unit other than `greptimedb-envelope`, `fleet-alert` and `devloop-reconcile`
- **THEN** magnetite's evaluation fails on the credential-holder assertion (R8.2)

#### Scenario: The evaluator's queries are checked at the fixture server

- **WHEN** the evaluator runs against the check's fixture server
- **THEN** the server answers 404 to any path other than `/v1/prometheus/api/v1/query` and `/v1/sql`, 400 to a PromQL query whose `x-greptime-db-name` or a SQL query whose `db` is not the database the leg's rule declares, and 401 to any account but `regulator` with the fixture password, and the leg fails if two queries are ever open at once

#### Scenario: Two databases are queried in one run

- **WHEN** the two-database leg runs a PromQL rule declared on `fleet` and `PullRequestQueueWaitBurn` declared on `devloop`
- **THEN** the server records one PromQL request with `x-greptime-db-name: fleet` and one `/v1/sql` request with `db=devloop`, and the mutant evaluator that sends every rule to `fleet` fails the leg

#### Scenario: The evaluator's queries fit the store's query limit

- **WHEN** the evaluator runs its rule set's queries against magnetite's store, which accepts at most 8 concurrent queries, 16 in a run with no memory rule firing and outside `WeeklyPipelineTest`'s window (one per unique presence selector and one per expression not gated by a window: 15 PromQL on `fleet` and one SQL on `devloop`), plus the attribution queries of a firing memory rule
- **THEN** it holds one of those 8 at a time; the 19 PromQL queries of S3's rule set, run one after another on magnetite on 2026-10-18, took 0.62 to 0.68 s in total, and the operator records the time of a run's queries at the deploy that adds the SQL rule

#### Scenario: The evaluator first runs on magnetite

- **WHEN** `fleet-alert.service` first runs on magnetite
- **THEN** it exits successfully having queried `fleet` and `devloop` as `regulator`, and the operator records the run

### Requirement: Alert rules are rendered from one Nix source to the evaluator and to promtool

The machine SHALL declare the alert rules once in `modules/nixos/fleet-alert/rules.nix`, each with `alert`, a `database` defaulting to `fleet`, a `language` of `promql` or `sql` defaulting to `promql`, an `expr` that carries its threshold, `for`, `labels.severity`, any presence selector with its expected hosts, and any annotation query, and SHALL render all of them to the evaluator's JSON and only the `promql` rules to a YAML rules file that only `promtool` reads.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s `promtool check rules` pass over the PromQL rules with its malformed-expression mutant, `vmTests.x86_64-linux.devloop-ingest`'s burn-rule case for the SQL rule, its fixture legs, which run the evaluator on the rendered rules, its notified-unit exclusion leg and its attribution legs; and task 7.6's forced condition for each shipped rule on magnetite's store.

#### Scenario: The rule set is rendered

- **WHEN** the rule table is rendered
- **THEN** it holds `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest` on `fleet` in PromQL and `PullRequestQueueWaitBurn` on `devloop` in SQL, the YAML for `promtool` holds every rule but `PullRequestQueueWaitBurn`, and the evaluator adds `StoreQueryFailing` and `RuleSignalMissing` of its own

#### Scenario: An expression does not parse

- **WHEN** the check's mutant gives one rule a malformed expression
- **THEN** `promtool check rules` rejects the rendered YAML and the check fails

#### Scenario: A unit the notifier reports fails

- **WHEN** the fixture server replays `systemd_unit_state{systemd_unit_active_state="failed"} == 1` for each unit in `services.observability-notify.units`
- **THEN** the evaluator posts no `SystemdUnitFailed`, because that rule's exclusion is rendered from that option, with its literal dot written `[.]`, as GreptimeDB 1.2.1 rejects `\.` in both double-quoted and backtick strings

#### Scenario: A memory alert carries its attribution

- **WHEN** the fixture server replays a firing `HostMemoryPressure` or `HostOOMKill` instance on a host
- **THEN** the posted body carries that host's `topk(3, process_memory_usage_bytes)`, `node_zfs_arc_size` and summed `system_paging_usage_bytes{state="used"}`, and states that resident memory omits swapped-out pages

### Requirement: Store errors and silent hosts freeze instance state

When a query fails or times out, the evaluator SHALL stop querying that query's database for that run, leave the state of every instance whose rule reads that database unchanged, keep evaluating the rules on databases that answered, and raise `StoreQueryFailing`, `critical`, with a `for` of 3 min, one instance per failing database, labelled with that `database` and naming it in its message.
A database whose queries the run's query deadline did not reach SHALL count as failed for that run.
While a host returns no `system_memory_usage_bytes`, the evaluator SHALL leave every instance labelled with that host unchanged, posting neither a `RESOLVED` nor a re-post, until the host reports again, except the `RuleSignalMissing` instance that reports that host's own absence.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s store-error, `devloop`-failure and silent-host fixture legs, its store-freeze, host-freeze and `allDatabasesFreeze` mutants, and its property test against the reference model's per-database store freeze and host freeze, whose two-database property was shown failing against the all-freeze transition before the change.

#### Scenario: The store freeze is dropped

- **WHEN** the check's mutant drops the store freeze and the fixture server answers a run with an error while an instance is firing
- **THEN** the mutant posts a `RESOLVED`, and the check fails

#### Scenario: The host freeze is dropped

- **WHEN** the check's mutant drops the host freeze and the fixture server stops returning `system_memory_usage_bytes` for a host with a firing instance
- **THEN** the mutant posts a `RESOLVED`, and the check fails

#### Scenario: One failed query bounds the run

- **WHEN** a query on one database times out after 10 s
- **THEN** the run issues no further query on that database, queries the other databases within its 30 s query deadline, and so ends well inside `TimeoutStartSec = 50s`

#### Scenario: Only the failing database is frozen

- **WHEN** the burn rule's SQL on `devloop` fails on every run for 4 min while `HostOOMKill` on `fleet` fires and its condition then goes
- **THEN** one `[FIRING] StoreQueryFailing devloop` is posted after 3 min, and `HostOOMKill` resolves 5 min after its condition goes, while `devloop` is still failing

#### Scenario: Every database is frozen by one failure

- **WHEN** the check's mutant `allDatabasesFreeze` freezes every instance whenever any database fails
- **THEN** the `devloop`-failure leg and the two-database property both fail, and the check fails

### Requirement: Alerts are posted to fleet-alerts with a title and a severity priority

The evaluator SHALL post each alert through `ntfy-send` to `fleet-alerts` at `https://ntfy.zt`, with `NTFY_TOKEN_FILE` naming its `alerter` credential, titled `[FIRING] <alert> <host>` or `[RESOLVED] <alert> <host>`, at priority `high` for `critical`, `default` for `warning` and `low` for `info`.
A host-less instance SHALL be titled without a host: `RuleSignalMissing` for a whole selector, `AlertBudgetExceeded`, `WeeklyPipelineTest`, `PullRequestQueueWaitBurn`, and `StoreQueryFailing`, which instead names its failing database, `[FIRING] StoreQueryFailing <database>` or `[RESOLVED] StoreQueryFailing <database>`, so the instances of two databases are told apart.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s fixture server, which records every post; the `alerter`-authenticated heartbeat requests recorded during the cutover; and regulator R9.3 at runtime, since once `*:fleet-*:ro` is in force a run posting without the `alerter` token has its heartbeat refused.

#### Scenario: A post is recorded

- **WHEN** the fixture server replays a firing `critical` instance on magnetite
- **THEN** it records one post to `fleet-alerts` titled `[FIRING] <alert> magnetite` with priority `high`

#### Scenario: A host-less post is recorded

- **WHEN** the fixture server answers a run with an error for 3 min
- **THEN** it records one post to `fleet-alerts` per database whose queries failed, titled `[FIRING] StoreQueryFailing <database>`, such as `[FIRING] StoreQueryFailing fleet`, with no host, at priority `high`

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the evaluator queries each rule's database as `regulator` on the path its language names, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats and the dead-man behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured with the stated access entries, provisioning and proxy settings

#### Scenario: A guarantee about ntfy's enforcement is sought

- **WHEN** someone asks whether these properties guarantee that ntfy refuses an anonymous `fleet-*` publish, rate-limits each client separately, or delivers a message to a subscribed device
- **THEN** the answer is no: ntfy enforces the access entries and rate limits and delivers to subscribed devices, and this machine only configures it, which R9.4's probe and the acceptance observations monitor

#### Scenario: A guarantee about the token's secrecy is sought

- **WHEN** someone asks whether only the evaluator, the dead-man and the notifier can read the `alerter` token
- **THEN** the answer is no: any root process on magnetite or cinnabar can read it

#### Scenario: A guarantee about an ntfy outage is sought

- **WHEN** someone asks whether an outage of cinnabar or its ntfy is reported
- **THEN** the answer is no: cinnabar is the single delivery path, and nothing here reports its outage, which ADR-009 Q5 defers

#### Scenario: An end-to-end guarantee is sought

- **WHEN** someone asks whether these properties guarantee that an alert reaches a person
- **THEN** the answer is no: each stage's configuration, the fixture check and the recorded acceptance observations behave as stated, and nothing here observes an alert reaching a person's device

## RENAMED Requirements

- FROM: `### Requirement: The evaluator queries the fleet database as the regulators' store account`
- TO: `### Requirement: The evaluator queries each rule's database as the regulators' store account`
