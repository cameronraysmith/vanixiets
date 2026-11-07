### Task 9: Close-out and integration verification

Implements `tasks.md` 9.1–9.6 and 10.1 (schema `verify` and `retrospective`; operations `archive` guidance).
It starts after Task 7 Step 4 and pull request 4.

**Files:**
- Create: `openspec/changes/verify-ntfy-before-sending-tokens/verify.md`, `review.md`, `retrospective.md`.
- Modify: `packages/docs/src/content/docs/development/traceability/satisfaction.md` (regenerated), the corpus under `openspec/specs/` (by archive).

- [ ] **Step 1: Integration (10.1)**

On each of magnetite, cinnabar and pyrite over `ssh <host>.zt "bash -s"`, and locally on stibnite:

```bash
paths=$(nix-store -qR /run/current-system | grep -E -- '-(ntfy-send|notify-permission-(prompt|wait))$')
echo "$paths"
for p in $paths; do rg -l -- '-sfk|--insecure' "$p" || true; done | sed 's/^/INSECURE /'
for p in $paths; do rg -l -- '--cacert' "$p" || true; done | sed 's/^/VERIFIES /'
```

Then `read-posts.sh` over the last 24 h, the dead-man's runs and the operator's statement on the watch service's email, `sudo journalctl -u caddy-root-check --no-pager` on cinnabar showing at least one timer run with exit 0, and caddy's journal since Task 3 showing no PKI error.
Expected: no `INSECURE` line on any host; a `VERIFIES` line naming each host's `ntfy-send`; every post explained; no email; one timer run passed; all in `verify.md` §Integration.

- [ ] **Step 2: verify.md (9.1, 9.2)**

Run the schema's `openspec-verify-change` procedure and write `verify.md`: per requirement of `specs/`, its discharge and evidence file; per check, its cost before (Task 1 Step 3) and after (Tasks 2, 4 and 5), with the method; the designation lint of `fleet-alerting`'s three added requirements' nouns against the `world-assumptions` table, recording any noun not in it; each of A78 to A83 as `configured`, `not violated` or `observed`, with the window it was observed over; Task 7 Step 5's table, the import record of Task 2 Step 4 and the served-chain reads of Task 3; and the migration-flag list, which records that no one-shot branch was added and that `NTFY_CURL_BIN` stays as the tests' seam.
Run `openspec validate verify-ntfy-before-sending-tokens --strict`.
Expected: `is valid`; every requirement has a row.

- [ ] **Step 3: Review and retrospective (9.3)**

Dispatch one read-only Opus subagent of the default `task` type to review the change as merged and deployed, writing `review.md` with a severity summary and a findings table; findings the operator accepts become a group §11 in `tasks.md` and are applied; then write `retrospective.md`, its §6 listing promotion candidates.

- [ ] **Step 4: Row check, satisfaction projection and archive (9.4–9.6)**

```bash
awk '/^## ADDED/{exit} {print}' openspec/changes/verify-ntfy-before-sending-tokens/specs/world-assumptions/spec.md | grep '^|' | LC_ALL=C sort > /tmp/rows-change
awk '/^### Requirement: Grounded vocabulary/,/^### Requirement: A1 /' openspec/specs/world-assumptions/spec.md | grep '^|' | LC_ALL=C sort > /tmp/rows-corpus
LC_ALL=C comm -3 /tmp/rows-corpus /tmp/rows-change
```

Expected: only the rows `service authority` and `verified connection`, in the second column; anything else stops the archive for the operator, because another change has modified the table since Task 1 Step 2.
Regenerate `satisfaction.md` wholesale from the post-sync corpus, archive with `openspec archive verify-ntfy-before-sending-tokens -y`, mirror the changed main specs to the `fleet-observability` Linear documents and move CAM-87 to Done per `openspec-linear-sync` (the orchestrator posts these), run `nix fmt`, and commit.
Expected: `openspec list` no longer shows the change; `satisfaction.md`'s `generated:` date is the archive date and its requirement count equals the sum of `requirementCount` in `openspec list --specs --json`.
