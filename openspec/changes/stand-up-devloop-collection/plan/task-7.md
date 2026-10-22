### Task 7: Deployment verification

Implements `tasks.md` 7.1–7.7 (design D1, D2, D6, D7, D9, D10, D11, Migration Plan, Risks; DCI `Each activation appends one deploy record`, `The devloop tables are pre-created with keys, a time index and deduplication`, `The collector reads nixbot's builds and attributes through two cursor queries`, `Each nixbot query re-reads a five-minute overlap in pages of 10,000 rows`, `Column grants are applied once nixbot's columns exist`, `devloop-reconcile runs daily as its own reader`; DC `A deploy can be attributed to the commits that built it`, `Every dev-loop event is recorded once and kept for a year`, `A gap in the dev-loop history reaches a person within a day`, `The past week of the dev loop can be asked about`; TSI `Databases and their retention are set at the telemetry store`, `Failure notices are posted to one topic`; HMC `magnetite contributes its own signals to the telemetry store`; FAI `The evaluator queries each rule's database as the regulators' store account`; FA `Pull-request builds that wait too long to start reach a person as a warning`; WA `A44`–`A49`).
This task is operations only, interleaved with the five deploys of magnetite, and it changes no repository file.
Step 0 writes the one deploy procedure that Tasks 1 to 5 invoke as `logs/s2-evidence/s2-deploy.sh magnetite D<n>`, Step 1 the read helpers, and Step 2 the baseline that must exist before D1.
The order is strict: Steps 0–2 before D1; Steps 3–4 (7.1) after D1 and before D2; Steps 7–8 (7.3) after D2 and before D3; Steps 9–20 (7.4) after D3 and before D4; Steps 21–25 (7.5) after D4 and before D5; Steps 26–27 (7.6) after D5; Steps 28–30 (7.7) at least seven days after D3; Step 5 (7.2) after the next natural reboot of magnetite after D1, and Step 6 at close-out, neither a gate for any deploy.
Every runtime observation has its failing side shown in the same task: the deploy-record file is shown absent before D1 and the previous closure read before D1 must reappear in the line; the peer rule is shown refusing the collector's role to another system user, and the column grants refusing an ungranted column; the reconcile is shown failing under a runtime drop-in before its passing runs are trusted; and the burn rule's rewritten window is shown equal to the deployed expression at the present instant before it is moved into the past.
A failed expectation stops the task at that step, and the next deploy does not start until the orchestrator decides; rollback, if chosen, follows design.md's Migration Plan in reverse order.
Every observation goes to `logs/s2-evidence/` (git-ignored); Task 8 folds it into `verify.md`, and `tasks.md` items 7.x are ticked in Task 8's change, not here.
No step prints or passes a credential on an argument list: the store password is read on magnetite under `sudo` into a mode-0600 netrc file that `curl --netrc-file` reads and that is removed on exit, and the PostgreSQL roles authenticate by peer with no password at all.

**Files:**
- Create (git-ignored helpers): `logs/s2-evidence/s2-deploy.sh`, `logs/s2-evidence/gsql.sh`, `logs/s2-evidence/pgq.sh`, `logs/s2-evidence/polls.sh`, `logs/s2-evidence/window.env`
- Create (git-ignored evidence): `logs/s2-evidence/7.<n>-<slug>-<UTC ts>.log` for every step below, the deploy logs `logs/s2-evidence/magnetite-D<n>-<UTC ts>.log` and the queue logs `logs/s2-evidence/queue-D<n>-<UTC ts>.log`
- Temporary: worktrees `/tmp/wt-s2-D<n>` at `origin/main`, removed by the procedure; on magnetite the runtime drop-in `/run/systemd/system/devloop-reconcile.service.d/zz-absent.conf` (Step 22, removed in Step 23)
- Modify: none in the repository

