---
title: Fleet observability
description: "Operating the fleet's telemetry store, metrics collector, dev-loop record and alerting: dashboard access, querying devloop, alerts and failure notices on fleet-alerts, the dead-man on cinnabar, the hourly envelope, the daily reconcile, credential rotation and retention."
---

This runbook is for the operator of the fleet's telemetry store, its dev-loop record and alerting, as deployed by slices S1, S2 and S3.
It assumes SSH access to `magnetite.zt` and `cinnabar.zt` over ZeroTier, `sudo` on both, and a vanixiets checkout with the `clan` CLI on the workstation.
The maintainer contract for the collector lives in `modules/clan/services/otel-collector/README.md`; the failure notifier lives in `modules/nixos/observability-notify.nix`, the alert evaluator and the dead-man in `modules/nixos/fleet-alert.nix`, and the rules in `modules/nixos/fleet-alert/rules.nix`.

## What runs where

S1's store and collector, S2's dev-loop collection and S3's alert evaluator run on magnetite; ntfy and S3's dead-man run on cinnabar.

- `greptimedb.service` runs GreptimeDB standalone, listening only on loopback: HTTP on `127.0.0.1:4000` and gRPC on `127.0.0.1:4001`.
- Its WAL and caches live on the ZFS dataset `zroot/root/greptimedb` at `/var/lib/greptimedb`, with a 16G quota and a 12G reservation.
- Its table data goes to Cloudflare R2, bucket `sciexp`, under the prefix `projects/vanixiets/observability/store/`.
- `greptimedb-schema.service` creates the databases and sets their retention each time the store starts.
- `opentelemetry-collector.service` collects magnetite's host, unit, process-memory, ZFS, OOM-kill and service metrics and writes them to the store; it also copies nixbot's builds and attributes, gitea-mq's batch transitions and magnetite's deploy records into `devloop`.
- `devloop-pg-grants.service` grants the collector's and the reconcile's PostgreSQL roles their columns of nixbot's database once per boot, and at an activation only when the unit changes, after waiting up to 300 s for the columns to exist.
- `devloop-reconcile.timer` runs `devloop-reconcile.service` at 02:15 UTC to compare the previous UTC day of `devloop` with its sources.
- `greptimedb-envelope.timer` runs `greptimedb-envelope.service` hourly to check the store's runtime envelope.
- `observability-notify@.service` posts unit failures to ntfy with the `alerter` token, on magnetite and on cinnabar.
- `fleet-alert.timer` runs `fleet-alert.service` on magnetite every 60 s: it evaluates each alert rule against its own database, `fleet` or, for `PullRequestQueueWaitBurn`, `devloop`, posts a heartbeat to `fleet-heartbeat`, and posts alerts to `fleet-alerts`.
- `fleet-deadman.timer` runs `fleet-deadman.service` on cinnabar every 5 min: it checks that anonymous publishing to `fleet-heartbeat` is refused, then raises `AlertEvaluatorSilent` when no heartbeat arrived in the last 10 min.
- `ntfy-sh.service` on cinnabar serves `https://ntfy.zt` through caddy; only the `alerter` user may publish to `fleet-*` topics, every other topic stays open to anonymous publishing, and anyone on the mesh may subscribe.
- Every NixOS and darwin machine activated since S2 appends one line to `/var/log/deploy-record.jsonl` at each activation, which on NixOS includes the activation at boot; S2 collects magnetite's file only.

The store holds three databases.

| Database | Retention | Written by |
|---|---|---|
| `fleet` | 30 days | the collector, from S1 |
| `devloop` | 365 days | the collector, from S2: nixbot's builds and attributes, gitea-mq's batch transitions and magnetite's deploy records |
| `agent` | 90 days | nothing until S7 |

The store has four users: `admin` (read and write), `collector` (write only), `perses` (read only) and `regulator` (read only).

## Reaching the dashboard

The store serves its embedded dashboard on the loopback listener, so reach it through an SSH tunnel from the workstation:

```sh
ssh -L 4000:127.0.0.1:4000 magnetite.zt
```

Open `http://127.0.0.1:4000/dashboard/` in a browser.
Sign in as `perses`, the read-only user, with the password from:

```sh
clan vars get magnetite greptimedb-users/perses-password
```

Open the connection settings from the gear and set the connection database to `fleet`; the status bar then shows `fleet`.
The database selector in the Tables panel does not change where queries run.
A query run while the connection database is `public` returns no rows.

Two queries confirm data is arriving:

- PromQL, in Metrics Query: `up`
- SQL, in Table Query: `SELECT count(*) FROM fleet.up`

## Subscribing to fleet-alerts

Alerts and failure notices go to the ntfy topic `fleet-alerts` at `https://ntfy.zt/fleet-alerts`.
`ntfy.zt` resolves only through cinnabar's dnsmasq and listens only on cinnabar's ZeroTier addresses, so a subscriber must be a ZeroTier member of the fleet network.
caddy serves it with a certificate from its internal CA, so a subscriber must also trust caddy's root certificate.
The root certificate is committed at `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt` (`CN=Caddy Local Authority - 2026 ECC Root`, SHA-256 fingerprint `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82`); caddy's live copy on cinnabar is `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`.
Before installing it anywhere, check that the committed file is still the live one:

```sh
openssl x509 -in modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt -noout -fingerprint -sha256
ssh cinnabar.zt 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' | openssl x509 -noout -fingerprint -sha256
```

The two fingerprints must match.

On macOS, a darwin host that enables `services.zt-services-trust` installs the certificate into the System keychain at activation.
On a Mac without it, install it by hand:

```sh
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt
```

Then open `https://ntfy.zt/fleet-alerts` in a browser, allow notifications, and keep the tab open.
The server configures no web push, so a browser shows notifications only while the page is open.

On Android, join the ZeroTier network in the ZeroTier app, copy `caddy-root-ca.crt` to the phone, and install it as a CA certificate under Settings, in Encryption & credentials → Install a certificate → CA certificate; the menus above that entry differ between Android versions.
Install the ntfy app from F-Droid or Google Play, and in it add a subscription to topic `fleet-alerts` on the server `https://ntfy.zt` (use another server, not `ntfy.sh`).
Nothing reaches the phone until the app holds this subscription.
The server sets no `upstream-base-url`, so iOS clients receive no instant push; this runbook supports Android and browser subscribers.

