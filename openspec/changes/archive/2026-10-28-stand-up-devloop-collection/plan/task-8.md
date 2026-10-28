### Task 8: Close-out and integration verification

Implements tasks.md 8.1–8.5 and 9.1 (design D1, D8, D9, D11, "Later slices"; spec requirements DCI `This capability states its own trust boundary`, FAI `This capability states its own trust boundary`, WA `Grounded vocabulary for behavioral requirements`, and through 9.1 DC `Every dev-loop event is recorded once and kept for a year`, DC `A deploy can be attributed to the commits that built it`, DC `A gap in the dev-loop history reaches a person within a day`, FA `Pull-request builds that wait too long to start reach a person as a warning`).

This task writes no code, so its RED-before-GREEN order is on its own judgements: each checking command runs first against the state that must fail it, then again once the artifact it judges exists.
The discharge check runs against `verify.md` as first rendered and lists every requirement name `tasks.md` discharges (RED), then prints nothing once §8b and §9 are filled (GREEN); the A43–A49 count prints `0` before the spec sync and `7` after; the satisfaction projection's title check fails against the current file with S2's 39 new titles and its one renamed title (RED), then passes on the regenerated file (GREEN); the sync-order check is run while its two sibling changes are still unarchived, which is the case that must stop it.
Step 2 is the one step of this task that runs before Task 7 ends: the orchestrator starts it when Task 5's pull request is opened, because the 10-minute arrival of pull request 5's last build can only be observed while that build finishes (S3 retrospective §6: a long-running capture runs on an always-on host, here magnetite).
All of it lands as one change and pull request 7; per `openspec-linear-sync`, the archive precedes the pull request.

**Files:**
- Create: `openspec/changes/stand-up-devloop-collection/verify.md`
- Create: `openspec/changes/stand-up-devloop-collection/review.md`
- Create: `openspec/changes/stand-up-devloop-collection/retrospective.md`
- Modify: `openspec/changes/stand-up-devloop-collection/tasks.md` (`:81-87` 7.1–7.7, `:91-95` 8.1–8.5, `:99` 9.1: the leading `- [ ]` only; a `## 10. Review follow-ups` section appended after `:99` only if Step 13 applies findings)
- Modify: `openspec/changes/stand-up-devloop-collection/proposal.md` (front matter `:1-14` only: `linear_story_state` `:6`, `last_synced_state` `:9`, `last_synced_at` `:10`, `review_round` `:11`, `attempt_log` `:13-14`)
- Modify (only if Step 4 finds a sibling change archived): `openspec/changes/stand-up-devloop-collection/specs/world-assumptions/spec.md` (the `Grounded vocabulary for behavioral requirements` table, `:95-272`)
- Create (by spec sync): `openspec/specs/devloop-collection/spec.md`, `openspec/specs/devloop-collection-interface/spec.md`
- Modify (by spec sync): `openspec/specs/fleet-alerting/spec.md`, `openspec/specs/fleet-alerting-interface/spec.md`, `openspec/specs/host-metrics-collection/spec.md`, `openspec/specs/telemetry-store-interface/spec.md`, `openspec/specs/world-assumptions/spec.md`
- Modify (Step 16, by hand): `openspec/specs/devloop-collection/spec.md` and `openspec/specs/devloop-collection-interface/spec.md` (the placeholder `## Purpose` body the archive writes)
- Rewrite wholesale (8.4): `packages/docs/src/content/docs/development/traceability/satisfaction.md` (all of `:1-457` today)
- Move (by archive): `openspec/changes/stand-up-devloop-collection/` → `openspec/changes/archive/<YYYY-MM-DD>-stand-up-devloop-collection/`
- Modify: `openspec/linear.yaml` (after `:96`, `projects."fleet-observability".archive_documents` gains `devloop-collection` and `devloop-collection-interface`)
- Create (git-ignored evidence): `logs/s2-evidence/9.1-arrival-watch.log`, `logs/s2-evidence/9.1-closed-record-<ts>.log`, `logs/s2-evidence/8.1-eval-cost-<ts>.log`, `logs/s2-evidence/8.3-sync-order-<ts>.log`, `logs/s2-evidence/8.4-satisfaction-<ts>.log`, `logs/s2-evidence/8.5-specs-<ts>.log`, `logs/s2-evidence/linear-doc-ids.txt`, and the `nix fmt` logs of Steps 12 and 21

**Interfaces:**
- Consumes (Task 7, confirmed by S2PlanT7): the logs `logs/s2-evidence/7.<n>-<slug>-<ts>.log`, which print `deploy record: PASS` (7.1), `boot record: PASS` or `boot record: not yet observed` (7.2, opportunistic, in `7.2-boot-record-<ts>.log` when it ran), `devloop tables: PASS` (7.3), `ingest: PASS` (7.4), `devloop-reconcile: C7 current-system: ok` and `FAILED devloop-reconcile.service on magnetite` (7.5), `burn rule history: recorded` (7.6) and `acceptance: PASS` (7.7); `logs/s2-evidence/window.env` holding `PRE_D1_SYSTEM`, `PRE_D1_LINES`, `D1_START` … `D5_END` (`date -u +%FT%TZ`), `D1_COMMIT` … `D5_COMMIT` (the full `origin/main` hash each deploy used), `T_BOOT` (only when a natural reboot was observed), `T_FORCED_FAIL`, `T_FORCED_RESOLVE`; the deploy procedure `logs/s2-evidence/s2-deploy.sh HOST LABEL` for any review follow-up redeploy.
- Consumes (Tasks 1–6): the evidence named in `tasks.md` and the plan (`1.1-plan-review-<ts>.md`, magnetite's normalised schema dump `1.2-schema-magnetite.norm.sql`, Task 2's schema diff `2.6-schema-diff-<ts>.log`, which decided lexical application, `2.7-precheck-<ts>.log`, `3.7-journal-assertion-<ts>.log`, `4.5-r31-<ts>.log`) and each task's `nix fmt`, evaluation-cost and container-test logs under `logs/s2-evidence/`; `flake.lib.devloopCollection.questions.formationToLand`; the reconcile's output lines `devloop-reconcile: C<n> <name>: ok` and `… FAIL <detail>` for `C1 attributes` … `C7 current-system`; `fleet-alert.service`'s configuration at `FLEET_ALERT_CONFIG`, whose `.rules[]` each carry `database` and `language` and which has no top-level `database` (Task 5); the evaluator's store-failure lines `fleet-alert: query failed:`, `fleet-alert: HTTP <code> for query:`, `fleet-alert: query deadline of` and `fleet-alert: the store did not answer; instances are frozen` (`modules/nixos/fleet-alert.nix:114`, `:126`, `:131`, `:266` today).
- Consumes (Linear and OpenSpec): CAM-69 in team `CAM`, project `fleet-observability` (slugId `aeed302bea3b`), workspace `cameronraysmith`; proposal.md's ledger (`linear_story_state` advanced to `In Progress` by Task 1's first tick); stored document ids in `openspec/linear.yaml:85-96`: `host-metrics-collection` `5a3a3fc0-fe9b-46dc-97c5-908743914066`, `telemetry-store-interface` `1b158db4-f5e8-42bb-b733-81fd9aa9fb38`, `fleet-alerting` `a14e48d5-3c08-4ac4-994e-c23a5439ff18`, `fleet-alerting-interface` `ee21d4e7-237f-4778-9bb4-2826a87332ab`, and the shared `world-assumptions` mirror `a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1` (registered under `pyrite-baremetal-nixos`, `openspec/linear.yaml:59-66`; S3 plan Task 8 Step 16).
- Produces: `verify.md` with the schema's §1–§8 and an evidence ledger §9–§10; `review.md`; `retrospective.md`; seven synced main specs, two of them new with a written Purpose; the regenerated satisfaction projection; the archived change; Linear documents `OpenSpec: devloop-collection` and `OpenSpec: devloop-collection-interface` created in `fleet-observability` and five existing documents updated; CAM-69 in `Done`.

- [ ] **Step 1: Confirm Task 7's evidence (gate)**

