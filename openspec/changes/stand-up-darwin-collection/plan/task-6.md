### Task 6: The darwin rules

Implements `tasks.md` 6.1–6.6 (design D9, Migration Plan step 8; O4, O5; S4-R6's replay rule; FAI `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Each rule's presence selector is watched`, `The evaluator queries each rule's database as the regulators' store account`; FA `Each known failure class on a host reaches a person as an alert`).
This is pull request 3, started at least 24 h after Task 5 Step 2, deployed to magnetite and then activated on stibnite with the operator present.
The stored names are read first and the replay over stibnite's history runs before any rule (Step 1); an empty replay or a stored name that differs from the rules blocks the pull request; the fixture legs take their names and values from that read and fail before the rules exist (Step 2).
`transition.jq` and `model.py` are unchanged here; their pending-time change landed in pull request 1.
The rules' runtime negative controls are Task 8 Steps 3 and 4, which make `LaunchdJobNotRunning` and `LaunchdJobFailed` fire on stibnite.

**Files:**
- Modify: `modules/nixos/fleet-alert/rules.nix` (the four darwin rules, their expected hosts, `smartHosts` with stibnite), `modules/clan/services/otel-collector/schema.nix` (`launchdLabels` gains `org.nixos.otel-envelope`; the kept-alive label set), `modules/checks/fleet-alert.nix` and its fixtures under `modules/checks/fleet-alert/fixtures/` (the eight legs)
- Create (git-ignored): `logs/s5-evidence/6.<n>-*.log`, `logs/s5-evidence/6.1-replay.sh`, `logs/s5-evidence/6.1-names.tsv`

**Interfaces:**
- Consumes: `flake.lib.fleetAlertRules` with `nixosHosts`, `darwinHosts` and `smartHosts` (Task 3); `flake.lib.otelCollectorSchema.launchdLabels` (Task 2); `flake.lib.observabilityHosts`' `notifiedUnits`; `STIBNITE_COLLECT_EPOCH`, `5.3-tables.tsv` and `rss.tsv` (Task 5); `gsql.sh`, `promq.sh`, `mark.sh`, `posts.sh`.
- Produces: the deployed darwin rules, read by Task 8 Steps 3 to 7; `6.1-replay.sh`, reused by Task 8 Step 1 and Task 9 Step 6.

- [ ] **Step 1: Stored names, the replay and the memory maxima (tasks.md 6.1)**

At least 24 h after Task 5 Step 2, read the stored names and labels of the launchd, textfile and SMART series as `regulator`, read-only:

```bash
L=logs/s5-evidence/6.1-replay-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
logs/s5-evidence/gsql.sh fleet "SELECT table_name, column_name, semantic_type FROM information_schema.columns WHERE table_schema = 'fleet' AND (table_name LIKE 'launchd_%' OR table_name LIKE 'node_textfile_%' OR table_name LIKE 'smartctl_%') AND semantic_type = 'TAG' ORDER BY table_name, column_name" | tee logs/s5-evidence/6.1-names.tsv | tee "$L"
logs/s5-evidence/gsql.sh fleet "SELECT launchd_label, launchd_state, count(*) FROM launchd_job_state WHERE host_name = 'stibnite' AND greptime_timestamp > now() - INTERVAL '1 hour' GROUP BY launchd_label, launchd_state ORDER BY launchd_label, launchd_state" | tee -a "$L"
```

Expected: the tables `launchd_job_state`, `launchd_job_last_exit_code`, `launchd_job_runs_total`, `node_textfile_mtime_seconds`, `node_textfile_scrape_error` and A4's eight `smartctl_device_*` names, with tags `launchd_label`, `launchd_state` (values `running`, `not_running`, `unloaded`, `other`), `file` and `device`; each allow-listed label stibnite evaluates, `org.nixos.omnigent-host-<alias>` and no owner's name among them.
A table or label name that differs from design D9's expressions blocks Step 4 until the operator decides whether the probe or the rules change.
Create `logs/s5-evidence/6.1-replay.sh` (git-ignored), which runs one PromQL expression as `regulator` through `query_range` at the evaluator's 60 s step from `STIBNITE_COLLECT_EPOCH` to now, in chunks of at most 10,000 points, and prints one line per contiguous run of points per series:

```bash
#!/usr/bin/env bash
# 6.1-replay.sh EXPR [START]: replays EXPR at a 60 s step; prints "<host> <label> <first ts> <last ts> <max value> <minutes>" per run.
set -euo pipefail
d=$(cd "$(dirname "$0")" && pwd)
. "$d/window.env"
expr=$1 start=${2:-$STIBNITE_COLLECT_EPOCH} end=$(/bin/date -u +%s)
pw_path=${GSQL_PW_PATH:-$(nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path)}
for ((s = start; s < end; s += 600000)); do
  e=$(( s + 599940 < end ? s + 599940 : end ))
  ssh magnetite.zt "bash -s -- $(printf '%q ' "$expr" "$s" "$e" "$pw_path")" < /dev/null <<'EOS'
set -euo pipefail
expr=$1 s=$2 e=$3 pw_path=$4
pw=$(sudo cat "$pw_path")
printf 'user = "regulator:%s"\n' "$pw" | curl -sS --fail-with-body --config - -G -H 'x-greptime-db-name: fleet' \
  --data-urlencode "query=$expr" --data-urlencode "start=$s" --data-urlencode "end=$e" --data-urlencode step=60 \
  http://127.0.0.1:4000/v1/prometheus/api/v1/query_range |
  jq -r '.data.result[]? | [(.metric.host_name // ""), (.metric.launchd_label // .metric.mountpoint // .metric.device // .metric.file // "")] as $k | .values[]? | ($k + [(.[0] | floor | tostring), .[1]]) | @tsv'
EOS
done | LC_ALL=C sort -t "$(printf '\t')" -k1,1 -k2,2 -k3,3n |
  awk -F '\t' -v OFS='\t' '{ k = $1 FS $2
    if (k != pk || $3 - pt > 60) { if (pk != "") print pk, first, pt, mx, (pt - first) / 60 + 1; first = $3; mx = $4 }
    if ($4 + 0 > mx + 0) mx = $4; pk = k; pt = $3 }
    END { if (pk != "") print pk, first, pt, mx, (pt - first) / 60 + 1 }'