To check a new subscription, post one test message to `fleet-alerts` as root on magnetite or cinnabar; its `[TEST]` title is not a `FIRING`, and the alert budget counts only the evaluator's state and `failed.log`, so it costs nothing:

```sh
sudo NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token "$(command -v ntfy-send)" "phone delivery check" fleet-alerts -H "Title: [TEST] phone delivery check"
```

The phone should show it within seconds.

From a shell on any mesh host, poll recent messages:

```sh
curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=1h' | jq -c '{time, title, priority, message}'
```

`-k` skips certificate verification; without it, `curl` on a host that does not trust caddy's root certificate fails with `unable to get local issuer certificate`.
Pass `--cacert` with a copy of `caddy-root-ca.crt` to verify instead, or post through `ntfy-send`, which uses `-k` as every fleet sender does.
ntfy keeps each topic's messages for 12 hours, so a poll or a reconnecting phone sees at most the last 12 hours.

## Reading alerts

An alert's title is `[FIRING] <alert> <host>` or `[RESOLVED] <alert> <host>`; an alert that carries no host, such as `RuleSignalMissing` for a whole selector, `AlertBudgetExceeded`, `WeeklyPipelineTest` or `PullRequestQueueWaitBurn`, has no host in its title, and `StoreQueryFailing` names the database that stopped answering in the host's place, as in `[FIRING] StoreQueryFailing devloop`.
Its priority follows the rule's severity: `high` for `critical`, `default` for `warning`, `low` for `info`.
An alert fires after its condition has held on every evaluation for the rule's `for`, and resolves after the condition has been absent for 5 minutes of unfrozen evaluations.
Time spent frozen does not count as absence: after the store stopped answering on an alert's database, or after a host's silence, an alert resolves only 5 minutes after the first unfrozen evaluation that no longer sees its condition.
A `critical` alert that stays firing is posted again once every 24 hours; a `warning` alert is never posted again while it fires; an `info` alert posts no `RESOLVED`.
`HostMemoryPressure` and `HostOOMKill` messages end with the host's three largest executables by resident memory, its ZFS ARC size and its swap used; resident memory omits swapped-out pages, so the ranking cannot see what sits in swap.

| Alert | Severity | What it means | What to do |
|---|---|---|---|
| `HostMemoryPressure` | warning | for 5 min, available memory plus reclaimable ARC was below 10% of memory, or swap was over 85% used | read the attribution in the message, then `systemctl status` the top executable's unit; on magnetite the nixbot evaluator is usually the cause |
| `HostOOMKill` | critical | the kernel OOM killer killed a process in the last 10 min | `sudo journalctl -k -g 'Killed process' --since -15min` on the host, then the owning unit's status |
| `ZfsPoolUnhealthy` | critical | a ZFS pool has been in a state other than `online` for 1 min | `zpool status -x` on the host; replace or reattach the failed device before anything else |
| `SystemdUnitRestartLoop` | warning | a unit restarted more than 5 times in 15 min | `systemctl status <unit>` and `sudo journalctl -u <unit> -n 100 --no-pager`; the notifier caps its own messages, so this alert is the one that shows the loop |
| `SystemdUnitFailed` | warning | a unit the collector watches (`systemdUnits` in `modules/clan/services/otel-collector/schema.nix`), other than the notifier's units, has been failed for 5 min | `systemctl status <unit>`; the notifier's own units report through `FAILED` notices instead, never through this alert; a failed `observability-notify@<unit>.service.service` means the notice about `<unit>` was never posted, so read that instance's journal, check `<unit>` itself, then `sudo systemctl reset-failed` the instance to resolve the alert |
| `LocalExporterDown` | warning | a loopback exporter the collector scrapes, job `node` or `smartctl`, has been down for 10 min, so the rules that read it are blind; at acceptance it fired about 10 min after the node exporter stopped | the message's `job` label names it; for `node`, `sudo systemctl restart prometheus-node-exporter`, then check `up{job="node"}` in the dashboard |
| `WeeklyPipelineTest` | info | the weekly test: it fires once each Monday between 09:00 and 09:05 New York time | nothing; its absence on a Monday morning means the path from the store to the phone is broken |
| `PullRequestQueueWaitBurn` | warning | for 1 h, at least 10 pull-request builds that started finished their first attempt in the trailing 24 h and more than 10% of those first attempts waited over 1 h from creation to start | list the slow builds and follow "When PullRequestQueueWaitBurn fires" under "Querying devloop" |
| `StoreQueryFailing` | critical | the store has not answered the evaluator's queries on one database for 3 min; the message names the database, there is one instance per failing database, and only that database's alerts are frozen meanwhile, so a `devloop` failure leaves the `fleet` alerts working | `systemctl status greptimedb greptimedb-schema` and `sudo journalctl -u greptimedb -n 100 --no-pager` on magnetite, and `sudo journalctl -u fleet-alert -n 20 --no-pager`, which names the failed database; for `devloop` alone, also `devloop_sql 'SHOW TABLES'` under "Querying devloop"; starting the store also starts `greptimedb-schema` again; that database's alerts resume when the store answers it |
| `RuleSignalMissing` | warning | a rule's input series has been absent for 30 min while its expected host reports memory, so the rule can no longer fire; the message's `rule` and `selector` labels name both | find the metric's producer: the collector config, the node exporter, or a renamed metric in a dependency update |
| `RuleSignalMissing <host>` | warning | an always-on host (magnetite in S3) has been missing from the store for 10 min while the store answers, with selector `system_memory_usage_bytes`; that host's alerts are frozen meanwhile | first that host's collector, `systemctl status opentelemetry-collector` and `sudo journalctl -u opentelemetry-collector -n 100 --no-pager`, then its export path to magnetite's ingress and the store |
| `AlertEvaluatorSilent` | critical | cinnabar's dead-man saw no heartbeat on `fleet-heartbeat` for 10 min; it runs every 5 min, so it fires up to 15 min after the evaluator stops (14 min 28 s at acceptance) and resolves within about 5 min of its return (4 min 12 s) | on magnetite `systemctl status fleet-alert.timer fleet-alert.service` and `sudo journalctl -u fleet-alert -n 50 --no-pager`; also check magnetite is up and on the mesh |
| `AlertBudgetExceeded` | none, posted at `default` | more than 10 `FIRING` messages, or more than 3 for stibnite or for pyrite, were posted in 24 hours | the alerts have become noise; read the 24 hours of `fleet-alerts` and tune the rule that dominates, through a pull request |

