### Task 9: Close-out and integration verification

Implements `tasks.md` 9.1–9.6 and 10.1 (`openspec/config.yaml` verify and archive guidance; FII `This capability states its own trust boundary`; FAI `This capability states its own trust boundary`; DCI `This capability states its own trust boundary`; WA `Grounded vocabulary for behavioral requirements`).
It runs after Tasks 1 to 8; its files land in one close-out pull request, titled in plain words, for example "Record the verification of host-metrics collection on stibnite and archive its change".
Step 6 (`tasks.md` 10.1) runs on the day of the close-out, before Step 5's archive, so `verify.md` §Integration is in the archived folder.

**Files:**
- Create: `openspec/changes/stand-up-darwin-collection/verify.md`, `review.md`, `retrospective.md`
- Modify: `openspec/changes/stand-up-darwin-collection/tasks.md` (ticks; a §11 group for applied review findings), `proposal.md` front matter (Linear ledger)
- Modify: `modules/lib/observability-hosts.nix`, `modules/clan/services/otel-collector/README.md` and any file Step 2's list names (stale one-shot branches and comments)
- Modify: `packages/docs/src/content/docs/development/traceability/satisfaction.md` (regenerated wholesale)
- Move: the change directory to `openspec/changes/archive/<YYYY-MM-DD>-stand-up-darwin-collection/`, and the synced main specs under `openspec/specs/`
- Create (git-ignored): `logs/s5-evidence/9.<n>-*.log`, `logs/s5-evidence/10.1-integration-<ts>.log`

**Interfaces:**
- Consumes: every `logs/s5-evidence/` record of Tasks 1 to 8; S4's archived `verify.md`, `review.md` and `retrospective.md` as forms; `gsql.sh`, `promq.sh`, `6.1-replay.sh`, `posts.sh`, `window.env`.
- Produces: the archived change and the synced specs.

- [ ] **Step 1: `verify.md` (tasks.md 9.1)**

