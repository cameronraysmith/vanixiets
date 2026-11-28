## Context

`cameronraysmith/vanixiets` locks 58 root flake inputs.
Since CAM-106 (`stand-up-renovate-on-magnetite`), a self-hosted Renovate updates the three inputs pinned by `rev` and the nine pinned by tag, and leaves the 45 branch-tracking inputs (default branch, a named branch, or a nixos.org channel tarball) to a second updater.
Today that second updater is `.github/workflows/update-flake-inputs.yaml`: on a GitHub-hosted runner at `0 22 * * 2,5`, it mints a token for the GitHub App `vanixiets-flake-updater` from the repository secrets `FLAKE_UPDATER_APP_ID` and `FLAKE_UPDATER_PRIVATE_KEY` and runs `mic92/update-flake-inputs`, which opens one pull request per changed input on `update-<input>`, labelled `flake-update`, signed off, with `playwright-web-flake` excluded.
nixbot builds those pull requests, and the operator enqueues them into gitea-mq, which lands them in batches of up to 20 (`modules/nixos/gitea-mq.nix` asserts `batchMax == 20` for these "flake-update waves").

This framework is to be reused on a private repository, where hosted-runner minutes are billed, and the workflow ties the update path to GitHub.
nixbot (pinned at `171a8c77`) ships `flakeUpdate`, a port of hercules-ci-effects' effect with a `perInput` mode that reproduces `update-flake-inputs`' per-input pull requests on GitHub, Gitea or GitLab, and it runs `onSchedule` effects from its own sweep loop on magnetite.
The vanixiets effects registry (`modules/effects/vanixiets/registry.nix`) is the one interpreter for this repository's effects: entries name a program and its rehearsal checks, and per trigger declare arguments, a lock and the secrets the run may read; `checks.effects-interpreter` pins the rendered entry point. It has no schedule trigger yet.

The decisions below were settled by the operator on 2026-11-17 (brainstorm.md, D-a to D-e); this document turns them into a design.
Stakeholders: the operator, who populates the secrets, enqueues update pull requests and deletes the old secrets; nixbot, which runs the effect and builds its pull requests; gitea-mq, which lands them; CAM-106, which owns every other dependency.

## Goals / Non-Goals

**Goals:**

- nixbot refreshes every branch-tracking flake input except `playwright-web-flake` every Tuesday and Friday at 22:00 UTC, one pull request per moved input, on branches `update-<input>`.
- No hosted runner on the update path, and nothing GitHub-Actions-specific in it.
- The App `vanixiets-flake-updater` remains the writing identity, through a per-run one-hour installation token; nixbot's own App gains no permission.
- The effect is declared through the registry, so `checks.effects-interpreter` and a rehearsal check cover it before it merges.
- The workflow, its recipe and its secrets are gone once the effect has run successfully.

**Non-Goals:**