Run from `$REPO`, at least seven days after `D3_END` and after 7.7 has run:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s2-evidence"
ls "$EV"
for p in '7.1:deploy record: PASS' '7.3:devloop tables: PASS' '7.4:ingest: PASS' \
         '7.5:devloop-reconcile: C7 current-system: ok' '7.5:FAILED devloop-reconcile.service on magnetite' \
         '7.6:burn rule history: recorded' '7.7:acceptance: PASS'; do
  n=${p%%:*}; s=${p#*:}
  printf '%s %s: %s\n' "$n" "$s" "$(rg -l -F "$s" "$EV"/"$n"-*.log 2>/dev/null | wc -l | tr -d ' ')"
done
echo "7.2: $(rg -h -o -e 'boot record: PASS' -e 'boot record: not yet observed' "$EV"/7.2-boot-record-*.log 2>/dev/null | tail -n 1 || true)"
ls "$EV"/1.1-plan-review-*.md "$EV"/1.2-schema-magnetite.norm.sql "$EV"/2.6-schema-diff-*.log "$EV"/3.7-journal-assertion-*.log "$EV"/4.5-r31-*.log
source "$EV/window.env"
for v in PRE_D1_SYSTEM D1_START D1_END D2_START D2_END D3_START D3_END D4_START D4_END D5_START D5_END D5_COMMIT T_FORCED_FAIL T_FORCED_RESOLVE; do
  printf '%s=%s\n' "$v" "${!v:-MISSING}"
done
echo "T_BOOT=${T_BOOT:-none}"
```

Expected: every count at least `1`; the five `ls` paths exist; no `MISSING`; `7.2:` followed by `boot record: PASS` and a `T_BOOT` time, or by `boot record: not yet observed` (or nothing, when no 7.2 log exists) and `T_BOOT=none`.
7.2 is opportunistic and gates nothing: it records the boot line at magnetite's next natural reboot after D1, and when none has occurred by close-out, `verify.md` §9.4 records `not yet observed` (Step 8).
A zero count or a missing file means its Task 7 or earlier step has not run or failed: stop, and run that step first.

- [ ] **Step 2: 9.1 — start the arrival watch on magnetite when Task 5's pull request opens**

The orchestrator runs this step right after Task 5's pull request is opened (5.7), before nixbot's first build of it finishes, and leaves it running until Step 3.
Its two value sources are nixbot's `builds.finished_at` and the attribute count, read as `postgres` from nixbot's database, and the rows `devloop` holds for the same `build_id`, read as `regulator`; the watch samples both every 30 s, so a build's arrival time is known to within 30 s.
Run:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s2-evidence"
PR5=$(gh pr list --repo cameronraysmith/vanixiets --state open --json number,files \
  --jq '[.[] | select(any(.files[]; .path == "modules/nixos/fleet-alert/rules.nix"))][0].number')
echo "PR5=$PR5" | tee -a "$EV/window.env"
ssh magnetite.zt 'sudo tee /var/lib/devloop-arrival-watch.sh >/dev/null' <<'EOF'
#!/run/current-system/sw/bin/bash
# Every 30 s, one line per finished nixbot build of pull request $PR:
# <now> <build_id> <nixbot finished_at epoch> <nixbot finished attrs> <ci_build rows> <ci_attribute rows>
set -u
pw=$(cat "$CREDENTIALS_DIRECTORY/regulator-password")
out=$STATE_DIRECTORY/watch.log
gcount() {
  printf 'user = "regulator:%s"\n' "$pw" \
    | curl -sS --max-time 10 -K - --data-urlencode "sql=$1" 'http://127.0.0.1:4000/v1/sql?db=devloop' \
    | jq -r '.output[0].records.rows[0][0] // "ERR"' 2>/dev/null || echo ERR
}
while :; do
  now=$(date -u +%s)
  psql -XAt -F ' ' -d nixbot -c "SELECT b.id, extract(epoch FROM b.finished_at)::bigint, count(DISTINCT a.attr) FILTER (WHERE a.finished_at IS NOT NULL) FROM builds b JOIN projects p ON p.id = b.project_id LEFT JOIN build_attributes a ON a.build_id = b.id WHERE p.owner = 'cameronraysmith' AND p.name = 'vanixiets' AND b.pr_number = $PR AND b.finished_at IS NOT NULL GROUP BY b.id, b.finished_at ORDER BY b.id" \
  | while read -r id fin nattr; do
      echo "$now $id $fin $nattr $(gcount "SELECT count(*) FROM ci_build WHERE build_id = $id") $(gcount "SELECT count(*) FROM ci_attribute WHERE build_id = $id")"
    done >> "$out"
  sleep 30
done
EOF
ssh magnetite.zt "sudo systemd-run --unit=devloop-arrival-watch -p User=postgres -p StateDirectory=devloop-arrival-watch \
  -p LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password \
  --setenv=PATH=/run/current-system/sw/bin --setenv=PR=$PR5 /run/current-system/sw/bin/bash /var/lib/devloop-arrival-watch.sh"
sleep 90
ssh magnetite.zt 'systemctl is-active devloop-arrival-watch; sudo tail -n 3 /var/lib/devloop-arrival-watch/watch.log'
```

Expected: `PR5=<number>` of Task 5's pull request (the only open one changing `modules/nixos/fleet-alert/rules.nix`); `active`; and, once nixbot has finished a build of it, lines of six fields with no `ERR`.
The password reaches curl on stdin through `--config -`, never as an argument, as `modules/lib/greptimedb-envelope.nix` does; the watch runs as `postgres` so it reads nixbot's tables by peer without touching the collector's or the reconcile's grants.
`psql`, `curl` and `jq` are on magnetite's system path (`logs/s2/grounding.md:14`; S3 plan Task 8 Step 2 ran `jq` there) [INFERENCE for `curl` under the transient unit's `PATH`; the first log lines confirm it].
A push to the pull request after this step starts is watched too; a build that finished before the watch started has no arrival time, and Step 3 rejects it.

- [ ] **Step 3: 9.1 — the closed dev-loop record**

