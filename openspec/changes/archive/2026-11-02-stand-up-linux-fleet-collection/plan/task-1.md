### Task 1: Plan review, baselines and rehearsal

Implements `tasks.md` 1.1–1.3 (S2-R6 promotions: plan review gated on a complete dispositions table; rehearsal of every verification block on cinnabar, magnetite and pyrite; evaluation cost measured before any change).
This task changes no repository file outside this change directory; on pyrite it runs read commands only, and on cinnabar and magnetite it starts, stops and restarts nothing.

**Files:**
- Modify, only for accepted plan-review findings and rehearsal fixes: `openspec/changes/stand-up-linux-fleet-collection/{design.md,tasks.md,plan.md,plan/*.md}` and `specs/`, before the planning pull request; `design.md` edits are coordinated with whoever owns it at the time.
- Create (git-ignored): `logs/s4-evidence/1.1-plan-review-<ts>.md`, `logs/s4-evidence/1.2-baseline-<ts>.log`, `logs/s4-evidence/1.2-stats/<check>.json`, `logs/s4-evidence/1.3-rehearsal-<ts>.log`, `logs/s4-evidence/gsql.sh`, `logs/s4-evidence/promq.sh`.

**Interfaces:**
- Consumes: the repository at `main@origin`; GR §6's baselines (otel-collector-config 488,430,112 B on 2026-10-28); the runbook's `/v1/sql` helper (`packages/docs/src/content/docs/development/operations/fleet-observability.md:360-365`).
- Produces: `logs/s4-evidence/gsql.sh` (store SQL as `regulator`) and `logs/s4-evidence/promq.sh` (PromQL as `regulator`), used by Tasks 4 to 9; the baseline figures every later cost step compares with; a rehearsal log that every verification block of Tasks 4 to 9 has run once.

- [ ] **Step 1: Review the plan before any implementation commit (tasks.md 1.1)**

The orchestrator spawns one subagent with the `task` tool, agent type `task` (the default), on an Opus model, read-only, with exactly this prompt:

```text
You are reviewing the plan of the vanixiets change stand-up-linux-fleet-collection (Linear CAM-71) before any of it is implemented. The repository is $REPO, jj-colocated; work in it read-only.

Read-only means: do not edit, create or delete any file; run no jj or git command that changes anything; run no nix build, no deploy, no ssh, and touch no Linear issue. You may read files, run `nix eval` (read-only), `rg`, and `gh api` GET requests.

Read, in this order:
- openspec/changes/stand-up-linux-fleet-collection/brainstorm.md, proposal.md, design.md, tasks.md, plan.md, plan/task-*.md and specs/*/spec.md
- docs/notes/development/observability/charter.md (v23 at the end), decisions/ADR-003-collection-topology.md, ADR-004-signal-scope-and-schema.md, ADR-009-alerting.md, components/otel-collector.md, components/host-probes.md
- logs/s4/grounding.md, logs/s4/design-inputs.md
- openspec/changes/archive/2026-10-28-stand-up-devloop-collection/retrospective.md §6, and the §6 of the two other archived observability changes
- every repository file the plan modifies, at the lines it cites, and vendor source at the pinned nixpkgs when a finding depends on it

Answer the holistic review's four questions over design.md, tasks.md, plan.md, plan/ and the specs:
1. Critical oversights: what will fail, lose data, leak a key or credential, break the mesh or a host that cannot be recovered remotely, or leave a requirement undischarged if the plan is executed as written?
2. Significant architecture improvements: where would a different design be clearly simpler or more robust for the same requirements?
3. Checks that cannot fail, clauses that restate the line they judge (a value compared with the line that sets it, or two values from one source), and properties that no check, assertion, container case or deploy observation covers.
4. Checks or mechanisms that cost more than the invariant they protect (evaluation cost against the 0.5 GiB budget, build time, operational burden).

Then list every new check clause, module or host assertion, container case and fixture leg in plan Tasks 2, 3, 6 and 7, each with its two independently defined value sources, each source given as file:line or as the evaluated attribute it reads, and say for each whether the two sources are independent; flag any whose sources are one value, or a value and the line that sets it.

Cite file:line for every claim; mark anything you did not verify [INFERENCE].

Your final answer is the report, in markdown, with exactly these headings in this order:
## Summary
## Findings
| Finding | Category | Severity | Belongs in |
|---|---|---|---|
## Finding details
## Clauses and assertions
| Task | Clause or assertion | Value source A | Value source B | Independent |
|---|---|---|---|---|
```

