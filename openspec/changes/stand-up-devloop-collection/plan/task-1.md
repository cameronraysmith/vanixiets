### Task 1: Plan review, schema baseline, deploy record and its obligation (deploy D1)

Implements `tasks.md` 1.1–1.7 (brainstorm D17; design D9, D12, D14; DCI `Each activation appends one deploy record`, `The x86_64-linux NixOS machine checks carry the deploy-record snippet`; DC `A deploy can be attributed to the commits that built it`; WA `A43 — nixbot's migrations create the build and attribute columns the dev-loop copy reads, and finish times are transaction start times`).
The plan review and the schema baseline come first and change no repository file; each piece of code after them is judged by a test or check that runs and fails before the code exists: the script test fails while `flake.lib.deployRecordScript` is undefined, and the obligation fails on magnetite and stibnite before any machine imports `deploy-record`; each then passes, the obligation's `extendModules` overrides are shown rejected, and the machine check's cost is measured with the leading-dot method before the commit.
The snippet is installed on all ten machines, but CI holds the obligation only on the five `x86_64-linux` NixOS machine checks (cinnabar, electrum, galena, magnetite, pyrite): the four darwin machines' checks live under `checks.aarch64-darwin`, which nixbot runs best-effort so that a failure there is an ignored failure blocking no merge (`nixbot.toml`; `modules/checks/nixbot-best-effort-darwin.nix`), and scheelite is deferred (`modules/checks/machines.nix:6`), so the darwin machines and scheelite are shown once by evaluation in Steps 9 to 13 and are not held by CI.
Task 1 creates no dev-loop file: `modules/nixos/devloop-collection.nix` and the abandonment-marker clause, now in `devloop-queries`, belong to Task 2.

**Files:**
- Create: `modules/system/deploy-record.nix` (`flake.lib.deployRecordScript`, `flake.lib.deployRecordObligations`, `flake.modules.nixos.deploy-record`, `flake.modules.darwin.deploy-record`)
- Modify: `modules/checks/machines.nix:31-45` (`obligations` and `withFleetObligations`)
- Modify: `modules/machines/nixos/cinnabar/default.nix:27`, `modules/machines/nixos/electrum/default.nix:27`, `modules/machines/nixos/galena/default.nix:26`, `modules/machines/nixos/magnetite/default.nix:53`, `modules/machines/nixos/pyrite/default.nix:51`, `modules/machines/nixos/scheelite/default.nix:29`, `modules/machines/darwin/argentum/default.nix:36`, `modules/machines/darwin/blackphos/default.nix:32`, `modules/machines/darwin/rosegold/default.nix:36`, `modules/machines/darwin/stibnite/default.nix:32` (each the `base` line of its `with flakeModules` list)
- Modify: `openspec/changes/stand-up-devloop-collection/tasks.md:13-17` (tick 1.1–1.5), `openspec/changes/stand-up-devloop-collection/proposal.md:6-14` (Linear ledger)
- Modify, only for accepted plan-review findings (Step 1): `openspec/changes/stand-up-devloop-collection/{design.md,tasks.md,plan.md}` and `specs/`, before the planning pull request
- Create (git-ignored helpers): `logs/s2-evidence/1.2-normalise.sh`, `logs/s2-evidence/1.2-decision`, `logs/s2-evidence/1.3-script-test.sh`, `logs/s2-evidence/1.4-activation.nix`, `logs/s2-evidence/1.5-obligation-control.nix`
- Create (git-ignored evidence): `logs/s2-evidence/1.1-plan-review-<ts>.md`, `logs/s2-evidence/1.2-schema-{scratch,magnetite}.sql`, `logs/s2-evidence/1.2-schema-{scratch,magnetite}.norm.sql`, and the `logs/s2-evidence/1.<n>-*.log` files named per step
- Temporary: `/tmp/s2-pg` (scratch PostgreSQL cluster, removed in Step 2), `/tmp/s2-deploy-record.*` (removed by the script test)

**Interfaces:**
- Consumes: nothing from earlier tasks.
  From the repository today: `self.lib.omnigentFleetObligations` (`modules/lib/omnigent-fleet-obligations.nix:432-440`, `failures = machine: hostConfig: [ <case name> … ]`, `expectedOwners`); `self.lib.machineSystems` (`nix eval --json .#.lib.machineSystems` printed, on 2026-10-21, `aarch64-darwin` for argentum, blackphos, rosegold and stibnite and `x86_64-linux` for the other six).
  From the pins: nixpkgs `ac1faec44836a722f7b003834f367486ff9adfd1` (`/nix/store/l9sdkpnv33hmdr49q2nhahph8bpjmc9s-source`), whose `nixos/modules/system/activation/activation-script.nix` sets `systemConfig='@out@'` at `:55`, splices every non-empty snippet at `:68-72` and relinks `/run/current-system` after them at `:79`, replaces a snippet without `supportsDryActivation` (default `false`, `:112-114`) by a comment when dry-activating (`:41-50`), and types each entry as `either str (submodule { deps; text; supportsDryActivation; })` (`:96-128`); nix-darwin `f0ec2b3fae4df92ea7788359aef9e07bb88d720f` (`/nix/store/5hfhsa68x2sxc2c58ab6c0rz11bdwwv8-source`), whose `modules/system/activation-scripts.nix` runs under `set -e` (`:88`), sets `systemConfig=@out@` at `:102`, splices `postActivation.text` at `:140`, relinks `/run/current-system` at `:146` and defaults `postActivation.text` to `mkDefault ""` at `:158`, so `postActivation` is a valid activation script name; `nix-darwin@f0ec2b3:eval-config.nix:89` exposes `extendModules`, and `nix eval .#darwinConfigurations.stibnite --apply 'c: c ? extendModules'` printed `true` on 2026-10-21.
  The nixbot input `Mic92/nixbot@d020013fa0db4ec40ddd0593b9bfce65fedbff64` (`/nix/store/x9d1q6yxj0rvanz80rsji5fkm3ynhwgc-source`), 37 migrations `0001_initial.sql` to `0037_effect_when_changed.sql` under `nixbot/nixbot/migrations/`, none with `COLLATE`, `TABLESPACE`, `CREATE EXTENSION`, `GRANT` or `OWNER` (read with `rg -il` on 2026-10-21).
  magnetite's `services.postgresql.package` evaluates to `postgresql-16.15` (`/nix/store/v0fl5y3x05a99y7wssn6m2y6fdr2d0ay-postgresql-16.15.drv`, source `/nix/store/60aq8n5y6lhaqksbskq0fs4pbpbqddyf-source`); nixpkgs' `aarch64-darwin` `postgresql_16` at the same pin is `postgresql-16.15` from the same source, substitutable from `cache.nixos.org` as `/nix/store/1fxwm7jmfxcab71iy41a9cj1wf7xa6mr-postgresql-16.15` (all read 2026-10-21).
  Task 7 Step 0's `logs/s2-evidence/s2-deploy.sh HOST LABEL` and Task 7 Step 2's pre-D1 baseline, which appends `PRE_D1_SYSTEM=<readlink -f /run/current-system>` and `PRE_D1_LINES=<line count of /var/log/deploy-record.jsonl, 0 when absent>` to `logs/s2-evidence/window.env`; `s2-deploy.sh` also appends `D1_COMMIT=<origin/main sha>` before `D1_START` (agreed with S2PlanT7).
  CAM-69 in team `CAM`, project `fleet-observability` (slugId `aeed302bea3b`), workspace `cameronraysmith`, with the ledger in `proposal.md`'s front matter (`:1-15`).
