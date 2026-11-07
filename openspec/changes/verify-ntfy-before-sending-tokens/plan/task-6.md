### Task 6: The deploy window

Implements `tasks.md` 6.1–6.7 (design D8, "Migration Plan" step 4; O6; FA `A host posts to the notification service only over a verified connection`; FAI `ntfy-send verifies ntfy.zt against caddy's root and fails closed`, `cinnabar checks the root caddy serves weekly`; WA A78, A82).
It starts only after pull requests 2 and 3 have merged, and runs as one sitting with the operator present for Steps 1, 5 and 6.
Every host's closure changes (`brainstorm.md` "Closures"); this window deploys the four running hosts the operator controls, in the order magnetite, cinnabar, pyrite, stibnite, because magnetite's evaluator reads cinnabar's new `notifiedUnits` and its minutely heartbeat is the first live sign of acceptance.
A mixed fleet between steps is safe: the server is unchanged, an old client still posts with `-k`, and a new one verifies.

**Files:**
- Create (git-ignored): `logs/magnetite-<ts>.log`, `logs/cinnabar-<ts>.log`, `logs/pyrite-<ts>.log`, `logs/stibnite-<ts>.log` (in `$DEPLOY`), `logs/cam87-evidence/6.<n>-*.log`, `logs/cam87-evidence/window.env`.

**Interfaces:**
- Consumes: pull requests 2 and 3 merged into `main@origin`; `$DEPLOY`; `read-posts.sh` and `recent-activation.sh` (Task 1 Step 4); each host's token path, read from its evaluated `clan.core.vars.generators.ntfy-alerter.files.token.path`.
- Produces: `window.env` with `WINDOW_START_EPOCH`, `MAGNETITE_DEPLOY_EPOCH`, `CINNABAR_DEPLOY_EPOCH`, `PYRITE_DEPLOY_EPOCH`, `STIBNITE_ACTIVATE_EPOCH`.

Stop rule, for every step: if cinnabar's `fleet-deadman` journal shows a run with zero heartbeats after magnetite's deploy, or any post of this window is refused, stop the window, record it, and take design "Migration Plan"'s rollback for the hosts already deployed; the operator decides whether to continue.

- [ ] **Step 1: Gate (6.1) [operator]**

The operator confirms in this session that they are at stibnite, on mains power and on the mesh, that pyrite is on its LAN and reachable from stibnite, and that no build is dispatched to stibnite.
Then:

