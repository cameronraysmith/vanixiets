### Task 3: `otel-envelope` and `fleet-ingress`

Implements `tasks.md` 3.1–3.5 (design D7, D10's failure-wiring change, D11, D12; FII `otel-envelope regulates each agent from its own collector`, and the delivery, refusal and back-pressure scenarios of FII, HMC, TSI and DCI named in 3.4; WA `A52 — The collector answers back-pressure with a retryable refusal and keeps its persistent queue across an outage and a restart`).
This is the second part of pull request 1, on top of Task 2's changes; Step 6 opens the pull request.
The check comes first and fails at evaluation (Step 1); the script makes it pass (Step 2); the units follow (Step 3); `fleet-ingress` is written against the finished pull request and run on magnetite before it merges (Steps 4, 5).

**Files:**
- Create: `modules/checks/otel-envelope.nix`, `modules/checks/otel-envelope/stub.py`, `modules/checks/otel-envelope/fixtures/*.prom`
- Create: `modules/lib/otel-envelope.nix`
- Modify: `modules/clan/services/otel-collector/flake-module.nix` (the agent fragment: `otel-envelope.service`, `otel-envelope.timer`)
- Modify: `modules/checks/otel-collector-config.nix:34-44` (`notifiedByPolicy`), `:369-371` (the policy clause's name), `mutants`
- Create: `modules/vm-tests/fleet-ingress.nix`, `modules/vm-tests/fleet-ingress/helpers.py`, `modules/vm-tests/fleet-ingress/target.py`
- Create (git-ignored): `logs/s4-evidence/3.<n>-*.log`, `logs/s4-evidence/2.2-overrides.nix`

**Interfaces:**
- Consumes: Task 2's options, collector names, credentials, `flake.lib.observabilityHosts` and SC keys; the collector's metric names at 0.155.0, read live on magnetite on 2026-10-29 and again in Task 1 Step 3 (`otelcol_exporter_queue_capacity` exists with a `data_type` label, the counters carry no `_total` suffix, and the memory receiver's id is `host_metrics/memory`); `flake.lib.observabilityNotifyScripts` and the notifier template; `modules/vm-tests/greptimedb-pipeline.nix` as the container pattern (`:41-84`: `nodePkgs` with the flake overlay, `requiredFeatures`, `containers.<name>`).
- Produces: `flake.lib.otelEnvelope pkgs { hostName; telemetryUrl ? "http://127.0.0.1:8888/metrics"; targets; ingress ? false; budget ? null; }`, its output contract (plan.md Interface contract) and the source markers `# mutant: <name>` that Task 7 extends; `otel-envelope.service` and `otel-envelope.timer` on every agent host; `vmTests.x86_64-linux.fleet-ingress` with `helpers.py` and the `cases` list Task 7 appends `budget` to.

- [ ] **Step 1: The check, seen failing (tasks.md 3.1)**

Write the fixtures first, copying metric and label names from the live read (`otelcol_exporter_queue_size` and `otelcol_exporter_queue_capacity` each carry `exporter` and `data_type`, and C3 pairs them on both); each fixture is one Prometheus exposition, and a case is a sequence of fixtures served on consecutive runs against one state directory:

| Fixture | Content |
|---|---|
| `agent-healthy.prom` | `otelcol_exporter_queue_size{exporter="otlp_http/ingress",data_type="metrics"} 3`, `otelcol_exporter_queue_capacity{exporter="otlp_http/ingress",data_type="metrics"} 419430400`, the same for `otlp_http/ingress-logs` with `data_type="logs"`, no `send_failed`, `enqueue_failed` or `refused` series |
| `agent-full.prom` | as healthy with `queue_size` 380000000 of 419430400 (90.6 %) |
| `agent-enqueue-1.prom`, `-2.prom` | `otelcol_exporter_enqueue_failed_metric_points{exporter="otlp_http/ingress"}` 5, then 9 |
| `agent-sendfail-0.prom`, `-reset.prom`, `-reset-fail.prom` | `send_failed` 10; then 0 after a restart (new `service_instance_id`); then 3 |
| `ingress-mesh-refused-1.prom`, `-2.prom` | only `otelcol_receiver_refused_metric_points{receiver="otlp/mesh",transport="http"}` 63, then 135 |
| `ingress-enqueue-1.prom`, `-2.prom` | only `otelcol_exporter_enqueue_failed_metric_points{exporter="otlp_http/fleet"}` 135, then 200, with `queue_size` 10 of 419430400 |
| `ingress-memory-refused-1.prom`, `-2.prom` | `otelcol_receiver_refused_metric_points{receiver="host_metrics/memory"}` 0, then 4 |

`stub.py` serves `/metrics` from the file named in `$STUB_FIXTURE`, re-read on each request, `/ok` with 200, and `/slow` answering 200 after 15 s, on `127.0.0.1:$STUB_PORT`; a closed port stands for a stopped exporter.
`modules/checks/otel-envelope.nix` builds, for `x86_64-linux` only, a `runCommand` that starts the stub and runs the script from `self.lib.otelEnvelope` (the root pin's `pkgs`, no NixOS configuration) once per fixture with `STATE_DIRECTORY` a fresh temporary directory per case, printing `ok: <case>` when every run's exit code matches:

| Case | Script arguments | Runs: fixture → expected exit |
|---|---|---|
| `healthy` | agent, targets `/ok` | baseline → 0, healthy → 0 |
| `missingSendFailed` | agent | healthy → 0, healthy → 0 |
| `noTelemetry` | agent, telemetry on a closed port | → 0, → 1 (C1 on the second) |
| `queueFull` | agent | healthy → 0, full → 1 (C3) |
| `agentEnqueueFailed` | agent | enqueue-1 → 0 (baseline), enqueue-2 → 1 (C4) |
| `ingressEnqueueFailed` | ingress | ingress-enqueue-1 → 0, ingress-enqueue-2 → 0 |
| `ingressMeshRefused` | ingress | mesh-refused-1 → 0, mesh-refused-2 → 0 |
| `ingressOwnRefused` | ingress | memory-refused-1 → 0, memory-refused-2 → 1 (C4) |
| `resetAfterRecorded` | agent | sendfail-0 → 0, sendfail-reset → 0 |
| `resetThenFailure` | agent | sendfail-0 → 0, sendfail-reset → 0, sendfail-reset-fail → 1 (C4) |
| `targetDownOnce` | agent, targets `/ok` then a closed port | → 0, → 0 (one run down) |
| `targetDownTwice` | agent, target a closed port | → 0, → 1 (C2) |
| `missThenSame` | agent | sendfail-0 → 0, closed telemetry port → 0 (first miss), sendfail-0 → 0 |
| `longRun` | agent, target `/slow` | 3 runs over `sendfail` counters growing by 0 → run 1 exit 0, runs 2–3 exit 1 on C2 only, each under 240 s, and `wc -l < $STATE_DIRECTORY/state` equal on runs 2 and 3 |

and, for each mutant, the script built with one marked line replaced, which must fail at least one case: `meshRefusalIsLoss` (`ingressMeshRefused`), `missingCounterFails` (`missingSendFailed`), `resetNegative` (`resetThenFailure`), `targetDownOneRun` (`targetDownOnce`), `noCarryForward` (`missThenSame`), each printing `mutant <name> rejected: <case>`.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-envelope 2>&1 | tee logs/s4-evidence/3.1-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -n 3
```

Expected: FAIL at evaluation, `attribute 'otelEnvelope' missing` (RED).

- [ ] **Step 2: The script (tasks.md 3.2)**

Create `modules/lib/otel-envelope.nix` exposing `flake.lib.otelEnvelope`, a `writeShellApplication` named `otel-envelope` with `runtimeInputs = [ pkgs.coreutils pkgs.curl pkgs.gawk pkgs.gnugrep pkgs.gnused ]` and, from Task 7, `jq` and `flake.lib.greptimedbSql`; `targets` is rendered into the script as `job url` lines.
The script's contract is plan.md's Interface contract; its hard part is the state comparison, which must keep these properties (design D7):

```bash
# key: metric name and labels without the per-start identity labels.
normalise() { sed -E 's/(service_instance_id|service_name|service_version|otel_scope_[a-z_]+)="[^"]*",?//g; s/,}/}/; s/\{\}//'; }
state="$STATE_DIRECTORY/state"; next="$STATE_DIRECTORY/state.next"; : > "$next"
baseline=0; [ -e "$state" ] || baseline=1
prev() { awk -v k="$1" '$1 == k { print $2; f = 1 } END { if (!f) print "absent" }' "$state" 2>/dev/null || echo absent; }

# C1: telemetry; a run without it fails only if the previous run also had none.
if curl -fsS --max-time 10 "$telemetry_url" -o "$tmp/now"; then echo "telemetry 0" >> "$next"; ok "C1 telemetry"
else
  echo "telemetry 1" >> "$next"; : > "$tmp/now"
  # mutant: noCarryForward
  # One missed read keeps the previous counters, so the next run does not
  # see their whole cumulative value as an increase.
  { grep -E '^otelcol_' "$state" 2>/dev/null || true; } >> "$next"
  [ "$(prev telemetry)" = 1 ] && fail "C1 telemetry" "no answer on two consecutive runs" || ok "C1 telemetry" "first miss"
fi

# C4: loss counters. An absent counter reads 0; a value below the recorded one
# is a restart, and the current value is the increase. The braces keep an
# empty match from failing the run under writeShellApplication's pipefail.
loss_re='^otelcol_exporter_send_failed_|^otelcol_receiver_refused_'
[ "$ingress" = 1 ] || loss_re="$loss_re|^otelcol_exporter_enqueue_failed_"
[ -s "$tmp/now" ] && { grep -E "$loss_re" "$tmp/now" || true; } | while read -r series value; do
  # mutant: meshRefusalIsLoss
  [ "$ingress" = 1 ] && [[ $series == otelcol_receiver_refused_* ]] && [[ $series == *'receiver="otlp/mesh"'* ]] && continue
  key=$(printf '%s' "$series" | normalise); was=$(prev "$key")
  echo "$key $value" >> "$next"
  [ "$baseline" = 1 ] && continue
  # mutant: missingCounterFails / resetNegative
  [ "$was" = absent ] && was=0
  inc=$(awk -v n="$value" -v p="$was" 'BEGIN { print (n < p) ? n : n - p }')
  if awk -v i="$inc" 'BEGIN { exit !(i > 0) }'; then echo "C4 $key +$inc" >> "$tmp/loss"; fi
done
```

C2 probes each declared target with `curl -s -o /dev/null -w '%{http_code}' --max-time 10` and records `down:<job> 0|1`, failing only when this run and the previous one are down (the line `# mutant: targetDownOneRun` guards the previous-run test); C3 fails when, for any `exporter`, `queue_size * 10 >= queue_capacity * 9`, and a capacity series missing for an exporter that has a size fails C3 with `capacity absent`.
The whole state file is replaced by `$next` at the end with `mv`, so it holds exactly the current series, or on a missed read the previous ones, and the down flags.
A first run with no state file records the baseline and judges C1 to C3 only, so a host whose counters are already non-zero from before the envelope existed does not fail its first run; the comment in the script says so.
The script prints one `otel-envelope: <clause> <name>: ok|FAIL <detail>` line per clause and exits 1 if any failed.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-envelope -L 2>&1 | tee logs/s4-evidence/3.2-check-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(ok|mutant|FAIL)'
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-envelope-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-envelope.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/otel-envelope-stats.json
```

Expected: 14 `ok:` lines, 5 `mutant … rejected` lines, no `FAIL`; the cost between about 0.12 and 0.2 GiB (design D10), below 536,870,912 in any case.

- [ ] **Step 3: The units on every agent host (tasks.md 3.3)**

In the agent fragment add:

```nix
systemd.services.otel-envelope = {
  description = "Collector delivery envelope (ADR-003 R3.2)";
  after = [ "opentelemetry-collector.service" ];
  serviceConfig = {
    Type = "oneshot";
    DynamicUser = true;
    StateDirectory = "otel-envelope";
    MemoryMax = "64M";
    TimeoutStartSec = "4min";
    ExecStart = lib.getExe (flakeLib.otelEnvelope pkgs {
      inherit hostName;
      ingress = config.vanixiets.otelCollector.ingress;
      # The targets the collector itself scrapes, so the two cannot drift.
      targets = lib.concatMap (name: map (job: {
        inherit (job) job_name;
        url = "${job.scheme or "http"}://${builtins.head (builtins.head job.static_configs).targets}${job.metrics_path or "/metrics"}";
      }) settings.receivers.${name}.config.scrape_configs)
        (builtins.filter (lib.hasPrefix "prometheus") (builtins.attrNames settings.receivers));
    });
  };
};
systemd.timers.otel-envelope = {
  wantedBy = [ "timers.target" ];
  timerConfig.OnCalendar = "*:0/5";
};
```

Where `services.zerotierone.enable` holds, the zerotierone target needs its bearer token: add `LoadCredential = [ "zerotier-metricstoken:/var/lib/zerotier-one/metricstoken.secret" ]` to `otel-envelope` in the existing `lib.mkIf config.services.zerotierone.enable` block, and give the script the target's credential file through the target's `authorization.credentials_file`, rewritten to `$CREDENTIALS_DIRECTORY/zerotier-metricstoken`, sent as `Authorization: Bearer` on curl's stdin config, never on an argument list.
The `prometheus/zerotier` job is otherwise probed like the others.
In the same commit, add `otel-envelope` to every host's `notifiedUnits` in `modules/lib/observability-hosts.nix` (the `agent` helper's list) and require it in the notified-unit assertion (`&& builtins.elem "otel-envelope" notified`, and the message names it), so every commit of pull request 1 evaluates (review finding on intermediate commits).
In CC, extend `notifiedByPolicy` with `|| name == "otel-envelope"`, rename the clause to `R3.1: a greptimedb*, zfs-set-*, zfs-assert-*, devloop-*, collector or otel-envelope unit is not notified`, and add the mutant:

```nix
envelopeNotNotified = i: i // { notifyUnits = lib.remove "otel-envelope" i.notifyUnits; };
```

Run:

```bash
jj st --no-pager >/dev/null
L=logs/s4-evidence/3.3-units-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for h in magnetite electrum; do echo "== $h"
  nix eval --json ".#nixosConfigurations.$h.config.systemd.services.otel-envelope" --apply 's: { inherit (s.serviceConfig) DynamicUser StateDirectory MemoryMax TimeoutStartSec; cred = s.serviceConfig.LoadCredential or [ ]; onFailure = s.unitConfig.OnFailure or null; }'
  nix eval --json ".#nixosConfigurations.$h.config.systemd.timers.otel-envelope.timerConfig.OnCalendar"
done 2>&1 | tee "$L"
nix build .#checks.x86_64-linux.otel-collector-config -L 2>&1 | tee -a "$L" | grep -E 'FAIL|ok: R3.1'
```

Expected: on both hosts `DynamicUser` true, `otel-envelope`, `64M`, `4min`, `cred` naming `zerotier-metricstoken`, `onFailure` `["observability-notify@%n.service"]`, `"*:0/5"`; the check passes, so `envelopeNotNotified` is rejected; cost recorded.
Repeat the loop for cinnabar and pyrite in the scratch tree (plan Global Constraints), expecting the same.

- [ ] **Step 4: The notified-unit assertion now requires `otel-envelope` (tasks.md 3.3's negative control)**

Add to `logs/s4-evidence/2.2-overrides.nix` the evaluation `electrumNoEnvelope`, electrum with `services.observability-notify.units = lib.mkForce [ "opentelemetry-collector" ]`, and run:

```bash
L=logs/s4-evidence/3.3-envelope-notified-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix eval --raw .#nixosConfigurations.electrum.config.system.build.toplevel.drvPath 2>&1 | tee "$L"; echo
nix eval --impure --raw --expr '(import ./logs/s4-evidence/2.2-overrides.nix (builtins.getFlake (toString ./.))).electrumNoEnvelope' 2>&1 | grep -o 'otel-collector agent[^(]*' | head -n 1 | tee -a "$L"
```

Expected: a drvPath, then the notified-unit assertion's message naming `otel-envelope` (negative control); then Task 2 Step 11 runs.

- [ ] **Step 5: `fleet-ingress` (tasks.md 3.4)**

Create `modules/vm-tests/fleet-ingress.nix`, following `greptimedb-pipeline` (`:31-84`): `vmTests.x86_64-linux.fleet-ingress`, `requiredFeatures = { nixos-test = true; uid-range = true; }`, `node.pkgs = lib.mkForce nodePkgs` with the flake overlay and an overlay replacing `ntfy-send` by a recorder that appends `<topic>|<title>` to `/run/ntfy-posts` and exits 0.
Certificates are made at test build by one `runCommand` with `pkgs.openssl`: a test CA, an ingress certificate with SAN `IP:127.0.0.1` and `serverAuth,clientAuth`, an agent certificate with `clientAuth`, and a rogue CA with its client certificate.
One container `store` holds:
- `greptimedb` with magnetite's databases, the schema job and the `devloop` tables and pipelines, as `greptimedb-pipeline` and `devloop-ingest` set them up;
- `opentelemetry-collector.service` from `otel-collector-agent` and `otel-collector-ingress` (the ingress host), with `vanixiets.otelCollector.caFile` the test CA, `otlp/mesh`'s endpoint forced to `127.0.0.1:4318`, and its two credentials loaded from the test certificates;
- `agent-collector.service`, `DynamicUser`, `StateDirectory = "agent-collector"`, running `otelcol-contrib --config=file:<yaml>` where the YAML renders electrum's evaluated `services.opentelemetry-collector.settings` (the agent role's non-ingress configuration on a host whose `collect` is true) with exactly these overrides: both exporters' endpoint `https://127.0.0.1:4318` and TLS files the test CA and agent certificate, `file_storage.directory` `/var/lib/agent-collector/queue`, `service.telemetry.metrics` on `127.0.0.1:8889`, `prometheus/zerotier` and its pipeline entry removed, and `file_log/deploy-record` reading `/var/lib/agent-collector/deploy-record.jsonl`; `host.name` stays `electrum`;
- `otel-envelope.service` from the agent fragment (the ingress host's), and `agent-envelope.service`, the same unit definition with the script built for `electrum`, `ingress = false`, telemetry `127.0.0.1:8889` and the agent's targets;
- `services.observability-notify.units = [ "opentelemetry-collector" "otel-envelope" "agent-collector" "agent-envelope" ]` and `services.observability-notify.tokenFile` a test token file, so the agent fragment's notified-unit assertion holds in the container and its failures reach the recording `ntfy-send`;
- `prometheus-node-exporter` on loopback, which both collectors scrape.

`helpers.py` provides `gsql(sql, db)` and `promql(expr)` as `regulator`, `metric(port, name_regex)` (summing a counter from a telemetry endpoint, 0 when absent), `envelope(unit)` (starts it, returns its exit code and its `otel-envelope:` lines from `journalctl -u <unit> -o cat`), and `collector_with(unit, mutant)` (installs `/run/systemd/system/<unit>.service.d/zz-mutant.conf` from `/etc/fleet-ingress/mutants/<mutant>.conf`, `daemon-reload`, restart; `None` removes it), as `devloop-ingest`'s helpers do.
The `testScript` is `helpers.py` followed by the `cases` list, each starting with `print("=== case <name>", flush=True)`:

| Case | Actions | Assertions |
|---|---|---|
| `refusal` | `curl --cacert ca.crt https://127.0.0.1:4318/v1/metrics` without a client certificate; with the rogue certificate; with the agent certificate and `--tls-max 1.2` | exit codes 55, 55 and 35 with GR §2's error strings; the ingress journal logs three `TLS handshake error`; `otelcol_receiver_accepted_metric_points{receiver="otlp/mesh"}` unchanged |
| `delivery` | start the store, schema job and both collectors together; append three lines to the agent's deploy-record file | within 3 min `count by (host_name) (system_memory_usage_bytes)` includes `electrum`; `SELECT count(*) FROM deploy_record WHERE host = 'electrum'` is 3; every exporter's `send_failed` on 8888 and 8889 is 0 |
| `backPressure` | ingress mutant `storeQueueTwo` (`otlp_http/fleet` queue `requests`, size 2) and `systemctl stop greptimedb` for 3 min; then ingress mutant `limiterRefusing` (`limit_mib` 2, spike 1) for 2 min; then both removed and the store started | the agent's `otelcol_exporter_queue_size` grows then returns to 0; the ingress counted `refused` on `otlp/mesh` and `enqueue_failed` on `otlp_http/fleet`; the agent's accepted point total equals the ingress's accepted total on `otlp/mesh` over the case; both envelopes exit 0 on every run in the case |
| `lossControls` | C1: stop `agent-collector`, run `agent-envelope` twice; C2: stop the node exporter, run twice; C3/C4: agent mutant `queueOneMiB` with the ingress stopped until the queue fills, run, then run again after more enqueue failures; C4 on the ingress: ingress mutant `limiterRefusing` while its own `host_metrics/memory` scrape runs | second runs exit 1 with `C1 telemetry: FAIL`, `C2 targets: FAIL node`, then `C3 queue: FAIL`, then `C4 loss: FAIL` naming `enqueue_failed`; the ingress envelope exits 1 with `C4 loss: FAIL` naming `host_metrics/memory`; each restored run passes |
| `crashLoop` | `systemctl kill -s KILL agent-collector` four times in 10 min, `agent-envelope` run after each kill and after each restart | runs with telemetry answering exit 0; a run that sees no telemetry twice in a row exits 1 only on C1; no run fails C4; the agent's points all arrive (accepted totals equal) |
| `longRun` | 10 `agent-envelope` runs with counters accumulating | each `ActiveEnterTimestamp`-to-exit under 240 s; `wc -l` of the state file equals the number of loss series plus the telemetry and target flags, constant across runs |
| `absentClientCa` | ingress mutant `absentClientCa` (`client_ca_file` a missing path) | the collector fails to start with `failed to load client CA`; `/var/lib/observability-notify/failed.log` gains one line for `opentelemetry-collector.service`; `/run/ntfy-posts` holds one `FAILED`; after removing the mutant, one `RESOLVED` |

Every case that touches ingest starts from the store, schema job and both collectors running and checks `send_failed` is 0 after their first send (S1-R6).
Then build it from the pull request's head on magnetite:

```bash
jj st --no-pager >/dev/null
nix build .#vmTests.x86_64-linux.fleet-ingress -L 2>&1 | tee logs/s4-evidence/3.4-fleet-ingress-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^=== case|FAIL|error:' 
```

Run from stibnite, which routes it to magnetite, the only builder advertising `uid-range` (`modules/README.md:56-69`).
Expected: seven `=== case` lines, the test passes, and the log holds each assertion's output, including `curl: (55)` twice and `curl: (35)` once.

- [ ] **Step 6: Format, cost and the pull request (tasks.md 3.5)**

Run `nix fmt 2>&1 | tee logs/s4-evidence/3.5-fmt-<ts>.log` and `nix fmt -- --fail-on-change`; re-measure `otel-collector-config`, `otel-envelope`, `fleet-alert` and `greptimedb-envelope` with the method of plan Global Constraints and record them beside 1.2's in `logs/s4-evidence/3.5-cost-<ts>.log`.
Commit as changes off `main@origin` with plain messages, for example "Check each collector's delivery every five minutes on its own host" and "Add a container test of certificate-authenticated ingest".
Open pull request 1 titled, for example, "Collect host metrics from every NixOS host over a certificate-authenticated ingress", whose body describes the change in words, links CAM-71, states the container-test run in words (the commit, the host it ran on, the date and the cases that passed) rather than a log path, says that cinnabar and pyrite stay unchanged until each one's own pull request turns its collection on, and carries no slice, decision, finding or task code.
Expected: nixbot green, including `otel-collector-config`, `otel-envelope`, `fleet-alert`, `greptimedb-envelope` and the five `nixos-<host>` checks.
