---
title: Fleet observability
description: "Operating the fleet's telemetry store, metrics collector and alerting: dashboard access, alerts and failure notices on fleet-alerts, the dead-man on cinnabar, the hourly envelope, credential rotation and retention."
---

This runbook is for the operator of the fleet's telemetry store and alerting, as deployed by slices S1 and S3.
It assumes SSH access to `magnetite.zt` and `cinnabar.zt` over ZeroTier, `sudo` on both, and a vanixiets checkout with the `clan` CLI on the workstation.
The maintainer contract for the collector lives in `modules/clan/services/otel-collector/README.md`; the failure notifier lives in `modules/nixos/observability-notify.nix`, the alert evaluator and the dead-man in `modules/nixos/fleet-alert.nix`, and the rules in `modules/nixos/fleet-alert/rules.nix`.

## What runs where

S1's store and collector, and S3's alert evaluator, run on magnetite; ntfy and S3's dead-man run on cinnabar.

- `greptimedb.service` runs GreptimeDB standalone, listening only on loopback: HTTP on `127.0.0.1:4000` and gRPC on `127.0.0.1:4001`.
- Its WAL and caches live on the ZFS dataset `zroot/root/greptimedb` at `/var/lib/greptimedb`, with a 16G quota and a 12G reservation.
- Its table data goes to Cloudflare R2, bucket `sciexp`, under the prefix `projects/vanixiets/observability/store/`.
- `greptimedb-schema.service` creates the databases and sets their retention each time the store starts.
- `opentelemetry-collector.service` collects magnetite's host, unit, process-memory, ZFS, OOM-kill and service metrics and writes them to the store.
- `greptimedb-envelope.timer` runs `greptimedb-envelope.service` hourly to check the store's runtime envelope.
- `observability-notify@.service` posts unit failures to ntfy with the `alerter` token, on magnetite and on cinnabar.
- `fleet-alert.timer` runs `fleet-alert.service` on magnetite every 60 s: it evaluates the alert rules against `fleet`, posts a heartbeat to `fleet-heartbeat`, and posts alerts to `fleet-alerts`.
- `fleet-deadman.timer` runs `fleet-deadman.service` on cinnabar every 5 min: it checks that anonymous publishing to `fleet-heartbeat` is refused, then raises `AlertEvaluatorSilent` when no heartbeat arrived in the last 10 min.
- `ntfy-sh.service` on cinnabar serves `https://ntfy.zt` through caddy; only the `alerter` user may publish to `fleet-*` topics, every other topic stays open to anonymous publishing, and anyone on the mesh may subscribe.

The store holds three databases.

| Database | Retention | Written by |
|---|---|---|
| `fleet` | 30 days | the collector, from S1 |
| `devloop` | 365 days | nothing until S2 |
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

An alert's title is `[FIRING] <alert> <host>` or `[RESOLVED] <alert> <host>`; an alert that carries no host, such as `StoreQueryFailing`, `RuleSignalMissing` for a whole selector, `AlertBudgetExceeded` or `WeeklyPipelineTest`, has no host in its title.
Its priority follows the rule's severity: `high` for `critical`, `default` for `warning`, `low` for `info`.
An alert fires after its condition has held on every evaluation for the rule's `for`, and resolves after the condition has been absent for 5 minutes of unfrozen evaluations.
Time spent frozen does not count as absence: after a store outage or a host's silence, an alert resolves only 5 minutes after the first unfrozen evaluation that no longer sees its condition.
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
| `StoreQueryFailing` | critical | the store has not answered the evaluator for 3 min; every other alert is frozen meanwhile | `systemctl status greptimedb greptimedb-schema` and `sudo journalctl -u greptimedb -n 100 --no-pager` on magnetite; starting the store also starts `greptimedb-schema` again; alerts resume when the store answers |
| `RuleSignalMissing` | warning | a rule's input series has been absent for 30 min while its expected host reports memory, so the rule can no longer fire; the message's `rule` and `selector` labels name both | find the metric's producer: the collector config, the node exporter, or a renamed metric in a dependency update |
| `RuleSignalMissing <host>` | warning | an always-on host (magnetite in S3) has been missing from the store for 10 min while the store answers, with selector `system_memory_usage_bytes`; that host's alerts are frozen meanwhile | first that host's collector, `systemctl status opentelemetry-collector` and `sudo journalctl -u opentelemetry-collector -n 100 --no-pager`, then its export path to magnetite's ingress and the store |
| `AlertEvaluatorSilent` | critical | cinnabar's dead-man saw no heartbeat on `fleet-heartbeat` for 10 min; it runs every 5 min, so it fires up to 15 min after the evaluator stops (14 min 28 s at acceptance) and resolves within about 5 min of its return (4 min 12 s) | on magnetite `systemctl status fleet-alert.timer fleet-alert.service` and `sudo journalctl -u fleet-alert -n 50 --no-pager`; also check magnetite is up and on the mesh |
| `AlertBudgetExceeded` | none, posted at `default` | more than 10 `FIRING` messages, or more than 3 for stibnite or for pyrite, were posted in 24 hours | the alerts have become noise; read the 24 hours of `fleet-alerts` and tune the rule that dominates, through a pull request |

While a host reports no `system_memory_usage_bytes`, its alerts are frozen: they neither resolve nor post again, so a sleeping laptop does not churn, and their 5 minutes of absence start only when the host reports again.

Nothing reports an outage of ntfy or cinnabar themselves: every alert, failure notice and dead-man post goes through ntfy on cinnabar, so such an outage shows only as a missing Monday `WeeklyPipelineTest`, up to 7 days after it begins.
Treat a Monday without that message as an outage of the alert path until a test post shows otherwise; CAM-76, scheduled before S5, adds a watch from outside cinnabar.

## Reading failure notices

Unit failures go to the same topic as plain messages without a title.
The notified units on magnetite are `greptimedb`, `greptimedb-schema`, `greptimedb-envelope`, `opentelemetry-collector`, `fleet-alert` and magnetite's `zfs-set-*` and `zfs-assert-*` oneshots; on cinnabar it is `fleet-deadman`.
Print the current list for a host:

```sh
nix eval --json .#nixosConfigurations.magnetite.config.services.observability-notify.units
```

- `FAILED <unit> on <host>` means the unit entered the failed state and a new failure episode began.
- `RESOLVED <unit> on <host>` means the same unit has since started again, or exited successfully, and the episode is over.

A `FAILED fleet-alert.service on magnetite` means a run could not post its heartbeat or an alert, or reached its post deadline; `sudo journalctl -u fleet-alert -n 50 --no-pager` on magnetite names the post.
A `FAILED fleet-deadman.service on cinnabar` means ntfy did not refuse the anonymous probe with 403, or the heartbeat poll failed; `sudo journalctl -u fleet-deadman -n 20 --no-pager` on cinnabar shows which.

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

- S2: dev-loop metrics into `devloop`: nixbot, gitea-mq and deploy records.
- S3 left for later slices: the filesystem, NVMe, launchd and `HostProbeStale` rules (S4, S5), the dev-loop SLO burn rule (S2), and an external watch of cinnabar and ntfy themselves (CAM-76).
- S4: the other NixOS hosts as collector agents, over an mTLS ingress on ZeroTier.
- S5: stibnite on darwin.
- S6: the dashboard on its own SSO-protected vhost with provisioned dashboards, replacing the SSH tunnel.
- S7: omp telemetry and journald logs into `agent` and `fleet`.
- S8: the Parquet export of the store and its reader.