- Produces:
  - `flake.lib.deployRecordScript { pkgs; hostName; file ? "/var/log/deploy-record.jsonl"; currentSystem ? "/run/current-system"; }`, returning the string `lib.getExe` of a `writeShellApplication` named `deploy-record-<hostName>`, so the path ends in `/bin/deploy-record-<hostName>`; it takes the activated closure as `$1`, creates `file` (and its directory) with mode `0644` when absent, and appends one line written by `printf`: `{"host":"<hostName>","closure":"<$1>","previous_closure":"<readlink -f currentSystem>","ts":"<date -u +%Y-%m-%dT%H:%M:%SZ>"}`, without `previous_closure` when `currentSystem` does not exist; `runtimeInputs = [ pkgs.coreutils ]`, no `jq`.
  - `flake.modules.nixos.deploy-record`: `system.activationScripts.deploy-record.text = "${config.vanixiets.deployRecord.script} \"$systemConfig\""`, no `deps`, no `supportsDryActivation`.
  - `flake.modules.darwin.deploy-record`: `system.activationScripts.postActivation.text = lib.mkAfter "${config.vanixiets.deployRecord.script} \"$systemConfig\""`.
  - Both declare the read-only option `vanixiets.deployRecord.script` (`types.str`, no default) and define it once as `deployRecordScript { inherit pkgs; inherit (config.networking) hostName; }`.
  - `flake.lib.deployRecordObligations = { failures = name: hostConfig: [ <message> … ]; }`, empty exactly when the activation script the platform assembles (`hostConfig.system.activationScripts.script` on NixOS, the string nixpkgs' `apply` adds to the option at `activation-script.nix:168-173`; `hostConfig.system.activationScripts.script.text` on darwin, defined at `activation-scripts.nix:83-152`; the platform chosen by `self.lib.machineSystems.${name}`) contains `hostConfig.vanixiets.deployRecord.script`, so it fails when the entry is dropped, emptied or replaced by any means; the messages are `<name> does not import deploy-record, so vanixiets.deployRecord.script is undefined` and `<name>'s <option path> does not run <script>`.
  - `modules/checks/machines.nix`'s `withFleetObligations` asserting both sets, with the message `Fleet obligations unmet on <name>: omnigentFleetObligations [<cases>]; deployRecordObligations [<messages>]`.
  - `logs/s2-evidence/1.2-normalise.sh` (stdin to stdout), the normalised dumps `logs/s2-evidence/1.2-schema-{scratch,magnetite}.norm.sql`, and `logs/s2-evidence/1.2-decision` holding exactly `lexical` or `migrator`, which Task 2's `devloop-queries` steps read.

- [ ] **Step 1: Review the plan before any implementation commit (tasks.md 1.1)**

The orchestrator spawns one subagent with the `task` tool, agent type `task` (the default), on an Opus model, read-only, with exactly this prompt:

```text
You are reviewing slice S2 of the vanixiets fleet observability work before any of it is implemented (Linear CAM-69). The repository is $REPO, jj-colocated; work in it read-only.

Read-only means: do not edit, create or delete any file; run no jj or git command that changes anything; run no nix build, no deploy, no ssh, and touch no Linear issue. You may read files, run `nix eval` (read-only), `rg`, and `gh api` GET requests.

Read, in this order:
- openspec/changes/stand-up-devloop-collection/brainstorm.md, proposal.md, design.md, tasks.md, plan.md, and specs/*/spec.md
- docs/notes/development/observability/charter.md (v22 at the end), decisions/ADR-004-signal-scope-and-schema.md, decisions/ADR-005-dev-loop-instrumentation.md, decisions/ADR-009-alerting.md, components/devloop-exporters.md, components/fleet-alert.md
- logs/s2/grounding.md and logs/s2/spike-dedup.md
- openspec/changes/archive/2026-10-21-stand-up-fleet-alerting/review.md and retrospective.md §6; openspec/changes/archive/2026-10-18-stand-up-greptimedb-on-magnetite/retrospective.md §6
- every repository file the plan modifies, at the lines it cites, and vendor source at the pinned revisions the plan cites when a finding depends on it

Answer the holistic review's four questions over design.md, tasks.md, plan.md and the specs:
1. Critical oversights: what will fail, lose data, leak free text or credentials, or leave a requirement undischarged if the plan is executed as written?
2. Significant architecture improvements: where would a different design be clearly simpler or more robust for the same requirements?
3. Checks that cannot fail, clauses that restate the line they judge (a value compared with the line that sets it, or two values from one source), and properties that no check, assertion, container case or deploy observation covers.
4. Checks or mechanisms that cost more than the invariant they protect (evaluation cost against the 0.5 GiB budget, build time, operational burden).

Then list every new check clause and every new module or host assertion in plan Tasks 1 to 5 (tasks.md groups 1 to 5), including container-test cases that act as negative controls, each with its two independently defined value sources, each source given as file:line or as the evaluated attribute it reads, and say for each whether the two sources are independent; flag any whose sources are one value, or a value and the line that sets it.

Cite file:line (repository) or owner/repo@rev:path:line (vendor) for every claim; mark anything you did not verify [INFERENCE].

Your final answer is the report, in markdown, with exactly these headings in this order:
## Summary
(one line per sentence: how many findings, how many critical, significant and minor, and the closest to critical)
## Findings
| Finding | Category | Severity | Belongs in |
|---|---|---|---|
(one row per finding; Finding is "F<n> <short title>"; Category is one or more of 1, 2, 3, 4; Severity is critical, significant or minor; Belongs in names the plan task, tasks.md item or design decision to change)
## Finding details
(### F<n> per finding: what, the evidence with citations, and the exact change you propose)
## Clauses and assertions
| Task | Clause or assertion | Value source A | Value source B | Independent |
|---|---|---|---|---|
```

The orchestrator writes the subagent's final answer verbatim to `logs/s2-evidence/1.1-plan-review-<ts>.md` (`<ts>` from `date -u +%Y%m%dT%H%M%SZ` when the answer arrives), then puts each finding to the operator and appends the operator's decisions to the same file under a final heading:

```markdown
## Dispositions

| Finding | Disposition | Operator's reason | Applied in |
|---|---|---|---|
| F1 | accepted | <reason> | <file and section, or tasks.md item> |
```

Disposition is exactly one of `accepted`, `rejected` or `deferred`; a deferred finding names its Linear issue or later slice in `Applied in`.
Run:

```bash
f=$(ls -t logs/s2-evidence/1.1-plan-review-*.md | head -n 1)
diff <(awk '/^## Findings/{s=1;next} /^## /{s=0} s && /^\| F[0-9]+ /{print $2}' "$f" | sort -u) \
     <(awk '/^## Dispositions/{s=1;next} /^## /{s=0} s && /^\| F[0-9]+ \| (accepted|rejected|deferred) \|/{print $2}' "$f" | sort -u) \
  && echo dispositions-complete
```

Expected: `dispositions-complete`, so every finding has exactly one recorded disposition (tasks.md 1.1's verify, delivered file).
Every accepted finding is applied to `design.md`, `tasks.md`, `plan.md` or `specs/` in the working copy before Step 3, and its `Applied in` cell names where; if an accepted finding changes this task, the executor rereads Task 1 before Step 3.
The planning pull request (this change directory, `plan.md` included, and the charter v22 amendments under `docs/notes/development/observability/`) is opened by the orchestrator after the dispositions are applied and lands through the merge queue before Step 3 starts.

- [ ] **Step 2: Take the schema baseline for `devloop-queries` (tasks.md 1.2)**

The scratch cluster runs on stibnite with nixpkgs' native `postgresql_16`, not magnetite's `x86_64-linux` package, which cannot execute on `aarch64-darwin`.
The expression below asserts that the local package has magnetite's version and the very same source tree (`src.outPath`), so the server catalogue and `pg_dump`'s formatting are those of 16.15 as magnetite runs it, and only the target platform differs; the migrations declare no collation, tablespace or extension, and `initdb --no-locale` keeps the cluster's locale out of the comparison, so nothing platform-dependent reaches the three tables' DDL.
If either assertion fails, stop: the fallback is the same procedure on magnetite as the operator's user under `/tmp`, with `/run/current-system/sw/bin`'s PostgreSQL, a socket under `/tmp/s2-pg` and no TCP listener, which leaves the production cluster untouched; record that choice in the log.

Create `logs/s2-evidence/1.2-normalise.sh` (git-ignored) with exactly:

```bash
#!/usr/bin/env bash
# Normalise a pg_dump --schema-only of builds, build_attributes and projects for comparison (tasks.md 1.2).
# Drops comments and blank lines, SET and set_config lines, pg_dump 16.10+'s \restrict/\unrestrict lines
# (a random key per dump), ownership, privileges and COMMENT ON. Task 2's devloop-queries reuses it.
set -euo pipefail
LC_ALL=C grep -vE -e '^--' -e '^$' -e '^SET ' -e '^SELECT pg_catalog\.set_config\(' -e '^\\(un)?restrict ' -e ' OWNER TO ' -e '^(GRANT|REVOKE) ' -e '^COMMENT ON '
```

Run:

```bash
chmod +x logs/s2-evidence/1.2-normalise.sh && bash -n logs/s2-evidence/1.2-normalise.sh && echo syntax-ok
```

Expected: `syntax-ok`.

Build the local package, start the scratch cluster and apply the input's migrations in lexical order:

```bash
ev=logs/s2-evidence; ts=$(date -u +%Y%m%dT%H%M%SZ)
{
  pg=$(nix build --no-link --print-out-paths --impure --expr '
    let
      f = builtins.getFlake (toString ./.);
      served = f.nixosConfigurations.magnetite.config.services.postgresql.package;
      local = f.inputs.nixpkgs.legacyPackages.${builtins.currentSystem}."postgresql_${f.inputs.nixpkgs.lib.versions.major served.version}";
    in
    assert local.version == served.version;
    assert local.src.outPath == served.src.outPath;
    local.out')
  echo "package: $pg"
  "$pg/bin/pg_dump" --version
  mig=$(nix eval --raw --impure --expr '(builtins.getFlake (toString ./.)).inputs.nixbot.outPath')/nixbot/nixbot/migrations
  echo "migrations: $mig ($(ls "$mig"/*.sql | wc -l | tr -d ' ') files)"
  rm -rf /tmp/s2-pg && mkdir -p /tmp/s2-pg
  "$pg/bin/initdb" -D /tmp/s2-pg/data -U postgres --auth=trust --no-locale --encoding=UTF8 >/tmp/s2-pg/initdb.log
  "$pg/bin/pg_ctl" -D /tmp/s2-pg/data -l /tmp/s2-pg/server.log -o "-k /tmp/s2-pg -c listen_addresses= -p 54329" -w start
  "$pg/bin/createdb" -h /tmp/s2-pg -p 54329 -U postgres nixbot
  for f in $(LC_ALL=C ls "$mig"/*.sql); do
    "$pg/bin/psql" -X -q -h /tmp/s2-pg -p 54329 -U postgres -d nixbot -v ON_ERROR_STOP=1 --single-transaction -f "$f" || { echo "FAILED: $(basename "$f")"; exit 1; }
    echo "applied: $(basename "$f")"
  done
  "$pg/bin/pg_dump" --schema-only -h /tmp/s2-pg -p 54329 -U postgres -d nixbot -t builds -t build_attributes -t projects > "$ev/1.2-schema-scratch.sql"
  "$pg/bin/pg_ctl" -D /tmp/s2-pg/data -m fast -w stop
  rm -rf /tmp/s2-pg
  wc -l "$ev/1.2-schema-scratch.sql"
} 2>&1 | tee "$ev/1.2-schema-scratch-$ts.log"
```

Expected: `package: /nix/store/1fxwm7jmfxcab71iy41a9cj1wf7xa6mr-postgresql-16.15`, `pg_dump (PostgreSQL) 16.15`, `(37 files)`, 37 `applied:` lines from `0001_initial.sql` to `0037_effect_when_changed.sql`, no `FAILED:` line, `server stopped`, and a non-empty `1.2-schema-scratch.sql`.
If a migration fails under `--single-transaction`, the `FAILED:` line names it; record it, select `migrator` below and continue with the magnetite dump.

Take magnetite's dump read-only, as `postgres`, with its schema version recorded:

```bash
ev=logs/s2-evidence; ts=$(date -u +%Y%m%dT%H%M%SZ)
{
  ssh magnetite.zt 'pg_dump --version; sudo -u postgres psql -XAt -d nixbot -c "select max(version), count(*) from schema_migrations"'
  ssh magnetite.zt 'sudo -u postgres pg_dump --schema-only -d nixbot -t builds -t build_attributes -t projects' > "$ev/1.2-schema-magnetite.sql"
  wc -l "$ev/1.2-schema-magnetite.sql"
} 2>&1 | tee "$ev/1.2-schema-magnetite-$ts.log"
```

Expected: `pg_dump (PostgreSQL) 16.15`, `37|37`, and a non-empty `1.2-schema-magnetite.sql`; `psql` is on magnetite's path (`logs/s2/grounding.md:14`), and `pg_dump` ships in the same package.

Normalise both identically, diff, and record the decision:

```bash
ev=logs/s2-evidence; ts=$(date -u +%Y%m%dT%H%M%SZ)
{
  for side in scratch magnetite; do
    logs/s2-evidence/1.2-normalise.sh < "$ev/1.2-schema-$side.sql" > "$ev/1.2-schema-$side.norm.sql"
  done
  shasum -a 256 "$ev"/1.2-schema-scratch.sql "$ev"/1.2-schema-magnetite.sql "$ev"/1.2-schema-scratch.norm.sql "$ev"/1.2-schema-magnetite.norm.sql
  grep -c '^\\restrict ' "$ev/1.2-schema-scratch.sql" "$ev/1.2-schema-magnetite.sql" || true
  if diff -u "$ev/1.2-schema-scratch.norm.sql" "$ev/1.2-schema-magnetite.norm.sql"; then
    echo lexical > "$ev/1.2-decision"
  else
    echo migrator > "$ev/1.2-decision"
  fi
  echo "decision: $(cat "$ev/1.2-decision")"
} 2>&1 | tee "$ev/1.2-schema-diff-$ts.log"
```

Expected: four sha256 lines, the two `\restrict` counts (1 each when pg_dump emits the line, which the normaliser removes), no diff output, and `decision: lexical`; tasks.md 1.2's verify is this log (command; magnetite read-only).
If the diff is not empty, read each differing line; a difference that is an artefact of the dump rather than of the schema (a further version-specific line) is added to `1.2-normalise.sh` as one more `-e` pattern, with the reason in the log, and the normalisation and diff are rerun; any remaining difference is a schema difference, the decision is `migrator`, and the difference stays in the log for Task 2, which then applies the migrations with nixbot's own migrator from the input.

- [ ] **Step 3: Confirm the base and record the machine check's cost before the change**

Run from `$REPO`:

```bash
pwd
jj git fetch
jj log --no-graph -r main@origin -T 'commit_id.shortest(12) ++ " " ++ description.first_line() ++ "\n"'
jj file show -r main@origin openspec/changes/stand-up-devloop-collection/plan.md | head -n 1
jj file show -r main@origin flake.lock | jq -r .nodes.nixbot.locked.rev
ls logs/s2-evidence/1.1-plan-review-*.md logs/s2-evidence/1.2-decision
jj diff --name-only -- modules
```

Expected: the repository path; `main@origin` contains the planning pull request, so the `plan.md` line prints `# Dev-loop collection (S2) implementation plan`; the nixbot revision is `d020013fa0db4ec40ddd0593b9bfce65fedbff64`; both evidence files exist; no file under `modules/` differs in the working copy.
If any differs, stop and report to the orchestrator.

Record the cost of the machine check this task changes, before the change (evaluation):

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/nixos-magnetite-before-stats.json \
  nix eval --option eval-cache false --raw .#.checks.x86_64-linux.nixos-magnetite.drvPath; echo
jq '{method: "NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.nixos-magnetite.drvPath", bytes: .gc.totalBytes, cpu: .cpuTime}' /tmp/nixos-magnetite-before-stats.json 2>&1 | tee logs/s2-evidence/1.5-nixos-magnetite-cost-before-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: a `/nix/store/…-nixos-system-magnetite-….drv` path and a `bytes` figure, recorded with its method; the 0.5 GiB budget does not apply to a machine's own toplevel check, which forces the whole host (about 2.61 GiB for magnetite, design D12, CH:319), so Step 13 records the difference instead.

- [ ] **Step 4: Write the deploy-record script test**

Create `logs/s2-evidence/1.3-script-test.sh` (git-ignored) with exactly:

```bash
#!/usr/bin/env bash
# tasks.md 1.3: render flake.lib.deployRecordScript with a scratch file and a scratch
# current-system link, run it as an activation runs it (closure as $1 from $systemConfig),
# and judge each appended line with jq. Run from the repository root.
set -euo pipefail
work=$(readlink -f "$(mktemp -d /tmp/s2-deploy-record.XXXXXX)")
trap 'rm -rf "$work"' EXIT
mkdir -p "$work/system-a" "$work/system-b"
file=$work/log/deploy-record.jsonl
farm=$(nix build --no-link --print-out-paths --impure --expr "
  let
    f = builtins.getFlake (toString ./.);
    pkgs = f.inputs.nixpkgs.legacyPackages.\${builtins.currentSystem};
    script = f.lib.deployRecordScript {
      inherit pkgs;
      hostName = \"testhost\";
      file = \"$file\";
      currentSystem = \"$work/current-system\";
    };
  in pkgs.linkFarm \"deploy-record-test\" [ { name = \"deploy-record\"; path = script; } ]")
script=$(readlink -f "$farm/deploy-record")
echo "script: $script"
case $script in */bin/deploy-record-testhost) ;; *) echo "FAIL: script is not named deploy-record-testhost"; exit 1 ;; esac
if grep -qE '/bin/jq|(^|[[:space:]])jq[[:space:]]' "$script"; then echo "FAIL: the script calls jq"; exit 1; fi

