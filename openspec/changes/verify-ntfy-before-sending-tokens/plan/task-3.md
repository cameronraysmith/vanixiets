### Task 3: cinnabar's switch to the vars

Implements `tasks.md` 3.1 (design D8 step 1; O12; FA `A reinstall of cinnabar keeps the service authority`; WA A78).
It starts after pull request 1 merges and deploys cinnabar alone, before any client changes, so a failure here is caddy's and no post depends on the new client.
Stop rule: if caddy is not `active` after the switch, or the served chain does not verify against RV, revert pull request 1 and deploy cinnabar again, which returns caddy to the same root in its storage.

**Files:**
- Create (git-ignored): `logs/cinnabar-<ts>.log` (in `$DEPLOY`), `logs/cam87-evidence/3.1-cinnabar-<ts>.log`.

**Interfaces:**
- Consumes: pull request 1 merged into `main@origin`; `$DEPLOY`; `read-posts.sh` (Task 1 Step 4); Task 1 Step 3's served intermediate.

- [ ] **Step 1: Before (3.1)**

```bash
cd "$REPO" && git fetch origin && git -C "$DEPLOY" checkout --detach origin/main
rv="$DEPLOY/vars/per-machine/cinnabar/caddy-root-ca/root.crt/value"
served() {
  openssl s_client -connect ntfy.zt:443 -servername ntfy.zt -showcerts < /dev/null 2>/dev/null \
    | awk '/BEGIN CERTIFICATE/{n++} n==2' | sed '/END CERTIFICATE/q' > /tmp/cam87-int.pem
  openssl x509 -in /tmp/cam87-int.pem -noout -issuer -fingerprint -sha256 -enddate
  openssl verify -CAfile "$rv" /tmp/cam87-int.pem
}
{
  echo "== served before"; served
  ssh cinnabar.zt 'tail -n 1 /var/log/deploy-record.jsonl'
  nixbot-logs queue
  echo "CINNABAR_SWITCH_EPOCH=$(/bin/date -u +%s)" | tee -a "$REPO/logs/cam87-evidence/window.env"
} 2>&1 | tee "logs/cam87-evidence/3.1-cinnabar-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `OK` against RV, the same intermediate as Task 1 Step 3 or a weekly renewal of it, `Queue is empty`.

- [ ] **Step 2: Deploy and after (3.1)**

```bash
source "$REPO/logs/cam87-evidence/window.env"
log=$(ls -t "$REPO"/logs/cam87-evidence/3.1-cinnabar-*.log | head -1)
cd "$DEPLOY" && clan machines update cinnabar 2>&1 | tee logs/cinnabar-$(date +%Y%m%d-%H%M%S).log
{
  ssh cinnabar.zt 'tail -n 1 /var/log/deploy-record.jsonl'
  ssh cinnabar.zt "bash -c 'systemctl is-active caddy; sudo stat -c \"%U %a %n\" /run/secrets/vars/per-machine/cinnabar/caddy-root-ca/root.key; sudo journalctl -u caddy --since @$CINNABAR_SWITCH_EPOCH --no-pager | grep -iE \"pki|root|intermediate|error\" | tail -20'"
  echo "== served after"; served
  curl -s --cacert "$rv" https://ntfy.zt/v1/health; echo
  "$REPO/logs/cam87-evidence/read-posts.sh" "$CINNABAR_SWITCH_EPOCH"
} 2>&1 | tee -a "$log"
```

`CINNABAR_SWITCH_EPOCH` is sourced from `window.env` before the block; the local shell expands it into the remote command.
Expected: the deploy log ends without error and its deploy record is the only new one; `active`; `caddy 400 …/root.key`; caddy's journal shows the PKI app provisioning without error, and a root path naming the var where caddy logs one; the served intermediate verifies `OK` against RV, the same as before or reissued, either recorded; `{"healthy":true…}`; every post since the switch has a cause written under `## Causes`.
