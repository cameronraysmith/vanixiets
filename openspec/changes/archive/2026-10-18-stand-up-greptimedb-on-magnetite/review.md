# S1 holistic review

A read-only review of slice S1 as merged and deployed, read against this change's proposal, design, specs and tasks and the observability decision records, made on 2026-10-17 by a subagent in place of the paid codex review the plan named (plan.md Task 7 Step 15), at the operator's direction.
It asked four questions: critical oversights, significant architecture improvements, checks that cannot fail or properties no check covers, and checks or mechanisms that cost more than the invariant they protect.
It found nothing critical and twelve findings, five significant and seven minor; every finding was applied, as tasks.md section 10 records with its verification, and charter v14 to v16 record the amendments to the decision records.

| Finding | Category | Severity | Applied in |
|---|---|---|---|
| F1 a crashed long-running unit silenced its own later failures | oversight | significant | tasks.md 10.1, charter v14 |
| F2 R7.2 compared a ratcheting `memory.peak` that counts page cache | oversight | significant | tasks.md 10.2, charter v14 |
| F3 the no-table-TTL rule contradicted S7's 14-day `fleet` logs table | oversight | significant | tasks.md 10.5, charter v15 |
| F4 the collector and the store kept separate database lists | oversight, architecture | significant | tasks.md 10.4, charter v15 |
| F5 the credential-holder clause cost about 2 GiB of evaluation per pull request | overzealous | significant | tasks.md 10.7, charter v16 |
| F6 design D8 claimed S4 restructures nothing S1 deployed | oversight | minor | tasks.md 10.6, charter v15 |
| F7 the failure-wiring clause compared against a literal copy of the unit list | check that cannot fail | significant | tasks.md 10.8, charter v16 |
| F8 several envelope clauses had no negative control | check gap | minor | tasks.md 10.10, charter v16 |
| F9 about half of R3.1's and R7.1's clauses copied module literals | overzealous | significant | tasks.md 10.9, charter v16 |
| F10 the unknown-key probe tested upstream's validator | overzealous | minor | tasks.md 10.9, charter v16 |
| F11 the users-file oracle mutants tested the check's own validator | overzealous | minor | tasks.md 10.9, charter v16 |
| F12 `ntfy-send` relied on its callers to put curl on PATH | architecture | minor | tasks.md 10.3, charter v14 |

The S3 handoff the fixes create: notifier stamps under `/var/lib/observability-notify` now contain `posted` or `suppressed`, so the R9.1 FIRING budget counts only `posted` stamps.

## Report

The review's report, verbatim:

I found nothing critical in S1. Nothing loses data or exposes a credential, nothing starves CI, and nothing breaks a later slice past repair. There are 12 findings: 5 significant and 7 minor. I worked against origin/main, which matches the working copy for every S1 file, and only read `magnetite.zt`.

**F1 (category 1, significant): a unit that crashes and auto-restarts silences its own later failures.**
- **Evidence:**
  - The template skips a post while `/var/lib/observability-notify/<unit>` exists (`flake-module.nix:305`).
  - The stamp is cleared only when `SERVICE_RESULT=success` at the unit's stop (`:95`).
  - In systemd 261, an auto-restart passes through the failed state (`src/core/service.c:98`), so `OnFailure=` fires on every crash. The stop that comes before an auto-restart is never a success, though.
  - So after the first crash of `opentelemetry-collector` (live: `Restart=always`, `RestartUSec=100ms`, `StartLimitBurst=5` per 10s) or of `greptimedb`, the stamp stays until the next clean stop, usually a deploy.
  - Every later crash is skipped, and the RESOLVED notice never follows the automatic recovery. The store's crashes are still caught by R7.2's `NRestarts`/OOM-journal clause; nothing catches the collector's.
  - The collector's 100 ms restart delay with the default start limit also leaves it permanently failed after any five quick start failures in a row, such as a briefly missing credential file [INFERENCE].
- **Change (S1 now):**
  - For units that aren't oneshots, end the episode on a successful start: add `ExecStartPost=-+${resolved}` with a "started" mode that posts RESOLVED and removes the stamp.
  - Give the collector `RestartSec=5s` and `StartLimitIntervalSec=0`, as the store already has.