While a host reports no `system_memory_usage_bytes`, its alerts are frozen: they neither resolve nor post again, so a sleeping laptop does not churn, and their 5 minutes of absence start only when the host reports again.

Nothing reports an outage of ntfy or cinnabar themselves: every alert, failure notice and dead-man post goes through ntfy on cinnabar, so such an outage shows only as a missing Monday `WeeklyPipelineTest`, up to 7 days after it begins.
Treat a Monday without that message as an outage of the alert path until a test post shows otherwise; CAM-76, scheduled before S5, adds a watch from outside cinnabar.

## Reading failure notices

Unit failures go to the same topic as plain messages without a title.
The notified units on magnetite are `greptimedb`, `greptimedb-schema`, `greptimedb-envelope`, `opentelemetry-collector`, `fleet-alert`, `devloop-pg-grants`, `devloop-reconcile` and magnetite's `zfs-set-*` and `zfs-assert-*` oneshots; on cinnabar it is `fleet-deadman`.
Print the current list for a host:

```sh
nix eval --json .#nixosConfigurations.magnetite.config.services.observability-notify.units
```

- `FAILED <unit> on <host>` means the unit entered the failed state and a new failure episode began.
- `RESOLVED <unit> on <host>` means the same unit has since started again, or exited successfully, and the episode is over.

A `FAILED fleet-alert.service on magnetite` means a run could not post its heartbeat or an alert, or reached its post deadline; `sudo journalctl -u fleet-alert -n 50 --no-pager` on magnetite names the post.
A `FAILED fleet-deadman.service on cinnabar` means ntfy did not refuse the anonymous probe with 403, or the heartbeat poll failed; `sudo journalctl -u fleet-deadman -n 20 --no-pager` on cinnabar shows which.
A `FAILED devloop-reconcile.service on magnetite` means a day of `devloop` differs from its sources, or a source could not be read; "When devloop-reconcile fails" under "Querying devloop" says what each clause means.
A `FAILED devloop-pg-grants.service on magnetite` means a column the dev-loop readers are granted did not appear in nixbot's database within 300 s of the unit's start, which a nixbot migration renaming or dropping it causes; the collector's nixbot queries fail until the grants apply, and `sudo journalctl -u devloop-pg-grants -n 20 --no-pager` names the column.
The grants are not applied again when nixbot restarts, so a grant lost to a later migration posts no `FAILED` of this unit; it shows as the collector's query errors and as a `FAILED devloop-reconcile.service on magnetite` the next morning.

Within one episode the notifier posts once, however many times the unit fails.
It also posts at most one `FAILED` per unit per 15 minutes: a failure within 15 minutes of the last posted `FAILED` opens a suppressed episode that ends without a message.
A unit in a crash loop therefore shows one `FAILED`/`RESOLVED` pair, then at most one new pair every 15 minutes, so the messages understate how often it is failing; `SystemdUnitRestartLoop` reports the loop itself.
Check the real restart count on magnetite:

```sh
systemctl show opentelemetry-collector -p NRestarts
```

Each failure runs one notifier instance, named after the failed unit with a second `.service` suffix:

```sh
sudo journalctl -u 'observability-notify@greptimedb-envelope.service.service' --no-pager
```

The notifier keeps one stamp per open episode in `/var/lib/observability-notify/<unit>`, containing `posted` or `suppressed`.
A stamp left behind by a failed `RESOLVED` post silences that unit until its next start or successful exit.
Each posted `FAILED` also appends one line `<epoch> <unit> <host>` to `/var/lib/observability-notify/failed.log`; a suppressed episode appends nothing.

## The alert budget and the evaluator's state

The evaluator keeps its state in `/var/lib/fleet-alert/state.json`, readable by root.
The alert budget counts `FIRING` messages over 24 hours: every posted `FIRING` and `critical` re-post recorded in `state.json`'s `.firings`, plus every line of `failed.log` from the same 24 hours; `info` alerts and `AlertBudgetExceeded` are not counted, and neither are cinnabar's dead-man and notifier posts.
Count it on magnetite the way the evaluator does:

```sh
now=$(date +%s)
sudo jq --argjson now "$now" '[.firings[] | select(.at > $now - 86400)] | length' /var/lib/fleet-alert/state.json
awk -v now="$now" '$1 > now - 86400' /var/lib/observability-notify/failed.log | wc -l
sudo jq '.budgetPostedAt' /var/lib/fleet-alert/state.json
```

A sum of the first two numbers above 10, or more than 3 of them on stibnite or on pyrite, raises one `AlertBudgetExceeded` per 24 hours; the third prints when it was last posted.
List the instances firing now:

```sh
sudo jq -c '.instances[] | select(.phase == "firing") | {alert, labels, activeSince, firingPostedAt}' /var/lib/fleet-alert/state.json
```

The dead-man keeps its own state in `/var/lib/fleet-deadman/state.json` on cinnabar.
A post that fails leaves its transition recorded as unposted, and the next run posts it, so a short ntfy outage delays alerts rather than losing them.

## Publishing to fleet topics

Only the `alerter` user may publish to topics matching `fleet-*`; an anonymous publish there is answered 403.
Every other topic, including each host's own topic used by agent notifications, still accepts anonymous publishing.
To publish to a `fleet-*` topic by hand as root on magnetite or cinnabar, give `ntfy-send` the token file:

```sh
sudo NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token "$(command -v ntfy-send)" "manual test" fleet-acceptance
```

`ntfy-send` reads the token from that file and passes it to curl on standard input, so it never appears on a command line.
Use `fleet-acceptance` for tests; it is a `fleet-*` topic that nobody subscribes to by default.

## Responding to an envelope failure

A `FAILED greptimedb-envelope.service on magnetite` notice means at least one envelope property failed.
Read the run's output on magnetite; journal reads need `sudo` there:

```sh
sudo journalctl -u greptimedb-envelope -n 50 --no-pager
```

Each failed property is one `FAIL <id>: ...` line.
After fixing the cause, rerun the envelope instead of waiting for the next hour; a passing run posts `RESOLVED`:

```sh
sudo systemctl start greptimedb-envelope
```

| Line | Meaning | Check first |
|---|---|---|
| `FAIL R6.4` | `http://127.0.0.1:4000/ready` did not answer 200 | `systemctl status greptimedb` and `sudo journalctl -u greptimedb -n 100 --no-pager`; the store may be down, restarting, or unable to reach R2 |
| `FAIL R6.2: no region ... reports sst_size` | no region has flushed table data | whether the collector is writing: `systemctl status opentelemetry-collector` |
| `FAIL R6.2: summed sst_size ...` | stored table data reached the 50 GiB bound | which database grew, and whether a retention setting changed |
| `FAIL R6.3: ... legacy sst_format=primary_key` | a table uses the legacy SST format | who created that table, and recreate it without `sst_format = 'primary_key'` |
| `FAIL R6.3: ... gave no base table` | no table exists in the store's databases | `systemctl status greptimedb-schema opentelemetry-collector` |
| `FAIL TTL` | a table's own TTL disagrees with `services.greptimedb.tableTtls` | whether the TTL was set on purpose; if so, declare it (see below), otherwise remove the table's own TTL |
| `FAIL R7.2: memory.stat anon ...` | the store's anonymous memory reached `MemoryHigh` (3 GiB) | `systemctl status greptimedb` for its current memory, and what load rose |
| `FAIL R7.2: memory.events high rose ...` | the kernel throttled the store at `MemoryHigh` since the last run | the same as above; throttling slows writes and queries |
| `FAIL R7.2: memory.events oom_kill` or `max rose ...` | the store hit `MemoryMax` (4 GiB) or lost a process to the OOM killer | `sudo journalctl -u greptimedb -n 100 --no-pager` |
| `FAIL R7.2: the kernel OOM killer killed processes ...` or `restarted automatically` | the store was killed or crashed and restarted since the last run | `systemctl show greptimedb -p NRestarts` and `sudo journalctl -u greptimedb --no-pager` around the restart |
| `FAIL R7.2: greptimedb.service has no current invocation` | the store is not running | `systemctl status greptimedb` |
| `FAIL R7.2: no journal entries ...` | the envelope could not read the journal | `systemctl show greptimedb-envelope -p SupplementaryGroups` lists `systemd-journal` |
| `FAIL R7.3: quota ...` or `reservation ...` | the dataset's quota or reservation differs from 16G or 12G | `systemctl status zfs-set-root-greptimedb-quota zfs-set-root-greptimedb-reservation` |
| `FAIL R7.3: used ... of quota` | the dataset is 80% full | `zfs list -o name,used,quota zroot/root/greptimedb` and the size of the WAL and caches under `/var/lib/greptimedb` |
| `FAIL R7.4` | the running store loaded a different users file from the one deployed | restart the store: `sudo systemctl restart greptimedb` |

The R7.2 lines about `high`, `oom_kill`, `max`, OOM kills and automatic restarts each fail one run only, because every run records a new baseline.
For those lines, a `FAILED` followed by `RESOLVED` an hour later records one past event, not a condition that cleared by itself.
The store's restart also restarts `greptimedb-schema`, which reapplies the databases and their retention.

## Forcing a failure deliberately

To confirm the envelope and the notifier still work end to end, lower the anonymous-memory threshold with a runtime drop-in and run the envelope:

```sh
printf "[Service]\nEnvironment=GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES=1\n" | sudo systemctl edit --runtime --stdin --drop-in=force-fail greptimedb-envelope
sudo systemctl start greptimedb-envelope
```

The start fails with `FAIL R7.2: memory.stat anon ... >= GREPTIMEDB_ENVELOPE_ANON_MAX_BYTES 1`, and `fleet-alerts` receives `FAILED greptimedb-envelope.service on magnetite`.
Remove the drop-in and run the envelope again:

```sh
sudo systemctl revert greptimedb-envelope
sudo systemctl start greptimedb-envelope
```

The run passes and `fleet-alerts` receives `RESOLVED greptimedb-envelope.service on magnetite`.
If a `FAILED` for the envelope was posted in the previous 15 minutes, both messages are suppressed; wait and repeat.
A runtime drop-in disappears at reboot, but revert it explicitly so the next hourly run is not left failing.

## Rotating credentials

The store's accounts come from the `greptimedb-users` generator, which writes all four passwords, the users file and its public sha256 together.
Regenerate them and deploy:

```sh
clan vars generate magnetite --regenerate --generator greptimedb-users
clan machines update magnetite
```

The deployment restarts `greptimedb.service`, which loads the new users file and restarts `greptimedb-schema`, and `opentelemetry-collector.service`, which loads the new `collector-password`.
The envelope reads `regulator-password` afresh on each run.
R7.4 then compares the sha256 the running store recorded for the users file it loaded with the deployed file's sha256, so the next envelope run fails if the store is still running on the old file.
Fetch the new `perses` password with `clan vars get` before signing in to the dashboard again.

The R2 token comes from the `greptimedb-r2` generator, whose two hidden prompts take an Object Read & Write token on bucket `sciexp`, minted in the Cloudflare dashboard:

```sh
clan vars generate magnetite --regenerate --generator greptimedb-r2
clan machines update magnetite
```

The deployment restarts `greptimedb.service` with the new environment file.
R7.4 does not cover this credential; a store that cannot reach R2 shows up in R6.4, so run the envelope after the deployment.

### The alerter token

The `alerter` token comes from the shared generator `ntfy-alerter`, whose `token` file is deployed to magnetite and cinnabar.
cinnabar's per-machine generator `ntfy-alerter-env` derives ntfy's provisioning file `ntfy-env` from that token and a password it hashes and discards.
Regenerating the token also reruns `ntfy-alerter-env`, because it depends on `ntfy-alerter`:

```sh
clan vars generate cinnabar --regenerate --generator ntfy-alerter
clan vars check cinnabar
clan vars check magnetite
```

