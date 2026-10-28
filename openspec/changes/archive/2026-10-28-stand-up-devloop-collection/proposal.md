---
linear_story_id: CAM-69
linear_story_identifier: CAM-69
linear_story_title: "S2: Collect dev-loop signals into the devloop database"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-69/s2-collect-dev-loop-signals-into-the-devloop-database
linear_story_state: Done
linear_team: CAM
linear_project: fleet-observability
last_synced_state: Done
last_synced_at: 2026-10-28T23:49:16Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-10-21T17:20:48Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; description seeded from this proposal" }
  - { at: "2026-10-22T00:13:34Z", transition: "Todo->In Progress", outcome: "posted", note: "first - [x] in tasks.md (1.1-1.5)" }
  - { at: "2026-10-28T23:37:44Z", transition: "In Progress->In Review", outcome: "posted", note: "T3 verify.md created, PASS WITH WARNINGS" }
  - { at: "2026-10-28T23:49:16Z", transition: "In Review->Done", outcome: "posted", note: "T4 archived; specs synced and mirrored to the Fleet observability project documents" }
---

## Why

CI outcomes, merge-queue batches and deploys leave no history beyond nixbot's 90-day prune and the rotated journal, so ADR-005's decision rules can only be computed by hand, as the 2026-09-02 audit was.
The store and the evaluator are deployed, and the dev loop is the primary consumer of the observability design.
This change copies nixbot's attribute outcomes and build timing, gitea-mq's batch events and a deploy record into `devloop` on magnetite, proves the copy complete every day, and alerts when PR builds wait too long for CI.

## What Changes

**Dev-loop collection on magnetite**
- The collector reads nixbot's `build_attributes` and `builds` through two `sqlquery` queries, authenticated by peer with no credential, polling every 60 s with a five-minute overlap and no index added to nixbot's database (D6, D15).
- It parses the five gitea-mq messages `batch formed`, `batch built`, `batch landed`, `batch bisecting` and `batch done` from the journal with `key_value_parser`, and drops each journal message body after parsing (D3, D10).
- Rows reach `devloop` through `logs/*` pipelines on the existing ingress routing (D4), into tables whose layout follows a container spike on deduplication and table creation (D5).
- Every column is taken from one `devloop` allow-list, which renders the queries' SELECT lists and the parser's keep-list (D3).
- The collector gains journal read; `abandoned` is derived from the marker shared with the nixbot patch.

**A deploy record on all ten machines**
- An activation snippet on all ten machines appends `{host, closure, previous_closure, ts}` to `/var/log/deploy-record.jsonl`; only magnetite ships its records until S4 and S5 (D9, D12).
- Commits are attributed by joining the closure against CI `outputs.out`, not recorded in the deploy record.

**Queries the dev loop can ask**
- Batch formation-to-land and the CI queue wait of PR builds replace CAM-69's enqueue-to-land latency (D7).
- Per-build CI outcome excludes flaky attributes, one `drv_path` with differing outcomes in the window, and abandoned attributes, computed at query time (D8).

