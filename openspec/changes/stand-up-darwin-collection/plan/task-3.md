### Task 3: The notifier wrapper, the darwin envelope and the alert plumbing

Implements `tasks.md` 3.1–3.8 (design D6, D8, D9's expected hosts by platform, D10; O2, O3, O5, O8; TSI `Failure notices are posted to one topic`, `A failure episode ends at the unit's next successful start or exit`, `The telemetry store and the collector run inside a declared envelope`; HMC `A failed collection or store job notifies a person`; FII `otel-envelope regulates each agent from its own collector`; FAI `Store errors and silent hosts freeze instance state`, `Each rule's presence selector is watched`; FA `An unreachable telemetry store or a silent host freezes alerts`).
This is the second part of pull request 1, on top of Task 2's commits, and like them built after Task 1 Step 4's gate; Step 8 opens the pull request.
Every regulator comes first: the wrapper's cases fail before the wrapper exists (Step 1), the darwin envelope cases before C5 exists (Step 3), `pendingAcrossFreeze` on today's `transition.jq` (Step 5), and `linuxSelectorDarwinOnly` on today's rules (Step 7).
The darwin rules themselves, `org.nixos.otel-envelope` on the launchd allow-list and stibnite among the NVMe rules' expected hosts are Task 6's; nothing here deploys or activates.

**Files:**
- Create: `modules/lib/observability-notify-run.nix` (`flake.lib.observabilityNotifyRun`, and `flake.lib.observabilityNotifyScripts` moved here)
- Modify: `modules/nixos/observability-notify.nix` (ON): the scripts (`:21-85`) leave for the new file; the template (`:87-215`) calls `flake.lib.observabilityNotifyScripts` with unchanged arguments
- Modify: `modules/lib/otel-envelope.nix` (OE): the header (`:1-84`), the `flake.lib.otelEnvelope` arguments (`:292-301`), C5 after C4 (`:453`)
- Modify: `modules/checks/otel-envelope.nix`: `variantsWith` (`:76-100`), `mutants` (`:117-166`), `cases` (`:212-454`), `caseNames` (`:456-478`); create `modules/checks/otel-envelope/fixtures/darwin-*.prom`
- Modify: `modules/checks/otel-collector-darwin.nix`: the wrapper's cases and `postEveryFailure`
- Modify: `modules/darwin/otel-collector-agent.nix`: `launchd.daemons.otel-envelope`, and `otel-envelope` in the calendar assertion's labels
- Modify: `modules/checks/fleet-alert.nix`: the legs (`:1023-1500`), `twoHostRules`' table (`:973-986`), `fixtureRehearsal` (`:1750-1811`)
- Modify: `modules/nixos/fleet-alert/transition.jq:18-20`, `:174-182`; `modules/checks/fleet-alert/model.py:217-230`
- Modify: `modules/nixos/fleet-alert/rules.nix:21-27`, `:48-52`, `:102-191`
- Create (git-ignored): `logs/s5-evidence/3.<n>-*.log`, and the scratch tree `$SCRATCH`

**Interfaces:**
- Consumes: Task 2's renderer (`flake.lib.otelCollectorDarwin`'s `targets` and `exporters`), fragment, `vanixiets.otelCollector.darwin.*`, `logs/s5-evidence/2.6-overrides.nix` and the check `otel-collector-darwin`; Task 1's baselines, among them promtool's rule count; ON's posting and episode code (`modules/nixos/observability-notify.nix:33-81`) and its rehearsal in `modules/checks/otel-collector-config.nix:86-195`, which calls `flake.lib.observabilityNotifyScripts` with `{ ntfySend; stampDir; hostName; }`; `pkgs/by-name/ntfy-send/package.nix:26-29`, which posts with `/usr/bin/curl` on darwin and reads `NTFY_TOKEN_FILE`; OE's state handling, which already reads `STATE_DIRECTORY` from the environment (`modules/lib/otel-envelope.nix:329`); the fleet-alert check's leg machinery (`stepAnswers` `:842-888`, `checkConfig` `:705`, `tableWith` `:1185-1194`, `runLeg`).
- Produces: `flake.lib.observabilityNotifyRun pkgs { label; host; topic ? "fleet-alerts"; tokenFile; stateDir; logFile; minIntervalSec ? 900; }` and `flake.lib.observabilityNotifyScripts pkgs { ntfySend; stampDir; hostName; topic ? "fleet-alerts"; logFile ? "${stampDir}/failed.log"; }`; `flake.lib.otelEnvelope`'s `darwinMemory ? null` and clause `C5 memory`; `launchd.daemons.otel-envelope`; the fixture legs `pendingAcrossFreeze`, `pendingAfterWake`, `linuxSelectorDarwinOnly`, `stibniteNotCollecting` and the stand-in rule list `probeStaleRules` that Task 6 replaces by the real table once `HostProbeStale` exists; `flake.lib.fleetAlertRules`' `nixosHosts`, `darwinHosts` and `smartHosts`, with the NVMe rules' expected hosts `lib.subtractLists darwinHosts smartHosts` until Task 6 makes them `smartHosts`.

