---
linear_story_id: 044c9309-c322-4f73-9bb4-b8afbdb22f7b
linear_story_identifier: CAM-107
linear_story_title: "Retire legacy sops tooling and narrow operator-credential readers"
linear_story_url: https://linear.app/cameronraysmith/issue/CAM-107/retire-legacy-sops-tooling-and-narrow-operator-credential-readers
linear_story_state: Todo
linear_team: CAM
linear_project: workstation-parity
last_synced_state: Todo
last_synced_at: 2026-11-17T00:01:18Z
review_round: 0
max_review_rounds: 3
attempt_log:
  - { at: "2026-11-16T23:33:33Z", transition: "Backlog->Todo", outcome: "posted", note: "T1 bind; issue created in project workstation-parity at Todo, description seeded from this proposal, one comment posted" }
  - { at: "2026-11-17T00:01:18Z", transition: "Todo (description re-sync)", outcome: "posted", note: "description re-seeded after operator decisions Q28-Q32 and D25 (dev retired, hash-encrypt and npmbw removed); state unchanged" }
---

## Why

The `sops-*` recipes and `scripts/sops/*` were written for the arrangement before clan and were never migrated: one exits at its first line, two would overwrite `.sops.yaml` or a workstation's age keys, and one would replace stibnite's pinned host key.
Meanwhile operator credentials in `secrets/shared.yaml` are readable by a retired machine's host key, a machine that no longer exists, and three people who are not the operator.
Locally activated darwin hosts never receive their clan machine key, so a host that gains machine secrets fails activation with no hint of the remedy.
The docs still teach the old model, and nothing checks that the public keys the repository names still correspond.
Retiring the tooling now, narrowing who can read operator credentials, and adding a check and a guard closes these before the next host or key change trips them.

## What Changes

**Who can read operator credentials (first)**
- From: `secrets/shared.yaml` and `secrets/test.yaml` are encrypted to admin, dev, ci, admin-user, raquel-user, janettesmith-user, christophersmith-user and the stibnite, blackphos and orb-nixos host keys; `&stibnite` is stibnite's retired hardware and `&orb-nixos` a machine that no longer exists.
- To: the `&stibnite` and `&orb-nixos` anchors and their fileless host rules are removed; those files are readable by the offline recovery key and the operator identity only; the unused `&dev` key is retired from every rule, with the operator identity taking its place as the maintenance reader of the five other people's home secrets; recipients are re-applied with `just update-all-keys` and the narrowed files' data keys are renewed. Credential values are not rotated.
- Reason: operator credentials should be readable by the operator only, and no identity should read secrets for hardware or people that have no use for them.
- Impact: non-breaking for every consumer found (all are operator-run); raquel, janettesmith, christophersmith, ci and the darwin host keys lose access to these two files only; `&dev`, held only by the operator, leaves every file, which re-wraps every file under `secrets/` without changing who can read it.

**Legacy tooling retired**
- From: `sops-validate-correspondences`, `sops-update-yaml`, `sops-extract-keys`, `sops-sync-keys`, `sops-deploy-host-key`, `sops-rotate`, `hash-encrypt`, `verify-hash` and `scripts/sops/*`; a `setup-user` path that generates a random workstation age key; an `npmbw` alias that runs an unpinned Bitwarden client from npm.
- To: all deleted. `update-all-keys` stays. `provision-bridge-key` stays and never writes a plaintext private key into the repository tree. A workstation's key is always derived from the person's Bitwarden SSH key, documented as a procedure. Rotation is a documented procedure with clan and sops commands. nixpkgs' `bw` is the only Bitwarden client the tooling uses.
- Reason: the deleted items are broken, destructive, orphaned or unpinned against today's arrangement, and two conventions for one key is one too many.
- Impact: removes recipes, an app and an alias; the CD bootstrap job stops generating a throwaway key.

