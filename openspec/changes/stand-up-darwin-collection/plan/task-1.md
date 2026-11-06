### Task 1: Plan review, baselines, rehearsal and the omnigent gate

Implements `tasks.md` 1.1–1.4 (S4-R6 promotions: plan review gated on a complete dispositions table; evaluation cost measured before any change; rehearsal of every verification block on stibnite and magnetite; vendored-tool probes with the consumers' exact argument lists, the schema `plan` instruction promoted in #3690; and O9's gate on the omnigent session).
This task changes no repository file outside this change directory; on stibnite and magnetite it runs read commands only, and it starts, stops, loads or restarts no launchd job and no systemd unit.

**Files:**
- Modify, only for accepted plan-review findings and rehearsal fixes: `openspec/changes/stand-up-darwin-collection/{design.md,tasks.md,plan.md,plan/*.md}` and `specs/`, before the planning pull request; `design.md` edits are coordinated with whoever owns it at the time.
- Create (git-ignored): `logs/s5-evidence/1.1-plan-review-<ts>.md`, `logs/s5-evidence/1.2-baseline-<ts>.log`, `logs/s5-evidence/1.2-stats/<check>.json`, `logs/s5-evidence/gsql.sh`, `logs/s5-evidence/promq.sh`, `logs/s5-evidence/1.3-rehearsal-<ts>.log`, `logs/s5-evidence/1.3-rehearsal/…`, `logs/s5-evidence/1.3-fixtures/…`, `logs/s5-evidence/1.4-gate-<ts>.log`.

**Interfaces:**
- Consumes: the repository at `main@origin`; S4's figures (`otel-envelope` 0.146 GiB, `fleet-alert` 0.316 GiB, `otel-collector-config` 0.443 GiB; design D13); the root pin, `nix eval --raw .#darwinConfigurations.stibnite.pkgs.path`, with `opentelemetry-collector-contrib` 0.155.0, `smartmontools` 7.5 and `prometheus-node-exporter` 1.12.1 (read with `nix eval --raw .#darwinConfigurations.stibnite.pkgs.<name>.version` on 2026-11-05).
- Produces: `logs/s5-evidence/gsql.sh DB SQL` (store SQL as `regulator`, TSV rows) and `logs/s5-evidence/promq.sh EXPR` (PromQL on `fleet` as `regulator`, one `host_name<TAB>value` line per series), used by Tasks 4 to 9; the baseline figures every later cost and hash step compares with; the recorded `launchctl print` and `smartctl` outputs under `logs/s5-evidence/1.3-fixtures/`, which Task 2 Step 5 copies into `modules/checks/otel-collector-darwin/`; the consumers' argument lists below, which Tasks 2 and 3 render exactly; and the gate commit of Step 4, onto which Tasks 2 and 3 are built.

- [ ] **Step 1: Review the plan before any implementation commit (tasks.md 1.1)**

The orchestrator spawns one subagent with the `task` tool, agent type `task` (the default), on an Opus model, read-only, with exactly this prompt:

```text
You are reviewing the plan of the vanixiets change stand-up-darwin-collection (Linear CAM-72) before any of it is implemented. The repository is $REPO, jj-colocated; work in it read-only.

Read-only means: do not edit, create or delete any file; run no jj or git command that changes anything; run no nix build, no deploy, no ssh, no launchctl other than `launchctl print`, and touch no Linear issue. You may read files, run `nix eval` (read-only), `rg`, and `gh api` GET requests.

Read, in this order:
- openspec/changes/stand-up-darwin-collection/brainstorm.md, proposal.md, design.md, tasks.md, plan.md, plan/task-*.md and specs/*/spec.md
- docs/notes/development/observability/charter.md (the last entry), decisions/ADR-003-collection-topology.md, ADR-004-signal-scope-and-schema.md, ADR-008-*.md, ADR-009-alerting.md, components/otel-collector.md, components/host-probes.md, components/fleet-alert.md
- openspec/changes/archive/2026-11-02-stand-up-linux-fleet-collection/retrospective.md §6, design.md and verify.md
- every repository file the plan modifies, at the lines it cites, and vendor source at the pinned nixpkgs, nix-darwin and clan-core when a finding depends on it

Answer the holistic review's four questions over design.md, tasks.md, plan.md, plan/ and the specs:
1. Critical oversights: what will fail, lose data, leak a key or token, break stibnite's activation or a host that cannot be recovered remotely, or leave a requirement undischarged if the plan is executed as written?
2. Significant architecture improvements: where would a different design be clearly simpler or more robust for the same requirements?
3. Checks that cannot fail, clauses that restate the line they judge (a value compared with the line that sets it, or two values from one source), and properties that no check, assertion, fixture leg or deploy observation covers.
4. Checks or mechanisms that cost more than the invariant they protect (evaluation cost against the 0.5 GiB budget, build time, operational burden on the operator at stibnite).

Then list every new check clause, module assertion, fixture leg and wrapper case in plan Tasks 2, 3 and 6, each with its two independently defined value sources, each source given as file:line or as the evaluated attribute it reads, and say for each whether the two sources are independent; flag any whose sources are one value, or a value and the line that sets it.

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

The orchestrator writes the answer verbatim to `logs/s5-evidence/1.1-plan-review-<ts>.md`, puts each finding to the operator, and appends:

```markdown
## Dispositions

| Finding | Disposition | Operator's reason | Applied in |
|---|---|---|---|
```

Disposition is exactly one of `accepted`, `rejected` or `deferred`.
Run:

```bash
f=$(ls -t logs/s5-evidence/1.1-plan-review-*.md | head -n 1)
diff <(awk '/^## Findings/{s=1;next} /^## /{s=0} s && /^\| F[0-9]+ /{print $2}' "$f" | sort -u) \
     <(awk '/^## Dispositions/{s=1;next} /^## /{s=0} s && /^\| F[0-9]+ \| (accepted|rejected|deferred) \|/{print $2}' "$f" | sort -u) \
  && echo dispositions-complete
