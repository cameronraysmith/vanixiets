---
linear_story_id: CAM-129
linear_story_identifier: CAM-129
linear_story_title: "Confine clan secrets to one seam so features and homes stop reading clan vars"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-129/confine-clan-secrets-to-one-seam-so-features-and-homes-stop-reading
linear_story_state: Done
linear_team: CAM
linear_project: den-ready-fleet
last_synced_state: Done
last_synced_at: "2026-11-28T01:53:09Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-26T22:58:21Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-129 created in Todo in project 06049a4f18a4 (Den-ready fleet architecture), no label, with description seeded from proposal.md's Why and What Changes; state and project confirmed by read-only view; bind comment posted" }
  - { at: "2026-11-28T01:52:30Z", transition: "archive->mirror", outcome: "posted", note: "Documents in project Den-ready fleet architecture (06049a4f18a4): OpenSpec: secret-consumption-seam (0e4ee73d) and secret-consumption-seam-interface (dd3e50dc) created; ids stored in openspec/linear.yaml" }
  - { at: "2026-11-28T01:52:30Z", transition: "archive->mirror", outcome: "dropped", note: "world-assumptions (69e977af) not updated: it is listed in defaults.archive_documents.unmirrored, and the synced spec is 273373 characters, over Linear's 250000-character document limit; the document still holds an earlier archive's copy" }
  - { at: "2026-11-28T01:53:09Z", transition: "In Progress->Done", outcome: "posted", note: "Catch-up in one transition: the intermediate transitions (Todo->In Progress, In Progress->In Review) were not recorded in this ledger, and Linear read In Progress before the transition. Archived after all 81 tasks were done and secret-consumption-seam, secret-consumption-seam-interface and world-assumptions were synced (8 designation rows added to main's 369-row table, A360-A364 added); verify.md records no In Review gate decision; no review.md. Workspace confirmed by linear auth whoami; state confirmed Done by read-only view; catch-up comment posted" }
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
- To: `hm-sops-bridge` propagates a read-only home view of the secrets a home's user owns, next to the age key it already propagates, on NixOS hosts and, through a darwin export carrying only the view, on nix-darwin hosts, for every home user; a standalone home sees no view, as it sees `osConfig == null` today.
- Impact: non-breaking for both bridged and standalone homes.

**Delivery**
- The secrets module lands first with no consumer. Then thirteen pull requests move one closed set of secrets each, its declarations and all its readers together, each step proven by a before/after diff showing no change to any NixOS, nix-darwin or home toplevel or any check outside the step's declared differences. A rule that no module outside the two seam files names `clan.core.vars`, except the named tests and checks that run a generator's recipe, shrinks with every step and reaches its final list in the last step.
- Preserved in every step: generator names, file names, scripts and prompts, owner, group, mode, `neededFor`, `restartUnits`, `share`, `validation` and dependencies. Five VM tests and `checks/greptimedb-envelope.nix` run magnetite's real `greptimedb-users` generator, so changing any of these changes what they test.

**Non-goals**: replacing clan; renaming any generator or moving anything under `vars/`; changing who can decrypt any secret; reading committed public vars values, which stop-reading-other-hosts-configs owns (`flake.lib.vars` and `flake.lib.hostKeys` keep their names and readers); host identity in homes, such as `vcs-signing.nix`'s machine-name read.

**Depends on** (lands last in the den-ready-fleet order)
- establish-refactor-oracle: the before/after drvPath diff (`just drv-diff`) that proves each step unchanged.
- stop-reading-other-hosts-configs: the committed-vars accessor `modules/lib/vars.nix`, the second of the two files clan is confined to, and `modules/lib/host-keys.nix`. It migrates the committed-path reads `lib/commit-signing.nix:166` and `lib/shared-vars-recipients.nix:45` to the accessor. It leaves the generator-tree reads `lib/commit-signing.nix:191`, `lib/shared-vars-recipients.nix:43,55` and `host-keys.nix`'s own-host `openssh` comparison, which this change moves behind the seam.
- compose-hosts-from-cohesive-aspects: lands immediately before this change, because both edit magnetite's and cinnabar's feature files; this change rebases onto it and re-runs `just drv-diff`.