# check LINE PREVIOUS: exit 0 when LINE has exactly the expected keys and values;
# PREVIOUS is true when previous_closure must be system-a, false when it must be absent.
check() {
  jq -e --arg a "$work/system-a" --arg b "$work/system-b" --argjson prev "$2" '
    (keys == (if $prev then ["closure", "host", "previous_closure", "ts"] else ["closure", "host", "ts"] end))
    and .host == "testhost"
    and .closure == $b
    and (if $prev then .previous_closure == $a else true end)
    and (.ts | test("^[0-9]{4}-[0-9]{2}-[0-9]{2}T[0-9]{2}:[0-9]{2}:[0-9]{2}Z$"))
  ' <<<"$1" >/dev/null
}

# Case 1: a current-system link exists; the file and its directory do not; a strict umask.
ln -s "$work/system-a" "$work/current-system"
systemConfig=$work/system-b
(umask 0077; "$script" "$systemConfig")
[ "$(wc -l < "$file" | tr -d ' ')" = 1 ] || { echo "FAIL: case 1 appended $(wc -l < "$file") lines"; exit 1; }
line1=$(sed -n 1p "$file")
check "$line1" true || { echo "FAIL: case 1 line: $line1"; exit 1; }
[ "$(ls -l "$file" | cut -c1-10)" = "-rw-r--r--" ] || { echo "FAIL: mode $(ls -l "$file" | cut -c1-10)"; exit 1; }
echo "ok: with a current-system link, one line with host, closure, previous_closure and ts; file created mode 0644 under umask 0077"

