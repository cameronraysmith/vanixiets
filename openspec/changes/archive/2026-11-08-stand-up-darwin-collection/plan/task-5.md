### Task 5: stibnite's watched activation

Implements `tasks.md` 5.1–5.4 (design D2 to D6, D11, D12, Migration Plan steps 4 and 5; O1; HMC `Each agent host contributes its own signals to the telemetry store`, `Each stored series names its host`; FII `A laptop's disk health is read on the host and served on loopback`; DCI `Each agent host's collector ships its own deploy records`; DC `Every dev-loop event is recorded once and kept for a year`; WA `A63 — stibnite's internal SSD answers the SMART health read without privilege at the pinned smartmontools`, `A65 — A store-built binary on stibnite reaches the ingress over ZeroTier`).
It starts only after Task 4 has passed; Steps 1 and 2 run with the operator at stibnite, Step 3 reads stibnite and magnetite read-only, and Step 4 deploys magnetite.
Step 2 opens pull request 2, the one-line change removing stibnite's `collect = false`, enqueued only after Step 1's recorded yes, so no routine activation from `main` starts the collector without the operator.
The magnetite deploy of Step 4 follows because the evaluator reads stibnite's row from magnetite's closure; until it lands the evaluator expects stibnite nowhere.
Each verification block below marked `rehearse:` was run once in Task 1 Step 3, before the jobs it reads existed, so its expected output there was the "not loaded" form.

**Files:**
- Create (git-ignored): `logs/stibnite-<ts>.log`, `logs/magnetite-<ts>.log` (in `$DEPLOY`), `logs/s5-evidence/5.<n>-*.log`, `logs/s5-evidence/rss-sampler.sh`, `logs/s5-evidence/rss.tsv`; `logs/s5-evidence/window.env` gains `STIBNITE_ACTIVATE_EPOCH`, `STIBNITE_COLLECT_EPOCH` and `MAGNETITE_DEPLOY_EPOCH`
- Modify (pull request 2): `modules/lib/observability-hosts.nix`, stibnite's row only

**Interfaces:**
- Consumes: Task 4 passed; `$DEPLOY`; `mark.sh`, `posts.sh` (Task 4 Step 1); `gsql.sh`, `promq.sh` (Task 1); design "Requirement applicability".
- Produces: stibnite's first stored series and their names, the deploy-record count, `STIBNITE_COLLECT_EPOCH` (the start of stibnite's history, read by Task 6's replay and Task 9), and `rss.tsv`, the collectors' resident memory sampled each minute stibnite is awake, read by Tasks 6 and 8.

- [ ] **Step 1: Presence gate (tasks.md 5.1) [operator]**

The orchestrator asks the operator, and does not proceed without the answer: "Are you at stibnite now, on mains power and on the mesh, with no build dispatched to it, and may I enqueue the pull request that starts its collection and then activate it?"
The answer is recorded verbatim with `/bin/date -u` in `logs/s5-evidence/5.1-presence-<ts>.log`, beside these reads; rehearse: stibnite, read-only:

```bash
L=logs/s5-evidence/5.1-presence-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
{
/bin/date -u
/usr/bin/pmset -g batt | /usr/bin/head -n 1
/sbin/ping6 -c 3 fddb:4344:343b:14b9:399:930f:39db:40d2; echo "ping-rc=$?"
/bin/ps -axo user,command | awk '$1 ~ /^_nixbld/ && $2 !~ /distnoted$/'; echo "builders-listed-above"
/usr/bin/sudo /usr/sbin/lsof -nP -a -c nix-grpc -iTCP -sTCP:ESTABLISHED; echo "lsof-rc=$?"
ls logs/s5-evidence/4.1-magnetite-*.log logs/s5-evidence/4.2-stibnite-*.log
} 2>&1 | tee -a "$L"
```

Expected: `Now drawing from 'AC Power'`; `ping-rc=0`; no line above `builders-listed-above` and `lsof-rc=1` (no build and no remote-build connection; launchd keeps one `distnoted agent` per build account at all times, 15 on 2026-11-05, which the filter leaves out); both Task 4 logs present and their verifications passed.
Without a recorded yes, Steps 2 to 4 do not run.

- [ ] **Step 2: Start stibnite's collection and activate it (tasks.md 5.2) [operator]**

Only after Step 1's recorded yes: in a change off `main@origin`, delete the `collect = false;` in stibnite's row of `modules/lib/observability-hosts.nix` (`stibnite = agent [ ] // { platform = "darwin"; notifiedUnits = [ "otel-envelope" ]; smartDevices = [ "disk0" ]; collect = false; };` becomes the same row without `collect = false;`), run `nix fmt` keeping its log, and confirm in `$REPO`:

```bash
jj st --no-pager >/dev/null
nix eval --json .#lib.observabilityHosts.stibnite.collect
nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath
```

Expected: `true`, then a drvPath; the darwin fragment's assertions hold, since a failing one stops this evaluation (evaluation).
Commit it alone with a plain message, for example "Start collecting stibnite's host metrics", open its pull request with the same title and a body saying it starts the collector agent, the process collector, the loopback node exporter, the host probe and the delivery check on stibnite ahead of an activation made with someone at the machine, and let it merge through the queue while the operator stays at stibnite.
Then, in `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `git -C $DEPLOY log -1 --format='%H %s'` showing the merge, and after `"$REPO/logs/s5-evidence/recent-activation.sh"` prints `no activation since` or its `STOP` is resolved with the operator (Task 4 Step 1):

```bash
"$REPO/logs/s5-evidence/recent-activation.sh"
"$REPO/logs/s5-evidence/mark.sh" STIBNITE_ACTIVATE_EPOCH
just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log
"$REPO/logs/s5-evidence/mark.sh" STIBNITE_COLLECT_EPOCH
```

Expected: the log ends without error.
A failed activation leaves the previous generation running; the operator reads the log at the machine, and rollback is the reverse of this step (restore `collect = false` by its own pull request and activate).
rehearse: stibnite, read-only, in `$REPO`:

```bash
L=logs/s5-evidence/5.2-activate-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
{
readlink /run/current-system
for j in otelcol otelcol-process prometheus-node-exporter otel-host-probe otel-envelope; do
  echo "== org.nixos.$j"
  /bin/launchctl print "system/org.nixos.$j" 2>&1 | grep -E '^[[:space:]](state|runs|pid|last exit code) = |Could not find service'
  /usr/bin/plutil -extract UserName raw "/Library/LaunchDaemons/org.nixos.$j.plist" 2>&1
done
} 2>&1 | tee "$L"
```

Expected: `state = running` with a `pid` for `otelcol`, `otelcol-process` and `prometheus-node-exporter`; `otel-host-probe` and `otel-envelope` loaded (no `Could not find service`), `runs` at least 1 for the probe within a minute and for the envelope within 5 min (rerun the block if read sooner); `UserName` `_otelcol` for `otelcol` and `otel-envelope`, `_prometheus-node-exporter` for `prometheus-node-exporter` and `otel-host-probe`, and none (root) for `otelcol-process` (delivered files).
Then the posts since the activation started:

```bash
. logs/s5-evidence/window.env
logs/s5-evidence/posts.sh "$STIBNITE_ACTIVATE_EPOCH" 2>&1 | tee -a "$L"
```

Expected: `grep-rc=1`, and `notify.log` empty or absent, or each post given its cause under `## Causes`; a `FAILED otel-envelope on stibnite` from the first run is a finding unless its envelope log line names a cause outside the change.

- [ ] **Step 3: stibnite's first-activation capture (tasks.md 5.3)**

Start the memory sampler, which Tasks 6 and 8 read, from `$REPO`, read-only:

```bash
cat > logs/s5-evidence/rss-sampler.sh <<'EOS'
#!/bin/bash
# rss-sampler.sh: each minute, appends "<epoch> <otelcol rss KiB> <otelcol-process rss KiB>" to rss.tsv.
d=$(cd "$(dirname "$0")" && pwd)
rss() { p=$(/bin/launchctl print "system/org.nixos.$1" 2>/dev/null | awk '$1 == "pid" { print $3; exit }'); [ -n "$p" ] && /bin/ps -o rss= -p "$p" | tr -d ' ' || echo NA; }
while :; do echo "$(/bin/date -u +%s) $(rss otelcol) $(rss otelcol-process)" >> "$d/rss.tsv"; sleep 60; done
EOS
chmod +x logs/s5-evidence/rss-sampler.sh
nohup logs/s5-evidence/rss-sampler.sh >/dev/null 2>&1 &
echo "sampler pid $!"
```

It runs as the operator's user, reads only, and pauses while stibnite sleeps; it is stopped (`kill <pid>`) after Task 8 Step 6.
rehearse: stibnite and magnetite, read-only:

```bash
L=logs/s5-evidence/5.3-stibnite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
sent() { /usr/bin/curl -s http://127.0.0.1:8888/metrics | grep -E '^otelcol_exporter_sent_metric_points(_total)?\{[^}]*exporter="otlp_http/ingress"'; }
{ /bin/date -u +%s; sent; sleep 60; /bin/date -u +%s; sent; } 2>&1 | tee "$L"
/usr/bin/curl -s http://127.0.0.1:8888/metrics | grep -E '^otelcol_exporter_(queue_size|send_failed_metric_points)' | tee -a "$L"
/usr/bin/sudo /usr/sbin/lsof -nP -iTCP -sTCP:LISTEN | awk 'NR == 1 || $1 ~ /otelcol|node_expo/' | tee -a "$L"
```

