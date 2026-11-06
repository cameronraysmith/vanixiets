### Task 8: Acceptance

Implements `tasks.md` 8.1–8.8 (design D6, D10, D12, Migration Plan steps 6 and 7; O5, O6, O7; Linear CAM-72's AC2 to AC4; HMC `Series cardinality stays bounded`, `A failed collection or store job notifies a person`; FII `otel-envelope regulates each agent from its own collector`, `The darwin probe reports each allow-listed launchd job and the host's disk health in a textfile`; TSI `The telemetry store and the collector run inside a declared envelope`, `Failure notices are posted to one topic`, `A failure episode ends at the unit's next successful start or exit`; FA `Each known failure class on a host reaches a person as an alert`, `An unreachable telemetry store or a silent host freezes alerts`; FAI `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Store errors and silent hosts freeze instance state`, `The alerter token travels only as a file`; WA `A61 — launchd misses a StartInterval firing during sleep and coalesces missed StartCalendarInterval firings into one run at wake`, `A62 — launchctl print reports a system job's state, runs and last exit code as unversioned text, and omits the exit code for some killed jobs`, `A64 — stibnite sleeps and wakes in the dark many times a day`, `A66 — ntfy refuses an anonymous post to a fleet topic from stibnite`).
No pull request.
Steps 2 to 6 are **[operator]**: each starts only after the orchestrator has asked "Are you at stibnite now, and may I run `tasks.md` 8.<n>?" and recorded the answer with `/bin/date -u` in `logs/s5-evidence/8.<n>-presence-<ts>.log`; without a recorded yes the step does not run, and outside them nothing here changes stibnite.
Steps 1 and 2 run after Task 5 Step 4; Steps 3 to 7 after Task 6 Step 6, because they need the darwin rules on magnetite and `org.nixos.otel-envelope` in stibnite's probe; Step 8 reads Step 2's post.
Every step that stops, kills, reloads or sleeps anything ends with `posts.sh` over its start epoch, each post given its cause under `## Causes`, and the operator confirms on their ntfy client the posts the step expects and that no other arrived.

**Files:**
- Create (git-ignored): `logs/s5-evidence/8.<n>-*.log`; `logs/s5-evidence/window.env` gains `OTELCOL_STOP_EPOCH`, `OTELCOL_START_EPOCH`, `GRPC_STOP_EPOCH`, `GRPC_START_EPOCH`, `KILL_EPOCH`, `KICKSTART_EPOCH`, `RELOAD_EPOCH`, `LID_CLOSE_EPOCH`, `LID_OPEN_EPOCH`

**Interfaces:**
- Consumes: Tasks 4 to 6 deployed and activated; `mark.sh`, `posts.sh`, `gsql.sh`, `promq.sh`, `6.1-replay.sh`, `rss.tsv` and its sampler; `window.env`.
- Produces: the acceptance records `verify.md` cites, and the observed values that confirm or amend design D12's `[INFERENCE]` about `SIGTERM`'s exit code.

- [ ] **Step 1: A day of envelopes and the stored bounds (tasks.md 8.1)**

Over the 24 h after Task 5 Step 4, read at any time after them; rehearse: stibnite and magnetite, read-only:

```bash
L=logs/s5-evidence/8.1-day-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
# The second MAGNETITE_DEPLOY_EPOCH in window.env is Task 5 Step 4's (the first is Task 4's; later ones are Task 6's).
s=$(grep '^MAGNETITE_DEPLOY_EPOCH=' logs/s5-evidence/window.env | sed -n 2p | cut -d= -f2); e=$(( s + 86400 ))
{
echo "window $s $e"
/usr/bin/sudo /bin/cat /var/lib/otel-envelope/notify.log | grep -c FAILED
for k in StandardOutPath StandardErrorPath; do
  p=$(/usr/bin/plutil -extract "$k" raw /Library/LaunchDaemons/org.nixos.otel-envelope.plist 2>/dev/null) || continue
  printf '%s FAIL lines: ' "$p"; /usr/bin/sudo grep -c 'FAIL' "$p"
done
} 2>&1 | tee "$L"
logs/s5-evidence/6.1-replay.sh 'time() - node_textfile_mtime_seconds{host_name="stibnite"} > 120' "$s" | tee -a "$L"
logs/s5-evidence/6.1-replay.sh 'count by (host_name) (system_memory_usage_bytes{host_name="stibnite"})' "$s" | tee -a "$L"
logs/s5-evidence/gsql.sh fleet "SELECT count(DISTINCT launchd_label) FROM launchd_job_state WHERE host_name = 'stibnite' AND greptime_timestamp >= to_timestamp_seconds($s) AND greptime_timestamp < to_timestamp_seconds($e)" | tee -a "$L"
logs/s5-evidence/gsql.sh fleet "SELECT count(DISTINCT process_executable_name) FROM process_memory_usage_bytes WHERE host_name = 'stibnite' AND greptime_timestamp >= to_timestamp_seconds($s) AND greptime_timestamp < to_timestamp_seconds($e)" | tee -a "$L"
awk -v s="$s" -v e="$e" '$1 >= s && $1 < e { if ($2 != "NA" && $2 > a) a = $2; if ($3 != "NA" && $3 > p) p = $3; n++ } END { printf "samples %d otelcol max %d KiB otelcol-process max %d KiB\n", n, a, p }' logs/s5-evidence/rss.tsv | tee -a "$L"
```

Expected: `0` `FAILED` lines in `notify.log` and `0` `FAIL` lines in the envelope's output over the window (a later step's controlled failure is outside it); every run of the stale-textfile replay lies inside a gap of the memory replay, that is the probe ran within each awake minute (a run while stibnite reports memory is a finding); at most 30 `launchd_label` values and at most 30 `process_executable_name` values; both collectors' resident memory maxima recorded against C5's 262,144 KiB and 131,072 KiB, which completes AC3's root-collector measurement.