# Case 2: a second activation appends exactly one line and leaves the first unchanged.
"$script" "$systemConfig"
[ "$(wc -l < "$file" | tr -d ' ')" = 2 ] || { echo "FAIL: case 2 left $(wc -l < "$file") lines"; exit 1; }
[ "$(sed -n 1p "$file")" = "$line1" ] || { echo "FAIL: case 2 changed the first line"; exit 1; }
check "$(sed -n 2p "$file")" true || { echo "FAIL: case 2 line: $(sed -n 2p "$file")"; exit 1; }
echo "ok: a second activation appends exactly one line"

# Case 3: no current-system link (the first activation of a NixOS boot).
rm "$work/current-system" "$file"
"$script" "$systemConfig"
[ "$(wc -l < "$file" | tr -d ' ')" = 1 ] || { echo "FAIL: case 3 appended $(wc -l < "$file") lines"; exit 1; }
line3=$(sed -n 1p "$file")
check "$line3" false || { echo "FAIL: case 3 line: $line3"; exit 1; }
echo "ok: without a current-system link, one line without previous_closure"

# The assertion can fail: case 1's assertion rejects case 3's line.
if check "$line3" true; then echo "FAIL: the four-field assertion accepted a line without previous_closure"; exit 1; fi
echo "ok: the four-field assertion rejects a line without previous_closure"
echo "all deploy-record script cases passed"
```

`/tmp` is a symbolic link to `/private/tmp` on macOS, so `work` is resolved first and the expected `previous_closure` equals what `readlink -f` returns.
The pattern for `jq` matches a command, not the letters `jq` inside a store-path hash, which nix's base-32 alphabet allows.
This test and Step 6's file were rehearsed during planning on stibnite, in a scratch flake under `/tmp` exporting Step 6's `flake.lib` over the nixpkgs pin: all four `ok:` lines and `all deploy-record script cases passed` printed, and `deployRecordObligations.failures` returned `[]` for a NixOS entry running the script and the expected messages for a missing option, an entry overridden to a plain string and a darwin `postActivation` without the script.
Run: `chmod +x logs/s2-evidence/1.3-script-test.sh && bash -n logs/s2-evidence/1.3-script-test.sh && echo syntax-ok`
Expected: `syntax-ok`.

- [ ] **Step 5: Run the script test before the renderer exists (RED, build)**

Run:

```bash
logs/s2-evidence/1.3-script-test.sh 2>&1 | tee logs/s2-evidence/1.3-script-test-red-$(date -u +%Y%m%dT%H%M%SZ).log; echo "exit ${PIPESTATUS[0]}"
```

Expected: `error: attribute 'deployRecordScript' missing`, no `ok:` line, and a non-zero exit.

- [ ] **Step 6: Write `modules/system/deploy-record.nix`**

Create `modules/system/deploy-record.nix` with exactly this content, following `modules/system/zt-dns.nix` (one file holding both platforms' modules) and `modules/nixos/fleet-alert.nix:51-458` (an outer `let` whose functions are exported through `flake.lib`):

```nix
# Deploy record (S2, design D9, D12). Every activation appends one JSON line
#
#   {"host":"<hostName>","closure":"<$systemConfig>","previous_closure":"<readlink -f /run/current-system>","ts":"<UTC>"}
#
# to /var/log/deploy-record.jsonl, created mode 0644, so a deploy can be
# attributed to the commits that built its closure. NixOS and nix-darwin both
# run their activation snippets before they relink /run/current-system
# (nixpkgs activation-script.nix, nix-darwin activation-scripts.nix), so the
# link still names the system being replaced; previous_closure is absent when
# the link does not exist, as on the first activation of a NixOS boot. Store
# paths need no JSON escaping, so printf writes the line and no machine needs
# jq at activation. The host name is a literal fixed at evaluation.
#
# Both modules define the read-only option vanixiets.deployRecord.script.
# flake.lib.deployRecordObligations, asserted by modules/checks/machines.nix on
# the five x86_64-linux NixOS machine checks, fails unless the machine's activation runs it.
{ config, lib, ... }:
let
  deployRecordScript =
    {
      pkgs,
      hostName,
      file ? "/var/log/deploy-record.jsonl",
      currentSystem ? "/run/current-system",
    }:
    lib.getExe (
      pkgs.writeShellApplication {
        name = "deploy-record-${hostName}";
        runtimeInputs = [ pkgs.coreutils ];
        text = ''
          closure=$1
          host=${lib.escapeShellArg hostName}
          file=${lib.escapeShellArg file}
          current=${lib.escapeShellArg currentSystem}
          ts=$(date -u +%Y-%m-%dT%H:%M:%SZ)
          if [ ! -e "$file" ]; then
            mkdir -p "$(dirname "$file")"
            touch "$file"
            chmod 0644 "$file"
          fi
          if [ -e "$current" ]; then
            previous=$(readlink -f "$current")
            printf '{"host":"%s","closure":"%s","previous_closure":"%s","ts":"%s"}\n' \
              "$host" "$closure" "$previous" "$ts" >>"$file"
          else
            printf '{"host":"%s","closure":"%s","ts":"%s"}\n' \
              "$host" "$closure" "$ts" >>"$file"
          fi
        '';
      }
    );

  scriptOption = lib.mkOption {
    type = lib.types.str;
    readOnly = true;
    description = ''
      The deploy-record script rendered for this host's networking.hostName;
      the activation runs it with the activated $systemConfig.
    '';
  };

  invocation = script: "${script} \"$systemConfig\"";

  deployRecordObligations = {
    failures =
      name: hostConfig:
      let
        isDarwin = lib.hasSuffix "-darwin" config.flake.lib.machineSystems.${name};
        script = hostConfig.vanixiets.deployRecord.script or null;
        optionPath =
          if isDarwin then "system.activationScripts.script.text" else "system.activationScripts.script";
        # The activation script the platform assembles from every snippet:
        # nixpkgs' activation-script.nix adds `script` in the option's apply,
        # nix-darwin's activation-scripts.nix defines `script.text`.
        text =
          if isDarwin then
            hostConfig.system.activationScripts.script.text
          else
            hostConfig.system.activationScripts.script;
      in
      if script == null then
        [ "${name} does not import deploy-record, so vanixiets.deployRecord.script is undefined" ]
      else
        # lib.hasInfix turns the script path into a regular expression, which
        # builtins.match refuses while it carries the script's string context.
        lib.optional (
          !lib.hasInfix (builtins.unsafeDiscardStringContext script) (
            builtins.unsafeDiscardStringContext text
          )
        ) "${name}'s ${optionPath} does not run ${script}";
  };
