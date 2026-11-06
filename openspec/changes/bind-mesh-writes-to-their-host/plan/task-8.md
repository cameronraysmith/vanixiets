### Task 8: Close-out and integration verification

Implements `tasks.md` 8.1–8.6 and 9.1 (schema `verify`, `retrospective` and apply step 5; FII, TSI and DCI `This capability states its own trust boundary`; WA `Grounded vocabulary for behavioral requirements`).

**Files:**
- Create: `verify.md`, `review.md`, `retrospective.md` in the change folder
- Regenerate: `packages/docs/src/content/docs/development/traceability/satisfaction.md`
- Modify at archive: `openspec/specs/fleet-ingress-interface/spec.md`'s Purpose paragraph

- [ ] **Step 1: verify.md (tasks.md 8.1, 9.1)**

Write `verify.md` with the schema's template: per requirement of `specs/`, its discharge and evidence file; per check, its cost before (Task 1 Step 2) and after with the method; the designation lint of the two behavioral requirements' nouns against the vocabulary delta; each of A71 to A76 as `configured`, `not violated` or `observed`, with its window (A71 and A72 `observed` at Task 6 Step 2, A73 at the container case and Task 6 Step 1, A75 and A76 at the container cases and Task 6 Steps 3 and 4); and §Integration with tasks.md 9.1's queries and results.
Expected: `openspec validate bind-mesh-writes-to-their-host --strict` passes (command).

- [ ] **Step 2: Migration-flag close-out (tasks.md 8.2)**

List every conditional this change added that keys on a one-time state; none is expected; record the list and each disposition in `verify.md`.

- [ ] **Step 3: Review and retrospective (tasks.md 8.3)**

One read-only Opus subagent of the default `task` type reviews the change as merged and deployed into `review.md`; applied findings become a group 10 in `tasks.md`; then `retrospective.md`, including whether each rule `brainstorm.md` adopted from #3690 was applied and what it caught.

- [ ] **Step 4: Row check, projection and Purpose (tasks.md 8.4, 8.5)**

```bash
rows() { grep -E '^\| [^-]' "$1" | grep -v '^| Term' | sort; }
LC_ALL=C comm -23 <(rows openspec/specs/world-assumptions/spec.md) <(rows openspec/changes/bind-mesh-writes-to-their-host/specs/world-assumptions/spec.md)
```

Expected: only the old `overlay network` row; anything else stops the archive.
After `openspec archive -y`, rewrite the `fleet-ingress-interface` Purpose paragraph's trust-boundary sentence to match its trust-boundary requirement, and regenerate `satisfaction.md` wholesale from the synced corpus, in the same commit.
Expected: `rg -n 'not bound to the' openspec/specs/fleet-ingress-interface/spec.md` prints nothing; the projection's requirement count equals the sum of `requirementCount` in `openspec list --specs --json`.

- [ ] **Step 5: Archive (tasks.md 8.6)**

`nix fmt`; commit; open the close-out pull request; the orchestrator mirrors the changed main specs to Linear and moves CAM-81.
Expected: `openspec list` no longer shows the change (command).
