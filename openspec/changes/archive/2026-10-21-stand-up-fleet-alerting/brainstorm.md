# Brainstorm: alert on the known failure classes through ntfy (S3, CAM-70)

## Background

Slice S3 of the fleet observability implementation (`docs/notes/development/observability/architecture/reference-architecture.md:252`): the evaluator on magnetite, the rules whose signals S1 provides, the dead-man on cinnabar, the `alerter` credential and the rule check.
It realizes ADR-009 (`decisions/ADR-009-alerting.md`), and its component is `fleet-alert` (`components/fleet-alert.md`).
S3 depends only on S1 (`reference-architecture.md:271`), and ADR-009 Q5, an external watch on cinnabar, is deferred to CAM-76 after S8 (`:273`).
The reference architecture lists the files S3 adds and modifies (`:198,209,210,219-221`): `modules/nixos/fleet-alert.nix`, `modules/nixos/fleet-alert/rules.nix`, `modules/checks/fleet-alert.nix`, magnetite's `default.nix` and cinnabar's `ntfy.nix`.
CAM-70 carries no acceptance text of its own beyond this sequencing (`logs/s3/s3brief.md:13`); the acceptance items are ADR-009's and the component's (`components/fleet-alert.md:164-174`).

Inputs gathered for this brainstorm:

- `logs/s3/s3brief.md`: the design corpus read against S3, with ADR-009's 17 decision items, the five envelopes and regulators R9.1 to R9.5, what S1 already provides, cinnabar's state and the series each rule needs.
- `logs/s3/ntfy-grounding.md`: the existing ntfy setup read against upstream ntfy 2.28.0 and ADR-009.
- A live read-only check on cinnabar on 2026-10-18 (`logs/s3/decisions.md:3`).
- The decisions D1 to D11 below, accepted by the operator on 2026-10-18 (`logs/s3/decisions.md`).
- The S1 retrospective's §6 rules (`openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/retrospective.md:130-181`).

## Grounding evidence

### ntfy as deployed

- cinnabar runs ntfy 2.28.0 at the root pin `ac1faec` (`logs/s3/ntfy-grounding.md:10`), confirmed live on 2026-10-18 and by `nix eval` of the pinned `ntfy-sh.version` while writing this file.
- `modules/machines/nixos/cinnabar/ntfy.nix:4-9` sets only `enable`, `listen-http = "[::1]:2586"` and `base-url = "https://ntfy.zt"` (`ntfy-grounding.md:9`).
- The NixOS module sets `auth-file`, so access control is already on, with `auth-default-access` at its default `read-write` (`ntfy-grounding.md:11-12`).
  The live check found no users and no tokens in `user.db`, and a cache holding only `fleet-alerts` (`decisions.md:3`).
- caddy serves `ntfy.zt` with `tls internal` and `reverse_proxy [::1]:2586`, bound to the mesh addresses, with 443 open only on `zt+` (`ntfy-grounding.md:13`; `s3brief.md:95`).
- `ntfy-send` runs `curl -sfk -m 5 "$@" -d msg https://ntfy.zt/$topic` and has no auth support (`pkgs/by-name/ntfy-send/ntfy-send.sh:30-34`; `ntfy-grounding.md:16`).
- The only `fleet-alerts` publisher is S1's notifier on magnetite, posting anonymously (`ntfy-grounding.md:19`).
  The agent hooks and skills publish anonymously to host-named topics (`ntfy-grounding.md:17-18`), which `fleet-*` access entries do not match (`ntfy-grounding.md:66`).
- cinnabar is not in the collector's agent role (`modules/clan/inventory/services/otel-collector.nix:11-12`), so `observability-notify@` does not exist there and a dead-man's `OnFailure=` would have nothing to call (`s3brief.md:102`; `ntfy-grounding.md:70`).
- No subscriber configuration exists in the repository (`ntfy-grounding.md:20`).

### ntfy 2.28.0 upstream

