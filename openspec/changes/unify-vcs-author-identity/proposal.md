---
linear_story_id: c4bf6d64-8d63-4d34-b49a-f7c6d1383d06
linear_story_identifier: CAM-98
linear_story_title: Unify VCS author identity
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-98/unify-vcs-author-identity
linear_story_state: In Progress
linear_team: CAM
linear_project: omnigent-magnetite
last_synced_state: In Progress
last_synced_at: "2026-11-09T01:28:33Z"
review_round: 0
attempt_log:
  - { at: "2026-11-09T01:14:48Z", transition: "Backlog->Todo", outcome: "posted", note: "created CAM-98 in Todo with seeded description; bind comment not posted" }
  - { at: "2026-11-09T01:28:33Z", transition: "Todo->In Progress", outcome: "posted", note: "task 1.1 ticked; transition comment not posted" }
---

## Why

A person's commit author is restated per profile, per worker and per credential policy, and each copy covers only what its originating commit needed.
As a result jj records an empty author name for five human profiles and for every Omnigent worker owned by Cameron, git records no name on those workers, and jj 0.47.1 refuses to push such commits.
A repository-local override hides the failure in one checkout only.
Deriving every author from the one person record removes the cause, not just the observed instance.

## What Changes

**Author derivation**
- From: git and jj author set by hand in some human profiles, defaulted to an empty string for jj in `modules/home/development/jujutsu.nix`, set as email only by the worker credential module, and set in full only for Janette's workers through `extraHomeModules`.
- To: one rule, `flake.lib.vcsAuthor meta = { name = meta.fullname; email = meta.gitEmail; }`, applied by one home-manager option `vcs.author = { name; email; }` (non-empty strings) that sets both git and jj `user`; human homes default it from their own profile, and the NixOS and Darwin worker adapters set it from the worker's owner.
- Reason: one source per person, no empty author, and git and jj agree.
- Impact: non-breaking for rendered values that are already correct; jj gains name and email for raquel, tara, christophersmith and ubuntu, a name for janettesmith, and Cameron's workers gain git and jj names.

**Worker owner**
- From: free-text `owner`, with identity data passed to the credential policy by hand and a hard-coded cameron-to-crs58 lookup in the fleet obligations.
- To: `owner` restricted to `flake.users` keys in the worker options and the clan interface, with the credential policy and the author both derived from that profile.
- Reason: tie a worker's identity to the person it runs for without a new field.
- Impact: every current owner value already qualifies; a non-profile owner now fails evaluation.

**Regulation**
- From: a Janette-only author binding with its own negative fixture in the fleet obligations.
- To: one `authorBinding` obligation over every Linux worker and eight inventory cases evaluated once in `omnigent-worker-inventory` (the `vcsAuthor` literal, the refusal of an owner that is not a profile key, and an `authorBound` control with five mutants), with no new check attribute.
- Reason: the per-person obligation could not catch Cameron's missing name.
- Impact: none outside the omnigent checks.

**Removals**
- The `janetteAuthor` `extraHomeModules` block, the hand-passed meta and `ownerMeta`, the worker credential module's `user.email` lines, the `mkDefault ""` jj author, and the hand-written `user` blocks in the six human profile files.
- After deployment, the repository-local `user.name` workaround in the omnigent-cameron checkout.

Signing, token selection, `expected.omnigentEmail` and the `git.sign-on-push` deprecation are unchanged.

## Capabilities

### New Capabilities

- `commit-author-identity` [behavioral]: every commit recorded for a person, by that person's own account or by an Omnigent worker acting for them, names that person with their recorded name and author address, never with an empty name, and verifies against the same address.
- `commit-author-identity-interface` [interface]: the derivation rule, the home-manager author option and its default, the owner type in the worker options and clan interface, the adapters' setting of the worker author, the signer principal, and the fleet obligation that regulates them.

Trust boundary of `commit-author-identity-interface`: its properties hold of evaluated NixOS, nix-darwin and home-manager configurations and of the files activation delivers from them.
They do not establish that a person's recorded name or address is correct, that a forge accepts the address, or that the configuration has been deployed to a given host.
They do not govern repository-local or environment author settings, which take precedence over account-level settings (world assumption A85), nor commits recorded while `user.name` was empty, which jj keeps refusing to push until they are re-authored (A84).
The Darwin worker home is a standalone home-manager generation the stibnite machine check cannot read; it is covered only through the shared module and adapter code the Linux workers exercise.
That no module other than `vcs-author` sets a human home's git or jj `user` is a review convention that no check verifies; worker homes are regulated by `authorBinding`.

### Modified Capabilities

- `world-assumptions` [world]: adds designations for author, author name, author address, sign-in address, profile (person and home senses), push, version-control tool, author setting and signer principal, adds a local sense of commit, and adds A84 (jj refuses to push a commit recorded while `user.name` was empty, and keeps refusing it after `user.name` is configured until it is re-authored) and A85 (repository-local and environment author settings take precedence over account-level ones).

No existing capability under `openspec/specs/` states commit-author requirements.
The unarchived `deploy-omnigent-magnetite` change's `omnigent-deployment-interface` states no author requirement either, and is not modified.

## Impact

Code: `modules/home/users/lib.nix`, a new `modules/home/development/vcs-author.nix`, `modules/home/development/{git,jujutsu}.nix`, the six `modules/home/users/*/default.nix` profiles, `modules/system/omnigent-worker-options.nix`, `modules/clan/services/omnigent/flake-module.nix`, `modules/nixos/omnigent-host.nix`, `modules/darwin/omnigent-host.nix`, `modules/home/ai/omnigent/credentials.nix`, `modules/clan/inventory/services/omnigent.nix`, `modules/lib/omnigent-fleet-obligations.nix` and `modules/checks/omnigent-workers.nix`.
Documentation: `modules/clan/services/omnigent/README.md` and a dated amendment in `docs/notes/development/omnigent/deployment-plan.md`.
Hosts whose closures change at their next deploy: magnetite, pyrite and stibnite (workers and human homes), and every host carrying one of the affected human profiles (argentum, blackphos, rosegold, galena, scheelite and any standalone home configuration).
No flake input, secret, Clan var or check attribute is added.