- [ ] **Step 1: The wrapper's cases, seen failing (tasks.md 3.1)**

The value sources of the wrapper's cases: the recording stub's log of `ntfy-send` calls against the notice texts typed in the check from TSI `Failure notices are posted to one topic` (`FAILED <label> on <host>`, `RESOLVED <label> on <host>`, topic `fleet-alerts`); the token's file path the check passes against the stub's recorded `NTFY_TOKEN_FILE` and argv.
In `modules/checks/otel-collector-darwin.nix`, build the wrapper over a recording `ntfy-send`, injected by overlay so the contract's arguments stay as they are:

```nix
      ntfyStub = pkgs.writeShellScriptBin "ntfy-send" ''
        # One line per post: the title, the topic, NTFY_TOKEN_FILE, and the argv.
        printf '%s|%s|%s|%s\n' "$1" "$2" "''${NTFY_TOKEN_FILE:-}" "$*" >> "$NTFY_STUB_LOG"
      '';
      notifyPkgs = pkgs.extend (_: _: { ntfy-send = ntfyStub; });
      tokenFile = pkgs.writeText "alerter-token" "tk_fixture00000000000000000000000";
      wrapper = self.lib.observabilityNotifyRun notifyPkgs {
        label = "otel-envelope";
        host = "stibnite";
        inherit tokenFile;
        # Expanded when the wrapper runs, so each case has its own directory.
        stateDir = "$NOTIFY_STATE";
        logFile = "$NOTIFY_STATE/notify.log";
      };
```

and the cases, each in a fresh `NOTIFY_STATE` and `NTFY_STUB_LOG`, running `observability-notify-run -- true`, `-- false` or `-- sh -c 'exit 3'` in sequence:

| Case | Runs | Passes when |
|---|---|---|
| `passFailFailPass` | true, false, false, true | the stub log's titles are exactly `FAILED otel-envelope on stibnite` then `RESOLVED otel-envelope on stibnite`, both on topic `fleet-alerts`; `notify.log` holds one line `<epoch> otel-envelope stibnite` |
| `secondEpisodeInsideInterval` | false, true, false, true, all within 900 s | the titles are exactly `FAILED …` then `RESOLVED …`: the second episode is suppressed |
| `firstRunFails` | false | the titles are exactly `FAILED otel-envelope on stibnite` |
| `tokenAsFile` | false | every stub line's third field equals `tokenFile`, and no line's fourth field contains `tk_fixture` |
| `exitCodeKept` | `sh -c 'exit 3'`, then true | the wrapper exits 3, then 0 |

The mutant `postEveryFailure` replaces, in a copy of `modules/lib/observability-notify-run.nix` imported as the flake-parts module it is (as `modules/checks/otel-envelope.nix:190-207` does for OE), the text `if [ -e "$stamp" ]; then`, which must occur exactly once, by `if false; then`, and runs only `passFailFailPass`.
No `# mutant:` marker is put in the scripts' text, because the NixOS notifier's scripts must keep their store paths (Step 2).
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-collector-darwin 2>&1 | tee logs/s5-evidence/3.1-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -n 3
```

Expected: FAIL at evaluation, `attribute 'observabilityNotifyRun' missing` (RED).

- [ ] **Step 2: The platform-neutral notifier (tasks.md 3.2)**

Record first, in `$DEPLOY` at `origin/main`, the NixOS notifier as deployed, so the move is shown to leave it unchanged:

```bash
L=$REPO/logs/s5-evidence/3.2-notifier-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
q='c: { failed = c.systemd.services."observability-notify@".serviceConfig.ExecStart; start = c.systemd.services.otel-envelope.serviceConfig.ExecStartPost; stop = c.systemd.services.otel-envelope.serviceConfig.ExecStopPost; }'
for h in magnetite cinnabar electrum; do printf '%s %s\n' "$h" "$(cd $DEPLOY && nix eval --json ".#nixosConfigurations.$h.config" --apply "$q" | sha256sum | cut -d' ' -f1)"; done | tee "$L"
```

Create `modules/lib/observability-notify-run.nix`, moving `observabilityNotifyScripts` (ON `:22-82`) into it verbatim except that the topic and the failure log become arguments whose defaults render today's text, `${ntfySend} "FAILED $unit on ${hostName}" ${topic}` and `log="${logFile}"`:

```nix
# The failure notifier's posting and episode code, shared by systemd and
# launchd (ADR-009 item 11; S3 design D3, D4, D9; design D6).
#
# flake.lib.observabilityNotifyScripts pkgs { ntfySend; stampDir; hostName;
# topic ? "fleet-alerts"; logFile ? "<stampDir>/failed.log"; } returns the
# `failed` and `resolved` scripts that observability-notify@.service and its
# hooks run on NixOS; with the defaults their text, and so their store paths,
# are what modules/nixos/observability-notify.nix rendered before the move.
#
# flake.lib.observabilityNotifyRun pkgs { label; host; topic ? "fleet-alerts";
# tokenFile; stateDir; logFile; minIntervalSec ? 900; } is the launchd
# counterpart of OnFailure plus the RESOLVED hooks, which launchd lacks:
# `observability-notify-run -- <command…>` runs the command, then `resolved
# start <label>` if it exited 0 and `failed <label>` otherwise, and exits with
# the command's code, so launchd records it. One episode per label: FAILED
# when a run fails after a pass or a first run fails, RESOLVED when a run
# passes after a posted FAILED, nothing for a new episode within
# minIntervalSec of the last FAILED. ntfy-send reads the token through
# NTFY_TOKEN_FILE, set only for its calls. checks.x86_64-linux.otel-collector-darwin
# runs it over a recording ntfy-send.
{ lib, ... }:
let
  observabilityNotifyScripts =
    pkgs:
    {
      ntfySend,
      stampDir,
      hostName,
      topic ? "fleet-alerts",
      logFile ? "${stampDir}/failed.log",
    }:
    {
      failed = pkgs.writeShellScript "observability-notify-failed" ''/* ON:43-63, with ${topic} and ${logFile} */'';
      resolved = pkgs.writeShellScript "observability-notify-resolved" ''/* ON:70-80, with ${topic} */'';
    };