Run after Step 1, at least seven scheduled `devloop-reconcile` runs after `D4_END`, from `$REPO`:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s2-evidence"
source "$EV/window.env"
ep() { date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$1" +%s; }
gsql() {
  ssh magnetite.zt 'sql=$(cat); printf "user = \"regulator:%s\"\n" "$(sudo cat /run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password)" | curl -sS --max-time 30 -K - --data-urlencode "sql=$sql" "http://127.0.0.1:4000/v1/sql?db=devloop"' <<< "$1" \
    | jq -c '.output[0].records.rows'
}
git fetch -q origin
{
  echo '## 10.1 pull request 5: last build and attributes within 10 minutes'
  ssh magnetite.zt 'sudo systemctl stop devloop-arrival-watch; sudo cat /var/lib/devloop-arrival-watch/watch.log' > "$EV/9.1-arrival-watch.log"
  gh pr view "$PR5" --repo cameronraysmith/vanixiets --json number,state,mergedAt --jq '"PR \(.number) \(.state) \(.mergedAt)"'
  SHA5=$(git log --reverse --format=%H -S PullRequestQueueWaitBurn origin/main -- modules/nixos/fleet-alert/rules.nix | head -n1)
  echo "SHA5=$SHA5 (first origin/main commit adding PullRequestQueueWaitBurn)"
  read -r LAST FIN <<< "$(awk '{print $2, $3}' "$EV/9.1-arrival-watch.log" | sort -u -k2,2n | tail -n1)"
  NATTR=$(awk -v id="$LAST" '$2 == id && $4 > m {m = $4} END {print m}' "$EV/9.1-arrival-watch.log")
  SEEN=$(awk -v id="$LAST" '$2 == id {print $1; exit}' "$EV/9.1-arrival-watch.log")
  TB=$(awk -v id="$LAST" '$2 == id && $5 >= 1 {print $1; exit}' "$EV/9.1-arrival-watch.log")
  TA=$(awk -v id="$LAST" -v n="$NATTR" '$2 == id && $6 == n {print $1; exit}' "$EV/9.1-arrival-watch.log")
  echo "last build $LAST finished_at=$(date -u -r "$FIN" +%FT%TZ) attrs=$NATTR first watched +$((SEEN - FIN))s ci_build +$((TB - FIN))s ci_attribute complete +$((TA - FIN))s"
  [ $((SEEN - FIN)) -le 60 ] && [ $((TB - FIN)) -le 600 ] && [ $((TA - FIN)) -le 600 ] \
    && echo "PASS: 9.1 arrival within 10 minutes" || echo "FAIL: 9.1 arrival"
  gsql "SELECT build_id, \"status\", pr_number, to_unixtime(finished_at) FROM ci_build WHERE build_id = $LAST"
  gsql "SELECT count(*) FROM ci_attribute WHERE build_id = $LAST"

  echo '## 10.2 its batch and formation-to-land'
  B=''
  while read -r b sha; do
    if git merge-base --is-ancestor "$SHA5" "$sha" 2>/dev/null; then B=$b; echo "batch $b landed $sha, which contains $SHA5"; break; fi
  done < <(gsql "SELECT batch, sha FROM batch_event WHERE msg = 'batch landed' ORDER BY ts" | jq -r '.[] | "\(.[0]) \(.[1])"')
  gsql "SELECT msg, to_unixtime(ts), members, landed, ejected, builds, flaky FROM batch_event WHERE batch = $B ORDER BY ts" | jq -c '.[]'
  F=$(gsql "SELECT to_unixtime(ts) FROM batch_event WHERE batch = $B AND msg = 'batch formed'" | jq '.[0][0]')
  D=$(gsql "SELECT to_unixtime(ts) FROM batch_event WHERE batch = $B AND msg = 'batch done'" | jq '.[0][0]')
  echo "formation-to-land of batch $B: $((D - F)) s"
  git worktree add -q --detach /tmp/wt-s2-close origin/main
  Q=$(cd /tmp/wt-s2-close && nix eval --raw .#.lib.devloopCollection.questions.formationToLand)
  git worktree remove /tmp/wt-s2-close
  if [ $(( $(date -u +%s) - D )) -lt 604800 ]; then
    gsql "$Q" | jq -c --argjson b "$B" '.[] | select(index($b) != null)'
  else
    echo "batch $B is older than the question's 7-day window; 7.7 recorded the question's answers"
  fi

  echo '## 10.3 D5 deploy record joined to its commit'
  rows=$(gsql "SELECT host, closure, previous_closure, to_unixtime(ts) FROM deploy_record WHERE host = 'magnetite' AND to_unixtime(ts) BETWEEN $(ep "$D5_START") AND $(ep "$D5_END")")
  echo "$rows" | jq -c '.[]'
  echo "D5 deploy-record rows: $(jq length <<< "$rows")"
  CLOSURE=$(jq -r '.[0][1]' <<< "$rows")
  gsql "SELECT DISTINCT commit_sha, branch, build_id FROM ci_attribute WHERE attr = 'checks.x86_64-linux.nixos-magnetite' AND \"status\" IN ('succeeded', 'skipped_local') AND outputs_out = '$CLOSURE'" | jq -c '.[]' | tee /tmp/s2-d5-join.txt
  grep -q "\"$D5_COMMIT\"" /tmp/s2-d5-join.txt && echo "D5_COMMIT $D5_COMMIT joins the D5 closure" || echo "FAIL: D5_COMMIT not among the joined commits"
  git merge-base --is-ancestor "$SHA5" "$D5_COMMIT" && echo "D5_COMMIT contains pull request 5 ($SHA5)" || echo "FAIL: D5_COMMIT lacks $SHA5"

  echo '## 10.4 seven consecutive scheduled devloop-reconcile passes'
  ssh magnetite.zt "sudo journalctl -u devloop-reconcile.service --since @$(ep "$D4_END") -o json --no-pager" > "$EV/9.1-reconcile-journal.json"
  jq -s -r '
    group_by(._SYSTEMD_INVOCATION_ID // .INVOCATION_ID // "")
    | map(select((.[0]._SYSTEMD_INVOCATION_ID // .[0].INVOCATION_ID // "") != ""))
    | map({start: ((map(.__REALTIME_TIMESTAMP | tonumber) | min) / 1000000 | floor),
           ok: ([.[] | (.MESSAGE // "") | strings | select(test("^devloop-reconcile: C[1-7] [a-z-]+: ok$"))] | length),
           fail: ([.[] | (.MESSAGE // "") | strings | select(test("^devloop-reconcile: C[1-7] [a-z-]+: FAIL"))] | length),
           result: ([.[] | select(.JOB_TYPE == "start") | .JOB_RESULT] | last)})
    | sort_by(.start)[]
    | "\(.start | todate) ok=\(.ok) fail=\(.fail) result=\(.result)"' "$EV/9.1-reconcile-journal.json" | tee /tmp/s2-reconcile-runs.txt
  grep -E 'T02:1[56]:' /tmp/s2-reconcile-runs.txt > /tmp/s2-scheduled.txt
  echo "scheduled runs since D4: $(wc -l < /tmp/s2-scheduled.txt); passing: $(grep -c 'ok=7 fail=0 result=done' /tmp/s2-scheduled.txt)"
  tail -n 7 /tmp/s2-scheduled.txt | cut -c1-10 > /tmp/s2-days.txt
  first=$(head -n1 /tmp/s2-days.txt)
  for i in 0 1 2 3 4 5 6; do date -j -u -v+"${i}"d -f %F "$first" +%F; done | diff - /tmp/s2-days.txt \
    && [ "$(tail -n 7 /tmp/s2-scheduled.txt | grep -c 'ok=7 fail=0 result=done')" -eq 7 ] \
    && echo "PASS: seven consecutive scheduled passes" || echo "FAIL: seven consecutive scheduled passes"
  echo "FAILED devloop-reconcile lines in failed.log since D4: $(ssh magnetite.zt "awk -v t=$(ep "$D4_END") '\$1 > t && \$2 == \"devloop-reconcile.service\"' /var/lib/observability-notify/failed.log | wc -l")"

  echo '## 10.5 the burn rule on devloop every minute, no StoreQueryFailing since D5'
  ssh magnetite.zt 'cfg=$(systemctl show -p Environment --value fleet-alert.service | tr " " "\n" | sed -n "s/^FLEET_ALERT_CONFIG=//p"); jq -c ".rules[] | select(.alert == \"PullRequestQueueWaitBurn\") | {alert, database, language, for}" "$cfg"; jq -c "{topLevelDatabase: has(\"database\")}" "$cfg"'
  ssh magnetite.zt "sudo journalctl -u fleet-alert.service --since @$(ep "$D5_END") -o json --no-pager" \
    | jq -s -r --argjson d5 "$(ep "$D5_END")" '
        [.[] | select(.JOB_TYPE == "start") | {t: ((.__REALTIME_TIMESTAMP | tonumber) / 1000000 | floor), r: .JOB_RESULT}] as $runs
        | ($runs | map(.t)) as $ts
        | "runs=\($runs | length) done=\([$runs[] | select(.r == "done")] | length) first=+\(($ts | min) - $d5)s maxgap=\([range(1; $ts | length) as $i | $ts[$i] - $ts[$i - 1]] | max)s minutes=\(((now | floor) - $d5) / 60 | floor)"'
  echo "store-failure lines since D5: $(ssh magnetite.zt "sudo journalctl -u fleet-alert.service --since @$(ep "$D5_END") -o cat --no-pager" | grep -cE 'fleet-alert: (query failed|HTTP [0-9]+ for query|query deadline of|the store did not answer)')"
} 2>&1 | tee "$EV/9.1-closed-record-$(date -u +%Y%m%dT%H%M%SZ).log"
ssh magnetite.zt 'sudo rm -r /var/lib/devloop-arrival-watch.sh /var/lib/devloop-arrival-watch'
```

Expected:
- 10.1: `PR <PR5> MERGED <time>`; `PASS: 9.1 arrival within 10 minutes`; one `ci_build` row for `LAST` with `pr_number` equal to `PR5`; the `ci_attribute` count equal to `attrs=`.
- 10.2: one `batch <B> landed <sha>` line; that batch's rows include exactly one `batch formed` and one `batch done`, and a `batch done` with `landed` at least 1; a positive formation-to-land; the question's row for `B`, or the out-of-window line.
- 10.3: `D5 deploy-record rows: 1`; at least one joined commit; `D5_COMMIT … joins the D5 closure`; `D5_COMMIT contains pull request 5`.
- 10.4: every scheduled line `ok=7 fail=0 result=done`, at least seven of them; `PASS: seven consecutive scheduled passes`; `FAILED devloop-reconcile lines in failed.log since D4: 0`.
- 10.5: `{"alert":"PullRequestQueueWaitBurn","database":"devloop","language":"sql","for":3600}` and `{"topLevelDatabase":false}`; `runs` equal to `done`, `first` at most `+120s`, `maxgap` at most `120s`, and `runs` within two of `minutes`; `store-failure lines since D5: 0`.

The two sources compared in 10.1 are nixbot's `finished_at` and the watch's first sight of the row in `devloop`; in 10.3 the store's `deploy_record.closure` and nixbot's `outputs_out` of the `nixos-magnetite` check, whose output is the system toplevel (`modules/checks/machines.nix:72-74`), joined to the commit `s2-deploy.sh` recorded as `D5_COMMIT`.
`"status"` is quoted because `status` is a reserved word in GreptimeDB's parser (Global Constraints); `succeeded` and `skipped_local` are the passing attribute statuses nixbot writes (`logs/s2/grounding.md:126`).
`to_unixtime` returns seconds for a timestamp column (`GreptimeTeam/greptimedb@v1.2.1:src/common/function/src/scalars/timestamp/to_unixtime.rs:30`, `:57`).
`StoreQueryFailing` is raised only from an observation with `storeError` set (`modules/nixos/fleet-alert/transition.jq:69-70`), and every store failure prints one of the four lines counted (`modules/nixos/fleet-alert.nix:114`, `:126`, `:131`, `:266`) [INFERENCE that Task 5's SQL path keeps those lines, since 5.4 ends a failed SQL query the way a PromQL one ends; the zero count with 7.6's recorded SQL runs confirms the path ran]; every rule with an `expr` is evaluated on each run (`transition.jq:72-74`), so a successful run every minute is the burn rule evaluated every minute.
The scheduled runs are the ones starting at 02:15 or 02:16 UTC (`OnCalendar = "*-*-* 02:15:00 UTC"` with the default one-minute `AccuracySec`); 7.5's hand starts fall outside that minute and are not counted.
`JOB_TYPE` and `JOB_RESULT` are the fields systemd sets on a job's completion entry [INFERENCE; `result=done` in the output confirms it].
Any `FAIL` line means 9.1 fails: record it in `verify.md` §10 and check `(fail) FAIL` in Step 8.

- [ ] **Step 4: 8.3 — the sync-order stop check**

Run:

```bash
{
  export LC_ALL=C
  rows() { awk '/^### Requirement: Grounded vocabulary for behavioral requirements/{f=1;next} f&&/^### Requirement/{exit} f&&/^\|/' "$1" | sort -u; }
  key() { awk -F'|' '{gsub(/^ +| +$/, "", $2); gsub(/^ +| +$/, "", $3); print $2 "|" $3}' | sort -u; }
  MAIN=openspec/specs/world-assumptions/spec.md
  S2=openspec/changes/stand-up-devloop-collection/specs/world-assumptions/spec.md
  for ch in stand-up-gitea-mq-on-magnetite stand-up-nixbot-on-magnetite; do
    echo "\$ ls -d openspec/changes/archive/*-$ch"; ls -d openspec/changes/archive/*-"$ch" 2>/dev/null || echo "$ch: not archived"
  done
  echo "main rows: $(rows $MAIN | wc -l)  S2 delta rows: $(rows $S2 | wc -l)"
  echo '# main rows missing from the S2 delta (S2 must carry every one)'; comm -23 <(rows $MAIN) <(rows $S2)
  for ch in stand-up-gitea-mq-on-magnetite stand-up-nixbot-on-magnetite; do
    D=openspec/changes/$ch/specs/world-assumptions/spec.md
    [ -f "$D" ] || continue
    echo "$ch delta rows: $(rows $D | wc -l)"
    echo "# main rows missing from the $ch delta: $(comm -23 <(rows $MAIN) <(rows $D) | wc -l)"
    echo "# term|sense pairs both S2 and $ch add to main:"
    comm -12 <(comm -13 <(rows $MAIN) <(rows $S2) | key) <(comm -13 <(rows $MAIN) <(rows $D) | key) | grep -v '^Term|Sense$' || true
  done
} 2>&1 | tee "$EV/8.3-sync-order-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected on 2026-10-21 (read then): both `not archived`; `main rows: 143  S2 delta rows: 178`; an empty list under `main rows missing from the S2 delta`; `stand-up-gitea-mq-on-magnetite delta rows: 65`, `main rows missing … 100`, and the pairs `batch|—`, `merge queue|—`, `pull request|—`; `stand-up-nixbot-on-magnetite delta rows: 56`, `main rows missing … 88`, and no pair.
The row counts include each table's header and separator line, as S3's check did; `LC_ALL=C` keeps `sort` and `comm` in one collation.
The decision for each case:
- A sibling `not archived` and its missing count non-zero (the expected case): STOP before Step 16's sync.
  Tell the operator in one message that this sibling's `world-assumptions` delta MODIFIES `Grounded vocabulary for behavioral requirements` from a copy that predates S1's, S3's and CAM-77's syncs and would delete those main rows and S2's 35 new rows if it synced after S2; that `stand-up-gitea-mq-on-magnetite` also adds `batch`, `merge queue` and `pull request` under the same term and sense as S2 with different text; and that S2 archives first only if the operator confirms that each sibling will rebuild its block on S2's synced main, deciding then which text each of those three terms keeps or splitting it into two senses, before its own sync.
  Record the operator's answer in `verify.md` §10.6 and proceed only on that confirmation.
- A sibling `not archived` and its missing count `0`: it has been rebased; S2 syncs first and the sibling rebuilds on S2's synced main; any listed term|sense pair is the sibling's to resolve then; record it.
- A sibling archived: every synced main row must be in the S2 delta; for each line under `main rows missing from the S2 delta`, add that row to the S2 delta's table (`:95-272` today) with the edit tool at the place of its term, unless S2 deliberately rewrote the same term and sense (an S2 row beginning with the same `| term | sense |`); for a listed term|sense pair whose two texts differ, stop and ask the operator which text stands, because the two rows state one term and sense differently; rerun this step until the missing list is empty; record it.
In every case the list `main rows missing from the S2 delta` must end empty before the sync.

- [ ] **Step 5: Run the verify precheck**

Run:

```bash
tasks_file=$(openspec status --change stand-up-devloop-collection --json | jq -r '.artifactPaths.tasks.existingOutputPaths[0] // empty')
[ -n "$tasks_file" ] && grep -c '^- \[x\]' "$tasks_file"
git log --oneline origin/main -- modules/system/deploy-record.nix modules/checks/machines.nix modules/nixos/devloop-collection.nix modules/checks/devloop-queries.nix modules/checks/devloop-queries modules/clan/services/otel-collector modules/nixos/greptimedb.nix modules/checks/otel-collector-config.nix modules/vm-tests/devloop-ingest.nix modules/vm-tests/devloop-ingest modules/nixos/fleet-alert.nix modules/nixos/fleet-alert modules/checks/fleet-alert.nix modules/checks/fleet-alert modules/machines/nixos/magnetite/default.nix packages/docs/src/content/docs/development/operations/fleet-observability.md modules/README.md
```

Expected: the number of items Tasks 1–6 ticked (`48`, items 1.1–6.5); pull requests 1–6 on `origin/main`, which are the implementation evidence, and any review follow-up already landed.

- [ ] **Step 6: Create the change**

Run:

```bash
jj new --no-edit -r main@origin -m 'docs(observability): verify and archive S2 dev-loop collection'
```

Expected: `Created new commit <change-id> ...`; note it as `VERIFY`.
The orchestrator adds `VERIFY` to the development join.

- [ ] **Step 7: Re-measure each S2 check's evaluation cost at `origin/main`**

Run:

```bash
git fetch -q origin
git worktree add -q --detach /tmp/wt-s2-cost origin/main
{
  echo "origin/main: $(git -C /tmp/wt-s2-cost log --oneline -1)"
  for c in devloop-queries otel-collector-config fleet-alert; do
    rm -f "/tmp/$c-stats.json"
    (cd /tmp/wt-s2-cost && NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="/tmp/$c-stats.json" nix eval --option eval-cache false --raw ".#.checks.x86_64-linux.$c.drvPath")
    echo
    jq -r --arg c "$c" '"\($c) gc.totalBytes=\(.gc.totalBytes) cpuTime=\(.cpuTime) under 0.5 GiB: \(.gc.totalBytes < 536870912)"' "/tmp/$c-stats.json"
  done
  echo 'method: NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/<c>-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.<c>.drvPath, at the origin/main above'
} 2>&1 | tee "$EV/8.1-eval-cost-$(date -u +%Y%m%dT%H%M%SZ).log"
git worktree remove /tmp/wt-s2-cost
```

Expected: three `drvPath`s, each followed by a line ending `under 0.5 GiB: true`, and the method line.
A `false` is a finding for §9.1 and the retrospective, not a reason to stop; the figures recorded by Tasks 1–5 stand beside these.

- [ ] **Step 8: Write `verify.md` (8.1), discharge check RED then GREEN**

Invoke `openspec-verify-change` for `stand-up-devloop-collection`; it renders the template from `openspec instructions verify --change stand-up-devloop-collection --json`.
Append after §8, before `## Overall Decision`:

```markdown
## 9. Deployment record

Sections 9 and 10 are the evidence ledger that `tasks.md` 7.1–7.7 and 9.1 require this file to hold.
`[operator]` marks an observation only the operator could make; every other entry gives the command and its output.

### 9.1 Evaluation cost of each new or changed check
<!-- 8.1-eval-cost; each Task 1-5 NIX_SHOW_STATS figure for devloop-queries, otel-collector-config and fleet-alert, one line per check: check, drvPath, gc.totalBytes, cpuTime, against 0.5 GiB, with the method -->

### 9.2 Planning-time evidence and the schema baseline (tasks.md 1.1, 1.2, 2.6)
<!-- 1.1-plan-review (findings and dispositions); 1.2's read-only magnetite dump (sha256 of 1.2-schema-magnetite.norm.sql); 2.6-schema-diff (the diff against devloop-queries' schema and the lexical-application decision it made) -->

### 9.3 D1 and the deploy record (tasks.md 1.7, 7.1)
<!-- 7.1-* (deploy record: PASS), queue-D1 and the tail of the D1 deploy log -->

### 9.4 The boot record, opportunistic (tasks.md 7.2)
<!-- 7.2-boot-record (boot record: PASS, with T_BOOT and the appended line) if magnetite rebooted naturally after D1; otherwise the single line "not yet observed: magnetite has not rebooted since D1 (uptime -s <time>)", which gates nothing -->

### 9.5 D2 and the devloop tables (tasks.md 2.7, 2.9, 7.3)
<!-- 2.7-precheck (the pre-D2 compile check on a throwaway store), 7.3-* (devloop tables: PASS), queue-D2 and the tail of the D2 deploy log -->

### 9.6 D3 and ingest (tasks.md 3.11, 7.4)
<!-- 7.4-* (ingest: PASS), the backfill's one exceedance of ADR-004's 100,000 rows a day, queue-D3 and the tail of the D3 deploy log -->

### 9.7 D4 and devloop-reconcile (tasks.md 4.8, 7.5)
<!-- 7.5-* (the passing hand start, FAILED devloop-reconcile.service on magnetite and its RESOLVED with T_FORCED_FAIL and T_FORCED_RESOLVE, the timer's first run and its memory peak against 128M, the oldest gitea-mq journal entry), queue-D4 and the tail of the D4 deploy log -->

### 9.8 D5 and the burn rule (tasks.md 5.8, 7.6)
<!-- 7.6-* (burn rule history: recorded; one normal run's duration with its query count computed from the rendered rule JSON, 16 on the plan's reading: 15 PromQL on fleet and one SQL on devloop; the seven days beside design D1's expectation), queue-D5 and the tail of the D5 deploy log -->

### 9.9 CAM-69 acceptance (tasks.md 7.7)
<!-- 7.7-* (acceptance: PASS; the three questions' answers; journalctl -u devloop-reconcile since D4) -->

## 10. Integration verification (tasks.md 9.1) and the sync order (tasks.md 8.3)

### 10.1 Pull request 5's last build and its attributes reach devloop within 10 minutes
<!-- 9.1-closed-record section 10.1 and the 9.1-arrival-watch lines of build LAST -->

### 10.2 Its merge-queue batch and formation-to-land
<!-- 9.1-closed-record section 10.2 -->

### 10.3 D5's deploy record joined to the commit it deployed
<!-- 9.1-closed-record section 10.3 -->

### 10.4 Seven consecutive scheduled devloop-reconcile passes
<!-- 9.1-closed-record section 10.4 -->

### 10.5 The burn rule evaluated every minute on devloop, with no StoreQueryFailing since D5
<!-- 9.1-closed-record section 10.5 -->

### 10.6 Sync order against stand-up-gitea-mq-on-magnetite and stand-up-nixbot-on-magnetite
<!-- 8.3-sync-order and the decision taken -->
```

Run the discharge check now, before any section is filled:

```bash
export LC_ALL=C
comm -23 \
  <(grep -o 'Discharges: .* — verify:' openspec/changes/stand-up-devloop-collection/tasks.md | sed -E 's/^Discharges: //; s/ — verify:$//' | grep -oE '(DCI|DC|FAI|FA|HMC|TSI|WA) `[^`]+`' | sed -E 's/^[A-Z]+ //' | sort -u) \
  <(grep -oE '`[^`]+`' openspec/changes/stand-up-devloop-collection/verify.md | sort -u) | wc -l
```

Expected (RED): a count near 49, the number of distinct requirement names quoted after `Discharges:` in `tasks.md`, less any the template already quotes.
The `sed` keeps the text between `Discharges: ` and ` — verify:` whole, because the world-assumption names themselves contain ` — ` (`A43 — nixbot's migrations …`).

Fill §1–§8 by the instruction's checks: §1 `openspec validate --all --json` totals; §2 open items (none after Step 9); §3 one row per `openspec status --change stand-up-devloop-collection --json | jq -r '.artifactPaths.specs.existingOutputPaths[]'`, all `pending sync` (`devloop-collection`, `devloop-collection-interface` new; `fleet-alerting`, `fleet-alerting-interface`, `host-metrics-collection`, `telemetry-store-interface` modified, `fleet-alerting-interface` also renaming `The evaluator queries the fleet database as the regulators' store account`; `world-assumptions` adds A43–A49 and modifies `Grounded vocabulary for behavioral requirements`); §4 samples D1, D6, D9, D11 and D12 against their requirements; §5 the commit range of Step 5; §7 plan rows marked `[~]`, if any; §8a the designation lint of `devloop-collection`'s and `fleet-alerting`'s behavioral nouns against the `world-assumptions` table plus this change's 35 new rows; §8b one discharge row per ADDED and MODIFIED requirement from the `Discharges:` clauses in `tasks.md`, the two `This capability states its own trust boundary` requirements (DCI and FAI) stated as their scenarios give them and discharged by statement; §8c the alphabet check.
In §8b, the row of DCI `The x86_64-linux NixOS machine checks carry the deploy-record snippet` states its coverage as it is: the snippet is installed on all ten machines, CI holds the obligation only on the five x86_64-linux NixOS machine checks (cinnabar, electrum, galena, magnetite, pyrite), and the four darwin machines and the deferred scheelite were shown once by evaluation in Task 1 and are not held by CI.
Replace each HTML comment in §9 and §10 with the named logs' commands and outputs, verbatim, in a fenced `text` block, and delete the comment.
Before pasting, check for credentials:

```bash
rg -c -F -f <(ssh magnetite.zt 'for f in admin-password collector-password perses-password regulator-password; do sudo cat /run/secrets/vars/per-machine/magnetite/greptimedb-users/$f; echo; done' | grep -v '^$') "$EV"; echo "store-password scan exit=$?"
rg -n 'tk_[-_A-Za-z0-9]{29}' "$EV"; echo "token scan exit=$?"
```

Expected: `store-password scan exit=1` and `token scan exit=1` (no match); the passwords travel as `rg`'s pattern file, never as arguments.
A match is removed from that log, and the password is rotated per the runbook before continuing.
Run the discharge check again:

```bash
export LC_ALL=C
comm -23 \
  <(grep -o 'Discharges: .* — verify:' openspec/changes/stand-up-devloop-collection/tasks.md | sed -E 's/^Discharges: //; s/ — verify:$//' | grep -oE '(DCI|DC|FAI|FA|HMC|TSI|WA) `[^`]+`' | sed -E 's/^[A-Z]+ //' | sort -u) \
  <(grep -oE '`[^`]+`' openspec/changes/stand-up-devloop-collection/verify.md | sort -u)
```

Expected (GREEN): no output.
Check `(pass) PASS` when every section holds, `(warn) PASS WITH WARNINGS` naming the warning when §4 or §8 records drift or Step 7 recorded a figure above budget, and `(fail) FAIL` when any 7.x or 9.1 expectation failed.

- [ ] **Step 9: Tick the items**

With the edit tool, in `openspec/changes/stand-up-devloop-collection/tasks.md`, change only the leading `- [ ]` to `- [x]` on the lines of 7.1–7.7 (`:81-87`), 8.1–8.5 (`:91-95`) and 9.1 (`:99`), and nothing else; 7.x lines Task 7 already ticked stay as they are, 7.2 is ticked whether `verify.md` §9.4 records the boot line or `not yet observed`, because the item asks only that close-out record which, and 8.2–8.5 are ticked now because this change completes them before it is pushed.
Run:

```bash
rg -n '^- \[ \]' openspec/changes/stand-up-devloop-collection/tasks.md
openspec validate stand-up-devloop-collection --strict; echo "validate exit=$?"
```

Expected: no unticked line; `Change 'stand-up-devloop-collection' is valid` and `validate exit=0`.

- [ ] **Step 10: Fire In Progress → In Review for CAM-69**

Run:

```bash
linear auth whoami --workspace cameronraysmith
CUR=$(linear issue view CAM-69 --json --workspace cameronraysmith | jq -r '.state.name'); echo "$CUR"
```

Expected: `whoami` confirms the `cameronraysmith` workspace; `CUR` is `In Progress`.
Proceed only if `CUR` is `Backlog`, `Todo` or `In Progress`; if it is `In Review` or `Done`, skip to Step 11 and record the no-op.
Run:

```bash
linear issue update CAM-69 --state "In Review" --workspace cameronraysmith
printf 'S2 is deployed on magnetite and verify.md records the five deploys, a week of daily reconcile passes and the closed dev-loop record of pull request 5. The change is ready for its holistic review and documenter review.\n' > /tmp/cam69-c.md
linear issue comment add CAM-69 --body-file /tmp/cam69-c.md --workspace cameronraysmith
```

Expected: both succeed; a `NotFoundError` is a dropped write recorded in Step 11, leaving the issue In Progress.
If `CUR` was `Todo` (the first-tick transition was dropped), first run `linear issue update CAM-69 --state "In Progress" --workspace cameronraysmith` as the catch-up, per the strictly-behind rule.

- [ ] **Step 11: Update the sync ledger**

With the edit tool, in `openspec/changes/stand-up-devloop-collection/proposal.md` front matter set `linear_story_state: In Review` (`:6`), `last_synced_state: In Review` (`:9`), `last_synced_at:` (`:10`) to the output of `date -u +%FT%TZ`, and append after the last `attempt_log` entry:

```yaml
  - { at: "<the same timestamp>", transition: "In Progress->In Review", outcome: "posted", note: "verify.md created; five deploys and 9.1 evidence recorded" }
```

`<the same timestamp>` is the value just written to `last_synced_at`.
If Step 10 dropped the write, use `outcome: "dropped"` with the error in `note` and leave both states at `In Progress`.

- [ ] **Step 12: Format and commit the verification**

Run:

```bash
jj st --no-pager >/dev/null
nix fmt -- openspec/changes/stand-up-devloop-collection 2>&1 | tee "$EV/8.1-fmt-$(date -u +%Y%m%dT%H%M%SZ).log"
nix fmt -- --fail-on-change openspec/changes/stand-up-devloop-collection; echo "fmt-exit=$?"
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- \
  openspec/changes/stand-up-devloop-collection/verify.md \
  openspec/changes/stand-up-devloop-collection/tasks.md \
  openspec/changes/stand-up-devloop-collection/proposal.md
jj log -r VERIFY --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `fmt-exit=0`; `VERIFY` shows the three files; do not push.
Wait until the orchestrator has added `VERIFY` to the join: `jj log -r 'VERIFY & ::@' --no-graph -T 'change_id.short()'` prints the id and `test -f openspec/changes/stand-up-devloop-collection/verify.md && echo present` prints `present`.

- [ ] **Step 13: Holistic review sub-gate (8.2, replaces the codex review)**

The operator declined the paid codex review (roborev) for this program to avoid its cost, so this gate is one read-only Opus subagent review of S2 as merged and deployed, the substitute S1 and S3 used (`openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/review.md`); the reason is stated in `review.md` itself (S1 retrospective §6, last rule).
First fix the reviewed range:

```bash
S2_PATHS='modules/system/deploy-record.nix modules/checks/machines.nix modules/machines/nixos/cinnabar/default.nix modules/machines/nixos/electrum/default.nix modules/machines/nixos/galena/default.nix modules/machines/nixos/magnetite/default.nix modules/machines/nixos/pyrite/default.nix modules/machines/nixos/scheelite/default.nix modules/machines/darwin/argentum/default.nix modules/machines/darwin/blackphos/default.nix modules/machines/darwin/rosegold/default.nix modules/machines/darwin/stibnite/default.nix modules/nixos/devloop-collection.nix modules/checks/devloop-queries.nix modules/checks/devloop-queries modules/clan/services/otel-collector modules/nixos/greptimedb.nix modules/checks/otel-collector-config.nix modules/vm-tests/devloop-ingest.nix modules/vm-tests/devloop-ingest modules/nixos/fleet-alert.nix modules/nixos/fleet-alert modules/checks/fleet-alert.nix modules/checks/fleet-alert packages/docs/src/content/docs/development/operations/fleet-observability.md modules/README.md modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md'
FIRST=$(git log --reverse --diff-filter=A --format=%H origin/main -- modules/system/deploy-record.nix | head -n1)
BASE=$(git rev-parse "$FIRST^"); TIP=$(git rev-parse origin/main)
git cat-file -t "$BASE"; git cat-file -t "$TIP"
for f in $(git diff --name-only "$BASE" "$TIP" | grep -vE '^(openspec|docs/notes)/'); do
  git diff "$BASE" "$TIP" -- "$f" | grep -qE 'devloop|deployRecord|deploy-record|PullRequestQueueWaitBurn' || continue
  covered=no; for p in $S2_PATHS; do case "$f" in "$p"|"$p"/*) covered=yes;; esac; done
  [ "$covered" = no ] && echo "uncovered: $f"
done
git diff --stat "$BASE" "$TIP" -- $S2_PATHS | tail -n1
echo "BASE=$BASE TIP=$TIP"
```

Expected: `commit` twice; no `uncovered:` line (an uncovered file carrying an S2 name, such as wherever Task 4 placed `flake.lib.devloopReconcile`, is appended to `S2_PATHS` and the loop rerun until none is printed); a diffstat line; the two hashes.
`FIRST` is Task 1's commit, the first on `origin/main` to add `modules/system/deploy-record.nix`, and `BASE` its parent.

Spawn one subagent of the default `task` agent type on an Opus model (the `reviewer` type has no model configured in this harness), read-only by its instructions, with this task, substituting the two hashes and the final path list:

```text
Review slice S2 (OpenSpec change stand-up-devloop-collection, Linear CAM-69) as merged and deployed. Read-only: change no file and run no build, deploy, formatter or mutating command.
Read: the change set `git diff <BASE> <TIP> -- <S2_PATHS>` and `git log --no-patch <BASE>..<TIP> -- <S2_PATHS>`; openspec/changes/stand-up-devloop-collection/{brainstorm.md,proposal.md,design.md,tasks.md,plan.md,verify.md} and its specs/; logs/s2/grounding.md and logs/s2/spike-dedup.md; docs/notes/development/observability/ (charter.md through v22, decisions/ADR-004-signal-scope-and-schema.md, decisions/ADR-005-dev-loop-instrumentation.md, decisions/ADR-009-alerting.md, components/devloop-exporters.md, components/fleet-alert.md, architecture/reference-architecture.md); and the S3 review at openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/review.md for the expected shape.
Answer four questions, each finding with file:line evidence and a proposed fix:
1. Critical oversights: a dev-loop event S2 claims to record that can be lost, duplicated or stored under the wrong key without devloop-reconcile reporting it within a day; error text, a message body or other free text reaching devloop; a write, index, view, function or trigger in nixbot's database; a path where a store password reaches a command line or an unintended reader; a deploy recorded twice or not at all, on magnetite or on any of the other nine machines, noting that CI holds the deploy-record obligation only on the five x86_64-linux NixOS machine checks and the four darwin machines and scheelite were shown once by evaluation; a burn-rule query that reaches the wrong database; or a contradiction with S4, S6, S7 or S8 as design.md "Later slices" and the decision records plan them.
2. Significant architecture improvements: places where the allow-list and its renderers, the logs ingress and queue split, the nixbot cursor queries and grants, the journal and file receivers, the deploy-record snippet and its obligation, devloop-reconcile, or the evaluator's per-rule database and language could be simpler or more robust for the same guarantees.
3. Checks that cannot fail, clauses or assertions that compare a value with itself or with a module literal, reconcile clauses or container-test cases never shown failing, and properties that no check, assertion, reconcile clause or deployment observation covers.
4. Overzealousness: checks, mutants, container cases or mechanisms that cost more (evaluation, build time on magnetite, maintenance, merge-queue risk) than the invariant they protect.
Return a markdown report in the S3 review.md form: a title, a paragraph stating what was read, when and why (in place of the paid codex review, which the operator declined for this program to avoid its cost), the four questions, a summary count by severity (critical, significant, minor), a table | Finding | Category | Severity | Applied in | with Applied in left as "pending", then one section per finding (F1, F2, ...) with evidence and the proposed fix.
```

Write the returned report verbatim to `openspec/changes/stand-up-devloop-collection/review.md` with the write tool, then run:

```bash
jj st --no-pager >/dev/null
nix fmt -- openspec/changes/stand-up-devloop-collection/review.md
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- openspec/changes/stand-up-devloop-collection/review.md
rg -c '^\| F[0-9]+ ' openspec/changes/stand-up-devloop-collection/review.md
```

Expected: the number of findings in the table.
Present the findings to the human, who decides which to apply; every applied finding is applied before Step 15.
For the applied findings, append to `tasks.md` after `:99` a section `## 10. Review follow-ups` with one item per finding (`- [ ] 10.<n> F<n>: <fix> — verify: <the check, assertion, reconcile clause or runtime observation shown red before and green after>`), and hand the items to the orchestrator, which lands them as their own pull requests and redeploys magnetite through `logs/s2-evidence/s2-deploy.sh magnetite F<n>`, which deploys only when nixbot's queue is empty.
As each lands, tick its item, fill its `Applied in` cell in `review.md`, and add to `verify.md` a section `## 11. Review follow-ups (tasks.md section 10)` recording the pull requests, the red-before and green-after evidence and any redeploy, in the form of S3's `verify.md` §11.
A finding the human declines gets `Applied in: declined, <reason>` in `review.md`, so the reason for every skipped fix is recorded.
If any finding is critical, it is a re-queue: check `- [x] (fail) FAIL` in `verify.md`; in proposal.md set `review_round` to its value plus one and both states to `In Progress`, and append `{ at: "<iso>", transition: "In Review->In Progress", outcome: "posted", note: "holistic review re-queue: <findings>" }`; run `linear issue update CAM-69 --state "In Progress" --workspace cameronraysmith`; squash into `VERIFY` as in Step 12; after the fixes land, this task restarts at Step 8.
Past `max_review_rounds` (3), post one escalation comment and stop.
Post one comment of at most two sentences, written from the actual result, with `linear issue comment add CAM-69 --body-file /tmp/cam69-c.md --workspace cameronraysmith`.

- [ ] **Step 14: Documenter sub-gate**

This gate stays a human step, and its scope includes the operator documentation (S1 retrospective §6: operator docs are in the documenter gate's scope).
Ask the human to review, against what was deployed: `verify.md` and `review.md`; the `devloop` section of the runbook `packages/docs/src/content/docs/development/operations/fleet-observability.md` (6.1); `modules/clan/services/otel-collector/README.md` (6.2); `modules/README.md` (6.3); the skill line in `modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md` (6.4); `docs/notes/development/observability/decisions/ADR-004-signal-scope-and-schema.md`, `ADR-005-dev-loop-instrumentation.md` and `ADR-009-alerting.md`, `components/devloop-exporters.md` and `components/fleet-alert.md` as amended by charter v22; and `design.md`.
Record `documenter: approved by <name> on <date>` or the rejection with its reason under `**Next step**:` in `verify.md`, then squash `verify.md` into `VERIFY` as in Step 12; a rejection re-queues as in Step 13.

- [ ] **Step 15: Write the retrospective (8.2)**

Run:

```bash
verify_file=$(openspec status --change stand-up-devloop-collection --json | jq -r '.artifactPaths.verify.existingOutputPaths[0] // empty')
test -n "$verify_file" && ! grep -q '^- \[x\] (fail) FAIL' "$verify_file" && echo "retrospective allowed"
openspec instructions retrospective --change stand-up-devloop-collection --json | jq -r '.instruction'
```

Expected: `retrospective allowed`, then the instruction.
Invoke `openspec-continue-change` for the `retrospective` artifact and write `retrospective.md` in S3's format (`openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/retrospective.md`, sections §0–§6).
In §4 put a table `| Rule | Source | Applied in S2 | What it caught |` with one row per rule below, filling `What it caught` from the cited evidence, or `nothing` when the rule ran and found nothing, or `not applied: <reason>`:

| Rule | Source | Applied in S2 |
|---|---|---|
| Read the upstream source behind a vendor option before depending on it | S1 §6 `:132` | plan pins and citations (otelcol-contrib `sqlquery`, `journald`, `file_log`; nixbot migrations; gitea-mq messages; GreptimeDB pipelines) |
| Each new producer has a start-order relation and a check for it | S1 §6 `:136` | R3.1's ordering clause and its `schemaOrderDropped` mutant keep the collector after `greptimedb-schema` (3.6); `devloop-ingest`'s `noAutoCreate` case shows a missing table is not auto-created (3.9) |
| Runtime tests start dependent units together and assert no dropped data | S1 §6 `:140` | every ingest case of `devloop-ingest` asserts `otelcol_exporter_send_failed_log_records` is zero after the first send (3.9) |
| A clause relates independently defined values; a property of one module is an assertion | S1 §6 `:144`, S3 §6 `:158` | the value sources named per clause in 1.5, 2.6 (including the marker clause bound to the patch's production lines), 3.6, 4.5; the journal-read assertion (3.7) and the R8.2 and kill-order assertions (4.4) shown failing by `extendModules` overrides |
| Measure each new check's evaluation cost against a budget, with `.#.checks…` and the method | S1 §6 `:148`, S3 §6 `:154` | each task's figure and Step 7's re-measurement (`verify.md` §9.1) |
| Every runtime regulator clause has a negative control on a real store | S1 §6 `:152` | C1–C7 each failed by a `devloop-ingest` mutant (4.6); 7.5's forced `devloop_absent` failure |
| `nix fmt` with its log before every commit | S1 §6 `:156` | 1.6, 2.8, 3.10, 4.7, 5.7, 6.5 and Steps 12 and 21 here |
| Operator documentation is a task in the documenter gate's scope | S1 §6 `:160` | group 6 and Step 14 |
| Holistic review of the planned regulators before Task 1 | S1 §6 `:164`, S3 §6 `:162` | 1.1's plan review (`1.1-plan-review-<ts>.md`) |
| Check each slice's rules against the later slices that touch the same objects | S1 §6 `:168` | design.md "Later slices" (S4, S6, S7, S8); question 1 of Step 13 |
| Notifier and regulator semantics tested across restart and cache-fill states | S1 §6 `:172` | `devloop-ingest`'s overlap and switch cases; 7.4's collector restart not re-sending the backfill |
| Resolve the designation-lint nouns at sync | S1 §6 `:176`, S3 §6 `:182` | the 35 rows S2's `world-assumptions` delta adds; `verify.md` §8a |
| Record the operator's reason whenever a planned gate is replaced | S1 §6 `:180` | `review.md`'s opening paragraph (Step 13) |
| A reference model is written from the specification's scenarios | S3 §6 `:142` | the burn-rule timeline leg taken from the `fleet-alerting-interface` scenario `The timeline is replayed` before any evaluator change (5.1) |
| A shared clan var gains a reader with `clan vars fix`, never `clan vars generate` | S3 §6 `:146` | not needed: S2 adds no var and `devloop-reconcile` loads the existing `regulator-password` |
| A human step a later observation depends on is its own gated step | S3 §6 `:150` | no later observation depends on a human step: 7.2 became opportunistic (plan review F18) and gates nothing; Step 14's documenter gate |
| Each slice names the regulator its own silence modes need | S3 §6 `:166` | `devloop-reconcile` (C4 batch liveness) for a silent gitea-mq; `RuleSignalMissing` does not cover `devloop` |
| Schedule CAM-76's watch before S5 | S3 §6 `:170` | not S2's: record CAM-76's state as read on the retrospective's date |
| S2 adds a per-rule `database` to the rule table, the fixture server and `promtool` | S3 §6 `:174` | 5.1–5.5 and 10.5 above |
| A long-running evidence capture runs on an always-on host | S3 §6 `:178` | Step 2's arrival watch on magnetite |
| A requirement ending on a person's device names one delivered message with its time | S3 §6 `:186` | 7.5's `FAILED devloop-reconcile.service on magnetite` and its `RESOLVED`, with `T_FORCED_FAIL` and `T_FORCED_RESOLVE` |

The `:<line>` cells cite the bold rule's line in `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/retrospective.md` (S1) and `openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/retrospective.md` (S3) as read on 2026-10-21.
In §3 (Plan deviations) record the two verify criteria this plan replaces, with their reasons: tasks.md 8.4's requirement count is compared with `openspec list --specs --json`, because `openspec validate --specs --json` counts specs (Step 17); and tasks.md 8.5's `openspec validate --specs --strict` is judged as "every S2 capability but `world-assumptions` passes and no spec newly fails", because main failed it on 17 of 22 specs before S2 (Step 16).
In §2 (Misses) state the deploy-record obligation's coverage: the snippet is on all ten machines, CI holds the obligation only on the five x86_64-linux NixOS machine checks, and the four darwin machines and the deferred scheelite were shown once by evaluation in Task 1 and are not held by CI; §6 carries a follow-up for holding them.
Close with a §6 promote list in S3's format; every undischarged §8b row, every §7 gap, every declined review finding and Step 4's sync-order decision appear there with a follow-up.
Run `rg -n '^## 6\. Promote' openspec/changes/stand-up-devloop-collection/retrospective.md`; expected: one line.
Then run:

```bash
jj st --no-pager >/dev/null
nix fmt -- openspec/changes/stand-up-devloop-collection/retrospective.md
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- openspec/changes/stand-up-devloop-collection/retrospective.md
```

Expected: the squash succeeds.

- [ ] **Step 16: Archive readiness, the spec sync and the new capabilities' Purpose (8.5)**

Confirm Step 4's decision allows the sync, then run:

```bash
openspec status --change stand-up-devloop-collection --json | jq -c '[.artifacts[] | {id, status}]'
openspec list --json | jq -c '.changes[] | select(.name == "stand-up-devloop-collection") | {totalTasks, completedTasks}'
planning_root=$(openspec status --change stand-up-devloop-collection --json | jq -r 'select(.planningHome.kind=="repo") | .planningHome.root'); echo "$planning_root"
caps=$(openspec status --change stand-up-devloop-collection --json | jq -r '.artifactPaths.specs.existingOutputPaths[] | split("/")[-2]'); echo $caps
openspec validate --specs --strict 2>&1 | grep -E '^[✗✓]' | sort > /tmp/s2-strict-before.txt; grep -c '✗' /tmp/s2-strict-before.txt
rg -c '^### Requirement: A(43|44|45|46|47|48|49) ' openspec/specs/world-assumptions/spec.md || echo 0
openspec list --specs --json | jq '[.specs[].requirementCount] | add'
```

Expected: every artifact `done`; `totalTasks` equal to `completedTasks`; `$REPO`; the seven capabilities `devloop-collection devloop-collection-interface fleet-alerting fleet-alerting-interface host-metrics-collection telemetry-store-interface world-assumptions`; the failing count under `--strict` (17 of 22 on 2026-10-21, every one from placeholder Purposes or requirement texts above 500 characters, none of them an S2 capability other than `world-assumptions`); `0` (RED: A43–A49 are not yet in main); `196`.
Keep `planning_root` and `caps` for Step 19.
Invoke `openspec-archive-change` for `stand-up-devloop-collection` and choose "Sync now (recommended)"; stop the skill before its move if it offers one, so Step 17 regenerates the projection before the folder moves (`openspec/config.yaml:56`).
Run:

```bash
{
  rg -n '^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements' openspec/specs/devloop-collection openspec/specs/devloop-collection-interface openspec/specs/fleet-alerting openspec/specs/fleet-alerting-interface openspec/specs/host-metrics-collection openspec/specs/telemetry-store-interface openspec/specs/world-assumptions || echo 'no delta headers'
  rg -c '^### Requirement: A(43|44|45|46|47|48|49) ' openspec/specs/world-assumptions/spec.md
  rg -n "The evaluator queries (the fleet|each rule's) database as the regulators' store account" openspec/specs/fleet-alerting-interface/spec.md
  openspec list --specs --json | jq '([.specs[].requirementCount] | add), (.specs | length)'
  sed -n '1,6p' openspec/specs/devloop-collection/spec.md openspec/specs/devloop-collection-interface/spec.md
} 2>&1 | tee "$EV/8.5-specs-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `no delta headers`; `7` (GREEN); one line naming `each rule's database` and none naming `the fleet database`; `234` and `24` (196 + 6 + 23 + 1 + 1 + 7 requirements, 22 + 2 capabilities) [INFERENCE from the delta headers counted on 2026-10-21; another archive landing first changes both and Step 17 uses whatever this prints]; each new spec's `## Purpose` holding the placeholder sentence the archive writes.
With the edit tool, in `openspec/specs/devloop-collection/spec.md`, replace the placeholder line under `## Purpose` with:

```text
This capability (stratum: `behavioral`) states what the fleet requires of its dev-loop history: that every attribute outcome, finished build, merge-queue batch event and deploy is recorded once in `devloop` and kept for a year; that a gap in that history reaches a person within a day; that no error text, message body or other free text enters it; that the past week of the dev loop can be asked about; that a deploy can be attributed to the commits that built it; and that the build service's records are read without being changed and without a stored credential.
```

In `openspec/specs/devloop-collection-interface/spec.md`, replace the placeholder line under `## Purpose` with these two lines:

```text
This capability (stratum: `interface`) states the properties at the machine's interface that discharge the `devloop-collection` requirements: the two nixbot cursor queries with their overlap, page size, allow-listed text columns and abandonment marker; the readers' peer authentication and column grants; the gitea-mq journal parse; the deploy-record snippet on every machine, held by the five x86_64-linux NixOS machine checks, and magnetite's file receiver; the pre-created `devloop` tables, their ingest pipelines and the one allow-list behind both; the logs routing; `devloop-reconcile`'s daily comparisons; and the checks `devloop-queries` and `devloop-ingest`.
Trust boundary: nixbot and gitea-mq produce the source rows and lines and this machine only reads them, trusting their schema and messages at the pinned revisions; any root process on magnetite can read the `regulator` password and the deploy-record file, which is world-readable on every host; hosts other than magnetite write deploy records that no collector ships until S4 and S5; nothing here guarantees that a given event reaches the store, only that each stage's configuration, the gating checks, the container test and the daily reconcile behave as stated.
```

The trust-boundary line restates the four scenarios of `devloop-collection-interface`'s `This capability states its own trust boundary` (change spec `:310-345`), in the form `fleet-alerting-interface`'s Purpose uses (`openspec/specs/fleet-alerting-interface/spec.md:6`).
Run:

```bash
openspec validate --specs --strict 2>&1 | grep -E '^[✗✓]' | sort > /tmp/s2-strict-after.txt
grep -E 'devloop-collection|fleet-alerting|host-metrics-collection|telemetry-store-interface' /tmp/s2-strict-after.txt
diff <(grep '✗' /tmp/s2-strict-before.txt) <(grep '✗' /tmp/s2-strict-after.txt) && echo "no new strict failure"
```

Expected: `✓` for `devloop-collection`, `devloop-collection-interface`, `fleet-alerting`, `fleet-alerting-interface`, `host-metrics-collection` and `telemetry-store-interface`; `no new strict failure` (`world-assumptions` fails `--strict` before and after on its placeholder Purpose and long requirement texts, which S2 does not touch).

- [ ] **Step 17: Regenerate the satisfaction projection wholesale (8.4)**

The projection is rebuilt from the post-sync corpus and never patched (`openspec/config.yaml:54-58`; `satisfaction.md:7`); its rows are one per current requirement, its annotations for requirements S2 did not touch are carried over by capability and title from the previous projection, as the file's own header states it does (`:8`), and every S2-touched requirement is annotated afresh from `verify.md` §8b, §9 and §10.
Snapshot the previous projection and list what the corpus requires:

```bash
export LC_ALL=C
F=packages/docs/src/content/docs/development/traceability/satisfaction.md
cp "$F" /tmp/satisfaction-prev.md
corpus() { for s in openspec/specs/*/spec.md; do c=$(basename "$(dirname "$s")"); awk -v c="$c" '/^### Requirement: /{sub(/^### Requirement: /, ""); print c " | " $0}' "$s"; done | sort -s -t'|' -k1,1; }
projected() { awk '/^## /{c=substr($0,4)} /^Source: /{ok=1} /^\| /&&!/^\| Requirement /&&!/^\|---/&&ok{split($0, f, " \\| "); t=f[1]; sub(/^\| /, "", t); print c " | " t}' "$1" | sort -s -t'|' -k1,1; }
touched() { for s in openspec/changes/stand-up-devloop-collection/specs/*/spec.md; do c=$(basename "$(dirname "$s")"); awk -v c="$c" '/^### Requirement: /{sub(/^### Requirement: /, ""); print c " | " $0}' "$s"; done | sort -u; }
{
  echo '# RED: corpus titles against the previous projection'
  diff <(corpus) <(projected /tmp/satisfaction-prev.md) | grep -E '^[<>]' | cut -c1 | sort | uniq -c
  echo "# S2-touched requirements: $(touched | wc -l)"
  echo '# corpus rows neither touched by S2 nor in the previous projection:'
  comm -23 <(corpus | sort -u) <(sort -u <(touched) <(projected /tmp/satisfaction-prev.md))
} 2>&1 | tee "$EV/8.4-satisfaction-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `39 <` and `1 >` (the 39 titles S2 adds, including the renamed `The evaluator queries each rule's database as the regulators' store account`, and the one old title it renames away); `S2-touched requirements: 50`; and nothing under the last heading.
A row printed under the last heading belongs to another change that archived after the previous projection; annotate it from that change's `verify.md` §8b the same way.
Build the new file in full with the write tool (never the edit tool on this file), from top to bottom:
1. Front matter: `title` and `description` unchanged, `generated:` the archive date, `date -u +%F`.
2. The five paragraph lines of `:7-11`, with `:8` naming the CAM-69 archive in place of the CAM-77 archive.
3. `## Status`: requirement and capability totals from Step 16; the discharged, undischarged and world-row counts computed by the check below; the per-change breakdown of discharged rows with `N from CAM-69's dev-loop collection slice` added; the world-row paragraph adding `A43–A49 carry CAM-69's deployment and acceptance observations`; the CAM-63 paragraphs unchanged.
4. `## Evidence and follow-up conventions`: every bullet kept, plus `- CAM-69 evidence/follow-ups: \`openspec/changes/archive/<YYYY-MM-DD>-stand-up-devloop-collection/verify.md\` §§8b,9,10,11, \`tasks.md\` §10, \`review.md\` and \`retrospective.md\` §6.` after the CAM-70 bullet (with §11 and §10 only if Step 13 applied findings), and the strata bullet adding `CAM-69 declares devloop-collection behavioral and devloop-collection-interface interface`.
5. One `## <capability>` section per main spec, in the previous file's order with `devloop-collection-interface` then `devloop-collection` inserted after `bare-metal-install-path`, each with its `Source:` line and table header as before; rows in the main spec's requirement order; an untouched requirement's row copied verbatim from `/tmp/satisfaction-prev.md`; an S2-touched requirement's row written as `| <title> | <stratum> | <Discharged by (S) from verify.md §8b> | <Under (W): the world-assumptions rows its Discharges clause names, or —> | discharged — CAM-69 verify §8b, §<9.x or 10.x> |` or `| … | undischarged — <follow-up reference from retrospective.md §6> |`, a MODIFIED requirement that a previous change discharged keeping that change's citation and adding `; amended by CAM-69 verify §8b`.
6. `world-assumptions` rows A43–A49 as `| A4x — <title> | world | <the requirements naming it in tasks.md Discharges clauses> | self-attested; observed by <the 7.x observation> (CAM-69 verify §9.x) |`, and the `Grounded vocabulary for behavioral requirements` row's status adding `CAM-69 verify §8a disposition`.
7. The paragraph after the world-assumptions table (`:390-393`) restated for the corpus as it now stands, adding that CAM-69's MODIFIED block was synced as a whole-block replacement carrying every pre-sync row plus its 35 rows, and Step 4's decision about the two sibling deltas.
8. The qualification sections kept, plus `## CAM-69 qualifications` after `## CAM-70 qualifications`, in their form: the verdict, the review follow-ups, what kinds of evidence the interface discharges are, and the trust boundary stated, not discharged.
9. `## Known limits` kept, plus one line for CAM-69's discharges: configuration, regulator, container-test and observed behavior on magnetite only; the deploy-record obligation held by CI on the five x86_64-linux NixOS machine checks only, the four darwin machines and scheelite shown once by evaluation; nothing about deploys on the other nine machines reaching `devloop`, nor about events nixbot or gitea-mq never record.
Then run the checks:

```bash
export LC_ALL=C
F=packages/docs/src/content/docs/development/traceability/satisfaction.md
{
  echo "generated: $(sed -n 's/^generated: //p' "$F") archive date: $(date -u +%F)"
  diff <(corpus) <(projected "$F") && echo "GREEN: titles match the corpus"
  echo "rows: $(projected "$F" | wc -l) corpus requirements: $(openspec list --specs --json | jq '[.specs[].requirementCount] | add')"
  echo "sections: $(grep -c '^Source: `openspec/specs/' "$F") specs validated: $(openspec validate --specs --json | jq '.totals.items')"
  awk '/^Source: /{gsub(/^Source: `|`\.$/, ""); print}' "$F" | while read -r p; do test -f "$p" || echo "missing source $p"; done
  awk -F' \\| ' '/^\| /&&!/^\| Requirement /&&!/^\|---/{print $NF}' "$F" | sed 's/ |$//' | awk '{print $1}' | sort | uniq -c
  echo "undischarged rows without a follow-up: $(awk -F' \\| ' '/^\| /&&!/^\| Requirement /&&!/^\|---/{print $NF}' "$F" | grep -cE '^undischarged *\|?$')"
  grep -oE '\*\*[0-9]+ requirements across [0-9]+ capabilities' "$F"
  grep -oE '[0-9]+ requirement-side rows are discharged|[0-9]+ remain undischarged|[0-9]+ world-assumption rows' "$F"
} 2>&1 | tee -a "$(ls -t "$EV"/8.4-satisfaction-*.log | head -n1)"
```

Expected: the two dates equal; `GREEN: titles match the corpus`; `rows:` equal to `corpus requirements:` (234 if Step 16 printed 234); `sections:` equal to `specs validated:` (24); no `missing source`; the counts per first status word (`discharged`, `self-attested;`, `undischarged`) equal to the three numbers the Status paragraph states, which the last two lines print, and their sum equal to the row count; `undischarged rows without a follow-up: 0`.
tasks.md 8.4 asks the requirement count to equal `openspec validate --specs --json`'s, but that output's `.totals.items` counts specs, not requirements (22 on 2026-10-21 against 196 requirements), so the requirement count is taken from `openspec list --specs --json` and the section count from `openspec validate --specs --json`, as retrospective §3 records (Step 15).
Squash the file into `VERIFY`:

```bash
jj st --no-pager >/dev/null
nix fmt -- packages/docs/src/content/docs/development/traceability/satisfaction.md
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- packages/docs/src/content/docs/development/traceability/satisfaction.md
```

- [ ] **Step 18: Archive (8.5)**

Let the skill perform the move, or run:

```bash
openspec archive stand-up-devloop-collection -y --skip-specs 2>&1 | tee "$EV/8.5-archive-$(date -u +%Y%m%dT%H%M%SZ).log"
ARCHIVED=$(ls -d openspec/changes/archive/*-stand-up-devloop-collection); echo "$ARCHIVED"
test ! -e openspec/changes/stand-up-devloop-collection && echo archived
openspec list --json | jq -r '.changes[].name' | grep -c '^stand-up-devloop-collection$' || true
openspec validate --specs --strict 2>&1 | grep -E '^[✗✓]' | sort | diff /tmp/s2-strict-after.txt - && echo "strict results unchanged by the move"
```

Expected: the archive directory, `archived`, `0`, `strict results unchanged by the move`.
`--skip-specs` because Step 16 synced; S3 read `openspec archive --help` listing `--skip-specs   Skip spec update operations` (S3 plan Task 8 Step 15).
tasks.md 8.5's verify clause asks `openspec validate --specs --strict` to pass, but on 2026-10-21 main already fails it on 17 of 22 specs for reasons outside S2, so the plan's criterion is that every S2 capability but `world-assumptions` passes and no spec newly fails (Step 16), as retrospective §3 records (Step 15).

- [ ] **Step 19: Mirror the main specs to Linear documents**

Run:

```bash
linear auth whoami --workspace cameronraysmith
: > "$EV/linear-doc-ids.txt"
for cap in $caps; do
  if [ "$cap" = world-assumptions ]; then
    linear document update a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1 --title "OpenSpec: world-assumptions" --content-file "$planning_root/openspec/specs/world-assumptions/spec.md" --workspace cameronraysmith
    printf '%s %s\n' "$cap" a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1 >> "$EV/linear-doc-ids.txt"
    continue
  fi
  DOC_ID=$(yq -r ".projects.\"fleet-observability\".archive_documents.\"$cap\".id // \"\"" openspec/linear.yaml)
  if [ -z "$DOC_ID" ]; then
    DOC_ID=$(linear document list --project aeed302bea3b --json --workspace cameronraysmith | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  if [ -n "$DOC_ID" ]; then
    linear document update "$DOC_ID" --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace cameronraysmith
  else
    linear document create --project aeed302bea3b --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace cameronraysmith
    DOC_ID=$(linear document list --project aeed302bea3b --json --workspace cameronraysmith | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  printf '%s %s\n' "$cap" "$DOC_ID" >> "$EV/linear-doc-ids.txt"
done
cat "$EV/linear-doc-ids.txt"
```

Expected: updates for `world-assumptions`, `fleet-alerting`, `fleet-alerting-interface`, `host-metrics-collection` and `telemetry-store-interface` (their stored ids), creates for `devloop-collection` and `devloop-collection-interface`, and seven lines with non-empty ids in the file.
`aeed302bea3b` is the slugId; a UUID would make `document list` return nothing and duplicate documents (`openspec/linear.yaml:82-83`).
With the edit tool, in `openspec/linear.yaml`, after `:96` (`        id: "ee21d4e7-237f-4778-9bb4-2826a87332ab"`), add:

```yaml
      "devloop-collection":
        id: "<id for devloop-collection from linear-doc-ids.txt>"
      "devloop-collection-interface":
        id: "<id for devloop-collection-interface from linear-doc-ids.txt>"
```

Each `<…>` is replaced by the id the loop printed; nothing else in the file changes (never `yq -i`, which drops comments).
Run `jj diff --git openspec/linear.yaml`; expected: four added lines with real ids and every comment intact.

- [ ] **Step 20: Fire In Review → Done for CAM-69**

Run:

```bash
CUR=$(linear issue view CAM-69 --json --workspace cameronraysmith | jq -r '.state.name'); echo "$CUR"
linear issue update CAM-69 --state "Done" --workspace cameronraysmith
printf 'The S2 change is archived, its specs are synced, the satisfaction projection is regenerated, and the canonical specs are mirrored to the Fleet observability project documents.\n' > /tmp/cam69-c.md
linear issue comment add CAM-69 --body-file /tmp/cam69-c.md --workspace cameronraysmith
```

Expected: `CUR` is `In Review` (or `In Progress` if Step 10 was dropped); both succeed; skip both if `CUR` is already `Done`.
With the edit tool, in the archived `proposal.md` front matter set `linear_story_state: Done`, `last_synced_state: Done`, `last_synced_at:` to `date -u +%FT%TZ`, `review_round: 0`, and append `  - { at: "<iso>", transition: "In Review->Done", outcome: "posted", note: "archive; spec sync, Purpose edits, satisfaction projection and document mirror done" }`, where `<iso>` is the `last_synced_at` value.

- [ ] **Step 21: Format and commit the close-out**

Run:

```bash
ARCHIVED=$(ls -d openspec/changes/archive/*-stand-up-devloop-collection)
jj st --no-pager >/dev/null
nix fmt -- "$ARCHIVED" openspec/specs openspec/linear.yaml packages/docs/src/content/docs/development/traceability/satisfaction.md 2>&1 | tee "$EV/8.5-fmt-$(date -u +%Y%m%dT%H%M%SZ).log"
nix fmt -- --fail-on-change "$ARCHIVED" openspec/specs openspec/linear.yaml packages/docs/src/content/docs/development/traceability/satisfaction.md; echo "fmt-exit=$?"
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- \
  openspec/changes/stand-up-devloop-collection "$ARCHIVED" \
  openspec/specs/devloop-collection openspec/specs/devloop-collection-interface openspec/specs/fleet-alerting openspec/specs/fleet-alerting-interface openspec/specs/host-metrics-collection openspec/specs/telemetry-store-interface openspec/specs/world-assumptions \
  packages/docs/src/content/docs/development/traceability/satisfaction.md \
  openspec/linear.yaml
jj log -r VERIFY --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `fmt-exit=0`; `VERIFY` shows the change directory deleted, the same files under the archive directory with `verify.md`, `review.md` and `retrospective.md`, the seven main specs, `satisfaction.md` and `openspec/linear.yaml`.
The orchestrator rebases the join, pushes and opens pull request 7, which lands through the merge queue; do not push.

- [ ] **Step 22: Pull request 7 merged**

After the orchestrator reports pull request 7 merged, run:

```bash
git fetch -q origin
PR7=$(gh pr list --repo cameronraysmith/vanixiets --state merged --search 'verify and archive S2 dev-loop collection in:title' --json number --jq '.[0].number'); echo "PR7=$PR7"
gh pr view "$PR7" --repo cameronraysmith/vanixiets --json state,mergedAt --jq '"\(.state) \(.mergedAt)"'
git ls-tree -d --name-only origin/main openspec/changes/archive/ | grep -c 'stand-up-devloop-collection$'
git ls-tree -d --name-only origin/main openspec/changes/ | grep -c '^openspec/changes/stand-up-devloop-collection$' || true
git show origin/main:packages/docs/src/content/docs/development/traceability/satisfaction.md | sed -n 's/^generated: //p'
```

Expected: `MERGED <time>`; `1`; `0`; the archive date of Step 17.
No deploy follows: pull request 7 changes no Nix module, so magnetite's configuration is unchanged by it.
