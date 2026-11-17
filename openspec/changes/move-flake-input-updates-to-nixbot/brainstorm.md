<!--
Raw capture of the 2026-11-17 decision session. The questions were explored by two read-only
investigations of nixbot at the pinned revision 171a8c77 and of this repository, and the operator
settled each decision; this file records that log as it ran, and design.md reorganizes it.
-->

# Brainstorm: move branch-tracking flake-input refreshes to nixbot's `flakeUpdate` effect

## Background

`.github/workflows/update-flake-inputs.yaml` refreshes the flake inputs of `cameronraysmith/vanixiets` twice a week (cron `0 22 * * 2,5`, Tuesday and Friday 22:00 UTC) on a GitHub-hosted runner.
It mints a token for the GitHub App `vanixiets-flake-updater` from the repository secrets `FLAKE_UPDATER_APP_ID` and `FLAKE_UPDATER_PRIVATE_KEY`, then runs `mic92/update-flake-inputs`, which opens one pull request per changed root input on branch `update-<input>`, labelled `flake-update`, with `--signoff`, excluding `playwright-web-flake`.
nixbot builds those pull requests and gitea-mq lands them in batches (`batchMax = 20`, which `modules/nixos/gitea-mq.nix` asserts for "flake-update waves").

Two pressures make this worth changing now.
The same framework is to be reused on a private repository, where GitHub Actions minutes are billed, so the update path should not need a hosted runner.
And nixbot supports GitHub, Gitea and GitLab, while the workflow ties the update path to GitHub Actions.

The sibling change `stand-up-renovate-on-magnetite` (CAM-106) makes a self-hosted Renovate the updater for every dependency except branch-tracking flake inputs: Renovate's `nix` manager stays enabled with lock file maintenance off, so it updates the three `rev`-pinned inputs and, through `custom.regex`, the nine tag-pinned ones.
It leaves the 45 branch-tracking inputs, nixpkgs among them, to "a separate change" that moves them to nixbot's `flakeUpdate` effect. This is that change.

## Evidence gathered