Land the vars change through a pull request, then deploy from a fresh worktree of `origin/main` as described below.
ntfy accepts only the token in its current `ntfy-env` and answers any other token with 401, so the deployments follow the cutover order, cinnabar then magnetite, back to back:

```sh
clan machines update cinnabar
clan machines update magnetite
```

Between the two deployments magnetite still posts with the old token and every post is refused with 401.
The evaluator records each refused transition as unposted and posts it on its first run after magnetite's deployment, so alerts are delayed, not lost.
A gap over 10 minutes also raises `AlertEvaluatorSilent` from cinnabar, whose dead-man already holds the new token.
A `FAILED` notice refused inside that window fails its notifier instance, which `SystemdUnitFailed` reports once magnetite's token is accepted; a refused `RESOLVED` is lost, so check `fleet-alerts` against `systemctl list-units --failed` on magnetite afterwards.

## Deploying the alerting changes

Alerting spans two hosts, and ntfy refuses a token it does not know even on an open topic, so changes that touch the token or ntfy's access entries deploy in a fixed order.
The S3 cutover took three deployments, each from a fresh worktree of `origin/main` and only when `nixbot-logs queue` prints `Queue is empty`:

1. cinnabar: ntfy provisions `alerter` and its token and separates mesh clients as visitors; there are no access entries yet, so every publisher still works.
2. magnetite: the evaluator and the notifier start posting with the token.
3. cinnabar: ntfy gains `auth-access` (`alerter:fleet-*:rw`, `*:fleet-*:ro`) and the dead-man starts.

Roll back in the reverse order: redeploy cinnabar without the access entries first, then revert magnetite to anonymous posting, and only then remove the provisioning.
Removing `alerter` from `ntfy-env` deletes the user and its token at ntfy's next start, and every token-bearing post is then refused with 401.

## Querying devloop

S2 copies the dev loop into the `devloop` database on magnetite: every finished nixbot attribute and build, every gitea-mq batch transition and every activation of magnetite.
The store keeps one row per key and time for 365 days, and no error text, log line or message body is stored.
Every night `devloop-reconcile` compares the previous UTC day with the sources, so a gap reaches `fleet-alerts` within a day.

### Reaching the SQL API

Both read-only accounts can read `devloop`: `perses` from the workstation through the SSH tunnel of "Reaching the dashboard", and `regulator` on magnetite.
In the dashboard, set the connection database to `devloop` and use Table Query.
In a shell, define a helper that gives curl the password on standard input, so it never appears on a command line.
On the workstation, with the tunnel open:

```sh
devloop_sql() {
  printf 'user = "perses:%s"\n' "$(clan vars get magnetite greptimedb-users/perses-password)" |
    curl --config - --silent --show-error --fail-with-body \
      'http://127.0.0.1:4000/v1/sql?db=devloop' --data-urlencode "sql=$1" |
    jq -r '.output[0].records | (.schema.column_schemas | map(.name)), (.rows[] | map(if . == null then "NULL" else tostring end)) | @tsv'
}
```

On magnetite:

```sh
devloop_sql() {
  printf 'user = "regulator:%s"\n' "$(sudo cat /run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password)" |
    curl --config - --silent --show-error --fail-with-body \
      'http://127.0.0.1:4000/v1/sql?db=devloop' --data-urlencode "sql=$1" |
    jq -r '.output[0].records | (.schema.column_schemas | map(.name)), (.rows[] | map(if . == null then "NULL" else tostring end)) | @tsv'
}
```

`devloop_sql 'SHOW TABLES'` then lists the four tables.
The database comes from `?db=devloop` or from the dashboard's connection database; a query run against `public` finds no table.
The queries below quote identifiers in double quotes, as `SHOW CREATE TABLE` prints them.

### The four tables

`flake.lib.otelCollectorSchema.devloop.tables` in `modules/clan/services/otel-collector/schema.nix` is the one list of tables and columns, and the store keeps nothing outside it.

| Table | One row per | Columns | Key | Time index |
|---|---|---|---|---|
| `ci_attribute` | finished attribute of a nixbot build | `build_id`, `attr`, `system`, `status`, `cached`, `abandoned`, `drv_path`, `outputs_out`, `started_at`, `finished_at`, `eval_wall_ms`, `eval_alloc_bytes`, `commit_sha`, `branch`, `pr_number`, `project` | `build_id`, `attr` | `finished_at` |
| `ci_build` | finished nixbot build | `build_id`, `created_at`, `started_at`, `finished_at`, `eval_duration_ms`, `status`, `pr_number`, `branch` | `build_id` | `finished_at` |
| `batch_event` | gitea-mq batch transition | `batch`, `msg`, `build`, `sha`, `failed_check`, `members`, `landed`, `ejected`, `builds`, `flaky`, `ts` | `batch`, `msg` | `ts` |
| `deploy_record` | activation or boot of a host | `host`, `closure`, `previous_closure`, `ts` | `host` | `ts` |

- `ci_attribute.status` is nixbot's attribute status: `succeeded`, `skipped_local` (already in the cache, not built), `failed`, `failed_eval`, `dependency_failed`, `ignored_failure`, `cancelled`, `building` or `pending`.
- `abandoned` is true only for an `ignored_failure` row whose error is nixbot's abandonment marker, an optional attribute that had not finished when the required attributes had settled; other `ignored_failure` rows are real failures of optional attributes.
- `outputs_out` is the attribute's `out` output path; `commit_sha`, `branch`, `pr_number` and `project` (`owner/name`) are its build's.
- `pr_number` is set for pull-request builds only; `main` builds and `gitea-mq/batch/<n>` builds have none.
- `ci_build.created_at` is when nixbot queued the build and `started_at` when it started; a build cancelled before it started has no `started_at`.
- `batch_event.msg` is one of `batch formed` (with `members`), `batch built` (with `build` and `sha`), `batch landed` (with `sha`), `batch bisecting` (with `build` and `failed_check`) and `batch done` (with `landed`, `ejected`, `builds` and `flaky`); `ts` is the journal's time of the line.
- A bisected batch repeats `batch built`, `batch landed` and `batch bisecting`, and each repetition is its own row, because its time differs.
- `deploy_record.closure` is the system the host activated and `previous_closure` the one it replaced; a record without `previous_closure` is a boot, not a deploy, and `ts` has whole seconds.
- An empty value is stored as `NULL`.