**Correspondence checked at commit time**
- From: no check; the only validator is broken.
- To: a flake check over public data fails when a user or machine anchor, a clan key, or a pinned darwin host key stops corresponding, when a file's recipients differ from its rule, or when an anchor is unclassified; NixOS hosts fail evaluation when a bridge key they use is not encrypted to them.
- Reason: drift is caught by nixbot on the push that introduces it, with no Bitwarden access.
- Impact: one new check on x86_64-linux; one evaluation assertion per NixOS host using the bridge.

**Darwin activation refuses to run without the machine key**
- From: `just activate` on a darwin host with machine secrets proceeds and fails in `sops-install-secrets`.
- To: activation stops first, naming `clan vars upload <host>`, when the host has a clan machine key in the repository and `/var/lib/sops-nix/key.txt` is missing or holds a different key.
- Reason: local darwin activation never installs the key; clan's upload does.
- Impact: argentum needs `clan vars upload argentum` when next online (operator).

**Documentation and orphans**
- To: every passage that teaches the old model is rewritten to the current architecture or deleted; `secrets/users/{admin-user,raquel-user}/*` and their rules are deleted after the operator confirms nothing needs migrating.

## Capabilities

### New Capabilities
- `secret-custody` (stratum: `behavioral`): who may read which of the fleet's secrets, that every public key the repository names corresponds to the person or machine it names, that a darwin host is not activated without its machine key, that provisioning never leaves a private key in the repository's working tree, one convention for a workstation's personal key, that maintenance tools never rewrite recipients or host identities from an external store, that narrowing readers keeps every reader still in use, and that the documentation describes only current procedures.
- `secret-custody-interface` (stratum: `interface`): the recipient rules and anchors in `.sops.yaml`, the `sops-correspondence` flake check and its controls, the `hm-sops-bridge` evaluation assertion, the guard in the `.#darwin` app, the stdin path of `provision-bridge-key`, and the absence of the retired recipes, scripts and app. Trust boundary: the machine controls what the repository declares, what evaluation and the check accept, and what the activation app and recipes do; it does not control what keys a host or workstation actually holds outside activation, what Bitwarden holds, earlier ciphertext in git history, or who already copied a credential value.

### Modified Capabilities
- `world-assumptions` (stratum: `world`): adds assumptions on clan's machine-key installation paths, clan-core's `sops.age.keyFile` default, sops-nix failing secret installation on an unreadable key file, ssh-to-age's deterministic conversion, sops' `updatekeys` keeping the data key, and the Bitwarden SSH item's key fields; the designation table gains the terms the new behavioral requirements use.

## Impact

Repository: `.sops.yaml`; every file under `secrets/` (recipients; `secrets/shared.yaml` and `secrets/test.yaml` also data key); `justfile` (six `sops-*` recipes, `hash-encrypt` and `verify-hash` deleted, `provision-bridge-key` rewritten, `bootstrap-setup-user` deleted); `scripts/sops/` deleted; `modules/apps/bootstrap/setup-user.{nix,sh}` deleted, `bootstrap.sh` hint; `Makefile`; `.github/workflows/cd.yaml` bootstrap steps; `modules/home/shell/aliases.nix` (`npmbw`); `modules/darwin/app.nix` (guard); `modules/system/ssh-known-hosts.nix` (darwin keys hoisted to a static attribute); `modules/nixos/hm-sops-bridge.nix` (assertion, header); new `modules/checks/sops-correspondence.nix`; `secrets/users/*` deleted after the operator check; the docs in design.md's documentation table.
Outside the repository: `clan vars upload argentum` (operator); one bridged NixOS host deployed to observe the re-wrapped files.
Related: CAM-100 (`separate-commit-signing-from-login`) separates the login key that is also `&admin-user`.
Out of scope: any Bitwarden client choice beyond the sops tooling using nixpkgs' `bw`, and any self-hosting; rotating credential values; the operator's `~/.config/sops/age/keys.txt`, including its now-inert `&dev` line.
