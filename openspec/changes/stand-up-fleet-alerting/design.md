## Context

This change is slice S3 of the fleet observability implementation (RA:252; Linear CAM-70).
It realizes ADR-009 and its component `fleet-alert`, and depends only on S1 (RA:271).
`brainstorm.md` records the grounding evidence and the decision chain D1 to D11, which the operator accepted on 2026-10-18 (DEC:5-15); this document develops that direction into the technical design.
ADR-009 and the component were amended in place under charter v17 for D1 to D11 and for the rule expressions measured on magnetite (`docs/notes/development/observability/charter.md:336-337`), so the amended texts are cited as they stand.

Citation keys:
A9 is `docs/notes/development/observability/decisions/ADR-009-alerting.md`, FA is `components/fleet-alert.md` and RA is `architecture/reference-architecture.md` under the same directory.
DEC is `logs/s3/decisions.md`, SL is `logs/s3/series-labels.md`, NG is `logs/s3/ntfy-grounding.md` and BR is `logs/s3/s3brief.md`.
S1 is `openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/`, and S1-R6 is its `retrospective.md` §6 (`:130-181`).
FM is `modules/clan/services/otel-collector/flake-module.nix`, MG is `modules/machines/nixos/magnetite/default.nix`, and GN is `modules/nixos/greptimedb.nix`.

The current state:

- magnetite runs S1's store, collector and notifier; nothing reads the stored series (proposal "Why").
- The notifier lives in the collector's `agent` role (FM:139-205, :367-395), posts `FAILED`/`RESOLVED` anonymously through `ntfy-send` (FM:112, :129), and is wired to the units in `services.observability-notify.units` (MG:327-340; FM:367).
- `ntfy-send` runs `curl -sfk -m 5 "$@" -d "$msg" https://ntfy.zt/$topic` and has no authentication (`pkgs/by-name/ntfy-send/ntfy-send.sh:30-34`).
- cinnabar's ntfy sets only `listen-http = "[::1]:2586"` and `base-url` (`modules/machines/nixos/cinnabar/ntfy.nix:4-9`); `user.db` holds no users or tokens, and anonymous clients may publish anywhere (DEC:3).
- cinnabar runs no collector and so has no `observability-notify@` template (`modules/clan/inventory/services/otel-collector.nix:11-12`; BR:102).
- The store accepts PromQL at `/v1/prometheus/api/v1/query` with `x-greptime-db-name: fleet` and caps `max_concurrent_queries` at 8 (SL:4, :16).
- The OOM order on magnetite is the nixbot evaluator at 900 (`modules/nixos/nix-eval-lock.nix:9-10`), the store at 500 (GN:268) and the collector at 300 (FM:545-546).
- magnetite and cinnabar set no `time.timeZone` and evaluate to `UTC` (`nix eval` of both, 2026-10-18); darwin hosts and pyrite set `America/New_York` (`modules/darwin/base.nix:57`; `modules/machines/nixos/pyrite/default.nix:128`).
- The root pin carries ntfy-sh 2.28.0, prometheus 3.15.0 (for `promtool`), jq 1.8.2, Python 3.14.7 and `python3Packages.hypothesis` 6.156.1 (`nix eval` of `inputs.nixpkgs.legacyPackages.x86_64-linux`, 2026-10-18).

Constraints that shape every decision below:

- A post whose `Authorization` header fails authentication gets 401 even where anonymous access is allowed (A9:49; `binwiederhier/ntfy@v2.28.0:server/server_auth.go:45-50`), and an anonymous write under `*:fleet-*:ro` gets 403 (NG:30).
- ntfy refuses to start when an access or token entry names an unprovisioned user, and accepts only tokens matching `^tk_[-_A-Za-z0-9]{29}$` (A9:50).
  `auth-users`, `auth-access` and `auth-tokens` are altsrc string-slice flags that read both `NTFY_AUTH_*` and the YAML file (`binwiederhier/ntfy@v2.28.0:cmd/serve.go:54-56`).
  All three are read from one context (`:175-177`) into one configuration (`:498-500`), so an `auth-access` entry in the YAML sees `alerter` provisioned through `NTFY_AUTH_USERS` (read through `gh api`, 2026-10-18).
- nixbot evaluates every `checks` attribute on every pull request and builds only `x86_64-linux`, so a check that can flake blocks the merge queue, and a check that needs `kvm` cannot gate (A9:58).
- S1-R6's rules apply: read the vendor source before depending on an option; plan unit start order; check clauses compare independently defined values; each check states an evaluation-cost budget; every runtime clause has a negative control; operator documentation is a planned task; rules are checked against later slices (DEC:17).

Stakeholders are the operator, who subscribes to `fleet-alerts` and acts on it, and slices S2, S4 and S5, which add rules and notified units to what S3 builds.

## Goals / Non-Goals

**Goals:**

- Evaluate the seven rules whose signals S1 stores, plus `StoreQueryFailing` and `RuleSignalMissing`, every 60 s on magnetite, and deliver one `FIRING` and at most one `RESOLVED` per instance to `fleet-alerts` (A9:65-72, :98).
- Raise `AlertEvaluatorSilent` from cinnabar when magnetite's heartbeat stops (A9:73).
- Restrict publishing on `fleet-*` to the `alerter` credential and give each mesh client its own ntfy rate-limit budget (A9:83-84).
- Carry the token through one sender without placing it on any command line (A9:75, :81).
- Back every envelope with a regulator shown able to fail: R9.1 to R9.5 (A9:191-209), the provisioning check (A9:86), and the token-transport and wiring checks of D19.
- Cut over in three deploys with no window in which a post is refused (A9:87).

**Non-Goals:**

- The filesystem, NVMe, launchd and `HostProbeStale` rules and other hosts' collectors (S4, S5; D7).
- The dev-loop SLO burn rule (S2; D8).
- An external watch of cinnabar or of ntfy itself (CAM-76, A9 Q5).
- Silencing, grouping or Alertmanager (A9 Q1, Q3).
- Subscriber configuration in the repository; the operator subscribes by hand, following the runbook (NG:20).
- Token rotation tooling; rotation is a runbook procedure (Risks).

## Decisions

### Layout

New files:

| Path | Content |
|---|---|
| `modules/nixos/fleet-alert.nix` | `flake.modules.nixos.fleet-alert`: options `services.fleet-alert.evaluator.{enable,tokenFile,regulatorPasswordFile,storeUrl,topic,heartbeatTopic}` and `services.fleet-alert.deadman.{enable,tokenFile,ntfyUrl,topic}`; `flake.lib.fleetAlertEvaluator pkgs { ntfySend; }` and `flake.lib.fleetAlertDeadman pkgs { ntfySend; }`, the scripts as `writeShellApplication` derivations, so the checks build them with a recording `ntfy-send` stub; `fleet-alert.{service,timer}` and `fleet-deadman.{service,timer}`; the R9.5 assertion (A9:226; D12, D13, D15, D16, D18) |
| `modules/nixos/fleet-alert/rules.nix` | `flake.lib.fleetAlertRules { lib; notifiedUnits; }` returning `{ rules; json; yaml; }`: the rule table in Nix, rendered to the evaluator's JSON and to `promtool`'s YAML (A9:227; D14); a flake-parts module, because import-tree loads every `.nix` file under `modules/` |
| `modules/nixos/fleet-alert/transition.jq` | `def transition($observations; $now; $rules)` over the state, returning `{ state, posts }`, and `def mark_posted($post)`, shared by the evaluator, the dead-man and the property test (D11, D15) |
| `modules/nixos/observability-notify.nix` | `flake.modules.nixos.observability-notify` and `flake.lib.observabilityNotifyScripts`, extracted from FM:84-137, :196-205, :367-395, with the option `services.observability-notify.tokenFile` (default `null`) (D3, D4) |
| `modules/nixos/ntfy-alerter.nix` | `flake.modules.nixos.ntfy-alerter`: the shared `ntfy-alerter` generator, holding only `token`, imported by magnetite and cinnabar (D17) |
| `modules/checks/fleet-alert.nix` and `modules/checks/fleet-alert/` | `checks.x86_64-linux.fleet-alert`: R9.2's `promtool` leg; `fixture_server.py --responses <file> --step-file <file> --port-file <file>`, which serves `responses[<step>][<query>]` on an ephemeral loopback port; the recording `ntfy-send` stub, which appends `{ topic, message, headers, tokenFile }` per call to `$FLEET_ALERT_POSTS` and exits with `$FLEET_ALERT_POST_STATUS`; the mutants; and `model.py` and `test_transition.py` for the Hypothesis property test; three parts, promtool, fixtures and property (D19) |
| `modules/checks/ntfy-provisioning.nix` | `checks.x86_64-linux.ntfy-provisioning`: D6's check over the generator's rendered strings and cinnabar's access entries |

Changed files:

| Path | Change |
|---|---|
| `pkgs/by-name/ntfy-send/{ntfy-send.sh,package.nix}` | `NTFY_TOKEN_FILE` (D2); `passthru.tests.token-transport` (D19) |
| `modules/checks/package-tests.nix` | Declares `ntfy-send = [ "token-transport" ]`, exposing `package-ntfy-send-test-token-transport` |
| `modules/clan/services/otel-collector/flake-module.nix` | The `agent` role imports `observability-notify` instead of defining it; `flake.lib.observabilityNotifyScripts` (FM:137) moves with the scripts, so the R3.1 rehearsal keeps its input (D4) |
| `modules/checks/otel-collector-config.nix` | The rehearsal (`:104-`) also asserts the `FAILED` log: one line per posted `FAILED`, none per suppressed episode (D9) |
| `modules/machines/nixos/magnetite/default.nix` | In PR 4 only: imports `fleet-alert` with the evaluator enabled and `ntfy-alerter`; sets `services.observability-notify.tokenFile` and the evaluator's token and password paths; adds `fleet-alert` to `services.observability-notify.units` (MG:327-340); `regulator-password = [ "greptimedb-envelope" "fleet-alert" ]` in the R8.2 holder assertion (MG:647) |
| `modules/machines/nixos/cinnabar/ntfy.nix` and cinnabar's imports | `environmentFile`, the D1 proxy settings and `log-level = "debug"` in PR 3; `auth-access` and the imports of `observability-notify` and `fleet-alert` with the dead-man enabled in PR 5; `log-level` back to its default in the revert PR (D5) |
| A9, FA, RA, component and package READMEs, operator runbook | Operator documentation, its own PR after C3 (S1-R6); A9 and FA are already amended (charter.md:336-337) |

Units after the cutover:

| Host | Unit | User | Role |
|---|---|---|---|
| magnetite | `fleet-alert.timer`, `fleet-alert.service` | `DynamicUser`, `StateDirectory = "fleet-alert"` | Evaluator, heartbeat, R9.1 |
| magnetite | `observability-notify@.service` | root, template | Failure notifier, now token-bearing, from the extracted module |
| cinnabar | `fleet-deadman.timer`, `fleet-deadman.service` | `DynamicUser`, `StateDirectory = "fleet-deadman"` | Dead-man and R9.4 probe |
| cinnabar | `observability-notify@.service` | root, template | Notifier for `fleet-deadman` |
| cinnabar | `ntfy-sh.service` | module `DynamicUser` (NG:11) | ntfy with provisioning, access entries and proxy settings |

### Data flow

```
fleet-alert.timer (60 s) ─▶ fleet-alert.service (magnetite, DynamicUser)
   │  LoadCredential: regulator-password, alerter token
   │  1. queries, sequential, curl --max-time 10, user from `curl --config -`
   │     http://127.0.0.1:4000/v1/prometheus/api/v1/query  x-greptime-db-name: fleet
   │     7 rule queries · 9 presence selectors · attribution for memory/OOM hosts
   │  2. reads /var/lib/fleet-alert/state.json and /var/lib/observability-notify/failed.log
   │  3. jq transition(state; observations; now; rules) ─▶ {state', posts}
   │  4. heartbeat: ntfy-send "ok <epoch>" fleet-heartbeat  -H "Priority: min"
   │  5. for each post: ntfy-send <body> fleet-alerts -H "Title: [FIRING|RESOLVED] <alert> <host>" -H "Priority: …"
   │        NTFY_TOKEN_FILE=$CREDENTIALS_DIRECTORY/alerter-token
   │        after each success: state ← mark_posted(state; post), written to a temp file and renamed
   ▼
https://ntfy.zt (caddy, X-Forwarded-For) ─▶ ntfy [::1]:2586 ─▶ fleet-alerts ─▶ phone, desktop

fleet-deadman.timer (5 min) ─▶ fleet-deadman.service (cinnabar, DynamicUser)
   │  1. R9.4 probe: anonymous POST http://[::1]:2586/fleet-heartbeat; pass only on HTTP 403
   │  2. GET http://[::1]:2586/fleet-heartbeat/json?poll=1&since=10m
   │  3. jq transition over the single rule AlertEvaluatorSilent (for 0, critical)
   │  4. posts through ntfy-send with the token, state in /var/lib/fleet-deadman/state.json
   ▼
fleet-alerts
```

