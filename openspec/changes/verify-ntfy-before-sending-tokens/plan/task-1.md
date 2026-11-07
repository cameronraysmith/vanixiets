### Task 1: Plan review, gate, baselines and rehearsal

Implements `tasks.md` 1.1–1.4 (design "Migration Plan" step 1; O7).
Nothing here changes code or deploys; Step 4 posts only to `fleet-acceptance`.

**Files:**
- Create: `openspec/changes/verify-ntfy-before-sending-tokens/review-plan.md` (Step 1).
- Create (git-ignored): `logs/cam87-evidence/1.2-gate-<ts>.log`, `1.3-baseline-<ts>.log`, `1.4-rehearsal-<ts>.log`, `logs/cam87-evidence/read-posts.sh`, `logs/cam87-evidence/recent-activation.sh`.

**Interfaces:**
- Produces: the dispositions of each review finding (Q1 to Q7 were decided on 2026-11-07), applied to the planning artifacts; the baseline figures every later cost comparison reads; `read-posts.sh` and `recent-activation.sh`, which Tasks 3 and 6 use.

- [ ] **Step 1: Plan review (1.1)**

Dispatch one read-only subagent of the default `task` type on an Opus model with this brief: read `brainstorm.md`, `design.md`, `tasks.md`, `plan.md`, `plan/` and `specs/` of this change, and answer the four holistic questions (critical oversights; significant architecture improvements; checks that cannot fail, clauses restating the line they judge, and properties nothing covers; checks or mechanisms costing more than the invariant they protect); list every test case, check clause, leg, build-time check and assertion of Tasks 2 to 5 with its two value sources, and judge the import procedure of Task 2 Step 4 and the security trade-off of storing caddy's root key as clan vars; write `review-plan.md` with a severity summary and a findings table.
Append a dispositions table with one row per finding, each with the recommendation from `brainstorm.md` or the review; the operator decides each row in the session.
Apply the accepted rows to the artifacts, then run:

```bash
openspec validate verify-ntfy-before-sending-tokens --strict
```

Expected: `Change 'verify-ntfy-before-sending-tokens' is valid`.
Commit the planning artifacts and open the planning pull request; it merges through the queue.

- [ ] **Step 2: The gate (1.2)**

Wait until `stand-up-darwin-collection` has archived on `main@origin`, then record:

```bash
git -C "$REPO" fetch origin
{
  git -C "$REPO" rev-parse origin/main
  openspec list --json | jq -r '.changes[].name'
  git -C "$REPO" ls-tree -d --name-only origin/main openspec/changes/archive/ | grep stand-up-darwin-collection
  rg -n 'A7[89] |A8[0-3] ' openspec/specs || echo "no A78-A83 in the corpus"
  rg -n '^- v30 ' docs/notes/development/observability/charter.md || echo "no charter v30"
} 2>&1 | tee "logs/cam87-evidence/1.2-gate-$(/bin/date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the list omits `stand-up-darwin-collection`, the archive directory exists, and both searches print their `no …` line.
Then compare the two modified requirements with their post-archive corpus text:

```bash
awk '/^### Requirement: This capability states its own trust boundary/,/^### Requirement: The pull-request/' openspec/specs/fleet-alerting-interface/spec.md > /tmp/tb-corpus.md
awk '/^## MODIFIED/{m=1} m' openspec/changes/verify-ntfy-before-sending-tokens/specs/fleet-alerting-interface/spec.md > /tmp/tb-change.md
diff /tmp/tb-corpus.md /tmp/tb-change.md
awk '/^## ADDED/{exit} {print}' openspec/changes/verify-ntfy-before-sending-tokens/specs/world-assumptions/spec.md | grep '^|' | LC_ALL=C sort > /tmp/rows-change
awk '/^### Requirement: Grounded vocabulary/,/^### Requirement: A1 /' openspec/specs/world-assumptions/spec.md | grep '^|' | LC_ALL=C sort > /tmp/rows-corpus
LC_ALL=C comm -3 /tmp/rows-corpus /tmp/rows-change
```

Expected: the trust-boundary diff shows only this change's added sentence and three scenarios; `comm -3` prints only the rows `service authority` and `verified connection` in the second column.
Any other difference is carried into this change's deltas, and the step is repeated until it holds.

- [ ] **Step 3: Baselines (1.3)**

At `main@origin` after Step 2, record evaluation costs:

```bash
for c in fleet-alert otel-collector-config otel-collector-darwin hook-gate-dangerous-commands package-ntfy-send-test-token-transport nixos-magnetite nixos-cinnabar nixos-pyrite; do
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/$c-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.$c.drvPath > /dev/null
  printf '%s %s %s\n' "$c" "$(jq '.gc.totalBytes' /tmp/$c-stats.json)" "$(jq '.cpuTime' /tmp/$c-stats.json)"
