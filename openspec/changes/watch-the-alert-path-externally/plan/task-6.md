### Task 6: Close-out and integration verification

Implements `tasks.md` 6.1–6.3 and 7.1 (design "Spec deltas"; `openspec/config.yaml` archive guidance; the S3 retrospective's condition on CAM-72).
Starts after Task 4 Step 6 and Task 5's merge.

**Files:**
- Create: this change's `verify.md`
- Modify: this change's `specs/world-assumptions/spec.md` (rebase only), then, at archive, `openspec/specs/fleet-alerting/spec.md`, `openspec/specs/fleet-alerting-interface/spec.md` (including its Purpose paragraph), `openspec/specs/world-assumptions/spec.md`, and `packages/docs/src/content/docs/development/traceability/satisfaction.md` (regenerated)

**Interfaces:**
- Consumes: every evidence log of Tasks 1 to 5.
- Produces: the archived change and the statement the orchestrator records in CAM-76.

- [ ] **Step 1: verify.md (tasks.md 6.1)**

Write `verify.md` from the schema's template: per requirement of `specs/`, its discharge and evidence file; the check's cost before (Task 1 Step 2) and after (Task 2 Step 4) with the method; the designation lint of `fleet-alerting`'s new requirement, every content noun resolved against the `world-assumptions` table; and `This capability states its own trust boundary` stated as its scenarios give it.
Then:

```bash
openspec validate watch-the-alert-path-externally --strict
sed -n 's/.*Discharges: \(.*\) — verify:.*/\1/p' openspec/changes/watch-the-alert-path-externally/tasks.md | grep -oE '`[^`]+`' | sort -u > /tmp/discharged
grep -oE '`[^`]+`' openspec/changes/watch-the-alert-path-externally/verify.md | sort -u > /tmp/verified
LC_ALL=C comm -23 /tmp/discharged /tmp/verified
```

Expected: `Change 'watch-the-alert-path-externally' is valid`, and `comm` prints nothing.

- [ ] **Step 2: Rebase the world-assumptions delta (tasks.md 6.2)**

If `stand-up-linux-fleet-collection` has archived, retake the designation table in this change's `specs/world-assumptions/spec.md` from the current main spec and add this change's three rows (`watch service`, `ping`, `email`) after its last row; A53 to A55 keep their numbers when A50 to A52 are in main.

```bash
main=openspec/specs/world-assumptions/spec.md
delta=openspec/changes/watch-the-alert-path-externally/specs/world-assumptions/spec.md
LC_ALL=C comm -23 <(grep '^| ' "$main" | sed -n '/^| Term /,$p' | sort -u) <(grep '^| ' "$delta" | sort -u)
```

Expected: nothing printed, so syncing the delta deletes no main row.

- [ ] **Step 3: Archive (tasks.md 6.3)**

Follow `skill://openspec-archive-change`: sync the deltas; in `openspec/specs/fleet-alerting-interface/spec.md`'s Purpose, replace "cinnabar is the single delivery path, and nothing reports an ntfy outage until CAM-76" with "cinnabar is the single delivery path for alerts, and healthchecks.io emails the operator when the dead-man's pings stop"; regenerate `satisfaction.md` wholesale before the folder moves; move the folder.

```bash
rg -n 'until CAM-76' openspec/specs packages/docs/src/content/docs/development/traceability/satisfaction.md
```

Expected: nothing printed.

- [ ] **Step 4: Integration verification (tasks.md 7.1)**

Confirm that `logs/cam76-evidence/4.2-ntfy-stop-*.log` and `logs/cam76-evidence/4.3-evaluator-stop-*.log` exist and that `verify.md` cites both, then report to the orchestrator, in one sentence each, the last ping, stop, down-email, start and up-email times of 4.2, so that it records in CAM-76 that an outage of the alert path reached the operator by a channel other than ntfy and CAM-72 may start.

Expected: both logs exist and are cited; the down email of 4.2 arrived within 15 min of the last accepted ping.