The orchestrator writes the answer verbatim to `logs/s4-evidence/1.1-plan-review-<ts>.md`, puts each finding to the operator, and appends:

```markdown
## Dispositions

| Finding | Disposition | Operator's reason | Applied in |
|---|---|---|---|
```

Disposition is exactly one of `accepted`, `rejected` or `deferred`.
Run:

```bash
f=$(ls -t logs/s4-evidence/1.1-plan-review-*.md | head -n 1)
diff <(awk '/^## Findings/{s=1;next} /^## /{s=0} s && /^\| F[0-9]+ /{print $2}' "$f" | sort -u) \
     <(awk '/^## Dispositions/{s=1;next} /^## /{s=0} s && /^\| F[0-9]+ \| (accepted|rejected|deferred) \|/{print $2}' "$f" | sort -u) \
  && echo dispositions-complete
```

Expected: `dispositions-complete`.
Accepted findings are applied before the planning pull request is enqueued; its title names what it does in plain words, for example "Plan the collection of host metrics from every NixOS host".

- [ ] **Step 2: Record the baselines (tasks.md 1.2)**

Create the deploy worktree once, `git -C $REPO worktree add --detach $DEPLOY origin/main` (plan Global Constraints), and run the cost measurements in it, at `origin/main`, writing their output to `$REPO/logs/s4-evidence/` (`cd $DEPLOY` and prefix each `logs/` path below with `$REPO/`):

```bash
mkdir -p logs/s4-evidence/1.2-stats
for c in otel-collector-config fleet-alert greptimedb-envelope nixos-magnetite nixos-cinnabar nixos-pyrite; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=logs/s4-evidence/1.2-stats/$c.json \
    nix eval --option eval-cache false --raw ".#.checks.x86_64-linux.$c.drvPath" >/dev/null
  printf '%s %s %s\n' "$c" "$(jq '.gc.totalBytes' logs/s4-evidence/1.2-stats/$c.json)" "$(jq '.cpuTime' logs/s4-evidence/1.2-stats/$c.json)"
done 2>&1 | tee logs/s4-evidence/1.2-baseline-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
clan vars get magnetite ntfy-alerter/token | sha256sum   # the decrypted value, never printed; Task 2 Step 4 compares with it
sha256sum vars/shared/zerotier-ip-magnetite-zerotier/ip/value
cat vars/shared/zerotier-ip-magnetite-zerotier/ip/value; echo
```

Expected: six lines `<check> <bytes> <seconds>`, `otel-collector-config` near 488,430,112 and below 536,870,912; the address `fddb:4344:343b:14b9:399:930f:39db:40d2`.
Append the two hashes and the address to the same log.

Create `logs/s4-evidence/gsql.sh` (git-ignored), which runs one SQL statement on magnetite's store as `regulator` with the password on curl's stdin:

```bash
#!/usr/bin/env bash
# gsql.sh DB SQL: one statement on magnetite's store as regulator; prints TSV rows.
set -euo pipefail
db=$1 sql=$2
# The deployed path of the regulator password, from magnetite's evaluated configuration.
pw_path=${GSQL_PW_PATH:-$(nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path)}
# ssh joins its arguments into one remote command line, so each is quoted for the remote shell.
ssh magnetite.zt "bash -s -- $(printf '%q ' "$db" "$sql" "$pw_path")" <<'EOS'
set -euo pipefail
db=$1 sql=$2 pw_path=$3
pw=$(sudo cat "$pw_path")
printf 'user = "regulator:%s"\n' "$pw" | curl -sS --fail-with-body --config - \
  --data-urlencode "sql=$sql" "http://127.0.0.1:4000/v1/sql?db=$db" |
  jq -r '.output[0].records.rows[]? | map(if . == null then "NULL" else tostring end) | @tsv'
EOS
```

Create `logs/s4-evidence/promq.sh` the same way, posting `query=<expr>` to `/v1/prometheus/api/v1/query` with `x-greptime-db-name: fleet` and printing `.data.result[]? | [.metric.host_name // "", .value[1]] | @tsv`.
Rehearse both in Step 3; if the credential path differs from the one the evaluator loads, fix the script there.

Record the unit and process counts:

```bash
logs/s4-evidence/gsql.sh fleet "SELECT host_name, systemd_unit_name LIKE 'observability-notify@%' AS notifier, count(DISTINCT systemd_unit_name) FROM systemd_unit_state WHERE greptime_timestamp > now() - INTERVAL '1 hour' GROUP BY host_name, notifier ORDER BY host_name, notifier"
logs/s4-evidence/gsql.sh fleet "SELECT host_name, count(DISTINCT process_executable_name) FROM process_memory_usage_bytes WHERE greptime_timestamp > now() - INTERVAL '1 hour' GROUP BY host_name"
```

Expected: `magnetite false 28` and `magnetite true 16` (GR §4) or the current figures, and one process count for magnetite.

- [ ] **Step 3: Rehearse every verification block (tasks.md 1.3)**

For each fenced verification block in `plan/task-4.md`, `task-5.md`, `task-6.md`, `task-7.md` and `task-9.md` marked `rehearse:`, run it once as written against the host it names, but with every mutating command (deploy, `systemctl stop|start|restart`, drop-ins, powering off) replaced by an `echo` of the command; every block reading `opentelemetry-collector`'s telemetry on cinnabar or pyrite, where the collector does not run yet, is expected to fail with `curl: (7)` and is recorded as such.
On pyrite (over `pyrite.zt` as the ssh user) only these are run: `awk '/^btime/ {print $2}' /proc/stat` (never `uptime -s`, which fails for the ssh user there), `getfacl /dev/nvme0`, `ls -l /dev/nvme0`, `systemctl is-active zerotierone`, `sudo zerotier-cli info` (without `sudo` the ssh user cannot read the daemon's port and token, rc 2), `wc -l < /var/log/deploy-record.jsonl`, `sudo journalctl -u zerotierone -n 5 -o cat`.
On magnetite also read `curl -s http://127.0.0.1:8888/metrics | grep -E '^otelcol_(exporter_queue_(size|capacity)|exporter_(send|enqueue)_failed|receiver_refused)' | head -n 20` and confirm what the review read live on 2026-10-29: `otelcol_exporter_queue_capacity` exists with a `data_type` label and the counters carry no `_total` suffix; Task 3 Step 1's fixtures copy these names.
Time design D8's budget queries on magnetite as `regulator`, read-only, each as `time logs/s4-evidence/gsql.sh fleet "<query>"` under bash on stibnite (bash's `time` keyword, since stibnite's `/bin/date` has no `%N`), whose `real` is an upper bound including the ssh round trip: B1 `SELECT count(DISTINCT __tsid) FROM greptime_physical_table WHERE greptime_timestamp > now() - INTERVAL '1 hour'`; B2 one query with a `count(DISTINCT <tag>)` for each tag column of `greptime_physical_table` (the columns listed by `SELECT column_name FROM information_schema.columns WHERE table_name = 'greptime_physical_table' AND semantic_type = 'TAG'`) over the same hour; B3's three per-host counts; B4's notifier count; B5's `devloop` row count over 24 h; B6's `information_schema` read; record each duration, their sum as the expected runtime of an hourly run against `TimeoutStartSec` of 240 s, and the number of tag columns.

Each block runs on stibnite in `$REPO` and makes its own ssh calls, so it is not wrapped in another ssh; it is written to a file and run with stdin closed, because an ssh inside a block reading the script from stdin consumes the rest of it.
In the copy, `logs/s4-evidence/window.env` and each `logs/s4-evidence/<4-9>.<n>-*` path become `logs/s4-evidence/1.3-rehearsal/…`, with rehearsal epochs in `1.3-rehearsal/window.env`, so no rehearsal output is taken for a real record later (Task 4 Step 3 globs `4.1-pre-cinnabar-*.log`):

```bash
{ printf 'set -uo pipefail\n'; cat logs/s4-evidence/1.3-rehearsal/<task>-<line>.sh; printf 'echo "rc=$?"\n'; } > /tmp/rehearse.sh
bash /tmp/rehearse.sh </dev/null 2>&1 | tee -a logs/s4-evidence/1.3-rehearsal-<ts>.log
```

Expected: every block prints `rc=0`, or the documented expected code; a block that fails for a reason of its own (a missing `sudo`, a GNU-only flag on stibnite, a jq filter failing on an absent field, `status` used in zsh) is fixed in its plan file and rerun, and the fix is listed at the end of the log under `## Fixes`.
