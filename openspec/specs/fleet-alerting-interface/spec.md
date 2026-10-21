# fleet-alerting-interface Specification

## Purpose

This capability (stratum: `interface`) states the properties at the machine's interface that discharge the `fleet-alerting` requirements: the query path, account and timeouts; the rule table rendered from one Nix source to the evaluator and to `promtool`; the state files; topic names, titles and priorities; the heartbeat and the dead-man's poll; the ntfy access entries, provisioning variables and proxy settings; token transport by file and `LoadCredential`; the notifier's FAILED log; and the R9.1 to R9.5 checks with their mutants.
Trust boundary: ntfy enforces the access entries and rate limits, and delivers to subscribed devices, and this machine only configures it; any root process on magnetite or cinnabar can read the `alerter` token; cinnabar is the single delivery path, and nothing reports an ntfy outage until CAM-76; nothing here guarantees that an alert reaches a person, only that each stage's configuration, the fixture check and the recorded acceptance observations behave as stated.

## Requirements

### Requirement: The evaluator queries the fleet database as the regulators' store account

The machine SHALL run on magnetite `fleet-alert.service`, a oneshot with `DynamicUser = true` and `StateDirectory = "fleet-alert"` that `fleet-alert.timer` starts every 60 s, issuing each rule's PromQL instant query to `http://127.0.0.1:4000/v1/prometheus/api/v1/query` with `x-greptime-db-name: fleet` as `regulator`, whose password it loads through `LoadCredential`, one query at a time with a 10 s timeout per query.

**Discharged by**: magnetite's credential-holder assertion (R8.2), which admits `fleet-alert` as a `regulator-password` holder; `checks.x86_64-linux.fleet-alert`, whose fixture server refuses any other path, database header or credential and fails a leg if two queries are ever open at once; and the operator's recorded first run on magnetite.

#### Scenario: A second unit loads the regulators' password

- **WHEN** magnetite's configuration loads `regulator-password` into a unit other than `greptimedb-envelope` and `fleet-alert`
- **THEN** magnetite's evaluation fails on the credential-holder assertion (R8.2)

#### Scenario: The evaluator's queries are checked at the fixture server

- **WHEN** the evaluator runs against the check's fixture server
- **THEN** the server answers 404 to any path other than `/v1/prometheus/api/v1/query`, 400 to a query without `x-greptime-db-name: fleet`, and 401 to any account but `regulator` with the fixture password, and the leg fails if two queries are ever open at once

#### Scenario: The evaluator's queries fit the store's query limit

- **WHEN** the evaluator runs its rule set's 19 rule, attribution and presence queries against magnetite's store, which accepts at most 8 concurrent queries
- **THEN** it holds one of those 8 at a time, and the same 19 queries, run one after another on magnetite on 2026-10-18, took 0.62 to 0.68 s in total

#### Scenario: The evaluator first runs on magnetite

- **WHEN** `fleet-alert.service` first runs on magnetite
- **THEN** it exits successfully having queried `fleet` as `regulator`, and the operator records the run

### Requirement: Alert rules are rendered from one Nix source to the evaluator and to promtool

The machine SHALL declare the alert rules once in `modules/nixos/fleet-alert/rules.nix` as Prometheus-format rules, each with `alert`, an `expr` that carries its threshold, `for`, `labels.severity`, a presence selector with its expected hosts, and any annotation query, and SHALL render them to the evaluator's JSON and to a YAML rules file that only `promtool` reads.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s `promtool check rules` pass with its malformed-expression mutant, its fixture legs, which run the evaluator on the rendered rules, its notified-unit exclusion leg and its attribution legs; and task 7.6's forced condition for each shipped rule on magnetite's store.

#### Scenario: The rule set is rendered

- **WHEN** the rule table is rendered
- **THEN** it holds `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest`, and the evaluator adds `StoreQueryFailing` and `RuleSignalMissing` of its own

#### Scenario: An expression does not parse

- **WHEN** the check's mutant gives one rule a malformed expression
- **THEN** `promtool check rules` rejects the rendered YAML and the check fails

#### Scenario: A unit the notifier reports fails

- **WHEN** the fixture server replays `systemd_unit_state{systemd_unit_active_state="failed"} == 1` for each unit in `services.observability-notify.units`
- **THEN** the evaluator posts no `SystemdUnitFailed`, because that rule's exclusion is rendered from that option, with its literal dot written `[.]`, as GreptimeDB 1.2.1 rejects `\.` in both double-quoted and backtick strings

#### Scenario: A memory alert carries its attribution

