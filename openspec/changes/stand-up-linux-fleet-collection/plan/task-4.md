### Task 4: Deploying to cinnabar and magnetite

Implements `tasks.md` 4.1–4.6 (design D5, D13, Migration Plan steps 2 and 3; FII `Each agent exports by its role`, `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`; TSI `Listeners are bound to loopback only`; HMC `Each agent host contributes its own signals to the telemetry store`; DCI `Each agent host's collector ships its own deploy records`; DC `Every dev-loop event is recorded once and kept for a year`, `A gap in the dev-loop history reaches a person within a day`).
It starts only after pull request 1 has merged; pull request 1 leaves cinnabar with `collect = false`, so cinnabar runs exactly what it ran before until Step 2's own pull request turns its collection on; it deploys cinnabar, then magnetite, and nothing else; pyrite is Task 5's.
cinnabar's switch stops and starts `zerotierone` and reruns the ZeroTier controller's hooks, so cinnabar is deployed over its public address and the controller's state is compared before and after (GR §3; design D13); during the restart the `.zt` resolver on cinnabar and every session over ZeroTier pause.
Each verification block below marked `rehearse:` was run once in Task 1 Step 3.

**Files:**
- Create (git-ignored): `logs/cinnabar-<ts>.log`, `logs/magnetite-<ts>.log` (the deploy logs), `logs/s4-evidence/4.<n>-*.log`, `logs/s4-evidence/window.env`

**Interfaces:**
- Consumes: pull request 1 merged into `main@origin`; `$DEPLOY` (plan Global Constraints); `logs/s4-evidence/gsql.sh` and `promq.sh` (Task 1 Step 2).
- Produces: `window.env` keys `CINNABAR_DEPLOY_EPOCH` and `MAGNETITE_RECEIVER_EPOCH`; cinnabar's measured queue rate; the deploy-record counts Task 9 and Task 10 cite.

- [ ] **Step 1: Before cinnabar's deploy (tasks.md 4.1)**

Refresh the deploy worktree; evidence paths below are relative to `$REPO`, and only the `clan machines update` lines run with `$DEPLOY` as the working directory:

```bash
git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main && git -C $DEPLOY log -1 --format='%H %s'
```

Expected: `$DEPLOY` is at `origin/main`, which contains pull request 1's merge.
rehearse: cinnabar and magnetite, read-only:

```bash
L=logs/s4-evidence/4.1-pre-cinnabar-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh root@49.13.68.78 'bash -s' <<'EOS' 2>&1 | tee "$L"
set -uo pipefail
zerotier-cli info
zerotier-cli listnetworks
find /var/lib/zerotier-one/controller.d/network -type f -print0 | sort -z | xargs -0 sha256sum
wc -l < /var/log/deploy-record.jsonl
readlink -f /run/current-system
EOS
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee -a "$L"
wc -l < /var/log/deploy-record.jsonl
readlink -f /run/current-system
EOS
```

Expected: `200 info <id> <version> ONLINE`, the network list, one hash line per controller file, two line counts and two closures.

- [ ] **Step 2: Turn on cinnabar's collection and deploy it over its public address (tasks.md 4.2)**

After Step 1, in a change off `main@origin`, change `collect = false;` to `collect = true;` in cinnabar's one line of `modules/lib/observability-hosts.nix` (`cinnabar = agent [ "fleet-deadman" ] // { collect = false; alwaysOn = true; };`), run `nix fmt`, and confirm in `$REPO`:

```bash
jj st --no-pager >/dev/null
nix eval --json .#nixosConfigurations.cinnabar.config.services.observability-notify.units
nix eval --raw .#nixosConfigurations.cinnabar.config.system.build.toplevel.drvPath
```

Expected: `["opentelemetry-collector","otel-envelope","fleet-deadman"]` in the table's order, each unit once, and a drvPath.
Commit it alone with a plain message, for example "Start collecting cinnabar's host metrics", open its pull request with the same title and a body saying it turns on the collector agent for cinnabar ahead of a watched deploy, and let it merge through the queue; enqueue it only when Steps 2 to 3 can follow at once.
Then refresh `$DEPLOY` (`git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`) and, in `$DEPLOY` (`window.env` is `$REPO/logs/s4-evidence/window.env`):

