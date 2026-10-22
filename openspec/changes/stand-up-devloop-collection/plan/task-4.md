### Task 4: `devloop-reconcile` (deploy D4)

Implements `tasks.md` 4.1–4.8 (design D6, D10, D11, D14, D16; DCI `devloop-queries binds the export queries to nixbot's migrations`, `The nixbot readers authenticate by peer and hold column grants only`, `devloop-reconcile compares CI rows with nixbot every day`, `devloop-reconcile compares batch events with the journal every day`, `devloop-reconcile compares deploy records with the file and the current system`, `devloop-reconcile runs daily as its own reader`, `devloop-ingest shows the collection path and the reconcile able to fail`, `gitea-mq's five batch messages are parsed from its journal`, `magnetite's collector ships its own deploy records`; DC `A gap in the dev-loop history reaches a person within a day`, `Every dev-loop event is recorded once and kept for a year`; TSI `Credentials exist only as activation-resolved files owned by non-worker users`, `Failure notices are posted to one topic`; FAI `The evaluator queries each rule's database as the regulators' store account`).
Each judge is written first and shown failing before the code it judges exists: the reconcile legs of `devloop-queries` fail at evaluation before `reconcileQueries` exists, the `reconcile` case of `devloop-ingest` fails at evaluation before `devloopReconcile` exists, magnetite's kill-order assertion fails before the unit exists, its R8.2 holder assertion fails once the unit loads the credential and before the holder list admits it, and R3.1 accepts the mutant `reconcileNotNotified` before its policy names `devloop-*`.
Then the code lands and each judge passes, every new assertion is shown able to fail by an `extendModules` override of magnetite, and every reconcile clause is shown failing by its `devloop-ingest` mutant on magnetite before the pull request merges.
The reconcile's comparison logic, its seven clauses, its exit codes and its PostgreSQL queries (as `devloop-reconcile`, against the input's 37 migrations on PostgreSQL 16.15, with grants that included `builds (id, branch, finished_at)` and `build_attributes (build_id, attr, finished_at)`, the only columns the queries read) were rehearsed during planning on stibnite against a canned-store stub: the unmutated inputs printed seven `ok` lines and exit 0, each of the C1–C7 failure inputs printed its clause's `FAIL` line and exit 1, and an unreadable store, an invisible journal, a missing deploy record and the day `2026-02-30` each exited 2 (scratch files under `/tmp`, not kept).

