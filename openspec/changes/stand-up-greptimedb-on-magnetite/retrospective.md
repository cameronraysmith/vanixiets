# Retrospective: stand-up-greptimedb-on-magnetite

> Written: 2026-10-17 (after verify passed with warnings, `verify.md` Overall Decision)
> Commit range: `3c726cccf..1ad3517f7`, filtered to the S1 paths (`git log f9451f3e~1..origin/main -- <S1 paths>`)
> Worktree: merged to main

---

## 0. Evidence

- **Commit range**: `3c726cccf..1ad3517f7` (13 commits on the S1 paths, one per pull request: #3462, #3487, #3488, #3489, #3490, #3491, #3492, #3493, #3494, #3497, #3498, #3499, #3500; `gh pr view`).
- **Diff size**: +5466 / -153 lines across 29 files (`git diff --shortstat 3c726cccf origin/main` over the S1 code paths, the change directory, `modules/machines/nixos/magnetite`, `modules/nixos/nixbot.nix`, `modules/README.md`, `modules/apps/updates.nix` and `modules/home/tools`).
- **Tasks done**: 43/43 (`grep -cE '^\s*- \[x\]' tasks.md` → 43; `- [ ]` → 0).
- **Active hours**: not recorded; the wall-clock span is #3462 merged 2026-10-16T17:31Z to #3500 merged 2026-10-17T21:49Z, about 28 hours (`gh pr view`).
- **Subagent dispatches**: not counted; named agents include `S1Task6Verify` (`verify.md:926`), `S1Task7Verify` (`verify.md:9`) and the holistic reviewer (`review.md:3`).
- **New external dependencies**: `greptimedb-bin` 1.2.1, the upstream release tarball, Apache-2.0 (`pkgs/by-name/greptimedb-bin/package.nix:29,72`); `opentelemetry-collector-contrib` 0.155 from the pinned nixpkgs (`verify.md:495`).
- **Bugs encountered post-merge**: 2 shipped defects found by verification: PromQL answering 404 because `prom_store` was disabled (#3490), and 279 points lost to a collector-before-schema race on first deploy (#3492); review findings F1 and F2 were live-path defects caught before they fired (`review.md:9-10`).
- **OpenSpec validate state at archive**: not run yet; at verify, `openspec validate stand-up-greptimedb-on-magnetite --strict` passed (`verify.md:24`).
- **Test coverage signal**: `vmTests.x86_64-linux.greptimedb-pipeline` 7/7, rerun after #3492 and after each review PR (`verify.md:1099`, `verify.md:1286`); `vmTests.x86_64-linux.greptimedb-oom-order` passed on pyrite and its mutant failed (`verify.md:1100`); two evaluation-time checks with mutants (`design.md:278-293`).

Commit chain (chronological):

```
3c726cccf (base)
f9451f3ef #3462 feat(pkgs): add greptimedb-bin 1.2.1 and move ntfy-send to pkgs/by-name
76694545b #3487 feat(greptimedb): run the telemetry store on magnetite with its evaluation-time envelope
57f138866 #3488 feat(otel-collector): collect magnetite metrics into the store, with failure notices
cebb618c8 #3489 feat(greptimedb): hourly runtime envelope for the store
9a0aa6ccb #3490 fix(greptimedb): enable prom_store, which also gates the PromQL query API
22fd7cead #3491 test(greptimedb): add pipeline and OOM-order runtime tests to the on-demand lane
7f5fbad47 #3492 fix(otel-collector): start the collector after the store databases exist
a521e573d #3493 openspec(stand-up-greptimedb-on-magnetite): verify S1 on magnetite
05729bcd6 #3494 openspec(stand-up-greptimedb-on-magnetite): record the operator dashboard check
60c10f370 #3497 fix(observability): notices across restarts with a rate limit, R7.2 on throttling, self-contained ntfy-send
f6fc63674 #3498 fix(observability): one source for databases, declared table retention, correct the S4 seam
eb4add8f2 #3499 refactor(observability): checks judge relations, module assertions hold settings, negative controls in the pipeline test
1ad3517f7 #3500 openspec(stand-up-greptimedb-on-magnetite): record the review follow-ups in verify.md
<archive commit: pending, plan.md Task 7 Steps 18-21>
```

---

## 1. Wins

- [evidence: `verify.md:216`] Every ADDED and MODIFIED requirement has a discharge, so §8b has no undischarged row.
- [evidence: `verify.md:131`] §7 has no deferred dogfood row, so there is no real gap to carry forward.
- [evidence: #3490 body; `logs/s1-evidence/fix-promstore-red-20261017-025705.log`] The pipeline container test caught the `prom_store` defect before any deployment, which is the job D13 gave it (`design.md:317`).
- [evidence: `verify.md:1104-1165`] The closed loop holds on magnetite: process memory and unit state answer through PromQL, both owners are stored only under their aliases, and the scheduled envelope passed.
- [evidence: `verify.md:1211-1229`] A store restart lost no unit series across a fifteen-minute window.
- [evidence: `verify.md:930-1081`, `verify.md:1231-1240`] R7.2 was forced to fail on the host and produced exactly one `FAILED` and one `RESOLVED` notice.
- [evidence: `verify.md:453-454`] The measured `fleet` queue rate, 76538 bytes per minute, is about 30% of the assumed 256000, so the 400 MiB queue holds a day with room.
- [evidence: `verify.md:1100`] The OOM-order test showed the kill order evaluator, store, collector on a real kernel, and its mutant failed.
- [evidence: `tasks.md:66-75`; `verify.md:1264`] Every review finding landed with its check shown red before and green after.
- [evidence: charter v11-v16, `docs/notes/development/observability/charter.md:274-323`] Each amendment to the decision records was logged as a charter version rather than edited silently.
- [evidence: `logs/s1-evidence/`, 155 files] Every verify claim points at a captured log, so this retrospective could be written cold.

## 2. Misses

- [high] [blocking | evidence: #3490; charter v13, `charter.md:292`] ADR-007 required `prom_store.enable = false`, and in GreptimeDB v1.2.1 that switch also unregisters the PromQL query API (`src/frontend/src/server.rs:130-158`), so every PromQL read would have answered 404.
- Planning missed it because the protocol list treated each listener toggle as independent and the source read for v12 (`charter.md:282-290`) did not open the frontend's handler registration.
- The evaluation-time check asserted the configured literal, so it agreed with the wrong decision; only a runtime read could disagree.
- [high] [blocking | evidence: #3492; `logs/s1-evidence/finding-collector-schema-race.log`; `verify.md:1087`] On first deploy the collector exported at 07:20:00.022, before `greptimedb-schema` created `fleet` at 07:20:00.226; the store answered 400, the exporter treats 400 as permanent, and 279 points were dropped.
- Planning missed it because design D7 and task 2.6 ordered the schema job after the store but nothing ordered the collector after the schema job, and no check related the start order of two units.
- The pipeline test passed with the race present (`logs/s1-evidence/6.1-greptimedb-pipeline-20261017-030404.log`) because its script waits for `greptimedb-schema.service` before it reads ingest (`modules/vm-tests/greptimedb-pipeline.nix:257-258` at `22fd7cead`) [INFERENCE: the first export in the container did not precede the schema job].
- [med] [painful | evidence: plan.md Task 2 has no format step, plan.md Task 5 Step 14 (`plan.md:4595-4598`) is the only one; `gh api .../issues/3487/events` shows `head_ref_force_pushed` at 06:30:55Z after the 06:07Z push; `jj evolog -r 76694545b`] #3487 failed the treefmt check because the plan had no format step before push, and the merged revision's last evolution changed only nixfmt layout in `modules/checks/greptimedb-envelope.nix` (`git diff e29c0b5f7 76694545b`, +28/-11).
- The two later fix PRs ran treefmt as a preflight (`logs/s1-evidence/fix-promstore-treefmt-preflight-20261017-030316.log`, `logs/s1-evidence/fix-schema-order-treefmt-preflight-20261017-045220.log`; #3490 body).
- [high] [painful | evidence: `review.md:9-20`] The holistic review found twelve problems that the plan's regulators and gates had passed: five significant, seven minor, none critical.
- F7, F9, F10 and F11 are checks that could not fail on a real mistake: clauses copying a module literal or rebuilding the module's own expression, a probe of upstream's validator, and oracle mutants testing the check's own validator (`review.md:82-123`).
- The plan's rule that every clause carries a mutant (`tasks.md:28`) rewarded those clauses, because a mutant on a literal-copy clause only shows the clause can fail on made-up input (`review.md:110`).
- F5 found the credential-holder clause cost about 2.03 GiB and 9.1 s of evaluation per pull request, close to magnetite's whole toplevel at 2.61 GiB, and no plan step measured check cost (`review.md:64-76`).
- After the fix the envelope check evaluates in about 0.41 GiB and 1.6 s (`verify.md:1287`).
- F8 found that only R7.2 had been shown able to fail on the host, while the TTL, R6.3, R6.2 and R7.3 clauses had no negative control (`review.md:86-92`).
- F1 and F2 were wrong runtime semantics: a crashing restarting unit silenced its own later notices, and R7.2 compared a ratcheting `memory.peak` that counts page cache (`review.md:30-47`; charter v14, `charter.md:296-303`).
- F3, F4 and F6 were cross-slice contradictions: a no-table-TTL rule against S7's 14-day logs table, two unrelated database lists, and a false "S4 restructures nothing" claim in D8 (`review.md:49-80`; charter v15, `charter.md:305-311`).
- [med] [painful | evidence: `verify.md:458-459`; `logs/s1-evidence/8.5-dashboard.log`] The dashboard opens with connection database `public` and status Disconnected, and a query returns rows only after the reader sets the connection database to `fleet` in the connection settings, not in the Tables panel.
- No document told the operator this, and ADR-002 Q10 leaves database selection open for S6 (`docs/notes/development/observability/decisions/ADR-002-dashboard-layer.md:118,198`).
- [med] [painful | evidence: `tasks.md:46-49`; `plan.md:5511`; `git ls-tree origin/main` at `3e68b7e33`] tasks.md section 7 planned only the charter check and the on-demand lane entry, the documenter gate's scope named no operator document, and `origin/main` has neither `modules/clan/services/otel-collector/README.md` nor `packages/docs/src/content/docs/development/operations/fleet-observability.md`.
- The missing operator docs were found only at the documenter gate (plan.md Task 7 Step 16), after deployment and review.
- [low] [nit | evidence: `verify.md:145-169`] Fifteen nouns in the behavioral requirements have no designation row.
- [low] [nit | evidence: `verify.md:218-222`] `Series cardinality stays bounded` names a machine phenomenon and a planning term ("slice S4") in a behavioral requirement.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 2.1 | `prom_store.enable` flipped to `true`, with a `promqlApi` clause and mutant | v1.2.1 gates the PromQL API on `prom_store` (#3490; charter v13, `charter.md:291-295`) |
| 3.2 | Collector ordered `After=` and `Wants=` `greptimedb-schema.service`, with an R3.1 clause and mutant | first-deploy race lost 279 points (#3492; `verify.md:329`) |
| 3 (probe) | The `memory_limiter` unknown-key probe did not behave as planned | `hostmetricsreceiver` ignores unknown top-level keys (`verify.md:1094`) |
| 5 | Two test-code fixes: `sql()` reads `affectedrows`; the OOM-order test sets `vm.panic_on_oom = 0` | nixpkgs test instrumentation sets `vm.panic_on_oom = 2` (`verify.md:1093`) |
| 6 (adaptation 1) | `__name__=~".+"` added to the host-name selector | v1.2.1 rejects a selector without a metric matcher (`verify.md:557`) |
| 6 (adaptation 2) | `sudo` on journal reads | unprivileged `journalctl` is refused on magnetite (`verify.md:980`) |
| 6 (adaptation 3) | Notifier instance read as `observability-notify@greptimedb-envelope.service.service` | systemd expands `%n` to the full unit name (`verify.md:1006`) |
| 6 (adaptation 4) | Counter names accepted without `_total` | collector 0.155 exposes them without the suffix (`verify.md:495`) |
| 6 (adaptation 5) | `read -p` prompts replaced by recorded snapshot values | the shell was non-interactive (`verify.md:521`) |
| 6 (adaptation 6) | Dashboard opened in headless Chromium instead of `open`, then checked by the operator | the agent could not use a desktop browser (`verify.md:926-927`) |
| 7.1 | The `v1.3.0-alpha.1` search matched `research/perses.md:216` | research notes are historical and ADR-002 cites R39 as superseded (`verify.md:322-323`) |
| 7 Step 15 | The paid codex (roborev) review was replaced by one holistic subagent review | cost: the operator declined it (§4) |
| 10 (new) | Section 10, review follow-ups 10.1-10.10, added after verify | twelve review findings (`review.md:5`; `tasks.md:64-75`) |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | yes (deployment from a fresh worktree of `origin/main`, `tasks.md:56`; `verify.md:327`) |
| superpowers:subagent-driven-development          | yes (`verify.md:9`, `verify.md:926`) |
| (transitive) superpowers:test-driven-development | yes (red and green logs, `tasks.md:66-75`; #3490, #3492 bodies) |
| (transitive) superpowers:requesting-code-review  | partial: the codex sub-step was skipped |
| superpowers:finishing-a-development-branch       | pending (plan.md Task 7 Steps 18-21) |

### Deliberately Skipped Skills

- **`superpowers:requesting-code-review`**
  - **What was skipped**: the roborev sub-gate, a paid `codex exec` review at `xhigh` (plan.md Task 7 Step 15, `plan.md:5468-5507`).
  - **Why this cycle**: cost; on 2026-10-17 the operator declined the paid codex review and asked instead for one holistic Opus 5.5 subagent review of S1 as a whole against the requirements and OpenSpec documents, looking for critical oversights, significant architecture improvements, check oversights and overzealousness (operator direction relayed by the orchestrator; `review.md:3-4`).
  - The substitute found nothing critical and twelve findings, all applied (`review.md:5`; `verify.md:1263-1264`).
  - **How to prevent recurrence**: `scope-judgment rule`: S2-S8 plans name the holistic subagent review with its four questions as the review gate, and name the paid codex review only as an optional second opinion that the operator opts into.

## 5. Surprises

- GreptimeDB v1.2.1 couples Prometheus remote read and write with the PromQL query API, and no setting disables remote storage alone (charter v13, `charter.md:292`).
- The OTLP exporter treats HTTP 400 as permanent and drops the batch rather than queueing it (#3492 body).
- systemd 261 passes a failed result to the stop before an automatic restart, so a stamp cleared only on a successful stop stays forever (charter v14, `charter.md:297`).
- `memory.peak` counts page cache and never decreases within an invocation (charter v14, `charter.md:301`).
- v1.2.1 renders `365d` as `11months 30days 3h 50m 24s`, so TTLs must be compared as durations (charter v15, `charter.md:308`).
- Projecting `LoadCredential` over every unit of one host costs as much evaluation as the host's toplevel (`review.md:64-74`).
- The embedded dashboard's database is a connection setting, and its default `public` holds no telemetry (`verify.md:459`).

## 6. Promote candidates → long-term learning

- [ ] [high] **Read the upstream source that registers a feature before a design disables any neighbouring switch.** → **Promote to** skill (`writing-plans`, research step for vendor configuration)
  > **Why**: ADR-007 disabled `prom_store`, which also removed PromQL; only the container test caught it (#3490).
  > **How to apply**: whenever a design sets a vendor option to `false`, cite the source lines showing what else that option gates.

- [ ] [high] **Every slice that adds a producer and the store object it writes into plans a start-order relation and a check for it.** → **Promote to** schema (OpenSpec design template, "Failure path" section)
  > **Why**: the collector started before the schema job and 279 points were dropped (#3492).
  > **How to apply**: in S2, S5 and S7 designs, for each new writer, state which unit creates its target and add an R3.1-style ordering clause with a mutant.

- [ ] [high] **Runtime tests start dependent units together and assert no dropped data, rather than waiting for each in turn.** → **Promote to** skill (`test-driven-development`, runtime-test guidance)
  > **Why**: the pipeline test waited for the schema job before reading, so it passed with the race present (`modules/vm-tests/greptimedb-pipeline.nix:257-258` at `22fd7cead`).
  > **How to apply**: in every S2-S8 `vmTests` case touching ingest, also assert the exporter's `send_failed` counter is zero after first start.

- [ ] [high] **A check clause judges a relation between independently defined values; a property of one module's own settings is an assertion in that module.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: F7, F9, F10 and F11 found clauses that copied literals or tested upstream or themselves (`review.md:82-123`; charter v16, `charter.md:313-321`).
  > **How to apply**: at S2-S8 planning, reject any clause whose expected value is read from the same source the module uses, before writing its mutant.

- [ ] [med] **Measure each new check's evaluation cost at planning and reject any above a stated budget.** → **Promote to** skill (`preferences-nix-checks-architecture`)
  > **Why**: one clause cost about 2 GiB per pull request until F5 moved it to an assertion (`review.md:64-76`; `verify.md:1287`).
  > **How to apply**: each S2-S8 plan task that adds a check records `NIX_SHOW_STATS` for its `drvPath` and states the budget, for example 0.5 GiB.

- [ ] [med] **Every runtime regulator clause gets a negative control on a real store, not only the one forced at deployment.** → **Promote to** schema (OpenSpec tasks template, runtime-envelope tasks)
  > **Why**: F8 found four envelope clauses never shown able to fail (`review.md:86-92`).
  > **How to apply**: an S2-S8 task that adds an envelope clause names the container-test case that makes it fail.

- [ ] [med] **Every task that ends in a push runs `nix fmt` (treefmt) and keeps its log before pushing.** → **Promote to** schema (plan template commit step)
  > **Why**: #3487 failed treefmt because Tasks 1-4 had no format step (`plan.md:4595-4598` is the only one).
  > **How to apply**: S2-S8 plans put a format-and-lint step immediately before every commit step.

- [ ] [med] **Plan operator documentation as a task and put it in the documenter gate's scope.** → **Promote to** schema (OpenSpec tasks template, Documentation section)
  > **Why**: no operator doc existed at deployment, and the dashboard's connection-database step was learned in a live session (`verify.md:458-459`; `tasks.md:46-49`; `plan.md:5511`).
  > **How to apply**: each S2-S8 tasks.md section 7 lists the operator page and component README it updates, with how to reach and query what the slice deploys.

- [ ] [med] **Run one holistic review of the planned regulators before implementation, asking which checks cannot fail and which cost more than they protect.** → **Promote to** skill (`writing-plans`, plan review step)
  > **Why**: the twelve S1 findings came after merge and cost three follow-up PRs (#3497, #3498, #3499).
  > **How to apply**: before S2-S8 Task 1, run the review's four questions (`review.md:4`) against design.md D11-D13 equivalents.

- [ ] [med] **Check each slice's rules against the later slices that touch the same objects.** → **Promote to** schema (OpenSpec design template, Risks section)
  > **Why**: F3, F4 and F6 were contradictions with S4 and S7 (`review.md:49-80`).
  > **How to apply**: an S2-S8 design lists every later slice that reads or writes its objects and states the rule each must keep.

- [ ] [med] **Notifier and regulator semantics are tested across restart and cache-fill states, not only a clean failure.** → **Promote to** memory (type: feedback)
  > **Why**: F1 (restart silences notices) and F2 (`memory.peak` ratchets) passed the 8.6 forced failure (`review.md:30-47`).
  > **How to apply**: S3's alerting and S4's `otel-envelope` include a crash-loop case and a long-running case in their plans.

- [ ] [low] **Resolve the designation-lint nouns at sync.** → **Promote to** one-off
  > **Why**: fifteen nouns lack a designation row and one behavioral requirement names a planning term (`verify.md:145-169`, `verify.md:218-222`).
  > **How to apply**: add the rows `verify.md` §8a proposes to the `world-assumptions` designation table in S2's delta, and drop "slice S4" from `Series cardinality stays bounded`.

- [ ] [low] **Record the operator's reason whenever a planned gate is replaced.** → **Promote to** one-off
  > **Why**: `review.md:3` records the substitution but not its cost reason, which this retrospective had to ask for.
