### Task 5: pyrite, with the operator present

Implements `tasks.md` 5.1–5.6 (design D4, D13, Migration Plan steps 4 and 7; O4, O7; FII `pyrite's NVMe health is read by a loopback exporter`; HMC `Each agent host contributes its own signals to the telemetry store`; DCI `Each agent host's collector ships its own deploy records`; DC `Every dev-loop event is recorded once and kept for a year`; FA `A missing signal is itself reported`; FAI `An always-on host's silence is reported`; WA `A13 — Resuming this laptop from a suspended state is unreliable, and recovering a failed resume requires a person at the machine`, `A51 — pyrite's NVMe controller answers the SMART health log at the pinned smartmontools`).
pyrite cannot be recovered remotely after a failed boot or network, so every step that changes it runs only after the operator has confirmed, in this session, being physically at pyrite (S3-R6; O4, O7).
Pull request 1 leaves pyrite with `collect = false`, so pyrite runs exactly what it ran before until Step 2's own pull request, enqueued only after the presence gate, turns its collection on.
There are two sittings: the first (Steps 1–4) after Task 4 has passed, the second (Steps 5–6) after `tasks.md` 6.7.
The switch stops and starts `zerotierone` on pyrite (GR §3), so the deploy runs over pyrite's LAN address, not `pyrite.zt`.
No reboot and no `udevadm trigger` is part of this task: the exporter's `ExecStartPre` grants the device ACL itself (design D4, D13).

**Files:**
- Create (git-ignored): `logs/pyrite-<ts>.log`, `logs/s4-evidence/5.<n>-*.log`; `logs/s4-evidence/window.env` gains `PYRITE_DEPLOY_EPOCH`, `PYRITE_OFFLINE_START`, `PYRITE_OFFLINE_END`

**Interfaces:**
- Consumes: Task 4 passed; `$DEPLOY`, the deploy worktree; pyrite's LAN address `$PYRITE_LAN`, which the operator gives at Step 1; `logs/s4-evidence/gsql.sh` and `promq.sh`.
- Produces: pyrite's first stored series, SMART read and deploy-record count; the offline window Task 10 cites.

- [ ] **Step 1: Presence gate, first sitting (tasks.md 5.1)**

The orchestrator asks the operator, and does not proceed without the answer: "Are you physically at pyrite now, with it on mains power and on its LAN, and what is its LAN address?"
Record the answer verbatim with `/bin/date -u` in `logs/s4-evidence/5.1-presence-<ts>.log`, and check from stibnite, read-only:

```bash
ssh root@"$PYRITE_LAN" 'bash -c "hostname; awk \"/^btime/ {print \\\$2}\" /proc/stat; systemctl is-active zerotierone"'
```

Expected: `pyrite`, its boot time as an epoch, `active`.
Without a recorded yes, Steps 2 to 4 do not run.

- [ ] **Step 2: Turn on pyrite's collection and deploy it (tasks.md 5.2)**

Only after Step 1's recorded yes: in a change off `main@origin`, change `collect = false;` to `collect = true;` in pyrite's one line of `modules/lib/observability-hosts.nix` (`pyrite = agent [ ] // { collect = false; smartDevices = [ "/dev/nvme0" ]; };`), run `nix fmt`, and confirm `nix eval --raw .#nixosConfigurations.pyrite.config.system.build.toplevel.drvPath` succeeds; commit it alone with a plain message, for example "Start collecting pyrite's host metrics and disk health", open its pull request with the same title and a body saying it turns on the collector agent and the disk-health exporter for pyrite ahead of a deploy made with someone at the machine, and let it merge through the queue while the operator stays at pyrite.
Then, in `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty` (`window.env` is `$REPO/logs/s4-evidence/window.env`):