A row that arrives again with the same key and time replaces the stored one, because the tables are created with `append_mode = 'false'`; the collector re-reads every nixbot row about five times while it is younger than five minutes, and the store keeps it once.

### The three questions

Each question covers the past 7 days.

Formation to land is, for each batch, the time from its `batch formed` row to its `batch done` row.
`batch done` occurs once per batch; the `batch landed` rows of a bisected batch are kept but are not the endpoint.

```sql
SELECT f."batch" AS "batch",
       CAST(CAST(d."ts" AS BIGINT) - CAST(f."ts" AS BIGINT) AS DOUBLE) / 1000000.0 AS "formation_to_land_s"
FROM "batch_event" AS f
JOIN "batch_event" AS d ON d."batch" = f."batch"
WHERE f."msg" = 'batch formed'
  AND d."msg" = 'batch done'
  AND d."ts" >= now() - INTERVAL '7 days'
ORDER BY f."batch"
```

Queue wait is the 50th, 90th and 99th percentile of `started_at - created_at` over the first attempt of each pull-request build that started.
A restarted build keeps its `build_id` and `created_at` and gets new start and finish times, so the store holds a second `ci_build` row for it whose wait counts from the original creation; only the row with the smallest `finished_at` per `build_id`, the first attempt, is counted.
ADR-005 D5-R4's objective is a 90th percentile of at most one hour.

```sql
SELECT percentile_cont(CAST(CAST(c."started_at" AS BIGINT) - CAST(c."created_at" AS BIGINT) AS DOUBLE) / 1000000.0, 0.5) AS "p50_s",
       percentile_cont(CAST(CAST(c."started_at" AS BIGINT) - CAST(c."created_at" AS BIGINT) AS DOUBLE) / 1000000.0, 0.9) AS "p90_s",
       percentile_cont(CAST(CAST(c."started_at" AS BIGINT) - CAST(c."created_at" AS BIGINT) AS DOUBLE) / 1000000.0, 0.99) AS "p99_s",
       count(*) AS "builds"
FROM "ci_build" AS c
JOIN (SELECT "build_id", min("finished_at") AS "first_finished" FROM "ci_build" GROUP BY "build_id") AS f
  ON c."build_id" = f."build_id" AND c."finished_at" = f."first_finished"
WHERE c."pr_number" IS NOT NULL
  AND c."started_at" IS NOT NULL
  AND c."created_at" IS NOT NULL
  AND c."finished_at" >= now() - INTERVAL '7 days'
```

Per-build outcome classifies each `ci_attribute` row of the window.
`succeeded` and `skipped_local` pass; `failed`, `failed_eval` and an `ignored_failure` that is not `abandoned` are the derivation's own failures; `dependency_failed` fails the build but is not the derivation's own outcome; `cancelled`, `building`, `pending` and abandoned rows are no outcome.
A `drv_path` is flaky in the window when it has both a pass row and an own-failure row there.
A build fails when any of its rows that is neither abandoned nor of a flaky `drv_path` is an own failure or `dependency_failed`, and passes otherwise.
A build with no outcome row in the window, only `cancelled`, `pending`, `building` or abandoned rows, is left out of the answer rather than counted as passed.

```sql
WITH "attempt" AS (
  SELECT "build_id", "drv_path", "status",
         "status" IN ('succeeded', 'skipped_local') AS "pass",
         ("status" IN ('failed', 'failed_eval') OR ("status" = 'ignored_failure' AND "abandoned" = false)) AS "own_fail"
  FROM "ci_attribute"
  WHERE "finished_at" >= now() - INTERVAL '7 days'
),
"flaky_drv" AS (
  SELECT "drv_path"
  FROM "attempt"
  WHERE "drv_path" IS NOT NULL
  GROUP BY "drv_path"
  HAVING max(CASE WHEN "pass" THEN 1 ELSE 0 END) = 1
     AND max(CASE WHEN "own_fail" THEN 1 ELSE 0 END) = 1
)
SELECT a."build_id" AS "build_id",
       CASE WHEN max(CASE WHEN (a."own_fail" OR a."status" = 'dependency_failed') AND f."drv_path" IS NULL THEN 1 ELSE 0 END) = 1
            THEN 'failed' ELSE 'passed' END AS "outcome"
FROM "attempt" AS a
LEFT JOIN "flaky_drv" AS f ON f."drv_path" = a."drv_path"
GROUP BY a."build_id"
HAVING max(CASE WHEN a."pass" OR a."own_fail" OR a."status" = 'dependency_failed' THEN 1 ELSE 0 END) = 1
ORDER BY a."build_id"
```

The store cannot attribute a `dependency_failed` row to the derivation that failed under it.
nixbot names that derivation only in its error text, which `devloop` never stores, and no dependency edge is collected.
So a build whose only failures are `dependency_failed` rows below a flaky derivation still counts as failed.
Flakiness and abandonment are computed when a query runs, so a change to their definitions reinterprets the whole year.

### Attributing a deploy to its commits

A deploy's `closure` is the `outputs_out` of the passing `checks.x86_64-linux.nixos-magnetite` attribute of every build that produced that system:

```sh
devloop_sql "$(cat <<'SQL'
SELECT d."ts", d."closure", a."commit_sha", a."branch", a."pr_number", a."build_id"
FROM "deploy_record" d
JOIN "ci_attribute" a ON a."outputs_out" = d."closure"
WHERE d."host" = 'magnetite'
  AND a."attr" = 'checks.x86_64-linux.nixos-magnetite'
  AND a."status" IN ('succeeded', 'skipped_local')
ORDER BY d."ts" DESC
LIMIT 20
SQL
)"
```

One deploy can match several rows, one per build that produced the same closure, such as a pull request's build and the merge queue's; each of their commits built it.
A deploy whose closure matches no row was built outside CI, an activation outside the closure operator in ADR-005 D5-R7's terms.
A boot record repeats the booted closure with no `previous_closure`, so a deploy is a record whose `closure` differs from the host's previous record.

### When devloop-reconcile fails