```

The run splitting is controlled first: replaying `count by (host_name) (system_memory_usage_bytes{host_name="stibnite"}) unless on () (minute() >= 30)` must print runs of at most 30 min, none crossing a half hour; a longer run means the splitting is wrong and the script is fixed before any rule is replayed (negative control).
Replay, each restricted to stibnite, with `kept` the kept-alive allow-listed labels read from stibnite's evaluation (`nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons --apply 'ds: builtins.filter (n: (ds.${n}.serviceConfig.KeepAlive or null) == true) (builtins.attrNames ds)'`, intersected with `launchdLabels` and prefixed `org.nixos.`):

```bash
r=logs/s5-evidence/6.1-replay.sh
kept='org[.]nixos[.](dnscrypt-proxy|nix-daemon|nix-grpc-daemon|otelcol|otelcol-process|prometheus-node-exporter)'
fs='sum by (host_name, mountpoint) (system_filesystem_usage_bytes{host_name="stibnite", state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes{host_name="stibnite"})'
{
echo "## LaunchdJobNotRunning (10 min)"; $r "launchd_job_state{host_name=\"stibnite\", launchd_state=\"running\", launchd_label=~\"$kept\"} == 0 or launchd_job_state{host_name=\"stibnite\", launchd_state=\"unloaded\"} == 1"
echo "## LaunchdJobFailed (5 min)"; $r 'launchd_job_last_exit_code{host_name="stibnite", launchd_label!~"org[.]nixos[.]otel-envelope"} != 0'
echo "## LaunchdJobRestartLoop (0)"; $r 'increase(launchd_job_runs_total{host_name="stibnite"}[15m]) > 5'
echo "## HostProbeStale (10 min)"; $r 'time() - node_textfile_mtime_seconds{host_name="stibnite"} > 300 or node_textfile_scrape_error{host_name="stibnite"} == 1'
echo "## NvmeCriticalWarning (0)"; $r 'smartctl_device_critical_warning_total{host_name="stibnite"} != 0'
echo "## NvmeWearHigh (1 h)"; $r 'smartctl_device_percentage_used_total{host_name="stibnite"} > 90'
echo "## FilesystemFillingWarn (15 min)"; $r "$fs > 0.85"
echo "## FilesystemFull (5 min)"; $r "$fs > 0.95"
for m in launchd_job_state launchd_job_last_exit_code launchd_job_runs_total node_textfile_mtime_seconds smartctl_device_critical_warning_total smartctl_device_percentage_used_total system_filesystem_usage_bytes 'up{job="node"'; do
  sel="$m"; case "$m" in *'{'*) sel="${m}, host_name=\"stibnite\"}";; *) sel="${m}{host_name=\"stibnite\"}";; esac
  echo "## present: $sel"; $r "count by (host_name) ($sel)"
  echo "## absent while stibnite reports memory (30 min): $sel"; $r "count by (host_name) (system_memory_usage_bytes{host_name=\"stibnite\"}) unless on (host_name) count by (host_name) ($sel)"
