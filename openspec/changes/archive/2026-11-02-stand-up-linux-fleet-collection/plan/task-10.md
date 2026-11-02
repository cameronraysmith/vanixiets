### Task 10: Close-out and integration verification

Implements `tasks.md` 10.1–10.5 and 11.1 (`openspec/config.yaml` verify and archive guidance; FII `This capability states its own trust boundary`; DCI `This capability states its own trust boundary`; WA `Grounded vocabulary for behavioral requirements`).
It runs after Tasks 1 to 9; its files land in one close-out pull request, titled in plain words, for example "Record the verification of host-metrics collection on the NixOS fleet and archive its change".

**Files:**
- Create: `openspec/changes/stand-up-linux-fleet-collection/verify.md`, `review.md`, `retrospective.md`
- Modify: `openspec/changes/stand-up-linux-fleet-collection/tasks.md` (ticks; a §12 group for applied review findings), `proposal.md` front matter (Linear ledger)
- Modify: `packages/docs/src/content/docs/development/traceability/satisfaction.md` (regenerated wholesale)
- Move: the change directory to `openspec/changes/archive/<YYYY-MM-DD>-stand-up-linux-fleet-collection/`, and the synced main specs under `openspec/specs/`

**Interfaces:**
- Consumes: every `logs/s4-evidence/` record of Tasks 1 to 9; S2's archived `verify.md`, `review.md` and `retrospective.md` as forms.
- Produces: the archived change and the synced specs.

- [ ] **Step 1: `verify.md` (tasks.md 10.1)**

Write, in S2's form: §1 the commit range and pull requests; §2 per check its cost before and after with the method (otel-collector-config, otel-envelope, fleet-alert, greptimedb-envelope, and the machine checks); §3 the plan-review dispositions; §4 the vars-step record; §8a the designation lint of `host-metrics-collection`'s, `fleet-alerting`'s and `devloop-collection`'s behavioral nouns against the `world-assumptions` table of this change's delta; §8b one row per requirement quoted after `Discharges:` in `tasks.md`, with its evidence file, the two trust-boundary requirements stated as their scenarios give them and discharged by statement; §9 the deploy and acceptance records of Tasks 4, 5, 6, 7 and 9, pasted from their logs after checking them for credentials (`rg -n 'tk_|password|BEGIN .*PRIVATE' <log>` prints nothing).
Run the adapted discharge-name check, both ways:

```bash
cd openspec/changes/stand-up-linux-fleet-collection
reqs() { for d in devloop-collection:DC devloop-collection-interface:DCI fleet-alerting:FA fleet-alerting-interface:FAI fleet-ingress-interface:FII host-metrics-collection:HMC telemetry-store-interface:TSI world-assumptions:WA; do
  awk -v p="${d#*:}" '/^### Requirement: /{ sub(/^### Requirement: /, ""); print p " `" $0 "`" }' "specs/${d%%:*}/spec.md"; done | LC_ALL=C sort -u; }
discharged() { grep -o 'Discharges: .* — verify:' tasks.md | sed -E 's/^Discharges: //; s/ — verify:$//' \
  | grep -oE '(DCI|DC|FAI|FA|FII|HMC|TSI|WA) `[^`]+`' | LC_ALL=C sort -u; }
echo "undischarged:"; LC_ALL=C comm -23 <(reqs) <(discharged)
echo "unknown:"; LC_ALL=C comm -13 <(reqs) <(discharged)
echo "absent from verify.md:"; LC_ALL=C comm -23 <(discharged | sed -E 's/^[A-Z]+ //' | LC_ALL=C sort -u) <(grep -oE '`[^`]+`' verify.md | LC_ALL=C sort -u)
openspec validate stand-up-linux-fleet-collection --strict
```

Expected: the three lists empty (37 requirements, each discharged by name and prefix; the prefix matters because FII and DCI each have `This capability states its own trust boundary`); `validate` passes.
The `sed` keeps `Discharges:` to ` — verify:` whole, because world-assumption names contain ` — `.
CAM-71 moves In Progress → In Review per `openspec-linear-sync`.

- [ ] **Step 2: Review and retrospective (tasks.md 10.2)**

One read-only subagent of the default `task` type on an Opus model reviews the change as merged and deployed, as Task 1 Step 1's did before it, and its report is written to `review.md` with a severity summary and a findings table; each applied finding becomes a `tasks.md` §12 item, and its dispositions table is complete before any of them is applied.
Then write `retrospective.md` in S2's format; its §4 records whether each §6 rule of S1, S2 and S3 aimed at this change was applied and what it caught (the plan review gate, the rehearsal, the replay, the per-host first-deploy captures, the unit run in a container test, the eval-cost stops, the two-source rule, the deploy-record line counts).

- [ ] **Step 3: The designation rows (tasks.md 10.3)**

```bash
row() { awk '/^\| /' "$1" | grep -vE '^\| *(Term|---)' | LC_ALL=C sort -u; }
LC_ALL=C comm -23 <(row openspec/specs/world-assumptions/spec.md) <(row openspec/changes/stand-up-linux-fleet-collection/specs/world-assumptions/spec.md)
```

Expected: nothing; any row printed is a main row this delta would drop, and the archive stops for the operator (design "Spec deltas beyond the proposal's list").

- [ ] **Step 4: The satisfaction projection (tasks.md 10.4)**

After syncing the specs and before moving the change folder, regenerate `packages/docs/src/content/docs/development/traceability/satisfaction.md` wholesale from the post-sync corpus in S2's form, adding this change's rows and its qualifications, with each undischarged requirement recorded with its follow-up reference; never patch it.
Expected: its `generated:` date is the archive date, and its requirement count equals `openspec list --specs --json | jq '[.[].requirementCount] | add'`.

- [ ] **Step 5: Archive (tasks.md 10.5)**

Archive the change with the OpenSpec archive workflow, sync its specs, mirror the changed main specs to the `fleet-observability` Linear documents, move CAM-71 to Done, run `nix fmt`, and commit with a plain message.
Expected: `openspec list` no longer shows the change.

- [ ] **Step 6: Integration verification (tasks.md 11.1)**

On the day of the close-out:

```bash
L=logs/s4-evidence/11.1-integration-$(/bin/date -u +%Y%m%dT%H%M%SZ).log
for m in system_memory_usage_bytes systemd_unit_state node_zfs_zpool_state system_filesystem_usage_bytes; do
  printf '%s ' "$m"; logs/s4-evidence/promq.sh "count by (host_name) (count_over_time(${m}[24h]))" | tr '\n' ' '; echo
done | tee "$L"
logs/s4-evidence/promq.sh 'count_over_time(smartctl_device_critical_warning_total{host_name="pyrite"}[24h])' | tee -a "$L"
for h in magnetite cinnabar pyrite; do printf '%s rows=' "$h"; logs/s4-evidence/gsql.sh devloop "SELECT count(*) FROM deploy_record WHERE host = '$h'"; done | tee -a "$L"
```

with each host's line count read as in Task 4 Step 6 and Task 5 Step 4.
Expected: magnetite, cinnabar and pyrite in every row (pyrite present for the hours it was on), pyrite's SMART count non-zero, every host's rows equal its lines; recorded in `verify.md` beside the controls of `tasks.md` 4.5, 5.6, 7.6, 9.2 and 9.3.