in
{
  flake.lib = {
    inherit observabilityNotifyScripts;
    observabilityNotifyRun =
      pkgs:
      {
        label,
        host,
        topic ? "fleet-alerts",
        tokenFile,
        stateDir,
        logFile,
        minIntervalSec ? 900,
      }:
      let
        scripts = observabilityNotifyScripts pkgs {
          ntfySend = lib.getExe pkgs.ntfy-send;
          stampDir = stateDir;
          hostName = host;
          inherit topic logFile;
        };
        token = "NTFY_TOKEN_FILE=${lib.escapeShellArg tokenFile}";
      in
      pkgs.writeShellApplication {
        name = "observability-notify-run";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          [ "''${1:-}" = -- ] && shift
          export OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC=${toString minIntervalSec}
          mkdir -p "${stateDir}"
          rc=0
          "$@" || rc=$?
          if [ "$rc" = 0 ]; then
            env ${token} ${scripts.resolved} start ${lib.escapeShellArg label}
          else
            env ${token} ${scripts.failed} ${lib.escapeShellArg label} \
              || echo "observability-notify-run: posting FAILED ${label} on ${host} failed; the next failing run posts again" >&2
          fi
          exit "$rc"
        '';
      };
  };
}
```

In ON, delete the scripts' `let` and `flake.lib = { inherit observabilityNotifyScripts; };`, take `config` in the file's arguments, and set `notifyScripts = config.flake.lib.observabilityNotifyScripts pkgs { … }` with the three arguments it passes today (`:96-100`); update the header to say the scripts live in `modules/lib/observability-notify-run.nix`.
`modules/checks/otel-collector-config.nix:88-103` keeps calling `self.lib.observabilityNotifyScripts` unchanged.
Run:

```bash
jj st --no-pager >/dev/null
for h in magnetite cinnabar electrum; do printf '%s %s\n' "$h" "$(nix eval --json ".#nixosConfigurations.$h.config" --apply "$q" | sha256sum | cut -d' ' -f1)"; done | diff - <(head -n 3 "$L") && echo "nixos notifier unchanged" | tee -a "$L"
nix build .#checks.x86_64-linux.otel-collector-darwin -L 2>&1 | tee -a "$L" | grep -E '^(ok|mutant|FAIL)'
nix build .#checks.x86_64-linux.otel-envelope .#checks.x86_64-linux.otel-collector-config 2>&1 | tail -n 2 | tee -a "$L"
```

Expected: `nixos notifier unchanged` (the hook and template store paths, so the notices, are what `origin/main` deploys); the five wrapper cases `ok:` and `mutant postEveryFailure rejected: passFailFailPass`; both other checks pass unchanged (evaluation, build).
Then, from stibnite, `fleet-ingress` from the commit that will be the pull request's head, which routes to magnetite, the only builder advertising `uid-range` (`modules/README.md:65-74`):

```bash
nix build .#vmTests.x86_64-linux.fleet-ingress -L 2>&1 | tee logs/s5-evidence/3.2-fleet-ingress-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E '^=== case|^ok: |FAIL|error:'
```

Expected: every `=== case` line with its `ok:`, among them `absentClientCa`, whose one `FAILED` and one `RESOLVED` reach the recording `ntfy-send` through the moved code, and `lossControls` (container); the commit, the host, the date and the passing cases are recorded for Step 8's description.
Commit, for example "Share the failure notifier's posting code between systemd and launchd".

- [ ] **Step 3: C5 and the darwin envelope cases, seen failing first (tasks.md 3.3)**

Measure `otel-envelope`'s cost first, against Task 1's figure.
The value sources of C5's cases: the resident sizes the `ps` stub reports for the pids the `launchctl` stub prints, against the limits O5 set, 268,435,456 B and 134,217,728 B, typed in the case table, where the fragment passes them as `darwinMemory.limits` (Step 4).
Write the fixtures `modules/checks/otel-envelope/fixtures/darwin-healthy.prom` (the agent's two exporters' `otelcol_exporter_queue_size` and `_capacity` as in `agent-healthy.prom`, plus `otelcol_receiver_refused_metric_points{receiver="otlp",transport="http"} 0` for `otelcol-process`'s loopback receiver) and `darwin-otlp-refused.prom` (that counter at 7), and in `modules/checks/otel-envelope.nix` add the variant, its stubs and the cases:

```nix
      # stibnite's envelope: the darwin renderer's job names on the stub's
      # ports, its exporters, and C5 over stubbed launchctl and ps.
      darwinTargets = map (t: t // { url = "http://127.0.0.1:${toString targetPort}/ok"; })
        (self.lib.otelCollectorDarwin { hostName = "stibnite"; certFile = "c"; keyFile = "k"; caFile = "a"; }).targets;
      launchctlStub = pkgs.writeShellScript "launchctl-stub" ''
        # `print system/<label>`: pid 101 for the agent and 202 for the process
        # collector, unless C5_UNLOADED names the label.
        label=''${2#system/}
        [ "$label" = "''${C5_UNLOADED:-}" ] && { echo "Could not find service \"$label\" in domain for system"; exit 113; }
        case $label in org.nixos.otelcol) pid=101 ;; org.nixos.otelcol-process) pid=202 ;; *) exit 113 ;; esac
        printf '%s = {\n\tstate = running\n\tpid = %s\n}\n' "system/$label" "$pid"
      '';
      psStub = pkgs.writeShellScript "ps-stub" ''
        # `-o rss= -p <pid>`: C5_RSS_<pid> KiB.
        v=C5_RSS_$4; echo "  ''${!v:-0}"
      '';