**Interfaces:**
- Consumes (Task 1): `/var/log/deploy-record.jsonl`, mode `0644`, one line `{"host":"<networking.hostName>","closure":"<$systemConfig>","previous_closure":"<readlink -f /run/current-system>","ts":"<date -u +%Y-%m-%dT%H:%M:%SZ>"}`, `previous_closure` omitted when `/run/current-system` does not exist.
- Consumes (Tasks 2, 3): `flake.lib.otelCollectorSchema.devloop.tables` (the four table names and their keys); `flake.lib.devloopCollection.queries.<ci_attribute|ci_build>`, `grants.<opentelemetry-collector|devloop-reconcile>.<builds|build_attributes|projects>` and `questions.<formationToLand|queueWait|buildOutcome>`; pipelines `devloop_<table>`; PostgreSQL roles `opentelemetry-collector` and `devloop-reconcile`; `devloop-pg-grants.service`; collector receivers `sqlquery/ci_attribute`, `sqlquery/ci_build`, `journald/gitea-mq`, `file_log/deploy-record` and exporters `otlp_http/devloop_<table>`.
- Consumes (Task 4): `devloop-reconcile.service` and `.timer`; its environment `DEVLOOP_RECONCILE_DAY`, `DEVLOOP_RECONCILE_DATABASE`; its output lines `devloop-reconcile: C<n> <name>: ok` and `devloop-reconcile: C<n> <name>: FAIL <detail>` for `C1 attributes` to `C7 current-system`, exit 1 when a clause fails and exit 2 when a source or the store cannot be read.
- Consumes (Task 5): `fleet-alert.service` with `Environment=FLEET_ALERT_CONFIG=<store path>`, whose JSON holds `user`, `storeUrl` and `rules[]` each with `database` and `language` and no top-level `database`; the rule `PullRequestQueueWaitBurn` with the `expr` of Global Constraints as amended by review F1 (first attempt per `build_id` through a join on `min(finished_at)`), containing the text `c.finished_at >= now() - INTERVAL '24 hours'` exactly once.
- Consumes (S1, S3): the store at `http://127.0.0.1:4000` with `regulator` (`ro`); `config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path`; the notifier's `FAILED <unit> on <host>` and `RESOLVED <unit> on <host>` posts on `fleet-alerts` and its `/var/lib/observability-notify/failed.log` lines `<epoch> <unit> <host>` (`modules/nixos/observability-notify.nix:55`, `:77`, `:39-41`); `nixbot-logs queue` printing `Queue is empty`.
- Consumes (vendor): the collector's internal telemetry, unset in magnetite's configuration (`modules/clan/services/otel-collector/flake-module.nix` sets no `service.telemetry`), defaults to level `normal` with a Prometheus reader on `localhost:8888` (`open-telemetry/opentelemetry-collector@v0.155.0:service/telemetry/otelconftelemetry/factory.go:50-59`), and 0.155 names its counters without a `_total` suffix (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/verify.md:494-501`); the collector's configuration path is the `--config=file:<path>` argument of its `ExecStart` (`NixOS/nixpkgs@ac1faec44836a722f7b003834f367486ff9adfd1:nixos/modules/services/monitoring/opentelemetry-collector.nix:114`); the store counts every HTTP request in `greptime_servers_http_requests_total{method,path,code,db}` and its latency in `greptime_servers_http_requests_elapsed`, unauthenticated at `/metrics` (`GreptimeTeam/greptimedb@v1.2.1:src/servers/src/metrics.rs:334-338`, `:454-483`; `src/servers/src/http.rs:1130-1133`), the `db` label being the bare schema name for the default catalog (`GreptimeTeam/greptimedb@v1.2.1:src/common/catalog/src/lib.rs:37-43`).
- Produces: `logs/s2-evidence/window.env` with `PRE_D1_SYSTEM`, `PRE_D1_LINES`, `D<n>_COMMIT`, `D<n>_START`, `D<n>_END` for `D1`…`D5`, `T_BOOT` (only when a natural reboot after D1 was observed), `T_FORCED_FAIL`, `T_FORCED_RESOLVE` (all times `date -u +%FT%TZ`); the gate lines Task 8 greps: `deploy record: PASS` (7.1), `boot record: PASS` or `boot record: not yet observed` in `7.2-boot-record-<ts>.log` (7.2), `devloop tables: PASS` (7.3), `ingest: PASS` (7.4), `devloop-reconcile: C7 current-system: ok` and `FAILED devloop-reconcile.service on magnetite` (7.5), `burn rule history: recorded` (7.6), `acceptance: PASS` (7.7).

- [ ] **Step 0: Write the deploy procedure (used by 1.7, 2.9, 3.11, 4.8 and 5.8)**

Create `logs/s2-evidence/s2-deploy.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Deploy one host from a fresh worktree of origin/main, only when nixbot's queue is empty.
# Usage: s2-deploy.sh HOST LABEL
#   LABEL names the window variables <LABEL>_COMMIT, <LABEL>_START and <LABEL>_END appended to window.env.
set -euo pipefail
[ "$#" -eq 2 ] || { echo "usage: s2-deploy.sh HOST LABEL" >&2; exit 64; }
host=$1; label=$2
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
ev=$repo/logs/s2-evidence
wt=/tmp/wt-s2-$label
ts() { date -u +%Y%m%dT%H%M%SZ; }
mkdir -p "$ev"
cd "$repo"
if [ -e "$wt" ]; then git worktree remove "$wt"; fi   # refuses on a dirty worktree: stop and ask, never --force
git fetch -q origin
git worktree add -q --detach "$wt" origin/main
commit=$(git -C "$wt" rev-parse HEAD)
echo "origin/main: $(git -C "$wt" log --oneline -1)"
# The queue listing goes to a file before grep reads it, so an early grep exit
# cannot SIGPIPE the writer and fail the test under pipefail.
while :; do
  q="$ev/queue-$label-$(ts).log"
  nixbot-logs queue > "$q" 2>&1 || true
  if grep -q 'Queue is empty' "$q"; then break; fi
  echo "queue busy at $(date -u +%FT%TZ); retrying in 120 s"; sleep 120
done
echo "${label}_COMMIT=$commit" | tee -a "$ev/window.env"
echo "${label}_START=$(date -u +%FT%TZ)" | tee -a "$ev/window.env"
cd "$wt"
mkdir -p logs
log="logs/$host-$label-$(ts).log"
set +e
clan machines update "$host" --upload-inputs 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
set -e
echo "${label}_END=$(date -u +%FT%TZ)" | tee -a "$ev/window.env"
mv "$log" "$ev/"
cd "$repo" && git worktree remove "$wt"
echo "clan exit=$status; log $ev/$(basename "$log")"
exit "$status"
```

Run:

```bash
chmod +x "$(git rev-parse --show-toplevel)/logs/s2-evidence/s2-deploy.sh"
bash -n "$(git rev-parse --show-toplevel)/logs/s2-evidence/s2-deploy.sh" && echo syntax-ok
```

Expected: `syntax-ok`.
This is S3's procedure (S3 plan Task 7 Step 0) without the `FILE LINE` negative-control mode, which S2 does not use, with the queue test reading a file instead of a pipe and with `<LABEL>_COMMIT` recorded for Step 30's join.
`nixbot-logs` prints the empty-queue line on stderr, which is why `2>&1` precedes the file (S1 plan Task 6 Step 5).
Tasks 1 to 5 each run `$REPO/logs/s2-evidence/s2-deploy.sh magnetite D<n>` after their own gate and expect `clan exit=0` as its last line.

- [ ] **Step 1: Write the read helpers**

Create `logs/s2-evidence/gsql.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Run SQL read from stdin against magnetite's store as regulator.
# Prints one JSON array per line: the column names, then each row.
# The password is read on magnetite under sudo into a 0600 netrc file, never onto an argument list.
# Usage: gsql.sh DATABASE < query.sql
set -euo pipefail
db=$1
sql=$(base64 | tr -d '\n')
ssh magnetite.zt "bash -s -- $(printf '%q ' "$db" "$sql")" <<'REMOTE'
set -euo pipefail
db=$1; sql=$2
pw=/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password
netrc=$(mktemp); trap 'rm -f "$netrc"' EXIT
chmod 600 "$netrc"
printf 'machine 127.0.0.1 login regulator password %s\n' "$(sudo cat "$pw")" > "$netrc"
resp=$(base64 -d <<<"$sql" | curl -sS --netrc-file "$netrc" -w '\n%{http_code}' \
  --data-urlencode sql@- "http://127.0.0.1:4000/v1/sql?db=$db")
code=${resp##*$'\n'}; body=${resp%$'\n'*}
if [ "$code" != 200 ]; then echo "HTTP $code: $body"; exit 1; fi
jq -c '.output[] | .records | (.schema.column_schemas | map(.name)), .rows[]' <<<"$body"
REMOTE
```

Create `logs/s2-evidence/pgq.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Run SQL read from stdin on magnetite's nixbot database as ROLE, by peer and with no password (-w).
# ROLE postgres runs under sudo -u postgres; any other ROLE runs in a transient DynamicUser unit whose
# user name is ROLE, the way opentelemetry-collector.service and devloop-reconcile.service connect.
# Usage: pgq.sh ROLE [psql flags...] < query.sql
set -euo pipefail
role=$1; shift
sql=$(base64 | tr -d '\n')
ssh magnetite.zt "bash -s -- $(printf '%q ' "$role" "$sql" "$@")" <<'REMOTE'
set -uo pipefail
role=$1; sql=$2; shift 2
psql=$(readlink -f /run/current-system/sw/bin/psql)
if [ "$role" = postgres ]; then
  base64 -d <<<"$sql" | sudo -u postgres "$psql" -X -w -d nixbot -v ON_ERROR_STOP=0 "$@" -f -
else
  base64 -d <<<"$sql" | sudo systemd-run --quiet --pipe --wait --collect \
    -p DynamicUser=yes -p "User=$role" \
    "$psql" -X -w -d nixbot -v ON_ERROR_STOP=0 "$@" -f -
fi
REMOTE
```

Create `logs/s2-evidence/polls.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Poll an ntfy topic anonymously from the workstation over the mesh.
# Usage: polls.sh TOPIC SINCE   (SINCE as ntfy accepts it: 10m, 1h, or an epoch)
set -euo pipefail
curl -sk "https://ntfy.zt/$1/json?poll=1&since=$2" \
  | jq -c 'select(.event == "message") | {time: (.time | todate), title, priority, message}'
```

Run:

```bash
cd "$(git rev-parse --show-toplevel)"
chmod +x logs/s2-evidence/gsql.sh logs/s2-evidence/pgq.sh logs/s2-evidence/polls.sh
bash -n logs/s2-evidence/gsql.sh && bash -n logs/s2-evidence/pgq.sh && bash -n logs/s2-evidence/polls.sh && echo syntax-ok
```

Expected: `syntax-ok`.
`gsql.sh` passes the SQL to magnetite base64-encoded as an argument, because the remote script itself arrives on ssh's stdin; the argument holds the query, never the password.
The transient unit of `pgq.sh` takes the name `opentelemetry-collector` or `devloop-reconcile` as its dynamic user, so PostgreSQL's `local all all peer` rule (`logs/s2/grounding.md` §1.1) maps it to the role of the same name exactly as it maps the real units; while `opentelemetry-collector.service` runs, systemd shares its dynamic UID with the transient unit by name.
The cameron login shell on magnetite is zsh (`modules/clan/inventory/services/users/cameron.nix:48`), which is why every multi-line remote script runs under `bash -s`.
Every `nix eval` of a `flake.lib` value below uses the leading-dot attribute path `#.lib.<name>`, because a plain `#lib.<name>` is first looked up under the default output prefixes, where nixpkgs' `lib` answers.

- [ ] **Step 2: Record the pre-D1 baseline and check the helpers (before 1.7)**

Run from stibnite before Task 1's deploy:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s2-evidence"
L="$EV/7.1-pre-d1-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo '$ nix eval --raw <main>#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path'
  nix eval --raw "git+file://$REPO?ref=main#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path"; echo
  pre=$(ssh magnetite.zt readlink -f /run/current-system)
  echo "PRE_D1_SYSTEM=$pre" | tee -a "$EV/window.env"
  n=$(ssh magnetite.zt 'if test -e /var/log/deploy-record.jsonl; then wc -l < /var/log/deploy-record.jsonl; else echo 0; fi')
  echo '$ ssh magnetite.zt ls -l /var/log/deploy-record.jsonl'
  ssh magnetite.zt 'ls -l /var/log/deploy-record.jsonl 2>&1 || true'
  echo "PRE_D1_LINES=$n" | tee -a "$EV/window.env"
  echo '$ gsql.sh fleet <<< "SELECT 1"'; echo 'SELECT 1' | "$EV/gsql.sh" fleet
  echo '$ pgq.sh postgres -At <<< "SELECT current_user"'; echo 'SELECT current_user;' | "$EV/pgq.sh" postgres -At
} 2>&1 | tee "$L"
```

Expected:
- `/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password`, the path `gsql.sh` reads (S3 recorded the same deployed path, `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/plan.md:6122`); if it differs, edit `pw=` in `gsql.sh` to the printed path and note the change in the log.
- `PRE_D1_SYSTEM=/nix/store/…-nixos-system-magnetite-…`.
- `ls: cannot access '/var/log/deploy-record.jsonl': No such file or directory` and `PRE_D1_LINES=0`: no snippet has written the file yet, which is the failing side of Step 3's check.
- `["Int64(1)"]` then `[1]` from the store as `regulator`, and `postgres` from PostgreSQL.
`ref=main` evaluates the local `main` bookmark, which the orchestrator keeps at `main@origin`; confirm with `jj log -r 'main & main@origin' --no-graph -T 'change_id.short()'` printing one id.

- [ ] **Step 3: 7.1 — D1 appended exactly one deploy record naming both closures (after 1.7)**

Run after `logs/s2-evidence/s2-deploy.sh magnetite D1` printed `clan exit=0`:

```bash
source "$EV/window.env"
L="$EV/7.1-deploy-record-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "PRE_D1_SYSTEM=$PRE_D1_SYSTEM PRE_D1_LINES=$PRE_D1_LINES D1_START=$D1_START D1_END=$D1_END"
  ssh magnetite.zt 'bash -s' > /tmp/s2-7.1.txt <<'REMOTE'
f=/var/log/deploy-record.jsonl
echo "stat $(stat -c '%a %U %G' "$f")"
echo "lines $(wc -l < "$f")"
echo "current $(readlink -f /run/current-system)"
echo "last $(tail -n 1 "$f" | jq -c .)"
REMOTE
  cat /tmp/s2-7.1.txt
  mode=$(sed -n 's/^stat //p' /tmp/s2-7.1.txt); lines=$(sed -n 's/^lines //p' /tmp/s2-7.1.txt)
  cur=$(sed -n 's/^current //p' /tmp/s2-7.1.txt); last=$(sed -n 's/^last //p' /tmp/s2-7.1.txt)
  host=$(jq -r .host <<<"$last"); clo=$(jq -r .closure <<<"$last")
  prev=$(jq -r '.previous_closure // "ABSENT"' <<<"$last"); t=$(jq -r .ts <<<"$last")
  echo "parsed: host=$host closure=$clo previous_closure=$prev ts=$t"
  if [ "$mode" = "644 root root" ] && [ "$lines" -eq $((PRE_D1_LINES + 1)) ] && [ "$host" = magnetite ] \
    && [ "$clo" = "$cur" ] && [ "$prev" = "$PRE_D1_SYSTEM" ] && [ "$clo" != "$prev" ] \
    && [[ "$t" > "$D1_START" || "$t" == "$D1_START" ]] && [[ "$t" < "$D1_END" || "$t" == "$D1_END" ]]; then
    echo "deploy record: PASS"
  else
    echo "deploy record: FAIL"
  fi
} 2>&1 | tee "$L"
```

Expected: `stat 644 root root`; `lines 1`; the parsed line names `magnetite`, a `closure` equal to `current` (the delivered `readlink -f /run/current-system`), a `previous_closure` equal to `PRE_D1_SYSTEM` read in Step 2, and a `ts` between `D1_START` and `D1_END`; then `deploy record: PASS`.
The two closures come from independent reads: `previous_closure` from the snippet during activation, `PRE_D1_SYSTEM` from Step 2 before the deploy, so their equality shows the snippet ran before activation relinked `/run/current-system` (WA `A49`), and the line count going from `PRE_D1_LINES` to one more shows D1 added exactly one line.
The timestamps compare as strings because the snippet and `window.env` both write `%Y-%m-%dT%H:%M:%SZ`.

- [ ] **Step 4: 7.1 gate**

Run:

```bash
{ rg -l 'deploy record: PASS' "$EV"/7.1-deploy-record-*.log && echo "7.1 passed: D2 may start"; } 2>&1 | tee "$EV/7.1-gate-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: one file name, then `7.1 passed: D2 may start`.
Task 2's 2.9 runs only after this line.

- [ ] **Step 5: 7.2 — the boot line at magnetite's next natural reboot after D1 (opportunistic, not a gate)**

No reboot is scheduled for this change (review F18): 7.2 is observed when magnetite next reboots for its own reasons after D1, and no deploy or other step waits on it.
Run this after any such reboot, and again at Step 6:

```bash
source "$EV/window.env"
L="$EV/7.2-boot-record-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "D1_END=$D1_END"
  ssh magnetite.zt 'bash -s' > /tmp/s2-7.2.txt <<'REMOTE'
f=/var/log/deploy-record.jsonl
boot=$(date -u -d "$(uptime -s)" +%FT%TZ)
echo "boot $boot"
echo "booted $(readlink -f /run/booted-system)"
echo "current $(readlink -f /run/current-system)"
echo "boots $(sudo journalctl --list-boots --no-pager -q | wc -l)"
jq -c --arg b "$boot" 'select(.ts >= $b)' "$f" | head -n 1 | sed 's/^/first-after-boot /'
jq -c --arg b "$boot" 'select(.ts >= $b and (has("previous_closure") | not))' "$f" | wc -l | sed 's/^/no-previous-after-boot /'
REMOTE
  cat /tmp/s2-7.2.txt
  boot=$(sed -n 's/^boot //p' /tmp/s2-7.2.txt); booted=$(sed -n 's/^booted //p' /tmp/s2-7.2.txt)
  first=$(sed -n 's/^first-after-boot //p' /tmp/s2-7.2.txt); np=$(sed -n 's/^no-previous-after-boot //p' /tmp/s2-7.2.txt)
  if [[ "$boot" < "$D1_END" ]]; then
    echo "boot record: not yet observed (magnetite last booted at $boot, before D1_END)"
  elif [ -n "$first" ] && [ "$np" = 1 ] && [ "$(jq -r .host <<<"$first")" = magnetite ] \
    && [ "$(jq -r .closure <<<"$first")" = "$booted" ] \
    && [ "$(jq -r 'has("previous_closure")' <<<"$first")" = false ]; then
    grep -q "^T_BOOT=$boot$" "$EV/window.env" || echo "T_BOOT=$boot" | tee -a "$EV/window.env"
    echo "boot record: PASS"
  else
    echo "boot record: FAIL"
  fi
} 2>&1 | tee "$L"
```