in
{
  flake.lib = {
    inherit deployRecordScript deployRecordObligations;
  };

  flake.modules.nixos.deploy-record =
    { config, pkgs, ... }:
    {
      options.vanixiets.deployRecord.script = scriptOption;
      config = {
        vanixiets.deployRecord.script = deployRecordScript {
          inherit pkgs;
          inherit (config.networking) hostName;
        };
        # No supportsDryActivation: a dry activation replaces the snippet
        # with a comment, so it appends nothing.
        system.activationScripts.deploy-record.text = invocation config.vanixiets.deployRecord.script;
      };
    };

  # postActivation runs under set -e as the last snippet before the relink;
  # mkAfter places the record after every other postActivation addition.
  flake.modules.darwin.deploy-record =
    { config, pkgs, ... }:
    {
      options.vanixiets.deployRecord.script = scriptOption;
      config = {
        vanixiets.deployRecord.script = deployRecordScript {
          inherit pkgs;
          inherit (config.networking) hostName;
        };
        system.activationScripts.postActivation.text = lib.mkAfter (
          invocation config.vanixiets.deployRecord.script
        );
      };
    };
}
```

`invocation` builds an ordinary string, so `$systemConfig` stays literal; an indented string starting with `''${` would escape the interpolation.
The option has no default and is defined once in the module, so a second definition anywhere fails evaluation as a read-only option set twice.
Then snapshot the new file:
Run: `jj st --no-pager >/dev/null && git ls-files modules/system/deploy-record.nix`
Expected: `modules/system/deploy-record.nix`.

- [ ] **Step 7: Run the script test (GREEN, build)**

Run:

```bash
logs/s2-evidence/1.3-script-test.sh 2>&1 | tee logs/s2-evidence/1.3-script-test-$(date -u +%Y%m%dT%H%M%SZ).log; echo "exit ${PIPESTATUS[0]}"
```

Expected: `script: /nix/store/…-deploy-record-testhost/bin/deploy-record-testhost`, then in order `ok: with a current-system link, one line with host, closure, previous_closure and ts; file created mode 0644 under umask 0077`, `ok: a second activation appends exactly one line`, `ok: without a current-system link, one line without previous_closure`, `ok: the four-field assertion rejects a line without previous_closure`, `all deploy-record script cases passed`, and `exit 0`; `writeShellApplication`'s build ran `shellcheck` over the script.
This is tasks.md 1.3's build verify; its evaluation verify is Step 11.

- [ ] **Step 8: Make the machine checks assert the deploy-record obligation**

The clause relates two independently defined values: the script `deploy-record.nix` renders into `vanixiets.deployRecord.script` from `flake.lib.deployRecordScript` and the host's `networking.hostName`, and the whole activation script the platform's own module assembles from every snippet (nixpkgs' `apply` at `activation-script.nix:168-173` builds `system.activationScripts.script` from all non-empty entries, `:68-72`; nix-darwin's `activation-scripts.nix:83-152` builds `system.activationScripts.script.text`, splicing the lines-merged `postActivation.text` at `:140`), so dropping, emptying or replacing the entry by any means fails it.
The negative controls are Step 9 (the real hosts before they import the module) and Step 12 (`extendModules` overrides).
In `modules/checks/machines.nix`, replace lines 31-45 (from `      obligations = self.lib.omnigentFleetObligations;` through the `        toplevel;` that ends `withFleetObligations`) with exactly:

```nix
      obligations = self.lib.omnigentFleetObligations;
      deployRecordObligations = self.lib.deployRecordObligations;

      withFleetObligations =
        name: machineConfig: toplevel:
        let
          unmet = obligations.failures name machineConfig;
          unmetDeployRecord = deployRecordObligations.failures name machineConfig;
          hostFailures = map (a: a.message) (lib.filter (a: !a.assertion) machineConfig.assertions);
        in
        assert lib.assertMsg (unmet == [ ] && unmetDeployRecord == [ ]) (
          "Fleet obligations unmet on ${name}: omnigentFleetObligations [${lib.concatStringsSep ", " unmet}]; deployRecordObligations [${lib.concatStringsSep ", " unmetDeployRecord}]"
          + lib.optionalString (hostFailures != [ ]) (
            "\n${name} assertion failures: ${lib.concatStringsSep "\n" hostFailures}"
          )
        );
        toplevel;
```

`scheelite` stays in `deferred` (`:6`), so it gets no machine check; the darwin checks are built from `darwinForSystem` (`:27-29`) as today and stay best-effort, because nixbot builds `x86_64-linux` only.
The assertion over `obligations.expectedOwners` (`:65-67`) is unchanged: the deploy-record obligation applies to every machine that has a check, so it has no owner list.
Because nixbot builds only `checks.x86_64-linux`, CI holds the obligation on cinnabar, electrum, galena, magnetite and pyrite only; Steps 9, 11 and 12 show the darwin machines and scheelite by evaluation, once.

- [ ] **Step 9: Show the obligation failing on the real hosts before any imports it (RED, evaluation)**

Run:

```bash
{
  nix eval --raw .#.checks.x86_64-linux.nixos-magnetite.drvPath; echo
  nix eval --raw .#.checks.aarch64-darwin.darwin-stibnite.drvPath; echo
} 2>&1 | tee logs/s2-evidence/1.5-obligation-red-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E 'Fleet obligations unmet|^/nix/store'
```

Expected: two errors and no store path: `Fleet obligations unmet on magnetite: omnigentFleetObligations []; deployRecordObligations [magnetite does not import deploy-record, so vanixiets.deployRecord.script is undefined]` and the same for `stibnite`.

- [ ] **Step 10: Import `deploy-record` on all ten machines (tasks.md 1.4)**

In each file below, replace the single line `        base` (eight spaces, then `base`) at the given line, the first entry of its `with flakeModules` list, with exactly these two lines:

```nix
        base
        deploy-record
```

| File | Line | Next line today |
|---|---|---|
| `modules/machines/nixos/cinnabar/default.nix` | 27 | `        fleet-alert` |
| `modules/machines/nixos/electrum/default.nix` | 27 | `        hm-sops-bridge` |
| `modules/machines/nixos/galena/default.nix` | 26 | `        hm-sops-bridge` |
| `modules/machines/nixos/magnetite/default.nix` | 53 | `        hm-sops-bridge` |
| `modules/machines/nixos/pyrite/default.nix` | 51 | `        dnscrypt-proxy` |
| `modules/machines/nixos/scheelite/default.nix` | 29 | `        hm-sops-bridge` |
| `modules/machines/darwin/argentum/default.nix` | 36 | `        ssh-ca-trust` |
| `modules/machines/darwin/blackphos/default.nix` | 32 | `        ssh-ca-trust` |
| `modules/machines/darwin/rosegold/default.nix` | 36 | `        ssh-ca-trust` |
| `modules/machines/darwin/stibnite/default.nix` | 32 | `        casks` |

`flakeModules` is `config.flake.modules.nixos` in the six NixOS files and `config.flake.modules.darwin` in the four darwin files (`:7`–`:11` of each), so the same name selects each platform's module.
Run: `jj diff --stat -- modules/machines | tail -n 1`
Expected: `10 files changed, 10 insertions(+), 0 deletions(-)`.

- [ ] **Step 11: Show each of the ten machines' activation running its own script before the relink, once by evaluation (GREEN, evaluation; tasks.md 1.3, 1.4)**

Create `logs/s2-evidence/1.4-activation.nix` (git-ignored, outside `modules/`, so import-tree does not load it) with exactly:

```nix
# tasks.md 1.3 and 1.4: one machine's deploy-record script, its presence in the
# activation entry and in the assembled activation script, and its place before
# the relink of /run/current-system.
{ repo, host }:
let
  f = builtins.getFlake repo;
  lib = f.inputs.nixpkgs.lib;
  isDarwin = lib.hasSuffix "-darwin" f.lib.machineSystems.${host};
  c = (if isDarwin then f.darwinConfigurations else f.nixosConfigurations).${host}.config;
  script = builtins.unsafeDiscardStringContext c.vanixiets.deployRecord.script;
  entry = builtins.unsafeDiscardStringContext (
    if isDarwin then
      c.system.activationScripts.postActivation.text
    else
      c.system.activationScripts.deploy-record.text
  );
  assembled = builtins.unsafeDiscardStringContext (
    if isDarwin then c.system.activationScripts.script.text else c.system.activationScripts.script
  );
  relink = ''ln -sfn "$(readlink -f "$systemConfig")" /run/current-system'';
  parts = lib.splitString relink assembled;
in
{
  inherit host;
  hostName = c.networking.hostName;
  inherit script;
  renderedForHost = lib.hasSuffix "/bin/deploy-record-${c.networking.hostName}" script;
  inEntry = lib.hasInfix script entry;
  inAssembled = lib.hasInfix script assembled;
  beforeRelink = builtins.length parts == 2 && lib.hasInfix script (builtins.head parts);
}
```

The relink line is the text of `activation-script.nix:79` and `activation-scripts.nix:146`, which each assembled script contains once.
Run:

```bash
{
  for h in cinnabar electrum galena magnetite pyrite scheelite argentum blackphos rosegold stibnite; do
    nix eval --impure --json --expr "import ./logs/s2-evidence/1.4-activation.nix { repo = \"$PWD\"; host = \"$h\"; }"; echo
  done
} 2>&1 | tee logs/s2-evidence/1.4-activation-$(date -u +%Y%m%dT%H%M%SZ).log | grep '^{' | jq -c '{host, hostName, renderedForHost, inEntry, inAssembled, beforeRelink}'
```

Expected: ten objects, each with `hostName` equal to `host`, and `renderedForHost`, `inEntry`, `inAssembled` and `beforeRelink` all `true`; the log keeps each machine's script path.
magnetite's and stibnite's rows are tasks.md 1.3's evaluation verify (each activation text contains the evaluated `vanixiets.deployRecord.script`); the ten rows are 1.4's; `beforeRelink` shows at evaluation the order world assumption A49 states, which Task 7's 7.1 observes at runtime.
Each command evaluates one whole machine, one at a time, to bound memory.

- [ ] **Step 12: Show the obligation able to fail with `extendModules` overrides (negative control, tasks.md 1.5)**

The two values the obligation compares are named in Step 8; these overrides change the activation text only, leaving the rendered script as it is.
Create `logs/s2-evidence/1.5-obligation-control.nix` (git-ignored) with exactly:

```nix
# tasks.md 1.5: the deploy-record obligation over the unmodified hosts and over
# extendModules overrides that drop or replace the activation entry.
{ repo, platform }:
let
  f = builtins.getFlake repo;
  lib = f.inputs.nixpkgs.lib;
  failures = f.lib.deployRecordObligations.failures;
  extended = host: module: (host.extendModules { modules = [ module ]; }).config;
  magnetite = f.nixosConfigurations.magnetite;
  stibnite = f.darwinConfigurations.stibnite;
  pyriteScript = f.lib.deployRecordScript {
    pkgs = f.inputs.nixpkgs.legacyPackages.x86_64-linux;
    hostName = "pyrite";
  };
  results = {
    nixos = {
      control = failures "magnetite" magnetite.config;
      entryEmptied = failures "magnetite" (
        extended magnetite { system.activationScripts.deploy-record.text = lib.mkForce ""; }
      );
      otherHostScript = failures "magnetite" (
        extended magnetite {
          system.activationScripts.deploy-record.text = lib.mkForce "${pyriteScript} \"$systemConfig\"";
        }
      );
    };
    darwin = {
      control = failures "stibnite" stibnite.config;
      postActivationEmptied = failures "stibnite" (
        extended stibnite { system.activationScripts.postActivation.text = lib.mkForce ""; }
      );
    };
  };
in
results.${platform}
```

Run:

```bash
{
  echo "=== nixos (magnetite)"
  nix eval --impure --json --expr "import ./logs/s2-evidence/1.5-obligation-control.nix { repo = \"$PWD\"; platform = \"nixos\"; }" | jq .
  echo "=== darwin (stibnite)"
  nix eval --impure --json --expr "import ./logs/s2-evidence/1.5-obligation-control.nix { repo = \"$PWD\"; platform = \"darwin\"; }" | jq .
} 2>&1 | tee logs/s2-evidence/1.5-obligation-control-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: under `nixos`, `control` is `[]`, `entryEmptied` is `["magnetite's system.activationScripts.script does not run /nix/store/…-deploy-record-magnetite/bin/deploy-record-magnetite"]` and `otherHostScript` holds the same message, so a snippet rendered for another host does not satisfy it; under `darwin`, `control` is `[]` and `postActivationEmptied` is `["stibnite's system.activationScripts.script.text does not run /nix/store/…-deploy-record-stibnite/bin/deploy-record-stibnite"]` (tasks.md 1.5's negative control, evaluation).

Steps 6, 9, 11 and 12 were rehearsed during planning (2026-10-21) by adding Step 6's modules to magnetite and stibnite with `extendModules` from a scratch copy under `/tmp`: without the module the obligation returned the `does not import deploy-record` message for each host; with it, `renderedForHost`, `inEntry`, `inAssembled` and `beforeRelink` were `true` and the obligation `[]`; `entryEmptied`, `otherHostScript` and `postActivationEmptied` returned exactly the messages above, naming `/nix/store/kqrb193gvigg0f5ii9sbwp3jwq7l0ll7-deploy-record-magnetite/bin/deploy-record-magnetite` and `/nix/store/qmf3h7knqgajsxi0qy9r0asjy7185c16-deploy-record-stibnite/bin/deploy-record-stibnite`.
The same rehearsal first failed with `the string '.*/nix/store/…-deploy-record-magnetite/bin/deploy-record-magnetite.*' is not allowed to refer to a store path`, because `lib.hasInfix` builds a regular expression from its needle, which is why Step 6's obligation and Step 11's file discard the script's string context before the search.

- [ ] **Step 13: Build the machine checks and record the obligation's added cost (build, evaluation; tasks.md 1.4, 1.5)**

Run:

```bash
{
  nix build --no-link -L .#checks.x86_64-linux.nixos-cinnabar .#checks.x86_64-linux.nixos-electrum .#checks.x86_64-linux.nixos-galena .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.nixos-pyrite && echo nixos-checks-built
  for h in argentum blackphos rosegold stibnite; do
    nix eval --raw .#.checks.aarch64-darwin.darwin-$h.drvPath; echo
  done
} 2>&1 | tee logs/s2-evidence/1.5-machine-checks-$(date -u +%Y%m%dT%H%M%SZ).log | grep -E 'nixos-checks-built|darwin-system|error'
```

Expected: `nixos-checks-built`, then four `/nix/store/…-darwin-system-….drv` paths, and no `error` line; the `x86_64-linux` toplevels are built by the remote builders stibnite routes them to.
Then record the obligation's cost on magnetite's check:

```bash
NIX_SHOW_STATS=1 NIX_SHOW_STATS_PATH=/tmp/nixos-magnetite-after-stats.json \
  nix eval --option eval-cache false --raw .#.checks.x86_64-linux.nixos-magnetite.drvPath; echo
jq -n --slurpfile b /tmp/nixos-magnetite-before-stats.json --slurpfile a /tmp/nixos-magnetite-after-stats.json \
  '{method: "NIX_SHOW_STATS=1 nix eval --option eval-cache false --raw .#.checks.x86_64-linux.nixos-magnetite.drvPath", before: $b[0].gc.totalBytes, after: $a[0].gc.totalBytes, delta: ($a[0].gc.totalBytes - $b[0].gc.totalBytes), cpuBefore: $b[0].cpuTime, cpuAfter: $a[0].cpuTime}' \
  2>&1 | tee logs/s2-evidence/1.5-nixos-magnetite-cost-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: `delta` is the obligation's cost plus the new module and its script derivation, a few MB at most `[INFERENCE: a string search over one already-forced attribute and one writeShellApplication; this measurement confirms it]`, recorded with the method; if `delta` exceeds 50 MB, stop and report the figure, because design D12 rests on the obligation costing nothing beyond the string search.

- [ ] **Step 14: Format (tasks.md 1.6, first half)**

Run:

```bash
{
  nix fmt -- modules/system/deploy-record.nix modules/checks/machines.nix \
    modules/machines/nixos/cinnabar/default.nix modules/machines/nixos/electrum/default.nix modules/machines/nixos/galena/default.nix \
    modules/machines/nixos/magnetite/default.nix modules/machines/nixos/pyrite/default.nix modules/machines/nixos/scheelite/default.nix \
    modules/machines/darwin/argentum/default.nix modules/machines/darwin/blackphos/default.nix modules/machines/darwin/rosegold/default.nix \
    modules/machines/darwin/stibnite/default.nix
  nix fmt -- --fail-on-change && echo fmt-clean
} 2>&1 | tee logs/s2-evidence/1.6-fmt-$(date -u +%Y%m%dT%H%M%SZ).log
```

Expected: the last line is `fmt-clean`.
If the first command reformatted any file, rerun Steps 7 and 11 and expect the same lines.

- [ ] **Step 15: Tick 1.1–1.5 and move CAM-69 to In Progress**

In `openspec/changes/stand-up-devloop-collection/tasks.md`, change the leading `- [ ]` of the lines beginning `- [ ] 1.1` to `- [ ] 1.5` (lines 13–17) to `- [x]` with the edit tool, and nothing else; 1.6 is ticked by the orchestrator when nixbot reports the pull request green, and 1.7 when Task 7's 7.1 has passed after D1.
Run: `jj diff --git -- openspec/changes/stand-up-devloop-collection/tasks.md | grep -c '^+- \[x\]'`
Expected: `5`.

This is the change's first `- [x]`, which by `skill://openspec-linear-sync` drives Todo → In Progress for CAM-69; every Linear write is best-effort and never blocks the commit.

```bash
linear auth whoami --workspace cameronraysmith
linear issue view CAM-69 --json --no-comments --workspace cameronraysmith | jq -r .state.name
```

Expected: `Workspace: cameronraysmith`, then `Todo`.
Only if the printed state is `Backlog` or `Todo`:

```bash
linear issue update CAM-69 --state "In Progress" --workspace cameronraysmith
printf 'Implementation has begun: the plan review and the nixbot schema baseline are recorded, and all ten machines now carry the deploy-record activation snippet, held by a machine-check obligation on the five x86_64-linux NixOS machine checks that CI builds (cinnabar, electrum, galena, magnetite, pyrite); the darwin machines and scheelite were shown by evaluation once (tasks 1.1-1.5).\n' > /tmp/cam69-in-progress.md
linear issue comment add CAM-69 --body-file /tmp/cam69-in-progress.md --workspace cameronraysmith
linear issue view CAM-69 --json --no-comments --workspace cameronraysmith | jq -r .state.name
date -u +%Y-%m-%dT%H:%M:%SZ
```

Expected: `In Progress`, then the timestamp `<now>`.
In `openspec/changes/stand-up-devloop-collection/proposal.md`'s front matter: if the transition posted, set `linear_story_state: In Progress` (`:6`), `last_synced_state: In Progress` (`:9`) and `last_synced_at: <now>` (`:10`), and append `  - { at: "<now>", transition: "Todo->In Progress", outcome: "posted", note: "first - [x] in tasks.md (1.1-1.5)" }` after `:14` in `attempt_log`; if a write failed, leave both states at `Todo` and append the same entry with `outcome: "dropped"` and the one-line error as `note`; if Linear was already at or past `In Progress`, set both states to the state read and `last_synced_at: <now>`, and append nothing.

- [ ] **Step 16: Commit**

Run:

```bash
jj new --no-edit -r main@origin -m 'feat(deploy-record): record every activation on the ten machines, held by the x86_64-linux NixOS machine checks'
change="$(jj log --no-graph -r 'children(main@origin) & empty() & description(substring:"feat(deploy-record): record every activation on the ten machines")' -T 'change_id.shortest(8)')"
jj squash --from @ --into "$change" --keep-emptied --use-destination-message -- \
  modules/system/deploy-record.nix \
  modules/checks/machines.nix \
  modules/machines/nixos/cinnabar/default.nix \
  modules/machines/nixos/electrum/default.nix \
  modules/machines/nixos/galena/default.nix \
  modules/machines/nixos/magnetite/default.nix \
  modules/machines/nixos/pyrite/default.nix \
  modules/machines/nixos/scheelite/default.nix \
  modules/machines/darwin/argentum/default.nix \
  modules/machines/darwin/blackphos/default.nix \
  modules/machines/darwin/rosegold/default.nix \
  modules/machines/darwin/stibnite/default.nix \
  openspec/changes/stand-up-devloop-collection/tasks.md \
  openspec/changes/stand-up-devloop-collection/proposal.md
jj diff --no-pager --summary -r "$change"
```

Expected: `A modules/system/deploy-record.nix`, `M modules/checks/machines.nix`, the ten `M modules/machines/…/default.nix`, `M openspec/changes/stand-up-devloop-collection/tasks.md` and, if Step 15 wrote the ledger, `M openspec/changes/stand-up-devloop-collection/proposal.md`, and nothing else.
If `tasks.md` or `proposal.md` carried hunks other than this task's before the squash, squash that file with `--interactive` and select only this task's hunks.
The orchestrator rebases the development join onto this change, pushes it, opens pull request 1 with the evidence logs of Steps 7, 11, 12 and 13 named in its description, and enqueues it.

- [ ] **Step 17: Pull request merged (tasks.md 1.6)**

The orchestrator's pull request shows nixbot green, including every `checks.x86_64-linux.nixos-<host>` (cinnabar, electrum, galena, magnetite, pyrite), the five checks that hold the obligation in CI, and merges through the queue; the orchestrator then ticks 1.6.
Verify: `jj git fetch && jj log --no-graph -r 'main@origin & description(substring:"feat(deploy-record): record every activation on the ten machines")' -T 'commit_id.shortest(12)'` prints one commit.

- [ ] **Step 18: Gate before deploy D1**

D1 waits for the merge of Step 17 and for Task 7 Step 0 (`logs/s2-evidence/s2-deploy.sh`) and Task 7 Step 2 (the pre-D1 baseline), which must run before D1 because 7.1 compares the record's `previous_closure` with the system D1 replaces.
Run:

```bash
bash -n logs/s2-evidence/s2-deploy.sh && echo deploy-script-ok
grep -E '^PRE_D1_(SYSTEM|LINES)=' logs/s2-evidence/window.env
ssh magnetite.zt 'readlink -f /run/current-system; test -e /var/log/deploy-record.jsonl && wc -l < /var/log/deploy-record.jsonl || echo 0'
```

Expected: `deploy-script-ok`; `PRE_D1_SYSTEM=/nix/store/…-nixos-system-magnetite-…` and `PRE_D1_LINES=0`; magnetite prints the same `PRE_D1_SYSTEM` path and `0`.
If magnetite's current system differs from `PRE_D1_SYSTEM`, a deploy happened after the baseline: rerun Task 7 Step 2 before D1.

- [ ] **Step 19: Deploy D1 (tasks.md 1.7)**

Run: `$REPO/logs/s2-evidence/s2-deploy.sh magnetite D1`
Expected: the last line is `clan exit=0; log $REPO/logs/s2-evidence/magnetite-<ts>.log`, and `window.env` gains `D1_COMMIT`, `D1_START` and `D1_END`.
Only magnetite is deployed; the other nine machines receive the snippet at their next routine update, and acceptance needs none of them.
D1 also brings magnetite to the rest of `origin/main`, including the nixbot input at `d020013fa` (design Context), whose migrations equal those magnetite has applied, so nixbot restarts with no new migration.
Verify: Task 7's 7.1 passes (magnetite's `/var/log/deploy-record.jsonl` exists with mode `0644`, exactly one line was added by D1, naming `magnetite`, a `closure` equal to `readlink -f /run/current-system` and a `previous_closure` equal to `PRE_D1_SYSTEM`, with `ts` inside the D1 window); Task 2's deploy D2 waits for 7.1.
If activation fails, the deploy log names the snippet (`Activation script snippet 'deploy-record' failed`, `activation-script.nix:22`), and NixOS still relinks the current system after a failed snippet (`:79`); roll back by redeploying magnetite from the previous `main@origin` commit through the same procedure, which removes the snippet and leaves the file in place.

#### Questions and contract notes for Task 1

1. `flake.lib.deployRecordObligations` is defined in `modules/system/deploy-record.nix`, beside the option it reads, rather than in a new `modules/lib/` file as `omnigentFleetObligations` is; design's Layout lists no lib file for it.
2. nix-darwin runs activation under `set -e` (`activation-scripts.nix:88`), so a failing deploy-record script would abort a darwin activation before the relink; the script fails only if `/var/log` is unwritable or the closure argument is missing.

---

