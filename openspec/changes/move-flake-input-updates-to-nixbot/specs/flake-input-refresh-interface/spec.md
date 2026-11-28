## ADDED Requirements

### Requirement: The scheduled update is declared from the repository with a fixed schedule

The flake's `herculesCI` output SHALL declare `onSchedule.flake-update` with the schedule `{ dayOfWeek = [ "Tue" "Fri" ]; hour = 22; minute = 0; }` and exactly one effect, `outputs.effects.flake-update`, produced by the vanixiets effects registry's `schedule` trigger kind from the registry entry `flake-update`.

#### Scenario: The declaration is evaluated

- **WHEN** `herculesCI.onSchedule` is evaluated from the flake
- **THEN** it has the attribute `flake-update` whose `when` is `{ dayOfMonth = null; dayOfWeek = [ "Tue" "Fri" ]; hour = [ 22 ]; minute = 0; }`, the value nixbot reads, which hercules-ci-effects' typed `when` option normalises from that schedule, and `outputs.effects` has exactly the attribute `flake-update`

#### Scenario: The registry entry declares no trigger

- **WHEN** a registry entry sets none of its triggers, `schedule` included
- **THEN** evaluation fails with a message naming every trigger kind, `schedule` among them

### Requirement: The scheduled effect gets a checkout and no identity token, and runs only on its schedule

The scheduled effect SHALL request nixbot's repository checkout (`__nixbot_effect_checkout` set) and SHALL declare no `idTokenAudiences`.
No `onPush` or `onEvent` effect SHALL be produced for the `flake-update` entry.

#### Scenario: The effect derivation is read

- **WHEN** `herculesCI.onSchedule.flake-update.outputs.effects.flake-update` is evaluated
- **THEN** it carries `__nixbot_effect_checkout` and no `idTokenAudiences`, and neither `onPush.default.outputs.effects` nor any `onEvent` kind has a `flake-update` attribute

### Requirement: A scheduled run receives exactly the application id and key

The scheduled effect's `secretsMap` SHALL be exactly `{ FLAKE_UPDATER_APP_ID = "FLAKE_UPDATER_APP_ID"; FLAKE_UPDATER_PRIVATE_KEY = "FLAKE_UPDATER_PRIVATE_KEY"; }`, with no forge token.
Both secrets SHALL be declared in `flake.lib.vanixietsEffectSecrets`, so they are prompted for, composed into the vanixiets effects secrets file and delivered to nixbot for `github:cameronraysmith/vanixiets`.

#### Scenario: The entry point runs with every secret available

- **WHEN** the `flake-update` entry point runs against a secrets file holding every vanixiets effect secret and nixbot's forge token
- **THEN** the program sees `FLAKE_UPDATER_APP_ID` and `FLAKE_UPDATER_PRIVATE_KEY` and no other vanixiets secret or forge token

### Requirement: A schedule trigger's entry point is unguarded and fails closed on a missing secret

The rendered entry point of a `schedule` trigger SHALL run no main-only guard, SHALL append no `--rev`, SHALL export each declared secret from `$HERCULES_CI_SECRETS_JSON` at `.<NAME>.data.value`, and SHALL exit non-zero before the program runs when a declared secret is absent, null or empty.

#### Scenario: A schedule entry point runs

- **WHEN** a synthetic entry's `schedule` entry point runs with its secrets present and no nixbot identity-token endpoint
- **THEN** the program runs with exactly the trigger's arguments, no `--rev`, and the trigger's secrets

#### Scenario: The key is missing

- **WHEN** the `flake-update` entry point runs against a secrets file lacking `FLAKE_UPDATER_PRIVATE_KEY`
- **THEN** it exits non-zero naming the secret, and the program does not run

### Requirement: A run mints its own installation token from the application key

The program SHALL derive the forge's API endpoint and the repository's owner and name from the checkout's `origin`, sign a GitHub App JWT with `FLAKE_UPDATER_APP_ID` and `FLAKE_UPDATER_PRIVATE_KEY`, look up the App's installation on that repository with `GET /repos/{owner}/{repo}/installation`, and mint an installation token for it.
It SHALL exit non-zero without pushing anything when the lookup or the minting fails, and the installation id SHALL NOT be a constant in the repository.

#### Scenario: A rehearsal run against a fake forge

- **WHEN** the rehearsal runs the program against a fake forge with a test App key
- **THEN** the fake forge receives the installation lookup with a JWT that verifies against the test key's public half and names the test App id, and every later push and pull-request call authenticates with the minted token and never with the checkout's token

