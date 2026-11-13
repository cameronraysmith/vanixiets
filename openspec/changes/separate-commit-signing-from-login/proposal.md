---
linear_story_id: CAM-100
linear_story_identifier: CAM-100
linear_story_title: "Sign commits with a key that cannot log in"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-100/sign-commits-with-a-key-that-cannot-log-in
linear_story_state: In Progress
linear_team: CAM
linear_project: workstation-parity
last_synced_state: In Progress
last_synced_at: "2026-11-14T00:38:41Z"
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-13T21:45:51Z", transition: "Backlog->Todo", outcome: "posted", note: "Issue CAM-100 created in Todo in project 69d5244a4e10 with description seeded from proposal.md; binding, state, project and labels confirmed by read-only view" }
  - { at: "2026-11-14T00:38:41Z", transition: "Todo->In Progress", outcome: "posted", note: "apply gate: first tasks.md checkboxes; description replaced with the clan-vars design from proposal.md (Why and What Changes); state and description confirmed by read-only view" }
---

## Why

Omnigent's execution boundary is being hardened in a documented order: dedicated worker accounts first, sandbox enforcement second (`docs/notes/development/omnigent/deployment-plan.md:199`, `:335`).
The first step moved agent sessions off the `cameron` account (commits d20ae8599 and a28464344), and workers receive only `ssh-signing-key`, never the owner's sops bundle (`:974`).
The deployment plan states that a worker identity grants no personal age identity (`:856`), but each person's commit-signing key is the same key pair as their login key, whose `ssh-to-age` image is their sops and clan-vars decryption identity (`:854`); Cameron's also opens a root login on every NixOS host, and the enrollment check (`expected.signingPublicKey = head meta.sshKeys`) requires each worker to hold it.
This change gives every person a separate signing key, so workers hold a credential that signs and does nothing else, and `:856` holds.
Reusing an authentication key for signing is permitted by GitHub and GitLab, and OpenSSH's signature namespaces keep a git signature from serving as a login signature (brainstorm, "Why a separate signing key here"), so the separation is not made for a cryptographic weakness.
It follows NIST SP 800-57 Part 1 Rev. 5 §5.2, "a single key shall be used for only one purpose", for two reasons that apply to this fleet: the key is also a decryption identity, the age recipient of 198 encrypted files (uses that interfere, reason 3), and unattended signing needs the key as a passphrase-less file in every human home and worker account, while login and decryption need few, tightly held copies (limiting damage on compromise, reason 2, which applies because of that distribution).
Radicle keeps the login key as its node identity, so the passphrase-less login key file remains on human homes after this change; a dedicated age identity per person is an option to weigh later.
On darwin, git signs through the Bitwarden agent, so an unattended commit waits on an unlocked vault and an authorization prompt; signing from a file through an agent-free program removes that wait.

## What Changes

**Signing key**
- From: each profile's commits are signed with the private half of its login key (sops `ssh-signing-key`), whose public half is `head meta.sshKeys` or a sops `ssh-public-key` placeholder.
- To: each profile records a dedicated `meta.signingKey` whose public half no host authorizes for login and no secret is encrypted to, and keeps its old key in `meta.retiredSigningKeys`.
  The key pair is made by one clan vars shared generator per person, `<person>-commit-signing-key` (`share = true`), whose script runs `ssh-keygen`; its secret file `key` holds the private half and its public file `key.pub` (`secret = false`) the public half, which `meta.signingKey` reads from `vars/shared/<person>-commit-signing-key/key.pub/value`.
  No key is made by hand, and rotation is `clan vars generate --regenerate`.
  The one exception is `ubuntu`, a standalone home on no clan machine, which keeps a home-manager sops entry `commit-signing-key` holding an already generated key.
- Reason: a signing key that admits no login and opens no secret can be given to agents; one generated source serves the person's homes and workers alike.
- Impact: every clan profile but raquel gets a generated key (Cameron, Janette, christophersmith, tara), each registered as a GitHub signing key where the person has a GitHub account; every machine carrying a person's home or worker becomes a recipient of that person's key, except blackphos, which has no clan machine key yet.
  blackphos is the one machine named in `flake.lib.commitSigningLegacyMachines`: it declares no generator, its homes (crs58, raquel) sign with the login key file through the agent-free program as a recorded transitional state, raquel, whose only host it is, gets no new key in this change, and enrolling blackphos is a prerequisite of the phase B cutover.

**Signing mechanism**
- From: git signs through the agent on darwin and with the key file on Linux; jj signs with the key file through `ssh-keygen` on `PATH`, which consults `SSH_AUTH_SOCK` first.
- To: one home module, `vcs-signing`, sets git and jj to sign with the generated key's delivered file (read through `osConfig` from the machine's generator; ubuntu's from its sops entry) through one program that unsets `SSH_AUTH_SOCK` before running nixpkgs' `ssh-keygen`; git's darwin branch is removed.
- Reason: no commit waits on a vault or a prompt, on either laptop.
- Impact: darwin git stops using the Bitwarden agent; the Bitwarden agent keeps serving SSH login.

**Verification**
- From: `allowed_signers` rendered per profile from a sops placeholder (ubuntu by literal).
- To: rendered by `vcs-signing` from the profile: the signing key, and each retired key with `valid-before` once the cutover is fixed; the principal stays `vcs.author.email`.
- Reason: public halves are not secret, and old commits keep verifying in git.

