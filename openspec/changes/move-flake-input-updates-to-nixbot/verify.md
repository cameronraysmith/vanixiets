# Verification Record

**Change**: `move-flake-input-updates-to-nixbot` (CAM-108)

Evidence names are files under `logs/`, which is git-ignored.
Times are UTC.
No key, JWT or token was printed or written; each JWT was signed in process memory (1.1) or in a shell variable on magnetite (1.3), and only ids, names and permissions were kept.

## 1. Forge application and identities (2026-11-17)

### 1.1 The App and its installation, read with the App's own JWT

`logs/cam-108-task-1.1-20261117T205707Z.log`; the App id and key were read from `sops -d secrets/shared.yaml` into process memory only.

| Read | Result |
|---|---|
| `GET /app` | id `2369061`, slug `vanixiets-flake-updater`, permissions `contents: write`, `metadata: read`, `pull_requests: write` |
| `GET /repos/cameronraysmith/vanixiets/installation` | installation id `96887219`, app id `2369061`, account `cameronraysmith` (`User`), `repository_selection: selected`, permissions `contents: write`, `metadata: read`, `pull_requests: write` |

The id `GET /app` reports equals `FLAKE_UPDATER_APP_ID`.
The installation id is recorded here for task 8.3 only; the program looks it up at run time.

### 1.2 The bot identity

`logs/cam-108-task-1.2-20261117T205707Z.log`: `gh api 'users/vanixiets-flake-updater%5Bbot%5D' --jq '{login,id,type}'` prints `{"id":246545483,"login":"vanixiets-flake-updater[bot]","type":"Bot"}`.

### 1.3 nixbot's own App cannot write contents

`logs/cam-108-task-1.3-20261117-155654.log`: on magnetite as root, a JWT signed from `/run/credentials/nixbot.service/github-app-secret-key` (the key nixbot loads, `appId = 4743700`) reads `GET /app` as `{"id":4743700,"slug":"sciexp-nixbot","permissions":{"checks":"write","contents":"read","members":"read","metadata":"read","pull_requests":"write"}}`: `contents: read`.

## 2. Implementation chain before task 2.1

Builds ran on magnetite at the chain's revision (`git+file://…?rev=<commit>`), each log naming its revision.

| Task | Evidence |
|---|---|
| 3.1, 3.2 | `logs/effects-interpreter-schedule-20261117-160043.log`; rebuilt green after later edits in `logs/effects-interpreter-schedule-20261117-161431.log` and `logs/cam108-docs-linkcheck-20261117-161739.log` |
| 3.3 | `logs/cam108-mutant-schedule-guard-20261117-160108.log`, `logs/cam108-mutant-schedule-rev-20261117-160108.log`, `logs/cam108-mutant-no-trigger-msg-20261117-160108.log` |
| 4.1 | `logs/flake-update-program-20261117-160924.log` |
| 4.2 | `logs/flake-update-rehearsal-20261117-161039.log` |
| 4.3 | `logs/flake-update-rehearsal-cost-20261117-160944.log` |
| 4.4, 4.5 | `logs/cam108-mutant-{drop-exclude,drop-identity,skip-token-file,keep-key-file,wrong-app-id}-20261117-161050.log`, each running case 1 only |
| 6.1, 6.2 | `logs/cam108-task-6.1-6.2-20261117-161520.log` |
| 6.3 | `logs/cam108-task-6.3-20261117-161739.log`, `logs/cam108-docs-linkcheck-20261117-161739.log` |

### The live `when` nixbot reads

hercules-ci-effects' typed `onSchedule.<name>.when` option normalises the registry's declared `{ dayOfWeek = [ "Tue" "Fri" ]; hour = 22; minute = 0; }` to `{ dayOfMonth = null; dayOfWeek = [ "Tue" "Fri" ]; hour = [ 22 ]; minute = 0; }`, the value the flake's `herculesCI` output carries and nixbot reads (`nixbot/nixbot/schedules.py` accepts a list `hour` and a null `dayOfMonth`); it is the same schedule.
First observed in `logs/cam108-scratch-with-2.1-20261117-161257.log`; the spec, task 5.2 and `checks.effects-interpreter` state the normalised value.

### Held back until task 2.2

Until 2.2 the chain declared no `FLAKE_UPDATER_*` secret, so the join kept evaluating and deploying as before.
`logs/cam-108-task-2.1.patch`, outside the chain, held the two `flake.lib.vanixietsEffectSecrets` entries (task 2.1), the entry's `secrets = [ "FLAKE_UPDATER_APP_ID" "FLAKE_UPDATER_PRIVATE_KEY" ]` (task 5.1), and the two `registry: flake-update` rows of `checks.effects-interpreter` with the trigger's granted secrets (task 5.2).
A scratch copy of the chain with the patch applied listed both secrets and both prompts and built `effects-interpreter`, `flake-update-rehearsal` and `nixbot-wiring` (`logs/cam108-scratch-with-2.1-20261117-161455.log`, `logs/cam108-scratch-with-2.1-20261117-161831.log`).