```

with `darwin = envelope { hostName = "stibnite"; targets = darwinTargets; darwinMemory = { launchctl = "${launchctlStub}"; ps = "${psStub}"; limits = { "org.nixos.otelcol" = 268435456; "org.nixos.otelcol-process" = 134217728; }; }; };` in `variantsWith`, its exporters the default agent pair, and:

| Case | Environment | Runs: fixture → expected exit |
|---|---|---|
| `darwinHealthy` | `C5_RSS_101=102400 C5_RSS_202=65536` | darwin-healthy → 0, darwin-healthy → 0, every clause `ok`, `C5 memory: ok` |
| `darwinOtlpRefused` | as `darwinHealthy` | darwin-healthy → 0, darwin-otlp-refused → 1, `C4 loss: FAIL` naming `receiver="otlp"` |
| `c5AgentAt255` | `C5_RSS_101=261120` | darwin-healthy → 0 |
| `c5AgentAt257` | `C5_RSS_101=263168` | darwin-healthy → 1, `C5 memory: FAIL org.nixos.otelcol 257 MiB` |
| `c5ProcessAt129` | `C5_RSS_101=102400 C5_RSS_202=132096` | darwin-healthy → 1, `C5 memory: FAIL org.nixos.otelcol-process 129 MiB` |
| `c5NotLoaded` | `C5_UNLOADED=org.nixos.otelcol-process` | darwin-healthy → 0, `C5 memory: ok`: a job without a pid is `LaunchdJobNotRunning`'s, and the agent's absence is C1's |

and the mutant `c5WrongPid`, which reads every label's pid from the agent's `launchctl print` and runs only `c5ProcessAt129`.
The cases add the target stub as the existing agent cases do (`run darwin "$s" darwin-healthy up 0`), with the environment exported before `run`.
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.otel-envelope 2>&1 | tee logs/s5-evidence/3.3-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | tail -n 3
```