- **WHEN** the fixture server replays a firing `HostMemoryPressure` or `HostOOMKill` instance on a host
- **THEN** the posted body carries that host's `topk(3, process_memory_usage_bytes)`, `node_zfs_arc_size` and summed `system_paging_usage_bytes{state="used"}`, and states that resident memory omits swapped-out pages

### Requirement: Alert instance state is kept in one state file and posted once per transition

The evaluator SHALL keep each instance, one rule and its result label set, in `/var/lib/fleet-alert/state.json` through a pure jq transition function, SHALL post one `FIRING` once its condition has held on every pass for `for` and one `RESOLVED` once it has been absent 5 min, and SHALL re-post a `critical` instance every 24 h, never re-post a `warning` one, and post no `RESOLVED` for an `info` one.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s fixture sequence, its no-state-write and zero-`for` mutants, and its property test comparing the jq transition function with the Python reference model.

#### Scenario: The evaluator runs twice on a held condition

- **WHEN** the check's mutant removes the state-file write and the fixture server replays a held condition on two runs
- **THEN** the second run re-posts, and the check fails

#### Scenario: A rule's holding time is dropped

- **WHEN** the check's mutant sets a rule's `for` to 0
- **THEN** the instance fires on the first run, and the check fails

#### Scenario: Generated timelines are compared with the reference model

- **WHEN** Hypothesis generates query timelines of held, absent and failing conditions across severities
- **THEN** the jq transition function's posts and state equal the reference model's at every step, including the 24 h re-post of a `critical` instance

### Requirement: Store errors and silent hosts freeze instance state

When a query fails or times out, the evaluator SHALL stop querying for that run, leave every other instance's state unchanged, and raise `StoreQueryFailing`, `critical`, with a `for` of 3 min.
While a host returns no `system_memory_usage_bytes`, the evaluator SHALL leave every instance labelled with that host unchanged, posting neither a `RESOLVED` nor a re-post, until the host reports again, except the `RuleSignalMissing` instance that reports that host's own absence.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s store-error and silent-host fixture legs, its store-freeze and host-freeze mutants, and its property test against the reference model's store and host freezes.

#### Scenario: The store freeze is dropped

- **WHEN** the check's mutant drops the store freeze and the fixture server answers a run with an error while an instance is firing
- **THEN** the mutant posts a `RESOLVED`, and the check fails

#### Scenario: The host freeze is dropped

- **WHEN** the check's mutant drops the host freeze and the fixture server stops returning `system_memory_usage_bytes` for a host with a firing instance
- **THEN** the mutant posts a `RESOLVED`, and the check fails

#### Scenario: One failed query bounds the run

- **WHEN** a query times out after 10 s
- **THEN** the run issues no further rule query, so it ends well inside `TimeoutStartSec = 50s`

### Requirement: Each rule's presence selector is watched

Each rule's presence selector SHALL be the bare metric name of its expression, except `up{job="node"}` for `LocalExporterDown`, its expected hosts SHALL be `magnetite` alone until other hosts store series, and the evaluator SHALL raise `RuleSignalMissing`, `warning`, for a rule whose selector has returned no series for 30 min while an expected host reports `system_memory_usage_bytes`.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s signal-gap fixture legs; the operator's recorded observation that no `RuleSignalMissing` fires within 30 min of the evaluator's first run on magnetite, with its negative control.

#### Scenario: A selector is empty while an expected host reports