Expected: the second `otlp_http/ingress` count above the first, which settles C1: the store-built collector reaches the ingress over ZeroTier (A65); the queue sizes near 0 and no growing `send_failed`; every listener of `otelcol-contrib` and `node_expo` on `127.0.0.1`, with `otelcol-process` holding none.
A count that does not grow stops the sequence: magnetite is not deployed, the operator is told, and the exporter's error is read from the agent's log under `/var/log/otelcol` (`/usr/bin/sudo /usr/bin/tail -n 50 /var/log/otelcol/*`) and the probe's at `/var/lib/prometheus-node-exporter/otel-host-probe.log`, and recorded; the queue holds the interval meanwhile (design Risks).
The store, on magnetite as `regulator`:

```bash
logs/s5-evidence/promq.sh 'count by (host_name) (system_memory_usage_bytes)' | tee -a "$L"
logs/s5-evidence/gsql.sh fleet "SELECT host_name, state, count(*) FROM system_memory_usage_bytes WHERE host_name = 'stibnite' GROUP BY host_name, state ORDER BY state" | tee -a "$L"
export GSQL_PW_PATH=$(nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path)
logs/s5-evidence/gsql.sh fleet "SELECT DISTINCT table_name FROM information_schema.columns WHERE table_schema = 'fleet' AND column_name = 'host_name' ORDER BY table_name" > logs/s5-evidence/5.3-tables.tsv
# One statement per 50 tables: one ssh and one evaluation per table took 1,300 s
# for 416 tables in the rehearsal on 2026-11-05.
split -l 50 logs/s5-evidence/5.3-tables.tsv /tmp/s5-tables.
for f in /tmp/s5-tables.*; do
  sql=$(awk -v q="'" 'NR > 1 { printf " UNION ALL " } { printf "SELECT %s%s%s AS t, count(*) AS n FROM \"%s\" WHERE host_name = %sstibnite%s AND greptime_timestamp > now() - INTERVAL %s15 minutes%s", q, $1, q, $1, q, q, q, q }' "$f")
  logs/s5-evidence/gsql.sh fleet "$sql" < /dev/null
done | awk -F'\t' '$2 > 0' | tee -a "$L"
rm -f /tmp/s5-tables.*
```

Expected: `stibnite` among the PromQL rows; the SQL read of `system_memory_usage_bytes` with `WHERE host_name = 'stibnite'` returns rows, for states `used`, `free` and `inactive`; and the stored tables under `host_name="stibnite"` cover every row of design "Requirement applicability" marked applies: `system_memory_usage_bytes`, `process_memory_usage_bytes`, the `system_disk_*` tables, `system_filesystem_usage_bytes`, `launchd_job_state`, `launchd_job_last_exit_code`, `launchd_job_runs_total`, `node_textfile_mtime_seconds`, `node_textfile_scrape_error`, `up`, A4's eight `smartctl_device_*` names and the `otelcol_*` self-telemetry of SC's keep-list.
None of the excluded rows appears for stibnite: `system_linux_memory_available_bytes`, `system_paging_usage_bytes`, `systemd_unit_state`, `systemd_service_restarts_total`, `node_zfs_*`, `node_vmstat_*`.
The table list is recorded as the stored names Task 6 Step 1 compares with the rules.
The bounds of item 21 and the SMART read:

```bash
for t in $(awk '/^system_disk_/' logs/s5-evidence/5.3-tables.tsv); do
  printf '%s ' "$t"; logs/s5-evidence/gsql.sh fleet "SELECT DISTINCT device FROM \"$t\" WHERE host_name = 'stibnite'" < /dev/null | tr '\n' ' '; echo
done | tee -a "$L"
logs/s5-evidence/gsql.sh fleet "SELECT DISTINCT mountpoint FROM system_filesystem_usage_bytes WHERE host_name = 'stibnite'" | tee -a "$L"
logs/s5-evidence/promq.sh 'smartctl_device_critical_warning_total{host_name="stibnite"}' | tee -a "$L"
logs/s5-evidence/promq.sh 'smartctl_device_percentage_used_total{host_name="stibnite"}' | tee -a "$L"
/usr/bin/sudo /bin/ls -l /var/lib/prometheus-node-exporter/textfile/ | tee -a "$L"
/usr/bin/sudo /usr/bin/grep -E '^smartctl_device_(critical_warning|percentage_used|smart_status)' /var/lib/prometheus-node-exporter/textfile/smartctl.prom | tee -a "$L"
```