Expected: FAIL at evaluation, `function 'anonymous lambda' called with unexpected argument 'darwinMemory'` (RED).
Then extend OE: the arguments gain `darwinMemory ? null`; the header gains C5's paragraph and says `STATE_DIRECTORY` is read from the environment, which systemd's `StateDirectory` sets on NixOS and the launchd plist's `EnvironmentVariables` on darwin (the script has required it since S4, `:329`, so no code changes for it); after C4 (`:453`):

```nix
        ${lib.optionalString (darwinMemory != null) ''
          # C5 (darwin; design D6, O5): launchd bounds no memory, so each
          # collector's resident size is read from its pid in `launchctl print`
          # and compared with its limit. A job with no pid is not judged here.
          over=""
          while read -r label limit; do
            [ -n "$label" ] || continue
            out=$(${darwinMemory.launchctl} print "system/$label" 2> /dev/null || true)
            # mutant: c5WrongPid
            pid=$(awk -F' = ' '$1 == "\tpid" { print $2; exit }' <<< "$out")
            [ -n "$pid" ] || continue
            rss=$(${darwinMemory.ps} -o rss= -p "$pid" | tr -d ' ') || continue
            if [ $((rss * 1024)) -gt "$limit" ]; then over="$over $label $((rss / 1024)) MiB"; fi
          done <<< ${lib.escapeShellArg (lib.concatStrings (lib.mapAttrsToList (l: b: "${l} ${toString b}\n") darwinMemory.limits))}
          if [ -n "$over" ]; then fail "C5 memory" "''${over# } above its limit"; else ok "C5 memory"; fi
        ''}
```

