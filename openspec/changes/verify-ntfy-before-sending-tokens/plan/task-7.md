### Task 7: Acceptance

Implements `tasks.md` 7.1–7.5 (design "Migration Plan" acceptance; FA `A host posts to the notification service only over a verified connection`, `The service authority's expiry reaches a person 180 days ahead`; FAI `ntfy-send verifies ntfy.zt against caddy's root and fails closed`, `cinnabar checks the root caddy serves weekly`; WA A78, A80).
Steps 1 to 3 start after their host's deploy in Task 6; Step 4 spans the 24 h after Task 6 Step 6.
Nothing here posts to `fleet-alerts`; the root check's controls run its script by hand, outside the unit, so no notice is sent.

**Files:**
- Create (git-ignored): `logs/cam87-evidence/7.<n>-*.log`.
- Modify: `openspec/changes/verify-ntfy-before-sending-tokens/verify.md` (Step 5's table; the file is created in Task 7 if it does not exist yet).

- [ ] **Step 1: A foreign server refuses the token (7.1)**

On magnetite, with the delivered `ntfy-send` found as in Task 6 Step 3 and the ingress's address from `vars/shared/zerotier-ip-magnetite-zerotier/ip/value`:

```bash
ssh magnetite.zt "bash -s" <<'EOF'
ns=<delivered ntfy-send>
ip=<magnetite's ZeroTier address>
rc=0
sudo env NTFY_TOKEN_FILE=<token> "$ns/bin/ntfy-send" "cam87 foreign" fleet-acceptance --connect-to "ntfy.zt:443:[$ip]:4318" > /dev/null 2>&1 || rc=$?
echo "rc=$rc"
EOF
sleep 60
"$REPO/logs/cam87-evidence/read-posts.sh" "$(( $(/bin/date -u +%s) - 300 ))" | grep -c 'cam87 foreign'
```

Expected: `rc=60` and a count of 0; tee to `logs/cam87-evidence/7.1-foreign-<ts>.log`.

- [ ] **Step 2: The hooks post through ntfy-send (7.2) [operator]**

On stibnite, in the operator's shell:

```bash
since=$(/bin/date -u +%s)
notify-permission-wait cam87 probe
printf '{"tool_name":"Bash","tool_input":{"command":"cam87 prompt probe"}}' | notify-permission-prompt
sleep 5
curl -s --cacert "$REPO/vars/per-machine/cinnabar/caddy-root-ca/root.crt/value" "https://ntfy.zt/stibnite/json?poll=1&since=$since" | jq -c 'select(.event == "message") | {title, message}'
for h in notify-permission-wait notify-permission-prompt; do echo "== $h"; rg -n 'curl|ntfy-send' "$(readlink -f "$(command -v $h)")"; done
```

Expected: two messages, `Waiting for permission: cam87: probe` and `Claude Code needs permission to use Bash: cam87 prompt probe`; each hook's only match is its `ntfy-send` call; tee to `logs/cam87-evidence/7.2-hooks-<ts>.log`.

- [ ] **Step 3: The root check's controls (7.3)**

The deployed script's `bundle`, `connect` and `servername` are fixed in its store path; the controls build `flake.lib.caddyRootCheck` from the deployed commit with one argument changed and copy it to cinnabar:

```bash
cd "$DEPLOY"
mk() { nix build --print-out-paths --no-link --impure --option builders "$(grep 930f /etc/nix/machines | head -1)" --expr "let f = builtins.getFlake (toString ./.); pkgs = f.nixosConfigurations.cinnabar.pkgs; in f.lib.caddyRootCheck pkgs ($1)"; }
drift=$(mk '{ bundle = "${./vars/shared/otel-ca/ca.crt/value}"; connect = "ntfy.zt:443"; servername = "ntfy.zt"; }')
early=$(mk '{ bundle = "${./vars/per-machine/cinnabar/caddy-root-ca/root.crt/value}"; connect = "ntfy.zt:443"; servername = "ntfy.zt"; minRemainingSec = 315360000; }')
nix copy --to ssh-ng://cinnabar.zt "$drift" "$early"
ssh cinnabar.zt "$drift/bin/caddy-root-check; echo rc=\$?; $early/bin/caddy-root-check; echo rc=\$?"
```

Expected: the first prints `does not verify` and `rc=1`, the second `expires Dec  6 14:29:17 2035 GMT, within 3650 days` and `rc=1`; `read-posts.sh` over the step's window shows no post on `fleet-alerts`; tee to `logs/cam87-evidence/7.3-root-check-<ts>.log`.

- [ ] **Step 4: A day of posts (7.4)**

24 h after Task 6 Step 6:

```bash
"$REPO/logs/cam87-evidence/read-posts.sh" "$STIBNITE_ACTIVATE_EPOCH"
ssh cinnabar.zt "bash -c 'sudo journalctl -u fleet-deadman --since @$STIBNITE_ACTIVATE_EPOCH --no-pager | grep -c \"heartbeat(s)\"; systemctl list-timers caddy-root-check.timer --no-pager'"
```

The operator states whether the watch service sent any email over the 24 h.
Expected: every post has a cause written under `## Causes`; one dead-man line per 5 min with no failed run; the timer's next run listed; no email; tee to `logs/cam87-evidence/7.4-day-<ts>.log`.

- [ ] **Step 5: Hosts outside the window (7.5)**

Record in `verify.md` a table of electrum, galena and scheelite with their `enabled` line in `modules/terranix/`, and of argentum, blackphos and rosegold with the commit of their last activation where its deploy record is readable, or "not readable" otherwise, and the operator's decision on telling their users (Q4).
Expected: six rows, each with its state and the decision.