`devloop-reconcile.service` runs at 02:15 UTC over the previous UTC day, from 00:00 to 24:00, as its own PostgreSQL role, the journal reader and the store's `regulator`.
It prints one line per clause, `devloop-reconcile: C<n> <name>: ok` or `devloop-reconcile: C<n> <name>: FAIL <detail>`, and exits 1 when any clause fails.
It exits 2 when it cannot read a source or the store at all, or when `DEVLOOP_RECONCILE_DAY` or `DEVLOOP_RECONCILE_DATABASE` is malformed.
Either failure posts `FAILED devloop-reconcile.service on magnetite` to `fleet-alerts`.
Read the run on magnetite, keeping only the clause lines, because a run also prints PostgreSQL's collation-version warnings and up to 12 `C7` wait lines:

```sh
sudo journalctl -u devloop-reconcile -o cat -n 200 --no-pager | grep '^devloop-reconcile: C'
systemctl show devloop-reconcile -p ExecMainStatus
```

| Clause | Fails when | Check first |
|---|---|---|
| `C1 attributes` | a nixbot attribute `(build_id, attr, finished_at)` of the day is missing from `ci_attribute`, or `ci_attribute` holds one nixbot cannot explain | `sudo journalctl -u opentelemetry-collector --since -1d --no-pager \| grep sqlquery`; then replay `sqlquery/ci_attribute` |
| `C2 builds` | the same for `ci_build` against nixbot's builds | the same, for `sqlquery/ci_build` |
| `C3 batch-lines` | the day's count of `gitea-mq.service` batch lines differs from `batch_event`'s for some `msg` | `sudo journalctl -u opentelemetry-collector --since -1d --no-pager \| grep journald`; then replay `journald/gitea-mq` |
| `C4 batch-liveness` | nixbot finished a `gitea-mq/batch/` build that day but `batch_event` has no `batch built` row | `sudo journalctl -u gitea-mq.service --since -1d --no-pager \| grep 'msg="batch'`; a renamed message stops the copy, and this clause is its only guard |
| `C5 batch-fields` | a `batch done` row lacks `landed`, `ejected`, `builds` or `flaky` | the `batch done` lines in the same journal; gitea-mq has changed that message's keys |
| `C6 deploys` | the day's lines of `/var/log/deploy-record.jsonl` and `deploy_record`'s rows for magnetite differ in number | `sudo journalctl -u opentelemetry-collector --since -1d --no-pager \| grep file_log`; then replay `file_log/deploy-record` |
| `C7 current-system` | the latest `deploy_record` row for magnetite does not name `readlink -f /run/current-system`, after the reconcile has retried the store read every 10 s for 120 s while the file's last line already names it | the last line of `/var/log/deploy-record.jsonl` and whether the last activation appended one |

A stored attribute row that nixbot no longer has is accepted when nixbot's current `finished_at` for that `(build_id, attr)` is empty or later, because a restarted attribute keeps its key and finishes again.
It is also accepted when nixbot no longer has the attribute and its build's current `finished_at` is empty or later, because a restarted build deletes its attributes for systems it no longer builds, finished ones included (`Mic92/nixbot@d020013fa:nixbot/nixbot/rerun_exec.py:83-92`).
Any other extra row means a table keeps duplicates, so compare `SHOW CREATE TABLE "<table>"` with `append_mode = 'false'` before replaying anything.
For an exit 2, check `systemctl status devloop-pg-grants postgresql greptimedb` first.
`devloop-pg-grants` grants once per boot, and at an activation only when the unit changes, and does not run again when nixbot restarts, so a nixbot migration that drops and recreates a granted column removes the grant until the unit next runs (boot, or `systemctl restart devloop-pg-grants`).
That shows as permission errors in `sudo journalctl -u opentelemetry-collector --since -1d --no-pager | grep sqlquery` and as a failed `C1` or `C2`, or an exit 2; `sudo systemctl restart devloop-pg-grants` grants again, and a replay restores the missed rows.
`C4` can fail falsely across midnight on a day with a single batch, when its build finished before 00:00 UTC and its `batch built` line was written after, or the reverse; check the neighbouring day's `batch built` rows for that build before replaying.

After fixing the cause, run the failed day again instead of waiting for the night, with a runtime drop-in naming the day as `YYYY-MM-DD`:

```sh
printf "[Service]\nEnvironment=DEVLOOP_RECONCILE_DAY=2026-10-20\n" | sudo systemctl edit --runtime --stdin --drop-in=rerun-day devloop-reconcile
sudo systemctl start devloop-reconcile
sudo journalctl -u devloop-reconcile -o cat -n 200 --no-pager | grep '^devloop-reconcile: C'
sudo systemctl revert devloop-reconcile
```

After a failure, the next passing run posts `RESOLVED devloop-reconcile.service on magnetite`, whatever day it checked, so rerun the day that failed rather than another.
Revert the drop-in after the run, so the next night checks its own previous day.
`DEVLOOP_RECONCILE_DATABASE` names the store database the same way, and a drop-in setting it to a database that does not exist forces a failure end to end, as "Forcing a failure deliberately" does for the envelope.

The timer is `Persistent=true`, so after magnetite was down at 02:15 the reconcile runs once at boot, for the previous day only.
Days missed while magnetite was down are never reconciled by themselves: rerun each of them with `DEVLOOP_RECONCILE_DAY` as above, one day per start.

### Replaying a gap

Each receiver keeps its position in the collector's storage directory, `/var/lib/opentelemetry-collector/queue`, in its own file:

| Receiver | Position file | Feeds | Without its file it reads |
|---|---|---|---|
| `sqlquery/ci_attribute` | `receiver_sqlquery_ci_attribute` | `ci_attribute` | nixbot's whole retained history, 10,000 rows a minute |
| `sqlquery/ci_build` | `receiver_sqlquery_ci_build` | `ci_build` | nixbot's whole retained history, 10,000 rows a minute |
| `journald/gitea-mq` | `receiver_journald_gitea-mq` | `batch_event` | the whole retained journal of `gitea-mq.service`, across every boot, because the receiver runs `journalctl` through a wrapper that adds `--boot=all` |
| `file_log/deploy-record` | `receiver_filelog_deploy-record` | `deploy_record` | the whole of `/var/log/deploy-record.jsonl` |

The `exporter_otlp_http_*` files in the same directory hold rows not yet written to the store; never remove one.
To replay a gap that a reconcile clause names, remove that receiver's position file while the collector is stopped:

