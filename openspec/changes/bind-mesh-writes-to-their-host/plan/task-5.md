### Task 5: Deploying pull request 2

Implements `tasks.md` 5.1–5.5 (design D4 "Pre-deploy gate" and "Rollback", Migration Plan steps 5 and 6; FII `magnetite pins each collecting host's neighbour entry`, `A mesh write is stored only under the host that sent it`; DC `A deploy record names the collected host that sent it`).
It starts only after pull request 2 has merged and every present collecting host passed Task 3 Step 5.
A wrong pinned entry cuts magnetite off from that host over ZeroTier, so the MAC gate is mandatory and the public SSH session is open before the deploy (O4).

**Files:**
- Create (git-ignored): `logs/cam81-evidence/5.<n>-*.log`, `logs/cam81-evidence/survey.sh`, `logs/cam81-evidence/mac-gate.sh`

**Interfaces:**
- Consumes: `posts.sh`, `mark.sh` (Task 3); the merged commit's evaluated `09-zerotier` neighbours.
- Produces: the deploy's evidence and, if needed, the rollback's.

- [ ] **Step 1: The honest-attribute survey (tasks.md 5.1) [gate]**

`logs/cam81-evidence/survey.sh <host>` reads the host's scrape targets from its evaluated configuration and counts host labels on each:

```bash
#!/usr/bin/env bash
# survey.sh HOST: lines with a host_name or host.name label on each target HOST's agent scrapes.
set -uo pipefail
h=$1
nix eval --json ".#nixosConfigurations.$h.config.services.opentelemetry-collector.settings.receivers" |
  jq -r 'to_entries[] | select(.key|startswith("prometheus")) | .value.config.scrape_configs[] | "\(.job_name) \(.static_configs[0].targets[0])\(.metrics_path // "/metrics")"' |
  while read -r job target; do
    if [ "$job" = zerotierone ]; then auth='-H "Authorization: Bearer $(sudo cat /var/lib/zerotier-one/metricstoken.secret)"'; else auth=; fi
    n=$(ssh "$h.zt" "bash -c 'curl -fsS --max-time 5 $auth http://$target | grep -v \"^#\" | grep -c -E \"[{,](host_name|host\\.name)=\"'")
    echo "$h $job ${n:-0}"
  done
```

Run it for each present NixOS collecting host; on stibnite run `curl -fsS 127.0.0.1:9100/metrics` and `127.0.0.1:8888/metrics` through the same `grep -c`.
Expected: every count is 0, as on 2026-11-06; a non-zero count stops the task, because the point rule would drop honest data.
Then repeat Task 3 Step 5's gate into the same log: every collecting row reads its URI SAN where its collector loads it, or carries the operator's recorded decision accepting the loss of its backlog; a row with neither stops the task.

- [ ] **Step 2: The MAC gate (tasks.md 5.2) [gate] [operator]**

The orchestrator asks: "May I run the MAC gate and then deploy pull request 2 to magnetite now, with a public SSH session open as the rollback path?"; the answer is recorded.
`logs/cam81-evidence/mac-gate.sh` compares magnetite's live table with the merged commit's rendering:

```bash
#!/usr/bin/env bash
set -euo pipefail
want=$(cd "$DEPLOY" && nix eval --json .#nixosConfigurations.magnetite.config.systemd.network.networks.09-zerotier.neighbors |
  jq -r '.[] | "\(.Address) \(.LinkLayerAddress)"')
live=$(ssh magnetite.zt 'bash -c "z=\$(ip -j link show | jq -r \".[] | select(.ifname|startswith(\\\"zt\\\")) | .ifname\"); ip -j -6 neigh show dev \$z"' |
  jq -r '.[] | "\(.dst) \(.lladdr // "")"')
bad=0
while read -r a m; do
  l=$(awk -v a="$a" '$1 == a {print $2}' <<< "$live")
  if [ -z "$l" ]; then echo "$a want $m live absent (not present on the mesh now)"
  elif [ "$l" = "$m" ]; then echo "$a want $m live $l equal"
  else echo "$a want $m live $l DIFFERENT"; bad=1; fi
done <<< "$want"
[ "$bad" = 0 ]
```