The mutant's `to` is `pid=$(awk -F' = ' '$1 == "\tpid" { print $2; exit }' <<< "$(${darwinMemory.launchctl} print system/org.nixos.otelcol 2> /dev/null)")`.
`/bin/launchctl` and `/bin/ps` are darwin system binaries, called by the absolute paths the fragment passes, not from `runtimeInputs` (plan Global Constraints).
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/3.3-envelope-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.otel-envelope -L 2>&1 | tee "$L" | grep -E '^(ok|mutant|FAIL)'
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-envelope-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-envelope.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/otel-envelope-stats.json | tee -a "$L"
(cd $DEPLOY && nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.otel-envelope.serviceConfig.ExecStart) | diff - <(nix eval --raw .#nixosConfigurations.magnetite.config.systemd.services.otel-envelope.serviceConfig.ExecStart) && echo "nixos envelope unchanged" | tee -a "$L"
```

Expected: every existing case and the six darwin cases `ok:`, every existing mutant and `mutant c5WrongPid rejected: c5ProcessAt129`, no `FAIL`; the cost under 0.17 GiB (design D13) and below 536,870,912; `nixos envelope unchanged`, because C5's text renders only with `darwinMemory` (build, evaluation).
Commit, for example "Bound the darwin collectors' resident memory in the delivery envelope".

- [ ] **Step 4: The envelope on stibnite (tasks.md 3.4)**

In `modules/darwin/otel-collector-agent.nix`, add `"otel-envelope"` to `own`, so the calendar assertion covers it, and to `launchd.daemons`:

```nix
          # R3.2 on stibnite (design D6): every 300 s, which skips sleep and
          # needs no zone (design D8), under the wrapper that posts its own
          # FAILED and RESOLVED to fleet-alerts, because a broken export path
          # would also stop a notice sent through the store.
          otel-envelope = {
            command = lib.concatStringsSep " " [
              (lib.getExe (flakeLib.observabilityNotifyRun pkgs {
                label = "otel-envelope";
                host = config.networking.hostName;
                tokenFile = gens.ntfy-alerter.files.token.path;
                stateDir = "/var/lib/otel-envelope";
                logFile = "/var/lib/otel-envelope/notify.log";
              }))
              "--"
              (lib.getExe (flakeLib.otelEnvelope pkgs {
                hostName = config.networking.hostName;
                inherit (rendered) targets exporters;
                darwinMemory = {
                  launchctl = "/bin/launchctl";
                  ps = "/bin/ps";
                  # The NixOS MemoryMax analogues (FM:619; O5).
                  limits = { "org.nixos.otelcol" = 268435456; "org.nixos.otelcol-process" = 134217728; };
                };
              }))
            ];
            environment.STATE_DIRECTORY = "/var/lib/otel-envelope";
            serviceConfig = {
              UserName = "_otelcol"; GroupName = "_otelcol";
              StartInterval = 300;
              StandardOutPath = "/var/log/otelcol/otel-envelope.log"; StandardErrorPath = "/var/log/otelcol/otel-envelope.log";
            };
          };
```

The token reaches `ntfy-send` only as the file path the wrapper sets in `NTFY_TOKEN_FILE` for its calls; the plist carries no token value and no token path in its environment.
Add `envelopeCalendar` to `logs/s5-evidence/2.6-overrides.nix` (`launchd.daemons.otel-envelope.serviceConfig.StartCalendarInterval = [ { Minute = 0; } ]`, design D8's own negative control).
In the scratch tree (Task 2 Step 1's form, stibnite's `collect = false` removed):

```bash
jj st --no-pager >/dev/null
git -C $REPO worktree add --detach $SCRATCH "$(jj log --no-pager --no-graph -r @ -T commit_id)"
# in $SCRATCH, remove stibnite's `collect = false;`
L=$REPO/logs/s5-evidence/3.4-envelope-daemon-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
cd $SCRATCH
nix eval --json .#darwinConfigurations.stibnite.config.launchd.daemons.otel-envelope.serviceConfig --apply 's: { inherit (s) StartInterval StartCalendarInterval UserName EnvironmentVariables; args = s.ProgramArguments; }' | tee "$L"
nix eval --impure --raw --expr "(import $REPO/logs/s5-evidence/2.6-overrides.nix (builtins.getFlake (toString ./.))).envelopeCalendar" 2>&1 | grep -o 'otel-collector darwin agent[^(]*' | head -n 1 | tee -a "$L"
nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath | tee -a "$L"; echo
cd $REPO && git worktree remove --force $SCRATCH
```

Expected: `StartInterval` 300, `StartCalendarInterval` null, `UserName` `"_otelcol"`, `EnvironmentVariables` `{"STATE_DIRECTORY":"/var/lib/otel-envelope"}`, `args` `/bin/sh -c "/bin/wait4path /nix/store && exec …/observability-notify-run -- …/otel-envelope"`; the calendar assertion's message naming `otel-envelope` (negative control); a drvPath (evaluation).
Commit, for example "Check stibnite's collector delivery every five minutes and post its failures".

- [ ] **Step 5: The pending-time timelines, seen failing (tasks.md 3.5)**

The legs' value sources: the step-indexed post lists typed in each leg from FAI `Store errors and silent hosts freeze instance state`'s scenarios against the evaluator's posts over the fixture server.
`HostProbeStale` does not exist until Task 6, so the legs carry a stand-in with ADR-009:134's expression and `for`, appended to the real table, never to the evaluator's deployed rules:

```nix
      # FAI's freeze scenarios on a time-relative rule. HostProbeStale is
      # Task 6's; until then this stand-in has ADR-009:134's expression and
      # `for`, and Task 6 replaces probeStaleRules by the real table.
      probeStale = {
        alert = "HostProbeStale";
        expr = "time() - node_textfile_mtime_seconds > 300 or node_textfile_scrape_error == 1";
        for = 600;
        severity = "warning";
        annotations.summary = "stand-in for the darwin probe's staleness rule";
        presence = [ ];
        attribution = [ ];
        database = "fleet";
        language = "promql";
      };
      probeStaleRules = evaluatorRules ++ [ probeStale ];
      probeStaleConfig = checkConfig probeStaleRules;
      stale = [ { host_name = "stibnite"; file = "/var/lib/prometheus-node-exporter/textfile/launchd.prom"; } ];
      # stibnite reports from minute 0 to 5, its probe stale from its last
      # sample at 5; silent from 10 to 125 (24 runs 5 min apart), when the
      # store's lookback no longer answers its last sample; then reports from
      # 126 with the condition as `wake` gives it.
      freezeTimeline =
        wake:
        map (n: { at = minute n; reporting = [ "stibnite" ]; series = lib.optionalAttrs (n == 5) { HostProbeStale = stale; }; }) (lib.range 0 5)
        ++ map (n: { at = minute (10 + 5 * n); series = lib.optionalAttrs (n == 0) { HostProbeStale = stale; }; }) (lib.range 0 23)
        ++ map (n: { at = minute n; reporting = [ "stibnite" ]; series = lib.optionalAttrs (wake n) { HostProbeStale = stale; }; }) (lib.range 126 140);
      pendingAcrossFreeze = {
        name = "HostProbeStale true at stibnite's last sample, 2 h silent, then true for 2 runs after wake and false after posts nothing";
        rules = probeStaleRules;
        steps = freezeTimeline (n: n <= 127);
        expect = [ ];
      };
      pendingAfterWake = {
        name = "HostProbeStale true for 11 min after stibnite wakes fires once, 10 min after wake";
        rules = probeStaleRules;
        steps = freezeTimeline (n: n <= 137);
        # Step 40 is minute 136: 6 runs before the silence, 24 silent, then 126 + 10.
        expect = [ "40 [FIRING] HostProbeStale stibnite default" ];
      };
```

Add both to `fixtureRehearsal` with `config = probeStaleConfig`, as `twoHostExclusionLeg` is run (`:1782-1785`).
Run:

```bash
jj st --no-pager >/dev/null
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s5-evidence/3.5-red-$(/bin/date -u +%Y%m%dT%H%M%SZ).log | grep -E 'MISS|FAIL' | head -n 5
```

Expected: FAIL with `MISS` lines naming `pendingAcrossFreeze`, which posts `30 [FIRING] HostProbeStale stibnite default` at minute 126 because today's `transition.jq` counts the pending time from minute 5 across the freeze; `pendingAfterWake` misses too, firing at step 30 instead of 40 (RED).

- [ ] **Step 6: Pending time counts only while the host reports (tasks.md 3.6)**

In `modules/nixos/fleet-alert/transition.jq`, replace the unfrozen branch of the reduce (`:179-181`) with:

```jq
          else
            # A pending instance frozen on the previous run counts its `for`
            # from this run: the store answers a sleeping host's last sample
            # for its lookback, so a condition seen then never held while the
            # host was awake (design D10). Frozen runs leave absenceFrom null.
            ( if $inst != null and $inst.phase == "pending" and ($inst | has("absenceFrom")) and $inst.absenceFrom == null
              then $inst | .activeSince = $now else $inst end ) as $thawed
            | advance($thawed; $cond; $now) as $next
            | if $next == null then . else .[$id] = $next end
          end) ) as $instances