#### Scenario: The App is not installed on the repository

- **WHEN** the installation lookup returns 404
- **THEN** the program exits non-zero, and the fake forge records no push and no pull-request call

### Requirement: The minted token reaches nixbot's script through a private file, and the key leaves no copy

The program SHALL write `{ "token": { "data": { "token": <installation token> } } }` to a file outside the checkout readable only by the run's user, and run nixbot's flake-update script with `HERCULES_CI_SECRETS_JSON` pointing at that file.
It SHALL write the key only to such a file, and remove it and unset both secret variables before nixbot's script starts.

#### Scenario: The key does not reach the checkout

- **WHEN** a rehearsal run finishes
- **THEN** no file in the checkout, its git objects or the run's home directory contains the test key, and the key file the program wrote no longer exists

### Requirement: The update script runs one input at a time with fixed arguments

The program SHALL run nixbot's `flakeUpdate` script configured with `perInput = true`, `updateBranch = "update"`, `excludeInputs = [ "playwright-web-flake" "nixpkgs" ]`, `forgeType = "github"`, `createPullRequest = true`, `autoMergeMethod = null`, `pullRequestTitle = null` and `pullRequestBody = null`, taken from the nixbot flake input the repository locks.
`nixpkgs` SHALL stay in `excludeInputs` only while its held update (Linear CAM-125: kernel 6.18.65 breaks pyrite's out-of-tree audio and Bluetooth modules) is blocked, because each run rebuilds and force-pushes every open update branch and would rebuild the held pull request; it SHALL be removed when that update is unblocked.

#### Scenario: The configuration is evaluated

- **WHEN** the configuration file the program passes to nixbot's script is read
- **THEN** it holds `perInput: true`, `updateBranch: "update"`, `flakes."."."excludeInputs": ["playwright-web-flake", "nixpkgs"]`, `forgeType: "github"`, `createPullRequest: true` and `autoMergeMethod: null`

#### Scenario: A rehearsal run with four inputs

- **WHEN** the rehearsal runs the program twice against a base whose lock file has the inputs `nixpkgs`, `playwright-web-flake`, `systems` and `utils`
- **THEN** after the first run the fake forge has branches `update-systems` and `update-utils`, each one commit ahead of the base, and pull-request calls for those two, and no `update-nixpkgs` or `update-playwright-web-flake`; the second run, with no input moved, changes no branch head

### Requirement: Commits carry the forge application's bot identity

The program SHALL set the git author and committer of every commit nixbot's script makes to `vanixiets-flake-updater[bot] <246545483+vanixiets-flake-updater[bot]@users.noreply.github.com>`.

#### Scenario: A rehearsal commit is read

- **WHEN** the rehearsal reads the head commit of `update-utils`
- **THEN** its author and committer are both that name and address

### Requirement: The rehearsal is part of the pre-merge effects gate

The `flake-update` registry entry's `rehearsals` SHALL include an `x86_64-linux` check that runs the same program, built by the same function with only the `nix` executable replaced by a stand-in, against a local fake forge, and fails when any scenario above that names the rehearsal does not hold.
As an input of the scheduled effect, it SHALL be built by every pull-request and merge-queue build that posts `nixbot/effects`.

#### Scenario: The rehearsal's expectations are broken

- **WHEN** a scratch copy drops `playwright-web-flake` from `excludeInputs`
- **THEN** the rehearsal fails naming the unexpected branch

### Requirement: No hosted workflow refreshes flake inputs

The repository SHALL contain no GitHub Actions workflow that updates `flake.lock`, and no `justfile` recipe that dispatches one.

#### Scenario: The repository is searched

- **WHEN** `.github/workflows/` and `justfile` are searched for `update-flake-inputs` and `flake.lock` updates
- **THEN** nothing is found

### Requirement: This capability states its own trust boundary

The properties above SHALL be read as guaranteeing only what the repository controls: the declared schedule, checkout request and secrets map, the entry point, the program's credential handling and arguments, the commit identity, and the rehearsal.
They SHALL NOT be read as guaranteeing when nixbot fires the schedule, how its sandbox isolates a run, the forge's token semantics, the App's installation or permissions, or whether a new revision builds.

#### Scenario: A guarantee outside the boundary is claimed

- **WHEN** a document cites this capability for a run having happened at a scheduled time or for the App's permission set
- **THEN** that claim rests instead on world assumptions `A122` and `A123`, or on the forge's own record of the App, and not on this capability