A host absent from the live table is pinged once from magnetite (`ping -6 -c 2 <address>`) and read again, so that every present collecting host is compared.
Expected: every present host `equal`, exit 0; `DIFFERENT` for any host stops the deploy, and the finding goes to the operator (runtime, magnetite; evaluation).

- [ ] **Step 3: Deploy magnetite (tasks.md 5.3) [operator]**

Open the rollback session first, in a separate terminal on stibnite: `ssh root@magnetite.scientistexperience.net`, leaving it at a shell.
Then, in `$DEPLOY`, after `nixbot-logs queue` prints `Queue is empty`:

```bash
L=$REPO/logs/cam81-evidence/5.3-magnetite-$(date -u +%Y%m%dT%H%M%SZ).log
"$REPO/logs/cam81-evidence/mark.sh" MAGNETITE_PR2_EPOCH | tee "$L"
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
```

If the deploy hangs or ZeroTier to magnetite stops answering, the rollback of Step 5 runs from the open session.
Then, rehearse: magnetite, read-only:

```bash
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee -a "$L"
set -uo pipefail
z=$(ip -j link show | jq -r '.[] | select(.ifname|startswith("zt")) | .ifname')
ip -j -6 neigh show dev "$z" nud permanent | jq -c '.[] | {dst, lladdr, state}'
for h in cinnabar pyrite stibnite; do ping -6 -c 3 -W 2 "$h.zt" >/dev/null && echo "$h reachable" || echo "$h UNREACHABLE"; done
systemctl is-active caddy opentelemetry-collector otel-envelope.timer
sudo ss -xlpn | grep otlp.sock; stat -c '%a %G' /run/otelcol-mesh
EOS
. logs/cam81-evidence/window.env; logs/cam81-evidence/posts.sh "$MAGNETITE_PR2_EPOCH" 2>&1 | tee -a "$L"
```

Expected: one `PERMANENT` entry per collecting host with its computed MAC; the present hosts `reachable`; `active` three times; the socket listening and the directory `2770 otelcol-mesh`; each post given its cause (a collector restart and caddy's first start are known causes).

- [ ] **Step 4: The first hour (tasks.md 5.4)**

One hour after Step 3, read on magnetite as `regulator`, for each present collecting host, `count_over_time(system_memory_usage_bytes{host_name="<host>"}[1h])` and `SELECT host, count(*) FROM deploy_record WHERE ts > now() - INTERVAL '1 hour' GROUP BY host`; on each host its exporters' `otelcol_exporter_queue_size` and `otelcol_exporter_send_failed_metric_points`; on magnetite `journalctl -u otel-envelope --since @$MAGNETITE_PR2_EPOCH | grep 'C6 binding'`; and the posts since Step 3.
Expected: about 60 samples per host, queues 0, send failures unchanged since Step 3, every C6 line `ok`, each post given its cause (`logs/cam81-evidence/5.4-hour-<ts>.log`) (runtime).

- [ ] **Step 5: Rollback (tasks.md 5.5), run only if Step 3 or 4 fails**

From the public session:

```bash
z=$(ip -j link show | jq -r '.[] | select(.ifname|startswith("zt")) | .ifname')
ip -6 neigh del <address> dev "$z"     # each wrong entry; emulation answers the next solicitation
```

networkd may reinstall an entry it manages on the next link event, so the pre-binding configuration is deployed at once, without waiting for the merge queue, under plan Global Constraints' rollback exception; on stibnite, with `<first>` the first commit pull request 2 put on `origin/main`:

```bash
git -C "$DEPLOY" checkout --detach "<first>^"
(cd "$DEPLOY" && clan machines update magnetite --target-host root@magnetite.scientistexperience.net 2>&1 | tee "$REPO/logs/magnetite-$(date +%Y%m%d-%H%M%S).log")
```

Then, in the public session on magnetite, `ip -j -6 neigh show dev "$z" nud permanent | jq -c '[.[] | {dst, lladdr}]'` reads the entries absent.

Then revert pull request 2 through the merge queue and deploy the reverted `origin/main` by the ordinary rule.
Expected: `otlp/mesh` back on the ZeroTier address, no caddy, no permanent entry for any collecting host after the rollback deploy, the agents' queues draining; the outcome or `not run` is recorded in `logs/cam81-evidence/5.5-rollback-<ts>.log`.