The evaluator's query user is `regulator`, whose password reaches curl on stdin as `user = "regulator:<pw>"` through `curl --config -`, the pattern of `modules/lib/greptimedb-envelope.nix:64-70`, so it never appears on a command line.
A host label is `host_name` (A9:94).
The heartbeat is posted after the transition and before the alert posts, so a run that completes its evaluation heartbeats even when it later runs out of posting time (A9:72).

### Credential flow

| Generator | File | Delivered as | Consumer |
|---|---|---|---|
| `greptimedb-users` (S1, MG:528-554) | `regulator-password` (`0400`, no `restartUnits`) | `LoadCredential` | `greptimedb-envelope`, and now `fleet-alert`; MG:647's holder assertion lists both |
| `ntfy-alerter` (`share = true`, D17) | `token` (`0400`, `tk_` from `ntfy token generate`, written with `printf '%s'`), deployed on every machine that imports `ntfy-alerter.nix` | `LoadCredential=alerter-token:<path>` | `fleet-alert` (magnetite), `fleet-deadman` (cinnabar), `observability-notify@` (both) |
| | | the vars path itself, as `NTFY_TOKEN_FILE` | the notifier's root `ExecStartPost`/`ExecStopPost` resolve hooks, which run inside each notified unit and cannot see the template's credential (D3) |
| `ntfy-alerter-env` (per machine, cinnabar only, `dependencies = [ "ntfy-alerter" ]`, D17) | `ntfy-env` (`NTFY_AUTH_USERS=alerter:<bcrypt>:user`, `NTFY_AUTH_TOKENS=alerter:<token>`; `restartUnits = [ "ntfy-sh.service" ]`), from `$in/ntfy-alerter/token` and a password discarded after hashing | `services.ntfy-sh.environmentFile`, read by systemd as `EnvironmentFile=` (NG:11) | `ntfy-sh.service` |

