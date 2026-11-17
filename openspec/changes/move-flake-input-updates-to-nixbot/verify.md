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