**Design questions** (settled in design.md)
1. Should the option mirror clan's generator schema field for field, or cover only what this fleet uses and pass the rest through? Settled: only the fields the fleet uses, no pass-through (D2).
2. Are the clan inventory services under `modules/clan/services/` on clan's side of the seam? Settled: no; they declare and read through the seam like any feature, and their generator-name settings keep their names (D6).
3. Should the VM tests and `greptimedb-envelope` read `greptimedb-users` through the seam, which then has to expose the generation script, or stay declared clan readers that pin clan's own generator? Settled: they stay named clan readers, with `clan-test-vars-fixture.nix` (D8).
4. Is the `options ? clan.core.vars` guard in `darwin/omnigent-host.nix:519` still needed once every nix-darwin host has the option? Settled: yes, for clan-free fixtures, once, in the secrets module (D3).
5. Before the last step, should a shrinking allow list of files still naming `clan.core.vars` be enforced, or nothing until the full rule can pass? Settled: a shrinking allow list from the first step (D9).
6. Which feature moves first? Settled: build cache and CI (niks3, nixbot) after the seam; `greptimedb-users` in the telemetry-store step (D10).
7. Do the obligation readers in `lib/` read the seam's read-only view of the host they check, or move into the secrets module? Settled: per-name readers read the option; the two whole-tree obligations read `flake.lib.secretsBackend.generatorsOf`, a second clan reader in the seam file (D7).

## Capabilities

### New Capabilities

- `secret-consumption-seam` (stratum: behavioral): a feature names the secrets it owns and the secrets it uses without naming the backend that produces them; moving a feature behind the seam leaves every delivered secret's location, contents, readers, permissions and restart behaviour unchanged; a home receives its secrets from its host without reading the host's configuration; replacing the secret backend changes only the seam.
- `secret-consumption-seam-interface` (stratum: interface): the `vanixiets.secrets.<name>` option on the NixOS and nix-darwin classes, its translation into `clan.core.vars.generators.<name>`, the home-side view propagated by `hm-sops-bridge`, and the structural rule confining `clan.core.vars` to the seam files. Trust boundary: the structural rule reads source text under `modules/` and cannot see an attribute path built from strings at evaluation time; the drvPath diff shows that evaluated outputs are unchanged, not that the secrets clan generates and deploys at runtime are unchanged; clan still generates, encrypts and deploys every secret, and nothing here checks clan's behaviour.

### Modified Capabilities

- `world-assumptions` (stratum: world): designations for secret, secret backend, generator (clan sense) and secret seam; an assumption recording that clan-core is in maintenance mode (an operator statement, not observed in the repository) and one recording clan's sops naming `vars/<rel_dir>/<file>`, which homes depend on today. Assumption ids come from A360-369.

## Impact

- Code: a new secrets module for the NixOS and nix-darwin classes; `modules/nixos/hm-sops-bridge.nix`, which gains a darwin export; over thirteen pull requests, about 45 of the 55 files that name `clan.core.vars`, among them `nixos/{niks3,nixbot,kanidm,matrix}.nix`, `darwin/{ssh-ca-trust,omnigent-host}.nix`, `home/development/vcs-signing.nix`, `home/ai/omnigent/credentials.nix`, `lib/{commit-signing,shared-vars-recipients,host-keys}.nix` and the clan services under `clan/services/`; a new structural check.
- Hosts: every NixOS and nix-darwin host evaluates the new option; no built system changes.
- Existing seam reused: `nixos/fleet-deployer.nix:148-151` (`notifyTokenFile`) already hides `ntfy-alerter` behind an option and becomes a reader of the new one.