nixbot `flakeUpdate` (`herculesCI/flake-update.nix`, `herculesCI/nixbot-flake-update.py` at 171a8c77):
- One upstream commit (`1315830`, PR #237, merged 2026-10-25), about three weeks old; one check (`checks/effects-lib-flake-update.nix`) against a fake forge and a fake `nix`; no known `perInput` user. Mic92's own repositories do not use it: his dotfiles moved flake inputs to Dependabot's `nix` ecosystem.
- With `perInput = true`, each root input of the base lock (less `excludeInputs`) gets branch `<updateBranch>-<input>` rebuilt from the base, `nix flake update <input> --commit-lock-file`, a force-push only when tree, parents or message differ, and a pull request; a 422 "already exists" counts as success; a branch whose input no longer moves is deleted; a failing input does not stop the others but fails the run.
- The script reads its push token from `$HERCULES_CI_SECRETS_JSON` at `.token.data.token`, drops the checkout's `insteadOf` entries, pushes through a credential store as `x-access-token`, and writes `access-tokens` for nix. Without overrides it commits as `nixbot <nixbot@localhost>`. It has no label or signoff option.
- No App support: nothing mints an installation token from an App key.

nixbot scheduling (`schedules.py`, `schedule_runner.py`, `after_build.py`):
- `onSchedule` definitions are re-read only after a successful non-pull-request default-branch build; a red main keeps the previous definition.
- An occurrence runs if a sweep sees it within a five-minute window; nothing catches up a missed occurrence.
- A scheduled run evaluates the effect from the default branch tip, gets a checkout of it, and a secrets file holding exactly what the effect's `secretsMap` names. Any default-branch effect may name any repository secret; conditions are per repository, not per effect.
- Manual run: `nbo schedule run <schedule> <effect> [-f]` with an admin token.
- Pull-request and batch builds already build the dependencies of every `onSchedule` effect for `nixbot/effects`.

vanixiets:
- The effects registry (`modules/effects/vanixiets/registry.nix`) interprets `vanixiets.effects` entries into `onPush` and `onEvent` effects through one renderer, pinned by `checks.effects-interpreter`; it has no schedule trigger.
- The composed effects secrets file has shape `{ NAME: { data: { value } } }` (`modules/effects/vanixiets/secrets.nix`), which `flakeUpdate` cannot read as `data.token`.
- The App's bot user is `vanixiets-flake-updater[bot]`, user id `246545483` (public `GET /users/vanixiets-flake-updater%5Bbot%5D`, 2026-11-17). The App itself is private (`GET /apps/vanixiets-flake-updater` returns 404 without its JWT).
- No `app/vanixiets-flake-updater` pull request was open on 2026-11-17; the last merged ones (#3843–#3845, 2026-11-13) landed in gitea-mq batches 311 and 312 with label `flake-update`.

## Decision chain

**Q1. Which updater refreshes branch-tracking flake inputs?**
Options: keep the GitHub Actions workflow; Renovate lock file maintenance (one combined pull request); pin every input to a `rev` in `flake.nix` so Renovate's digest updates cover all of them; Dependabot's `nix` ecosystem (what Mic92/dotfiles now uses); nixbot `flakeUpdate` with `perInput`.
Operator decision (D-a): nixbot `flakeUpdate` with `perInput = true`. One pull request per input keeps a failing input from holding the others back, and gitea-mq batches them. Lock file maintenance was withdrawn because its single pull request loses that isolation. Dependabot is GitHub-only, so not forge-portable, and its billing on a private repository is unverified. The workflow uses billed minutes on a private repository.
The objections the Renovate change raised against a scheduled effect (its D1) apply only weakly here: the sandbox runs git and `nix flake update` of trusted `main`, which only collaborators reach, rather than repository task commands; and a run missed while nixbot is down is a late twice-weekly refresh, recoverable with `nbo schedule run`.

**Q2. Which credential pushes and opens the pull requests?**
Options: nixbot's own forge token (`sciexp-nixbot`); a fine-grained PAT; the existing `vanixiets-flake-updater` App key, minting an installation token inside the effect.
Operator decision (D-b): the App key. `sciexp-nixbot` must not hold Contents write (the gitea-mq change's rule). A PAT is long-lived and tied to a personal account. A wrapper in the effect mints a one-hour installation token, discovering the installation through `GET /repos/{owner}/{repo}/installation` with the App's JWT rather than hard-coding its id, writes `{ token: { data: { token } } }` to a private file and points `HERCULES_CI_SECRETS_JSON` at it for nixbot's script. The App id and key move from GitHub repository secrets and `secrets/shared.yaml` into the vanixiets effects secrets. Stated exposure: the PEM is present in this effect's sandbox for the run; any `main` effect could name these secrets; only collaborators reach `main`.

**Q3. Declare directly or through the registry?**
Options: a direct `herculesCI.onSchedule.flake-update` declaration; a new `schedule` trigger kind in the registry.
Operator decision (D-c): a `schedule` trigger kind, so one interpreter convention covers every effect and the private-repository reuse inherits it. The kind carries a `when`, renders without the main-only guard, `--rev` or `idTokenAudiences`, can request nixbot's checkout, maps to `onSchedule`, and is named in `requireTrigger`'s message. A rehearsal check against a fake forge (after nixbot's own check) and `checks.effects-interpreter` rows pin it.

**Q4. Arguments, branch names, identity, labels.**
Operator decision (D-d): `updateBranch = "update"` so branches stay `update-<input>` and an open pull request of the old updater carries over; `excludeInputs = [ "playwright-web-flake" ]`; commits authored and committed as `vanixiets-flake-updater[bot] <246545483+vanixiets-flake-updater[bot]@users.noreply.github.com>`; drop the `flake-update` label (nothing reads it; the only mention is a commented line in `.github/mergify.yml`) and signoff (nothing requires it); `when = { dayOfWeek = [ "Tue" "Fri" ]; hour = 22; minute = 0; }`, the workflow's cron.

**Q5. Cutover.**
Operator decision (D-e): in this change. Delete the workflow, the `update-flake-inputs` justfile recipe, the `FLAKE_UPDATER_*` lines of `ghsecrets` and the documentation rows; after the effect's first successful run, the operator deletes the two GitHub repository secrets and the `secrets/shared.yaml` keys. Keep the App.

## Points found while writing the design

- `nix flake update <input>` on a `rev`-pinned or tag-pinned input re-locks the same revision, so the effect pushes no branch for the twelve inputs Renovate owns unless an upstream tag is moved. The split between the two updaters therefore holds without listing those inputs in `excludeInputs`; the first live runs check it.
- nixbot names a scheduled effect by schedule and effect. The registry names `onPush` and `onEvent` effects after the entry, so the entry `flake-update` becomes `onSchedule.flake-update.outputs.effects.flake-update`, and the manual run is `nbo schedule run flake-update flake-update -f`; the session's draft command `nbo schedule run flake-update update -f` assumed a direct declaration.
- The installation-token minting is GitHub-specific. nixbot's script is forge-portable, so on Gitea or GitLab the same entry would hand the script a bot account's token instead of minting one; that variant is outside this change.
- Prompts added to `vanixiets-effects-secrets` make the generator out of date for magnetite until they are populated, and `clan machines update` regenerates missing generators before deploying, so the declaration and its population go into the tree together.
