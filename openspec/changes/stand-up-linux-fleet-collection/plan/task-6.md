### Task 6: Rules over the fleet

Implements `tasks.md` 6.1–6.7 (design D9, Migration Plan step 6; S2-R6's replay rule; FAI `Alert rules are rendered from one Nix source to the evaluator and to promtool`, `Each rule's presence selector is watched`, `An always-on host's silence is reported`, `The evaluator queries each rule's database as the regulators' store account`; FA `Each known failure class on a host reaches a person as an alert`, `A missing signal is itself reported`).
This is pull request 2, started after Task 5 Step 4, deployed to magnetite only.
The replay over stored history (Step 1) precedes the rules, the fixture legs (Step 2) fail before the rules change (Step 3), and the deployed rules are observed for 30 min with a hand-run negative control (Step 7).
`transition.jq` and `model.py` are unchanged: `alwaysOn` and the expected hosts are data their rules already read (design D9).

**Files:**
- Modify: `modules/nixos/fleet-alert/rules.nix:42-45` (`presence`), `:85-177` (the rule list), header `:19-25`
- Modify: `modules/checks/fleet-alert.nix` (legs after `alwaysOnSilentLeg`, `:777-798`; `legs`, `:945-960`; `runtimeMutants`, `:1059-1118`), and fixtures under `modules/checks/fleet-alert/fixtures/` as the existing legs keep them
- Create (git-ignored): `logs/s4-evidence/6.<n>-*.log`, `logs/s4-evidence/6.1-replay.sh`

**Interfaces:**
- Consumes: `flake.lib.fleetAlertRules { lib, hosts ? … }` and `twoHostExclusionLeg` (Task 2 Step 9); `flake.lib.observabilityHosts`; the existing legs `signalGapLeg`, `alwaysOnSilentLeg`, `silentHostLeg` and the runtime mutant `noHostsUpdate` as patterns; magnetite's stored `fleet` history since Tasks 4 and 5.
- Produces: the deployed rule set of 11 PromQL rules plus `PullRequestQueueWaitBurn`, read by Task 9 Step 2's acceptance and Task 5 Step 6's offline test.

- [ ] **Step 1: Replay the new rules over stored history (tasks.md 6.1)**

Start at least 24 h after Task 5 Step 2, so pyrite has a day of history.
Create `logs/s4-evidence/6.1-replay.sh`, which runs one PromQL expression as `regulator` through `/v1/prometheus/api/v1/query_range` with `start` the earliest of the three hosts' first `system_memory_usage_bytes` sample, `end` now and `step=60`, and prints `<host_name> <mountpoint or device> <first ts> <last ts> <max value>` for each contiguous run of points; rehearse it in Task 1 Step 3 against magnetite's history.
Replay:

```bash
L=logs/s4-evidence/6.1-replay-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
r=logs/s4-evidence/6.1-replay.sh
$r 'sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.85' | tee "$L"
$r 'sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes) > 0.95' | tee -a "$L"
$r 'smartctl_device_critical_warning != 0' | tee -a "$L"
$r 'smartctl_device_percentage_used > 90' | tee -a "$L"
$r 'count by (host_name) (system_memory_usage_bytes{host_name="cinnabar"})' | tee -a "$L"
```

Expected: for each of the first four, the runs that last at least the rule's `for` (15 min, 5 min, 0, 1 h) are the would-be firings; for the last, each gap of 10 min or more between cinnabar's runs is a would-be `RuleSignalMissing cinnabar`.
Each would-be firing is attributed in the log to its cause (a ZFS dataset near its quota, a deploy's restart of cinnabar's collector, and so on); a rule whose would-be firings share one known cause is put to the operator, whose decision is recorded under `## Decision` before Step 4.

- [ ] **Step 2: The fixture legs, seen failing (tasks.md 6.2)**

Add to `modules/checks/fleet-alert.nix`, built with the existing `gap` and `minute` helpers and the real `rules` (rendered from `flake.lib.observabilityHosts`):

| Leg | Replayed answers | Expected posts |
|---|---|---|
| `cinnabarSilentLeg` | `system_memory_usage_bytes` for magnetite every run; for cinnabar until t0, then none for 40 min, then again | one `[FIRING] RuleSignalMissing cinnabar` 10 min after cinnabar last reported, one `[RESOLVED] RuleSignalMissing cinnabar` when it reports again, nothing else |
| `laptopSilentLeg` | `HostOOMKill` firing for pyrite, then no `system_memory_usage_bytes` for pyrite or electrum for 40 min while magnetite and cinnabar report | nothing about pyrite or electrum: no silence, no resolution, no repeat |
| `nvmeExpectsPyriteLeg` | memory for magnetite and cinnabar only, no `smartctl_device_critical_warning`, 30 min; then pyrite's memory too for 30 min, still no SMART series | nothing in the first 30 min; then one `[FIRING] RuleSignalMissing` naming `NvmeCriticalWarning`, and one naming `NvmeWearHigh` |
| `filesystemLeg` | cinnabar's `/` at 0.9 for 15 min, then 0.97 for 5 min | one `[FIRING] FilesystemFillingWarn cinnabar` at priority `default`, then one `[FIRING] FilesystemFull cinnabar` at the critical priority |
| `nvmeLeg` | pyrite's `smartctl_device_critical_warning` 1 on one run | one `[FIRING] NvmeCriticalWarning pyrite` at the critical priority |

Add the runtime mutant `alwaysOnMagnetiteOnly`, the real evaluator with a rules JSON whose `RuleSignalMissing.alwaysOn` is `[ "magnetite" ]`, which `cinnabarSilentLeg` must reject; and add the five legs to `legs`.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s4-evidence/6.2-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E 'FAIL|leg'
```

Expected: FAIL, naming `cinnabarSilentLeg`, `nvmeExpectsPyriteLeg`, `filesystemLeg` and `nvmeLeg` (no such rules or hosts yet); `laptopSilentLeg` may already pass, since today nothing about pyrite is expected (RED).

- [ ] **Step 3: The rules read the host table (tasks.md 6.3)**

In `modules/nixos/fleet-alert/rules.nix`:

```nix
# A host is expected, or always-on, only once it collects (design D6, D9).
collecting = lib.filterAttrs (_: h: h.collect) hosts;
agentHosts = builtins.attrNames collecting;
smartHosts = builtins.attrNames (lib.filterAttrs (_: h: h.smartDevices != [ ]) collecting);
presence = expectedHosts: selector: { inherit selector expectedHosts; };
```

Every existing rule's `presence` becomes `map (presence agentHosts) [ … ]` or `[ (presence agentHosts "…") ]`; `RuleSignalMissing.alwaysOn = builtins.attrNames (lib.filterAttrs (_: h: h.alwaysOn) collecting);` replaces `[ "magnetite" ]`; and four rules are added after `ZfsPoolUnhealthy`, with the expressions of the FAI scenario `The file-system and disk-health rules are rendered`.
The leg `notCollectingLeg`, written in Step 2 with the others, takes the real table with pyrite's `collect` set false: pyrite silent for 40 min with no SMART series while magnetite and cinnabar report, expecting no `RuleSignalMissing` naming an NVMe rule or pyrite; it fails until this filter exists.
The four rules:

```nix
{ alert = "FilesystemFillingWarn"; expr = fsRatio + " > 0.85"; for = "15m"; severity = "warning";
  annotations.summary = "A ZFS file system is more than 85 % full"; presence = [ (presence agentHosts "system_filesystem_usage_bytes") ]; }
{ alert = "FilesystemFull"; expr = fsRatio + " > 0.95"; for = "5m"; severity = "critical";
  annotations.summary = "A ZFS file system is more than 95 % full"; presence = [ (presence agentHosts "system_filesystem_usage_bytes") ]; }
{ alert = "NvmeCriticalWarning"; expr = "smartctl_device_critical_warning != 0"; for = "0s"; severity = "critical";
  annotations.summary = "A laptop's NVMe controller reports a critical warning"; presence = [ (presence smartHosts "smartctl_device_critical_warning") ]; }
{ alert = "NvmeWearHigh"; expr = "smartctl_device_percentage_used > 90"; for = "1h"; severity = "warning";
  annotations.summary = "A laptop's SSD has used more than 90 % of its rated endurance"; presence = [ (presence smartHosts "smartctl_device_percentage_used") ]; }
```

with `fsRatio = ''sum by (host_name, mountpoint) (system_filesystem_usage_bytes{state="used"}) / sum by (host_name, mountpoint) (system_filesystem_usage_bytes)'';`, and the header comment's `:19-25` saying the expected and always-on hosts come from `flake.lib.observabilityHosts` (design D9).
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s4-evidence/6.3-rules-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee "$L" | grep -E 'SUCCESS|FAIL|mutant|Leg'
nix eval --json .#.lib.fleetAlertRules --apply 'f: let r = (f { lib = (builtins.getFlake "nixpkgs").lib; }).rules; in map (x: { inherit (x) alert; hosts = map (p: p.expectedHosts) (x.presence or [ ]); alwaysOn = x.alwaysOn or null; }) r' | tee -a "$L"
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/fleet-alert-stats.json | tee -a "$L"
```

If `builtins.getFlake "nixpkgs"` is not resolvable on the machine, evaluate through `.#nixosConfigurations.magnetite.config.services.fleet-alert` instead, whose rendered JSON the module carries.
Expected: `SUCCESS: 11 rules found`; every leg passes, the five new ones included; `alwaysOnMagnetiteOnly` rejected; every PromQL rule's expected hosts are the six agent hosts, the NVMe rules' `["pyrite"]`, and `RuleSignalMissing`'s `alwaysOn` `["cinnabar","magnetite"]`; cost between 0.30 and 0.34 GiB and below 536,870,912 (design D10).

- [ ] **Step 4: The pull request (tasks.md 6.4)**

Run `nix fmt` and `nix fmt -- --fail-on-change`, keeping the log; commit with a plain message, for example "Alert on full file systems and failing laptop disks, and on cinnabar's silence"; open pull request 2 with the same kind of title, its body describing the rules and stating in words the replay's would-be firings, their causes and the operator's decision (no log path), with no slice, decision or task code.
Expected: nixbot green, including `fleet-alert` and `nixos-magnetite`.

- [ ] **Step 5: Deploy magnetite (tasks.md 6.5)**

In `$DEPLOY`, after `git -C $REPO fetch origin && git -C $DEPLOY checkout --detach origin/main` and `nixbot-logs queue` printing `Queue is empty`:

```bash
clan machines update magnetite 2>&1 | tee logs/magnetite-$(date +%Y%m%d-%H%M%S).log
ssh magnetite.zt 'bash -c "systemctl is-active fleet-alert.timer opentelemetry-collector"'
```

Expected: the log ends without error; `active` twice.

- [ ] **Step 6: The evaluator's first run (tasks.md 6.6)**

rehearse: magnetite:

```bash
L=logs/s4-evidence/6.6-first-run-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -c "systemctl show fleet-alert -p ExecMainStatus -p ExecMainStartTimestamp -p ExecMainExitTimestamp; sudo journalctl -u fleet-alert -o cat -n 60"' | tee "$L"
nix eval --raw .#nixosConfigurations.magnetite.config.services.fleet-alert.evaluator.rulesJson 2>/dev/null \
  | jq '[.[] | select(.expr and (.window // null) == null and (.alert | test("^Host(MemoryPressure|OOMKill)$") | not)) ] | length' | tee -a "$L"
```

If the evaluator module exposes the rendered JSON under another option, read it there (the module's `rendered.json`, `modules/nixos/fleet-alert.nix:573-576`), and count unique presence selectors plus expressions outside the weekly window the same way.
Expected: `ExecMainStatus=0`; the journal shows `fleet` and `devloop` queried as `regulator`; the count gives 23 queries in a run with no memory rule firing (22 PromQL, one SQL), and the time between start and exit is recorded beside S3's 0.62–0.68 s for 19 queries.

- [ ] **Step 7: Thirty minutes without a missing signal, and the hand-run control (tasks.md 6.7)**

Thirty minutes after Step 5, rehearse: magnetite:

```bash
L=logs/s4-evidence/6.7-signals-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
ssh magnetite.zt 'bash -c "sudo journalctl -u fleet-alert -o cat --since \"-35min\" | grep -c RuleSignalMissing"' | tee "$L"
```

Expected: `0`.
The negative control: run the deployed evaluator once by hand, as S3's acceptance did, with scratch state, topic `fleet-acceptance`, one selector misspelt (`system_filesystem_usage_byte`) and its `for` at 0, by copying the deployed rules JSON, editing that one rule with `jq`, and starting the evaluator's `ExecStart` under `systemd-run --pty -p DynamicUser=yes -p StateDirectory=fleet-alert-acceptance -p LoadCredential=regulator-password:<path> -p LoadCredential=alerter-token:<path>` with the evaluator's environment pointing at the copied file and the topic.
Expected: the hand run posts one `[FIRING] RuleSignalMissing` naming `FilesystemFillingWarn` to `fleet-acceptance`, and the operator records it beside the `0` above.