Write, in S4's form: §1 the commit range and the four pull requests with their numbers; §2 per check its cost before and after with the method (`otel-collector-darwin`, `otel-envelope`, `fleet-alert`, `otel-collector-config`, `darwin-stibnite`, `nixos-magnetite`); §3 the plan-review dispositions; §4 the vars-step record with the hashes of `tasks.md` 2.3; §8a the designation lint of `host-metrics-collection`'s, `fleet-alerting`'s and `devloop-collection`'s behavioral nouns against the `world-assumptions` table of this change's delta, each noun with the row it resolves to (`darwin host`, `launchd job`, `kept-alive job`, `probe`, `sleep`, `dark wake` and `collected host` among them); §8b one row per requirement quoted after `Discharges:` in `tasks.md`, with its evidence file, the three trust-boundary requirements stated as their scenarios give them and discharged by statement; §8c each world assumption A61 to A66 with its status and window; §9 the deploy, activation and acceptance records of Tasks 4, 5, 6 and 8, pasted from their logs after checking them for credentials (`rg -n 'tk_|password|BEGIN .*PRIVATE' <log>` prints nothing), each with its `## Causes`.
Each status in §8c and each requirement row in §8b uses one of three words, as the schema's `verify` rule defines them: `configured`, when only the delivered configuration or an evaluation shows it (for example `No darwin collection job runs on a calendar schedule`, shown by the fragment's assertion and the delivered plists); `not violated`, when a watch over a stated window saw no counter-example (for example A61's coalescing of `StartCalendarInterval`, which no S5 job uses, over the window from Task 5 Step 2 to the close-out); and `observed`, when a step made it happen and saw it, with the window it was observed over (for example A62's missing exit code, observed in Task 8 Step 4 at `KILL_EPOCH`, or A64's dark wakes counted in Task 8 Steps 6 and 7).
Run the adapted discharge-name check, both ways:

```bash
cd openspec/changes/stand-up-darwin-collection
reqs() { for d in devloop-collection:DC devloop-collection-interface:DCI fleet-alerting:FA fleet-alerting-interface:FAI fleet-ingress-interface:FII host-metrics-collection:HMC telemetry-store-interface:TSI world-assumptions:WA; do
  [ -f "specs/${d%%:*}/spec.md" ] && awk -v p="${d#*:}" '/^### Requirement: /{ sub(/^### Requirement: /, ""); print p " `" $0 "`" }' "specs/${d%%:*}/spec.md"; done | LC_ALL=C sort -u; }
discharged() { grep -o 'Discharges: .* — verify:' tasks.md | sed -E 's/^Discharges: //; s/ — verify:$//' \
  | grep -oE '(DCI|DC|FAI|FA|FII|HMC|TSI|WA) `[^`]+`' | LC_ALL=C sort -u; }
echo "undischarged:"; LC_ALL=C comm -23 <(reqs) <(discharged)
echo "unknown:"; LC_ALL=C comm -13 <(reqs) <(discharged)
echo "absent from verify.md:"; LC_ALL=C comm -23 <(discharged | sed -E 's/^[A-Z]+ //' | LC_ALL=C sort -u) <(grep -oE '`[^`]+`' verify.md | LC_ALL=C sort -u)
openspec validate stand-up-darwin-collection --strict
```

Expected: the three lists empty (every requirement of this change's deltas discharged by name and prefix, the prefix mattering because FII, FAI and DCI each have `This capability states its own trust boundary`); `validate` passes.
The `sed` keeps `Discharges:` to ` — verify:` whole, because world-assumption names contain ` — `.
CAM-72 moves In Progress → In Review per `openspec-linear-sync`, posted by the orchestrator.

- [ ] **Step 2: Migration-flag close-out (tasks.md 9.2)**

List every one-shot branch this change added, read from the merged code:

```bash
L=logs/s5-evidence/9.2-flags-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
rg -n '\bcollect\b' modules/lib/observability-hosts.nix modules/clan/services/otel-collector/flake-module.nix modules/darwin/otel-collector-agent.nix modules/lib/otel-collector-darwin.nix modules/nixos/fleet-alert/rules.nix modules/checks/otel-collector-darwin.nix modules/checks/fleet-alert.nix modules/clan/services/otel-collector/README.md | tee "$L"
rg -n 'collect = false' modules/lib/observability-hosts.nix | tee -a "$L"; echo "rg-rc=$?" | tee -a "$L"
```

Expected: stibnite's `collect = false` gone (`rg-rc=1`), removed by pull request 2; every other line is either the role's permanent import gate in `flake-module.nix`, the rules' `collecting` filter, a fixture that renders a table with `collect` forced (`stibniteNotCollecting`), or a one-shot branch or stale comment (for example a comment in `modules/lib/observability-hosts.nix` or the README that says stibnite is added with `collect = false` pending its watched activation).
Each line is written to `verify.md` §10 with its disposition (permanent, with its reason, or removed in this pull request); the removed ones are deleted here, and `nix eval --raw .#darwinConfigurations.stibnite.config.system.build.toplevel.drvPath` and `nix build .#checks.x86_64-linux.fleet-alert .#checks.x86_64-linux.otel-collector-darwin` still pass after the removal (evaluation, build).

- [ ] **Step 3: Review and retrospective (tasks.md 9.3)**

One read-only subagent of the default `task` type on an Opus model reviews the change as merged and deployed, as `tasks.md` 1.1's did before it, answering the same four questions over the merged code, the deltas and `verify.md`; its report is written to `review.md` with a severity summary and a findings table, and its dispositions table is complete before any finding is applied.
Each applied finding becomes a `tasks.md` §11 item and a step under §11 below.
Then write `retrospective.md` in S4's format; its §4 records whether each S4 §6 rule aimed at this change was applied and what it caught (the plan-review gate, the rehearsal with the consumers' exact argument lists, the replay before the rules, the magnetite deploy after each row change, the per-step post read with causes, the eval-cost stops, the two-source rule with its mutants, the deploy-record line counts, the migration-flag close-out, the observed-status wording); its §6 lists the rules to promote.

- [ ] **Step 4: The designation rows (tasks.md 9.4)**

```bash
row() { awk '/^\| /' "$1" | grep -vE '^\| *(Term|---)' | LC_ALL=C sort -u; }
LC_ALL=C comm -23 <(row openspec/specs/world-assumptions/spec.md) <(row openspec/changes/stand-up-darwin-collection/specs/world-assumptions/spec.md) | tee logs/s5-evidence/9.4-rows-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
```

Expected: only main's `collected host` row, which the delta rewrites to include stibnite; any other row printed is a main row this delta would drop, and the archive stops for the operator (design "Spec deltas beyond the proposal's list").
The output is pasted into `verify.md` §8a.

- [ ] **Step 5: The satisfaction projection and the archive (tasks.md 9.5, 9.6)**

After syncing the specs and before moving the change folder, regenerate `packages/docs/src/content/docs/development/traceability/satisfaction.md` wholesale from the post-sync corpus in S4's form, adding this change's rows and its qualifications, with each undischarged requirement recorded with its follow-up reference; never patch it.
Expected: its `generated:` date is the archive date, and its requirement count equals `openspec list --specs --json | jq '[.[].requirementCount // 0] | add'`.
Then archive the change with the OpenSpec archive workflow, mirror the changed main specs to the `fleet-observability` Linear documents, move CAM-72 to Done per `openspec-linear-sync` (the orchestrator posts both), run `nix fmt` and `nix fmt -- --fail-on-change`, and commit with a plain message.
Expected: `openspec list` no longer shows the change.

- [ ] **Step 6: Integration verification (tasks.md 10.1)**

On the day of the close-out, before Step 5's archive, read-only on stibnite and magnetite:

```bash
L=logs/s5-evidence/10.1-integration-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
t=$(( $(/bin/date -u +%s) - 86400 ))
for m in system_memory_usage_bytes process_memory_usage_bytes system_filesystem_usage_bytes launchd_job_state node_textfile_mtime_seconds smartctl_device_critical_warning_total; do
  printf '%s ' "$m"; logs/s5-evidence/promq.sh "count by (host_name) (count_over_time(${m}{host_name=\"stibnite\"}[24h]))" | tr '\n' ' '; echo
done | tee "$L"
for d in $(awk '/^system_disk_/' logs/s5-evidence/5.3-tables.tsv); do printf '%s ' "$d"; logs/s5-evidence/promq.sh "count by (host_name) (count_over_time(${d}{host_name=\"stibnite\"}[24h]))"; done | tee -a "$L"
logs/s5-evidence/6.1-replay.sh 'count by (host_name) (system_memory_usage_bytes{host_name="stibnite"})' "$t" | tee -a "$L"
/usr/bin/pmset -g log | grep -E '[[:space:]](Sleep|Wake)[[:space:]]' | tail -n 400 | tee -a "$L" >/dev/null
lines=$(/usr/bin/wc -l < /var/log/deploy-record.jsonl | tr -d ' ')
rows=$(logs/s5-evidence/gsql.sh devloop "SELECT count(*) FROM deploy_record WHERE host = 'stibnite'")
echo "stibnite lines=$lines rows=$rows" | tee -a "$L"
for m in system_memory_usage_bytes systemd_unit_state node_zfs_zpool_state system_filesystem_usage_bytes; do
  printf '%s ' "$m"; logs/s5-evidence/promq.sh "count by (host_name) (count_over_time(${m}[24h]))" | tr '\n' ' '; echo
done | tee -a "$L"
logs/s5-evidence/promq.sh 'count_over_time(smartctl_device_critical_warning_total{host_name="pyrite"}[24h])' | tee -a "$L"
logs/s5-evidence/posts.sh "$t" 2>&1 | tee -a "$L"
```

`posts.sh` over `$t` has no recorded `notify.log` count for that epoch and so prints the whole `notify.log`; the lines before `$t` are ignored.
Expected: each stibnite series present for the last 24 h with a non-zero count, every disk table included; every gap between the memory replay's runs longer than 60 s lies inside a `Sleep`–`Wake` pair of `pmset -g log`, so no gap over 60 s outside recorded sleeps (a gap without one is a finding, with its times); `lines` equal `rows`; magnetite, cinnabar and pyrite in every S4 row (pyrite for the hours it was on, its SMART count non-zero), so S4's series still report; and every post of the last 24 h with a cause recorded in a step's `## Causes` or in this log.
All of it is written to `verify.md` §Integration beside the controls of Task 8 Steps 2 to 6, cited by log name and epoch.

### §11 Applied review findings

Filled from Step 3's `review.md` dispositions: one step per applied finding, each naming its `tasks.md` §11 item, the files it changes, its verification and the interpreter of any command block; no finding is applied before the dispositions table is complete.