```

and extend the header (`:18-20`) with the sentence "A pending instance thawed on this run restarts its `for` at this run."
In `modules/checks/fleet-alert/model.py`, before `nxt = advance(instance, condition, now)` (`:228`):

```python
        # design D10: a pending instance frozen on the previous run restarts its `for`.
        if instance is not None and instance["phase"] == "pending" and "absenceFrom" in instance and instance["absenceFrom"] is None:
            instance = dict(instance, activeSince=now)
```

Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/3.6-transition-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee "$L" | grep -E 'pendingAcrossFreeze|pendingAfterWake|^ok: every leg|mutant noRepost|FAIL'
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/fleet-alert-stats.json | tee -a "$L"
```

Expected: both legs pass, `ok: every leg passed`, the property test comparing `transition.jq` with the model passes and `mutant noRepost rejected`, no `FAIL`; the existing freeze legs (`silentHostLeg`, `hostThawLeg`, `storeThawLeg`) still pass, because they concern firing instances; the cost recorded beside 1.2's and below 536,870,912 (build).
Commit, for example "Count a pending alert's time only while its host reports".

- [ ] **Step 7: Expected hosts by platform (tasks.md 3.7)**

The legs' value sources: the Linux-only selectors typed in the check from design "Requirement applicability" (`system_linux_memory_available_bytes`, `system_paging_usage_bytes`, `node_zfs_arc_size`, `node_zfs_zpool_state`, `node_vmstat_oom_kill`, `systemd_unit_state`, `systemd_service_restarts_total`) against the presence selectors and expected hosts the rules render from HT.
First the legs, from a table where stibnite collects and the two always-on hosts are not marked always-on, so their silence, which the legs need to leave stibnite the only reporting host, raises nothing of its own:

```nix
      linuxSelectors = [ "system_linux_memory_available_bytes" "system_paging_usage_bytes" "node_zfs_arc_size" "node_zfs_zpool_state" "node_vmstat_oom_kill" "systemd_unit_state" "systemd_service_restarts_total" ];
      onlyStibniteTable = stibnite: hosts // {
        stibnite = hosts.stibnite // stibnite;
        magnetite = hosts.magnetite // { alwaysOn = false; };
        cinnabar = hosts.cinnabar // { alwaysOn = false; };
      };
      onlyStibniteRules = stibnite: builtins.fromJSON (self.lib.fleetAlertRules { inherit lib; hosts = onlyStibniteTable stibnite; }).json;
      stibniteOnlySteps = missing: map (n: { at = gap n; reporting = [ "stibnite" ]; silent = alwaysOnHosts; inherit missing; }) (lib.range 0 7);
      linuxSelectorDarwinOnly = {
        name = "stibnite, the only host reporting, with every Linux-only selector absent for 35 min, raises nothing";
        rules = onlyStibniteRules { collect = true; };
        steps = stibniteOnlySteps linuxSelectors;
        expect = [ ];
      };
      stibniteNotCollecting = {
        name = "stibnite, not collecting and the only host reporting, with every selector but host memory absent for 35 min, raises nothing";
        rules = onlyStibniteRules { };
        steps = stibniteOnlySteps (lib.remove "system_memory_usage_bytes" selectors);
        expect = [ ];
      };
```

