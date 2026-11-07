### Task 3: Deploying pull request 1

Implements `tasks.md` 3.1–3.4 (design D2, Migration Plan steps 3 and 4; FII `The collection CA issues each agent host one certificate`).
It starts only after pull request 1 has merged; magnetite deploys first, because its own server certificate is reissued and `flake.lib.hosts` is in its closure, then cinnabar, pyrite and stibnite.
No listener reads the SAN yet, so every step here changes certificates only.

**Files:**
- Create (git-ignored): `logs/<machine>-<ts>.log`, `logs/cam81-evidence/3.<n>-*.log`, `logs/cam81-evidence/{window.env,mark.sh,posts.sh,recent-activation.sh}`

**Interfaces:**
- Consumes: pull request 1 merged into `main@origin`; `$DEPLOY`.
- Produces: `mark.sh`, `posts.sh` and `recent-activation.sh`, which every later deploy, activation and operator step uses.

- [ ] **Step 1: The start and post helpers**

Copy `mark.sh`, `posts.sh` and `recent-activation.sh` from `stand-up-darwin-collection`'s `plan/task-4.md` Step 1 (under `openspec/changes/archive/` after Task 1 Step 3) into `logs/cam81-evidence/`, changing only their evidence directory, and make each executable.
`posts.sh <epoch>` prints magnetite's `fleet-alert` and `observability-notify@*` posts since the epoch and the lines stibnite's `notify.log` gained since `mark.sh` recorded its count.
rehearse: stibnite and magnetite, as in that plan.

- [ ] **Step 2: Deploy magnetite (tasks.md 3.1)**

In `$DEPLOY`, after refreshing it and `nixbot-logs queue` printing `Queue is empty`:

```bash
L=$REPO/logs/cam81-evidence/3.1-magnetite-$(date -u +%Y%m%dT%H%M%SZ).log
"$REPO/logs/cam81-evidence/mark.sh" MAGNETITE_PR1_EPOCH | tee "$L"
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
```

Expected: the log ends without error.
Then, rehearse: magnetite, read-only:

```bash
ssh magnetite.zt 'bash -s' <<'EOS' 2>&1 | tee -a "$L"
set -uo pipefail
readlink -f /run/current-system
c=$(systemctl show opentelemetry-collector -p LoadCredential --value | tr ' ' '\n' | sed -n 's/^otel-cert://p')
sudo openssl x509 -noout -ext subjectAltName -in "$c"
r() { curl -s 127.0.0.1:8888/metrics | awk '/^otelcol_receiver_accepted_metric_points.*receiver="otlp\/mesh"/ {s+=$2} END {print s+0}'; }
a=$(r); sleep 60; b=$(r); echo "accepted $a -> $b"
EOS
. logs/cam81-evidence/window.env; logs/cam81-evidence/posts.sh "$MAGNETITE_PR1_EPOCH" 2>&1 | tee -a "$L"
```

Expected: a new closure; `URI:spiffe://vanixiets/host/magnetite` among the SANs; the accepted count grows, so the agents accept the reissued server certificate; `grep-rc=1`, or each post given its cause under `## Causes` (a collector restart by `restartUnits` is a known cause).

- [ ] **Step 3: Deploy cinnabar and pyrite (tasks.md 3.2)**

The same commands for `cinnabar`, then `pyrite` if `ping -6 -c 1 pyrite.zt` answers; otherwise pyrite deploys when it returns, before Task 5.
After each, rehearse: the host, read-only:

```bash
ssh <host>.zt 'bash -s' <<'EOS'
c=$(systemctl show opentelemetry-collector -p LoadCredential --value | tr ' ' '\n' | sed -n 's/^otel-cert://p')
sudo openssl x509 -noout -ext subjectAltName -in "$c"
sudo systemctl start otel-envelope.service; systemctl show otel-envelope -p Result --value
EOS
```

Expected: the host's URI SAN; `success`; each post since the deploy given its cause.

- [ ] **Step 4: stibnite's activation (tasks.md 3.3) [operator]**

The orchestrator asks: "Are you at stibnite now, and may I activate pull request 1 on it with `just activate`?"; the answer and its time are recorded, and without a yes this step does not run.

```bash
L=$REPO/logs/cam81-evidence/3.3-stibnite-$(date -u +%Y%m%dT%H%M%SZ).log
"$REPO/logs/cam81-evidence/recent-activation.sh" 2>&1 | tee "$L"
/usr/bin/plutil -extract EnvironmentVariables.OTEL_CERT_SHA256 raw /Library/LaunchDaemons/org.nixos.otelcol.plist | tee -a "$L"
"$REPO/logs/cam81-evidence/mark.sh" STIBNITE_PR1_EPOCH | tee -a "$L"
just activate 2>&1 | tee logs/stibnite-$(date +%Y%m%d-%H%M%S).log
/usr/bin/plutil -extract EnvironmentVariables.OTEL_CERT_SHA256 raw /Library/LaunchDaemons/org.nixos.otelcol.plist | tee -a "$L"
/bin/launchctl print system/org.nixos.otelcol | grep -E '^\s*(pid|state) =' | tee -a "$L"
s() { curl -s 127.0.0.1:8888/metrics | awk '/^otelcol_exporter_sent_metric_points.*exporter="otlp_http\/ingress"/ {s+=$2} END {print s+0}'; }
a=$(s); sleep 60; b=$(s); echo "sent $a -> $b" | tee -a "$L"
```

Expected: `no activation since`; two different hashes; `state = running` with a new `pid`; the sent count grows; each post since the activation given its cause.

- [ ] **Step 5: The reissued-certificate gate (tasks.md 3.4) [gate]**

Collect the four SAN readings of Steps 2 to 4 into `logs/cam81-evidence/3.4-san-gate-<ts>.log`, and for stibnite add `sudo openssl x509 -noout -ext subjectAltName -in "$(nix eval --raw '.#darwinConfigurations.stibnite.config.clan.core.vars.generators.otel-cert.files."cert.pem".path')"`.
List every collecting row of `flake.lib.observabilityHosts` (`nix eval --json .#lib.observabilityHosts --apply 'builtins.mapAttrs (_: r: r.collect)'`) beside its reading.
A host absent now, pyrite off the mesh or stibnite asleep, is read when it returns and before Task 5 Step 3; otherwise the orchestrator asks: "<host> still holds its old certificate; once the binding deploys, caddy answers it 403 and its exporter drops up to 24 h of queued data. Do you accept that loss, or should Task 5 wait for it?"; the answer and its time are recorded in the log.
electrum, galena and scheelite, not provisioned and holding no backlog, are listed as taking their certificate from the committed vars when next provisioned.
Expected: magnetite, cinnabar, pyrite and stibnite each read their URI SAN from the file their collector loads, or carry the operator's recorded decision; a host with neither stops Task 5.