Expected, before any reboot since D1: `boot` earlier than `D1_END` and `boot record: not yet observed (…)`.
Expected, after a natural reboot: `boot` after `D1_END`; the first line with `ts` at or after the boot names `magnetite`, has a `closure` equal to `booted` and no `previous_closure` key; `no-previous-after-boot 1`, exactly one line without `previous_closure` since that boot; `T_BOOT=<boot>` appended once; `boot record: PASS`.
At boot the activation runs from a fresh `/run`, before it links `/run/current-system`, so the snippet finds no current system (design D9); a deploy after the boot adds lines that do carry `previous_closure`, which the filter leaves out.
`uptime -s` prints the kernel's boot time in magnetite's local zone, which the remote `date -u -d` converts to UTC; the activation runs after it, so the boot's line has a `ts` at or after it.
If the reboot happens after D3, the collector ships this line too, and C6 and C7 of later reconcile runs count it.

- [ ] **Step 6: 7.2 — the final record at close-out**

Run Step 5's block once more when Task 8 starts, whether or not a reboot has occurred.

Expected: the newest `7.2-boot-record-*.log` ends in `boot record: PASS` or `boot record: not yet observed (…)`; Task 8 records 7.2 as observed or as not yet observed accordingly, and neither result blocks close-out.

- [ ] **Step 7: 7.3 — the four tables and pipelines exist, empty, without a TTL of their own (after 2.9)**

Run after `s2-deploy.sh magnetite D2` printed `clan exit=0`:

```bash
L="$EV/7.3-tables-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  want=$(nix eval --json "git+file://$REPO?ref=main#.lib.otelCollectorSchema.devloop.tables" --apply builtins.attrNames | jq -r 'sort | join(",")')
  echo "allow-list tables: $want"
  echo '$ SHOW TABLES FROM devloop'; echo 'SHOW TABLES FROM devloop' | "$EV/gsql.sh" devloop | tee /tmp/s2-7.3-tables.txt
  have=$(sed 1d /tmp/s2-7.3-tables.txt | jq -r '.[0]' | sort | paste -sd, -)
  ok=yes; [ "$have" = "$want" ] || ok=no
  for t in batch_event ci_attribute ci_build deploy_record; do
    echo "\$ SHOW CREATE TABLE $t"
    echo "SHOW CREATE TABLE \"$t\"" | "$EV/gsql.sh" devloop | sed -n 2p | jq -r '.[1]' | tee /tmp/s2-7.3-create.txt
    grep -qF "append_mode = 'false'" /tmp/s2-7.3-create.txt || ok=no
    grep -qF "sst_format = 'flat'" /tmp/s2-7.3-create.txt || ok=no
    echo "\$ SELECT count(*) FROM $t"
    c=$(echo "SELECT count(*) FROM \"$t\"" | "$EV/gsql.sh" devloop | sed -n 2p | jq '.[0]'); echo "$t rows=$c"
    [ "$c" = 0 ] || ok=no
  done
  echo '$ information_schema.tables create_options for devloop'
  echo "SELECT table_name, create_options FROM information_schema.tables WHERE table_schema = 'devloop' ORDER BY table_name" | "$EV/gsql.sh" devloop | tee /tmp/s2-7.3-options.txt
  if grep -q ttl /tmp/s2-7.3-options.txt; then ok=no; fi
  echo '$ SHOW CREATE DATABASE devloop'; echo 'SHOW CREATE DATABASE devloop' | "$EV/gsql.sh" devloop
  echo '$ pipelines'
  echo "SELECT DISTINCT name FROM greptime_private.pipelines WHERE name LIKE 'devloop_%' ORDER BY name" | "$EV/gsql.sh" devloop | tee /tmp/s2-7.3-pipelines.txt
  pipes=$(sed 1d /tmp/s2-7.3-pipelines.txt | jq -r '.[0]' | sort | paste -sd, -)
  [ "$pipes" = "$(echo "$want" | tr ',' '\n' | sed 's/^/devloop_/' | paste -sd, -)" ] || ok=no
  [ "$ok" = yes ] && echo "devloop tables: PASS" || echo "devloop tables: FAIL"
} 2>&1 | tee "$L"
```

Expected:
- `allow-list tables: batch_event,ci_attribute,ci_build,deploy_record` from the evaluated allow-list, and the same four names from `SHOW TABLES FROM devloop` on the store, the two independently produced sets being equal.
- Each `SHOW CREATE TABLE` shows its columns, `PRIMARY KEY`, `TIME INDEX`, `append_mode = 'false'` and `sst_format = 'flat'`, and the inherited `ttl = '11months 30days 3h 50m 24s'`, which is `devloop`'s 365 days printed by the store (`logs/s2/spike-dedup.md:73`).
- `rows=0` for each of the four tables.
- `create_options` of the four tables without `ttl`, which is how the store shows a table holding no TTL of its own (`logs/s2/spike-dedup.md:73`), and `SHOW CREATE DATABASE devloop` showing the database's `ttl`.
- The four names `devloop_batch_event`, `devloop_ci_attribute`, `devloop_ci_build`, `devloop_deploy_record`, possibly listed once each although the schema job uploads a new version per run (design Risks, last trade-off).
- `devloop tables: PASS`.
The regulator's read of `greptime_private.pipelines` is `[INFERENCE]` from its `ro` permission covering every schema; if the store answers 403 there, stop and report, because 7.3 names that table and `regulator` as its reader.

- [ ] **Step 8: 7.3 — the next scheduled `greptimedb-envelope` run passes; gate**

Run, then wait until the printed `NEXT` time has passed (the timer is hourly with up to 5 min of randomized delay, `modules/nixos/greptimedb.nix:334-341`) and run the second block:

```bash
ssh magnetite.zt 'systemctl list-timers greptimedb-envelope.timer --all --no-pager'
```

```bash
source "$EV/window.env"
L="$EV/7.3-envelope-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "D2_END=$D2_END"
  ssh magnetite.zt "systemctl show greptimedb-envelope -p Result -p ExecMainStatus -p ExecMainStartTimestamp -p ExecMainExitTimestamp; sudo journalctl -u greptimedb-envelope --since '$D2_END' -p warning --no-pager -q || true"
  rg -l 'devloop tables: PASS' "$EV"/7.3-tables-*.log && echo "7.3 passed: D3 may start"
} 2>&1 | tee "$L"
```

Expected: `LAST` of the timer after `D2_END`; `Result=success`, `ExecMainStatus=0` and an `ExecMainStartTimestamp` after `D2_END`; no warning-or-worse journal line; the Step 7 file name, then `7.3 passed: D3 may start`.
Task 3's 3.11 runs only after this line.

- [ ] **Step 9: 7.4 — the backfill reaches nixbot's counts (start within a minute of D3_END)**

Run as soon as `s2-deploy.sh magnetite D3` printed `clan exit=0`:

```bash
source "$EV/window.env"
L="$EV/7.4-backfill-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "D3_END=$D3_END"
  done_a=no; done_b=no
  for i in $(seq 1 30); do
    na=$(echo "SELECT count(*) FROM build_attributes a JOIN builds b ON b.id = a.build_id JOIN projects p ON p.id = b.project_id WHERE a.finished_at IS NOT NULL;" | "$EV/pgq.sh" postgres -At)
    nb=$(echo "SELECT count(*) FROM builds WHERE finished_at IS NOT NULL;" | "$EV/pgq.sh" postgres -At)
    sa=$(echo 'SELECT count(*) FROM (SELECT DISTINCT build_id, attr FROM ci_attribute)' | "$EV/gsql.sh" devloop | sed -n 2p | jq '.[0]')
    sb=$(echo 'SELECT count(*) FROM (SELECT DISTINCT build_id FROM ci_build)' | "$EV/gsql.sh" devloop | sed -n 2p | jq '.[0]')
    echo "poll $i $(date -u +%FT%TZ) ci_attribute keys=$sa nixbot finished attributes=$na ci_build keys=$sb nixbot finished builds=$nb"
    [ "$done_a" = no ] && [ "$sa" -ge "$na" ] && { done_a=yes; echo "ci_attribute reached nixbot's count at poll $i"; }
    [ "$done_b" = no ] && [ "$sb" -ge "$nb" ] && { done_b=yes; echo "ci_build reached nixbot's count at poll $i"; }
    [ "$done_a" = yes ] && [ "$done_b" = yes ] && break
    sleep 60
  done
  [ "$done_a" = yes ] && [ "$done_b" = yes ] && echo "backfill: PASS" || echo "backfill: FAIL"
} 2>&1 | tee "$L"
```

Expected: `ci_attribute` keys climbing by about 10,000 a minute, one page per 60 s poll (design D6), and `ci_attribute reached nixbot's count at poll` 19 to 25, from about 200,000 attribute rows (`logs/s2/grounding.md` §1.4, 200,006 on 2026-10-21) plus those finished since; `ci_build` reaching its count within the first one or two polls (about 1,720 builds); then `backfill: PASS`.
The two counts come from separate systems, nixbot's PostgreSQL as `postgres` and the store as `regulator`, so neither is derived from the other.
nixbot's attribute count joins `builds` and `projects` as the export query does (review F22e), so an attribute whose build or project row is missing is excluded on both sides; the build count takes `builds` alone, as the `ci_build` query joins nothing.
A store count above nixbot's is expected by the size of restarted attributes, whose earlier finish the store keeps under the same `(build_id, attr)` while nixbot's row now has a later or null `finished_at` (design D11 Rationale).

- [ ] **Step 10: 7.4 — every devloop exporter sends with no failure**

Run once Step 9 printed `backfill: PASS`:

```bash
L="$EV/7.4-exporters-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ssh magnetite.zt 'curl -s http://127.0.0.1:8888/metrics' > /tmp/s2-otel-metrics.txt
  echo '$ otelcol exporter log-record counters for otlp_http/devloop_*'
  grep -E '^otelcol_exporter_(sent|send_failed)_log_records(_total)?\{' /tmp/s2-otel-metrics.txt | grep 'exporter="otlp_http/devloop_' || echo "no devloop exporter counters"
  ok=yes
  for t in batch_event ci_attribute ci_build deploy_record; do
    for k in sent send_failed; do
      v=$(awk -v e="exporter=\"otlp_http/devloop_$t\"" -v k="$k" '$0 ~ "^otelcol_exporter_" k "_log_records(_total)?\\{" && index($0, e) { s += $NF } END { printf "%d", s }' /tmp/s2-otel-metrics.txt)
      echo "otlp_http/devloop_$t $k=$v"
      if [ "$k" = sent ] && [ "$v" -le 0 ]; then ok=no; fi
      if [ "$k" = send_failed ] && [ "$v" -ne 0 ]; then ok=no; fi
    done
  done
  [ "$ok" = yes ] && echo "exporters: PASS" || echo "exporters: FAIL"
} 2>&1 | tee "$L"
```

Expected: for each of the four exporters `sent` above zero and `send_failed=0`, a counter absent from the listing counting as zero, then `exporters: PASS`.
`batch_event` has sent rows because the journal holds gitea-mq lines since 2026-09-16 (`logs/s2/grounding.md` §2.1), and `deploy_record` because the file holds D1's, D2's and D3's lines.
A non-zero `send_failed` names the exporter whose table or pipeline the store refused, the failure `devloop-ingest`'s writer-ordering case shows (Global Constraints, S1 retrospective §6).

- [ ] **Step 11: 7.4 — both roles connect by peer with no password and hold exactly the evaluated column grants**

Run:

```bash
L="$EV/7.4-grants-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo '$ systemctl is-active devloop-pg-grants'
  ssh magnetite.zt 'systemctl is-active devloop-pg-grants'
  for r in opentelemetry-collector devloop-reconcile; do
    echo "\$ pgq.sh $r: current_user, password-less (-w)"
    echo 'SELECT current_user;' | "$EV/pgq.sh" "$r" -At
  done
  echo '$ pgq.sh opentelemetry-collector: SELECT error FROM builds (not granted)'
  echo 'SELECT error FROM builds LIMIT 1;' | "$EV/pgq.sh" opentelemetry-collector -At
  echo '$ pgq.sh devloop-reconcile: SELECT error FROM build_attributes (not granted)'
  echo 'SELECT error FROM build_attributes LIMIT 1;' | "$EV/pgq.sh" devloop-reconcile -At
  echo '$ ssh magnetite.zt psql -w -U opentelemetry-collector as cameron (peer must refuse)'
  ssh magnetite.zt 'psql -X -w -d nixbot -U opentelemetry-collector -c "SELECT 1" 2>&1 || true'
  echo '$ live column privileges'
  echo "SELECT json_object_agg(grantee, t) FROM (SELECT grantee, json_object_agg(table_name, cols) AS t FROM (SELECT grantee, table_name, json_agg(column_name::text ORDER BY column_name) AS cols FROM information_schema.column_privileges WHERE privilege_type = 'SELECT' AND grantee IN ('opentelemetry-collector', 'devloop-reconcile') GROUP BY 1, 2) c GROUP BY 1) g;" \
    | "$EV/pgq.sh" postgres -At > /tmp/s2-7.4-live-grants.json
  jq -S . /tmp/s2-7.4-live-grants.json
  nix eval --json "git+file://$REPO?ref=main#.lib.devloopCollection.grants" \
    | jq -S 'map_values(map_values(sort) | with_entries(select(.value | length > 0)))' > /tmp/s2-7.4-eval-grants.json
  echo '$ evaluated flake.lib.devloopCollection.grants'; cat /tmp/s2-7.4-eval-grants.json
  if diff <(jq -S . /tmp/s2-7.4-live-grants.json) /tmp/s2-7.4-eval-grants.json; then echo "grants: PASS"; else echo "grants: FAIL"; fi
} 2>&1 | tee "$L"
```

Expected:
- `active`.
- `opentelemetry-collector` and `devloop-reconcile`, each printed by its own role's session, which `-w` would have refused had a password been asked for (WA `A45`).
- `ERROR:  permission denied for table builds` and `ERROR:  permission denied for table build_attributes`: an ungranted column is refused to each role.
- `psql: error: … FATAL:  Peer authentication failed for user "opentelemetry-collector"`: the role is admitted only to the system user of the same name, the failing side of the first two connections.
- The live privileges and the evaluated `grants` printed, then no `diff` output and `grants: PASS`; the live side is PostgreSQL's catalog after `devloop-pg-grants` ran, the evaluated side is the Nix value the grant SQL is rendered from, and they differ if the unit applied a different or partial set.
The two transient units run as dynamic users named after the roles, which is how both services connect, so these sessions exercise the peer rule and the column grants together.

- [ ] **Step 12: 7.4 — `devloop-pg-grants` ran after nixbot and both roles query their tables**

Run:

```bash
L="$EV/7.4-pg-grants-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ssh magnetite.zt 'systemctl show devloop-pg-grants -p ActiveState -p Result -p After -p WantedBy -p PartOf -p ActiveEnterTimestamp; systemctl show nixbot -p ActiveEnterTimestamp'
  ssh magnetite.zt 'sudo journalctl -u devloop-pg-grants -b --no-pager -o short-iso -q'
  echo '$ pgq.sh opentelemetry-collector: count over the granted columns of builds, build_attributes, projects'
  echo 'SELECT count(*) FROM build_attributes a JOIN builds b ON b.id = a.build_id JOIN projects p ON p.id = b.project_id WHERE a.finished_at IS NOT NULL;' | "$EV/pgq.sh" opentelemetry-collector -At
  echo '$ pgq.sh devloop-reconcile: count over the granted columns of builds and build_attributes'
  echo 'SELECT (SELECT count(*) FROM builds WHERE finished_at IS NOT NULL) || $$ $$ || (SELECT count(*) FROM build_attributes WHERE finished_at IS NOT NULL);' | "$EV/pgq.sh" devloop-reconcile -At
  echo "pg-grants: recorded"
} 2>&1 | tee "$L"
```

Expected: `ActiveState=active`, `Result=success`, `After=` containing `postgresql.service`, `postgresql-setup.service` and `nixbot.service`, `WantedBy=multi-user.target`, an empty `PartOf=`, and an `ActiveEnterTimestamp` after nixbot's; the unit's journal for this boot showing its one run after D3's activation; a positive count from each role, with no `permission denied`; `pg-grants: recorded`.
The unit grants once per boot, and at an activation only when the unit changes, after nixbot's columns exist (review F6; S2 review F2); it does not run again when nixbot restarts, and a grant lost to a later nixbot migration is detected by the collector's query errors and by reconcile C1 and C2 (missing keys, or exit 2), not repaired, so no step here claims a re-run.

- [ ] **Step 13: 7.4 — per-message journal counts equal `batch_event`'s**

Run twice, a minute apart, at a time no merge-queue batch is running (`nixbot-logs queue` empty):

```bash
L="$EV/7.4-batch-lines-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ssh magnetite.zt 'bash -s' > /tmp/s2-7.4-journal.tsv <<'REMOTE'
sudo journalctl -u gitea-mq.service -o cat --no-pager \
  | grep -oE 'msg="batch (formed|built|landed|bisecting|done)"' \
  | sed -E 's/^msg="(.*)"$/\1/' | sort | uniq -c \
  | awk '{ n = $1; $1 = ""; sub(/^ /, ""); print $0 "\t" n }'
REMOTE
  echo '$ journal (gitea-mq.service) per msg'; cat /tmp/s2-7.4-journal.tsv
  echo 'SELECT msg, count(*) FROM batch_event GROUP BY msg ORDER BY msg' | "$EV/gsql.sh" devloop | sed 1d | jq -r '"\(.[0])\t\(.[1])"' | sort > /tmp/s2-7.4-store.tsv
  echo '$ batch_event per msg'; cat /tmp/s2-7.4-store.tsv
  if diff <(LC_ALL=C sort /tmp/s2-7.4-journal.tsv) <(LC_ALL=C sort /tmp/s2-7.4-store.tsv); then echo "batch lines: PASS"; else echo "batch lines: FAIL"; fi
} 2>&1 | tee "$L"
```

Expected: the same five-or-fewer rows on both sides, `batch built`, `batch done`, `batch formed`, `batch landed` and, if retained, `batch bisecting`, with equal counts (about 2,535 lines over the 7 days before 2026-10-21, more over the whole journal, `logs/s2/grounding.md` §2.2); no `diff` output; `batch lines: PASS` on both runs.
The journal side counts the lines `journald/gitea-mq` is configured to select, read by `journalctl` independently of the collector, and the store side the rows the pipeline wrote (WA `A44`).
The journal side runs without `--follow`, so it reads every retained boot; the collector's `journalctl` always runs with `--follow`, which systemd 261 limits to the current boot unless the receiver's `journalctl_path` wrapper adds `--boot=all`.
This step's first run after D3 failed for that reason (282 of 772 lines, `logs/s2-evidence/7.4-batch-lines-20261022T*.log`); after the fix's deploy, Step 13a resets the receiver's cursor and this step is run again.

- [ ] **Step 13a: 7.4 — reset the `journald/gitea-mq` cursor once after the `--boot=all` fix is deployed (operator)**

Run from `$REPO` on stibnite after the deploy that carries the wrapper, with `nixbot-logs queue` empty:

```bash
logs/s2-evidence/s2-journald-cursor-reset.sh
```

The script checks that the running collector configuration's `journalctl_path` carries `--boot=all`, stops the collector, moves aside only `/var/lib/private/opentelemetry-collector/queue/receiver_journald_gitea-mq` (the `file_storage` extension keeps one bbolt file per component; the `exporter_*` queues and the other receivers' cursors stay), starts the collector, and waits up to 10 min for `batch_event`'s per-`msg` counts to equal the journal's over every boot.
Expected: the guard prints the wrapper and its `--boot=all` line; `equal after poll <n>`; both per-`msg` listings equal (772 lines on 2026-10-22: `batch bisecting` 9, `batch built` 217, `batch done` 180, `batch formed` 180, `batch landed` 186, plus any written since); `batch_event [total, distinct (batch, msg, ts)]` equal; `otlp_http/devloop_batch_event send_failed=0`; `cursor reset: PASS`, logged to `logs/s2-evidence/7.4-cursor-reset-<ts>.log`.
The re-read re-sends the 282 stored lines, which the store keeps once each under `batch_event`'s key and time index (WA `A46`).
Then run Step 13 again; its `batch lines: PASS` is the line Step 20 needs.

- [ ] **Step 14: 7.4 — no table holds a duplicate key**

Run:

```bash
L="$EV/7.4-keys-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ok=yes
  for spec in 'ci_attribute:build_id, attr, finished_at' 'ci_build:build_id, finished_at' 'batch_event:batch, msg, ts' 'deploy_record:host, ts'; do
    t=${spec%%:*}; k=${spec#*:}
    r=$(echo "SELECT (SELECT count(*) FROM $t) AS total, (SELECT count(*) FROM (SELECT DISTINCT $k FROM $t)) AS distinct_keys" | "$EV/gsql.sh" devloop | sed -n 2p)
    echo "$t ($k): [total, distinct_keys] = $r"
    [ "$(jq '.[0] == .[1] and .[0] > 0' <<<"$r")" = true ] || ok=no
  done
  [ "$ok" = yes ] && echo "keys: PASS" || echo "keys: FAIL"
} 2>&1 | tee "$L"
```