```bash
cd "$REPO" && git fetch origin && git -C "$DEPLOY" checkout --detach origin/main
{
  git -C "$DEPLOY" log --oneline -5
  nixbot-logs queue
  echo "WINDOW_START_EPOCH=$(/bin/date -u +%s)" | tee -a logs/cam87-evidence/window.env
} 2>&1 | tee "logs/cam87-evidence/6.1-gate-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the log shows the merge commits of pull requests 2 and 3, `Queue is empty`, and the start epoch; the operator's confirmation and its time are written into the same log.

- [ ] **Step 2: Pre-deploy probe with the merged package (6.2)**

In `$DEPLOY`:

```bash
lin=$(nix build --print-out-paths --no-link .#packages.x86_64-linux.ntfy-send --option builders "$(grep 930f /etc/nix/machines | head -1)")
dar=$(nix build --print-out-paths --no-link .#packages.aarch64-darwin.ntfy-send)
for h in magnetite cinnabar pyrite; do nix copy --to "ssh-ng://$h.zt" "$lin"; done
```

On each NixOS host, as root, with `<token>` that host's evaluated token path:

```bash
ssh <host>.zt "bash -s" <<EOF
rc=0
sudo env NTFY_TOKEN_FILE=<token> $lin/bin/ntfy-send "cam87 probe \$(hostname -s)" fleet-acceptance -H "Title: cam87 probe" > /dev/null || rc=\$?
echo "rc=\$rc"
EOF
```

On stibnite: `/usr/bin/sudo -u _otelcol env NTFY_TOKEN_FILE=<stibnite token> "$dar/bin/ntfy-send" "cam87 probe stibnite" fleet-acceptance -H "Title: cam87 probe"; echo "rc=$?"`.
Then `read-posts.sh "$WINDOW_START_EPOCH"`, keeping its `fleet-acceptance` section.
Expected: four `rc=0` and four `cam87 probe <host>` messages; any other result stops the window here, before any deploy; tee to `logs/cam87-evidence/6.2-probe-<ts>.log`.

- [ ] **Step 3: magnetite (6.3)**

```bash
cd "$DEPLOY"
ssh magnetite.zt 'tail -n 1 /var/log/deploy-record.jsonl'
nixbot-logs queue
echo "MAGNETITE_DEPLOY_EPOCH=$(/bin/date -u +%s)" >> "$REPO/logs/cam87-evidence/window.env"
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
ssh magnetite.zt 'tail -n 1 /var/log/deploy-record.jsonl'
```

Then verify:

```bash
ssh magnetite.zt "bash -s" <<'EOF'
systemctl is-active fleet-alert.timer
w=$(systemctl show -p ExecStart fleet-alert.service | grep -o '/nix/store/[^ ;]*' | head -1)
ns=$(nix-store -qR "$w" | grep -- '-ntfy-send$' | head -1)
sed -n 's/^export NTFY_CACERT=//p' "$ns/bin/ntfy-send"
EOF
```

Copy the printed `NTFY_CACERT` path's content back and `cmp` it with RV; read `sudo journalctl -u fleet-deadman --since @$MAGNETITE_DEPLOY_EPOCH | grep heartbeat` on cinnabar for the next two runs; post `cam87 deployed magnetite` to `fleet-acceptance` with the delivered `ntfy-send` as root and the token; run `read-posts.sh "$MAGNETITE_DEPLOY_EPOCH"` and write each post's cause under `## Causes`.
Expected: `active`; the CA equals RV; each of the next two dead-man runs reports at least one heartbeat; the post is accepted and read back; every post has a cause; tee to `logs/cam87-evidence/6.3-magnetite-<ts>.log`.

- [ ] **Step 4: cinnabar (6.4)**

As Step 3 with `cinnabar`, `CINNABAR_DEPLOY_EPOCH` and `clan machines update cinnabar`, then:

```bash
ssh cinnabar.zt "bash -s" <<'EOF'
systemctl is-active fleet-deadman.timer caddy-root-check.timer
sudo systemctl start caddy-root-check; echo "rc=$?"
sudo journalctl -u caddy-root-check -n 3 --no-pager
systemctl list-timers caddy-root-check.timer --no-pager
EOF
```

Then the delivered `ntfy-send` (from `fleet-deadman.service`'s closure) posts `cam87 deployed cinnabar`; `read-posts.sh "$CINNABAR_DEPLOY_EPOCH"` with causes.
Expected: `active` twice; `rc=0` and `caddy-root-check: served chain verifies against root 7E:78:F6:7C:…:2E:82, expires Dec  6 14:29:17 2035 GMT`; the next Monday 14:00 UTC listed; the next `fleet-deadman` run passes; every post has a cause; tee to `logs/cam87-evidence/6.4-cinnabar-<ts>.log`.

- [ ] **Step 5: pyrite over its LAN address (6.5) [operator]**

With the operator at pyrite's LAN, from stibnite in `$DEPLOY`:

```bash
ssh root@<pyrite LAN address> 'tail -n 1 /var/log/deploy-record.jsonl'
nixbot-logs queue
echo "PYRITE_DEPLOY_EPOCH=$(/bin/date -u +%s)" >> "$REPO/logs/cam87-evidence/window.env"
clan machines update pyrite --target-host root@<pyrite LAN address> 2>&1 | tee logs/pyrite-$(date +%Y%m%d-%H%M%S).log
```

Then `systemctl is-active otel-envelope.timer opentelemetry-collector`, the delivered `ntfy-send` (from an `observability-notify@` hook's closure) posting `cam87 deployed pyrite`, and `read-posts.sh "$PYRITE_DEPLOY_EPOCH"` with causes.
Expected: `active` twice; the post accepted and read back; every post has a cause; tee to `logs/cam87-evidence/6.5-pyrite-<ts>.log`.

- [ ] **Step 6: stibnite (6.6) [operator]**

```bash
"$REPO/logs/cam87-evidence/recent-activation.sh"
echo "STIBNITE_ACTIVATE_EPOCH=$(/bin/date -u +%s)" >> "$REPO/logs/cam87-evidence/window.env"
cd "$DEPLOY" && just activate 2>&1 | tee logs/stibnite-$(/bin/date +%Y%m%d-%H%M%S).log
```

`recent-activation.sh` exiting 1 stops the step for the operator.
Then verify the delivered envelope job's client:

```bash
p=$(grep -o '/nix/store/[^ <"]*-observability-notify-run' /Library/LaunchDaemons/org.nixos.otel-envelope.plist | head -1)
ns=$(nix-store -qR "$p" | grep -- '-ntfy-send$' | head -1)
grep -E '^export NTFY_(CURL_BIN|CACERT)=' "$ns/bin/ntfy-send"
grep -o '/nix/store/[^:]*-curl-[^:/]*/bin' "$ns/bin/ntfy-send" | head -1
cmp "$(sed -n 's/^export NTFY_CACERT=//p' "$ns/bin/ntfy-send")" "$REPO/vars/per-machine/cinnabar/caddy-root-ca/root.crt/value" && echo "NTFY_CACERT equals RV"
sleep 330; /bin/launchctl print system/org.nixos.otel-envelope | grep -E 'runs|last exit code'
/usr/bin/sudo -u _otelcol env NTFY_TOKEN_FILE=<stibnite token> "$ns/bin/ntfy-send" "cam87 deployed stibnite" fleet-acceptance > /dev/null; echo "rc=$?"
"$REPO/logs/cam87-evidence/read-posts.sh" "$STIBNITE_ACTIVATE_EPOCH"
```

Expected: `NTFY_CURL_BIN=curl`, a store curl directory on the wrapper's `PATH`, the CA equal to RV; `runs` one higher than before the activation and `last exit code = 0`; `rc=0` and the message read back; every post has a cause; tee to `logs/cam87-evidence/6.6-stibnite-<ts>.log`.

- [ ] **Step 7: Close the window (6.7)**

```bash
"$REPO/logs/cam87-evidence/read-posts.sh" "$WINDOW_START_EPOCH" 2>&1 | tee "logs/cam87-evidence/6.7-window-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Write each post's cause under `## Causes` in the same log: the probes and deploy posts of this task, each deploy's restarted units, and anything else with its journal evidence.
Expected: no post without a cause; if magnetite's heartbeats stopped at any point, the log records the stop, the rollback taken, and the operator's decision.