- **WHEN** the fixture server returns no series for a rule's selector for 30 min while an expected host returns `system_memory_usage_bytes`
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing` naming that rule

#### Scenario: A selector is empty while every expected host is silent

- **WHEN** the fixture server returns no series for a rule's selector and no `system_memory_usage_bytes` for any of its expected hosts for 30 min
- **THEN** the evaluator posts nothing for that rule

#### Scenario: The deployed selectors are checked at acceptance

- **WHEN** at acceptance the operator runs the deployed evaluator by hand with one presence selector misspelt, its `for` at 0, scratch state and topic `fleet-acceptance`, and then waits 30 min after the evaluator's first scheduled run
- **THEN** the hand run posts `RuleSignalMissing` for the misspelt selector, the scheduled runs post none, and the operator records both

### Requirement: An always-on host's silence is reported

For each host the rule table marks always-on, `magnetite` alone in S3, the evaluator SHALL raise `RuleSignalMissing` with `selector="system_memory_usage_bytes"` and that `host_name` once the store has answered but the host has been absent from `system_memory_usage_bytes` for 10 min since it last reported, or since the evaluator's first run if it never has, and SHALL resolve it once the host reports again.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s always-on-host fixture leg, with the mutant that stops recording when each host last reported.

#### Scenario: An always-on host stops reporting while the store answers

- **WHEN** the fixture server answers every query but returns no series for magnetite for 40 min after it last reported, with `node_vmstat_oom_kill` empty, and then magnetite reports again
- **THEN** the evaluator posts one `[FIRING] RuleSignalMissing magnetite` 10 min after magnetite last reported, none for `node_vmstat_oom_kill`, and one `[RESOLVED] RuleSignalMissing magnetite` once magnetite reports again 5 min after the last run that found it silent

### Requirement: Alerts are posted to fleet-alerts with a title and a severity priority

The evaluator SHALL post each alert through `ntfy-send` to `fleet-alerts` at `https://ntfy.zt`, with `NTFY_TOKEN_FILE` naming its `alerter` credential, titled `[FIRING] <alert> <host>` or `[RESOLVED] <alert> <host>`, at priority `high` for `critical`, `default` for `warning` and `low` for `info`.
A host-less instance SHALL be titled without a host: `StoreQueryFailing`, `RuleSignalMissing` for a whole selector, `AlertBudgetExceeded`, `WeeklyPipelineTest`.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s fixture server, which records every post; the `alerter`-authenticated heartbeat requests recorded during the cutover; and regulator R9.3 at runtime, since once `*:fleet-*:ro` is in force a run posting without the `alerter` token has its heartbeat refused.

#### Scenario: A post is recorded

- **WHEN** the fixture server replays a firing `critical` instance on magnetite
- **THEN** it records one post to `fleet-alerts` titled `[FIRING] <alert> magnetite` with priority `high`

#### Scenario: A host-less post is recorded

- **WHEN** the fixture server answers a run with an error for 3 min
- **THEN** it records one post to `fleet-alerts` titled `[FIRING] StoreQueryFailing`, with no host, at priority `high`

### Requirement: Each completed evaluator run posts a heartbeat

Each completed run of the evaluator, including one that raised `StoreQueryFailing`, SHALL publish one message at priority `min` to `fleet-heartbeat` through `ntfy-send` with the `alerter` token.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s fixture legs, which record the heartbeat on a normal run and on a store-error run; regulator R9.3's dead-man at runtime.

#### Scenario: A run meets a store error

- **WHEN** the fixture server answers every query of a run with an error
- **THEN** the run still records one post to `fleet-heartbeat` with priority `min`

### Requirement: The dead-man on cinnabar polls the heartbeat topic after an anonymous-publish probe

On cinnabar, `fleet-deadman.timer` SHALL start `fleet-deadman.service` every 5 min, with `DynamicUser = true`, `StateDirectory = "fleet-deadman"` and `OnFailure=observability-notify@%n.service`, which SHALL first publish anonymously to `http://[::1]:2586/fleet-heartbeat` and fail if accepted, then poll `/fleet-heartbeat/json?poll=1&since=10m` there and, in its `state.json`, raise `AlertEvaluatorSilent`, `critical`, on an empty result and resolve it when a heartbeat returns.

**Discharged by**: regulator R9.3, shown able to fail at acceptance by stopping `fleet-alert.timer`, resting on world assumption `A42 — ntfy keeps a topic's messages for 12 hours and returns a recent window to a poll`, whose `AlertEvaluatorSilent` reaches `fleet-alerts` only with the `alerter` credential once `*:fleet-*:ro` is in force; regulator R9.4, shown able to fail at acceptance by removing `*:fleet-*:ro`; and the assertions that hold R9.4's premise on cinnabar, `fleet-alert.nix`'s on ntfy's listener and access entries and cinnabar's on the dead-man's ordering, each shown able to fail by an `extendModules` override.

#### Scenario: The evaluator's timer is stopped

- **WHEN** at acceptance the operator stops `fleet-alert.timer` on magnetite, then starts it again
- **THEN** `AlertEvaluatorSilent` is posted to `fleet-alerts` within 15 min of the stop, and its `RESOLVED` after the start, and the operator records both

#### Scenario: The anonymous read-only entry is removed

- **WHEN** at acceptance the operator removes `*:fleet-*:ro` from cinnabar's `auth-access`
- **THEN** the probe's anonymous publish is accepted, `fleet-deadman.service` fails, a `FAILED` naming it and cinnabar appears on `fleet-alerts`, and the operator records both

#### Scenario: The probe is refused

- **WHEN** the access entries are in force and the dead-man runs
- **THEN** the probe's anonymous publish is refused with 403 and the unit goes on to poll

### Requirement: ntfy grants the fleet topics to alerter through declarative provisioning