**Files:**
- Modify: `modules/nixos/devloop-collection.nix` (Task 3's final file, header `{ config, lib, ... }:`): the `let` bindings `reconcileQueries` and `devloopReconcile` after `grantColumns`; `reconcileQueries` inherited into `flake.lib.devloopCollection`; `flake.lib.devloopReconcile`; `systemd.services.devloop-reconcile` and `systemd.timers.devloop-reconcile` in `flake.modules.nixos.devloop-collection`, directly after Task 3's `systemd.services.devloop-pg-grants = { … };` block
- Modify: `modules/checks/devloop-queries.nix` (Task 2's file): header comment, `clockVars`, `fixtureFiles`, `roleQueries`, `assertions`, `mutants`
- Create: `modules/checks/devloop-queries/reconcile-fixtures.sql`
- Modify: `modules/vm-tests/devloop-ingest.nix` (Task 3's file): the outer `let` (`unitMutants`, the case `reconcile`, `cases`, `credentialConsumers` and the helper bindings below) and the `containers.store` module
- Modify: `modules/checks/otel-collector-config.nix:32-40` (`notifiedByPolicy`), `:335` (the policy clause's message), and the `mutants` attrset (`:372-513` today; Task 3 adds `logsQueueNotPersistent` and `otlpInLogsPipeline` to it), lines as on `main@origin` `5f94a946baae`
- Modify: `modules/machines/nixos/magnetite/default.nix:329-343` (`services.observability-notify.units`), `:651-654` (R8.2 `regulator-password` holders), `:716-721` (`order`), `:734-747` (kill-order assertion), and a new block after `:779` (the end of `systemd.services.greptimedb-envelope`), lines as on `main@origin` `5f94a946baae`; Tasks 1 and 2 each add one import line at `:53-77` and Task 3 adds `"devloop-pg-grants"` to the notified units, so at this task's base the list starts two lines later and every later anchor is three lines later `[INFERENCE]`, confirmed by Step 1
- Modify: `openspec/changes/stand-up-devloop-collection/tasks.md` (tick 4.1–4.6)
- Evidence (git-ignored): `logs/s2-evidence/4.*-*.log`

**Interfaces:**
- Consumes (Task 1): `flake.lib.deployRecordScript { pkgs; hostName; file ? "/var/log/deploy-record.jsonl"; currentSystem ? "/run/current-system"; }`, the store path of a script taking the activated closure as `$1` and appending `{"host":…,"closure":…,"previous_closure":…,"ts":…}` in that key order.
- Consumes (Task 2): `flake.lib.devloopCollection.{queries,ddl,pipelines,grantSql}`; `ddl.ci_attribute` contains `'append_mode' = 'false'` exactly once; `pipelines.batch_event` contains the VRL line `        .flaky = if a.flaky == null || a.flaky == "" { null } else { to_bool!(a.flaky) }` exactly once, and without it the pipeline's `transform` entry for `flaky` writes null (Task 2's Interfaces); `grantSql` contains the line `GRANT SELECT ("build_id", "attr", "finished_at") ON "build_attributes" TO "devloop-reconcile";`.
  In `modules/checks/devloop-queries.nix`'s `perSystem` `let`: `dc`, `clockVars` (name → SQL timestamp expression, passed to every query as `-v <name>=<value>`), `fixtureFiles` (loaded in order as `postgres` after the grants), `roleQueries = queries: [ { name; role; types; sql; executions = { <label> = [ <EXECUTE argument> … ]; }; } … ]` (each execution's result, a header line and tab-separated rows, at `$(result <name> <label>)`), `assertions = [ { label; script; } … ]` (each prints `ok: <label>` or `FAIL: <label>`), `replaceOnce = name: from: to: text:`, `real` and `mutants.<name>` (each run a fresh database with its own `grantSql`, `queries` and `afterFixtures`, running every `roleQueries` entry and every assertion; a rejected mutant prints `mutant <name> rejected: <first line matching 'FAIL: |ERROR: '>`) (Task 2's Interfaces).
- Consumes (Task 3): `modules/nixos/devloop-collection.nix` as Task 3 leaves it: a flake-parts module `{ config, lib, ... }:` whose top-level `let` ends with `grantColumns` before `in`, whose `flake.lib.devloopCollection = { inherit abandonMarker ddl pipelines queries grants grantSql; selects = …; inherit questions batchEventKeys; };` is the module's first attribute, and whose `flake.modules.nixos.devloop-collection` is a function `{ config, pkgs, ... }:` returning a plain attrset (no `mkIf` or `mkMerge`) that reads the file's outer `lib`, with `systemd.services.devloop-pg-grants`; `grants.devloop-reconcile` = `builds [ "id" "branch" "finished_at" ]` and `build_attributes [ "build_id" "attr" "finished_at" ]`; the PostgreSQL roles `opentelemetry-collector` and `devloop-reconcile`; the receivers `"sqlquery/ci_attribute"` and `"sqlquery/ci_build"` (`queries = [ { sql = queries.<table>; tracking_column = "finished_at"; tracking_start_value = "1970-01-01T00:00:00.000000Z"; logs = [ { body_column = "body"; attribute_columns = <the table's allow-list column names>; } ]; } ]`), `"journald/gitea-mq"` (`operators = [ key_value_parser "parse-message" from body.MESSAGE, retain "keep-list" of attributes.<batchEventKeys>, remove "drop-body" ]`) and `"file_log/deploy-record"` (`include = [ "/var/log/deploy-record.jsonl" ]`); magnetite's notified units already list `devloop-pg-grants`.
  In `modules/vm-tests/devloop-ingest.nix` (header `{ self, inputs, ... }:`): the outer `let` with `unitMutants = { };`, one binding per case and `cases = [ firstStart noAutoCreate overlap tableShape switch documentedQueries ];`, `testScript = builtins.readFile ./devloop-ingest/helpers.py + lib.concatStringsSep "\n" cases`; `vars = "/run/devloop-ingest-vars"` and `credentialConsumers`; the container `store` (`networking.hostName = "store"`), which renders each `unitMutants.<name> = { unit; module; }` to `/etc/devloop-ingest/mutants/<name>.conf`; the stub `gitea-mq.service`, a RemainAfterExit oneshot printing each line of /run/devloop-ingest/gitea-mq-lines to standard output with a 50 ms pause; that path is a symlink to `/etc/devloop-ingest/gitea-mq-lines.txt` (13 lines, eleven matching D7's pattern, among them `batch built` and `batch done` lines with `landed`, `ejected`, `builds` and `flaky`) or to the empty `/etc/devloop-ingest/gitea-mq-empty.txt`; nixbot's project `1` and builds `9001`, `9002` (`gitea-mq/batch/1`, null `pr_number`) and `9101`; the helpers `gsql`, `admin_sql`, `psql`, `nixbot_rows`, `collector_restart`, `reset_devloop` (leaves the collector stopped, keeps the journal), `send_failed`, `wait_rows` (until at least `n` rows), `key_counts` (`(rows, distinct primary key and time index)`), `utc_today` and `config()` (key `vars`); every Task 3 case ends with the collector running, no drop-in and the tables reset (Task 3's Interfaces).
- Consumes (S1, S3): `config.flake.lib.greptimedbSql pkgs { url; user; }` (`modules/lib/greptimedb-envelope.nix:48-89`), which reads `$CREDENTIALS_DIRECTORY/<user>-password` into `curl --config -`, posts to `<url>/v1/sql`, prints the one records result as TSV with `NULL` for null, and exits 1 on a transport failure, a non-200 answer, a body that is not one records result, or zero rows; magnetite's R8.2 holder assertion and kill-order assertion (`modules/machines/nixos/magnetite/default.nix:642-750`); R3.1's `notifiedByPolicy`, `failures` and `mutants` (`modules/checks/otel-collector-config.nix:35-40`, `:202-366`, `:372-513`).
- Produces: `flake.lib.devloopCollection.reconcileQueries.{attributes,builds,batchBuilds,currentFinish}`, PostgreSQL texts without a trailing `;`, prepared over `$1`, `$2` (`timestamptz`, the window `[$1, $2)`), and for `currentFinish` also `$3` (`jsonb`, an array of `{ "build_id": <int>, "attr": <string or null>, "finished_at_us": <int> }`, `attr` null for a build); times are epoch microseconds, the form the store returns for `TIMESTAMP(6)` (`logs/s2/spike-dedup.md:176-180`):
  - `attributes`: `build_id`, `attr`, `finished_at_us` of every `build_attributes` row finished in the window;
  - `builds`: `build_id`, `finished_at_us` of every `builds` row finished in the window;
  - `batchBuilds`: one row, `batch_builds`, the count of builds on a `gitea-mq/batch/` branch finished in the window;
  - `currentFinish`: of the keys of `$3` whose `finished_at_us` lies in the window, those nixbot does not explain, as `build_id`, `attr` (empty for a build), `stored_us`, `current_us` (`absent` when nixbot has no such row); a key is explained when nixbot has it with a null or later `finished_at`.
- Produces: `flake.lib.devloopReconcile pkgs { psql; journalctl ? "journalctl"; storeUrl ? "http://127.0.0.1:4000"; hostName; deployRecord ? "/var/log/deploy-record.jsonl"; currentSystem ? "/run/current-system"; }`, a `writeShellApplication` named `devloop-reconcile` whose `psql` is the path of a `psql` binary; environment `DEVLOOP_RECONCILE_DAY` (default yesterday, UTC) and `DEVLOOP_RECONCILE_DATABASE` (default `devloop`), and `CREDENTIALS_DIRECTORY` holding `regulator-password`; stdout one line per clause in order C1–C7, `devloop-reconcile: C<n> <name>: ok` or `devloop-reconcile: C<n> <name>: FAIL <detail>`; stderr `devloop-reconcile: cannot read <source>` before exit 2; exit 0, 1 (any `FAIL`) or 2 (nixbot, the journal, the deploy record, the current system or the store unreadable, or a malformed environment value).
- Produces: `devloop-reconcile.service` and `devloop-reconcile.timer` as the Global Constraints state, plus the `greptimedb-envelope` hardening set (`modules/nixos/greptimedb.nix:57-73`); `LoadCredential` is set by the host, as for `greptimedb-envelope`, so the module stays free of clan vars.
- Produces: the `devloop-queries` legs labelled `reconcile: …` and its mutants `reconcileGrantWithoutFinishedAt` and `currentFinishIgnoresDuplicates`; the `devloop-ingest` case `reconcile`, its Nix-side `unitMutants` `omitCached`, `omitNullPr`, `noKeyValueParser`, `deployRecordOtherPath` and its runtime mutants `appendModeAttribute`, `silentStub`, `pipelineWithoutFlaky`, `snippetSwapsClosures`; R3.1's mutant `reconcileNotNotified`; magnetite's holder list `[ "devloop-reconcile" "fleet-alert" "greptimedb-envelope" ]`, `devloop-reconcile` added to the notified units, and the kill-order message starting `magnetite: R7.1, S3 design D12 and S2 design D11 require`.

- [ ] **Step 1: Confirm the base and the anchors**

Run from `$REPO`:

```bash
mkdir -p logs/s2-evidence
{
  pwd
  jj git fetch
  jj log --no-graph -r '::main@origin' --limit 6 -T 'commit_id.shortest(12) ++ " " ++ description.first_line() ++ "\n"'
  rg -n '^\{ config, lib, \.\.\. \}:|^in$|grantColumns = |flake\.lib\.devloopCollection = \{|inherit questions batchEventKeys;|flake\.modules\.nixos\.devloop-collection =|systemd\.services\.devloop-pg-grants = \{' modules/nixos/devloop-collection.nix
  rg -n 'clockVars = \{|fixtureFiles = \[|roleQueries = queries: \[|^      assertions = \[|replaceOnce =|^      mutants = \{|grantWithoutError = real' modules/checks/devloop-queries.nix
  rg -n 'unitMutants = \{|cases = \[|credentialConsumers = \[|containers\.store =|documentedQueries =' modules/vm-tests/devloop-ingest.nix
  rg -n 'services\.observability-notify\.units = \[|regulator-password = \[|fleet-alert = unitAdj|order\.opentelemetry-collector > order\.fleet-alert|systemd\.services\.greptimedb-envelope = \{' modules/machines/nixos/magnetite/default.nix
  rg -n 'notifiedByPolicy =|unit is not notified|listedWithoutService =|schemaOrderDropped =' modules/checks/otel-collector-config.nix
} 2>&1 | tee logs/s2-evidence/4.0-base-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `pwd` prints `$REPO`; the log lists Task 3's merge above Task 2's and Task 1's; every pattern matches once in its file; magnetite's anchors print at `:331`, `:654`, `:723` and `:759`, the list two lines and the others three lines below `main@origin` `5f94a946baae`'s `:329`, `:651`, `:720` and `:756`, and the notified-units list's first element is `"devloop-pg-grants"`.
Record the printed line numbers in the log; the edits below quote the text they replace, so a different number changes nothing but the citation.
If a pattern is missing, stop and report to the orchestrator, because Task 2's or Task 3's names then differ from this task's Interfaces.

- [ ] **Step 2: Show the reconcile does not exist yet (RED, evaluation)**

Run:

```bash
{
  nix eval --json .#.lib.devloopCollection --apply 'c: c ? reconcileQueries'
  nix eval --json .#.lib --apply 'l: l ? devloopReconcile'
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services --apply 's: s ? devloop-reconcile'
} 2>&1 | tee logs/s2-evidence/4.1-absent-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `false`, `false`, `false`.

- [ ] **Step 3: Write the reconcile fixtures for `devloop-queries`**

Create `modules/checks/devloop-queries/reconcile-fixtures.sql` with exactly:

```sql
-- devloop-reconcile's PostgreSQL side (S2 design D11, tasks.md 4.1), over the
-- window [2026-10-20 00:00, 2026-10-21 00:00) UTC that clockVars'
-- window_start and window_end name. Ids from 9100 keep these rows apart from
-- fixtures.sql, whose rows lie within 30 minutes of the build's clock, after
-- the window. Loaded as postgres after fixtures.sql.
INSERT INTO projects (id, forge, forge_repo_id, owner, name, default_branch, url)
  OVERRIDING SYSTEM VALUE
  VALUES (9100, 'gitea', 'reconcile-fixture', 'reconcile', 'fixture', 'main', 'https://gitea.invalid/reconcile/fixture');
INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at)
  OVERRIDING SYSTEM VALUE
  VALUES
    -- a pull-request build inside the window
    (9101, 9100, 1, 'c9101', 'pr-41', 41, 'succeeded', '2026-10-20T09:00:00Z', '2026-10-20T09:01:00Z', '2026-10-20T10:00:00.123456Z'),
    -- a merge-queue batch build inside the window
    (9102, 9100, 2, 'c9102', 'gitea-mq/batch/7', NULL, 'succeeded', '2026-10-20T10:30:00Z', '2026-10-20T10:31:00Z', '2026-10-20T11:00:00Z'),
    -- a batch build finishing exactly at the window's end, which is outside it
    (9103, 9100, 3, 'c9103', 'gitea-mq/batch/8', NULL, 'succeeded', '2026-10-20T23:00:00Z', '2026-10-20T23:01:00Z', '2026-10-21T00:00:00Z'),
    -- a build finishing one microsecond before the window
    (9104, 9100, 4, 'c9104', 'main', NULL, 'succeeded', '2026-10-19T23:00:00Z', '2026-10-19T23:01:00Z', '2026-10-19T23:59:59.999999Z'),
    -- a build finishing exactly at the window's start, which is inside it
    (9106, 9100, 6, 'c9106', 'main', NULL, 'succeeded', '2026-10-19T23:30:00Z', '2026-10-19T23:31:00Z', '2026-10-20T00:00:00Z');
INSERT INTO build_attributes (build_id, attr, status, cached, finished_at)
  VALUES
    (9101, 'checks.x86_64-linux.a', 'succeeded', false, '2026-10-20T10:00:00.123456Z'),
    (9101, 'checks.x86_64-linux.cached', 'skipped_local', true, '2026-10-20T10:00:00.123456Z'),
    -- restarted after the window and finished again
    (9102, 'checks.x86_64-linux.restarted', 'succeeded', false, '2026-10-21T00:30:00Z'),
    -- restarted and not finished again
    (9102, 'checks.x86_64-linux.running', 'building', false, NULL),
    (9104, 'checks.x86_64-linux.old', 'succeeded', false, '2026-10-19T23:59:59.999999Z'),
    -- finished exactly at the window's start, which is inside it
    (9106, 'checks.x86_64-linux.midnight', 'succeeded', false, '2026-10-20T00:00:00Z');
```

Every `NOT NULL` column without a default is set: `projects` per `0001_initial.sql:4-21`, `builds.number` and `commit_sha` and `branch` per `:25-50`, and `build_attributes.log_size`/`log_truncated` default per `0020_log_metadata.sql:9-10` (`Mic92/nixbot@d020013fa:nixbot/nixbot/migrations/…`); the ids are `GENERATED ALWAYS`, hence `OVERRIDING SYSTEM VALUE`.
The epoch microseconds the assertions below expect are `2026-10-20T00:00:00Z` = `1792454400000000`, `10:00:00.123456Z` = `1792490400123456`, `11:00:00Z` = `1792494000000000`, `12:00:00Z` = `1792497600000000` and `13:00:00Z` = `1792501200000000` (`date -u -d … +%s`).
Build `9106` and its attribute finish exactly at the window's start and must be counted (the window is `[start, end)`, plan review F22b); build `9105` stays unused because `reconcileKeys` names it as a build nixbot does not have.
Then snapshot it:

```bash
jj st --no-pager >/dev/null && git ls-files modules/checks/devloop-queries
```

Expected: `fixtures.sql`, `mutant-rename-cached.sql` and `reconcile-fixtures.sql` under `modules/checks/devloop-queries/`.

- [ ] **Step 4: Extend `devloop-queries` with the reconcile's legs and mutants**

The two values each new clause relates: the rows PostgreSQL returns for `reconcileQueries.<q>`, run as `devloop-reconcile` under `grantSql` against the input's migrated schema, and the rows and verdicts `reconcile-fixtures.sql` defines for the window.
The mutants are written with the clauses: `reconcileGrantWithoutFinishedAt` (the grant without `build_attributes.finished_at`, so the run must be refused) and `currentFinishIgnoresDuplicates` (a `currentFinish` that explains every key nixbot still has, so a duplicated stored row, which an append-mode table leaves, would pass C1).

In `modules/checks/devloop-queries.nix`, make these six edits.

1. In the header comment, replace the line

```nix
# Task 4 extends `clockVars`, `fixtureFiles`, `roleQueries`, `assertions`
# and `mutants` with the reconcile's queries run as devloop-reconcile.
```

with

```nix
# Task 4 (design D11): the reconcile's queries, reconcileQueries, run as
# devloop-reconcile over the fixed window of reconcile-fixtures.sql; the
# clauses relate their rows to that file's rows and verdicts, and the
# mutants reconcileGrantWithoutFinishedAt (the role's grant without
# build_attributes.finished_at) and currentFinishIgnoresDuplicates (a
# currentFinish explaining every key nixbot still has) must fail the run.
```

2. In `clockVars`, after `cursor_recent = "t0 - interval '1 minute'";`, insert:

```nix
        window_start = "timestamptz '2026-10-20 00:00:00+00'";
        window_end = "timestamptz '2026-10-21 00:00:00+00'";
```

3. Replace `fixtureFiles = [ ./devloop-queries/fixtures.sql ];` with:

```nix
      fixtureFiles = [
        ./devloop-queries/fixtures.sql
        ./devloop-queries/reconcile-fixtures.sql
      ];
```

4. In `roleQueries`, after the `ci_build` entry's closing `}` and before the list's closing `];`, insert the four entries below, and directly before `roleQueries = queries: [` insert the binding `reconcileKeys` below them; the entries read `queries.reconcile` when a run supplies it (the mutant `currentFinishIgnoresDuplicates`) and `dc.reconcileQueries` otherwise.

```nix
        {
          name = "reconcile_attributes";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).attributes;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
          ];
        }
        {
          name = "reconcile_builds";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).builds;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
          ];
        }
        {
          name = "reconcile_batch_builds";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).batchBuilds;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
          ];
        }
        {
          name = "reconcile_current_finish";
          role = "devloop-reconcile";
          types = [
            "timestamptz"
            "timestamptz"
            "jsonb"
          ];
          sql = (queries.reconcile or dc.reconcileQueries).currentFinish;
          executions.window = [
            ":'window_start'"
            ":'window_end'"
            "'${builtins.toJSON reconcileKeys}'"
          ];
        }
```

```nix
      # Stored keys that nixbot's window lacks, as devloop-reconcile passes
      # them to currentFinish: restarted and finished later (explained),
      # restarted and unfinished (explained), equal to nixbot's (a duplicate,
      # unexplained), unknown to nixbot (unexplained), a build equal to
      # nixbot's (unexplained), an unknown build (unexplained), and a key
      # outside the window (ignored).
      reconcileKeys = [
        {
          build_id = 9102;
          attr = "checks.x86_64-linux.restarted";
          finished_at_us = 1792497600000000;
        }
        {
          build_id = 9102;
          attr = "checks.x86_64-linux.running";
          finished_at_us = 1792497600000000;
        }
        {
          build_id = 9101;
          attr = "checks.x86_64-linux.a";
          finished_at_us = 1792490400123456;
        }
        {
          build_id = 9101;
          attr = "checks.x86_64-linux.gone";
          finished_at_us = 1792501200000000;
        }
        {
          build_id = 9102;
          attr = null;
          finished_at_us = 1792494000000000;
        }
        {
          build_id = 9105;
          attr = null;
          finished_at_us = 1792494000000000;
        }
        {
          build_id = 9101;
          attr = "checks.x86_64-linux.a";
          finished_at_us = 1792627200000000;
        }
      ];
```

5. In `assertions`, after the last entry and before the list's closing `];`, insert:

```nix
        {
          label = "reconcile: attributes returns nixbot's (build_id, attr, finished_at) in the window, the start included, as devloop-reconcile";
          script = ''
            [ "$(tail -n +2 "$(result reconcile_attributes window)" | LC_ALL=C sort)" = ${
              lib.escapeShellArg (
                lib.concatStringsSep "\n" [
                  "9101\tchecks.x86_64-linux.a\t1792490400123456"
                  "9101\tchecks.x86_64-linux.cached\t1792490400123456"
                  "9106\tchecks.x86_64-linux.midnight\t1792454400000000"
                ]
              )
            } ]
          '';
        }
        {
          label = "reconcile: builds returns nixbot's (id, finished_at) in the window, the start included and the end excluded, as devloop-reconcile";
          script = ''
            [ "$(tail -n +2 "$(result reconcile_builds window)" | LC_ALL=C sort)" = ${
              lib.escapeShellArg (
                lib.concatStringsSep "\n" [
                  "9101\t1792490400123456"
                  "9102\t1792494000000000"
                  "9106\t1792454400000000"
                ]
              )
            } ]
          '';
        }
        {
          label = "reconcile: batchBuilds counts the one gitea-mq/batch/ build finished in the window as devloop-reconcile";
          script = ''[ "$(tail -n +2 "$(result reconcile_batch_builds window)")" = 1 ]'';
        }
        {
          label = "reconcile: currentFinish returns exactly the stored keys nixbot does not explain, as devloop-reconcile";
          script = ''
            [ "$(tail -n +2 "$(result reconcile_current_finish window)" | LC_ALL=C sort)" = ${
              lib.escapeShellArg (
                lib.concatStringsSep "\n" [
                  "9101\tchecks.x86_64-linux.a\t1792490400123456\t1792490400123456"
                  "9101\tchecks.x86_64-linux.gone\t1792501200000000\tabsent"
                  "9102\t\t1792494000000000\t1792494000000000"
                  "9105\t\t1792494000000000\tabsent"
                ]
              )
            } ]
          '';
        }
```

6. In `mutants`, after the `grantWithoutError` entry, insert:

```nix
        # The reconcile's grant without build_attributes.finished_at: its
        # attribute query must then be refused (design D10).
        reconcileGrantWithoutFinishedAt = real // {
          grantSql =
            replaceOnce "reconcileGrantWithoutFinishedAt"
              ''GRANT SELECT ("build_id", "attr", "finished_at") ON "build_attributes" TO "devloop-reconcile";''
              ''GRANT SELECT ("build_id", "attr") ON "build_attributes" TO "devloop-reconcile";''
              dc.grantSql;
        };
        # A currentFinish that explains every key nixbot still has, so a
        # duplicated stored row would pass C1 (design D11).
        currentFinishIgnoresDuplicates = real // {
          queries = dc.queries // {
            reconcile = dc.reconcileQueries // {
              currentFinish =
                replaceOnce "currentFinishIgnoresDuplicates"
                  "WHERE NOT c.present OR (c.current_us IS NOT NULL AND c.current_us <= c.finished_at_us)"
                  "WHERE NOT c.present"
                  dc.reconcileQueries.currentFinish;
            };
          };
        };
```

`builtins.toJSON` writes the keys as one line with no single quote, so the quoted `EXECUTE` argument needs no escaping, and psql does not interpolate `:name` inside a quoted literal.
`fixtures.sql`'s rows are relative to `fixture_clock.t0`, the build's clock, which is after 2026-10-21 for every build of this plan, so none of them falls in the window and the expected rows above are exactly `reconcile-fixtures.sql`'s.

- [ ] **Step 5: Run the extended check before `reconcileQueries` exists (RED, evaluation)**

Run:

```bash
nix build --no-link -L .#checks.x86_64-linux.devloop-queries 2>&1 | tee logs/s2-evidence/4.1-devloop-queries-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o "attribute 'reconcileQueries' missing"
```

Expected: `attribute 'reconcileQueries' missing`, and no build starts.

- [ ] **Step 6: Add `reconcileQueries` to `flake.lib.devloopCollection`**

In `modules/nixos/devloop-collection.nix`, add this binding to the top-level `let`, directly after `grantColumns = …;` and before `in` (nixfmt re-indents it to the `let`'s two spaces in Step 22), and replace `inherit questions batchEventKeys;` in `flake.lib.devloopCollection` with `inherit questions batchEventKeys reconcileQueries;`:

```nix
    # The reconcile's nixbot side (design D11), run by devloop-reconcile as
    # the role devloop-reconcile under its column grants (design D10), each
    # prepared over the window [$1, $2) as timestamptz. currentFinish also
    # takes $3, a jsonb array of { build_id, attr (null for a build),
    # finished_at_us }: the stored keys nixbot's window lacks; it returns
    # those nixbot does not explain, a key being explained when nixbot has
    # it with a null or later finished_at (a restart). Times are epoch
    # microseconds, the form the store returns for TIMESTAMP(6).
    # checks.x86_64-linux.devloop-queries runs all four as devloop-reconcile.
    reconcileQueries =
      let
        us = expression: "((extract(epoch FROM ${expression}) * 1000000)::bigint)";
      in
      {
        attributes = lib.concatStringsSep "\n" [
          "SELECT a.build_id::text AS build_id, a.attr AS attr, ${us "a.finished_at"}::text AS finished_at_us"
          "FROM build_attributes a"
          "WHERE a.finished_at >= $1 AND a.finished_at < $2"
          "ORDER BY a.build_id, a.attr"
        ];
        builds = lib.concatStringsSep "\n" [
          "SELECT b.id::text AS build_id, ${us "b.finished_at"}::text AS finished_at_us"
          "FROM builds b"
          "WHERE b.finished_at >= $1 AND b.finished_at < $2"
          "ORDER BY b.id"
        ];
        batchBuilds = lib.concatStringsSep "\n" [
          "SELECT count(*)::text AS batch_builds"
          "FROM builds b"
          "WHERE starts_with(b.branch, 'gitea-mq/batch/') AND b.finished_at >= $1 AND b.finished_at < $2"
        ];
        currentFinish = lib.concatStringsSep "\n" [
          "WITH k AS ("
          "  SELECT r.build_id, r.attr, r.finished_at_us"
          "  FROM jsonb_to_recordset($3) AS r(build_id bigint, attr text, finished_at_us bigint)"
          "  WHERE r.finished_at_us >= ${us "$1"} AND r.finished_at_us < ${us "$2"}"
          "), c AS ("
          "  SELECT k.build_id, k.attr, k.finished_at_us,"
          "    coalesce(a.build_id, b.id) IS NOT NULL AS present,"
          "    ${us "coalesce(a.finished_at, b.finished_at)"} AS current_us"
          "  FROM k"
          "  LEFT JOIN build_attributes a ON k.attr IS NOT NULL AND a.build_id = k.build_id AND a.attr = k.attr"
          "  LEFT JOIN builds b ON k.attr IS NULL AND b.id = k.build_id"
          ")"
          "SELECT coalesce(c.build_id::text, 'NULL') AS build_id, coalesce(c.attr, '') AS attr,"
          "  c.finished_at_us::text AS stored_us,"
          "  CASE WHEN NOT c.present THEN 'absent' ELSE coalesce(c.current_us::text, 'null') END AS current_us"
          "FROM c"
          "WHERE NOT c.present OR (c.current_us IS NOT NULL AND c.current_us <= c.finished_at_us)"
          "ORDER BY 1, 2, 3"
        ];
      };
```

The texts reference only `builds (id, branch, finished_at)` and `build_attributes (build_id, attr, finished_at)`, exactly `grants.devloop-reconcile`, so the reconcile reads neither `pr_number` nor `created_at`; `starts_with` exists in PostgreSQL 16 and is not a pattern match.
`$1` and `$2` are literal in a Nix double-quoted string, which interpolates only `${…}`.
The four texts, run as `devloop-reconcile` on PostgreSQL 16.15 over the input's 37 migrations with those grants and the rows of Step 3, returned exactly the rows Step 4 expects, and with `finished_at` revoked the attribute query failed with `ERROR:  permission denied for table build_attributes` (rehearsed on stibnite during planning).

- [ ] **Step 7: Run `devloop-queries` (GREEN, build)**

Run:

```bash
jj st --no-pager >/dev/null
nix build --no-link -L .#checks.x86_64-linux.devloop-queries 2>&1 | tee logs/s2-evidence/4.1-devloop-queries-$(date -u +%Y%m%dT%H%M%SZ).log | rg 'ok: |FAIL|mutant .* rejected|error:'
```

Expected: the build succeeds; Task 2's `ok:` lines, then `ok: reconcile: attributes returns nixbot's (build_id, attr, finished_at) in the window, the start included, as devloop-reconcile`, `ok: reconcile: builds returns nixbot's (id, finished_at) in the window, the start included and the end excluded, as devloop-reconcile`, `ok: reconcile: batchBuilds counts the one gitea-mq/batch/ build finished in the window as devloop-reconcile` and `ok: reconcile: currentFinish returns exactly the stored keys nixbot does not explain, as devloop-reconcile`; then six rejections in attribute order: `mutant currentFinishIgnoresDuplicates rejected: FAIL: reconcile: currentFinish returns exactly the stored keys nixbot does not explain, as devloop-reconcile`, `mutant errorUnderAlias rejected: …`, `mutant grantWithoutError rejected: …`, `mutant reconcileGrantWithoutFinishedAt rejected: psql:/nix/store/…-devloop-queries-reconcile_attributes-window.sql:<n>: ERROR:  permission denied for table build_attributes`, `mutant renameCached rejected: …` and `mutant selectError rejected: …`, the four of Task 2 with the same reasons as Task 2's log; no `FAIL` outside a rejection line and no `error:`.
The `-U devloop-reconcile` in each `reconcile_*` run (Task 2's runner) and the refused grant mutant are what show the queries ran as that role under the rendered grants.

- [ ] **Step 8: Re-record `devloop-queries`' evaluation cost (evaluation)**

Run:

```bash
log=logs/s2-evidence/4.1-devloop-queries-cost-$(date -u +%Y%m%dT%H%M%SZ).log
{
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/devloop-queries-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.devloop-queries.drvPath; echo
  jq '{gcTotalBytes: .gc.totalBytes, cpuTime}' /tmp/devloop-queries-stats.json
  echo "method: NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/devloop-queries-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.devloop-queries.drvPath"
} 2>&1 | tee "$log"
```

Expected: a `/nix/store/…-devloop-queries.drv` path and `gcTotalBytes` below `536870912`, within a few MB of Task 2's recorded figure, because the task adds four strings, one fixture file and two mutant databases' Nix text `[INFERENCE]`, which this measurement confirms; if it exceeds 0.5 GiB, stop and report it beside Task 2's figure.

- [ ] **Step 9: Write the `reconcile` case and the D11 mutants of `devloop-ingest`**

The case relates, for each clause, the reconcile's verdict and the configuration it ran against: the unmutated container must pass, and each of D11's eight mutants must fail with exactly its clause (two clauses where the mutant removes both clauses' rows), so a reconcile that cannot fail is rejected (devloop-exporters.md:134).
In `modules/vm-tests/devloop-ingest.nix`, make these edits.

1. In the outer `let`, replace `unitMutants = { };` with the block below; Task 3's outer `let` already binds `devloop = self.lib.devloopCollection;`, so the block does not bind it again:

```nix
            # Task 4: an attribute rendered at runtime by a container path.
            currentSystemLink = "/run/devloop-ingest/current-system";
            # replaceOnce NAME FROM TO TEXT: TEXT with its one FROM replaced.
            replaceOnce =
              name: from: to: text:
              assert lib.assertMsg (
                builtins.length (lib.splitString from text) == 2
              ) "devloop-ingest: mutant ${name} must match exactly once";
              builtins.replaceStrings [ from ] [ to ] text;
            # A list option cannot be edited in place, so the receiver
            # mutants below rebuild a whole list; the container asserts that
            # each rebuilt list, given the real values, equals its
            # configuration's, so a mutant differs only where it says.
            queryElement = table: sql: {
              inherit sql;
              tracking_column = "finished_at";
              tracking_start_value = "1970-01-01T00:00:00.000000Z";
              logs = [
                {
                  body_column = "body";
                  attribute_columns = map (
                    column: column.name
                  ) self.lib.otelCollectorSchema.devloop.tables.${table}.columns;
                }
              ];
            };
            journaldOperators = [
              {
                type = "key_value_parser";
                id = "parse-message";
                parse_from = "body.MESSAGE";
              }
              {
                type = "retain";
                id = "keep-list";
                fields = map (key: "attributes.${key}") devloop.batchEventKeys;
              }
              {
                type = "remove";
                id = "drop-body";
                field = "body";
              }
            ];
            # Task 4 (design D11): one collector mutant per D11 row whose
            # change is the collector's configuration.
            unitMutants = {
              # C1: an attribute query that omits cached = true rows.
              omitCached = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."sqlquery/ci_attribute".queries = lib.mkForce [
                      (queryElement "ci_attribute" (
                        replaceOnce "omitCached" "WHERE " "WHERE NOT cached AND " devloop.queries.ci_attribute
                      ))
                    ];
                  };
              };
              # C2: a build query that omits rows with a null pr_number.
              omitNullPr = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."sqlquery/ci_build".queries = lib.mkForce [
                      (queryElement "ci_build" (
                        replaceOnce "omitNullPr" "WHERE " "WHERE pr_number IS NOT NULL AND " devloop.queries.ci_build
                      ))
                    ];
                  };
              };
              # C3: the gitea-mq receiver without key_value_parser.
              noKeyValueParser = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."journald/gitea-mq".operators = lib.mkForce (
                      lib.drop 1 journaldOperators
                    );
                  };
              };
              # C6: file_log/deploy-record reading another path.
              deployRecordOtherPath = {
                unit = "opentelemetry-collector";
                module =
                  { lib, ... }:
                  {
                    services.opentelemetry-collector.settings.receivers."file_log/deploy-record".include = lib.mkForce [
                      "/var/log/deploy-record-other.jsonl"
                    ];
                  };
              };
            };
```

`cached` and `pr_number` are unqualified because only `build_attributes` has `cached` and only `builds` has `pr_number` (`0001_initial.sql:25-63`), and a `WHERE` clause reads input columns, not the select list's aliases.

2. In `credentialConsumers`, after its last element, add `"devloop-reconcile.service"`.

3. The `containers.store` module (the function `{ config, extendModules, pkgs, ... }:` whose body is an attrset with no `let`) gains a `let`: between its argument set's closing `}:` and the attrset's opening `{` (the line before `imports = [`), insert `let`, the bindings below, and `in`:

```nix
                # The deploy-record snippet as the reconcile case runs it,
                # reading the previous closure from a scratch link that the
                # case relinks after each run, as activation relinks
                # /run/current-system after its snippets (design D9).
                deployRecord = self.lib.deployRecordScript {
                  inherit pkgs;
                  hostName = config.networking.hostName;
                  currentSystem = currentSystemLink;
                };
                # C7's mutant: the same snippet's line with closure and
                # previous_closure swapped, appended to the real file.
                mutantLine = self.lib.deployRecordScript {
                  inherit pkgs;
                  hostName = config.networking.hostName;
                  file = "/run/devloop-ingest/mutant-line.jsonl";
                  currentSystem = currentSystemLink;
                };
                snippetSwapsClosures = pkgs.writeShellScript "deploy-record-swapped" ''
                  set -euo pipefail
                  rm -f /run/devloop-ingest/mutant-line.jsonl
                  ${mutantLine} "$1"
                  line=$(cat /run/devloop-ingest/mutant-line.jsonl)
                  swapped=$(printf '%s\n' "$line" | ${pkgs.gnused}/bin/sed -E 's/"closure":"([^"]*)","previous_closure":"([^"]*)"/"closure":"\2","previous_closure":"\1"/')
                  if [ "$swapped" = "$line" ]; then
                    echo "snippetSwapsClosures: nothing swapped in $line" >&2
                    exit 1
                  fi
                  printf '%s\n' "$swapped" >> /var/log/deploy-record.jsonl
                '';
```

and in its attribute set, after `environment.systemPackages = [ pkgs.curl ];`, add:

```nix
                # Task 4's mutants rebuild these lists; they must equal the
                # configuration's when given the real values.
                assertions = [
                  {
                    assertion =
                      let
                        receivers = config.services.opentelemetry-collector.settings.receivers;
                      in
                      receivers."sqlquery/ci_attribute".queries == [
                        (queryElement "ci_attribute" devloop.queries.ci_attribute)
                      ]
                      && receivers."sqlquery/ci_build".queries == [ (queryElement "ci_build" devloop.queries.ci_build) ]
                      && receivers."journald/gitea-mq".operators == journaldOperators;
                    message = "devloop-ingest: queryElement or journaldOperators no longer rebuilds the collector's receiver lists, so a Task 4 mutant would change more than its clause";
                  }
                ];

                # The reconcile under test: devloop-collection's unit with
                # the container's credential and the scratch current-system
                # link; started by the case, never by its timer.
                systemd.services.devloop-reconcile.serviceConfig = {
                  LoadCredential = [ "regulator-password:${vars}/regulator-password" ];
                  ExecStart = lib.mkForce (
                    lib.getExe (
                      self.lib.devloopReconcile pkgs {
                        psql = lib.getExe' config.services.postgresql.package "psql";
                        journalctl = lib.getExe' config.systemd.package "journalctl";
                        hostName = config.networking.hostName;
                        currentSystem = currentSystemLink;
                      }
                    )
                  );
                };
                systemd.timers.devloop-reconcile.wantedBy = lib.mkForce [ ];

                environment.etc = {
                  "devloop-ingest/deploy-record".source = deployRecord;
                  "devloop-ingest/mutants/snippet-swaps-closures".source = snippetSwapsClosures;
                  # C1's table mutant: ci_attribute in append mode.
                  "devloop-ingest/mutants/append-mode-ci_attribute.sql".text =
                    replaceOnce "appendModeAttribute" "'append_mode' = 'false'" "'append_mode' = 'true'"
                      devloop.ddl.ci_attribute;
                  # C5's pipeline mutant: devloop_batch_event without flaky.
                  "devloop-ingest/mutants/pipeline-without-flaky.yaml".text =
                    replaceOnce "pipelineWithoutFlaky"
                      "        .flaky = if a.flaky == null || a.flaky == \"\" { null } else { to_bool!(a.flaky) }\n"
                      ""
                      devloop.pipelines.batch_event;
                };
```

The container already sets `environment.etc = { … };` (Task 3's `gitea-mq-lines.txt`, `gitea-mq-empty.txt`, `config.json` and the mutant files), so merge these four entries into that attrset instead of adding a second definition.

4. After the binding `documentedQueries = '' … '';`, add the binding `reconcile` below, and in the multi-line `cases = [ … ];` list add the line `reconcile` after `documentedQueries` (Task 5 appends `burnRule` after it).

````nix
            # Task 4 (tasks.md 4.6; design D11, D16): devloop-reconcile, as
            # its unit runs, passes on the unmutated collection after the
            # overlap re-reads, with an attribute restarted and with it
            # finished again after the window, and fails naming its clause
            # for each of D11's eight mutants. Every leg starts from the
            # day's journal emptied of earlier stub lines, the tables and
            # cursors reset, one deploy record and the stub's lines, so the
            # window holds only that leg's events.
            reconcile = ''
              import datetime
              import re
              import time

              print("=== case reconcile")
              CURRENT_SYSTEM = "${currentSystemLink}"
              DAY_CONF = "/run/systemd/system/devloop-reconcile.service.d/zz-day.conf"
              STUB_LINES = "/run/devloop-ingest/gitea-mq-lines"
              FIXTURE_LINES = "/etc/devloop-ingest/gitea-mq-lines.txt"
              EMPTY_LINES = "/etc/devloop-ingest/gitea-mq-empty.txt"
              REAL_RECORD = "/etc/devloop-ingest/deploy-record"
              SWAPPED_RECORD = "/etc/devloop-ingest/mutants/snippet-swaps-closures"
              BATCH = "msg=\"batch (formed|built|landed|bisecting|done)\""
              CLAUSES = [
                  "C1 attributes",
                  "C2 builds",
                  "C3 batch-lines",
                  "C4 batch-liveness",
                  "C5 batch-fields",
                  "C6 deploys",
                  "C7 current-system",
              ]
              TABLES = ["ci_attribute", "ci_build", "batch_event", "deploy_record"]
              VARS = config()["vars"]
              RESTARTED = "checks.x86_64-linux.reconcile-restarted"


              # C7's wait prints this on stderr before each 10 s retry; the
              # verdict lines are the seven clause lines alone.
              WAITING = "devloop-reconcile: C7 current-system: waiting for "
              VERDICT = re.compile(r"^devloop-reconcile: C[1-7] [a-z-]+: (ok$|FAIL )")
              WAITS = {"n": 0}


              def reconcile(day, during=None):
                  store.succeed(
                      "mkdir -p /run/systemd/system/devloop-reconcile.service.d",
                      f"printf '[Service]\\nEnvironment=DEVLOOP_RECONCILE_DAY=%s\\n' {day} > {DAY_CONF}",
                      "systemctl daemon-reload",
                  )
                  if during is None:
                      store.execute("systemctl start devloop-reconcile.service")
                  else:
                      store.succeed("systemctl start --no-block devloop-reconcile.service")
                      during()
                      store.wait_until_succeeds(
                          'test "$(systemctl show -P ActiveState devloop-reconcile.service)" != activating',
                          timeout=300,
                      )
                  invocation = store.succeed("systemctl show -P InvocationID devloop-reconcile.service").strip()
                  status = int(store.succeed("systemctl show -P ExecMainStatus devloop-reconcile.service").strip())
                  journal = f"journalctl --no-pager -o cat _SYSTEMD_INVOCATION_ID={invocation}"
                  if status in (0, 1):
                      store.wait_until_succeeds(f"{journal} | grep -q '^devloop-reconcile: C7 current-system: [oF]'", timeout=60)
                  output = store.succeed(journal).splitlines()
                  lines = [l for l in output if VERDICT.match(l)]
                  WAITS["n"] = sum(1 for l in output if l.startswith(WAITING))
                  print(f"reconcile {day}: exit {status}, {WAITS['n']} C7 waits")
                  for line in lines:
                      print(line)
                  return status, lines


              def passes(stage, status, lines):
                  assert status == 0, (stage, status, lines)
                  assert lines == [f"devloop-reconcile: {clause}: ok" for clause in CLAUSES], (stage, lines)
                  print(f"reconcile passes: {stage}")


              def rejected(name, expected, status, lines):
                  fails = sorted(l.split(": ")[1] for l in lines if ": FAIL " in l)
                  assert status == 1 and fails == sorted(expected), (name, expected, status, lines)
                  print(f"mutant {name} rejected: " + " | ".join(l for l in lines if ": FAIL " in l))


              def batch_lines(command):
                  return int(store.succeed(f"{command} | grep -cE '{BATCH}' || true").strip())


              def activate(record, closure):
                  # As activation does: the snippet, then the relink.
                  store.succeed(f"{record} {closure}", f"ln -sfn {closure} {CURRENT_SYSTEM}")


              def fresh_leg(silent=False):
                  store.succeed("systemctl stop gitea-mq.service")
                  # Earlier stub lines would otherwise stay in the day (C3, C4).
                  # The container cannot set the journal directory's setgid
                  # bit (systemd-tmpfiles' fchmod is refused at boot), so the
                  # file journald opens on rotation is root:root; chgrp gives
                  # it the group the collector and the reconcile read through,
                  # as tmpfiles' `z .../system.journal` line does at boot.
                  store.succeed(
                      "journalctl --rotate",
                      "sleep 2",
                      "journalctl --vacuum-time=1s",
                      "chgrp systemd-journal /var/log/journal/*/system.journal",
                  )
                  reset_devloop()
                  stub = EMPTY_LINES if silent else FIXTURE_LINES
                  store.succeed(
                      "mkdir -p /run/devloop-ingest",
                      f"ln -sfn {stub} {STUB_LINES}",
                      f"ln -sfn {X0} {CURRENT_SYSTEM}",
                  )


              def start_sources(record=REAL_RECORD, silent=False, mutant=None):
                  activate(record, X1)
                  store.succeed("systemctl restart gitea-mq.service")
                  want = 0 if silent else batch_lines(f"cat {FIXTURE_LINES}")
                  retry(
                      lambda _last: batch_lines("journalctl --no-pager -o cat -u gitea-mq.service") == want,
                      timeout=datetime.timedelta(minutes=1),
                  )
                  collector_restart(mutant)


              def settle(touched=()):
                  expected = {
                      "ci_attribute": int(psql("SELECT count(*) FROM build_attributes WHERE finished_at IS NOT NULL").strip()),
                      "ci_build": int(psql("SELECT count(*) FROM builds WHERE finished_at IS NOT NULL").strip()),
                      "batch_event": batch_lines(f"cat {FIXTURE_LINES}"),
                      "deploy_record": 1,
                  }
                  for table in TABLES:
                      if table not in touched:
                          wait_rows(table, expected[table])
                          assert send_failed(table) == 0, (table, send_failed(table))
                  if touched:
                      # Two further 60 s polls of the mutated receiver.
                      time.sleep(130)


              # The case runs about 45 minutes; it starts at least an hour
              # before 00:00 UTC so every leg's events fall in one UTC day.
              to_midnight = int(store.succeed("echo $(( 86400 - $(date -u +%s) % 86400 ))").strip())
              if to_midnight < 3600:
                  print(f"reconcile: {to_midnight} s before 00:00 UTC; waiting for the next day")
                  time.sleep(to_midnight + 60)
              DAY = utc_today()
              NEXT_DAY = (datetime.date.fromisoformat(DAY) + datetime.timedelta(days=1)).isoformat()
              X0 = store.succeed("readlink -f /run/current-system").strip()
              X1 = store.succeed("readlink -f /run/current-system/sw").strip()
              assert X0 != X1, (X0, X1)
              assert int(store.succeed(f"grep -cE 'msg=\"batch built\"' {FIXTURE_LINES}").strip()) > 0
              assert int(store.succeed(f"grep -cE 'msg=\"batch done\".* landed=.* ejected=.* builds=.* flaky=' {FIXTURE_LINES}").strip()) > 0

              with subtest("devloop-reconcile passes after the overlap re-reads and a restarted attribute"):
                  fresh_leg()
                  nixbot_rows(
                      "INSERT INTO builds (id, project_id, number, commit_sha, branch, pr_number, status, created_at, started_at, finished_at) "
                      "OVERRIDING SYSTEM VALUE VALUES "
                      "(9201, 1, 9201, 'c9201', 'pr-9201', 9201, 'succeeded', now() - interval '3 minutes', now() - interval '2 minutes', now()), "
                      "(9202, 1, 9202, 'c9202', 'gitea-mq/batch/9202', NULL, 'succeeded', now() - interval '3 minutes', now() - interval '2 minutes', now())"
                  )
                  nixbot_rows(
                      "INSERT INTO build_attributes (build_id, attr, system, status, cached, started_at, finished_at) VALUES "
                      "(9201, 'checks.x86_64-linux.reconcile-pass', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now()), "
                      "(9201, 'checks.x86_64-linux.reconcile-cached', 'x86_64-linux', 'skipped_local', true, NULL, now()), "
                      f"(9202, '{RESTARTED}', 'x86_64-linux', 'succeeded', false, now() - interval '1 minute', now())"
                  )
                  start_sources()
                  # A row younger than five minutes is re-read on every 60 s
                  # poll (design D6), so 190 s gives each new row three reads.
                  time.sleep(190)
                  settle()
                  for table in TABLES:
                      rows, keys = key_counts(table)
                      assert rows == keys, (table, rows, keys)
                  passes("after the overlap re-reads", *reconcile(DAY))
                  nixbot_rows(
                      "UPDATE build_attributes SET status = 'building', started_at = now(), finished_at = NULL "
                      f"WHERE build_id = 9202 AND attr = '{RESTARTED}'"
                  )
                  passes("an attribute restarted and not finished again", *reconcile(DAY))
                  nixbot_rows(
                      f"UPDATE build_attributes SET status = 'succeeded', finished_at = '{NEXT_DAY}T00:30:00Z' "
                      f"WHERE build_id = 9202 AND attr = '{RESTARTED}'"
                  )
                  retry(
                      lambda _last: gsql(f"SELECT count(*) FROM ci_attribute WHERE \"attr\" = '{RESTARTED}'")[0][0] == 2,
                      timeout=datetime.timedelta(minutes=3),
                  )
                  passes("the attribute finished again after the window", *reconcile(DAY))
                  assert WAITS["n"] == 0, WAITS

                  # C7's wait: a deploy whose record is not yet shipped when
                  # the run starts is shipped during the wait, and the run passes.
                  store.succeed("systemctl stop opentelemetry-collector.service")
                  activate(REAL_RECORD, X0)
                  since = store.succeed("date +%s").strip()

                  def ship_during_wait():
                      store.wait_until_succeeds(
                          f"journalctl --no-pager -o cat -u devloop-reconcile.service --since=@{since} | grep -qF '{WAITING}'",
                          timeout=120,
                      )
                      store.succeed("systemctl start opentelemetry-collector.service")

                  passes("a deploy record shipped during C7's wait", *reconcile(DAY, during=ship_during_wait))
                  assert WAITS["n"] >= 1, WAITS

              with subtest("each of D11's mutants fails devloop-reconcile naming its clause"):
                  # C1: an attribute query that omits cached = true rows.
                  fresh_leg()
                  start_sources(mutant="omitCached")
                  settle(touched=["ci_attribute"])
                  rejected("omitCached", ["C1 attributes"], *reconcile(DAY))

                  # C1: ci_attribute in append mode keeps the overlap's re-reads.
                  fresh_leg()
                  admin_sql('DROP TABLE "ci_attribute"')
                  admin_sql(store.succeed("cat /etc/devloop-ingest/mutants/append-mode-ci_attribute.sql"))
                  start_sources()
                  nixbot_rows(
                      "INSERT INTO build_attributes (build_id, attr, system, status, cached, finished_at) VALUES "
                      "(9201, 'checks.x86_64-linux.reconcile-append-1', 'x86_64-linux', 'succeeded', false, now()), "
                      "(9201, 'checks.x86_64-linux.reconcile-append-2', 'x86_64-linux', 'succeeded', false, now())"
                  )
                  retry(
                      lambda _last: key_counts("ci_attribute")[0] > key_counts("ci_attribute")[1],
                      timeout=datetime.timedelta(minutes=4),
                  )
                  settle(touched=["ci_attribute"])
                  rejected("appendModeAttribute", ["C1 attributes"], *reconcile(DAY))

                  # C2: a build query that omits rows with a null pr_number.
                  fresh_leg()
                  start_sources(mutant="omitNullPr")
                  settle(touched=["ci_build"])
                  rejected("omitNullPr", ["C2 builds"], *reconcile(DAY))

                  # C3: no key_value_parser, so no row carries msg, and none is batch built.
                  fresh_leg()
                  start_sources(mutant="noKeyValueParser")
                  settle(touched=["batch_event"])
                  rejected("noKeyValueParser", ["C3 batch-lines", "C4 batch-liveness"], *reconcile(DAY))

                  # C4: a stub gitea-mq printing nothing while batch builds exist.
                  batch_builds = int(psql(
                      "SELECT count(*) FROM builds WHERE starts_with(branch, 'gitea-mq/batch/') "
                      f"AND finished_at >= '{DAY}T00:00:00Z' AND finished_at < '{NEXT_DAY}T00:00:00Z'"
                  ).strip())
                  assert batch_builds > 0, batch_builds
                  fresh_leg(silent=True)
                  start_sources(silent=True)
                  settle(touched=["batch_event"])
                  rejected("silentStub", ["C4 batch-liveness"], *reconcile(DAY))

                  # C5: a devloop_batch_event pipeline that drops flaky.
                  fresh_leg()
                  store.succeed(
                      f"curl -sSf --netrc-file {VARS}/admin.netrc -X POST "
                      "'http://127.0.0.1:4000/v1/pipelines/devloop_batch_event?db=devloop' "
                      "-F file=@/etc/devloop-ingest/mutants/pipeline-without-flaky.yaml"
                  )
                  start_sources()
                  settle()
                  rejected("pipelineWithoutFlaky", ["C5 batch-fields"], *reconcile(DAY))

                  # C6: file_log/deploy-record reading another path; C7 then has
                  # no row, waits the full 120 s because the file's last line
                  # names the current system, and fails.
                  fresh_leg()
                  start_sources(mutant="deployRecordOtherPath")
                  settle(touched=["deploy_record"])
                  rejected("deployRecordOtherPath", ["C6 deploys", "C7 current-system"], *reconcile(DAY))
                  assert WAITS["n"] == 12, WAITS

                  # C7: a snippet writing the previous closure as closure; the
                  # file's last line then names another system, so no wait.
                  fresh_leg()
                  start_sources(record=SWAPPED_RECORD)
                  settle()
                  rejected("snippetSwapsClosures", ["C7 current-system"], *reconcile(DAY))
                  assert WAITS["n"] == 0, WAITS

              store.succeed(
                  f"rm -f {DAY_CONF}",
                  "systemctl daemon-reload",
                  f"ln -sfn {FIXTURE_LINES} {STUB_LINES}",
                  "systemctl restart gitea-mq.service",
              )
              reset_devloop()
              collector_restart()
              assert utc_today() == DAY, (DAY, utc_today())
              print("ok: reconcile")
            '';
````

Grounding for the case: a newly posted pipeline replaces the cached `latest` version at once (`GreptimeTeam/greptimedb@v1.2.1:src/pipeline/src/manager/pipeline_cache.rs:156-161`), so the C5 leg's upload takes effect before the collector restarts, and the next leg's `reset_devloop()` restarts `greptimedb-schema`, which posts the real pipeline again (Task 2).
A table recreated by `reset_devloop()` and then dropped and recreated in append mode keeps every re-read row, as the spike's append control kept all 9 of 3 distinct rows (`logs/s2/spike-dedup.md:90-95`).
`journalctl --rotate` archives the active files and `--vacuum-time=1s` removes archived files whose entries are older than a second, so the wait in `start_sources` for exactly the fixture's count of matching lines confirms that no earlier leg's line survived `[INFERENCE]`, which Step 23's log confirms.
In the nspawn container the new `system.journal` is `root:root`, because the boot's `systemd-tmpfiles` cannot set the journal directory's setgid bit (`fchmod() of /var/log/journal/<machine-id> failed: Operation not permitted`), so without the `chgrp` the collector's journalctl and the reconcile, both reading through `systemd-journal`, open no journal file (`logs/s2-evidence/4.6-devloop-ingest-diag-*.log`); magnetite's journal directories carry the setgid bit (`drwxr-sr-x root:systemd-journal`, and `system.journal` is `root:systemd-journal`, read 2026-10-22), so this is the container's alone.
Each leg's `reset_devloop()` drops the collector's cursors, so every receiver reads nixbot, the journal and the deploy record from the beginning, and every leg compares the same nixbot rows of the day.
The container's new assertion is enforced when the container's own system builds, not in the `extendModules` evaluations from which Task 3 reads only a mutant's `ExecStart`, so the mutants do not trip it.
The case's Python contains no `''` and no `${` other than `${currentSystemLink}`, so the Nix indented string carries it unchanged.

- [ ] **Step 10: Evaluate `devloop-ingest` before `devloopReconcile` exists (RED, evaluation)**

Run:

```bash
jj st --no-pager >/dev/null
nix eval --raw .#vmTests.x86_64-linux.devloop-ingest.drvPath 2>&1 | tee logs/s2-evidence/4.6-devloop-ingest-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o "attribute 'devloopReconcile' missing"
```

Expected: `attribute 'devloopReconcile' missing`.

- [ ] **Step 11: Place `devloop-reconcile` in magnetite's kill order (RED, evaluation)**

In `modules/machines/nixos/magnetite/default.nix`, replace (today's `:734-747`)

```nix
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
```

with

```nix
            # R7.1 (A7:100,127), S3 design D12 and S2 design D11: under host
            # OOM the kernel kills the evaluator, then the dev-loop reconcile
            # (which fails visibly and runs again the next day), then the
            # store, then the collector, so the collector outlives the store
            # and queues; the alert evaluator, which reports OOM kills, is
            # taken after all four.
            {
              assertion =
                config.services.nixEvalLock.enable
                && evaluatorAdj != null
                && evaluatorAdj > order.devloop-reconcile
                && order.devloop-reconcile > order.greptimedb
                && order.greptimedb > order.opentelemetry-collector
                && order.opentelemetry-collector > order.fleet-alert;
              message = "magnetite: R7.1, S3 design D12 and S2 design D11 require the evaluation lock and oom_score_adj nix-eval-jobs > devloop-reconcile > greptimedb > opentelemetry-collector > fleet-alert; the lock is ${
```

and in `order` (today's `:716-721`) insert after `nix-eval-jobs = evaluatorAdj;`:

```nix
              devloop-reconcile = unitAdj "devloop-reconcile";
```

Run the harness of S3 plan Task 4 Step 23 with the control only:

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  host = flake.nixosConfigurations.magnetite;
  failing = m: map (a: a.message) (lib.filter (a: !a.assertion) (host.extendModules { modules = [ m ]; }).config.assertions);
in lib.mapAttrs (_: failing) { control = { }; }' 2>&1 | tee logs/s2-evidence/4.4-kill-order-red-$(date -u +%Y%m%dT%H%M%SZ).log | jq -r 'to_entries[] | "=== \(.key)", .value[]'
```

Expected: `=== control`, then exactly one message, `magnetite: R7.1, S3 design D12 and S2 design D11 require the evaluation lock and oom_score_adj nix-eval-jobs > devloop-reconcile > greptimedb > opentelemetry-collector > fleet-alert; the lock is enabled and the values are {"devloop-reconcile":1000,"fleet-alert":0,"greptimedb":500,"nix-eval-jobs":900,"opentelemetry-collector":300}.`, because an absent unit reads as 1000 (`:711-715`).
The two values the assertion relates are each unit's `OOMScoreAdjust` as its module sets it (`greptimedb.nix`, `fleet-alert.nix`, the collector's role, `devloop-collection.nix`) and the evaluator's value read from `modules/lib/nix-eval-lock.sh:99` (`echo 900`); magnetite's assertion orders them.

- [ ] **Step 12: Add `devloopReconcile`, its unit and its timer**

In `modules/nixos/devloop-collection.nix`'s top-level `let`, directly after Step 6's `reconcileQueries` binding, add the binding below; `config` there is the flake-parts configuration, so `config.flake.lib.greptimedbSql` is S1's helper.
Then, directly after the closing `};` of `flake.lib.devloopCollection = { … };`, add the attribute `flake.lib.devloopReconcile = devloopReconcile;`.

````nix
  # flake.lib.devloopReconcile (design D11): devloop-reconcile.service's
  # ExecStart. Over one UTC day, [DEVLOOP_RECONCILE_DAY 00:00, +1 day)
  # (default yesterday), it compares each table of DEVLOOP_RECONCILE_DATABASE
  # (default devloop) with its source and prints one line per clause,
  # `devloop-reconcile: C<n> <name>: ok` or `... FAIL <detail>`:
  #   C1 attributes, C2 builds: nixbot's keys in the window against the
  #     table's, compared as multisets, so a duplicated row is an extra key;
  #     an extra key is explained only when nixbot's current finished_at for
  #     it is null or later (a restart), and any other fails, as does a
  #     missing key;
  #   C3 batch-lines: per-msg counts of the gitea-mq.service journal lines
  #     matching design D7's pattern, by __REALTIME_TIMESTAMP, against
  #     batch_event's rows;
  #   C4 batch-liveness: a gitea-mq/batch/ build finished in the window and
  #     no batch built row;
  #   C5 batch-fields: a batch done row with a null landed, ejected, builds
  #     or flaky;
  #   C6 deploys: the deploy record's lines with ts in the window against
  #     the host's deploy_record rows;
  #   C7 current-system: the current system against the host's latest
  #     stored closure; when the deploy record's last line names the
  #     current system and the store's latest row does not, the store is
  #     read again every 10 s for up to 120 s first, because that line may
  #     not be shipped yet (a deploy just before the run, or the timer's
  #     Persistent catch-up at boot).
  # nixbot is read by peer as devloop-reconcile through
  # devloopCollection.reconcileQueries; the store as `regulator` through
  # greptimedbSql (modules/lib/greptimedb-envelope.nix), which reads
  # $CREDENTIALS_DIRECTORY/regulator-password into `curl --config -` and
  # fails on an empty answer, so every store query here counts first and
  # reads keys only after a non-zero count (S1 review F3). Exit 1 when a
  # clause fails; exit 2, naming the source on stderr, when nixbot, the
  # journal, the deploy record, the current system or the store cannot be
  # read, or an environment value is malformed.
  devloopReconcile =
    pkgs:
    {
      psql,
      journalctl ? "journalctl",
      storeUrl ? "http://127.0.0.1:4000",
      hostName,
      deployRecord ? "/var/log/deploy-record.jsonl",
      currentSystem ? "/run/current-system",
    }:
    let
      queries = reconcileQueries;
      sqlFile = name: pkgs.writeText "devloop-reconcile-${name}.sql" queries.${name};
      attributesSql = sqlFile "attributes";
      buildsSql = sqlFile "builds";
      batchBuildsSql = sqlFile "batchBuilds";
      currentFinishSql = sqlFile "currentFinish";
      storeSql = config.flake.lib.greptimedbSql pkgs {
        url = storeUrl;
        user = "regulator";
      };
      # The extra stored keys, one `build_id<TAB>attr<TAB>finished_at` (C1)
      # or `build_id<TAB>finished_at` (C2) line each, as currentFinish's $3;
      # a NULL or non-numeric field reads as null, which nixbot never has.
      extraKeysJq = pkgs.writeText "devloop-reconcile-extra-keys.jq" ''
        split("\n")
        | map(select(length > 0) | split("\t"))
        | map(
            if length == 3 then
              { build_id: (.[0] | tonumber? // null), attr: .[1], finished_at_us: (.[2] | tonumber? // null) }
            else
              { build_id: (.[0] | tonumber? // null), attr: null, finished_at_us: (.[1] | tonumber? // null) }
            end
          )
      '';
      # The slurped journal entries in [$from, $to) microseconds of
      # __REALTIME_TIMESTAMP whose MESSAGE carries one of design D7's five
      # messages, the closing quote making each match exact, counted per
      # message as `<msg><TAB><count>` lines.
      batchLinesJq = pkgs.writeText "devloop-reconcile-batch-lines.jq" ''
        [ .[]
          | select(.MESSAGE | type == "string")
          | select((.__REALTIME_TIMESTAMP | tonumber) as $t | $t >= $from and $t < $to)
          | .MESSAGE
          | capture("msg=\"(?<msg>batch (?:formed|built|landed|bisecting|done))\"")
          | .msg ]
        | group_by(.)
        | .[]
        | "\(.[0])\t\(length)"
      '';
      # The deploy record's lines whose ts lies in [$from, $to).
      deployLinesJq = pkgs.writeText "devloop-reconcile-deploy-lines.jq" ''
        select(.ts >= $from and .ts < $to) | .ts
      '';
    in
    pkgs.writeShellApplication {
      name = "devloop-reconcile";
      # diffutils for C3's cmp: a unit's PATH has no cmp.
      runtimeInputs = [
        pkgs.coreutils
        pkgs.diffutils
        pkgs.jq
      ];
      text = ''
        tab=$'\t'
        failed=0
        host=${lib.escapeShellArg hostName}
        unreadable() {
          printf 'devloop-reconcile: cannot read %s\n' "$1" >&2
          exit 2
        }
        ok() {
          printf 'devloop-reconcile: %s: ok\n' "$1"
        }
        fail() {
          printf 'devloop-reconcile: %s: FAIL %s\n' "$1" "$2"
          failed=1
        }
        # sample FILE: FILE's line count and its first three lines, tabs as "/".
        sample() {
          printf '%s (first: %s)' "$(wc -l < "$1")" "$(head -n 3 "$1" | tr '\t' '/' | paste -s -d ',' -)"
        }

        day=''${DEVLOOP_RECONCILE_DAY:-$(date -u -d yesterday +%F)}
        db=''${DEVLOOP_RECONCILE_DATABASE:-devloop}
        [[ $day =~ ^[0-9]{4}-[0-9]{2}-[0-9]{2}$ ]] || unreadable "DEVLOOP_RECONCILE_DAY=$day: not YYYY-MM-DD"
        [[ $db =~ ^[a-z_][a-z0-9_]*$ ]] || unreadable "DEVLOOP_RECONCILE_DATABASE=$db: not a database name"
        from_s=$(date -u -d "$day" +%s 2>/dev/null) || unreadable "DEVLOOP_RECONCILE_DAY=$day: not a date"
        to_s=$((from_s + 86400))
        from_iso=$(date -u -d "@$from_s" +%Y-%m-%dT%H:%M:%SZ)
        to_iso=$(date -u -d "@$to_s" +%Y-%m-%dT%H:%M:%SZ)
        [ "$from_iso" = "''${day}T00:00:00Z" ] || unreadable "DEVLOOP_RECONCILE_DAY=$day: not a calendar day"
        work=$(mktemp -d)
        trap 'rm -rf "$work"' EXIT

        # pg QUERY [KEYS_FILE]: one reconcileQueries text as devloop-reconcile,
        # prepared over the window as $1 and $2 and, with KEYS_FILE, its JSON as
        # $3; psql reads that file itself (\set with a backquoted cat), so no key
        # list is on an argument list. Prints the rows, tab-separated, no header.
        pg() {
          local keys="" types="timestamptz, timestamptz" args=":'from', :'to'"
          if [ "$#" -eq 2 ]; then
            keys="\\set keys \`cat $2\`"
            types="$types, jsonb"
            args="$args, :'keys'"
          fi
          printf '%s\nPREPARE q(%s) AS %s;\nEXECUTE q(%s);\n' "$keys" "$types" "$1" "$args" |
            ${psql} -X -q -A -t -v ON_ERROR_STOP=1 -F "$tab" -v from="$from_iso" -v to="$to_iso" \
              "host=/run/postgresql dbname=nixbot user=devloop-reconcile"
        }
        # storeq SQL: one statement as `regulator`; greptimedbSql fails on an
        # empty answer, so callers count first and read keys only after a
        # non-zero count.
        storeq() {
          ${lib.getExe storeSql} "$1"
        }
        # win COLUMN: the window predicate over a store column.
        win() {
          printf '%s' "\"$1\" >= '$from_iso' AND \"$1\" < '$to_iso'"
        }
        # tbl TABLE: the table in the reconciled database.
        tbl() {
          printf '%s' "\"$db\".\"$1\""
        }

        # keyed CLAUSE TABLE COLUMNS QUERY: C1 and C2. Keys are compared as
        # multisets (sorted, not made unique), so a duplicated stored row is an
        # extra key; an extra key is explained only when nixbot's current
        # finished_at for it is null or later than the stored one (a restart).
        keyed() {
          local clause=$1 table=$2 columns=$3 query=$4 n detail=""
          pg "$(< "$query")" > "$work/source.raw" || unreadable "nixbot's $table keys as devloop-reconcile"
          n=$(storeq "SELECT count(*) FROM $(tbl "$table") WHERE $(win finished_at)") || unreadable "$db.$table in the store"
          if [ "$n" -gt 0 ]; then
            storeq "SELECT $columns FROM $(tbl "$table") WHERE $(win finished_at)" > "$work/store.raw" ||
              unreadable "$db.$table keys in the store"
          else
            : > "$work/store.raw"
          fi
          LC_ALL=C sort "$work/source.raw" > "$work/source"
          LC_ALL=C sort "$work/store.raw" > "$work/store"
          LC_ALL=C comm -23 "$work/source" "$work/store" > "$work/missing"
          LC_ALL=C comm -13 "$work/source" "$work/store" > "$work/extra"
          : > "$work/unexplained"
          if [ -s "$work/extra" ]; then
            jq -R -s -f ${extraKeysJq} "$work/extra" > "$work/extra.json" || unreadable "the stored $table keys"
            pg "$(< ${currentFinishSql})" "$work/extra.json" > "$work/unexplained" ||
              unreadable "nixbot's current finished_at as devloop-reconcile"
          fi
          if [ -s "$work/missing" ]; then
            detail="missing from $db.$table: $(sample "$work/missing")"
          fi
          if [ -s "$work/unexplained" ]; then
            detail="''${detail:+$detail; }unexplained in $db.$table: $(sample "$work/unexplained")"
          fi
          if [ -n "$detail" ]; then
            fail "$clause" "$detail"
          else
            ok "$clause"
          fi
        }

        keyed "C1 attributes" ci_attribute '"build_id", "attr", "finished_at"' ${attributesSql}
        keyed "C2 builds" ci_build '"build_id", "finished_at"' ${buildsSql}

        # C3: the journal is readable only if PID 1's entries are visible, so an
        # empty gitea-mq answer below means a quiet day, not a missing group.
        seen=$(${journalctl} --quiet --no-pager --lines=1 --output=cat _PID=1) || unreadable "the journal"
        [ -n "$seen" ] || unreadable "the journal: no entry of PID 1 is visible to this user"
        ${journalctl} --quiet --no-pager --output=json --unit=gitea-mq.service --since="@$from_s" --until="@$to_s" \
          > "$work/journal.json" || unreadable "the gitea-mq.service journal"
        jq -r -s --argjson from "$((from_s * 1000000))" --argjson to "$((to_s * 1000000))" -f ${batchLinesJq} \
          "$work/journal.json" > "$work/journal.raw" || unreadable "the gitea-mq.service journal entries"
        n=$(storeq "SELECT count(*) FROM $(tbl batch_event) WHERE $(win ts)") || unreadable "$db.batch_event in the store"
        if [ "$n" -gt 0 ]; then
          storeq "SELECT \"msg\", count(*) FROM $(tbl batch_event) WHERE $(win ts) GROUP BY \"msg\"" > "$work/batch.raw" ||
            unreadable "$db.batch_event counts in the store"
        else
          : > "$work/batch.raw"
        fi
        LC_ALL=C sort "$work/journal.raw" > "$work/journal.counts"
        LC_ALL=C sort "$work/batch.raw" > "$work/batch.counts"
        if cmp -s "$work/journal.counts" "$work/batch.counts"; then
          ok "C3 batch-lines"
        else
          fail "C3 batch-lines" "journal {$(tr '\t' '=' < "$work/journal.counts" | paste -s -d ',' -)} store {$(tr '\t' '=' < "$work/batch.counts" | paste -s -d ',' -)}"
        fi

        batch_builds=$(pg "$(< ${batchBuildsSql})") || unreadable "nixbot's gitea-mq/batch/ builds as devloop-reconcile"
        built=$(storeq "SELECT count(*) FROM $(tbl batch_event) WHERE \"msg\" = 'batch built' AND $(win ts)") ||
          unreadable "$db.batch_event in the store"
        if [ "$batch_builds" -gt 0 ] && [ "$built" -eq 0 ]; then
          fail "C4 batch-liveness" "nixbot finished $batch_builds gitea-mq/batch/ builds and $db.batch_event has no batch built row"
        else
          ok "C4 batch-liveness"
        fi

        nulls=$(storeq "SELECT count(*) FROM $(tbl batch_event) WHERE \"msg\" = 'batch done' AND $(win ts) AND (\"landed\" IS NULL OR \"ejected\" IS NULL OR \"builds\" IS NULL OR \"flaky\" IS NULL)") ||
          unreadable "$db.batch_event in the store"
        if [ "$nulls" -eq 0 ]; then
          ok "C5 batch-fields"
        else
          fail "C5 batch-fields" "$nulls batch done rows have a null landed, ejected, builds or flaky"
        fi

        # C7 reads the store first, because its wait also lets C6 count the rows
        # the collector ships meanwhile. When the deploy record's last line names
        # the current system and the store's latest row does not, that line may
        # not be shipped yet (a deploy just before the run, or the timer's
        # Persistent catch-up at boot), so the store is read again every 10 s for
        # up to 120 s before C7 judges.
        current=$(readlink -f ${lib.escapeShellArg currentSystem}) || unreadable ${lib.escapeShellArg currentSystem}
        last=$(tail -n 1 ${lib.escapeShellArg deployRecord} | jq -r '.closure // ""') || unreadable ${lib.escapeShellArg deployRecord}
        # latest_closure: the host's latest stored closure, or nothing without a row.
        latest_closure() {
          local stored
          stored=$(storeq "SELECT count(*) FROM $(tbl deploy_record) WHERE \"host\" = '$host'") ||
            unreadable "$db.deploy_record in the store"
          if [ "$stored" -gt 0 ]; then
            storeq "SELECT \"closure\" FROM $(tbl deploy_record) WHERE \"host\" = '$host' ORDER BY \"ts\" DESC LIMIT 1" ||
              unreadable "$db.deploy_record in the store"
          fi
        }
        latest=$(latest_closure) || exit 2
        waited=0
        if [ "$last" = "$current" ]; then
          while [ "$latest" != "$current" ] && [ "$waited" -lt 120 ]; do
            printf 'devloop-reconcile: C7 current-system: waiting for %s in the store (%s s)\n' "$current" "$waited" >&2
            sleep 10
            waited=$((waited + 10))
            latest=$(latest_closure) || exit 2
          done
        fi

        lines=$(jq -r --arg from "$from_iso" --arg to "$to_iso" -f ${deployLinesJq} ${lib.escapeShellArg deployRecord} | wc -l) ||
          unreadable ${lib.escapeShellArg deployRecord}
        rows=$(storeq "SELECT count(*) FROM $(tbl deploy_record) WHERE \"host\" = '$host' AND $(win ts)") ||
          unreadable "$db.deploy_record in the store"
        if [ "$lines" -eq "$rows" ]; then
          ok "C6 deploys"
        else
          fail "C6 deploys" "${deployRecord} has $lines lines in the window and $db.deploy_record $rows rows for $host"
        fi

        after=""
        if [ "$waited" -gt 0 ]; then
          after=" after waiting $waited s"
        fi
        if [ -z "$latest" ]; then
          fail "C7 current-system" "$db.deploy_record has no row for $host$after; the current system is $current"
        elif [ "$latest" = "$current" ]; then
          ok "C7 current-system"
        else
          fail "C7 current-system" "the latest stored closure is $latest$after and the current system is $current"
        fi

        exit "$failed"
      '';
    };
````

Then, in `flake.modules.nixos.devloop-collection`, directly after the closing `};` of `systemd.services.devloop-pg-grants = { … };`, insert:

```nix

      # devloop-reconcile (design D11): once a day, 2 h 15 min after the
      # previous UTC day closed, every devloop table is compared with its
      # source over that day. The host sets LoadCredential=regulator-password,
      # so this module stays free of clan vars, as greptimedb.nix's
      # greptimedb-envelope does, and lists the unit in
      # services.observability-notify.units for OnFailure. No `wants`: a run
      # whose sources are down exits 2 and is notified instead of starting
      # them. OOMScoreAdjust 600 puts it after nixbot's evaluator (900) and
      # before the store (500); magnetite asserts the order. Persistent=true
      # catches up one missed run at boot, which reconciles only the previous
      # day; days missed while magnetite was down are rerun by hand with
      # DEVLOOP_RECONCILE_DAY (design D11; plan review F13).
      systemd.services.devloop-reconcile = {
        description = "Daily reconcile of the devloop tables with nixbot, the journal and the deploy record";
        after = [
          "postgresql.service"
          "greptimedb.service"
          "greptimedb-schema.service"
          "devloop-pg-grants.service"
        ];
        serviceConfig = {
          Type = "oneshot";
          ExecStart = lib.getExe (
            devloopReconcile pkgs {
              psql = lib.getExe' config.services.postgresql.package "psql";
              journalctl = lib.getExe' config.systemd.package "journalctl";
              hostName = config.networking.hostName;
            }
          );
          DynamicUser = true;
          SupplementaryGroups = [ "systemd-journal" ];
          MemoryMax = "128M";
          TimeoutStartSec = "10min";
          OOMScoreAdjust = 600;
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
      };

      systemd.timers.devloop-reconcile = {
        description = "Daily devloop reconcile";
        wantedBy = [ "timers.target" ];
        timerConfig = {
          OnCalendar = "*-*-* 02:15:00 UTC";
          Persistent = true;
        };
      };
```

The unit's user is the dynamic user `devloop-reconcile`, the name of Task 3's PostgreSQL role, so the default `local all all peer` rule admits it (`logs/s2/grounding.md:20-31`); `RestrictAddressFamilies` keeps `AF_UNIX` for PostgreSQL's socket and `AF_INET` for the store.
`curl` reaches the script through `greptimedbSql`'s own `runtimeInputs` (`modules/lib/greptimedb-envelope.nix:53-57`), so the reconcile's `runtimeInputs` are `coreutils`, `diffutils` (C3's `cmp`, absent from a NixOS unit's `PATH`; without it every C3 run failed with equal counts, `logs/s2-evidence/4.6-devloop-ingest-20261022T014655Z.log`) and `jq`, and `psql` and `journalctl` are absolute paths.
Window strings are compared by GreptimeDB as timestamps (`"finished_at" >= '2026-10-20T00:00:00Z'`) and the database-qualified name `"devloop"."ci_attribute"` resolves without `?db=` `[INFERENCE]`; Step 23's passing legs confirm both, because a predicate that matched no row would fail C1 against nixbot's rows.
A column grant lost to a later nixbot migration is not repaired, because `devloop-pg-grants` applies the grants once per boot or activation (design D10 as amended by plan review F6); the reconcile is its detector, because its nixbot read then fails and the run exits 2 naming nixbot's keys, and a lost collector grant leaves keys missing, which C1 or C2 reports.
C7's wait, the 120 s retry, was rehearsed during planning with a stub `sleep`: with the last line naming the current system and the store's latest row older, the run printed 12 `waiting` lines and then `FAIL the latest stored closure is … after waiting 120 s …`; with the row appearing after the first wait it printed one `waiting` line and passed; with the last line naming another closure it failed at once with no wait.

- [ ] **Step 13: Evaluate the unit and the kill order (evaluation)**

Run:

```bash
jj st --no-pager >/dev/null
{
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.services.devloop-reconcile --apply 's: { inherit (s) after wants; serviceConfig = { inherit (s.serviceConfig) Type ExecStart DynamicUser SupplementaryGroups MemoryMax TimeoutStartSec OOMScoreAdjust; }; }'
  nix eval --json .#nixosConfigurations.magnetite.config.systemd.timers.devloop-reconcile.timerConfig
  nix eval --impure --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
    lib = flake.inputs.nixpkgs.lib;
    host = flake.nixosConfigurations.magnetite;
    failing = m: map (a: a.message) (lib.filter (a: !a.assertion) (host.extendModules { modules = [ m ]; }).config.assertions);
  in lib.mapAttrs (_: failing) { control = { }; }'
} 2>&1 | tee logs/s2-evidence/4.3-unit-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `after` is `["postgresql.service","greptimedb.service","greptimedb-schema.service","devloop-pg-grants.service"]`, `wants` `[]`, and `serviceConfig` `{"DynamicUser":true,"ExecStart":"/nix/store/…-devloop-reconcile/bin/devloop-reconcile","MemoryMax":"128M","OOMScoreAdjust":600,"SupplementaryGroups":["systemd-journal"],"TimeoutStartSec":"10min","Type":"oneshot"}`; the timer `{"OnCalendar":"*-*-* 02:15:00 UTC","Persistent":true}`; the control `{"control":[]}`: the kill order now holds, and R8.2 holds because no unit has loaded the credential yet.

- [ ] **Step 14: Load the credential on magnetite (RED for R8.2, evaluation)**

In `modules/machines/nixos/magnetite/default.nix`, after the closing `};` of `systemd.services.greptimedb-envelope = { … };` (today's `:779`), insert:

```nix

      # devloop-reconcile's store credential, the third regulator-password
      # holder (S2 design D11); devloop-collection.nix stays free of clan vars.
      systemd.services.devloop-reconcile.serviceConfig.LoadCredential = [
        "regulator-password:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}"
      ];
```

Run Step 13's control expression alone, logging to `logs/s2-evidence/4.4-r82-red-$(date -u +%Y%m%dT%H%M%SZ).log`.
Expected: one message starting `magnetite: greptimedb-users credentials are loaded by` whose `regulator-password` list is `["devloop-reconcile","fleet-alert","greptimedb-envelope"]`, followed by `R8.2 allows only` with `["fleet-alert","greptimedb-envelope"]`.
The two values the assertion relates are the units whose evaluated `LoadCredential` names the generator's file (every module that loads it) and the holder list magnetite declares.

- [ ] **Step 15: Admit `devloop-reconcile` as a holder (GREEN, evaluation)**

Replace (today's `:650-654`)

```nix
            # Sorted, because `actual` is naturalSorted.
            regulator-password = [
              "fleet-alert"
              "greptimedb-envelope"
            ];
```

with

```nix
            # Sorted, because `actual` is naturalSorted.
            regulator-password = [
              "devloop-reconcile"
              "fleet-alert"
              "greptimedb-envelope"
            ];
```

Run Step 13's control expression alone, logging to `logs/s2-evidence/4.4-r82-$(date -u +%Y%m%dT%H%M%SZ).log`.
Expected: `{"control":[]}`.

- [ ] **Step 16: Show both assertions able to fail with `extendModules` overrides (tasks.md 4.4)**

Run the harness of S3 plan Task 4 Step 23 with this task's two overrides:

```bash
nix eval --impure --json --expr '
let
  flake = builtins.getFlake (toString ./.);
  lib = flake.inputs.nixpkgs.lib;
  host = flake.nixosConfigurations.magnetite;
  failing = m: map (a: a.message) (lib.filter (a: !a.assertion) (host.extendModules { modules = [ m ]; }).config.assertions);
in lib.mapAttrs (_: failing) {
  control = { };
  fourthRegulatorHolder = { config, ... }: { systemd.services.nginx.serviceConfig.LoadCredential = [ "stolen:${config.clan.core.vars.generators.greptimedb-users.files.regulator-password.path}" ]; };
  reconcileOomZero = { systemd.services.devloop-reconcile.serviceConfig.OOMScoreAdjust = lib.mkForce 0; };
}' 2>&1 | tee logs/s2-evidence/4.4-assertion-mutants-$(date -u +%Y%m%dT%H%M%SZ).log | jq -r 'to_entries[] | "=== \(.key)", .value[]'
```

Expected:
- `=== control` with no message;
- `=== fourthRegulatorHolder` with one message starting `magnetite: greptimedb-users credentials are loaded by` whose `regulator-password` list is `["devloop-reconcile","fleet-alert","greptimedb-envelope","nginx"]`;
- `=== reconcileOomZero` with one message, `magnetite: R7.1, S3 design D12 and S2 design D11 require the evaluation lock and oom_score_adj nix-eval-jobs > devloop-reconcile > greptimedb > opentelemetry-collector > fleet-alert; the lock is enabled and the values are {"devloop-reconcile":0,"fleet-alert":0,"greptimedb":500,"nix-eval-jobs":900,"opentelemetry-collector":300}.`

If `extendModules` is missing on the clan-built configuration, stop and report, as S3 plan Task 4 Step 21 directs.

- [ ] **Step 17: Notify `devloop-reconcile` on failure**

Replace (today's `:329-330`, after Task 3's edit)

```nix
      services.observability-notify.units = [
        "devloop-pg-grants"
```

with

```nix
      services.observability-notify.units = [
        "devloop-pg-grants"
        "devloop-reconcile"
```

Run:

```bash
nix eval --json .#nixosConfigurations.magnetite.config.systemd.services --apply 's: { units = map (n: { inherit n; onFailure = s.${n}.unitConfig.OnFailure or null; }) [ "devloop-pg-grants" "devloop-reconcile" ]; }' 2>&1 | tee logs/s2-evidence/4.4-notified-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: both units with `"onFailure":["observability-notify@%n.service"]`, `devloop-pg-grants` from Task 3's listing and `devloop-reconcile` from this edit, the wiring the collector's agent role applies to every listed unit.

- [ ] **Step 18: Add R3.1's mutant before its policy names `devloop-*` (RED, evaluation)**

The two values the extended clause relates: the evaluated service names of magnetite (`devloop-pg-grants` from Task 3's module and `devloop-reconcile` from this task's) and the evaluated `services.observability-notify.units` magnetite declares.
In `modules/checks/otel-collector-config.nix`'s `mutants`, after the `listedWithoutService` entry and before `schemaOrderDropped =`, insert:

```nix
        # S2 design D11: the dev-loop reconcile drops out of the notified units.
        reconcileNotNotified = i: i // { notifyUnits = lib.remove "devloop-reconcile" i.notifyUnits; };
```

Run:

```bash
nix build --no-link .#checks.x86_64-linux.otel-collector-config 2>&1 | tee logs/s2-evidence/4.5-r31-red-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o 'otel-collector-config accepted a mutant: \[[^]]*\]'
```

Expected: `otel-collector-config accepted a mutant: ["reconcileNotNotified"]`, because today's policy (`:35-40`) names no `devloop-` unit.

- [ ] **Step 19: Extend R3.1's failure-wiring policy to `devloop-*` (GREEN, build)**

Replace (today's `:32-40`)

```nix
      # The failure path's policy (design "Failure path"): every store unit,
      # every disk-share oneshot and the collector notify, so a new unit of
      # these kinds fails the check until it is listed.
      notifiedByPolicy =
        name:
        lib.hasPrefix "greptimedb" name
        || lib.hasPrefix "zfs-set-" name
        || lib.hasPrefix "zfs-assert-" name
        || name == "opentelemetry-collector";
```

with

```nix
      # The failure path's policy (design "Failure path"): every store unit,
      # every disk-share oneshot, every dev-loop unit (S2 design D11) and the
      # collector notify, so a new unit of these kinds fails the check until
      # it is listed.
      notifiedByPolicy =
        name:
        lib.hasPrefix "greptimedb" name
        || lib.hasPrefix "zfs-set-" name
        || lib.hasPrefix "zfs-assert-" name
        || lib.hasPrefix "devloop-" name
        || name == "opentelemetry-collector";
```

and replace the clause name (today's `:335`) `"R3.1: a greptimedb*, zfs-set-*, zfs-assert-* or collector unit is not notified"` with `"R3.1: a greptimedb*, zfs-set-*, zfs-assert-*, devloop-* or collector unit is not notified"`.
Run:

```bash
log=logs/s2-evidence/4.5-r31-$(date -u +%Y%m%dT%H%M%SZ).log
{
  nix build --no-link -L .#checks.x86_64-linux.otel-collector-config && echo r31-built
  nix eval --impure --json --expr '
  let
    flake = builtins.getFlake (toString ./.);
    c = flake.nixosConfigurations.magnetite.config;
    units = c.services.observability-notify.units;
  in builtins.filter (n: builtins.substring 0 8 n == "devloop-" && !(builtins.elem n units)) (builtins.attrNames c.systemd.services)'
} 2>&1 | tee "$log" | tail -n 2
```

Expected: `r31-built`, so `failures input == [ ]` and every mutant, `reconcileNotNotified` among them, has a non-empty failure list (`:518-522`), then `[]`: no `devloop-` unit of magnetite is unlisted.
The mutant's one failure is `R3.1: a greptimedb*, zfs-set-*, zfs-assert-*, devloop-* or collector unit is not notified`, the only clause reading `notifyUnits` against the host's names that `lib.remove` of one listed unit can break.

- [ ] **Step 20: Re-record R3.1's evaluation cost (evaluation)**

Run:

```bash
log=logs/s2-evidence/4.5-r31-cost-$(date -u +%Y%m%dT%H%M%SZ).log
{
  NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-collector-config-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-collector-config.drvPath; echo
  jq '{gcTotalBytes: .gc.totalBytes, cpuTime}' /tmp/otel-collector-config-stats.json
  echo "method: NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/otel-collector-config-stats.json nix eval --option eval-cache false --raw .#.checks.x86_64-linux.otel-collector-config.drvPath"
} 2>&1 | tee "$log"
```

Expected: `gcTotalBytes` below `536870912`; at planning it was `483140336` (0.450 GiB, cpuTime 1.64 s) on stibnite at `@` `8cdbdf0c70c4` above `main@origin` `5f94a946baae`, by this method, so the record states both figures and Task 3's own measurement.
This task adds one prefix test over names the check already forces and one mutant, so the change is a few MB `[INFERENCE]`, which this measurement confirms; if the figure exceeds 0.5 GiB, stop and report it with Task 3's figure, because the margin was 53.7 MB before S2.

- [ ] **Step 21: Build the reconcile and its unit (build)**

Run:

```bash
nix build --no-link -L '.#nixosConfigurations.magnetite.config.systemd.units."devloop-reconcile.service".unit' '.#nixosConfigurations.magnetite.config.systemd.units."devloop-reconcile.timer".unit' 2>&1 | tee logs/s2-evidence/4.2-build-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 3
```

Expected: both units build, which builds `devloop-reconcile` (the service unit's `ExecStart` is its `bin/devloop-reconcile`) and runs `writeShellApplication`'s `shellcheck` over the script.
During planning the script, with the Nix interpolations replaced by paths, passed `shellcheck` 0.11.0 except for one finding that the replacement itself introduced (an environment variable standing for `currentSystem`).
From stibnite the build is routed to an `x86_64-linux` builder; if none accepts it, nixbot builds it on the pull request, and its log is this evidence instead.

- [ ] **Step 22: Format**

Run:

```bash
{
  nix fmt -- modules/nixos/devloop-collection.nix modules/checks/devloop-queries.nix modules/vm-tests/devloop-ingest.nix modules/checks/otel-collector-config.nix modules/machines/nixos/magnetite/default.nix
  nix fmt -- --fail-on-change && echo fmt-clean
} 2>&1 | tee logs/s2-evidence/4.7-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the last line is `fmt-clean`.
If the first command reformatted a file, rerun Steps 7, 16, 19 and 21 and expect the same lines.

- [ ] **Step 23: Run `devloop-ingest` on magnetite (GREEN, build, tasks.md 4.6)**

Run from the working copy, whose tree is the pull request's except for Step 25's ticks, on stibnite, which routes the build to magnetite, the only builder advertising `uid-range` (`modules/README.md:56-62`):

```bash
jj st --no-pager >/dev/null
nix build --no-link -L .#vmTests.x86_64-linux.devloop-ingest 2>&1 | tee logs/s2-evidence/4.6-devloop-ingest-$(date -u +%Y%m%dT%H%M%SZ).log | rg -o '(=== case [A-Za-z]+|ok: [A-Za-z]+|reconcile [0-9-]+: exit .*|reconcile passes: .*|mutant [A-Za-z]+ rejected: .*|devloop-reconcile: C[1-7] [a-z-]+: (ok|FAIL.*)|error:.*)$'
```

Expected: the build succeeds; Task 3's six cases each print `=== case <name>` and `ok: <name>` as in Task 3's log; then `=== case reconcile`, four times the seven lines `devloop-reconcile: C1 attributes: ok` … `devloop-reconcile: C7 current-system: ok` followed by `reconcile passes: after the overlap re-reads`, `reconcile passes: an attribute restarted and not finished again`, `reconcile passes: the attribute finished again after the window` and `reconcile passes: a deploy record shipped during C7's wait`, the last run's summary line reading `exit 0, <n> C7 waits` with `<n>` at least 1 and the earlier ones `0 C7 waits`; then, each after its leg's seven lines:
- `mutant omitCached rejected: devloop-reconcile: C1 attributes: FAIL missing from devloop.ci_attribute: …` naming `checks.x86_64-linux.reconcile-cached`;
- `mutant appendModeAttribute rejected: devloop-reconcile: C1 attributes: FAIL unexplained in devloop.ci_attribute: …` naming a `reconcile-append-` key whose stored and current microseconds are equal;
- `mutant omitNullPr rejected: devloop-reconcile: C2 builds: FAIL missing from devloop.ci_build: …` naming `9202`;
- `mutant noKeyValueParser rejected: devloop-reconcile: C3 batch-lines: FAIL journal {…} store {…} | devloop-reconcile: C4 batch-liveness: FAIL nixbot finished … gitea-mq/batch/ builds and devloop.batch_event has no batch built row`;
- `mutant silentStub rejected: devloop-reconcile: C4 batch-liveness: FAIL …`;
- `mutant pipelineWithoutFlaky rejected: devloop-reconcile: C5 batch-fields: FAIL <n> batch done rows have a null landed, ejected, builds or flaky`;
- `mutant deployRecordOtherPath rejected: devloop-reconcile: C6 deploys: FAIL /var/log/deploy-record.jsonl has 1 lines in the window and devloop.deploy_record 0 rows for store | devloop-reconcile: C7 current-system: FAIL devloop.deploy_record has no row for store after waiting 120 s; …`, after a summary line with `12 C7 waits` (the retry and its eventual failure);
- `mutant snippetSwapsClosures rejected: devloop-reconcile: C7 current-system: FAIL the latest stored closure is <X0> and the current system is <X1>`, after a summary line with `0 C7 waits`, because the file's last line names `<X0>`, not the current system;

then `ok: reconcile`, and no `error:` line.
Each leg's run is the real unit, started by systemd as its dynamic user with the container's `regulator-password` credential and the `systemd-journal` group, connecting to PostgreSQL by peer, so the passing legs also show the unit's identity, credential and journal access working.
The pull request's description names this log (Step 27).
If the case fails, the log's `reconcile <day>: exit <n>` line and the clause lines after it name the clause and the source; fix and rerun before Step 25.

- [ ] **Step 24: Build the neighbouring checks and magnetite (build)**

Run:

```bash
nix build --no-link .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.fleet-alert .#checks.x86_64-linux.greptimedb-envelope 2>&1 | tee logs/s2-evidence/4.7-neighbours-$(date -u +%Y%m%dT%H%M%SZ).log | tail -n 3
```

Expected: all three build.
`fleet-alert` rebuilds because `SystemdUnitFailed` excludes magnetite's notified units, which now include `devloop-reconcile` (`modules/nixos/fleet-alert/rules.nix:14-17`, `:55-58`), and the name matches `[A-Za-z0-9_-]+`.
If `nixos-magnetite` is not the attribute name, list the candidates with `nix eval --json .#checks.x86_64-linux --apply 'c: builtins.filter (n: builtins.match ".*magnetite.*" n != null) (builtins.attrNames c)'` and build the machine's toplevel check.

- [ ] **Step 25: Tick 4.1–4.6**

In `openspec/changes/stand-up-devloop-collection/tasks.md`, change the leading `- [ ]` of the lines beginning `- [ ] 4.1`, `- [ ] 4.2`, `- [ ] 4.3`, `- [ ] 4.4`, `- [ ] 4.5` and `- [ ] 4.6` to `- [x]` with the edit tool, and nothing else; 4.7 is ticked by the orchestrator when nixbot reports the pull request green, and 4.8 after D4.
Run: `rg -n '^- \[x\] 4\.[1-6] ' openspec/changes/stand-up-devloop-collection/tasks.md`
Expected: exactly six lines.

- [ ] **Step 26: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(devloop): daily devloop-reconcile against nixbot, the journal and the deploy record'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(devloop): daily devloop-reconcile against nixbot")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/nixos/devloop-collection.nix \
  modules/checks/devloop-queries.nix \
  modules/checks/devloop-queries/reconcile-fixtures.sql \
  modules/vm-tests/devloop-ingest.nix \
  modules/checks/otel-collector-config.nix \
  modules/machines/nixos/magnetite/default.nix \
  openspec/changes/stand-up-devloop-collection/tasks.md
jj diff --no-pager --summary -r "$change"
```

Expected: `M modules/nixos/devloop-collection.nix`, `M modules/checks/devloop-queries.nix`, `A modules/checks/devloop-queries/reconcile-fixtures.sql`, `M modules/vm-tests/devloop-ingest.nix`, `M modules/checks/otel-collector-config.nix`, `M modules/machines/nixos/magnetite/default.nix` and `M openspec/changes/stand-up-devloop-collection/tasks.md`, and nothing else.
If `tasks.md` carried hunks other than the six ticks before the squash, squash that file with `--interactive` and select only the ticks.
The orchestrator rebases the development join onto this change, pushes it and opens pull request 4 with `logs/s2-evidence/4.6-devloop-ingest-<ts>.log` named in its description; it is enqueued only after pull request 3 has landed.

- [ ] **Step 27: Pull request merged (tasks.md 4.7)**

The orchestrator's pull request shows nixbot green, including `checks.x86_64-linux.devloop-queries`, `otel-collector-config`, `fleet-alert` and `nixos-magnetite`, names Step 23's log, and merges through the queue; the orchestrator ticks 4.7.
Verify:

```bash
jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(devloop): daily devloop-reconcile against nixbot")' -T 'commit_id.shortest(12) ++ "\n"'
jj file show -r main@origin modules/machines/nixos/magnetite/default.nix | rg -c '"devloop-reconcile"'
```

Expected: one commit, then `3` (the notified unit, the holder and the kill-order key's string in `unitAdj "devloop-reconcile"`).

- [ ] **Step 28: Gate before deploy D4 (tasks.md 7.4 passed)**

Task 7's 7.4 has passed after D3: every `otlp_http/devloop_<table>` exporter's send-failed count is zero, `devloop-pg-grants` is active with both roles connecting by peer, the tables match their sources, and the deploy day's row counts are recorded (Task 7).
Run: `ls logs/s2-evidence/7.4-*.log && rg -n '^D3_END=' logs/s2-evidence/window.env`
Expected: Task 7's 7.4 evidence files and one `D3_END=` line, and Task 7's 7.4 record states the pass; if 7.4 has not passed, stop: D4 would start a reconcile against a collection not yet shown complete.

- [ ] **Step 29: Deploy D4 (tasks.md 4.8)**

Run:

```bash
logs/s2-evidence/s2-deploy.sh magnetite D4 2>&1 | tee logs/s2-evidence/4.8-deploy-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the procedure (Task 7 Step 0) finds `Queue is empty` in `nixbot-logs queue`, deploys magnetite from a fresh worktree of `origin/main`, and appends `D4_START=` and `D4_END=` to `logs/s2-evidence/window.env`; no other machine is deployed.
Verify on magnetite: `ssh magnetite.zt 'systemctl list-timers devloop-reconcile.timer --no-pager; systemctl show devloop-reconcile.service -p LoadCredential -p OOMScoreAdjust -p MemoryMax -p DynamicUser -p SupplementaryGroups'` shows the timer's next elapse at 02:15:00 UTC and `LoadCredential=regulator-password:/run/secrets/vars/per-machine/magnetite/greptimedb-users/regulator-password`, `OOMScoreAdjust=600`, `MemoryMax=134217728`, `DynamicUser=yes`, `SupplementaryGroups=systemd-journal` (delivered unit), logged to `logs/s2-evidence/4.8-delivered-$(date -u +%Y%m%dT%H%M%SZ).log`.
Task 7's 7.5 passes before group 5's deploy; the orchestrator ticks 4.8 then.
If the first runs fail, `journalctl -u devloop-reconcile` names the clause or the unreadable source; roll back by redeploying the previous `main@origin` commit through the same procedure, which removes the unit, its credential and its notification together.

#### Notes for Task 4

1. `devloop-reconcile`'s `LoadCredential` is set in magnetite's configuration, beside `greptimedb-envelope`'s (`:756-759`), not in `devloop-collection.nix`, so the module stays free of clan vars as `greptimedb.nix` and `fleet-alert.nix` are and the container can load its own file; `tasks.md` 4.3's verify still reads magnetite's evaluated `serviceConfig`, which carries it.
2. `reconcileQueries` takes the contract's `$1`, `$2` and `$3`; `currentFinish` uses the window to ignore keys outside it, and it returns only the unexplained keys, so the shell never interprets a timestamp.
   One `currentFinish` serves C1 and C2: a key with `attr` null is a build.
3. `devloop-queries` gains two mutants beyond the contract's three, `reconcileGrantWithoutFinishedAt` and `currentFinishIgnoresDuplicates`, so each new clause has a failing mutant; the contract row should list them.
4. The container case overrides the unit's `ExecStart` with the same function and a scratch `currentSystem`, because relinking the container's `/run/current-system` would break the test driver's `PATH`; the unit's identity, credential, groups and ordering are the module's.

---