Expected: four lines whose two numbers are equal and positive, then `keys: PASS`.
The polls re-sent every row younger than five minutes about five times and the journal and file receivers send each line once (design D6), so equality is the store keeping one row per key and time in a pre-created non-append table (WA `A46`), the property `devloop-ingest`'s append-mode table mutant shows failing.

- [ ] **Step 15: 7.4 — `EXPLAIN ANALYZE` of each export query as `opentelemetry-collector` with the live cursor**

Run:

```bash
L="$EV/7.4-explain-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  cfg=$(ssh magnetite.zt 'systemctl show opentelemetry-collector -p ExecStart --value' | grep -o 'config=file:[^ ;]*' | cut -d: -f2)
  echo "collector config $cfg"
  ssh magnetite.zt "cat '$cfg'" > /tmp/s2-otelcol.yaml
  for t in ci_attribute ci_build; do
    q=$(nix run nixpkgs#yq-go -- -r ".receivers.\"sqlquery/$t\".queries[0].sql" /tmp/s2-otelcol.yaml)
    e=$(nix eval --raw "git+file://$REPO?ref=main#.lib.devloopCollection.queries.$t")
    [ "$q" = "$e" ] && echo "$t: delivered query = evaluated flake.lib.devloopCollection.queries.$t" || echo "$t: delivered query DIFFERS from the evaluated one"
    us=$(echo "SELECT CAST(max(finished_at) AS BIGINT) FROM $t" | "$EV/gsql.sh" devloop | sed -n 2p | jq '.[0]')
    cursor="$(date -u -r $((us / 1000000)) +%Y-%m-%dT%H:%M:%S).$(printf '%06d' $((us % 1000000)))Z"
    echo "$t live cursor: $cursor (from $us)"
    echo "\$ pgq.sh opentelemetry-collector: PREPARE q(text) AS <query>; EXPLAIN (ANALYZE, BUFFERS) EXECUTE q('$cursor')"
    printf 'PREPARE q(text) AS %s;\nEXPLAIN (ANALYZE, BUFFERS) EXECUTE q(%s);\n' "$q" "'$cursor'" | "$EV/pgq.sh" opentelemetry-collector -At
  done
  echo "explain: recorded"
} 2>&1 | tee "$L"
```

Expected:
- `ci_attribute: delivered query = evaluated …` and the same for `ci_build`: the query is read from the delivered configuration and compared with the evaluated value, not taken from source.
- Each live cursor within the last ten minutes, which also confirms that the cast yields microseconds; a cursor in 1970 or in a far year means the unit is different, and the step is rerun with the divisor corrected `[INFERENCE: GreptimeDB casts a TIMESTAMP(6) to its microsecond count]`.
- Two plans, each ending in `Execution Time: … ms`, the top node's `rows=` the rows of the last five minutes plus those tied with the cursor, and for `build_attributes` the index `build_attributes_build_finished_idx` the design names (design D6, `logs/s2/grounding.md` §1.6) `[INFERENCE: grounding measured a window query, not this exact query]`; the plans are recorded, with no threshold (BS D15).
- `explain: recorded`.
The cursor is the last stored `finished_at`, which is the tracking value the receiver keeps, because each poll is ordered by `finished_at` and its last row is the newest row it sent (`open-telemetry/opentelemetry-collector-contrib@aaf5045a2:receiver/sqlqueryreceiver/README.md:166-173`); the parameter is bound as text, as the receiver binds it, and cast by the query's own `$1::timestamptz`.

- [ ] **Step 16: 7.4 — the widest `finished_at` tie is below 10,000**

Run:

```bash
L="$EV/7.4-tie-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  for t in build_attributes builds; do
    echo "\$ widest finished_at tie in $t"
    echo "SELECT finished_at, count(*) FROM $t WHERE finished_at IS NOT NULL GROUP BY 1 ORDER BY 2 DESC LIMIT 1;" | "$EV/pgq.sh" postgres -At | tee /tmp/s2-7.4-tie-$t.txt
  done
  w=$(cut -d'|' -f2 /tmp/s2-7.4-tie-build_attributes.txt)
  [ "$w" -lt 10000 ] && echo "tie: PASS (widest build_attributes tie $w rows)" || echo "tie: FAIL (widest build_attributes tie $w rows)"
} 2>&1 | tee "$L"
```

Expected: one `finished_at|count` line per table, the attribute tie a small number (nine tied values exist, `logs/s2/grounding.md` §1.6), then `tie: PASS (widest build_attributes tie <n> rows)`.
A tie of 10,000 or more would stall the cursor at that value, since a page could never get past it (design Risks).

- [ ] **Step 17: 7.4 — the deploy day's sent and stored rows against 100,000 (before 23:50 UTC on D3's day, before Step 18)**

Run:

```bash
source "$EV/window.env"
L="$EV/7.4-budget-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "D3_END=$D3_END now=$(date -u +%FT%TZ) collector since $(ssh magnetite.zt 'systemctl show opentelemetry-collector -p ActiveEnterTimestamp --value')"
  ssh magnetite.zt 'curl -s http://127.0.0.1:8888/metrics' > /tmp/s2-otel-metrics.txt
  sent=0; stored=0
  for t in batch_event ci_attribute ci_build deploy_record; do
    s=$(awk -v e="exporter=\"otlp_http/devloop_$t\"" '$0 ~ "^otelcol_exporter_sent_log_records(_total)?\\{" && index($0, e) { s += $NF } END { printf "%d", s }' /tmp/s2-otel-metrics.txt)
    r=$(echo "SELECT count(*) FROM $t" | "$EV/gsql.sh" devloop | sed -n 2p | jq '.[0]')
    echo "$t sent=$s stored=$r"
    sent=$((sent + s)); stored=$((stored + r))
  done
  echo "budget: D3 day ${D3_END%%T*} sent=$sent stored=$stored against ADR-004's 100000 rows a day; exceedance: the backfill of nixbot's retained history, accepted once on the deploy day (design Risks)"
  echo "budget: recorded"
} 2>&1 | tee "$L"
```

Expected: the collector active since D3's activation on the same UTC day; `ci_attribute sent` at or above its `stored`, both above 200,000, and the other three in the hundreds to thousands; the `budget:` line with totals above 100,000, naming the backfill as the one exceedance; `budget: recorded`.
The sent figures are the exporters' counters since the collector started at D3, which on D3's day are the day's sends; the stored figures are the tables' rows, all written since 7.3 found them empty.
Sent exceeds stored by the overlap re-reads the store deduplicated (design D6: about five sends per row younger than five minutes).

- [ ] **Step 18: 7.4 — a collector restart does not re-send the backfill**

Run after Step 17:

```bash
L="$EV/7.4-restart-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  T=$(date -u +%FT%TZ); echo "restart at $T"
  ssh magnetite.zt 'sudo systemctl restart opentelemetry-collector; systemctl is-active opentelemetry-collector'
  sleep 200
  ssh magnetite.zt 'curl -s http://127.0.0.1:8888/metrics' > /tmp/s2-otel-metrics.txt
  acc() { awk -v e="receiver=\"$1\"" '$0 ~ "^otelcol_receiver_accepted_log_records(_total)?\\{" && index($0, e) { s += $NF } END { printf "%d", s }' /tmp/s2-otel-metrics.txt; }
  a=$(acc sqlquery/ci_attribute); b=$(acc sqlquery/ci_build); j=$(acc journald/gitea-mq); f=$(acc file_log/deploy-record)
  jl=$(ssh magnetite.zt "sudo journalctl -u gitea-mq.service --since '$T' -o cat --no-pager | grep -cE 'msg=\"batch (formed|built|landed|bisecting|done)\"' || true")
  echo "accepted since restart: sqlquery/ci_attribute=$a sqlquery/ci_build=$b journald/gitea-mq=$j (journal lines since restart $jl) file_log/deploy-record=$f"
  [ "$a" -lt 10000 ] && [ "$b" -lt 10000 ] && [ "$j" -le "$jl" ] && [ "$f" -eq 0 ] && echo "restart: PASS" || echo "restart: FAIL"
} 2>&1 | tee "$L"
```

Expected: `active`; after about three polls `sqlquery/ci_attribute` and `sqlquery/ci_build` accepted only the overlap rows of the last five minutes and any ties, well below one page of 10,000, where a lost cursor would have re-read the history from 1970 at 10,000 rows a poll; `journald/gitea-mq` at most the lines written since the restart; `file_log/deploy-record=0`; `restart: PASS`.
The counters restart at zero with the process, so their values are the post-restart reads, and each receiver resumed from the position its `file_storage` kept (WA `A47` for the cursor queries).

- [ ] **Step 19: 7.4 — `fleet` holds no log table**

Run:

```bash
L="$EV/7.4-fleet-logs-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "SELECT table_name FROM information_schema.tables WHERE table_schema = 'fleet' AND table_name IN ('opentelemetry_logs', 'ci_attribute', 'ci_build', 'batch_event', 'deploy_record')" | "$EV/gsql.sh" fleet | tee /tmp/s2-7.4-fleet.txt
  echo "SELECT count(*) FROM information_schema.tables WHERE table_schema = 'fleet'" | "$EV/gsql.sh" fleet
  [ "$(sed 1d /tmp/s2-7.4-fleet.txt | wc -l | tr -d ' ')" = 0 ] && echo "fleet logs: PASS" || echo "fleet logs: FAIL"
} 2>&1 | tee "$L"
```

Expected: the header `["table_name"]` and no row; the count of `fleet` tables recorded (388 base tables on 2026-10-21, `logs/s2/grounding.md` §3); `fleet logs: PASS`.
A log record routed to `fleet` would create `opentelemetry_logs` there, or a table under a header's name, so their absence shows the routing kept every row in `devloop`.

- [ ] **Step 20: 7.4 gate**

Run:

```bash
{
  n=0
  for p in 'backfill: PASS' 'exporters: PASS' 'grants: PASS' 'pg-grants: recorded' 'batch lines: PASS' 'keys: PASS' 'explain: recorded' 'tie: PASS' 'budget: recorded' 'restart: PASS' 'fleet logs: PASS'; do
    if rg -l -F "$p" "$EV"/7.4-*.log > /dev/null; then echo "found: $p"; n=$((n + 1)); else echo "missing: $p"; fi
  done
  [ "$n" -eq 11 ] && echo "ingest: PASS" && echo "7.4 passed: D4 may start"
} 2>&1 | tee "$EV/7.4-gate-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: eleven `found:` lines, `ingest: PASS`, then `7.4 passed: D4 may start`.
Task 4's 4.8 runs only after this line.

- [ ] **Step 21: 7.5 — a hand start passes for the previous day (after 4.8)**

Run after `s2-deploy.sh magnetite D4` printed `clan exit=0`:

```bash
L="$EV/7.5-hand-start-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ssh magnetite.zt 'systemctl show devloop-reconcile -p LoadCredential -p DynamicUser -p SupplementaryGroups -p MemoryMax -p OOMScoreAdjust -p Environment; systemctl list-timers devloop-reconcile.timer --all --no-pager'
  T=$(date -u +%FT%TZ)
  ssh magnetite.zt "sudo systemctl start devloop-reconcile.service; echo \"start exit=\$?\"; systemctl show devloop-reconcile -p Result -p ExecMainStatus; sudo journalctl -u devloop-reconcile --since '$T' -o cat --no-pager -q"
} 2>&1 | tee "$L"
```

Expected: `LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password`, `DynamicUser=yes`, `SupplementaryGroups=systemd-journal`, `MemoryMax=134217728`, `OOMScoreAdjust=600`, no `DEVLOOP_RECONCILE_DATABASE` in `Environment`; the timer's `NEXT` at the coming 02:15 UTC; `start exit=0`, `Result=success`, `ExecMainStatus=0`; the seven lines `devloop-reconcile: C1 attributes: ok` through `devloop-reconcile: C7 current-system: ok`, and a `Consumed … memory peak.` line.
Run soon after D4, C7 may find D4's own deploy record not yet shipped; the reconcile then retries the store read every 10 s for up to 120 s before failing (review F13), so the start can take up to two minutes longer, well inside `TimeoutStartSec=10min`.

- [ ] **Step 22: 7.5 — a forced failure posts one `FAILED` and one `failed.log` line**

Run:

```bash
L="$EV/7.5-forced-fail-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "T_FORCED_FAIL=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'bash -s' <<'REMOTE'
d=/run/systemd/system/devloop-reconcile.service.d
sudo mkdir -p "$d"
printf '[Service]\nEnvironment=DEVLOOP_RECONCILE_DATABASE=devloop_absent\n' | sudo tee "$d/zz-absent.conf"
sudo systemctl daemon-reload
systemctl show devloop-reconcile -p Environment -p DropInPaths
T=$(date -u +%FT%TZ)
sudo systemctl start devloop-reconcile.service; echo "start exit=$?"
systemctl show devloop-reconcile -p Result -p ExecMainStatus
sleep 20
sudo journalctl -u devloop-reconcile --since "$T" -o cat --no-pager -q
systemctl show 'observability-notify@devloop-reconcile.service.service' -p Result
echo "\$ tail -1 failed.log"; tail -n 1 /var/lib/observability-notify/failed.log
echo "\$ sudo cat stamp"; sudo cat /var/lib/observability-notify/devloop-reconcile.service
REMOTE
  source "$EV/window.env"
  sleep 5
  echo '$ polls.sh fleet-alerts' "$T_FORCED_FAIL"
  "$EV/polls.sh" fleet-alerts "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_FORCED_FAIL" +%s)"
} 2>&1 | tee "$L"
```

Expected:
- The drop-in's two lines echoed; `Environment=DEVLOOP_RECONCILE_DATABASE=devloop_absent` and `DropInPaths=` naming `/run/systemd/system/devloop-reconcile.service.d/zz-absent.conf`.
- `Job for devloop-reconcile.service failed …`, `start exit=1`, `Result=exit-code`, `ExecMainStatus=2`, the reconcile's exit for an unreadable store, because the store answers 400 for a database its schema job did not create (`modules/clan/services/otel-collector/flake-module.nix:446-447`); the journal shows the reconcile's message naming `devloop_absent` and no `: ok` line for a store clause.
- `Result=success` for the notifier instance; `failed.log`'s last line `<epoch> devloop-reconcile.service magnetite` with an epoch at or after `T_FORCED_FAIL`; stamp `posted`.
- Exactly one message `FAILED devloop-reconcile.service on magnetite` from the poll.
This is the reconcile's deploy-time negative control (design D11: a runtime drop-in forces the failure, as `greptimedb-envelope`'s thresholds do in S1 tasks.md 8.6); its comparisons' own fallibility is shown by `devloop-ingest` (A5:153).

- [ ] **Step 23: 7.5 — removing the drop-in and starting again posts the `RESOLVED`**

Run:

```bash
L="$EV/7.5-forced-resolve-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "T_FORCED_RESOLVE=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'bash -s' <<'REMOTE'
sudo rm /run/systemd/system/devloop-reconcile.service.d/zz-absent.conf
sudo rmdir /run/systemd/system/devloop-reconcile.service.d 2>/dev/null || true
sudo systemctl daemon-reload
systemctl show devloop-reconcile -p Environment -p DropInPaths
T=$(date -u +%FT%TZ)
sudo systemctl start devloop-reconcile.service; echo "start exit=$?"
systemctl show devloop-reconcile -p Result
sudo journalctl -u devloop-reconcile --since "$T" -o cat --no-pager -q
test ! -e /var/lib/observability-notify/devloop-reconcile.service && echo "stamp removed"
REMOTE
  source "$EV/window.env"
  sleep 5
  echo '$ polls.sh fleet-alerts' "$T_FORCED_FAIL"
  "$EV/polls.sh" fleet-alerts "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_FORCED_FAIL" +%s)"
} 2>&1 | tee "$L"
```

Expected: no `DEVLOOP_RECONCILE_DATABASE` in `Environment` and no `zz-absent.conf` in `DropInPaths`; `start exit=0`; `Result=success`; the seven `: ok` lines; `stamp removed`; the poll prints exactly two messages since `T_FORCED_FAIL`, `FAILED devloop-reconcile.service on magnetite` and, after it, `RESOLVED devloop-reconcile.service on magnetite`, posted by the unit's `ExecStartPost` hook (`modules/nixos/observability-notify.nix:7-9`, `:77`).

- [ ] **Step 24: 7.5 — the timer's first scheduled run passes; memory peak against 128M**

Run after the first 02:15 UTC following `D4_END`:

```bash
source "$EV/window.env"
t=${D4_END#*T}
if [[ "$t" < "02:15:00Z" ]]; then day=${D4_END%%T*}; else day=$(date -j -u -v+1d -f '%Y-%m-%dT%H:%M:%SZ' "$D4_END" +%F); fi
L="$EV/7.5-scheduled-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "first scheduled run day: $day"
  ssh magnetite.zt "systemctl list-timers devloop-reconcile.timer --all --no-pager; sudo journalctl -u devloop-reconcile --since '$day 02:14:00 UTC' --until '$day 02:40:00 UTC' -o short-iso --no-pager -q"
  echo '$ sudo journalctl -u devloop-reconcile -g "memory peak"'
  ssh magnetite.zt "sudo journalctl -u devloop-reconcile -g 'memory peak' --no-pager -q -o short-iso"
} 2>&1 | tee "$L"
```

Expected: the timer's `LAST` at `$day 02:15` UTC; in that window the journal's `Starting`, the seven `: ok` lines with `devloop-reconcile: C7 current-system: ok` last, the `Deactivated successfully` and `Consumed … memory peak.` lines, and no `FAIL`; the `memory peak` lines of every run so far, the scheduled run's peak recorded against 128M, with the design's expectation a wide margin (design D11, about 13,000 attribute keys a day, `[INFERENCE]` checked here).

- [ ] **Step 25: 7.5 — gitea-mq's journal reaches back more than two days; gate**

Run:

```bash
L="$EV/7.5-journal-retention-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ssh magnetite.zt 'bash -s' <<'REMOTE'
first=$(sudo journalctl -u gitea-mq.service -o short-unix --no-pager -q | head -n 1 | cut -d' ' -f1)
age=$(( $(date +%s) - ${first%.*} ))
echo "oldest gitea-mq.service entry: $(date -u -d "@${first%.*}" +%FT%TZ), age $((age / 86400)) days"
grep -E '^(SystemMaxUse|MaxRetentionSec)' /etc/systemd/journald.conf || echo "no SystemMaxUse or MaxRetentionSec set"
[ "$age" -gt 172800 ] && echo "journal retention: PASS" || echo "journal retention: FAIL"
REMOTE
  rg -l -F 'devloop-reconcile: C7 current-system: ok' "$EV"/7.5-scheduled-*.log \
    && rg -l -F 'FAILED devloop-reconcile.service on magnetite' "$EV"/7.5-forced-fail-*.log \
    && rg -l -F 'RESOLVED devloop-reconcile.service on magnetite' "$EV"/7.5-forced-resolve-*.log \
    && echo "7.5 passed: D5 may start"
} 2>&1 | tee "$L"
```

Expected: an oldest entry on or near 2026-09-16 (`logs/s2/grounding.md` §2.1) unless vacuumed since, aged well over two days; `no SystemMaxUse or MaxRetentionSec set`; `journal retention: PASS` (WA `A48`); three file names, then `7.5 passed: D5 may start`.
Task 5's 5.8 runs only after this line.

- [ ] **Step 26: 7.6 — the evaluator queries `fleet` and `devloop` as `regulator`; one run's queries timed (after 5.8)**

Run at least 5 minutes after `D5_END`, away from the hour (the envelope's run) and from 02:15 UTC (the reconcile's):

```bash
source "$EV/window.env"
L="$EV/7.6-evaluator-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ssh magnetite.zt 'bash -s' <<'REMOTE'
cfg=$(systemctl show fleet-alert -p Environment --value | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
echo "config $cfg"
jq -c '{user, storeUrl, topLevelDatabase: has("database"), rules: (.rules | length),
  byDatabase: (.rules | group_by(.database) | map({database: .[0].database, languages: (map(.language) | unique), n: length})),
  queriesPerRun: (([.rules[] | .presence[]? | .selector] | unique | length) + ([.rules[] | select(.expr != null and .window == null)] | length)),
  promqlPerRun: (([.rules[] | .presence[]? | .selector] | unique | length) + ([.rules[] | select(.expr != null and .window == null and .language == "promql")] | length)),
  sqlPerRun: ([.rules[] | select(.expr != null and .window == null and .language == "sql")] | length)}' "$cfg"
