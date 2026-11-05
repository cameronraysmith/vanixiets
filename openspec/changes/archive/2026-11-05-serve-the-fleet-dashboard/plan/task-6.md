### Task 6: Deploy and acceptance

Implements `tasks.md` 4.1–4.5 (design Migration Plan; O8).
No pull request; DNS, then one magnetite deploy, with the operator present.

**Files:**
- Create (git-ignored): `logs/cam73-evidence/4.*-<ts>.log`, `logs/magnetite-<ts>.log`

**Interfaces:**
- Consumes: pull request 2 merged on `origin/main`.
- Produces: the deployment observations FD and FDI scenarios cite; `cameron` in `perses_users`.

- [ ] **Step 1: DNS (tasks.md 4.1)**

Gated, the operator: `just terraform-apply`; then `dig +short obs.scientistexperience.net | tee logs/cam73-evidence/4.1-dns-<ts>.log`.

Expected: `magnetite.scientistexperience.net.` and magnetite's address.

- [ ] **Step 2: Deploy (tasks.md 4.2)**

In `$DEPLOY`, refreshed to `origin/main`, after `nixbot-logs queue` prints `Queue is empty`:

```bash
L=logs/cam73-evidence/4.2-deploy-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
clan vars check magnetite 2>&1 | tee -a "$L"   # must pass before the deploy; a failure stops the step
START=$(/bin/date -u +%Y-%m-%dT%H:%M:%SZ)
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
git -C "$DEPLOY" status --porcelain vars/ | tee -a "$L"   # must print nothing
ssh magnetite.zt 'bash -s' <<'EOF' | tee -a "$L"
systemctl is-active perses kanidm nginx
ss -ltnH | awk '{print $4}' | grep -E ':8095$'
systemctl show perses -p MemoryHigh -p MemoryMax -p OOMScoreAdjust -p Restart
sudo journalctl -u perses --since -10min -o cat | tail -20
EOF
curl -s -o /dev/null -w 'projects %{http_code}\n' https://obs.scientistexperience.net/api/v1/projects | tee -a "$L"
curl -s -o /dev/null -w 'metrics %{http_code}\n' https://obs.scientistexperience.net/metrics | tee -a "$L"
ssh magnetite.zt "sudo journalctl -u fleet-alert --since '$START' -o cat | grep -E 'FIRING|RESOLVED|FAILED'" | tee -a "$L"
```

Then the operator runs `kanidm system oauth2 get perses` and logs in to `omni.` once; both are recorded in the log; every alert and notice since `START`, from the journal above and from `fleet-alerts`, is recorded with its cause.

Expected: `clan vars check` passes before the deploy and `git status --porcelain vars/` prints nothing after it, so the deploy generated no var outside a commit; `active` three times; `127.0.0.1:8095` only; `MemoryMax=268435456`, `OOMScoreAdjust=600`; `projects 401`; `metrics 404`; the client shown with `perses_users`; the `omni.` login succeeds; `kanidm.service`'s restart explains any notice that arrives.

- [ ] **Step 3: The refusal (tasks.md 4.3)**

Gated, the operator: first run `kanidm group get perses_users` and state its members, which the agent records; then, in a browser with no Kanidm session, open `https://obs.scientistexperience.net/`, choose Kanidm, log in as `cameron`.

Expected: `cameron` is not among `perses_users`' members (if he is, stop and ask the operator, because the refusal would be impossible); Kanidm's Access Denied page with an operation id; the operator states the time and the page text, recorded in `logs/cam73-evidence/4.3-refusal-<ts>.log`.

- [ ] **Step 4: The admission (tasks.md 4.4)**

Gated, the operator: `kanidm group add-members perses_users cameron`; log out of Kanidm at `accounts.`; open `https://obs.scientistexperience.net/` and log in again.
Record: the views `fleet-hosts` and `devloop` are listed; `fleet-hosts` with all hosts shows magnetite, cinnabar and pyrite (pyrite only if it is on); `devloop` shows rows; in the browser's developer tools, local storage and session storage for `obs.` hold no value containing the `perses` password or `Basic `; an attempt to save or delete a view is refused or offered no control; the Kanidm apps portal shows the "Observability" tile.

Expected: every observation recorded in `logs/cam73-evidence/4.4-admission-<ts>.log`.

- [ ] **Step 5: The kill (tasks.md 4.5)**

```bash
L=logs/cam73-evidence/4.5-kill-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -c "sudo systemctl kill -s KILL perses; sleep 30; systemctl is-active perses; systemctl show perses -p MemoryCurrent -p MemoryPeak -p NRestarts"' | tee -a "$L"
```

The operator states the time the `FAILED perses on magnetite` notice arrived on `fleet-alerts`, recorded in the log.

Expected: `active` after 30 s; `MemoryPeak` below 268,435,456; one notice.