```

Expected: `dispositions-complete`.
Accepted findings are applied before the planning pull request is enqueued; its title names what it does in plain words, for example "Plan the collection of stibnite's host metrics on darwin".

- [ ] **Step 2: Record the baselines (tasks.md 1.2)**

Create the deploy worktree once, `git -C $REPO worktree add --detach $DEPLOY origin/main` (plan Global Constraints), and run the measurements in it at `origin/main`, writing to `$REPO/logs/s5-evidence/` (`cd $DEPLOY` and prefix each `logs/` path below with `$REPO/`), under `/bin/bash` on stibnite:

```bash
set -uo pipefail
mkdir -p logs/s5-evidence/1.2-stats
L=logs/s5-evidence/1.2-baseline-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
git rev-parse HEAD | tee "$L"
for c in x86_64-linux.otel-envelope x86_64-linux.fleet-alert x86_64-linux.otel-collector-config x86_64-linux.nixos-magnetite aarch64-darwin.darwin-stibnite; do
  s=logs/s5-evidence/1.2-stats/${c#*.}.json
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=$s nix eval --option eval-cache false --raw ".#.checks.$c.drvPath" >/dev/null
  printf '%s %s %s\n' "$c" "$(jq '.gc.totalBytes // 0' "$s")" "$(jq '.cpuTime // 0' "$s")"
done 2>&1 | tee -a "$L"
echo "otel-ca $(sha256sum < vars/shared/otel-ca/ca.crt/value | cut -d' ' -f1)" | tee -a "$L"
# The decrypted token, hashed in a pipe and never printed; Task 2 Step 3 compares with it.
echo "ntfy-alerter $(clan vars get magnetite ntfy-alerter/token | sha256sum | cut -d' ' -f1)" | tee -a "$L"
ls vars/shared/ntfy-alerter/token/machines/ | tee -a "$L"
find vars/shared/otel-ca -maxdepth 3 | sort | tee -a "$L"
nix build --no-link --print-out-paths .#checks.x86_64-linux.fleet-alert.promtoolRehearsal >/dev/null
nix log "$(nix eval --raw .#checks.x86_64-linux.fleet-alert.promtoolRehearsal.drvPath)" | grep -E 'SUCCESS: [0-9]+ rules found' | tee -a "$L"
```

Expected: five lines `<check> <bytes> <seconds>`, `otel-envelope` near 0.146 GiB, `fleet-alert` near 0.328 GiB (351,940,224 B at `b325407984e6`), `otel-collector-config` near 0.445 GiB, each below 536,870,912 (the two machine checks are recorded, not budgeted); the two hashes; six readers `cinnabar electrum galena magnetite pyrite scheelite`; under `otel-ca` only `ca.crt/value` and `ca.key/{secret,users/}`, no `machines/` directory, because `ca.key` is not deployed and `ca.crt` is not secret; one `SUCCESS: <n> rules found`, the rule count Task 3 Step 7 compares with (evaluation, build).
Then on stibnite, read-only, appending to the same log:

```bash
{
  echo "deploy-record lines $(wc -l < /var/log/deploy-record.jsonl)"
  readlink /run/current-system
  /usr/bin/sudo /bin/launchctl list | awk '$3 ~ /^org\.nixos\./'
  dscl . -list /Users UniqueID | awk '$2 == 536 { print "uid 536 taken by " $1; t = 1 } END { if (!t) print "uid 536 free" }'
  dscl . -list /Groups PrimaryGroupID | awk '$2 == 536 { print "gid 536 taken by " $1; t = 1 } END { if (!t) print "gid 536 free" }'
  nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons --apply 'd: builtins.mapAttrs (_: v: { label = v.serviceConfig.Label; keepAlive = v.serviceConfig.KeepAlive; calendar = v.serviceConfig.StartCalendarInterval != null; interval = v.serviceConfig.StartInterval; }) d'
} 2>&1 | tee -a "$L"
```

Expected: the line count; the current system; the `org.nixos.` jobs, among them `nix-daemon`, `nix-grpc-daemon`, `dnscrypt-proxy`, `harmonia-gc`, `nix-cleanup-gcroots`, `sops-install-secrets` and `omnigent-host-cameron`, and no `otelcol`; `uid 536 free` and `gid 536 free`; ten evaluated daemons, three with `keepAlive` `true` and two with `calendar` true (`harmonia-gc`, `nix-cleanup-gcroots`), as design "Context" states (runtime on stibnite, evaluation).

Create `logs/s5-evidence/gsql.sh` (git-ignored), which runs one SQL statement on magnetite's store as `regulator` with the password on curl's stdin:

```bash
#!/usr/bin/env bash
# gsql.sh DB SQL: one statement on magnetite's store as regulator; prints TSV rows.
set -euo pipefail
db=$1 sql=$2
# The deployed path of the regulator password, from magnetite's evaluated configuration.
pw_path=${GSQL_PW_PATH:-$(nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path)}
# ssh joins its arguments into one remote command line, so each is quoted for the remote shell;
# magnetite's login shell is zsh, so the script runs under bash -s.
ssh magnetite.zt "bash -s -- $(printf '%q ' "$db" "$sql" "$pw_path")" <<'EOS'
set -euo pipefail
db=$1 sql=$2 pw_path=$3
pw=$(sudo cat "$pw_path")
printf 'user = "regulator:%s"\n' "$pw" | curl -sS --fail-with-body --config - \
  --data-urlencode "sql=$sql" "http://127.0.0.1:4000/v1/sql?db=$db" |
  jq -r '.output[0].records.rows[]? | map(if . == null then "NULL" else tostring end) | @tsv'
EOS
```

Create `logs/s5-evidence/promq.sh` the same way, sending `GET /v1/prometheus/api/v1/query` with `--get --data-urlencode "query=$1"` and the header `x-greptime-db-name: fleet`, and printing `.data.result[]? | [.metric.host_name // "", .value[1] // ""] | @tsv`; `chmod +x` both.
Record the store's view of the fleet before stibnite reports:

```bash
logs/s5-evidence/promq.sh 'count by (host_name) (system_memory_usage_bytes)' | tee -a "$L"
logs/s5-evidence/gsql.sh devloop "SELECT host, count(*) FROM deploy_record GROUP BY host ORDER BY host" | tee -a "$L"
```

Expected: one line per collecting host that is up, from magnetite, cinnabar, pyrite, electrum, galena and scheelite, of which electrum, galena and scheelite are provisioned on demand and may be absent (on 2026-11-05 only cinnabar, magnetite and pyrite answered), and none for stibnite; `deploy_record` rows per host, none for stibnite (runtime on magnetite).

- [ ] **Step 3: Rehearse every verification block and probe the vendored consumers (tasks.md 1.3)**

Every fenced block in `plan/task-4.md`, `task-5.md`, `task-6.md` and `task-8.md` marked `rehearse:` is run once as written against the host it names, with every mutating command (`clan machines update`, `just activate`, `launchctl bootout|bootstrap|kickstart|kill`, `kill`, closing the lid, a deploy) replaced by an `echo` of the command.
Each block names its interpreter: on stibnite it runs under `/bin/bash` with `/bin/date`, `/bin/launchctl` and `/usr/bin/sudo`; on magnetite it runs as `ssh magnetite.zt 'bash -c '"'"'…'"'"''` or as a quoted heredoc to `bash -s`, because magnetite's login shell is zsh; every journal read uses `sudo`; a zsh variable for an exit code is `rc`, never `status`; every jq filter tolerates a missing field (`// empty`, `// 0`).
A block that reads stibnite's collector, probe or envelope, which do not run yet, is expected to answer `curl: (7)`, `Could not find service` or a missing file, and is recorded as such.
Each block is written to a file and run with stdin closed, because an ssh inside a block reading the script from stdin consumes the rest of it; in the copy, `logs/s5-evidence/window.env` and each `logs/s5-evidence/<4-8>.<n>-*` path become `logs/s5-evidence/1.3-rehearsal/…`, so no rehearsal output is taken for a real record later:

```bash
{ printf 'set -uo pipefail\n'; cat logs/s5-evidence/1.3-rehearsal/<task>-<line>.sh; printf 'echo "rc=$?"\n'; } > /tmp/rehearse.sh
/bin/bash /tmp/rehearse.sh </dev/null 2>&1 | tee -a logs/s5-evidence/1.3-rehearsal-<ts>.log
```

Expected: every block prints `rc=0` or its documented expected code; a block that fails for a reason of its own (a missing `sudo`, a GNU-only flag such as `date -d` or `stat -c` on stibnite, a jq filter failing on an absent field, `status` used in zsh) is fixed in its plan file before the planning pull request and rerun, and the fix is listed at the end of the log under `## Fixes`.

Then the vendored consumers, each with the exact argument list its consumer runs, recorded as run; these lists are what Tasks 2 and 3 render, and a change to one is a change to this step first.

| Consumer | Exact argument list | Runs as |
|---|---|---|
| `otel-host-probe`, disk health (design D4) | `<root pin smartmontools>/bin/smartctl -j -H -A disk0` | `_prometheus-node-exporter`; rehearsed as `nobody`, since the account does not exist before Task 4 |
| `otel-host-probe`, job state (design D4) | `/bin/launchctl print system/org.nixos.<label>` | the same |
| `otel-envelope` C5 (design D6) | `/bin/launchctl print system/org.nixos.otelcol` and `system/org.nixos.otelcol-process`, then `/bin/ps -o rss= -p <pid>` | `_otelcol`; rehearsed as `nobody` |
| `launchd.daemons.otelcol` (design D2) | `otelcol-contrib --config <store path>` behind `/bin/sh -c '/bin/wait4path /nix/store && exec …'` | `_otelcol` |
| `otel-collector-darwin`'s validate case (design D13) | `otelcol-contrib validate --config <file>` | the check's build user on `x86_64-linux` |

Run on stibnite, in `$REPO`, under `/bin/bash`:

```bash
set -uo pipefail
F=logs/s5-evidence/1.3-fixtures; mkdir -p "$F/launchctl"
L=logs/s5-evidence/1.3-rehearsal-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
SMARTCTL=$(nix build --no-link --print-out-paths '.#darwinConfigurations.stibnite.pkgs.smartmontools.out')/bin/smartctl
OTELCOL=$(nix build --no-link --print-out-paths '.#darwinConfigurations.stibnite.pkgs.opentelemetry-collector-contrib.out')/bin/otelcol-contrib
"$SMARTCTL" --version | head -n 1 | tee -a "$L"
"$OTELCOL" --version | tee -a "$L"
sw_vers | tee -a "$L"

# smartctl, the probe's argument list, unprivileged.
/usr/bin/sudo -u nobody "$SMARTCTL" -j -H -A disk0 > "$F/smartctl-disk0.json"; echo "smartctl rc=$?" | tee -a "$L"
jq -c '{protocol: .device.protocol, model: .model_name, passed: .smart_status.passed,
  cw: .nvme_smart_health_information_log.critical_warning, used: .nvme_smart_health_information_log.percentage_used,
  spare: .nvme_smart_health_information_log.available_spare, spare_th: .nvme_smart_health_information_log.available_spare_threshold,
  media: .nvme_smart_health_information_log.media_errors, errlog: .nvme_smart_health_information_log.num_err_log_entries,
  temp: (.temperature.current // null), exit: .smartctl.exit_status}' "$F/smartctl-disk0.json" | tee -a "$L"

# launchctl print, the probe's argument list: every allow-listed label stibnite evaluates,
# a label that is not loaded, and a system job that jetsam reclaimed while idle, taken from
# a survey of the system domain (com.apple.progressd is not a system job: rc 113).
labels=$(nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons --apply 'd: map (v: v.serviceConfig.Label) (builtins.attrValues d)' |
  jq -r '.[] | select(test("^org\\.nixos\\.(nix-daemon|nix-grpc-daemon|harmonia-gc|nix-cleanup-gcroots|sops-install-secrets|dnscrypt-proxy|omnigent-host-.*)$"))')
idle=$(/bin/launchctl print system | awk '/^\tservices = \{/ { s = 1; next } s && /^\t\}/ { exit } s { print $NF }' |
  while read -r j; do /bin/launchctl print "system/$j" 2>/dev/null | grep -q $'^\tlast exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT' && { echo "$j"; break; }; done)
for l in $labels org.nixos.otelcol "$idle"; do
  /usr/bin/sudo -u nobody /bin/launchctl print "system/$l" > "$F/launchctl/$l.txt" 2>&1; rc=$?
  echo "$rc" > "$F/launchctl/$l.rc"
  printf '%s rc=%s %s\n' "$l" "$rc" "$(grep -E '^\s*(state|runs|pid|last exit code|last exit reason) = ' "$F/launchctl/$l.txt" | tr -s '\t ' ' ' | paste -s -d ';' -)" | tee -a "$L"
done
# C5's read: the resident size of a running job's pid, unprivileged.
pid=$(awk -F' = ' '$1 ~ /^[[:space:]]*pid$/ { print $2; exit }' "$F/launchctl/org.nixos.nix-daemon.txt")
/usr/bin/sudo -u nobody /bin/ps -o rss= -p "$pid" | tee -a "$L"; echo "ps rc=$?" | tee -a "$L"
```

Expected: `smartctl 7.5`, `otelcol-contrib version 0.155.0`, `ProductVersion: 26.7.1`; `smartctl rc=0` and `protocol` `NVMe`, `passed` true, `cw` 0, `used` 0, `model` null because `-H -A` reads no identity, as BS "Found while preparing" read on 2026-11-05; for `org.nixos.nix-daemon` `state = running`, a `runs` count, a `pid` and `last exit code = 0`; for `org.nixos.otelcol` `Could not find service` with rc 113; for the idle-reclaimed job (`com.apple.tzlinkd` on 2026-11-05) `last exit reason = JETSAM_REASON_MEMORY_IDLE_EXIT` and no `last exit code` line; one resident size in KiB and `ps rc=0` (runtime, stibnite).
No system job showed a signal on 2026-11-05; the non-idle fixture of Task 2 Step 5 is the per-user job with `last exit reason = JETSAM_REASON_MEMORY_PERPROCESSLIMIT` read from `/bin/launchctl print gui/$(id -u)/<label>`, or, if none is found, a copy of the idle fixture with the reason edited to `JETSAM_REASON_MEMORY_PERPROCESSLIMIT`, saying so in a first comment line the stub strips.
If `launchctl print` as `nobody` prints less than as `crs58` (a field missing, or `Could not find service` for a loaded job), stop: the probe's account cannot read job state, and design D4 goes back to the operator.
If no allow-listed job shows `last exit code = 78` today, the exit-78 fixture of Task 2 Step 5 is a copy of `org.nixos.nix-daemon.txt` with that one line edited, and its file says so in a first comment line the stub strips.

The collector's argument lists, against a configuration rendered by hand from design D2 with its exporters replaced by `debug`, so nothing leaves stibnite:

```bash
cat > /tmp/s5-agent.yaml <<'EOF'
extensions:
  file_storage: { directory: /tmp/s5-otelcol-queue, create_directory: true }
receivers:
  host_metrics/memory:
    collection_interval: 60s
    scrapers:
      memory: {}
      disk:
        include: { devices: [disk0], match_type: strict }
        metrics: { system.disk.io_time: { enabled: false }, system.disk.pending_operations: { enabled: false } }
      filesystem:
        include_mount_points: { mount_points: [/System/Volumes/Data], match_type: strict }
        metrics: { system.filesystem.usage: { enabled: true }, system.filesystem.inodes.usage: { enabled: false }, system.filesystem.utilization: { enabled: false } }
  otlp:
    protocols: { http: { endpoint: 127.0.0.1:4318 } }
  prometheus:
    config:
      scrape_configs:
        - { job_name: node, scrape_interval: 60s, static_configs: [ { targets: [127.0.0.1:9100] } ] }
        - { job_name: otelcol, scrape_interval: 60s, static_configs: [ { targets: [127.0.0.1:8888] } ] }
  file_log/deploy-record:
    include: [/var/log/deploy-record.jsonl]
    start_at: beginning
    storage: file_storage
processors:
  memory_limiter: { check_interval: 1s, limit_mib: 150, spike_limit_mib: 30 }
  resource/agent: { attributes: [ { key: host.name, value: stibnite, action: upsert } ] }
exporters:
  debug: {}
service:
  extensions: [file_storage]
  telemetry:
    metrics:
      readers: [ { pull: { exporter: { prometheus: { host: 127.0.0.1, port: 8888 } } } } ]
  pipelines:
    metrics/host: { receivers: [host_metrics/memory, otlp, prometheus], processors: [memory_limiter, resource/agent], exporters: [debug] }
    logs/devloop-deploy_record: { receivers: [file_log/deploy-record], processors: [memory_limiter], exporters: [debug] }
EOF
"$OTELCOL" validate --config /tmp/s5-agent.yaml 2>&1 | tee -a "$L"; echo "validate rc=${PIPESTATUS[0]}" | tee -a "$L"
```

Expected: `validate rc=0`; a non-zero code naming a key is a vendored-schema fact for Task 2 Step 4 (the darwin `disk` include key, or the telemetry reader shape), recorded and fixed in `plan/task-2.md` before the planning pull request (runtime, stibnite).
Then read, at the root pin, the telemetry setting that leaves `otelcol-process` without a listener: `otelcol-contrib` sets `proxyVendor = true` (nixpkgs `pkgs/tools/misc/opentelemetry-collector/releases.nix:163`), so its `goModules` (`nix build --no-link --print-out-paths .#darwinConfigurations.stibnite.pkgs.opentelemetry-collector-contrib.goModules`) is a module download cache, from which `go.opentelemetry.io/collector/service/@v/v0.155.0.zip` is unzipped to read `service/telemetry/otelconftelemetry/`.
On 2026-11-05 the answer was `service.telemetry.metrics.level: none`, for which `createMeterProvider` builds no reader (`metrics.go:28-30`), where the default is a pull reader on `localhost:8888` (`factory.go:48-59`) and `readers` is required only when the level is not `none` (`config.go:52-56`); record the `path:line` read again, and validate a copy of the configuration above reduced to `host_metrics/process`, that setting and `otlp_http` to `http://127.0.0.1:4318`, and record its rc.
Expected: one cited `path:line` and `validate rc=0` for the reduced configuration; Task 2 Step 4's clause "no telemetry listener" names that value (vendored source, runtime).
Finally the 8.8 block: an anonymous POST to `fleet-acceptance` from stibnite with `/usr/bin/curl`, expected `403` as on 2026-11-05 (A66), the token never read (runtime, stibnite).

- [ ] **Step 4: Gate pull request 1's implementation on the omnigent session (tasks.md 1.4)**

O9: the session upgrading omnigent edits `modules/clan/services/otel-collector/flake-module.nix` and `schema.nix`; pull request 1 touches those two files only in the hunks Tasks 2 and 3 name, and its implementation starts only after that session's pull request has merged, or the operator states in this session that it no longer will.
Run in `$REPO`, under `/bin/bash`:

```bash
set -uo pipefail
L=logs/s5-evidence/1.4-gate-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
jj git fetch 2>&1 | tail -n 1
jj log --no-pager --no-graph -r 'main@origin' -T 'commit_id ++ "\n"' | tee "$L"
# Commits to the two files since the planning base (design "Context": origin/main f3beacfbf).
git log --format='%H %s' f3beacfbf..origin/main -- modules/clan/services/otel-collector/flake-module.nix modules/clan/services/otel-collector/schema.nix | tee -a "$L"
for c in $(git log --format='%H' f3beacfbf..origin/main -- modules/clan/services/otel-collector/flake-module.nix modules/clan/services/otel-collector/schema.nix); do
  gh api "repos/cameronraysmith/vanixiets/commits/$c/pulls" --jq '.[] | "#\(.number) \(.state) merged=\(.merged_at // "no") \(.title)"'
done | sort -u | tee -a "$L"
```

Expected: `main@origin`'s commit; the omnigent session's merged pull request among the listed numbers, recorded with its number; or, if it is not there, the operator's statement with `/bin/date -u`, appended to the log verbatim.
Any commit of this change already made for groups 2 and 3 is rebased onto that `main@origin` with `jj rebase -s <first such change> -d main@origin`, and every conflict in the two files is resolved by keeping the session's text and reapplying only this change's hunks: the agent role's `darwinModule` and `otel-cert`'s `restartUnits` in FM (Task 2 Step 2), and SC's `darwinNodeExporterKeep` and `launchdLabels` (Task 2 Step 4).
Expected after the rebase: `jj log --no-pager -r 'main@origin..@'` shows only this change's commits; `nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath` evaluates (command, evaluation).
Then re-run Step 2's cost loop for the three gating checks at the new `main@origin`, appending to the same log, because the session's edits may have moved them; Tasks 2 and 3 compare with these figures.