```bash
nixbot-logs queue
```

Expected: `Queue is empty`; otherwise wait and rerun.
Then:

```bash
echo "CINNABAR_DEPLOY_EPOCH=$(/bin/date -u +%s)" >> "$REPO/logs/s4-evidence/window.env"
clan machines update cinnabar --target-host root@49.13.68.78 2>&1 | tee logs/cinnabar-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error; it lists `zerotierone.service` among the restarted units.
rehearse: cinnabar:

```bash
ssh root@49.13.68.78 'bash -c "systemctl is-active opentelemetry-collector otel-envelope.timer prometheus-node-exporter zerotierone"'
```

Expected: `active` four times.

- [ ] **Step 3: cinnabar's first-deploy capture (tasks.md 4.3)**

rehearse: cinnabar:

```bash
L=logs/s4-evidence/4.3-cinnabar-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh root@49.13.68.78 'bash -s' <<'EOS' 2>&1 | tee "$L"
set -uo pipefail
zerotier-cli info
zerotier-cli listnetworks
find /var/lib/zerotier-one/controller.d/network -type f -print0 | sort -z | xargs -0 sha256sum
ping -6 -c 3 fddb:4344:343b:14b9:399:930f:39db:40d2; echo "rc=$?"
EOS
diff <(grep -A100 'listnetworks' logs/s4-evidence/4.1-pre-cinnabar-*.log | grep -E '^200 listnetworks|^[0-9a-f]{64} ') \
     <(grep -E '^200 listnetworks|^[0-9a-f]{64} ' "$L") && echo zerotier-unchanged
```

Expected: `ONLINE`, `rc=0`, `zerotier-unchanged`.
A difference in the network list or a controller file stops the sequence: magnetite is not deployed, and the operator decides between rollback of cinnabar over `root@49.13.68.78` (design Migration Plan) and repair.
Then read cinnabar's metrics queue every 10 min until Step 4, appending to `$L`:

```bash
ssh root@49.13.68.78 'bash -c "curl -s http://127.0.0.1:8888/metrics | grep -E \"^otelcol_exporter_queue_size\\{.*otlp_http/ingress\\\"\""' | sed "s/^/$(/bin/date -u +%s) /" | tee -a "$L"
```

Expected: the size grows while magnetite has no receiver, and cinnabar's own `otel-envelope` keeps passing, because its exporter's `send_failed` does not increase while it retries (`sudo journalctl -u otel-envelope -o cat -n 20` on cinnabar shows no `FAIL`).

- [ ] **Step 4: Deploy magnetite (tasks.md 4.4)**

In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty`:

```bash
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
ssh magnetite.zt 'bash -c "systemctl show opentelemetry-collector -p ActiveEnterTimestampMonotonic --value; cat /proc/uptime"'
```

Record `MAGNETITE_RECEIVER_EPOCH` in `window.env` as the collector's active-enter time converted with `/proc/stat`'s `btime` (`btime + ActiveEnterTimestampMonotonic / 1e6`).
Expected: the log ends without error; magnetite's `zerotierone` is not restarted (its `enableMetrics` is unchanged).
rehearse: magnetite:

```bash
ssh magnetite.zt 'bash -c "systemctl is-active opentelemetry-collector otel-envelope.timer"'
```

Expected: `active` twice.

- [ ] **Step 5: magnetite's first-deploy capture (tasks.md 4.5)**

rehearse: magnetite:

```bash
L=logs/s4-evidence/4.5-magnetite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -c "sudo ss -tlnHp"' | tee "$L" | awk '$4 !~ /^(127\.|\[::1\])/' | tee -a "$L"
```

Expected: the filtered lines hold `[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318` owned by `otelcol-contrib` and no other line owned by `otelcol-contrib` or `greptime`; listeners of other services (ssh, nginx, caddy) are outside this check.
Queue drain and rate, from cinnabar and Step 3's record:

```bash
. logs/s4-evidence/window.env
q=$(awk -v t="$MAGNETITE_RECEIVER_EPOCH" '$1 <= t { last = $NF } END { print last }' logs/s4-evidence/4.3-cinnabar-*.log)
echo "cinnabar queue at receiver start: $q bytes over $(( (MAGNETITE_RECEIVER_EPOCH - CINNABAR_DEPLOY_EPOCH) / 60 )) min" | tee -a "$L"
awk -v q="$q" -v m="$(( (MAGNETITE_RECEIVER_EPOCH - CINNABAR_DEPLOY_EPOCH) / 60 ))" 'BEGIN { printf "rate %.0f bytes/min against 256000\n", q / m }' | tee -a "$L"
ssh root@49.13.68.78 'bash -c "curl -s http://127.0.0.1:8888/metrics | grep -E \"^otelcol_exporter_queue_size\""' | tee -a "$L"
logs/s4-evidence/promq.sh 'count by (host_name) (system_memory_usage_bytes)' | tee -a "$L"
```

Expected: a rate recorded (a rate above 256,000 bytes a minute is a finding against design D2's queue sizing); the queue sizes 0 within 30 min; two rows, `magnetite` and `cinnabar`.
If a routine deploy of magnetite from `main` brought the receiver before cinnabar's deploy, cinnabar never queues, and the rate is recorded as not measured, with the reason and the time magnetite's receiver came up (design D13); a later store outage gives the measurement instead.
The refusal from stibnite (AC2), run on stibnite:

```bash
curl -sS --max-time 10 -o /dev/null -w '%{http_code}\n' -k -X POST -H 'Content-Type: application/x-protobuf' \
  'https://[fddb:4344:343b:14b9:399:930f:39db:40d2]:4318/v1/metrics'; echo "rc=$?"
```

Expected: `000` and `rc=55` with `certificate required`, or `rc=35`; the operator records the error line (FII scenario `A mesh member without a certificate connects at deploy`).
Each host's first `otel-envelope` run:

```bash
for h in magnetite.zt root@49.13.68.78; do ssh "$h" 'bash -c "sudo journalctl -u otel-envelope -o cat -n 20 | grep -E \"^otel-envelope: \""'; done | tee -a "$L"
```

Expected: every clause line `ok` on both hosts (a first run records the baseline for C4).
An hour after cinnabar's series first appear, record every post naming cinnabar from the evaluator's journal, with its cause, because cinnabar now feeds the existing unit, restart, memory and exporter rules that no replay covered (review finding on new hosts):

```bash
ssh magnetite.zt 'bash -c "sudo journalctl -u fleet-alert -o cat --since \"-70min\" | grep -E \"cinnabar\" || true"' | tee -a "$L"
```

Expected: no post, or each post attributed to its cause in the log; a post with no benign cause is a finding.

- [ ] **Step 6: Deploy records after the receiver moved (tasks.md 4.6)**

rehearse: magnetite and cinnabar:

```bash
L=logs/s4-evidence/4.6-deploy-records-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for h in magnetite cinnabar; do
  t=$([ $h = cinnabar ] && echo root@49.13.68.78 || echo magnetite.zt)
  lines=$(ssh "$t" 'bash -c "wc -l < /var/log/deploy-record.jsonl"')
  rows=$(logs/s4-evidence/gsql.sh devloop "SELECT count(*) FROM deploy_record WHERE host = '$h'")
  echo "$h lines=$lines rows=$rows"
done | tee "$L"
ssh magnetite.zt 'bash -c "sudo journalctl -u devloop-reconcile -o cat --since today | grep -E \"^devloop-reconcile: C\""' | tee -a "$L"
```

Expected: `lines` equal `rows` for each; magnetite's line count is Step 1's plus one; cinnabar's rows appeared within 5 min of Step 4 (its file was shipped from `start_at: beginning`); the next scheduled `devloop-reconcile` (02:15 UTC) prints every clause `ok`, `C6 deploys` included.
A difference is a finding recorded in `verify.md`, with the missing or extra `ts` values listed from `SELECT ts FROM deploy_record WHERE host = '<h>' ORDER BY ts` against `jq -r '.ts // empty' /var/log/deploy-record.jsonl`.