- One access row decides, ordered user before `*`, longer topic pattern first, so `alerter:fleet-*:rw` beats `*:fleet-*:ro`; an anonymous write under `*:fleet-*:ro` gets 403 (`ntfy-grounding.md:25-30`).
- Declarative provisioning, available since 2.14.0, takes `auth-users`, `auth-access` and `auth-tokens`, or `NTFY_AUTH_USERS`, `NTFY_AUTH_ACCESS` and `NTFY_AUTH_TOKENS` (`ntfy-grounding.md:31-32`).
  A token must match `^tk_[-_A-Za-z0-9]{29}$`; an access or token entry naming an unprovisioned user stops the server from starting; entries removed from the configuration are deleted at the next start (`ntfy-grounding.md:34-36`).
  The deployed binary's `ntfy serve --help` lists `--auth-users`, `--auth-access`, `--auth-tokens`, `--behind-proxy`, `--proxy-trusted-hosts`, `--proxy-forwarded-header`, `--visitor-request-limit-exempt-hosts` and `--cache-duration` (`decisions.md:3`).
- Without a tier, a visitor is keyed by IP address, masked to a /64 for IPv6, and every request through caddy arrives from `::1`, so `alerter`, every mesh hook and the dead-man's polls would share one rate-limit budget of a burst of 60 refilled at one per 5 s (`ntfy-grounding.md:3,40-44`).
  This shared budget is the grounding's main new finding; neither ADR-009 nor the brief mentions it.
- `/<topic>/json?poll=1&since=10m` returns cached messages from that window, and the cache keeps 12 h in a persistent file (`ntfy-grounding.md:46-48`).
- A publish takes `Authorization: Bearer tk_…` and a `Priority` of `min` to `urgent` (`ntfy-grounding.md:51-53`).
- A request whose `Authorization` header fails authentication gets 401 even where anonymous access would be allowed (pinned source `server/server_auth.go:45-50`, read while writing this file); D5 was amended on this evidence.

### What S1 provides

- The notifier: a `failed` script that posts `FAILED <unit> on <host>` at most once per 15 min per unit and stamps `posted` or `suppressed`, and a `resolved` hook run as `ExecStartPost`/`ExecStopPost` (`modules/clan/services/otel-collector/flake-module.nix:97-131,384`; `s3brief.md:71-78`).
- The `regulator:ro` store account, loaded by `LoadCredential`, whose holder assertion admits only `greptimedb-envelope` today (`magnetite/default.nix:540,551-553,647,676-678`; `s3brief.md:81-85`).
- PromQL at `/v1/prometheus/api/v1/query` with `x-greptime-db-name: fleet`; v1.2.1 rejects a selector without a metric matcher and caps the store at `max_concurrent_queries = 8` (`s3brief.md:86-89`).
- The OOM order: nixbot evaluator 900, store 500, collector 300 (`flake-module.nix:540-545`).
- The series behind seven of ADR-009's 18 rules; filesystem, NVMe, launchd and probe-staleness series do not exist before S4 and S5 (`s3brief.md:145-165`).

## Decision chain

### D1. Rate-limit identity

Options (`ntfy-grounding.md:75-79`): set `behind-proxy` so caddy's `X-Forwarded-For` separates mesh clients; exempt `::1` through `visitor-request-limit-exempt-hosts`, which without `behind-proxy` exempts the whole mesh; give `alerter` a tier; accept the shared budget and record it.

Decision: `behind-proxy: true`, `proxy-trusted-hosts = ::1` and `visitor-prefix-bits-ipv6: 128`, with no exemptions.

- With caddy trusted as the proxy, each mesh client becomes its own visitor, so a hook storm on one host cannot starve the evaluator's posts.
- Amended on 2026-10-18 after the first acceptance: every ZeroTier member shares `fddb:4344:343b:14b9::/64`, and ntfy masks an IPv6 visitor to `--visitor-prefix-bits-ipv6`, default 64, which the deployed 2.28.0 binary lists.
  At the default every mesh member would remain one visitor even behind the proxy, so the prefix is set to 128.
- An exemption was rejected because it would remove rate limiting for every mesh client rather than separate them.

### D2. Token transport

Options (`s3brief.md:126`; `ntfy-grounding.md:80`): curl `-H @file`, curl `--config` on stdin, an extension to `ntfy-send`, or `?auth=`.

Decision: `ntfy-send` gains `NTFY_TOKEN_FILE`; when set, it sends `Authorization: Bearer <token>` read from that file and never puts the token on argv, with curl reading the header from a file or stdin.

