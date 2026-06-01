# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `<change-name>`
**Verified at**: `YYYY-MM-DD HH:mm`
**Verifier**: `<who / which agent>`

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
<paste a summary of the openspec validate --all output>
```

If any items fail, list their id and issues:

| Item | Type | Issues |
|---|---|---|
| — | — | — |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

**Incomplete tasks** (if any):

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| — | — | — |

---

## 3. Delta Spec Sync State

For each capability directory under `openspec/changes/<name>/specs/`, compare against
`openspec/specs/<capability>/spec.md`:

| Capability | Sync status | Notes |
|---|---|---|
| — | synced / pending sync / N/A | — |

---

## 4. Design / Specs Coherence Spot Check

Spot-check whether the decisions in `design.md` are reflected in the Requirements and
Scenarios of `specs/*.md`:

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| — | — | — | — |

**Drift warnings** (non-blocking):

- <if any, list them; if none, write "none">

---

## 5. Implementation Signal

- [ ] No unstaged files in the worktree
- [ ] All related commits have been pushed

**Commit range** (if known): `<from-sha>..<to-sha>`

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

Design output should not land in `docs/superpowers/specs/` (the brainstorm artifact's
output redirection routes it to `openspec/changes/<name>/brainstorm.md`).

Detect:

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [ ] No files, or any existing files are legitimate residue from before schema installation

**Leak list** (if any):

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

> Does not block archive. Leaks produced by a new schema-installed cycle should be moved into
> `openspec/changes/<name>/brainstorm.md` or `design.md`, then the original file deleted.

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

For each manual dogfood / smoke task in plan.md marked `[~]` deferred, list the
equivalent automated test coverage item by item. If there is no equivalent automated test, that item should be treated as a **real gap**
rather than a legitimate deferral, and recorded in the retrospective Misses.

| Deferred dogfood (plan §) | Equivalent automated test | Coverage assessment | Real gap? |
|---|---|---|---|
| e.g. §11.3 `compose up + curl /actuator/health` | `LinebcIntegrationApplicationTests` (Testcontainers, 24s) | Spring context boot + Flyway run complete + main beans injected | no (equivalently covered) |
| — | — | — | — |

> **Interpretation rules**:
> - "Equivalent" = the automated test's assertion set is a superset of the manual dogfood's expected assertions
> - "Coverage assessment" = list the layers actually exercised (context / DB schema / wiring / HTTP path / etc.)
> - For any row where Real gap = yes, the Overall Decision can still PASS, but a follow-up item must be left in the retrospective

> **When this whole section may be left blank**: when plan.md has no rows marked `[~]` at all, this section does not need to be filled in (blank means PASS).
> As soon as any `[~]` appears in plan.md, this section must be filled in item by item, otherwise the Overall Decision should be downgraded to FAIL.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `<explanation>`
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

<describe the next action>
