# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `stand-up-greptimedb-on-magnetite`
**Verified at**: `2026-10-17 10:07 UTC`
**Verifier**: `S1Task7Verify (agent), running plan.md Task 7 Steps 1–10 except Step 7`

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items report `"valid": true`

**Result**:

```text
items 33, passed 33, failed 0; change 18 of 18 passed; spec 15 of 15 passed
{"totals":{"items":33,"passed":33,"failed":0},"byType":{"change":{"items":18,"passed":18,"failed":0},"spec":{"items":15,"passed":15,"failed":0}}}
```

`openspec validate stand-up-greptimedb-on-magnetite --strict` prints `Change 'stand-up-greptimedb-on-magnetite' is valid`.
Repository-wide, `openspec validate --all --json --strict` fails 30 of 33 items, because `--strict` promotes warnings in other changes and in main specs (164 requirement-length warnings, 10 placeholder Purpose sections), including the main `world-assumptions` spec; this change passes under it.

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | — |

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]`

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

Task 7 ticked 7.1, 8.4, 8.5, 8.6 and 9.1; Tasks 1–5 had ticked the rest, and Task 2 ticked 8.1–8.3.
After the ticks, `rg -n '^- \[ \]' openspec/changes/stand-up-greptimedb-on-magnetite/tasks.md` prints nothing.
8.5 is ticked because every item its wording lists has evidence in §9.4.
Its wording does not include the dashboard.
The authenticated dashboard check, Task 6 Step 15's `[operator]` line in `8.5-dashboard.log`, was made by the operator on 2026-10-17 and is recorded in §9.4.

---

## 3. Delta Spec Sync State

For each delta spec file reported by the CLI
(`openspec status --change "stand-up-greptimedb-on-magnetite" --json | jq -r '.artifactPaths.specs.existingOutputPaths[]'`),
compare against the corresponding main capability spec:

| Capability | Sync status | Notes |
|---|---|---|
| `host-metrics-collection` | pending sync | New capability; `openspec/specs/host-metrics-collection/` does not exist yet. |
| `telemetry-store` | pending sync | New capability; `openspec/specs/telemetry-store/` does not exist yet. |
| `telemetry-store-interface` | pending sync | New capability; `openspec/specs/telemetry-store-interface/` does not exist yet. |
| `world-assumptions` | pending sync | Adds A29–A33 and modifies `Grounded vocabulary for behavioral requirements`; the main spec has no A29–A33 and still reads "Twelve terms carry two senses" (`openspec/specs/world-assumptions/spec.md:96`). |

All four sync at archive.

---

## 4. Design / Specs Coherence Spot Check

Spot-check whether the decisions in `design.md` are reflected in the Requirements and
Scenarios of `specs/*.md`:

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D3 | `greptimedb.service` as static user `greptimedb` with `MemoryHigh = "3G"`, `MemoryMax = "4G"`, `MemorySwapMax = "0"`, `OOMScoreAdjust = 500`, `CPUWeight = 20`, `global_rt_size = 4`, `compact_rt_size = 2`; the `loaded-users.sha256` `ExecStartPre` | `telemetry-store` "The telemetry store stays inside a memory envelope that leaves build capacity to the build service" (4 GiB, throttled before it, out of compressed swap, reduced processor share, fixed parallelism, kill order); `telemetry-store-interface` "The telemetry store and the collector run inside a declared envelope" (same values) and "The account file the telemetry store loaded is recorded" | none |
| D4 | HTTP `127.0.0.1:4000`, gRPC `127.0.0.1:4001` with a `127.0.0.0/8` assertion, five protocols disabled, no firewall port, Prometheus remote read and write kept for the PromQL API (charter v13), credentials on every `/v1/` path | `telemetry-store-interface` "Listeners are bound to loopback only", "Prometheus remote storage stays enabled for the PromQL query API", "Store accounts carry fixed permission modes" | none |
| D6 | hex passwords, exactly four `<user>:<mode>=<hex>` lines, `greptimedb-r2` prompts, values only as activation-resolved files, restart on rotation, R7.4 hash comparison | `telemetry-store-interface` "Store accounts carry fixed permission modes", "Credentials exist only as activation-resolved files owned by non-worker users", "The account file the telemetry store loaded is recorded"; `telemetry-store` "A replaced store credential takes effect on the running telemetry store" | none |
| D10 | `observability-notify@.service` in the `agent` role, `ntfy-send`, topic `fleet-alerts` at `https://ntfy.zt`, anonymous, one post per episode, `RESOLVED` on recovery | `telemetry-store-interface` "Failure notices are posted to one topic" (template, single package, topic, no credential, `OnFailure=` on the store, schema, envelope, collector and nine ZFS oneshots); `telemetry-store` "The telemetry store's own failures reach a person"; `host-metrics-collection` "A failed collection or store job notifies a person"; A33 | none |
| D12 | hourly `greptimedb-envelope` asserting R6.2, R6.3, R6.4 readiness, R7.2 keyed by `InvocationID`, R7.3, R7.4, no per-table TTL; empty result or missing table is failure | `telemetry-store-interface` "Runtime regulators treat absent evidence as failure" and the envelope requirement's hourly scenario; `telemetry-store` disk-envelope and retention requirements name the hourly regulator's cases | none |

**Drift warnings** (non-blocking):

- none

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree
- [x] All related commits have been pushed

The implementation landed as seven commits on `origin/main`, listed by Step 6's path-filtered `git log` (§10.5): `f9451f3ef`, `76694545b`, `57f138866`, `cebb618c8`, `9a0aa6ccb` (PR #3490), `22fd7cead` and `7f5fbad47` (PR #3492).
`git status --porcelain` printed nothing before this file and the `tasks.md` ticks were written; those two files are the change Task 7 commits.

**Commit range** (if known): `3c726cccfff173b68521aa2ac335a121c816753f..7f5fbad4778b684000e042f829f0d9756d379820`, filtered to the S1 paths; the unfiltered range also holds 47 unrelated commits.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

Design output should not land in `docs/superpowers/specs/` (the brainstorm artifact's
output redirection routes it to the change's resolved brainstorm.md — the `brainstorm`
entry in `artifactPaths` from `openspec status --change "stand-up-greptimedb-on-magnetite" --json`).

Detect:

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files, or any existing files are legitimate residue from before schema installation

The command printed nothing and exited 2, because the glob matched no file.

**Leak list** (if any):

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

> Does not block archive. Leaks produced by a new schema-installed cycle should be moved into
> the change's brainstorm.md (resolved via `artifactPaths.brainstorm`) or `design.md`, then the
> original file deleted.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no row marked `[~]`, so this section is blank by the template's rule.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| — | — | — | — |

---

## 8. Designation lint and discharge coherence

This section is agent-executed and non-blocking.
`openspec validate` checks markdown structure and delta well-formedness only; nothing here is validation.
The designation table used is the one this change's `world-assumptions` delta carries (the MODIFIED `Grounded vocabulary for behavioral requirements`), because the main spec's table lacks the telemetry terms until sync.

### 8a. Designation lint

The proposal tags `telemetry-store` and `host-metrics-collection` `behavioral`.
A lexer pass over their requirement statements, excluding scenarios and `Discharged by` lines, leaves these content nouns without a row:

| Noun | Requirement | Disposition proposed |
|---|---|---|
| service | `magnetite contributes its own signals to the telemetry store` ("the services on magnetite") | designation table: shared |
| source | same ("gathering each from a source on magnetite itself") | designation table: shared |
| log record, trace | same ("no log records and no traces") | designation table: shared, as the two non-series telemetry kinds |
| memory, out-of-memory (as signals) | same | designation table, or read as instances of the existing `signal` row |
| host's name | `Each stored series names its host` | designation table: a second sense distinct from the existing `hostname` row (the public name a person reaches a service at) |
| identifier, process number, command line | `Series cardinality stays bounded` | interface stratum: these are collector attributes |
| memory floor, collector stage | same | interface stratum: the 64 MiB filter and the pipeline stages are machine phenomena |
| slice | same ("regulated at runtime from slice S4") | neither: a planning term; the requirement could drop it |
| gap | `Collection survives a telemetry store restart without losing the queued interval` | designation table: shared |
| Omnigent worker, person, alias | `Stored unit names carry no owner's name` | designation table: `person` world-only, `alias` shared; `Omnigent worker` as a sense of `unit` |
| notifier, credential (for the notification service) | `A failed collection or store job notifies a person` | designation table: `notifier` shared; `credential` needs a sense distinct from `store credential` |
| part of a database | `A database keeps its series for its retention and no longer` | designation table: shared (a table) |
| throttle, parallelism | `The telemetry store stays inside a memory envelope that leaves build capacity to the build service` | interface stratum: `MemoryHigh` and the runtime pool sizes |
| local state, object data | `The telemetry store stays inside a disk envelope of its own` | designation table: shared; `object data` against the existing `object storage` row |
| build (the vendor's published build) | `The telemetry store runs a stable vendor release that serves its dashboard` | designation table: a sense distinct from `build service` |

Every other content noun resolves to a row, including the thirteen double-sense terms as used here (`host` fleet sense, `database` telemetry sense, `package` nix sense in "the channel's package").
Each row above is a finding for the retrospective's Promote section, not a rewrite applied here.

### 8b. Discharge coherence

Each behavioral requirement's `Discharged by` line names its interface requirements and world assumptions; each `tasks.md` `Discharges:` clause names the requirements that task discharges.

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| host-metrics-collection: magnetite contributes its own signals to the telemetry store | `Ingest is OTLP over HTTP with a database header`; `Scrape targets are reached on loopback`; `The collector's configuration bounds what it gathers` (tasks 3.2) | — | discharged |
| host-metrics-collection: Each stored series names its host | `Ingest is OTLP over HTTP with a database header`; `Reads are PromQL and SQL over HTTP with a database header`; `Prometheus remote storage stays enabled for the PromQL query API` (tasks 3.2, 8.5) | — | discharged |
| host-metrics-collection: Series cardinality stays bounded | `The collector's configuration bounds what it gathers` (tasks 3.1, 8.5) | — | discharged |
| host-metrics-collection: Collection survives a telemetry store restart without losing the queued interval | `The collector's queue persists across a telemetry store restart` (tasks 6.1, 8.5, 9.1) | — | discharged |
| host-metrics-collection: Stored unit names carry no owner's name | `Omnigent unit names are stored under aliases` (tasks 3.1, 4.4, 6.1, 9.1) | — | discharged |
| host-metrics-collection: A failed collection or store job notifies a person | `Failure notices are posted to one topic` (tasks 3.4, 3.5, 4.4) | A33 | discharged |
| telemetry-store: A database keeps its series for its retention and no longer | `Databases and their retention are set at the telemetry store`; `Object data lives under one prefix of one bucket` (task 2.6) | A29 | discharged |
| telemetry-store: Only the collector writes and only named readers read | `Store accounts carry fixed permission modes`; `Listeners are bound to loopback only`; `Credentials exist only as activation-resolved files owned by non-worker users` (task 4.3) | — | discharged |
| telemetry-store: A replaced store credential takes effect on the running telemetry store | `Credentials exist only as activation-resolved files owned by non-worker users`; `The account file the telemetry store loaded is recorded` (task 2.4) | — | discharged |
| telemetry-store: The telemetry store stays inside a memory envelope that leaves build capacity to the build service | `The telemetry store and the collector run inside a declared envelope` (tasks 2.2, 6.2) | A31, A32 | discharged |
| telemetry-store: The telemetry store stays inside a disk envelope of its own | `The telemetry store and the collector run inside a declared envelope` (tasks 2.3, 8.5) | — | discharged |
| telemetry-store: The telemetry store sends no usage report to its vendor | `The telemetry store's release and usage reporting are fixed at evaluation` (task 2.1) | — | discharged |
| telemetry-store: The telemetry store runs a stable vendor release that serves its dashboard | `The telemetry store's release and usage reporting are fixed at evaluation` (tasks 1.1, 6.1) | A30 | discharged |
| telemetry-store: The telemetry store's own failures reach a person | `Failure notices are posted to one topic` (tasks 3.4, 3.5, 8.6) | A33 | discharged |
| telemetry-store-interface: Listeners are bound to loopback only | R7.1 in `greptimedb-envelope` check (tasks 2.1, 4.1) | — | discharged |
| telemetry-store-interface: Prometheus remote storage stays enabled for the PromQL query API | task 2.1; the pipeline container test's PromQL cases | — | discharged |
| telemetry-store-interface: Scrape targets are reached on loopback | R3.1 (tasks 3.3, 3.7, 4.4) | — | discharged |
| telemetry-store-interface: Store accounts carry fixed permission modes | users-file check and R8.2 (tasks 2.4, 4.3); auth matrix (task 6.1) | — | discharged |
| telemetry-store-interface: Ingest is OTLP over HTTP with a database header | R3.1, R1.2 (tasks 3.2, 4.4); ingest case (task 6.1) | — | discharged |
| telemetry-store-interface: Reads are PromQL and SQL over HTTP with a database header | read-back case (task 6.1) | — | discharged |
| telemetry-store-interface: Databases and their retention are set at the telemetry store | schema oneshot (task 2.6); retention cases (task 6.1) | — | discharged |
| telemetry-store-interface: Object data lives under one prefix of one bucket | R6.4 storage clause (tasks 2.1, 2.5, 4.3); R6.3 (task 5.1) | A29 | discharged |
| telemetry-store-interface: Credentials exist only as activation-resolved files owned by non-worker users | R8.2 with its mutants (tasks 2.4, 4.3) | — | discharged |
| telemetry-store-interface: The account file the telemetry store loaded is recorded | the `ExecStartPre` hash (task 2.2) and R7.4 (task 5.1) | — | discharged; no `Discharges:` clause names it by title, task 5.1 names it as R7.4 |
| telemetry-store-interface: The telemetry store and the collector run inside a declared envelope | R7.1 with seven mutants (tasks 2.2, 4.1); R7.2, R7.3 (task 5.1); kill order (task 6.2) | A31, A32 | discharged |
| telemetry-store-interface: Runtime regulators treat absent evidence as failure | renamed-table mutant (tasks 5.1, 5.2) | — | discharged |
| telemetry-store-interface: The telemetry store's release and usage reporting are fixed at evaluation | R1.1 amended, R1.4 with mutants (task 4.2) | A30 | discharged |
| telemetry-store-interface: The collector's configuration bounds what it gathers | R3.1 process and systemd clauses (tasks 3.2, 4.4) | — | discharged |
| telemetry-store-interface: Omnigent unit names are stored under aliases | R3.1 alias clause (task 4.4); alias read-back (task 6.1) | — | discharged |
| telemetry-store-interface: The collector's queue persists across a telemetry store restart | R3.1 queue clause (tasks 3.2, 4.4); restart case (task 6.1) | — | discharged |
| telemetry-store-interface: Failure notices are posted to one topic | R3.1 failure-wiring clause (tasks 3.4, 3.5, 4.4); forced failure (task 8.6) | A33 | discharged |
| telemetry-store-interface: This capability states its own trust boundary | the requirement's own statement; no regulator applies | — | discharged by statement |
| world-assumptions: A29 | world assumption, not discharged by S; monitored by first activation (§9.4 R2) and R6.4's readiness probe | — | assumption, holding at first activation |
| world-assumptions: A30 | world assumption; R1.1 accepts the channel's package once it declares the dashboard | — | assumption, holding |
| world-assumptions: A31 | world assumption; R7.2 hourly | — | assumption, holding |
| world-assumptions: A32 | world assumption; kill-order test on pyrite (task 6.2) | — | assumption, holding |
| world-assumptions: A33 | world assumption; forced failure delivered at first activation (§9.5) | — | assumption, holding |
| world-assumptions: Grounded vocabulary for behavioral requirements (MODIFIED) | the designation table in the delta | — | discharged, with the unresolved nouns of 8a |

No ADDED or MODIFIED requirement is undischarged.

### 8c. Alphabet check

`Series cardinality stays bounded`, a behavioral requirement, names two non-world phenomena in its second sentence: "no stage of the pinned collector" (a machine phenomenon) and "slice S4" (a planning term).
`The telemetry store stays inside a memory envelope that leaves build capacity to the build service` states "throttled" and "fixed parallelism", which are `MemoryHigh` and the runtime pool sizes phrased in world terms; this is recorded, not counted as a violation.
No interface requirement references world state the machine cannot observe: `This capability states its own trust boundary` names R2 durability, root processes and notice delivery only to disclaim them.

---

## 9. Deployment record

Sections 9 and 10 are the evidence ledger that `tasks.md` 8.3–8.6 and 9.1 require this file to hold.
`[operator]` marks an observation only the operator could make; every other entry gives the command and its output.

Before pasting, `rg -n '[0-9a-f]{32,}' logs/s1-evidence/*.log` was run.
Among the logs pasted here it matched the two sha256 lines of `8.4-users-hash.log`, which are public, and three other kinds of value, none a credential: the R2 account endpoint in `8.4-paths.log`, which the repository already holds (`modules/home/tools/awscli.nix:17`); systemd `Invocation:` ids in `8.4-units.log`, `8.6-forced-failure.log`, `8.6-resolved.log` and `9.1-envelope-scheduled.log`; and nix store hashes.
The plan expected only the sha256 lines; the extra matches are recorded here rather than redacted.

### 9.1 Dataset created by hand (tasks.md 8.3)

`8.3-zfs-create.log`:

```text
NAME                   MOUNTPOINT           QUOTA  RESERV  COM.SUN:AUTO-SNAPSHOT
zroot/root/greptimedb  /var/lib/greptimedb   none    none  false
```

### 9.2 Charter v11 amendments present (tasks.md 7.1)

`7.1-charter-v11.log`:

```text
$ rg -n "v11" charter.md
274:- v11 (2026-10-16): amendments carried by slice S1 (`openspec/changes/stand-up-greptimedb-on-magnetite/`); no earlier text is edited beyond the status and version lines, and D1–D9, the requirements and the acceptance criteria are unchanged.
$ rg -n "v1\.3\.0-alpha\.1" decisions/ADR-002-dashboard-layer.md research
research/perses.md:216:R39 That API first appears in GreptimeDB `v1.3.0-alpha.1`; the latest stable GreptimeDB tag `v1.2.1` does not have it, and `v1.3.0-beta.2` is the newest prerelease (2026-10-15).
research/nix-packaging-status.md:176:R17 Tagged releases and scheduled nightlies carry darwin assets, but the manually dispatched `v1.3.0-alpha.1-…-20260928` and `v1.4.0-alpha.0-…-20261007` builds carry only Linux and Android assets, which is the conditional macOS job of F16 observed in practice (https://api.github.com/repos/GreptimeTeam/greptimedb/releases, fetched 2026-10-15; `GreptimeTeam/greptimedb@179ff8e50:.github/workflows/release.yml:248`).
research/otel-collector-topology.md:318:The bearer branch exists only from v1.3.0-alpha.1 onward (`GreptimeTeam/greptimedb@4859e57e0:src/servers/src/http/authorize.rs:83-87`), and even there it calls `UserProvider::authenticate_bearer_token`, whose default implementation fails with an unsupported-method error (`GreptimeTeam/greptimedb@4859e57e0:src/auth/src/user_provider.rs:90-95`) and which neither in-tree provider, `static_user_provider` nor `watch_file_user_provider`, overrides.
$ rg -n "embedded|percli" decisions/ADR-002-dashboard-layer.md
17:The facts about the embedded dashboard that bind this decision are these.
31:It imports Perses dashboard JSON but not Grafana JSON; the upstream skill converts a Grafana dashboard with `percli migrate --online` against a standalone Perses server (`GreptimeTeam/dashboard@7b4b275a:skills/greptimedb-perses-dashboard/reference.md:562`).
36:The root pin, lock node `nixpkgs_10` at `NixOS/nixpkgs@ac1faec4`, packages Perses and `percli` 0.54.0 with the NixOS module `services.perses` (`research/perses.md` R11, R13; `research/nix-packaging-status.md` R13).
38:`percli lint` is tautologically green without plugin schemas (charter RK8; `research/perses.md` R17, R18).
56:Standalone Perses is kept as tooling only: `percli migrate` with an ephemeral local Perses server converts Grafana community dashboards into Perses JSON, and `percli lint` against the Perses schema version the embedded dashboard runs is a flake check.
57:A deployed standalone Perses server is the fallback only if a dashboard needs a feature the embedded dashboard lacks, such as `StaticListVariable` or projects with RBAC.
67:The embedded dashboard satisfies the three D2 conditions with no service beyond the store.
69:Its definitions are Perses dashboard JSON, the format `percli lint` checks offline and the upstream dashboard skill generates (`research/perses.md` R43, R45).
72:The version before charter v11 rejected the embedded dashboard for four reasons, and each has been re-examined.
79:It buys capabilities this design does not use: projects and RBAC do not partition reads under ADR-008's shared read zone (charter RK9), and of the ten plugins the earlier decision selected, the embedded dashboard lacks only `StaticListVariable`.
80:`percli` stays useful without the server, because lint and migrate run on files.
83:`sso-gateway` admits readers, rather than a direct Kanidm client, because the embedded dashboard has no OIDC login, and the gateway module directs services without OIDC to register with it (`modules/nixos/sso-gateway.nix:288-298`); this follows web-verification D11 rather than excepting it.
89:The lint check runs against the embedded Perses version rather than the root pin's 0.54.0, because the embedded dashboard parses the stored JSON with Perses 0.53.1 and its plugin versions, and a lint against other schemas could accept a file the deployed renderer rejects or the reverse `[INFERENCE]`.
102:- A direct Kanidm OIDC client: the embedded dashboard has no OIDC login to use it.
105:- Bare `percli lint`: validates nothing beyond unmarshalling and reports success (charter RK8; `research/perses.md` R17).
106:- `percli lint --plugin.path <archive directory>`: fails closed on valid files, so it does not discriminate (`research/perses.md` R19, R20).
107:- `percli lint --online` as the gating regulator: needs a running Perses server inside the check and excludes `--custom-rule.path` (`research/perses.md` R25).
108:- MySQL or PostgreSQL wire route to the store: the embedded datasources do not use it, and it adds a second listener on the store (`research/perses.md` R31).
116:Dashboards cannot use `StaticListVariable`; a dashboard that needs it triggers the standalone-server fallback or is rewritten with the variables the embedded dashboard registers.
117:The Perses version follows the store: 0.53.1 at GreptimeDB `v1.2.1`, and 0.54.0 once a stable GreptimeDB release embeds dashboard `v0.14.2`; each store upgrade that changes the embedded dashboard version must move the lint tooling in the same commit.
119:Grafana community dashboards reach the repository only through `percli migrate --online` against a local Perses server, followed by rewriting their datasources to `promql-default` and `sql-default`.
130:| Dashboard files | Every file under the dashboard tree lints clean against the Perses version and plugin set the deployed store embeds, and against custom rules forbidding `SELECT *` and any datasource name other than `promql-default` and `sql-default`, each rule targeting a scalar (`research/perses.md` R23) | flake check `perses-lint`: `percli lint --plugin.path <extracted plugins> --custom-rule.path <rules>` over each file, with `percli` and the plugins at the versions `greptimedb-bin`'s embedded dashboard pins; deterministic, nixbot `x86_64-linux` | an enumerated mutant set built in the same derivation (empty `query`, extra field in a query spec, unknown query kind, a `StaticListVariable`, `SELECT *`, a third datasource name) each of which must exit non-zero, plus the valid set which must exit zero, so both the tautological pass of RK8 and the fail-closed archive form of R19 turn the check red |
163:- `percli` and plugin archives at the embedded dashboard's versions, for the lint check; the root pin carries `percli` 0.54.0, so the check either packages 0.53.1 or shows by its mutant legs that the root pin's tooling discriminates the same set.
183:Resolution: accepted at the 2026-10-15 gate; amended under charter v11, after both premises were found not to hold: GreptimeDB's embedded dashboard is the dashboard layer, per the Decision.
185:Resolution: recommended answer accepted at the 2026-10-15 gate; under charter v11 the embedded dashboard fixes both datasources, so the answer holds without configuration.
193:Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11, because the embedded dashboard compiles its plugins into the store binary and extracts nothing to a tmpfs.
195:Resolution: recommended answer accepted at the 2026-10-15 gate; superseded under charter v11 by Perses `Dashboard` JSON reconciled through `/v1/dashboards`, because the embedded dashboard has no resource provisioning.
$ rg -n "no .pkgs/by-name. entry|gRPC disabled|cutover" decisions components
$ rg -n "greptimedb-bin|embedsDashboard" decisions/ADR-001-store.md decisions/ADR-007-packaging-placement-and-clan-service.md components/greptimedb.md
decisions/ADR-001-store.md:8:Amended in place under charter v11 (2026-10-16): the store package is `greptimedb-bin` because its upstream release tarball embeds the dashboard ADR-002 adopts, and R1.1 requires a stable release that serves that dashboard.
decisions/ADR-001-store.md:48:The store is the open build of GreptimeDB, run as one standalone process, consumed as `greptimedb-bin`, a first-party package of the upstream release tarball under `pkgs/by-name/greptimedb-bin`, and never from a prerelease.
decisions/ADR-001-store.md:49:`greptimedb-bin` is the intended package, not a stopgap: the release tarball embeds the dashboard that ADR-002 adopts as the dashboard layer, and the package tracks stable upstream releases through its `update.sh`.
decisions/ADR-001-store.md:92:Each later version step, 1.2.1 to `v1.3`, arrives through `greptimedb-bin`'s `update.sh` and therefore through the closure operator; the derivation and its updater are first-party and ours to maintain.
decisions/ADR-001-store.md:99:Envelope E1.1, version and dashboard: the deployed store package's version is a stable `MAJOR.MINOR.PATCH` with no prerelease suffix, and the package serves the embedded dashboard; `greptimedb-bin` is the package, and `pkgs.greptimedb` qualifies only if it carries the dashboard.
decisions/ADR-001-store.md:100:Regulator R1.1, amended under charter v11: an evaluation-time assertion in the store module (ADR-007) that `cfg.package.version` matches `^[0-9]+\.[0-9]+\.[0-9]+$` and that `cfg.package.passthru.embedsDashboard` is `true`, which `greptimedb-bin` sets; it fails on two mutants enumerated in the check per the existing mutant-asserting pattern (`research/dev-loop-signals.md` F12): `package` set to an `overrideAttrs` with version `1.3.0-beta.2`, and `package` set to the pinned `pkgs.greptimedb`, which lacks `passthru.embedsDashboard`.
decisions/ADR-001-store.md:125:- `pkgs/by-name/greptimedb-bin/{package.nix,update.sh}`: the upstream release tarball for `x86_64-linux`, with `passthru.embedsDashboard = true`, and `apps.update-greptimedb-bin`; its build details are specified in ADR-007.
decisions/ADR-001-store.md:133:Q1 Deploy `v1.2.1` first? Recommended at the gate: yes, through a root-pin bump that includes https://github.com/NixOS/nixpkgs/pull/574558 (merged 2026-10-15), with `greptimedb-bin` held for a channel delay; deploying 1.1.4 first starts the store on a superseded release.
decisions/ADR-001-store.md:135:Amended under charter v11: `v1.2.1` is deployed as `greptimedb-bin`, the intended package rather than a fallback, because the nixpkgs build omits the dashboard ADR-002 adopts.
decisions/ADR-007-packaging-placement-and-clan-service.md:8:Amended in place under charter v11 (2026-10-16): the store package is `greptimedb-bin`, the intended package because its release tarball embeds the dashboard ADR-002 adopts; gRPC is bound to loopback because `v1.2.1` cannot disable it; and the `perses` credential is held by nginx rather than a Perses server; and under charter v12 (2026-10-16): R7.4 compares the sha256 of the users file the running store loaded with the deployed file's public sha256, R7.2 keeps its baseline across store restarts, R7.3 also reads the reservation, the memory-knob list gains the prefilter-result cache, and `greptimedb-bin` exists on `x86_64-linux` only, with `apps.update-greptimedb-bin` on every system; and under charter v13 (2026-10-17): Prometheus remote read and write stay enabled, because `v1.2.1` registers the PromQL query API only together with them.
decisions/ADR-007-packaging-placement-and-clan-service.md:14:ADR-001 fixes the store as GreptimeDB standalone consumed as `greptimedb-bin`, ADR-006 fixes R2 as its substrate and a daily Parquet export, ADR-003 fixes the collection topology, and ADR-002 fixes the dashboard layer as the dashboard the store itself embeds.
decisions/ADR-007-packaging-placement-and-clan-service.md:62:Packaging: the store package is `greptimedb-bin` 1.2.1, a first-party `pkgs/by-name/greptimedb-bin` package of the upstream release tarball for `x86_64-linux` only, `null` on every other system, with `passthru.embedsDashboard = true`, an `update.sh` and `apps.update-greptimedb-bin`, which exists on every system, stibnite included, and runs the update script directly, with no overlay and no second nixpkgs input.
decisions/ADR-007-packaging-placement-and-clan-service.md:91:`greptimedb-bin` is the only route that delivers the embedded dashboard with no source build: upstream builds the release tarball with `servers/dashboard` (`research/nix-packaging-status.md` R10), and the package only fetches and patches it.
decisions/ADR-007-packaging-placement-and-clan-service.md:92:Its cost is a first-party package, its updater and the `package-greptimedb-bin` flake check that every `pkgs/by-name` entry produces (`research/nix-packaging-status.md` F22).
decisions/ADR-007-packaging-placement-and-clan-service.md:180:- Add `pkgs/by-name/greptimedb-bin/{package.nix,update.sh}`: a `fetchurl` of `greptime-linux-amd64-v1.2.1.tar.gz` with its upstream sha256 on `x86_64-linux`, `null` on other systems, `autoPatchelfHook`, `mainProgram = "greptime"` and `passthru.embedsDashboard = true`, plus `apps.update-greptimedb-bin` in `modules/apps/updates.nix` on every system, running `update.sh` directly.
decisions/ADR-007-packaging-placement-and-clan-service.md:187:Q2 How is 1.2.1 taken? Recommended at the gate: through a root-pin bump that includes https://github.com/NixOS/nixpkgs/pull/574558, with a `greptimedb-bin` over the upstream checksummed 1.2.1 tarball held for a channel delay; an `overrideAttrs` to 1.2.1 is a 34-minute source build on the memory-constrained builders.
decisions/ADR-007-packaging-placement-and-clan-service.md:189:Amended under charter v11: `greptimedb-bin` is the intended package rather than a channel-delay fallback, because the nixpkgs build omits the dashboard ADR-002 adopts.
components/greptimedb.md:14:- ADR-001 Decision: the open build of GreptimeDB, standalone, consumed as `greptimedb-bin`, a first-party package of the upstream release tarball, and never from a prerelease.
components/greptimedb.md:15:- ADR-001 Decision: `greptimedb-bin` is the intended package because the tarball embeds the dashboard ADR-002 adopts; `pkgs.greptimedb` is acceptable only if it carries that dashboard.
components/greptimedb.md:17:- ADR-001 Decision and Q6: the `v1.3.x` line is adopted only when a stable `v1.3` release is published, through `greptimedb-bin`'s `update.sh`, and not through an overlay.
components/greptimedb.md:105:- Add `pkgs/by-name/greptimedb-bin/{package.nix,update.sh}`: the upstream checksummed `greptime-linux-amd64-v1.2.1.tar.gz` on `x86_64-linux` only, `null` on other systems, `autoPatchelfHook`, `mainProgram = "greptime"`, `passthru.embedsDashboard = true`, and `apps.update-greptimedb-bin` on every system, running `update.sh` directly (ADR-001 Implementation surface, ADR-007 Decision and Implementation surface).
components/greptimedb.md:125:| E1.1 version and dashboard: stable `MAJOR.MINOR.PATCH`, and the package serves the embedded dashboard; `greptimedb-bin` is the package, and `pkgs.greptimedb` qualifies only if it carries the dashboard | R1.1, amended under charter v11: evaluation-time assertion on `cfg.package.version` and `cfg.package.passthru.embedsDashboard`, with enumerated mutants an `overrideAttrs` at `1.3.0-beta.2` and the pinned `pkgs.greptimedb`; runtime case in S1's container test `vmTests.x86_64-linux.greptimedb-pipeline`: `GET http://127.0.0.1:4000/dashboard/` returns 200 | ADR-001 |
components/greptimedb.md:175:- `v1.3.x`: adopted when a stable `v1.3` release is published and `greptimedb-bin`'s `update.sh` takes it, at which point R1.2 no longer requires the collector's exponential-histogram conversion and tracks its removal; restart-on-rotation stays because `LoadCredential` snapshots credentials at start (ADR-001 Consequences, ADR-007 Q6).
$ rg -n "observability-notify" architecture/reference-architecture.md
70:  regs -->|"OnFailure observability-notify@"| ntfy
83:| magnetite | NixOS, always on, Hetzner `cx53` | `opentelemetry-collector.service` with `agent` and `ingress` roles, devloop collection (`sqlquery`, gitea-mq `journald`), loopback `prometheus-node-exporter`, `greptimedb.service` serving the embedded dashboard, `greptimedb-schema.service`, `greptimedb-export.service` and `.timer`, `greptimedb-envelope.service` and `.timer`, the nginx vhost `perses.scientistexperience.net` registered with `sso-gateway` and proxying to the store's API listener `127.0.0.1:4006`, `perses-dashboards.service`, `fleet-alert.service` and `.timer`, `otel-envelope` service and timer, `devloop-reconcile` service and timer, `observability-notify@` template, loopback nginx server `127.0.0.1:9180` for nixbot `/metrics`, deploy-record snippet | store placement and containment per ADR-007; dashboard admission through the shared `sso-gateway` Kanidm client per ADR-002 |
84:| cinnabar | NixOS, always on, Hetzner `cx43` | collector `agent`, loopback `prometheus-node-exporter`, `observability-notify@` template, `ntfy-sh` with `auth-access` and `environmentFile`, `fleet-deadman.service` and `.timer`, deploy-record snippet | ZeroTier controller and `.zt` resolver; not a store host (ADR-007 Rationale) |
85:| pyrite | NixOS, laptop, bare metal | collector `agent`, loopback `prometheus-node-exporter`, `prometheus-smartctl-exporter` on `127.0.0.1:9633` with `smartDevices = [ "/dev/nvme0" ]`, `observability-notify@` template, deploy-record snippet | KVM-capable host for the on-demand QEMU `vmTests` (ADR-005; S1's OOM-order test); silence raises nothing (ADR-009 item 16) |
86:| electrum, galena, scheelite | NixOS, cloud hosts provisioned on demand | collector `agent`, loopback `prometheus-node-exporter`, `observability-notify@` template, deploy-record snippet | silence fails R3.2 only while terranix provisions them (ADR-003 R3.2; ADR-009 item 16); `scheelite` deploys report as out-of-band under D5-R7 while its machine check stays deferred (ADR-005 Consequences) |
167:Every observability regulator and oneshot sets `OnFailure=observability-notify@%n.service`: `otel-envelope`, `devloop-reconcile`, `greptimedb-envelope`, `greptimedb-export`, `greptimedb-schema`, `fleet-alert.service`, `fleet-deadman.service`, magnetite's six existing `zfs-assert-*` and `zfs-set-*` oneshots and ADR-007's three `greptimedb` dataset oneshots (ADR-003 Q9; ADR-007 Decision; ADR-009 item 11).
168:The `observability-notify@` template lives in the collector `agent` role on every in-scope NixOS host, cinnabar included, and posts through the existing `ntfy-send` to `ntfy.zt` (ADR-003 Implementation surface).
191:| `pkgs/by-name/ntfy-send` | package | add: the existing `ntfy-send` script as a package, consumed by the home-manager command, the `observability-notify@` template and the S3 evaluator | ADR-009; ADR-003 | 1 |
196:| `modules/machines/nixos/magnetite/default.nix` | file | modify: `OnFailure=observability-notify@%n.service` on the six existing and three new dataset oneshots | ADR-007; ADR-009 | 1 |
200:| `modules/clan/services/otel-collector/flake-module.nix` | file | add: clan service `otel-collector` with roles `agent` and `ingress`, NixOS and darwin modules, `otel-envelope`, `observability-notify@` in the `agent` role, content stages, R8.2 ownership assertions | ADR-003; ADR-004; ADR-008; ADR-009 | 1, 4, 5, 7 |
246:1. S1, CAM-68: the store with its containment, dataset, users, R2 store prefix, `greptimedb-schema` and `greptimedb-envelope`, fed metrics-only by magnetite's own collector in the `ingress` role writing to the loopback store, and the `observability-notify@` template with `OnFailure=` on S1's units and magnetite's dataset oneshots, posting anonymously until S3.
```

The second search also scans `research/`, where `research/perses.md:216` (R39) keeps the superseded claim that the dashboards API first appears in `v1.3.0-alpha.1`.
Research notes are historical by decision, and ADR-002 cites R39 as superseded, so this line is a plan-expectation deviation and not an unamended claim.

### 9.3 Deployment from origin/main (tasks.md 8.4)

The first deployment ran from a fresh worktree of `origin/main` with the queue empty.
On that first deployment the collector exported before `greptimedb-schema` had created the databases and lost 279 points (`finding-collector-schema-race.log`).
PR #3492 ordered the collector `After=` and `Wants=` `greptimedb-schema.service`, with an R3.1 clause and its mutant, and magnetite was redeployed from `origin/main` `7f5fbad4`; the redeployment's queue, update tail and unit state follow the first deployment's.

`8.4-paths.log`:

```text
$ nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path
/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password
$ nix eval --raw .#nixosConfigurations.magnetite.config.clan.core.vars.generators.greptimedb-users.files.users-sha256.path
/nix/store/qnzd2ggnbbgcriadmh7rgqi5rghp43nj-per-machine-magnetite-greptimedb-users_users-sha256
$ nix eval --raw ...greptimedb-r2.files.env.path
/run/secrets/vars/per-machine/magnetite/greptimedb-r2/env
$ nix eval --json ...services.greptimedb.settings.storage
{"bucket":"sciexp","cache_capacity":"4GiB","data_home":"/var/lib/greptimedb","disable_ec2_metadata":true,"enable_virtual_host_style":false,"endpoint":"https://1ece4a9a8f092f8cbdd679d22b9ecb1f.r2.cloudflarestorage.com","region":"auto","root":"projects/vanixiets/observability/store/","type":"S3"}
```

`8.4-queue.log`:

```text
Queue is empty on https://nixbot.scientistexperience.net.
```

`8.4-clan-update.log`, last 15 lines:

```text
[magnetite] activating the configuration...
[magnetite] removing group ‘ghq’
[magnetite] removing user ‘ghq’
[magnetite] WARN: restarting or reloading systemd units from the activation script is deprecated and will be removed in NixOS 26.11.
[magnetite] reloading user units for root...
[magnetite] reloading the following user units: dbus-broker.service
[magnetite] restarting the following user units: nixos-activation.service
[magnetite] reloading user units for cameron...
[magnetite] reloading the following user units: dbus-broker.service
[magnetite] restarting the following user units: nixos-activation.service
[magnetite] restarting sysinit-reactivation.target
[magnetite] reloading the following units: dbus-broker.service
[magnetite] restarting the following units: home-manager-cameron.service, home-manager-omnigent\x2dcameron.service, home-manager-omnigent\x2djanettesmith.service, nginx.service
[magnetite] starting the following units: greptimedb.service, omnigent-host-cameron.service, omnigent-host-janettesmith.service, opentelemetry-collector.service, systemd-tmpfiles-resetup.service, zerotierone.service, zfs-assert-root-docker-noautosnap.service, zfs-assert-root-nix-noautosnap.service, zfs-assert-root-podman-noautosnap.service, zfs-set-root-home-reservation.service, zfs-set-root-nix-quota.service, zfs-set-root-nixos-reservation.service
[magnetite] the following new units were started: greptimedb-envelope.timer, greptimedb-schema.service, greptimedb.service, opentelemetry-collector.service, prometheus-node-exporter.service, zfs-assert-root-greptimedb-noautosnap.service, zfs-set-root-greptimedb-quota.service, zfs-set-root-greptimedb-reservation.service
```

`8.4-units.log`:

```text
$ systemctl is-active greptimedb opentelemetry-collector
active
active
$ systemctl show greptimedb-schema -p Result -p ExecMainStatus -p ActiveState
ActiveState=active
Result=success
ExecMainStatus=0
$ systemctl status greptimedb-schema --no-pager
● greptimedb-schema.service - GreptimeDB databases and retention
     Loaded: loaded (/etc/systemd/system/greptimedb-schema.service; enabled; preset: ignored)
     Active: active (exited) since Sat 2026-10-17 07:20:00 UTC; 12s ago
 Invocation: 5bba4f6f5c2244bb8b4449f9aa9c59fd
    Process: 968717 ExecStart=/nix/store/vcd7d41cgwb3dj7m6bznckvd4s5g3w9z-greptimedb-schema/bin/greptimedb-schema (code=exited, status=0/SUCCESS)
   Main PID: 968717 (code=exited, status=0/SUCCESS)
         IP: 3.6K in, 4.1K out
         IO: 0B read, 0B written
   Mem peak: 4.6M
        CPU: 145ms
$ systemctl is-active prometheus-node-exporter greptimedb-envelope.timer
active
active
$ systemctl show -p Result zfs-set-root-greptimedb-quota zfs-set-root-greptimedb-reservation zfs-assert-root-greptimedb-noautosnap
Result=success

Result=success

Result=success
$ systemctl list-units --failed --no-legend
```

`8.4-users-hash.log`:

```text
$ cat /nix/store/qnzd2ggnbbgcriadmh7rgqi5rghp43nj-per-machine-magnetite-greptimedb-users_users-sha256
ead34b92806a6be487c0e930d9033c323c8f5b00ecdd897ce1cd25fb67586738
$ cat /run/greptimedb/loaded-users.sha256
ead34b92806a6be487c0e930d9033c323c8f5b00ecdd897ce1cd25fb67586738
$ stat -c %a /run/greptimedb/loaded-users.sha256
444
```

`8.4-queue-redeploy.log`:

```text
Queue is empty on https://nixbot.scientistexperience.net.
```

`8.4-clan-update-redeploy.log`, last 15 lines:

```text
[magnetite] SIZE: 32.2 GiB -> 32.2 GiB
[magnetite] DIFF: +2.47 KiB
[magnetite] ---
[magnetite] updating GRUB 2 menu...
[magnetite] stopping the following units: omnigent-host-cameron.service, omnigent-host-janettesmith.service, opentelemetry-collector.service
[magnetite] activating the configuration...
[magnetite] setting up /etc...
[magnetite] reloading user units for root...
[magnetite] restarting the following user units: nixos-activation.service
[magnetite] reloading user units for cameron...
[magnetite] restarting the following user units: nixos-activation.service
[magnetite] restarting sysinit-reactivation.target
[magnetite] restarting the following units: home-manager-cameron.service, home-manager-omnigent\x2dcameron.service, home-manager-omnigent\x2djanettesmith.service
[magnetite] starting the following units: omnigent-host-cameron.service, omnigent-host-janettesmith.service, opentelemetry-collector.service
[magnetite] the following new units were started: greptimedb-schema.service
```

`8.4-units-redeploy.log`:

```text
Wants=greptimedb-schema.service
After=sysinit.target
greptimedb-schema.service
active
active
active
```

### 9.4 Deployment-time items (tasks.md 8.5)

The measured `fleet` queue rate is 76538 bytes per minute, about 30% of the assumed `fleetBytesPerMinute = 256000`.
A day at the measured rate is 110214720 bytes, inside the 419430400-byte (400 MiB) `fleet` queue, so no follow-up change is needed.
`8.5-promql-host-name.log` and the queue and journal reads in §9.5 carry Task 6's recorded adaptations of plan commands: `__name__=~".+"` added because v1.2.1 rejects a selector with no metric matcher, `sudo` on journal reads, the notifier instance name `observability-notify@greptimedb-envelope.service.service` (systemd expands `%n` to the full unit name), counter names without `_total` in collector 0.155, and non-interactive snapshot values in place of `read -p`.

The authenticated dashboard check passed.
`8.5-dashboard.log` first shows `200` over the tunnel and the page rendered in headless Chromium, marked `[agent S1Task6Verify, not operator]`, then the operator's `[operator]` line: signed in as `perses` with the connection database `fleet`, PromQL `count(up)` returned 6 at every step and SQL `SELECT count(*) FROM fleet.up` returned 4091.
The dashboard selects its query database in the connection settings, not in the Tables panel; a query run while the connection database is `public` returns no rows, which is ADR-002 Q10 and an S6 concern.
This check is not part of tasks.md 8.5's wording; the dashboard requirement's scenario is also discharged by the container test's dashboard case.

`8.5-r2.log`:

```text
$ ssh magnetite.zt systemctl show greptimedb -p ActiveEnterTimestamp
ActiveEnterTimestamp=Sat 2026-10-17 07:19:58 UTC
Sat Oct 17 08:30:23 AM UTC 2026
$ list s3://sciexp/projects/vanixiets/observability/store/ with the greptimedb-r2 credential
2026-10-17 07:22:02       2932 projects/vanixiets/observability/store/data/greptime/fleet/1024/1024_0000000000/metadata/manifest/00000000000000000005.json
2026-10-17 07:23:02        710 projects/vanixiets/observability/store/data/greptime/fleet/1024/1024_0000000000/metadata/manifest/00000000000000000006.json

Total Objects: 29
   Total Size: 410488
$ gq.sh sql fleet "SELECT sum(sst_size) FROM information_schema.region_statistics"
[[298769]]
```

`8.5-queue-rate.log`:

```text
$ nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.telemetry
error: flake 'git+file:///private/tmp/wt-main' does not provide attribute 'packages.aarch64-darwin.nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.telemetry', 'legacyPackages.aarch64-darwin.nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.telemetry' or 'nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.service.telemetry'
$ nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.exporters --apply builtins.attrNames
["otlp_http/agent","otlp_http/devloop","otlp_http/fleet"]
$ nix eval --json .#nixosConfigurations.magnetite.config.services.opentelemetry-collector.settings.extensions
{"basicauth/store":{"client_auth":{"password_file":"/run/credentials/opentelemetry-collector.service/collector-password","username":"collector"}},"file_storage":{"create_directory":true,"directory":"/var/lib/opentelemetry-collector/queue"}}
$ nix eval --json .#lib.otelCollectorSchema
{"databases":["fleet","devloop","agent"],"nodeExporterKeep":["node_zfs_zpool_state","node_zfs_arc_size","node_zfs_arc_c","node_zfs_arc_c_min","node_zfs_arc_c_max","node_zfs_arc_hits","node_zfs_arc_misses","node_zfs_arc_memory_throttle_count","node_vmstat_oom_kill"],"ownerAliases":{"cameron":"owner-1","janettesmith":"owner-2"},"process":{"maxNames":30,"minBytes":67108864},"promotedResourceAttributes":["host.name","systemd.unit.name","process.executable.name"],"systemdUnits":["gitea.service","gitea-mq.service","nixbot*.service","niks3*.service","nix-daemon.service","nix-grpc-daemon.service","harmonia-gc.service","postgresql.service","nginx.service","greptimedb.service","opentelemetry-collector.service","zerotierone.service","omnigent-host-*.service","omnigraph.service","otel-envelope.service","devloop-reconcile.service","greptimedb-envelope.service","greptimedb-export.service","greptimedb-schema.service","prometheus-node-exporter.service","prometheus-smartctl-exporter.service","zfs-assert-*.service","zfs-set-*.service"]}
NEXT                         LEFT LAST                           PASSED UNIT                      ACTIVATES
Sat 2026-10-17 09:03:20 UTC 32min Sat 2026-10-17 08:00:56 UTC 29min ago greptimedb-envelope.timer greptimedb-envelope.service

1 timers listed.
Pass --all to see loaded but inactive timers, too.
# telemetry unset in the evaluated config (attribute absent) -> default 127.0.0.1:8888; fleet exporter otlp_http/fleet; FILE_STORAGE_DIR=/var/lib/opentelemetry-collector/queue
# ADAPTATION (a): collector 0.155 exposes otelcol_exporter_sent_metric_points / send_failed_metric_points without the _total suffix, so the grep accepts both forms.
# before stop
2026-10-17T08:30:46Z
otelcol_exporter_queue_capacity{data_type="metrics",exporter="otlp_http/fleet"} 4.194304e+08
otelcol_exporter_queue_size{data_type="metrics",exporter="otlp_http/fleet"} 0
otelcol_exporter_send_failed_metric_points{exporter="otlp_http/fleet",server_address="127.0.0.1",server_port="4000",url_path="/v1/otlp/v1/metrics"} 279
otelcol_exporter_sent_metric_points{exporter="otlp_http/fleet",server_address="127.0.0.1",server_port="4000",url_path="/v1/otlp/v1/metrics"} 66584
327680	/var/lib/opentelemetry-collector/queue
$ sudo systemctl stop greptimedb
inactive
# after 600 s stopped
2026-10-17T08:40:49Z
otelcol_exporter_queue_capacity{data_type="metrics",exporter="otlp_http/fleet"} 4.194304e+08
otelcol_exporter_queue_size{data_type="metrics",exporter="otlp_http/fleet"} 765385
otelcol_exporter_send_failed_metric_points{exporter="otlp_http/fleet",server_address="127.0.0.1",server_port="4000",url_path="/v1/otlp/v1/metrics"} 279
otelcol_exporter_sent_metric_points{exporter="otlp_http/fleet",server_address="127.0.0.1",server_port="4000",url_path="/v1/otlp/v1/metrics"} 66584
1114112	/var/lib/opentelemetry-collector/queue
$ sudo systemctl start greptimedb
active
# 300 s after start
2026-10-17T08:45:53Z
otelcol_exporter_queue_capacity{data_type="metrics",exporter="otlp_http/fleet"} 4.194304e+08
otelcol_exporter_queue_size{data_type="metrics",exporter="otlp_http/fleet"} 0
otelcol_exporter_send_failed_metric_points{exporter="otlp_http/fleet",server_address="127.0.0.1",server_port="4000",url_path="/v1/otlp/v1/metrics"} 279
otelcol_exporter_sent_metric_points{exporter="otlp_http/fleet",server_address="127.0.0.1",server_port="4000",url_path="/v1/otlp/v1/metrics"} 76863
2162688	/var/lib/opentelemetry-collector/queue
# ADAPTATION (a): the plan's interactive 'read -p' prompts replaced by assigning the observed snapshot values (non-interactive shell).
fleet queue_size before stop (bytes): 0
fleet queue_size after 600 s (bytes): 765385
measured fleetBytesPerMinute=76538
measured 24h volume=110214720 bytes; queue size=419430400 bytes (400 MiB); assumed constant 256000 B/min gives 368640000 bytes
PASS: 24 h of fleet fits the 400 MiB queue
# cross-checks: du -sb FILE_STORAGE_DIR 327680 -> 1114112 while stopped (+786432 B, bbolt preallocation upper bound), 2162688 after drain; sent_metric_points 66584 -> 76863 (+10279 points in the 300 s after start); send_failed_metric_points unchanged at 279 (all 279 at 07:20:00, before greptimedb-schema created database fleet)
```

`8.5-zfs.log`:

```text
$ zfs get quota,reservation zroot/root/greptimedb
NAME                   PROPERTY     VALUE   SOURCE
zroot/root/greptimedb  quota        16G     local
zroot/root/greptimedb  reservation  12G     local
$ zfs get -Hp used,quota zroot/root/greptimedb
zroot/root/greptimedb	used	635392	-
zroot/root/greptimedb	quota	17179869184	local
$ findmnt -no SOURCE /var/lib/greptimedb
zroot/root/greptimedb
```

`8.5-zram-paging.log`:

```text
$ gq.sh promql fleet 'system_paging_usage_bytes{host_name="magnetite",device="/dev/zram0"}'
"success"
[{"metric":{"__name__":"system_paging_usage_bytes","device":"/dev/zram0","host_name":"magnetite","state":"used"},"value":[1792221715.163,"488800256"]},{"metric":{"__name__":"system_paging_usage_bytes","device":"/dev/zram0","host_name":"magnetite","state":"free"},"value":[1792221715.163,"48800034816"]}]
```

`8.5-promql-host-name.log`:

```text
$ gq.sh promql fleet 'count by (__name__) ({host_name="magnetite"})'
{"status":"error","error":"Expect a metric matcher, but not found","errorType":"InvalidSyntax"}
# ADAPTATION (a): GreptimeDB v1.2.1 rejects a selector without a metric-name matcher (InvalidSyntax 'Expect a metric matcher, but not found'); adding __name__=~".+" supplies one without narrowing the selection.
$ gq.sh promql fleet 'count by (__name__) ({__name__=~".+", host_name="magnetite"})'
success
327
process_virtual_memory_max_bytes 2
node_zfs_zpool_state 7
system_linux_memory_available_bytes 1
opendal_operation_entries_sum 3
opendal_operation_bytes_rate_sum 3
opendal_http_response_bytes_count 2
opendal_operation_bytes_bucket 33
sys_jemalloc_allocated 1
opendal_operation_executing 8
opendal_http_request_bytes_rate_sum 2
opendal_http_request_duration_seconds_sum 2
opendal_operation_entries_count 3
opendal_operation_ttfb_seconds_sum 1
promhttp_metric_handler_requests_total 3
process_resident_memory_bytes 3
opendal_http_request_bytes_count 2
opendal_http_request_duration_seconds_count 2
zt_num_networks 1
scrape_samples_scraped 6
opendal_http_response_bytes_sum 2
systemd_unit_state 216
opendal_http_request_bytes_sum 2
process_network_receive_bytes_total 2
opendal_operation_entries_bucket 30
opendal_http_request_bytes_rate_count 2
process_network_transmit_bytes_total 2
process_max_fds 3
sys_jemalloc_resident 1
opendal_http_response_bytes_bucket 22
scrape_series_added 6
opendal_http_response_duration_seconds_count 2
system_memory_usage_bytes 6
scrape_duration_seconds 6
zt_packet_error_total 16
zt_network_multicast_groups_subscribed 1
up 6
opendal_http_request_bytes_rate_bucket 24
opendal_operation_errors_total 1
systemd_service_restarts_total 27
process_memory_usage_bytes 6
opendal_http_response_duration_seconds_sum 2
opendal_operation_bytes_rate_bucket 36
opendal_operation_ttfb_seconds_count 1
process_start_time_seconds 2
zt_data_total 4
opendal_http_request_duration_seconds_bucket 26
zt_network_packets_total 4
process_open_fds 3
opendal_http_executing 3
opendal_operation_bytes_rate_count 3
opendal_http_response_duration_seconds_bucket 26
opendal_operation_entries_rate_count 3
opendal_operation_entries_rate_sum 3
opendal_operation_entries_rate_bucket 27
opendal_operation_duration_seconds_sum 7
process_cpu_seconds_total 3
opendal_http_response_bytes_rate_bucket 24
opendal_http_response_bytes_rate_count 2
opendal_operation_bytes_sum 3
opendal_http_request_bytes_bucket 22
zt_packet_total 42
process_virtual_memory_bytes 3
opendal_operation_duration_seconds_bucket 91
process_threads 1
promhttp_metric_handler_requests_in_flight 1
opendal_operation_bytes_count 3
opendal_operation_duration_seconds_count 7
opendal_http_status_errors_total 1
opendal_operation_ttfb_seconds_bucket 11
scrape_samples_post_metric_relabeling 6
opendal_http_response_bytes_rate_sum 2
system_paging_usage_bytes 2
greptime_mito_region_count 8
greptime_mito_read_rows_return_count 1
greptime_servers_http_sql_elapsed_bucket 11
greptime_mito_flush_requests_total 2
niks3_upload_skipped_paths_total 1
node_zfs_arc_memory_throttle_count 1
niks3_upload_skipped_nar_bytes_total 1
greptime_mito_compaction_stage_elapsed_count 1
niks3_cache_logical_bytes 1
nginx_connections_current 4
greptime_runtime_threads_alive 3
niks3_commit_duration_seconds_sum 1
greptime_mito_read_sst_count_bucket 9
greptime_table_operator_create_tables_bucket 12
nixbot_build_duration_seconds_sum 1
niks3_commit_objects_total 1
greptime_mito_read_rows_return_bucket 9
greptime_mito_write_stage_elapsed_count 3
niks3_commit_duration_seconds_count 1
greptime_table_operator_ingest_rows_total 1
greptime_mito_handle_request_elapsed_sum 4
greptime_table_operator_create_alter_on_demand_sum 1
niks3_pending_closures 1
node_zfs_arc_hits 1
node_zfs_arc_size 1
greptime_servers_grpc_requests_elapsed_sum 1
node_vmstat_oom_kill 1
greptime_servers_http_otlp_metrics_elapsed_bucket 12
greptime_mito_write_stage_elapsed_bucket 21
greptime_mito_write_rows_total 2
greptime_mito_read_batches_return_sum 1
greptime_mito_compaction_stage_elapsed_bucket 7
mito_upload_bytes_total 1
nixbot_work_queue 7
greptime_mito_read_rows_in_row_group_total 4
greptime_table_operator_create_tables_count 1
greptime_mito_write_stall_total 1
greptime_mito_read_batches_return_bucket 8
greptime_mito_request_wait_time_count 8
niks3_gc_duration_seconds_count 1
greptime_servers_grpc_requests_total 1
greptime_mito_read_row_groups_total 5
greptime_mito_write_buffer_bytes 1
greptime_mito_cache_hit_total 1
greptime_servers_request_memory_limit_bytes 1
niks3_commit_duration_seconds_bucket 16
greptime_mito_flush_elapsed_count 8
greptime_mito_read_rows_total 1
greptime_mito_read_sst_count_count 1
nixbot_projects 2
nixbot_effects 6
greptime_mito_read_stage_elapsed_sum 9
greptime_servers_http_sql_elapsed_count 1
node_zfs_arc_c 1
greptime_mito_merge_filter_rows_total 2
greptime_mito_cache_eviction_total 1
greptime_region_worker_handle_write_sum 1
greptime_servers_http_requests_total 5
greptime_servers_http_otlp_metrics_elapsed_count 1
nixbot_eval_duration_seconds_sum 1
greptime_mito_precise_filter_rows_total 1
niks3_cache_objects 1
greptime_mito_write_stage_elapsed_sum 3
greptime_mito_compaction_stage_elapsed_sum 1
greptime_mito_read_stage_elapsed_bucket 72
greptime_mito_inflight_flush_count 1
niks3_http_requests_total 10
niks3_gc_duration_seconds_bucket 14
nginx_connections_handled_total 1
niks3_gc_objects_deleted_total 1
greptime_mito_request_wait_time_bucket 72
greptime_servers_http_otlp_metrics_elapsed_sum 1
nixbot_builds_oldest_active_age_seconds 1
greptime_mito_flush_file_total 1
nixbot_build_duration_seconds_count 1
greptime_mito_flush_bytes_total 1
greptime_servers_http_requests_elapsed_bucket 55
node_zfs_arc_c_max 1
greptime_servers_grpc_requests_elapsed_count 1
niks3_db_connections_max 1
greptime_mito_write_stalling_count 8
greptime_mito_read_rows_return_sum 1
greptime_table_operator_create_tables_sum 1
niks3_http_request_duration_seconds_sum 10
niks3_http_request_duration_seconds_count 10
greptime_servers_grpc_requests_elapsed_bucket 11
greptime_table_operator_create_table_bucket 12
nginx_requests_total 1
niks3_http_request_duration_seconds_bucket 160
niks3_db_connections_in_use 1
greptime_metric_engine_physical_region_count 1
niks3_http_requests_in_flight 1
node_zfs_arc_misses 1
greptime_table_operator_create_alter_on_demand_bucket 12
niks3_gc_last_run_timestamp_seconds 1
node_zfs_arc_c_min 1
greptime_servers_request_memory_in_use_bytes 1
nixbot_eval_duration_seconds_count 1
greptime_servers_http_requests_elapsed_sum 5
greptime_mito_pruner_active_builders 1
greptime_mito_memtable_field_builder_count 1
greptime_mito_read_batches_return_count 1
greptime_servers_http_requests_elapsed_count 5
greptime_mito_read_stage_elapsed_count 9
greptime_runtime_threads_idle 3
greptime_mito_compaction_memory_limit_bytes 1
nixbot_builds 3
nginx_connections_accepted_total 1
nixbot_queue_depth 1
greptime_mito_in_progress_scan 1
greptime_mito_cache_miss_total 1
greptime_mito_read_sst_count_sum 1
greptime_mito_cache_bytes 7
greptime_table_operator_mirror_pending_rows 1
greptime_mito_flush_elapsed_bucket 56
nixbot_attributes 7
greptime_mito_handle_request_elapsed_bucket 32
greptime_table_operator_create_table_sum 1
greptime_mito_flush_elapsed_sum 8
niks3_gc_duration_seconds_sum 1
greptime_mito_handle_request_elapsed_count 4
greptime_region_worker_handle_write_count 1
greptime_table_operator_create_alter_on_demand_count 1
greptime_mito_request_wait_time_sum 8
greptime_servers_http_sql_elapsed_sum 1
greptime_table_operator_create_table_count 1
greptime_region_worker_handle_write_bucket 6
go_threads 2
greptime_app_version 1
go_memstats_mcache_inuse_bytes 2
go_gc_duration_seconds 10
go_memstats_gc_sys_bytes 2
gitea_projects 1
greptime_manifest_op_elapsed_sum 2
go_memstats_stack_inuse_bytes 2
controller_db_get_member_list_total 1
controller_db_get_network_and_member_total 1
greptime_meta_cache_container_load_cache_count 8
greptime_logstore_op_elapsed_count 1
greptime_index_create_elapsed_bucket 28
greptime_logstore_op_bytes_total 1
gitea_issues_closed 1
greptime_meta_create_catalog_sum 1
greptime_meta_create_schema_count 1
go_memstats_mspan_sys_bytes 2
go_memstats_heap_released_bytes 2
gitea_hooktasks 1
gitea_build_info 1
greptime_metric_engine_mito_ddl_sum 1
controller_db_get_networK_and_member_summary_total 1
go_info 2
gitea_watches 1
greptime_metric_engine_mito_op_elapsed_count 1
go_memstats_frees_total 2
greptime_datanode_handle_region_request_elapsed_count 1
gitea_organizations 1
controller_network_config_request_threads 1
greptime_meta_procedure_create_tables_bucket 36
controller_network_count 1
greptime_meta_create_catalog_count 1
greptime_index_create_elapsed_count 4
go_memstats_heap_alloc_bytes 2
greptime_cgroups_memory_usage_bytes 1
controller_network_change_count_total 1
gitea_projects_boards 1
controller_sso_expiration_checks_total 1
go_memstats_alloc_bytes_total 2
go_memstats_alloc_bytes 2
greptime_meta_procedure_create_tables_count 3
controller_db_member_change_total 1
go_memstats_sys_bytes 2
go_memstats_heap_inuse_bytes 2
greptime_index_io_bytes_total 1
controller_member_count 1
greptime_index_create_elapsed_sum 4
gitea_webhooks 1
gitea_teams 1
gitea_stars 1
gitea_follows 1
greptime_cgroups_cpu_usage_microseconds 1
gitea_issues 1
go_gc_gogc_percent 2
greptime_meta_create_schema_sum 1
greptime_metric_engine_mito_op_elapsed_sum 1
gitea_updatetasks 1
greptime_meta_create_catalog_counter_total 1
go_memstats_heap_objects 2
greptime_meta_create_schema_counter_total 1
greptime_metric_engine_physical_column_count 1
go_memstats_heap_sys_bytes 2
controller_db_get_network_total 1
gitea_labels 1
greptime_datanode_region_request_fail_count_total 3
greptime_datanode_handle_region_request_elapsed_bucket 12
go_memstats_last_gc_time_seconds 2
go_memstats_buck_hash_sys_bytes 2
gitea_users 2
controller_network_config_request_queue 1
gitea_releases 1
greptime_meta_procedure_create_table_sum 3
greptime_index_io_op_total 2
gitea_repositories 1
greptime_metric_engine_mito_ddl_count 1
go_gc_duration_seconds_sum 2
go_sched_gomaxprocs_threads 2
greptime_metric_engine_mito_ddl_bucket 12
greptime_meta_procedure_create_table_bucket 36
greptime_meta_create_schema_bucket 12
greptime_logstore_op_elapsed_sum 1
go_gc_gomemlimit_bytes 2
go_memstats_mallocs_total 2
controller_network_config_request_total 1
greptime_index_create_rows_total 1
greptime_meta_procedure_create_tables_sum 3
greptime_datanode_region_changed_row_count_total 1
greptime_manifest_op_elapsed_bucket 14
greptime_meta_procedure_create_table_count 3
go_memstats_other_sys_bytes 2
gitea_publickeys 1
controller_member_deauth_count_total 1
gitea_issues_open 1
greptime_index_create_bytes_total 1
greptime_meta_cache_container_load_cache_sum 8
go_goroutines 2
controller_member_change_count_total 1
go_gc_duration_seconds_count 2
greptime_frontend_otlp_metrics_rows_total 1
greptime_cpu_limit_in_millicores 1
greptime_flow_run_interval_ms 1
greptime_datanode_handle_region_request_elapsed_sum 1
greptime_meta_cache_container_cache_miss_total 8
go_memstats_next_gc_bytes 2
greptime_metric_engine_mito_op_elapsed_bucket 8
go_memstats_stack_sys_bytes 2
greptime_index_create_memory_usage 3
gitea_comments 1
gitea_mirrors 1
gitea_accesses 1
greptime_meta_cache_container_cache_get_total 8
go_memstats_mcache_sys_bytes 2
greptime_meta_cache_container_load_cache_bucket 96
greptime_logstore_op_elapsed_bucket 17
controller_sso_timeouts_total 1
controller_db_network_change_total 1
greptime_memory_limit_in_bytes 1
gitea_attachments 1
gitea_loginsources 1
go_memstats_heap_idle_bytes 2
controller_member_auth_count_total 1
go_memstats_mspan_inuse_bytes 2
gitea_milestones 1
greptime_meta_create_catalog_bucket 12
greptime_manifest_op_elapsed_count 2
gitea_oauths 1
controller_db_get_network_list_total 1
```

`8.5-process-name-bound.log`:

```text
$ gq.sh promql fleet 'count(count by (process_executable_name) (process_memory_usage_bytes{host_name="magnetite"}))'
6
PASS: 6 distinct names <= 30
$ gq.sh promql fleet 'count(count by (process_executable_name) (count_over_time(process_memory_usage_bytes{host_name="magnetite"}[1h])))'
6
PASS: 6 distinct names <= 30
# re-run at 2026-10-17T08:30:35Z, 70 min after store start, so the [1h] window covers a full hour of data
$ gq.sh promql fleet 'count(count by (process_executable_name) (count_over_time(process_memory_usage_bytes{host_name="magnetite"}[1h])))'
7
PASS: 7 distinct names <= 30
```

`8.5-sql-host-name.log`:

```text
$ gq.sh sql fleet "SELECT host_name, count(*) AS points, max(greptime_timestamp) AS latest FROM process_memory_usage_bytes WHERE greptime_timestamp > now() - INTERVAL '1 hour' GROUP BY host_name"
[["magnetite",8,1792221660058]]
```

`8.5-no-log-trace-tables.log`:

```text
$ gq.sh sql fleet "SELECT table_schema, table_name FROM information_schema.tables WHERE table_name IN ('opentelemetry_logs', 'opentelemetry_traces') OR table_name LIKE '%logs' OR table_name LIKE '%traces%'"
[]
$ gq.sh sql fleet "SELECT table_schema, count(*) FROM information_schema.tables WHERE table_schema IN ('fleet', 'devloop', 'agent') GROUP BY table_schema"
[["fleet",358]]
```

`8.5-dashboard.log`:

```text
$ curl -s -o /dev/null -w "%{http_code}\n" http://127.0.0.1:4000/dashboard/
200
[agent S1Task6Verify, not operator] 2026-10-17T07:22:55Z: dashboard at http://127.0.0.1:4000/dashboard/ rendered over ssh -L 4000:127.0.0.1:4000 magnetite.zt in headless Chromium (in place of `open`); observed: title "Dashboard | Greptime", redirected to #/dashboard/query, nav shows Table Query / Metrics Query / Logs Query / Traces Query / Ingest / Flow; connection panel shows host http://127.0.0.1:4000, database public, status Disconnected with "Not found http or grpc authorization header" (store requires auth; no credential entered because credentials must not leave magnetite). Operator observation of an authenticated query is still owed.
[operator] 2026-10-17T18:42:25Z: signed in to http://127.0.0.1:4000/dashboard/ over ssh -L 4000:127.0.0.1:4000 magnetite.zt as perses (ro), connection database fleet, status Connected; PromQL count(up) over the last 5 minutes at 30s step returned 6 at each of 11 steps (14:37:04 to 14:42:04 UTC-4); SQL SELECT count(*) FROM fleet.up returned 4091. Observed and reported by the operator in session with screenshots.
```

### 9.5 R7.2 shown able to fail, with one notice and one RESOLVED (tasks.md 8.6)

The runtime drop-in `r7-2-force.conf` was removed by `systemctl revert`; `DropInPaths=` is empty afterwards (`8.6-resolved.log`).

`8.6-baseline.log`:

```text
$ cat /sys/fs/cgroup/system.slice/greptimedb.service/memory.peak
484499456
$ systemctl show greptimedb-envelope -p Environment -p Result
Result=success
Environment=GREPTIMEDB_ENVELOPE_DATASET=zroot/root/greptimedb GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT=80 GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=3221225472 GREPTIMEDB_ENVELOPE_QUOTA_BYTES=17179869184 GREPTIMEDB_ENVELOPE_RESERVATION_BYTES=12884901888 GREPTIMEDB_ENVELOPE_SST_MAX_BYTES=53687091200 GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE=/nix/store/qnzd2ggnbbgcriadmh7rgqi5rghp43nj-per-machine-magnetite-greptimedb-users_users-sha256 LOCALE_ARCHIVE=/nix/store/1m9dlscbzj1ma5xjsbfw2kk0gwfq3qb7-glibc-locales-2.44-25/lib/locale/locale-archive PATH=/nix/store/2gfxiwls9hbgwdwcy43mprchwsq36mg6-coreutils-9.11/bin:/nix/store/ycrbcy9sg4knpnik6a01dk70l0m673x7-findutils-4.11.0/bin:/nix/store/3668q0d9zhc5n9l2pnyvpd44kz9bjsjm-gnugrep-3.12/bin:/nix/store/1ggxndc1gd5061j5hqprhnhx9p30yilv-gnused-4.10/bin:/nix/store/l5hiab3932k2n4d6nirh09mk6xgxp61w-systemd-261.3/bin:/nix/store/2gfxiwls9hbgwdwcy43mprchwsq36mg6-coreutils-9.11/sbin:/nix/store/ycrbcy9sg4knpnik6a01dk70l0m673x7-findutils-4.11.0/sbin:/nix/store/3668q0d9zhc5n9l2pnyvpd44kz9bjsjm-gnugrep-3.12/sbin:/nix/store/1ggxndc1gd5061j5hqprhnhx9p30yilv-gnused-4.10/sbin:/nix/store/l5hiab3932k2n4d6nirh09mk6xgxp61w-systemd-261.3/sbin TZDIR=/nix/store/n8fqcpnr5ni28l3i9svqa70wz46798v9-tzdata-2026d/share/zoneinfo
$ sudo ls -la /var/lib/observability-notify
ls: cannot access '/var/lib/observability-notify': No such file or directory
$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'
T0=2026-10-17T07:23:06Z
```

`8.6-forced-failure.log`:

```text
$ printf "[Service]\nEnvironment=GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=1\n" | sudo systemctl edit --runtime --stdin --drop-in=r7-2-force greptimedb-envelope
Successfully installed edited file '/run/systemd/system/greptimedb-envelope.service.d/r7-2-force.conf'.
$ sudo systemctl start greptimedb-envelope
Job for greptimedb-envelope.service failed because the control process exited with error code.
See "systemctl status greptimedb-envelope.service" and "journalctl -xeu greptimedb-envelope.service" for details.
exit=1
$ systemctl status greptimedb-envelope --no-pager
× greptimedb-envelope.service - GreptimeDB runtime envelope
     Loaded: loaded (/etc/systemd/system/greptimedb-envelope.service; linked; preset: ignored)
    Drop-In: /run/systemd/system/greptimedb-envelope.service.d
             └─r7-2-force.conf
     Active: failed (Result: exit-code) since Sat 2026-10-17 07:23:16 UTC; 16s ago
 Invocation: c6045ffcc66249e69e5554fc8bc0e067
TriggeredBy: ● greptimedb-envelope.timer
    Process: 969887 ExecStart=/nix/store/624d8y5kqsbxxd5hh8jfli2rcydfaml5-greptimedb-envelope/bin/greptimedb-envelope (code=exited, status=1/FAILURE)
    Process: 969927 ExecStopPost=/nix/store/44jagira13v9bimx30cbjc9kbbx0xz84-observability-notify-resolved greptimedb-envelope.service (code=exited, status=0/SUCCESS)
   Main PID: 969887 (code=exited, status=1/FAILURE)
         IP: 113K in, 1.8K out
         IO: 651K read, 0B written
   Mem peak: 6.1M
        CPU: 351ms
No journal files were opened due to insufficient permissions.
$ sudo ls -la /var/lib/observability-notify
total 4
drwxr-xr-x  2 root root  3 Oct 17 07:23 .
drwxr-xr-x 31 root root 37 Oct 17 07:23 ..
-rw-r--r--  1 root root  0 Oct 17 07:23 greptimedb-envelope.service
$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'
{"time":1792221796,"message":"FAILED greptimedb-envelope.service on magnetite"}
# ADAPTATION (a): unprivileged journalctl on magnetite printed 'No journal files were opened due to insufficient permissions'; rerun with sudo.
$ sudo journalctl -u greptimedb-envelope -n 20 --no-pager
Oct 17 07:23:16 magnetite systemd[1]: Starting GreptimeDB runtime envelope...
Oct 17 07:23:16 magnetite greptimedb-envelope[969887]: FAIL R7.2: memory.peak 484499456 >= GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES 1
Oct 17 07:23:16 magnetite systemd[1]: greptimedb-envelope.service: Main process exited, code=exited, status=1/FAILURE
Oct 17 07:23:16 magnetite systemd[1]: greptimedb-envelope.service: Failed with result 'exit-code'.
Oct 17 07:23:16 magnetite systemd[1]: Failed to start GreptimeDB runtime envelope.
Oct 17 07:23:16 magnetite systemd[1]: greptimedb-envelope.service: Consumed 351ms CPU time over 429ms wall clock time, 6.1M memory peak, 651K read from disk, 113K incoming IP traffic, 1.8K outgoing IP traffic.
Oct 17 07:23:16 magnetite systemd[1]: greptimedb-envelope.service: Triggering OnFailure= dependencies.
```

`8.6-repeat-failure.log`:

```text
$ sudo systemctl start greptimedb-envelope
Job for greptimedb-envelope.service failed because the control process exited with error code.
See "systemctl status greptimedb-envelope.service" and "journalctl -xeu greptimedb-envelope.service" for details.
exit=1
$ systemctl show greptimedb-envelope -p Result -p ExecMainStatus
Result=exit-code
ExecMainStatus=1
# ADAPTATION (a): journalctl run with sudo (unprivileged read is denied on magnetite, see 8.6-forced-failure.log).
$ sudo journalctl -u "observability-notify@greptimedb-envelope.service" -n 20 --no-pager
-- No entries --
$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'
{"time":1792221796,"message":"FAILED greptimedb-envelope.service on magnetite"}
# ADAPTATION (a): OnFailure=observability-notify@%n.service with %n=greptimedb-envelope.service names the instance observability-notify@greptimedb-envelope.service.service; the plan's unit name matches nothing ('-- No entries --').
$ systemctl list-units --all "observability-notify@*" --no-pager
  UNIT                                                                       LOAD   ACTIVE   SUB  DESCRIPTION
  observability-notify@greptimedb-envelope.service.service                   loaded inactive dead Post a failure notice for greptimedb-envelope.service to ntfy
  observability-notify@greptimedb-schema.service.service                     loaded inactive dead Post a failure notice for greptimedb-schema.service to ntfy
  observability-notify@greptimedb.service.service                            loaded inactive dead Post a failure notice for greptimedb.service to ntfy
  observability-notify@opentelemetry-collector.service.service               loaded inactive dead Post a failure notice for opentelemetry-collector.service to ntfy
  observability-notify@zfs-assert-root-docker-noautosnap.service.service     loaded inactive dead Post a failure notice for zfs-assert-root-docker-noautosnap.service to ntfy
  observability-notify@zfs-assert-root-greptimedb-noautosnap.service.service loaded inactive dead Post a failure notice for zfs-assert-root-greptimedb-noautosnap.service to ntfy
  observability-notify@zfs-assert-root-nix-noautosnap.service.service        loaded inactive dead Post a failure notice for zfs-assert-root-nix-noautosnap.service to ntfy
  observability-notify@zfs-assert-root-podman-noautosnap.service.service     loaded inactive dead Post a failure notice for zfs-assert-root-podman-noautosnap.service to ntfy
  observability-notify@zfs-set-root-greptimedb-quota.service.service         loaded inactive dead Post a failure notice for zfs-set-root-greptimedb-quota.service to ntfy
  observability-notify@zfs-set-root-greptimedb-reservation.service.service   loaded inactive dead Post a failure notice for zfs-set-root-greptimedb-reservation.service to ntfy
  observability-notify@zfs-set-root-home-reservation.service.service         loaded inactive dead Post a failure notice for zfs-set-root-home-reservation.service to ntfy
  observability-notify@zfs-set-root-nix-quota.service.service                loaded inactive dead Post a failure notice for zfs-set-root-nix-quota.service to ntfy
  observability-notify@zfs-set-root-nixos-reservation.service.service        loaded inactive dead Post a failure notice for zfs-set-root-nixos-reservation.service to ntfy

Legend: LOAD   → Reflects whether the unit definition was properly loaded.
        ACTIVE → The high-level unit activation state, i.e. generalization of SUB.
        SUB    → The low-level unit activation state, values depend on unit type.

13 loaded units listed.
To show all installed unit files use 'systemctl list-unit-files'.
$ sudo journalctl -u "observability-notify@greptimedb-envelope.service.service" -n 20 --no-pager
Oct 17 07:23:16 magnetite systemd[1]: Starting Post a failure notice for greptimedb-envelope.service to ntfy...
Oct 17 07:23:16 magnetite ntfy-send[969938]: {"id":"FtCdhRd5OnrG","time":1792221796,"expires":1792264996,"event":"message","topic":"fleet-alerts","message":"FAILED greptimedb-envelope.service on magnetite"}
Oct 17 07:23:16 magnetite systemd[1]: observability-notify@greptimedb-envelope.service.service: Deactivated successfully.
Oct 17 07:23:16 magnetite systemd[1]: Finished Post a failure notice for greptimedb-envelope.service to ntfy.
Oct 17 07:23:16 magnetite systemd[1]: observability-notify@greptimedb-envelope.service.service: Consumed 65ms CPU time over 125ms wall clock time, 3.4M memory peak, 1K read from disk, 3.6K incoming IP traffic, 2.9K outgoing IP traffic.
Oct 17 07:23:47 magnetite systemd[1]: Starting Post a failure notice for greptimedb-envelope.service to ntfy...
Oct 17 07:23:47 magnetite systemd[1]: observability-notify@greptimedb-envelope.service.service: Skipped due to 'exec-condition'.
Oct 17 07:23:47 magnetite systemd[1]: Condition check resulted in Post a failure notice for greptimedb-envelope.service to ntfy being skipped.
```

`8.6-resolved.log`:

```text
$ sudo systemctl revert greptimedb-envelope
Removed '/run/systemd/system/greptimedb-envelope.service.d/r7-2-force.conf'.
Removed '/run/systemd/system/greptimedb-envelope.service.d'.
$ systemctl show greptimedb-envelope -p Environment -p DropInPaths
DropInPaths=
Environment=GREPTIMEDB_ENVELOPE_DATASET=zroot/root/greptimedb GREPTIMEDB_ENVELOPE_DISK_USED_MAX_PERCENT=80 GREPTIMEDB_ENVELOPE_MEMORY_PEAK_MAX_BYTES=3221225472 GREPTIMEDB_ENVELOPE_QUOTA_BYTES=17179869184 GREPTIMEDB_ENVELOPE_RESERVATION_BYTES=12884901888 GREPTIMEDB_ENVELOPE_SST_MAX_BYTES=53687091200 GREPTIMEDB_ENVELOPE_USERS_SHA256_FILE=/nix/store/qnzd2ggnbbgcriadmh7rgqi5rghp43nj-per-machine-magnetite-greptimedb-users_users-sha256 LOCALE_ARCHIVE=/nix/store/1m9dlscbzj1ma5xjsbfw2kk0gwfq3qb7-glibc-locales-2.44-25/lib/locale/locale-archive PATH=/nix/store/2gfxiwls9hbgwdwcy43mprchwsq36mg6-coreutils-9.11/bin:/nix/store/ycrbcy9sg4knpnik6a01dk70l0m673x7-findutils-4.11.0/bin:/nix/store/3668q0d9zhc5n9l2pnyvpd44kz9bjsjm-gnugrep-3.12/bin:/nix/store/1ggxndc1gd5061j5hqprhnhx9p30yilv-gnused-4.10/bin:/nix/store/l5hiab3932k2n4d6nirh09mk6xgxp61w-systemd-261.3/bin:/nix/store/2gfxiwls9hbgwdwcy43mprchwsq36mg6-coreutils-9.11/sbin:/nix/store/ycrbcy9sg4knpnik6a01dk70l0m673x7-findutils-4.11.0/sbin:/nix/store/3668q0d9zhc5n9l2pnyvpd44kz9bjsjm-gnugrep-3.12/sbin:/nix/store/1ggxndc1gd5061j5hqprhnhx9p30yilv-gnused-4.10/sbin:/nix/store/l5hiab3932k2n4d6nirh09mk6xgxp61w-systemd-261.3/sbin TZDIR=/nix/store/n8fqcpnr5ni28l3i9svqa70wz46798v9-tzdata-2026d/share/zoneinfo
$ sudo systemctl start greptimedb-envelope
exit=0
$ systemctl status greptimedb-envelope --no-pager
# ADAPTATION (a): journalctl run with sudo (unprivileged read is denied on magnetite, see 8.6-forced-failure.log).
○ greptimedb-envelope.service - GreptimeDB runtime envelope
     Loaded: loaded (/etc/systemd/system/greptimedb-envelope.service; linked; preset: ignored)
     Active: inactive (dead) since Sat 2026-10-17 07:24:33 UTC; 16s ago
 Invocation: f61b2842450743f983fead58c98e7420
TriggeredBy: ● greptimedb-envelope.timer
    Process: 970332 ExecStart=/nix/store/624d8y5kqsbxxd5hh8jfli2rcydfaml5-greptimedb-envelope/bin/greptimedb-envelope (code=exited, status=0/SUCCESS)
    Process: 970376 ExecStopPost=/nix/store/44jagira13v9bimx30cbjc9kbbx0xz84-observability-notify-resolved greptimedb-envelope.service (code=exited, status=0/SUCCESS)
   Main PID: 970332 (code=exited, status=0/SUCCESS)
         IP: 116.7K in, 4.8K out
         IO: 0B read, 0B written
   Mem peak: 5.5M
        CPU: 397ms
Oct 17 07:24:33 magnetite greptimedb-envelope[970332]: greptimedb-envelope: all checks passed
Oct 17 07:24:33 magnetite 44jagira13v9bimx30cbjc9kbbx0xz84-observability-notify-resolved[970380]: {"id":"XfjPr6RTX4Vl","time":1792221873,"expires":1792265073,"event":"message","topic":"fleet-alerts","message":"RESOLVED greptimedb-envelope.service on magnetite"}
Oct 17 07:24:33 magnetite systemd[1]: greptimedb-envelope.service: Deactivated successfully.
Oct 17 07:24:33 magnetite systemd[1]: Finished GreptimeDB runtime envelope.
Oct 17 07:24:33 magnetite systemd[1]: greptimedb-envelope.service: Consumed 397ms CPU time over 503ms wall clock time, 5.5M memory peak, 116.7K incoming IP traffic, 4.8K outgoing IP traffic.
$ sudo ls -la /var/lib/observability-notify
total 3
drwxr-xr-x  2 root root  2 Oct 17 07:24 .
drwxr-xr-x 31 root root 37 Oct 17 07:23 ..
$ curl -sk 'https://ntfy.zt/fleet-alerts/json?poll=1&since=10m'
{"time":1792221796,"message":"FAILED greptimedb-envelope.service on magnetite"}
{"time":1792221873,"message":"RESOLVED greptimedb-envelope.service on magnetite"}
$ systemctl cat greptimedb-envelope | grep -E "^# "; ls /run/systemd/system.control /run/systemd/system/greptimedb-envelope.service.d
# /etc/systemd/system/greptimedb-envelope.service -> /nix/store/4p0vgk0y7xip8c9v019nz4h5djyb3js4-unit-greptimedb-envelope.service/greptimedb-envelope.service
ls: cannot access '/run/systemd/system.control/greptimedb-envelope.service.d': No such file or directory
ls: cannot access '/run/systemd/system/greptimedb-envelope.service.d': No such file or directory
```

### 9.6 Defects found and fixed during verification

PR #3490: `prom_store.enable = false` disabled the whole PromQL query API in v1.2.1 (`src/frontend/src/server.rs:130-158`).
The pipeline container test found it; charter v13 records the amendment, and the fix is merged and deployed.
PR #3492: the collector exported before `greptimedb-schema` created the databases on first deploy, losing 279 points (`finding-collector-schema-race.log`).
The fix orders the collector after the schema unit, with an R3.1 clause and its mutant; it is merged and deployed (`8.4-clan-update-redeploy.log`, `8.4-units-redeploy.log`).

### 9.7 Plan-expectation deviations (not defects)

Task 7.1's search scans `research/`, where historical `research/perses.md:216` keeps its superseded claim (§9.2).
Task 5 needed two test-code fixes: `sql()` reads `affectedrows`, and the OOM-order test sets `vm.panic_on_oom = 0` because nixpkgs test instrumentation sets it to 2.
Task 3's `memory_limiter` unknown-key probe did not behave as the plan expected, because `hostmetricsreceiver` ignores unknown top-level keys.
Task 6 applied six adaptations to plan commands, listed in §9.4.

### 9.8 Runtime tests

`vmTests.x86_64-linux.greptimedb-pipeline` passed 7/7 on magnetite and was rerun after PR #3492 (`fix-schema-order-pipeline-20261017-045030.log`).
`vmTests.x86_64-linux.greptimedb-oom-order` passed on pyrite (`6.2-greptimedb-oom-order-20261017-025224.log`), and its mutant failed as required (`6.2-greptimedb-oom-order-mutant-20261017-025351.log`).

## 10. Integration verification (tasks.md 9.1)

### 10.1 Process memory and unit state from the last hour

The process-memory query returned `success` with 13 series, inside the 30-series cap.
The long-lived processes `otelcol-contrib`, `systemd-journald` and `.gitea-wrapped` each hold 60 points.
`greptime` holds 50, because Task 6 Step 17 stopped the store from 08:30:46Z to 08:40:49Z to measure the queue rate; its series has no sample between 08:30:51Z and 08:41:51Z.
Short-lived processes such as `nix-eval-jobs` and `nix-instantiate` hold fewer points, and `.postgres-wrapp` holds 126, consistent with several processes reporting under one executable name.
The unit-state query returned `success` with 216 series; every unit name matches a pattern in `nix eval --json .#lib.otelCollectorSchema.systemdUnits`, and the names include `greptimedb.service` and `opentelemetry-collector.service`.
The owners deployed are `cameron` and `janettesmith`, matching the evaluated `omnigent-host-cameron` and `omnigent-host-janettesmith`; the alias check printed four `PASS` lines per owner and no `FAIL`.

`9.1-process-memory.log`:

```text
$ gq.sh promql fleet 'count_over_time(process_memory_usage_bytes{host_name="magnetite"}[1h])'
success
13
python3.14 57
niks3 6
.postgres-wrapp 126
harmonia-gc 1
nix 2
nix-daemon 1
nix-eval-jobs 9
otelcol-contrib 60
systemd-journald 60
nix-instantiate 2
MainThread 2
.gitea-wrapped 60
greptime 50
```

`9.1-unit-state.log`:

```text
$ gq.sh promql fleet 'count_over_time(systemd_unit_state{host_name="magnetite"}[1h])'
success
216
gitea-mq.service gitea.service greptimedb-envelope.service greptimedb-schema.service greptimedb.service harmonia-gc.service nginx.service niks3-gc.service niks3.service nix-daemon.service nix-grpc-daemon.service nixbot.service omnigent-host-owner-1.service omnigent-host-owner-2.service opentelemetry-collector.service postgresql.service prometheus-node-exporter.service zerotierone.service zfs-assert-root-docker-noautosnap.service zfs-assert-root-greptimedb-noautosnap.service zfs-assert-root-nix-noautosnap.service zfs-assert-root-podman-noautosnap.service zfs-set-root-greptimedb-quota.service zfs-set-root-greptimedb-reservation.service zfs-set-root-home-reservation.service zfs-set-root-nix-quota.service zfs-set-root-nixos-reservation.service
```

`9.1-owner-aliases.log`:

```text
$ systemctl list-units "omnigent-host-*" --all --plain --no-legend
cameron
janettesmith
$ nix eval --json .#lib.otelCollectorSchema.ownerAliases
{"cameron":"owner-1","janettesmith":"owner-2"}
PASS: owner cameron has alias owner-1
$ gq.sh promql fleet 'count_over_time(systemd_unit_state{host_name="magnetite", systemd_unit_name=~".*cameron.*"}[1h])'
PASS: no stored systemd_unit_state systemd_unit_name contains cameron
$ gq.sh promql fleet 'count_over_time(systemd_service_restarts_total{host_name="magnetite", systemd_unit_name=~".*cameron.*"}[1h])'
PASS: no stored systemd_service_restarts_total systemd_unit_name contains cameron
$ gq.sh promql fleet 'count_over_time(systemd_unit_state{host_name="magnetite", systemd_unit_name=~".*owner-1.*"}[1h])'
PASS: alias owner-1 stored (success 8)
PASS: owner janettesmith has alias owner-2
$ gq.sh promql fleet 'count_over_time(systemd_unit_state{host_name="magnetite", systemd_unit_name=~".*janettesmith.*"}[1h])'
PASS: no stored systemd_unit_state systemd_unit_name contains janettesmith
$ gq.sh promql fleet 'count_over_time(systemd_service_restarts_total{host_name="magnetite", systemd_unit_name=~".*janettesmith.*"}[1h])'
PASS: no stored systemd_service_restarts_total systemd_unit_name contains janettesmith
$ gq.sh promql fleet 'count_over_time(systemd_unit_state{host_name="magnetite", systemd_unit_name=~".*owner-2.*"}[1h])'
PASS: alias owner-2 stored (success 8)
```

### 10.2 The next scheduled envelope run

The timer's `NEXT` was 10:02:28 UTC; the run started at 10:02:31 UTC, within the timer's accuracy window, and `LAST` now shows it.
`systemctl status` shows `TriggeredBy: ● greptimedb-envelope.timer`, and `Result=success`, `ExecMainStatus=0`, `ExecMainExitTimestamp=Sat 2026-10-17 10:02:31 UTC`.
The journal read without `sudo` was refused, so it was re-run with `sudo`, as Task 6 did; it shows `greptimedb-envelope: all checks passed` from the scheduled run.
This run is the first after the store restart in §10.3, so R7.2 took its new-invocation path and passed.

`9.1-envelope-scheduled.log`:

```text
$ systemctl list-timers greptimedb-envelope.timer --no-pager
NEXT                         LEFT LAST                              PASSED UNIT                      ACTIVATES
Sat 2026-10-17 11:00:38 UTC 55min Sat 2026-10-17 10:02:31 UTC 2min 30s ago greptimedb-envelope.timer greptimedb-envelope.service

1 timers listed.
Pass --all to see loaded but inactive timers, too.
$ systemctl status greptimedb-envelope --no-pager
○ greptimedb-envelope.service - GreptimeDB runtime envelope
     Loaded: loaded (/etc/systemd/system/greptimedb-envelope.service; linked; preset: ignored)
     Active: inactive (dead) since Sat 2026-10-17 10:02:31 UTC; 2min 31s ago
 Invocation: 25ba426ca78947baaef9df57d987cd33
TriggeredBy: ● greptimedb-envelope.timer
    Process: 1078357 ExecStart=/nix/store/624d8y5kqsbxxd5hh8jfli2rcydfaml5-greptimedb-envelope/bin/greptimedb-envelope (code=exited, status=0/SUCCESS)
    Process: 1078401 ExecStopPost=/nix/store/44jagira13v9bimx30cbjc9kbbx0xz84-observability-notify-resolved greptimedb-envelope.service (code=exited, status=0/SUCCESS)
   Main PID: 1078357 (code=exited, status=0/SUCCESS)
         IP: 116.9K in, 1.9K out
         IO: 0B read, 0B written
   Mem peak: 7.4M
        CPU: 394ms
$ systemctl show greptimedb-envelope -p Result -p ExecMainStatus -p ExecMainExitTimestamp
Result=success
ExecMainExitTimestamp=Sat 2026-10-17 10:02:31 UTC
ExecMainStatus=0
$ journalctl -u greptimedb-envelope --since "-10min" --no-pager
No journal files were opened due to insufficient permissions.
# ADAPTATION (a): the journal read without sudo printed "No journal files were opened due to insufficient permissions", so it is re-run with sudo (as Task 6 Steps 19-21), over the window of the scheduled run.
$ sudo journalctl -u greptimedb-envelope --since "2026-10-17 10:00:00 UTC" --until "2026-10-17 10:05:00 UTC" --no-pager
Oct 17 10:02:31 magnetite systemd[1]: Starting GreptimeDB runtime envelope...
Oct 17 10:02:31 magnetite greptimedb-envelope[1078357]: greptimedb-envelope: all checks passed
Oct 17 10:02:31 magnetite systemd[1]: greptimedb-envelope.service: Deactivated successfully.
Oct 17 10:02:31 magnetite systemd[1]: Finished GreptimeDB runtime envelope.
Oct 17 10:02:31 magnetite systemd[1]: greptimedb-envelope.service: Consumed 394ms CPU time over 464ms wall clock time, 7.4M memory peak, 116.9K incoming IP traffic, 1.9K outgoing IP traffic.
```

### 10.3 No gap in fleet across a store restart

The store was restarted at T0 = 1792228327 (2026-10-17T09:12:07Z) and was `active` at once.
Fifteen minutes later the range query returned `success`, 26 points, and `min` equal to `max` at 216 unit series, so no two-minute window across the restart lost a series.
`NRestarts=0` confirms the restart was the manual one, not an automatic restart.

`9.1-restart-no-gap.log`:

```text
T0=1792228327
active
$ gq.sh promql_range fleet 'count(count_over_time(systemd_unit_state{host_name="magnetite"}[2m]))' 1792227727 1792229227 60
"success"
26
{"min":216,"max":216}
$ systemctl show greptimedb -p ActiveEnterTimestamp -p NRestarts
ActiveEnterTimestamp=Sat 2026-10-17 09:12:09 UTC
NRestarts=0
```

### 10.4 The failure notice and its RESOLVED pair

The two `fleet-alerts` messages from `8.6-resolved.log`, with their times (Unix seconds, then UTC):

```text
{"time":1792221796,"message":"FAILED greptimedb-envelope.service on magnetite"}
{"time":1792221873,"message":"RESOLVED greptimedb-envelope.service on magnetite"}
```

The FAILED notice was posted at 2026-10-17T07:23:16Z and the RESOLVED notice at 2026-10-17T07:24:33Z; exactly these two messages are on the topic for that episode.

### 10.5 Verify precheck

`9.1-verify-precheck.log`:

```text
$ git log --oneline $(git merge-base HEAD origin/main)..HEAD | wc -l
23
$ grep -c "^- \[x\]" tasks.md
28
$ git log --oneline origin/main -- <S1 paths>
7f5fbad47 fix(otel-collector): start the collector after the store databases exist
22fd7cead test(greptimedb): add pipeline and OOM-order runtime tests to the on-demand lane
9a0aa6ccb fix(greptimedb): enable prom_store, which also gates the PromQL query API
cebb618c8 feat(greptimedb): hourly runtime envelope for the store
57f138866 feat(otel-collector): collect magnetite metrics into the store, with failure notices
76694545b feat(greptimedb): run the telemetry store on magnetite with its evaluation-time envelope
f9451f3ef feat(pkgs): add greptimedb-bin 1.2.1 and move ntfy-send to pkgs/by-name
```

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: §8a and §8c record designation and alphabet findings
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

The operator's authenticated dashboard check, the one item previously open, passed on 2026-10-17 (§9.4).
The remaining warnings are §8a, nouns without a designation row, and §8c, two non-world phenomena in a behavioral requirement; both are non-blocking findings for the retrospective.
No 8.x or 9.1 expectation failed.

**Next step**:

plan.md Task 7 Step 15 onwards: the roborev and documenter sub-gates, the retrospective, then archive.
