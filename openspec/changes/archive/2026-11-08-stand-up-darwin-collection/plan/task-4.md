### Task 4: Deploying pull request 1

Implements `tasks.md` 4.1–4.3 (design D5, D7, D10, Migration Plan steps 2 and 3; FII `One host table declares the agent hosts and what each reports`, `The collection CA issues each agent host one certificate`; TSI `Credentials exist only as activation-resolved files owned by non-worker users`; FAI `The alerter token travels only as a file`).
It starts only after pull request 1 has merged; the vars step (`tasks.md` 2.3) is committed in pull request 1, in the commit that adds the role, so magnetite deploys first, stibnite's routine activation second and cinnabar third.
Pull request 1 leaves stibnite with `collect = false`, so its activation installs the `otel-cert` key and the `ntfy-alerter` token and starts no collector, probe or envelope (design D7).
magnetite deploys because stibnite's row and the evaluator's expected hosts are in its closure; with `collect = false` stibnite is expected by no rule; cinnabar deploys because its `fleet-deadman` shares the changed `transition.jq`.
Each verification block below marked `rehearse:` was run once in Task 1 Step 3, with its paths under `logs/s5-evidence/1.3-rehearsal/`.

**Files:**
- Create (git-ignored): `logs/magnetite-<ts>.log`, `logs/stibnite-<ts>.log`, `logs/cinnabar-<ts>.log` (the deploy and activation logs, in `$DEPLOY`), `logs/s5-evidence/4.<n>-*.log`, `logs/s5-evidence/window.env`, `logs/s5-evidence/mark.sh`, `logs/s5-evidence/posts.sh`, `logs/s5-evidence/recent-activation.sh`, `logs/s5-evidence/notify-lines-<epoch>`