cinnabar's ntfy SHALL set `auth-access` to `alerter:fleet-*:rw` and `*:fleet-*:ro`, SHALL leave `auth-default-access` at `read-write`, and SHALL read `NTFY_AUTH_USERS=alerter:<bcrypt hash>:user` and `NTFY_AUTH_TOKENS=alerter:<token>` from `services.ntfy-sh.environmentFile`, the `ntfy-env` file of the per-machine `ntfy-alerter-env` generator, whose replacement restarts `ntfy-sh.service`.

**Discharged by**: `checks.x86_64-linux.ntfy-provisioning` with its mutants; regulator R9.4; the operator's recorded anonymous publish to a host-named topic at acceptance.

#### Scenario: The rendered provisioning strings are checked

- **WHEN** `checks.x86_64-linux.ntfy-provisioning` reads the rendered `NTFY_AUTH_*` strings and `auth-access`, within its evaluation budget of 0.5 GiB
- **THEN** it passes only if the token matches `^tk_[-_A-Za-z0-9]{29}$`, the hash has bcrypt's shape, and every access entry names a provisioned user, and it fails on a mutant for each of the three

#### Scenario: The access entries arrive last

- **WHEN** the cutover is deployed
- **THEN** cinnabar first provisions `alerter` and its token with no access entries, magnetite then deploys the token-bearing notifier and evaluator, and cinnabar last adds `auth-access`, after which R9.4's probe confirms the refusal, so no publish is refused at any step

#### Scenario: A host-named topic stays anonymous

- **WHEN** after the access entries are in force a client without a token publishes to a topic named after a host
- **THEN** ntfy accepts it, and the operator records the accepted publish

### Requirement: ntfy counts each mesh client as its own visitor

cinnabar's ntfy SHALL set `behind-proxy: true`, `proxy-trusted-hosts` to `::1` and `visitor-prefix-bits-ipv6: 128`, and SHALL exempt no host through `visitor-request-limit-exempt-hosts`.

**Discharged by**: the operator's recorded observation, at the cutover's first cinnabar deploy, that ntfy counts requests from two mesh clients as two visitors; no evaluation-time check applies, because one would only restate cinnabar's own settings.

#### Scenario: Two mesh clients publish

- **WHEN** at the cutover's first cinnabar deploy each of two mesh hosts reads its anonymous `/v1/account` from `https://ntfy.zt` after publishing to its own host-named topic
- **THEN** each sees only its own requests counted, rather than one budget shared through `::1` or one `/64`, and the operator records both answers

### Requirement: The alerter token travels only as a file

The `ntfy-alerter` generator, shared by magnetite and cinnabar, SHALL hold only the `alerter` token, as `token` with mode `0400`; the per-machine `ntfy-alerter-env` generator, declared on cinnabar only, SHALL derive `ntfy-env` from that token.
`ntfy-send` SHALL, when `NTFY_TOKEN_FILE` is set, send `Authorization: Bearer` with that file's token without placing it on curl's argument list, and every `fleet-*` publisher SHALL pass the token to it through `NTFY_TOKEN_FILE`.

**Discharged by**: `checks.<system>.package-ntfy-send-test-token-transport` with its argv mutant; the resolve-hook assertion in `observability-notify.nix`, shown able to fail by an `extendModules` override; the cutover order, resting on world assumption `A39 — ntfy refuses a request whose token it does not know, even where anonymous access is allowed`; the `alerter`-authenticated heartbeat requests recorded during the cutover; and, once `*:fleet-*:ro` is in force, the forced failure notice delivered with `alerter` and regulator R9.3's `AlertEvaluatorSilent`, both of which ntfy refuses without the token.

#### Scenario: The sender is run with a recording curl

- **WHEN** `checks.<system>.package-ntfy-send-test-token-transport` runs `ntfy-send` with `NTFY_TOKEN_FILE` set and a recording curl stub
- **THEN** the token never appears in the stub's argument list and arrives as an `Authorization: Bearer` header read from stdin, and a mutant script passing the header on the argument list fails the test

#### Scenario: Each notified unit's resolve hooks carry the token

- **WHEN** magnetite's and cinnabar's configurations are evaluated
- **THEN** `observability-notify.nix`'s assertion holds that every notified unit's resolve hooks run under `env NTFY_TOKEN_FILE=<tokenFile>`, and an `extendModules` override replacing one unit's hooks makes evaluation fail

### Requirement: The alert budget is counted over the evaluator's state and the notifier's FAILED log