done
} 2>&1 | tee -a "$L"
```

Expected: for each of the first eight, the runs lasting at least the rule's `for` are its would-be firings; for each selector, its `present` replay prints runs (an empty one blocks Step 4, because a replay of an absent name proves nothing), and an `absent` run of 30 min or more is a would-be `RuleSignalMissing` naming that selector's rules.
A run that ends within 5 min after a gap in stibnite's memory series is the store's 300 s lookback over a sleep, which design D10's pending-time rule keeps from firing, and is attributed to the sleep by the gap's times and `pmset -g log`'s `Sleep` line, not counted as a would-be firing.
Each would-be firing is attributed in the log to its cause (a crash, an activation, a sleep, the probe's own interval); a rule whose would-be firings share one known cause is put to the operator, whose decision is recorded under `## Decision` before Step 4.
Then both collectors' resident memory over the 24 h, and C5's limits:

```bash
awk -v t="$(( $(/bin/date -u +%s) - 86400 ))" '$1 >= t { if ($2 != "NA" && $2 > a) a = $2; if ($3 != "NA" && $3 > p) p = $3; n++ } END { printf "samples %d otelcol max %d KiB otelcol-process max %d KiB\n", n, a, p }' logs/s5-evidence/rss.tsv | tee -a "$L"
```

Expected: the two maxima against C5's 262,144 KiB and 131,072 KiB; the operator confirms the limits or sets new ones, recorded under `## Decision` (O5); a change is made in pull request 3's `darwinMemory.limits` with the matching `otel-envelope` cases.

- [ ] **Step 2: The fixture legs, seen failing (tasks.md 6.2)**

Record the evaluation cost of `fleet-alert` before the step:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/fleet-alert-stats.json | tee logs/s5-evidence/6.2-cost-before-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Add to `modules/checks/fleet-alert.nix`, built with the existing `gap` and `minute` helpers and the real `rules` rendered from `flake.lib.observabilityHosts`, with every series name and label copied from Step 1's `6.1-names.tsv` and its label read, and the label sets added to `fixtures/series.json`; the two independently defined values each leg relates are the rendered rule set and the fixture's replayed store answers.
The fixture cannot replay metric values: `stepAnswers` answers each rule's whole expression with label sets of value `"1"` on the steps whose `series.<Alert>` lists them, and answers presence from `reporting`, `silent` and `missing` (`modules/checks/fleet-alert.nix:842-888`); so each leg states its condition as the steps on which the expression is answered, each leg's `name` starts with its identifier, and the column below names those steps:

| Leg | Replayed answers | Expected posts |
|---|---|---|
| `darwinSignalMissing` | stibnite reports memory each step and `launchd_job_state` is in `missing` for 30 min, the other launchd selectors present | one `[FIRING] RuleSignalMissing` naming `LaunchdJobNotRunning`, nothing else |
| `keptAliveStopped` | `series.LaunchdJobNotRunning` holds `{host_name="stibnite", launchd_label="org.nixos.nix-grpc-daemon", launchd_state="running"}` for 15 min, then nothing | one `[FIRING] LaunchdJobNotRunning stibnite` after 10 min, one `[RESOLVED]` |
| `envelopeUnloaded` | `series.LaunchdJobNotRunning` holds `{host_name="stibnite", launchd_label="org.nixos.otel-envelope", launchd_state="unloaded"}` for 15 min, then nothing | one `[FIRING] LaunchdJobNotRunning stibnite` after 10 min, one `[RESOLVED]` |
| `envelopeFailedNotReported` | the store's answer to `LaunchdJobFailed`'s expression with the exclusion removed, `{host_name="stibnite", launchd_label="org.nixos.otel-envelope"}`, filtered by the rendered exclusion as `exclusionLeg` filters `SystemdUnitFailed`'s (`modules/checks/fleet-alert.nix:954-963`), for 15 min | nothing, the wrapper having posted its own notice |
| `harmoniaFailedReported` | `series.LaunchdJobFailed` holds `{host_name="stibnite", launchd_label="org.nixos.harmonia-gc"}` for 15 min | one `[FIRING] LaunchdJobFailed stibnite` after 5 min, nothing more |
| `restartLoop` | `series.LaunchdJobRestartLoop` holds `{host_name="stibnite", launchd_label="org.nixos.nix-grpc-daemon"}` on the runs where the 15 min increase exceeds 5, then nothing | one `[FIRING] LaunchdJobRestartLoop stibnite` on the first such run, one `[RESOLVED]` 5 min after the last |
| `probeStale` | stibnite reports memory each run while `series.HostProbeStale` holds `{host_name="stibnite", file="<launchd.prom's path>"}` for 20 min | one `[FIRING] HostProbeStale stibnite` 10 min after the first such run |
| `nvmeExpectsStibnite` | stibnite reports memory with both `smartctl_device_*` selectors in `missing` for 30 min, pyrite silent | one `[FIRING] RuleSignalMissing` naming `NvmeCriticalWarning` and one naming `NvmeWearHigh` |
| `stibniteSilent` | `series.LaunchdJobFailed` holds `{host_name="stibnite", launchd_label="org.nixos.harmonia-gc"}` until it fires, then stibnite is in `silent` for 40 min while the expression still answers that label set | after the `[FIRING]`, nothing: no silence, no resolution, no repeat; the darwin counterpart of `laptopSilentLeg`, which covers pyrite and electrum only |

Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s5-evidence/6.2-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E 'FAIL|Leg'
```

Expected: FAIL at the first new leg, because no darwin rule exists and the NVMe rules do not expect stibnite; `envelopeFailedNotReported` alone passes before the rules, and is seen failing in Step 3; `stibniteSilent` fails because `LaunchdJobFailed` does not exist (RED).

- [ ] **Step 3: The four darwin rules (tasks.md 6.3)**

In `modules/clan/services/otel-collector/schema.nix`, `launchdLabels` gains `org.nixos.otel-envelope` (A4:121, amended), and the kept-alive set is the list `launchdKeptAlive` beside it, holding the allow-listed labels whose evaluated `KeepAlive` is `true` (A4:123); the darwin fragment asserts that list equals the labels of its evaluated `launchd.daemons` with `serviceConfig.KeepAlive == true` intersected with `launchdLabels`, the two sources being the schema and stibnite's evaluation, shown failing by an `extendModules` override of stibnite setting `launchd.daemons.otel-host-probe.serviceConfig.KeepAlive = true` (negative control).
A job whose `KeepAlive` is a condition set is outside the kept-alive set and is not widened into it: `org.nixos.omnigent-host-cameron` evaluates `KeepAlive = { SuccessfulExit = false; }`, so launchd restarts it only after a failing exit, and it may exit 0 and stay down legitimately, which `LaunchdJobNotRunning` must not report; a non-zero exit of it is still `LaunchdJobFailed`'s (design D9).
In `modules/nixos/fleet-alert/rules.nix`, add after the NVMe rules, with `keptAlive` that list joined into an alternation with each `.` written `[.]` (ADR-009's note on GreptimeDB 1.2.1) and `selfNotified` the darwin rows' `notifiedUnits` as `org[.]nixos[.]<unit>`:

```nix
{ alert = "LaunchdJobNotRunning"; for = "10m"; severity = "warning";
  expr = ''launchd_job_state{launchd_state="running", launchd_label=~"${keptAlive}"} == 0 or launchd_job_state{launchd_state="unloaded"} == 1'';
  annotations.summary = "A kept-alive launchd job is not running, or an allow-listed job is not loaded"; presence = [ (presence darwinHosts "launchd_job_state") ]; }
{ alert = "LaunchdJobFailed"; for = "5m"; severity = "warning";
  expr = ''launchd_job_last_exit_code{launchd_label!~"${selfNotified}"} != 0'';
  annotations.summary = "A launchd job's last exit was not clean"; presence = [ (presence darwinHosts "launchd_job_last_exit_code") ]; }
{ alert = "LaunchdJobRestartLoop"; for = "0s"; severity = "warning";
  expr = "increase(launchd_job_runs_total[15m]) > 5";
  annotations.summary = "A launchd job relaunched more than five times in 15 minutes"; presence = [ (presence darwinHosts "launchd_job_runs_total") ]; }
{ alert = "HostProbeStale"; for = "10m"; severity = "warning";
  expr = "time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1";
  annotations.summary = "A darwin host's probe has stopped writing its textfile"; presence = [ (presence darwinHosts "node_textfile_mtime_seconds") ]; }