**Interfaces:**
- Consumes: pull request 1 merged into `main@origin`; `$DEPLOY` (plan Global Constraints); `logs/s5-evidence/gsql.sh` and `logs/s5-evidence/promq.sh` (Task 1); the delivered evaluator configuration on magnetite (`FLEET_ALERT_CONFIG` in `fleet-alert.service`'s environment).
- Produces: `window.env` keys `MAGNETITE_DEPLOY_EPOCH`, `STIBNITE_ACTIVATE_EPOCH` and `CINNABAR_DEPLOY_EPOCH`; `mark.sh` and `posts.sh`, which every later deploy, activation and operator step uses to record every post since its start; `recent-activation.sh`, which every stibnite activation runs first.

- [ ] **Step 1: The start and post helpers**

Create `logs/s5-evidence/mark.sh` (git-ignored), which records a start epoch and the line count of stibnite's `notify.log` at that moment, so a later read lists exactly the posts after it whatever the file's line format:

```bash
#!/bin/bash
# mark.sh KEY: appends KEY=<epoch> to window.env and records stibnite's notify.log line count at that epoch.
set -euo pipefail
d=$(cd "$(dirname "$0")" && pwd)
t=$(/bin/date -u +%s)
n=$({ /usr/bin/sudo /bin/cat /var/lib/otel-envelope/notify.log 2>/dev/null || true; } | /usr/bin/wc -l | /usr/bin/tr -d ' ')
echo "$1=$t" >> "$d/window.env"
echo "$n" > "$d/notify-lines-$t"
echo "$1=$t notify-lines=$n"
```

Create `logs/s5-evidence/posts.sh` (git-ignored), which prints every post since a recorded epoch: the evaluator's and the NixOS notifier's journal lines on magnetite, and the lines stibnite's wrapper appended to `notify.log` after the recorded count:

```bash
#!/bin/bash
# posts.sh EPOCH: every post since EPOCH (a value mark.sh wrote) on magnetite and on stibnite.
set -uo pipefail
d=$(cd "$(dirname "$0")" && pwd)
start=$1
skip=$(/bin/cat "$d/notify-lines-$start" 2>/dev/null || echo 0)
echo "== magnetite: fleet-alert and observability-notify@* since @$start"
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -u \"observability-notify@*\" --since @$start -o short-iso --no-pager | grep -E \"FIRING|RESOLVED|FAILED\"; echo grep-rc=\$?'"
echo "== stibnite: /var/lib/otel-envelope/notify.log after line $skip"
if /usr/bin/sudo /bin/test -e /var/lib/otel-envelope/notify.log; then
  /usr/bin/sudo /usr/bin/tail -n "+$((skip + 1))" /var/lib/otel-envelope/notify.log
else
  echo "notify.log absent"
fi
```

Both run under `/bin/bash` on stibnite and are called by absolute path, `"$REPO/logs/s5-evidence/<script>"`, from `$REPO` or `$DEPLOY`.
`grep-rc=1` means no post on magnetite.
Each printed post is given its cause on a line beneath it in the step's log, under a heading `## Causes`; a post no cause explains is a finding recorded in `verify.md`.
rehearse: stibnite and magnetite, with `mark.sh` writing to `1.3-rehearsal/window.env`; the rehearsal also runs `posts.sh` over an epoch a day back and confirms that the filter prints at least one known past post line from magnetite's journal.

Create `logs/s5-evidence/recent-activation.sh` (git-ignored), which every stibnite activation runs before `just activate`, because another session activated stibnite at 2026-11-05T23:26:45Z while `tasks.md` 1.2 was being recorded:

```bash
#!/bin/bash
# recent-activation.sh [EPOCH]: prints stibnite's current system and last deploy records, and exits 1
# if the last record is newer than EPOCH (the step's previous read) or than an hour ago, whichever is earlier.
set -uo pipefail
now=$(/bin/date -u +%s); hour=$((now - 3600)); since=${1:-$hour}; [ "$since" -lt "$hour" ] || since=$hour
readlink /run/current-system
/usr/bin/tail -n 3 /var/log/deploy-record.jsonl
ts=$(/usr/bin/tail -n 1 /var/log/deploy-record.jsonl | /usr/bin/sed -n 's/.*"ts":"\([^"]*\)".*/\1/p')
last=$(/bin/date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$ts" +%s 2>/dev/null || echo 0)
if [ "$last" -gt "$since" ]; then echo "STOP: stibnite was activated at $ts; ask the operator before activating"; exit 1; fi
echo "no activation since @$since"
```

A `STOP` is put to the operator, who names the other activation's source before the step continues; the answer is recorded in the step's log.
rehearse: stibnite, read-only, with no argument and with the epoch of `tasks.md` 1.2's read (`STOP` expected for the latter on 2026-11-05).

- [ ] **Step 2: Deploy magnetite (tasks.md 4.1)**

Refresh the deploy worktree; evidence paths below are relative to `$REPO`, and only the `nixbot-logs` and `clan machines update` lines run with `$DEPLOY` as the working directory:

```bash
git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main && git -C $DEPLOY log -1 --format='%H %s'
```

Expected: `$DEPLOY` is at `origin/main`, which contains pull request 1's merge.
Before the deploy, record what magnetite runs, rehearse: magnetite, read-only:

```bash
L=logs/s5-evidence/4.1-magnetite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -c "readlink -f /run/current-system; systemctl is-active fleet-alert.timer opentelemetry-collector otel-envelope.timer"' 2>&1 | tee "$L"
```

Expected: a closure and `active` three times.
Then, in `$DEPLOY`:

```bash
nixbot-logs queue
```

Expected: `Queue is empty`; otherwise wait and rerun.
Then:

```bash
"$REPO/logs/s5-evidence/mark.sh" MAGNETITE_DEPLOY_EPOCH | tee -a "$REPO/$L"
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
rehearse: magnetite, read-only, in `$REPO`:

```bash
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee -a "$L"
set -uo pipefail
readlink -f /run/current-system
systemctl is-active fleet-alert.timer opentelemetry-collector otel-envelope.timer
c=$(systemctl show fleet-alert -p Environment --value | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
jq -c '[.rules[]? | ((.presence // [])[] | .expectedHosts // [])[], (.alwaysOn // [])[]] | map(select(. == "stibnite")) | length' "$c"
systemctl cat 'observability-notify@.service' | grep -c 'observability-notify-failed'
EOS
```

Expected: a new closure; `active` three times; `0`, because no rule expects stibnite while its `collect` is false (delivered file); a non-zero count, the NixOS template still calling `observability-notify-failed`, whose store path Task 3 Step 2 keeps unchanged, so the template never names `observability-notify-run` (delivered file).
Then the posts since the deploy started:

```bash
. logs/s5-evidence/window.env
logs/s5-evidence/posts.sh "$MAGNETITE_DEPLOY_EPOCH" 2>&1 | tee -a "$L"
```

Expected: `grep-rc=1` and `notify.log absent`, or each post given its cause under `## Causes` in `$L` (a restart of `opentelemetry-collector` or `otel-envelope` by the deploy is a known cause; a `FAILED` with no such cause is a finding).

- [ ] **Step 3: stibnite's routine activation, with its collection still off (tasks.md 4.2) [operator]**

The orchestrator asks the operator, and does not proceed without the answer: "Are you at stibnite now, and may I activate pull request 1 on it with `just activate`?"
The answer and its time (`/bin/date -u`) are recorded in `logs/s5-evidence/4.2-presence-<ts>.log`; without a recorded yes this step does not run.
Before the activation, rehearse: stibnite, read-only, in `$REPO`:

```bash
L=logs/s5-evidence/4.2-stibnite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
"$REPO/logs/s5-evidence/recent-activation.sh" 2>&1 | tee "$L"
{ readlink /run/current-system; /usr/bin/wc -l < /var/log/deploy-record.jsonl; } 2>&1 | tee -a "$L"
```

Expected: `no activation since`, or a `STOP` resolved with the operator as Step 1 states; the closure and line count recorded at `tasks.md` 1.2, or the newer values with the routine activations since.
Then, in `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main`:

```bash
"$REPO/logs/s5-evidence/mark.sh" STIBNITE_ACTIVATE_EPOCH | tee -a "$REPO/$L"
just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
The key and token paths are read from stibnite's evaluated configuration at the same commit, and their owner and mode from the delivered files; rehearse: stibnite, read-only, in `$DEPLOY` (writing to `$REPO/$L`):

```bash
{
readlink /run/current-system
/usr/bin/sudo /bin/launchctl list | awk '$3 ~ /^org\.nixos\.(otelcol|otel-|prometheus-node-exporter)/'; echo "jobs-listed-above"
k=$(nix eval --raw '.#darwinConfigurations.stibnite.config.clan.core.vars.generators.otel-cert.files."key.pem".path')
t=$(nix eval --raw '.#darwinConfigurations.stibnite.config.clan.core.vars.generators.ntfy-alerter.files.token.path')
/usr/bin/sudo /bin/ls -lL "$k" "$t"
id _otelcol
/usr/bin/wc -l < /var/log/deploy-record.jsonl
} 2>&1 | tee -a "$REPO/$L"
```

Expected: a new closure; no job line above `jobs-listed-above` (nothing of the darwin fragment is loaded); both files `-r--------` owned by `_otelcol`; `uid=536(_otelcol) gid=536(_otelcol)`; the line count one above the first block's (delivered files).
The `-L` reads the file a symlinked secrets directory points at.
Then the posts since the activation started:

```bash
. logs/s5-evidence/window.env
logs/s5-evidence/posts.sh "$STIBNITE_ACTIVATE_EPOCH" 2>&1 | tee -a "$L"
```

Expected: `grep-rc=1` and `notify.log absent`, or each post given its cause under `## Causes`; stibnite is expected by no rule yet, so a post naming stibnite is a finding.

- [ ] **Step 4: Deploy cinnabar (tasks.md 4.3)**

cinnabar's `fleet-deadman` shares `modules/nixos/fleet-alert/transition.jq`, so pull request 1's pending-time change (Task 3 Step 6) is in cinnabar's closure; on 2026-11-05 the review found cinnabar's closure differing from `main` in `transition.jq` and `fleet-deadman` beyond the flake source (design D10).
In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty`:

```bash
L=$REPO/logs/s5-evidence/4.3-cinnabar-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
"$REPO/logs/s5-evidence/mark.sh" CINNABAR_DEPLOY_EPOCH | tee "$L"
clan machines update cinnabar 2>&1 | tee logs/cinnabar-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
Then, rehearse: cinnabar and magnetite, read-only, in `$REPO`:

```bash
. logs/s5-evidence/window.env
ssh cinnabar.zt 'bash -s' <<EOS 2>&1 | tee -a "$L"
readlink -f /run/current-system
systemctl is-active fleet-deadman.timer
sudo journalctl -u fleet-deadman -u 'observability-notify@*' --since @$CINNABAR_DEPLOY_EPOCH -o short-iso --no-pager | grep -E 'FIRING|RESOLVED|FAILED'; echo grep-rc=\$?
EOS
logs/s5-evidence/posts.sh "$CINNABAR_DEPLOY_EPOCH" 2>&1 | tee -a "$L"
```

Expected: a new closure; `active`; `grep-rc=1` on cinnabar and on magnetite, or each post given its cause under `## Causes` (runtime, cinnabar, magnetite).