## 3. Effect secrets (2026-11-17)

### 2.2 Operator record (performed by the orchestrator at the operator's request, 2026-11-17)

`logs/cam-108-task-2.2-20261117-165812.log`: the orchestrator, at the operator's request, applied `logs/cam-108-task-2.1.patch`, set `vanixiets-effects-secrets/flake-updater-app-id` and `flake-updater-private-key` from `sops -d --extract` over stdin with `clan vars set`, never printed, then ran `clan vars generate magnetite -g vanixiets-effects-secrets --no-regenerate </dev/null`, which keeps every stored prompt value.
The composed secrets' keys are the seven names, the key's first line is the PEM header, and the App id is `2369061`; the five existing prompt files were re-encrypted (ciphertext only).
clan made three commits on the detached HEAD (`5739726b3`, `d0879fc9a`, `ba8549de2`); the orchestrator moved HEAD back to the join with `git reset --soft`, leaving them unreferenced and holding only sops ciphertext.
The patched files and the `vars/per-machine/magnetite/vanixiets-effects-secrets/` files were then routed into the chain.

### 2.1, 5.1, 5.2 at the chain's revision

`logs/cam-108-task-2.1-20261117-165923.log` (revision `dda2a600`): `lib.vanixietsEffectSecrets` lists both names, magnetite's generator prompts list `flake-updater-app-id` and `flake-updater-private-key`, and `checks.x86_64-linux` (171) and `checks.aarch64-darwin` (111) evaluate.
`effects-interpreter`, `flake-update-rehearsal` and `nixbot-wiring` build on magnetite (`logs/effects-interpreter-flake-update-20261117-165923.log`), and `effects-interpreter` rebuilt with `--rebuild` ran both `registry: flake-update` rows (`logs/effects-interpreter-flake-update-rebuild-20261117-165935.log`).

### 2.3 Leak scan

`logs/flake-update-leak-20261117-165955.log`, counts only.
Three interior lines of the PEM (lines 5, 12 and 20, 64 characters each) were taken from `sops -d` into a shell variable and each matched in four layers: files of the working tree including ignored paths (`.git` and `.jj` excluded, as the object layers cover them), files of the chain's tree, every object reachable from all refs (decompressed through `git cat-file --batch`), and every object in the git store, the three unreferenced clan commits included.
Every count is 0.
The control string `vanixiets-flake-updater` counts 228 files, 18 files, 169 lines and 169 lines.
The object layers replace `git log --all -S`, whose needle would sit in `git`'s argv; they read the same history and more.
For the two object layers, grep read the needle from a file under `/tmp` that was removed as soon as grep finished and is absent (checked after the scan); no other copy was written.
This was a deviation from the rule that key material is never written to a file: the file was local to the workstation, existed for about 40 seconds and was deleted, and the operator was informed.

## 4. Landing and deployment (2026-11-17)

### 7.1 Landing

`logs/cam108-task-7.1-20261117-172152.log`: #3951 (body `Part of CAM-108.`, through gitea-mq) merged at 22:16:33Z as `727f2a57`, which `main` contains.
Its `nixbot/nix-eval`, `nixbot/nix-build` and `nixbot/effects` contexts passed from build 2546, in which the effect check `schedule.flake-update.flake-update` (run 22306) succeeded.
That check builds the effect's inputs; the effect's derivation, evaluated at `727f2a57`, has `flake-update-rehearsal.drv` among its inputs, and the rehearsal's output is the one built during implementation (`mgj1r1lm…`), so the attribute shows `skipped_local` in builds 2545 and 2546.
The pull request's earlier head `f97c03e7` (build 2545) failed only `checks.x86_64-linux.treefmt`; the delivery commit gained a formatting-only fix.

### 7.2 Deployment, delivered secrets and posts

`logs/pr-cam-108-flake-update-effect-fix-20261117-171041.log`: `clan machines update magnetite` from `main` exited 0 and restarted `nixbot.service`, active since 22:17:51Z; the key set of `/run/credentials/nixbot.service/effects-secret__github_colon_cameronraysmith_slash_vanixiets` is the seven names, both new ones included, with no value printed.
`logs/cam108-task-7.2-ntfy-20261117-172100.log`: ntfy.zt history since 22:10:00Z on `fleet-alerts`, `fleet-alert`, `fleet-heartbeat`, `fleet-beat` and the host-named topics `magnetite`, `cinnabar`, `stibnite` and `pyrite` holds only the dead-man's heartbeats (`ok <epoch>` on `fleet-heartbeat`, one a minute); no alert or failure notice was posted.

The deploy's nixbot restart did fail two effect runs, which posted no notice.
Build 2546 ran `default.docs` and `default.release-packages` once for the push (runs 22308 and 22309, both succeeded) and once for each tag the docs release pushed on `727f2a57` (`@vanixiets/docs-v0.19.0`, `docs-v0`, `docs-v0.19`).
The tag runs exit 0 at the main-only guard (`EFFECT-GUARD: skipping outside a push to main (event=tag …)`, runs 22312 and 22313); the `docs-v0.19` pair (22318, 22319) was failed by nixbot with "interrupted by a service restart" at 22:17:54Z, three seconds after the restart, and would also have been guard skips.
Cause: deploy timing, not a defect; their `nixbot/effect …#default.docs` and `…#default.release-packages` commit statuses on `727f2a57` read FAILURE. Build 2542 of `main`'s parent `24bc0a55` ran both effects green. No rerun was made.