```

and `smartHosts` takes every collecting row with `smartDevices`, stibnite included, for `NvmeCriticalWarning` and `NvmeWearHigh`.
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/6.3-rules-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee "$L" | grep -E 'SUCCESS|FAIL|mutant|Leg'
nix eval --json .#.checks.x86_64-linux.fleet-alert.rules.rules --apply 'r: map (x: { inherit (x) alert; hosts = map (p: p.expectedHosts) (x.presence or [ ]); expr = x.expr or null; }) r' | jq -c '.[] | select(.alert | test("^(Launchd|HostProbe|Nvme)"))' | tee -a "$L"
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/fleet-alert-stats.json | tee -a "$L"
```

Expected: promtool's `SUCCESS` with four more rules than at `tasks.md` 1.2; every leg passes, the nine new ones included; to see `envelopeFailedNotReported` fail, the rule is first built without the `selfNotified` exclusion (`6.3-red-noexclusion-<ts>.log`), then with it; `launchdKeptAlive` is `[ "org.nixos.dnscrypt-proxy" "org.nixos.nix-daemon" "org.nixos.nix-grpc-daemon" "org.nixos.otelcol" "org.nixos.otelcol-process" "org.nixos.prometheus-node-exporter" ]`, without `org.nixos.omnigent-host-cameron`; the four darwin rules expect `["stibnite"]` and the NVMe rules `["pyrite","stibnite"]` (evaluation); the cost below 536,870,912 and within design D13's figure.

- [ ] **Step 4: The pull request (tasks.md 6.4)**

Only after Step 1's `## Decision` is complete: run `nix fmt` and `nix fmt -- --fail-on-change`, keeping the log; commit with a plain message, for example "Alert on stopped, failing and looping launchd jobs and a stale probe on stibnite"; open pull request 3 with the same kind of title, its body describing the rules and stating in words the replay's would-be firings, their causes and the operator's decision, and the C5 limits as confirmed (no log path), with no slice, decision or task code.
Expected: nixbot green, including `fleet-alert` and `nixos-magnetite`.

- [ ] **Step 5: Deploy magnetite (tasks.md 6.5)**

In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty`:

```bash
"$REPO/logs/s5-evidence/mark.sh" MAGNETITE_DEPLOY_EPOCH
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
ssh magnetite.zt 'bash -c "systemctl is-active fleet-alert.timer opentelemetry-collector"'
```

Expected: the log ends without error; `active` twice.
The delivered rules are compared with the evaluated ones by Task 5 Step 4's block, run again into this step's log, now expecting the four darwin rules with `["stibnite"]`.
The evaluator's first run and its query count, rehearse: magnetite, read-only:

```bash
L=logs/s5-evidence/6.5-rules-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -c "systemctl show fleet-alert -p ExecMainStatus -p ExecMainStartTimestamp -p ExecMainExitTimestamp"' | tee "$L"
ssh magnetite.zt 'bash -s' <<'EOS' \
  | jq '([.[] | select(.alert == "RuleSignalMissing") | {selector: "system_memory_usage_bytes", database}] + [.[] | .database as $database | .presence[]? | {selector, database: $database}] | unique | length) as $p | [.[] | select(.expr and (.window // null) == null)] as $e | {presence: $p, promql: ([$e[] | select(.language == "promql")] | length), sql: ([$e[] | select(.language == "sql")] | length), total: ($p + ($e | length))}' | tee -a "$L"