run in `fixtureRehearsal`, each with `checkConfig` of its own rules; add `platform = "nixos";` to `twoHostRules`' rows `a` and `b` (`:974-985`), which the rules read from Step 7 on.
Run `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s5-evidence/3.7-red-<ts>.log | grep -E 'MISS|FAIL' | head -n 5`.
Expected: `linuxSelectorDarwinOnly` misses, posting one `[FIRING] RuleSignalMissing` at step 6 for each rule with a Linux-only presence selector, because today every collecting host, stibnite included, is expected for every rule; `stibniteNotCollecting` passes, guarding the `collect` filter that Step 7 keeps (RED).
Then in `modules/nixos/fleet-alert/rules.nix` replace `:48-52`:

```nix
      # A host is expected, or always-on, only once it collects (S4 design D6,
      # D9), and only for the selectors its platform writes (design D9):
      # darwin writes no available memory, paging, ZFS, OOM or systemd series.
      collecting = lib.filterAttrs (_: h: h.collect) hosts;
      onPlatform = p: builtins.attrNames (lib.filterAttrs (_: h: h.platform == p) collecting);
      agentHosts = builtins.attrNames collecting;
      nixosHosts = onPlatform "nixos";
      darwinHosts = onPlatform "darwin";
      smartHosts = builtins.attrNames (lib.filterAttrs (_: h: h.smartDevices != [ ]) collecting);
      # Until the darwin rules land, the NVMe rules keep their NixOS hosts.
      nvmeHosts = lib.subtractLists darwinHosts smartHosts;
      presence = expectedHosts: selector: { inherit selector expectedHosts; };
```

and set `presence nixosHosts` for `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop` and `SystemdUnitFailed`, `presence nvmeHosts` for the two NVMe rules, and keep `presence agentHosts` for `FilesystemFillingWarn`, `FilesystemFull`, `LocalExporterDown` and `WeeklyPipelineTest`; rewrite the header's `:21-27` to state the three host sets and which rules each expects (design D9's table).
Run:

```bash
jj st --no-pager >/dev/null
L=logs/s5-evidence/3.7-platform-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee "$L" | grep -E 'linuxSelectorDarwinOnly|stibniteNotCollecting|^ok: every leg|FAIL'
nix log "$(nix eval --raw .#checks.x86_64-linux.fleet-alert.promtoolRehearsal.drvPath)" | grep -E 'SUCCESS: [0-9]+ rules found' | tee -a "$L"
# The check's passthru `rules` is the table rendered from flake.lib.observabilityHosts (modules/checks/fleet-alert.nix:72, :1866-1867).
nix eval --json .#checks.x86_64-linux.fleet-alert.rules --apply 'r: map (x: { inherit (x) alert; hosts = map (p: p.expectedHosts) x.presence; }) r.rules' | tee -a "$L"
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.fleet-alert.drvPath >/dev/null && jq '.gc.totalBytes, .cpuTime' /tmp/fleet-alert-stats.json | tee -a "$L"
```

Expected: both legs and every other leg pass; promtool's `SUCCESS: <n> rules found` with the same `<n>` as Task 1 Step 2; every rule's expected hosts the six NixOS hosts, stibnite in none while its `collect` is false; the cost recorded, below 536,870,912 and within design D13's 0.32 to 0.35 GiB (evaluation, build).
Commit, for example "Expect each alert's signals only from the hosts whose platform writes them".

- [ ] **Step 8: Format, cost and pull request 1 (tasks.md 3.8)**

Run `nix fmt 2>&1 | tee logs/s5-evidence/3.8-fmt-$(/bin/date -u +%Y%m%dT%H%M%SZ).log` and `nix fmt -- --fail-on-change`; re-measure `otel-collector-darwin`, `otel-envelope`, `fleet-alert`, `otel-collector-config`, `nixos-magnetite` and `darwin-stibnite` with the method of plan Global Constraints and record them beside Task 1's in `logs/s5-evidence/3.8-cost-<ts>.log`.
Push the commits of Tasks 2 and 3 as one branch off `main@origin` per the repository's jj workflow and open pull request 1, titled in plain words, for example "Collect stibnite's host metrics on darwin over the mutually authenticated ingress".
Its body describes the change in words: stibnite's row, added with collection off so that magnetite's deploy and stibnite's next activation install only its account and secret files; the darwin role, renderers, probe, wrapper and envelope; the pending-time and expected-host changes in the evaluator; and the `fleet-ingress` run of Step 2, stated as the commit, the host it ran on, the date and the cases that passed, not as a log path; it links CAM-72 and carries no slice, decision, finding, requirement or task code and no pull-request ordinal.
Expected: `nix fmt -- --fail-on-change` exits 0; nixbot green on the gating checks `otel-collector-darwin`, `otel-envelope`, `fleet-alert`, `otel-collector-config` and `nixos-magnetite`; `darwin-stibnite`'s best-effort result recorded as nixbot reports it (`modules/checks/nixbot-best-effort-darwin.nix:28-29`); each cost below 536,870,912 (command).