jq -c '.rules[] | select(.alert == "PullRequestQueueWaitBurn") | {alert, database, language, for, severity, presence}' "$cfg"
systemctl show fleet-alert -p Result -p LoadCredential
REMOTE
  ssh magnetite.zt "sudo journalctl -u fleet-alert --since '$D5_END' --no-pager -q -o cat | grep -cE 'Deactivated successfully|Finished'; sudo journalctl -u fleet-alert --since '$D5_END' -p warning --no-pager -q || true"
  echo '$ StoreQueryFailing posts since D5_START, per database named in the body'
  "$EV/polls.sh" fleet-alerts "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$D5_START" +%s)" | grep StoreQueryFailing || echo "no StoreQueryFailing post"
  echo '$ evaluator journal lines naming a failed database since D5_END'
  ssh magnetite.zt "sudo journalctl -u fleet-alert --since '$D5_END' --no-pager -q -o cat | grep -E 'did not answer queries on (fleet|devloop)' || echo 'no failed database'"
  echo '$ StoreQueryFailing instances in state.json'
  ssh magnetite.zt "sudo grep -o 'StoreQueryFailing[^}]*' /var/lib/fleet-alert/state.json || echo 'no StoreQueryFailing instance'"
  snap() { ssh magnetite.zt 'curl -s http://127.0.0.1:4000/metrics' | grep -E '^greptime_servers_http_requests_(total|elapsed_sum)\{' | grep -E 'db="(fleet|devloop)"' | grep -E 'path="/v1/(sql|prometheus/api/v1/query)"' | awk '{ print $1, $NF }' | LC_ALL=C sort -k1,1; }
  for w in 1 2 3; do
    snap > /tmp/s2-7.6-a.txt; sleep 60; snap > /tmp/s2-7.6-b.txt
    echo "window $w: store-side delta per series over 60 s (one timer run)"
    LC_ALL=C join -j1 /tmp/s2-7.6-a.txt /tmp/s2-7.6-b.txt | awk '{ printf "%s %.6f\n", $1, $3 - $2 }'
    ssh magnetite.zt 'systemctl show fleet-alert -p ExecMainStartTimestampMonotonic -p ExecMainExitTimestampMonotonic' \
      | awk -F= '{ v[$1] = $2 } END { printf "run wall time %.3f s\n", (v["ExecMainExitTimestampMonotonic"] - v["ExecMainStartTimestampMonotonic"]) / 1000000 }'
  done
} 2>&1 | tee "$L"
```

Expected:
- `"user":"regulator"`, `"storeUrl":"http://127.0.0.1:4000"`, `"topLevelDatabase":false`, `byDatabase` with `devloop` holding one rule in `["sql"]` and `fleet` the rest in `["promql"]`, and `queriesPerRun` 16, `promqlPerRun` 15 and `sqlPerRun` 1, computed from the delivered rule JSON as the unique presence selectors plus the expressions of rules not gated by a window (review F8: 9 unique selectors, 7 ungated expressions; `WeeklyPipelineTest` is skipped outside its window).
- `PullRequestQueueWaitBurn` with `"database":"devloop"`, `"language":"sql"`, `"for":3600`, `"severity":"warning"` and no presence selector.
- `Result=success` and `LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password` beside the alerter token; a count of successful runs since `D5_END` of one per minute; no warning-or-worse line; `no StoreQueryFailing post`, `no failed database` and `no StoreQueryFailing instance`: every run's `storeErrors` was `[]`.
- In each window, a `greptime_servers_http_requests_total` delta of exactly `sqlPerRun` (1) on `method="POST",path="/v1/sql",code="200",db="devloop"` and of exactly `promqlPerRun` (15) on `method="GET",path="/v1/prometheus/api/v1/query",code="200",db="fleet"`, and no non-200 series moving; the `elapsed_sum` deltas of those series summed give the store-side duration of the run's 16 queries, recorded with the run's wall time.
A memory rule that is firing adds its attribution queries, and a dashboard read adds `fleet` requests, so a window with a PromQL delta above 15 is discarded in favour of another; the step is not run on a Monday between 09:00 and 09:05 New York time, when `WeeklyPipelineTest`'s window adds its expression.
The evaluator logs nothing per successful query (`modules/nixos/fleet-alert.nix:113-133`), so the store's own request counters, labelled by path and database (`GreptimeTeam/greptimedb@v1.2.1:src/servers/src/metrics.rs:454-483`), are the observation that the run queried both databases on their paths, and the delivered configuration's `user` and `LoadCredential` that it did so as `regulator`.
The exact `path` label of the PromQL route is `[INFERENCE: axum's matched path of the nested route]`; the step prints whatever label the store uses.
Under review F7 a failed query ends only its own database's queries for the run, the run's observations list the failed databases in `storeErrors`, and each failing database gets its own `StoreQueryFailing` instance labelled `database`, posted as `[FIRING] StoreQueryFailing <db>` with a body naming the database too (`the store did not answer queries on <db>`) after 3 min; a `devloop` failure therefore leaves `fleet` rules evaluating, and if a post does appear here, its body names the database to examine, which is recorded.
The journal and body text `did not answer queries on <db>` is the wording of the F7 decision, `[INFERENCE]` until Task 5's `devloopFailureLeg` shows the evaluator's exact text, which this step's grep is then aligned with.

- [ ] **Step 27: 7.6 — the burn rule over past days, run by hand as `regulator`**

Run:

```bash
source "$EV/window.env"
L="$EV/7.6-burn-history-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  cfg=$(ssh magnetite.zt "systemctl show fleet-alert -p Environment --value" | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
  expr=$(ssh magnetite.zt "jq -r '.rules[] | select(.alert == \"PullRequestQueueWaitBurn\") | .expr' '$cfg'")
  echo "deployed expr: $expr"
  old="c.finished_at >= now() - INTERVAL '24 hours'"
  win() { new="c.finished_at >= CAST('$1' AS TIMESTAMP) - INTERVAL '24 hours' AND c.finished_at < CAST('$1' AS TIMESTAMP)"; echo "${expr/"$old"/"$new"}"; }
  [ "$(win X)" != "$expr" ] && echo "rewrite applies" || echo "rewrite DID NOT APPLY: stop"
  now=$(date -u +%FT%TZ)
  echo "control at $now: deployed expression, then rewritten with end=$now"
  echo "$expr" | "$EV/gsql.sh" devloop | sed 1d
  win "$now" | "$EV/gsql.sh" devloop | sed 1d
  d5=${D5_START%%T*}
  echo "seven days before D5 ($d5):"
  for i in 7 6 5 4 3 2 1; do
    end="$(date -j -u -v-${i}d -f '%Y-%m-%d' "$d5" +%F)T00:00:00Z"
    r=$(win "$end" | "$EV/gsql.sh" devloop | sed 1d)
    [ -n "$r" ] && echo "$end holds value=$(jq '.[0]' <<<"$r")" || echo "$end silent"
  done
  echo "design D1's 14 days (windows ending 00:00 UTC 2026-10-08 to 2026-10-22):"
  for dd in 08 09 10 11 12 13 14 15 16 17 18 19 20 21 22; do
    end="2026-10-${dd}T00:00:00Z"
    r=$(win "$end" | "$EV/gsql.sh" devloop | sed 1d)
    [ -n "$r" ] && echo "$end holds value=$(jq '.[0]' <<<"$r")" || echo "$end silent"
  done
  echo "design D1 expects rows for the days 2026-10-10, -14, -17, -21 (windows ending 2026-10-11, -15, -18, -22) and silence on the others (logs/s2/grounding.md §1.6)"
  echo "burn rule history: recorded"
} 2>&1 | tee "$L"
```

Expected:
- The deployed expression printed and `rewrite applies`.
- The control's two results identical, both empty or both the same one-row `[value]`, unless a pull-request build finished between the two reads: the rewrite with the present as its end is the deployed rule, so the rewrite moves only the window.
- Seven lines for the days before D5, each `holds value=<share>` or `silent`, recorded.
- Fifteen lines for design D1's period, with `holds` expected on the windows ending 2026-10-11 (4 of 23, 0.174), 2026-10-15 (11 of 43, 0.256), 2026-10-18 (5 of 24, 0.208) and 2026-10-22 (9 of 36, 0.25) and `silent` elsewhere; a day's share may differ slightly, because grounding grouped builds by `created_at` day and the rule windows `finished_at` `[INFERENCE]`, and any difference is recorded beside D1's expectation, not corrected.
- The shares count each build's first attempt only, as the deployed expression does through its join on `min(finished_at)` per `build_id` (review F1); the re-run of 2026-10-21 found 1 of 615 finished pull-request builds in 30 days settled twice and none of those slow (`logs/s2/burn-rule-reruns-<ts>.log`), so grounding's per-day shares stand as the expectation.
- `burn rule history: recorded`.
The rewrite replaces the one `now()` comparison with a window of the same 24 hours ending at a literal instant, adding the upper bound `c.finished_at < end`, without which rows finished after that day would count; everything else in the expression, including the first-attempt join, the `HAVING` minimum and the threshold, is the deployed text.
The join's subquery takes each build's earliest `finished_at` over all stored rows, so a build re-run after the literal end is still counted by its first attempt inside the window, as the live rule would have counted it on that day.
The backfill of 7.4 holds nixbot's builds since 2026-08-28, so both periods are covered.

- [ ] **Step 28: 7.7 — the reconcile passed every scheduled run since D4 and no `FAILED` was posted (at least seven days after D3)**

Run:

```bash
source "$EV/window.env"
L="$EV/7.7-reconcile-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  d3=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$D3_END" +%s); age=$(( ($(date +%s) - d3) / 86400 ))
  echo "days since D3_END: $age"
  t=${D4_END#*T}
  if [[ "$t" < "02:15:00Z" ]]; then day=${D4_END%%T*}; else day=$(date -j -u -v+1d -f '%Y-%m-%dT%H:%M:%SZ' "$D4_END" +%F); fi
  if [ "$(date -u +%H%M)" -ge 0240 ]; then last=$(date -u +%F); else last=$(date -j -u -v-1d +%F); fi
  ok=yes; runs=0; missed=""
  while [[ "$day" < "$last" || "$day" == "$last" ]]; do
    out=$(ssh magnetite.zt "sudo journalctl -u devloop-reconcile --since '$day 02:14:00 UTC' --until '$day 02:40:00 UTC' -o cat --no-pager -q")
    nok=$(grep -c ': ok$' <<<"$out" || true); nfail=$(grep -c ': FAIL' <<<"$out" || true)
    if [ "$nok" -eq 0 ] && [ "$nfail" -eq 0 ]; then
      covered=$(date -j -u -v-1d -f '%Y-%m-%d' "$day" +%F)
      echo "$day 02:15 run: none (magnetite down at 02:15?); day $covered needs a hand rerun"
      rerun=$(ls "$EV"/7.7-rerun-"$covered"-*.log 2>/dev/null | tail -n 1 || true)
      if [ -n "$rerun" ] && [ "$(grep -c ': ok$' "$rerun")" -eq 7 ] && ! grep -q ': FAIL' "$rerun"; then
        echo "  hand rerun of $covered: $rerun passed"
      else
        missed="$missed $covered"; ok=no
      fi
    else
      echo "$day 02:15 run: ok=$nok fail=$nfail"
      [ "$nok" -eq 7 ] && [ "$nfail" -eq 0 ] || ok=no
      runs=$((runs + 1))
    fi
    day=$(date -j -u -v+1d -f '%Y-%m-%d' "$day" +%F)
  done
  echo "days without a passing reconcile:${missed:- none}"
  echo '$ failed.log lines for devloop-reconcile.service'
  ssh magnetite.zt "awk '\$2 == \"devloop-reconcile.service\"' /var/lib/observability-notify/failed.log" | tee /tmp/s2-7.7-failed.txt
  ff=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_FORCED_FAIL" +%s); fr=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_FORCED_RESOLVE" +%s)
  outside=$(awk -v a="$ff" -v b="$fr" '$1 < a || $1 > b' /tmp/s2-7.7-failed.txt | wc -l | tr -d ' ')
  echo "scheduled runs checked: $runs; FAILED posts outside the forced failure: $outside"
  [ "$age" -ge 7 ] && [ "$runs" -ge 7 ] && [ "$ok" = yes ] && [ "$outside" = 0 ] && echo "reconcile: PASS" || echo "reconcile: FAIL"
} 2>&1 | tee "$L"
```

Expected: `days since D3_END` at least 7; one line per day from the first 02:15 after D4 to the last 02:15 that has finished, each `ok=7 fail=0`; `days without a passing reconcile: none`; exactly one `failed.log` line, the forced one between `T_FORCED_FAIL` and `T_FORCED_RESOLVE`; `FAILED posts outside the forced failure: 0`; `reconcile: PASS`.
`failed.log` gains a line for every posted `FAILED` (`modules/nixos/observability-notify.nix:39-41`) and is not rotated, so it covers the whole period, which ntfy's message cache need not.
Fewer than seven scheduled runs means waiting and rerunning this step.
The loop counts a day's 02:15 run only once it has finished: before 02:40 UTC today's run is left out and checked at the next rerun (review F22d).
A day whose 02:15 run is missing was one on which magnetite was down at 02:15; `Persistent=true` then catches up at boot but reconciles only the day before the boot, so the day named `needs a hand rerun` is reconciled by hand with a runtime drop-in, as Step 22 forces its failure, and the step is run again (review F13):

```bash
day=<YYYY-MM-DD named above>
ssh magnetite.zt "bash -s -- $day" <<'REMOTE' 2>&1 | tee "$EV/7.7-rerun-$day-$(date -u +%Y%m%dT%H%M%SZ).log"
d=/run/systemd/system/devloop-reconcile.service.d
sudo mkdir -p "$d"
printf '[Service]\nEnvironment=DEVLOOP_RECONCILE_DAY=%s\n' "$1" | sudo tee "$d/zz-day.conf"
sudo systemctl daemon-reload
T=$(date -u +%FT%TZ)
sudo systemctl start devloop-reconcile.service; echo "start exit=$?"
sudo journalctl -u devloop-reconcile --since "$T" -o cat --no-pager -q
sudo rm "$d/zz-day.conf"; sudo rmdir "$d" 2>/dev/null || true
sudo systemctl daemon-reload
REMOTE
```

Expected: `start exit=0` and the seven `: ok` lines for that day; a `FAIL` here is a gap the scheduled reconcile missed and is reported, not rerun.

- [ ] **Step 29: 7.7 — the three questions answer for the past week**

Run:

```bash
L="$EV/7.7-questions-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  ok=yes
  for q in formationToLand queueWait buildOutcome; do
    sql=$(nix eval --raw "git+file://$REPO?ref=main#.lib.devloopCollection.questions.$q")
    echo "=== $q"; echo "$sql"
    echo "$sql" | "$EV/gsql.sh" devloop | tee /tmp/s2-7.7-$q.txt
    n=$(sed 1d /tmp/s2-7.7-$q.txt | wc -l | tr -d ' '); echo "$q rows=$n"
    [ "$n" -gt 0 ] || ok=no
    grep -q '^HTTP ' /tmp/s2-7.7-$q.txt && ok=no
  done
  [ "$ok" = yes ] && echo "questions: PASS" || echo "questions: FAIL"
} 2>&1 | tee "$L"
```

Expected: each query's text, its column names and rows: `formationToLand` one row per batch formed and done in the past seven days with its interval, `queueWait` one row with the 50th, 90th and 99th percentiles of `started_at - created_at` over each build's first attempt (the row with the smallest `finished_at` per `build_id`, review F1), `buildOutcome` one row per build with its outcome; `rows=` above zero for each; `questions: PASS`.
The queries are rendered from the evaluated `flake.lib.devloopCollection.questions`, the values Task 6's runbook copies, and run on the store as `regulator`; their fixture answers are `devloop-ingest`'s documented-query case.

- [ ] **Step 30: 7.7 — D5's deploy record is one line and joins to the commit D5 deployed; acceptance**

Run:

```bash
source "$EV/window.env"
L="$EV/7.7-join-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "D5_COMMIT=$D5_COMMIT D5_START=$D5_START D5_END=$D5_END"
  ssh magnetite.zt "jq -c --arg s '$D5_START' --arg e '$D5_END' 'select(.ts >= \$s and .ts <= \$e)' /var/log/deploy-record.jsonl" | tee /tmp/s2-7.7-d5.txt
  n=$(wc -l < /tmp/s2-7.7-d5.txt | tr -d ' '); clo=$(jq -r .closure /tmp/s2-7.7-d5.txt)
  echo "D5 lines: $n closure: $clo"
  echo "SELECT host, closure, ts FROM deploy_record WHERE closure = '$clo'" | "$EV/gsql.sh" devloop
  echo "SELECT build_id, commit_sha, branch, pr_number, status, cached FROM ci_attribute WHERE attr = 'checks.x86_64-linux.nixos-magnetite' AND outputs_out = '$clo' AND status IN ('succeeded', 'skipped_local') ORDER BY finished_at" \
    | "$EV/gsql.sh" devloop | tee /tmp/s2-7.7-join.txt
  cd "$(git rev-parse --show-toplevel)"; git fetch -q origin
  want=$(git rev-parse "$D5_COMMIT^{tree}"); hit=no
  for sha in $(sed 1d /tmp/s2-7.7-join.txt | jq -r '.[1]'); do
    git cat-file -e "$sha^{commit}" 2>/dev/null || git fetch -q origin "$sha" 2>/dev/null || true
    tree=$(git rev-parse "$sha^{tree}" 2>/dev/null || echo unknown)
    echo "commit $sha tree $tree (D5 tree $want)"
    if [ "$sha" = "$D5_COMMIT" ] || [ "$tree" = "$want" ]; then hit=yes; fi
  done
  [ "$n" = 1 ] && [ "$hit" = yes ] && echo "join: PASS" || echo "join: FAIL"
  echo '$ fleet-alerts posts since D5_END, from the evaluator journal (ntfy publish responses on ntfy-send stdout)'
  ssh magnetite.zt "sudo journalctl -u fleet-alert --since '$D5_END' -o cat --no-pager -q" > /tmp/s2-7.7-fleet-alert.txt
  echo "first JSON line: $(grep -m1 '^{' /tmp/s2-7.7-fleet-alert.txt)"
  grep '^{' /tmp/s2-7.7-fleet-alert.txt | jq -s -c '[.[] | select(.event == "message" and .topic == "fleet-alerts")] | {
    firing_StoreQueryFailing: ([.[] | select(.title | startswith("[FIRING] StoreQueryFailing"))] | length),
    resolved_StoreQueryFailing: ([.[] | select(.title | startswith("[RESOLVED] StoreQueryFailing"))] | length),
    firing_PullRequestQueueWaitBurn: ([.[] | select(.title | startswith("[FIRING] PullRequestQueueWaitBurn"))] | length),
    resolved_PullRequestQueueWaitBurn: ([.[] | select(.title | startswith("[RESOLVED] PullRequestQueueWaitBurn"))] | length)}'
  echo "post failed lines: $(grep -c 'fleet-alert: post failed:' /tmp/s2-7.7-fleet-alert.txt || true)"
  echo '$ cross-check over the last 24 h: journal [FIRING] counts vs state.json .firings'
  now=$(date +%s)
  ssh magnetite.zt "sudo journalctl -u fleet-alert --since '@$((now - 86400))' -o cat --no-pager -q" | grep '^{' \
    | jq -s -c '[.[] | select(.event == "message" and .topic == "fleet-alerts" and (.title | startswith("[FIRING] ")))] | map(.title | sub("^\\[FIRING\\] "; "") | split(" ")[0]) | group_by(.) | map({(.[0]): length}) | add // {}' > /tmp/s2-7.7-j24.json
  ssh magnetite.zt "sudo jq -c --argjson now $now '[.firings[] | select(.at > \$now - 86400) | .alert] | group_by(.) | map({(.[0]): length}) | add // {}' /var/lib/fleet-alert/state.json" > /tmp/s2-7.7-s24.json
  echo "journal 24 h: $(cat /tmp/s2-7.7-j24.json)"; echo "state.json 24 h: $(cat /tmp/s2-7.7-s24.json)"
  for a in StoreQueryFailing PullRequestQueueWaitBurn; do
    [ "$(jq -r --arg a "$a" '.[$a] // 0' /tmp/s2-7.7-j24.json)" = "$(jq -r --arg a "$a" '.[$a] // 0' /tmp/s2-7.7-s24.json)" ] || { echo "24 h mismatch for $a"; hit=no; }
  done
  for p in 'reconcile: PASS' 'questions: PASS' 'join: PASS'; do rg -l -F "$p" "$EV"/7.7-*.log > /dev/null || { echo "missing: $p"; hit=no; }; done
  rg -l -F 'join: PASS' "$EV"/7.7-join-*.log > /dev/null && [ "$hit" = yes ] && echo "acceptance: PASS"
} 2>&1 | tee "$L"
```

Expected: one line with `ts` inside D5's window, `D5 lines: 1`, and its closure; one `deploy_record` row for that closure, shipped by `file_log/deploy-record`; at least one `ci_attribute` row for `checks.x86_64-linux.nixos-magnetite` with that `outputs_out`, the check being the machine's toplevel itself (`modules/checks/machines.nix:33-45`, `:72-74`); a `commit … tree …` line whose commit is `D5_COMMIT` or whose tree is `D5_COMMIT`'s; `join: PASS`; a `first JSON line` that is an ntfy message object with `"event":"message"`, `"topic"` and `"title"`; the four post counts since D5 recorded (review F22f), `firing_StoreQueryFailing` and `resolved_StoreQueryFailing` expected 0, and the `PullRequestQueueWaitBurn` counts a `FIRING` and a `RESOLVED` per episode on the days Step 27's method marks as holding; `post failed lines: 0`; the journal's and `state.json`'s 24 h counts equal for both alerts, with no `24 h mismatch` line; then `acceptance: PASS`.
The evaluator logs nothing of its own for a successful post, only `fleet-alert: post failed: <title>` on failure (`modules/nixos/fleet-alert.nix:257-262`); each post's evidence is ntfy's publish response, which `ntfy-send` prints on stdout because its `curl -sfk` has no `-o` (`pkgs/by-name/ntfy-send/ntfy-send.sh`), and the unit's stdout goes to the journal.
ntfy's publish handler answers with the published message as JSON (`binwiederhier/ntfy@v2.28.0:server/server.go:980-988`, `s.writeJSON(w, m.ForJSON())`); that the deployed server's response carries `title` as shown is `[INFERENCE]`, confirmed by this step's `first JSON line`.
`state.json`'s `.firings` gains `{at, alert, host}` for each non-`info` `FIRING` post (`modules/nixos/fleet-alert/transition.jq:190`) and keeps only the last 24 h (`:154`), so the cross-check covers the last 24 h only, two independent records of the same posts.
The closure comes from the snippet on magnetite and the output path from nixbot's build record, two independent sources whose equality is the attribution (DC `A deploy can be attributed to the commits that built it`).
The tree comparison is there because the merge queue lands a tree that a pull-request or batch build already built, so nixbot's row can carry that build's commit rather than the `main` commit D5 deployed, with the same tree.

- [ ] **Step 31: No commit**

This task changes no repository file.
Task 8 ticks 7.1 to 7.7 in `tasks.md` and folds this task's evidence and `window.env` into `verify.md`.

---

