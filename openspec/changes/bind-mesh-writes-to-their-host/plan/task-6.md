### Task 6: Acceptance

Implements `tasks.md` 6.1–6.5 (design D4, D6, D10; O10; FII `magnetite pins each collecting host's neighbour entry`, `otel-envelope on the ingress host fails when the binding refuses or drops a write`, `A mesh write is accepted only from the host its certificate names, at that host's overlay address`, `The ingress proxy runs inside a declared envelope`; HMC `A series is stored only under the host that gathered it`; WA A71, A72).
Every step but Step 5 runs with the operator present, only after Task 5 Steps 3 and 4 passed, and records every post since its start with its cause.
No step copies a key or certificate between hosts.

**Files:**
- Create (git-ignored): `logs/cam81-evidence/6.<n>-*.log`

- [ ] **Step 1: zerotierone restarts on magnetite (tasks.md 6.1) [operator]**

The orchestrator asks: "May I restart zerotierone on magnetite over its public SSH path now? ZeroTier traffic to magnetite stops for about a minute."; the answer is recorded.
Over `ssh root@magnetite.scientistexperience.net`:

```bash
z=$(ip -j link show | jq -r '.[] | select(.ifname|startswith("zt")) | .ifname')
ip -j -6 neigh show dev "$z" nud permanent | jq -c '[.[] | {dst, lladdr}]'
systemctl restart zerotierone; sleep 60
z=$(ip -j link show | jq -r '.[] | select(.ifname|startswith("zt")) | .ifname')
ip -j -6 neigh show dev "$z" nud permanent | jq -c '[.[] | {dst, lladdr}]'
systemctl start otel-envelope.service; journalctl -u otel-envelope -n 20 -o cat | grep 'C6 binding'
```

Expected: the same entries before and after and `C6 binding: ok`; otherwise C6 fails naming the missing entries, which is recorded as a finding and decided by the operator (for example `networkctl reconfigure <link>` in a `zerotierone` `ExecStartPost`, a further change) before Step 2 runs.

- [ ] **Step 2: The spoofing acceptance (tasks.md 6.2) [operator]**

The orchestrator asks: "May I, as root on pyrite, claim stibnite's ZeroTier address toward magnetite, and then a phone's, and clean up afterwards?"; the answer is recorded.
On magnetite, record the table; on pyrite, as root, with `$S` stibnite's address, `$M` magnetite's and `$Z` pyrite's ZeroTier link:

```bash
ip -6 addr add "$S/128" dev "$Z" nodad
python3 /tmp/na.py "$Z" "$S" "$M"     # unsolicited NA, override and solicited flags, target $S, to $M
curl -sS --interface "$S" --max-time 10 -o /dev/null -w '%{http_code}\n' "https://[$M]:4318/v1/metrics"; echo "curl-rc=$?"
ip -6 addr del "$S/128" dev "$Z"
```

`logs/cam81-evidence/na.py`, written in this step, copied to pyrite's `/tmp/na.py` with `scp` and run once with `--dry-run` to print the message before it is sent, builds the ICMPv6 type 136 message with flags `0x60` (solicited, override) and the target link-layer option carrying pyrite's link MAC, and sends it with hop limit 255 from a raw socket bound to `$Z`.
On magnetite, read the entry for `$S` again.
Expected: magnetite's entry for stibnite stays `PERMANENT` with `02:9d:0d:e2:00:15`; curl exits 28 with no HTTP status.
Then the baseline: on magnetite `ping -6 -c 2` the phone `pixel11`'s address `$P`, or, with it off the mesh, another non-collecting member the operator names, so an entry exists; repeat the pyrite block with `$P`; read magnetite's entry for `$P`, then delete it with `ip -6 neigh del "$P" dev <link>` on magnetite.
Expected: magnetite's entry for `$P` names pyrite's MAC after the advertisement, which A72 and A73 predict, and is gone after the deletion; pyrite holds neither address at the end (`logs/cam81-evidence/6.2-spoof-<ts>.log`) (runtime, pyrite, magnetite).

- [ ] **Step 3: The forced mismatch (tasks.md 6.3) [operator]**

From pyrite with its own collector credentials (`sudo` reading the paths its unit loads), one OTLP/JSON gauge `cam81_acceptance` whose resource `host.name` is `cinnabar`, posted to `https://[$M]:4318/v1/metrics`; then `sudo systemctl start otel-envelope.service` on magnetite twice, five minutes apart.
Expected: status 200; `SELECT count(*) FROM cam81_acceptance` as `regulator` fails for a missing table or returns 0; the first run fails `C6 binding` naming `filter/mesh-host-metrics`, one `FAILED otel-envelope.service on magnetite` arrives, the second run passes and its `RESOLVED` follows; each post recorded.

- [ ] **Step 4: The 403 control (tasks.md 6.4) [operator]**

On magnetite, the same gauge with `host.name` `magnetite`, posted to its own mesh site with the certificate and key `opentelemetry-collector` loads (read through `sudo`).
Expected: status 403; caddy's `code="403"` count on `127.0.0.1:2019/metrics` one higher; the next envelope run fails C6 naming caddy and the one after passes; both posts recorded.

- [ ] **Step 5: The first day (tasks.md 6.5)**

Over the 24 h after Task 5 Step 3: `journalctl -u otel-envelope | grep 'C6 binding: FAIL'` lists only Steps 3 and 4; `cat /sys/fs/cgroup/system.slice/caddy.service/memory.peak` is recorded, and above 96 MiB is put to the operator; for each present collecting host, the largest gap between `system_memory_usage_bytes` samples outside its recorded sleeps is at most 60 s.
Expected: `logs/cam81-evidence/6.5-day-<ts>.log` (runtime, magnetite).