**F2 (category 1, significant): R7.2's `memory.peak` clause ratchets up, and one envelope stamp hides every other clause.**
- **Evidence:**
  - `greptimedb-envelope.nix:176` compares `memory.peak` against `MemoryHigh`. `memory.peak` is a high-water mark for the whole invocation, and it counts page cache: live `memory.stat` shows file 42 MB beside anon 109 MB, peak 169 MB.
  - With 4 GiB of write cache and 4 GiB of read cache on local disk, file pages will plausibly fill the cgroup up to `memory.high`, where reclaim starts [INFERENCE; most likely under S4's load].
  - From then on the envelope fails every hour until the store restarts. It never exits successfully, so no RESOLVED is posted and the stamp stays (F1's mechanism). Later R6.2, R7.3 and R7.4 failures are then silent.
- **Change:** regulate "throttled" directly. Track the delta of the `high` counter in `memory.events` per invocation, the way `oom_kill` and `max` are already tracked, or compare anon memory only. Amend ADR-007 E7.2 to match. Optionally put the `FAIL` lines into the notice. S1 now; the ADR amendment goes with it.

**F3 (category 1, significant): S1's retention rule contradicts S7's 14-day `fleet` logs table.**
- **Evidence:**
  - The envelope fails on any base table in the three databases that sets its own `ttl=` (`greptimedb-envelope.nix` line 164 in `modules/lib/`).
  - The spec says "no part of a database SHALL keep its series on a retention other than the database's own" (`telemetry-store/spec.md:6`).
  - ADR-004, ADR-006:14 and `components/greptimedb.md:21,113` put a 14-day logs table inside 30-day `fleet`. The envelope will fail hourly from S7's first deploy.
- **Change:** reword the spec now so a declared per-table TTL is allowed. In S7, replace "no table TTL" with a match against a declared map such as `{ "fleet.<logs>" = "14d"; }`.

**F4 (categories 1 and 2, significant): the collector and the store each keep their own list of database names, with nothing tying them together.**
- **Evidence:**
  - The collector routes and exports by `otelCollectorSchema.databases` (`schema.nix:78`).
  - The store creates its databases from magnetite's `services.greptimedb.databases` attrset.
  - Neither check, nor any assertion, relates the two.
  - If S2 or S7 adds a database to one list only, the store answers 400, which the exporter treats as permanent and drops: the same mechanism that lost 279 points at first deploy.
- **Change (S1 now):** keep one source, `schema.databases = { fleet = "30d"; devloop = "365d"; agent = "90d"; }`, and have magnetite read it. Or add an assertion in the ingress module that the names are equal whenever `services.greptimedb.enable` is set.

**F5 (category 4, significant): the credential-holder clause costs about as much to evaluate as building magnetite's whole configuration.**
- **Measurements** (`NIX_SHOW_STATS`, `drvPath`, cold):

  | What was evaluated | Allocation | CPU |
  |---|---|---|
  | `greptimedb-envelope` check | 2.03 GiB | 9.1 s |
  | `otel-collector-config` check | 0.46 GiB | 1.7 s |
  | `nixbot-wiring` (existing check, for comparison) | 0.54 GiB | 2.1 s |
  | magnetite toplevel | 2.61 GiB | 11.8 s |
  | `LoadCredential` projection over every magnetite service (`greptimedb-envelope.nix:342`) | 2.03 GiB | 10.4 s |
  | store settings alone | 0.17 GiB | — |

- **Change (S1 now):** move `credentialHolders` into a NixOS `assertions` entry on magnetite. The machine toplevel, which CI evaluates anyway, already forces every unit, so the extra cost is close to zero and no failure mode is lost. This cuts about 1.8 GiB from every PR's evaluation.

**F6 (category 1, minor): D8's claim that S4 restructures nothing S1 deployed is false.**
- **Evidence:** the agent pipelines hard-code `exporters = [ "forward" ]` (`flake-module.nix:259,270`). On a host with only the agent role, nothing receives from that connector, so `otelcol validate` rejects the configuration [INFERENCE: not run].
- **Change:** correct D8 now. S4 then picks the exporter by role: `forward` when the ingress role is on the same host, an OTLP exporter to the ingress otherwise. Separately, the notifier template could become its own `flake.modules.nixos.observability-notify`, so magnetite's ZFS notices don't depend on its collector role membership (S3 or S4).

**F7 (category 3, significant): R3.1's failure-wiring clause can't fail when a new disk unit is added.**
- **Evidence:** `notifiedUnits` (`otel-collector-config.nix:33`) is a literal copy of the host's list. A new `zfs-set-root-foo-quota` that isn't listed passes both copies, even though `telemetry-store/spec.md:146` requires every disk-share unit to notify.
- **Change (S1):** make it relational. Every magnetite service matching `greptimedb*`, `zfs-set-*`, `zfs-assert-*` or `opentelemetry-collector` must be in `observability-notify.units`, and every listed name must have an `ExecStart`, so a typo isn't silently created as an empty stub unit. Delete the literal copy.

**F8 (category 3, minor): parts of the hourly envelope have never been shown able to fail.**
- **Evidence:**
  - Only R7.2 was forced to fail on the host (verify §9.5).
  - The build-time rehearsal tests `greptimedbSql` alone. The TTL-override and R6.3 string matches, the R6.2 awk sum and R7.3 have no negative control, although `components/greptimedb.md:130` names a scratch legacy-format table as R6.3's control.
  - `create_options` does render as space-separated `key=value` (v1.2.1 `src/table/src/requests.rs:219-241`), so the matches are probably right.
  - "SHALL NOT keep them past it" has no test at all.
- **Change (S1 or S7):** in the `greptimedb-pipeline` container test, run the envelope's SQL clauses against a table created `WITH (ttl='1d')` and one with `sst_format='primary_key'`, and require a failure. Optionally add a short-TTL expiry case.

**F9 (category 4, significant): about half of R3.1's and R7.1's clauses can't catch a real mistake.**
- **Clauses that rebuild the expected value from the same source the module uses:**
  - systemd units equal `schema` (`:230`)
  - routing conditions
  - exporter headers
  - node keep-list regex
  - alias statement text
  - process filter text
- **Literal copies of module literals:**
  - `process.metrics`, paging, node flags, `MemoryMax` "64M", basicauth
  - the limiter values 384/512M/300
  - `expectedScrapeTargets` (`:58`), already covered by the loopback property
  - `maxNames == 30` (`:212`), a number with no consumer until S4
  - R7.1's 15-value `memoryKnobs` (`greptimedb-envelope.nix:296`)
  - `storageBucket`, `storageRoot`
  - `httpLoopback` (`:332`), which repeats `listenersLoopback` in the same check, and that clause repeats the module's own gRPC assertion
- **Mutants:** those on such clauses (for example `systemdUnitsDiverge`, `diskoQuotaDiffers` on a constant) only show the clause can fail on made-up input.
- **Change (S1 cleanup):**
  - Delete the clauses above and their mutants.
  - Move the security properties (loopback, protocols off, `user_provider`, telemetry off, the six process identifiers off) into `assertions` in `greptimedb.nix` and the agent module.
  - Keep the relational clauses: ≤40 units on the host, owner aliases, queue arithmetic, the override scope, ordering after the schema job, R1.2 against the store version, disko against the dataset binding, the users-file generator run.
  - Drop `schema.process.maxNames` until S4.

**F10 (category 4, minor): the unknown-key probe tests upstream.**
- **Evidence:** the probe (`otel-collector-config.nix:451`) checks that `otelcol validate` rejects unknown keys, which is upstream's behaviour, not ours, and it has already needed one rework. `test -s $validated` repeats what the magnetite toplevel build already establishes.
- **Change:** delete both. The check then needs no build step, only its evaluation-time asserts.

**F11 (category 4, minor): parts of the users-file and SQL-helper checks verify themselves.**
- **Evidence:** the users-file check's oracle mutants (fifth line, `=` inside a password) test the check's own validator. The Python-stub rehearsal tests 40 lines of `curl`/`jq` against recorded 1.2.1 answers that can go stale on an upgrade.
- **Change:** keep the generator run. Drop the oracle mutants. Optionally move the rehearsal's three cases into the pipeline test against the real store, together with F8.

**F12 (category 2, minor): `ntfy-send` isn't self-contained.**
- **Evidence:** the package doesn't depend on `curl`, so the notifier sets `path = [ curl ]` and the RESOLVED hook exports its own `PATH`.
- **Change (S1):** add `runtimeInputs = lib.optional (!isDarwin) curl` to the package and delete both workarounds.

Measurements were cold single `nix eval` runs, not an A/B/A/B benchmark. Everything else was read from source, from verify.md, or from read-only `systemctl`/`cgroup` reads on `magnetite.zt`. I ran no checks, builds or tests.
