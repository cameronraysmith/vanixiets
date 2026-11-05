### Task 1: Plan review and baselines

Implements `tasks.md` 1.1–1.2 (design "Open Questions"; the S3 retrospective's plan-review rule).
Nothing in this task changes the repository outside this change directory.

**Files:**
- Modify: this change's `design.md`, `tasks.md`, `plan.md`, `plan/` and `specs/` with accepted findings and answers only
- Create (git-ignored): `logs/cam73-evidence/1.1-plan-review-<ts>.md`, `logs/cam73-evidence/1.2-baseline-<ts>.log`

**Interfaces:**
- Consumes: the planning artifacts.
- Produces: the operator's answers to Q1–Q4, and the baseline costs and host figures Tasks 2 to 6 compare against.

- [ ] **Step 1: Plan review (tasks.md 1.1)**

Dispatch one read-only subagent of the default `task` agent type with this brief: answer the holistic review's four questions over `openspec/changes/serve-the-fleet-dashboard/{design.md,tasks.md,plan.md,plan/,specs/}` (critical oversights; significant architecture improvements; checks that cannot fail, clauses that restate the line they judge, and properties nothing covers; checks or mechanisms that cost more than the invariant they protect), and list each leg, mutant and assertion of plan Tasks 2 to 5 with the two independently defined values it compares.
Save its answer to `logs/cam73-evidence/1.1-plan-review-$(/bin/date -u +%Y%m%dT%H%M%SZ).md`.
Put each finding and design Q1 to Q4 to the operator; apply accepted findings and the answers to the planning artifacts; record each decision in the log.
Then run `openspec validate serve-the-fleet-dashboard --strict` and enqueue the planning pull request.

Expected: `Change 'serve-the-fleet-dashboard' is valid`, and every finding and question has a recorded decision.

- [ ] **Step 2: Evaluation-cost baseline (tasks.md 1.2)**

At `main@origin`, before any commit of this change:

```bash
L=logs/cam73-evidence/1.2-baseline-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/nixos-magnetite-stats.json \
  nix eval --option eval-cache false --raw .#.checks.x86_64-linux.nixos-magnetite.drvPath >/dev/null
echo "nixos-magnetite $(jq -r '[.gc.totalBytes, .cpuTime] | @tsv' /tmp/nixos-magnetite-stats.json)" | tee -a "$L"
```

Expected: one line, recorded for comparison in Task 5 Step 4.

- [ ] **Step 3: magnetite's current state (tasks.md 1.2)**

```bash
ssh magnetite.zt 'bash -s' <<'EOF' | tee -a "$L"
echo "== listeners"; ss -ltnH | awk '{print $4}' | sort -u
echo "== 8095"; ss -ltnH | awk '{print $4}' | grep -c ':8095$' || true
echo "== memory"; free -m
echo "== store unit"; systemctl show greptimedb -p OOMScoreAdjust -p MemoryHigh -p MemoryMax
EOF
clan vars check magnetite 2>&1 | tee -a "$L"
```

Expected: `8095` count `0`; `OOMScoreAdjust=500`; `clan vars check` reports nothing to regenerate.

The statement of `cameron`'s Kanidm groups, first planned here, is taken at deployment instead: Task 6 Step 3 runs `kanidm group get perses_users` before the refusal login (operator decision, 2026-11-05).
