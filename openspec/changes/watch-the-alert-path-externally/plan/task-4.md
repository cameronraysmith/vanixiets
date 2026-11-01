### Task 4: Deploy and acceptance

Implements `tasks.md` 3.1–3.2 and 4.1–4.4 (design Migration Plan steps 3–6; FA `An outage of the alert path reaches the operator by email from outside the fleet`; FAI `The dead-man pings the watch service only after a passing run`, `The ping URL travels only as a credential read on stdin`; WA `A53 — healthchecks.io counts a ping by its URL and emails when pings stop for longer than a check's period and grace`, `A55 — The operator's mailbox is reached without the fleet`).
Starts after pull request 1 has merged.
Steps 3 to 6 are gated on the operator's presence, because only the operator sees the emails and the `fleet-alerts` messages.

**Files:**
- Create (git-ignored): `logs/cam76-evidence/3.<n>-*.log`, `logs/cam76-evidence/4.<n>-*.log`

**Interfaces:**
- Consumes: pull request 1 on `origin/main`; the check of Task 3 Step 1.
- Produces: the recorded times that Task 6 cites in `verify.md` and that the orchestrator records in CAM-76 to unblock CAM-72.

- [ ] **Step 1: Deploy cinnabar (tasks.md 3.1)**

```bash
git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main
nixbot-logs queue   # must print: Queue is empty
cd $DEPLOY && clan machines update cinnabar 2>&1 | tee logs/cinnabar-$(date +%Y%m%d-%H%M%S).log
ssh cinnabar.zt 'systemctl is-active fleet-deadman.timer'
```

Expected: the deploy log ends without error, and `active`.

- [ ] **Step 2: The first 30 minutes (tasks.md 3.2)**

```bash
L=$REPO/logs/cam76-evidence/3.2-first-pings-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
sleep 1800
ssh cinnabar.zt 'bash -s' <<'EOF' 2>&1 | tee "$L"
sudo journalctl -u fleet-deadman --since -30min -o cat | grep -E 'heartbeat\(s\) on|external ping|no external ping|Failed'
systemctl show fleet-deadman -p Environment -p LoadCredential
systemctl show fleet-deadman -p Environment -p LoadCredential | grep -c hc-ping || true
EOF
```

Expected: six runs, each `fleet-deadman: external ping accepted`, no `Failed`; `Environment=` holds `FLEET_DEADMAN_PING_CONFIG=%d/external-ping` and `LoadCredential=` the `curl-config` path under `/run/secrets/`; the `hc-ping` count is `0`.
Ask the operator to confirm that the check shows "up" with a ping every 5 min and that no `FAILED fleet-deadman` arrived; record the reply in the log.

- [ ] **Step 3: Presence gate (tasks.md 4.1)**

Ask the operator to confirm being at a device that receives both `fleet-alerts` and the check's email address; record the confirmation and its time in `logs/cam76-evidence/4.1-presence-<ts>.log`.

- [ ] **Step 4: The ntfy stop (tasks.md 4.2)**

```bash
L=$REPO/logs/cam76-evidence/4.2-ntfy-stop-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh cinnabar.zt 'sudo journalctl -u fleet-deadman -n 50 -o short-iso | grep "external ping accepted" | tail -1' | tee "$L"
ssh cinnabar.zt 'sudo systemctl stop ntfy-sh.service; /usr/bin/env date -u +%FT%TZ' | sed 's/^/stopped: /' | tee -a "$L"
```

Ask the operator to report when the healthchecks.io email saying the check is down arrives, with its time; record it.
Then:

```bash
ssh cinnabar.zt 'sudo systemctl start ntfy-sh.service; /usr/bin/env date -u +%FT%TZ' | sed 's/^/started: /' | tee -a "$L"
sleep 600
ssh cinnabar.zt 'sudo journalctl -u fleet-deadman --since -40min -o short-iso | grep -E "R9.4|external ping|no external ping|Failed"' | tee -a "$L"
```

Ask the operator to report the up email's time, and every `fleet-alerts` message since the stop; record them.

Expected: the down email's time minus the last accepted ping's is at most 15 min; the runs during the stop log `R9.4: anonymous publish … answered HTTP 000` and no ping; after the start a run logs `external ping accepted` and the up email follows; `AlertEvaluatorSilent` may fire and resolve after the start, and `FAILED fleet-deadman on cinnabar` arrives once ntfy is back; a down email later than 15 min after the last ping is a finding put to the operator.

- [ ] **Step 5: The evaluator stop (tasks.md 4.3)**

```bash
L=$REPO/logs/cam76-evidence/4.3-evaluator-stop-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'sudo systemctl stop fleet-alert.timer; /usr/bin/env date -u +%FT%TZ' | sed 's/^/stopped: /' | tee "$L"
sleep 1200
ssh magnetite.zt 'sudo systemctl start fleet-alert.timer; /usr/bin/env date -u +%FT%TZ' | sed 's/^/started: /' | tee -a "$L"
sleep 900
ssh cinnabar.zt 'sudo journalctl -u fleet-deadman --since -40min -o short-iso | grep -E "heartbeat\(s\) on|external ping|no external ping"' | tee -a "$L"
```

Ask the operator for the times of `[FIRING] AlertEvaluatorSilent magnetite`, the down email, `[RESOLVED] AlertEvaluatorSilent magnetite` and the up email; record them.

Expected: the runs with `0 heartbeat(s)` log `no external ping`; all four messages arrive, the down email within 15 min of the last accepted ping before the stop.

- [ ] **Step 6: A day without a false email (tasks.md 4.4)**

24 h after Step 5's start:

```bash
L=$REPO/logs/cam76-evidence/4.4-day-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh cinnabar.zt 'sudo journalctl -u fleet-deadman --since -24h -o cat | grep -c "external ping accepted"; sudo journalctl -u fleet-deadman --since -24h -o cat | grep -c "no external ping" || true' | tee "$L"
```

Ask the operator to confirm that no healthchecks.io email arrived in the 24 h and that the check's log, which keeps its last 100 pings (about 8 h), shows a ping every 5 min apart from runs that logged no heartbeat; record the reply.

Expected: about 288 accepted pings, the no-ping count near 0, and no email.
