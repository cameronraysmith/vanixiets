### Task 1: Plan review and baselines

Implements `tasks.md` 1.1–1.2 (design D2, D8; the S3 retrospective's plan-review rule).
Nothing in this task changes the repository outside this change directory.

**Files:**
- Modify: this change's `design.md`, `tasks.md`, `plan.md`, `plan/` and `specs/` with accepted findings only
- Create (git-ignored): `logs/cam76-evidence/1.1-plan-review-<ts>.log`, `logs/cam76-evidence/1.2-baseline-<ts>.log`

**Interfaces:**
- Consumes: the planning artifacts.
- Produces: the baseline costs Task 2 Step 6 compares against, and the count of heartbeat-less dead-man runs that Task 2 Step 4 depends on.

- [ ] **Step 1: Plan review (tasks.md 1.1)**

Dispatch one read-only subagent of the default `task` agent type with this brief: answer the holistic review's four questions over `openspec/changes/watch-the-alert-path-externally/{design.md,tasks.md,plan.md,plan/,specs/}` (critical oversights; significant architecture improvements; checks that cannot fail, clauses that restate the line they judge, and properties nothing covers; checks or mechanisms that cost more than the invariant they protect), and list each leg, mutant and assertion of plan Task 2 with the two independently defined values it compares.
Save its answer to `logs/cam76-evidence/1.1-plan-review-$(/bin/date -u +%Y%m%dT%H%M%SZ).log`.
Put each finding to the operator; apply accepted findings to the planning artifacts; record each decision under the finding in the log.
Then run `openspec validate watch-the-alert-path-externally --strict` and enqueue the planning pull request.

Expected: `Change 'watch-the-alert-path-externally' is valid`, and every finding has a recorded decision.

- [ ] **Step 2: Evaluation-cost baselines (tasks.md 1.2)**

At `main@origin`, before any commit of this change:

```bash
L=logs/cam76-evidence/1.2-baseline-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for c in fleet-alert nixos-cinnabar; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c-stats.json \
    nix eval --option eval-cache false --raw .#.checks.x86_64-linux.$c.drvPath >/dev/null
  echo "$c $(jq -r '[.gc.totalBytes, .cpuTime] | @tsv' /tmp/$c-stats.json)" | tee -a "$L"
done
```

Expected: two lines, each below 536,870,912 B for `fleet-alert`; `nixos-cinnabar` is recorded for comparison only.

- [ ] **Step 3: The dead-man's last week (tasks.md 1.2)**

```bash
ssh cinnabar.zt 'bash -s' <<'EOF' | tee -a "$L"
sudo journalctl -u fleet-deadman --since -7d -o cat > /tmp/deadman-7d.log
echo "runs: $(grep -c 'heartbeat(s) on' /tmp/deadman-7d.log || true)"
echo "zero-heartbeat runs: $(grep -c ': 0 heartbeat(s) on' /tmp/deadman-7d.log || true)"
echo "failed runs: $(sudo journalctl -u fleet-deadman --since -7d -o cat | grep -c 'Failed with result' || true)"
grep -o '[0-9]* heartbeat(s) on' /tmp/deadman-7d.log | awk '{ if ($1 == 0) { n++; if (n > max) max = n } else n = 0 } END { print "longest run of zero-heartbeat runs: " max + 0 }'
rm /tmp/deadman-7d.log
EOF
```

Expected: about 2,016 runs; a longest run of three or more zero-heartbeat runs is an episode that, with the 5 min period and 10 min grace, would have emailed; each such episode, found with `grep -n` in the same journal, is put to the operator before Task 2 Step 4, with its cause from the evaluator's journal on magnetite at that time.