- The `rev`- and tag-pinned inputs (Renovate's, CAM-106), and Renovate itself.
- Auto-enqueueing or auto-merging update pull requests; enqueueing stays an operator act.
- A Gitea or GitLab credential path; nixbot's script is forge-portable, but the App-token minting here is GitHub's.
- Changing gitea-mq's `batchMax` or the `PullRequestQueueWaitBurn` rule.
- Any edit to nixbot, gitea-mq, the App's permissions or its installation.

## Decisions

### D1: nixbot `flakeUpdate` with `perInput` refreshes branch-tracking flake inputs (operator D-a)

- **Choice**: nixbot's `flakeUpdate` (from the locked `inputs.nixbot`, `lib.effects { inherit pkgs; }`) with `perInput = true`, run as a scheduled effect on magnetite.
- **Rationale**: one pull request per input means one failing input holds back no other, and gitea-mq batches them. Runs happen on our own host, on any forge nixbot supports. The objections CAM-106's D1 raised against running Renovate as a scheduled effect apply weakly here: the sandbox runs only our program, git and `nix flake update` of trusted `main`, which only collaborators can change, not repository task commands; and a run missed while nixbot is down is a late twice-weekly refresh, recovered with `nbo schedule run flake-update flake-update -f`.
- **Scope of inputs**: all root inputs less `playwright-web-flake`, and less `nixpkgs` while its held update (CAM-125) is blocked: the effect rebuilds and force-pushes every open update branch on each run, so the held pull request would get a full CI build twice a week. `nix flake update <input>` re-locks a `rev`-pinned input to the same revision and a tag-pinned one to the commit its tag names (A127), so the effect pushes no branch for Renovate's twelve inputs unless an upstream tag is moved; the split holds without listing them in `excludeInputs`, and task 9.7 checks it.
- **Alternatives considered**: keep the workflow (hosted minutes, GitHub-only); Renovate lock file maintenance (one pull request for every input, withdrawn because it loses isolation); pin every input to a `rev` in `flake.nix` so Renovate's digest updates cover them (turns 45 floating references into churn in `flake.nix` and loses the meaning of tracking a branch); Dependabot's `nix` ecosystem, which Mic92/dotfiles now uses (GitHub-only, and its billing on a private repository is unverified).
- **Boundary**: vendored-versus-first-party. nixbot's script and its `flakeUpdate` wrapper are consumed unedited from the locked input; vanixiets owns only the arguments, the credential step and the identity. A nixbot bump that changes the script changes the effect, which is why the rehearsal (D6) runs the vendored script itself and world assumption A125 names its behaviour at `171a8c77`.

### D2: The App key mints a per-run installation token inside the effect (operator D-b)

- **Choice**: the effect's secrets are `FLAKE_UPDATER_APP_ID` and `FLAKE_UPDATER_PRIVATE_KEY`, and a first-party program, `flake-update`, turns them into an installation token before nixbot's script runs:
  1. Take the API endpoint and `owner/repo` from the checkout's `origin`, as nixbot's script does (`https://api.github.com` for `github.com`, `<url>/api/v3` otherwise).
  2. Under `umask 077`, in a fresh directory outside the checkout, write the key to a file and sign a nine-minute App JWT with `gh-token generate --jwt --duration 9 --app-id … --key <file>`, which signs locally and makes no request.
  3. `GET /repos/{owner}/{repo}/installation` with the JWT; `POST /app/installations/{id}/access_tokens` with a body restricting the token to this repository and to `contents: write` and `pull_requests: write`.
  4. Delete the key file, `unset` both variables, write `{ "token": { "data": { "token": … } } }` to a second private file, export `HERCULES_CI_SECRETS_JSON` pointing at it, and run nixbot's script.
  5. On exit, revoke the token with `DELETE /installation/token` (best effort) and remove the directory.
  Any failure before step 4 exits non-zero with nothing pushed. The installation id is never a constant.
- **Rationale**: keeps the identity reviewers already know and keeps write access out of `sciexp-nixbot`, which must not hold Contents write (the gitea-mq change's rule). The installation token expires in an hour and, narrowed in step 3, reaches one repository with two permissions. Discovering the installation at run time lets the same program serve the private repository with only different secrets.
- **Tooling (`gh-token` for the JWT, `curl` for the three calls)**: CAM-106 mints with `gh-token` (`modules/nixos/renovate.nix`, `renovate-mint-token`), so the JWT comes from the same tool. `gh-token` 2.0.10, the version the locked nixpkgs ships, cannot make the three API calls this design needs, which is why they go through `curl`:
  - it builds every endpoint as `https://<hostname>…` (`internal/generate.go:101,139`, `internal/installations.go:79`, `internal/revoke.go:34`), so it cannot reach the rehearsal's plain-`http` fake forge;
  - its token request is a `POST` with no body (`internal/generate.go:140`), so it cannot restrict the token to a repository or to permissions;
  - without `--installation-id` it takes the first entry of `GET /app/installations?per_page=1` (`internal/generate.go:72-77,101`), not the App's installation on a given repository, and its `installations` command lists every installation rather than looking one up per repository.
  It can revoke (`gh-token revoke`), but only over `https`, so the revocation also uses `curl`, keeping all three calls on the endpoint derived from `origin` that the rehearsal points at its fake forge.
- **Secret shape**: the composed vanixiets secrets file stores `{ NAME: { data: { value } } }`; nixbot's script reads `.token.data.token`. The registry's entry point exports `data.value` secrets as variables (D3), and step 4 writes the shape the script reads, so neither the composer nor nixbot changes.
- **Exposure, stated plainly**: the PEM is in this run's sandbox for the whole run, in nixbot's read-only `/run/secrets.json` (A124) even after step 4 drops our copies. Code in that sandbox is our program, git, and `nix flake update`, which fetches inputs and evaluates their `inputs` declarations, answering "n" to `nixConfig`. Any effect declared on `main` could name these two secrets, because nixbot scopes secrets per repository, not per effect, and the registry's per-trigger `secrets` list is a convention that review enforces. Only collaborators can change `main`.
- **Provisioning**: two entries in `flake.lib.vanixietsEffectSecrets`, `FLAKE_UPDATER_APP_ID` (`line`) and `FLAKE_UPDATER_PRIVATE_KEY` (`multiline-hidden`), so the clan prompts, the composed file and the registry's `secrets` enum all gain them. The values move from `secrets/shared.yaml`. The composer's `--arg … "$(cat …)"` keeps the PEM's interior newlines and drops the trailing one, which PEM parsing tolerates; the rehearsal's key goes through the same shape.
- **Alternatives considered**: nixbot's forge token (`GitToken`), excluded by the Contents-write rule; a fine-grained PAT (long-lived, tied to a personal account, rejected as for CAM-106's D2); minting outside nixbot (the secrets file is snapshotted as a systemd credential at nixbot's start, `secrets.nix:100-110`, so a rotating token would need nixbot restarts).
- **Boundary**: source-versus-delivered. The secret declarations are source; their values exist only as the clan vars ciphertext and, on magnetite, the composed credential nixbot reads. Task 2.3 checks no key material entered the repository; task 7.2 reads the delivered key set on the host.

### D3: A `schedule` trigger kind in the effects registry (operator D-c)

- **Choice**: `triggers.schedule`, a submodule that imports the existing trigger options (`args`, `lock`, `secrets`, `forgeToken`) and adds:
  - `when`: `minute` (int or null), `hour` (int, list of ints, or null), `dayOfWeek` (list of `Mon`…`Sun`), `dayOfMonth` (list of ints), with null and empty values dropped before they reach hercules-ci-effects' own typed `when` option;
  - `checkout` (bool, default false), passed to `mkEffect` as `__nixbot_effect_checkout`.
  The renderer treats `schedule` like the event kinds: no main-only guard, no `--rev`, secrets exported from `.<NAME>.data.value`. `mkEffect` declares no `idTokenAudiences` for it. The interpreter maps each entry with a schedule trigger to `herculesCI.onSchedule.<entry>` with that `when` and one effect `outputs.effects.<entry>`. `requireTrigger`'s message and the header comment name the new kind.
- **Naming (operator decision, 2026-11-17)**: the effect is named after the entry, as `onPush` and `onEvent` effects are, so the entry `flake-update` is `onSchedule.flake-update.outputs.effects.flake-update` and the manual run is `nbo schedule run flake-update flake-update -f`.
- **Rationale**: one interpreter convention covers every effect, so the entry point, the per-trigger secrets map and the rehearsal gate hold for the scheduled effect too, and the private-repository reuse inherits them. The main-only guard reads an identity token whose event must be a push to `main`; a scheduled run's token says `schedule`, so the guard would refuse it, and scheduled effects are evaluated only from the default branch anyway (A122).
- **Lock**: the entry sets `lock = "flake-update"`. nixbot's sweep already runs one occurrence per schedule and effect at a time; whether it honours `lock` for a scheduled or manual run is unverified, so the design does not rely on it (see Risks).
- **Alternatives considered**: a direct `herculesCI.onSchedule.flake-update` declaration (the registry would no longer be the one interpreter, and nothing would pin the effect's secrets map or entry point).
- **Boundary**: vendored-versus-first-party. `onSchedule`'s option and `mkEffect` come from hercules-ci-effects; `__nixbot_effect_checkout` is nixbot's attribute, passed through `mkEffect`'s extra attributes to the derivation. The registry is first-party; `checks.effects-interpreter` evaluates the produced attributes rather than the source.

### D4: Arguments, branch names and identity (operator D-d)

- **Choice**: `flakeUpdate { perInput = true; updateBranch = "update"; excludeInputs = [ "playwright-web-flake" "nixpkgs" ]; forgeType = "github"; createPullRequest = true; autoMergeMethod = null; }`, `nixpkgs` only while its held update is blocked, everything else at its default (title `Update <input>`, body the lock diff, `nix = pkgs.nix`). The program sets `GIT_AUTHOR_NAME`, `GIT_AUTHOR_EMAIL`, `GIT_COMMITTER_NAME` and `GIT_COMMITTER_EMAIL` to `vanixiets-flake-updater[bot]` and `246545483+vanixiets-flake-updater[bot]@users.noreply.github.com`, which the script keeps (`setdefault`, A125). `when = { dayOfWeek = [ "Tue" "Fri" ]; hour = 22; minute = 0; }`, the workflow's cron in UTC.
- **Rationale**: `updateBranch = "update"` reproduces `update-<input>`, so a pull request the old updater left open is found (the 422 "already exists" answer) and updated rather than duplicated; none was open on 2026-11-17. The bot user id was read from the public `GET /users/vanixiets-flake-updater%5Bbot%5D`. The `flake-update` label is dropped because nothing reads it (only a commented line in `.github/mergify.yml`), and signoff because no rule requires it. `autoMergeMethod = null` leaves merge authorization with people.
- **Unchanged from today**: commits are made by git and pushed, so they are unsigned, as the action's were; no ruleset requires signatures on `update-*` branches.
- **Alternatives considered**: nixbot's default `flake-update-<input>` branches (orphans open pull requests); keeping a label through a post-step (no consumer).

### D5: Program placement

- **Choice**: `modules/effects/vanixiets/flake-update.nix` defines a function of `pkgs` and `nix` that builds the `flake-update` program (`writeShellApplication`, runtime inputs `git`, `curl`, `jq`, `gh-token`, `coreutils`), exposes it as `apps.flake-update` for `x86_64-linux`, and builds the rehearsal check from the same function with a stand-in `nix`. nixbot's script is reached through `(flakeUpdate { … }).effectScript`, the only form nixbot exports, a string naming the script and its configuration file in the store.
- **Rationale**: the effects are bound to `x86_64-linux` (magnetite). Building production and rehearsal from one function means they differ only in `nix`.
- **Boundary**: vendored-versus-first-party, as in D1.

### D6: The rehearsal runs the program against a fake forge

- **Choice**: `checks.x86_64-linux.flake-update-rehearsal`, after nixbot's `checks/effects-lib-flake-update.nix`: a local bare repository behind an `http://127.0.0.1:<port>` URL, a checkout set up as nixbot sets one up (its token in `origin` and in `insteadOf` entries), a fake API, a stand-in `nix` that rewrites `flake.lock` and commits, and a test RSA key generated in the build. The fake API serves the installation lookup (verifying the JWT's signature with the test key's public half and its `iss`), the token mint (checking the repository and permission restriction), pull-request creation (422 the second time) and token revocation, and logs every request. Cases:
  1. Two runs over a base whose lock has `nixpkgs`, `utils` and `playwright-web-flake`, with no input moving between them. After the first: `update-nixpkgs` and `update-utils` exist, one commit ahead of the base, authored and committed by the bot identity; no `update-playwright-web-flake`; every push and pull-request call used the minted token; `~/.git-credentials` holds the minted token. After the second: no branch head changed.
  2. Installation lookup answers 404: the program exits non-zero; no push, no pull-request call.
  3. After each run: no file in the checkout, its `.git` objects or `$HOME` contains a line of the test key, and the program's private directory is gone.
- **Rationale**: the registry requires every entry to name a rehearsal, and nixbot builds each scheduled effect's inputs on every pull-request and batch build for `nixbot/effects`, so the rehearsal gates merges. It runs nixbot's vendored script unmodified, so a nixbot bump that changes behaviour this design relies on fails here before it reaches `main`.
- **Integrity**: tasks 4.4 and 4.5 mutate a scratch copy (drop `excludeInputs`, drop the identity, skip the token-file step) and confirm each mutant fails, running only the case it must fail.
- **Cost**: a single `runCommand` with no NixOS evaluation, keyed only on static data, so it adds one attribute to `checks.x86_64-linux` and no host instantiation.

### D7: Cutover in this change (operator D-e)

- **Choice**: in the same pull request, delete `.github/workflows/update-flake-inputs.yaml`, the `update-flake-inputs` recipe, and the two `FLAKE_UPDATER_*` lines of `ghsecrets` in `justfile`, and update the live documentation that names them: the recipe row in `packages/docs/src/content/docs/reference/justfile-recipes.md`, the `secrets/shared.yaml` description in `packages/docs/src/content/docs/guides/secrets-management.md`, and the CI/CD pages (`about/contributing/ci-cd-setup.md`, `reference/ci-jobs.md`), including any sentence CAM-106's task 7.5 adds that points at the workflow. Dated notes, incident reports, ADRs and archived changes keep their references as historical record. After the effect's first successful run, the operator deletes the two GitHub repository secrets and the two `secrets/shared.yaml` keys. The App and its installation stay.
- **Rationale**: one updater at a time, with no window in which both the workflow and the effect write `update-*` branches. The old secrets outlive the merge only until the effect has proved itself, so a rollback can restore the workflow unchanged.
- **Gap at cutover**: the schedule registers after the first green `main` build that contains it (A122). If a Tuesday or Friday 22:00 falls between the merge and that build, the occurrence is lost; task 9.1 runs the effect by hand anyway.

### D8: Deployment touches magnetite only

- **Choice**: deploy magnetite after the merge so nixbot reads the recomposed `vanixiets-effects-secrets` file; the generator's `restartUnits = [ "nixbot.service" ]` restarts nixbot on that deploy. No other host's closure changes.
- **Ordering constraint**: the two prompts and their values enter the implementation chain together (task 2.2 runs straight after 2.1). A tree that declares the prompts without values makes the generator out of date for magnetite, and `clan machines update` regenerates missing generators for every machine before deploying, so such a tree could not deploy any host (as CAM-106's D3 records).

## Risks / Trade-offs

- [Risk] Early-stage upstream: `flakeUpdate` is one commit old, covered only against a fake forge, with no known `perInput` user, so we expect to find bugs → Mitigation: the rehearsal runs the vendored script; the first runs are watched by hand (9.1–9.5); fixes go upstream to Mic92/nixbot rather than into a local patch; the old secrets stay until a successful run, so reverting restores the workflow.
- [Risk] The schedule registers only after a green non-pull-request `main` build, and a red `main` keeps the previous definition → Mitigation: task 7.3 confirms registration after the landing build; a run can always be started by hand.
- [Risk] No catch-up: an occurrence missed while nixbot is down for more than five minutes is lost → accepted for a twice-weekly refresh; `nbo schedule run flake-update flake-update -f` recovers it.
- [Risk] Waves of up to 45 pull requests against gitea-mq's `batchMax = 20`, which also fire the `PullRequestQueueWaitBurn` warning, as today's waves do → accepted; unchanged from the workflow's behaviour, and gitea-mq bisects failing batches. Task 9.2 records the alerts each wave posts.
- [Risk] The App key sits in the sandbox for the run, and any `main` effect could name it (A124) → accepted as stated in D2; the token itself is narrowed to one repository and two permissions and revoked at exit.
- [Risk] A manual run overlapping a scheduled one: nixbot deduplicates sweep runs but gives a manual run its own key, and may not honour `lock` for scheduled effects [INFERENCE] → both runs compute the same branches from the same base and force-push identical trees, and the second pull-request call is answered "already exists"; the operator avoids manual runs at 22:00 on Tuesday and Friday.
- [Risk] An upstream tag moved on a tag-pinned input would make both updaters touch that input → rare; task 9.7 checks the split, and listing the input in `excludeInputs` closes it.
- [Risk] A nixbot bump changes the script's behaviour → the rehearsal fails on the bump's pull request; A125 names the revision it was checked at.
- [Trade-off] Pull request titles and bodies change from the action's format (`Update <input>` and the lock diff) and lose the label → accepted; nothing matches on them.
- [Trade-off] The workflow's manual `exclude_patterns` and `auto_merge` inputs are gone; a manual run takes no parameters → accepted; neither was used.
- [Risk] nixbot's script also hands the minted token to nix as its `access-tokens` entry for `github.com`, so every input fetch uses a token restricted to this repository; GitHub serves public repositories to any valid token [INFERENCE] → task 9.1 observes the fetches succeed; if they do not, step 3 of D2 drops the repository restriction and keeps the permission restriction.

## Migration Plan

1. Confirm the App's permissions and installation with its own JWT, and the bot user id (group 1).
2. In one sitting, declare the two effect secrets and populate them from `secrets/shared.yaml`, then route the vars files into the implementation chain (group 2).
3. Add the `schedule` trigger kind and its interpreter rows (group 3), the program and its rehearsal (group 4), and the `flake-update` entry (group 5).
4. Remove the workflow, recipe lines and documentation references (group 6).
5. Land the pull request (body: `Part of CAM-108.`) through nixbot and gitea-mq; deploy magnetite; confirm the schedule registered and the secrets were delivered (group 7).
6. Run the effect by hand and verify its pull requests, a landed batch, idempotence and the first scheduled occurrence (group 9).
7. After a successful run, delete the GitHub repository secrets and the `secrets/shared.yaml` keys (group 8).

Hosts: magnetite only.

Rollback: before step 7, revert the pull request and deploy magnetite. The workflow returns with its secrets still in place, and the schedule disappears at the next green `main` build. After step 7, the rollback also needs `just ghsecrets` with the keys restored to `secrets/shared.yaml` from the clan vars values.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record, one row per requirement in this change's three delta specs.
No row routes to a Gherkin scenario, so the change lays out no `.feature` file: the repository has no BDD runner, and every observable here is either a property of the evaluated flake (witnessed by `nix eval` and flake checks), a behaviour of the program against a fake forge (witnessed by the rehearsal), or an observation of nixbot and the forge (witnessed by the integration tasks as smoke tests).

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| The flake-input updater runs twice a week and on demand | `flake-input-refresh` | behavioral | build gate (interpreter rows) and smoke (nixbot, forge) | tasks 5.2, 7.3, 9.1, 9.5; the scenario "The build service is down at the scheduled time" rests on A123 and no task observes it |
| Each moved branch-tracking flake input gets an update pull request of its own | `flake-input-refresh` | behavioral | rehearsal and smoke (forge) | tasks 4.2, 9.1; "One input cannot be refreshed" by A125 and the rehearsal's reading of the vendored script, not by a live failure |
| The flake-input updater leaves the Playwright flake input and pinned flake inputs alone | `flake-input-refresh` | behavioral | rehearsal and smoke (forge) | tasks 4.2, 4.4, 9.1, 9.7 |
| Each branch-tracking flake input has at most one open update pull request, and a stale one is withdrawn | `flake-input-refresh` | behavioral | rehearsal and smoke (forge) | tasks 4.2, 9.3, 9.4; "The repository already has the update" rests on A125 and is observed only if it occurs, recorded as pending otherwise |
| The flake-input updater acts under its own forge application with expiring credentials | `flake-input-refresh` | behavioral | rehearsal, smoke (forge) and operator record | tasks 1.1, 1.2, 1.3, 4.2, 9.1 |
| Merge authorization for flake-input updates stays with people | `flake-input-refresh` | behavioral | build gate (configuration) and smoke (forge) | tasks 4.1, 9.2 |
| Flake-input refreshes use no hosted runner | `flake-input-refresh` | behavioral | content search and smoke (forge) | tasks 6.1, 9.6 |
| The scheduled update is declared from the repository with a fixed schedule | `flake-input-refresh-interface` | interface | build gate (interpreter rows) | tasks 3.2, 5.2 |
| The scheduled effect gets a checkout and no identity token, and runs only on its schedule | `flake-input-refresh-interface` | interface | build gate (interpreter rows) | task 5.2 |
| A scheduled run receives exactly the application id and key | `flake-input-refresh-interface` | interface | build gate (interpreter rows) and host read | tasks 2.1, 5.2, 7.2 |
| A schedule trigger's entry point is unguarded and fails closed on a missing secret | `flake-input-refresh-interface` | interface | build gate (interpreter rows, negative control) | tasks 3.2, 3.3 |
| A run mints its own installation token from the application key | `flake-input-refresh-interface` | interface | rehearsal | tasks 4.2, 4.5 |
| The minted token reaches nixbot's script through a private file, and the key leaves no copy | `flake-input-refresh-interface` | interface | rehearsal and content search | tasks 2.3, 4.2, 4.5 |
| The update script runs one input at a time with fixed arguments | `flake-input-refresh-interface` | interface | build gate (configuration read) and rehearsal | tasks 4.1, 4.2, 4.4 |
| Commits carry the forge application's bot identity | `flake-input-refresh-interface` | interface | rehearsal and smoke (forge) | tasks 4.2, 4.4, 9.1 |
| The rehearsal is part of the pre-merge effects gate | `flake-input-refresh-interface` | interface | build gate and smoke (pull-request status) | tasks 4.3, 7.1 |
| No hosted workflow refreshes flake inputs | `flake-input-refresh-interface` | interface | content search | task 6.1 |
| This capability states its own trust boundary | `flake-input-refresh-interface` | interface | capability text | specs text, task 6.3 |
| A122–A127 | `world-assumptions` | world | violation-condition witness | each its own scenario; A125 and A127 are also observed in tasks 4.2 and 9.7 |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | designation table and its lint | the table itself; task 9.9 re-merges it before archive |

No row carries an `est-property`, `est-contract` or `est-symbolic` modality, so the change carries no executable-specification-testing obligation.

## Open Questions

- None blocking. Whether nixbot honours `lock` for scheduled and manual runs is left to observation (Risks); it changes nothing in the design.
- Ordering with CAM-106: either change may archive first. This change's `world-assumptions` delta carries CAM-106's designation rows plus `hosted runner`; whichever archives second re-merges the table (task 9.9).