The evaluator SHALL count the non-`info` `FIRING` posts of the last 24 h in its state file together with the lines of `/var/lib/observability-notify/failed.log`, and when they exceed 10 across the fleet or 3 for `stibnite` or for `pyrite`, SHALL post one `AlertBudgetExceeded` per 24 h naming the rule and host with the most firings, suppressing no alert.
A missing `failed.log` SHALL count as empty, and a `failed.log` that exists but cannot be read SHALL fail the run before any post.

**Discharged by**: regulator R9.1, shown able to fail by `checks.x86_64-linux.fleet-alert`'s two budget legs, and its unreadable-log leg.

#### Scenario: The fleet budget is exceeded

- **WHEN** the check fires 11 synthetic instances within 24 h
- **THEN** exactly one `AlertBudgetExceeded` is posted and all 11 `FIRING` posts are recorded

#### Scenario: A laptop's budget is exceeded

- **WHEN** the check fires 4 synthetic instances on `stibnite` within 24 h
- **THEN** exactly one `AlertBudgetExceeded` is posted

#### Scenario: The FAILED log cannot be read

- **WHEN** the check makes an existing `failed.log` unreadable
- **THEN** the run exits non-zero and posts nothing

### Requirement: The rule check runs promtool, fixture mutants and a property test

`checks.x86_64-linux.fleet-alert` SHALL run `promtool check rules` over the rendered YAML, run the evaluator in the build sandbox against a loopback fixture server that replays canned query responses and records every ntfy post, compare the jq transition function with a Python reference model over Hypothesis-generated timelines, and fail on each of its mutants, within an evaluation budget of 0.5 GiB.

**Discharged by**: the check's own mutants, each of which must produce a non-empty failure list, and the plan-time measurement of its evaluation cost with `NIX_SHOW_STATS`.

#### Scenario: The mutants are run

- **WHEN** the check runs its mutants: no state write, a `for` of 0, no store freeze, no absence freeze, a malformed expression, and a notifier template without `NTFY_TOKEN_FILE`
- **THEN** each produces a non-empty failure list, and the unmutated evaluator produces none

#### Scenario: The check's evaluation cost is measured

- **WHEN** the check's derivation is evaluated with `NIX_SHOW_STATS`
- **THEN** its evaluation stays within the 0.5 GiB budget

### Requirement: The evaluator's memory ceiling and start timeout are asserted

`fleet-alert.service` SHALL run with `MemoryMax = 64M`, and the `fleet-alert` module SHALL assert it and that a run's worst case, the later of the query deadline plus the heartbeat's post timeout and the post deadline, plus one post timeout and the notifier hook's post timeout, is below `TimeoutStartSec`, which is below the timer period, when magnetite's configuration is evaluated.

**Discharged by**: regulator R9.5, the module's assertions, with its mutant that drops `MemoryMax`, and the timing relation's failure at the earlier `postDeadlineSec = 40`.

#### Scenario: The memory ceiling is dropped

- **WHEN** a mutant of magnetite's configuration drops `MemoryMax` from `fleet-alert.service`
- **THEN** magnetite's evaluation fails on the `fleet-alert` module's assertion

### Requirement: The weekly test rule is evaluated in one window each Monday

`WeeklyPipelineTest` SHALL query `count(count by (host_name) (system_memory_usage_bytes))` at severity `info` with a `for` of 0, and the evaluator SHALL evaluate it only on Mondays from 09:00 to 09:05 in the `America/New_York` time zone that the rule table names, converting that zone for this rule alone while magnetite's `time.timeZone` stays unset.

**Discharged by**: `checks.x86_64-linux.fleet-alert`'s window legs inside and on either side of the window; regulator R9.3's weekly observation by the operator.

#### Scenario: Runs inside and outside the window

- **WHEN** the fixture legs run the evaluator at a Monday 09:02 and at a Monday 08:59 and 09:06 in `America/New_York`
- **THEN** only the 09:02 run posts `[FIRING] WeeklyPipelineTest` at priority `low`, and no `RESOLVED` follows it

### Requirement: This capability states its own trust boundary

This capability SHALL state what its properties guarantee and what they do not, and SHALL NOT be described, by itself or in any downstream report, as an end-to-end guarantee that an alert reaches a person.

**Discharged by**: the requirement's own statement in the scenarios below; no regulator applies.

#### Scenario: The properties above are read as a set

- **WHEN** the properties of this capability are read as a set
- **THEN** what they establish is that the evaluator queries `fleet` as `regulator` on the stated path, that the rules render from one source to the evaluator and to `promtool`, that instance state, freezes, presence watching, titles, priorities, heartbeats and the dead-man behave as the fixture check, its mutants, its property test and the recorded acceptance observations show, and that ntfy is configured with the stated access entries, provisioning and proxy settings

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