done
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/darwin-stibnite-stats.json nix eval --option eval-cache false --raw .#.checks.aarch64-darwin.darwin-stibnite.drvPath > /dev/null
jq '.gc.totalBytes, .cpuTime' /tmp/darwin-stibnite-stats.json
```

Record the hosts whose closure holds `ntfy-send` (evaluation):

```bash
for h in cinnabar electrum galena magnetite pyrite scheelite; do
  d=$(nix eval --raw .#nixosConfigurations.$h.config.system.build.toplevel.drvPath)
  printf '%s %s\n' "$h" "$(nix-store -qR "$d" | grep -c -- '-ntfy-send.drv$')"
done
for h in argentum blackphos rosegold stibnite; do
  d=$(nix eval --raw .#darwinConfigurations.$h.config.system.build.toplevel.drvPath)
  printf '%s %s\n' "$h" "$(nix-store -qR "$d" | grep -c -- '-ntfy-send.drv$')"
done
rg -n 'enabled = ' modules/terranix/hetzner.nix modules/terranix/gcp.nix
```

Expected: each of the ten hosts prints a count of at least 1; electrum, galena and scheelite are `enabled = false`.
Record caddy's stored root against CR (A78):

```bash
ssh cinnabar.zt 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' | openssl x509 -noout -fingerprint -sha256 -enddate
openssl x509 -in modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt -noout -fingerprint -sha256 -enddate
```

Expected: both print `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82` and `notAfter=Dec  6 14:29:17 2035 GMT`.
Record the chain caddy serves, the baseline Task 3 compares with:

```bash
openssl s_client -connect ntfy.zt:443 -servername ntfy.zt -showcerts < /dev/null 2>/dev/null \
  | awk '/BEGIN CERTIFICATE/{n++} n==2' | sed '/END CERTIFICATE/q' > /tmp/cam87-int.pem
openssl x509 -in /tmp/cam87-int.pem -noout -subject -issuer -fingerprint -sha256 -enddate
openssl verify -CAfile modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt /tmp/cam87-int.pem
cfg=$(nix eval --raw .#nixosConfigurations.cinnabar.config.services.caddy.configFile)
nix build --no-link --option builders "$(grep 930f /etc/nix/machines | head -1)" "$cfg" 2>/dev/null || true
grep -n 'pki' "$cfg" || echo "no pki block"
```

Expected: the intermediate's issuer is `Caddy Local Authority - 2026 ECC Root`, `openssl verify` prints `OK`, and cinnabar's evaluated Caddyfile (`services.caddy.configFile`, built locally) holds no `pki` block.
On magnetite, cinnabar, pyrite and stibnite record `readlink /run/current-system` and `tail -n 1 /var/log/deploy-record.jsonl`.
Tee all of it to `logs/cam87-evidence/1.3-baseline-<ts>.log`.

- [ ] **Step 4: Rehearsal (1.4)**

Create `logs/cam87-evidence/read-posts.sh` (git-ignored):

```bash
#!/bin/bash
# read-posts.sh SINCE_EPOCH: every post since SINCE_EPOCH from the four hosts and the topics.
set -uo pipefail
since=$1
ca="$REPO/vars/per-machine/cinnabar/caddy-root-ca/root.crt/value"
[ -f "$ca" ] || ca="$REPO/modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt"  # before pull request 1
echo "== magnetite"; ssh magnetite.zt "bash -c 'sudo journalctl -u fleet-alert -u \"observability-notify@*\" --since @$since -o short-iso --no-pager'"
echo "== cinnabar"; ssh cinnabar.zt "bash -c 'sudo journalctl -u fleet-deadman -u \"observability-notify@*\" -u caddy-root-check --since @$since -o short-iso --no-pager'"
echo "== pyrite"; ssh pyrite.zt "bash -c 'sudo journalctl -u \"observability-notify@*\" --since @$since -o short-iso --no-pager'"
echo "== stibnite otel-envelope.log"; /usr/bin/sudo /usr/bin/tail -n 200 /var/log/otelcol/otel-envelope.log
echo "== stibnite notify.log"; /usr/bin/sudo /bin/cat /var/lib/otel-envelope/notify.log 2>/dev/null || echo "notify.log absent"
for t in fleet-alerts fleet-acceptance magnetite cinnabar pyrite stibnite; do
  echo "== topic $t"
  curl -s --cacert "$ca" "https://ntfy.zt/$t/json?poll=1&since=$since" | jq -c 'select(.event == "message") | {time, title: (.title // ""), message}'
done
```

`recent-activation.sh` is copied from `logs/s5-evidence/recent-activation.sh`, which CAM-72's Task 4 wrote, with its evidence directory changed to `logs/cam87-evidence`.
Then, on each host, post with exactly the argument list of plan "Grounding", using the root pin's curl for that system and a copy of CR the account reads:

```bash
# magnetite, cinnabar, pyrite (as root); <curl> from `nix build --print-out-paths --option builders "$(grep 930f /etc/nix/machines | head -1)" .#nixosConfigurations.<host>.pkgs.curl.bin` copied with `nix copy --to ssh-ng://<host>.zt`
ssh <host>.zt "bash -s" <<'EOF'
set -uo pipefail
rc=0
printf 'Authorization: Bearer %s\n' "$(sudo cat <token path>)" \
  | <curl>/bin/curl -sf --cacert /tmp/cam87-caddy-root.crt -m 5 -H @- -H 'Title: cam87 rehearsal' -d "cam87 rehearsal $(hostname -s)" https://ntfy.zt/fleet-acceptance || rc=$?
echo "rc=$rc"
EOF
```

The token path is read from each host's evaluated `clan.core.vars.generators.ntfy-alerter.files.token.path` before the step, never assumed.
On stibnite, run the same as `_otelcol` with `/usr/bin/sudo -u _otelcol /bin/bash -c '…'`, the token path from `darwinConfigurations.stibnite.config.clan.core.vars.generators.ntfy-alerter.files.token.path`, and `<curl>` from `nix build --print-out-paths .#darwinConfigurations.stibnite.pkgs.curl.bin`.
Then run once, read-only, every verification block of Tasks 3, 6 and 7 that does not deploy, post or run a hand control, and Task 2 Step 4's comparisons against CR in place of RV, with `read-posts.sh` over the last 24 h.
Expected: four `rc=0` lines and four `cam87 rehearsal <host>` messages in `read-posts.sh`'s `fleet-acceptance` section; tee to `logs/cam87-evidence/1.4-rehearsal-<ts>.log`.
