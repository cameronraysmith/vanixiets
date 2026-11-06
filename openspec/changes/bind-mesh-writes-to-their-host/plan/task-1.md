### Task 1: Plan review, baselines, the archive gate, rehearsal and the filter probe

Implements `tasks.md` 1.1–1.5 (design D5, D11, Migration Plan steps 1 and 5; O6).
Nothing here commits code; Step 3 is the gate every implementation commit waits for.

**Files:**
- Create (committed): `openspec/changes/bind-mesh-writes-to-their-host/review-plan.md`
- Create (git-ignored): `logs/cam81-evidence/1.<n>-*.log`, `logs/cam81-evidence/1.4-rehearsal/`, `logs/cam81-evidence/1.5-probe/`

**Interfaces:**
- Consumes: `main@origin`; `$DEPLOY` (plan Global Constraints).
- Produces: the baselines every later cost and hash comparison reads; the rehearsed blocks; the probe's recorded argument lists.

- [ ] **Step 1: Plan review (tasks.md 1.1)**

Dispatch one read-only subagent of the default `task` type on an Opus model with the four questions of `tasks.md` 1.1 over `design.md`, `tasks.md`, `plan.md`, `plan/` and `specs/`.
It also lists every clause, assertion and case named in the plan's interface contract with its two value sources.
Write its answer to `review-plan.md` with a dispositions table (`| Finding | Severity | Disposition | Operator decision |`); the operator decides each row; accepted findings are applied to the artifacts before Step 3.

- [ ] **Step 2: Baselines (tasks.md 1.2)**

```bash
L=logs/cam81-evidence/1.2-baseline-$(date -u +%Y%m%dT%H%M%SZ).log
for c in otel-collector-config otel-envelope nixos-magnetite; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.$c.drvPath >/dev/null
  echo "$c $(jq -c '[.gc.totalBytes, .cpuTime]' /tmp/$c-stats.json)"
done 2>&1 | tee "$L"
sha256sum vars/shared/otel-ca/ca.crt/value | tee -a "$L"
CLAN_NO_COMMIT=1 clan vars get magnetite ntfy-alerter/token | sha256sum | tee -a "$L"
for m in magnetite cinnabar pyrite electrum galena scheelite stibnite; do
  echo "== $m"; openssl x509 -noout -subject -ext subjectAltName -in vars/per-machine/$m/otel-cert/cert.pem/value
done 2>&1 | tee -a "$L"
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee -a "$L"
set -uo pipefail
z=$(ip -j link show | jq -r '.[] | select(.ifname|startswith("zt")) | .ifname')
echo "link=$z"; ip -j link show dev "$z" | jq -c '.[0] | {ifname, address}'
ip -j -6 neigh show dev "$z" | jq -c '.[] | {dst, lladdr, state}'
systemctl show -p MemoryCurrent opentelemetry-collector greptimedb perses; free -b
EOS
```

Expected: three costs below 536,870,912 B; two hashes; no URI SAN on any certificate; magnetite's link name and its neighbour entries.

- [ ] **Step 3: The archive gate (tasks.md 1.3) [gate]**

```bash
L=logs/cam81-evidence/1.3-archive-gate-$(date -u +%Y%m%dT%H%M%SZ).log
openspec list --json | jq -r '.changes[]?.name' | tee "$L" | grep -qx stand-up-darwin-collection && { echo "STOP: not archived" | tee -a "$L"; exit 1; }
```

Then rebase each MODIFIED requirement onto the archived corpus: for `fleet-ingress-interface` (`One host table declares the agent hosts and what each reports`, `The collection CA issues each agent host one certificate`, `The ingress receiver accepts only certificate holders on magnetite's ZeroTier address`, `This capability states its own trust boundary`), `devloop-collection-interface` (`This capability states its own trust boundary`), `telemetry-store-interface` (`This capability states its own trust boundary`) and `world-assumptions` (`Grounded vocabulary for behavioral requirements`), extract the main requirement from `openspec/specs/<capability>/spec.md`, diff it against this change's text, and reduce the diff to this change's edits alone (the address sentence and scenario, the URI SAN and reissue scenario, the caddy and socket text, the trust-boundary scenarios, the two vocabulary rows and the `overlay network` row).
Record each diff in `$L`, then:

```bash
openspec validate bind-mesh-writes-to-their-host --strict 2>&1 | tee -a "$L"
```

Expected: `is valid`; any other output stops the task.

- [ ] **Step 4: Rehearsal (tasks.md 1.4)**

Run every block of Tasks 3, 5 and 6 marked `rehearse:` once, read-only, with paths under `logs/cam81-evidence/1.4-rehearsal/`.
The public path is rehearsed from stibnite:

```bash
ssh root@magnetite.scientistexperience.net 'bash -c "z=\$(ip -j link show | jq -r \".[] | select(.ifname|startswith(\\\"zt\\\")) | .ifname\"); ip -j -6 neigh show dev \$z | jq length"'
```

Expected: a count; a host-key prompt is answered by comparing with `ssh-keyscan` over ZeroTier, and the answer is recorded.

- [ ] **Step 5: The vendored filter probe (tasks.md 1.5) [gate]**

Read the consumer's argument list:

```bash
nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.opentelemetry-collector.serviceConfig.ExecStart
```

Expected: `<store path>/bin/otelcol-contrib --config=file:<path>`; the probe uses the same binary path and the same flag form.
Write `logs/cam81-evidence/1.5-probe/config.yaml` for a two-host table (`alpha`, `beta`):

```yaml
receivers:
  otlp/mesh:
    protocols:
      http:
        transport: unix
        endpoint: /tmp/cam81-probe/otlp.sock
        include_metadata: true
processors:
  memory_limiter: { check_interval: 1s, limit_mib: 128 }
  filter/mesh-host-metrics:
    error_mode: ignore
    metric_conditions:
      - 'not (otelcol.client.metadata["x-vanixiets-host"][0] == "alpha" or otelcol.client.metadata["x-vanixiets-host"][0] == "beta")'
      - 'resource.attributes["host.name"] != otelcol.client.metadata["x-vanixiets-host"][0]'
      - 'datapoint.attributes["host.name"] != nil or datapoint.attributes["host_name"] != nil'
  filter/mesh-host-logs:
    error_mode: ignore
    log_conditions:
      - 'not (otelcol.client.metadata["x-vanixiets-host"][0] == "alpha" or otelcol.client.metadata["x-vanixiets-host"][0] == "beta")'
      - 'resource.attributes["host.name"] != otelcol.client.metadata["x-vanixiets-host"][0]'
      - 'log.attributes["host"] != nil and log.attributes["host"] != otelcol.client.metadata["x-vanixiets-host"][0]'
      - 'log.attributes["host.name"] != nil or log.attributes["host_name"] != nil'
exporters:
  debug: { verbosity: detailed }
service:
  telemetry: { metrics: { readers: [ { pull: { exporter: { prometheus: { host: 127.0.0.1, port: 18888 } } } } ] } }
  pipelines:
    metrics/mesh: { receivers: [otlp/mesh], processors: [memory_limiter, filter/mesh-host-metrics], exporters: [debug] }
    logs/mesh: { receivers: [otlp/mesh], processors: [memory_limiter, filter/mesh-host-logs], exporters: [debug] }
```

Run it with the pinned binary, `mkdir -p /tmp/cam81-probe && <otelcol-contrib> --config=file:logs/cam81-evidence/1.5-probe/config.yaml`, and post through the socket with `curl --unix-socket /tmp/cam81-probe/otlp.sock http://x/v1/metrics -H 'Content-Type: application/json'`: a gauge with resource `host.name=alpha` and header `X-Vanixiets-Host: alpha`; the same with header `beta`; one with header `alpha` and a point attribute `host_name=beta`; a deploy record (`/v1/logs`) with header `alpha` and attribute `host=beta`; a matching record; a request without the header; and one with header name `x-VANIXIETS-host: alpha`.
Expected: the debug exporter prints only the matching gauge, the matching record and the mixed-case request; every request answers 200; `curl -s 127.0.0.1:18888/metrics | grep -E 'otelcol_processor_filter_(datapoints|logs)_filtered'` shows the dropped counts with `filter="filter/mesh-host-metrics"` and `filter="filter/mesh-host-logs"`, and the series names as printed, with or without `_total`, are what Task 4 Step 1's fixtures use.
If a condition is rejected at start, or a request lands where it should not, the conditions are corrected here and `design.md` D5 is amended before Task 4.