c=$(systemctl show fleet-alert -p Environment --value | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
jq -c '.rules' "$c"
EOS
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee -a "$L"
c=$(systemctl show fleet-alert -p Environment --value | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
jq -c '{regulatorAt: [paths(scalars) as $p | select(getpath($p) == "regulator") | $p | map(tostring) | join(".")], databases: ([.rules[]?.database // empty] | unique)}' "$c"
for s in /var/lib/private/fleet-alert/state.json /var/lib/fleet-alert/state.json; do sudo test -e "$s" && sudo jq -c '.instances // {} | keys' "$s"; done
EOS
```

The count is the evaluator's own per-run query set, computed from the delivered rule JSON as S4's `tasks.md` 6.6 computed it: each unique presence selector and database, `system_memory_usage_bytes` in `RuleSignalMissing`'s database included, plus each expression outside the weekly window.
Expected: `ExecMainStatus=0`; a total recorded beside the expected 31 `[INFERENCE: S4's 23, plus the four darwin presence selectors and the four darwin expressions]`, a different figure recorded with the rules that make it up; `regulator` as the store account at the configuration's user path, and the databases `devloop` and `fleet`; no `StoreQueryFailing` instance among the state's keys, which a failed query on either database would raise; the run's duration recorded beside S4's for 23 queries (delivered file, runtime).
Thirty minutes after the deploy, rehearse: magnetite, read-only, appending to the same `$L`:

```bash
. logs/s5-evidence/window.env
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o cat --since @$MAGNETITE_DEPLOY_EPOCH | grep -E \"RuleSignalMissing\"; echo grep-rc=\$?'" | tee -a "$L"
logs/s5-evidence/posts.sh "$MAGNETITE_DEPLOY_EPOCH" 2>&1 | tee -a "$L"
```

Expected: no `RuleSignalMissing` line naming `LaunchdJobNotRunning`, `LaunchdJobFailed`, `LaunchdJobRestartLoop`, `HostProbeStale` or an NVMe rule; each post since the deploy given its cause under `## Causes`.
stibnite's probe does not yet read `org.nixos.otel-envelope`, so `envelopeUnloaded`'s case cannot occur until Step 6.

- [ ] **Step 6: stibnite's activation of pull request 3 (tasks.md 6.6) [operator]**

The orchestrator asks "Are you at stibnite now, and may I activate pull request 3 on it?" and records the answer with `/bin/date -u` in `logs/s5-evidence/6.6-presence-<ts>.log`; without a recorded yes this step does not run.
In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`, and after `recent-activation.sh` prints `no activation since` or its `STOP` is resolved with the operator (Task 4 Step 1):

```bash
"$REPO/logs/s5-evidence/recent-activation.sh"
"$REPO/logs/s5-evidence/mark.sh" STIBNITE_ACTIVATE_EPOCH
just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
rehearse: stibnite and magnetite, read-only, in `$REPO`:

```bash
. logs/s5-evidence/window.env
L=logs/s5-evidence/6.6-stibnite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
sleep 60
/usr/bin/sudo /usr/bin/grep -E 'launchd_label="org[.]nixos[.]otel-envelope"' /var/lib/prometheus-node-exporter/textfile/launchd.prom | tee "$L"
/usr/bin/stat -f '%m %N' /var/lib/prometheus-node-exporter/textfile/launchd.prom | tee -a "$L"
sleep 120
logs/s5-evidence/promq.sh 'launchd_job_state{host_name="stibnite", launchd_label="org.nixos.otel-envelope"}' | tee -a "$L"
logs/s5-evidence/posts.sh "$STIBNITE_ACTIVATE_EPOCH" 2>&1 | tee -a "$L"
```

Expected: `launchd.prom` holds `org.nixos.otel-envelope`'s state lines within 60 s of the activation, with an mtime after `STIBNITE_ACTIVATE_EPOCH`; the store holds them for stibnite; each post since the activation given its cause under `## Causes`, and no `LaunchdJobNotRunning` or `LaunchdJobFailed` naming stibnite, since the activation reloads only what changed (delivered file, runtime).