### 7.3 Registration

`logs/cam108-task-7.3-schedule-20261117-172125.log`: after build 2546, the first green non-pull-request build of `main` with the change, nixbot's effects page lists schedule `flake-update` with effect `flake-update`, "at 22:00 UTC on Tue, Fri", next run 2026-11-20T22:00:00Z, last run never.
The landing came after that Tuesday's 22:00Z occurrence, which was therefore not run (design D7's cutover gap); task 9.1's manual run covers it.

## 5. Integration (2026-11-17)

### 9.1 Manual run

The operator pressed run-now on the effects page (no API token was used): run 22320, event `schedule`, 22:21:47–22:27:50Z, succeeded.
`logs/cam108-task-9.1-run-22320-20261117-172806.log` is its log: one `Update <input>...` line for each of the 56 root inputs other than `playwright-web-flake`, no error or failed input, 23 `Opened …/pull/<n>` lines and `No updates to push` for the rest, and no `ghs_`, `eyJ`, `PRIVATE KEY` or `x-access-token` string.
The program at `727f2a57` logs nothing on a successful installation lookup, so run 22320's log shows the lookup only through the run's success (the program exits non-zero before nixbot's script when the lookup or the mint fails).
Task 9.1 stays open for that reason: the program now prints `flake-update: App installation <id> on <owner>/<repo>` after the lookup, never a token or JWT, and `flake-update-rehearsal` asserts the line in case 1 and its absence in case 2; the first run after that change deploys witnesses the lookup in nixbot's log.
`logs/cam108-task-9.1-prs-20261117-172806.log`: each of #3954–#3976 is authored by `app/vanixiets-flake-updater` on `update-<input>`, its head commit's author and committer are `246545483+vanixiets-flake-updater[bot]@users.noreply.github.com`, it changes only `flake.lock`, and it is open with no label and no auto-merge; none is for `playwright-web-flake`.
`logs/cam108-task-9.1-status-20261117-172852.log`: `nixbot/nix-eval` had started on all 23, so their webhooks reached nixbot.
The repository also holds eight `update-*` branches no run of this change touches, left by the old updater for inputs no longer locked (`aeneas`, `agenix`, `nix-fast-build`, `nix-rosetta-builder`, `nixos-generators`, `nvim-treesitter-main`, `worktrunk`) or excluded (`playwright-web-flake`, last pull request #3097, closed 2026-09-18).

### 9.3 Rerun

The operator pressed run-now again: run 22433, event `schedule`, 22:46:44–22:51:03Z, succeeded, from the same `main` (`727f2a57`).
`logs/cam108-task-9.3-run-22433-20261117-175115.log` has one `Update <input>...` line for each of the 56 inputs and no `ghs_`, `eyJ`, `PRIVATE KEY` or `x-access-token` string; its 23 "Validation Failed" lines are GitHub's "A pull request already exists" answers, which the script treats as success.
Of the 23 pull-request branches, 21 print `update-<input> is up to date.` and are unchanged; the other 33 inputs print `No updates to push`.
`logs/cam108-task-9.3-before-20261117-172835.log` against `logs/cam108-task-9.3-after-20261117-175115.log`: 29 of the 31 `update-*` heads are equal, and the app's pull requests after 7.1 are still 23, so the run opened none.
The two changed heads follow inputs that moved upstream between the runs, not a defect: `llm-agents` from `cd5d0317` to `60ed0dea` and `niks3` from `48598972` to `753b9533` (each run's `Updated input` lines).
Each new head (`be124c05`, `05eca0d9`) is one bot-authored commit on `727f2a57` changing only `flake.lock`, force-pushed onto the open #3961 and #3962, which kept their numbers.

### 9.6 Hosted runner

`logs/cam108-task-9.6-20261117-172125.log`, read 22:21Z: the newest `update-flake-inputs.yaml` run was created 2026-11-13T01:56:52Z, none after the merge, and the workflow query prints nothing.

### 9.7 One updater per input

`logs/cam108-task-9.7-20261117-172835.log`: the 23 branches of the `app/vanixiets-flake-updater` pull requests created after the merge.
None is among the three revision-pinned inputs (`catppuccin-bottom`, `catppuccin-starship`, `easykubenix`) or the nine tag-pinned inputs Renovate's regex managers update (`argocd-helm-src`, `argocd-src`, `cilium-src`, `dms-src`, `gateway-api-src`, `lazyvim-nix`, `nix-unit`, `playwright-web-flake`, `sops-secrets-operator-src`); for each of those except the excluded `playwright-web-flake`, runs 22320 and 22433 both printed `No updates to push`, as A127 predicts, and run 22433 opened no pull request, so the set is unchanged after the second live run.