```sh
sudo ls -1 /var/lib/opentelemetry-collector/queue
sudo systemctl stop opentelemetry-collector
sudo rm /var/lib/opentelemetry-collector/queue/receiver_sqlquery_ci_attribute
sudo systemctl start opentelemetry-collector
```

The receiver then starts from its beginning and sends every row again, and the store keeps one row per key and time, so only the missing rows are added.
nixbot keeps 90 days of builds, and the journal keeps `gitea-mq.service`'s lines only until journald rotates them out, about five weeks on magnetite in October 2026, so a replay restores only what the source still holds.
A replay of `sqlquery/ci_attribute` sends about 200,000 rows in about 20 minutes; wait until `devloop_sql 'SELECT count(*) FROM "ci_attribute"'` stops rising, then rerun the failed day as above.
A record the store's pipeline cannot convert fails the whole OTLP request with HTTP 400, which the exporter drops as permanent, while `sqlquery` has already advanced its cursor past it; so one bad record can lose up to 10,000 nixbot rows, one page, or a batch of journal or deploy-record lines.
No alert reports that at once: `C1`, `C2`, `C3` or `C6` fails the next morning, and the replay above restores the rows once the cause is fixed.
The collector also stores each nixbot query's position under a key that contains the query's text, so a merged change to an export query replays that query's whole history at its first start, about 200,000 attribute rows, over the row budget that day.
Both nixbot queries advance their position before the rows are delivered, so nixbot rows the collector's `memory_limiter` refuses are lost once they are older than the five-minute overlap; the reconcile reports them and the replay above restores them.
`journald/gitea-mq` also advances its position first, but retries a refused line with no time limit, so a refusal holds its reader until the line is accepted rather than losing it.

### The row budget

ADR-004 bounds `devloop` at 100,000 rows a day.
The busiest day before S2, 2026-10-14, would send about 64,800 attribute rows, counting each row's five re-reads, and store 12,867.
S2's deploy of the collection (D3) sent nixbot's retained history, about 200,000 attribute rows in about 20 polls, and exceeded the budget on that day only, as the design accepted: on 2026-10-22 the collector sent 204,203 rows and the store held 204,163.
A replay of `sqlquery/ci_attribute` exceeds it the same way, once.
Count the stored rows per day:

```sh
devloop_sql "$(cat <<'SQL'
SELECT date_trunc('day', "finished_at") AS "day", count(*) AS "rows"
FROM "ci_attribute"
WHERE "finished_at" >= now() - INTERVAL '14 days'
GROUP BY 1
ORDER BY 1
SQL
)"
```

### When PullRequestQueueWaitBurn fires

`PullRequestQueueWaitBurn` is a `warning` that reads `devloop` through SQL: it holds when at least 10 pull-request builds that started finished their first attempt in the trailing 24 hours and more than one in ten of those first attempts waited over an hour from `created_at` to `started_at`, and it fires after holding for an hour.
A restarted build's later attempts are left out, because their wait counts from the build's original creation.
Its expression is in `modules/nixos/fleet-alert/rules.nix`.
It is posted once as `[FIRING] PullRequestQueueWaitBurn` with no host, is never posted again while it fires, and resolves after 5 minutes without the condition.
On a day with fewer than 10 pull-request builds it stays silent, so a single slow build cannot fire it.
The flake updater opens one pull request per changed input, and its runs of 10 to 26 at once caused every firing in S2's first weeks: a firing during an updater run is that run's queue contention, kept deliberately because one combined pull request would let any failing input hold back every other update.
A missing `devloop` or `ci_build` table fails the query, which freezes only the rules on `devloop` and raises one `StoreQueryFailing` whose message names `devloop`; the `fleet` rules keep being evaluated and posted.

When it fires, list the slow builds:

```sh
devloop_sql "$(cat <<'SQL'
SELECT c."build_id", c."pr_number", c."branch", c."created_at", c."started_at", c."finished_at"
FROM "ci_build" c
JOIN (SELECT "build_id", min("finished_at") AS "first_finished" FROM "ci_build" GROUP BY "build_id") f
  ON c."build_id" = f."build_id" AND c."finished_at" = f."first_finished"
WHERE c."pr_number" IS NOT NULL
  AND c."started_at" > c."created_at" + INTERVAL '1 hour'
  AND c."finished_at" >= now() - INTERVAL '24 hours'
ORDER BY c."created_at"
SQL
)"
```

Then see whether nixbot's queue is still deep with `nixbot-logs queue`, and read each slow pull request's builds with `nixbot-logs builds --pr <pr_number>`.
Run the queue-wait question above for the week: a 90th percentile over one hour breaks ADR-005 D5-R4's objective.
D5-R4's response is to move attributes out of the pull-request lane through D5-R1, by pull request, rather than to add evaluators, because nixbot's evaluator is memory-bound.

## Declaring a per-table TTL

Every table normally keeps its database's retention, and the envelope fails on any table with a TTL of its own.
A table allowed its own TTL is declared in magnetite's configuration as `<database>.<table>`:

```nix
services.greptimedb.tableTtls = {
  "fleet.logs" = "14d";
};
```

The envelope then requires that table to carry exactly that TTL; a declared table that does not exist yet is not judged.
The declaration does not set the TTL: the change that creates the table sets it, and S7 does so for the `fleet` logs table.

## Not covered yet

- S2 left for later slices: the deploy records of the hosts other than magnetite, collected once S4 and S5 run collectors there, while `devloop-reconcile` checks magnetite's alone; dashboards over `devloop` (S6); and attributing a `dependency_failed` attribute to the derivation that failed under it, which would need error text or dependency edges that S2 does not store.
- S3 left for later slices: the filesystem, NVMe, launchd and `HostProbeStale` rules (S4, S5), and an external watch of cinnabar and ntfy themselves (CAM-76).
- S4: the other NixOS hosts as collector agents, over an mTLS ingress on ZeroTier.
- S5: stibnite on darwin.
- S6: the dashboard on its own SSO-protected vhost with provisioned dashboards, replacing the SSH tunnel.
- S7: omp telemetry and journald logs into `agent` and `fleet`.
- S8: the Parquet export of the store and its reader.