Expected: `disk0` only for each disk table; `/System/Volumes/Data` only; stored critical warning `0` and percentage used `0`, as A63's read on 2026-11-05; `launchd.prom` and `smartctl.prom` owned by `_prometheus-node-exporter` with an mtime within the last minute, so the SMART read ran without privilege as that user (A63; delivered files).
Deploy records and the envelope's first runs:

```bash
lines=$(/usr/bin/wc -l < /var/log/deploy-record.jsonl | tr -d ' ')
rows=$(logs/s5-evidence/gsql.sh devloop "SELECT count(*) FROM deploy_record WHERE host = 'stibnite'")
echo "stibnite lines=$lines rows=$rows" | tee -a "$L"
for k in StandardOutPath StandardErrorPath; do
  p=$(/usr/bin/plutil -extract "$k" raw /Library/LaunchDaemons/org.nixos.otel-envelope.plist 2>/dev/null) || continue
  echo "== $k $p"; /usr/bin/sudo /usr/bin/tail -n 20 "$p"
done 2>&1 | tee -a "$L"
/usr/bin/sudo /bin/cat /var/lib/otel-envelope/notify.log 2>&1 | tee -a "$L"
/usr/bin/tail -n 3 logs/s5-evidence/rss.tsv | tee -a "$L"
```

Expected: `lines` equal `rows` (the file was shipped from its beginning; a difference lists the missing `ts` values from `SELECT ts FROM deploy_record WHERE host = 'stibnite' ORDER BY ts` against `jq -r '.ts // empty' /var/log/deploy-record.jsonl`, and is a finding); every envelope clause line `ok`, C5's included, on each run since activation (the first run records C4's baseline); `notify.log` without `FAILED`; both collectors' resident memory in KiB, recorded against C5's 256 MiB and 128 MiB.
An hour after stibnite's series first appear, record every post naming stibnite from the evaluator's journal with its cause, because stibnite now feeds rules no replay covered: `ssh magnetite.zt 'bash -c "sudo journalctl -u fleet-alert -o cat --since \"-70min\" | grep -E \"stibnite\" || true"' | tee -a "$L"`; until Step 4 the evaluator expects stibnite nowhere, so a post naming it is a finding.

- [ ] **Step 4: Deploy magnetite (tasks.md 5.4)**

In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty`:

```bash
"$REPO/logs/s5-evidence/mark.sh" MAGNETITE_DEPLOY_EPOCH
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
The delivered rule set is compared with the evaluated one at the same commit; rehearse: magnetite, read-only, run in `$DEPLOY` with the log in `$REPO`:

```bash
L=$REPO/logs/s5-evidence/5.4-magnetite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -s' <<'EOS' | jq -S . > /tmp/s5-rules-delivered.json
c=$(systemctl show fleet-alert -p Environment --value | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
jq '[.rules[]? | {alert, hosts: ([(.presence // [])[] | .expectedHosts // []] | add // [] | sort)}] | sort_by(.alert)' "$c"
EOS
nix eval --json .#.checks.x86_64-linux.fleet-alert.rules.rules --apply 'r: map (x: { inherit (x) alert; hosts = builtins.concatMap (p: p.expectedHosts) (x.presence or [ ]); }) r' \
  | jq -S '[.[] | .hosts |= sort] | sort_by(.alert)' > /tmp/s5-rules-evaluated.json
diff /tmp/s5-rules-delivered.json /tmp/s5-rules-evaluated.json && echo rules-match | tee "$L"
jq -c '.[] | select(.hosts | index("stibnite")) | .alert' /tmp/s5-rules-delivered.json | tee -a "$L"
```

Expected: `rules-match`, the delivered configuration against `fleet-alert`'s evaluation of the same commit (delivered file, evaluation); stibnite listed for `FilesystemFillingWarn`, `FilesystemFull`, `LocalExporterDown` and `WeeklyPipelineTest`'s presence, and for none of `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop` or `SystemdUnitFailed` (design D9); the NVMe rules list it only as Task 3 rendered them, recorded as found.
Then the posts since Step 2's activation started, from both hosts:

```bash
. "$REPO/logs/s5-evidence/window.env"
"$REPO/logs/s5-evidence/posts.sh" "$STIBNITE_ACTIVATE_EPOCH" 2>&1 | tee -a "$L"
```

`window.env`'s last `STIBNITE_ACTIVATE_EPOCH` is Step 2's, which precedes this deploy's `MAGNETITE_DEPLOY_EPOCH`, so the read covers both.
Expected: each post given its cause under `## Causes`; a restart of magnetite's units by the deploy is a known cause, and a post naming stibnite with no cause is a finding.
An hour after the deploy, the same read of the evaluator's journal for `stibnite` as Step 3's is appended to `$L`, since stibnite is now an expected host of the rules above.
