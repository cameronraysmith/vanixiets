### Task 9: Acceptance

Implements `tasks.md` 9.1–9.4 (design Migration Plan steps 5, 7 and 8; Linear CAM-71's AC4 for cinnabar; FA `A missing signal is itself reported`; FAI `An always-on host's silence is reported`; FII `otel-envelope regulates each agent from its own collector`; HMC `Series cardinality stays bounded`, `A failed collection or store job notifies a person`, `Each agent host contributes its own signals to the telemetry store`; TSI `Failure notices are posted to one topic`, `Scrape targets are reached on loopback`; WA `A50 — electrum, galena and scheelite exist only while provisioned on demand`).
No pull request; the operator stops and starts units on cinnabar by hand in Steps 2 and 3, and nothing here touches pyrite.
Steps 2 and 3 run after `tasks.md` 6.7, so the always-on list is magnetite and cinnabar; Step 1 starts after `tasks.md` 4.5 and is read after 24 h, from pyrite's deploy for pyrite.

**Files:**
- Create (git-ignored): `logs/s4-evidence/9.<n>-*.log`; `window.env` gains `CINNABAR_STOP_EPOCH`, `CINNABAR_START_EPOCH`, `EXPORTER_STOP_EPOCH`, `EXPORTER_START_EPOCH`

**Interfaces:**
- Consumes: Tasks 4 to 7 deployed; `gsql.sh`, `promq.sh`; `window.env`.
- Produces: the acceptance records `verify.md` cites.

- [ ] **Step 1: A day of envelopes and the stored bounds (tasks.md 9.1)**

rehearse: magnetite, cinnabar and pyrite (read-only):

```bash
. logs/s4-evidence/window.env
L=logs/s4-evidence/9.1-day-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for t in magnetite.zt root@49.13.68.78 pyrite.zt; do echo "== $t"
  ssh "$t" "bash -c 'sudo journalctl -u otel-envelope -o cat --since \"-24h\" | grep -cE \"^otel-envelope: .*FAIL\"; sudo journalctl -u otel-envelope -o cat --since \"-24h\" | grep -c \"^otel-envelope: C1\"'"
done 2>&1 | tee "$L"
logs/s4-evidence/gsql.sh fleet "SELECT host_name, systemd_unit_name LIKE 'observability-notify@%' AS notifier, count(DISTINCT systemd_unit_name) FROM systemd_unit_state WHERE greptime_timestamp > now() - INTERVAL '24 hours' GROUP BY host_name, notifier ORDER BY host_name, notifier" | tee -a "$L"
logs/s4-evidence/gsql.sh fleet "SELECT host_name, count(DISTINCT process_executable_name) FROM process_memory_usage_bytes WHERE greptime_timestamp > now() - INTERVAL '24 hours' GROUP BY host_name" | tee -a "$L"
logs/s4-evidence/gsql.sh fleet "SELECT DISTINCT host_name, systemd_unit_name FROM systemd_unit_state WHERE systemd_unit_name LIKE 'observability-notify@%' AND greptime_timestamp > now() - INTERVAL '24 hours' ORDER BY host_name" | tee -a "$L"
```

Expected: `0` failing lines and about 288 `C1` lines per host (one run each 5 min); per host at most 40 ordinary unit names, at most 30 process names, and every stored notifier instance `observability-notify@<u>.service.service` with `<u>` in that host's `notifiedUnits`; any exceedance is a finding against design D8's bounds, recorded with the names.

- [ ] **Step 2: cinnabar's silence while ntfy runs (tasks.md 9.2, AC4)**

The orchestrator asks the operator to watch `fleet-alerts` on their ntfy client, then (rehearse: echoed):

```bash
echo "CINNABAR_STOP_EPOCH=$(/bin/date -u +%s)" >> logs/s4-evidence/window.env
ssh root@49.13.68.78 'bash -c "systemctl stop opentelemetry-collector"'
```

After 15 min:

```bash
ssh root@49.13.68.78 'bash -c "systemctl start opentelemetry-collector"'
echo "CINNABAR_START_EPOCH=$(/bin/date -u +%s)" >> logs/s4-evidence/window.env
```

Fifteen minutes after the start, rehearse: magnetite and cinnabar:

```bash
. logs/s4-evidence/window.env
L=logs/s4-evidence/9.2-cinnabar-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o cat --since @$CINNABAR_STOP_EPOCH | grep -E \"RuleSignalMissing cinnabar\"'" | tee "$L"
ssh root@49.13.68.78 "bash -c 'sudo awk -v t=$CINNABAR_STOP_EPOCH \"\\\$1 >= t\" /var/lib/observability-notify/failed.log; sudo journalctl -u otel-envelope -o cat --since @$CINNABAR_STOP_EPOCH | grep -E \"^otel-envelope: C1\"'" | tee -a "$L"
```

Expected: one `failed.log` line for `otel-envelope.service` within 10 min of the stop (C1 failing on its second run) and its `RESOLVED` after the start, as the FII scenario bounds it; one `[FIRING] RuleSignalMissing cinnabar` within 15 min of the stop and one `[RESOLVED] RuleSignalMissing cinnabar` after the start, as the FA scenario bounds it; no `FAILED opentelemetry-collector.service`, because `systemctl stop` is not a failure; the operator confirms the four posts on `fleet-alerts` with their times.

- [ ] **Step 3: cinnabar's stopped exporter (tasks.md 9.3)**

As Step 2, with `prometheus-node-exporter` in place of the collector, the stop held for 15 min, and `EXPORTER_STOP_EPOCH`/`EXPORTER_START_EPOCH` recorded.
rehearse: cinnabar:

```bash
. logs/s4-evidence/window.env
ssh root@49.13.68.78 "bash -c 'sudo journalctl -u otel-envelope -o cat --since @$EXPORTER_STOP_EPOCH | grep -E \"^otel-envelope: C2\"; sudo awk -v t=$EXPORTER_STOP_EPOCH \"\\\$1 >= t\" /var/lib/observability-notify/failed.log'" | tee logs/s4-evidence/9.3-exporter-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `C2 targets: FAIL node` on the second run after the stop, within 10 min; one `failed.log` line; the operator receives `FAILED otel-envelope.service on cinnabar` within 10 min and `[FIRING] LocalExporterDown cinnabar` after the rule's 10 min `for`, and after the start both `RESOLVED`; the evaluator's journal on magnetite shows the `LocalExporterDown` pair.

- [ ] **Step 4: The hosts that are not provisioned (tasks.md 9.4)**

```bash
L=logs/s4-evidence/9.4-unprovisioned-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
logs/s4-evidence/promq.sh 'count by (host_name) (system_memory_usage_bytes)' | tee "$L"
rg -n 'enabled = ' modules/terranix/hetzner.nix modules/terranix/gcp.nix | tee -a "$L"
```

Expected: magnetite, cinnabar and pyrite only; electrum, galena and scheelite `enabled = false` (A50's monitor).