- [ ] **Step 2: The envelope's own control (tasks.md 8.2) [operator]**

After the recorded yes, in `$REPO` (rehearse: echoed):

```bash
logs/s5-evidence/mark.sh OTELCOL_STOP_EPOCH
/usr/bin/sudo /bin/launchctl bootout system/org.nixos.otelcol; echo "rc=$?"
```

Two envelope periods later, 12 min after the stop (the second failing run, C1's two-run rule, lands within 10 min):

```bash
/usr/bin/sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/org.nixos.otelcol.plist; echo "rc=$?"
logs/s5-evidence/mark.sh OTELCOL_START_EPOCH
```

Ten minutes after the start, rehearse: stibnite and magnetite, read-only:

```bash
. logs/s5-evidence/window.env
L=logs/s5-evidence/8.2-envelope-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
/bin/launchctl print system/org.nixos.otelcol | grep -E '^[[:space:]](state|runs) = ' | tee "$L"
logs/s5-evidence/posts.sh "$OTELCOL_STOP_EPOCH" 2>&1 | tee -a "$L"
```

Expected: `state = running`; from `notify.log`, exactly one `FAILED otel-envelope on stibnite` within 10 min of `OTELCOL_STOP_EPOCH` and one `RESOLVED otel-envelope on stibnite` after `OTELCOL_START_EPOCH`; `grep-rc=1` on magnetite, because with its agent stopped stibnite reports nothing and its instances freeze; the operator records both posts' times from the phone, and that nothing else arrived.

- [ ] **Step 3: AC2, a stopped kept-alive job (tasks.md 8.3) [operator]**

After the recorded yes, and only with no build dispatched to stibnite, rehearse: stibnite, read-only:

```bash
L=logs/s5-evidence/8.3-ac2-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
{ /bin/ps -axo user,command | awk '$1 ~ /^_nixbld/ && $2 !~ /distnoted$/'; echo "builders-listed-above"
  /usr/bin/sudo /usr/sbin/lsof -nP -a -c nix-grpc -iTCP -sTCP:ESTABLISHED; echo "lsof-rc=$?"; } 2>&1 | tee "$L"
```

Expected: no builder line and `lsof-rc=1` (each build account's permanent `distnoted agent` is filtered out); otherwise wait and reread.
Then (rehearse: echoed):

```bash
logs/s5-evidence/mark.sh GRPC_STOP_EPOCH
/usr/bin/sudo /bin/launchctl bootout system/org.nixos.nix-grpc-daemon; echo "rc=$?"
```

After 15 min:

```bash
/usr/bin/sudo /bin/launchctl bootstrap system /Library/LaunchDaemons/org.nixos.nix-grpc-daemon.plist; echo "rc=$?"
logs/s5-evidence/mark.sh GRPC_START_EPOCH
```

Fifteen minutes after the start, rehearse: stibnite and magnetite, read-only:

```bash
. logs/s5-evidence/window.env
logs/s5-evidence/6.1-replay.sh 'launchd_job_state{host_name="stibnite", launchd_label="org.nixos.nix-grpc-daemon", launchd_state="unloaded"} == 1' "$GRPC_STOP_EPOCH" | tee -a "$L"
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o cat --since @$GRPC_STOP_EPOCH | grep -E \"stibnite\"; echo grep-rc=\$?'" | tee -a "$L"
logs/s5-evidence/posts.sh "$GRPC_STOP_EPOCH" 2>&1 | tee -a "$L"
```

Expected: one run of `unloaded` from about `GRPC_STOP_EPOCH` to `GRPC_START_EPOCH`; exactly one `[FIRING] LaunchdJobNotRunning stibnite` about 10 min after the stop and one `[RESOLVED] LaunchdJobNotRunning stibnite` after the start, and no other line naming stibnite; nothing in `notify.log`; the operator confirms the two posts on the phone with their times.
This is the runtime negative control of `LaunchdJobNotRunning` and of Task 6 Step 5's 30 min without a darwin `RuleSignalMissing`.

- [ ] **Step 4: AC3, a signal-killed job (tasks.md 8.4) [operator]**

After the recorded yes, in `$REPO` (rehearse: echoed, with the `kill` and `kickstart` lines printed, not run):

```bash
L=logs/s5-evidence/8.4-signal-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
pid=$(/bin/launchctl print system/org.nixos.otelcol-process | awk '$1 == "pid" { print $3; exit }'); echo "pid=$pid" | tee "$L"
logs/s5-evidence/mark.sh KILL_EPOCH | tee -a "$L"
/usr/bin/sudo /bin/kill -KILL "$pid"; echo "rc=$?" | tee -a "$L"
sleep 70
/bin/launchctl print system/org.nixos.otelcol-process | grep -E '^[[:space:]](state|runs|pid|last exit code|last exit reason) = ' | tee -a "$L"
/usr/bin/sudo grep -E 'launchd_label="org[.]nixos[.]otelcol-process"' /var/lib/prometheus-node-exporter/textfile/launchd.prom | tee -a "$L"
```

Expected: launchd relaunches the job (`state = running`, `runs` one higher, a new `pid`); `last exit code` reads as launchd reports a `SIGKILL`, and `launchd.prom` holds `launchd_job_last_exit_code{launchd_label="org.nixos.otelcol-process"} -1` if the line is missing or not an integer (A62); the observed `launchctl print` lines are recorded verbatim.
Six minutes after `KILL_EPOCH`, the evaluator's journal shows one `[FIRING] LaunchdJobFailed stibnite` (`ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o cat --since @$KILL_EPOCH | grep -E \"LaunchdJobFailed\"'" | tee -a "$L"`), and the operator confirms it on the phone.
Then:

```bash
logs/s5-evidence/mark.sh KICKSTART_EPOCH | tee -a "$L"
/usr/bin/sudo /bin/launchctl kickstart -k system/org.nixos.otelcol-process; echo "rc=$?" | tee -a "$L"
sleep 70
/bin/launchctl print system/org.nixos.otelcol-process | grep -E '^[[:space:]](state|runs|pid|last exit code|last exit reason) = ' | tee -a "$L"
/usr/bin/sudo grep -E 'launchd_job_last_exit_code\{[^}]*org[.]nixos[.]otelcol-process' /var/lib/prometheus-node-exporter/textfile/launchd.prom | tee -a "$L"
```

Expected: `last exit code = 0` after the `SIGTERM` of `kickstart -k`, the textfile reading 0, and one `[RESOLVED] LaunchdJobFailed stibnite` on the next evaluator run; if the exit code reads otherwise, the observed value is recorded, `LaunchdJobFailed` stays firing until a clean exit, and the ADR-003 item 23 and runbook amendment it calls for is put to the operator (design D12's `[INFERENCE]`).
Ten minutes after the kickstart, `logs/s5-evidence/posts.sh "$KILL_EPOCH" 2>&1 | tee -a "$L"`; expected: the two posts above and nothing else.
This is the runtime negative control of `LaunchdJobFailed`.

- [ ] **Step 5: AC3, a reload fires nothing (tasks.md 8.5) [operator]**

The activation is the next routine change on `main` that changes `org.nixos.otelcol`'s plist, activated with `just activate` in `$DEPLOY` as Task 6 Step 6 activates.
If none is due, the operator may instead approve a scratch activation: in `$SCRATCH` at `origin/main`, a one-line change to the agent configuration's rendered description in `modules/lib/otel-collector-darwin.nix`, activated with `just activate` there, and the revert activated from `$DEPLOY` within the step; this is the one activation outside `$DEPLOY` this plan allows, and the approval is recorded in the presence log.
Before the activation, rehearse: stibnite, read-only:

```bash
L=logs/s5-evidence/8.5-reload-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
/usr/bin/shasum -a 256 /Library/LaunchDaemons/org.nixos.otelcol.plist | tee "$L"
/bin/launchctl print system/org.nixos.otelcol | grep -E '^[[:space:]](runs|pid) = ' | tee -a "$L"
```

Then `"$REPO/logs/s5-evidence/recent-activation.sh"`, which must print `no activation since` or have its `STOP` resolved with the operator (Task 4 Step 1), and `"$REPO/logs/s5-evidence/mark.sh" RELOAD_EPOCH` immediately before `just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log`.
Fifteen minutes after `RELOAD_EPOCH`, in `$REPO`:

```bash
. logs/s5-evidence/window.env
/usr/bin/shasum -a 256 /Library/LaunchDaemons/org.nixos.otelcol.plist | tee -a "$L"
/bin/launchctl print system/org.nixos.otelcol | grep -E '^[[:space:]](state|runs|pid|last exit code) = ' | tee -a "$L"
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o cat --since @$RELOAD_EPOCH | grep -E \"Launchd(JobFailed|JobNotRunning) stibnite\"; echo grep-rc=\$?'" | tee -a "$L"
logs/s5-evidence/posts.sh "$RELOAD_EPOCH" 2>&1 | tee -a "$L"
```

Expected: a different plist hash (the activation did reload the job) and a new `pid`, `state = running`, `last exit code` 0 or never exited; `grep-rc=1`; each post since `RELOAD_EPOCH` given its cause.

- [ ] **Step 6: AC4, the suspend gate (tasks.md 8.6) [operator]**

Only after at least an hour of uninterrupted collection since the last of Steps 2 to 5 (`count by (host_name) (system_memory_usage_bytes{host_name="stibnite"})` replayed over the last hour shows one run), and on mains power, as O6 states.
Before the lid closes, rehearse: stibnite, read-only:

```bash
L=logs/s5-evidence/8.6-suspend-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
snap() {
  /bin/date -u +%s
  /usr/bin/curl -s http://127.0.0.1:8888/metrics | grep -E '^otelcol_exporter_queue_size'
  for j in otel-envelope otel-host-probe otelcol otelcol-process; do printf '%s ' "$j"; /bin/launchctl print "system/org.nixos.$j" | grep -E '^[[:space:]](state|runs|pid) = ' | tr '\n\t' '  '; echo; done
  /usr/bin/stat -f '%m %N' /var/lib/prometheus-node-exporter/textfile/launchd.prom /var/lib/prometheus-node-exporter/textfile/smartctl.prom
  for j in otelcol otelcol-process; do p=$(/bin/launchctl print "system/org.nixos.$j" | awk '$1 == "pid" { print $3; exit }'); printf '%s rss_kib=%s\n' "$j" "$(/bin/ps -o rss= -p "$p" | tr -d ' ')"; done
}
snap 2>&1 | tee "$L"
```

Then `logs/s5-evidence/mark.sh LID_CLOSE_EPOCH`, and the operator closes the lid for at least 30 min and opens it; on opening, `logs/s5-evidence/mark.sh LID_OPEN_EPOCH`.
Immediately, after 60 s, after 300 s, and then each minute until the queues read 0 (at most 30 min), append `snap 2>&1 | tee -a "$L"`.
Thirty minutes after `LID_OPEN_EPOCH`, rehearse: stibnite and magnetite, read-only:

```bash
. logs/s5-evidence/window.env
# pmset prints local times (-0500 on stibnite) and logs "Delays to Sleep/Wake
# notifications" lines, so the event type is matched in its own column and
# the date is local.
/usr/bin/pmset -g log | awk -v s="$(/bin/date -r "$LID_CLOSE_EPOCH" '+%Y-%m-%d')" '$1 >= s && $4 ~ /^(Sleep|Wake|DarkWake)$/' | tee -a "$L"
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o short-iso --since @$LID_CLOSE_EPOCH --until @$(( LID_OPEN_EPOCH + 1800 )) | grep -E \"stibnite\"; echo grep-rc=\$?'" | tee -a "$L"
logs/s5-evidence/posts.sh "$LID_CLOSE_EPOCH" 2>&1 | tee -a "$L"
```

Expected: `pmset -g log` shows a `Sleep` after `LID_CLOSE_EPOCH` and a `Wake` before `LID_OPEN_EPOCH` plus the window's `DarkWake` entries, counted (A64); each exporter's `otelcol_exporter_queue_size` back to 0; `otel-host-probe`'s `runs` one higher within 60 s of wake and `otel-envelope`'s within 300 s, with no burst of runs, since launchd skipped the intervals missed while asleep (A61); `launchd.prom`'s mtime after `LID_OPEN_EPOCH` within 60 s; both collectors' resident memory recorded beside the pre-sleep values; `grep-rc=1` on magnetite from the lid's closing until 30 min after wake, so no firing, no resolution and no repeat (design D10, FAI `Store errors and silent hosts freeze instance state`); and no post in `posts.sh`'s output naming stibnite.
Then stop the memory sampler (`pkill -f rss-sampler.sh`), whose last use this is.

- [ ] **Step 7: The next natural overnight sleep (tasks.md 8.7)**

On the morning after Step 6, with no operator needed; rehearse: stibnite and magnetite, read-only:

```bash
L=logs/s5-evidence/8.7-overnight-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
/usr/bin/pmset -g log | awk -v s="$(/bin/date -v-1d '+%Y-%m-%d')" '$1 >= s && $4 ~ /^(Sleep|Wake|DarkWake)$/' | tee "$L"
logs/s5-evidence/6.1-replay.sh 'count by (host_name) (system_memory_usage_bytes{host_name="stibnite"})' "$(( $(/bin/date -u +%s) - 86400 ))" | tee -a "$L"
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o short-iso --since -24h | grep -E \"stibnite\"; echo grep-rc=\$?'" | tee -a "$L"
/usr/bin/sudo /bin/cat /var/lib/otel-envelope/notify.log | tail -n 20 | tee -a "$L"
```

Expected: the night's longest sleep from its `Sleep` and `Wake` lines, its `DarkWake` count (A64), and the memory replay's gap matching it, with the dark wakes' brief runs inside it; no evaluator line and no `notify.log` line naming stibnite from the sleep's start until 30 min after its wake, each line outside that window given its cause.

- [ ] **Step 8: The alerter's access from stibnite (tasks.md 8.8)**

rehearse: stibnite, read-only on the server (an anonymous post that the server refuses leaves nothing):

```bash
L=logs/s5-evidence/8.8-ntfy-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
/usr/bin/curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' -d 'anonymous acceptance post from stibnite' https://ntfy.zt/fleet-acceptance 2>&1 | tee "$L"
grep -E 'FAILED otel-envelope on stibnite|RESOLVED otel-envelope on stibnite' logs/s5-evidence/8.2-envelope-*.log | tee -a "$L"
```

Expected: `403` (A66); Step 2's two posts, which the wrapper sent with the token from `NTFY_TOKEN_FILE` and which the operator saw arrive, so the token was accepted while the anonymous post was refused.