**The dev-loop SLO burn rule**
- A 24 h slow-burn rule at severity `warning` fires when more than 10% of PR builds in the trailing day waited over 1 h to start, above a minimum build count (D1).
- Each rule in the rule table declares `database` and `language`; SQL rules are sent to `/v1/sql`, only PromQL rules are rendered for `promtool`, and the fixture server answers both and gains a leg that queries both databases (D2, absorbing S3's F10).

**Regulators**
- `devloop-reconcile`, a daily timer running as its own `DynamicUser` with a peer-authenticated nixbot role, journal read and the `regulator` store account, counts each signal on both sides over a closed 24 h window and fails on any difference, notifying through `observability-notify` (D11).
- `checks.x86_64-linux.devloop-queries` applies nixbot's migrations in lexical order, falling back to nixbot's migrator, and runs the export queries against fixtures with a renamed-column mutant; it also holds the abandonment marker against the patch's production code with embedded negative controls, so no separate `devloop-signals` check is created before S7 (D14, D15).
- Deploy-record presence is an obligation in `modules/checks/machines.nix`, evaluated with each machine's toplevel, which CI holds on the five x86_64-linux NixOS machines; the four darwin machines and `scheelite` are shown carrying the snippet once by evaluation (D12).
- `devloop-ingest` is an on-demand nspawn container test on magnetite carrying the reconcile, parser and deploy-record mutants (D13).

**Decision records amended through a charter version entry**
- From: S1 to S5 are metrics-only with no logs pipeline (CH:272, RA:245); "any OTLP log record" is never stored (A4:107); gitea-mq lines beginning `batch ` are admitted (A4:58); no CI or merge-queue rule is in the initial alert set (A9 item 15); `devloop-ingest` is a QEMU VM test because no container-test pattern exists (A5:157-160, A5 Q13); ADR-005's envelopes are unnumbered and its upstream lines cite pre-pin revisions.
- To: a non-content `devloop` logs path is admitted in S2 through an explicit allow-list with no message bodies; the five exact batch messages are admitted; the dev-loop SLO burn rule is the one dev-loop alert; `devloop-ingest` is an nspawn container test on magnetite; ADR-005's envelopes are E5.1 to E5.6, and upstream lines are cited at gitea-mq `02264515` and nixbot `b1f69980`.
- Reason: every S2 signal is a log row, the prefix match admits four unrelated messages, the charter scheduled the burn rule in S2 without defining it, and S1 established the container-test pattern on magnetite.
- Impact: non-breaking; documentation only, with S7 still bringing the content stages for content-bearing pipelines.

**Linear story corrected**
- CAM-69's reader credential becomes peer authentication, its enqueue-to-land latency becomes batch formation-to-land plus CI queue wait, its flaky exclusion is defined as in D8, and its deploy record drops "commit and outcome" (D6 to D9).

## Capabilities

### New Capabilities
- `devloop-collection` (stratum: `behavioral`): what the fleet requires of the dev-loop record — that every finished CI attribute, every finished build, every merge-queue batch event and every deploy on a collected host is recorded once in the dev-loop history and kept for its retention; that a gap in the copy is reported within a day; that no CI error text, journal message body or other free text enters the history; that batch formation-to-land, CI queue wait and per-build outcome excluding flaky and abandoned attributes can be asked of the past week; and that a deploy can be attributed to the commits that built its closure.
- `devloop-collection-interface` (stratum: `interface`): the properties at the machine's interface that discharge it — the two nixbot queries, their columns, cursor, overlap and poll interval, and peer authentication; the journald unit, the five matched messages and the parsed keys; the deploy-record file and its fields; the `devloop` tables, their keys and time index, and the unit that creates them; the `logs/*` routes; the allow-list; `devloop-reconcile`'s identity, roles, window and comparisons; and the `devloop-queries`, machine-obligation and `devloop-ingest` regulators with their mutants.
  Trust boundary: nixbot and gitea-mq produce the source rows and journal lines, and this machine only reads them, so a source that never records an event is not detected; nixbot's schema and gitea-mq's messages are trusted at the pinned revisions; PostgreSQL's peer rule and systemd's journal group grant the reads; any root process on magnetite can read the `regulator` password and the deploy-record file; hosts other than magnetite write records that no collector ships until S4 and S5; nothing here guarantees that a row reaches the store end to end, only that each stage's configuration, the gating checks, the container test and the daily reconcile behave as stated.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): new assumptions record nixbot's schema as created by its migrations at `b1f69980`, gitea-mq's five batch messages and their keys at `02264515`, PostgreSQL's default peer rule, and GreptimeDB's deduplication behaviour as the spike finds it; the designation table gains the terms the new behavioral requirements use and the rows S1's and S3's `verify.md` §8a propose.
- `telemetry-store-interface` (stratum: `interface`): `Ingest is OTLP over HTTP with a database header` admits `logs/*` pipelines into `devloop` and still forbids traces; `Databases and their retention are set at the telemetry store` replaces "no logs table" with the `devloop` tables S2 declares; `Credentials exist only as activation-resolved files owned by non-worker users` admits `devloop-reconcile` as a `regulator-password` holder; and `Failure notices are posted to one topic` adds `devloop-reconcile.service` to the units with `OnFailure=`.
- `host-metrics-collection` (stratum: `behavioral`): `magnetite contributes its own signals to the telemetry store` narrows "SHALL write no log records" to the `fleet` database, because the dev-loop rows are `devloop-collection`'s.
- `fleet-alerting` (stratum: `behavioral`): a new requirement that PR builds waiting too long for CI reach a person as a warning, beside `Each known failure class on a host reaches a person as an alert`, whose classes are per host.
- `fleet-alerting-interface` (stratum: `interface`): the evaluator's query requirement takes each rule's `database` and `language`, with SQL over `/v1/sql`; the rule-rendering requirement renders only PromQL rules to `promtool`; and the fixture server accepts both databases and both paths.

`telemetry-store`'s `Only the collector writes and only named readers read` is unchanged, because the collector remains the only writer and `devloop-reconcile` reads as the existing regulators' account.

## Impact

- New: `modules/nixos/devloop-collection.nix`, `modules/system/deploy-record.nix` (NixOS and darwin), `modules/checks/devloop-queries.nix` and `modules/vm-tests/devloop-ingest.nix`.
- Changed: the collector's ingress role (`logs/*` routes), `schema.nix` (the `devloop` tables or pipelines and the allow-list), `modules/nixos/fleet-alert.nix`, `modules/nixos/fleet-alert/rules.nix` and `modules/checks/fleet-alert.nix` (per-rule database and language, `/v1/sql`, the burn rule), `modules/checks/machines.nix` (deploy-record obligation), `modules/checks/otel-collector-config.nix` (failure wiring), `modules/machines/nixos/magnetite/default.nix` (import, credential holder, notified units), and the machine aggregates that import the deploy record on all ten machines.
- Documentation: the charter version entry carrying the amendments to CH:272, RA:245, A4:58, A4:107, ADR-005 (E5.1 to E5.6, the deploy-record regulator, the Q13 premise, the re-cited upstream lines) and ADR-009 item 15; the `telemetry-store-interface` and `fleet-alerting-interface` specs at sync; the `devloop-exporters` component; and the operator page on querying `devloop`.
- New secrets: none; both readers of nixbot's database authenticate by peer, and `devloop-reconcile` loads the existing `regulator-password`.
- Deployment: `clan machines update magnetite`, then each other machine at its next routine update; the spike precedes the table layout, and the nixbot scan is measured with `EXPLAIN ANALYZE` at deploy.
- Residual risk: the reconcile job samples one host of ten for the deploy record, and the other nine are covered at build time only (A5:154).
- Out of scope, each in a later slice: deploy records shipped from other hosts (S4, S5), dashboards over `devloop` (S6), the omp emitter and `fleet` journald logs (S7), and the Parquet export of `devloop` (S8).
