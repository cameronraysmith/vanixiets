---
linear_story_id: 731fbccd-57ca-4c76-aa44-7e5bdc4cbc4c
linear_story_identifier: CAM-108
linear_story_title: "Move flake input updates to a nixbot scheduled effect"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-108/move-flake-input-updates-to-a-nixbot-scheduled-effect
linear_story_state: Todo
linear_team: CAM
linear_project: nixbot-herculesci-cicd
last_synced_state: Todo
last_synced_at: 2026-11-17T19:15:34Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-17T19:15:34Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue created in project nixbot-herculesci-cicd at Todo, description seeded from this proposal, one comment posted" }
---

## Why

Branch-tracking flake inputs are refreshed by a GitHub Actions workflow that runs on hosted runners, and the same setup is about to be reused on a private repository, where those runner minutes are billed.
The workflow also ties the update path to GitHub, while nixbot, which already builds every update pull request, runs scheduled effects on our own host for GitHub, Gitea and GitLab.
Renovate is taking over every other dependency (CAM-106) and leaves exactly these inputs to a separate updater, so the refresh should move now, before the private-repository reuse copies the workflow.

## What Changes

**Where flake-input refreshes run**
- From: `.github/workflows/update-flake-inputs.yaml` runs `mic92/update-flake-inputs` on a GitHub-hosted runner every Tuesday and Friday at 22:00 UTC.
- To: nixbot runs its `flakeUpdate` effect with `perInput = true` on magnetite on the same schedule, from `main`, declared through the vanixiets effects registry.
- Reason: no hosted runner on the update path, and the effect works on any forge nixbot supports.
- Impact: non-breaking for reviewers. Pull requests stay one per input on branch `update-<input>`, so an open one carries over; titles become `Update <input>` and bodies become the lock diff; the unused `flake-update` label and the signoff trailer are dropped.

**Which identity writes**
- From: the workflow mints a token for the GitHub App `vanixiets-flake-updater` from two GitHub repository secrets.
- To: the effect mints a one-hour installation token for the same App from its key, now held in the vanixiets effects secrets on magnetite, discovering the installation at run time; commits are authored as the App's bot user. nixbot's own forge identity gains no write permission.
- Reason: keeps the existing identity and keeps write access out of the build service's own credential.
- Impact: the App's key is present inside this effect's sandbox during a run; any effect declared on `main` could name it, and only collaborators can change `main`.

**A schedule trigger in the effects registry**
- From: the registry interprets only push-to-main and pull-request, close and build-finished events.
- To: it also interprets a schedule, with the same rendered entry point, per-trigger secrets and rehearsal gate, and `checks.effects-interpreter` pins the new kind.
- Reason: one interpreter convention for every effect, which the private-repository reuse inherits.
- Impact: a rehearsal check against a fake forge joins the pre-merge `nixbot/effects` gate.

**Cutover in this change**
- Removed: the workflow, the `update-flake-inputs` justfile recipe, the `FLAKE_UPDATER_*` lines of the `ghsecrets` recipe and their documentation rows. After the effect's first successful run, the operator deletes the two GitHub repository secrets and the `secrets/shared.yaml` keys. The App stays.
- Manual runs move from `just update-flake-inputs` to `nbo schedule run`.

## Capabilities

### New Capabilities
- `flake-input-refresh` (stratum: `behavioral`): what the flake-input updater must do for the repository — refresh each branch-tracking flake input on a fixed twice-weekly schedule as its own update pull request, leave the Playwright flake input alone, keep at most one open update pull request per input and drop one whose input caught up, act under its own forge application with expiring credentials and never the build service's, leave merge authorization to people, and run without a hosted runner.
- `flake-input-refresh-interface` (stratum: `interface`): the properties at the machine's interface that discharge them — the scheduled effect's evaluated declaration (schedule, checkout, secrets map, arguments), the rendered entry point without the main-only guard, the token minted per run from the application key with the installation discovered at run time, the commit identity, and the rehearsal check that exercises the program against a fake forge. Trust boundary: the machine controls what the effect is declared to run, with which secrets and arguments, and what the program does with them; it does not control when nixbot registers or fires the schedule, nixbot's sandbox and secrets delivery, the forge's token semantics, which repositories the App is installed on, or whether an upstream input's new revision builds.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): adds assumptions on nixbot's schedule registration and firing window, its per-effect secrets delivery, the behaviour of its `flakeUpdate` script with `perInput`, the forge's App installation lookup and webhook delivery for App pushes, and `nix flake update` leaving a revision- or tag-pinned input where it is; the designation table gains `hosted runner`.

## Impact

Implementation touches: `modules/effects/vanixiets/registry.nix` (the `schedule` trigger kind and its `onSchedule` mapping); `modules/effects/vanixiets/effects.nix` (the `flake-update` entry); `modules/effects/vanixiets/secrets.nix` (two new effect secrets); a new program and rehearsal check beside them; `modules/checks/effects-interpreter.nix` (rows for the new kind and entry); deletion of `.github/workflows/update-flake-inputs.yaml`; `justfile`; `packages/docs` pages that name the workflow or its recipe.
Deployment: magnetite, to deliver the recomposed effects secrets to nixbot.
Outside the repository: the operator populates the two secrets, and after the first successful run deletes the GitHub repository secrets and the `secrets/shared.yaml` keys.

Nothing in nixbot, gitea-mq or Renovate is edited, and the App's permissions and installation are unchanged.
Out of scope: auto-enqueueing update pull requests (enqueueing stays an operator act); the `rev`- and tag-pinned flake inputs, which Renovate updates; a Gitea or GitLab variant of the credential step; changing gitea-mq's `batchMax`.
Ordering with CAM-106: either change can land first. This change's world-assumptions delta carries CAM-106's designation rows and must be re-merged with whatever is on main before it archives.
