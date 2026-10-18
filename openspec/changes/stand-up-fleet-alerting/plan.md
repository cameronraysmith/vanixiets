# Fleet alerting (S3) implementation plan

> **For agentic workers:** REQUIRED SUB-SKILL: Use superpowers:subagent-driven-development (recommended) or superpowers:executing-plans to implement this plan task-by-task. Steps use checkbox (`- [ ]`) syntax for tracking.

**Goal:** Evaluate the failure classes S1's series cover on magnetite every 60 s and deliver one `FIRING` and at most one `RESOLVED` per instance to `fleet-alerts`, raise `AlertEvaluatorSilent` from cinnabar when the evaluator goes silent, and restrict publishing on `fleet-*` to the `alerter` credential, cut over in three deploys with no refused post.

**Architecture:** A first-party NixOS module `flake.modules.nixos.fleet-alert` runs `fleet-alert.service`, a timer-driven `DynamicUser` oneshot over curl and jq, which queries the store's PromQL API as `regulator`, applies a pure jq transition function to `/var/lib/fleet-alert/state.json`, and posts through `ntfy-send` with the `alerter` token read from `NTFY_TOKEN_FILE`; the same module runs `fleet-deadman.service` on cinnabar.
The failure notifier moves out of the collector's `agent` role into `flake.modules.nixos.observability-notify`, gains the token and a `FAILED` log, and is imported on cinnabar for the dead-man.
A shared clan vars generator `ntfy-alerter` holds the token, a per-machine generator `ntfy-alerter-env` on cinnabar derives ntfy's declarative provisioning from it, and evaluation-time checks (a fixture server with mutants, a Hypothesis property test, provisioning and token-transport checks) regulate it before deploy.

**Tech Stack:** nix flakes with flake-parts and import-tree; clan-core vars with sops (`share = true`); NixOS `services.ntfy-sh` (ntfy 2.28.0); `writeShellApplication` over curl and jq 1.8.2; `promtool` from `prometheus.cli` 3.15.0; Python 3.14.7 with `hypothesis` 6.156.1; all at the root pin `nixpkgs_10` (`nix eval` of `inputs.nixpkgs.legacyPackages.x86_64-linux`, 2026-10-18).

**Spec:** `openspec/changes/stand-up-fleet-alerting/` — `design.md` (D1–D19), `specs/`, `tasks.md`; `logs/s3/decisions.md` (D1–D11 as accepted); `logs/s3/series-labels.md` (live expressions and latencies); the decision records under `docs/notes/development/observability/` (charter v17; ADR-009 and `components/fleet-alert.md` as amended).

## Global Constraints

- Repository: `/Users/crs58/projects/vanixiets`, jj-colocated; never relocate `@`; commit each plan task as one change off `main@origin` per the repository's jj workflow.
- After creating or renaming any file, run `jj st --no-pager >/dev/null` before any `nix` command reads the tree, so the snapshot includes it.
- Each plan task is one pull request, in the order of the task map; each lands through the merge queue before the next task's PR is enqueued.
- Before every commit run `nix fmt` and keep its log; a commit whose tree fails `nix fmt -- --fail-on-change` is not pushed.
- Evidence: long or output-heavy commands are captured as `<command> 2>&1 | tee logs/s3-evidence/<task>-$(date -u +%Y%m%dT%H%M%SZ).log`, with any filter after the `tee`.
- nix-managed outputs are verified by `nix eval`, `nix build`, or inspecting the delivered path after activation, never by reading source; each step says which.
- Every new check records `NIX_SHOW_STATS=1 nix eval --raw .#.checks.x86_64-linux.<check>.drvPath` against a budget of 0.5 GiB, always with the leading dot: `.#checks…` first probes `packages.x86_64-linux` and `legacyPackages.x86_64-linux`, adding about 114 MB that is not the check's (charter v19); every check clause relates independently defined values, and a property of one module's own settings is an assertion in that module.
- Every runtime clause has a negative control that is shown to fail.
- import-tree loads every `.nix` file under `modules/`, so each `.nix` file there is a flake-parts module; non-module inputs (`transition.jq`, Python, fixtures) use other extensions.
- Pinned versions: ntfy-sh 2.28.0, jq 1.8.2, prometheus 3.15.0 (`promtool`), Python 3.14.7, `python3Packages.hypothesis` 6.156.1; vendor source is read at `binwiederhier/ntfy@v2.28.0` before depending on an option.
- Store query: `http://127.0.0.1:4000/v1/prometheus/api/v1/query` with header `x-greptime-db-name: fleet`, user `regulator` passed as `user = "regulator:<pw>"` to `curl --config -`; one query in flight; `--max-time 10` per query; query phase ends at the first failure or at 30 s; no post starts after 40 s.
- Evaluator unit: `fleet-alert.service`, `Type = oneshot`, `DynamicUser = true`, `StateDirectory = "fleet-alert"`, `UMask = "0077"`, `OOMScoreAdjust = 0`, `MemoryMax = "64M"`, `TimeoutStartSec = "50s"`, `after = [ "greptimedb.service" "greptimedb-schema.service" "zerotierone.service" ]`, no `wants`; `fleet-alert.timer` `OnCalendar = "minutely"`, `AccuracySec = "1s"`.
- Dead-man unit: `fleet-deadman.service`, `DynamicUser = true`, `StateDirectory = "fleet-deadman"`, `after = [ "ntfy-sh.service" "caddy.service" "zerotierone.service" ]`, no `wants`; `fleet-deadman.timer` `OnCalendar = "*:0/5"`, `AccuracySec = "5s"`; probe anonymous `POST http://[::1]:2586/<heartbeat topic>` passes only on HTTP 403; poll `http://[::1]:2586/<heartbeat topic>/json?poll=1&since=10m`; the heartbeat topic is the evaluator host's `services.fleet-alert.evaluator.heartbeatTopic`, compared across hosts by the check.
- OOM order on magnetite: nixbot evaluator 900, store 500, collector 300, alert evaluator 0.
- Topics: alerts `fleet-alerts`, heartbeat `fleet-heartbeat` at `Priority: min`, acceptance runs `fleet-acceptance`; title `[FIRING|RESOLVED] <alert> <host>`; priority `high` for `critical`, `default` for `warning`, `low` for `info`.
- Semantics: Prometheus `for`; resolve after 5 min absent; `critical` re-posted every 24 h, `warning` never, `info` no `RESOLVED`; `StoreQueryFailing` after 3 min freezes every other instance; a host without `system_memory_usage_bytes` freezes its instances; `RuleSignalMissing` after 30 min while an expected host reports; R9.1 budget 10 `FIRING` per 24 h, 3 per laptop, one `AlertBudgetExceeded` per 24 h.
- S3 rules, expressions exactly as amended in `docs/notes/development/observability/decisions/ADR-009-alerting.md:102-119`: `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed` (dot written `[.]`, exclusion from `services.observability-notify.units`), `LocalExporterDown` (presence selector `up{job="node"}`), `WeeklyPipelineTest`; internal `StoreQueryFailing`, `RuleSignalMissing`, `AlertEvaluatorSilent`; expected host `magnetite` only.
- `WeeklyPipelineTest` window: Mondays 09:00 to 09:05 `America/New_York`, converted by the evaluator under `TZ`; magnetite's `time.timeZone` stays unset.
- ntfy on cinnabar: `behind-proxy = true`, `proxy-trusted-hosts = "::1"`, `visitor-prefix-bits-ipv6 = 128`, no exempt host; `log-level = "debug"` from C1 until the revert PR after 7.4; `auth-access = [ "alerter:fleet-*:rw" "*:fleet-*:ro" ]` from deploy 3 only, one entry per line in nixfmt form; `auth-default-access` unset.
- Token: `^tk_[-_A-Za-z0-9]{29}$`, mode `0400`, never on any argv; `ntfy-send` sends `Authorization: Bearer` read from `NTFY_TOKEN_FILE` via `-H @-`.
- Cutover, three deploys, each by `logs/s3-evidence/s3-deploy.sh <host> <C1|C2|C3>` (Task 7 Step 0), which runs `clan machines update <host>` from a fresh worktree of `origin/main` only when `nixbot-logs queue` prints `Queue is empty` and appends `<label>_START`/`<label>_END` to `logs/s3-evidence/window.env`: C1 cinnabar (provisioning, proxy settings, debug log level, no access entries), gated by `tasks.md` 7.1; C2 magnetite (evaluator, token-bearing notifier), gated by 7.2; C3 cinnabar (access entries, dead-man), gated by 7.3. Rollback runs in reverse order.
- Shared vars: `clan vars generate` runs in the working copy before the task's commit and its `vars/` changes are squashed into that task's change. A machine is added as a reader of an existing shared var with `CLAN_NO_COMMIT=1 clan vars fix <machine> --generator <generator>`, never `clan vars generate <machine> --generator <generator>`: on 2026-10-18 `generate magnetite --generator ntfy-alerter` regenerated the shared token and re-ran the dependent `ntfy-alerter-env` (`logs/s3-evidence/4.8-vars-magnetite-20261018T073644Z.log`), while `vars fix` added magnetite's age key (clan-core `sops.py:446-450`, `allow_member`) and re-encrypted only `vars/shared/ntfy-alerter/token/secret` with the value unchanged (`4.8-vars-fix-magnetite-20261018T073724Z.log`); `clan vars check <machine>` verifies.
- No credential value in any repository file; credentials are clan vars consumed by path through `LoadCredential`, `EnvironmentFile` or `NTFY_TOKEN_FILE`.
- Runtime tests stay out of `checks`; S3 adds no `vmTests` and needs no `kvm`; pyrite serves only as an always-on subscriber that captures `fleet-alerts` for 9.1's 24 h window (`fleet-alerts-capture.service`, `/var/lib/fleet-alerts-capture.jsonl`, curl `-k`, because pyrite does not trust caddy's internal CA).
- Review: one read-only subagent of the default `task` agent type on an Opus model reviews S3 as merged and deployed, in place of the paid codex review (roborev), writing `openspec/changes/stand-up-fleet-alerting/review.md`; applied findings become `tasks.md` §10.

## Interface contract

Every task uses exactly these names.

| Kind | Name | Defined in |
|---|---|---|
| Package | `ntfy-send` (`ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`); env `NTFY_TOKEN_FILE` (path; unset means anonymous), `NTFY_CURL_BIN` (set by `package.nix`) | Task 1 |
| Package test | `passthru.tests.token-transport`, exposed as `checks.<system>.package-ntfy-send-test-token-transport` through `modules/checks/package-tests.nix` | Task 1 |
| NixOS module | `flake.modules.nixos.observability-notify` at `modules/nixos/observability-notify.nix`, module `key = "vanixiets#observability-notify"`, so a host importing it directly and through the `agent` role loads it once; options `services.observability-notify.units` (`listOf str`, default `[ ]`, unit names without `.service`), `services.observability-notify.tokenFile` (`nullOr str`, default `null`) | Task 2 |
| Lib | `flake.lib.observabilityNotifyScripts pkgs { ntfySend; stampDir; hostName; }` returning `{ failed; resolved; }`, moved from the otel-collector flake module | Task 2 |
| Units and hooks | `observability-notify@.service` (`Type = "oneshot"`, `StateDirectory = "observability-notify"`, `ExecStart = "<failed> %i"`, `environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC = "900"`); with `tokenFile` set, also `serviceConfig.LoadCredential = [ "alerter-token:<tokenFile>" ]` and `environment.NTFY_TOKEN_FILE = "%d/alerter-token"`. Hooks on each listed unit: with `tokenFile = null`, `ExecStartPost = [ "-+<resolved> start %n" ]` and `ExecStopPost = [ "-+<resolved> stop %n" ]`; with `tokenFile` set, `"-+${pkgs.coreutils}/bin/env NTFY_TOKEN_FILE=<tokenFile> <resolved> start %n"` and the same with `stop`; R3.1's `resolvedHook` accepts the optional `env NTFY_TOKEN_FILE=<path> ` prefix | Task 2 |
| State | stamps `/var/lib/observability-notify/<unit>`; `last-failed/<unit>`; log `/var/lib/observability-notify/failed.log`, mode `0644`, one line `<epoch> <unit> <host>` appended after each successful `FAILED` post, `<unit>` the instance `%i` with its `.service` suffix (`1760800000 greptimedb.service magnetite`); a suppressed episode or a failed post appends nothing | Task 2 |
| `LoadCredential` id | `alerter-token` (template, evaluator, dead-man); `regulator-password` (evaluator, beside `greptimedb-envelope`) | Tasks 2, 4, 5 |
| NixOS module | `flake.modules.nixos.ntfy-alerter` at `modules/nixos/ntfy-alerter.nix`, declaring the shared generator; cinnabar declares `ntfy-alerter-env` in its own configuration; no options | Task 3 |
| Generator | `ntfy-alerter` (`share = true`, `runtimeInputs = [ pkgs.ntfy-sh ]`): one file `token` (`0400`, `tk_` plus 29 characters, no trailing newline), deployed on every machine importing `ntfy-alerter.nix`; path read from `clan.core.vars.generators.ntfy-alerter.files.token.path` (`/run/secrets/vars/shared/ntfy-alerter/token`) | Task 3 |
| Generator | `ntfy-alerter-env` (per machine, declared in `modules/machines/nixos/cinnabar/ntfy.nix` only, `dependencies = [ "ntfy-alerter" ]`, `runtimeInputs = [ pkgs.ntfy-sh pkgs.openssl ]`): reads `$in/ntfy-alerter/token`, hashes a random password it discards; one file `ntfy-env` (`0400`, exactly two lines `NTFY_AUTH_USERS=alerter:<bcrypt>:user` and `NTFY_AUTH_TOKENS=alerter:<token>`, `restartUnits = [ "ntfy-sh.service" ]`), path `/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env` | Task 3 |
| Check | `checks.x86_64-linux.ntfy-provisioning` at `modules/checks/ntfy-provisioning.nix`: runs both generators' `finalScript` in the sandbox; clauses for the token shape, the bcrypt shape, token equality (`NTFY_AUTH_TOKENS` carries exactly the shared token, else every token-bearing post gets 401) and access users against cinnabar's `services.ntfy-sh.settings.auth-access or [ ]` | Task 3 |
| Lib | `flake.lib.fleetAlertRules { lib; notifiedUnits; }` returning `{ rules; json; yaml; }` at `modules/nixos/fleet-alert/rules.nix`; each element of `rules` is `{ alert; expr; for; severity; annotations = { summary; }; presence = [ { selector; expectedHosts; } ]; attribution = [ { name; query; label; } ]; window ? { zone; weekday; start; end; }; }` with `for` a duration string; `StoreQueryFailing` and `RuleSignalMissing` have no `expr`; `json` holds the same objects with `for` in integer seconds; `yaml` is the Prometheus rules file of the rules with an `expr`, written as JSON, read only by `promtool`; `window.weekday` ISO (Monday 1), `start` inclusive, `end` exclusive, `HH:MM` | Task 4 |
| jq | `modules/nixos/fleet-alert/transition.jq`: `def transition($observations; $now; $rules)` over the state (`null` or `{}` on a first run), returning `{ state, posts }`, each post `{ title, priority, message, key = { kind, id } }` with `kind` in `firing`, `repost`, `resolved`, `budget` and no topic, which the caller adds with `.posts \|= map({topic: $topic} + .)`; `def mark_posted($post)` over the state, timed by `state.lastRun`; `def in_window($window; $now)` run under `TZ=<window.zone>` | Task 4 |
| Observations and state | observations `{ storeError, results = { <alert> = [ { labels, value } ] }, presence = { <selector> = [ <host> ] }, reporting = [ <host> ], failedLog = [ { at, unit, host } ], windows ? { <alert> = bool }, attribution ? { <host> = text } }`; state `{ instances = { <id> = { alert, labels, phase, severity, for, summary, attributed, value, activeSince, lastSeen, firingPostedAt, lastPostedAt } }, hosts = { <host> = epoch }, firings = [ { at, alert, host } ], budgetPostedAt, lastRun }`, `<id>` = `[alert, (labels \| to_entries \| sort_by(.key))] \| tojson`; an instance without `host_name` is never host-frozen and its title omits the host | Task 4 |
| Lib | `flake.lib.fleetAlertEvaluator pkgs { ntfySend; transition ? <transition.jq>; }` (`writeShellApplication` `fleet-alert`) and `flake.lib.fleetAlertDeadman pkgs { ntfySend; transition ? transitionJq; }` (`writeShellApplication` `fleet-deadman`); `transition` lets the check build them over mutant jq; outer `let` bindings `transitionJq` and `jqLib` in `modules/nixos/fleet-alert.nix` | Tasks 4, 5 |
| Evaluator config | JSON at `FLEET_ALERT_CONFIG`: `{ storeUrl, database, user, queryTimeoutSec: 10, queryDeadlineSec: 30, postDeadlineSec: 40, topic, heartbeatTopic, stateFile, failedLog, rules }`; env `FLEET_ALERT_NOW` (epoch seconds, set only by checks), `CREDENTIALS_DIRECTORY`; the unit sets `NTFY_TOKEN_FILE = "%d/alerter-token"`, read by `ntfy-send` | Task 4 |
| Dead-man config | JSON at `FLEET_DEADMAN_CONFIG`: `{ ntfyUrl, topic, evaluatorHost, heartbeatTopic, window: "10m", stateFile: "/var/lib/fleet-deadman/state.json", rules: [ AlertEvaluatorSilent ] }`; requires `NTFY_TOKEN_FILE`; time from `FLEET_ALERT_NOW` when set | Task 5 |
| NixOS module | `flake.modules.nixos.fleet-alert` at `modules/nixos/fleet-alert.nix`; options `services.fleet-alert.evaluator.{enable,tokenFile,regulatorPasswordFile,storeUrl,topic,heartbeatTopic}` (defaults `http://127.0.0.1:4000`, `fleet-alerts`, `fleet-heartbeat`), declared in Task 4; `services.fleet-alert.deadman.{enable,tokenFile,ntfyUrl,topic,evaluatorHost}` (defaults `http://[::1]:2586`, `fleet-alerts`, `magnetite`; `tokenFile` has none), declared in Task 5 | Tasks 4, 5 |
| Units and state | `fleet-alert.service`, `fleet-alert.timer`, `/var/lib/fleet-alert/state.json`; `fleet-deadman.service`, `fleet-deadman.timer`, `/var/lib/fleet-deadman/state.json` | Tasks 4, 5 |
| Check | `checks.x86_64-linux.fleet-alert` at `modules/checks/fleet-alert.nix`, data under `modules/checks/fleet-alert/` (`fixture_server.py`, `ntfy_stub.py`, `model.py`, `test_transition.py`, `fixtures/*.json`); `passthru` parts `promtoolRehearsal`, `fixtureRehearsal`, `propertyRehearsal`, and from Task 5 `deadmanRehearsal`; `perSystem` `let` bindings `ntfySendStub`, `fixtureCredentials`, `updateService`, `runtimeMutants`, and from Task 5 `deadmanFailures`, `deadmanMutants`, `deadmanInput`, `decision` | Task 4, extended in Task 5 |
| Fixture server | `python3 fixture_server.py --responses <file> --step-file <file> --port-file <file>`: binds `127.0.0.1` on an ephemeral port written to `--port-file`; serves `GET`/`POST /v1/prometheus/api/v1/query` from `responses[<step>][<query>]` (a Prometheus JSON body, or `{ "status": <code> }`); 404 for any other path, 400 without `x-greptime-db-name: fleet`, 401 for any user other than `regulator` with the fixture password `00112233445566778899aabbccddeeff`; prints `REQUEST <step> <query>`, `UNEXPECTED <step> <query>` and `VIOLATION <text>` lines, and records a violation if two requests are open at once | Task 4 |
| ntfy stub | `python3 ntfy_stub.py --topic <topic> --probe-status <code> --poll-status <code> …`: loopback stand-in for ntfy's publish and poll endpoints, used by `deadmanRehearsal` | Task 5 |
| Recording `ntfy-send` stub | `ntfySendStub` (`pkgs.writeShellScriptBin "ntfy-send"`): appends one JSON line `{ topic, message, headers, tokenFile }` per call to `$FLEET_ALERT_POSTS`; exits with `$FLEET_ALERT_POST_STATUS` (default 0) | Task 4 |
| Assertion | R9.5 in `modules/nixos/fleet-alert.nix`: `MemoryMax = "64M"` and `TimeoutStartSec = "50s"` on `fleet-alert.service` | Task 4 |
| Assertion | magnetite R8.2 holders `regulator-password = [ "fleet-alert" "greptimedb-envelope" ]`, written sorted (`modules/machines/nixos/magnetite/default.nix:647`) | Task 4 |
| Deploy procedure | `logs/s3-evidence/s3-deploy.sh HOST LABEL [FILE LINE]` (git-ignored); `logs/s3-evidence/window.env` holding `C1_START` … `C3_END`, `T_BADTOKEN`, `T_ANON403`, `T_CURL22`, `W_END`, `T_STOP`, `T_START`, `T_CAP_START`, `T_OOM`, `T_STORE_STOP`, `T_STORE_START`, `T_EXP_STOP`, `T_EXP_START`, `T_FORCED` | Task 7 |
| Assertions | token wiring: `observability-notify.nix` (with `tokenFile` set, the template loads it and names that credential in `NTFY_TOKEN_FILE`; every notified unit's resolve hooks run under `env NTFY_TOKEN_FILE=<tokenFile>`), `fleet-alert.nix` (`fleet-alert.service`, and from Task 5 `fleet-deadman.service`, load their `tokenFile` and name it in `NTFY_TOKEN_FILE`), magnetite's and, from Task 5, cinnabar's configuration (every `tokenFile` equals the `ntfy-alerter` token path); magnetite's R7.1 memory ceilings and kill order `nix-eval-jobs` > `greptimedb` > `opentelemetry-collector` > `fleet-alert`; each shown able to fail by an `extendModules` override | Tasks 4, 5 |

## Task map

| Plan task | `tasks.md` items | Pull request |
|---|---|---|
| Task 1: `ntfy-send` token transport | 1.1–1.4 | 1 |
| Task 2: Notifier module, `FAILED` log and token option | 2.1–2.6 | 2 |
| Task 3: `ntfy-alerter` provisioning and cinnabar proxy settings (cutover C1) | 3.1–3.7 | 3, then deploy C1 |
| Task 4: Evaluator, rules, transition function and `checks.fleet-alert` (cutover C2) | 4.1–4.11 | 4, then deploy C2 |
| Task 5: Dead-man and access entries (cutover C3) | 5.1–5.5 | 5, then deploy C3 |
| Task 6: Documentation | 6.1–6.5 | 6 |
| Task 7: Deployment verification | 7.1–7.7, interleaved: 7.1 after C1 and before C2, 7.2 after C2 and before C3, 7.3–7.7 after C3; 7.4's `log-level` revert is its own small PR | none (operations), plus the 7.4 revert PR |
| Task 8: Close-out | 8.1–8.5, 9.1, and §10 for applied review findings | 7 (`verify.md`, `review.md`, retrospective, archive) |

---

### Task 1: `ntfy-send` token transport

Implements `tasks.md` 1.1–1.4 (design D2, D19; FAI `The alerter token travels only as a file`; TSI `Failure notices are posted to one topic`).
The package test is written first and fails against today's script, then the script learns `NTFY_TOKEN_FILE` and the test passes, with a mutant of the script that passes the header on curl's argv rejected by the same assertions.

**Files:**
- Modify: `pkgs/by-name/ntfy-send/ntfy-send.sh` (whole file, 34 lines today)
- Modify: `pkgs/by-name/ntfy-send/package.nix` (whole file, 26 lines today)
- Create: `pkgs/by-name/ntfy-send/test-token-transport.nix`
- Modify: `modules/checks/package-tests.nix:21-40` (`declared`)
- Modify: `openspec/changes/stand-up-fleet-alerting/tasks.md` (ticks 1.1–1.3), `openspec/changes/stand-up-fleet-alerting/proposal.md` (Linear ledger)
- Test: `checks.<system>.package-ntfy-send-test-token-transport` (every system; the package differs per platform through `NTFY_CURL_BIN`, so the test is not gated to x86_64-linux)

**Interfaces:**
- Consumes: nothing from earlier tasks.
- Produces:
  - `ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, usage unchanged.
  - Environment `NTFY_TOKEN_FILE`: unset or empty means an anonymous post with curl's argv exactly as today; set and non-empty means the script reads the file with `$(< "$NTFY_TOKEN_FILE")`, pipes `Authorization: Bearer <token>\n` from the `printf` builtin into curl, and passes `-H @-` immediately after `-sfk -m 5` and before the caller's `CURL_ARGS`; an unreadable or missing file exits 1 before curl runs.
  - Environment `NTFY_CURL_BIN`, unchanged (set by `package.nix`; overridden by the test).
  - `passthru.tests.token-transport`, exposed as `checks.<system>.package-ntfy-send-test-token-transport` through `modules/checks/package-tests.nix`.

- [ ] **Step 1: Show the check does not exist yet (RED, evaluation)**

Run:

```bash
mkdir -p logs/s3-evidence
nix eval --json .#checks.x86_64-linux --apply 'c: builtins.hasAttr "package-ntfy-send-test-token-transport" c' 2>&1 | tee logs/s3-evidence/1.3-check-absent-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `false`.

- [ ] **Step 2: Write the token-transport test**

Create `pkgs/by-name/ntfy-send/test-token-transport.nix` with exactly this content, following `pkgs/by-name/ghq-shared/test-wrapper.nix` (a `runCommand` with a recording stub and an `expect`-style helper):

````nix
# passthru.tests.token-transport (design D2, D19): with NTFY_TOKEN_FILE set,
# ntfy-send hands the token to curl only on stdin, as the header file that
# `-H @-` reads, so it is on no argv. It runs the source script, not the built
# wrapper, so that NTFY_CURL_BIN can name a curl stub recording its argv and
# stdin. The same assertions run against a mutant of the script that passes the
# header with -H and must reject it.
{
  runCommand,
  bash,
}:
runCommand "ntfy-send-test-token-transport" { } ''
  set -euo pipefail
  work=$(mktemp -d)
  token=tk_AbCdEfGhIjKlMnOpQrStUvWxYz012
  printf '%s' "$token" > "$work/token"
  cat > "$work/curl" <<'STUB'
  #!${bash}/bin/bash
  printf '%s\n' "$@" > "$REC/argv"
  cat > "$REC/stdin"
  STUB
  chmod +x "$work/curl"
  export NTFY_CURL_BIN="$work/curl"
  caller=$(printf '%s\n' -H "Title: t" -d hello https://ntfy.zt/fleet-acceptance)

  # run SCRIPT ENV...: runs SCRIPT under `env ENV...` with the stub recording
  # into a fresh $REC; sets $status.
  run() {
    local script=$1
    shift
    REC=$(mktemp -d)
    export REC
    status=0
    env "$@" ${bash}/bin/bash "$script" hello fleet-acceptance -H "Title: t" < /dev/null || status=$?
  }

  # cases SCRIPT: returns 0 when every assertion holds, 1 at the first failure.
  cases() {
    local script=$1

    run "$script" NTFY_TOKEN_FILE="$work/token"
    [ "$status" = 0 ] || { echo "FAIL: token set: exit $status"; return 1; }
    if grep -qF "$token" "$REC/argv"; then echo "FAIL: token set: the token is on curl's argv"; return 1; fi
    [ "$(cat "$REC/stdin")" = "Authorization: Bearer $token" ] || { echo "FAIL: token set: stdin is not exactly the header"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sfk -m 5 -H @-)"$'\n'"$caller" ] || { echo "FAIL: token set: argv is not -H @- before the caller's arguments"; return 1; }
    echo "ok: token set: header on stdin, -H @- on argv, token on no argv"

    run "$script" -u NTFY_TOKEN_FILE
    [ "$status" = 0 ] || { echo "FAIL: token unset: exit $status"; return 1; }
    [ ! -s "$REC/stdin" ] || { echo "FAIL: token unset: curl got stdin"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sfk -m 5)"$'\n'"$caller" ] || { echo "FAIL: token unset: argv changed"; return 1; }
    echo "ok: token unset: argv unchanged, no stdin"

    run "$script" NTFY_TOKEN_FILE=
    [ "$status" = 0 ] || { echo "FAIL: token empty: exit $status"; return 1; }
    [ ! -s "$REC/stdin" ] || { echo "FAIL: token empty: curl got stdin"; return 1; }
    [ "$(cat "$REC/argv")" = "$(printf '%s\n' -sfk -m 5)"$'\n'"$caller" ] || { echo "FAIL: token empty: argv changed"; return 1; }
    echo "ok: token empty: argv unchanged, no stdin"

    run "$script" NTFY_TOKEN_FILE="$work/missing"
    [ "$status" != 0 ] || { echo "FAIL: unreadable token file: exit 0"; return 1; }
    [ ! -e "$REC/argv" ] || { echo "FAIL: unreadable token file: curl ran"; return 1; }
    echo "ok: unreadable token file: exit $status before curl"
  }

  cases ${./ntfy-send.sh}

  ${bash}/bin/bash ${./ntfy-send.sh} --help | grep -q '^  NTFY_TOKEN_FILE '
  echo "ok: --help documents NTFY_TOKEN_FILE"

  # The negative control: the header on argv instead of stdin.
  substitute ${./ntfy-send.sh} "$work/mutant.sh" \
    --replace-fail '-H @- "$@"' '-H "Authorization: Bearer $token" "$@"'
  if cases "$work/mutant.sh"; then
    echo "FAIL: the mutant passing the header on argv was accepted"
    exit 1
  fi
  echo "ok: the mutant passing the header on argv was rejected"
  touch "$out"
''
````

The fixture token is `tk_` plus 29 characters of `[-_A-Za-z0-9]`, the shape ntfy 2.28.0 accepts (`user/util.go:24`); it is not a credential.
`substitute --replace-fail` fails the build if the pattern is absent, so the mutant always differs from the script it mutates.
This logic was rehearsed with bash 5 on a scratch copy of the Step 6 script during planning: the real script passed all five assertions and the mutant failed at `FAIL: token set: the token is on curl's argv`.

- [ ] **Step 3: Rewrite `pkgs/by-name/ntfy-send/package.nix` with the test and the documented variable**

Replace the whole file with exactly:

```nix
# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# and system units run it from ExecStart.
#
# Endpoint security software on Darwin blocks ad-hoc signed (Nix store)
# binaries from TCP connections over ZeroTier. The preamble injects
# NTFY_CURL_BIN, the eval-time-resolved curl path, so Darwin uses /usr/bin/curl
# while Linux uses the curl from runtimeInputs.
#
# NTFY_TOKEN_FILE, when set and non-empty, names a file holding an ntfy access
# token, such as the `alerter` token that fleet-* topics require. The script
# reads it with bash's $(< file) and prints `Authorization: Bearer <token>` with
# the printf builtin into curl's stdin, which curl reads with `-H @-`, so the
# token is on no process's argv. Unset, the post is anonymous, which host
# topics accept. passthru.tests.token-transport runs the source script against
# a recording curl stub, with a mutant that passes the header on argv.
{
  lib,
  stdenv,
  curl,
  callPackage,
  writeShellApplication,
}:
writeShellApplication {
  name = "ntfy-send";
  runtimeInputs = lib.optional (!stdenv.hostPlatform.isDarwin) curl;
  text = ''
    export NTFY_CURL_BIN=${if stdenv.hostPlatform.isDarwin then "/usr/bin/curl" else "curl"}
    ${builtins.readFile ./ntfy-send.sh}
  '';
  passthru.tests.token-transport = callPackage ./test-token-transport.nix { };
  meta = {
    description = "Send push notification via ntfy.zt (Apple-signed curl on Darwin)";
    license = lib.licenses.mit;
    mainProgram = "ntfy-send";
  };
}
```

`writeShellApplication` at the root pin takes `passthru ? { }` (`pkgs/build-support/trivial-builders/default.nix:282` in `/nix/store/l9sdkpnv33hmdr49q2nhahph8bpjmc9s-source`, the `ac1faec` source).

- [ ] **Step 4: Declare the test in `modules/checks/package-tests.nix`**

In the `declared` attribute set, insert between the `ghq-shared` entry (`:23-26`) and `playwright-cli = [ "smoke" ];` (`:27`):

```nix
        ntfy-send = [ "token-transport" ];
```

The declaration and the `passthru.tests` must land together: the `declarationMatches` assertion (`:66-69`) fails every `package-*-test-*` check while they disagree.
Then snapshot the new file:

```bash
jj st --no-pager >/dev/null && git ls-files pkgs/by-name/ntfy-send
```

Expected: `pkgs/by-name/ntfy-send/ntfy-send.sh`, `pkgs/by-name/ntfy-send/package.nix` and `pkgs/by-name/ntfy-send/test-token-transport.nix`.

- [ ] **Step 5: Run the test against today's script (RED, build)**

Run:

```bash
nix build -L .#checks.aarch64-darwin.package-ntfy-send-test-token-transport 2>&1 | tee logs/s3-evidence/1.2-token-transport-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg 'FAIL|ok:|error:'
```

Expected: the build fails; the log's first assertion line is `FAIL: token set: stdin is not exactly the header`, because today's script ignores `NTFY_TOKEN_FILE`, so curl's stdin is empty, followed by `error: builder for '/nix/store/…-ntfy-send-test-token-transport.drv' failed with exit code 1`.

- [ ] **Step 6: Teach `ntfy-send.sh` to read `NTFY_TOKEN_FILE`**

Replace the whole of `pkgs/by-name/ntfy-send/ntfy-send.sh` with exactly:

```bash
#!/usr/bin/env bash
# Send push notification via ntfy.zt
set -euo pipefail

case "${1:-}" in
  -h|--help)
    cat <<'HELP'
Send push notification via ntfy.zt

Usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]

Arguments:
  MESSAGE     Notification body text (required)
  TOPIC       ntfy topic (default: local hostname)
  CURL_ARGS   Extra curl arguments (e.g. -H "Priority: high")

Environment:
  NTFY_TOKEN_FILE  File holding an ntfy access token; when set and non-empty,
                   the token is sent as "Authorization: Bearer" on curl's
                   stdin (-H @-), never on a command line. fleet-* topics
                   need it; host topics accept anonymous posts.

On Darwin, uses /usr/bin/curl (Apple-signed) because endpoint security
software blocks ad-hoc signed Nix store binaries from TCP connections
over ZeroTier.

Examples:
  ntfy-send "build complete"
  ntfy-send "deploy finished" stibnite
  ntfy-send "alert" stibnite -H "Priority: urgent" -H "Tags: warning"
  NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token ntfy-send "probe" fleet-acceptance
HELP
    exit 0
    ;;
esac

msg="${1:?usage: ntfy-send MESSAGE [TOPIC] [CURL_ARGS...]}"
topic="${2:-$(hostname -s)}"
shift 2 2>/dev/null || shift $#
if [ -n "${NTFY_TOKEN_FILE:-}" ]; then
  # $(< file) and printf are bash builtins, so the token is on no argv.
  token=$(< "$NTFY_TOKEN_FILE")
  printf 'Authorization: Bearer %s\n' "$token" |
    "${NTFY_CURL_BIN:-curl}" -sfk -m 5 -H @- "$@" -d "$msg" "https://ntfy.zt/$topic"
else
  "${NTFY_CURL_BIN:-curl}" \
    -sfk -m 5 "$@" -d "$msg" "https://ntfy.zt/$topic"
fi
```

The message stays in `-d`, so stdin is free for the header (design D2).
Under `set -e`, `token=$(< missing)` returns 1 and the script exits before curl; under `pipefail`, a curl failure is the pipeline's status, so callers' `|| exit 1` still sees it.
The token path in the example is the shared generator's path that Task 3 provisions; it is a path, not a credential.

- [ ] **Step 7: Run the test on both platforms (GREEN, build)**

Run:

```bash
jj st --no-pager >/dev/null
nix build -L .#checks.aarch64-darwin.package-ntfy-send-test-token-transport .#checks.x86_64-linux.package-ntfy-send-test-token-transport 2>&1 | tee logs/s3-evidence/1.2-token-transport-$(date -u +%Y%m%dT%H%M%SZ).log | rg 'FAIL|ok:|error:'
```

Expected: both builds succeed; each system's log shows, in order, `ok: token set: header on stdin, -H @- on argv, token on no argv`, `ok: token unset: argv unchanged, no stdin`, `ok: token empty: argv unchanged, no stdin`, `ok: unreadable token file: exit 1 before curl`, `ok: --help documents NTFY_TOKEN_FILE`, then the mutant's run with `FAIL: token set: the token is on curl's argv` followed by `ok: the mutant passing the header on argv was rejected`; no `error:` line.
If the x86_64-linux build cannot be scheduled locally, nixbot builds it on the pull request, and its log is fetched as this evidence instead.

- [ ] **Step 8: Build the package and read the delivered help text (build, built output)**

Run:

```bash
{
  nix build --no-link .#checks.x86_64-linux.package-ntfy-send .#checks.aarch64-darwin.package-ntfy-send && echo package-checks-built
  nix run .#ntfy-send -- --help | rg -n 'NTFY_TOKEN_FILE'
} 2>&1 | tee logs/s3-evidence/1.1-ntfy-send-package-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `package-checks-built` (each build runs `writeShellApplication`'s `shellcheck` over the new script), then `17:  NTFY_TOKEN_FILE  File holding an ntfy access token; when set and non-empty,` and `29:  NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token ntfy-send "probe" fleet-acceptance` (line numbers of the help output, which starts at the script's `Send push notification via ntfy.zt` line).

- [ ] **Step 9: Record the check's evaluation cost (evaluation)**

Run:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/1.2-token-transport-stats.json \
  nix eval --raw '.#.checks.x86_64-linux.package-ntfy-send-test-token-transport.drvPath'; echo
jq '{bytes: .gc.totalBytes, cpu: .cpuTime}' /tmp/1.2-token-transport-stats.json 2>&1 | tee logs/s3-evidence/1.2-token-transport-cost-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: a `/nix/store/…-ntfy-send-test-token-transport.drv` path, then `bytes` below 536870912 (0.5 GiB).
The value forces `declarationMatches`, which reads every non-blacklisted package's `passthru.tests` names, exactly as each existing `package-*-test-*` check already does; if `bytes` exceeds the budget, stop and report the figure with the same measurement for `package-atomic-test-help` beside it, because the cost is then the shared declaration assertion, not this test.

- [ ] **Step 10: Format**

Run:

```bash
{
  nix fmt -- pkgs/by-name/ntfy-send/ntfy-send.sh pkgs/by-name/ntfy-send/package.nix pkgs/by-name/ntfy-send/test-token-transport.nix modules/checks/package-tests.nix
  nix fmt -- --fail-on-change && echo fmt-clean
} 2>&1 | tee logs/s3-evidence/1.4-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the last line is `fmt-clean`.
If the first command reformatted any file, rerun Step 7's darwin build before committing.

- [ ] **Step 11: Tick 1.1–1.3 and move CAM-70 to In Progress**

In `openspec/changes/stand-up-fleet-alerting/tasks.md`, change the leading `- [ ]` of the lines beginning `- [ ] 1.1`, `- [ ] 1.2` and `- [ ] 1.3` (lines 9–11) to `- [x]`, and nothing else; 1.4 is ticked by the orchestrator when nixbot reports the pull request green.
Run: `jj diff --git -- openspec/changes/stand-up-fleet-alerting/tasks.md | grep -c '^+- \[x\]'`
Expected: `3`.

This is the change's first `- [x]`, which by `skill://openspec-linear-sync` drives Todo → In Progress for CAM-70; every Linear write is best-effort and never blocks the commit.

```bash
linear auth whoami --workspace cameronraysmith
linear issue view CAM-70 --json --no-comments --workspace cameronraysmith | jq -r .state.name
```

Expected: `Workspace: cameronraysmith`, then `Todo`.
Only if the printed state is `Backlog` or `Todo`:

```bash
linear issue update CAM-70 --state "In Progress" --workspace cameronraysmith
printf 'Implementation has begun: ntfy-send reads the alerter token from NTFY_TOKEN_FILE, with a token-transport package test and its argv mutant (tasks 1.1-1.3).\n' > /tmp/cam70-in-progress.md
linear issue comment add CAM-70 --body-file /tmp/cam70-in-progress.md --workspace cameronraysmith
linear issue view CAM-70 --json --no-comments --workspace cameronraysmith | jq -r .state.name
date -u +%Y-%m-%dT%H:%M:%SZ
```

Expected: `In Progress`, then the timestamp `<now>`.
In `openspec/changes/stand-up-fleet-alerting/proposal.md`'s frontmatter: if the transition posted, set `linear_story_state: In Progress`, `last_synced_state: In Progress`, `last_synced_at: <now>`, and append `  - { at: "<now>", transition: "Todo->In Progress", outcome: "posted", note: "first - [x] in tasks.md (1.1-1.3)" }` to `attempt_log`; if a write failed, leave both states at `Todo` and append the same entry with `outcome: "dropped"` and the one-line error as `note`; if Linear was already at or past `In Progress`, set both states to the state read and `last_synced_at: <now>`, and append nothing.

- [ ] **Step 12: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(ntfy-send): send the token from NTFY_TOKEN_FILE on stdin, never on argv'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(ntfy-send): send the token from NTFY_TOKEN_FILE")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  pkgs/by-name/ntfy-send \
  modules/checks/package-tests.nix \
  openspec/changes/stand-up-fleet-alerting/tasks.md \
  openspec/changes/stand-up-fleet-alerting/proposal.md
jj diff --no-pager --summary -r "$change"
```

Expected: `M pkgs/by-name/ntfy-send/ntfy-send.sh`, `M pkgs/by-name/ntfy-send/package.nix`, `A pkgs/by-name/ntfy-send/test-token-transport.nix`, `M modules/checks/package-tests.nix`, `M openspec/changes/stand-up-fleet-alerting/tasks.md` and, if Step 11 wrote the ledger, `M openspec/changes/stand-up-fleet-alerting/proposal.md`, and nothing else.
If `tasks.md` or `proposal.md` carried hunks other than this task's before the squash, squash that file with `--interactive` and select only this task's hunks.
The orchestrator rebases the development join onto this change, pushes it, opens pull request 1 and enqueues it; it lands through the merge queue before Task 2's pull request is enqueued.

---

### Task 2: Notifier module, `FAILED` log and token option

Implements `tasks.md` 2.1–2.6 (design D3, D4, D9, D19; TSI `Failure notices are posted to one topic`; FAI `The alert budget is counted over the evaluator's state and the notifier's FAILED log`).
The move is proved a pure refactor by an evaluated baseline and an empty diff; the `FAILED` log is driven by the rehearsal, which fails first and then rejects two mutants of the `failed` script; the token wiring is added behind `tokenFile = null`, so magnetite's evaluated units differ from the baseline only in the `failed` script's store path.

**Files:**
- Create: `modules/nixos/observability-notify.nix`
- Modify: `modules/clan/services/otel-collector/flake-module.nix:16-23` (header), `:81-137` (scripts and `flake.lib`, moved out), `:147-154` (agent `let` bindings), `:194` (agent `imports`), `:196-205` (option, moved out), `:367-395` (wiring and template, moved out), `:566-574` (manifest readme)
- Modify: `modules/checks/otel-collector-config.nix:70` (`resolvedHook`), `:104-140` (`notifierRehearsal`), `:186-190` (`hookScripts`)
- Modify: `modules/clan/services/otel-collector/README.md:3`, `:79`, `:96-114`, `:126`, `:139`
- Modify: `openspec/changes/stand-up-fleet-alerting/tasks.md` (ticks 2.1–2.5)
- Test: `checks.x86_64-linux.otel-collector-config` (R3.1 and its `observability-notify-rehearsal`), `checks.x86_64-linux.nixos-magnetite`

**Interfaces:**
- Consumes: Task 1's `ntfy-send` reading `NTFY_TOKEN_FILE`.
- Produces:
  - `flake.modules.nixos.observability-notify` at `modules/nixos/observability-notify.nix`, module `key = "vanixiets#observability-notify"` (a host importing it directly and through the `agent` role loads it once).
  - Option `services.observability-notify.units` (`listOf str`, default `[ ]`), unchanged.
  - Option `services.observability-notify.tokenFile` (`nullOr str`, default `null`).
  - `flake.lib.observabilityNotifyScripts pkgs { ntfySend; stampDir; hostName; }` returning `{ failed; resolved; }`, signature unchanged, moved here.
  - `observability-notify@.service`: `Type = "oneshot"`, `StateDirectory = "observability-notify"`, `ExecStart = "<failed> %i"`, `environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC = "900"`; with `tokenFile` set, also `serviceConfig.LoadCredential = [ "alerter-token:<tokenFile>" ]` and `environment.NTFY_TOKEN_FILE = "%d/alerter-token"`.
  - Hooks on each listed unit: with `tokenFile = null`, `ExecStartPost = [ "-+<resolved> start %n" ]` and `ExecStopPost = [ "-+<resolved> stop %n" ]` as today; with `tokenFile` set, `"-+${pkgs.coreutils}/bin/env NTFY_TOKEN_FILE=<tokenFile> <resolved> start %n"` and the same with `stop`.
  - `/var/lib/observability-notify/failed.log`, mode `0644`, one line `<epoch> <unit> <host>` appended after each successful `FAILED` post, where `<unit>` is the template instance `%i` including `.service` (for example `1760800000 greptimedb.service magnetite`); a suppressed episode or a failed post appends nothing.
  - R3.1's `resolvedHook` accepts the optional `env NTFY_TOKEN_FILE=<path> ` prefix; its last capture is the script.

- [ ] **Step 1: Record the notifier baseline (2.1, evaluation)**

Run:

```bash
mkdir -p logs/s3-evidence
ts=$(date -u +%Y%m%dT%H%M%SZ)
nix eval --json .#nixosConfigurations.magnetite.config --apply 'c: let names = [ "observability-notify@" "opentelemetry-collector" "greptimedb" "greptimedb-envelope" "greptimedb-schema" ] ++ c.services.observability-notify.units; in builtins.listToAttrs (map (n: { name = n; value = { inherit (c.systemd.services.${n}) unitConfig serviceConfig environment; }; }) names)' | jq -S . > logs/s3-evidence/2.1-notifier-baseline-$ts.json
jq -r 'keys | length, .[]' logs/s3-evidence/2.1-notifier-baseline-$ts.json
```

Expected: `14`, then `greptimedb`, `greptimedb-envelope`, `greptimedb-schema`, `observability-notify@`, `opentelemetry-collector`, `zfs-assert-root-docker-noautosnap`, `zfs-assert-root-greptimedb-noautosnap`, `zfs-assert-root-nix-noautosnap`, `zfs-assert-root-podman-noautosnap`, `zfs-set-root-greptimedb-quota`, `zfs-set-root-greptimedb-reservation`, `zfs-set-root-home-reservation`, `zfs-set-root-nix-quota`, `zfs-set-root-nixos-reservation`: the 13 notified units (magnetite's 12 at `modules/machines/nixos/magnetite/default.nix:327-340` plus the agent's `opentelemetry-collector`) and the template.
This output was confirmed on `main` at planning time (2026-10-18), with `greptimedb-schema`'s hooks `-+/nix/store/1aw2xlpaw66l413nzvnwipzpxgfaj2bk-observability-notify-resolved start %n` and `… stop %n`.
Keep the path in `baseline` for later steps: `baseline=logs/s3-evidence/2.1-notifier-baseline-$ts.json`.

- [ ] **Step 2: Create `modules/nixos/observability-notify.nix` by moving the notifier**

Create the file with exactly this content.
Its `observabilityNotifyScripts` body is `modules/clan/services/otel-collector/flake-module.nix:84-134` unchanged; its option is `:196-205` unchanged; its wiring is `:369-393` minus `prometheus-node-exporter` and the collector's own `units` entry, with the hook strings built by `hook`, which yields the same strings while `tokenFile` is `null`.

```nix
# Failure notifier for systemd units (ADR-009 item 11; S3 design D3, D4, D9).
#
# observability-notify@.service posts `FAILED <unit> on <host>` once per
# failure episode to ntfy's fleet-alerts topic through the one ntfy-send
# package, guarded by a stamp per unit. Every unit listed in
# services.observability-notify.units gets OnFailure= and two root hooks that
# post RESOLVED and remove the stamp: ExecStartPost= on the unit's next
# successful start, which ends an episode across automatic restarts, and
# ExecStopPost= on its next successful exit.
#
# Hosts import this module directly or through the otel-collector agent role;
# the key makes a host doing both load it once. It reads no clan var: a host
# that sets services.observability-notify.tokenFile supplies the token's path.
{ ... }:
let
  # The notifier's two scripts, a function so that
  # checks.x86_64-linux.otel-collector-config can rehearse them against a
  # temporary stamp directory and a recording ntfy-send.
  observabilityNotifyScripts =
    pkgs:
    {
      ntfySend,
      stampDir,
      hostName,
    }:
    {
      # One post per failure episode: skip while the stamp exists. A unit
      # whose last FAILED was posted less than OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC
      # ago opens a `suppressed` episode instead, which the resolve hooks end
      # without a post. A persistent crash loop therefore yields one
      # FAILED/RESOLVED pair, then at most one new pair per interval per unit;
      # detecting crash loops by restart rate belongs to S3. A failed post
      # writes no stamp, so the next failure posts again.
      failed = pkgs.writeShellScript "observability-notify-failed" ''
        : "''${OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC:?}"
        unit="$1"
        stamp="${stampDir}/$unit"
        last="${stampDir}/last-failed/$unit"
        if [ -e "$stamp" ]; then
          exit 0
        fi
        now=$(${pkgs.coreutils}/bin/date +%s)
        if [ -s "$last" ] && [ $((now - $(< "$last"))) -lt "$OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC" ]; then
          echo suppressed > "$stamp"
          exit 0
        fi
        ${ntfySend} "FAILED $unit on ${hostName}" fleet-alerts || exit 1
        echo posted > "$stamp"
        ${pkgs.coreutils}/bin/mkdir -p "${stampDir}/last-failed"
        echo "$now" > "$last"
      '';

      # Runs as root (`+`) after a notified unit starts (`start`) or stops
      # (`stop`); a failed post leaves the stamp for the next chance and never
      # fails the unit.
      resolved = pkgs.writeShellScript "observability-notify-resolved" ''
        mode="$1"
        unit="$2"
        stamp="${stampDir}/$unit"
        if [ -e "$stamp" ] && { [ "$mode" = start ] || [ "''${SERVICE_RESULT:-}" = success ]; }; then
          if [ "$(< "$stamp")" = suppressed ]; then
            ${pkgs.coreutils}/bin/rm -f "$stamp"
          else
            ${ntfySend} "RESOLVED $unit on ${hostName}" fleet-alerts && ${pkgs.coreutils}/bin/rm -f "$stamp"
          fi
        fi
        exit 0
      '';
    };
in
{
  flake.lib = { inherit observabilityNotifyScripts; };

  flake.modules.nixos.observability-notify =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.observability-notify;
      notifyScripts = observabilityNotifyScripts pkgs {
        ntfySend = lib.getExe pkgs.ntfy-send;
        stampDir = "/var/lib/observability-notify";
        hostName = config.networking.hostName;
      };
      hook = mode: "-+${notifyScripts.resolved} ${mode} %n";
    in
    {
      key = "vanixiets#observability-notify";

      options.services.observability-notify.units = lib.mkOption {
        type = lib.types.listOf lib.types.str;
        default = [ ];
        description = ''
          systemd.services attribute names (without `.service`) whose failure
          posts a notice to ntfy's fleet-alerts topic through
          observability-notify@.service, and whose next successful start or
          exit after a notice posts RESOLVED.
        '';
      };

      config.systemd.services = lib.mkMerge [
        (lib.genAttrs cfg.units (_: {
          unitConfig.OnFailure = [ "observability-notify@%n.service" ];
          serviceConfig = {
            # An automatic restart's stop is never a success, so the
            # episode ends at the next start. systemd runs ExecStartPost
            # before ExecStopPost and both run the one script, so a
            # oneshot's stop hook finds the stamp gone and posts no second
            # RESOLVED.
            ExecStartPost = [ (hook "start") ];
            ExecStopPost = [ (hook "stop") ];
          };
        }))
        {
          "observability-notify@" = {
            environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC = "900";
            description = "Post a failure notice for %i to ntfy";
            serviceConfig = {
              Type = "oneshot";
              StateDirectory = "observability-notify";
              ExecStart = "${notifyScripts.failed} %i";
            };
          };
        }
      ];
    };
}
```

flake-parts wraps each `flake.modules.nixos.*` value without a key (`extras/modules.nix`, `addInfo`, "TODO: set key?" at flake-parts `024633c`), so the key here is what deduplicates a double import, as `collectorCore`'s key does in `flake-module.nix:56`.

- [ ] **Step 3: Remove the notifier from the collector's flake module and import the new module**

In `modules/clan/services/otel-collector/flake-module.nix`:

1. Replace the header lines `:16-23` (from `# The agent also owns the failure notifier (ADR-009 item 11):` through `# no credential.`) with:

```nix
# The agent imports the failure notifier, flake.modules.nixos.observability-
# notify (modules/nixos/observability-notify.nix), and lists its own unit in
# services.observability-notify.units.
```

2. Delete `:81-134` (the comment `# The notifier's two scripts, …` through the closing `};` of `observabilityNotifyScripts`), so the `let` ends with `collectorCore`.
3. Delete `:137` (`flake.lib = { inherit observabilityNotifyScripts; };`) and the blank line after it.
4. In the agent's `let`, delete `:147` (`cfg = …`), `:149-154` (`stampDir`, `notifyScripts`, `resolved`), keeping `hostName = config.networking.hostName;`.
5. Replace `:194` (`imports = [ collectorCore ];`) with:

```nix
      imports = [
        collectorCore
        nixosModules.observability-notify
      ];
```

6. Delete `:196-205` (the `options.services.observability-notify.units` declaration) and the blank line after it.
7. Replace `:369-395` (from `systemd.services = lib.mkMerge [` through its closing `];`) with:

```nix
          systemd.services.prometheus-node-exporter.serviceConfig.MemoryMax = "64M";
```

leaving `:367` (`services.observability-notify.units = [ "opentelemetry-collector" ];`) as it is.
8. In the manifest `readme` (`:566-574`), replace `node_exporter on loopback, and owns the observability-notify@` with `node_exporter on loopback, and imports the observability-notify@`.

After these edits nothing in the agent fragment refers to `cfg`, `stampDir`, `notifyScripts` or `resolved`; `nixosModules` is the file's existing `config.flake.modules.nixos` binding (`:32`).
The container test's import of `self.modules.nixos.otel-collector-agent` (`modules/vm-tests/greptimedb-pipeline.nix:113`) now brings the notifier through this import, as it did before through the agent itself.

Then snapshot and confirm the new file is tracked:

```bash
jj st --no-pager >/dev/null && git ls-files modules/nixos/observability-notify.nix
```

Expected: `modules/nixos/observability-notify.nix`.

- [ ] **Step 4: Show the move changed nothing magnetite deploys (2.2, evaluation)**

Run the Step 1 evaluation again and diff it against the baseline:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
nix eval --json .#nixosConfigurations.magnetite.config --apply 'c: let names = [ "observability-notify@" "opentelemetry-collector" "greptimedb" "greptimedb-envelope" "greptimedb-schema" ] ++ c.services.observability-notify.units; in builtins.listToAttrs (map (n: { name = n; value = { inherit (c.systemd.services.${n}) unitConfig serviceConfig environment; }; }) names)' | jq -S . > logs/s3-evidence/2.2-notifier-moved-$ts.json
diff "$baseline" logs/s3-evidence/2.2-notifier-moved-$ts.json 2>&1 | tee logs/s3-evidence/2.2-notifier-diff-$ts.log && echo IDENTICAL
```

Expected: `diff` prints nothing and the last line is `IDENTICAL`: both scripts are built from the same text and name, so even their store paths are unchanged.

Then show the lib moved and the key deduplicates a second import:

```bash
{
  nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in builtins.attrNames (f.lib.observabilityNotifyScripts f.nixosConfigurations.magnetite.pkgs { ntfySend = "true"; stampDir = "/tmp"; hostName = "x"; })'
  nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in builtins.length (f.nixosConfigurations.magnetite.extendModules { modules = [ f.modules.nixos.observability-notify ]; }).config.services.observability-notify.units'
} 2>&1 | tee logs/s3-evidence/2.2-notifier-lib-key-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `["failed","resolved"]`, then `13`.
Without the key, the second evaluation would fail with ``The option `services.observability-notify.units' in … is already declared in …``.

- [ ] **Step 5: Extend the rehearsal with the `FAILED` log and its mutants (2.3)**

In `modules/checks/otel-collector-config.nix`, replace `notifierRehearsal` (`:104-140`, from `notifierRehearsal =` through the closing `'';`) with:

```nix
      notifierRehearsal =
        pkgs.runCommand "observability-notify-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
            ];
            meta.description = "behavioural check: a crash loop yields one FAILED/RESOLVED pair per interval and one failed.log line per posted FAILED";
          }
          ''
            set -euo pipefail
            export NTFY_STUB_LOG="$TMPDIR/posts" OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC=900
            # systemd gives services UMask 0022; 0077 here shows the script
            # sets failed.log's mode itself.
            umask 077
            unit=opentelemetry-collector.service
            failed="FAILED $unit on rehearsal|fleet-alerts"
            resolved="RESOLVED $unit on rehearsal|fleet-alerts"
            expect() {
              if [ "$(cat "$NTFY_STUB_LOG")" != "$2" ]; then
                echo "FAIL: $1; posts were:" >&2
                cat "$NTFY_STUB_LOG" >&2
                exit 1
              fi
              echo "ok: $1"
            }
            # expectLog DESCRIPTION COUNT: failed.log is mode 0644 and holds
            # exactly COUNT lines `<epoch> <unit> rehearsal`, each epoch within
            # this rehearsal.
            expectLog() {
              local log="$TMPDIR/notify/failed.log" lines epoch rest
              lines=$(grep -cE '^[0-9]+ '"$unit"' rehearsal$' "$log" 2>/dev/null || true)
              if [ ! -e "$log" ] || [ "$(wc -l < "$log")" != "$2" ] || [ "$lines" != "$2" ] || [ "$(stat -c %a "$log")" != 644 ]; then
                echo "FAIL: $1; failed.log was:" >&2
                ls -l "$log" >&2 || true
                cat "$log" >&2 || true
                exit 1
              fi
              while read -r epoch rest; do
                if [ "$epoch" -lt "$t0" ] || [ "$epoch" -gt "$(date +%s)" ]; then
                  echo "FAIL: $1; epoch $epoch is outside the rehearsal" >&2
                  exit 1
                fi
              done < "$log"
              echo "ok: $1"
            }
            # rehearse FAILED: the crash loop against a fresh stamp directory,
            # with FAILED as the notifier's failed script.
            rehearse() {
              local failedScript=$1
              rm -rf "$TMPDIR/notify"
              mkdir "$TMPDIR/notify"
              : > "$NTFY_STUB_LOG"
              t0=$(date +%s)
              # systemd's order for a crash with automatic restart: the stop
              # hook with a failed result, OnFailure's notifier, then the start.
              crash() { SERVICE_RESULT=exit-code ${rehearsedNotify.resolved} stop "$unit"; "$failedScript" "$unit"; }
              start() { ${rehearsedNotify.resolved} start "$unit"; }

              crash; start; crash; start
              expect "crash, start, crash, start within the interval posts one pair" "$failed"$'\n'"$resolved"
              expectLog "one posted FAILED and one suppressed episode log one line" 1

              mkdir -p "$TMPDIR/notify/last-failed"
              echo $(( $(date +%s) - 901 )) > "$TMPDIR/notify/last-failed/$unit"
              crash; "$failedScript" "$unit"; start
              SERVICE_RESULT=success ${rehearsedNotify.resolved} stop "$unit"
              expect "a crash after the interval posts a new pair, once" "$failed"$'\n'"$resolved"$'\n'"$failed"$'\n'"$resolved"
              expectLog "a second posted FAILED logs a second line, a repeated failure none" 2
            }
            # mutant NAME LINE: the failed script without its one line
            # containing LINE must fail the rehearsal.
            mutant() {
              local script="$TMPDIR/failed-$1"
              grep -vF "$2" ${rehearsedNotify.failed} > "$script"
              chmod +x "$script"
              if [ "$(wc -l < "$script")" -ne $(( $(wc -l < ${rehearsedNotify.failed}) - 1 )) ]; then
                echo "FAIL: mutant $1 did not remove exactly one line" >&2
                exit 1
              fi
              if (rehearse "$script"); then
                echo "FAIL: the rehearsal accepted mutant $1" >&2
                exit 1
              fi
              echo "ok: mutant $1 rejected"
            }

            rehearse ${rehearsedNotify.failed}
            mutant drop-append '>> "$log"'
            mutant drop-mode 'install -m 0644'
            touch "$out"
          '';
```

The mutants edit the subject, the `failed` script, never the assertions (S1 `review.md` F11).
The scenario is S1's crash loop unchanged; only the log expectations, the `umask` and the mutant runs are new.
This shell was rehearsed during planning with bash 5 against scratch renderings of Step 7's scripts: the real script passed all four expectations, `drop-append` failed at the first `expectLog` with an empty log, and `drop-mode` failed there with mode `600`.

- [ ] **Step 6: Run the rehearsal against today's `failed` script (RED, build)**

Run:

```bash
jj st --no-pager >/dev/null
nix build -L .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s3-evidence/2.3-rehearsal-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg 'FAIL|ok:|error:'
```

Expected: the build fails after `ok: crash, start, crash, start within the interval posts one pair` with `FAIL: one posted FAILED and one suppressed episode log one line; failed.log was:`, because no script writes `failed.log` yet, then `error: builder for '/nix/store/…-observability-notify-rehearsal.drv' failed with exit code 1`.

- [ ] **Step 7: Append each posted `FAILED` to `failed.log` (2.3)**

In `modules/nixos/observability-notify.nix`, in the `failed` script, replace

```nix
        ${pkgs.coreutils}/bin/mkdir -p "${stampDir}/last-failed"
        echo "$now" > "$last"
      '';
```

with

```nix
        ${pkgs.coreutils}/bin/mkdir -p "${stampDir}/last-failed"
        echo "$now" > "$last"
        # R9.1 counts these lines (design D9). The evaluator, a DynamicUser,
        # reads the log, so it is created world-readable.
        log="${stampDir}/failed.log"
        [ -e "$log" ] || ${pkgs.coreutils}/bin/install -m 0644 /dev/null "$log"
        printf '%s %s %s\n' "$now" "$unit" "${hostName}" >> "$log"
      '';
```

and replace the script's comment line `# writes no stamp, so the next failure posts again.` with:

```nix
      # writes no stamp, so the next failure posts again. Each posted FAILED
      # appends `<epoch> <unit> <host>` to failed.log; a suppressed episode
      # and a failed post append nothing.
```

The two mutant patterns of Step 5 (`>> "$log"` and `install -m 0644`) each match exactly one line of the rendered script.

- [ ] **Step 8: Run the rehearsal again (GREEN, build)**

Run:

```bash
jj st --no-pager >/dev/null
nix build -L .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s3-evidence/2.3-rehearsal-$(date -u +%Y%m%dT%H%M%SZ).log | rg 'FAIL|ok:|error:'
```

Expected: the build succeeds; the log shows `ok: crash, start, crash, start within the interval posts one pair`, `ok: one posted FAILED and one suppressed episode log one line`, `ok: a crash after the interval posts a new pair, once`, `ok: a second posted FAILED logs a second line, a repeated failure none`, then for `drop-append` the first `ok:` line, `FAIL: one posted FAILED and one suppressed episode log one line; failed.log was:` and `ok: mutant drop-append rejected`, then the same for `drop-mode` ending `ok: mutant drop-mode rejected`; no `error:` line.
The R3.1 clause `notifier is not the rehearsed observability-notify-failed script` still holds, because magnetite's template and `deployedNotify` are built from the one changed function.

- [ ] **Step 9: Show the token option does not exist yet (RED, evaluation)**

Run:

```bash
nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); in (f.nixosConfigurations.magnetite.extendModules { modules = [ { services.observability-notify.tokenFile = "/run/secrets/vars/shared/ntfy-alerter/token"; } ]; }).config.systemd.services."observability-notify@".serviceConfig' 2>&1 | tee logs/s3-evidence/2.4-token-option-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o "The option .services.observability-notify.tokenFile' does not exist"
```

Expected: ``The option `services.observability-notify.tokenFile' does not exist``.

- [ ] **Step 10: Add `tokenFile` and its wiring (2.4)**

In `modules/nixos/observability-notify.nix`:

1. Replace the header's last paragraph

```nix
# Hosts import this module directly or through the otel-collector agent role;
# the key makes a host doing both load it once. It reads no clan var: a host
# that sets services.observability-notify.tokenFile supplies the token's path.
```

with

```nix
# With services.observability-notify.tokenFile set, the template loads that
# file as the `alerter-token` credential and ntfy-send reads it through
# NTFY_TOKEN_FILE; the hooks run as root inside each notified unit, where the
# template's credential is not visible, so they pass the file's path itself
# (design D3). Each posted FAILED is also appended to failed.log (design D9).
#
# Hosts import this module directly or through the otel-collector agent role;
# the key makes a host doing both load it once. It reads no clan var: the host
# supplies the token's path.
```

2. Replace the `hook` binding

```nix
      hook = mode: "-+${notifyScripts.resolved} ${mode} %n";
```

with

```nix
      tokenEnv = lib.optionalString (
        cfg.tokenFile != null
      ) "${pkgs.coreutils}/bin/env NTFY_TOKEN_FILE=${cfg.tokenFile} ";
      hook = mode: "-+${tokenEnv}${notifyScripts.resolved} ${mode} %n";
```

3. Replace `options.services.observability-notify.units = lib.mkOption {` and its body through its closing `};` with:

```nix
      options.services.observability-notify = {
        units = lib.mkOption {
          type = lib.types.listOf lib.types.str;
          default = [ ];
          description = ''
            systemd.services attribute names (without `.service`) whose failure
            posts a notice to ntfy's fleet-alerts topic through
            observability-notify@.service, and whose next successful start or
            exit after a notice posts RESOLVED.
          '';
        };
        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = ''
            Path of the file holding the `alerter` ntfy token, or null to post
            anonymously. When set, observability-notify@.service loads it as
            the credential `alerter-token` and sets
            NTFY_TOKEN_FILE=%d/alerter-token, and the resolve hooks run under
            `env NTFY_TOKEN_FILE=<this path>`.
          '';
        };
      };
```

4. After the template's attribute set in `config.systemd.services`'s `lib.mkMerge` list (after the `{ "observability-notify@" = { … }; }` element), add:

```nix
        (lib.mkIf (cfg.tokenFile != null) {
          "observability-notify@" = {
            environment.NTFY_TOKEN_FILE = "%d/alerter-token";
            serviceConfig.LoadCredential = [ "alerter-token:${cfg.tokenFile}" ];
          };
        })
```

NixOS renders `environment` as `Environment="NTFY_TOKEN_FILE=%d/alerter-token"` (`nixos/lib/systemd-lib.nix:785` at the root pin), and systemd expands the `%d` specifier (the unit's credentials directory) in `Environment=`.
The hook carries the token's path on argv, never the token.

- [ ] **Step 11: Evaluate the wiring with and without a token (2.4, evaluation)**

Run:

```bash
{
  nix eval .#nixosConfigurations.magnetite.config.services.observability-notify.tokenFile
  nix eval --impure --json --expr 'let f = builtins.getFlake (toString ./.); c = (f.nixosConfigurations.magnetite.extendModules { modules = [ { services.observability-notify.tokenFile = "/run/secrets/vars/shared/ntfy-alerter/token"; } ]; }).config; t = c.systemd.services."observability-notify@"; s = c.systemd.services.greptimedb-schema.serviceConfig; in { credential = t.serviceConfig.LoadCredential; env = t.environment.NTFY_TOKEN_FILE; start = s.ExecStartPost; stop = s.ExecStopPost; }' | jq .
} 2>&1 | tee logs/s3-evidence/2.4-token-wiring-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `null`, then:

```json
{
  "credential": [ "alerter-token:/run/secrets/vars/shared/ntfy-alerter/token" ],
  "env": "%d/alerter-token",
  "start": [ "-+/nix/store/<hash>-coreutils-<version>/bin/env NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token /nix/store/<hash>-observability-notify-resolved start %n" ],
  "stop": [ "-+/nix/store/<hash>-coreutils-<version>/bin/env NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token /nix/store/<hash>-observability-notify-resolved stop %n" ]
}
```

with the same `observability-notify-resolved` store path in `start` and `stop`, and the same as magnetite's unmodified `ExecStartPost` in the baseline.

- [ ] **Step 12: Show R3.1 rejects the token-bearing hooks as unwired (RED, evaluation)**

Run R3.1's `failures` (exposed as the check's `passthru.failures`) over magnetite extended with a token:

```bash
cat > /tmp/2.4-r31-token.expr <<'EOF'
let
  flake = builtins.getFlake (toString ./.);
  c =
    (flake.nixosConfigurations.magnetite.extendModules {
      modules = [ { services.observability-notify.tokenFile = "/run/secrets/vars/shared/ntfy-alerter/token"; } ];
    }).config;
in
flake.checks.x86_64-linux.otel-collector-config.passthru.failures {
  settings = c.services.opentelemetry-collector.settings;
  overrides = c.services.opentelemetry-collector.validateConfigOverrides;
  collectorService = c.systemd.services.opentelemetry-collector.serviceConfig;
  node = c.services.prometheus.exporters.node;
  services = c.systemd.services;
  notifyUnits = c.services.observability-notify.units;
  schema = flake.lib.otelCollectorSchema;
  storeVersion = c.services.greptimedb.package.version;
  notifierInterval =
    c.systemd.services."observability-notify@".environment.OBSERVABILITY_NOTIFY_MIN_INTERVAL_SEC or null;
}
EOF
nix eval --impure --json --expr "$(cat /tmp/2.4-r31-token.expr)" 2>&1 | tee logs/s3-evidence/2.4-r31-token-red-$(date -u +%Y%m%dT%H%M%SZ).log
```

The expression is passed inline with `--expr`, so `./.` resolves against the working directory: run it from the repository root.
`import /tmp/…` would not work, because `./.` inside an imported file names that file's directory (`/tmp`).
The same expression with `modules = [ ]` evaluated to `[]` on `main` at planning time, which confirms the input construction and the `passthru.failures` access.
The input is `otel-collector-config.nix:72-84`'s `input`, built from the extended configuration.
Expected: `["R3.1: a named unit is not wired to the notifier","R3.1: a notified unit lacks the start-time RESOLVED hook sharing its stop hook's script"]`, because `resolvedHook` (`:70`) matches only `-+<script> <mode> %n`; Task 4 sets magnetite's `tokenFile`, so without the next step its pull request would fail R3.1.

- [ ] **Step 13: Let R3.1 accept the `env NTFY_TOKEN_FILE=` prefix**

In `modules/checks/otel-collector-config.nix`, replace `:70`

```nix
      resolvedHook = mode: "-\\+(/nix/store/[a-z0-9]{32}-observability-notify-resolved) ${mode} %n";
```

with

```nix
      # A notified unit's hook; with services.observability-notify.tokenFile
      # set it runs under `env NTFY_TOKEN_FILE=<path>`. The last capture is
      # the script.
      resolvedHook =
        mode:
        "-\\+(/nix/store/[a-z0-9]{32}-coreutils-[^/ ]+/bin/env NTFY_TOKEN_FILE=[^ ]+ )?(/nix/store/[a-z0-9]{32}-observability-notify-resolved) ${mode} %n";
```

and replace `hookScripts` (`:186-190`)

```nix
          hookScripts =
            mode: hooks:
            lib.unique (
              lib.concatMap (hook: lib.toList (builtins.match (resolvedHook mode) hook)) (lib.toList hooks)
            );
```

with

```nix
          hookScripts =
            mode: hooks:
            lib.unique (
              lib.concatMap (
                hook:
                let
                  m = builtins.match (resolvedHook mode) hook;
                in
                lib.optional (m != null) (lib.last m)
              ) (lib.toList hooks)
            );
```

`unitWired` (`:183`) and the `startHookDropped` mutant (`:389`) only test whether `resolvedHook` matches, so they need no change; `oneshotStartHookOtherScript` (`:402`) still differs in its script and is still rejected.

- [ ] **Step 14: R3.1 accepts the token-bearing hooks and the check still passes (GREEN, evaluation and build)**

Run:

```bash
jj st --no-pager >/dev/null
nix eval --impure --json --expr "$(cat /tmp/2.4-r31-token.expr)" 2>&1 | tee logs/s3-evidence/2.4-r31-token-$(date -u +%Y%m%dT%H%M%SZ).log
nix build -L .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s3-evidence/2.4-otel-collector-config-$(date -u +%Y%m%dT%H%M%SZ).log | rg 'FAIL|ok:|error:'
```

Expected: `[]`; then the build succeeds with Step 8's `ok:` lines, including both mutants rejected, and no `error:` line, which also shows every existing R3.1 mutant still rejected (the check's second `assert`).

- [ ] **Step 15: Diff magnetite against the baseline (2.2 and 2.4, evaluation)**

Run:

```bash
ts=$(date -u +%Y%m%dT%H%M%SZ)
nix eval --json .#nixosConfigurations.magnetite.config --apply 'c: let names = [ "observability-notify@" "opentelemetry-collector" "greptimedb" "greptimedb-envelope" "greptimedb-schema" ] ++ c.services.observability-notify.units; in builtins.listToAttrs (map (n: { name = n; value = { inherit (c.systemd.services.${n}) unitConfig serviceConfig environment; }; }) names)' | jq -S . > logs/s3-evidence/2.4-notifier-final-$ts.json
{
  diff "$baseline" logs/s3-evidence/2.4-notifier-final-$ts.json
  rg -c 'LoadCredential.*alerter-token|NTFY_TOKEN_FILE' logs/s3-evidence/2.4-notifier-final-$ts.json || echo no-token-wiring
} 2>&1 | tee logs/s3-evidence/2.4-notifier-diff-$ts.log
```

Expected: `diff` prints exactly one changed line, in `observability-notify@`'s `serviceConfig`: `"ExecStart": "/nix/store/<old hash>-observability-notify-failed %i"` becomes `"ExecStart": "/nix/store/<new hash>-observability-notify-failed %i"`, the `failed.log` append; then `no-token-wiring`.
Every hook string, `OnFailure` and the template's environment are unchanged, so nothing magnetite deploys changes before cutover deploy 1.

- [ ] **Step 16: Update the collector README (2.5)**

In `modules/clan/services/otel-collector/README.md`:

1. Replace line 3 with:

```markdown
This clan service collects fleet metrics into the GreptimeDB telemetry store, and its `agent` role imports the failure notifier that posts unit failures to ntfy.
```

2. Replace line 79 (`The notifier holds no credential, because ntfy on cinnabar has no authentication.`) with:

```markdown
The notifier reads no clan var itself; a host passes the path of the `alerter` ntfy token through `services.observability-notify.tokenFile` (see Failure notifier).
```

3. Replace lines 98-100 (from `The agent role owns` through `in \`modules/machines/nixos/magnetite/default.nix\`.`) with:

```markdown
The notifier lives in `modules/nixos/observability-notify.nix` as `flake.modules.nixos.observability-notify`, which the `agent` role imports; a host without the role imports it directly.
It defines `observability-notify@.service` and the options `services.observability-notify.units` and `services.observability-notify.tokenFile`.
Entries in `units` are `systemd.services` attribute names without `.service`.
The agent lists `opentelemetry-collector` itself, and magnetite lists the store units and its ZFS oneshots in `modules/machines/nixos/magnetite/default.nix`.
```

4. Replace line 114 (`S3's alert evaluator reads these stamps for the R9.1 FIRING budget, and it must count only stamps containing \`posted\`.`) with:

```markdown
For each posted `FAILED` the notifier appends one line `<epoch> <unit> <host>` to `/var/lib/observability-notify/failed.log`, which it creates with mode `0644` so the alert evaluator, a `DynamicUser`, can read it; a suppressed episode and a failed post append nothing.
The evaluator counts that log's lines from the last 24 hours, together with its own `FIRING` posts, for the R9.1 budget; the log is not rotated, and the 15-minute interval bounds its growth.

`services.observability-notify.tokenFile` (default `null`) names the file holding the `alerter` ntfy token.
When it is set, the template loads the file as the credential `alerter-token` with `NTFY_TOKEN_FILE=%d/alerter-token`, and both hooks run the script under `env NTFY_TOKEN_FILE=<tokenFile>`, because they run inside each notified unit and cannot see the template's credential.
`ntfy-send` sends the token as an `Authorization: Bearer` header on curl's stdin, never on a command line.
With `tokenFile` unset the notifier posts anonymously, which ntfy refuses on `fleet-*` topics once cinnabar's access entries are in force.
```

5. Replace line 126 (`- The notifier lives in the agent role, so a host's ZFS and store notices depend on its membership in that role.`) with:

```markdown
- A host's ZFS and store notices depend on its importing `observability-notify`, through the `agent` role or directly; the module's key `vanixiets#observability-notify` makes a host doing both load it once.
```

6. Replace line 139 with:

```markdown
Its build runs `observability-notify-rehearsal`, which drives the notifier scripts through a crash loop against a recording `ntfy-send`, requires one pair per interval and one `failed.log` line, mode `0644`, per posted `FAILED`, and rejects two mutants of the `failed` script, one without the append and one without the mode.
```

Run:

```bash
rg -n "observability-notify.nix|failed.log|tokenFile" modules/clan/services/otel-collector/README.md
rg -n "holds no credential|reads these stamps" modules/clan/services/otel-collector/README.md || echo none
```

Expected: the first command lists lines containing each of `observability-notify.nix`, `failed.log` and `tokenFile`; the second prints `none`.

- [ ] **Step 17: Build magnetite and record the check's evaluation cost (build, evaluation)**

Run:

```bash
nix build .#checks.x86_64-linux.nixos-magnetite 2>&1 | tee logs/s3-evidence/2.2-nixos-magnetite-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 5
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/2.3-otel-collector-config-stats.json \
  nix eval --raw '.#.checks.x86_64-linux.otel-collector-config.drvPath'; echo
jq '{bytes: .gc.totalBytes, cpu: .cpuTime}' /tmp/2.3-otel-collector-config-stats.json 2>&1 | tee logs/s3-evidence/2.3-otel-collector-config-cost-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the build succeeds; then a `/nix/store/…-otel-collector-config.drv` path and `bytes`, which is recorded, not judged, because `otel-collector-config` is S1's check extended by one derivation's text, and `bytes` should be within a few MiB of the same measurement at `main@origin` (run it there for comparison and record both); a growth above 0.5 GiB is reported instead of committed.

- [ ] **Step 18: Format**

Run:

```bash
{
  nix fmt -- modules/nixos/observability-notify.nix modules/clan/services/otel-collector/flake-module.nix modules/checks/otel-collector-config.nix modules/clan/services/otel-collector/README.md
  nix fmt -- --fail-on-change && echo fmt-clean
} 2>&1 | tee logs/s3-evidence/2.6-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the last line is `fmt-clean`.
If the first command reformatted a `.nix` file, rerun Step 14's build before committing.

- [ ] **Step 19: Tick 2.1–2.5**

In `openspec/changes/stand-up-fleet-alerting/tasks.md`, change the leading `- [ ]` of the lines beginning `- [ ] 2.1` through `- [ ] 2.5` (lines 16–20) to `- [x]`, and nothing else; 2.6 is ticked by the orchestrator when nixbot reports the pull request green.
Run: `jj diff --git -- openspec/changes/stand-up-fleet-alerting/tasks.md | grep -c '^+- \[x\]'`
Expected: `5`.

- [ ] **Step 20: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'refactor(observability-notify): extract the failure notifier with a FAILED log and an alerter token option'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"refactor(observability-notify): extract the failure notifier")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/nixos/observability-notify.nix \
  modules/clan/services/otel-collector/flake-module.nix \
  modules/clan/services/otel-collector/README.md \
  modules/checks/otel-collector-config.nix \
  openspec/changes/stand-up-fleet-alerting/tasks.md
jj diff --no-pager --summary -r "$change"
```

Expected: `A modules/nixos/observability-notify.nix` and `M` for the other four paths, and nothing else.
If `tasks.md` carried hunks other than the five ticks before the squash, squash it with `--interactive` and select only the ticks.
The orchestrator rebases the development join onto this change (after Task 1's merge), pushes it, opens pull request 2 and enqueues it; it lands through the merge queue before Task 3's pull request is enqueued.
No host sets `tokenFile` in this pull request, so no deployed post changes before cutover deploy 1.

---

### Task 3: `ntfy-alerter` provisioning and cinnabar proxy settings (cutover C1)

Implements `tasks.md` 3.1–3.7 (design D1, D5 step 1, D6, D17 as amended to option C; FAI `ntfy grants the fleet topics to alerter through declarative provisioning`, FAI `ntfy counts each mesh client as its own visitor`, FAI `The alerter token travels only as a file`).
The check is written first and fails at evaluation, then the shared token generator, cinnabar's per-machine env generator and the D1 settings make it pass.
No access entry is added here; `auth-access` arrives in Task 5 (C3), so every existing anonymous publisher keeps working after C1.

Vendor facts this task rests on, read for this plan at the pins (each re-read in Steps 1 and 2 as evidence):
- ntfy 2.28.0 (`nix eval --raw .#nixosConfigurations.cinnabar.config.services.ntfy-sh.package.version` prints `2.28.0`), source at `binwiederhier/ntfy@v2.28.0`:
  - `ntfy token generate` prints `user.GenerateToken()`, `tk_` plus 29 lowercase alphanumerics (`cmd/token.go:76-83,224-227`; `user/util.go:73-75`; `user/manager.go:32-33`).
  - `ntfy user hash` reads the password and its confirmation from stdin, one line each, when stdin is not a TTY, and prints a bcrypt hash at cost 10 on stdout; prompts go to stderr (`cmd/user.go:173-187,396-407,483-500`; `util/util.go:301-331`; `user/manager.go:42`).
    Both were run with the pinned aarch64-darwin build (`/nix/store/g161v3w84a14mx0i9iry5l83vmpncyzv-ntfy-sh-2.28.0`): `ntfy token generate` printed a `tk_` token of 32 characters; `printf '%s\n%s\n' pw pw | ntfy user hash` exited 0 and printed one `$2a$10$…` line of 60 characters.
  - Without `-c`, `ntfy user`/`ntfy token` skip a missing `/etc/ntfy/server.yml` (`cmd/config_loader.go:14-21`), so both run in the build sandbox and in clan's generator sandbox.
  - Provisioning parse: `auth-users` entries `name:hash:role` with exactly three `:` fields and `ValidPasswordHash(hash, 10)` (`cmd/serve.go:620-645`); `auth-tokens` entries `user:token[:label]`, user provisioned, `ValidToken` (`cmd/serve.go:690-720`); `auth-access` users must be `*`/`everyone` or provisioned (`cmd/serve.go:647-668`; `cmd/access.go:18`).
  - `ValidPasswordHash`: prefix `$2a$`, `$2b$` or `$2y$`, then `bcrypt.Cost` must parse, then cost ≥ 10 (`user/util.go:52-65`); `golang.org/x/crypto` v0.55.0 (ntfy's `go.mod`) requires at least 59 bytes, a two-digit cost in 4..31 and a 22-character salt (`bcrypt/bcrypt.go:22-24,57-63,168-190,282-300`); `GenerateFromPassword` emits exactly 60 bytes, so the check's shape is `\$2[aby]\$[0-9]{2}\$[./A-Za-z0-9]{53}`.
  - `behind-proxy` with the default `proxy-forwarded-header = X-Forwarded-For` (`cmd/serve.go:107-109,389-390`); `proxy-trusted-hosts` is a comma-separated string, each entry a CIDR or a host passed through `net.LookupHost`, which returns an IP literal unchanged (`cmd/serve.go:230,454-460,595-618`); the right-most untrusted address of the header is the visitor, falling back to the TCP peer when the header is absent (`server/util.go:86-141`).
  - `visitor-prefix-bits-ipv6` defaults to 64 and accepts 1..128 (`server/config.go:110`; `cmd/serve.go:102,393-394`); a visitor's id is `ip:<address masked to that prefix>` (`server/visitor.go:555-565`).
  - Logging: 401 and 403 are `normalErrorCodes` (`server/log.go:37`), logged by `handleError` only at `debug` as `Connection closed with HTTP <code> (ntfy error <code>)` with the visitor's fields `visitor_id` and `visitor_ip` (`server/server.go:516-545`; `server/visitor.go:149-160`); request headers, including `Authorization`, are rendered only at `trace` (`server/server.go:500-501`; `server/log.go:100-107`), so `debug` writes no token to the journal.
- caddy 2.11.7 (`nix eval --raw .#nixosConfigurations.cinnabar.config.services.caddy.package.src.rev` prints `refs/tags/v2.11.7`): every `reverse_proxy` calls `addForwardedHeaders`, which, for a client that is not a trusted proxy (none is configured), replaces any incoming `X-Forwarded-For` with the TCP peer's address (`modules/caddyhttp/reverseproxy/reverseproxy.go:142-155,908-912,929-994` at `v2.11.7`).
  cinnabar's `ntfy.zt` vhost (`modules/machines/nixos/cinnabar/caddy.nix:29-35`) sets no `header_up` and no `trusted_proxies`, unlike `hermes.zt` (`:76-79`), so ntfy receives each mesh client's own address in `X-Forwarded-For`.
- systemd 261.3 (`nix eval --raw .#nixosConfigurations.cinnabar.config.systemd.package.version`): in an `EnvironmentFile=` an unquoted value is parsed with POSIX-shell backslash rules only and `$` is not expanded (`man/systemd.exec.xml:3256-3284` at `v261.3`), so a value made only of `[-_.:/$A-Za-z0-9]` reaches ntfy byte for byte.
- clan-core (the flake's `clan-core` input): a shared generator whose files' `secret`/`deploy`/`neededFor` differ between machines is rejected (`pkgs/clan-cli/clan_lib/vars/generator.py:106-116,270-297`; `clan_lib/nix_selectors.py:197-199`), which is why `ntfy-env` lives in a per-machine generator; a dependency's file `f` of generator `g` is `$in/g/f` (`nixosModules/clanCore/vars/interface.nix:114`); `finalScript` is `set -euo pipefail`, `PATH` from `runtimeInputs` plus coreutils, then the script (`modules/clan/export-modules/generic-generator.nix:325-360`); file `mode` defaults to `0400` (`:170-173`).

**Files:**
- Create: `modules/checks/ntfy-provisioning.nix`
- Create: `modules/nixos/ntfy-alerter.nix`
- Modify: `modules/machines/nixos/cinnabar/default.nix:26-31` (import `ntfy-alerter`)
- Modify: `modules/machines/nixos/cinnabar/ntfy.nix` (whole file: the `ntfy-alerter-env` generator, `environmentFile`, the D1 settings and the cutover `log-level`)
- Create (by `clan vars generate`, Step 15): `vars/shared/ntfy-alerter/token/`, `vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env/`
- Modify: `openspec/changes/stand-up-fleet-alerting/tasks.md` (tick 3.1–3.4 and 3.6)
- Evidence (git-ignored): `logs/s3-evidence/3.1-ntfy-logging-*.log`, `logs/s3-evidence/3-caddy-xff-*.log`, `logs/s3-evidence/3.4-*.log`, `logs/s3-evidence/3.3-*.log`, `logs/s3-evidence/3.6-*.log`, `logs/s3-evidence/3-fmt-*.log`

**Interfaces:**
- Consumes (Task 1): nothing at evaluation time; C1's 7.1 token probe runs `ntfy-send` with `NTFY_TOKEN_FILE` on cinnabar, which needs Task 1 merged before deploy C1.
- Consumes (Task 7): Task 7 Step 0's deploy procedure and its pre-C1 baseline step (Step 21 here).
- Produces:
  - `flake.modules.nixos.ntfy-alerter` at `modules/nixos/ntfy-alerter.nix`, no options; it declares the shared generator `clan.core.vars.generators.ntfy-alerter` (`share = true`, `runtimeInputs = [ pkgs.ntfy-sh ]`) with one secret file `token` (`mode = "0400"`, deployed on every machine that imports the module, content `tk_` plus 29 characters with no trailing newline).
    Hosts read its path as `config.clan.core.vars.generators.ntfy-alerter.files.token.path`, which evaluates to `/run/secrets/vars/shared/ntfy-alerter/token` (Step 11); magnetite (Task 4) imports only this module; cinnabar (this task) imports it and declares the env generator.
  - Per-machine generator `ntfy-alerter-env` on cinnabar only, declared in `modules/machines/nixos/cinnabar/ntfy.nix`: `dependencies = [ "ntfy-alerter" ]`, `runtimeInputs = [ pkgs.ntfy-sh pkgs.openssl ]`, one secret file `ntfy-env` (`mode = "0400"`, `restartUnits = [ "ntfy-sh.service" ]`) holding exactly two lines, `NTFY_AUTH_USERS=alerter:<bcrypt hash>:user` and `NTFY_AUTH_TOKENS=alerter:<token>`, the token read from `$in/ntfy-alerter/token`; the password is random and discarded after hashing, so `alerter` authenticates only by token.
    Path `config.clan.core.vars.generators.ntfy-alerter-env.files.ntfy-env.path`, evaluating to `/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env` (Step 11).
  - cinnabar `services.ntfy-sh`: `environmentFile` = that path; `settings.behind-proxy = true`, `settings.proxy-trusted-hosts = "::1"`, `settings.visitor-prefix-bits-ipv6 = 128`, `settings.log-level = "debug"` (removed by the 7.4 revert PR); no `auth-access`, no `auth-default-access`, no `visitor-request-limit-exempt-hosts`.
    Task 5 adds `settings.auth-access = [ "alerter:fleet-*:rw" "*:fleet-*:ro" ];` to the same `settings` attrset in `modules/machines/nixos/cinnabar/ntfy.nix`.
  - `checks.x86_64-linux.ntfy-provisioning` at `modules/checks/ntfy-provisioning.nix`: runs both generators' `finalScript` in the sandbox and judges their output against ntfy 2.28.0's parse rules and cinnabar's evaluated `services.ntfy-sh.settings.auth-access or [ ]`; its access clause is vacuous until Task 5 adds entries, and its `alertr` mutant is appended to whatever entries exist, so it bites before and after Task 5.
  - Shared vars recipients: after Step 15 the shared `token` is encrypted for cinnabar only.
    Task 4, after importing the module on magnetite, runs `CLAN_NO_COMMIT=1 clan vars fix magnetite --generator ntfy-alerter`, which adds magnetite's age key to the existing shared secret without regenerating its value (clan-core `sops.py:446-450`, `allow_member`); `clan vars generate magnetite --generator ntfy-alerter` regenerates it instead (`logs/s3-evidence/4.8-vars-magnetite-20261018T073644Z.log`). It verifies with `clan vars check magnetite`; its evidence is `jj diff --name-only -- vars/` listing only `vars/shared/ntfy-alerter/token/secret`, with `vars/per-machine/cinnabar/ntfy-alerter-env/` untouched; a regenerated token would leave cinnabar's provisioned token stale and every magnetite post would get 401.
    Its evidence is `jj diff --name-only -- vars/` listing magnetite's recipient entry `vars/shared/ntfy-alerter/token/machines/magnetite` (plus `token/secret` only if sops rewrites its recipient metadata), with `vars/per-machine/cinnabar/ntfy-alerter-env/` untouched; a regenerated token would leave cinnabar's provisioned token stale and every magnetite post would get 401.

- [ ] **Step 1: Record ntfy 2.28.0's logging of 401 and 403 (tasks.md 3.1)**

Run:

```bash
mkdir -p logs/s3-evidence
f="logs/s3-evidence/3.1-ntfy-logging-$(date -u +%Y%m%dT%H%M%SZ).log"
src() { gh api "repos/binwiederhier/ntfy/contents/$1?ref=v2.28.0" --jq .content | base64 --decode; }
{
  echo '== server/log.go:37 @ v2.28.0'
  src server/log.go | sed -n '37p'
  echo '== server/server.go:516-545 @ v2.28.0 (handleError)'
  src server/server.go | sed -n '516,545p'
  echo '== server/server.go:500-501 @ v2.28.0 (headers rendered only at trace)'
  src server/server.go | sed -n '500,501p'
  echo '== server/log.go:100-107 @ v2.28.0 (renderHTTPRequest)'
  src server/log.go | sed -n '100,107p'
  echo '== server/visitor.go:155-160 and 555-565 @ v2.28.0 (visitor fields)'
  src server/visitor.go | sed -n '155,160p;555,565p'
  echo '== conclusion'
  echo '401 and 403 are normalErrorCodes and are logged only at log-level debug, as "Connection closed with HTTP <code> (ntfy error <code>)";'
  echo 'the visitor is carried by fields visitor_id (ip:<address masked to visitor-prefix-bits>) and visitor_ip;'
  echo 'Authorization headers appear only at trace, so debug is set for the cutover window and trace is not.'
} 2>&1 | tee "$f"
```

Expected: line 37 lists `http.StatusUnauthorized, http.StatusForbidden` inside `normalErrorCodes`; the `handleError` excerpt shows `if isNormalError {` followed by `ev.Debug("Connection closed with HTTP %d (ntfy error %d)", …)`; the visitor excerpt shows `"visitor_id":` and `"visitor_ip":`; and the excerpt at 500-501 shows `if ev.IsTrace() {` around `renderHTTPRequest(r)`.
If any excerpt differs (in particular if 401 or 403 is not in `normalErrorCodes`), stop and report it: Step 7's `log-level = "debug"` is conditional on this finding (tasks.md 3.3).

- [ ] **Step 2: Record that caddy forwards each mesh client's address (D1 premise)**

Run:

```bash
f="logs/s3-evidence/3-caddy-xff-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo "== caddy package rev at the root pin"
  nix eval --raw .#nixosConfigurations.cinnabar.config.services.caddy.package.src.rev; echo
  echo '== modules/caddyhttp/reverseproxy/reverseproxy.go:908-912 and 929-994 @ v2.11.7'
  gh api 'repos/caddyserver/caddy/contents/modules/caddyhttp/reverseproxy/reverseproxy.go?ref=v2.11.7' --jq .content | base64 --decode | sed -n '908,912p;929,994p'
  echo '== cinnabar ntfy.zt vhost'
  sed -n '29,35p' modules/machines/nixos/cinnabar/caddy.nix
} 2>&1 | tee "$f"
```

Expected: the rev line is `refs/tags/v2.11.7`; the excerpt shows `err = h.addForwardedHeaders(req)` and, at its end, `} else if clientIP != "" {` followed by `req.Header.Set("X-Forwarded-For", clientIP)`; the vhost block is `tls internal` and `reverse_proxy [::1]:2586` with no `header_up` line.

- [ ] **Step 3: Write the failing provisioning check**

Create `modules/checks/ntfy-provisioning.nix` with exactly this content:

```nix
# Evaluation-time regulator for ntfy's declarative provisioning on cinnabar
# (design D6). A rejected environmentFile stops ntfy for every publisher, not
# only alerts, so the generators' rendered strings are judged before deploy.
#
# The check runs cinnabar's ntfy-alerter and ntfy-alerter-env generators in
# the build sandbox exactly as clan does (finalScript: PATH from runtimeInputs
# plus coreutils, then the script) and judges what they write against the
# parse rules of the pinned ntfy 2.28.0, read at binwiederhier/ntfy@v2.28.0:
#   - token: ^tk_[-_A-Za-z0-9]{29}$ (user/util.go:24, ValidToken);
#   - NTFY_AUTH_USERS: name:hash:role, three fields (cmd/serve.go:620-645),
#     hash accepted by ValidPasswordHash(hash, 10) (user/util.go:52-65): a
#     $2a$/$2b$/$2y$ prefix, a two-digit cost from 10 to 31, and the 53
#     bcrypt characters GenerateFromPassword emits (golang.org/x/crypto
#     v0.55.0 bcrypt/bcrypt.go:57-63,168-190,282-300);
#   - NTFY_AUTH_TOKENS: user:token, user provisioned (cmd/serve.go:690-720),
#     carrying the same token the publishers read from the token file;
#   - auth-access: every user is * or everyone or provisioned
#     (cmd/serve.go:647-668, cmd/access.go:18).
# The patterns admit no backslash, quote or whitespace, so systemd reads each
# unquoted EnvironmentFile value byte for byte (systemd.exec(5) at v261.3).
# The access clause relates cinnabar's evaluated settings to the users the
# generator provisions, two independently written values.
#
# Mutants edit the subjects, never the validator (S1 review.md F11): a token
# generator emitting tk_ plus 28 characters, an env generator writing the
# unhashed password, and an auth-access entry naming alertr. Each must be
# rejected, or the build fails.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      cinnabar = self.nixosConfigurations.cinnabar.config;
      tokenGenerator = cinnabar.clan.core.vars.generators.ntfy-alerter;
      envGenerator = cinnabar.clan.core.vars.generators.ntfy-alerter-env;
      accessEntries = cinnabar.services.ntfy-sh.settings.auth-access or [ ];

      # A mutant generator: the generator's own script with one line replaced,
      # wrapped the way clan's finalScript wraps it. A replacement that
      # matches nothing is an evaluation error, not a silently equal mutant.
      mutantGenerator =
        name: generator: from: to:
        let
          script = builtins.replaceStrings [ from ] [ to ] generator.script;
        in
        assert lib.assertMsg (
          script != generator.script
        ) "ntfy-provisioning: mutant ${name} matched nothing in its generator's script";
        pkgs.writeScript "ntfy-provisioning-${name}" ''
          set -euo pipefail
          PATH=${lib.makeBinPath (generator.runtimeInputs ++ [ pkgs.coreutils ])}
          ${script}
        '';

      shortTokenGenerator =
        mutantGenerator "short-token" tokenGenerator ''token="$(ntfy token generate)"''
          ''token="$(ntfy token generate | cut -c 1-31)"'';
      unhashedEnvGenerator =
        mutantGenerator "unhashed-password" envGenerator
          ''hash="$(printf '%s\n%s\n' "$password" "$password" | ntfy user hash)"''
          ''hash="$password"'';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        ntfy-provisioning = pkgs.runCommand "ntfy-provisioning" { } ''
          token_re='^tk_[-_A-Za-z0-9]{29}$'
          users_re='^NTFY_AUTH_USERS=alerter:\$2[aby]\$([0-9]{2})\$[./A-Za-z0-9]{53}:user$'

          # $1: token file, $2: ntfy-env file.
          valid_provisioning() {
            local token users cost
            token="$(cat "$1")"
            if ! [[ $token =~ $token_re ]]; then
              echo "ntfy-provisioning: the token does not match ^tk_[-_A-Za-z0-9]{29}\$ (user/util.go:24)" >&2
              return 1
            fi
            if [ "$(wc -l < "$2")" -ne 2 ]; then
              echo "ntfy-provisioning: ntfy-env must hold exactly the NTFY_AUTH_USERS and NTFY_AUTH_TOKENS lines" >&2
              return 1
            fi
            users="$(sed -n 1p "$2")"
            if ! [[ $users =~ $users_re ]]; then
              echo "ntfy-provisioning: line 1 is not NTFY_AUTH_USERS=alerter:<bcrypt hash>:user (cmd/serve.go:620-645, user/util.go:52-65)" >&2
              return 1
            fi
            cost=$((10#''${BASH_REMATCH[1]}))
            if [ "$cost" -lt 10 ] || [ "$cost" -gt 31 ]; then
              echo "ntfy-provisioning: bcrypt cost $cost is outside 10..31 (user/util.go:58-63)" >&2
              return 1
            fi
            if [ "$(sed -n 2p "$2")" != "NTFY_AUTH_TOKENS=alerter:$token" ]; then
              echo "ntfy-provisioning: line 2 is not NTFY_AUTH_TOKENS=alerter:<the token file's token> (cmd/serve.go:690-720)" >&2
              return 1
            fi
          }

          # $1: ntfy-env file; the rest: auth-access entries.
          valid_access() {
            local env="$1" entry user provisioned
            shift
            provisioned="$(sed -n 's/^NTFY_AUTH_USERS=//p' "$env" | tr ',' '\n' | cut -d ':' -f 1)"
            for entry in "$@"; do
              user="''${entry%%:*}"
              case "$user" in
                '*' | everyone) continue ;;
              esac
              if ! grep -qxF -- "$user" <<< "$provisioned"; then
                echo "ntfy-provisioning: auth-access entry $entry names $user, who is not provisioned (cmd/serve.go:647-668)" >&2
                return 1
              fi
            done
          }

          expect_rejected() {
            local name="$1"
            shift
            if "$@"; then
              echo "ntfy-provisioning: mutant $name was accepted" >&2
              exit 1
            fi
            echo "ntfy-provisioning: mutant $name rejected"
          }

          # The real generators, run as clan runs them.
          real="$TMPDIR/real"
          mkdir -p "$real/ntfy-alerter" "$real/ntfy-alerter-env"
          out="$real/ntfy-alerter" bash ${tokenGenerator.finalScript}
          in="$real" out="$real/ntfy-alerter-env" bash ${envGenerator.finalScript}
          valid_provisioning "$real/ntfy-alerter/token" "$real/ntfy-alerter-env/ntfy-env" || exit 1
          valid_access "$real/ntfy-alerter-env/ntfy-env" ${lib.escapeShellArgs accessEntries} || exit 1
          echo "ntfy-provisioning: generators and cinnabar's ${toString (builtins.length accessEntries)} auth-access entries accepted"

          # Mutant: tk_ plus 28 characters.
          short="$TMPDIR/short-token"
          mkdir -p "$short/ntfy-alerter" "$short/ntfy-alerter-env"
          out="$short/ntfy-alerter" bash ${shortTokenGenerator}
          in="$short" out="$short/ntfy-alerter-env" bash ${envGenerator.finalScript}
          expect_rejected short-token valid_provisioning "$short/ntfy-alerter/token" "$short/ntfy-alerter-env/ntfy-env"

          # Mutant: the password written where its hash belongs.
          unhashed="$TMPDIR/unhashed-password"
          mkdir -p "$unhashed/ntfy-alerter-env"
          cp -r "$real/ntfy-alerter" "$unhashed/ntfy-alerter"
          in="$unhashed" out="$unhashed/ntfy-alerter-env" bash ${unhashedEnvGenerator}
          expect_rejected unhashed-password valid_provisioning "$unhashed/ntfy-alerter/token" "$unhashed/ntfy-alerter-env/ntfy-env"

          # Mutant: an access entry naming a user nobody provisions.
          expect_rejected access-user-alertr valid_access "$real/ntfy-alerter-env/ntfy-env" ${
            lib.escapeShellArgs (accessEntries ++ [ "alertr:fleet-*:rw" ])
          }

          touch "$out"
        '';
      };
    };
}
```

- [ ] **Step 4: Run the check and watch it fail**

Run: `jj st --no-pager >/dev/null && nix build .#checks.x86_64-linux.ntfy-provisioning -L 2>&1 | tee logs/s3-evidence/3.4-red-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: FAIL at evaluation with `error: attribute 'ntfy-alerter' missing`, pointing at `tokenGenerator` in `modules/checks/ntfy-provisioning.nix`; no generator exists on cinnabar yet.

- [ ] **Step 5: Write the shared token generator module**

Create `modules/nixos/ntfy-alerter.nix` with exactly this content:

```nix
# The alerter's ntfy access token, a shared clan vars generator (design D17).
#
# Shared, so it is generated once and every machine that imports this module
# deploys the same token (clan-core nixosModules/clanCore/vars/interface.nix:
# 90-100); one module is the single definition, because two copies of a
# shared script can drift. Every fleet-* publisher reads the token by path,
# config.clan.core.vars.generators.ntfy-alerter.files.token.path, through
# LoadCredential or NTFY_TOKEN_FILE, never on a command line.
#
# The ntfy server's provisioning file is a separate per-machine generator,
# ntfy-alerter-env in modules/machines/nixos/cinnabar/ntfy.nix, which depends
# on this one: pinned clan rejects a shared generator whose files' deploy
# differs between machines (clan_lib/vars/generator.py:270-297), and only
# cinnabar may hold that file. checks.x86_64-linux.ntfy-provisioning runs
# both scripts and judges their output.
{ ... }:
{
  flake.modules.nixos.ntfy-alerter =
    { pkgs, ... }:
    {
      # `ntfy token generate` prints tk_ plus 29 characters (ntfy 2.28.0
      # cmd/token.go:224-227); printf '%s' writes it without a newline.
      clan.core.vars.generators.ntfy-alerter = {
        share = true;
        files.token.mode = "0400";
        runtimeInputs = [ pkgs.ntfy-sh ];
        script = ''
          token="$(ntfy token generate)"
          printf '%s' "$token" > "$out/token"
        '';
      };
    };
}
```

- [ ] **Step 6: Import it on cinnabar**

In `modules/machines/nixos/cinnabar/default.nix`, replace lines 26-31:

```nix
      ++ (with flakeModules; [
        base
        hm-sops-bridge
        kvm-declaration
        ssh-known-hosts
      ]);
```

with:

```nix
      ++ (with flakeModules; [
        base
        hm-sops-bridge
        kvm-declaration
        ntfy-alerter
        ssh-known-hosts
      ]);
```

- [ ] **Step 7: Write cinnabar's ntfy settings and the env generator**

Replace the whole of `modules/machines/nixos/cinnabar/ntfy.nix` with exactly this content:

```nix
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, pkgs, ... }:
    {
      # ntfy's provisioning of the alerter user and its token (design D5,
      # D17). Depends on the shared ntfy-alerter token; the password is
      # random and discarded after hashing, so alerter authenticates by token
      # only. `ntfy user hash` reads the password and its confirmation from
      # stdin (ntfy 2.28.0 cmd/user.go:396-407,483-500). Removing a user from
      # this file deletes it and its token at ntfy's next start, so rollback
      # reverts magnetite's token-bearing posts first (design Migration Plan).
      # checks.x86_64-linux.ntfy-provisioning judges the rendered lines.
      clan.core.vars.generators.ntfy-alerter-env = {
        dependencies = [ "ntfy-alerter" ];
        files.ntfy-env = {
          mode = "0400";
          restartUnits = [ "ntfy-sh.service" ];
        };
        runtimeInputs = [
          pkgs.ntfy-sh
          pkgs.openssl
        ];
        script = ''
          token="$(cat "$in/ntfy-alerter/token")"
          password="$(openssl rand -hex 32)"
          hash="$(printf '%s\n%s\n' "$password" "$password" | ntfy user hash)"
          printf 'NTFY_AUTH_USERS=alerter:%s:user\nNTFY_AUTH_TOKENS=alerter:%s\n' "$hash" "$token" > "$out/ntfy-env"
        '';
      };

      services.ntfy-sh = {
        enable = true;
        environmentFile = config.clan.core.vars.generators.ntfy-alerter-env.files.ntfy-env.path;
        settings = {
          listen-http = "[::1]:2586";
          base-url = "https://ntfy.zt";

          # Design D1: each mesh client is its own visitor. caddy's
          # reverse_proxy sets X-Forwarded-For to the client's address
          # (caddy v2.11.7 reverseproxy.go:929-994) and connects from ::1;
          # ntfy takes the right-most untrusted address of that header
          # (ntfy 2.28.0 server/util.go:86-141). ZeroTier members share one
          # /64, so visitors are keyed by the full address. No host is
          # exempt from rate limits.
          behind-proxy = true;
          proxy-trusted-hosts = "::1";
          visitor-prefix-bits-ipv6 = 128;

          # Cutover window only (tasks.md 3.3, reverted by 7.4): ntfy logs
          # 401 and 403 only at debug (server/log.go:37,
          # server/server.go:541-545). Not trace, which logs request headers
          # including Authorization (server/server.go:500-501).
          log-level = "debug";
        };
      };
    };
}
```

- [ ] **Step 8: Run the check and watch it pass**

Run: `jj st --no-pager >/dev/null && nix build .#checks.x86_64-linux.ntfy-provisioning -L 2>&1 | tee logs/s3-evidence/3.4-green-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: PASS; the log contains, in order, `ntfy-provisioning: generators and cinnabar's 0 auth-access entries accepted`, `ntfy-provisioning: mutant short-token rejected` (preceded by the token message on stderr), `ntfy-provisioning: mutant unhashed-password rejected` (preceded by the line 1 message), and `ntfy-provisioning: mutant access-user-alertr rejected` (preceded by `auth-access entry alertr:fleet-*:rw names alertr, who is not provisioned`).
Run: `grep -c 'rejected$' logs/s3-evidence/3.4-green-*.log`
Expected: `3`.

- [ ] **Step 9: Show the check fails on a broken real generator (negative control)**

In `modules/nixos/ntfy-alerter.nix`, temporarily change the line `printf '%s' "$token" > "$out/token"` to `printf '%s\n%s' "$token" "$token" > "$out/token"`, so the real generator writes two tokens into the file.
Run: `jj st --no-pager >/dev/null && nix build .#checks.x86_64-linux.ntfy-provisioning -L 2>&1 | tee logs/s3-evidence/3.4-negative-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: FAIL in the build with `ntfy-provisioning: the token does not match ^tk_[-_A-Za-z0-9]{29}$ (user/util.go:24)` and no `accepted` line.
Restore the line to `printf '%s' "$token" > "$out/token"`.
Run: `rg -cF "printf '%s' \"\$token\" > \"\$out/token\"" modules/nixos/ntfy-alerter.nix`
Expected: `1`.

- [ ] **Step 10: Record the check's evaluation cost**

Run: `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/ntfy-provisioning-stats.json nix eval --raw .#.checks.x86_64-linux.ntfy-provisioning.drvPath 2>&1 | tee logs/s3-evidence/3.4-eval-cost-$(date -u +%Y%m%dT%H%M%SZ).log && jq '{gcTotalBytes: .gc.totalBytes, cpuTime}' /tmp/ntfy-provisioning-stats.json | tee -a logs/s3-evidence/3.4-eval-cost-*.log`
Expected: a `/nix/store/…-ntfy-provisioning.drv` path and `gcTotalBytes` below `536870912` (0.5 GiB).
At planning, evaluating cinnabar's ntfy settings plus the `ntfy-sh` and `openssl` drvPaths cost `360456896` bytes, so a figure near 0.35–0.45 GiB is expected; above 0.5 GiB, stop and report.

- [ ] **Step 11: Verify the generators by evaluation (tasks.md 3.2)**

Run:

```bash
nix eval --json .#nixosConfigurations.cinnabar.config.clan.core.vars.generators --apply 'g: builtins.mapAttrs (n: gen: { inherit (gen) share dependencies; files = builtins.mapAttrs (f: v: { inherit (v) mode deploy secret restartUnits path; }) gen.files; }) { inherit (g) ntfy-alerter ntfy-alerter-env; }' 2>&1 | tee logs/s3-evidence/3.2-generators-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected (key order as `nix eval` sorts it):
`ntfy-alerter` has `share = true`, `dependencies = []`, one file `token` with `mode = "0400"`, `deploy = true`, `secret = true`, `restartUnits = []`, `path = "/run/secrets/vars/shared/ntfy-alerter/token"`;
`ntfy-alerter-env` has `share = false`, `dependencies = ["ntfy-alerter"]`, one file `ntfy-env` with `mode = "0400"`, `deploy = true`, `secret = true`, `restartUnits = ["ntfy-sh.service"]`, `path = "/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env"`.
If either path differs, stop and report it: Tasks 4 and 5 and the 7.1 probe use the `token` path.

- [ ] **Step 12: Verify cinnabar's ntfy settings by evaluation (tasks.md 3.3)**

Run:

```bash
f="logs/s3-evidence/3.3-ntfy-settings-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  nix eval --json .#nixosConfigurations.cinnabar.config.services.ntfy-sh.settings; echo
  nix eval --raw .#nixosConfigurations.cinnabar.config.services.ntfy-sh.environmentFile; echo
  nix eval --raw .#nixosConfigurations.cinnabar.config.systemd.services.ntfy-sh.serviceConfig.EnvironmentFile; echo
} 2>&1 | tee "$f"
```

Expected, line 1: `{"attachment-cache-dir":"/var/lib/ntfy-sh/attachments","auth-file":"/var/lib/ntfy-sh/user.db","base-url":"https://ntfy.zt","behind-proxy":true,"cache-file":"/var/lib/ntfy-sh/cache-file.db","listen-http":"[::1]:2586","log-level":"debug","proxy-trusted-hosts":"::1","visitor-prefix-bits-ipv6":128}` (no `auth-access`, no `auth-default-access`, no `visitor-request-limit-exempt-hosts`); lines 2 and 3: `/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env`.

- [ ] **Step 13: Verify the rendered server configuration**

Run: `p="$(nix build --no-link --print-out-paths '.#nixosConfigurations.cinnabar.config.environment.etc."ntfy/server.yml".source')" && cat "$p" 2>&1 | tee logs/s3-evidence/3.3-server-yml-$(date -u +%Y%m%dT%H%M%SZ).log`
The NixOS module installs the same `server.yml` that `ntfy serve -c` reads as `/etc/ntfy/server.yml` (nixpkgs `nixos/modules/services/misc/ntfy-sh.nix:101-106,124` at the root pin).
Expected: the YAML holds `behind-proxy: true`, `log-level: debug`, `proxy-trusted-hosts` with value `::1` (quoted as `pkgs.formats.yaml` renders it), `visitor-prefix-bits-ipv6: 128`, and no `auth-access` key (built output).

- [ ] **Step 14: Build cinnabar (tasks.md 3.3)**

Run: `nix build .#checks.x86_64-linux.nixos-cinnabar -L 2>&1 | tee logs/s3-evidence/3.3-nixos-cinnabar-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: succeeds.
clan's sops backend skips secret files not yet generated (clan-core `nixosModules/clanCore/vars/secret/sops/generators-to-sops.nix:72`), so the build does not need Step 15's vars.

- [ ] **Step 15: Human step 3.6, generate the vars**

From this change's working copy, the operator runs, in this order:

```bash
CLAN_NO_COMMIT=1 clan vars generate cinnabar --generator ntfy-alerter 2>&1 | tee logs/s3-evidence/3.6-generate-$(date -u +%Y%m%dT%H%M%SZ).log
CLAN_NO_COMMIT=1 clan vars generate cinnabar --generator ntfy-alerter-env 2>&1 | tee -a logs/s3-evidence/3.6-generate-*.log
```

`CLAN_NO_COMMIT=1` keeps clan from making a git commit in the jj-colocated repository (`modules/clan/services/omnigent/README.md:236`); neither generator prompts.
Run: `clan vars list cinnabar 2>&1 | grep -E '^ntfy-alerter(-env)?/'`
Expected: `ntfy-alerter/token` and `ntfy-alerter-env/ntfy-env`, each shown masked.
Run: `jj st --no-pager >/dev/null && jj diff --name-only -- vars/ sops/`
Expected: only paths under `vars/shared/ntfy-alerter/token/` (`secret`, `machines/cinnabar`, `users/…`) and `vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env/`; nothing under any other generator.
If anything else changed, stop and report it; do not regenerate other vars.

- [ ] **Step 16: Tick the task items**

In `openspec/changes/stand-up-fleet-alerting/tasks.md`, change the leading `- [ ] 3.1`, `- [ ] 3.2`, `- [ ] 3.3`, `- [ ] 3.4` and `- [ ] 3.6` to `- [x] 3.1`, `- [x] 3.2`, `- [x] 3.3`, `- [x] 3.4` and `- [x] 3.6`.
Run: `rg -n "^- \[x\] 3\.[12346] " openspec/changes/stand-up-fleet-alerting/tasks.md`
Expected: exactly five lines.

- [ ] **Step 17: Format**

Run: `nix fmt -- modules/checks/ntfy-provisioning.nix modules/nixos/ntfy-alerter.nix modules/machines/nixos/cinnabar/default.nix modules/machines/nixos/cinnabar/ntfy.nix 2>&1 | tee logs/s3-evidence/3-fmt-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: exits 0.
Run: `nix fmt -- --fail-on-change 2>&1 | tee -a logs/s3-evidence/3-fmt-*.log`
Expected: exits 0.
If Step 17 reformatted a file, rerun Step 8 and expect the same PASS.

- [ ] **Step 18: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(ntfy): provision the alerter token on cinnabar and key each mesh client as its own visitor'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(ntfy): provision the alerter token on cinnabar")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/checks/ntfy-provisioning.nix \
  modules/nixos/ntfy-alerter.nix \
  modules/machines/nixos/cinnabar/default.nix \
  modules/machines/nixos/cinnabar/ntfy.nix \
  vars/shared/ntfy-alerter \
  vars/per-machine/cinnabar/ntfy-alerter-env \
  openspec/changes/stand-up-fleet-alerting/tasks.md
jj diff --name-only -r "$change"
```

Expected: the last command lists the four module files, `tasks.md`, and the files under `vars/shared/ntfy-alerter/` and `vars/per-machine/cinnabar/ntfy-alerter-env/`, and nothing else.
If `jj diff -r @ -- openspec/changes/stand-up-fleet-alerting/tasks.md` showed hunks other than the five ticks before the squash, squash that file with `jj squash --from @ --into "$change" --interactive --keep-emptied --use-destination-message -- openspec/changes/stand-up-fleet-alerting/tasks.md` and select only the ticks.
The orchestrator rebases the development join, pushes, opens the pull request and enqueues it.

- [ ] **Step 19: Pull request merged (tasks.md 3.5)**

The orchestrator's pull request for this change shows nixbot green, including `checks.x86_64-linux.ntfy-provisioning` and `nixos-cinnabar`, and merges through the queue.
Verify: `jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(ntfy): provision the alerter token on cinnabar")' -T 'commit_id.shortest(12)'` prints one commit.
The ticks for 3.5 and 3.7 are not part of this change; they are recorded with the merge and deploy evidence by the orchestrator.

- [ ] **Step 20: Gate before deploy C1**

Task 1 has merged, because the 7.1 token probe on cinnabar runs `ntfy-send` with `NTFY_TOKEN_FILE`.
Run: `jj git fetch && jj file show -r main@origin pkgs/by-name/ntfy-send/ntfy-send.sh | grep -c NTFY_TOKEN_FILE`
Expected: a count of at least `1`.

- [ ] **Step 21: Deploy C1 (tasks.md 3.7)**

Run Task 7's pre-C1 baseline step, then Task 7 Step 0's deploy procedure for host `cinnabar`; magnetite is not deployed.
Verify: Task 7's 7.1 passes, in particular `systemctl is-active ntfy-sh` prints `active` on cinnabar, `systemctl show ntfy-sh -p EnvironmentFiles` names `/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env`, and the token probe with `NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token` exits 0; group 4's deploy waits for 7.1.
If `ntfy-sh` fails to start, the journal's `invalid auth-users`/`invalid auth-tokens` line names the cause; roll back by redeploying cinnabar from the previous `main@origin` commit through the same procedure, since no other host depends on C1 yet.

---

### Task 4: Evaluator, rules, transition function and `checks.fleet-alert` (cutover C2)

Implements `tasks.md` 4.1–4.11 (design D3, D10–D16, D18, D19, "Failure path"; ADR-009 items 1–8, 10, 14, 17, R9.1, R9.2, R9.5; specs `fleet-alerting-interface` and `fleet-alerting`).
The whole check is written first, with its fixture server, label fixtures, reference model and property test, and each of its three parts is built on its own and fails before the code it judges exists: the `promtool` part before `rules.nix`, the property part before `transition.jq`, and the fixture part before `fleet-alert.nix`.
The token wiring and R7.1's memory and kill-order relations are host-local, so they are module and host assertions rather than check clauses, because relations within one host belong in that host's module assertions, which CI already pays for when it evaluates the host (S1 review F5); measured with `.#.checks…`, `checks.fleet-alert` costs 0.252 GiB at Task 4's merge `6ccc644b` (270,361,264 B) and 0.453 GiB at Task 5's merge `dbec98c7` and at `origin/main` `6caa2425` (485,950,608 B and 485,945,120 B); Task 4's earlier 0.557 GiB for `checks.fleet-alert` and 553 MB for `checks.greptimedb-envelope` were taken without the leading dot, which adds about 114 MB for probing `packages` and `legacyPackages` first, so both checks were under budget (about 484 MB and 439 MB) before the move (charter v19).
magnetite's token, kill-order and R8.2 holder assertions are made to fail first, by the order of the steps, and every new assertion is shown able to fail by an `extendModules` override.

**Files:**
- Create: `modules/nixos/fleet-alert/rules.nix` (a flake-parts module defining `flake.lib.fleetAlertRules`)
- Create: `modules/nixos/fleet-alert/transition.jq` (`.jq`, so import-tree does not load it)
- Create: `modules/nixos/fleet-alert.nix` (`flake.lib.fleetAlertEvaluator`, `flake.modules.nixos.fleet-alert`)
- Create: `modules/checks/fleet-alert.nix` (`checks.x86_64-linux.fleet-alert`)
- Create: `modules/checks/fleet-alert/fixture_server.py`, `modules/checks/fleet-alert/model.py`, `modules/checks/fleet-alert/test_transition.py`, `modules/checks/fleet-alert/fixtures/series.json`
- Modify: `modules/nixos/observability-notify.nix` (the template and hook token assertions)
- Modify: `modules/checks/greptimedb-envelope.nix` (delete the `memoryCeilings` and `killOrder` clauses, the `view` fields only they read and their mutants; header comment)
- Modify: `modules/machines/nixos/magnetite/default.nix` (imports `fleet-alert` and `ntfy-alerter`; `services.observability-notify.units` gains `fleet-alert`; evaluator and notifier token settings; R8.2 `regulator-password` holders; the token, R7.1 memory-ceiling and kill-order assertions)
- Modify (by `clan vars fix magnetite --generator ntfy-alerter`, Step 24): `vars/shared/ntfy-alerter/token/secret` (re-encrypted with magnetite's age key added; the value is not regenerated)
- Modify: `openspec/changes/stand-up-fleet-alerting/tasks.md` (tick 4.1–4.9)
- Evidence (git-ignored): `logs/s3-evidence/4.*-*.log`

**Interfaces:**
- Consumes (Task 1): `pkgs.ntfy-send`, usage `ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, posting to `https://ntfy.zt/<topic>` with `curl -sfk -m 5`, reading the token from the file named by `NTFY_TOKEN_FILE` when set.
- Consumes (Task 2): `flake.modules.nixos.observability-notify`, imported by the collector's `agent` role on magnetite, with `services.observability-notify.units` and `services.observability-notify.tokenFile` (`nullOr str`, default `null`).
  When `tokenFile` is set, the template gets `serviceConfig.LoadCredential = [ "alerter-token:<tokenFile>" ]` and `environment.NTFY_TOKEN_FILE = "%d/alerter-token"`, and each notified unit's hooks become exactly `-+${pkgs.coreutils}/bin/env NTFY_TOKEN_FILE=<tokenFile> ${resolved} start %n` and `… stop %n` (S3PlanT12, 2026-10-18).
  The notifier appends `<epoch> <unit> <host>` to `/var/lib/observability-notify/failed.log` (mode `0644`) per posted `FAILED`, `<unit>` with its `.service` suffix.
- Consumes (Task 3): `flake.modules.nixos.ntfy-alerter` (no options), whose shared generator `ntfy-alerter` holds only `token`, read as `config.clan.core.vars.generators.ntfy-alerter.files.token.path` (`/run/secrets/vars/shared/ntfy-alerter/token`); the per-machine `ntfy-alerter-env` exists on cinnabar only.
  `vars/shared/ntfy-alerter/token/` exists on `main` with cinnabar as its only machine.
- Consumes (S1): `config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path`; the store at `http://127.0.0.1:4000` with database `fleet`; `systemd.services.opentelemetry-collector.serviceConfig.OOMScoreAdjust = 300`.
- Produces: `flake.lib.fleetAlertRules { lib; notifiedUnits; }` returning `{ rules; json; yaml; }`.
  Each element of `rules` is `{ alert; expr; for; severity; annotations = { summary; }; presence = [ { selector; expectedHosts; } ]; attribution = [ { name; query; label; } ]; window ? { zone; weekday; start; end; }; }` with `for` a duration string (`"0s"`, `"1m"`, `"5m"`); the internal rules `StoreQueryFailing` and `RuleSignalMissing` have no `expr`.
  `json` is the evaluator's rule list, the same objects with `for` in integer seconds; `yaml` is a Prometheus rules file of the rules that have an `expr`, written as JSON (which YAML accepts), read only by `promtool`.
  `window.weekday` is ISO (Monday 1); `start` is inclusive and `end` exclusive, both `HH:MM`.
- Produces: `modules/nixos/fleet-alert/transition.jq` with
  - `def transition($observations; $now; $rules)`: input is the state (`null` or `{}` on a first run); output `{ state, posts }`; each post `{ title, priority, message, key = { kind, id } }`, `kind` one of `firing`, `repost`, `resolved`, `budget`; the caller adds `topic` with `.posts |= map({topic: $topic} + .)`.
  - `def mark_posted($post)`: a filter over the state, timed by `state.lastRun`.
  - `def in_window($window; $now)`: run under `TZ=<window.zone>`.
  - Observations: `{ storeError, results = { <alert> = [ { labels, value } ] }, presence = { <selector> = [ <host> ] }, reporting = [ <host> ], failedLog = [ { at, unit, host } ], windows ? { <alert> = bool }, attribution ? { <host> = text } }`.
  - State: `{ instances = { <id> = { alert, labels, phase, severity, for, summary, attributed, value, activeSince, lastSeen, firingPostedAt, lastPostedAt } }, hosts = { <host> = epoch }, firings = [ { at, alert, host } ], budgetPostedAt, lastRun }`; `<id>` is `[alert, (labels | to_entries | sort_by(.key))] | tojson`.
  - An instance without `host_name` is never host-frozen, and its title omits the host: `[FIRING] StoreQueryFailing`.
  - A rule is evaluated from `results` when it has an `expr` or, from Task 5, when `results` holds an entry for its alert name (the dead-man's `AlertEvaluatorSilent`); `StoreQueryFailing` and `RuleSignalMissing` come only from the function's own logic, never from `results`.
- Produces: `flake.lib.fleetAlertEvaluator pkgs { ntfySend; transition ? <transition.jq>; }`, a `writeShellApplication` named `fleet-alert`; the optional `transition` exists so the check can build the evaluator over mutant jq (contract extension, see questions).
  It reads `FLEET_ALERT_CONFIG` (`{ storeUrl, database, user, queryTimeoutSec, queryDeadlineSec, postDeadlineSec, topic, heartbeatTopic, stateFile, failedLog, rules }`), `$CREDENTIALS_DIRECTORY/regulator-password`, optional `FLEET_ALERT_NOW`; `NTFY_TOKEN_FILE` is read by `ntfy-send`, not by the evaluator.
- Produces: `flake.modules.nixos.fleet-alert`, outer `let` with `flakeLib`, `transitionJq`, `jqLib`, `fleetAlertEvaluator`; inside, `cfg = config.services.fleet-alert` and the `hardening` attrset; options `services.fleet-alert.evaluator.{enable,tokenFile,regulatorPasswordFile,storeUrl,topic,heartbeatTopic}` declared unconditionally; `config = lib.mkMerge [ (lib.mkIf cfg.evaluator.enable { … }) ]`.
  Task 5 adds `services.fleet-alert.deadman.*`, `fleetAlertDeadman` and a second `mkMerge` element; this task declares no `deadman` option (agreed with S3PlanT5; see questions).
- Produces: `fleet-alert.service` (`Type = "oneshot"`, `DynamicUser`, `StateDirectory = "fleet-alert"`, `UMask = "0077"`, the `greptimedb-envelope` hardening set, `OOMScoreAdjust = 0`, `MemoryMax = "64M"`, `TimeoutStartSec = "50s"`, `LoadCredential = [ "regulator-password:<path>" "alerter-token:<path>" ]`, `environment = { FLEET_ALERT_CONFIG = <store path>; NTFY_TOKEN_FILE = "%d/alerter-token"; }`, `after = [ "greptimedb.service" "greptimedb-schema.service" "zerotierone.service" ]`, no `wants`), `fleet-alert.timer` (`OnCalendar = "minutely"`, `AccuracySec = "1s"`), state `/var/lib/fleet-alert/state.json`.
- Produces: the R9.5 assertion in `modules/nixos/fleet-alert.nix`, message starting `fleet-alert: R9.5 requires`.
- Produces: `checks.x86_64-linux.fleet-alert`, a `runCommand` whose `passthru` holds `rules`, `promtoolRehearsal`, `fixtureRehearsal` and `propertyRehearsal`, each built alone in the steps below.
  `perSystem` `let` names Task 5 extends: `ntfySendStub` (`pkgs.writeShellScriptBin "ntfy-send"`), `fixtureCredentials`, `updateService`, `runtimeMutants`.
- Produces: the token-wiring assertions in `observability-notify.nix` and `fleet-alert.nix`, and magnetite's token, R7.1 memory-ceiling and kill-order assertions, with messages starting `observability-notify:`, `fleet-alert:` and `magnetite:`.
- Produces: the fixture server CLI of the contract; it prints `REQUEST <step> <query>`, `UNEXPECTED <step> <query>` and `VIOLATION <text>` lines on stdout, which the check redirects to a file, and its fixture password is the constant `00112233445566778899aabbccddeeff`.

- [ ] **Step 1: Confirm the base**

Run from `/Users/crs58/projects/vanixiets`:

```bash
pwd
jj git fetch
jj log --no-graph -r main@origin -T 'description.first_line() ++ "\n"'
nix eval --json .#nixosConfigurations.magnetite.config.services.observability-notify --apply 'o: { inherit (o) tokenFile; units = builtins.length o.units; }'
nix eval --raw .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.ntfy-alerter.files.token.path
nix eval .#nixosConfigurations.magnetite.config.clan.core.vars.generators --apply 'g: g ? ntfy-alerter'
jj file show -r main@origin modules/checks/otel-collector-config.nix | grep -c 'coreutils-\[^/ \]+/bin/env NTFY_TOKEN_FILE'
```

Expected: `pwd` prints `/Users/crs58/projects/vanixiets`; `main@origin` contains the merges of Tasks 1, 2 and 3; the notifier prints `{"tokenFile":null,"units":13}` (the 12 host units plus `opentelemetry-collector`); the token path is `/run/secrets/vars/shared/ntfy-alerter/token`; the last eval prints `false`; the `grep -c` prints `1` (Task 2 widened R3.1's hook pattern).
Also confirm Task 7's 7.1 has passed on cinnabar (its evidence log exists under `logs/s3-evidence/7.1-*`), because deploy C2 in Step 33 depends on it.
If any differs, stop and report to the orchestrator.

- [ ] **Step 2: Confirm the vendored tools at the root pin**

Run:

```bash
nix eval --impure --json --expr 'let p = (builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux; in { jq = p.jq.version; prometheus = p.prometheus.version; python = p.python3.version; hypothesis = p.python3Packages.hypothesis.version; tzdata = p.tzdata.version; shellAppHasText = (p.writeShellApplication { name = "x"; text = "true"; }) ? text; }' 2>&1 | tee logs/s3-evidence/4.0-pins-$(date -u +%Y%m%dT%H%M%SZ).log
nix build --no-link --print-out-paths --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixpkgs.legacyPackages.x86_64-linux.prometheus.cli' | xargs -I{} ls {}/bin
```

Expected: `jq` `1.8.2`, `prometheus` `3.15.0`, `python` `3.14.7`, `hypothesis` `6.156.1`, `shellAppHasText` `true` (the no-state-write mutant overrides that attribute); the listing contains `promtool`.
At planning (2026-10-18) the first five values and `shellAppHasText = true` were read this way; if `promtool` is not under `prometheus.cli`, stop and report, since Step 6's `nativeBuildInputs` names it.

- [ ] **Step 3: Write the fixture server**

Create `modules/checks/fleet-alert/fixture_server.py`:

```python
"""Loopback stand-in for GreptimeDB's PromQL instant-query API.

checks.x86_64-linux.fleet-alert runs the evaluator against this server
(design D19; fleet-alerting-interface "The evaluator queries the fleet
database as the regulators' store account"). It serves GET and POST
/v1/prometheus/api/v1/query from responses[<step>][<query>], where <step>
is the content of --step-file, read per request, and each answer is a
Prometheus JSON body or {"status": <code>} for an error. It answers 404 to
any other path, 400 without `x-greptime-db-name: fleet`, and 401 to any
account but `regulator` with the fixture password. A query with no answer
gets 500 and an UNEXPECTED line. If two connections are ever open at once
it prints a VIOLATION line and exits 1, so a leg fails if the evaluator
queries concurrently (design D13). Everything it records is a line on
stdout: REQUEST, UNEXPECTED, VIOLATION.
"""

import argparse
import base64
import binascii
import json
import os
import threading
from http.server import BaseHTTPRequestHandler, ThreadingHTTPServer
from urllib.parse import parse_qs, urlsplit

QUERY_PATH = "/v1/prometheus/api/v1/query"
FIXTURE_USER = "regulator"
# The same value checks.x86_64-linux.fleet-alert writes to the fixture
# credentials' regulator-password.
FIXTURE_PASSWORD = "00112233445566778899aabbccddeeff"


def main():
    parser = argparse.ArgumentParser()
    parser.add_argument("--responses", required=True)
    parser.add_argument("--step-file", required=True)
    parser.add_argument("--port-file", required=True)
    args = parser.parse_args()
    with open(args.responses) as f:
        responses = json.load(f)

    lock = threading.Lock()
    connections = {"open": 0}

    def record(line):
        print(line, flush=True)

    class Server(ThreadingHTTPServer):
        daemon_threads = True

        # Counted from accept, so a client holding a connection without
        # sending counts as one open request.
        def process_request(self, request, client_address):
            with lock:
                connections["open"] += 1
                if connections["open"] > 1:
                    record("VIOLATION two requests open at once")
                    os._exit(1)
            super().process_request(request, client_address)

    class Handler(BaseHTTPRequestHandler):
        def setup(self):
            super().setup()
            self.counted = True

        # Released before the answer is sent, so the evaluator's next query,
        # which starts only after it has read this answer, never overlaps.
        def release(self):
            if self.counted:
                self.counted = False
                with lock:
                    connections["open"] -= 1

        def finish(self):
            try:
                super().finish()
            finally:
                self.release()

        def reply(self, code, body):
            data = json.dumps(body).encode()
            self.release()
            self.send_response(code)
            self.send_header("Content-Type", "application/json")
            self.send_header("Content-Length", str(len(data)))
            self.end_headers()
            self.wfile.write(data)

        def credentials(self):
            auth = self.headers.get("Authorization", "")
            if not auth.startswith("Basic "):
                return None
            try:
                user, _, password = base64.b64decode(auth[6:]).decode().partition(":")
            except (binascii.Error, UnicodeDecodeError):
                return None
            return user, password

        def answer(self):
            url = urlsplit(self.path)
            form = parse_qs(url.query)
            if self.command == "POST":
                length = int(self.headers.get("Content-Length") or 0)
                form.update(parse_qs(self.rfile.read(length).decode()))
            if url.path != QUERY_PATH:
                return self.reply(404, {"status": "error", "error": "not found"})
            if self.headers.get("x-greptime-db-name") != "fleet":
                return self.reply(400, {"status": "error", "error": "database is not fleet"})
            if self.credentials() != (FIXTURE_USER, FIXTURE_PASSWORD):
                return self.reply(401, {"status": "error", "error": "unauthorized"})
            with open(args.step_file) as f:
                step = f.read().strip()
            query = form.get("query", [""])[0]
            record(f"REQUEST {step} {query}")
            body = responses.get(step, {}).get(query)
            if body is None:
                record(f"UNEXPECTED {step} {query}")
                return self.reply(500, {"status": "error", "error": "no fixture for this query"})
            if set(body) == {"status"} and isinstance(body["status"], int):
                return self.reply(body["status"], {"status": "error", "errorType": "fixture", "error": "replayed error"})
            return self.reply(200, body)

        do_GET = answer
        do_POST = answer

        def log_message(self, *args):
            pass

    server = Server(("127.0.0.1", 0), Handler)
    with open(args.port_file, "w") as f:
        f.write(str(server.server_port))
    server.serve_forever()


if __name__ == "__main__":
    main()
```

- [ ] **Step 4: Write the measured label fixtures**

Create `modules/checks/fleet-alert/fixtures/series.json`.
`series` holds one result label set per rule, as measured on magnetite's `fleet` database on 2026-10-18 (`logs/s3/series-labels.md:52-63`); the three entries carrying `__name__` exercise the evaluator's removal of it, because whether GreptimeDB 1.2.1 keeps the metric name on a filtering comparison was not measured.
`attribution` holds the answers to the three attribution queries, in `rules.nix`'s order (top three executables, ARC size, swap used), with the values measured at planning (`series-labels.md:38-40`), rounded to whole megabytes:

```json
{
  "series": {
    "HostMemoryPressure": { "host_name": "magnetite" },
    "HostOOMKill": {
      "host_name": "magnetite",
      "instance": "127.0.0.1:9100",
      "job": "node",
      "service_instance_id": "127.0.0.1:9100",
      "service_name": "node"
    },
    "ZfsPoolUnhealthy": {
      "__name__": "node_zfs_zpool_state",
      "host_name": "magnetite",
      "instance": "127.0.0.1:9100",
      "job": "node",
      "service_instance_id": "127.0.0.1:9100",
      "service_name": "node",
      "state": "degraded",
      "zpool": "zroot"
    },
    "SystemdUnitRestartLoop": {
      "host_name": "magnetite",
      "systemd_unit_name": "omnigent-host-owner-1.service"
    },
    "SystemdUnitFailed": {
      "__name__": "systemd_unit_state",
      "host_name": "magnetite",
      "systemd_unit_active_state": "failed",
      "systemd_unit_name": "nginx.service"
    },
    "LocalExporterDown": {
      "__name__": "up",
      "host_name": "magnetite",
      "instance": "127.0.0.1:9100",
      "job": "node",
      "service_instance_id": "127.0.0.1:9100",
      "service_name": "node"
    },
    "WeeklyPipelineTest": {}
  },
  "attribution": [
    [
      { "metric": { "process_executable_name": "nix-instantiate" }, "value": "471000000" },
      { "metric": { "process_executable_name": "nix-eval-jobs" }, "value": "400000000" },
      { "metric": { "process_executable_name": "niks3" }, "value": "314000000" }
    ],
    [
      {
        "metric": {
          "instance": "127.0.0.1:9100",
          "job": "node",
          "service_instance_id": "127.0.0.1:9100",
          "service_name": "node"
        },
        "value": "4120000000"
      }
    ],
    [{ "metric": {}, "value": "960000000" }]
  ]
}
```

The check adds `host_name` to each attribution series that has labels, per queried host.

- [ ] **Step 5: Write the reference model and the property test**

Create `modules/checks/fleet-alert/model.py`:

```python
"""Reference model of fleet-alert's instance transition (design D11).

checks.x86_64-linux.fleet-alert's property test compares this model with
modules/nixos/fleet-alert/transition.jq over generated timelines: posts
(title, priority, kind, instance id) and state. It is written from the
specification, not translated from the jq: Prometheus `for` over instances
of a rule plus its result label set; resolve after 5 min absent; a
`critical` instance re-posted every 24 h, a `warning` never, an `info` with
no RESOLVED and not counted; a store error freezes every instance but
StoreQueryFailing; a host without system_memory_usage_bytes freezes its
instances; RuleSignalMissing per presence selector while an expected host
reports; R9.1's 24 h count over posted FIRINGs and failed.log with one
AlertBudgetExceeded per 24 h. Messages are not modelled.
"""

import copy
import json

RESOLVE_AFTER = 300
REPOST_EVERY = 86400
BUDGET_WINDOW = 86400
BUDGET_FLEET = 10
BUDGET_HOSTS = {"stibnite": 3, "pyrite": 3}
PRIORITY = {"critical": "high", "warning": "default", "info": "low"}


def instance_id(alert, labels):
    entries = [{"key": key, "value": labels[key]} for key in sorted(labels)]
    return json.dumps([alert, entries], separators=(",", ":"), ensure_ascii=False)


def normalize(state):
    base = {"instances": {}, "hosts": {}, "firings": [], "budgetPostedAt": None, "lastRun": None}
    base.update(copy.deepcopy(state or {}))
    return base


def rule_named(rules, name):
    return next((rule for rule in rules if rule["alert"] == name), None)


# Raised only by the logic below, never from results.
INTERNAL = ("StoreQueryFailing", "RuleSignalMissing")


def conditions(observations, rules):
    if observations["storeError"]:
        rule = rule_named(rules, "StoreQueryFailing")
        return [] if rule is None else [(rule, {}, "1")]
    found = []
    windows = observations.get("windows") or {}
    results = observations.get("results") or {}
    for rule in rules:
        # A rule with an `expr`, or one whose alert has a results entry (a
        # caller's own query, such as the dead-man's AlertEvaluatorSilent).
        if "expr" not in rule and (rule["alert"] in INTERNAL or rule["alert"] not in results):
            continue
        if rule.get("window") is not None and windows.get(rule["alert"]) is not True:
            continue
        for series in results.get(rule["alert"]) or []:
            labels = {k: v for k, v in series["labels"].items() if k != "__name__"}
            found.append((rule, labels, str(series["value"])))
    missing = rule_named(rules, "RuleSignalMissing")
    if missing is not None:
        reporting = observations.get("reporting") or []
        presence = observations.get("presence") or {}
        for rule in rules:
            for selector in rule.get("presence") or []:
                if presence.get(selector["selector"]):
                    continue
                if any(host in reporting for host in selector["expectedHosts"]):
                    found.append((missing, {"rule": rule["alert"], "selector": selector["selector"]}, "0"))
    return found


def frozen(alert, labels, observations):
    if alert == "StoreQueryFailing":
        return False
    if observations["storeError"]:
        return True
    host = labels.get("host_name")
    if host is None:
        return False
    return host not in (observations.get("reporting") or [])


def advance(instance, condition, now):
    if condition is not None:
        rule, labels, _value = condition
        if instance is None:
            nxt = {
                "alert": rule["alert"],
                "labels": labels,
                "phase": "pending",
                "activeSince": now,
                "firingPostedAt": None,
                "lastPostedAt": None,
            }
        else:
            nxt = copy.deepcopy(instance)
        nxt.update({"severity": rule["severity"], "for": rule["for"], "lastSeen": now})
        if nxt["phase"] == "resolved":
            nxt["phase"] = "firing"
        if nxt["phase"] == "pending" and now - nxt["activeSince"] >= nxt["for"]:
            nxt["phase"] = "firing"
        return nxt
    if instance is None or instance["phase"] == "pending":
        return None
    if instance["phase"] == "firing" and now - instance["lastSeen"] >= RESOLVE_AFTER:
        if instance["severity"] == "info" or instance["firingPostedAt"] is None:
            return None
        nxt = copy.deepcopy(instance)
        nxt["phase"] = "resolved"
        return nxt
    return instance


def post_kind(instance, now):
    if instance["phase"] == "firing" and instance["firingPostedAt"] is None:
        return "firing"
    if (
        instance["phase"] == "firing"
        and instance["severity"] == "critical"
        and now - instance["lastPostedAt"] >= REPOST_EVERY
    ):
        return "repost"
    if instance["phase"] == "resolved":
        return "resolved"
    return None


def title(kind, alert, host):
    word = "RESOLVED" if kind == "resolved" else "FIRING"
    return f"[{word}] {alert}" + (f" {host}" if host else "")


def budget_post(state, observations, now):
    entries = [(f'{f["alert"]} {f["host"]}', f["host"]) for f in state["firings"]]
    entries += [
        (f'FAILED {f["unit"]} {f["host"]}', f["host"])
        for f in observations.get("failedLog") or []
        if f["at"] > now - BUDGET_WINDOW
    ]
    laptops = [
        host for host, limit in BUDGET_HOSTS.items() if sum(1 for _, h in entries if h == host) > limit
    ]
    due = state["budgetPostedAt"] is None or now - state["budgetPostedAt"] >= BUDGET_WINDOW
    if (len(entries) > BUDGET_FLEET or laptops) and due:
        return [
            {
                "title": "[FIRING] AlertBudgetExceeded",
                "priority": "default",
                "key": {"kind": "budget", "id": "AlertBudgetExceeded"},
            }
        ]
    return []


def transition(state, observations, now, rules):
    state = normalize(state)
    state["firings"] = [f for f in state["firings"] if f["at"] > now - BUDGET_WINDOW]
    conds = {}
    for rule, labels, value in conditions(observations, rules):
        conds[instance_id(rule["alert"], labels)] = (rule, labels, value)
    ids = sorted(set(state["instances"]) | set(conds))
    instances = {}
    for iid in ids:
        instance = state["instances"].get(iid)
        condition = conds.get(iid)
        if instance is not None:
            alert, labels = instance["alert"], instance["labels"]
        else:
            alert, labels = condition[0]["alert"], condition[1]
        if frozen(alert, labels, observations):
            if instance is not None:
                instances[iid] = instance
            continue
        nxt = advance(instance, condition, now)
        if nxt is not None:
            instances[iid] = nxt
    state["instances"] = instances
    state["lastRun"] = now
    if not observations["storeError"]:
        for host in observations.get("reporting") or []:
            state["hosts"][host] = now
    posts = []
    for iid in ids:
        instance = instances.get(iid)
        if instance is None or frozen(instance["alert"], instance["labels"], observations):
            continue
        kind = post_kind(instance, now)
        if kind is not None:
            posts.append(
                {
                    "title": title(kind, instance["alert"], instance["labels"].get("host_name") or ""),
                    "priority": PRIORITY.get(instance["severity"], "default"),
                    "key": {"kind": kind, "id": iid},
                }
            )
    return state, posts + budget_post(state, observations, now)


def mark_posted(state, post):
    state = normalize(state)
    at = state["lastRun"]
    kind, iid = post["key"]["kind"], post["key"]["id"]
    if kind in ("firing", "repost"):
        instance = state["instances"].get(iid)
        if instance is not None:
            if instance["firingPostedAt"] is None:
                instance["firingPostedAt"] = at
            instance["lastPostedAt"] = at
            if instance["severity"] != "info":
                state["firings"].append(
                    {"at": at, "alert": instance["alert"], "host": instance["labels"].get("host_name") or ""}
                )
    elif kind == "resolved":
        state["instances"].pop(iid, None)
    elif kind == "budget":
        state["budgetPostedAt"] = at
    return state
```

Create `modules/checks/fleet-alert/test_transition.py`:

```python
"""Property test: transition.jq equals model.py (design D11; tasks.md 4.6).

Hypothesis generates timelines of runs: the time step, a store error, the
hosts reporting system_memory_usage_bytes, each rule's firing hosts, and the
index of the first post that fails in that run (the posts before it
succeed, as the evaluator posts in order and stops at a failure). One jq
process folds each whole timeline through transition and mark_posted; the
model does the same; posts and state must be equal at every run. The test
is derandomized, with no example database and no deadline, so it is a pure
function of its source and cannot flake the merge queue.
FLEET_ALERT_JQ_LIB names a directory holding transition.jq.
"""

import json
import os
import subprocess

from hypothesis import HealthCheck, given, settings
from hypothesis import strategies as st

import model

JQ_LIB = os.environ["FLEET_ALERT_JQ_LIB"]
HOSTS = ["magnetite", "stibnite"]
T0 = 1793102400


def rule(alert, seconds, severity):
    return {
        "alert": alert,
        "expr": alert.lower(),
        "for": seconds,
        "severity": severity,
        "annotations": {"summary": alert},
        "presence": [],
        "attribution": [],
    }


RULES = [
    rule("Crit", 0, "critical"),
    rule("Warn", 120, "warning"),
    rule("Info", 0, "info"),
    {
        "alert": "StoreQueryFailing",
        "for": 180,
        "severity": "critical",
        "annotations": {"summary": "store"},
        "presence": [],
        "attribution": [],
    },
]
RULE_NAMES = ["Crit", "Warn", "Info"]

DRIVER = r"""
include "transition";
. as $timeline
| reduce $timeline.steps[] as $s ({state: null, posts: []};
    (.state | transition($s.observations; $s.now; $timeline.rules)) as $r
    | .posts += [$r.posts | map({title, priority, kind: .key.kind, id: .key.id})]
    | .state = (reduce ($r.posts | if $s.failAt == null then . else .[:$s.failAt] end)[] as $p
                ($r.state; mark_posted($p))))
"""

INSTANCE_FIELDS = (
    "alert",
    "labels",
    "phase",
    "severity",
    "for",
    "activeSince",
    "lastSeen",
    "firingPostedAt",
    "lastPostedAt",
)


def project(state):
    state = model.normalize(state)
    return {
        "instances": {
            iid: {field: instance.get(field) for field in INSTANCE_FIELDS}
            for iid, instance in state["instances"].items()
        },
        "hosts": state["hosts"],
        "firings": state["firings"],
        "budgetPostedAt": state["budgetPostedAt"],
        "lastRun": state["lastRun"],
    }


def build(steps):
    now = T0
    built = []
    for step in steps:
        now += step["dt"]
        built.append(
            {
                "now": now,
                "failAt": step["failAt"],
                "observations": {
                    "storeError": step["storeError"],
                    "reporting": step["reporting"],
                    "presence": {},
                    "results": {
                        alert: [{"labels": {"host_name": host}, "value": "1"} for host in hosts]
                        for alert, hosts in step["results"].items()
                    },
                    "failedLog": [],
                },
            }
        )
    return {"rules": RULES, "steps": built}


def run_jq(timeline):
    done = subprocess.run(
        ["jq", "-c", "-L", JQ_LIB, DRIVER],
        input=json.dumps(timeline),
        capture_output=True,
        text=True,
        check=True,
    )
    result = json.loads(done.stdout)
    return {"posts": result["posts"], "state": project(result["state"])}


def run_model(timeline):
    state = None
    posts = []
    for step in timeline["steps"]:
        state, planned = model.transition(state, step["observations"], step["now"], timeline["rules"])
        posts.append(
            [
                {"title": p["title"], "priority": p["priority"], "kind": p["key"]["kind"], "id": p["key"]["id"]}
                for p in planned
            ]
        )
        succeeded = planned if step["failAt"] is None else planned[: step["failAt"]]
        for post in succeeded:
            state = model.mark_posted(state, post)
    return {"posts": posts, "state": project(state)}


step_strategy = st.fixed_dictionaries(
    {
        "dt": st.sampled_from([60, 60, 60, 120, 300, 900, 3600, 86400]),
        "storeError": st.sampled_from([False, False, False, False, True]),
        "reporting": st.sampled_from([HOSTS, HOSTS, HOSTS, ["magnetite"], ["stibnite"], []]),
        "results": st.fixed_dictionaries(
            {name: st.lists(st.sampled_from(HOSTS), unique=True) for name in RULE_NAMES}
        ),
        "failAt": st.one_of(st.none(), st.integers(min_value=0, max_value=3)),
    }
)


@settings(
    derandomize=True,
    database=None,
    deadline=None,
    max_examples=200,
    print_blob=False,
    suppress_health_check=[HealthCheck.too_slow, HealthCheck.data_too_large],
)
@given(st.lists(step_strategy, min_size=1, max_size=40))
def test_transition_matches_model(steps):
    timeline = build(steps)
    expected = run_model(timeline)
    actual = run_jq(timeline)
    for index, (want, got) in enumerate(zip(expected["posts"], actual["posts"])):
        assert want == got, f"run {index}: model posts {want}, transition.jq posts {got}"
    assert expected["state"] == actual["state"], (
        f"final state differs:\nmodel {json.dumps(expected['state'], sort_keys=True)}\n"
        f"jq    {json.dumps(actual['state'], sort_keys=True)}"
    )


if __name__ == "__main__":
    test_transition_matches_model()
    print("ok: transition.jq equals the reference model on every generated timeline")
```

- [ ] **Step 6: Write the check**

Create `modules/checks/fleet-alert.nix`:

```nix
# checks.x86_64-linux.fleet-alert: regulator R9.2 (ADR-009 R9.2; design D10,
# D11, D13-D16, D19; tasks.md 4.5, 4.6).
#
# Three parts, each a derivation in passthru so it can be built alone:
# - promtoolRehearsal: `promtool check rules` over the YAML rendered from
#   modules/nixos/fleet-alert/rules.nix, and a malformed-expression mutant
#   that promtool must reject.
# - fixtureRehearsal: the evaluator, flake.lib.fleetAlertEvaluator built with
#   a recording ntfy-send, runs in the build sandbox against
#   fleet-alert/fixture_server.py, which replays canned answers to the
#   store's PromQL API per run. A leg is a timeline of runs at
#   FLEET_ALERT_NOW. Every run must record one heartbeat at priority min and
#   post only with NTFY_TOKEN_FILE naming the fixture credential, and the
#   alert posts of the leg must equal its list. The four runtime R9.2
#   mutants (no state write, `for` 0, no store freeze, no absence freeze)
#   must each produce a non-empty failure list.
# - propertyRehearsal: fleet-alert/test_transition.py compares transition.jq
#   with the reference model fleet-alert/model.py over derandomized
#   Hypothesis timelines, and must fail on the no-re-post mutant.
#
# The alerter token's wiring (tasks.md 4.7) is asserted where the units are
# declared: modules/nixos/observability-notify.nix (template and resolve
# hooks), modules/nixos/fleet-alert.nix (the evaluator) and magnetite's
# configuration (both read the ntfy-alerter token): a relation within one
# host is a module assertion, which CI already pays for when it evaluates
# the host (S1 review F5).
#
# The fixtures cannot see the store's real metric names (ADR-009
# Consequences); RuleSignalMissing watches those after deploy. The label
# sets in fleet-alert/fixtures/series.json are those measured on magnetite's
# `fleet` database on 2026-10-18 (logs/s3/series-labels.md). The fixture
# server cannot evaluate PromQL, so the SystemdUnitFailed exclusion leg
# replays only the failed units the rendered exclusion regex keeps, matched
# here with the full-match semantics PromQL uses for `!~`.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      magnetite = self.nixosConfigurations.magnetite.config;
      notifiedUnits = magnetite.services.observability-notify.units;
      rules = self.lib.fleetAlertRules { inherit lib notifiedUnits; };
      evaluatorRules = builtins.fromJSON rules.json;
      transitionJq = ../nixos/fleet-alert/transition.jq;
      fixtureServer = ./fleet-alert/fixture_server.py;
      fixtures = lib.importJSON ./fleet-alert/fixtures/series.json;

      # ADR-009 item 10, stated here independently of transition.jq.
      priorityOf =
        severity:
        {
          critical = "high";
          warning = "default";
          info = "low";
        }
        .${severity};

      ruleNamed =
        alert:
        lib.findFirst (r: r.alert == alert) (throw "fleet-alert check: no rule ${alert}") evaluatorRules;

      # --- promtool -----------------------------------------------------------

      rulesYaml = pkgs.writeText "fleet-alert-rules.yaml" rules.yaml;

      mutateText =
        name: from: to: text:
        assert lib.assertMsg (lib.hasInfix from text) "fleet-alert check: mutant ${name} found nothing to replace";
        builtins.replaceStrings [ from ] [ to ] text;

      malformedYaml = pkgs.writeText "fleet-alert-rules-malformed.yaml" (
        mutateText "malformedExpression" "increase(node_vmstat_oom_kill[10m]) > 0"
          "increase(node_vmstat_oom_kill[10m] > 0"
          rules.yaml
      );

      promtoolRehearsal =
        pkgs.runCommand "fleet-alert-promtool"
          {
            nativeBuildInputs = [ pkgs.prometheus.cli ];
            meta.description = "R9.2: every rendered rule parses as PromQL, and a malformed expression is rejected";
          }
          ''
            set -euo pipefail
            promtool check rules ${rulesYaml}
            if promtool check rules ${malformedYaml} > malformed.log 2>&1; then
              cat malformed.log
              echo "FAIL: promtool accepted the malformed-expression mutant" >&2
              exit 1
            fi
            cat malformed.log
            echo "mutant malformedExpression rejected"
            touch "$out"
          '';

      # --- fixture legs -------------------------------------------------------

      fixturePassword = "00112233445566778899aabbccddeeff";
      fixtureCredentials = pkgs.runCommand "fleet-alert-fixture-credentials" { } ''
        mkdir "$out"
        printf '%s' ${fixturePassword} > "$out/regulator-password"
        printf '%s' tk_fixture00000000000000000000000 > "$out/alerter-token"
      '';

      # Records each call as { topic, message, headers, tokenFile } and exits
      # with FLEET_ALERT_POST_STATUS.
      ntfySendStub = pkgs.writeShellScriptBin "ntfy-send" ''
        set -euo pipefail
        message=$1
        topic=$2
        shift 2
        headers=()
        while [ "$#" -gt 0 ]; do
          if [ "$1" = -H ]; then
            headers+=("$2")
            shift 2
          else
            shift
          fi
        done
        ${lib.getExe pkgs.jq} -nc --arg topic "$topic" --arg message "$message" \
          --arg tokenFile "''${NTFY_TOKEN_FILE:-}" \
          '{topic: $topic, message: $message, headers: $ARGS.positional, tokenFile: $tokenFile}' \
          --args "''${headers[@]}" >> "$FLEET_ALERT_POSTS"
        exit "''${FLEET_ALERT_POST_STATUS:-0}"
      '';

      evaluatorWith =
        transition:
        self.lib.fleetAlertEvaluator pkgs {
          ntfySend = lib.getExe ntfySendStub;
          inherit transition;
        };
      realEvaluator = evaluatorWith transitionJq;

      checkConfig =
        rulesList:
        pkgs.writeText "fleet-alert-check-config.json" (
          builtins.toJSON {
            storeUrl = "http://127.0.0.1:1";
            database = "fleet";
            user = "regulator";
            queryTimeoutSec = 10;
            queryDeadlineSec = 30;
            postDeadlineSec = 40;
            topic = "fleet-alerts";
            heartbeatTopic = "fleet-heartbeat";
            stateFile = "/nonexistent/state.json";
            failedLog = "/nonexistent/failed.log";
            rules = rulesList;
          }
        );
      realConfig = checkConfig evaluatorRules;

      # Tuesday 2026-10-27 12:00 UTC: outside WeeklyPipelineTest's window.
      t0 = 1793102400;
      minute = n: t0 + 60 * n;

      selectors = lib.unique (
        [ "system_memory_usage_bytes" ] ++ lib.concatMap (r: map (p: p.selector) r.presence) evaluatorRules
      );

      seriesOn =
        host: alert:
        fixtures.series.${alert} // lib.optionalAttrs (fixtures.series.${alert} ? host_name) { host_name = host; };

      vector = at: series: {
        status = "success";
        data = {
          resultType = "vector";
          result = map (s: {
            inherit (s) metric;
            value = [
              at
              s.value
            ];
          }) series;
        };
      };

      attributionAnswers =
        at: host:
        lib.listToAttrs (
          lib.zipListsWith (
            entry: series:
            lib.nameValuePair (builtins.replaceStrings [ "<host>" ] [ host ] entry.query) (
              vector at (
                map (
                  s: s // { metric = s.metric // lib.optionalAttrs (s.metric != { }) { host_name = host; }; }
                ) series
              )
            )
          ) (ruleNamed "HostMemoryPressure").attribution fixtures.attribution
        );

      # Every query the evaluator may issue in one run, with this step's
      # answers: presence selectors return the reporting hosts unless
      # listed in `missing`; rule expressions return the step's `series`;
      # `error` replaces every answer with that HTTP status.
      stepAnswers =
        step:
        let
          reporting =
            step.reporting or [
              "magnetite"
            ];
          missing = step.missing or [ ];
          series = step.series or { };
          presence = lib.listToAttrs (
            map (
              selector:
              lib.nameValuePair "count by (host_name) (${selector})" (
                vector step.at (
                  map (host: {
                    metric.host_name = host;
                    value = "1";
                  }) (if builtins.elem selector missing then [ ] else reporting)
                )
              )
            ) selectors
          );
          ruleAnswers = lib.listToAttrs (
            map (
              r:
              lib.nameValuePair r.expr (
                vector step.at (
                  map (labels: {
                    metric = labels;
                    value = "1";
                  }) (series.${r.alert} or [ ])
                )
              )
            ) (builtins.filter (r: r ? expr) evaluatorRules)
          );
          answers =
            presence
            // ruleAnswers
            // attributionAnswers step.at "magnetite"
            // attributionAnswers step.at "stibnite";
        in
        if step ? error then lib.mapAttrs (_: _: { status = step.error; }) answers else answers;

      responsesFile =
        leg:
        pkgs.writeText "fleet-alert-responses.json" (
          builtins.toJSON (
            lib.listToAttrs (lib.imap0 (i: step: lib.nameValuePair (toString i) (stepAnswers step)) leg.steps)
          )
        );

      both = [
        "magnetite"
        "stibnite"
      ];

      # A rule's condition holds from minute 0 to its `for` plus one, then
      # clears: one FIRING at its `for`, none on the next run, one RESOLVED
      # 5 min after it was last seen.
      fireAndResolve =
        alert:
        let
          f = (ruleNamed alert).for / 60;
          priority = priorityOf (ruleNamed alert).severity;
        in
        {
          name = "${alert} fires once after its for of ${toString f} min and resolves once 5 min after it clears";
          steps = map (n: {
            at = minute n;
            series = lib.optionalAttrs (n <= f + 1) { ${alert} = [ (seriesOn "magnetite" alert) ]; };
          }) (lib.range 0 (f + 7));
          expect = [
            "${toString f} [FIRING] ${alert} magnetite ${priority}"
            "${toString (f + 6)} [RESOLVED] ${alert} magnetite ${priority}"
          ];
          messages = lib.optionals ((ruleNamed alert).attribution != [ ]) [
            "nix-instantiate 471 MB, nix-eval-jobs 400 MB, niks3 314 MB"
            "4120 MB"
            "960 MB"
            "omits swapped-out pages"
          ];
        };

      exclusionRegex =
        let
          m = builtins.match ''.*systemd_unit_name!~"([^"]*)".*'' (ruleNamed "SystemdUnitFailed").expr;
        in
        if m == null then throw "fleet-alert check: SystemdUnitFailed has no systemd_unit_name exclusion" else builtins.head m;
      failedCandidates = map (unit: "${unit}.service") notifiedUnits ++ [ "nginx.service" ];
      storeKeeps = name: builtins.match exclusionRegex name == null;

      exclusionLeg = {
        name = "a failed state for every notified unit posts no SystemdUnitFailed, and nginx, not notified, posts one";
        steps = map (n: {
          at = minute n;
          series.SystemdUnitFailed = map (name: fixtures.series.SystemdUnitFailed // { systemd_unit_name = name; }) (
            builtins.filter storeKeeps failedCandidates
          );
        }) (lib.range 0 5);
        expect = [ "5 [FIRING] SystemdUnitFailed magnetite default" ];
      };

      storeErrorLeg = {
        name = "a store error freezes a firing HostOOMKill, raises StoreQueryFailing after 3 min, heartbeats, and resumes";
        steps = [
          {
            at = minute 0;
            series.HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          error = 503;
          requests = 1;
        }) (lib.range 1 8)
        ++ map (n: { at = minute n; }) (lib.range 9 13);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "4 [FIRING] StoreQueryFailing high"
          "9 [RESOLVED] HostOOMKill magnetite high"
          "13 [RESOLVED] StoreQueryFailing high"
        ];
      };

      silentHostLeg = {
        name = "stibnite falls silent with HostOOMKill firing, posts nothing until it reports, then resolves once";
        steps = [
          {
            at = minute 0;
            reporting = both;
            series.HostOOMKill = [ (seriesOn "stibnite" "HostOOMKill") ];
          }
        ]
        ++ map (n: { at = minute n; }) (lib.range 1 10)
        ++ [
          {
            at = minute 11;
            reporting = both;
            series.HostOOMKill = [ (seriesOn "stibnite" "HostOOMKill") ];
          }
        ]
        ++ map (n: {
          at = minute n;
          reporting = both;
        }) (lib.range 12 16);
        expect = [
          "0 [FIRING] HostOOMKill stibnite high"
          "16 [RESOLVED] HostOOMKill stibnite high"
        ];
      };

      gap = n: t0 + 300 * n;
      signalGapLeg = {
        name = "node_vmstat_oom_kill empty for 30 min while magnetite reports raises one RuleSignalMissing";
        steps = map (n: {
          at = gap n;
          missing = [ "node_vmstat_oom_kill" ];
        }) (lib.range 0 7);
        expect = [ "6 [FIRING] RuleSignalMissing default" ];
        messages = [ "rule=HostOOMKill" ];
      };
      silentGapLeg = {
        name = "the same 30 min gap while every expected host is silent raises nothing";
        steps = map (n: {
          at = gap n;
          reporting = [ ];
          missing = [ "node_vmstat_oom_kill" ];
        }) (lib.range 0 7);
        expect = [ ];
      };

      # Mondays: 2026-10-26 is EDT (UTC-4), 2026-11-02 is EST (UTC-5).
      weekly = at: {
        inherit at;
        series.WeeklyPipelineTest = [ fixtures.series.WeeklyPipelineTest ];
      };
      windowLeg = {
        name = "WeeklyPipelineTest posts once at 09:02 New York time on both sides of the daylight-saving change, never at 08:59, 09:06 or 09:02 EDT clock time in EST";
        steps = map weekly [
          1793019720 # 2026-10-26 09:02 EDT
          1793019960 # 2026-10-26 09:06 EDT
          1793624520 # 2026-11-02 08:02 EST (13:02 UTC, 09:02 under a fixed EDT offset)
          1793627940 # 2026-11-02 08:59 EST
          1793628120 # 2026-11-02 09:02 EST
          1793628360 # 2026-11-02 09:06 EST
        ];
        expect = [
          "0 [FIRING] WeeklyPipelineTest low"
          "4 [FIRING] WeeklyPipelineTest low"
        ];
      };

      restartLoopOn =
        host: unit: (seriesOn host "SystemdUnitRestartLoop") // { systemd_unit_name = unit; };
      budgetUnits = n: map (i: "budget-${toString i}.service") (lib.range 1 n);
      budgetFleetLeg = {
        name = "11 instances within 24 h post all 11 FIRINGs and exactly one AlertBudgetExceeded";
        steps = map (n: {
          at = minute n;
          series.SystemdUnitRestartLoop = map (restartLoopOn "magnetite") (budgetUnits 11);
        }) (lib.range 0 2);
        expect = lib.replicate 11 "0 [FIRING] SystemdUnitRestartLoop magnetite default" ++ [
          "1 [FIRING] AlertBudgetExceeded default"
        ];
      };
      budgetLaptopLeg = {
        name = "4 instances on stibnite within 24 h post exactly one AlertBudgetExceeded";
        steps = map (n: {
          at = minute n;
          reporting = both;
          series.SystemdUnitRestartLoop = map (restartLoopOn "stibnite") (budgetUnits 4);
        }) (lib.range 0 2);
        expect = lib.replicate 4 "0 [FIRING] SystemdUnitRestartLoop stibnite default" ++ [
          "1 [FIRING] AlertBudgetExceeded default"
        ];
      };
      failedLine = at: "${toString at} greptimedb.service magnetite";
      oomRuns = n: {
        at = minute n;
        series.HostOOMKill = [ (seriesOn "magnetite" "HostOOMKill") ];
      };
      budgetFailedLogLeg = {
        name = "10 FAILED lines of the last 24 h and one FIRING exceed the budget";
        failedLog = map (i: failedLine (t0 - 600 * i)) (lib.range 1 10);
        steps = map oomRuns (lib.range 0 2);
        expect = [
          "0 [FIRING] HostOOMKill magnetite high"
          "1 [FIRING] AlertBudgetExceeded default"
        ];
      };
      budgetOldLogLeg = {
        name = "FAILED lines older than 24 h are not counted";
        failedLog =
          map (i: failedLine (t0 - 600 * i)) (lib.range 1 9) ++ map (i: failedLine (t0 - 90000 - i)) (lib.range 1 5);
        steps = map oomRuns (lib.range 0 2);
        expect = [ "0 [FIRING] HostOOMKill magnetite high" ];
      };
      retryLeg = {
        name = "a failed heartbeat fails the run, and the FIRING it left pending is posted once on the next run";
        steps = [
          (
            oomRuns 0
            // {
              postStatus = 1;
              exit = 1;
            }
          )
          (oomRuns 1)
          (oomRuns 2)
        ];
        expect = [ "1 [FIRING] HostOOMKill magnetite high" ];
      };

      legs =
        map fireAndResolve [
          "HostMemoryPressure"
          "HostOOMKill"
          "ZfsPoolUnhealthy"
          "SystemdUnitRestartLoop"
          "SystemdUnitFailed"
          "LocalExporterDown"
        ]
        ++ [
          exclusionLeg
          storeErrorLeg
          silentHostLeg
          signalGapLeg
          silentGapLeg
          windowLeg
          budgetFleetLeg
          budgetLaptopLeg
          budgetFailedLogLeg
          budgetOldLogLeg
          retryLeg
        ];

      runStep =
        leg: step:
        let
          i = toString step.i;
          posts = "$leg_dir/posts-${i}.jsonl";
          exit = toString (step.exit or 0);
        in
        ''
          echo ${i} > "$leg_dir/step"
          : > "${posts}"
          code=0
          FLEET_ALERT_CONFIG="$leg_dir/config.json" FLEET_ALERT_NOW=${toString step.at} \
            FLEET_ALERT_POSTS="${posts}" FLEET_ALERT_POST_STATUS=${toString (step.postStatus or 0)} \
            CREDENTIALS_DIRECTORY=${fixtureCredentials} NTFY_TOKEN_FILE=${fixtureCredentials}/alerter-token \
            "$evaluator" > "$leg_dir/run-${i}.log" 2>&1 || code=$?
          [ "$code" = ${exit} ] \
            || miss "${leg.name}: run ${i} exited $code, expected ${exit}: $(tail -n 3 "$leg_dir/run-${i}.log" | tr '\n' ' ')"
          [ "$(jq -s 'map(select(.topic == "fleet-heartbeat" and any(.headers[]; . == "Priority: min"))) | length' "${posts}")" = 1 ] \
            || miss "${leg.name}: run ${i} did not record exactly one heartbeat at priority min"
          [ "$(jq -s --arg token ${fixtureCredentials}/alerter-token 'all(.[]; .tokenFile == $token)' "${posts}")" = true ] \
            || miss "${leg.name}: run ${i} posted without NTFY_TOKEN_FILE naming the alerter credential"
          ${lib.optionalString ((step.postStatus or 0) == 0) ''
            jq -r 'select(.topic == "fleet-alerts") | "${i} " + ([.headers[] | select(startswith("Title: ")) | ltrimstr("Title: ")] | first) + " " + ([.headers[] | select(startswith("Priority: ")) | ltrimstr("Priority: ")] | first)' "${posts}" >> "$leg_dir/actual"
            jq -r 'select(.topic == "fleet-alerts") | .message' "${posts}" >> "$leg_dir/messages"
          ''}
          ${lib.optionalString (step ? requests) ''
            [ "$(grep -c '^REQUEST ${i} ' "$leg_dir/server.log")" = ${toString step.requests} ] \
              || miss "${leg.name}: run ${i} queried again after a failed query"
          ''}
        '';

      runLeg =
        { evaluator, config }:
        leg:
        let
          expected = pkgs.writeText "fleet-alert-expected" (lib.concatMapStrings (line: line + "\n") leg.expect);
        in
        ''
          echo "--- ${leg.name}"
          evaluator=${evaluator}
          leg_dir=$(mktemp -d)
          : > "$leg_dir/actual"
          : > "$leg_dir/messages"
          printf '%s' ${lib.escapeShellArg (lib.concatMapStrings (line: line + "\n") (leg.failedLog or [ ]))} > "$leg_dir/failed.log"
          python3 ${fixtureServer} --responses ${responsesFile leg} \
            --step-file "$leg_dir/step" --port-file "$leg_dir/port" > "$leg_dir/server.log" 2>&1 &
          server_pid=$!
          for _ in $(seq 100); do [ -s "$leg_dir/port" ] && break; sleep 0.1; done
          if [ -s "$leg_dir/port" ]; then
            jq --arg url "http://127.0.0.1:$(cat "$leg_dir/port")" --arg state "$leg_dir/state.json" \
              --arg failed "$leg_dir/failed.log" \
              '.storeUrl = $url | .stateFile = $state | .failedLog = $failed' ${config} > "$leg_dir/config.json"
            ${lib.concatMapStrings (runStep leg) (lib.imap0 (i: step: step // { inherit i; }) leg.steps)}
          else
            miss ${lib.escapeShellArg "${leg.name}: the fixture server did not start"}
          fi
          kill "$server_pid" 2>/dev/null || true
          wait "$server_pid" 2>/dev/null || true
          server_pid=
          if grep -E '^(VIOLATION|UNEXPECTED) ' "$leg_dir/server.log" >&2; then
            miss ${lib.escapeShellArg "${leg.name}: the fixture server recorded a violation or an unexpected query"}
          fi
          if ! diff -u ${expected} "$leg_dir/actual" >&2; then
            miss ${lib.escapeShellArg "${leg.name}: the alert posts differ from the expected list"}
          fi
          ${lib.concatMapStrings (text: ''
            grep -qF -- ${lib.escapeShellArg text} "$leg_dir/messages" \
              || miss ${lib.escapeShellArg "${leg.name}: no posted message carries: ${text}"}
          '') (leg.messages or [ ])}
        '';

      mutantTransition =
        name: from: to:
        pkgs.writeText "transition-${name}.jq" (mutateText name from to (builtins.readFile transitionJq));

      # ADR-009 R9.2's runtime mutants; the fifth, a malformed expression, is
      # promtoolRehearsal's.
      runtimeMutants = {
        noStateWrite = {
          evaluator = realEvaluator.overrideAttrs (old: {
            text = mutateText "noStateWrite" ''mv -f "$state_file.tmp" "$state_file"'' ''rm -f "$state_file.tmp"'' old.text;
          });
          config = realConfig;
          legs = [ (fireAndResolve "HostOOMKill") ];
        };
        forZero = {
          evaluator = realEvaluator;
          config = checkConfig (
            map (r: if r.alert == "HostMemoryPressure" then r // { for = 0; } else r) evaluatorRules
          );
          legs = [ (fireAndResolve "HostMemoryPressure") ];
        };
        noStoreFreeze = {
          evaluator = evaluatorWith (
            mutantTransition "noStoreFreeze" "  elif $observations.storeError then true\n"
              "  elif $observations.storeError then false\n"
          );
          config = realConfig;
          legs = [ storeErrorLeg ];
        };
        noAbsenceFreeze = {
          evaluator = evaluatorWith (
            mutantTransition "noAbsenceFreeze"
              "  else (($inst.labels.host_name) as $h | any(($observations.reporting // [])[]; . == $h) | not)\n"
              "  else false\n"
          );
          config = realConfig;
          legs = [ silentHostLeg ];
        };
      };

      mutantRun = name: mutant: ''
        echo "=== mutant ${name}"
        misses="$TMPDIR/misses-${name}"
        : > "$misses"
        ${lib.concatMapStrings (runLeg {
          evaluator = lib.getExe mutant.evaluator;
          inherit (mutant) config;
        }) mutant.legs}
        if [ -s "$misses" ]; then
          echo "mutant ${name} rejected: $(head -n 1 "$misses")"
        else
          echo "FAIL: mutant ${name} produced no failure" >&2
          mutant_missed=1
        fi
      '';

      controlResponses = pkgs.writeText "fleet-alert-control-responses.json" (
        builtins.toJSON { "0".up = vector t0 [ ]; }
      );

      # The fixture server's own clauses, each with its negative control.
      serverControls = ''
        echo "--- the fixture server refuses other paths, databases and accounts, and detects two open requests"
        control=$(mktemp -d)
        echo 0 > "$control/step"
        python3 ${fixtureServer} --responses ${controlResponses} \
          --step-file "$control/step" --port-file "$control/port" > "$control/server.log" 2>&1 &
        server_pid=$!
        for _ in $(seq 100); do [ -s "$control/port" ] && break; sleep 0.1; done
        [ -s "$control/port" ] || { echo "FAIL: the control fixture server did not start" >&2; exit 1; }
        port=$(cat "$control/port")
        query_url="http://127.0.0.1:$port/v1/prometheus/api/v1/query"
        ask() {
          printf 'user = "%s"\n' "$1" | curl --config - --silent --output /dev/null --write-out '%{http_code}' "''${@:2}" || true
        }
        expect_code() {
          [ "$2" = "$3" ] || { echo "FAIL: fixture server: $1 answered $2, expected $3" >&2; exit 1; }
        }
        good=regulator:${fixturePassword}
        expect_code "the query path" "$(ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 200
        expect_code "another path" "$(ask "$good" -H 'x-greptime-db-name: fleet' "http://127.0.0.1:$port/v1/sql")" 404
        expect_code "a query without the database header" "$(ask "$good" --get --data-urlencode 'query=up' "$query_url")" 400
        expect_code "another account" "$(ask perses:${fixturePassword} -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        expect_code "a wrong password" "$(ask regulator:wrong -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url")" 401
        python3 -c 'import socket, sys, time; s = socket.create_connection(("127.0.0.1", int(sys.argv[1]))); time.sleep(10)' "$port" &
        holder=$!
        sleep 1
        ask "$good" -H 'x-greptime-db-name: fleet' --get --data-urlencode 'query=up' "$query_url" > /dev/null
        for _ in $(seq 50); do kill -0 "$server_pid" 2>/dev/null || break; sleep 0.1; done
        if kill -0 "$server_pid" 2>/dev/null; then
          kill "$server_pid" "$holder" 2>/dev/null || true
          echo "FAIL: the fixture server kept serving with two requests open" >&2
          exit 1
        fi
        server_status=0
        wait "$server_pid" || server_status=$?
        server_pid=
        kill "$holder" 2>/dev/null || true
        if [ "$server_status" = 0 ] || ! grep -q '^VIOLATION two requests open at once' "$control/server.log"; then
          cat "$control/server.log" >&2
          echo "FAIL: the fixture server did not record two open requests" >&2
          exit 1
        fi
        echo "ok: fixture server refusals and the concurrency guard"
      '';

      fixtureRehearsal =
        pkgs.runCommand "fleet-alert-fixtures"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.curl
              pkgs.diffutils
              pkgs.gnugrep
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "R9.2: the evaluator against a replaying fixture server; every leg passes and every runtime mutant fails a leg";
          }
          ''
            set -euo pipefail
            server_pid=
            trap '[ -z "$server_pid" ] || kill "$server_pid" 2>/dev/null || true' EXIT
            miss() {
              printf 'MISS %s\n' "$*" >&2
              printf '%s\n' "$*" >> "$misses"
            }
            ${serverControls}
            misses="$TMPDIR/misses-real"
            : > "$misses"
            ${lib.concatMapStrings (runLeg {
              evaluator = lib.getExe realEvaluator;
              config = realConfig;
            }) legs}
            mutant_missed=0
            ${lib.concatStrings (lib.mapAttrsToList mutantRun runtimeMutants)}
            if [ -s "$TMPDIR/misses-real" ]; then
              echo "FAIL: the evaluator failed these legs:" >&2
              cat "$TMPDIR/misses-real" >&2
              exit 1
            fi
            echo "ok: every leg passed"
            [ "$mutant_missed" = 0 ]
            touch "$out"
          '';

      # --- property test ------------------------------------------------------

      jqLibOf =
        name: transition:
        pkgs.linkFarm "fleet-alert-jq-${name}" [
          {
            name = "transition.jq";
            path = transition;
          }
        ];
      noRepostTransition =
        mutantTransition "noRepost" ''>= repost_every then "repost"'' ''>= repost_every and false then "repost"'';

      propertyRehearsal =
        pkgs.runCommand "fleet-alert-property"
          {
            nativeBuildInputs = [
              (pkgs.python3.withPackages (p: [ p.hypothesis ]))
              pkgs.jq
              pkgs.gnugrep
            ];
            meta.description = "D11: transition.jq equals the reference model on derandomized Hypothesis timelines, and the no-re-post mutant is caught";
          }
          ''
            set -euo pipefail
            export HOME="$TMPDIR"
            cd "$TMPDIR"
            FLEET_ALERT_JQ_LIB=${jqLibOf "real" transitionJq} python3 ${./fleet-alert}/test_transition.py
            if FLEET_ALERT_JQ_LIB=${jqLibOf "noRepost" noRepostTransition} python3 ${./fleet-alert}/test_transition.py > no-repost.log 2>&1; then
              cat no-repost.log
              echo "FAIL: the property test accepted the no-re-post mutant" >&2
              exit 1
            fi
            cat no-repost.log
            grep -q 'Falsifying' no-repost.log
            echo "mutant noRepost rejected"
            touch "$out"
          '';
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        fleet-alert =
          pkgs.runCommand "fleet-alert"
            {
              passthru = {
                inherit
                  rules
                  promtoolRehearsal
                  fixtureRehearsal
                  propertyRehearsal
                  ;
              };
            }
            ''
              # R9.2: rules parse; the evaluator against fixtures; the model.
              test -e ${promtoolRehearsal}
              test -e ${fixtureRehearsal}
              test -e ${propertyRehearsal}
              touch "$out"
            '';
      };
    };
}
```

Run: `jj st --no-pager >/dev/null && nix eval --json .#checks.x86_64-linux --apply 'c: c ? fleet-alert'`
Expected: `true` (the attribute exists; nothing below it is forced).

- [ ] **Step 7: Run the promtool part and see it fail**

Run: `nix build --no-link .#checks.x86_64-linux.fleet-alert.promtoolRehearsal 2>&1 | tee logs/s3-evidence/4.1-red-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 5`
Expected: evaluation fails with `error: attribute 'fleetAlertRules' missing`.

- [ ] **Step 8: Write the rule table**

Create `modules/nixos/fleet-alert/rules.nix`:

```nix
# The fleet alert rule table (ADR-009 Decision items 2, 5, 7, 14; design
# D10, D14, D16; tasks.md 4.1).
#
# One Nix source for the evaluator and for promtool. fleetAlertRules returns
# `rules`; `json`, the evaluator's rule list with `for` in seconds; and
# `yaml`, a Prometheus rules file of the rules with an expression, written as
# JSON (which YAML accepts) and read only by checks.x86_64-linux.fleet-alert's
# promtool pass. The expressions are ADR-009's rule table as amended
# (ADR-009-alerting.md:102-119), measured on magnetite on 2026-10-18
# (logs/s3/series-labels.md): each carries its threshold, because an instant
# query returns every input series otherwise, and SystemdUnitFailed writes
# its literal dot as `[.]`, because GreptimeDB 1.2.1 rejects `\.` in
# double-quoted and backtick strings, so no expression may contain a
# backslash. SystemdUnitFailed excludes `notifiedUnits`, the evaluating
# host's services.observability-notify.units, so the notifier and the rule
# never report one failure twice (D10); when S4 adds notified units on other
# hosts, this must become their union (design D10, "Later slices").
#
# StoreQueryFailing and RuleSignalMissing have no expression: transition.jq
# raises them, and they are listed so their `for` lives in this one table.
# The expected host is magnetite alone until S4 brings other hosts' series.
{
  flake.lib.fleetAlertRules =
    { lib, notifiedUnits }:
    let
      presence = selector: {
        inherit selector;
        expectedHosts = [ "magnetite" ];
      };

      # Appended to HostMemoryPressure and HostOOMKill messages (ADR-009 item
      # 5); the evaluator substitutes the firing host for <host>.
      memoryAttribution = [
        {
          name = "top 3 executables by resident memory, which omits swapped-out pages";
          query = ''topk(3, process_memory_usage_bytes{host_name="<host>"})'';
          label = "process_executable_name";
        }
        {
          name = "ZFS ARC size";
          query = ''node_zfs_arc_size{host_name="<host>"}'';
          label = null;
        }
        {
          name = "swap used";
          query = ''sum(system_paging_usage_bytes{host_name="<host>", state="used"})'';
          label = null;
        }
      ];

      units = lib.unique (lib.naturalSort notifiedUnits);
      notifiedRegex =
        assert lib.assertMsg (lib.all (unit: builtins.match "[A-Za-z0-9_-]+" unit != null) units)
          "fleetAlertRules: notified unit names must match [A-Za-z0-9_-]+, so the exclusion needs no escape; got ${builtins.toJSON units}";
        "(${lib.concatStringsSep "|" units})[.]service";

      rule =
        r:
        {
          presence = [ ];
          attribution = [ ];
        }
        // r;

      rules = map rule [
        {
          alert = "HostMemoryPressure";
          expr = ''((sum by (host_name) (system_linux_memory_available_bytes) + sum by (host_name) (node_zfs_arc_size - node_zfs_arc_c_min)) / (sum by (host_name) (system_memory_usage_bytes{state="used"}) + sum by (host_name) (system_linux_memory_available_bytes)) < 0.10) or (sum by (host_name) (system_paging_usage_bytes{state="used"}) / sum by (host_name) (system_paging_usage_bytes) > 0.85)'';
          for = "5m";
          severity = "warning";
          annotations.summary = "Available memory, counting the ZFS ARC above its minimum, is below 10 % of total, or swap use is above 85 %";
          presence = map presence [
            "system_linux_memory_available_bytes"
            "node_zfs_arc_size"
            "system_memory_usage_bytes"
            "system_paging_usage_bytes"
          ];
          attribution = memoryAttribution;
        }
        {
          alert = "HostOOMKill";
          expr = "increase(node_vmstat_oom_kill[10m]) > 0";
          for = "0s";
          severity = "critical";
          annotations.summary = "The kernel killed a process for memory in the last 10 min";
          presence = [ (presence "node_vmstat_oom_kill") ];
          attribution = memoryAttribution;
        }
        {
          alert = "ZfsPoolUnhealthy";
          expr = ''node_zfs_zpool_state{state!="online"} == 1'';
          for = "1m";
          severity = "critical";
          annotations.summary = "A ZFS pool is not online";
          presence = [ (presence "node_zfs_zpool_state") ];
        }
        {
          alert = "SystemdUnitRestartLoop";
          expr = "increase(systemd_service_restarts_total[15m]) > 5";
          for = "0s";
          severity = "warning";
          annotations.summary = "A unit restarted more than 5 times in 15 min";
          presence = [ (presence "systemd_service_restarts_total") ];
        }
        {
          alert = "SystemdUnitFailed";
          expr = ''systemd_unit_state{systemd_unit_active_state="failed", systemd_unit_name!~"${notifiedRegex}"} == 1'';
          for = "5m";
          severity = "warning";
          annotations.summary = "A unit the failure notifier does not report has failed";
          presence = [ (presence "systemd_unit_state") ];
        }
        {
          alert = "LocalExporterDown";
          expr = ''up{job=~"node|smartctl"} == 0'';
          for = "10m";
          severity = "warning";
          annotations.summary = "A loopback exporter the collector scrapes is down";
          presence = [ (presence ''up{job="node"}'') ];
        }
        {
          alert = "WeeklyPipelineTest";
          expr = "count(count by (host_name) (system_memory_usage_bytes))";
          for = "0s";
          severity = "info";
          annotations.summary = "Weekly test of the alert path: the value is the number of hosts reporting host memory";
          presence = [ (presence "system_memory_usage_bytes") ];
          window = {
            zone = "America/New_York";
            weekday = 1;
            start = "09:00";
            end = "09:05";
          };
        }
        {
          alert = "StoreQueryFailing";
          for = "3m";
          severity = "critical";
          annotations.summary = "The telemetry store has not answered the evaluator's queries; every other alert instance is frozen";
        }
        {
          alert = "RuleSignalMissing";
          for = "30m";
          severity = "warning";
          annotations.summary = "A rule's presence selector returned no series while an expected host reported host memory, so the rule cannot fire";
        }
      ];

      seconds =
        duration:
        let
          m = builtins.match "([0-9]+)([smh])" duration;
        in
        assert lib.assertMsg (m != null) "fleetAlertRules: `for` must be <n>s, <n>m or <n>h, got ${duration}";
        lib.toInt (builtins.head m)
        * {
          s = 1;
          m = 60;
          h = 3600;
        }
        .${builtins.elemAt m 1};

      promRule = r: {
        inherit (r)
          alert
          expr
          for
          annotations
          ;
        labels.severity = r.severity;
      };
    in
    {
      inherit rules;
      json = builtins.toJSON (map (r: r // { for = seconds r.for; }) rules);
      yaml = builtins.toJSON {
        groups = [
          {
            name = "fleet-alert";
            rules = map promRule (builtins.filter (r: r ? expr) rules);
          }
        ];
      };
    };
}
```

- [ ] **Step 9: Run the promtool part and see it pass; check the rendered expressions**

Run: `jj st --no-pager >/dev/null && nix build --no-link -L .#checks.x86_64-linux.fleet-alert.promtoolRehearsal 2>&1 | tee logs/s3-evidence/4.1-promtool-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E 'SUCCESS|FAILED|rejected'`
Expected: a `SUCCESS: 7 rules found` line for the real file, a `FAILED` line naming a parse error for the malformed file, and `mutant malformedExpression rejected`.

Run:

```bash
nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json 2>&1 | tee logs/s3-evidence/4.1-rules-json-$(date -u +%Y%m%dT%H%M%SZ).log \
  | jq -r '"rules: \(length)", "with backslash: \([.[] | select(.expr // "" | contains("\\"))] | length)", "dot as [.]service: \([.[] | select(.expr // "" | contains("[.]service"))] | map(.alert))", "for: \(map({(.alert): .for}) | add)", "selectors: \([.[].presence[].selector] | unique | length)"'
```

Expected:

```
rules: 9
with backslash: 0
dot as [.]service: ["SystemdUnitFailed"]
for: {"HostMemoryPressure":300,"HostOOMKill":0,"ZfsPoolUnhealthy":60,"SystemdUnitRestartLoop":0,"SystemdUnitFailed":300,"LocalExporterDown":600,"WeeklyPipelineTest":0,"StoreQueryFailing":180,"RuleSignalMissing":1800}
selectors: 9
```

The JSON text itself escapes each `"` of a label matcher as `\"`, which is JSON syntax, not part of the expression; the count above is over the decoded expressions, which is what reaches the store (see questions on tasks.md 4.1's wording).
Run: `nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -r '.[] | select(.alert == "SystemdUnitFailed") | .expr'`
Expected: `systemd_unit_state{systemd_unit_active_state="failed", systemd_unit_name!~"(greptimedb|greptimedb-envelope|greptimedb-schema|opentelemetry-collector|zfs-assert-root-docker-noautosnap|zfs-assert-root-greptimedb-noautosnap|zfs-assert-root-nix-noautosnap|zfs-assert-root-podman-noautosnap|zfs-set-root-greptimedb-quota|zfs-set-root-greptimedb-reservation|zfs-set-root-home-reservation|zfs-set-root-nix-quota|zfs-set-root-nixos-reservation)[.]service"} == 1` (magnetite's 13 notified units before Step 25 adds `fleet-alert`).

- [ ] **Step 10: Run the property part and see it fail**

Run: `nix build --no-link .#checks.x86_64-linux.fleet-alert.propertyRehearsal 2>&1 | tee logs/s3-evidence/4.2-red-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 5`
Expected: evaluation fails with `error: path '…/modules/nixos/fleet-alert/transition.jq' does not exist`.

- [ ] **Step 11: Write the transition function**

Create `modules/nixos/fleet-alert/transition.jq`:

```jq
# Alert-instance transition for fleet-alert (ADR-009 items 3-7, 17, R9.1;
# design D11, D15; tasks.md 4.2).
#
# Pure: the input is the state (null or {} on a first run), and
# transition($observations; $now; $rules) returns {state, posts}; nothing
# here reads a clock, a file or the environment, except in_window, which the
# evaluator runs under TZ=<window zone>. An instance is one rule plus its
# result label set. It fires once its condition has held on every run for
# the rule's `for` (seconds) and resolves once the condition has been absent
# 300 s; a critical instance is re-posted every 24 h, a warning never, and an
# info instance posts no RESOLVED and is not counted. A store error freezes
# every instance but StoreQueryFailing; a host missing from `reporting`
# (system_memory_usage_bytes) freezes the instances labelled with it.
# StoreQueryFailing and RuleSignalMissing are raised only if $rules lists
# them, with their `for`. Posts carry no topic; the caller adds it. The
# caller posts in order and applies mark_posted($post) to the saved state
# after each successful post, so a failed post or a killed run leaves the
# difference for the next run (D15). modules/checks/fleet-alert/model.py is
# the reference model the property test compares this file with.

def resolve_after: 300;
def repost_every: 86400;
def budget_window: 86400;
def budget_fleet: 10;
def budget_hosts: { stibnite: 3, pyrite: 3 };

def priority_of($severity):
  { critical: "high", warning: "default", info: "low" }[$severity] // "default";

def instance_id($alert; $labels):
  [$alert, ($labels | to_entries | sort_by(.key))] | tojson;

def normalize_state:
  { instances: {}, hosts: {}, firings: [], budgetPostedAt: null, lastRun: null } + (. // {});

def title($kind; $alert; $host):
  "[\(if $kind == "resolved" then "RESOLVED" else "FIRING" end)] \($alert)"
  + (if $host == "" then "" else " \($host)" end);

def minutes_of($hhmm): ($hhmm | split(":") | map(tonumber)) as $p | $p[0] * 60 + $p[1];

# jq's localtime gives [year, month, mday, hours, minutes, seconds,
# wday (Sunday 0), yday]; $window.weekday is ISO (Monday 1); end exclusive.
def in_window($window; $now):
  ($now | localtime) as $t
  | ($t[3] * 60 + $t[4]) as $minute
  | ((if $t[6] == 0 then 7 else $t[6] end) == $window.weekday)
    and $minute >= minutes_of($window.start)
    and $minute < minutes_of($window.end);

def rule_named($rules; $name): [ $rules[] | select(.alert == $name) ] | .[0];

# A rule is evaluated from $observations.results when it has an `expr` (the
# evaluator's PromQL rules) or when results has an entry for its alert name
# (a caller's own query, such as fleet-deadman's AlertEvaluatorSilent);
# StoreQueryFailing and RuleSignalMissing come only from the logic below.
def internal_rule($alert): $alert | IN("StoreQueryFailing", "RuleSignalMissing");

def conditions($observations; $rules):
  if $observations.storeError then
    [ rule_named($rules; "StoreQueryFailing") | select(. != null) | {rule: ., labels: {}, value: "1"} ]
  else
    [ $rules[] | . as $r
      | select(has("expr")
               or ((internal_rule($r.alert) | not) and (($observations.results // {}) | has($r.alert))))
      | select(($r.window == null) or ($observations.windows[$r.alert] == true))
      | ($observations.results[$r.alert] // [])[]
      | {rule: $r, labels: (.labels | del(.__name__)), value: (.value | tostring)} ]
    + ( rule_named($rules; "RuleSignalMissing") as $missing
        | if $missing == null then [] else
            [ $rules[] | . as $r | ($r.presence // [])[]
              | select((($observations.presence[.selector] // []) | length) == 0)
              | select(. as $p | any(($observations.reporting // [])[]; . as $h | any($p.expectedHosts[]; . == $h)))
              | {rule: $missing, labels: {rule: $r.alert, selector: .selector}, value: "0"} ]
          end )
  end;

def frozen($inst; $observations):
  if $inst.alert == "StoreQueryFailing" then false
  elif $observations.storeError then true
  elif ($inst.labels.host_name // null) == null then false
  else (($inst.labels.host_name) as $h | any(($observations.reporting // [])[]; . == $h) | not)
  end;

def advance($inst; $cond; $now):
  if $cond != null then
    ($inst // { alert: $cond.rule.alert, labels: $cond.labels, phase: "pending",
                activeSince: $now, firingPostedAt: null, lastPostedAt: null })
    | . + { severity: $cond.rule.severity, for: $cond.rule.for,
            summary: ($cond.rule.annotations.summary // ""),
            attributed: ((($cond.rule.attribution // []) | length) > 0),
            value: $cond.value, lastSeen: $now }
    | if .phase == "resolved" then .phase = "firing" else . end
    | if .phase == "pending" and ($now - .activeSince) >= .for then .phase = "firing" else . end
  elif $inst == null then null
  elif $inst.phase == "pending" then null
  elif $inst.phase == "firing" and ($now - $inst.lastSeen) >= resolve_after then
    if $inst.severity == "info" or $inst.firingPostedAt == null then null
    else $inst | .phase = "resolved" end
  else $inst
  end;

def post_for($id; $inst; $now; $observations):
  ($inst.labels.host_name // "") as $host
  | ( if $inst.phase == "firing" and $inst.firingPostedAt == null then "firing"
      elif $inst.phase == "firing" and $inst.severity == "critical" and ($now - $inst.lastPostedAt) >= repost_every then "repost"
      elif $inst.phase == "resolved" then "resolved"
      else empty end ) as $kind
  | { title: title($kind; $inst.alert; $host),
      priority: priority_of($inst.severity),
      message: ( [ $inst.summary,
                   ($inst.labels | to_entries | map("\(.key)=\(.value)") | join(", ")),
                   (if $kind != "resolved" then "value \($inst.value)" else empty end),
                   (if $kind != "resolved" and $inst.attributed and $host != ""
                    then ($observations.attribution[$host] // "attribution unavailable") else empty end) ]
                 | map(select(. != "")) | join("\n") ),
      key: { kind: $kind, id: $id } };

def budget_post($state; $observations; $now):
  ( [ $state.firings[] | {key: "\(.alert) \(.host)", host} ]
    + [ ($observations.failedLog // [])[] | select(.at > $now - budget_window)
        | {key: "FAILED \(.unit) \(.host)", host} ] ) as $all
  | ($all | length) as $total
  | [ budget_hosts | to_entries[] | . as $limit
      | select(([ $all[] | select(.host == $limit.key) ] | length) > $limit.value) ] as $laptops
  | if ($total > budget_fleet or ($laptops | length) > 0)
       and ($state.budgetPostedAt == null or ($now - $state.budgetPostedAt) >= budget_window)
    then ( $all | group_by(.key) | map({key: .[0].key, count: length}) | sort_by(-.count, .key) | .[0] ) as $top
      | [ { title: "[FIRING] AlertBudgetExceeded",
            priority: "default",
            message: "\($total) FIRING posts and failure notices in 24 h exceed the alert budget (10 fleet-wide, 3 per laptop); most firings: \($top.key) (\($top.count)). Nothing is suppressed; review the threshold.",
            key: { kind: "budget", id: "AlertBudgetExceeded" } } ]
    else [] end;

def transition($observations; $now; $rules):
  normalize_state
  | .firings |= map(select(.at > $now - budget_window))
  | . as $state
  | ( conditions($observations; $rules)
      | map({key: instance_id(.rule.alert; .labels), value: .}) | from_entries ) as $conds
  | ( [ ($state.instances | keys[]), ($conds | keys[]) ] | unique ) as $ids
  | ( reduce $ids[] as $id ({};
        $state.instances[$id] as $inst
        | $conds[$id] as $cond
        | if frozen(($inst // {alert: $cond.rule.alert, labels: $cond.labels}); $observations) then
            (if $inst == null then . else .[$id] = $inst end)
          else
            advance($inst; $cond; $now) as $next
            | if $next == null then . else .[$id] = $next end
          end) ) as $instances
  | ( $state
      | .instances = $instances
      | .lastRun = $now
      | if $observations.storeError then .
        else .hosts += (reduce ($observations.reporting // [])[] as $h ({}; .[$h] = $now)) end ) as $next
  | { state: $next,
      posts: ( [ $ids[] as $id
                 | $instances[$id] as $inst
                 | select($inst != null)
                 | select(frozen($inst; $observations) | not)
                 | post_for($id; $inst; $now; $observations) ]
               + budget_post($next; $observations; $now) ) };

def mark_posted($post):
  normalize_state
  | .lastRun as $t
  | if $post.key.kind == "firing" or $post.key.kind == "repost" then
      .instances[$post.key.id] as $inst
      | if $inst == null then .
        else .instances[$post.key.id] = ($inst | .firingPostedAt = (.firingPostedAt // $t) | .lastPostedAt = $t)
          | if $inst.severity == "info" then .
            else .firings += [ {at: $t, alert: $inst.alert, host: ($inst.labels.host_name // "")} ] end
        end
    elif $post.key.kind == "resolved" then del(.instances[$post.key.id])
    elif $post.key.kind == "budget" then .budgetPostedAt = $t
    else . end;
```

Run, as a quick sanity check before the build: `jq -n -L modules/nixos/fleet-alert 'include "transition"; null | transition({storeError: false, results: {A: [{labels: {host_name: "m"}, value: "1"}]}, presence: {}, reporting: ["m"], failedLog: []}; 1000; [{alert: "A", expr: "a", for: 0, severity: "critical", annotations: {summary: "s"}, presence: [], attribution: []}]) | .posts | map(.title)'`
Expected: `["[FIRING] A m"]` (printed over several lines).
Run: `TZ=America/New_York TZDIR=$(nix build --no-link --print-out-paths nixpkgs#tzdata)/share/zoneinfo jq -n -L modules/nixos/fleet-alert 'include "transition"; [1793628120, 1793624520] | map(in_window({weekday: 1, start: "09:00", end: "09:05"}; .))' -c`
Expected: `[true,false]`.

- [ ] **Step 12: Run the property part and see it pass, with the mutant rejected**

Run: `jj st --no-pager >/dev/null && nix build --no-link -L .#checks.x86_64-linux.fleet-alert.propertyRehearsal 2>&1 | tee logs/s3-evidence/4.6-property-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^fleet-alert-property> (ok:|mutant|Falsifying|FAIL)'`
Expected: `ok: transition.jq equals the reference model on every generated timeline`, then a `Falsifying example: test_transition_matches_model(` line from the mutant run with its shrunk timeline, then `mutant noRepost rejected`.
If the first run fails, the log's assertion names the run and the differing posts or state; fix whichever of `transition.jq` and `model.py` departs from the specification in the module headers, never by loosening the comparison.
If the mutant is not caught, stop and report: `max_examples` is a reviewed constant (design "Trade-offs").

Run the determinism check: `nix build --no-link --print-out-paths --rebuild .#checks.x86_64-linux.fleet-alert.propertyRehearsal 2>&1 | tee -a logs/s3-evidence/4.6-property-*.log | tail -n 1`
Expected: the rebuild succeeds and prints the same output path as the first build (`--rebuild` fails if the output differs).

- [ ] **Step 13: Run the fixture part and see it fail**

Run: `nix build --no-link .#checks.x86_64-linux.fleet-alert.fixtureRehearsal 2>&1 | tee logs/s3-evidence/4.5-red-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 5`
Expected: evaluation fails with `error: attribute 'fleetAlertEvaluator' missing`.

- [ ] **Step 14: Write the evaluator module**

Create `modules/nixos/fleet-alert.nix`:

```nix
# Fleet alert evaluator (ADR-009 Decision items 1-8, 10, 14, 17; R9.1, R9.5;
# design D11-D16, D18; tasks.md 4.3, 4.4).
#
# fleet-alert.timer starts fleet-alert.service every minute. The evaluator
# reads its configuration from the JSON at FLEET_ALERT_CONFIG, queries the
# store's PromQL API one query at a time as `regulator` (password from
# $CREDENTIALS_DIRECTORY/regulator-password, passed to curl on stdin, as
# modules/lib/greptimedb-envelope.nix does), each with --max-time
# queryTimeoutSec, and ends the query phase at the first failed query or at
# queryDeadlineSec: a store error, which transition.jq turns into a freeze
# and, after 3 min, StoreQueryFailing. It reads the notifier's failed.log,
# applies transition.jq's pure transition to state.json, writes the state,
# posts the heartbeat at priority min, then posts each alert through
# ntfy-send, which reads the alerter token from NTFY_TOKEN_FILE, and records
# each successful post with mark_posted, writing the state through a
# temporary file and a rename. No post starts after postDeadlineSec, and a
# failed heartbeat or post fails the run, so the notifier reports it and the
# next run retries what is unposted. A run with a store error that posts
# its heartbeat exits 0.
#
# WeeklyPipelineTest's window is evaluated under TZ=<window zone> with the
# tz database at TZDIR, for that rule only; the host's time zone is not
# used. FLEET_ALERT_NOW, set only by checks.x86_64-linux.fleet-alert,
# replaces the clock.
#
# Site-neutral and free of clan vars, as modules/nixos/greptimedb.nix is:
# the host sets tokenFile and regulatorPasswordFile. The rules come from
# fleet-alert/rules.nix with the host's services.observability-notify.units.
# The check runs flake.lib.fleetAlertEvaluator, the same function, against a
# fixture server with a recording ntfy-send. R9.5 is an assertion below:
# fleet-alert.service runs with MemoryMax = 64M and TimeoutStartSec = 50s.
# The kill order (evaluator 900, store 500, collector 300, this unit 0) is
# judged by checks.x86_64-linux.greptimedb-envelope.
{ config, ... }:
let
  flakeLib = config.flake.lib;
  transitionJq = ./fleet-alert/transition.jq;
  jqLib =
    pkgs: transition:
    pkgs.linkFarm "fleet-alert-jq" [
      {
        name = "transition.jq";
        path = transition;
      }
    ];

  fleetAlertEvaluator =
    pkgs:
    {
      ntfySend,
      transition ? transitionJq,
    }:
    pkgs.writeShellApplication {
      name = "fleet-alert";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      # `$name` inside the jq programs is a jq variable, not a shell expansion.
      excludeShellChecks = [ "SC2016" ];
      text = ''
        config=''${FLEET_ALERT_CONFIG:?FLEET_ALERT_CONFIG is unset}
        credentials=''${CREDENTIALS_DIRECTORY:?CREDENTIALS_DIRECTORY is unset}
        now=''${FLEET_ALERT_NOW:-$(date +%s)}
        export TZDIR=${pkgs.tzdata}/share/zoneinfo
        jqlib=${jqLib pkgs transition}

        setting() {
          jq -er --arg key "$1" '.[$key]' "$config"
        }
        store_url=$(setting storeUrl)
        database=$(setting database)
        user=$(setting user)
        query_timeout=$(setting queryTimeoutSec)
        query_deadline=$(setting queryDeadlineSec)
        post_deadline=$(setting postDeadlineSec)
        topic=$(setting topic)
        heartbeat_topic=$(setting heartbeatTopic)
        state_file=$(setting stateFile)
        failed_log=$(setting failedLog)

        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT
        : > "$work/presence.jsonl"
        : > "$work/results.jsonl"
        : > "$work/windows.jsonl"
        : > "$work/attribution.jsonl"

        # One instant query; its body lands in $work/body. Fails on a
        # transport error, a timeout, any status but 200, a body that is not
        # a vector, or when the query deadline has passed.
        query() {
          local remaining status
          remaining=$((query_deadline - SECONDS))
          if [ "$remaining" -le 0 ]; then
            echo "fleet-alert: query deadline of ''${query_deadline}s reached" >&2
            return 1
          fi
          if [ "$remaining" -gt "$query_timeout" ]; then
            remaining=$query_timeout
          fi
          if ! status=$(printf 'user = "%s:%s"\n' "$user" "$(< "$credentials/regulator-password")" \
            | curl --config - --silent --show-error --max-time "$remaining" \
                --header "x-greptime-db-name: $database" \
                --get --data-urlencode "query=$1" \
                --output "$work/body" --write-out '%{http_code}' \
                "$store_url/v1/prometheus/api/v1/query"); then
            printf 'fleet-alert: query failed: %s\n' "$1" >&2
            return 1
          fi
          if [ "$status" != 200 ] \
            || ! jq -e '.status == "success" and .data.resultType == "vector"' "$work/body" > /dev/null; then
            printf 'fleet-alert: HTTP %s for query: %s\n' "$status" "$1" >&2
            return 1
          fi
        }

        # Presence selectors (system_memory_usage_bytes first among them is
        # what `reporting` reads), then rule expressions, then attribution
        # for the hosts in the results of rules that name attribution
        # queries. Stops at the first failed query.
        collect() {
          local selector rule alert expr window inside host attr name label attr_query
          while IFS= read -r selector; do
            query "count by (host_name) ($selector)" || return 1
            jq -c --arg selector "$selector" \
              '{selector: $selector, hosts: [.data.result[].metric.host_name // empty]}' \
              "$work/body" >> "$work/presence.jsonl"
          done < <(jq -r '["system_memory_usage_bytes"] + [.rules[].presence[]?.selector] | unique | .[]' "$config")

          while IFS= read -r rule; do
            alert=$(jq -r .alert <<< "$rule")
            expr=$(jq -r .expr <<< "$rule")
            window=$(jq -c '.window // empty' <<< "$rule")
            if [ -n "$window" ]; then
              inside=$(TZ=$(jq -r .zone <<< "$window") jq -n -L "$jqlib" \
                --argjson window "$window" --argjson now "$now" \
                'include "transition"; in_window($window; $now)')
              jq -nc --arg alert "$alert" --argjson inside "$inside" \
                '{alert: $alert, inside: $inside}' >> "$work/windows.jsonl"
              if [ "$inside" != true ]; then
                continue
              fi
            fi
            query "$expr" || return 1
            jq -c --arg alert "$alert" \
              '{alert: $alert, result: [.data.result[] | {labels: .metric, value: .value[1]}]}' \
              "$work/body" >> "$work/results.jsonl"
          done < <(jq -c '.rules[] | select(has("expr"))' "$config")

          while IFS= read -r host; do
            if ! [[ "$host" =~ ^[A-Za-z0-9._-]+$ ]]; then
              printf 'fleet-alert: no attribution for host label %q\n' "$host" >&2
              continue
            fi
            while IFS= read -r attr; do
              name=$(jq -r .name <<< "$attr")
              label=$(jq -r '.label // ""' <<< "$attr")
              attr_query=$(jq -r .query <<< "$attr")
              query "''${attr_query//<host>/$host}" || return 1
              jq -c --arg host "$host" --arg name "$name" --arg label "$label" \
                '{host: $host, name: $name, label: $label, result: .data.result}' \
                "$work/body" >> "$work/attribution.jsonl"
            done < <(jq -c '[.rules[].attribution[]?] | unique | .[]' "$config")
          done < <(jq -r --slurpfile results "$work/results.jsonl" '
            [.rules[] | select((.attribution // []) | length > 0) | .alert] as $attributed
            | [$results[] | select(.alert as $a | any($attributed[]; . == $a)) | .result[].labels.host_name // empty]
            | unique | .[]' "$config")
        }

        store_error=false
        if ! collect; then
          store_error=true
        fi

        if [ -r "$failed_log" ]; then
          jq -R -s '[split("\n")[] | select(test("^[0-9]+ [^ ]+ [^ ]+$")) | split(" ")
            | {at: (.[0] | tonumber), unit: .[1], host: .[2]}]' "$failed_log" > "$work/failed.json"
        else
          echo '[]' > "$work/failed.json"
        fi

        jq -n --argjson storeError "$store_error" \
          --slurpfile presence "$work/presence.jsonl" \
          --slurpfile results "$work/results.jsonl" \
          --slurpfile windows "$work/windows.jsonl" \
          --slurpfile attribution "$work/attribution.jsonl" \
          --slurpfile failed "$work/failed.json" '
          def mb: (tonumber / 1000000 | floor | tostring) + " MB";
          {
            storeError: $storeError,
            presence: ($presence | map({key: .selector, value: .hosts}) | from_entries),
            reporting: ([$presence[] | select(.selector == "system_memory_usage_bytes") | .hosts[]] | unique),
            results: ($results | map({key: .alert, value: .result}) | from_entries),
            windows: ($windows | map({key: .alert, value: .inside}) | from_entries),
            attribution: ($attribution | group_by(.host) | map({
              key: .[0].host,
              value: (map(.label as $l | "\(.name): " + (.result
                | map((if $l == "" then "" else (.metric[$l] // "?") + " " end) + (.value[1] | mb))
                | join(", "))) | join("\n"))
            }) | from_entries),
            failedLog: $failed[0]
          }' > "$work/observations.json"

        if [ -s "$state_file" ]; then
          cp "$state_file" "$work/state.json"
        else
          echo null > "$work/state.json"
        fi
        jq -n -L "$jqlib" --slurpfile state "$work/state.json" \
          --slurpfile observations "$work/observations.json" \
          --slurpfile config "$config" --argjson now "$now" --arg topic "$topic" '
          include "transition";
          $state[0] | transition($observations[0]; $now; $config[0].rules)
          | .posts |= map({topic: $topic} + .)' > "$work/result.json"

        save_state() {
          cat > "$state_file.tmp"
          mv -f "$state_file.tmp" "$state_file"
        }
        jq .state "$work/result.json" | save_state

        if ! ${ntfySend} "ok $now" "$heartbeat_topic" -H "Priority: min"; then
          echo "fleet-alert: heartbeat post failed" >&2
          exit 1
        fi

        while IFS= read -r post; do
          if [ "$SECONDS" -ge "$post_deadline" ]; then
            echo "fleet-alert: post deadline of ''${post_deadline}s reached; unposted transitions stay pending" >&2
            exit 1
          fi
          if ! ${ntfySend} "$(jq -r .message <<< "$post")" "$(jq -r .topic <<< "$post")" \
            -H "Title: $(jq -r .title <<< "$post")" -H "Priority: $(jq -r .priority <<< "$post")"; then
            printf 'fleet-alert: post failed: %s\n' "$(jq -r .title <<< "$post")" >&2
            exit 1
          fi
          jq -L "$jqlib" --argjson post "$post" 'include "transition"; mark_posted($post)' "$state_file" | save_state
        done < <(jq -c '.posts[]' "$work/result.json")

        if [ "$store_error" = true ]; then
          echo "fleet-alert: the store did not answer; instances are frozen" >&2
        fi
      '';
    };
in
{
  flake.lib = { inherit fleetAlertEvaluator; };

  flake.modules.nixos.fleet-alert =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.services.fleet-alert;

      # greptimedb-envelope's set (modules/nixos/greptimedb.nix:305-326),
      # less its journal group.
      hardening = {
        DynamicUser = true;
        UMask = "0077";
        NoNewPrivileges = true;
        PrivateTmp = true;
        ProtectSystem = "strict";
        ProtectHome = true;
        ProtectKernelTunables = true;
        ProtectKernelModules = true;
        ProtectKernelLogs = true;
        ProtectControlGroups = true;
        RestrictSUIDSGID = true;
        RestrictAddressFamilies = [
          "AF_UNIX"
          "AF_INET"
          "AF_INET6"
        ];
      };

      rendered = flakeLib.fleetAlertRules {
        inherit lib;
        notifiedUnits = config.services.observability-notify.units or [ ];
      };
      evaluatorConfig = pkgs.writeText "fleet-alert-config.json" (
        builtins.toJSON {
          inherit (cfg.evaluator) storeUrl topic heartbeatTopic;
          database = "fleet";
          user = "regulator";
          queryTimeoutSec = 10;
          queryDeadlineSec = 30;
          postDeadlineSec = 40;
          stateFile = "/var/lib/fleet-alert/state.json";
          failedLog = "/var/lib/observability-notify/failed.log";
          rules = builtins.fromJSON rendered.json;
        }
      );
      evaluator = fleetAlertEvaluator pkgs { ntfySend = lib.getExe pkgs.ntfy-send; };
      unit = config.systemd.services.fleet-alert.serviceConfig;
    in
    {
      options.services.fleet-alert.evaluator = {
        enable = lib.mkEnableOption "the fleet alert evaluator (ADR-009)";
        tokenFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path of the ntfy `alerter` token, loaded as the credential `alerter-token`.";
        };
        regulatorPasswordFile = lib.mkOption {
          type = lib.types.nullOr lib.types.str;
          default = null;
          description = "Path of the store's `regulator` password, loaded as the credential `regulator-password`.";
        };
        storeUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://127.0.0.1:4000";
          description = "Base URL of the store's HTTP API.";
        };
        topic = lib.mkOption {
          type = lib.types.str;
          default = "fleet-alerts";
          description = "ntfy topic for FIRING and RESOLVED posts.";
        };
        heartbeatTopic = lib.mkOption {
          type = lib.types.str;
          default = "fleet-heartbeat";
          description = "ntfy topic for the heartbeat each completed run posts at priority min.";
        };
      };

      config = lib.mkMerge [
        (lib.mkIf cfg.evaluator.enable {
          assertions = [
            {
              assertion = cfg.evaluator.tokenFile != null && cfg.evaluator.regulatorPasswordFile != null;
              message = "fleet-alert: services.fleet-alert.evaluator.tokenFile and regulatorPasswordFile must be set when the evaluator is enabled.";
            }
            # R9.5 (ADR-009 E9.5).
            {
              assertion = (unit.MemoryMax or null) == "64M" && (unit.TimeoutStartSec or null) == "50s";
              message = "fleet-alert: R9.5 requires fleet-alert.service to run with MemoryMax = \"64M\" and TimeoutStartSec = \"50s\" (ADR-009 E9.5); it has MemoryMax = ${
                builtins.toJSON (unit.MemoryMax or null)
              }, TimeoutStartSec = ${builtins.toJSON (unit.TimeoutStartSec or null)}.";
            }
          ];

          systemd.services.fleet-alert = {
            description = "Fleet alert evaluator (ADR-009)";
            # Ordered, never pulled in: a store the operator stopped must
            # surface as StoreQueryFailing (design D12).
            after = [
              "greptimedb.service"
              "greptimedb-schema.service"
              "zerotierone.service"
            ];
            environment = {
              FLEET_ALERT_CONFIG = "${evaluatorConfig}";
              NTFY_TOKEN_FILE = "%d/alerter-token";
            };
            serviceConfig = hardening // {
              Type = "oneshot";
              ExecStart = lib.getExe evaluator;
              StateDirectory = "fleet-alert";
              LoadCredential =
                lib.optional (
                  cfg.evaluator.regulatorPasswordFile != null
                ) "regulator-password:${cfg.evaluator.regulatorPasswordFile}"
                ++ lib.optional (cfg.evaluator.tokenFile != null) "alerter-token:${cfg.evaluator.tokenFile}";
              # Last of the four the kernel takes on magnetite: the unit that
              # reports an OOM kill must outlive it (design D12).
              OOMScoreAdjust = 0;
              MemoryMax = "64M";
              TimeoutStartSec = "50s";
            };
          };

          systemd.timers.fleet-alert = {
            description = "Run the fleet alert evaluator every minute";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "minutely";
              AccuracySec = "1s";
            };
          };
        })
      ];
    };
}
```

- [ ] **Step 15: Run the fixture part and see it pass, with every runtime mutant rejected**

Run: `jj st --no-pager >/dev/null && nix build --no-link -L .#checks.x86_64-linux.fleet-alert.fixtureRehearsal 2>&1 | tee logs/s3-evidence/4.5-fixtures-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^fleet-alert-fixtures> (---|===|ok:|mutant|MISS|FAIL)'`
Expected, in this order: the control line and `ok: fixture server refusals and the concurrency guard`; seventeen `---` leg lines with no `MISS` between them; `ok: every leg passed`; then for each of `forZero`, `noAbsenceFreeze`, `noStateWrite` and `noStoreFreeze` an `=== mutant <name>` line, at least one `MISS` line, and `mutant <name> rejected: <first miss>`.
The expected first misses are: `forZero`, the HostMemoryPressure leg's posts differing (a FIRING at run 0); `noAbsenceFreeze`, the silent-host leg's posts differing (a RESOLVED at run 5); `noStateWrite`, the HostOOMKill leg's posts differing (a second FIRING at run 1); `noStoreFreeze`, the store-error leg's posts differing (a RESOLVED at run 5).
If a leg misses with the real evaluator, read `run-<i>.log` lines in the `MISS` text and fix the evaluator, the transition or the leg's fixture answers to match the specification; a leg's `expect` changes only if it contradicts the spec scenario it cites.

- [ ] **Step 16: Add the token-wiring assertions to the two modules**

The token wiring is a relation among one host's units, so it is asserted where the units are defined rather than in `checks.fleet-alert`, because relations within one host belong in that host's module assertions, which CI already pays for when it evaluates the host (S1 review F5); the check was under its 0.5 GiB budget either way (charter v19).

In `modules/nixos/observability-notify.nix`, add to the module's `let`, after `hook`:

```nix
      # LoadCredential entries are "<id>:<source path>"; the ids loading `path`.
      credentialIds =
        path: serviceConfig:
        lib.concatMap (
          entry:
          let
            m = builtins.match "([^:]+):(.+)" entry;
          in
          lib.optional (m != null && builtins.elemAt m 1 == path) (builtins.head m)
        ) (lib.toList (serviceConfig.LoadCredential or [ ]));
      template = config.systemd.services."observability-notify@";
      templateIds = credentialIds cfg.tokenFile template.serviceConfig;
      exportsToken =
        mode: hooks:
        lib.any (
          hook:
          builtins.match "-\\+/nix/store/[^ ]+/bin/env NTFY_TOKEN_FILE=${lib.escapeRegex cfg.tokenFile} /nix/store/[^ ]+-observability-notify-resolved ${mode} %n" hook
          != null
        ) (lib.toList hooks);
      unitsWithoutToken = builtins.filter (
        name:
        let
          unit = config.systemd.services.${name}.serviceConfig;
```

and after the option declarations:

```nix
      # With a token, every fleet-* post of this module carries it (design
      # D3): the template loads tokenFile and names that credential in
      # NTFY_TOKEN_FILE, and each notified unit's resolve hooks pass tokenFile
      # itself. A relation within one host is a module assertion, which CI
      # already pays for when it evaluates the host (S1 review F5).
      config.assertions = lib.mkIf (cfg.tokenFile != null) [
        {
          assertion =
            templateIds != [ ]
            && builtins.elem (template.environment.NTFY_TOKEN_FILE or null) (map (id: "%d/${id}") templateIds);
          message = "observability-notify: observability-notify@.service must load tokenFile (${cfg.tokenFile}) as a credential and name it in NTFY_TOKEN_FILE; it loads ${
            builtins.toJSON (template.serviceConfig.LoadCredential or [ ])
          } and sets NTFY_TOKEN_FILE = ${builtins.toJSON (template.environment.NTFY_TOKEN_FILE or null)}.";
        }
        {
          assertion = unitsWithoutToken == [ ];
          message = "observability-notify: the resolve hooks of ${builtins.toJSON unitsWithoutToken} do not run under `env NTFY_TOKEN_FILE=${cfg.tokenFile}`.";
        }
      ];
```

In `modules/nixos/fleet-alert.nix`, add to the module's `let`, after `unit`:

```nix
      tokenIds = lib.concatMap (
        entry:
        let
          m = builtins.match "([^:]+):(.+)" entry;
        in
        lib.optional (m != null && builtins.elemAt m 1 == cfg.evaluator.tokenFile) (builtins.head m)
      ) (lib.toList (unit.LoadCredential or [ ]));
      tokenEnv = config.systemd.services.fleet-alert.environment.NTFY_TOKEN_FILE or null;
```

and append to the evaluator's `assertions`, after R9.5:

```nix
            # Design D3: the evaluator's posts carry the alerter token.
            {
              assertion = tokenIds != [ ] && builtins.elem tokenEnv (map (id: "%d/${id}") tokenIds);
              message = "fleet-alert: fleet-alert.service must load evaluator.tokenFile (${toString cfg.evaluator.tokenFile}) as a credential and name it in NTFY_TOKEN_FILE; it loads ${
                builtins.toJSON (unit.LoadCredential or [ ])
              } and sets NTFY_TOKEN_FILE = ${builtins.toJSON tokenEnv}.";
            }
```

Run: `jj st --no-pager >/dev/null && nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath 2>&1 | tail -n 2`
Expected: a `.drv` path; magnetite sets no `tokenFile` and has no evaluator yet, so neither assertion applies.

- [ ] **Step 17: Move R7.1's relations into magnetite's assertions**

In `modules/checks/greptimedb-envelope.nix`, delete the `memoryCeilings` and `killOrder` clauses with their comment, the `view` fields only they read and their mutants, and rewrite the header so the check names R1.1, R8.2's file ownership, the disk binding, the PromQL read path and the users-file run, and says that R7.1's memory and kill-order relations are magnetite assertions.

In `modules/machines/nixos/magnetite/default.nix`, append to `assertions`, after the R8.2 holder assertion:

```nix
        # Relations among magnetite's own units, asserted here rather than in
        # a flake check: a relation within one host is a module assertion,
        # which CI already pays for when it evaluates the host (S1 review F5).
        ++ (
          let
            tokenPath = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
            evaluator = config.services.fleet-alert.evaluator;
            notifierTokenFile = config.services.observability-notify.tokenFile;

            # systemd memory sizes with an M or G suffix, which systemd reads
            # as powers of 1024.
            sizeBytes =
              size:
              let
                m = builtins.match "([0-9]+)([MG])" (toString size);
              in
              if m == null then
                null
              else
                lib.toInt (builtins.head m)
                * (if builtins.elemAt m 1 == "G" then 1024 * 1024 * 1024 else 1024 * 1024);
            store = config.systemd.services.greptimedb.serviceConfig;
            high = sizeBytes (store.MemoryHigh or "");
            max = sizeBytes (store.MemoryMax or "");

            # The evaluator's oom_score_adj is set by the nix-eval-lock wrapper
            # script, not by a unit, so it is read from that script.
            evaluatorAdj =
              let
                matches = lib.concatMap (
                  line:
                  let
                    m = builtins.match "[[:space:]]*echo ([0-9]+) >/proc/self/oom_score_adj" line;
                  in
                  if m == null then [ ] else m
                ) (lib.splitString "\n" (builtins.readFile ../../../lib/nix-eval-lock.sh));
              in
              if builtins.length matches == 1 then lib.toInt (builtins.head matches) else null;
            # An absent unit or setting reads as 1000, so the order fails.
            unitAdj =
              name:
              ((config.systemd.services.${name} or { serviceConfig = { }; }).serviceConfig.OOMScoreAdjust or 1000);
            order = {
              nix-eval-jobs = evaluatorAdj;
              greptimedb = unitAdj "greptimedb";
              opentelemetry-collector = unitAdj "opentelemetry-collector";
              fleet-alert = unitAdj "fleet-alert";
            };
          in
          [
            # S3 design D3: the evaluator and the failure notifier post with
            # the shared alerter token.
            {
              assertion = evaluator.enable && evaluator.tokenFile == tokenPath && notifierTokenFile == tokenPath;
              message = "magnetite: the fleet alert evaluator must be enabled, and it and the failure notifier must read the ntfy-alerter token ${tokenPath}; evaluator enabled = ${builtins.toJSON evaluator.enable}, evaluator.tokenFile = ${builtins.toJSON evaluator.tokenFile}, observability-notify.tokenFile = ${builtins.toJSON notifierTokenFile}.";
            }
            # R7.1: the store is throttled before its ceiling and never swaps.
            {
              assertion = high != null && max != null && high < max && toString (store.MemorySwapMax or "unset") == "0";
              message = "magnetite: R7.1 requires greptimedb.service to run with MemoryHigh below MemoryMax and MemorySwapMax = 0; it has MemoryHigh = ${
                builtins.toJSON (store.MemoryHigh or null)
              }, MemoryMax = ${builtins.toJSON (store.MemoryMax or null)}, MemorySwapMax = ${
                builtins.toJSON (store.MemorySwapMax or null)
              }.";
            }
            # R7.1 (A7:100,127) and S3 design D12: under host OOM the kernel
            # kills the evaluator, then the store, then the collector, so the
            # collector outlives the store and queues; the alert evaluator,
            # which reports OOM kills, is taken after all three.
            {
              assertion =
                config.services.nixEvalLock.enable
                && evaluatorAdj != null
                && evaluatorAdj > order.greptimedb
                && order.greptimedb > order.opentelemetry-collector
                && order.opentelemetry-collector > order.fleet-alert;
              message = "magnetite: R7.1 and S3 design D12 require the evaluation lock and oom_score_adj nix-eval-jobs > greptimedb > opentelemetry-collector > fleet-alert; the lock is ${
                if config.services.nixEvalLock.enable then "enabled" else "disabled"
              } and the values are ${builtins.toJSON order}.";
            }
          ]
        );
```

Run: `jj st --no-pager >/dev/null && nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath 2>&1 | tee logs/s3-evidence/4.9-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -o 'magnetite: [^;]*' | sort -u`
Expected: the token assertion (`magnetite: the fleet alert evaluator must be enabled …`) and the kill-order assertion (`magnetite: R7.1 and S3 design D12 require …`, with `"fleet-alert":1000`, because magnetite has no `fleet-alert` unit yet) fail; the memory-ceiling assertion holds.

- [ ] **Step 18: Wire magnetite, without the holder change, and see R8.2 fail**

In `modules/machines/nixos/magnetite/default.nix`, in the `(with flakeModules; [ … ])` import list, after the line `greptimedb`, insert:

```nix
        fleet-alert
        ntfy-alerter
```

In `services.observability-notify.units` (`:327-340` at 2026-10-18), insert as the first element, before `"greptimedb"`:

```nix
        "fleet-alert"
```

After the `systemd.services.greptimedb-envelope = { … };` block (ending `:698` at 2026-10-18), insert:

```nix

      # Fleet alert evaluator (ADR-009; design D3, D12): queries `fleet` as
      # the regulator account and posts to fleet-alerts with the shared
      # alerter token, which the failure notifier's template and resolve
      # hooks use too. magnetite holds only the token side of ntfy-alerter;
      # cinnabar holds the server's ntfy-alerter-env.
      services.fleet-alert.evaluator = {
        enable = true;
        tokenFile = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
        regulatorPasswordFile =
          config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path;
      };
      services.observability-notify.tokenFile =
        config.clan.core.vars.generators.ntfy-alerter.files.token.path;
```

Run: `jj st --no-pager >/dev/null && nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath 2>&1 | tee logs/s3-evidence/4.8-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -o 'magnetite: greptimedb-users credentials are loaded by .*'`
Expected: `magnetite: greptimedb-users credentials are loaded by {"admin-password":["greptimedb-schema"],"collector-password":["opentelemetry-collector"],"perses-password":[],"regulator-password":["fleet-alert","greptimedb-envelope"],"users":["greptimedb"]}; R8.2 allows only {…"regulator-password":["greptimedb-envelope"]…}`.

- [ ] **Step 19: Admit `fleet-alert` as a regulator-password holder**

In the same file, in the R8.2 assertion's `allowed` set (`:642-648`), replace:

```nix
            regulator-password = [ "greptimedb-envelope" ];
```

with:

```nix
            # Sorted, because `actual` is naturalSorted.
            regulator-password = [
              "fleet-alert"
              "greptimedb-envelope"
            ];
```

Run: `jj st --no-pager >/dev/null && nix eval --raw .#nixosConfigurations.magnetite.config.system.build.toplevel.drvPath 2>&1 | tee logs/s3-evidence/4.8-green-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 1`
Expected: a `/nix/store/…-nixos-system-magnetite-….drv` path and no assertion message.

- [ ] **Step 20: Evaluate the deployed settings**

Run:

```bash
{
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.fleet-alert --apply 'u: { inherit (u) after wants environment; serviceConfig = builtins.intersectAttrs { DynamicUser = 0; StateDirectory = 0; UMask = 0; OOMScoreAdjust = 0; MemoryMax = 0; TimeoutStartSec = 0; LoadCredential = 0; Type = 0; } u.serviceConfig; }'
  nix eval --raw '.#nixosConfigurations.magnetite.config.systemd.units."fleet-alert.service".text' | grep -E '^(After|Wants|Environment|LoadCredential|MemoryMax|TimeoutStartSec|OOMScoreAdjust)='
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.timers.fleet-alert.timerConfig
  nix eval --json .#nixosConfigurations.magnetite.config.clan.core.vars.generators --apply 'g: { token = g ? ntfy-alerter; env = g ? ntfy-alerter-env; }'
  nix eval --json '.#nixosConfigurations.magnetite.config.systemd.services."observability-notify@"' --apply 'u: { inherit (u.serviceConfig) LoadCredential; NTFY_TOKEN_FILE = u.environment.NTFY_TOKEN_FILE; }'
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.greptimedb.serviceConfig.ExecStartPost
} 2>&1 | tee logs/s3-evidence/4.3-evaluated-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected:
- `after` contains `greptimedb.service`, `greptimedb-schema.service` and `zerotierone.service`; `wants` is `[]`; `environment` has `FLEET_ALERT_CONFIG` = `/nix/store/…-fleet-alert-config.json` and `NTFY_TOKEN_FILE` = `%d/alerter-token`; `serviceConfig` has `DynamicUser` `true`, `StateDirectory` `fleet-alert`, `UMask` `0077`, `OOMScoreAdjust` `0`, `MemoryMax` `64M`, `TimeoutStartSec` `50s`, `Type` `oneshot`, and `LoadCredential` `["regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password","alerter-token:/run/secrets/vars/shared/ntfy-alerter/token"]`.
- The unit text has `Environment="NTFY_TOKEN_FILE=%d/alerter-token"`, both `LoadCredential=` lines, `MemoryMax=64M`, `TimeoutStartSec=50s`, `OOMScoreAdjust=0`, and no `Wants=` line.
- The timer has `OnCalendar` `minutely` and `AccuracySec` `1s`.
- Generators print `{"env":false,"token":true}`.
- The template prints `{"LoadCredential":["alerter-token:/run/secrets/vars/shared/ntfy-alerter/token"],"NTFY_TOKEN_FILE":"%d/alerter-token"}`.
- `greptimedb`'s `ExecStartPost` holds `-+/nix/store/…-coreutils-…/bin/env NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token /nix/store/…-observability-notify-resolved start %n`.

Run: `nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.fleet-alert.environment.FLEET_ALERT_CONFIG --apply 'p: builtins.fromJSON (builtins.readFile p)' | jq -c '{storeUrl, database, user, topic, heartbeatTopic, stateFile, failedLog, rules: (.rules | length)}'`
Expected: `{"storeUrl":"http://127.0.0.1:4000","database":"fleet","user":"regulator","topic":"fleet-alerts","heartbeatTopic":"fleet-heartbeat","stateFile":"/var/lib/fleet-alert/state.json","failedLog":"/var/lib/observability-notify/failed.log","rules":9}` (`readFile` builds the small JSON file first, an import-from-derivation that local evaluation allows).

- [ ] **Step 21: Show R9.5 able to fail (tasks.md 4.4)**

Run:

```bash
nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); m = f.nixosConfigurations.magnetite.extendModules { modules = [ ({ lib, ... }: { systemd.services.fleet-alert.serviceConfig.MemoryMax = lib.mkForce null; }) ]; }; in builtins.concatStringsSep "\n" (map (a: a.message) (builtins.filter (a: !a.assertion) m.config.assertions))' 2>&1 | tee logs/s3-evidence/4.4-r95-mutant-$(date -u +%Y%m%dT%H%M%SZ).log
nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); m = f.nixosConfigurations.magnetite; in "failed assertions: " + builtins.concatStringsSep "\n" (map (a: a.message) (builtins.filter (a: !a.assertion) m.config.assertions))' 2>&1 | tee logs/s3-evidence/4.4-r95-control-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the first prints exactly `fleet-alert: R9.5 requires fleet-alert.service to run with MemoryMax = "64M" and TimeoutStartSec = "50s" (ADR-009 E9.5); it has MemoryMax = null, TimeoutStartSec = "50s".`; the second prints `failed assertions: ` and nothing after it.
If `extendModules` is missing on the clan-built configuration, stop and report; the fallback is a temporary branch commit with the `mkForce null` line, evaluated and discarded.

- [ ] **Step 22: Show R8.2 able to fail with `fleet-alert` admitted (tasks.md 4.8)**

Run:

```bash
nix eval --impure --raw --expr 'let f = builtins.getFlake (toString ./.); m = f.nixosConfigurations.magnetite.extendModules { modules = [ ({ config, ... }: { systemd.services.nginx.serviceConfig.LoadCredential = [ "stolen:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}" ]; }) ]; }; in builtins.concatStringsSep "\n" (map (a: a.message) (builtins.filter (a: !a.assertion) m.config.assertions))' 2>&1 | tee logs/s3-evidence/4.8-r82-mutant-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: one message starting `magnetite: greptimedb-users credentials are loaded by` whose `regulator-password` list is `["fleet-alert","greptimedb-envelope","nginx"]`.

- [ ] **Step 23: Show every new assertion able to fail with an `extendModules` override**

Each override extends magnetite's evaluated configuration and lists the messages of the assertions that fail; `control` is the unmodified host.

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  host = flake.nixosConfigurations.magnetite;
  failing = m: map (a: a.message) (lib.filter (a: !a.assertion) (host.extendModules { modules = [ m ]; }).config.assertions);
in lib.mapAttrs (_: failing) {
  control = { };
  templateWithoutTokenFile = { systemd.services."observability-notify@".environment.NTFY_TOKEN_FILE = lib.mkForce null; };
  evaluatorTokenFromAnotherPath = { systemd.services.fleet-alert.serviceConfig.LoadCredential = lib.mkForce [ "regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password" "alerter-token:/run/secrets/elsewhere" ]; };
  notifierTokenUnset = { services.observability-notify.tokenFile = lib.mkForce null; };
  evaluatorRemoved = { services.fleet-alert.evaluator.enable = lib.mkForce false; };
}' 2>&1 | jq -r 'to_entries[] | "=== \(.key)", .value[]' | tee logs/s3-evidence/4.7-assertion-mutants-$(date -u +%Y%m%dT%H%M%SZ).log
```

Add the override `hooksWithoutToken`, which sets `greptimedb`'s `ExecStartPost` and `ExecStopPost` with `lib.mkForce` to the two resolve hooks without the `env NTFY_TOKEN_FILE=` prefix, built from `flake.lib.observabilityNotifyScripts`.
Run the same expression with the R7.1 overrides `alertEvaluatorAboveCollector = { systemd.services.fleet-alert.serviceConfig.OOMScoreAdjust = lib.mkForce 400; };`, `storeAboveEvaluator = { systemd.services.greptimedb.serviceConfig.OOMScoreAdjust = lib.mkForce 950; };` and `dropMemoryMax = { systemd.services.greptimedb.serviceConfig.MemoryMax = lib.mkForce null; };`, logging to `4.9-assertion-mutants-*.log`.
Expected (`logs/s3-evidence/4.7-assertion-mutants-20261018T073054Z.log`, `4.9-assertion-mutants-20261018T073326Z.log`): `control` lists nothing; `templateWithoutTokenFile`, `hooksWithoutToken`, `evaluatorTokenFromAnotherPath`, `notifierTokenUnset`, `alertEvaluatorAboveCollector`, `storeAboveEvaluator` and `dropMemoryMax` each list their own assertion's message (`observability-notify: …`, `fleet-alert: …` or `magnetite: …`); `evaluatorRemoved` lists the R8.2 holder, token and kill-order messages.
Steps 16 and 17 are the controls on magnetite's real configuration: both failed before Step 18 wired magnetite.

- [ ] **Step 24: Add magnetite as a reader of the shared token**

The shared `ntfy-alerter` token exists, encrypted for cinnabar (Task 3).
Use `clan vars fix`, never `clan vars generate`: on 2026-10-18 `clan vars generate magnetite --generator ntfy-alerter` regenerated the shared token and re-ran the dependent `ntfy-alerter-env` (`logs/s3-evidence/4.8-vars-magnetite-20261018T073644Z.log`; the repository token's sha256 prefix changed from the deployed `1e0237…` to `5936d5…`), because clan-core's `test_vars_shared.py:175-222` runs `generate` without `--generator`; those files were reverted.
`clan vars fix` adds the machine's age key to the secret's recipients (clan-core `sops.py:446-450`, `allow_member`) without regenerating the value.
Record the value's hash before, without printing it:
Run: `clan vars get cinnabar ntfy-alerter/token | sha256sum | tee logs/s3-evidence/4.8-token-hash-before-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: one sha256 line.
Run: `CLAN_NO_COMMIT=1 clan vars fix magnetite --generator ntfy-alerter 2>&1 | tee logs/s3-evidence/4.8-vars-fix-magnetite-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: `Syncing keys for file …/vars/shared/ntfy-alerter/token/secret`, one added `+++ age1…` recipient, then `synced with new keys`.
Run: `jj st --no-pager >/dev/null && jj diff --name-only -- vars/ sops/`
Expected: only `vars/shared/ntfy-alerter/token/secret`; `vars/per-machine/cinnabar/ntfy-alerter-env/` untouched.
If any other path changed, stop and report; do not regenerate other vars.
Run: `clan vars get magnetite ntfy-alerter/token | sha256sum | tee logs/s3-evidence/4.8-token-hash-after-$(date -u +%Y%m%dT%H%M%SZ).log && clan vars check magnetite; echo "check exit $?"`
Expected: the same sha256 as before, equal to cinnabar's deployed token (`1e0237…`), and `check exit 0`.

- [ ] **Step 25: Build the whole check and measure its evaluation cost**

Run: `nix build --no-link -L .#checks.x86_64-linux.fleet-alert 2>&1 | tee logs/s3-evidence/4.5-check-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '(ok:|mutant .* rejected|FAIL|MISS)'`
Expected: the `ok:` lines and five `mutant … rejected` lines of Steps 9, 12 and 15 (the parts rebuild because magnetite's notified units now include `fleet-alert`, which changes the rendered rules); no `FAIL` and no `MISS` from the real evaluator.
Run: `nix eval --raw .#.checks.x86_64-linux.fleet-alert.rules.json | jq -r '.[] | select(.alert == "SystemdUnitFailed") | .expr' | grep -o '(fleet-alert|greptimedb|'`
Expected: `(fleet-alert|greptimedb|`.

Run: `NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/fleet-alert-stats.json nix eval --raw .#.checks.x86_64-linux.fleet-alert.drvPath 2>&1 | tee logs/s3-evidence/4.5-eval-cost-$(date -u +%Y%m%dT%H%M%SZ).log && jq '{gcTotalBytes: .gc.totalBytes, cpuTime}' /tmp/fleet-alert-stats.json | tee -a logs/s3-evidence/4.5-eval-cost-*.log`
Expected: a `/nix/store/…-fleet-alert.drv` path and `gcTotalBytes` below `536870912` (0.5 GiB).
The check forces magnetite's `observability-notify.units`, the names of its `systemd.services`, three publisher units, the 14 notified units' hooks and the `ntfy-alerter` token path, not the toplevel; if the figure is above 0.5 GiB, stop and report.
Run the same for `greptimedb-envelope` (`NIX_SHOW_STATS_PATH=/tmp/greptimedb-envelope-stats.json`, log `4.9-eval-cost-…`) and record the difference from its S1 figure of 0.41 GiB (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/tasks.md:72`).

- [ ] **Step 26: Run the neighbouring checks and magnetite's configuration**

Run: `nix build --no-link .#checks.x86_64-linux.otel-collector-config .#checks.x86_64-linux.greptimedb-envelope .#checks.x86_64-linux.nixos-magnetite 2>&1 | tee logs/s3-evidence/4.8-neighbours-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 3`
Expected: all three build.
`otel-collector-config` stays green because `fleet-alert` is a unit with an `ExecStart`, its hooks match Task 2's widened `resolvedHook`, and it is outside the `greptimedb*`/`zfs-*` policy.
If `nixos-magnetite` is not the attribute name, list them with `nix eval --json .#checks.x86_64-linux --apply 'c: builtins.filter (n: builtins.match ".*magnetite.*" n != null) (builtins.attrNames c)'` and build the one that is the machine's toplevel.

- [ ] **Step 27: Tick the task items**

In `openspec/changes/stand-up-fleet-alerting/tasks.md`, change the leading `- [ ] 4.1` to `- [ ] 4.9` (nine items) to `- [x] 4.1` … `- [x] 4.9`.
Run: `rg -n "^- \[x\] 4\.[1-9] " openspec/changes/stand-up-fleet-alerting/tasks.md`
Expected: exactly nine lines.

- [ ] **Step 28: Format**

Run: `nix fmt -- modules/nixos/fleet-alert.nix modules/nixos/fleet-alert/rules.nix modules/checks/fleet-alert.nix modules/checks/fleet-alert/fixture_server.py modules/checks/fleet-alert/model.py modules/checks/fleet-alert/test_transition.py modules/checks/fleet-alert/fixtures/series.json modules/checks/greptimedb-envelope.nix modules/machines/nixos/magnetite/default.nix 2>&1 | tee logs/s3-evidence/4-fmt-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: exits 0.
Run: `nix fmt -- --fail-on-change 2>&1 | tee -a logs/s3-evidence/4-fmt-*.log`
Expected: exits 0.
If Step 28 reformatted a file, rerun Step 25's build and expect the same lines.

- [ ] **Step 29: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(fleet-alert): evaluate the S1-backed alert rules on magnetite every minute, gated by checks.fleet-alert'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(fleet-alert): evaluate the S1-backed alert rules")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/nixos/fleet-alert.nix \
  modules/nixos/fleet-alert \
  modules/checks/fleet-alert.nix \
  modules/checks/fleet-alert \
  modules/checks/greptimedb-envelope.nix \
  modules/machines/nixos/magnetite/default.nix \
  vars/shared/ntfy-alerter \
  openspec/changes/stand-up-fleet-alerting/tasks.md
jj diff --name-only -r "$change"
```

Expected: the last command lists `modules/nixos/fleet-alert.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/nixos/fleet-alert/transition.jq`, `modules/checks/fleet-alert.nix`, the four files under `modules/checks/fleet-alert/`, `modules/checks/greptimedb-envelope.nix`, `modules/machines/nixos/magnetite/default.nix`, `vars/shared/ntfy-alerter/token/machines/magnetite`, `vars/shared/ntfy-alerter/token/secret` and `openspec/changes/stand-up-fleet-alerting/tasks.md`, and nothing else.
If `jj diff -r @ -- openspec/changes/stand-up-fleet-alerting/tasks.md` showed hunks other than the nine ticks before the squash, squash that file with `--interactive` and select only the ticks.
The orchestrator rebases the development join, pushes, opens the pull request and enqueues it.

- [ ] **Step 30: Pull request merged (tasks.md 4.10)**

The orchestrator's pull request shows nixbot green, including `checks.x86_64-linux.fleet-alert`, `greptimedb-envelope`, `otel-collector-config` and magnetite's configuration check, and merges through the queue.
Verify: `jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(fleet-alert): evaluate the S1-backed alert rules")' -T 'commit_id.shortest(12)'` prints one commit.
The fixture part runs about 120 evaluator runs plus the mutants' legs; record the check's build time from the nixbot log in the evidence, for the retrospective.

- [ ] **Step 31: Gate before deploy C2**

Task 7's 7.1 has passed after deploy C1: cinnabar's ntfy accepts the `alerter` token (the token probe exited 0), so magnetite's token-bearing posts will not get 401 (design D5; world assumption A39).
Run: `ls logs/s3-evidence/7.1-*.log`
Expected: the 7.1 evidence files exist and `verify.md`'s 7.1 entry records the probe's exit 0; if not, stop: deploying magnetite before C1 makes every post fail with 401.

- [ ] **Step 32: Deploy C2 (tasks.md 4.11)**

Run Task 7 Step 0's deploy procedure for host `magnetite`; cinnabar is not deployed.
Verify: Task 7's 7.2 passes, in particular `systemctl list-timers fleet-alert.timer` shows it scheduled, `sudo jq . /var/lib/fleet-alert/state.json` parses, `fleet-heartbeat` on cinnabar holds at least 9 messages in 10 min, and `observability-notify@acceptance-probe.service` posts with the token; group 5's deploy waits for 7.2.
If the evaluator fails on its first runs, `journalctl -u fleet-alert` names the failed query, post or deadline; roll back by redeploying magnetite from the previous `main@origin` commit through the same procedure, which reverts the evaluator and the notifier's token together, and cinnabar needs no change since it has no access entries yet.

#### Questions and contract notes for Task 4

1. tasks.md 4.3 says this group declares `services.fleet-alert.deadman.*`; with S3PlanT5 I agreed that Task 5 declares all `deadman` options together with the units that use them, so Task 4 adds no unused option. Confirm, or Task 4 gains the four option declarations from Task 5's Interfaces.
2. `flake.lib.fleetAlertEvaluator pkgs { ntfySend; transition ? <transition.jq>; }` adds an optional argument to the contract's `{ ntfySend; }`, so the check can build the evaluator over its mutant jq files. Task 5's `fleetAlertDeadman` mirrors it.
3. Posts from `transition` carry no `topic`; the evaluator adds it from its configuration (`.posts |= map({topic: $topic} + .)`), because the transition has no configuration input and the acceptance run posts to `fleet-acceptance` without a rebuild. The contract's post `{ topic, title, priority, message, key }` holds after that step. Agreed with S3PlanT5.
4. Magnetite's R8.2 list is written `[ "fleet-alert" "greptimedb-envelope" ]`, not plan-head's `[ "greptimedb-envelope" "fleet-alert" ]`, because the assertion compares it with a `naturalSort`ed list.
5. tasks.md 4.1's verify ("the rendered JSON contains `[.]service` and no backslash") cannot hold literally: JSON escapes each `"` of a label matcher as `\"`. Step 9 counts backslashes in the decoded expressions, which is what reaches the store. tasks.md 4.1's wording should say "no rendered expression contains a backslash".
6. `StoreQueryFailing` and `RuleSignalMissing` are listed in `rules.nix` without `expr`, so their `for` lives in the one table and Task 7's hand run can set `RuleSignalMissing`'s `for` to 0 in a copied configuration (S3PlanT678). The spec's "the evaluator adds StoreQueryFailing and RuleSignalMissing of its own" still holds: no query exists for them, and `promtool` never sees them.
7. Titles of host-less instances omit the host (`[FIRING] StoreQueryFailing`, `[FIRING] WeeklyPipelineTest`, `[FIRING] RuleSignalMissing`, whose body names the rule and selector), matching the spec scenarios; `AlertBudgetExceeded` names its top rule and host in the body, and is posted on the run after the breach, because it counts recorded posts only.
8. Whether GreptimeDB 1.2.1 keeps `__name__` on a filtering comparison was not measured; the evaluator removes it from instance labels either way, and three fixtures carry it.
9. The window is `start` inclusive, `end` exclusive (09:00 ≤ t < 09:05); with the minutely timer that is five runs, the first of which posts.
10. `NTFY_TOKEN_FILE = "%d/alerter-token"` in `environment` relies on systemd expanding `%d` in `Environment=`, as Task 2's template does; Step 20 shows the rendered line, and Task 7's 7.2 token-bearing posts confirm the expansion at runtime.

---

### Task 5: Dead-man and access entries (cutover C3)

Implements `tasks.md` 5.1–5.5 (design D4, D5 step 3, D12, D15, D19, "Failure path"; ADR-009 items 9, 11, 12, R9.3, R9.4; specs `fleet-alerting-interface` and `fleet-alerting`).
The dead-man's legs and the cinnabar relation clauses are written first and fail, then `flake.lib.fleetAlertDeadman`, the `deadman` options and units, cinnabar's wiring and finally the access entries make them pass.
The access entries come last on purpose: with the dead-man wired and no `auth-access`, the access-decision clauses must fail, which shows they read cinnabar's real entries before the entries exist.

**Files:**
- Create: `modules/checks/fleet-alert/ntfy_stub.py` (loopback stand-in for ntfy's publish and poll endpoints; `.py`, so import-tree does not load it)
- Create: `modules/machines/nixos/cinnabar/fleet-alert.nix` (cinnabar's dead-man and notifier settings and its token assertion, a fragment of `flake.modules.nixos."machines/nixos/cinnabar"` like `zt-dns.nix`)
- Modify: `modules/nixos/fleet-alert.nix` (outer `let`: `alertEvaluatorSilent`, `fleetAlertDeadman`; `flake.lib` export; options `services.fleet-alert.deadman.*`; a second `lib.mkMerge` element with `fleet-deadman.service`, `fleet-deadman.timer` and the dead-man's token-wiring assertion; header comment)
- Modify: `modules/checks/fleet-alert.nix` (`deadmanRehearsal` with its probe mutant; `deadmanFailures` with eleven mutants, asserted in `deadmanClause`; the check value references both and lists them in `passthru`)
- Modify: `modules/machines/nixos/cinnabar/default.nix` (imports `fleet-alert` and `observability-notify`)
- Modify: `modules/machines/nixos/cinnabar/ntfy.nix` (`settings.auth-access`)
- Modify: `modules/nixos/fleet-alert/transition.jq` and `modules/checks/fleet-alert/model.py` (a rule without an `expr` is evaluated when `results` holds an entry for its alert name, `StoreQueryFailing` and `RuleSignalMissing` excepted, so the dead-man's `AlertEvaluatorSilent` fires; found at Step 10, where Task 4's `select(has("expr"))` dropped it)
- Modify: `modules/checks/fleet-alert/test_transition.py` (a property that a rule without an `expr` and with a results entry behaves as its `expr` twin, and an example that one without either produces nothing)
- Modify: `openspec/changes/stand-up-fleet-alerting/design.md` (D11, D15) and this plan (Task 4's transition description and listings) to record the selection
- Modify: `openspec/changes/stand-up-fleet-alerting/tasks.md` (4.2's wording; tick 5.1, 5.2, 5.3)

**Interfaces:**
- Consumes (Task 1): `pkgs.ntfy-send` reading `NTFY_TOKEN_FILE` and sending `Authorization: Bearer` through `-H @-`; usage `ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, posting to `https://ntfy.zt/<topic>` with `curl -sfk -m 5`.
- Consumes (Task 2): `flake.modules.nixos.observability-notify` with `services.observability-notify.units` and `services.observability-notify.tokenFile`; every listed unit gets `OnFailure = [ "observability-notify@%n.service" ]`, so a failed run posts `FAILED fleet-deadman.service on cinnabar` to `fleet-alerts`.
- Consumes (Task 3): `flake.modules.nixos.ntfy-alerter`, already imported on cinnabar; the shared generator `ntfy-alerter` holds only `token`, at `config.clan.core.vars.generators.ntfy-alerter.files.token.path` (`/run/secrets/vars/shared/ntfy-alerter/token`); cinnabar's per-machine `ntfy-alerter-env` feeds `services.ntfy-sh.environmentFile`; cinnabar's `ntfy.nix` sets `behind-proxy`, `proxy-trusted-hosts`, `visitor-prefix-bits-ipv6` and `environmentFile`, and no `auth-access`; `checks.x86_64-linux.ntfy-provisioning` judges every user named in cinnabar's `services.ntfy-sh.settings.auth-access or [ ]`.
- Consumes (Task 4), from `modules/nixos/fleet-alert.nix`: the outer `let` bindings `transitionJq = ./fleet-alert/transition.jq;` and `jqLib = pkgs: transition: pkgs.linkFarm "fleet-alert-jq" [ { name = "transition.jq"; path = transition; } ];`, `fleetAlertEvaluator`, and `flake.lib = { inherit fleetAlertEvaluator; };`; inside the NixOS module, `cfg = config.services.fleet-alert`, the `hardening` attrset (the `greptimedb-envelope` set: `DynamicUser`, `UMask = "0077"`, `NoNewPrivileges` … `RestrictAddressFamilies`), options `services.fleet-alert.evaluator.{enable,tokenFile,regulatorPasswordFile,storeUrl,topic,heartbeatTopic}` declared unconditionally (`topic` default `fleet-alerts`, `heartbeatTopic` default `fleet-heartbeat`), and `config = lib.mkMerge [ (lib.mkIf cfg.evaluator.enable { … }) ];`.
- Consumes (Task 4), from `transition.jq`: `def transition($observations; $now; $rules)` over the state (`{}` or `null` when empty) returning `{ state, posts }`, each post `{ title, priority, message, key = { kind, id } }` with no topic, which the caller adds; `def mark_posted($post)` over the state, timed by `state.lastRun`; rule `{ alert, for (int seconds), severity, annotations = { summary }, presence, attribution }` with `expr` absent for internal rules, and `StoreQueryFailing` and `RuleSignalMissing` enabled only when listed in `$rules`; observations `{ storeError, results = { <alert> = [ { labels, value } ] }, presence, reporting, failedLog }`; an instance labelled `host_name = h` with `h` in `reporting` is never host-frozen and is titled `[FIRING|RESOLVED] <alert> <h>`; `critical` maps to priority `high`; an instance resolves after 300 s absent. Task 4's `conditions` read `results` only for rules with an `expr`; this task widens it so a rule without one is read when `results` holds an entry for its alert name (`StoreQueryFailing` and `RuleSignalMissing` excepted), the way `AlertEvaluatorSilent` reaches the transition.
- Consumes (Task 4), from `modules/checks/fleet-alert.nix`'s `perSystem` `let`:
  - `ntfySendStub` (`pkgs.writeShellScriptBin "ntfy-send"`): appends one `{ topic, message, headers, tokenFile }` per call to `$FLEET_ALERT_POSTS` (`headers` is the list of `-H` values, `tokenFile` is `$NTFY_TOKEN_FILE`) and exits `$FLEET_ALERT_POST_STATUS`, default 0.
  - `fixtureCredentials`: a store directory holding `regulator-password` and `alerter-token`.
  - The check value `pkgs.runCommand "fleet-alert" { passthru = { inherit rules promtoolRehearsal fixtureRehearsal propertyRehearsal; }; } '' test -e ${promtoolRehearsal} test -e ${fixtureRehearsal} test -e ${propertyRehearsal} touch "$out" ''`; Task 4 moved the token wiring into module and host assertions (charter v18), so this check holds no wiring clause.
- Consumes (Task 4): the token-wiring assertions in `observability-notify.nix` (template and resolve hooks) and `fleet-alert.nix` (the evaluator), and magnetite's host assertion, the pattern this task repeats for the dead-man and cinnabar.
- Produces: `flake.lib.fleetAlertDeadman pkgs { ntfySend; transition ? transitionJq; }`, a `writeShellApplication` named `fleet-deadman`. It reads the JSON configuration at `FLEET_DEADMAN_CONFIG`, requires `NTFY_TOKEN_FILE`, and takes time from `FLEET_ALERT_NOW` when set. On stdout it prints `fleet-deadman: R9.4 probe refused with HTTP 403` and `fleet-deadman: <n> heartbeat(s) on <topic> in the last 10m`. On stderr it prints `fleet-deadman: R9.4: anonymous publish to <topic> answered HTTP <code>, expected 403` or `fleet-deadman: poll of <topic> failed`, then exits 1.
- Produces: the dead-man configuration JSON `{ ntfyUrl, topic, evaluatorHost, heartbeatTopic, window: "10m", stateFile: "/var/lib/fleet-deadman/state.json", rules: [ AlertEvaluatorSilent ] }`; `heartbeatTopic` is `services.fleet-alert.evaluator.heartbeatTopic`, the same option the evaluator posts to.
- Produces: options `services.fleet-alert.deadman.enable` (bool), `.tokenFile` (`str`, no default), `.ntfyUrl` (default `http://[::1]:2586`), `.topic` (default `fleet-alerts`), `.evaluatorHost` (default `magnetite`; contract addition, decided by the orchestrator).
- Produces: units `fleet-deadman.service` (oneshot, `DynamicUser`, `StateDirectory = "fleet-deadman"`, `LoadCredential = [ "alerter-token:<tokenFile>" ]`, `environment.NTFY_TOKEN_FILE = "%d/alerter-token"`, `after = [ "ntfy-sh.service" "caddy.service" "zerotierone.service" ]`, no `wants`; decided by the orchestrator, superseding plan-head's `after = [ "ntfy-sh.service" ]`) and `fleet-deadman.timer` (`OnCalendar = "*:0/5"`, `AccuracySec = "5s"`).
- Produces: cinnabar's `services.ntfy-sh.settings.auth-access = [ "alerter:fleet-*:rw" "*:fleet-*:ro" ]` in this nixfmt form, which Task 7's R9.4 negative-control branch edits by deleting the line `"*:fleet-*:ro"`:

  ```nix
          auth-access = [
            "alerter:fleet-*:rw"
            "*:fleet-*:ro"
          ];
  ```

Facts this task rests on, each confirmed against the cited source (`gh api repos/binwiederhier/ntfy/contents/<path>?ref=v2.28.0`, read 2026-10-18):

- A topic write that the access entries do not grant fails `authorizeTopic` with `errHTTPForbidden` (`server/server_middleware.go:153-171`), which is HTTP 403 with code 40301 (`server/errors.go:156`); the check happens before the message is stored, so a refused probe adds nothing to the cache.
- `GET /<topic>/json?poll=1&since=10m` replays the cached messages of that window as one JSON object per line and returns; with none it answers 200 with an empty body (`server/server.go:1484-1489`, `:1749-1782`, `:1785-1800`); each object has `event` (`"message"` for a published message), `time`, `topic` and `message` (`model/model.go:16`, `:35-40`).
- `auth-access` is a string-slice flag read from the YAML file and `NTFY_AUTH_ACCESS` (`cmd/serve.go:55`); each entry is `user:topic:permission`, `*` names anonymous clients, a named user must be provisioned with role `user`, and `rw`/`ro` are accepted permissions (`cmd/serve.go:647-677`; `user/types.go:241-254`); `auth-default-access` defaults to `read-write` (`cmd/serve.go:53`).
- One access row decides a request: rows for the user or `*` whose pattern matches, ordered `u.user DESC, LENGTH(topic) DESC, write DESC` (world assumption A38; `user/manager.go:702-735`, `user/manager_sqlite.go:90-96`); `deadmanFailures` below reproduces that order.
- cinnabar resolves `ntfy.zt` to its own ZeroTier address through systemd-resolved's `~zt` route to its dnsmasq (`modules/machines/nixos/cinnabar/zt-dns.nix:30-31`, `:113-117`), so `ntfy-send` on cinnabar reaches its own caddy; `nix eval .#nixosConfigurations.cinnabar.config.networking.hostName` prints `cinnabar` (2026-10-18).
- The dead-man's script, legs, probe mutant and access-decision function were run outside the repository on 2026-10-18 against a stand-in `transition.jq`: `shellcheck` reported nothing on the script and the legs, every leg passed, and the probe mutant failed at the HTTP 200 leg. The `nix eval` of `decision` gave `ro`, `rw` and `null` for anonymous `fleet-heartbeat`, alerter `fleet-heartbeat` and anonymous `magnetite` under the two entries. Without `*:fleet-*:ro` it gave `null` for anonymous `fleet-alerts`.

- [ ] **Step 1: Confirm the base**

Run from `/Users/crs58/projects/vanixiets`:

```bash
pwd
jj git fetch
jj log --no-graph -r main@origin -T 'description.first_line() ++ "\n"'
nix eval --json .#nixosConfigurations.cinnabar.config.services.ntfy-sh.settings --apply 's: { access = s.auth-access or null; proxy = s.behind-proxy or null; }'
nix eval --raw .#nixosConfigurations.magnetite.config.services.fleet-alert.evaluator.heartbeatTopic
nix eval .#nixosConfigurations.cinnabar.config.services.fleet-alert.deadman.enable
```

Expected: `pwd` prints `/Users/crs58/projects/vanixiets`; `main@origin` contains Task 4's merge; the settings print `{"access":null,"proxy":true}` (C1 state: proxy settings, no access entries); the heartbeat topic prints `fleet-heartbeat`; the last command fails with `error: attribute 'fleet-alert' missing` (cinnabar does not import the module yet).
If any differs, stop and report to the orchestrator.

- [ ] **Step 2: Write the ntfy stand-in**

Create `modules/checks/fleet-alert/ntfy_stub.py`:

```python
"""Loopback stand-in for ntfy 2.28.0's publish and poll endpoints, for the
fleet-deadman legs of checks.x86_64-linux.fleet-alert (tasks.md 5.1).

POST /<topic> answers --probe-status, with ntfy's error body for 403
(binwiederhier/ntfy@v2.28.0 server/errors.go:156, raised by authorizeTopic in
server/server_middleware.go:153-171). GET /<topic>/json?poll=1&since=10m
answers --poll-status, and on 200 the --poll-body file, one JSON message per
line (server/server.go:1484-1489, 1749-1782). The probe and the poll are
anonymous (ADR-009 R9.4), so a request carrying an Authorization header gets
400. Every request is appended to --log as "<METHOD> <path>?<query> auth=<yes|no>".
"""

import argparse
import json
from http.server import BaseHTTPRequestHandler, HTTPServer
from urllib.parse import parse_qs, urlsplit

parser = argparse.ArgumentParser()
parser.add_argument("--topic", required=True)
parser.add_argument("--probe-status", type=int, required=True)
parser.add_argument("--poll-status", type=int, required=True)
parser.add_argument("--poll-body", required=True)
parser.add_argument("--port-file", required=True)
parser.add_argument("--log", required=True)
args = parser.parse_args()


def error(status, message):
    return json.dumps({"code": status * 100 + 1, "http": status, "error": message})


class Handler(BaseHTTPRequestHandler):
    def reply(self, status, body):
        data = body.encode()
        self.send_response(status)
        self.send_header("Content-Type", "application/json")
        self.send_header("Content-Length", str(len(data)))
        self.end_headers()
        self.wfile.write(data)

    def record(self):
        url = urlsplit(self.path)
        authorized = "Authorization" in self.headers
        with open(args.log, "a") as log:
            log.write(f"{self.command} {url.path}?{url.query} auth={'yes' if authorized else 'no'}\n")
        return url, authorized

    def do_POST(self):
        url, authorized = self.record()
        self.rfile.read(int(self.headers.get("Content-Length", "0")))
        if authorized:
            return self.reply(400, error(400, "stub: Authorization on an anonymous request"))
        if url.path != f"/{args.topic}":
            return self.reply(404, error(404, "page not found"))
        if 200 <= args.probe_status < 300:
            return self.reply(
                args.probe_status,
                json.dumps({"id": "probe", "time": 0, "event": "message", "topic": args.topic, "message": "probe"}),
            )
        return self.reply(args.probe_status, error(args.probe_status, "forbidden" if args.probe_status == 403 else "stub"))

    def do_GET(self):
        url, authorized = self.record()
        query = parse_qs(url.query)
        if authorized:
            return self.reply(400, error(400, "stub: Authorization on an anonymous request"))
        if url.path != f"/{args.topic}/json" or query.get("poll") != ["1"] or query.get("since") != ["10m"]:
            return self.reply(404, error(404, "page not found"))
        if args.poll_status != 200:
            return self.reply(args.poll_status, error(args.poll_status, "stub"))
        with open(args.poll_body) as body:
            return self.reply(200, body.read())

    def log_message(self, *_):
        pass


server = HTTPServer(("127.0.0.1", 0), Handler)
with open(args.port_file, "w") as port_file:
    port_file.write(str(server.server_port))
server.serve_forever()
```

Run: `jj st --no-pager >/dev/null`
Expected: exit 0, so the snapshot includes the new file.

- [ ] **Step 3: Write the failing dead-man legs and the probe mutant**

In `modules/checks/fleet-alert.nix`'s `perSystem` `let` block, after Task 4's `ntfySendStub` and `fixtureCredentials`, add:

```nix
      cinnabar = self.nixosConfigurations.cinnabar.config;
      cinnabarPkgs = self.nixosConfigurations.cinnabar.pkgs;

      # The dead-man (tasks.md 5.1; design D12, "Failure path"; ADR-009 R9.3,
      # R9.4), built from the function cinnabar deploys with the recording
      # ntfy-send, and run against cinnabar's own rendered configuration with
      # only ntfyUrl and stateFile pointed at the sandbox.
      deadmanRehearsed = self.lib.fleetAlertDeadman pkgs { ntfySend = lib.getExe ntfySendStub; };
      deadmanConfigFile = cinnabar.systemd.services.fleet-deadman.environment.FLEET_DEADMAN_CONFIG;

      # R9.4's build-time negative control: a dead-man that passes any HTTP
      # answer to its probe. --replace-fail proves the edit hit the script.
      deadmanProbeMutant = pkgs.runCommand "fleet-deadman-probe-mutant" { } ''
        mkdir -p "$out/bin"
        cp ${lib.getExe deadmanRehearsed} "$out/bin/fleet-deadman"
        chmod +w "$out/bin/fleet-deadman"
        substituteInPlace "$out/bin/fleet-deadman" \
          --replace-fail '[ "$probe" != 403 ]' '[ "$probe" = 000 ]'
      '';

      # The legs take the dead-man executable and fail at the first broken
      # expectation, printing `FAIL: <leg>`; the stand-in serves
      # binwiederhier/ntfy@v2.28.0's answers (ntfy_stub.py).
      deadmanLegs = pkgs.writeShellScript "fleet-deadman-legs" ''
        set -euo pipefail
        deadman="$1"
        work=$(mktemp -d)
        export FLEET_ALERT_POSTS="$work/posts" NTFY_TOKEN_FILE="${fixtureCredentials}/alerter-token"
        touch "$FLEET_ALERT_POSTS"
        hb_topic=$(jq -er .heartbeatTopic ${deadmanConfigFile})
        alert_topic=$(jq -er .topic ${deadmanConfigFile})
        host=$(jq -er .evaluatorHost ${deadmanConfigFile})
        empty="$work/empty.jsonl"
        : > "$empty"
        heartbeat="$work/heartbeat.jsonl"
        jq -nc --arg t "$hb_topic" '{id: "hb1", time: 1000, expires: 44200, event: "message", topic: $t, message: "ok 1000", priority: 1}' > "$heartbeat"

        stub_pid=
        stop_stub() {
          if [ -n "$stub_pid" ]; then
            kill "$stub_pid"
            wait "$stub_pid" || true
            stub_pid=
          fi
        }
        trap stop_stub EXIT
        fail() {
          echo "FAIL: $*" >&2
          sed 's/^/  request: /' "$work/requests" >&2
          sed 's/^/  post: /' "$FLEET_ALERT_POSTS" >&2
          exit 1
        }
        reset() {
          rm -f "$work/state.json"
          : > "$FLEET_ALERT_POSTS"
        }
        # run PROBE_STATUS|closed POLL_STATUS POLL_BODY NOW [POST_STATUS]:
        # one dead-man run; its exit status in $code.
        run() {
          local url
          : > "$work/requests"
          if [ "$1" = closed ]; then
            url=http://127.0.0.1:9
          else
            rm -f "$work/port"
            python3 ${./fleet-alert/ntfy_stub.py} --topic "$hb_topic" --probe-status "$1" --poll-status "$2" \
              --poll-body "$3" --port-file "$work/port" --log "$work/requests" &
            stub_pid=$!
            for _ in $(seq 100); do [ -s "$work/port" ] && break; sleep 0.1; done
            [ -s "$work/port" ] || fail "ntfy stub did not start"
            url="http://127.0.0.1:$(cat "$work/port")"
          fi
          jq --arg url "$url" --arg state "$work/state.json" '.ntfyUrl = $url | .stateFile = $state' \
            ${deadmanConfigFile} > "$work/config.json"
          code=0
          FLEET_DEADMAN_CONFIG="$work/config.json" FLEET_ALERT_NOW="$4" FLEET_ALERT_POST_STATUS="''${5:-0}" \
            "$deadman" > "$work/out" 2>&1 || code=$?
          stop_stub
          sed 's/^/    /' "$work/out"
        }
        # posts TITLE: posts with that title, priority high (critical), the
        # alert topic and the token file.
        posts() {
          jq -s --arg title "Title: $1" --arg topic "$alert_topic" --arg token "$NTFY_TOKEN_FILE" \
            '[.[] | select(any(.headers[]; . == $title) and any(.headers[]; . == "Priority: high") and .topic == $topic and .tokenFile == $token)] | length' \
            "$FLEET_ALERT_POSTS"
        }
        total() { jq -s length "$FLEET_ALERT_POSTS"; }
        probe_line="POST /$hb_topic? auth=no"
        poll_line="GET /$hb_topic/json?poll=1&since=10m auth=no"
        firing="[FIRING] AlertEvaluatorSilent $host"
        resolved="[RESOLVED] AlertEvaluatorSilent $host"

        reset
        run 403 200 "$heartbeat" 1000
        [ "$code" = 0 ] || fail "a refused probe and one heartbeat: exit $code, expected 0"
        [ "$(cat "$work/requests")" = "$probe_line"$'\n'"$poll_line" ] \
          || fail "a refused probe and one heartbeat: requests are not the anonymous probe then the anonymous poll"
        grep -qxF "fleet-deadman: R9.4 probe refused with HTTP 403" "$work/out" || fail "no probe-refused line"
        [ "$(total)" = 0 ] || fail "a heartbeat in the window raised a post"
        echo "ok: a refused probe and one heartbeat exit 0 with no post"

        for status in 200 500 closed; do
          reset
          run "$status" 200 "$heartbeat" 1000
          [ "$code" != 0 ] || fail "an anonymous publish answered $status exited 0"
          answered=$([ "$status" = closed ] && echo 000 || echo "$status")
          grep -qF "answered HTTP $answered, expected 403" "$work/out" || fail "probe answered $status: no R9.4 failure line"
          if [ "$status" != closed ]; then
            [ "$(cat "$work/requests")" = "$probe_line" ] || fail "probe answered $status: the run polled anyway"
          fi
          [ "$(total)" = 0 ] || fail "probe answered $status: a post was made"
          echo "ok: a probe answered $status fails the run before the poll"
        done

        reset
        run 403 500 "$heartbeat" 1000
        [ "$code" != 0 ] || fail "a failed poll exited 0"
        grep -qF "fleet-deadman: poll of $hb_topic failed" "$work/out" || fail "a failed poll: no poll failure line"
        echo "ok: a failed poll fails the run"

        reset
        run 403 200 "$empty" 1000
        [ "$code" = 0 ] || fail "an empty window: exit $code"
        [ "$(posts "$firing")" = 1 ] && [ "$(total)" = 1 ] || fail "an empty window did not post exactly one $firing"
        run 403 200 "$empty" 1300
        [ "$(total)" = 1 ] || fail "a second empty window posted again"
        run 403 200 "$heartbeat" 1600
        run 403 200 "$heartbeat" 1900
        [ "$code" = 0 ] || fail "heartbeats resumed: exit $code"
        [ "$(posts "$resolved")" = 1 ] && [ "$(total)" = 2 ] || fail "resumed heartbeats did not post exactly one $resolved"
        echo "ok: an empty window posts one FIRING, resumed heartbeats one RESOLVED"

        reset
        run 403 200 "$empty" 1000 1
        [ "$code" != 0 ] || fail "a failed post exited 0"
        [ -s "$work/state.json" ] || fail "a failed post left no state"
        run 403 200 "$empty" 1300
        [ "$code" = 0 ] || fail "the retry run: exit $code"
        run 403 200 "$empty" 1600
        [ "$(posts "$firing")" = 2 ] || fail "a failed FIRING was not retried exactly once"
        echo "ok: a failed post fails the run and the next run posts it once"
      '';

      deadmanRehearsal =
        pkgs.runCommand "fleet-deadman-rehearsal"
          {
            nativeBuildInputs = [
              pkgs.coreutils
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
              pkgs.python3
            ];
            meta.description = "behavioural check: the dead-man passes only on a refused probe and posts one FIRING and one RESOLVED";
          }
          ''
            ${deadmanLegs} ${lib.getExe deadmanRehearsed}
            if ${deadmanLegs} ${deadmanProbeMutant}/bin/fleet-deadman > mutant.log 2>&1; then
              cat mutant.log
              echo "FAIL: the legs accepted a dead-man that passes any HTTP answer to its probe" >&2
              exit 1
            fi
            grep -qF "FAIL: an anonymous publish answered 200 exited 0" mutant.log \
              || { cat mutant.log; echo "FAIL: the probe mutant failed for another reason" >&2; exit 1; }
            echo "ok: the probe mutant is rejected"
            touch "$out"
          '';
```

In the same file's `checks.x86_64-linux.fleet-alert` `runCommand`, add `deadmanRehearsal` to Task 4's `passthru` `inherit` list, after `propertyRehearsal`, and in its body, after Task 4's `test -e ${propertyRehearsal}` line, add:

```nix
            test -e ${deadmanRehearsal}
```

Run: `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s3-evidence/5.1-fleet-alert-red-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: evaluation fails with `error: attribute 'fleetAlertDeadman' missing`.

- [ ] **Step 4: Write the failing cinnabar relation clauses**

In the same `let` block, after `deadmanRehearsal`, add:

```nix
      # Relations between independently written values on cinnabar and
      # magnetite (tasks.md 5.1-5.3; design D5 step 3, D12). The access
      # decision reproduces ntfy 2.28.0's: one row decides, rows for the user
      # or `*` whose pattern matches, ordered user DESC, pattern length DESC,
      # write DESC (world assumption A38; user/manager.go:702-735,
      # user/manager_sqlite.go:90-96); no matching row means
      # auth-default-access, here unset and so read-write (cmd/serve.go:53).
      deadmanInput = {
        execStart = cinnabar.systemd.services.fleet-deadman.serviceConfig.ExecStart;
        deployedDeadman = lib.getExe (
          self.lib.fleetAlertDeadman cinnabarPkgs { ntfySend = lib.getExe cinnabarPkgs.ntfy-send; }
        );
        deadman = cinnabar.services.fleet-alert.deadman;
        pollTopic = cinnabar.services.fleet-alert.evaluator.heartbeatTopic;
        evaluator = magnetite.services.fleet-alert.evaluator;
        evaluatorHostName = magnetite.networking.hostName;
        deadmanHostName = cinnabar.networking.hostName;
        deadmanAfter = cinnabar.systemd.services.fleet-deadman.after;
        deadmanWants = cinnabar.systemd.services.fleet-deadman.wants;
        # The path's units that exist on the dead-man's host: ntfy behind
        # listenHttp, caddy serving https://ntfy.zt to ntfy-send, and the
        # ZeroTier address caddy binds (modules/machines/nixos/cinnabar/caddy.nix,
        # zt-dns.nix).
        pathUnits = builtins.filter (name: cinnabar.systemd.services ? ${name}) deadmanPathUnits;
        listenHttp = cinnabar.services.ntfy-sh.settings.listen-http;
        access = cinnabar.services.ntfy-sh.settings.auth-access or [ ];
      };

      decision =
        access: user: topic:
        let
          rows = lib.concatMap (
            entry:
            let
              parts = lib.splitString ":" entry;
              pattern = builtins.elemAt parts 1;
            in
            lib.optional
              (
                builtins.length parts == 3
                && builtins.elem (builtins.head parts) (lib.unique [ user "*" ])
                && builtins.match (builtins.replaceStrings [ "*" ] [ ".*" ] pattern) topic != null
              )
              {
                user = builtins.head parts;
                length = builtins.stringLength pattern;
                permission = builtins.elemAt parts 2;
              }
          ) access;
          writes = row: builtins.elem row.permission [ "rw" "read-write" "wo" "write-only" "write" ];
          ordered = lib.sort (
            a: b:
            if a.user != b.user then
              a.user > b.user
            else if a.length != b.length then
              a.length > b.length
            else
              writes a && !writes b
          ) rows;
        in
        if ordered == [ ] then null else (builtins.head ordered).permission;

      # The units a dead-man run needs: the probe and poll reach ntfy, and
      # every post goes through caddy on cinnabar's ZeroTier address.
      deadmanPathUnits = [
        "ntfy-sh"
        "caddy"
        "zerotierone"
      ];

      readOnly = p: builtins.elem p [ "ro" "read-only" "read" ];
      readWrite = p: builtins.elem p [ "rw" "read-write" ];

      deadmanFailures =
        i:
        let
          check = name: ok: lib.optional (!ok) name;
          anonymous = decision i.access "*";
          alerter = decision i.access "alerter";
        in
        lib.concatLists [
          (check "deadman: fleet-deadman does not run the rehearsed fleetAlertDeadman built with ntfy-send" (
            i.execStart == i.deployedDeadman
          ))
          # Ordered after every unit on its path, and never starting one, so
          # a boot neither probes a half-started path nor starts a unit the
          # operator stopped (design D12).
          (check "deadman: fleet-deadman is not ordered after ntfy-sh, caddy and zerotierone on its host, or wants one of them" (
            i.pathUnits == deadmanPathUnits
            && lib.all (name: builtins.elem "${name}.service" i.deadmanAfter) i.pathUnits
            && !(lib.any (name: builtins.elem "${name}.service" i.deadmanWants) i.pathUnits)
          ))
          (check "deadman: the dead-man polls a heartbeat topic other than the one magnetite's evaluator posts to" (
            i.pollTopic == i.evaluator.heartbeatTopic
          ))
          (check "deadman: the dead-man posts to a topic other than magnetite's evaluator" (
            i.deadman.topic == i.evaluator.topic
          ))
          (check "deadman: evaluatorHost is not the host whose evaluator is enabled" (
            i.evaluator.enable && i.deadman.evaluatorHost == i.evaluatorHostName
          ))
          (check "deadman: ntfyUrl is not ntfy's listener on the dead-man's host" (
            i.deadman.ntfyUrl == "http://${i.listenHttp}"
          ))
          # E9.4 and R9.4's premise: anonymous clients may read but not write
          # both fleet topics, alerter may write both, host topics stay open.
          (check "deadman: an anonymous write to the heartbeat or alert topic is not refused" (
            lib.all (t: anonymous t != null && readOnly (anonymous t)) [
              i.pollTopic
              i.deadman.topic
            ]
          ))
          (check "deadman: alerter may not write the heartbeat or alert topic" (
            lib.all (t: alerter t != null && readWrite (alerter t)) [
              i.pollTopic
              i.deadman.topic
            ]
          ))
          (check "deadman: an access entry decides a host-named topic" (
            lib.all (t: anonymous t == null) [
              i.evaluatorHostName
              i.deadmanHostName
            ]
          ))
        ];

      deadmanActual = deadmanFailures deadmanInput;

      deadmanMutants = {
        execStartOther =
          i:
          i
          // {
            execStart = "/nix/store/${lib.fixedWidthString 32 "0" ""}-fleet-deadman/bin/fleet-deadman";
          };
        evaluatorHeartbeatRenamed = i: i // { evaluator = i.evaluator // { heartbeatTopic = "fleet-beat"; }; };
        deadmanTopicOther = i: i // { deadman = i.deadman // { topic = "fleet-alert"; }; };
        evaluatorHostWrong = i: i // { deadman = i.deadman // { evaluatorHost = "cinnabar"; }; };
        listenerMoved = i: i // { listenHttp = "[::1]:2587"; };
        caddyOrderDropped = i: i // { deadmanAfter = lib.remove "caddy.service" i.deadmanAfter; };
        zerotierOrderDropped = i: i // { deadmanAfter = lib.remove "zerotierone.service" i.deadmanAfter; };
        ntfyWanted = i: i // { deadmanWants = i.deadmanWants ++ [ "ntfy-sh.service" ]; };
        # R9.4's acceptance negative control, at evaluation time.
        anonymousReadOnlyRemoved = i: i // { access = lib.remove "*:fleet-*:ro" i.access; };
        alerterEntryRemoved = i: i // { access = lib.remove "alerter:fleet-*:rw" i.access; };
        hostTopicsCovered = i: i // { access = i.access ++ [ "*:*:ro" ]; };
      };
```

After `deadmanMutants`, add the derivation that holds the evaluation-time asserts:

```nix
      deadmanClause =
        assert lib.assertMsg (deadmanActual == [ ]) "fleet-alert dead-man failures: ${builtins.toJSON deadmanActual}";
        assert lib.assertMsg
          (lib.all (mutant: deadmanFailures (mutant deadmanInput) != [ ]) (lib.attrValues deadmanMutants))
          "fleet-alert accepted a dead-man mutant: ${
            builtins.toJSON (
              builtins.attrNames (lib.filterAttrs (_: m: deadmanFailures (m deadmanInput) == [ ]) deadmanMutants)
            )
          }";
        pkgs.runCommand "fleet-alert-deadman-clause" { } ''
          echo "ok: dead-man relations hold and ${toString (builtins.length (lib.attrNames deadmanMutants))} mutants are rejected"
          touch "$out"
        '';
```

In the check's `passthru`, add `deadmanClause` after `deadmanRehearsal`, and in its body, after the `test -e ${deadmanRehearsal}` line from Step 3, add:

```nix
            test -e ${deadmanClause}
```

Run: `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s3-evidence/5.1-fleet-alert-red-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: evaluation still fails with `error: attribute 'fleetAlertDeadman' missing`.

- [ ] **Step 5: Add `fleetAlertDeadman` and the rule**

In `modules/nixos/fleet-alert.nix`'s outer `let`, after Task 4's `fleetAlertEvaluator`, add:

```nix
  # AlertEvaluatorSilent (ADR-009 rule table; design D12): raised on the
  # dead-man's host when no heartbeat reached ntfy in the poll window. The
  # poll is its query, so it has no `expr`; transition.jq evaluates it from
  # the results entry the dead-man builds, and the single-rule list enables
  # neither StoreQueryFailing nor RuleSignalMissing.
  alertEvaluatorSilent = {
    alert = "AlertEvaluatorSilent";
    for = 0;
    severity = "critical";
    annotations.summary = "No fleet-heartbeat message reached ntfy in 10 min: the evaluator, its host or its path to ntfy is down, and no other alert can be sent.";
    presence = [ ];
    attribution = [ ];
  };

  # The dead-man (design D12, "Failure path"; ADR-009 item 9, R9.4), a
  # function so checks.x86_64-linux.fleet-alert runs it against a loopback
  # ntfy stand-in and a recording ntfy-send. Configuration comes from the
  # JSON file at FLEET_DEADMAN_CONFIG, the token from NTFY_TOKEN_FILE (the
  # unit sets it to its alerter-token credential), and time from
  # FLEET_ALERT_NOW when set, which only the check does.
  fleetAlertDeadman =
    pkgs:
    {
      ntfySend,
      transition ? transitionJq,
    }:
    pkgs.writeShellApplication {
      name = "fleet-deadman";
      runtimeInputs = [
        pkgs.coreutils
        pkgs.curl
        pkgs.jq
      ];
      text = ''
        config="''${FLEET_DEADMAN_CONFIG:?}"
        : "''${NTFY_TOKEN_FILE:?}"
        ntfy_url=$(jq -er .ntfyUrl "$config")
        heartbeat_topic=$(jq -er .heartbeatTopic "$config")
        window=$(jq -er .window "$config")
        topic=$(jq -er .topic "$config")
        state_file=$(jq -er .stateFile "$config")
        now="''${FLEET_ALERT_NOW:-$(date +%s)}"
        jqlib=${jqLib pkgs transition}

        # R9.4 (ADR-009): an anonymous publish to the heartbeat topic must be
        # refused with 403 (binwiederhier/ntfy@v2.28.0
        # server/server_middleware.go:153-171, server/errors.go:156). Any other
        # answer, or none (000), fails the unit before the poll, so OnFailure's
        # notifier reports it and an accepted probe never counts as a heartbeat.
        probe=$(curl -s -o /dev/null -w '%{http_code}' --max-time 5 \
          -d "fleet-deadman anonymous-publish probe" "$ntfy_url/$heartbeat_topic" || true)
        if [ "$probe" != 403 ]; then
          echo "fleet-deadman: R9.4: anonymous publish to $heartbeat_topic answered HTTP $probe, expected 403" >&2
          exit 1
        fi
        echo "fleet-deadman: R9.4 probe refused with HTTP 403"

        if ! poll=$(curl -sf --max-time 10 "$ntfy_url/$heartbeat_topic/json?poll=1&since=$window"); then
          echo "fleet-deadman: poll of $heartbeat_topic failed" >&2
          exit 1
        fi
        heartbeats=$(jq -s '[.[] | select(.event == "message")] | length' <<< "$poll")
        echo "fleet-deadman: $heartbeats heartbeat(s) on $heartbeat_topic in the last $window"

        # One instance of the single rule while the window is empty, labelled
        # with the evaluator's host, which counts as reporting so the
        # transition's host freeze never holds it.
        observations=$(jq -c --argjson heartbeats "$heartbeats" '{
          storeError: false,
          results: {(.rules[0].alert): (if $heartbeats == 0 then [{labels: {host_name: .evaluatorHost}, value: "1"}] else [] end)},
          presence: {},
          reporting: [.evaluatorHost],
          failedLog: []
        }' "$config")
        rules=$(jq -c .rules "$config")
        state='{}'
        if [ -s "$state_file" ]; then
          state=$(< "$state_file")
        fi
        result=$(jq -n -c -L "$jqlib" --argjson state "$state" --argjson observations "$observations" \
          --argjson now "$now" --argjson rules "$rules" --arg topic "$topic" \
          'include "transition"; $state | transition($observations; $now; $rules) | .posts |= map({topic: $topic} + .)')

        write_state() {
          printf '%s\n' "$state" > "$state_file.tmp"
          mv "$state_file.tmp" "$state_file"
        }
        state=$(jq -c .state <<< "$result")
        write_state

        # After each successful post the state records it (mark_posted); a
        # failed post fails the run and stays pending for the next one
        # (design D15).
        while IFS= read -r post; do
          [ -n "$post" ] || continue
          ${ntfySend} "$(jq -r .message <<< "$post")" "$(jq -r .topic <<< "$post")" \
            -H "Title: $(jq -r .title <<< "$post")" \
            -H "Priority: $(jq -r .priority <<< "$post")"
          state=$(jq -c -L "$jqlib" --argjson post "$post" 'include "transition"; mark_posted($post)' <<< "$state")
          write_state
        done <<< "$(jq -c '.posts[]' <<< "$result")"
      '';
    };
```

Change Task 4's export line from `flake.lib = { inherit fleetAlertEvaluator; };` to:

```nix
  flake.lib = { inherit fleetAlertEvaluator fleetAlertDeadman; };
```

Run: `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s3-evidence/5.1-fleet-alert-red-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: evaluation fails with `error: attribute 'fleet-deadman' missing` (cinnabar has no such unit).

Run: `nix build --no-link --print-out-paths --impure --expr 'let f = builtins.getFlake (toString ./.); pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux; in f.lib.fleetAlertDeadman pkgs { ntfySend = "${pkgs.lib.getExe pkgs.ntfy-send}"; }' -L 2>&1 | tee logs/s3-evidence/5.1-fleet-deadman-build-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: one store path ending in `-fleet-deadman`; `writeShellApplication`'s shellcheck phase passes (build).
If `pkgs.ntfy-send` is missing from plain nixpkgs, use `f.packages.x86_64-linux.ntfy-send` in the expression instead; the expected result is the same.

- [ ] **Step 6: Add the `deadman` options and units**

In `modules/nixos/fleet-alert.nix`'s NixOS-module `let`, after Task 4's evaluator bindings, add:

```nix
      deadman = fleetAlertDeadman pkgs { ntfySend = lib.getExe pkgs.ntfy-send; };
      deadmanConfig = pkgs.writeText "fleet-deadman.json" (
        builtins.toJSON {
          inherit (cfg.deadman) ntfyUrl topic evaluatorHost;
          # The option the evaluator posts its heartbeat to; declared
          # whether or not this host runs the evaluator.
          heartbeatTopic = cfg.evaluator.heartbeatTopic;
          window = "10m";
          stateFile = "/var/lib/fleet-deadman/state.json";
          rules = [ alertEvaluatorSilent ];
        }
      );
```

Beside Task 4's `options.services.fleet-alert.evaluator`, add:

```nix
      options.services.fleet-alert.deadman = {
        enable = lib.mkEnableOption "the fleet alert dead-man (fleet-deadman.timer), which probes ntfy's access entries and raises AlertEvaluatorSilent when the heartbeat stops";
        tokenFile = lib.mkOption {
          type = lib.types.str;
          description = "Path of the alerter token, loaded through LoadCredential as alerter-token.";
        };
        ntfyUrl = lib.mkOption {
          type = lib.types.str;
          default = "http://[::1]:2586";
          description = "ntfy's own listener, reached directly so the anonymous probe and the poll bypass the proxy.";
        };
        topic = lib.mkOption {
          type = lib.types.str;
          default = "fleet-alerts";
          description = "Topic the dead-man posts AlertEvaluatorSilent to.";
        };
        evaluatorHost = lib.mkOption {
          type = lib.types.str;
          default = "magnetite";
          description = "host_name the AlertEvaluatorSilent instance carries: the host whose evaluator posts the heartbeat.";
        };
      };
```

Append a second element to Task 4's `config = lib.mkMerge [ … ];` list:

```nix
        (lib.mkIf cfg.deadman.enable {
          systemd.services.fleet-deadman = {
            description = "Fleet alert dead-man: R9.4 anonymous-publish probe and heartbeat poll";
            # Ordered, never pulled in: a boot does not probe ntfy or post
            # through caddy and ZeroTier before they are up (every post goes
            # to https://ntfy.zt), and the dead-man never starts a unit the
            # operator stopped; ntfy's outage is CAM-76's (design D12).
            after = [
              "ntfy-sh.service"
              "caddy.service"
              "zerotierone.service"
            ];
            environment = {
              FLEET_DEADMAN_CONFIG = "${deadmanConfig}";
              NTFY_TOKEN_FILE = "%d/alerter-token";
            };
            serviceConfig = hardening // {
              Type = "oneshot";
              ExecStart = lib.getExe deadman;
              DynamicUser = true;
              StateDirectory = "fleet-deadman";
              LoadCredential = [ "alerter-token:${cfg.deadman.tokenFile}" ];
            };
          };

          # A silence that starts just after a run is seen 10 min later and
          # reported by the next run, inside E9.3's 15 min.
          systemd.timers.fleet-deadman = {
            description = "Five-minute fleet alert dead-man";
            wantedBy = [ "timers.target" ];
            timerConfig = {
              OnCalendar = "*:0/5";
              AccuracySec = "5s";
            };
          };
        })
```

Append to the module's header comment, after Task 4's paragraphs:

```nix
#
# With services.fleet-alert.deadman.enable, fleet-deadman.timer runs
# fleet-deadman.service every 5 min on the ntfy host. Each run first
# publishes anonymously to the heartbeat topic on ntfy's own listener and
# fails unless ntfy answers 403 (R9.4). It then polls the topic's last
# 10 min and applies transition.jq to the single rule AlertEvaluatorSilent,
# keeping /var/lib/fleet-deadman/state.json. It posts through ntfy-send
# with the alerter credential. The host lists fleet-deadman in
# services.observability-notify.units, so a failed run reaches fleet-alerts
# through the notifier.
```

Run: `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s3-evidence/5.1-fleet-alert-red-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: evaluation still fails with `error: attribute 'fleet-deadman' missing`, because cinnabar does not import the module yet.

- [ ] **Step 7: Add the dead-man's token-wiring assertion**

The token wiring is asserted where the units are defined, as Task 4 did for the evaluator and the notifier (charter v18), not by a check clause reading cinnabar.
In `modules/nixos/fleet-alert.nix`, in the `lib.mkIf cfg.deadman.enable` element Step 6 added, add beside `systemd.services.fleet-deadman`:

```nix
          # Design D3: the dead-man's posts carry the alerter token.
          assertions =
            let
              deadmanUnit = config.systemd.services.fleet-deadman;
              deadmanTokenIds = lib.concatMap (
                entry:
                let
                  m = builtins.match "([^:]+):(.+)" entry;
                in
                lib.optional (m != null && builtins.elemAt m 1 == cfg.deadman.tokenFile) (builtins.head m)
              ) (lib.toList (deadmanUnit.serviceConfig.LoadCredential or [ ]));
              deadmanTokenEnv = deadmanUnit.environment.NTFY_TOKEN_FILE or null;
            in
            [
              {
                assertion = deadmanTokenIds != [ ] && builtins.elem deadmanTokenEnv (map (id: "%d/${id}") deadmanTokenIds);
                message = "fleet-alert: fleet-deadman.service must load deadman.tokenFile (${cfg.deadman.tokenFile}) as a credential and name it in NTFY_TOKEN_FILE; it loads ${
                  builtins.toJSON (deadmanUnit.serviceConfig.LoadCredential or [ ])
                } and sets NTFY_TOKEN_FILE = ${builtins.toJSON deadmanTokenEnv}.";
              }
            ];
```

Run: `jj st --no-pager >/dev/null && nix build --no-link .#checks.x86_64-linux.fleet-alert 2>&1 | tail -n 3`
Expected: evaluation still fails with `error: attribute 'fleet-deadman' missing`, because cinnabar does not import the module yet; the assertion is shown able to fail in Step 10, after Step 8 wires cinnabar.

- [ ] **Step 8: Wire cinnabar**

In `modules/machines/nixos/cinnabar/default.nix`, add `fleet-alert` and `observability-notify` to the `with flakeModules; [ … ]` list, keeping it alphabetical; after Task 3's `ntfy-alerter` it reads:

```nix
      ++ (with flakeModules; [
        base
        fleet-alert
        hm-sops-bridge
        kvm-declaration
        ntfy-alerter
        observability-notify
        ssh-known-hosts
      ]);
```

Create `modules/machines/nixos/cinnabar/fleet-alert.nix`:

```nix
# The fleet alert dead-man and its failure notifier on cinnabar (design D4,
# D12; ADR-009 items 9 and 11, R9.4). Both post to fleet-alerts with the
# shared alerter token, loaded by path; cinnabar runs no collector, so it
# imports observability-notify directly and fleet-deadman is its one
# notified unit.
{ ... }:
{
  flake.modules.nixos."machines/nixos/cinnabar" =
    { config, ... }:
    let
      alerterToken = config.clan.core.vars.generators.ntfy-alerter.files.token.path;
    in
    {
      services.observability-notify = {
        units = [ "fleet-deadman" ];
        tokenFile = alerterToken;
      };

      services.fleet-alert.deadman = {
        enable = true;
        tokenFile = alerterToken;
      };

      # S3 design D3: the dead-man and the failure notifier post with the
      # shared alerter token. A host assertion rather than a check clause,
      # as on magnetite (charter v18).
      assertions = [
        {
          assertion =
            config.services.fleet-alert.deadman.enable
            && config.services.fleet-alert.deadman.tokenFile == alerterToken
            && config.services.observability-notify.tokenFile == alerterToken;
          message = "cinnabar: the fleet alert dead-man must be enabled, and it and the failure notifier must read the ntfy-alerter token ${alerterToken}; deadman enabled = ${builtins.toJSON config.services.fleet-alert.deadman.enable}, deadman.tokenFile = ${builtins.toJSON config.services.fleet-alert.deadman.tokenFile}, observability-notify.tokenFile = ${builtins.toJSON config.services.observability-notify.tokenFile}.";
        }
      ];
    };
}
```

Run: `jj st --no-pager >/dev/null`
Expected: exit 0.

Run: `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s3-evidence/5.3-fleet-alert-red-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: evaluation fails with `fleet-alert dead-man failures: ["deadman: an anonymous write to the heartbeat or alert topic is not refused","deadman: alerter may not write the heartbeat or alert topic"]`. This is the access clause failing on cinnabar's real settings, which have no `auth-access` yet.

- [ ] **Step 9: Set the access entries (tasks.md 5.2)**

In `modules/machines/nixos/cinnabar/ntfy.nix`, inside `services.ntfy-sh.settings`, after the last entry Task 3 added, add (and set no `auth-default-access`):

```nix
        # Only alerter publishes on fleet-*, anonymous clients (phones
        # included) may subscribe, and every other topic keeps the default
        # read-write (design D5 step 3; ADR-009 item 12). The named user's
        # row outranks `*` (user/manager.go:702-735 at ntfy v2.28.0), and an
        # anonymous write under `*:fleet-*:ro` is refused with 403, which
        # fleet-deadman's probe asserts every 5 min.
        auth-access = [
          "alerter:fleet-*:rw"
          "*:fleet-*:ro"
        ];
```

Run:

```bash
nix eval --json .#nixosConfigurations.cinnabar.config.services.ntfy-sh.settings.auth-access
nix eval .#nixosConfigurations.cinnabar.config.services.ntfy-sh.settings --apply 's: s ? auth-default-access'
```

Expected: `["alerter:fleet-*:rw","*:fleet-*:ro"]` and `false` (evaluation).

- [ ] **Step 10: Run the check green**

Run: `nix build .#checks.x86_64-linux.fleet-alert -L 2>&1 | tee logs/s3-evidence/5.1-fleet-alert-green-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E '^(ok|FAIL)'`
Expected: exit 0. The filtered log holds Task 4's `ok:` lines and these seven: `ok: a refused probe and one heartbeat exit 0 with no post`, `ok: a probe answered 200 fails the run before the poll`, the same for `500` and `closed`, `ok: a failed poll fails the run`, `ok: an empty window posts one FIRING, resumed heartbeats one RESOLVED`, `ok: a failed post fails the run and the next run posts it once`. After them come `ok: the probe mutant is rejected` and `ok: dead-man relations hold and 11 mutants are rejected` (build).
If the RESOLVED leg fails with exactly one post, Task 4's resolve comparison is strict (`> 300`); stop and report rather than moving the run times.

Run: `nix build .#checks.x86_64-linux.ntfy-provisioning -L 2>&1 | tee logs/s3-evidence/5.2-ntfy-provisioning-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: exit 0; the access-user clause now judges `alerter` and `*`, and its log shows Task 3's `alertr` mutant rejected (build).

Show the dead-man's and cinnabar's token assertions able to fail, with Task 4 Step 23's `extendModules` harness pointed at cinnabar:

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  host = flake.nixosConfigurations.cinnabar;
  failing = m: map (a: a.message) (lib.filter (a: !a.assertion) (host.extendModules { modules = [ m ]; }).config.assertions);
in lib.mapAttrs (_: failing) {
  control = { };
  deadmanWithoutTokenFile = { systemd.services.fleet-deadman.environment.NTFY_TOKEN_FILE = lib.mkForce null; };
  deadmanTokenFromAnotherPath = { services.fleet-alert.deadman.tokenFile = lib.mkForce "/run/secrets/elsewhere"; };
  notifierTokenUnset = { services.observability-notify.tokenFile = lib.mkForce null; };
  templateWithoutTokenFile = { systemd.services."observability-notify@".environment.NTFY_TOKEN_FILE = lib.mkForce null; };
}' 2>logs/s3-evidence/5.3-assertion-mutants-stderr.log | jq -r 'to_entries[] | "=== \(.key)", .value[]' | tee logs/s3-evidence/5.3-assertion-mutants-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `control` lists nothing; `deadmanWithoutTokenFile` lists `fleet-alert: fleet-deadman.service must load deadman.tokenFile …`; `deadmanTokenFromAnotherPath` and `notifierTokenUnset` list `cinnabar: the fleet alert dead-man must be enabled, and it and the failure notifier must read the ntfy-alerter token …`; `templateWithoutTokenFile` lists `observability-notify: observability-notify@.service must load tokenFile …` (evaluation, negative control).

- [ ] **Step 11: Record the evaluation cost**

Run:

```bash
stats=logs/s3-evidence/5.1-fleet-alert-eval-cost-$(date -u +%Y%m%dT%H%M%SZ).json
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH="$PWD/$stats" nix eval --raw .#.checks.x86_64-linux.fleet-alert.drvPath
jq '{GiB: (.gc.totalBytes / 1073741824), cpuTime}' "$stats"
```

Expected: a `.drv` path, then `GiB` below `0.5`, recorded beside Task 4's measurement in the evidence log.
If it exceeds 0.5, stop and report: the likely cost is `deployedDeadman` forcing cinnabar's `pkgs.ntfy-send`, and the remedy (dropping the `execStart` clause or moving it to a cinnabar assertion) is a design decision for the orchestrator.

- [ ] **Step 12: Verify the delivered units by evaluation (tasks.md 5.1, 5.3)**

Run:

```bash
nix eval --json .#nixosConfigurations.cinnabar.config.systemd.services.fleet-deadman --apply 'u: { inherit (u) after wants environment; onFailure = u.unitConfig.OnFailure; inherit (u.serviceConfig) Type DynamicUser StateDirectory LoadCredential UMask; }' | jq -S . | tee logs/s3-evidence/5.1-fleet-deadman-unit-$(date -u +%Y%m%dT%H%M%SZ).json
nix eval --json .#nixosConfigurations.cinnabar.config.systemd.timers.fleet-deadman.timerConfig
nix eval --json .#nixosConfigurations.cinnabar.config.systemd.services.observability-notify@.serviceConfig.LoadCredential
```

Expected (evaluation):
- `after` contains `ntfy-sh.service`, `caddy.service` and `zerotierone.service`; `wants` is `[]`; `environment.NTFY_TOKEN_FILE` is `%d/alerter-token`; `environment.FLEET_DEADMAN_CONFIG` is a `/nix/store/…-fleet-deadman.json` path.
- `onFailure` is `["observability-notify@%n.service"]`.
- `Type` is `oneshot`; `DynamicUser` is `true`; `StateDirectory` is `fleet-deadman`; `UMask` is `0077`.
- `LoadCredential` is `["alerter-token:/run/secrets/vars/shared/ntfy-alerter/token"]`.
- The timer prints `{"AccuracySec":"5s","OnCalendar":"*:0/5"}`.
- The template's `LoadCredential` is `["alerter-token:/run/secrets/vars/shared/ntfy-alerter/token"]`.

Run: `nix build "$(nix eval --raw .#nixosConfigurations.cinnabar.config.systemd.services.fleet-deadman.environment.FLEET_DEADMAN_CONFIG)" && jq -S . "$(nix eval --raw .#nixosConfigurations.cinnabar.config.systemd.services.fleet-deadman.environment.FLEET_DEADMAN_CONFIG)"`
Expected: `evaluatorHost` `magnetite`, `heartbeatTopic` `fleet-heartbeat`, `ntfyUrl` `http://[::1]:2586`, `topic` `fleet-alerts`, `window` `10m`, `stateFile` `/var/lib/fleet-deadman/state.json`, and one rule, `AlertEvaluatorSilent`, with `for` `0` and severity `critical` (built output).

- [ ] **Step 13: Build cinnabar (tasks.md 5.3)**

Run: `nix build .#checks.x86_64-linux.nixos-cinnabar -L 2>&1 | tee logs/s3-evidence/5.3-nixos-cinnabar-$(date -u +%Y%m%dT%H%M%SZ).log`
Expected: exit 0; the toplevel builds with the dead-man, notifier and access entries (build).

- [ ] **Step 14: Tick the tasks**

In `openspec/changes/stand-up-fleet-alerting/tasks.md`, change `- [ ]` to `- [x]` on the lines beginning `- [ ] 5.1`, `5.2` and `5.3`, and nothing else.
Run: `jj diff --git -- openspec/changes/stand-up-fleet-alerting/tasks.md | grep -c '^+- \[x\]'`
Expected: `3`.

- [ ] **Step 15: Format (tasks.md 5.4)**

Run:

```bash
nix fmt -- modules/nixos/fleet-alert.nix modules/checks/fleet-alert.nix modules/checks/fleet-alert/ntfy_stub.py modules/machines/nixos/cinnabar/default.nix modules/machines/nixos/cinnabar/fleet-alert.nix modules/machines/nixos/cinnabar/ntfy.nix openspec/changes/stand-up-fleet-alerting/tasks.md 2>&1 | tee logs/s3-evidence/5.4-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
nix fmt -- --fail-on-change 2>&1 | tee -a logs/s3-evidence/5.4-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: both exit 0.
If the first command reformatted anything, rerun Step 10's `fleet-alert` build before committing, since the probe mutant's `--replace-fail` string must still match the formatted script.

- [ ] **Step 16: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(fleet-alert): run the dead-man on cinnabar and restrict fleet-* publishing to alerter'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(fleet-alert): run the dead-man on cinnabar")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/nixos/fleet-alert.nix \
  modules/checks/fleet-alert.nix \
  modules/checks/fleet-alert/ntfy_stub.py \
  modules/machines/nixos/cinnabar/default.nix \
  modules/machines/nixos/cinnabar/fleet-alert.nix \
  modules/machines/nixos/cinnabar/ntfy.nix \
  openspec/changes/stand-up-fleet-alerting/tasks.md
jj diff --name-only -r "$change"
```

Expected: the last command lists exactly the seven paths.
If `jj diff -r @ -- openspec/changes/stand-up-fleet-alerting/tasks.md` showed hunks other than the three ticks before the squash, squash that file with `--interactive` and select only the ticks.
The orchestrator rebases the development join, pushes, opens the pull request and enqueues it; nixbot must report `checks.x86_64-linux.fleet-alert`, `ntfy-provisioning` and `nixos-cinnabar` green, and the PR must be merged before Step 17.

- [ ] **Step 17: Deploy C3 (tasks.md 5.5)**

Gate: Task 7's 7.2 evidence is recorded (magnetite's evaluator heartbeats at least 9 times in 10 min on cinnabar and posts with the token), and this task's PR is merged on `origin/main`.
Deploy cinnabar with Task 7 Step 0's procedure; magnetite is not deployed.
Immediately after activation, run `ssh cinnabar.zt 'systemctl is-active ntfy-sh; systemctl list-timers fleet-deadman.timer --no-pager' 2>&1 | tee logs/s3-evidence/5.5-c3-activation-$(date -u +%Y%m%dT%H%M%SZ).log`.
Expected: `active`, and the timer listed with its next run within 5 min (delivered units).
If `ntfy-sh` is not active, roll back by redeploying cinnabar from the C2 revision per design.md's Migration Plan, and stop.
Verify: Task 7's 7.3 passes. It covers the probe answered 403 every 5 min, stibnite's three-way publish matrix, and R9.4's runtime negative control: a temporary deploy without the `"*:fleet-*:ro"` line makes `fleet-deadman.service` fail and `FAILED fleet-deadman.service on cinnabar` arrive.

---

Questions and contract notes for the orchestrator:

1. Contract additions to fold into `plan-head.md`:
   - option `services.fleet-alert.deadman.evaluatorHost` (str, default `magnetite`), as decided;
   - env `FLEET_DEADMAN_CONFIG` with the JSON `{ ntfyUrl, topic, evaluatorHost, heartbeatTopic, window, stateFile, rules }`;
   - `flake.lib.fleetAlertDeadman pkgs { ntfySend; transition ? transitionJq; }`, mirroring the evaluator's signature;
   - check bindings `deadmanRehearsal`, `deadmanClause`, `deadmanFailures`, `deadmanMutants`, `deadmanInput`, `decision`, and data file `modules/checks/fleet-alert/ntfy_stub.py`;
   - the dead-man's token-wiring assertion in `fleet-alert.nix` and cinnabar's host token assertion, each shown able to fail by an `extendModules` override, in place of extending a check clause to cinnabar (charter v18).
2. The heartbeat topic is `services.fleet-alert.evaluator.heartbeatTopic` on both hosts, not a literal. The dead-man reads cinnabar's value of that option, which is its default there. `deadmanFailures` relates it to magnetite's value, so a change on magnetite alone fails the check.
3. Task 4 names this task relies on, which S3PlanT4 sent as final on 2026-10-18:
   - bindings `ntfySendStub` (its `headers` field is the list of `-H` values) and `fixtureCredentials`;
   - the check's `passthru` and its `test -e ${propertyRehearsal}` line, after which Step 3 inserts;
   - in the module, `hardening`, `jqLib` and `transitionJq`.

   Check them against the final `plan-T4.md` at assembly.
4. Resolution timing: with Task 4's "absent ≥ 300 s" rule and 5-min runs, `RESOLVED` normally comes on the first run after heartbeats resume. If the comparison is strict, it comes on the second. Step 10 stops rather than adapting, and S3PlanT678 was told to allow up to two runs in 7.5.
5. Resolved by the orchestrator: `fleet-deadman.service` is ordered after `ntfy-sh.service`, `caddy.service` and `zerotierone.service`, with no `wants`. `deadmanFailures` checks that those three units exist on cinnabar, that each is in `after` and that none is in `wants`; three mutants cover it. On 2026-10-18, `nix eval` of cinnabar's `systemd.services` found all three units, so `pathUnits` equals `deadmanPathUnits` at the base. plan-head's dead-man constraint needs the same change at assembly.
6. Step 11's budget is shared with Task 4's measurement of the same check. If Task 4 already sits near 0.5 GiB, the `execStart` clause, which forces cinnabar's `ntfy-send` derivation, is the first candidate to move into an assertion.

---

### Task 6: Documentation

This task is `tasks.md` group 6 and lands as pull request 6, after Task 5's pull request has merged.
It changes prose only; no module, check or package changes.
The runbook describes the system as deployed after C3, so it is written after Task 7's 7.1 to 7.3 have passed, and any runbook fact Task 7 contradicts is corrected here before the commit.

**Files:**
- Modify: `packages/docs/src/content/docs/development/operations/fleet-observability.md` (front matter `description`, `:6-8`, `:10-20`, `:56-86`, `:147-170`, `:186-189`)
- Modify: `modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md` (`:196`)
- Modify: `modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md` (`:140`)
- Modify: `modules/README.md` (after `:49`)
- Create (git-ignored evidence): `logs/s3-evidence/6.1-linkcheck-<ts>.log`, `logs/s3-evidence/6.x-rg-<ts>.log`, `logs/s3-evidence/6.3-delivered-<ts>.log`, `logs/s3-evidence/6.5-fmt-<ts>.log`

**Interfaces:**
- Consumes: every name in the plan's Interface contract as it was deployed: topics `fleet-alerts`, `fleet-heartbeat`, `fleet-acceptance`; units `fleet-alert.{service,timer}`, `fleet-deadman.{service,timer}`, `observability-notify@.service`; files `/var/lib/fleet-alert/state.json` (its `.firings[]` entries `{at, alert, host}` and `.budgetPostedAt`, from Task 4), `/var/lib/observability-notify/failed.log`, `/var/lib/fleet-deadman/state.json`; generators `ntfy-alerter` (shared, file `token`) and `ntfy-alerter-env` (cinnabar only, file `ntfy-env`, `dependencies = [ "ntfy-alerter" ]`); `ntfy-send`'s `NTFY_TOKEN_FILE`; caddy's root certificate `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt` (CN `Caddy Local Authority - 2026 ECC Root`, SHA-256 `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82`), live on cinnabar at `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt` (`services.caddy.dataDir` evaluates to `/var/lib/caddy`; the directory listing was read on cinnabar on 2026-10-18), and installed on darwin hosts by `flake.modules.darwin.zt-services-trust`.
- Produces: the operator's alerting runbook that Task 7's 7.7 follows; the agent-facing line that `fleet-*` topics need `NTFY_TOKEN_FILE`; the `modules/README.md` entry for the two new gating checks.

- [ ] **Step 1: Create the change**

Run from `/Users/crs58/projects/vanixiets`:

```bash
jj new --no-edit -r main@origin -m 'docs(observability): alerting runbook and ntfy-send token notes for S3'
```

Expected: `Created new commit <change-id> ...`; note `<change-id>` as `DOCS`.
Edits below are made in the working copy; Step 9 moves them into `DOCS`.

- [ ] **Step 2: Write the failing documentation probe**

Run:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s3-evidence"; mkdir -p "$EV"
RB=packages/docs/src/content/docs/development/operations/fleet-observability.md
{
  for p in 'fleet-alerts' 'NTFY_TOKEN_FILE' 'AlertEvaluatorSilent' 'WeeklyPipelineTest' 'StoreQueryFailing' 'RuleSignalMissing' 'AlertBudgetExceeded' 'state.json' 'failed.log' 'observability-notify.nix' 'caddy-root-ca.crt' 'ntfy-alerter-env'; do
    printf '%s %s\n' "$(rg -c -F "$p" "$RB" || echo 0)" "$p"
  done
  echo '$ rg -n "S3: alert rules" '"$RB"; rg -n 'S3: alert rules' "$RB" || true
  echo '$ rg -n NTFY_TOKEN_FILE skills'; rg -n 'NTFY_TOKEN_FILE' modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md || echo 'no NTFY_TOKEN_FILE line'
  echo '$ rg -n "fleet-alert|observability-notify|ntfy-provisioning" modules/README.md'; rg -n 'fleet-alert|observability-notify|ntfy-provisioning' modules/README.md || echo 'no README entry'
} 2>&1 | tee "$EV/6.x-rg-before-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected (the failing state): `0` before every term except `fleet-alerts` (2 on today's page); the `S3: alert rules` line at `:189`; `no NTFY_TOKEN_FILE line`; `no README entry`.

- [ ] **Step 3: Rewrite the runbook's opening and "What runs where" (6.1, 6.2)**

In `packages/docs/src/content/docs/development/operations/fleet-observability.md`, replace the front-matter `description` line (`:3`) with:

```yaml
description: "Operating the fleet's telemetry store, metrics collector and alerting: dashboard access, alerts and failure notices on fleet-alerts, the dead-man on cinnabar, the hourly envelope, credential rotation and retention."
```

Replace `:6-8` with:

```markdown
This runbook is for the operator of the fleet's telemetry store and alerting, as deployed by slices S1 and S3.
It assumes SSH access to `magnetite.zt` and `cinnabar.zt` over ZeroTier, `sudo` on both, and a vanixiets checkout with the `clan` CLI on the workstation.
The maintainer contract for the collector lives in `modules/clan/services/otel-collector/README.md`; the failure notifier lives in `modules/nixos/observability-notify.nix`, the alert evaluator and the dead-man in `modules/nixos/fleet-alert.nix`, and the rules in `modules/nixos/fleet-alert/rules.nix`.
```

Replace `:10-20` (the heading through the `observability-notify@.service` bullet) with:

```markdown
## What runs where

S1's store and collector, and S3's alert evaluator, run on magnetite; ntfy and S3's dead-man run on cinnabar.

- `greptimedb.service` runs GreptimeDB standalone, listening only on loopback: HTTP on `127.0.0.1:4000` and gRPC on `127.0.0.1:4001`.
- Its WAL and caches live on the ZFS dataset `zroot/root/greptimedb` at `/var/lib/greptimedb`, with a 16G quota and a 12G reservation.
- Its table data goes to Cloudflare R2, bucket `sciexp`, under the prefix `projects/vanixiets/observability/store/`.
- `greptimedb-schema.service` creates the databases and sets their retention each time the store starts.
- `opentelemetry-collector.service` collects magnetite's host, unit, process-memory, ZFS, OOM-kill and service metrics and writes them to the store.
- `greptimedb-envelope.timer` runs `greptimedb-envelope.service` hourly to check the store's runtime envelope.
- `observability-notify@.service` posts unit failures to ntfy with the `alerter` token, on magnetite and on cinnabar.
- `fleet-alert.timer` runs `fleet-alert.service` on magnetite every 60 s: it evaluates the alert rules against `fleet`, posts a heartbeat to `fleet-heartbeat`, and posts alerts to `fleet-alerts`.
- `fleet-deadman.timer` runs `fleet-deadman.service` on cinnabar every 5 min: it checks that anonymous publishing to `fleet-heartbeat` is refused, then raises `AlertEvaluatorSilent` when no heartbeat arrived in the last 10 min.
- `ntfy-sh.service` on cinnabar serves `https://ntfy.zt` through caddy; only the `alerter` user may publish to `fleet-*` topics, every other topic stays open to anonymous publishing, and anyone on the mesh may subscribe.
```

- [ ] **Step 4: Replace "Reading fleet-alerts" with the alerting section (6.1, 6.2)**

Replace `:56-86` (from `## Reading fleet-alerts` through the stamp paragraph ending `...until its next start or successful exit.`) with:

````markdown
## Subscribing to fleet-alerts

Alerts and failure notices go to the ntfy topic `fleet-alerts` at `https://ntfy.zt/fleet-alerts`.
`ntfy.zt` resolves only through cinnabar's dnsmasq and listens only on cinnabar's ZeroTier addresses, so a subscriber must be a ZeroTier member of the fleet network.
caddy serves it with a certificate from its internal CA, so a subscriber must also trust caddy's root certificate.
The root certificate is committed at `modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt` (`CN=Caddy Local Authority - 2026 ECC Root`, SHA-256 fingerprint `7E:78:F6:7C:83:BD:DC:81:51:FF:EB:8F:82:1A:68:5D:02:89:9F:93:27:33:7F:9B:F2:41:9B:F9:3B:AA:2E:82`); caddy's live copy on cinnabar is `/var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt`.
Before installing it anywhere, check that the committed file is still the live one:

```sh
openssl x509 -in modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt -noout -fingerprint -sha256
ssh cinnabar.zt 'sudo cat /var/lib/caddy/.local/share/caddy/pki/authorities/local/root.crt' | openssl x509 -noout -fingerprint -sha256
```

The two fingerprints must match.

On macOS, a darwin host that enables `services.zt-services-trust` installs the certificate into the System keychain at activation.
On a Mac without it, install it by hand:

```sh
sudo security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt
```

Then open `https://ntfy.zt/fleet-alerts` in a browser and allow notifications, or add the server `https://ntfy.zt` and the topic `fleet-alerts` in the ntfy desktop app.

On Android, join the ZeroTier network in the ZeroTier app, copy `caddy-root-ca.crt` to the phone, and install it under Settings → Security → Encryption & credentials → Install a certificate → CA certificate.
In the ntfy app, add a subscription to topic `fleet-alerts` on the server `https://ntfy.zt` (use another server, not `ntfy.sh`).
The server sets no `upstream-base-url`, so iOS clients receive no instant push; this runbook supports Android and desktop subscribers.

From a shell on any mesh host, poll recent messages:

```sh
curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=1h' | jq -c '{time, title, priority, message}'
```

ntfy keeps each topic's messages for 12 hours, so a poll or a reconnecting phone sees at most the last 12 hours.

## Reading alerts

An alert's title is `[FIRING] <alert> <host>` or `[RESOLVED] <alert> <host>`.
Its priority follows the rule's severity: `high` for `critical`, `default` for `warning`, `low` for `info`.
An alert fires after its condition has held on every evaluation for the rule's `for`, and resolves after the condition has been absent for 5 minutes.
A `critical` alert that stays firing is posted again once every 24 hours; a `warning` alert is never posted again while it fires; an `info` alert posts no `RESOLVED`.
`HostMemoryPressure` and `HostOOMKill` messages end with the host's three largest executables by resident memory, its ZFS ARC size and its swap used; resident memory omits swapped-out pages, so the ranking cannot see what sits in swap.

| Alert | Severity | What it means | What to do |
|---|---|---|---|
| `HostMemoryPressure` | warning | for 5 min, available memory plus reclaimable ARC was below 10% of memory, or swap was over 85% used | read the attribution in the message, then `systemctl status` the top executable's unit; on magnetite the nixbot evaluator is usually the cause |
| `HostOOMKill` | critical | the kernel OOM killer killed a process in the last 10 min | `sudo journalctl -k -g 'Killed process' --since -15min` on the host, then the owning unit's status |
| `ZfsPoolUnhealthy` | critical | a ZFS pool has been in a state other than `online` for 1 min | `zpool status -x` on the host; replace or reattach the failed device before anything else |
| `SystemdUnitRestartLoop` | warning | a unit restarted more than 5 times in 15 min | `systemctl status <unit>` and `journalctl -u <unit> -n 100`; the notifier caps its own messages, so this alert is the one that shows the loop |
| `SystemdUnitFailed` | warning | an allow-listed unit outside the notifier's units has been failed for 5 min | `systemctl status <unit>`; the notifier's own units report through `FAILED` notices instead, never through this alert |
| `LocalExporterDown` | warning | the host's node exporter has been down for 10 min, so its OOM, ZFS and memory rules are blind | `sudo systemctl restart prometheus-node-exporter`, then check `up{job="node"}` in the dashboard |
| `WeeklyPipelineTest` | info | the weekly test: it fires once each Monday between 09:00 and 09:05 New York time | nothing; its absence on a Monday morning means the path from the store to the phone is broken |
| `StoreQueryFailing` | critical | the store has not answered the evaluator for 3 min; every other alert is frozen meanwhile | `systemctl status greptimedb` and `sudo journalctl -u greptimedb -n 100 --no-pager` on magnetite; alerts resume when it answers |
| `RuleSignalMissing` | warning | a rule's input series has been absent for 30 min while its expected host reports memory, so the rule can no longer fire | find the metric's producer: the collector config, the node exporter, or a renamed metric in a dependency update |
| `AlertEvaluatorSilent` | critical | cinnabar's dead-man saw no heartbeat on `fleet-heartbeat` for 10 min | on magnetite `systemctl status fleet-alert.timer fleet-alert.service` and `journalctl -u fleet-alert -n 50`; also check magnetite is up and on the mesh |
| `AlertBudgetExceeded` | warning | more than 10 `FIRING` messages, or more than 3 for one laptop, were posted in 24 hours | the alerts have become noise; read the 24 hours of `fleet-alerts` and tune the rule that dominates, through a pull request |

While a host reports no `system_memory_usage_bytes`, its alerts are frozen: they neither resolve nor post again, so a sleeping laptop does not churn.

## Reading failure notices

Unit failures go to the same topic as plain messages without a title.
The notified units on magnetite are `greptimedb`, `greptimedb-schema`, `greptimedb-envelope`, `opentelemetry-collector`, `fleet-alert` and magnetite's `zfs-set-*` and `zfs-assert-*` oneshots; on cinnabar it is `fleet-deadman`.
Print the current list for a host:

```sh
nix eval --json .#nixosConfigurations.magnetite.config.services.observability-notify.units
```

- `FAILED <unit> on <host>` means the unit entered the failed state and a new failure episode began.
- `RESOLVED <unit> on <host>` means the same unit has since started again, or exited successfully, and the episode is over.

Within one episode the notifier posts once, however many times the unit fails.
It also posts at most one `FAILED` per unit per 15 minutes: a failure within 15 minutes of the last posted `FAILED` opens a suppressed episode that ends without a message.
A unit in a crash loop therefore shows one `FAILED`/`RESOLVED` pair, then at most one new pair every 15 minutes, so the messages understate how often it is failing; `SystemdUnitRestartLoop` reports the loop itself.
Check the real restart count on magnetite:

```sh
systemctl show opentelemetry-collector -p NRestarts
```

Each failure runs one notifier instance, named after the failed unit with a second `.service` suffix:

```sh
sudo journalctl -u 'observability-notify@greptimedb-envelope.service.service' --no-pager
```

The notifier keeps one stamp per open episode in `/var/lib/observability-notify/<unit>`, containing `posted` or `suppressed`.
A stamp left behind by a failed `RESOLVED` post silences that unit until its next start or successful exit.
Each posted `FAILED` also appends one line `<epoch> <unit> <host>` to `/var/lib/observability-notify/failed.log`; a suppressed episode appends nothing.

## The alert budget and the evaluator's state

The evaluator keeps its state in `/var/lib/fleet-alert/state.json`, readable by root.
The alert budget counts `FIRING` messages over 24 hours: every posted `FIRING` and `critical` re-post recorded in `state.json`'s `.firings`, plus every line of `failed.log` from the same 24 hours; `info` alerts and `AlertBudgetExceeded` are not counted, and neither are cinnabar's dead-man and notifier posts.
Count it on magnetite the way the evaluator does:

```sh
now=$(date +%s)
sudo jq --argjson now "$now" '[.firings[] | select(.at > $now - 86400)] | length' /var/lib/fleet-alert/state.json
awk -v now="$now" '$1 > now - 86400' /var/lib/observability-notify/failed.log | wc -l
sudo jq '.budgetPostedAt' /var/lib/fleet-alert/state.json
```

The sum of the first two numbers above 10 raises one `AlertBudgetExceeded` per 24 hours, and the third prints when it was last posted.
List what is firing now:

```sh
sudo jq '.' /var/lib/fleet-alert/state.json | less
```

The dead-man keeps its own state in `/var/lib/fleet-deadman/state.json` on cinnabar.
A post that fails leaves its transition recorded as unposted, and the next run posts it, so a short ntfy outage delays alerts rather than losing them.

## Publishing to fleet topics

Only the `alerter` user may publish to topics matching `fleet-*`; an anonymous publish there is answered 403.
Every other topic, including each host's own topic used by agent notifications, still accepts anonymous publishing.
To publish to a `fleet-*` topic by hand as root on magnetite or cinnabar, give `ntfy-send` the token file:

```sh
sudo NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token "$(command -v ntfy-send)" "manual test" fleet-acceptance
```

`ntfy-send` reads the token from that file and passes it to curl on standard input, so it never appears on a command line.
Use `fleet-acceptance` for tests; it is a `fleet-*` topic that nobody subscribes to by default.
````

- [ ] **Step 5: Add the deploy order, rollback and token rotation (6.1)**

Insert after the `## Rotating credentials` section's last line (`R7.4 does not cover this credential; ...`, `:170`) and before `## Declaring a per-table TTL`:

````markdown
### The alerter token

The `alerter` token comes from the shared generator `ntfy-alerter`, whose `token` file is deployed to magnetite and cinnabar.
cinnabar's per-machine generator `ntfy-alerter-env` derives ntfy's provisioning file `ntfy-env` from that token and a password it hashes and discards.
ntfy accepts only the token in its current `ntfy-env`, and answers any other token with 401, so rotation follows the cutover order, cinnabar then magnetite, back to back:

```sh
clan vars generate cinnabar --regenerate --generator ntfy-alerter
clan vars generate cinnabar --regenerate --generator ntfy-alerter-env
clan machines update cinnabar
clan machines update magnetite
```

Between the two deployments magnetite still posts with the old token and every post is refused with 401.
The evaluator records each refused transition as unposted and posts it on its first run after magnetite's deployment, so alerts are delayed, not lost.
A `FAILED` or `RESOLVED` notice from magnetite's notifier inside that window is lost; check `fleet-alerts` against `systemctl list-units --failed` on magnetite afterwards.
Run the rotation from a fresh worktree of `origin/main` with the vars commit pushed through a pull request first, following the deployment procedure below.

## Deploying the alerting changes

Alerting spans two hosts, and ntfy refuses a token it does not know even on an open topic, so changes that touch the token or ntfy's access entries deploy in a fixed order.
The S3 cutover took three deployments, each from a fresh worktree of `origin/main` and only when `nixbot-logs queue` prints `Queue is empty`:

1. cinnabar: ntfy provisions `alerter` and its token and separates mesh clients as visitors; there are no access entries yet, so every publisher still works.
2. magnetite: the evaluator and the notifier start posting with the token.
3. cinnabar: ntfy gains `auth-access` (`alerter:fleet-*:rw`, `*:fleet-*:ro`) and the dead-man starts.

Roll back in the reverse order: redeploy cinnabar without the access entries first, then revert magnetite to anonymous posting, and only then remove the provisioning.
Removing `alerter` from `ntfy-env` deletes the user and its token at ntfy's next start, and every token-bearing post is then refused with 401.
````

- [ ] **Step 6: Update "Not covered yet" (6.1)**

Replace `:189` (`- S3: alert rules on the store, the dead-man on cinnabar, and ntfy access control.`) with:

```markdown
- S3 left for later slices: the filesystem, NVMe, launchd and `HostProbeStale` rules (S4, S5), the dev-loop SLO burn rule (S2), and an external watch of cinnabar and ntfy themselves (CAM-76).
```

Run:

```bash
nix build .#checks.x86_64-linux.package-vanixiets-docs-test-linkcheck -L 2>&1 | tee "$EV/6.1-linkcheck-$(date -u +%Y%m%dT%H%M%SZ).log" | tail -n 5
```

Expected: the build succeeds (exit 0); a failure names the broken link, which is fixed in the page before continuing.
If it fails on a link outside this page, record it in the log and ask the orchestrator; never edit another page under this task.

- [ ] **Step 7: Add the `NTFY_TOKEN_FILE` line to the two skills (6.3)**

The skill sources are under `modules/home/ai/plugins/*/.apm/skills/` (`modules/home/ai/README.md`, "Source versus delivered"); neither skill carries `generatedBy` front matter, so both are hand-authored (`modules/home/ai/plugins/README.md:18`).
Confirm:

```bash
rg -n '^generatedBy' modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md || echo 'hand-authored'
```

Expected: `hand-authored`.

In `nix-flake-pr-cycle/SKILL.md`, insert after `:196` (the paragraph beginning `The wrapper script lives at`):

```markdown
Host topics accept anonymous posts, so these NOTICEs need no credential; topics matching `fleet-*` (`fleet-alerts`, `fleet-heartbeat`, `fleet-acceptance`) accept only the `alerter` token, which `ntfy-send` reads from the file named by `NTFY_TOKEN_FILE` and never places on a command line; agents do not post there.
```

In `preferences-style-and-conventions/SKILL.md`, replace `:140` with:

```markdown
  - Notification (push alert to user): use `ntfy-send "<message>"` where `<message>` includes the repo name and summarizes the completed task (default topic is the local hostname; override with `ntfy-send "<message>" <topic>`; `fleet-*` topics need the `alerter` token through `NTFY_TOKEN_FILE`, host topics stay anonymous)
```

- [ ] **Step 8: Add the gating checks to `modules/README.md` (6.4)**

`modules/README.md` does not list individual `nixos/` modules (`:28`), so no module entry is added; it names gated checks in the `## On-demand VM tests` section's opening paragraph.
Insert after `:49` (the `zerotier-mss-clamp` sentence):

```markdown
The fleet-alerting checks are gated the same way and need no runtime host: `checks.x86_64-linux.fleet-alert` runs `promtool` over the rules rendered by `nixos/fleet-alert/rules.nix`, replays canned store answers through a loopback fixture server against the evaluator in `nixos/fleet-alert.nix` with a recording `ntfy-send`, compares `nixos/fleet-alert/transition.jq` with a Python reference model under a derandomized Hypothesis test, and checks that every `fleet-*` publisher on magnetite and cinnabar, `observability-notify@` from `nixos/observability-notify.nix` included, loads the `ntfy-alerter` token by path; `checks.x86_64-linux.ntfy-provisioning` runs the `ntfy-alerter` and `ntfy-alerter-env` generators from `nixos/ntfy-alerter.nix` in the sandbox and checks the rendered token, password hash and cinnabar's access entries before ntfy could refuse them at start.
ntfy's access control, its rate limiting and the rules against real series are verified at deployment, not by these checks.
```

Run the probe again:

```bash
{
  for p in 'fleet-alerts' 'NTFY_TOKEN_FILE' 'AlertEvaluatorSilent' 'WeeklyPipelineTest' 'StoreQueryFailing' 'RuleSignalMissing' 'AlertBudgetExceeded' 'state.json' 'failed.log' 'observability-notify.nix' 'caddy-root-ca.crt' 'ntfy-alerter-env'; do
    printf '%s %s\n' "$(rg -c -F "$p" "$RB" || echo 0)" "$p"
  done
  rg -n 'S3: alert rules|holds no credential|anonymous' "$RB" || true
  rg -n 'NTFY_TOKEN_FILE' modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md
  rg -n 'fleet-alert|observability-notify|ntfy-provisioning' modules/README.md
} 2>&1 | tee "$EV/6.x-rg-after-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: every count at least `1`; no `S3: alert rules` line; the `anonymous` matches are only the subscription, host-topic and 403 sentences written above; one `NTFY_TOKEN_FILE` line per skill; the README lines naming both checks and the three modules.

- [ ] **Step 9: Format and commit**

Run:

```bash
jj st --no-pager >/dev/null
nix fmt -- packages/docs/src/content/docs/development/operations/fleet-observability.md modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md modules/README.md 2>&1 | tee "$EV/6.5-fmt-$(date -u +%Y%m%dT%H%M%SZ).log"
nix fmt -- --fail-on-change packages/docs/src/content/docs/development/operations/fleet-observability.md modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md modules/README.md; echo "fmt-exit=$?"
jj squash --from @ --into DOCS --keep-emptied --use-destination-message -- \
  packages/docs/src/content/docs/development/operations/fleet-observability.md \
  modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md \
  modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md \
  modules/README.md
jj log -r DOCS --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `fmt-exit=0`; `DOCS` shows the four files.
In `openspec/changes/stand-up-fleet-alerting/tasks.md` tick 6.1 to 6.5 and squash it into `DOCS` the same way.
The orchestrator adds `DOCS` to the development join, pushes and opens pull request 6; nixbot's green run is 6.5's verification.

- [ ] **Step 10: Verify the delivered skill line after activation (6.3)**

After pull request 6 merges and the workstation is activated from `origin/main` (`just activate` on stibnite), run:

```bash
{
  for s in nix-flake-pr-cycle preferences-style-and-conventions; do
    for root in ~/.claude/skills ~/.agents/skills; do
      echo "\$ rg -n NTFY_TOKEN_FILE $root/$s/SKILL.md"; rg -n 'NTFY_TOKEN_FILE' "$root/$s/SKILL.md" || echo "MISSING in $root/$s"
    done
  done
} 2>&1 | tee "$EV/6.3-delivered-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: one line per file and no `MISSING`; `~/.claude/skills/*` are read-only store symlinks and `~/.agents/skills/*` real-file copies (`modules/home/ai/README.md`), so both delivery forms are checked.

---

### Task 7: Deployment verification

This task is `tasks.md` group 7: operations interleaved with the three cutover deploys, plus one small pull request (7.4's `log-level` revert).
Step 0 defines the single deploy procedure that Task 3's 3.7, Task 4's 4.11 and Task 5's 5.5 invoke, and the baseline that must run before C1.
The order is strict: Steps 0–2 before C1; Steps 3–8 (7.1) after C1 and before C2; Steps 9–15 (7.2) after C2 and before C3; Steps 16–21 (7.3) after C3; Steps 22–26 (7.4); Steps 27–28 (7.5); Steps 29–34 (7.6); Step 35 (7.7).
A failed expectation stops the task at that step, and the next deploy does not start until the orchestrator decides; rollback, if chosen, follows design.md's reverse order.
Every observation goes to `logs/s3-evidence/` (git-ignored); Task 8 folds it into `verify.md`; `tasks.md` items 7.x are ticked in Task 8's change, not here.
No step prints a credential: token-bearing commands read files, and any output that could carry a `tk_` value is redacted before it is written.

**Files:**
- Create (git-ignored helpers): `logs/s3-evidence/s3-deploy.sh`, `logs/s3-evidence/handrun.sh`, `logs/s3-evidence/polls.sh`, `logs/s3-evidence/window.env`
- Create (git-ignored evidence): `logs/s3-evidence/<id>-<slug>-<UTC ts>.log` for every step below, and the deploy logs `logs/s3-evidence/<host>-<ts>.log`
- Modify (7.4 revert pull request): `modules/machines/nixos/cinnabar/ntfy.nix` (remove `log-level`), only if Task 3 set it
- Temporary: worktrees `/tmp/wt-s3-<label>` at `origin/main`, removed by the procedure

**Interfaces:**
- Consumes: `fleet-alert.service`/`.timer` with `Environment=FLEET_ALERT_CONFIG=/nix/store/…-fleet-alert-config.json` and a bare-executable `ExecStart` (Task 4); the config keys `storeUrl, database, user, queryTimeoutSec, queryDeadlineSec, postDeadlineSec, topic, heartbeatTopic, stateFile, failedLog, rules`, each rule `{ alert, expr (fully rendered), for (integer seconds), severity, annotations, presence, attribution, window? }`, `RuleSignalMissing` and `StoreQueryFailing` as `.rules[]` entries with `for` 1800 and 180, the window `{ zone: "America/New_York", weekday: 1 (ISO, Mon=1..Sun=7), start: "09:00", end: "09:05" }` with `start` inclusive and `end` exclusive (Task 4, confirmed by S3PlanT4); `state.json`'s `.firings[] = { at, alert, host }` and `.budgetPostedAt` (Task 4); credentials `regulator-password` and `alerter-token`, the evaluator reading `$CREDENTIALS_DIRECTORY/regulator-password` and `ntfy-send` reading `NTFY_TOKEN_FILE`; `fleet-deadman.service` journal lines `fleet-deadman: R9.4 probe refused with HTTP 403`, `fleet-deadman: R9.4: anonymous publish to fleet-heartbeat answered HTTP <code>, expected 403`, `fleet-deadman: <n> heartbeat(s) on fleet-heartbeat in the last 10m`, its timer `OnCalendar = "*:0/5"` (Task 5, confirmed by S3PlanT5); cinnabar's `auth-access` written as the three lines `auth-access = [` / `"alerter:fleet-*:rw"` / `"*:fleet-*:ro"` / `];` (Task 5); generators `ntfy-alerter` (shared, `token`) and `ntfy-alerter-env` (cinnabar, `ntfy-env`) (Task 3); `observability-notify@.service` and `failed.log` (Task 2); ntfy 2.28.0's debug log lines `HTTP request finished (…)` and `Connection closed with HTTP <code> (ntfy error <n>) (…)`, whose fields are sorted `key=value` pairs including `http_method`, `http_path`, `visitor_ip` and, for an authenticated request, `user_name` (`binwiederhier/ntfy@v2.28.0:server/server.go:499-545`, `log/event.go:199-209`, `server/visitor.go:149-180`); the anonymous `GET /v1/account` answer, whose `.stats.messages` is that visitor's message counter (`server/server.go:592`, `server/server_account.go` `handleAccountGet`, `server/visitor.go:338`).
- Produces: magnetite and cinnabar running C3 then the revert; the evidence logs listed per step; `window.env` with `C1_START`, `C1_END`, `C2_START`, `C2_END`, `C3_START`, `C3_END`, `T_BADTOKEN`, `T_ANON403`, `T_CURL22`, `W_END`, `T_STOP`, `T_START`, `T_CAP_START`, `T_OOM`, `T_STORE_STOP`, `T_STORE_START`, `T_EXP_STOP`, `T_EXP_START`, `T_FORCED`; the running capture `fleet-alerts-capture.service` on pyrite, writing `/var/lib/fleet-alerts-capture.jsonl`, which Task 8 Step 2 stops and copies.

- [ ] **Step 0: Write the deploy procedure (used by 3.7, 4.11, 5.5 and this task)**

Create `logs/s3-evidence/s3-deploy.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Deploy one host from a fresh worktree of origin/main, only when nixbot's queue is empty.
# Usage: s3-deploy.sh HOST LABEL [FILE LINE]
#   LABEL names the window variables (<LABEL>_START, <LABEL>_END) appended to window.env.
#   FILE LINE (negative controls only): delete exactly that line from FILE in the worktree before deploying.
set -euo pipefail
host=$1; label=$2; file=${3:-}; line=${4:-}
repo=$(git -C "$(dirname "$0")" rev-parse --show-toplevel)
ev=$repo/logs/s3-evidence
wt=/tmp/wt-s3-$label
ts() { date -u +%Y%m%dT%H%M%SZ; }
cd "$repo"
if [ -e "$wt" ]; then git worktree remove "$wt"; fi   # refuses on a dirty worktree: stop and ask, never --force
git fetch -q origin
git worktree add -q --detach "$wt" origin/main
echo "origin/main: $(git -C "$wt" log --oneline -1)"
if [ -n "$file" ]; then
  grep -vxF -- "$line" "$wt/$file" > "$wt/$file.new"
  mv "$wt/$file.new" "$wt/$file"
  git -C "$wt" diff --numstat
  [ "$(git -C "$wt" diff --numstat)" = "$(printf '0\t1\t%s' "$file")" ] || { echo "edit is not exactly one deleted line"; exit 1; }
fi
until nixbot-logs queue 2>&1 | tee "$ev/queue-$label-$(ts).log" | grep -q 'Queue is empty'; do
  echo "queue busy at $(date -u +%FT%TZ); retrying in 120 s"; sleep 120
done
echo "${label}_START=$(date -u +%FT%TZ)" | tee -a "$ev/window.env"
cd "$wt"
mkdir -p logs
log="logs/$host-$(ts).log"
clan machines update "$host" --upload-inputs 2>&1 | tee "$log"
status=${PIPESTATUS[0]}
echo "${label}_END=$(date -u +%FT%TZ)" | tee -a "$ev/window.env"
mv "$log" "$ev/"
if [ -n "$file" ]; then git checkout -q -- "$file"; fi
cd "$repo" && git worktree remove "$wt"
echo "clan exit=$status; log $ev/$(basename "$log")"
exit "$status"
```

Run:

```bash
chmod +x "$(git rev-parse --show-toplevel)/logs/s3-evidence/s3-deploy.sh"
bash -n "$(git rev-parse --show-toplevel)/logs/s3-evidence/s3-deploy.sh" && echo syntax-ok
```

Expected: `syntax-ok`.
`nixbot-logs` prints the empty-queue line on stderr, which is why `2>&1` precedes `tee` (S1 plan Task 6 Step 5).
The only use of `FILE LINE` is Step 20's R9.4 negative control; every cutover deploy runs `s3-deploy.sh <host> <C1|C2|C3>` with no edit.
3.7, 4.11 and 5.5 each run `/Users/crs58/projects/vanixiets/logs/s3-evidence/s3-deploy.sh cinnabar C1`, `… magnetite C2` and `… cinnabar C3` respectively, after their own gate, and expect `clan exit=0`.

- [ ] **Step 1: Write the poll and hand-run helpers**

Create `logs/s3-evidence/polls.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Poll a topic anonymously from the workstation over the mesh.
# Usage: polls.sh TOPIC SINCE   (SINCE as ntfy accepts it: 10m, 1h, or an epoch)
set -euo pipefail
curl -sk "https://ntfy.zt/$1/json?poll=1&since=$2" \
  | jq -c 'select(.event == "message") | {time: (.time | todate), title, priority, message}'
```

Create `logs/s3-evidence/handrun.sh` (git-ignored) with:

```bash
#!/usr/bin/env bash
# Run the deployed evaluator on magnetite with a transformed copy of its rendered configuration,
# a scratch state directory, and both topics set to fleet-acceptance.
# Usage: handrun.sh JQ_FILTER [RUNS] [INTERVAL_S]
#        handrun.sh reset          (delete the scratch state)
set -euo pipefail
ssh magnetite.zt "bash -s -- $(printf '%q ' "$@")" <<'REMOTE'
set -euo pipefail
if [ "$1" = reset ]; then sudo rm -rf /var/lib/private/fleet-alert-acceptance; echo "scratch state removed"; exit 0; fi
filter=$1; runs=${2:-1}; interval=${3:-60}
cfg=$(systemctl show fleet-alert -p Environment --value | tr ' ' '\n' | sed -n 's/^FLEET_ALERT_CONFIG=//p')
exe=$(systemctl show fleet-alert -p ExecStart --value | sed -n 's/.*path=\([^ ;]*\).*/\1/p' | head -n1)
echo "config $cfg"; echo "evaluator $exe"
sudo install -d -m 0755 /run/fleet-alert-acceptance
jq "($filter) | .topic = \"fleet-acceptance\" | .heartbeatTopic = \"fleet-acceptance\" | .stateFile = \"/var/lib/fleet-alert-acceptance/state.json\"" "$cfg" \
  | sudo tee /run/fleet-alert-acceptance/config.json >/dev/null
sudo chmod 0644 /run/fleet-alert-acceptance/config.json
for i in $(seq 1 "$runs"); do
  echo "# run $i at $(date -u +%FT%TZ)"
  sudo systemd-run --unit=fleet-alert-acceptance --wait --pipe --collect \
    -p DynamicUser=yes -p StateDirectory=fleet-alert-acceptance \
    -p LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password \
    -p LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token \
    -E NTFY_TOKEN_FILE=/run/credentials/fleet-alert-acceptance.service/alerter-token \
    -E FLEET_ALERT_CONFIG=/run/fleet-alert-acceptance/config.json \
    "$exe" && echo "exit=0" || echo "exit=$?"
  if [ "$i" -lt "$runs" ]; then sleep "$interval"; fi
done
REMOTE
```

Run:

```bash
chmod +x logs/s3-evidence/polls.sh logs/s3-evidence/handrun.sh
bash -n logs/s3-evidence/polls.sh && bash -n logs/s3-evidence/handrun.sh && echo syntax-ok
```

Expected: `syntax-ok`.
`NTFY_TOKEN_FILE` names the transient unit's credential directory by its fixed unit name rather than `%d`, so it does not rely on specifier expansion in a transient unit's environment.
The credential paths are confirmed in Step 9 against the deployed unit's `LoadCredential=` before the first hand run.

- [ ] **Step 2: Record the pre-C1 baseline, including the visitor negative control (before 3.7)**

Run from the workstation (stibnite) before Task 3's deploy:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s3-evidence"
L="$EV/7.1-pre-c1-visitors-$(date -u +%Y%m%dT%H%M%SZ).log"
acct() { jq -r '.stats.messages'; }
{
  echo '$ ssh cinnabar.zt grep -E "behind-proxy|proxy-trusted|visitor-prefix|auth-access|log-level" <server.yml>'
  ssh cinnabar.zt 'yml=$(systemctl show ntfy-sh -p ExecStart --value | sed -n "s/.*-c \([^ ;]*\).*/\1/p"); echo "$yml"; grep -E "behind-proxy|proxy-trusted|visitor-prefix|auth-access|log-level" "$yml" || echo "none set"'
  s0=$(curl -sk https://ntfy.zt/v1/account | acct); m0=$(ssh magnetite.zt 'curl -sk https://ntfy.zt/v1/account' | acct)
  echo "before: stibnite=$s0 magnetite=$m0"
  for i in 1 2 3; do ntfy-send "s3 pre-c1 visitor probe $i" stibnite; done
  s1=$(curl -sk https://ntfy.zt/v1/account | acct); m1=$(ssh magnetite.zt 'curl -sk https://ntfy.zt/v1/account' | acct)
  echo "after 3 stibnite posts: stibnite=$s1 magnetite=$m1"
  [ $((m1 - m0)) -ge 3 ] && echo "NEGATIVE CONTROL HOLDS: magnetite's visitor counted stibnite's posts (one shared visitor)" || echo "UNEXPECTED: magnetite delta $((m1 - m0))"
} 2>&1 | tee "$L"
```

Expected: `none set`; then `NEGATIVE CONTROL HOLDS`, because before C1 every request through caddy arrives from `::1` and ntfy keys anonymous visitors by address (design D1), so stibnite's three posts raise the counter magnetite reads too.
An `UNEXPECTED` line means the observable cannot tell shared from separate visitors; stop and report, because Step 7 would then be vacuous.

- [ ] **Step 3: 7.1 — ntfy is up with `alerter` provisioned (after 3.7)**

First resolve the paths from the evaluated configuration at `origin/main`:

```bash
L="$EV/7.1-provisioning-$(date -u +%Y%m%dT%H%M%SZ).log"
{
  echo '$ nix eval --raw .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.ntfy-alerter.files.token.path'
  nix eval --raw "git+file:///Users/crs58/projects/vanixiets?ref=main#nixosConfigurations.cinnabar.config.clan.core.vars.generators.ntfy-alerter.files.token.path"; echo
  echo '$ nix eval --raw .#nixosConfigurations.cinnabar.config.clan.core.vars.generators.ntfy-alerter-env.files.ntfy-env.path'
  nix eval --raw "git+file:///Users/crs58/projects/vanixiets?ref=main#nixosConfigurations.cinnabar.config.clan.core.vars.generators.ntfy-alerter-env.files.ntfy-env.path"; echo
} 2>&1 | tee "$L"
```

Expected: `/run/secrets/vars/shared/ntfy-alerter/token` and `/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env`.
If either differs, use the printed path in every later step and note the difference in the log.
`ref=main` evaluates the local `main` bookmark, which the orchestrator keeps at `main@origin`; confirm with `jj log -r 'main & main@origin' --no-graph -T 'change_id.short()'` printing one id.

Then run:

```bash
{
  ssh cinnabar.zt '
    echo "\$ systemctl is-active ntfy-sh"; systemctl is-active ntfy-sh
    echo "\$ systemctl show ntfy-sh -p EnvironmentFiles"; systemctl show ntfy-sh -p EnvironmentFiles
    echo "\$ sudo ntfy user list"; sudo ntfy user list 2>&1
    echo "\$ sudo ntfy token list alerter (values redacted)"; sudo ntfy token list alerter 2>&1 | sed -E "s/tk_[-_A-Za-z0-9]{29}/tk_<redacted>/g"
    echo "\$ count of listed tokens equal to the deployed token file"; sudo bash -c "ntfy token list alerter 2>&1 | grep -c -F -f /run/secrets/vars/shared/ntfy-alerter/token"
    echo "\$ stat token"; sudo stat -c "%a %U" /run/secrets/vars/shared/ntfy-alerter/token
    yml=$(systemctl show ntfy-sh -p ExecStart --value | sed -n "s/.*-c \([^ ;]*\).*/\1/p")
    echo "\$ grep settings $yml"; grep -E "behind-proxy|proxy-trusted|visitor-prefix|auth-access|log-level|auth-default" "$yml"
  '
} 2>&1 | tee -a "$L"
```

Expected:
- `active`.
- `EnvironmentFiles=/run/secrets/vars/per-machine/cinnabar/ntfy-alerter-env/ntfy-env (ignore_errors=no)`.
- `ntfy user list` shows `user alerter (role: user, …)` and the anonymous `*` entry; `alerter` is marked provisioned.
- One redacted `tk_<redacted>` line under `alerter`, and the count `1`: the listed token equals the deployed file, compared through `grep -f` so the token is never an argument.
- `400 root` for the token file.
- `behind-proxy: true`, `proxy-trusted-hosts: ::1`, `visitor-prefix-bits-ipv6: 128`, and `log-level: debug` if Task 3's 3.1 found 401/403 logged only at debug (at `9fe512a` they are: `server/log.go:37`, `server/server.go:631-632`; at v2.28.0 `server/server.go:539-543`); no `auth-access` and no `auth-default-access` line.

- [ ] **Step 4: 7.1 — the token is accepted with no access entries, and an unknown token is refused**

Run:

```bash
{
  echo '$ ssh cinnabar.zt ntfy-send --help | grep NTFY_TOKEN_FILE'
  ssh cinnabar.zt 'ntfy-send --help 2>&1 | grep -n NTFY_TOKEN_FILE'
  T=$(date -u +%FT%TZ)
  echo '$ ssh cinnabar.zt sudo NTFY_TOKEN_FILE=<token path> ntfy-send "c1 token probe" fleet-acceptance'
  ssh cinnabar.zt 'sudo NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token "$(command -v ntfy-send)" "c1 token probe" fleet-acceptance; echo "exit=$?"'
  echo '# negative control: a well-formed token ntfy does not know, from stibnite'
  bad=$(mktemp); printf 'tk_%s' "$(LC_ALL=C tr -dc 'A-Za-z0-9' </dev/urandom | head -c 29)" > "$bad"
  echo "T_BADTOKEN=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  printf 'Authorization: Bearer %s\n' "$(< "$bad")" | curl -sk -o /dev/null -w 'unknown token: HTTP %{http_code}\n' -H @- -d 'c1 unknown token probe' https://ntfy.zt/fleet-acceptance
  rm -f "$bad"
  sleep 2
  echo '$ ssh cinnabar.zt sudo journalctl -u ntfy-sh --since T (fleet-acceptance lines)'
  ssh cinnabar.zt "sudo journalctl -u ntfy-sh --since '$T' --no-pager -o short-iso | grep 'http_path=/fleet-acceptance' | grep -oE '(HTTP request finished|Connection closed with HTTP [0-9]+)|user_name=[^,)]*|visitor_ip=[^,)]*' | paste -sd ' ' -"
} 2>&1 | tee "$EV/7.1-token-probe-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected:
- A help line naming `NTFY_TOKEN_FILE` (cinnabar's `ntfy-send` is the C1 build).
- `exit=0` for the token probe: no 401 although there are no access entries (design D5 step 1; A39).
- `unknown token: HTTP 401`, the negative control showing the token path is authenticated rather than ignored; it is also 7.4's deliberate 401, matched by `T_BADTOKEN`.
- In the journal: a `HTTP request finished … user_name=alerter` entry for the probe and a `Connection closed with HTTP 401` entry for the unknown token, both with a mesh `visitor_ip`, neither `::1`.
  If `log-level` stayed at its default because 3.1 found these logged at `info`, the same lines appear at `INFO`; if no lines appear at all, stop: 7.4 then has no observable.
`sudo VAR=value cmd` is allowed because the operator's sudoers rule is `ALL`, which implies `SETENV`; the absolute path is passed because `sudo`'s `secure_path` omits the per-user profile.
The token value appears only on `printf`'s argument list, which is a bash builtin and spawns no process.

- [ ] **Step 5: 7.1 — anonymous publishing is unchanged**

Run from stibnite:

```bash
{
  echo '$ ntfy-send "c1 anon" stibnite'; ntfy-send "c1 anon" stibnite; echo "exit=$?"
  echo '$ ntfy-send "c1 anon" fleet-acceptance'; ntfy-send "c1 anon" fleet-acceptance; echo "exit=$?"
} 2>&1 | tee "$EV/7.1-anon-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `exit=0` twice.

- [ ] **Step 6: 7.1 — each mesh client is its own visitor, by the journal**

Run:

```bash
{
  T=$(date -u +%FT%TZ)
  ntfy-send "c1 visitor stibnite" stibnite; echo "stibnite exit=$?"
  ssh magnetite.zt 'ntfy-send "c1 visitor magnetite" magnetite; echo "magnetite exit=$?"'
  sleep 2
  ssh cinnabar.zt "sudo journalctl -u ntfy-sh --since '$T' --no-pager | grep 'HTTP request finished' | grep -E 'http_path=/(stibnite|magnetite)[,)]' | grep -oE 'http_path=[^,)]*|visitor_ip=[^,)]*' | paste -d ' ' - -"
} 2>&1 | tee "$EV/7.1-visitor-journal-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: exit 0 twice; two lines, `http_path=/stibnite visitor_ip=<stibnite's ZeroTier address>` and `http_path=/magnetite visitor_ip=<magnetite's ZeroTier address>`, the two addresses different and neither `::1`.
Record each host's ZeroTier address beside it (`ssh magnetite.zt ip -br addr show | grep zt`; `ifconfig | grep fddb` on stibnite) to show the address is the client's, taken from caddy's `X-Forwarded-For` (A41).

- [ ] **Step 7: 7.1 — each mesh client is its own visitor, by its counter (the negative control's pair)**

Run the Step 2 experiment again:

```bash
acct() { jq -r '.stats.messages'; }
{
  s0=$(curl -sk https://ntfy.zt/v1/account | acct); m0=$(ssh magnetite.zt 'curl -sk https://ntfy.zt/v1/account' | acct)
  echo "before: stibnite=$s0 magnetite=$m0"
  for i in 1 2 3; do ntfy-send "s3 post-c1 visitor probe $i" stibnite; done
  s1=$(curl -sk https://ntfy.zt/v1/account | acct); m1=$(ssh magnetite.zt 'curl -sk https://ntfy.zt/v1/account' | acct)
  echo "after 3 stibnite posts: stibnite=$s1 magnetite=$m1"
  [ $((s1 - s0)) -ge 3 ] && [ $((m1 - m0)) -eq 0 ] && echo "PASS: separate visitors" || echo "FAIL: stibnite delta $((s1 - s0)), magnetite delta $((m1 - m0))"
} 2>&1 | tee "$EV/7.1-post-c1-visitors-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `PASS: separate visitors`, where Step 2 showed the shared visitor before C1.
A magnetite delta above 0 can come from a magnetite post in the same seconds; rerun once, and record a second `FAIL` as a failure of FAI `ntfy counts each mesh client as its own visitor`.

- [ ] **Step 8: 7.1 gate**

Run:

```bash
rg -l 'PASS: separate visitors' "$EV"/7.1-post-c1-visitors-*.log && rg -c 'unknown token: HTTP 401' "$EV"/7.1-token-probe-*.log && echo "7.1 passed: C2 may start"
```

Expected: one file name, `1`, then `7.1 passed: C2 may start`.
Task 4's 4.11 runs only after this line.

- [ ] **Step 9: 7.2 — the evaluator runs and heartbeats (after 4.11)**

Run at least 10 minutes after `C2_END`:

```bash
{
  ssh magnetite.zt '
    echo "\$ systemctl list-timers fleet-alert.timer"; systemctl list-timers fleet-alert.timer --no-pager
    echo "\$ systemctl show fleet-alert -p Result -p LoadCredential -p OOMScoreAdjust -p MemoryMax -p TimeoutStartUSec"; systemctl show fleet-alert -p Result -p LoadCredential -p OOMScoreAdjust -p MemoryMax -p TimeoutStartUSec
    echo "\$ sudo jq -c keys /var/lib/fleet-alert/state.json"; sudo jq -c keys /var/lib/fleet-alert/state.json
    echo "\$ journalctl -u fleet-alert -g \"memory peak\" -n 5"; journalctl -u fleet-alert -g "memory peak" -n 5 --no-pager
    echo "\$ journalctl -u fleet-alert --since -10min -p warning"; journalctl -u fleet-alert --since -10min -p warning --no-pager
  '
  echo '$ ssh cinnabar.zt curl heartbeat poll | jq -s length'
  ssh cinnabar.zt "curl -s 'http://[::1]:2586/fleet-heartbeat/json?poll=1&since=10m' | jq -s length"
  echo '$ heartbeat requests authenticated as alerter in the last 5 min'
  ssh cinnabar.zt "sudo journalctl -u ntfy-sh --since -5min --no-pager | grep 'HTTP request finished' | grep 'http_path=/fleet-heartbeat' | grep -c 'user_name=alerter'"
} 2>&1 | tee "$EV/7.2-evaluator-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected:
- `fleet-alert.timer` with `NEXT` under a minute away and `LAST` within the last minute.
- `Result=success`; `LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password` and `LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token` (the paths `handrun.sh` uses); `OOMScoreAdjust=0`; `MemoryMax=67108864`; `TimeoutStartUSec=50s`.
- `state.json` parses and prints its top-level keys, including `firings`.
- Five lines `fleet-alert.service: Consumed … CPU time, … memory peak.`; record the largest peak against 64M (R9.5; the D18 MemoryPeak reading).
- No warning-or-worse lines.
- A heartbeat count of at least `9`, and at least 4 heartbeat requests with `user_name=alerter`.
If the `LoadCredential` paths differ, edit `handrun.sh` to match before Step 13.

- [ ] **Step 10: 7.2 — the notifier posts with the token and logs the `FAILED`**

Run:

```bash
{
  T=$(date +%s)
  ssh magnetite.zt '
    echo "\$ sudo systemctl start observability-notify@acceptance-probe.service"; sudo systemctl start observability-notify@acceptance-probe.service; echo "exit=$?"
    echo "\$ systemctl show observability-notify@acceptance-probe -p LoadCredential -p Environment"; systemctl show observability-notify@acceptance-probe -p LoadCredential -p Environment
    echo "\$ tail -1 failed.log"; tail -n1 /var/lib/observability-notify/failed.log
    echo "\$ stat failed.log"; stat -c "%a %U" /var/lib/observability-notify/failed.log
    echo "\$ sudo cat stamp"; sudo cat /var/lib/observability-notify/acceptance-probe
  '
  sleep 3
  echo '$ polls.sh fleet-alerts' "$T"; "$EV/polls.sh" fleet-alerts "$T"
  echo '$ ssh magnetite.zt sudo rm /var/lib/observability-notify/acceptance-probe'
  ssh magnetite.zt 'sudo rm /var/lib/observability-notify/acceptance-probe; test ! -e /var/lib/observability-notify/acceptance-probe && echo "stamp removed"'
} 2>&1 | tee "$EV/7.2-notifier-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `exit=0`; `LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token` and `NTFY_TOKEN_FILE=%d/alerter-token` in `Environment=` (systemd shows the unexpanded specifier); `failed.log`'s last line `<epoch> acceptance-probe magnetite` with an epoch at or after `T`; mode `644 root`; stamp `posted`; the poll prints exactly one message `FAILED acceptance-probe on magnetite`; `stamp removed`.
This line is one of the `failed.log` lines Task 8's 9.1 counts.

- [ ] **Step 11: 7.2 — the ARC inference**

Run:

```bash
{
  ssh magnetite.zt '
    m=$(cat /proc/meminfo); a=$(cat /proc/spl/kstat/zfs/arcstats)
    echo "$m" | grep -E "^(MemTotal|MemFree|MemAvailable|Cached|SReclaimable):"
    echo "$a" | awk "\$1 == \"size\" || \$1 == \"c_min\""
    free=$(echo "$m" | awk "/^MemFree:/ {print \$2*1024}"); avail=$(echo "$m" | awk "/^MemAvailable:/ {print \$2*1024}")
    cached=$(echo "$m" | awk "/^Cached:/ {print \$2*1024}"); srec=$(echo "$m" | awk "/^SReclaimable:/ {print \$2*1024}")
    arc=$(echo "$a" | awk "\$1 == \"size\" {print \$3}")
    sum=$((free + cached + srec)); gap=$((sum - avail))
    echo "MemFree+Cached+SReclaimable=$sum MemAvailable=$avail gap=$gap arc_size=$arc"
    [ "$avail" -lt "$sum" ] && [ "$arc" -gt "$gap" ] && echo "PASS: MemAvailable excludes the ARC" || echo "FAIL: inference not supported by this sample"
  '
} 2>&1 | tee "$EV/7.2-arc-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `PASS: MemAvailable excludes the ARC` (ADR-009:128; FA:159); both files are read at one instant from the shell variables.
A `FAIL` is recorded for the orchestrator, because `HostMemoryPressure`'s added ARC term then double-counts.

- [ ] **Step 12: 7.2 — no `RuleSignalMissing` in the 30 minutes after the first run**

Run once 35 minutes after `C2_END` (read it from `window.env`):

```bash
source "$EV/window.env"
since=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$C2_END" +%s)
{
  echo "C2_END=$C2_END"
  echo '$ polls.sh fleet-alerts' "$since"; "$EV/polls.sh" fleet-alerts "$since"
  echo '$ count of RuleSignalMissing posts'; "$EV/polls.sh" fleet-alerts "$since" | grep -c 'RuleSignalMissing' || true
  echo '$ RuleSignalMissing instances in state.json'; ssh magnetite.zt "sudo grep -c RuleSignalMissing /var/lib/fleet-alert/state.json" || true
} 2>&1 | tee "$EV/7.2-rulesignalmissing-silence-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the poll lists whatever real alerts fired (record them); both counts are `0`.

- [ ] **Step 13: 7.2 — `RuleSignalMissing`'s negative control**

Run:

```bash
T=$(date +%s)
{
  "$EV/handrun.sh" reset
  "$EV/handrun.sh" '(.rules[] | select(.alert == "HostOOMKill") | .presence[0].selector) = "node_vmstat_oom_kil" | (.rules[] | select(.alert == "RuleSignalMissing") | .for) = 0' 2 60
  sleep 3
  echo '$ polls.sh fleet-acceptance' "$T"; "$EV/polls.sh" fleet-acceptance "$T"
  "$EV/handrun.sh" reset
} 2>&1 | tee "$EV/7.2-rulesignalmissing-negative-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: two runs with `exit=0`; the poll shows the hand runs' heartbeats and one `[FIRING] RuleSignalMissing magnetite` message (warning, priority 3) naming `HostOOMKill`'s misspelt selector; nothing new on `fleet-alerts`.
This shows the 30-minute silence of Step 12 is a rule that can fire, not an empty one.

- [ ] **Step 14: 7.2 — the evaluator's posts were never refused**

Run:

```bash
source "$EV/window.env"
{
  ssh magnetite.zt "journalctl -u fleet-alert --since '$C2_START' --no-pager | grep -E 'status=|Failed' || echo 'no failed run'"
  ssh cinnabar.zt "sudo journalctl -u ntfy-sh --since '$C2_START' --no-pager | grep -E 'Connection closed with HTTP 40[13] ' | grep -v 'http_path=/fleet-acceptance' || echo 'no 401/403 outside the acceptance topic'"
} 2>&1 | tee "$EV/7.2-no-refusal-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `no failed run` and `no 401/403 outside the acceptance topic`.

- [ ] **Step 15: 7.2 gate**

Run:

```bash
rg -l 'FAILED acceptance-probe on magnetite' "$EV"/7.2-notifier-*.log && rg -l 'RuleSignalMissing' "$EV"/7.2-rulesignalmissing-negative-*.log && echo "7.2 passed: C3 may start"
```

Expected: two file names, then `7.2 passed: C3 may start`.
Task 5's 5.5 runs only after this line.

- [ ] **Step 16: 7.3 — the dead-man runs with its probe refused (after 5.5)**

Run at least 15 minutes after `C3_END`:

```bash
source "$EV/window.env"
{
  ssh cinnabar.zt "
    systemctl list-timers fleet-deadman.timer --no-pager
    systemctl show fleet-deadman -p Result -p LoadCredential
    journalctl -u fleet-deadman --since '$C3_END' --no-pager | grep -E 'R9.4|heartbeat\\(s\\)|status='
    echo \"probe refusals: \$(journalctl -u fleet-deadman --since '$C3_END' --no-pager | grep -c 'R9.4 probe refused with HTTP 403')\"
  "
} 2>&1 | tee "$EV/7.3-deadman-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the timer scheduled on a 5-minute boundary; `Result=success`; `LoadCredential=alerter-token:/run/secrets/vars/shared/ntfy-alerter/token`; every run printing `fleet-deadman: R9.4 probe refused with HTTP 403` and `fleet-deadman: <n> heartbeat(s) on fleet-heartbeat in the last 10m` with `n` at least 9; `probe refusals:` at least 3; no `status=` failure line.

- [ ] **Step 17: 7.3 — the three-way publish matrix (E9.4)**

Run from stibnite:

```bash
{
  echo "T_ANON403=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  printf 'anonymous fleet-alerts: HTTP %s\n' "$(curl -sk -o /dev/null -w '%{http_code}' -d x https://ntfy.zt/fleet-alerts)"
  printf 'anonymous stibnite:     HTTP %s\n' "$(curl -sk -o /dev/null -w '%{http_code}' -d x https://ntfy.zt/stibnite)"
  echo '$ alerter on cinnabar to fleet-acceptance'
  ssh cinnabar.zt 'sudo NTFY_TOKEN_FILE=/run/secrets/vars/shared/ntfy-alerter/token "$(command -v ntfy-send)" "c3 alerter probe" fleet-acceptance; echo "alerter exit=$?"'
  echo '$ systemctl status fleet-alert on magnetite'
  ssh magnetite.zt 'systemctl show fleet-alert -p Result; journalctl -u fleet-alert --since -10min --no-pager | grep -c "Deactivated successfully"'
  echo '$ anonymous read of fleet-alerts still allowed'
  printf 'anonymous read: HTTP %s\n' "$(curl -sk -o /dev/null -w '%{http_code}' 'https://ntfy.zt/fleet-alerts/json?poll=1&since=1m')"
} 2>&1 | tee "$EV/7.3-matrix-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `anonymous fleet-alerts: HTTP 403`; `anonymous stibnite: HTTP 200`; `alerter exit=0`; `Result=success` and a count of at least 9 successful evaluator runs in 10 minutes; `anonymous read: HTTP 200`.

- [ ] **Step 18: 7.4's curl-exit-22 control (closes the window)**

Run:

```bash
{
  echo "T_CURL22=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemd-run --unit=s3-curl22-control --wait --collect "$(command -v ntfy-send)" "c3 anonymous refused probe" fleet-acceptance; echo "exit=$?"'
  ssh magnetite.zt 'journalctl -u s3-curl22-control --since -2min --no-pager | grep "status=22"'
} 2>&1 | tee "$EV/7.4-curl22-control-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `exit=22` and a journal line `… Main process exited, code=exited, status=22/n/a`: an anonymous post to a `fleet-*` topic fails curl with exit 22 and leaves the line Step 23 searches for, so Step 23's zero count is not vacuous.

- [ ] **Step 19: 7.3 — record the R9.4 baseline before the negative control**

Run:

```bash
{
  ssh cinnabar.zt 'sudo ls -la /var/lib/observability-notify; systemctl show fleet-deadman -p Result'
  "$EV/polls.sh" fleet-alerts 10m
} 2>&1 | tee "$EV/7.3-r94-baseline-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: no stamp `fleet-deadman.service`; `Result=success`; no `fleet-deadman` message in the last 10 minutes.

- [ ] **Step 20: 7.3 — R9.4's negative control: deploy cinnabar without `*:fleet-*:ro`**

Run:

```bash
T=$(date +%s)
"$EV/s3-deploy.sh" cinnabar R94NEG modules/machines/nixos/cinnabar/ntfy.nix '          "*:fleet-*:ro"' 2>&1 | tee "$EV/7.3-r94-negative-deploy-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the numstat line `0	1	modules/machines/nixos/cinnabar/ntfy.nix`, then `clan exit=0`.
Within 6 minutes of `R94NEG_END`, run:

```bash
{
  ssh cinnabar.zt "journalctl -u fleet-deadman --since -8min --no-pager | grep -E 'R9.4|status='; systemctl show fleet-deadman -p Result; sudo cat /var/lib/observability-notify/fleet-deadman.service"
  "$EV/polls.sh" fleet-alerts "$T"
} 2>&1 | tee "$EV/7.3-r94-negative-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `fleet-deadman: R9.4: anonymous publish to fleet-heartbeat answered HTTP 200, expected 403`; `Result=exit-code`; stamp `posted`; exactly one `FAILED fleet-deadman.service on cinnabar` on `fleet-alerts` (A38: with no `*` entry the default `read-write` applies to anonymous publishers).
While this revision runs, anonymous publishing to `fleet-*` is open again; Step 21 follows at once.

- [ ] **Step 21: 7.3 — redeploy C3 and see `RESOLVED`**

Run:

```bash
T=$(date +%s)
"$EV/s3-deploy.sh" cinnabar C3RE 2>&1 | tee "$EV/7.3-r94-redeploy-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `clan exit=0`.
Within 6 minutes of `C3RE_END`, run:

```bash
{
  ssh cinnabar.zt "journalctl -u fleet-deadman --since -8min --no-pager | grep -E 'R9.4|status='; systemctl show fleet-deadman -p Result; sudo test ! -e /var/lib/observability-notify/fleet-deadman.service && echo 'stamp cleared'"
  "$EV/polls.sh" fleet-alerts "$T"
  echo "W_END=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
} 2>&1 | tee "$EV/7.3-r94-resolved-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `fleet-deadman: R9.4 probe refused with HTTP 403`; `Result=success`; `stamp cleared`; exactly one `RESOLVED fleet-deadman.service on cinnabar`.
`W_END` closes the 7.4 window at the end of 7.3.

- [ ] **Step 22: 7.4 — extract the window's ntfy journal**

Run:

```bash
source "$EV/window.env"
J="$EV/7.4-ntfy-journal-$(date -u +%Y%m%dT%H%M%SZ).log"
ssh cinnabar.zt "sudo journalctl -u ntfy-sh --since '$C1_START' --until '$W_END' --no-pager -o short-iso" 2>&1 | tee "$J" | wc -l
```

Expected: a line count well above zero; the file starts no later than `C1_END`.

- [ ] **Step 23: 7.4 — classify every 401 and 403 and every curl exit 22**

Run:

```bash
source "$EV/window.env"
{
  echo "window: $C1_START .. $W_END"
  grep -E 'Connection closed with HTTP (401|403) ' "$J" > /tmp/s3-refusals.txt || true
  echo "all 401/403: $(wc -l < /tmp/s3-refusals.txt)"
  echo "deliberate R9.4 probes (POST /fleet-heartbeat from ::1, HTTP 403): $(grep 'HTTP 403' /tmp/s3-refusals.txt | grep 'http_method=POST' | grep 'http_path=/fleet-heartbeat' | grep -c 'visitor_ip=::1')"
  echo "deliberate 7.1 unknown token at $T_BADTOKEN (HTTP 401, /fleet-acceptance):"; grep 'HTTP 401' /tmp/s3-refusals.txt | grep 'http_path=/fleet-acceptance' || true
  echo "deliberate 7.3 anonymous probe at $T_ANON403 (HTTP 403, /fleet-alerts):"; grep 'HTTP 403' /tmp/s3-refusals.txt | grep 'http_path=/fleet-alerts' || true
  echo "deliberate 7.4 control at $T_CURL22 (HTTP 403, /fleet-acceptance):"; grep 'HTTP 403' /tmp/s3-refusals.txt | grep 'http_path=/fleet-acceptance' || true
  echo "unexplained:"
  grep -v -e 'http_path=/fleet-heartbeat' -e 'http_path=/fleet-acceptance' /tmp/s3-refusals.txt | grep -v 'http_path=/fleet-alerts' || echo none
  grep 'http_path=/fleet-alerts' /tmp/s3-refusals.txt | wc -l | xargs printf '/fleet-alerts refusals (must be 1): %s\n'
  grep 'http_path=/fleet-heartbeat' /tmp/s3-refusals.txt | grep -v 'visitor_ip=::1' || echo 'no /fleet-heartbeat refusal from a mesh client'
  echo '$ magnetite journal, status=22 since C1_START'
  ssh magnetite.zt "sudo journalctl --since '$C1_START' --until '$W_END' --no-pager -o short-iso | grep 'status=22/'"
} 2>&1 | tee "$EV/7.4-refusals-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected:
- The deliberate R9.4 count equals the number of dead-man runs between `C3_END` and `W_END` minus the R9.4 negative-control runs (Step 16's journal gives the run count).
- Exactly one 401 line on `/fleet-acceptance` at `T_BADTOKEN`, one 403 on `/fleet-alerts` at `T_ANON403`, one 403 on `/fleet-acceptance` at `T_CURL22`, each timestamp within 5 s of its recorded time.
- `unexplained:` followed by `none`; `/fleet-alerts refusals (must be 1): 1`; `no /fleet-heartbeat refusal from a mesh client`.
- On magnetite, exactly one `status=22/` line, from `s3-curl22-control.service` at `T_CURL22`, and none from `fleet-alert.service` or any notified unit's hook.
Record the counts in the log's last lines; any unexplained line is a refused post inside the cutover and fails design D5.

- [ ] **Step 24: 7.4 — return cinnabar's `log-level` to its default (the revert pull request)**

Skip this step and Steps 25–26 if Step 3 showed no `log-level: debug`; record `log-level never raised` in `$EV/7.4-revert-skipped.log`.
Otherwise run from `/Users/crs58/projects/vanixiets`:

```bash
jj new --no-edit -r main@origin -m 'fix(cinnabar): return ntfy log-level to its default after the S3 cutover'
rg -n -B3 'log-level' modules/machines/nixos/cinnabar/ntfy.nix
```

Expected: `Created new commit <change-id> ...`, noted as `REVERT`; the `rg` output shows the `log-level = "debug";` line inside `settings` and the comment lines Task 3 placed directly above it.
With the edit tool, delete the `log-level = "debug";` line and those comment lines, nothing else.
Then run:

```bash
jj st --no-pager >/dev/null
nix eval --json .#nixosConfigurations.cinnabar.config.services.ntfy-sh.settings --apply 's: s.log-level or null'
nix fmt -- modules/machines/nixos/cinnabar/ntfy.nix 2>&1 | tee "$EV/7.4-revert-fmt-$(date -u +%Y%m%dT%H%M%SZ).log"
nix fmt -- --fail-on-change modules/machines/nixos/cinnabar/ntfy.nix; echo "fmt-exit=$?"
jj squash --from @ --into REVERT --keep-emptied --use-destination-message -- modules/machines/nixos/cinnabar/ntfy.nix
jj diff --git -r REVERT
```

Expected: `null` (evaluation; before the edit it printed `"debug"`); `fmt-exit=0`; a diff that removes only the `log-level` line and its comment.
The orchestrator adds `REVERT` to the join, pushes it and opens the revert pull request; nixbot's green run gates it; do not push.

- [ ] **Step 25: 7.4 — deploy the revert**

After the revert pull request has merged, run:

```bash
"$EV/s3-deploy.sh" cinnabar REVERT 2>&1 | tee "$EV/7.4-revert-deploy-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `clan exit=0`.

- [ ] **Step 26: 7.4 — confirm the delivered setting**

Run 6 minutes after `REVERT_END`:

```bash
source "$EV/window.env"
{
  ssh cinnabar.zt "yml=\$(systemctl show ntfy-sh -p ExecStart --value | sed -n 's/.*-c \\([^ ;]*\\).*/\\1/p'); grep -E 'log-level|behind-proxy|auth-access' -A2 \"\$yml\" || true
    echo \"DEBUG lines since restart: \$(sudo journalctl -u ntfy-sh --since '$REVERT_END' --no-pager | grep -c ' DEBUG ')\"
    journalctl -u fleet-deadman --since '$REVERT_END' --no-pager | grep 'R9.4'"
} 2>&1 | tee "$EV/7.4-revert-delivered-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: no `log-level` line in the delivered `server.yml`, with `behind-proxy: true` and both `auth-access` entries still present; `DEBUG lines since restart: 0`; the dead-man's probe still `refused with HTTP 403` (delivered path, runtime).

- [ ] **Step 27: 7.5 — R9.3: stop the evaluator**

Run:

```bash
{
  echo "T_STOP=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemctl stop fleet-alert.timer; systemctl is-active fleet-alert.timer || true'
} 2>&1 | tee "$EV/7.5-stop-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `inactive`.
Wait 15 minutes, then run:

```bash
source "$EV/window.env"
since=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_STOP" +%s)
{
  "$EV/polls.sh" fleet-alerts "$since"
  ssh cinnabar.zt "journalctl -u fleet-deadman --since '$T_STOP' --no-pager | grep 'heartbeat(s)'"
} 2>&1 | tee "$EV/7.5-silent-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: exactly one `[FIRING] AlertEvaluatorSilent …` message at priority `4` (`high`, for `critical`), posted no later than 15 minutes after `T_STOP`; the dead-man's poll counts falling to `0 heartbeat(s)` at the run that raised it.

- [ ] **Step 28: 7.5 — start the evaluator and see `RESOLVED`; start the 24-hour capture on pyrite**

Run:

```bash
{
  echo "T_START=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemctl start fleet-alert.timer; systemctl is-active fleet-alert.timer'
} 2>&1 | tee "$EV/7.5-start-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `active`.
Wait 11 minutes, then run:

```bash
source "$EV/window.env"
since=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_STOP" +%s)
{
  "$EV/polls.sh" fleet-alerts "$since"
  ssh cinnabar.zt "journalctl -u fleet-deadman --since '$T_START' --no-pager | grep 'heartbeat(s)'"
} 2>&1 | tee "$EV/7.5-resolved-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the `FIRING` from Step 27 and exactly one `[RESOLVED] AlertEvaluatorSilent …`, posted no later than 10 minutes after `T_START`: the dead-man resolves under the shared transition's 5-minutes-absent rule, which on its 5-minute timer is the first run that sees a heartbeat or, if that run falls short of 300 s, the second (S3PlanT5).
`tasks.md` 7.5's "`RESOLVED` arrives within the next 5 min dead-man run" should read "`RESOLVED` arrives within 10 min, at the first or second dead-man run after the timer restarts"; the orchestrator folds that wording back (decision Q5).

Before Step 29, start a subscriber-side capture of `fleet-alerts` on pyrite, which is always on and on ZeroTier, so Task 8's 9.1 can count 24 hours of messages that ntfy's 12-hour cache cannot show.
pyrite does not trust caddy's internal CA (`curl https://ntfy.zt/v1/health` there fails with `unable to get local issuer certificate`, read 2026-10-18), so the capture uses `-k`, as `ntfy-send` does.
Run:

```bash
ssh pyrite.zt 'sudo tee /var/lib/fleet-alerts-capture.sh >/dev/null' <<'EOF'
#!/usr/bin/env bash
# Append every fleet-alerts event to a JSON-lines file, resuming after the last captured message id.
set -u
PATH=/run/current-system/sw/bin
f=/var/lib/fleet-alerts-capture.jsonl
since=$(date +%s)
while :; do
  last=$(jq -r 'select(.event == "message") | .id' "$f" 2>/dev/null | tail -n1)
  curl -sNk "https://ntfy.zt/fleet-alerts/json?since=${last:-$since}" >> "$f"
  sleep 2
done
EOF
{
  ssh pyrite.zt 'sudo systemd-run --unit=fleet-alerts-capture /run/current-system/sw/bin/bash /var/lib/fleet-alerts-capture.sh; sleep 5; systemctl is-active fleet-alerts-capture; sudo tail -n1 /var/lib/fleet-alerts-capture.jsonl'
  echo "T_CAP_START=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
} 2>&1 | tee "$EV/9.1-capture-start-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `active` and an `{"id":…,"event":"open",…,"topic":"fleet-alerts"}` line.
The loop resumes after the last captured message id whenever the stream drops, so a reconnect neither loses nor repeats a message; anonymous reads of `fleet-*` stay allowed by `*:fleet-*:ro`.
Task 8 Step 2 stops it.

- [ ] **Step 29: 7.6 — `HostOOMKill` by a cgroup OOM kill**

Run:

```bash
{
  ssh magnetite.zt 'systemctl list-timers greptimedb-envelope.timer --no-pager'
  ssh magnetite.zt 'echo "oom_kill before: $(awk "/^oom_kill / {print \$2}" /proc/vmstat)"'
  echo "T_OOM=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemd-run --unit=s3-oom-probe --wait --collect -p MemoryMax=32M -p MemorySwapMax=0 /run/current-system/sw/bin/tail /dev/zero; echo "exit=$?"'
  ssh magnetite.zt 'echo "oom_kill after: $(awk "/^oom_kill / {print \$2}" /proc/vmstat)"; journalctl -u s3-oom-probe --since -2min --no-pager | grep -iE "oom|memory"'
} 2>&1 | tee "$EV/7.6-oom-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: the envelope's `NEXT` at least 25 minutes away (otherwise wait until it has run, so Step 30's store stop does not fail it); `oom_kill after` one more than `before`, which confirms the `[INFERENCE]` of `tasks.md` 7.6 that a memcg kill increments `/proc/vmstat` `oom_kill`; a non-zero `exit=`; the journal shows `s3-oom-probe.service: A process of this unit has been killed by the OOM killer` and `Failed with result 'oom-kill'`.
`tail /dev/zero` reads one endless line and grows without bound, and `MemorySwapMax=0` keeps zram out of it.
If the counter did not move, stop: `HostOOMKill` cannot observe memcg kills, and the orchestrator decides how to force it.
Within 3 minutes, `"$EV/polls.sh" fleet-alerts 5m` shows one `[FIRING] HostOOMKill magnetite` at priority 4, its message ending in the attribution (three executables, ARC size, swap used); append that poll to the log.

- [ ] **Step 30: 7.6 — `StoreQueryFailing` while `HostOOMKill` fires, and no false `RESOLVED`**

Start this step 3 minutes after `T_OOM`, with Step 29's `FIRING` already posted.
Run:

```bash
{
  echo "T_STORE_STOP=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemctl stop greptimedb; systemctl is-active greptimedb || true'
  sleep 420
  echo '# polls at the end of the 7-minute stop'; "$EV/polls.sh" fleet-alerts 8m
  echo "T_STORE_START=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemctl start greptimedb; systemctl is-active greptimedb greptimedb-schema'
  ssh magnetite.zt "journalctl -u fleet-alert --since -8min --no-pager | grep -E 'status=|Failed' || echo 'every run during the stop exited 0'"
} 2>&1 | tee "$EV/7.6-store-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected:
- `inactive` after the stop; `active` twice after the start.
- During the stop, exactly one `[FIRING] StoreQueryFailing …` (priority 4), posted 3 to 4 minutes after `T_STORE_STOP`, and no `RESOLVED` of any kind; in particular no `[RESOLVED] HostOOMKill magnetite`, which an evaluator without the store freeze would have posted 5 minutes into the stop, about 8 minutes after the kill.
- `every run during the stop exited 0`, because a store failure still heartbeats and exits 0 (design, Failure path).
The stop lasts 7 minutes, beyond `tasks.md`'s 4-minute minimum, so the freeze is shown able to matter (orchestrator decision).

- [ ] **Step 31: 7.6 — both resolve once the store answers**

Wait 12 minutes after `T_STORE_START`, then run:

```bash
source "$EV/window.env"
since=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_OOM" +%s)
{
  "$EV/polls.sh" fleet-alerts "$since"
  echo "HostOOMKill FIRING: $("$EV/polls.sh" fleet-alerts "$since" | grep -c 'FIRING] HostOOMKill')  RESOLVED: $("$EV/polls.sh" fleet-alerts "$since" | grep -c 'RESOLVED] HostOOMKill')"
  echo "StoreQueryFailing FIRING: $("$EV/polls.sh" fleet-alerts "$since" | grep -c 'FIRING] StoreQueryFailing')  RESOLVED: $("$EV/polls.sh" fleet-alerts "$since" | grep -c 'RESOLVED] StoreQueryFailing')"
} 2>&1 | tee "$EV/7.6-oom-store-resolved-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `HostOOMKill FIRING: 1  RESOLVED: 1` and `StoreQueryFailing FIRING: 1  RESOLVED: 1`; each `RESOLVED` is later than `T_STORE_START`, `StoreQueryFailing`'s about 5 minutes after it and `HostOOMKill`'s once the kill has left the 10-minute `increase` window plus 5 minutes.

- [ ] **Step 32: 7.6 — `LocalExporterDown` by stopping the node exporter**

Run:

```bash
{
  echo "T_EXP_STOP=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemctl stop prometheus-node-exporter; systemctl is-active prometheus-node-exporter || true'
  sleep 120
  echo '$ gq up{job="node"} 2 min into the stop'
  ssh magnetite.zt 'printf "user = \"regulator:%s\"\n" "$(sudo cat /run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password)" | curl -sS -G -K - -H "x-greptime-db-name: fleet" --data-urlencode "query=up{job=\"node\"}" http://127.0.0.1:4000/v1/prometheus/api/v1/query' | jq -c '[.data.result[] | .value[1]]'
  sleep 600
  echo "T_EXP_START=$(date -u +%FT%TZ)" | tee -a "$EV/window.env"
  ssh magnetite.zt 'sudo systemctl start prometheus-node-exporter; systemctl is-active prometheus-node-exporter'
} 2>&1 | tee "$EV/7.6-exporter-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `inactive`, then `["0"]` (the collector reports the dead scrape as `up` 0), then `active` 12 minutes after the stop.
The regulator password reaches curl through `--config -` on stdin, never as an argument, as `modules/lib/greptimedb-envelope.nix:64-70` does.
Wait 7 minutes, then run:

```bash
source "$EV/window.env"
since=$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_EXP_STOP" +%s)
"$EV/polls.sh" fleet-alerts "$since" 2>&1 | tee "$EV/7.6-exporter-alerts-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: exactly one `[FIRING] LocalExporterDown magnetite` (priority 3), 10 to 11 minutes after `T_EXP_STOP`, and exactly one `[RESOLVED] LocalExporterDown magnetite` about 5 minutes after `T_EXP_START`; no `RuleSignalMissing`, whose 30 minutes the 12-minute stop does not reach.
The operator also records this pair arriving on the phone (Task 8's 9.1):

```bash
printf '[operator] %s: LocalExporterDown FIRING and RESOLVED seen on the phone at %s and %s\n' "$(date -u +%FT%TZ)" "<FIRING time on the phone>" "<RESOLVED time on the phone>" >> "$EV/7.6-exporter-alerts-"*.log
```

The two `<…>` times are read off the phone at the time and typed in by the operator; this records Step 35's subscription in use, so Step 35 runs its subscription part before this step.

- [ ] **Step 33: 7.6 — the rules that cannot be forced safely, by hand runs (firing)**

Compute the weekly window for now in New York and fire the five forced rules together on scratch state:

```bash
wd=$(TZ=America/New_York date +%u); st=$(TZ=America/New_York date +%H:%M); en=$(TZ=America/New_York date -v+12M +%H:%M)
echo "window now: weekday=$wd start=$st end=$en"
F='(.rules[] | select(.alert == "HostMemoryPressure") | .expr) |= sub("< 0.10"; "< 1.10")
 | (.rules[] | select(.alert == "ZfsPoolUnhealthy") | .expr) = "node_zfs_zpool_state{state=\"online\"} == 1"
 | (.rules[] | select(.alert == "SystemdUnitRestartLoop") | .expr) = "increase(systemd_service_restarts_total{systemd_unit_name=\"nixbot.service\"}[15m]) >= 0"
 | (.rules[] | select(.alert == "SystemdUnitFailed") | .expr) |= sub("systemd_unit_active_state=\"failed\""; "systemd_unit_active_state=\"active\", systemd_unit_name=\"nix-daemon.service\"")
 | (.rules[] | select(.alert == "WeeklyPipelineTest") | .window) |= (.weekday = '"$wd"' | .start = "'"$st"'" | .end = "'"$en"'")'
T=$(date +%s); echo "T_FORCED=$T" | tee -a "$EV/window.env"
{
  "$EV/handrun.sh" reset
  "$EV/handrun.sh" "$F" 8 60
  sleep 3
  "$EV/polls.sh" fleet-acceptance "$T" | grep -v '"title":null'
} 2>&1 | tee "$EV/7.6-forced-firing-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: `en` is later than `st` on the same day (do not start within 15 minutes of midnight New York time); eight runs with `exit=0`; exactly five `[FIRING]` messages on `fleet-acceptance`: `ZfsPoolUnhealthy magnetite` (priority 4, after its 60 s `for`), `SystemdUnitRestartLoop magnetite` (priority 3, first run), `HostMemoryPressure magnetite` (priority 3, with attribution, after 300 s), `SystemdUnitFailed magnetite` (priority 3, after 300 s), and `WeeklyPipelineTest` (priority 2, first run in the window).
Each forced expression keeps the rule's real metric, labels, `for` and severity and changes only the threshold or the label matcher, so the real series satisfy it: the available-memory ratio is about 0.73 (`logs/s3/series-labels.md:13`), `zroot`'s `online` series is 1, `nixbot.service`'s restart increase is at least 0, and `nix-daemon.service` is `active` and outside the notified units, whose exclusion the rendered `SystemdUnitFailed` expression keeps.
`date -v+12M` is BSD date on stibnite.

- [ ] **Step 34: 7.6 — the same rules resolve on their original expressions**

Run, on the same scratch state:

```bash
{
  "$EV/handrun.sh" '.' 8 60
  sleep 3
  source "$EV/window.env"
  "$EV/polls.sh" fleet-acceptance "$T_FORCED" | grep -v '"title":null'
  for a in HostMemoryPressure ZfsPoolUnhealthy SystemdUnitRestartLoop SystemdUnitFailed WeeklyPipelineTest; do
    printf '%s FIRING %s RESOLVED %s\n' "$a" "$("$EV/polls.sh" fleet-acceptance "$T_FORCED" | grep -c "FIRING] $a")" "$("$EV/polls.sh" fleet-acceptance "$T_FORCED" | grep -c "RESOLVED] $a")"
  done
  "$EV/handrun.sh" reset
} 2>&1 | tee "$EV/7.6-forced-resolved-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected: eight runs with `exit=0`; `FIRING 1 RESOLVED 1` for `HostMemoryPressure`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop` and `SystemdUnitFailed`, each `RESOLVED` about 5 minutes into these runs; `WeeklyPipelineTest FIRING 1 RESOLVED 0`, because an `info` alert posts no `RESOLVED`; nothing new on `fleet-alerts`.
Together with Steps 29–32 every shipped rule has one `FIRING` and one `RESOLVED` (or, for `WeeklyPipelineTest`, none) with timestamps.

- [ ] **Step 35: 7.7 — subscription and the first Monday message (human)**

Before Step 32, the operator subscribes phone and desktop to `fleet-alerts` following the runbook's "Subscribing to fleet-alerts" (Task 6) and records it:

```bash
printf '[operator] %s: subscribed %s to fleet-alerts at https://ntfy.zt; CA fingerprint check matched: %s\n' "$(date -u +%FT%TZ)" "<phone model and app version; desktop app or browser>" "<yes|no>" >> "$EV/7.7-subscription.log"
```

On the first Monday after C2, at 09:06 New York time, run:

```bash
{
  "$EV/polls.sh" fleet-alerts 10m | grep 'WeeklyPipelineTest'
  printf '[operator] %s: WeeklyPipelineTest arrived on the phone at %s New York time\n' "$(date -u +%FT%TZ)" "<time shown on the phone>"
} 2>&1 | tee -a "$EV/7.7-weekly.log"
```

Expected: one `[FIRING] WeeklyPipelineTest` message (priority 2) timed between 09:00 and 09:05 New York time, and the operator's line with the phone's time.
The `<…>` texts are the operator's own observations, typed at the time.

- [ ] **Step 36: No commit**

Apart from Step 24's revert pull request, this task changes no repository file.
Task 8 ticks 7.1 to 7.7 in `tasks.md` and records this task's evidence in `verify.md`.

---

### Task 8: Close-out

This task is `tasks.md` groups 8 and 9: the integration verification (9.1), `verify.md` (8.1, which fires In Progress → In Review for CAM-70), the two In Review sub-gates (a holistic subagent review in place of the paid codex review, at the operator's direction as in S1, then the human documenter gate), the retrospective (8.2), the sync-order stop check (8.3), the spec sync, the Purpose edit (8.4), the archive (8.5), the Linear document mirror and In Review → Done.
All of it lands as one change and pull request 7; per `openspec-linear-sync`, archive precedes the pull request.

**Files:**
- Create: `openspec/changes/stand-up-fleet-alerting/verify.md`
- Create: `openspec/changes/stand-up-fleet-alerting/review.md`
- Create: `openspec/changes/stand-up-fleet-alerting/retrospective.md`
- Modify: `openspec/changes/stand-up-fleet-alerting/tasks.md` (tick 7.1–7.7, 8.1–8.5, 9.1)
- Modify: `openspec/changes/stand-up-fleet-alerting/proposal.md` (front-matter sync ledger only)
- Modify (only if 8.3 finds `share-ghq-reference-tree` archived): `openspec/changes/stand-up-fleet-alerting/specs/world-assumptions/spec.md` (the `Grounded vocabulary for behavioral requirements` table)
- Create (by spec sync): `openspec/specs/fleet-alerting/spec.md`, `openspec/specs/fleet-alerting-interface/spec.md`
- Modify (by spec sync): `openspec/specs/host-metrics-collection/spec.md`, `openspec/specs/telemetry-store/spec.md`, `openspec/specs/telemetry-store-interface/spec.md`, `openspec/specs/world-assumptions/spec.md`
- Modify (8.4, by hand): `openspec/specs/telemetry-store-interface/spec.md` (`:6`, the Purpose's trust-boundary sentence)
- Move (by archive): `openspec/changes/stand-up-fleet-alerting/` → `openspec/changes/archive/<YYYY-MM-DD>-stand-up-fleet-alerting/`
- Modify: `openspec/linear.yaml` (`projects."fleet-observability".archive_documents` gains `fleet-alerting` and `fleet-alerting-interface`)
- Create (git-ignored evidence): `logs/s3-evidence/9.1-budget-<ts>.log`, `logs/s3-evidence/8.3-sync-order-<ts>.log`, `logs/s3-evidence/linear-doc-ids.txt`

**Interfaces:**
- Consumes: Task 7's evidence and `window.env`; Tasks 1–6's evaluation-cost and `nix fmt` logs under `logs/s3-evidence/`; `state.json`'s `.firings[] = { at, alert, host }` (every posted `FIRING` and `critical` re-post, never `info`, pruned after 86400 s) and R9.1's count `[.firings[] | select(.at > now - 86400)] | length` plus `failed.log` lines with epoch above `now - 86400` (Task 4, confirmed by S3PlanT4); CAM-70 in team `CAM`, project `fleet-observability` (slugId `aeed302bea3b`), workspace `cameronraysmith`; proposal.md's ledger (`linear_story_state` advanced to `In Progress` by the first tick); the stored document ids `host-metrics-collection` `5a3a3fc0-fe9b-46dc-97c5-908743914066`, `telemetry-store` `aaf61f9d-03d1-4a0d-8711-d8e89eaf75ff`, `telemetry-store-interface` `1b158db4-f5e8-42bb-b733-81fd9aa9fb38` (`openspec/linear.yaml`) and the shared `world-assumptions` mirror `a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1` (registered under `pyrite-baremetal-nixos`).
- Produces: `verify.md` with the schema's §1–§8 and an evidence ledger §9–§10; the archived change; six synced main specs; Linear documents `OpenSpec: fleet-alerting` and `OpenSpec: fleet-alerting-interface` created in `fleet-observability`, four existing documents updated; CAM-70 in `Done`.

- [ ] **Step 1: Confirm Task 7's evidence**

Run from `/Users/crs58/projects/vanixiets`:

```bash
export EV="$(git rev-parse --show-toplevel)/logs/s3-evidence"
ls "$EV"
for p in 'PASS: separate visitors' 'NEGATIVE CONTROL HOLDS' 'FAILED acceptance-probe on magnetite' 'answered HTTP 200, expected 403' 'RESOLVED fleet-deadman.service on cinnabar' 'AlertEvaluatorSilent' 'HostOOMKill FIRING: 1  RESOLVED: 1' 'WeeklyPipelineTest FIRING 1 RESOLVED 0'; do
  printf '%s: %s\n' "$p" "$(rg -l -F "$p" "$EV" | wc -l | tr -d ' ')"
done
rg -n 'unexplained:' -A1 "$EV"/7.4-refusals-*.log
```

Expected: every count at least `1`; `unexplained:` followed by `none`.
A missing file means its Task 7 step has not run; stop.

- [ ] **Step 2: 9.1 — the budget count equals the messages over 24 hours**

Run at least 24 hours after `T_CAP_START` (Task 7 Step 28), so pyrite's capture covers the whole 24-hour window R9.1 counts, which includes all of 7.6.
Run:

```bash
source "$EV/window.env"
{
  echo '$ capture unit on pyrite'; ssh pyrite.zt 'systemctl show fleet-alerts-capture -p ActiveState -p ActiveEnterTimestamp -p NRestarts'
  now=$(date +%s); echo "now=$now T_CAP_START=$T_CAP_START"
  [ "$(date -j -u -f '%Y-%m-%dT%H:%M:%SZ' "$T_CAP_START" +%s)" -le $((now - 86400)) ] && echo "capture covers the 24 h window" || echo "TOO EARLY: wait"
  st=$(ssh magnetite.zt "sudo jq --argjson now $now '[.firings[] | select(.at > \$now - 86400)] | length' /var/lib/fleet-alert/state.json")
  fl=$(ssh magnetite.zt "awk -v now=$now '\$1 > now - 86400' /var/lib/observability-notify/failed.log | wc -l")
  echo "R9.1 over 24 h: state.json firings=$st failed.log=$fl total=$((st + fl))"
  ssh pyrite.zt 'sudo systemctl stop fleet-alerts-capture; sudo cat /var/lib/fleet-alerts-capture.jsonl' > "$EV/9.1-fleet-alerts-capture.jsonl"
  jq -c --argjson now "$now" 'select(.event == "message" and .time > $now - 86400)' "$EV/9.1-fleet-alerts-capture.jsonl" | jq -s -c 'unique_by(.id)[]' > /tmp/s3-24h.jsonl
  echo "messages in window: $(wc -l < /tmp/s3-24h.jsonl)"
  f=$(jq -r 'select((.title // "") | startswith("[FIRING]")) | select(.priority != 2) | select((.title | test("AlertEvaluatorSilent|AlertBudgetExceeded")) | not) | .title' /tmp/s3-24h.jsonl | wc -l)
  n=$(jq -r 'select(.title == null) | .message' /tmp/s3-24h.jsonl | grep -c '^FAILED .* on magnetite$' || true)
  echo "fleet-alerts over 24 h: counted FIRING=$f magnetite FAILED=$n total=$((f + n))"
  [ $((st + fl)) -eq $((f + n)) ] && echo "PASS: R9.1 count equals the posted messages" || echo "FAIL"
} 2>&1 | tee "$EV/9.1-budget-$(date -u +%Y%m%dT%H%M%SZ).log"
ssh pyrite.zt 'sudo rm /var/lib/fleet-alerts-capture.sh /var/lib/fleet-alerts-capture.jsonl'
```

Expected: `ActiveState=active` with `NRestarts=0` before the stop (a pyrite reboot would end the transient unit and leave a gap; then rerun Task 7 Step 28's capture and this step 24 hours later); `capture covers the 24 h window`; `PASS: R9.1 count equals the posted messages`, the window holding at least Task 7's real `HostOOMKill`, `StoreQueryFailing` and `LocalExporterDown` `FIRING`s and 7.2's `FAILED acceptance-probe on magnetite` if it falls inside.
Priority 2 is `info` (`WeeklyPipelineTest`), which R9.1 does not count; `AlertEvaluatorSilent` and cinnabar's notices are cinnabar's, which R9.1 does not count either (design Trade-offs); `AlertBudgetExceeded` is not counted by R9.1.
The rest of 9.1 is the evidence already recorded: the `LocalExporterDown` pair with the operator's phone times (Task 7 Step 32), the `AlertEvaluatorSilent` pair (Steps 27–28), the 403-beside-200 matrix (Step 17) and the 7.4 classification (Step 23).

- [ ] **Step 3: 8.3 — the sync-order stop check**

Run:

```bash
{
  rows() { awk '/^### Requirement: Grounded vocabulary for behavioral requirements/{f=1;next} f&&/^### Requirement/{exit} f&&/^\|/' "$1" | sort -u; }
  MAIN=openspec/specs/world-assumptions/spec.md
  S3=openspec/changes/stand-up-fleet-alerting/specs/world-assumptions/spec.md
  GHQ=openspec/changes/share-ghq-reference-tree/specs/world-assumptions/spec.md
  echo "\$ ls -d openspec/changes/archive/*-share-ghq-reference-tree"; ls -d openspec/changes/archive/*-share-ghq-reference-tree 2>/dev/null || echo 'not archived'
  echo "main rows: $(rows $MAIN | wc -l)  S3 delta rows: $(rows $S3 | wc -l)"
  echo '# main rows missing from the S3 delta (S3 must carry every one)'; comm -23 <(rows $MAIN) <(rows $S3)
  if [ -f "$GHQ" ]; then
    echo "ghq delta rows: $(rows $GHQ | wc -l)"
    echo "# main rows missing from the ghq delta: $(comm -23 <(rows $MAIN) <(rows $GHQ) | wc -l)"
    comm -23 <(rows $MAIN) <(rows $GHQ) | grep -E '^\|(person|writer)\|' || true
  fi
} 2>&1 | tee "$EV/8.3-sync-order-$(date -u +%Y%m%dT%H%M%SZ).log"
```

Expected, and the decision for each case:
- `not archived` and a non-zero count of main rows missing from the ghq delta (on 2026-10-18 main held 117 rows plus header and the ghq delta 66, so about 51 rows, among them S1's `person` and `writer` rows): STOP before Step 13's sync. Tell the operator in one message that `share-ghq-reference-tree`'s `world-assumptions` delta MODIFIES `Grounded vocabulary for behavioral requirements` from a copy predating S1's sync and would delete those rows; S3 may archive first only if the operator confirms that change will rebase its block before its own sync. Record the decision in `verify.md` §10.
- `not archived` and a count of `0`: the ghq delta has been rebased; S3 syncs first, and the ghq change rebases on S3's synced main; record it.
- Archived: the S3 delta must carry every synced main row; for each line under `main rows missing from the S3 delta`, add that row to the S3 delta's table with the edit tool at the place of its term, unless S3 deliberately rewrote the same term and sense (an S3 row beginning with the same `|term|sense|`), then rerun this step until that list is empty; record it.
In every case the S3 list `main rows missing from the S3 delta` must end empty before the sync.

- [ ] **Step 4: Run the verify precheck**

Run:

```bash
tasks_file=$(openspec status --change stand-up-fleet-alerting --json | jq -r '.artifactPaths.tasks.existingOutputPaths[0] // empty')
[ -n "$tasks_file" ] && grep -c '^- \[x\]' "$tasks_file"
git log --oneline origin/main -- pkgs/by-name/ntfy-send modules/nixos/observability-notify.nix modules/nixos/ntfy-alerter.nix modules/nixos/fleet-alert.nix modules/nixos/fleet-alert modules/checks/fleet-alert.nix modules/checks/fleet-alert modules/checks/ntfy-provisioning.nix modules/machines/nixos/magnetite/default.nix modules/machines/nixos/cinnabar packages/docs/src/content/docs/development/operations/fleet-observability.md
```

Expected: the number of items Tasks 1–6 ticked (at least 1); the pull requests 1–6 and the 7.4 revert on `origin/main`, which are the implementation evidence.

- [ ] **Step 5: Create the change**

Run:

```bash
jj new --no-edit -r main@origin -m 'docs(observability): verify and archive S3 fleet alerting'
```

Expected: `Created new commit <change-id> ...`; note it as `VERIFY`.
The orchestrator adds `VERIFY` to the development join.

- [ ] **Step 6: Write `verify.md` (8.1)**

Invoke `openspec-verify-change` for `stand-up-fleet-alerting`; it renders the template from `openspec instructions verify --change stand-up-fleet-alerting --json`.
Fill §1–§8 by the instruction's checks: §1 `openspec validate --all --json` totals; §2 open items (none after Step 7); §3 one row per `openspec status --change stand-up-fleet-alerting --json | jq -r '.artifactPaths.specs.existingOutputPaths[]'`, all `pending sync` (`fleet-alerting`, `fleet-alerting-interface` new; `host-metrics-collection`, `telemetry-store`, `telemetry-store-interface` modified; `world-assumptions` adds A37–A42, modifies A33 and the grounded-vocabulary requirement, renames A33); §4 samples D1, D5, D11, D13 and D15 against their requirements; §5 the commit range of Step 4; §7 plan rows marked `[~]`, if any; §8a the designation lint of `fleet-alerting`'s behavioral nouns against the `world-assumptions` table plus this change's rows, §8b one discharge row per ADDED and MODIFIED requirement from the `Discharges:` clauses in `tasks.md`, §8c the alphabet check.
Append after §8, before `## Overall Decision`:

```markdown
## 9. Deployment record

Sections 9 and 10 are the evidence ledger that `tasks.md` 7.1–7.7 and 9.1 require this file to hold.
`[operator]` marks an observation only the operator could make; every other entry gives the command and its output.

### 9.1 Evaluation cost of each new check
<!-- every NIX_SHOW_STATS log of Tasks 1-5, one line per check: check, drvPath, gc heap bytes, against 0.5 GiB -->

### 9.2 Pre-C1 baseline and C1 (tasks.md 7.1)
<!-- 7.1-pre-c1-visitors, 7.1-provisioning, 7.1-token-probe, 7.1-anon, 7.1-visitor-journal, 7.1-post-c1-visitors, the tail of the C1 deploy log -->

### 9.3 C2 (tasks.md 7.2)
<!-- 7.2-evaluator, 7.2-notifier, 7.2-arc, 7.2-rulesignalmissing-silence, 7.2-rulesignalmissing-negative, 7.2-no-refusal, the tail of the C2 deploy log -->

### 9.4 C3 and R9.4 (tasks.md 7.3)
<!-- 7.3-deadman, 7.3-matrix, 7.3-r94-baseline, 7.3-r94-negative-deploy, 7.3-r94-negative, 7.3-r94-redeploy, 7.3-r94-resolved -->

### 9.5 No refused post across the cutover (tasks.md 7.4)
<!-- window.env, 7.4-curl22-control, 7.4-refusals (counts and classification), 7.4-revert-delivered or 7.4-revert-skipped -->

### 9.6 R9.3 (tasks.md 7.5)
<!-- 7.5-stop, 7.5-silent, 7.5-start, 7.5-resolved -->

### 9.7 Every shipped rule fired and resolved (tasks.md 7.6)
<!-- 7.6-oom, 7.6-store, 7.6-oom-store-resolved, 7.6-exporter, 7.6-exporter-alerts, 7.6-forced-firing, 7.6-forced-resolved -->

### 9.8 Subscription and the first Monday message (tasks.md 7.7)
<!-- 7.7-subscription.log, 7.7-weekly.log -->

## 10. Integration verification (tasks.md 9.1) and the sync order (tasks.md 8.3)

### 10.1 The closed alert loop
<!-- the LocalExporterDown pair with the operator's phone times; the AlertEvaluatorSilent pair; the 403 beside 200 of 7.3; the 7.4 result -->

### 10.2 The alert budget count against the posted messages
<!-- 9.1-budget, with the 12-hour window and its reason (ntfy cache-duration 12 h, A42) -->

### 10.3 Sync order against share-ghq-reference-tree
<!-- 8.3-sync-order and the decision taken -->
```

Replace each HTML comment with the named logs' commands and outputs, verbatim, in a fenced `text` block, and delete the comment.
Before pasting, check for credentials:

```bash
rg -n 'tk_[-_A-Za-z0-9]{29}' "$EV" ; rg -n '\$2[aby]\$[0-9]{2}\$' "$EV"; echo "credential scan exit=$?"
```

Expected: no match from either pattern (token and bcrypt hash shapes); a match is removed from that log and the token is rotated per the runbook before continuing.
Check `(pass) PASS` when every section holds, `(warn) PASS WITH WARNINGS` naming the warning when §4 or §8 records drift, and `(fail) FAIL` when any 7.x or 9.1 expectation failed.

- [ ] **Step 7: Tick the items**

In `openspec/changes/stand-up-fleet-alerting/tasks.md` change `- [ ]` to `- [x]` at the start of 7.1–7.7, 8.1–8.5 and 9.1, and nothing else (8.2–8.5 are ticked now because this change completes them before it is pushed).
Run:

```bash
rg -n '^- \[ \]' openspec/changes/stand-up-fleet-alerting/tasks.md
openspec validate stand-up-fleet-alerting --strict; echo "validate exit=$?"
```

Expected: no unticked line; `validate exit=0`.
Then confirm every discharge resolves: each requirement name quoted after `Discharges:` in `tasks.md` must appear in `verify.md`; run

```bash
comm -23 \
  <(grep -o 'Discharges: [^—]*' openspec/changes/stand-up-fleet-alerting/tasks.md | grep -oE '(FAI|FA|TSI) `[^`]+`' | sed -E 's/^[A-Z]+ //' | sort -u) \
  <(grep -oE '`[^`]+`' openspec/changes/stand-up-fleet-alerting/verify.md | sort -u)
```

Expected: no output.

- [ ] **Step 8: Fire In Progress → In Review for CAM-70**

Run:

```bash
linear auth whoami --workspace cameronraysmith
CUR=$(linear issue view CAM-70 --json --workspace cameronraysmith | jq -r '.state.name'); echo "$CUR"
```

Expected: `whoami` confirms the `cameronraysmith` workspace; `CUR` is `In Progress`.
Proceed only if `CUR` is `Backlog`, `Todo` or `In Progress`; if it is `In Review` or `Done`, skip to Step 9 and record the no-op.
Run:

```bash
linear issue update CAM-70 --state "In Review" --workspace cameronraysmith
printf 'S3 is deployed on magnetite and cinnabar and verify.md records the cutover and the closed alert loop. The change is ready for its holistic review and documenter review.\n' > /tmp/cam70-c.md
linear issue comment add CAM-70 --body-file /tmp/cam70-c.md --workspace cameronraysmith
```

Expected: both succeed; a `NotFoundError` is a dropped write recorded in Step 9, leaving the issue In Progress.
If `CUR` was `Todo` (the first-tick transition was dropped), first run `linear issue update CAM-70 --state "In Progress" --workspace cameronraysmith` as the catch-up, per the strictly-behind rule.

- [ ] **Step 9: Update the sync ledger**

In `openspec/changes/stand-up-fleet-alerting/proposal.md` front matter set `linear_story_state: In Review`, `last_synced_state: In Review`, `last_synced_at:` to `date -u +%FT%TZ`, and append:

```yaml
  - { at: "<the same timestamp>", transition: "In Progress->In Review", outcome: "posted", note: "verify.md created; cutover and 9.1 evidence recorded" }
```

`<the same timestamp>` is the value just written to `last_synced_at`.
If Step 8 dropped the write, use `outcome: "dropped"` with the error in `note` and leave both states at `In Progress`.

- [ ] **Step 10: Commit the verification**

Run:

```bash
nix fmt -- openspec/changes/stand-up-fleet-alerting 2>&1 | tee "$EV/8.1-fmt-$(date -u +%Y%m%dT%H%M%SZ).log"
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- \
  openspec/changes/stand-up-fleet-alerting/verify.md \
  openspec/changes/stand-up-fleet-alerting/tasks.md \
  openspec/changes/stand-up-fleet-alerting/proposal.md
jj log -r VERIFY --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `VERIFY` shows the three files; do not push.
Wait until the orchestrator has added `VERIFY` to the join: `jj log -r 'VERIFY & ::@' --no-graph -T 'change_id.short()'` prints the id and `test -f openspec/changes/stand-up-fleet-alerting/verify.md && echo present` prints `present`.

- [ ] **Step 11: Holistic review sub-gate (replaces the codex review)**

The operator declined the paid codex review for this program, so this gate is one read-only Opus subagent review of S3 as merged and deployed, the substitute S1 used (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/review.md`, and that change's `verify.md` §11).
First fix the reviewed range:

```bash
S3_PATHS='pkgs/by-name/ntfy-send modules/checks/package-tests.nix modules/nixos/observability-notify.nix modules/clan/services/otel-collector modules/checks/otel-collector-config.nix modules/nixos/ntfy-alerter.nix modules/checks/ntfy-provisioning.nix modules/machines/nixos/cinnabar modules/nixos/fleet-alert.nix modules/nixos/fleet-alert modules/checks/fleet-alert.nix modules/checks/fleet-alert modules/checks/greptimedb-envelope.nix modules/machines/nixos/magnetite/default.nix packages/docs/src/content/docs/development/operations/fleet-observability.md modules/README.md modules/home/ai/plugins/nix-build-operations/.apm/skills/nix-flake-pr-cycle/SKILL.md modules/home/ai/plugins/preferences-code-and-collaboration-conventions/.apm/skills/preferences-style-and-conventions/SKILL.md'
FIRST=$(git log --reverse --format=%H -S NTFY_TOKEN_FILE origin/main -- pkgs/by-name/ntfy-send/ntfy-send.sh | head -n1)
BASE=$(git rev-parse "$FIRST^"); TIP=$(git rev-parse origin/main)
git cat-file -t "$BASE"; git cat-file -t "$TIP"
git diff --stat "$BASE" "$TIP" -- $S3_PATHS | tail -n1
echo "BASE=$BASE TIP=$TIP"
```

Expected: `commit` twice, a diffstat line, and the two hashes; `FIRST` is Task 1's commit, the first on `origin/main` to add `NTFY_TOKEN_FILE` to `ntfy-send.sh`, and `BASE` its parent.

Spawn one subagent of the default `task` agent type on an Opus model (the `reviewer` type has no model configured in this harness), read-only by its instructions, as S1's review ran, with this task, substituting the two hashes and the path list printed above:

```text
Review slice S3 (OpenSpec change stand-up-fleet-alerting, Linear CAM-70) as merged and deployed. Read-only: change no file and run no build, deploy, formatter or mutating command.
Read: the change set `git diff <BASE> <TIP> -- <S3_PATHS>` and `git log --no-patch <BASE>..<TIP> -- <S3_PATHS>`; openspec/changes/stand-up-fleet-alerting/{proposal.md,design.md,tasks.md,verify.md} and its specs/; docs/notes/development/observability/ (charter.md, decisions/ADR-009-alerting.md, components/fleet-alert.md, architecture/reference-architecture.md); and the S1 review at openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/review.md for the expected shape.
Answer four questions, each finding with file:line evidence and a proposed fix:
1. Critical oversights: a failure class S3 claims to report that cannot reach a person, a path where a credential reaches a command line or an unintended reader, a post that can be lost rather than retried, an alert that can fire or resolve twice, or a contradiction with S2, S4, S5 or S7 as the decision records plan them.
2. Significant architecture improvements: places where the evaluator, transition function, dead-man, notifier or ntfy provisioning could be simpler or more robust for the same guarantees.
3. Checks that cannot fail, clauses that compare a value with itself or with a module literal, and properties that no check, assertion or deployment observation covers.
4. Overzealousness: checks, mutants or mechanisms that cost more (evaluation, maintenance, merge-queue risk) than the invariant they protect.
Return a markdown report in the S1 review.md form: a title, a paragraph stating what was read, when and why (in place of the codex review, at the operator's direction), the four questions, a summary count by severity (critical, significant, minor), a table | Finding | Category | Severity | Applied in | with Applied in left as "pending", then one section per finding (F1, F2, ...) with evidence and the proposed fix.
```

Write the returned report verbatim to `openspec/changes/stand-up-fleet-alerting/review.md`, then run:

```bash
jj st --no-pager >/dev/null
nix fmt -- openspec/changes/stand-up-fleet-alerting/review.md
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- openspec/changes/stand-up-fleet-alerting/review.md
rg -c '^\| F[0-9]+ ' openspec/changes/stand-up-fleet-alerting/review.md
```

Expected: the number of findings in the table.
Present the findings to the human, who decides which to apply; every applied finding is applied before Step 12.
For the applied findings, append to `tasks.md` a section `## 10. Review follow-ups` with one item per finding (`- [ ] 10.<n> F<n>: <fix> — verify: <the check, assertion or runtime observation shown red before and green after>`), and hand the items to the orchestrator, which lands them as their own pull requests and redeploys the affected hosts through Task 7 Step 0's procedure.
As each lands, tick its item, fill its `Applied in` cell in `review.md`, and add to `verify.md` a section `## 11. Review follow-ups (tasks.md section 10)` recording the pull requests, the red-before and green-after evidence and any redeploy, in the form of S1's `verify.md` §11.
A finding the human declines gets `Applied in: declined, <reason>` in `review.md`, so the reason for every skipped fix is recorded (S1-R6's last promote rule).
If any finding is critical, it is a re-queue: check `- [x] (fail) FAIL` in `verify.md`; in proposal.md set `review_round` to its value plus one and both states to `In Progress`, and append `{ at: "<iso>", transition: "In Review->In Progress", outcome: "posted", note: "holistic review re-queue: <findings>" }`; run `linear issue update CAM-70 --state "In Progress" --workspace cameronraysmith`; squash into `VERIFY` as in Step 10; after the fixes land, this task restarts at Step 6.
Past `max_review_rounds` (3), post one escalation comment and stop.
Post one comment of at most two sentences, written from the actual result, with `linear issue comment add CAM-70 --body-file /tmp/cam70-c.md --workspace cameronraysmith`.

- [ ] **Step 12: documenter sub-gate**

This gate stays a human step, and its scope includes the operator documentation (S1-R6's rule that operator docs are in the documenter gate's scope).
Ask the human to review, against what was deployed: `verify.md` and `review.md`; the runbook `packages/docs/src/content/docs/development/operations/fleet-observability.md`; `modules/clan/services/otel-collector/README.md`; `modules/README.md`; the two skill lines of Task 6 Step 7; ADR-009 and `components/fleet-alert.md` as amended; and design.md.
Record `documenter: approved by <name> on <date>` or the rejection with its reason under `**Next step**:` in `verify.md`; a rejection re-queues as in Step 11.

- [ ] **Step 13: Write the retrospective (8.2)**

Run:

```bash
verify_file=$(openspec status --change stand-up-fleet-alerting --json | jq -r '.artifactPaths.verify.existingOutputPaths[0] // empty')
test -n "$verify_file" && ! grep -q '^- \[x\] (fail) FAIL' "$verify_file" && echo "retrospective allowed"
openspec instructions retrospective --change stand-up-fleet-alerting --json | jq -r '.instruction'
```

Expected: `retrospective allowed`, then the instruction.
Invoke `openspec-continue-change` for the `retrospective` artifact and write `retrospective.md` in the S1 format (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/retrospective.md`), with a table that takes each S1-R6 rule (`:132-181` there) and states whether S3 applied it and what it caught: vendor source read before depending on an option (the v2.28.0 401-on-unknown-token finding that turned two deploys into three, and the /64 visitor grouping); start ordering (`fleet-alert` after the store and schema job, the dead-man after ntfy); independent-value clauses; evaluation budgets (each check's §9.1 figure); negative controls (the pre-C1 visitor control, the unknown-token 401, the curl-22 control, R9.4, `RuleSignalMissing`); format before commit; operator docs as a task; later-slice rules (D10's S4 union).
Close with a §6 promote list in the S1 format; every undischarged §8b row and every §7 gap appears with a follow-up.
Run `rg -n '^## 6\. Promote' openspec/changes/stand-up-fleet-alerting/retrospective.md`; expected: one line.

- [ ] **Step 14: Archive readiness, the sync and the Purpose edit (8.4)**

Confirm Step 3's decision allows the sync, then run:

```bash
openspec status --change stand-up-fleet-alerting --json | jq -c '[.artifacts[] | {id, status}]'
openspec list --json | jq -c '.changes[] | select(.name == "stand-up-fleet-alerting") | {totalTasks, completedTasks}'
planning_root=$(openspec status --change stand-up-fleet-alerting --json | jq -r 'select(.planningHome.kind=="repo") | .planningHome.root'); echo "$planning_root"
caps=$(openspec status --change stand-up-fleet-alerting --json | jq -r '.artifactPaths.specs.existingOutputPaths[] | split("/")[-2]'); echo $caps
```

Expected: every artifact `done`; `totalTasks` equal to `completedTasks`; `/Users/crs58/projects/vanixiets`; the six capabilities.
Keep `planning_root` and `caps` for Step 16.
Invoke `openspec-archive-change` for `stand-up-fleet-alerting` and choose "Sync now (recommended)"; stop the skill before its move if it offers one, so the Purpose edit lands first; otherwise do the Purpose edit right after the move on the same main spec.
Run:

```bash
rg -n '^## (ADDED|MODIFIED|REMOVED|RENAMED) Requirements' openspec/specs/fleet-alerting openspec/specs/fleet-alerting-interface openspec/specs/host-metrics-collection openspec/specs/telemetry-store openspec/specs/telemetry-store-interface openspec/specs/world-assumptions
rg -c '^### Requirement: A(37|38|39|40|41|42) ' openspec/specs/world-assumptions/spec.md
rg -n 'ntfy access is ZeroTier membership' openspec/specs/
```

Expected: no output; `6`; one line, `openspec/specs/telemetry-store-interface/spec.md:6`.
With the edit tool, in `openspec/specs/telemetry-store-interface/spec.md:6`, replace `ntfy access is ZeroTier membership;` with:

```text
ntfy on cinnabar, reached over ZeroTier, lets only the `alerter` token publish to `fleet-*` topics, any root process on magnetite or cinnabar can read that token, and cinnabar is the single delivery path, which nothing here watches;
```

Run `rg -n 'ntfy access is ZeroTier membership' openspec/specs/ || echo gone`; expected: `gone`.

- [ ] **Step 15: Archive (8.5)**

Let the skill perform the move, or run:

```bash
openspec archive stand-up-fleet-alerting -y --skip-specs 2>&1 | tee "logs/openspec-archive-s3-$(date +%Y%m%d-%H%M%S).log"
ARCHIVED=$(ls -d openspec/changes/archive/*-stand-up-fleet-alerting); echo "$ARCHIVED"
test ! -e openspec/changes/stand-up-fleet-alerting && echo archived
openspec list --json | jq -r '.changes[].name' | grep -c '^stand-up-fleet-alerting$' || true
openspec validate --specs --strict; echo "validate exit=$?"
```

Expected: the archive directory, `archived`, `0`, `validate exit=0`.
`--skip-specs` because Step 14 synced; `openspec archive --help` at the pin lists `--skip-specs   Skip spec update operations` (read 2026-10-18).

- [ ] **Step 16: Mirror the main specs to Linear documents**

Run:

```bash
linear auth whoami --workspace cameronraysmith
: > "$EV/linear-doc-ids.txt"
for cap in $caps; do
  if [ "$cap" = world-assumptions ]; then
    linear document update a7f9d24e-8fe2-4120-9ba0-e7d4d3a23fe1 --title "OpenSpec: world-assumptions" --content-file "$planning_root/openspec/specs/world-assumptions/spec.md" --workspace cameronraysmith
    continue
  fi
  DOC_ID=$(yq -r ".projects.\"fleet-observability\".archive_documents.\"$cap\".id // \"\"" openspec/linear.yaml)
  if [ -z "$DOC_ID" ]; then
    DOC_ID=$(linear document list --project aeed302bea3b --json --workspace cameronraysmith | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  if [ -n "$DOC_ID" ]; then
    linear document update "$DOC_ID" --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace cameronraysmith
  else
    linear document create --project aeed302bea3b --title "OpenSpec: $cap" --content-file "$planning_root/openspec/specs/$cap/spec.md" --workspace cameronraysmith
    DOC_ID=$(linear document list --project aeed302bea3b --json --workspace cameronraysmith | jq -r --arg t "OpenSpec: $cap" '.nodes[] | select(.title == $t) | .id')
  fi
  printf '%s %s\n' "$cap" "$DOC_ID" >> "$EV/linear-doc-ids.txt"
done
cat "$EV/linear-doc-ids.txt"
```

Expected: updates for `world-assumptions`, `host-metrics-collection`, `telemetry-store`, `telemetry-store-interface` (their stored ids), creates for `fleet-alerting` and `fleet-alerting-interface`, and five non-empty ids in the file.
`aeed302bea3b` is the slugId; a UUID would make `document list` return nothing and duplicate documents.
With the edit tool, in `openspec/linear.yaml` under `"fleet-observability"` → `archive_documents`, after the `"telemetry-store-interface"` entry's `id:` line, add:

```yaml
      "fleet-alerting":
        id: "<id for fleet-alerting from linear-doc-ids.txt>"
      "fleet-alerting-interface":
        id: "<id for fleet-alerting-interface from linear-doc-ids.txt>"
```

Each `<…>` is replaced by the id the loop printed; nothing else in the file changes (never `yq -i`, which drops comments).
Run `jj diff --git openspec/linear.yaml`; expected: four added lines with real ids and every comment intact.

- [ ] **Step 17: Fire In Review → Done for CAM-70**

Run:

```bash
CUR=$(linear issue view CAM-70 --json --workspace cameronraysmith | jq -r '.state.name'); echo "$CUR"
linear issue update CAM-70 --state "Done" --workspace cameronraysmith
printf 'The S3 change is archived and its canonical specs are mirrored to the Fleet observability project documents.\n' > /tmp/cam70-c.md
linear issue comment add CAM-70 --body-file /tmp/cam70-c.md --workspace cameronraysmith
```

Expected: `CUR` is `In Review` (or `In Progress` if Step 8 was dropped); both succeed; skip both if `CUR` is already `Done`.
In the archived `proposal.md` front matter set `linear_story_state: Done`, `last_synced_state: Done`, `last_synced_at:` to `date -u +%FT%TZ`, `review_round: 0`, and append `{ at: "<iso>", transition: "In Review->Done", outcome: "posted", note: "archive; spec sync, Purpose edit and document mirror done" }`, where `<iso>` is the `last_synced_at` value.

- [ ] **Step 18: Format and commit the close-out**

Run:

```bash
ARCHIVED=$(ls -d openspec/changes/archive/*-stand-up-fleet-alerting)
jj st --no-pager >/dev/null
nix fmt -- "$ARCHIVED" openspec/specs openspec/linear.yaml 2>&1 | tee "$EV/8.5-fmt-$(date -u +%Y%m%dT%H%M%SZ).log"
nix fmt -- --fail-on-change "$ARCHIVED" openspec/specs openspec/linear.yaml; echo "fmt-exit=$?"
jj squash --from @ --into VERIFY --keep-emptied --use-destination-message -- \
  openspec/changes/stand-up-fleet-alerting "$ARCHIVED" \
  openspec/specs/fleet-alerting openspec/specs/fleet-alerting-interface openspec/specs/host-metrics-collection openspec/specs/telemetry-store openspec/specs/telemetry-store-interface openspec/specs/world-assumptions \
  openspec/linear.yaml
jj log -r VERIFY --no-graph -T 'change_id.short() ++ " " ++ description.first_line() ++ "\n"' --stat
```

Expected: `fmt-exit=0`; `VERIFY` shows the change directory deleted, the same files under the archive directory with `retrospective.md`, the six main specs and `openspec/linear.yaml`.
The orchestrator rebases the join, pushes and opens pull request 7, which lands through the merge queue; do not push.

---