**Workers**
- From: `expected.signingPublicKey = head meta.sshKeys`, and worker vars holding the owner's login key, filled by hand through `sops -d --extract | clan vars set` (`docs/notes/development/omnigent/deployment-plan.md:974-982`).
- To: `expected.signingPublicKey = meta.signingKey`, and the worker generator `omnigent-<owner>-signing-key` keeps its name, file, owner, mode and delivered path but takes its key from the owner's `<person>-commit-signing-key` through `dependencies` instead of a hidden prompt; the manual pipeline is retired.
- Impact: the enrollment check passes only with the new key; regenerating the person's generator regenerates every worker copy in the same run; the login key leaves every worker's delivered files at the next deploy of magnetite, pyrite and stibnite.

**Regulation**
- New fleet obligations `flake.lib.commitSigningObligations`, asserted by every existing machine check, that enumerate every login-authorization source of the evaluated host and require no profile's signing key in any, bind every human home's git and jj signing to the key file and the agent-free program, and bind every worker's declared signing key to its owner's.
- One new check attribute, `checks.x86_64-linux.commit-signing-key`, holding the profile-level relations, the predicates' controls and mutants, the program's agent test, and the comparison of each signing key's age image with every sops recipient.

**Removals**
- git's darwin signing branch, the sops `allowed_signers` templates and `ssh-public-key` declarations in five profiles, ubuntu's literal signers file, git and jj references to `ssh-signing-key`, the worker signing generator's hidden prompt and the deployment plan's manual signing pipeline, and, in phase B, the login key's GitHub signing registrations.

Login authorization, the login key, Radicle's identity and the signer principal are unchanged.

## Capabilities

### New Capabilities

- `commit-signing-key` [behavioral]: every commit by a person or by an agent acting for them is signed, without interaction, by that person's signing key, which admits no login on any host and opens no secret; agents hold no key that admits a login; a forge marks every commit verified throughout the migration; and commits signed before the cutover keep verifying.
- `commit-signing-key-interface` [interface]: the profile's `signingKey` and `retiredSigningKeys`, the `vcs-signing` home module and its agent-free program, the rendered `allowed_signers`, the worker's declared signing key, the `commitSigningObligations` cases over every login-authorization source and every home, and the `commit-signing-key` check.

Trust boundary of `commit-signing-key-interface`: its properties hold of evaluated NixOS, nix-darwin and home-manager configurations, of the files activation delivers from them, of the public halves recorded in profiles, and of the sops recipients recorded in this repository.
They do not establish that a delivered private key file is the private half of the recorded public key (the worker enrollment check and the delivered-path smoke tasks observe that), that no `~/.ssh/authorized_keys` file edited by hand on a host carries a signing key, anything about the login key itself, whose rotation is a later optional hardening step, that a forge holds a given signing registration, or that `valid-before` bounds anything beyond the time a commit claims (A91).
stibnite's worker home is a standalone home-manager generation that `checks.aarch64-darwin.darwin-stibnite` cannot read; its signing key is covered through the system-level worker declaration and the shared credential module.

### Modified Capabilities

- `commit-author-identity-interface` [interface]: the requirement `The signer principal is the author address` changes its key source from a per-profile sops placeholder or literal to the profile's `signingKey`, and `A worker's author is its owner's profile, set by the host` changes `expected.signingPublicKey` from `head meta.sshKeys` to `meta.signingKey`.
  This capability is introduced by the unarchived `unify-vcs-author-identity` change; this change archives after it.
- `world-assumptions` [world]: adds designations for public key, private key, signing key, login key, retired signing key, cutover, login authorization, key agent, decryption identity, forge account, signing registration, verified mark and interaction, carries `remote-login credential`, `remote shell` and `password vault` and the author-identity rows this change's requirements use, and adds A91 (git verifies at the time a commit claims), A92 (jj verifies at the time of verification), A93 (`ssh-keygen` signs through an agent that holds the key), A94 (GitHub's verified mark follows signing registrations and persists once given) and A95 (`ssh-to-age` maps a key pair to one age identity).

## Impact

Code: `modules/home/users/lib.nix`, the six `modules/home/users/*/meta.nix` and `default.nix` profiles, a new `modules/home/development/vcs-signing.nix`, `modules/home/development/{git,jujutsu}.nix`, `modules/home/core/bitwarden.nix` (comment), a new `modules/lib/commit-signing.nix`, a new system module declaring each person's generator on NixOS and nix-darwin, `modules/home/ai/omnigent/credentials.nix` (`mkDelivery`'s signing generator), `modules/checks/machines.nix`, a new `modules/checks/commit-signing-key.nix`, `modules/clan/inventory/services/omnigent.nix`, `modules/lib/omnigent-fleet-obligations.nix` and `modules/checks/omnigent-workers.nix`.
The inert login-key literal in `modules/clan/inventory/services/emergency-access.nix` delivers nothing and is left for a separate change.
Secrets: new clan vars `vars/shared/<person>-commit-signing-key/{key,key.pub}` for crs58, janettesmith, christophersmith and tara, regenerated ciphertext under `vars/shared/omnigent-{cameron,janettesmith}-signing-key/key`, a `commit-signing-key` entry in `secrets/home-manager/users/ubuntu/secrets.yaml`, and the `ssh-public-key` entries removed from the five human sops files; blackphos's first machine key and raquel's generated key follow in phase B.
Documentation: `modules/clan/services/omnigent/README.md` and a dated amendment in `docs/notes/development/omnigent/deployment-plan.md` retiring the manual signing pipeline.
Forge: new GitHub signing keys on `cameronraysmith` and `janetteasmith` before any deploy; removal of the login keys' signing registrations in phase B.
Hosts whose closures change at deploy: every host with a human home (cinnabar, electrum, galena, scheelite, magnetite, pyrite, argentum, blackphos, rosegold, stibnite), and the workers on magnetite, pyrite and stibnite.
Check attributes: `checks.x86_64-linux` gains `commit-signing-key`; no other attribute is added or renamed.