```bash
echo "PYRITE_DEPLOY_EPOCH=$(/bin/date -u +%s)" >> "$REPO/logs/s4-evidence/window.env"
clan machines update pyrite --target-host root@"$PYRITE_LAN" 2>&1 | tee logs/pyrite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
rehearse: pyrite (rehearsed with read commands only):

```bash
ssh root@"$PYRITE_LAN" 'bash -c "systemctl is-active opentelemetry-collector otel-envelope.timer prometheus-smartctl-exporter zerotierone; zerotier-cli info"'
```

Expected: `active` four times and `200 info … ONLINE`; if `zerotierone` is not active or not `ONLINE`, the operator restores the network at the machine before anything else, and a failed deploy is rolled back from the machine (`nixos-rebuild switch --rollback`) with the operator there.

- [ ] **Step 3: The SMART read without a reboot (tasks.md 5.3)**

rehearse: pyrite and magnetite:

```bash
L=logs/s4-evidence/5.3-smart-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh root@"$PYRITE_LAN" 'bash -c "awk \"/^btime/ {print \\\$2}\" /proc/stat; getfacl -p /dev/nvme0; curl -s http://127.0.0.1:9633/metrics | grep -E \"^smartctl_device_(critical_warning|percentage_used)\""' | tee "$L"
sleep 120
logs/s4-evidence/promq.sh 'smartctl_device_critical_warning{host_name="pyrite"}' | tee -a "$L"
logs/s4-evidence/promq.sh 'smartctl_device_percentage_used{host_name="pyrite"}' | tee -a "$L"
```

Expected: the boot epoch earlier than `PYRITE_DEPLOY_EPOCH` (no reboot); `group:smartctl-exporter-access:rw-` in the ACL; the exporter's two series locally; one stored row each for pyrite, critical warning `0` and percentage used near A51's 11 (AC3).
If the series are missing, read `sudo journalctl -u prometheus-smartctl-exporter -n 50 -o cat` on pyrite and record it; A51's violation condition applies if the exporter reads the device but reports no health log.

- [ ] **Step 4: pyrite's first-deploy capture (tasks.md 5.4)**

rehearse: pyrite and magnetite:

```bash
L=logs/s4-evidence/5.4-pyrite-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for m in system_memory_usage_bytes systemd_unit_state node_zfs_zpool_state system_filesystem_usage_bytes; do
  printf '%s ' "$m"; logs/s4-evidence/promq.sh "count(${m}{host_name=\"pyrite\"})"
done | tee "$L"
lines=$(ssh root@"$PYRITE_LAN" 'bash -c "wc -l < /var/log/deploy-record.jsonl"')
rows=$(logs/s4-evidence/gsql.sh devloop "SELECT count(*) FROM deploy_record WHERE host = 'pyrite'")
echo "pyrite lines=$lines rows=$rows" | tee -a "$L"
ssh root@"$PYRITE_LAN" 'bash -c "sudo journalctl -u otel-envelope -o cat -n 20 | grep -E \"^otel-envelope: \""' | tee -a "$L"
logs/s4-evidence/promq.sh 'count by (host_name) (system_memory_usage_bytes)' | tee -a "$L"
```

Expected: a non-zero count for each of the four metrics; `lines` equal `rows`; every envelope clause `ok`; three hosts, magnetite, cinnabar and pyrite, which completes AC1 for the provisioned hosts.
An hour after pyrite's series first appear, record every post naming pyrite from the evaluator's journal with its cause, as Task 4 Step 5 did for cinnabar: `ssh magnetite.zt 'bash -c "sudo journalctl -u fleet-alert -o cat --since \"-70min\" | grep -E \"pyrite\" || true"' | tee -a "$L"`; a post with no benign cause is a finding.
The first sitting ends here; the operator may leave pyrite.

- [ ] **Step 5: Presence gate, second sitting (tasks.md 5.5)**

Only after `tasks.md` 6.7 has passed, so the rules read always-on and expected hosts from the table: the orchestrator asks "Are you physically at pyrite now?" and records the answer with `/bin/date -u` in `logs/s4-evidence/5.5-presence-<ts>.log`.
Without a recorded yes, Step 6 does not run.

- [ ] **Step 6: pyrite offline for 20 minutes (tasks.md 5.6)**

Record whether any pyrite instance is firing first:

```bash
ssh magnetite.zt 'bash -c "sudo jq -c \"[.instances // {} | to_entries[] | select(.key | test(\\\"pyrite\\\")) | .key]\" /var/lib/private/fleet-alert/state.json 2>/dev/null || sudo jq -c \"[.instances // {} | to_entries[] | select(.key | test(\\\"pyrite\\\")) | .key]\" /var/lib/fleet-alert/state.json"'
```

Then the operator takes pyrite off its network (unplugging or disabling Wi-Fi at the machine) or powers it off, and the orchestrator records `PYRITE_OFFLINE_START=$(/bin/date -u +%s)`; after 20 min the operator restores it and the orchestrator records `PYRITE_OFFLINE_END`.
rehearse: magnetite:

```bash
. logs/s4-evidence/window.env
L=logs/s4-evidence/5.6-offline-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -o cat --since @$PYRITE_OFFLINE_START --until @$(( PYRITE_OFFLINE_END + 900 ))'" | grep -iE 'pyrite' | tee "$L"; echo "matches=${PIPESTATUS[1]}" | tee -a "$L"
ssh root@"$PYRITE_LAN" 'bash -c "curl -s http://127.0.0.1:8888/metrics | grep -E \"^otelcol_exporter_queue_size\""' | tee -a "$L"
```

Expected: no line naming pyrite (`grep` exit 1, `matches=1`) from the start of the window until 15 min after it ends, so no `RuleSignalMissing pyrite`, no resolution and no repeat of a firing instance; the queue back to 0 within 30 min; the operator confirms no message naming pyrite reached `fleet-alerts` on their ntfy client.