- ADR-009 item 10's `-H` token would sit in curl's argv, readable through `/proc` (`ntfy-grounding.md:64`).
- Every caller keeps the one sender S1 established (P11 in S1's brainstorm), so S3 builds no second curl wrapper.

### D3. Notifier token

Options (`ntfy-grounding.md:81`): read the clan vars path directly as root, copy the token into `/var/lib/observability-notify`, or route `RESOLVED` through the template unit.

Decision: the `observability-notify@` template loads the `alerter` token through `LoadCredential`, and the root `ExecStartPost`/`ExecStopPost` resolve hooks read the same clan vars path through `NTFY_TOKEN_FILE`.

- The resolve hooks run as `+` inside each notified unit, where `$CREDENTIALS_DIRECTORY` belongs to that unit, so they cannot use the template's credential (`s3brief.md:125`; `ntfy-grounding.md:65`).

### D4. Notifier extraction

Options (`s3brief.md:119-122`): pull the notifier out into its own NixOS module and import it on cinnabar; add cinnabar to the agent role early, which needs S4's exporter-by-role change; have the dead-man post its own failure.

Decision: the notifier moves out of the collector's agent role into `flake.modules.nixos.observability-notify`, with `services.observability-notify.units` unchanged; the agent role imports it, and cinnabar imports it in S3 so the dead-man's `OnFailure=` has a notifier.
No collector runs on cinnabar before S4.

- S1's review suggested the extraction (`review.md:80`), and it keeps one notifier rather than a second failure path in the dead-man.

### D5. Cutover order

Options (`ntfy-grounding.md:83`): one deploy that turns on access control and gives magnetite's notifier the token together, or the token first and access control second.

Decision: three deploys, ordered so that no post is refused at any point.

1. cinnabar provisions `alerter` and its token through `NTFY_AUTH_USERS` and `NTFY_AUTH_TOKENS`, with no access entries, so anonymous and token-bearing posts are both accepted.
2. magnetite deploys the token-bearing notifier and evaluator.
3. cinnabar adds `auth-access` (`alerter:fleet-*:rw`, `*:fleet-*:ro`), and R9.4's anonymous-publish probe confirms that an anonymous publish to `fleet-*` is refused.

- The single deploy was rejected because magnetite and cinnabar cannot switch at the same instant, and any anonymous post between them gets 403, which fails `curl -f`, leaves `failed` without a stamp and keeps `resolved`'s stamp (`ntfy-grounding.md:65`).
- Amended on 2026-10-18 after the first acceptance, which ordered two deploys with magnetite first.
  ntfy 2.28.0 answers a token it does not know with 401 even where anonymous access is allowed (`server/server_auth.go:45-50` at the pin), so under that order every token-bearing post from magnetite would have been refused until cinnabar provisioned `alerter`.
  Provisioning the user and token before any sender carries the token removes that window, and adding the access entries last removes the 403 window.

### D6. Provisioning safety

The grounding found that a missing or malformed `environmentFile` stops ntfy, taking every hook publisher down with it (`ntfy-grounding.md:67,84-87`).
Options: accept failing closed, move `auth-access` into the env file so a missing file means no access rules, or check the file before deploy.

Decision: a flake check validates the rendered `NTFY_AUTH_*` strings before deploy: the token matches `^tk_[-_A-Za-z0-9]{29}$`, the hash has bcrypt's shape, and every access entry's user is provisioned.
The residual risk that nothing reports an ntfy outage is recorded against CAM-76, ADR-009 Q5's external watcher.

### D7. Rule scope

Options (`s3brief.md:111-114`): ship only the S1-backed rules; ship all rules with empty expected-host lists; add a filesystem scraper in S3, which reaches into ADR-003 and ADR-004.

Decision: S3 ships only rules whose signals S1 already stores in `fleet`; the filesystem, NVMe, launchd and probe-staleness rules land with S4 and S5.

- This matches the sequencing text, "the rules whose signals S1 provides" (`reference-architecture.md:252`).
- At S3 the shipped table rules are `HostMemoryPressure`, `HostOOMKill`, `ZfsPoolUnhealthy`, `SystemdUnitRestartLoop`, `SystemdUnitFailed`, `LocalExporterDown` and `WeeklyPipelineTest`, plus the evaluator's `StoreQueryFailing` and `RuleSignalMissing` and the dead-man's `AlertEvaluatorSilent` (`s3brief.md:148-165`).

### D8. Dev-loop SLO burn rule

Options (`s3brief.md:115-118`): drop it from the sequencing, define it now with a charter entry amending ADR-009 item 15, or defer it.

Decision: it lands in S2.
The sequencing says "with the later of S2 and S3", and S2 is the later slice; no ADR changes.

### D9. R9.1 counting

A stamp is removed on resolve, and `last-failed` holds only the latest epoch per unit, so counting FIRINGs over 24 h from S1's stamps undercounts (`s3brief.md:127-130`).
Options: append a log of posted `FAILED` events, count open stamps plus the latest `last-failed`, or accept the undercount.

Decision: the notifier appends each posted `FAILED` (timestamp, unit, host) to a log under `/var/lib/observability-notify`, and R9.1 counts that log over 24 h together with the evaluator's own FIRING state.

- S1's design said S3 would not rewrite the template (`design.md:271`); D4 already moves the notifier, and the log is a one-line append.

### D10. `SystemdUnitFailed` duplicates

ADR-009's regex (`ADR-009-alerting.md:96`) does not exclude `greptimedb.service` or `opentelemetry-collector.service`, which S1's notifier already reports, so their failures would arrive twice (`s3brief.md:131`).

Decision: the rule's exclusion list derives from `services.observability-notify.units`, the single source, and ADR-009's `SystemdUnitFailed` rule text is amended to say so.

### D11. State-machine verification

Options (`s3brief.md:137-141`): R9.2's mutants alone, as ADR-009 states; a Lean specification with the evaluator checked against it; a property-based fixture generator.
The repository records no intent to place a formal specification in S3 (`s3brief.md:104-108`).

Decision: the evaluator's per-instance transition function is a pure jq function, and a property-based check runs beside R9.2's fixture mutants.
Hypothesis generates query timelines and compares the jq function against a small Python reference model of pending, firing and resolved, the store freeze, the host freeze and the re-post cadence.
A Lean refinement was offered and not chosen.

## Rules adopted from the S1 retrospective

The §6 rules of S1's retrospective apply to S3's planning (`retrospective.md:130-181`; `decisions.md:17`):

- Read the vendor source before disabling or depending on an option; the D1 and D5 amendments both came from this.
- Plan the start order between units, such as the evaluator against the store and the dead-man against ntfy.
- A check compares independently defined values, never a module's own literal; a property of one module's own settings, such as R9.5, is an assertion in that module.
- Each new check states an evaluation-cost budget.
- Every runtime regulator clause gets a negative control.
- Format before every commit.
- Operator documentation, the README and runbook, is a planned task.
- Each rule is checked against the later slices that touch the same objects, here S2's SLO rule and the S4 and S5 rules.
- Notifier and regulator semantics are tested across restart and cache-fill states, including a crash-loop case and a long-running case (`retrospective.md:172-174`).

## Left for design

- Evaluator unit settings: `OOMScoreAdjust` relative to the store's 500 and the collector's 300; whether the evaluator runs as a `DynamicUser`; and the query fan-out for the S3 rules, their presence selectors and attribution queries against the store's `max_concurrent_queries = 8` inside `TimeoutStartSec = 50s` at a 10 s per-query timeout (`s3brief.md:136`).
- `WeeklyPipelineTest`'s "local time": magnetite sets no `time.timeZone` (only darwin and pyrite set `America/New_York`), so whether the window is 09:00 UTC or 09:00 in the operator's zone, and whether the evaluator or the rule table converts it.
- Exact label names: `up{job=…}` and `systemd_unit_state`'s active-state label are unverified (`s3brief.md:132-135`); a parallel task is querying them live.
- Which of D5's three deploys carries each remaining cinnabar change: the D1 proxy settings, the notifier import and the dead-man; R9.4's probe fails while anonymous publishing to `fleet-*` is still open, so the dead-man cannot be enabled before the third deploy.