clan maps each deployed secret file to a sops secret under `vars/<rel_dir>/<file>` (clan-core `nixosModules/clanCore/vars/secret/sops/generators-to-sops.nix:15-17`, `:48`), so `ntfy-env`, declared only in cinnabar's configuration, exists only on cinnabar.
Shared generators are keyed `vars/shared/<generator>/<file>` (clan-core `nixosModules/clanCore/vars/secret/sops/generators-to-sops-test.nix:76`, `:386-394`), and sops-nix places a secret at `/run/secrets/<key>` by default, so the token lives at `/run/secrets/vars/shared/ntfy-alerter/token`, matching the evaluated `per-machine` path `/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password`.
Hosts take the path from `clan.core.vars.generators.ntfy-alerter.files.token.path`, never as a literal.
The shared token is created once, for cinnabar, and magnetite is added later as a reader with `CLAN_NO_COMMIT=1 clan vars fix magnetite --generator ntfy-alerter`, which re-encrypts the secret for its age key and leaves the value unchanged (`clan vars generate magnetite --generator ntfy-alerter` regenerates the shared token and re-runs `ntfy-alerter-env`, `logs/s3-evidence/4.8-vars-magnetite-20261018T073644Z.log`; `vars fix` adds magnetite's age key through clan-core `sops.py:446-450` `allow_member` and re-encrypts only `vars/shared/ntfy-alerter/token/secret`, `4.8-vars-fix-magnetite-20261018T073724Z.log`).
The site-neutral modules (`fleet-alert`, `observability-notify`) take the token path as an option set by the host, as GN:3-7 keeps the store module free of clan vars, so the checks instantiate them with fixture credentials.
`services.observability-notify.tokenFile` defaults to `null`, which leaves the notifier anonymous, so the extraction's PR changes no deployed post; magnetite sets it, and imports `ntfy-alerter`, only in the PR deployed as C2, so no magnetite deploy before C1 sends a token that ntfy would answer with 401.
Any root process on magnetite or cinnabar can read the token (proposal, trust boundary).

### Failure path

- `fleet-alert` joins magnetite's `services.observability-notify.units`, and `fleet-deadman` is cinnabar's only entry, so a failed run of either reaches `fleet-alerts` through the notifier at most once per 15 minutes per unit (A9:78; FA:54).
- A run fails when a post or the heartbeat fails, or when `TimeoutStartSec` kills it; the state written before the failure keeps every unposted transition pending, so the next run posts it (D15).
- A store that does not answer raises `StoreQueryFailing` after 3 min and freezes every other instance; the run still heartbeats and exits 0 (A9:70, :116).
- A host without `system_memory_usage_bytes` freezes its instances (A9:91).
- ntfy unreachable: every post fails, the evaluator, notifier and dead-man fail, and nothing reaches a person until ntfy returns; this is the residual risk recorded against CAM-76 (A9:179).
- The dead-man fails its unit when the R9.4 probe is accepted, when the probe returns anything other than 403, or when the poll fails (A9:205).
- `SystemdUnitFailed` excludes every unit in `services.observability-notify.units`, so the notifier and the rule never report one failure twice (D10).

### D1: Each mesh client is its own ntfy visitor

- **Choice**: `behind-proxy: true`, `proxy-trusted-hosts` set to caddy's `::1`, `visitor-prefix-bits-ipv6: 128`, and no exempt host (DEC:5; A9 item 12, :84).
- **Rationale**: without a tier, ntfy keys a visitor by IP masked to /64 (A9:45), every request through caddy arrives from `::1` (A9:46), and every ZeroTier member shares `fddb:4344:343b:14b9::/64` (A9:47), so the evaluator, every hook and every mesh client would share a burst of 60 refilled at one per 5 s.
  With `behind-proxy`, ntfy takes the right-most untrusted address of the forwarded header and falls back to the TCP peer when the header is absent (`binwiederhier/ntfy@v2.28.0:server/util.go:86-98`, read via `gh api` while writing this design).
  The dead-man's direct `[::1]:2586` requests carry no forwarded header, so they form the one visitor `::1`, separate from every mesh client.
- **Boundary**: vendored versus first-party; the settings are ntfy's, and S3 only sets them.
- **Regulation**: an observation at deploy 1 that two mesh hosts are keyed as different visitors (Migration Plan); no check clause or assertion repeats the three literals, because it would fail only when they are edited on purpose (S1 `review.md` F9).
- **Alternatives considered**: exempting `::1` through `visitor-request-limit-exempt-hosts`, rejected because without `behind-proxy` it exempts the whole mesh rather than separating it; a tier for `alerter`, rejected because hooks would still share one budget and starve each other; accepting the shared budget, rejected because a hook storm could 429 the evaluator (NG:62, :75-79).

### D2: `ntfy-send` reads the token from `NTFY_TOKEN_FILE`

- **Choice**: when `NTFY_TOKEN_FILE` is set, `ntfy-send` prints `Authorization: Bearer <token>` with bash's `printf` builtin and curl reads it with `-H @-` from stdin; the message stays in `-d`, so stdin is free (DEC:6; A9 item 10, :75).
  Callers keep the usage `ntfy-send MESSAGE [TOPIC] [CURL_ARGS…]`, and an unset variable leaves behaviour unchanged for every hook and skill caller (NG:17-18).
- **Rationale**: a `-H` token sits in curl's argv, readable through `/proc` (NG:64); the token is read with `$(< file)` and `printf`, neither of which executes a program, so it never appears in any argv.
  One sender remains (S1 D2).
- **Boundary**: source versus delivered; `ntfy-send.sh` is the source, and `package.nix:19` prepends `NTFY_CURL_BIN`, which the token-transport test overrides by running the source script directly.
- **Alternatives considered**: curl `--config -` carrying the header, equivalent but it would make stdin carry curl options; `?auth=` in the URL, rejected because the URL is argv (NG:80); a second wrapper for authenticated posts, rejected by S1's single-sender decision.

### D3: The notifier's token

- **Choice**: when `services.observability-notify.tokenFile` is set, `observability-notify@` loads the token through `LoadCredential` and sets `NTFY_TOKEN_FILE=%d/alerter-token`, and the root resolve hooks set `NTFY_TOKEN_FILE` to the vars path; when it is `null`, the default, both post anonymously as in S1 (DEC:7; A9 item 11, :81).
- **Rationale**: the hooks run as `+` inside each notified unit, where `$CREDENTIALS_DIRECTORY` belongs to that unit (BR:125).
- **Alternatives considered**: copying the token under `/var/lib/observability-notify`, rejected as a second copy with its own lifecycle; routing `RESOLVED` through the template, rejected because it would change S1's rehearsed hook semantics (NG:81).

### D4: The notifier becomes `flake.modules.nixos.observability-notify`

- **Choice**: move FM:84-134 (scripts), FM:196-205 (option) and FM:367-395 (wiring and template) into `modules/nixos/observability-notify.nix`; the `agent` role imports it and keeps adding `opentelemetry-collector` (FM:367); cinnabar imports it from deploy 3 (DEC:8; A9:80).
  `flake.lib.observabilityNotifyScripts` (FM:137) moves with the scripts, and the R3.1 rehearsal (`modules/checks/otel-collector-config.nix:85-92`, `:104-`) keeps reading it.
- **Rationale**: `fleet-deadman`'s `OnFailure=` needs a notifier on cinnabar, which runs no collector before S4 (BR:102); one notifier keeps one failure path (S1 `review.md:80`).
- **Alternatives considered**: adding cinnabar to the `agent` role early, rejected because it needs S4's exporter-by-role change; the dead-man posting its own failure, rejected as a second failure path (BR:119-122).

### D5: Three deploys, no rejection window

- **Choice**: (1) cinnabar provisions `alerter` and its token with no access entries; (2) magnetite deploys the token-bearing notifier and evaluator; (3) cinnabar adds `auth-access` and the dead-man (DEC:9; A9 item 13, :87).
  The Migration Plan gives each deploy's content and verification.
- **Rationale**: ntfy answers an unknown token with 401 even where anonymous access is allowed (A9:49), so provisioning precedes the first token-bearing post; anonymous `fleet-*` posts get 403 once access entries exist (NG:30), so access entries follow the last anonymous publisher's cutover.
- **Alternatives considered**: one deploy, rejected because two hosts cannot switch at one instant; two deploys with magnetite first, the first accepted order, rejected by the 401 evidence (DEC:9).

### D6: Provisioning check before deploy

- **Choice**: `checks.x86_64-linux.ntfy-provisioning` runs the `ntfy-alerter` script and then the `ntfy-alerter-env` script with the first one's output as `$in/ntfy-alerter`, in the build sandbox, and asserts: the token matches `^tk_[-_A-Za-z0-9]{29}$` (A9:50); `NTFY_AUTH_USERS` is `alerter:<hash>:user` with a hash of bcrypt's shape, the pattern taken from ntfy 2.28.0's `ValidPasswordHash` when the check is written (NG:67); `NTFY_AUTH_TOKENS` carries the token the shared generator wrote; and every user named in cinnabar's evaluated `services.ntfy-sh.settings.auth-access` is `*` or provisioned in the rendered `NTFY_AUTH_USERS` (DEC:10; A9:86).
  Mutants edit the subjects, never the validator (S1 `review.md` F11): a shared generator emitting a 28-character token, an env generator emitting an unhashed password, an env generator writing a token other than its input, and an access entry naming `alertr`.
  Evaluation budget: 0.5 GiB, measured with `NIX_SHOW_STATS` on the check's `drvPath` at plan time (S1-R6).
- **Rationale**: a rejected `environmentFile` stops ntfy for every publisher, not only alerts (A9:179); the access-user clause relates two independently written values, the generator's script and cinnabar's settings.
- **Alternatives considered**: putting `auth-access` in the env file so a missing file means no rules, rejected because a missing file would silently reopen `fleet-*`; starting the pinned ntfy in the sandbox with the rendered strings, rejected as a server start in a gating check, the runtime class S1 D13 keeps out of `checks`.
  The residual risk that nothing reports an ntfy outage stays with CAM-76 (A9:179).

### D7: Rule scope

- **Choice**: `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest`, with `StoreQueryFailing`, `RuleSignalMissing` and `AlertEvaluatorSilent` (DEC:11; A9:98).
- **Rationale**: these are the rules whose series exist in `fleet` (SL:10); the deferred rules' series are absent (SL:44), so shipping them would only produce `RuleSignalMissing` or vacuous rules.
- **Alternatives considered**: all rules with empty expected-host lists, rejected as vacuous rules; a filesystem scraper in S3, rejected as scope creep into ADR-003 and ADR-004 (BR:111-114).

### D8: The dev-loop SLO burn rule lands in S2

- **Choice**: no SLO rule in S3 (DEC:12).
- **Rationale**: the sequencing places it with the later of S2 and S3, and S2 is later; ADR-009 is unchanged.

### D9: The notifier logs each posted `FAILED`

- **Choice**: the `failed` script appends `<epoch> <unit> <host>` to `/var/lib/observability-notify/failed.log` after a successful post, created mode `0644` in the template's `StateDirectory` (default mode `0755`); a suppressed episode appends nothing (DEC:13; A9:82).
  R9.1 counts that log's lines from the last 24 h together with the `FIRING` timestamps the evaluator keeps in `state.json`, and posts one `AlertBudgetExceeded` per 24 h on breach (A9:192).
- **Rationale**: stamps are removed on resolve and `last-failed` keeps one epoch per unit, so counting from them undercounts (BR:127-130).
  The log is world-readable because the `DynamicUser` evaluator reads it; it carries unit and host names, which `fleet-alerts` already shows every mesh member (A9:182).
- **Alternatives considered**: counting open stamps plus `last-failed`, rejected as lossy; accepting the undercount, rejected because E9.1 would then be unregulated for notifier posts.

### D10: `SystemdUnitFailed` excludes the notified units

- **Choice**: `rules.nix` renders `<notified units>` from the evaluating host's `services.observability-notify.units` into `systemd_unit_name!~"(<notified units>)[.]service"` (DEC:14; A9:97, :110).
- **Rationale**: a single source; without it `greptimedb.service` and `opentelemetry-collector.service` failures arrive twice (BR:131).
  In S3 the evaluator runs only on magnetite and only magnetite reports, so its option is the whole list.
- **Later slices**: when S4 adds notified units on other hosts, the exclusion must become the union over the hosts whose series the evaluator reads; S4's design keeps that rule.

### D11: The transition is a pure jq function, checked against a reference model

- **Choice**: `transition.jq` defines `transition(state; observations; now; rules)` returning `{state, posts}` and `mark_posted(state; post)`; the evaluator's shell is limited to querying, reading files and posting (DEC:15; A9:198).
  A Hypothesis test generates query timelines and compares the jq function with a Python reference model of pending, firing and resolved instances, the store freeze, the host freeze and the re-post cadence.
- **Rationale**: the five R9.2 mutants show the check can fail on five named faults; the property test explores interleavings the fixtures do not enumerate, such as a store freeze that starts while an instance is pending.
- **Alternatives considered**: mutants alone, as A9 first stated; a Lean specification with a refinement check, offered and not chosen (DEC:15).

### D12: Evaluator unit settings

- **Choice**:
  - `DynamicUser = true`, `StateDirectory = "fleet-alert"` and `UMask = "0077"`, the hardening set of `greptimedb-envelope` (GN:305-326); the dead-man takes the same with `StateDirectory = "fleet-deadman"`.
  - `OOMScoreAdjust = 0`, set explicitly, so the kill order on magnetite is nixbot evaluator 900, store 500, collector 300, alert evaluator 0.
  - `after = [ "greptimedb.service" "greptimedb-schema.service" "zerotierone.service" ]` with no `wants`; the dead-man takes `after = [ "ntfy-sh.service" ]` with no `wants`.
- **Rationale**:
  - `DynamicUser` follows S1's regulator precedent; `LoadCredential` works under it, the state directory persists across runs, and the evaluator needs no file another unit writes except the world-readable `failed.log`.
  - The alert evaluator is the process that reports an OOM kill (`HostOOMKill`), so it is the last of the four the kernel should take, and it costs little to keep: it is bounded by `MemoryMax = 64M` and lives under 50 s of every 60 (A9:138, :208).
    A negative value is not used, because it would rank the evaluator below `sshd` and other default-0 services the operator needs during an incident, and `MemoryMax` already bounds its own growth inside its cgroup.
  - Ordering without `wants` keeps a boot from raising `StoreQueryFailing` for a store that is still starting, while never starting a store the operator stopped; a stopped store must surface as `StoreQueryFailing` (A9:70).
    The schema job is ordered because a query against a database the schema job has not created yet would read as a store failure (S1-R6, start ordering).
    `zerotierone` is ordered because posts reach `ntfy.zt` over the mesh, as the collector orders itself (FM:414).
  - The dead-man is ordered after `ntfy-sh` so a boot does not fail its first probe against a server that is still starting; it never starts ntfy, whose outage is CAM-76's.
- **Regulation**: magnetite's configuration asserts the kill order `nix-eval-jobs` > `greptimedb` > `opentelemetry-collector` > `fleet-alert`, each value read from its unit or, for the nixbot evaluator, from the `nix-eval-lock` wrapper, beside R7.1's memory ceilings (`MemoryHigh` below `MemoryMax`, `MemorySwapMax = 0`); these relations moved from `checks.greptimedb-envelope` into host assertions, as S1's F5 did, to keep that check under its 0.5 GiB budget (charter v18), and each is shown able to fail by an `extendModules` override (`logs/s3-evidence/4.9-assertion-mutants-20261018T073326Z.log`).
- **Later slices**: a slice that adds a memory-bounded unit on magnetite adds it to that assertion.

### D13: Query fan-out is sequential

- **Choice**: one query in flight; each query `--max-time 10` (A9:65); the first failed or timed-out rule query ends the query phase and counts as a store failure; a cumulative query deadline of 30 s counts as a store failure; the heartbeat follows the transition; alert posts start only before 40 s have elapsed; a failed post ends the posting phase.
- **Rationale**: the full S3 set, seven rules, three attribution queries and nine presence selectors, took 0.62 to 0.68 s sequentially on magnetite, and the seven rules alone 0.31 to 0.36 s (SL:15), about 1 % of the 60 s period.
  Concurrency would cut well under a second from a run that has 50 s, while occupying up to 8 of the store's `max_concurrent_queries = 8` (SL:16) that the collector's store, the envelope and later the dashboard share.
  Sequential order also makes the fixture server's replay deterministic.
  Ending at the first failure is the store freeze's own semantics: once one query fails, every other instance is frozen and further answers cannot change a post.
  The deadlines bound a run at about 45 s: at most 30 s of queries, one 5 s heartbeat (`ntfy-send.sh:34`), and posts started before 40 s, each bounded by 5 s; this stays inside `TimeoutStartSec = 50s`, so one run cannot overlap the next (A9:208).
- **Alternatives considered**: a fixed pool of N concurrent queries, rejected because it buys nothing at 0.68 s and contends with other store readers; one PromQL query joining all rules, rejected because a rule's failure would then hide which rule broke.

### D14: The rule table and the corrected expressions

- **Choice**: `rules.nix` holds each rule's `alert`, `expr`, `for`, `labels.severity`, `annotations`, presence selectors with expected hosts, attribution queries and the `WeeklyPipelineTest` window, rendered to JSON for the evaluator and YAML for `promtool` (A9:66, :227).
  The S3 expressions are A9's rule table as amended (A9:102-119; charter.md:336-337):
  - `HostMemoryPressure` divides by `used` plus available memory, whose sum equalled `MemTotal` on magnetite, instead of the sum over six overlapping states (A9:102; SL:80-86).
  - `HostOOMKill` and `SystemdUnitRestartLoop` carry `> 0` and `> 5` in the expression, because an uncompared instant query returns every input series (A9:103, :109; SL:95-96).
  - `SystemdUnitFailed` writes the literal dot as `[.]`, because GreptimeDB 1.2.1 rejects `\.` in double-quoted and backtick strings, and `[.]` needs no escape in PromQL, JSON or YAML (A9:110; SL:91-94).
  - `LocalExporterDown`'s presence selector is `up{job="node"}`, because bare `up` carries six jobs on magnetite (A9:111, :117; SL:97-99).
  The presence selectors are the nine measured in SL:42, each queried as `count by (host_name) (<selector>)`; the expected host in S3 is magnetite, the only reporting host (SL:100-101).
- **Rationale**: one Nix source for evaluator and `promtool`, so a rule edit cannot reach one and miss the other (A9:66).
  The fixture check cannot see deployed metric names (A9:185), so the live measurement of every expression is what grounds them, and `RuleSignalMissing` guards them after deploy.
- **Later slices**: the S4 and S5 rows already carry comparisons (charter.md:337) but are unverified against live series; S4 and S5 measure them as SL did.

### D15: State and retries

- **Choice**: `state.json` holds, per instance (rule plus label set), its phase, first-seen, last-seen, the time its `FIRING` and last re-post were posted and whether its `RESOLVED` was posted; per host, the last time it reported `system_memory_usage_bytes`; per presence selector, the last time it returned a series; the store-failure start; and the `FIRING` timestamps of the last 24 h for R9.1.
  `transition` emits a post wherever the desired posted state differs from the recorded one; the wrapper writes `mark_posted(state; post)` to a temporary file and renames it after each successful post.
  The evaluator reads its configuration from the JSON file named by `FLEET_ALERT_CONFIG` (`storeUrl`, `database`, `user`, `queryTimeoutSec` 10, `queryDeadlineSec` 30, `postDeadlineSec` 40, `topic`, `heartbeatTopic`, `stateFile`, `failedLog`, `rules`), rendered by the module.
  It reads its time from `date +%s`, or from `FLEET_ALERT_NOW` when set, which only the fixture check sets.
- **Rationale**: a post that fails, or a run that `TimeoutStartSec` kills, leaves the difference recorded, so the next run retries it; an atomic rename means a kill loses at most the record of one post, which could repeat that one post but never drops an alert.
  The time seam is the one test input in the script; the transition function itself already takes `now` as an argument.
  The store URL, the alert topic and the heartbeat topic come from the evaluator's rendered configuration, not from code, so the checks point it at the fixture server and the acceptance run of the Migration Plan posts to `fleet-acceptance` without a second build.
- **Alternatives considered**: writing state once at the end of the run, rejected because a killed run would repost everything or lose transitions.

### D16: `WeeklyPipelineTest` runs at 09:00 New York time

- **Choice**: the rule's window is Mondays 09:00 to 09:05 in `America/New_York`; the rule table carries the zone name, and the evaluator converts its epoch with jq's `localtime` under `TZ=America/New_York` for that check only (A9:88).
  magnetite's `time.timeZone` stays unset.
- **Rationale**: "local time" in A9 item 14 is the time of the person whose phone proves the path, and the operator's machines use `America/New_York` (`modules/darwin/base.nix:57`; `modules/machines/nixos/pyrite/default.nix:128`); 09:00 UTC would arrive at 04:00 or 05:00 there.
  The tz database handles daylight saving, so the message stays at 09:00 through both changes.
  Setting magnetite's time zone would change every journal and calendar timer on a shared build host to serve one rule.
- **Alternatives considered**: 09:00 UTC, rejected for the hour above; converting in `rules.nix`, rejected because a fixed UTC offset cannot follow daylight saving.

### D17: One shared generator module

- **Choice**: `modules/nixos/ntfy-alerter.nix` declares `clan.core.vars.generators.ntfy-alerter` with `share = true`, `runtimeInputs` `ntfy-sh`, and one file, `token`, deployed on every machine that imports the module; cinnabar's `ntfy.nix` declares the per-machine generator `ntfy-alerter-env` with `dependencies = [ "ntfy-alerter" ]`, `runtimeInputs` `ntfy-sh` and openssl, which reads `$in/ntfy-alerter/token`, generates a password it discards after hashing, and writes `ntfy-env` (A9:234-235; FA:118-119; charter v17).
- **Rationale**: a shared generator is generated once and reused by later machines (clan-core `nixosModules/clanCore/vars/interface.nix:90-100`), so both hosts must declare it identically; one module is the single definition.
  clan-core refuses a shared generator whose files differ in `deploy` between machines ("Machines cinnabar and magnetite have different definitions for shared generator", `clan_lib/vars/generator.py:270-297` at the pin), which would break fleet-wide `clan vars` commands, so the cinnabar-only `ntfy-env` lives in a per-machine generator that depends on the shared token.
  `ntfy user hash` reads the password and its confirmation from stdin (NG:37); the password is never stored, because ntfy authenticates `alerter` only by token.
- **Alternatives considered**: one shared generator with `ntfy-env` set to `deploy = false` on magnetite, rejected by the clan-core check above; declaring the shared generator in each machine's `default.nix`, as S1's per-host generators are (MG:528), rejected because two copies of a shared script can drift.

### D18: R9.5 is an assertion in `fleet-alert.nix`

- **Choice**: an evaluation-time assertion that `fleet-alert.service` sets `MemoryMax = "64M"` and `TimeoutStartSec = "50s"` (A9:208-209).
  It is shown able to fail by evaluating magnetite once with an override that drops `MemoryMax`, recorded as a task, as S1 recorded its assertion overrides (S1 design D11).
- **Rationale**: a property of one module's own settings is an assertion in that module, not a check clause (charter v16; S1-R6).
  64M bounds the run below the collector's 512M and the node exporter's 64M (FM:383, :545) on a host with an OOM history; the observed peak is recorded at acceptance from the `memory peak` systemd logs when a run ends.
  The 50 s timeout under a 60 s timer leaves no overlap (D13).

### D19: Test selection

- **Choice**:

| Lane | What it covers | Host needed |
|---|---|---|
| Evaluation-time assertions | R9.5 (D18); magnetite's R8.2 holder assertion with `fleet-alert` added (MG:647); the token-wiring assertions: `observability-notify.nix` (template credential named in `NTFY_TOKEN_FILE`, resolve hooks under `env NTFY_TOKEN_FILE=<tokenFile>`), `fleet-alert.nix` (evaluator and dead-man credential named in `NTFY_TOKEN_FILE`), and magnetite's and cinnabar's host assertions that every `tokenFile` equals the `ntfy-alerter` token path; magnetite's R7.1 memory-ceiling and kill-order assertions (D12); each shown able to fail by an `extendModules` override (`logs/s3-evidence/4.7-assertion-mutants-20261018T073054Z.log`, `4.9-assertion-mutants-20261018T073326Z.log`) | none; nixbot |
| `checks.x86_64-linux.fleet-alert` | `promtool check rules` over the rendered YAML; the fixture legs, the evaluator against a loopback Python fixture server replaying `/v1/prometheus/api/v1/query` responses, built with a recording `ntfy-send` stub (A9:196); the server answers 404 to any other path, 400 to a request without `x-greptime-db-name: fleet`, 401 to any user other than `regulator` with the fixture password, and fails the leg if two requests are ever open at once (D13): each S3 rule firing once after its `for` and resolving once, `ZfsPoolUnhealthy` included; a replayed `failed` state for a notified unit producing no `SystemdUnitFailed` post (D10); attribution appended to `HostMemoryPressure` and `HostOOMKill` messages (A9:69); a store error producing `StoreQueryFailing` after 3 min and no `RESOLVED`; a silent host producing no `RESOLVED` until it reports again; a presence gap of 30 min producing `RuleSignalMissing` while an expected host reports, and nothing while every expected host is silent; `WeeklyPipelineTest` inside its `America/New_York` window and on either side of it (D16); the R9.1 legs of 11 instances and of 4 on stibnite (A9:193); the five mutants (A9:197); the Hypothesis property test of `transition.jq` against the Python model, `derandomize=True`, `database=None`, a fixed `max_examples` and `deadline=None`, one `jq` process per generated timeline | none; nixbot, in the sandbox, loopback only |
| `checks.x86_64-linux.ntfy-provisioning` | D6 | none; nixbot |
| `package-ntfy-send-test-token-transport` | Runs `ntfy-send.sh` with `NTFY_CURL_BIN` pointing at a recording curl stub; asserts the token is absent from argv and arrives as `Authorization: Bearer` on stdin; a mutant passing the header with `-H` must fail | none |
| R3.1 rehearsal (`otel-collector-config`) | The notifier's crash loop now also yields one `<epoch> <unit> <host>` line in `failed.log` per posted `FAILED` and none per suppressed episode, with a mutant that drops the append (S1-R6, crash-loop case) | none; nixbot |
| Deployment on cinnabar and magnetite | D1 visitor separation, D5's three steps, E9.4's three-way publish matrix, R9.3 and R9.4 with their negative controls, `RuleSignalMissing` silence for 30 min plus its negative control, the ARC inference, the run's logged memory peak, subscription and the first Monday message (Migration Plan; FA:151-161) | magnetite and cinnabar |

  Each new check states a 0.5 GiB evaluation budget, measured with `NIX_SHOW_STATS` on its `drvPath`; `checks.fleet-alert` measured 0.557 GiB with the token-wiring clause (582 MB of it the clause) and 0.36 GiB after that clause became module and host assertions, and `checks.greptimedb-envelope` 0.484 GiB after its memory and kill-order clauses did the same (charter v18).
- **Rationale**: the sandbox has a loopback interface, and Hypothesis, `promtool`, jq and the fixture server need no network, so every pre-merge leg runs on nixbot; derandomizing makes the property test a pure function of the source, so it cannot flake the merge queue.
  ntfy's access control, rate limiting and delivery exist only on cinnabar, and the series exist only on magnetite, so those claims are verified at deployment with negative controls.
  No VM test is added, because `vmTests` need pyrite's `kvm` and do not gate (A9:58, :167); nothing in S3 needs pyrite.
- **Alternatives considered**: a container test of ntfy's access matrix, rejected because deploy 3's probe and matrix test the deployed server directly; a randomized property test, rejected for merge-queue flakes.

## Risks / Trade-offs

- [Risk] ntfy or cinnabar is down and nothing reports it. → Mitigation: the D6 check guards the configuration that can stop ntfy; the residual risk is recorded against CAM-76 (A9 Q5, :179).
- [Risk] A malformed `ntfy-env` from `ntfy-alerter-env` stops ntfy for every publisher (A9:179). → Mitigation: D6 before merge; deploy 1 verifies the start immediately and rolls back by redeploying the previous cinnabar configuration.
- [Risk] A deploy happens out of D5's order, for example magnetite before cinnabar's deploy 1, and token-bearing posts get 401. → Mitigation: the three deploys come from three ordered revisions (Migration Plan), and the runbook states the order and the reverse order for rollback.
- [Risk] Token rotation regenerates a shared value that cinnabar and magnetite pick up at different deploys, reopening the 401 window. → Mitigation: the runbook gives rotation the D5 order, provisioning the new token beside the old one first, since `NTFY_AUTH_TOKENS` is a list (NG:32).
- [Risk] A metric is renamed and a rule goes vacuous; the fixtures cannot see deployed names (A9:185). → Mitigation: `RuleSignalMissing` within 30 min, with its deployment negative control.
- [Risk] The active `share-ghq-reference-tree` change's `world-assumptions` delta MODIFIES `Grounded vocabulary for behavioral requirements` from a copy that predates S1's sync, so syncing it as it stands would delete about 60 of S1's designation rows and reword S1's `person` and `writer` rows; S3's delta MODIFIES the same requirement from current main, and that change also takes A34 to A36 (`openspec/changes/share-ghq-reference-tree/verify.md:46`; `specs/world-assumptions/spec.md:3-38`). → Mitigation: S3's new assumptions start at A37 (proposal); whichever change archives second rebases its block on the synced main before its sync, and S3's archive step checks this and stops if the other change has not been rebased; the operator is told, so the other change's owner can rebase its block.
- [Risk] The direct `[::1]:2586` path trusts any local process's forwarded header, because ntfy reads the header whenever `behind-proxy` is set (`server/util.go:86-92`). → Accepted: only root-capable processes on cinnabar reach it, and they can already read the token.
- [Trade-off] R9.1 counts magnetite's evaluator state and magnetite's notifier log; `AlertEvaluatorSilent` and cinnabar's notifier posts are not counted (D9). → Accepted: they report a broken alert path, which E9.1's muting failure does not concern, and they are bounded by the dead-man's single-instance state and the notifier's 15-minute rate limit.
- [Trade-off] `failed.log` grows without rotation. → Accepted: the notifier posts at most once per 15 min per unit (A9:78), and the log is the alert history A9:176 names.
- [Trade-off] Sequential queries leave concurrency unused. → Accepted on the measured 0.68 s (D13).
- [Trade-off] The property test is derandomized and explores the same examples each build. → Accepted for a non-flaking gate; widening `max_examples` is a reviewed edit.
- [Trade-off] Rule expressions are measured only on magnetite. → Accepted: only magnetite reports until S4 (SL:100-101); S4 re-measures on each new host.

## Migration Plan

The change lands as six pull requests and one follow-up, merged in order; the three deploys run from the heads of PRs 3, 4 and 5:

| Pull request | Contains | Deploy |
|---|---|---|
| 1 | `ntfy-send` `NTFY_TOKEN_FILE` and its token-transport test | none |
| 2 | `observability-notify.nix` extraction, `failed.log`, `tokenFile` defaulting to `null`; no host sets it | none needed; a magnetite deploy changes no post |
| 3 | `ntfy-alerter.nix`; `ntfy-provisioning`; cinnabar imports `ntfy-alerter`, declares `ntfy-alerter-env`, sets `environmentFile`, the D1 proxy settings and `log-level = "debug"`; the encrypted vars under `vars/shared/ntfy-alerter/` and `vars/per-machine/cinnabar/ntfy-alerter-env/` | C1, cinnabar |
| 4 | `fleet-alert.nix`, `rules.nix`, `transition.jq`; `checks.fleet-alert`; magnetite imports `fleet-alert` and `ntfy-alerter`, sets `tokenFile`, the notified-units entry and the holder assertion; magnetite added as a recipient of the shared token | C2, magnetite |
| 5 | cinnabar's `auth-access`, the `observability-notify` import with `units = [ "fleet-deadman" ]`, and `fleet-alert` with the dead-man enabled | C3, cinnabar |
| 6 | operator runbook, READMEs and skill lines | none |
| revert | cinnabar's `log-level` back to its default, after the no-refusal record of the cutover window | cinnabar |

`log-level = "debug"` stays on from C1 until the revert, because ntfy logs a refused request (401, 403) only at `debug`, which classifies both as normal errors (`binwiederhier/ntfy@9fe512a65:server/log.go:37`, `server/server.go:631-632`; re-read at v2.28.0 before PR 3), and because the debug log carries each request's visitor address, the observable for D1's two-visitor check.
The window's log is the record that no post was refused between C1 and the end of C3's verification, apart from the deliberate refusals of C3's checks.

Before each PR's commit, in the working copy, squashing the resulting `vars/` changes into that PR as S1 did (S1 `plan.md:1710-1714`): PR 3 runs `clan vars generate cinnabar`, which creates the shared token and cinnabar's `ntfy-env`; PR 4 runs `CLAN_NO_COMMIT=1 clan vars fix magnetite --generator ntfy-alerter`, which adds magnetite as a reader of the existing token without regenerating it (`clan vars generate magnetite --generator ntfy-alerter` regenerates the shared token and re-runs `ntfy-alerter-env`, `logs/s3-evidence/4.8-vars-magnetite-20261018T073644Z.log`; `vars fix` adds magnetite's age key through clan-core `sops.py:446-450` `allow_member` and re-encrypts only `vars/shared/ntfy-alerter/token/secret`, `4.8-vars-fix-magnetite-20261018T073724Z.log`).
Never add a reader with `clan vars generate <machine> --generator <generator>`: it regenerates a shared value, and a token that differs from the one cinnabar provisioned makes every magnetite post get 401.

1. Deploy cinnabar from PR 3's head.
   Contains provisioning, visitor separation and the debug log level; no access entries, so every existing publisher works.
   Verified by: `ntfy-sh.service` active; `ntfy user list` and `ntfy token list` on cinnabar show `alerter` and one token; on cinnabar, `ntfy-send` with `NTFY_TOKEN_FILE` set to the deployed token posts to `fleet-acceptance` and returns 0 (no 401); anonymous `ntfy-send` from stibnite to `stibnite` and to `fleet-acceptance` both succeed; one publish each from stibnite and magnetite shows two distinct visitor addresses in ntfy's debug log, neither `::1`.
2. Deploy magnetite from PR 4's head.
   Contains the evaluator, the token-bearing notifier and the `failed.log`.
   Verified by: `fleet-alert.timer` active, `/var/lib/fleet-alert/state.json` written, and on cinnabar a `fleet-heartbeat` message every minute; `systemctl start observability-notify@acceptance-probe.service` posts `FAILED acceptance-probe on magnetite` with the token and appends one `failed.log` line, after which the stamp is removed by hand; no `RuleSignalMissing` in the 30 min after deploy, and its negative control: one hand run of the deployed evaluator with a rules file whose one presence selector is misspelt, `for` 0, a scratch state directory and topic `fleet-acceptance`, posts `RuleSignalMissing`; the ARC inference is checked against `/proc/meminfo` and arcstats (FA:159); the memory peak systemd logs at the end of a run is recorded against R9.5's 64M.
3. Deploy cinnabar from PR 5's head.
   Contains the access entries and the dead-man.
   Verified by: `fleet-deadman.service` succeeds every 5 min, its probe answered 403; from stibnite an anonymous publish to `fleet-alerts` gets 403, an anonymous publish to `stibnite` succeeds, and magnetite's token-bearing posts still succeed (E9.4, A9:204); R9.3's negative control: stopping `fleet-alert.timer` on magnetite produces `AlertEvaluatorSilent` within 15 min, and starting it produces `RESOLVED` (A9:202); R9.4's negative control: a temporary cinnabar deploy without `*:fleet-*:ro` makes `fleet-deadman.service` fail and `FAILED fleet-deadman on cinnabar` arrive, followed by the C3 redeploy (A9:206).
4. Over the window from C1 to the end of step 3, ntfy's debug log holds no 401 or 403 other than step 3's deliberate ones, and magnetite's `fleet-alert` and notifier journals hold no failed post; then the revert PR returns `log-level` to its default and cinnabar is deployed from it.
5. The operator subscribes phone and desktop to `fleet-alerts` and records the first Monday `WeeklyPipelineTest` message (FA:161).

Rollback runs in reverse order: redeploy cinnabar from PR 4's head (no access entries) before reverting magnetite, and revert magnetite to anonymous posting (`tokenFile` unset) before removing the provisioning, because removing `alerter` from the environment deletes the user and token at ntfy's next start (NG:36) and every token-bearing post would then get 401.

## Open Questions

None.
