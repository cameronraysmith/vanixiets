---
linear_story_id: CAM-129
linear_story_identifier: CAM-129
linear_story_title: "Confine clan secrets to one seam so features and homes stop reading clan vars"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-129/confine-clan-secrets-to-one-seam-so-features-and-homes-stop-reading
linear_story_state: Todo
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Todo
last_synced_at: "2026-11-26T22:58:21Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T22:58:21Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-129 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
---

## Why

Every feature that needs a secret declares and reads clan's vars generators directly: 55 files under `modules/` name `clan.core.vars`, features read each other's generators (`nixos/nixbot.nix:269` reads niks3's token, `nixos/matrix.nix:345` reads kanidm's), and homes read the host's clan configuration (`home/development/vcs-signing.nix:22-27`, `home/ai/omnigent/credentials.nix:102-177`). Clan-core is in maintenance mode, so a later den layer or a replacement for clan vars would have to edit all of those files at once. A single seam that is the only writer and reader of clan vars confines clan to two files and makes that later swap a two-file change.

## What Changes

**Secret declaration and consumption**
- From: each feature writes `clan.core.vars.generators.<name>` and each consumer reads `clan.core.vars.generators.<name>.files.<f>.path`, knowing the owning feature's generator and file names.
- To: a feature declares `vanixiets.secrets.<name>` and consumers read the delivered path from that option; one secrets module translates declarations into clan generators. `<name>` stays the generator name.
- Impact: non-breaking; no host's or home's built system changes.

**Secrets in homes**
- From: home modules read `osConfig.clan.core.vars.generators` and clan's sops secret naming.
- To: `hm-sops-bridge` propagates a read-only home view of the secrets a home uses, next to the age key it already propagates; a standalone home sees no view, as it sees `osConfig == null` today.
- Impact: non-breaking for both bridged and standalone homes.

**Delivery**
- The secrets module lands first with no consumer. Then one feature moves per step, its declaration and all its readers together, each step proven by a before/after diff showing no change to any NixOS, nix-darwin or home toplevel or any check. A rule that no module outside the two seam files names `clan.core.vars` arrives in the last step.
- Preserved in every step: generator names, file names, scripts and prompts, owner, group, mode, `neededFor`, `restartUnits`, `share`, `validation` and dependencies. Five VM tests and `checks/greptimedb-envelope.nix` run magnetite's real `greptimedb-users` generator, so changing any of these changes what they test.

**Non-goals**: replacing clan; renaming any generator or moving anything under `vars/`; changing who can decrypt any secret; reading committed public vars values, which stop-reading-other-hosts-configs owns.

**Depends on** (lands last in the den-ready-fleet order)
- establish-refactor-oracle: the before/after drvPath diff (`just drv-diff`) that proves each step unchanged.
- stop-reading-other-hosts-configs: the committed-vars accessor `modules/lib/vars.nix`, the second of the two files clan is confined to, and `modules/lib/host-keys.nix`. It migrates the committed-path reads `lib/commit-signing.nix:166` and `lib/shared-vars-recipients.nix:45` to the accessor. It leaves the generator-tree reads `lib/commit-signing.nix:191`, `lib/shared-vars-recipients.nix:43,55` and `host-keys.nix`'s own-host `openssh` comparison, which this change moves behind the seam.
- compose-hosts-from-cohesive-aspects: lands immediately before this change, because both edit magnetite's and cinnabar's feature files; this change rebases onto it and re-runs `just drv-diff`.

**Open design questions** (to settle in design, after the dependencies land)
1. Should the option mirror clan's generator schema field for field, or cover only what this fleet uses and pass the rest through? A pass-through puts clan back into feature files.
2. Are the clan inventory services under `modules/clan/services/` on clan's side of the seam? At least `hermes-agent` and `openclaw`, which take generator names as settings, should name a secret instead.
3. Should the VM tests and `greptimedb-envelope` read `greptimedb-users` through the seam, which then has to expose the generation script, or stay declared clan readers that pin clan's own generator?
4. Is the `options ? clan.core.vars` guard in `darwin/omnigent-host.nix:519` still needed once every nix-darwin host has the option?
5. Before the last step, should a shrinking allow list of files still naming `clan.core.vars` be enforced, or nothing until the full rule can pass?
6. Which feature moves first? Recommended: niks3 → nixbot or kanidm → matrix (a single cross-feature read each); `greptimedb-users` only after question 3.
7. Do the obligation readers in `lib/` (`commit-signing.nix:191`, `shared-vars-recipients.nix:43,55`, `host-keys.nix`'s `openssh` comparison) read the seam's read-only view of the host they check, or move into the secrets module?

## Capabilities

### New Capabilities

- `secret-consumption-seam` (stratum: behavioral): a feature names the secrets it owns and the secrets it uses without naming the backend that produces them; moving a feature behind the seam leaves every delivered secret's location, contents, readers, permissions and restart behaviour unchanged; a home receives its secrets from its host without reading the host's configuration; replacing the secret backend changes only the seam.
- `secret-consumption-seam-interface` (stratum: interface): the `vanixiets.secrets.<name>` option on the NixOS and nix-darwin classes, its translation into `clan.core.vars.generators.<name>`, the home-side view propagated by `hm-sops-bridge`, and the structural rule confining `clan.core.vars` to the seam files. Trust boundary: the structural rule reads source text under `modules/` and cannot see an attribute path built from strings at evaluation time; the drvPath diff shows that evaluated outputs are unchanged, not that the secrets clan generates and deploys at runtime are unchanged; clan still generates, encrypts and deploys every secret, and nothing here checks clan's behaviour.

### Modified Capabilities

- `world-assumptions` (stratum: world): designations for secret, secret backend, generator (clan sense) and secret seam; an assumption recording that clan-core is in maintenance mode (an operator statement, not observed in the repository) and one recording clan's sops naming `vars/<rel_dir>/<file>`, which homes depend on today. Assumption ids come from A360-369.

## Impact

- Code: a new secrets module for the NixOS and nix-darwin classes; `modules/nixos/hm-sops-bridge.nix`; over the steps, about 45 of the 55 files that name `clan.core.vars`, among them `nixos/{niks3,nixbot,kanidm,matrix}.nix`, `darwin/{ssh-ca-trust,omnigent-host}.nix`, `home/development/vcs-signing.nix`, `home/ai/omnigent/credentials.nix`, `lib/{commit-signing,shared-vars-recipients,host-keys}.nix` and the clan services under `clan/services/`; a new structural check.
- Hosts: every NixOS and nix-darwin host evaluates the new option; no built system changes.
- Existing seam reused: `nixos/fleet-deployer.nix:148-151` (`notifyTokenFile`) already hides `ntfy-alerter` behind an option and becomes a reader of the new one.
