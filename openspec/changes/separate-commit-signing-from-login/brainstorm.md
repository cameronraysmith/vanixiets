<!--
Raw capture of superpowers:brainstorming output.

This file captures the output of the brainstorming skill verbatim; it does not impose any structure.
The skill's natural output is usually a decision-log format (background → decision chain Q1-Qn → design trade-offs),
but the organization may vary depending on the conversation.

design.md is extracted from this file and reorganized into a structured design document.

Do not copy this file's content into design.md — design.md is an independent, reorganized artifact;
the two are complementary but do not overlap.
-->

# Brainstorm: separate-commit-signing-from-login

Session date: 2026-11-13.
This file is the decision log of a delegated research session, not of an interactive session with the user.
The user's decision was given as the session's brief; every other answer below was derived from the repository, from vendored source, or from public forge data, and the user's later answers to this session's questions are recorded under "Questions and accepted answers".

## The user's decision (brief)

Every commit, by a person or an agent, is signed without interaction by a dedicated signing-only key file that is authorized for login nowhere, under the signer principal the `unify-vcs-author-identity` change defines (the author address, `vcs.author.email`; for workers `credentials.expected.gitEmail`, equal to it by that change's spec).
Workers receive only that signing key, and the login key is removed from worker vars.
The Bitwarden agent serves only interactive SSH login, and git's darwin agent-signing branch goes away.
This is its own change, ahead of the workstation-parity program's SSH slice (`openspec/changes/workstation-parity/design.md` D6).

## Hardening sequence

This change is the next step of a documented hardening sequence for Omnigent's execution boundary.
Native sessions first ran as `cameron` without sandbox enforcement, and the execution boundary was the `cameron` account (`openspec/changes/deploy-omnigent-magnetite/proposal.md:45`, `specs/omnigent-deployment-interface/spec.md:74`).
The deployment plan fixed the order: dedicated user first, `enforce_sandbox` second (`docs/notes/development/omnigent/deployment-plan.md:199`, `:335`).
Commits d20ae8599 (2026-09-10, "prepare dedicated worker accounts") and a28464344 (2026-09-15, "migrate magnetite to personal workers") took the first step.
The plan records that private homes and mode `0400` do not isolate credentials from the same UID (`:948`), and that workers receive only `ssh-signing-key`, never the owner's sops bundle (`:974`).
Every agent that runs under the human account today, omp and Claude Code among them, can read the same key in that account's sops secrets, so moving agents into worker accounts narrowed what they can read.
One statement of the plan does not yet hold: `:856` says the worker identity grants no personal age identity, while `:854` records that a person's age recipient corresponds to their SSH public key with `sopsAgeKeyId` null, and the delivered `ssh-signing-key` is that SSH key, so by construction it is both the person's age identity and a login credential.
This change makes `:856` true.

## Why a separate signing key here

Reusing a login key for git signing is not, by itself, a weakness or a departure from forge guidance.
GitHub says "You can even upload your existing authentication key to GitHub to also use as a signing key" (https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) and "If you want to use the same SSH key for both authentication and signing, you need to upload it twice" (https://docs.github.com/en/authentication/connecting-to-github-with-ssh/adding-a-new-ssh-key-to-your-github-account).
GitLab says "You may use the same SSH keys for git+ssh authentication to GitLab and signing commit signatures as long as their usage type is Authentication & Signing" (https://docs.gitlab.com/user/project/repository/signed_commits/ssh/).
OpenSSH's signature format binds each signature to a namespace, which "prevents cross-protocol attacks caused by signatures intended for one intended domain being accepted in another" (https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.sshsig, lines 53-56), so a `git`-namespace signature cannot stand in for a login signature.

The reasons that do apply are NIST SP 800-57 Part 1 Rev. 5 §5.2 (https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-57pt1r5.pdf): "In general, a single key shall be used for only one purpose", for reasons including (2) "Limiting the use of a key limits the damage that could be done if the key is compromised" and (3) "Some uses of keys interfere with each other", whose example is one key pair used for both key transport (decryption) and digital signatures, where the two uses' retention requirements conflict.
The same publication lists the private signature key and the private authentication key as distinct key types.
Two facts of this fleet bring those reasons into play.

- Fact 1, reason (3): the login key is also a decryption identity; its `ssh-to-age` image is the age recipient of 198 encrypted files (F2), so signing and decryption share one private key.
- Fact 2, reason (2): custody differs by use. Signing must be unattended, so the signing key is copied as a passphrase-less file to every human home and to worker accounts, while root login and decryption need few, tightly held copies. The reason applies because of that distribution, not because login and signing differ as operations.

A key used only for signing can be distributed as widely as unattended signing requires without widening who can log in or decrypt.

## Background

One ed25519 key, `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+` (the login key below), is the first entry of `modules/home/users/crs58/meta.nix:10-14` `sshKeys`.
It is authorized for `crs58` on every NixOS host (`modules/system/admins.nix:20`), for `cameron` through the clan `user-cameron` instance (`modules/clan/inventory/services/users/cameron.nix:50`) on cinnabar, electrum, argentum, rosegold, galena, scheelite, magnetite and pyrite, for `crs58` on blackphos and stibnite (`modules/machines/darwin/blackphos/default.nix:137`, `modules/machines/darwin/stibnite/default.nix:133`), for `root` on every NixOS host as the union of wheel users' keys (`modules/system/admins.nix:24-30`), and for the initrd unlock shell (`modules/system/initrd-networking.nix:26`).
Its private half is the sops secret `ssh-signing-key` in `secrets/home-manager/users/crs58/secrets.yaml`, declared mode 0400 in `modules/home/users/crs58/default.nix:155-157`.
`modules/home/development/radicle.nix:21` moves that secret's path to `~/.radicle/keys/radicle`, so the same file is the Radicle node identity, and jj's `signing.key` (`modules/home/development/jujutsu.nix:190`) resolves to that path on every human home.
git signs with it on Linux (`modules/home/development/git.nix:33-34`) and, on darwin, through whatever agent `SSH_AUTH_SOCK` names, given the sops `ssh-public-key` file (`git.nix:31-32`), which `modules/home/core/bitwarden.nix:29-31` points at the Bitwarden socket.
Omnigent workers sign with `vars/shared/omnigent-<worker>-signing-key/key`, a hidden-prompt shared generator (`modules/home/ai/omnigent/credentials.nix:215-240`) filled by piping the owner's sops `ssh-signing-key` into `clan vars set` (`docs/notes/development/omnigent/deployment-plan.md:974-982`).
The worker's enrollment check requires that key's public half to equal `credentials.expected.signingPublicKey` (`modules/home/ai/omnigent/credentials.py:343-361`), which the inventory sets to `builtins.head meta.sshKeys` (`modules/clan/inventory/services/omnigent.nix:37`) and the fleet obligations restate (`modules/lib/omnigent-fleet-obligations.nix:212`).
So the enrollment check requires each worker to hold its owner's login key, which on Cameron's workers on magnetite, pyrite and stibnite is a credential that also opens a root login on every NixOS host and decrypts the 198 files of F2.

## Findings

F1: Janette's construction is the same.
Her worker generator `omnigent-janettesmith-signing-key` is filled from her sops `ssh-signing-key`, and her worker's expected public key is `head meta.sshKeys`, `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0` (`modules/home/users/janettesmith/meta.nix:11-13`; `openspec/changes/unify-vcs-author-identity/verify.md:371`).
That key is authorized for `janettesmith` on rosegold (`modules/machines/darwin/rosegold/default.nix:113`), and GitHub's public list of her signing keys titles it `sops-janettesmith-user-ssh age1mqfqckc` (`https://api.github.com/users/janetteasmith/ssh_signing_keys`, read 2026-11-13).

F2: every profile's login key is also that person's sops decryption identity.
`ssh-to-age` of the login key yields `age1vn8fpkmkzkjttcuc3prq3jrp7t5fsrdqey74ydu5p88keqmcupvs8jtmv8`, which is `&admin-user` in `.sops.yaml:10` and the clan user key of both `sops/users/crs58` and `sops/users/cameron`.
`ssh-to-age` of Janette's, Christopher's, Raquel's and Tara's `sshKeys` entries yields exactly `&janettesmith-user`, `&christophersmith-user`, `&raquel-user` and `&tara-user` (computed 2026-11-13).
198 files outside `.sops.yaml` carry the `admin-user` recipient, among them `vars/shared/openssh-ca/id_ed25519`, `vars/shared/otel-ca/ca.key`, `vars/shared/user-password-cameron/*`, `vars/shared/wifi.fleet/*`, the zerotier identities and `secrets/users/admin-user/*`.
A holder of the login key who can read this repository's ciphertext can therefore decrypt every one of them, which is why the signing key handed to workers must be a separate key pair.
The sshd CA is a host CA only (`modules/clan/inventory/services/sshd.nix`, clan-core `clanServices/sshd`), so it does not mint login certificates.

F3: the emergency-access key is not delivered.
`modules/clan/inventory/services/emergency-access.nix:9-12` sets `allowedKeys` with the login key, but clan-core's `clanServices/emergency-access/default.nix` (pinned `dbae21013aca57424620d06863cbfd2e4107352b`) declares no settings and only sets an initrd emergency password; `allowedKeys` belongs to clan-core's `admin` service, which this inventory does not instantiate.
`nixosConfigurations.cinnabar.config.users.users.root.openssh.authorizedKeys.keys` evaluated on 2026-11-13 holds the three `crs58` keys twice (from `crs58` and `cameron`) and no `camrn86@gmail.com` entry.
The setting is inert today; the spike's table (`logs/parity/ssh-identity-spike-q2-q4.md`, Q4) assumed otherwise.

F4: `ssh-keygen -Y sign` asks the agent first.
openssh-portable `ssh-keygen.c` `sig_sign` loads the public half from the `-f` path, asks the agent named by `SSH_AUTH_SOCK` whether it holds that key, signs through the agent if it does, and reads the private file only otherwise.
Bitwarden's agent answers list requests on a locked vault without prompting and prompts on sign requests (`logs/parity/bitwarden-ssh-agent.md:22-27`).
So a private key file alone does not keep signing off the agent: if the vault holds the same key, the agent signs and prompts.
The spike's statement that jj on stibnite "already" signs unattended with the file key holds only if stibnite's vault does not hold the login key, which contradicts the [INFERENCE] that darwin git signs through the vault with that key; one of the two is wrong, and neither was observed.

F5: jj and git differ on signature time.
git passes `-Overify-time=<signed payload's timestamp>` to `ssh-keygen -Y find-principals` and `-Y verify` (git `gpg-interface.c`, master, lines 499-501).
jj's ssh backend (`lib/src/ssh_signing.rs`, main) passes no verify time, so `ssh-keygen` judges validity at the time of verification; once a `valid-before` passes, `find-principals` matches nothing and jj reports the signature `Unknown` (it runs `check-novalidate`), not `Bad`.
jj 0.47.1 reads `signing.backends.ssh.program` (`ssh_signing.rs` `from_settings`), so jj can be pointed at a program other than `ssh-keygen` on `PATH`.

F6: GitHub state, read 2026-11-13 without credentials.
`https://github.com/cameronraysmith.keys` lists one RSA authentication key and not the login key.
`https://api.github.com/users/cameronraysmith/ssh_signing_keys` lists three signing keys: `cameron.ray.smith@gmail.com` (`…IP1yAjN9…`), `Git Signing Key (id_ed25519)` (id 670975, the login key) and `devin-ubuntu-ssh` (`…IBTeBMUf…`).
`tarachari3` has no keys of either kind; Christopher and Raquel have no `githubUser`.
The local `gh` token has scopes `gist, read:org, repo, workflow`, so `gh ssh-key add --type signing` needs `gh auth refresh -s admin:ssh_signing_key` first.
GitHub keeps a commit verified once verified (persistent commit signature verification, generally available 2024-12-10), and `cameronraysmith/vanixiets` `main` has no required-signatures rule (rules: deletion, non_fast_forward, two required status checks).

F7: the ubuntu profile already signs with a key that is in no `sshKeys` list (`modules/home/users/ubuntu/meta.nix:13`, `default.nix:89-91`), but that key, `devin-ubuntu-ssh`, is `&ubuntu-user` (`.sops.yaml:15`), the sandbox's own sops decryption identity.

F8: consumers of `meta.sshKeys`.
Login authorization (stay `sshKeys`): `modules/system/admins.nix:20` and root at `:24`, `modules/clan/inventory/services/users/cameron.nix:50`, `modules/clan/inventory/services/users/tara.nix:36`, `modules/machines/darwin/argentum/default.nix:113`, `modules/machines/darwin/blackphos/default.nix:137,145`, `modules/machines/darwin/rosegold/default.nix:113`, `modules/machines/darwin/stibnite/default.nix:133`, and through root `modules/system/initrd-networking.nix:26`.
Signing (become `signingKey`): `modules/clan/inventory/services/omnigent.nix:37` and `modules/lib/omnigent-fleet-obligations.nix:212`, both `head meta.sshKeys`; from those, `credentials.nix:184,264` and `credentials.py:343-361` read `expected.signingPublicKey` and need no edit.
Literal copies of the login key: `emergency-access.nix:11` (inert, F3) and the Radicle public key `modules/home/users/crs58/default.nix:363-365`, which stays with Radicle.
Signing key sources that are not `sshKeys`: the sops `ssh-public-key` placeholder in five profiles' `allowed_signers` templates and in git's darwin branch, ubuntu's literal at `default.nix:89-91`, and the fixture literal `modules/checks/omnigent-workers.nix:709`.

F9: homes. crs58 or cameron homes exist on all ten clan machines: cameron on cinnabar, electrum, galena, scheelite, magnetite, pyrite, argentum and rosegold, crs58 on blackphos and stibnite, plus `homeConfigurations` entries `crs58@*` and `cameron@*` for three systems each.
Janette's human home is on rosegold, her workers on magnetite and pyrite; Cameron's workers are on magnetite, pyrite and stibnite (`modules/clan/inventory/services/omnigent.nix`).
NixOS homes decrypt their sops file with the bridged age key (`modules/nixos/hm-sops-bridge.nix`); darwin homes read `~/.config/sops/age/keys.txt` (`modules/home/base/sops.nix:26`).

## Option chain

### Q1: where the signing key is generated and how it is delivered

O1a, person sops file as the one source: the operator generates the key pair once, writes the private half as a new `commit-signing-key` entry in the person's `secrets/home-manager/users/<user>/secrets.yaml`, records the public half in the person's profile, and pipes the private half into the worker's existing shared generator with `clan vars set`, as enrollment does today.
Human homes then decrypt it the way they decrypt every home secret, on every host and in every `homeConfigurations` entry, with no change to the worker credential contract or its obligations.
The cost is that the worker copy is a second ciphertext synchronized by a pipeline, and only the worker's enrollment check and a signed-commit smoke on a human home detect drift.

O1b, clan vars shared generator as the one source: a generator such as `commit-signing-key-cameron` runs `ssh-keygen` itself, delivers to each host's human account as a system-level secret, and the worker generator depends on it and copies it.
No person handles the private key and the worker copy follows regeneration.
The costs: human home modules would read a system-level secret path, which standalone `homeConfigurations` cannot supply; every machine key of a host carrying the person's home becomes a recipient of the private key, where O1a's recipients stay `admin`, `dev` and the person; the worker generator changes from hidden-prompt to dependency-copy, which changes `mkDelivery` for every credential and the `declaredCredentials` and `credentialDelivery` obligations that assert `prompts.<file>.type == "hidden"`; and darwin human homes would gain a dependency on clan vars delivery for a home secret, which they do not have today.

Recommendation at the time: O1a. Superseded on 2026-11-13 by the user's decision for clan vars; see "Decision revision, 2026-11-13" below.

### Q2: the public-key contract

A required `meta.signingKey` (the public half, one OpenSSH line) beside `sshKeys`, and `meta.retiredSigningKeys`, a list of `{ key; validBefore; }`.
The two `head meta.sshKeys` consumers switch to `meta.signingKey`; every login consumer keeps `sshKeys`.
`allowed_signers` stops being a sops template: public halves are not secret, so one home module renders it from the profile, as ubuntu already does by literal.
The sops `ssh-public-key` entries lose every consumer.

### Q3: signing without an agent

Keeping `user.signingkey` a private-key path is not enough (F4).
One program, an `ssh-keygen` wrapper that unsets `SSH_AUTH_SOCK` and execs the store path of nixpkgs' `ssh-keygen`, is git's `gpg.ssh.program` and jj's `signing.backends.ssh.program` on every human home, and git's darwin branch is removed.
Apple's `/usr/bin/ssh-keygen` with the same `unset` would also work, but the store path makes one artifact on both platforms that a Linux build can exercise, and keeps its version independent of macOS updates; Nix OpenSSH is withheld from darwin homes only from `PATH`, for the client's ZeroTier routing (A90), which signing does not involve.
Workers keep `ssh-keygen` from `PATH`, because `omnigent-worker-capabilities` already rejects any inherited agent or signing socket in a worker home.

### Q4: historical signatures

`allowed_signers` keeps the login key under the same principal with `valid-before="<cutover>"`.
F5 bounds what this buys: git accepts any signature whose commit claims a time before the cutover, and the committer time is chosen by the signer, so a holder of the old key can still produce commits git verifies; jj shows every old signature as `Unknown` once the cutover passes.
The forge is where a retired key actually stops counting: GitHub stops marking new pushes verified once the key's signing registration is removed, and keeps already-verified commits verified (F6).

### Q5: GitHub

Register each new public half as a signing key before any host deploys, keep the login key registered until every host and worker has deployed and every unpushed old-key commit is re-signed, and only then remove it.

### Q6: workers

Re-set `omnigent-cameron-signing-key/key` and `omnigent-janettesmith-signing-key/key` from the new sops entry in the same commit that switches `expected.signingPublicKey`, so the enrollment check and the delivered key change at the same deploy.
Superseded on 2026-11-13: the worker generator now derives its key from the person's generator (see "Decision revision, 2026-11-13").

### Q7: order

Two delivery phases.
Phase A ships the new key everywhere with the login key still accepted (no `valid-before`) and still registered on GitHub, so hosts that have not deployed keep producing commits both git and GitHub verify.
Phase B, after every host and worker has deployed and been observed signing with the new key, adds `valid-before` and removes the login key's GitHub signing registration.
Phase A must not deploy anywhere before the new key's GitHub registration exists.

### Q8: rotating the login key

Rotating the login key is an optional later hardening step, outside this change.
F2 sizes it: rotating the login key also rotates Cameron's sops and clan-vars decryption identity, which means re-encrypting every file with the `admin-user` recipient and replacing `sops/users/{crs58,cameron}`, the bridge key `secrets/bridge/crs58-age-key.enc`, the darwin `keys.txt` files, the Bitwarden items, the phones' authorized keys [INFERENCE: the Termux and Moshi hosts authorize it], the Radicle identity and GitHub signing key 670975.

### Q9: a dedicated age identity per person (open option, not in scope)

Fact 1 could also be removed from the other side: giving each person a dedicated age identity through `meta.sopsAgeKeyId` and `secrets/bridge/<id>-age-key.enc`, as `modules/nixos/hm-sops-bridge.nix` already supports, would decouple decryption from SSH keys entirely.
That re-encrypts every file addressed to the person's current recipient and touches the darwin `keys.txt` provisioning; it is recorded as an option to weigh later, not decided here.

### Known remainder: Radicle stays on the login key

`modules/home/development/radicle.nix:21` places the sops secret `ssh-signing-key`, the login key, at `~/.radicle/keys/radicle` as the Radicle node identity, and this change leaves Radicle's identity unchanged.
So after this change the passphrase-less login key file still exists on every human home that imports `development`; it leaves git and jj signing and every worker account, not human homes.

## Questions and accepted answers

1. Scope beyond Cameron and Janette: included. christophersmith, raquel and tara are in scope, starting with a comparison of each person's signing public half (sops `ssh-public-key`) with their login public half (`sshKeys`); a person whose signing key is already not a login key keeps it.
   Since the 2026-11-13 revision every clan person gets a generated key, so the comparison now only decides which old public key each person's `retiredSigningKeys` keeps for verifying past commits.
2. ubuntu, whose signing key is its own sops decryption identity (F7): it gets a new signing key.
3. Janette's GitHub signing registration on `janetteasmith`: an operator step, performed by the user or by Janette.
4. "A signing key opens no secret": kept.
5. Login-key rotation (Q8): deferred as an optional later hardening step.
6. Whether stibnite's vault holds the login key (F4): a follow-up check, not design-affecting.

## Invariants to preserve

- The signer principal stays the author address (`vcs.author.email`; workers `expected.gitEmail`).
- No worker home imports a human module, sops material or an agent socket; the `users = throw` guard in `modules/checks/omnigent-workers.nix` stays.
- Radicle keeps its identity.
- Login authorization is unchanged by this change.
- No commit signed during the migration carries a signature GitHub does not mark verified.

## Decision revision, 2026-11-13: clan vars hold the signing key

The user decided that the signing key moves from per-person home-manager sops entries (O1a) to clan vars (a form of O1b).

Decision: one shared generator per person, `<person>-commit-signing-key` with `share = true`, whose script runs `ssh-keygen -t ed25519 -N '' -C '<meta.gitEmail> commit signing'` itself, with a secret file `key` for the private half and a file `key.pub` with `secret = false` for the public half.
No key is made by hand; rotation is `clan vars generate --regenerate`.
The person's home on each clan machine and the person's Omnigent workers read the same generated key, so the second ciphertext synchronized by hand that O1a carried disappears, and the deployment plan's `sops -d --extract | clan vars set` signing pipeline (`docs/notes/development/omnigent/deployment-plan.md:974-982`) is retired.
The one exception is `ubuntu`, a standalone home-manager profile on no clan machine, which keeps a home-manager sops entry `commit-signing-key`; its key is already generated and stored, public half `ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINTr2Jio/Qi41YjYKSmSqwzUyL3NwJf6ae2tQRSIrRtD cameron.ray.smith@gmail.com commit signing` (`logs/parity/new-signing-keys.pub`).

Evidence weighed.
This repository keeps personal secrets, signing keys included, in home-manager sops (`modules/nixos/hm-sops-bridge.nix:5-6`), and that arrangement has no OpenSpec change or ADR (`:33-34`).
Upstream, clan-core documents vars for user-scoped and shared material (`docs/src/guides/vars/vars-concepts.md:69` `neededFor = "users"`, `:75` `share = true`; `vars-advanced-examples.md:84,127,145`, at the pinned `dbae21013`), and clan-infra uses vars for machine keys and per-user service credentials (`modules/mailserver.nix:166`, `modules/samba.nix:136`, `git.clan.lol/clan/clan-infra` at `008b3ecb`).
None of these references delivers a person's git signing key either way.

Trade-off: every machine carrying the person's home or worker becomes a recipient of the private key; root on those machines can already read the home-manager-decrypted copy, so no new reader is added.

Questions this revision raised, answered from clan-core and this repository:

- R1, ownership: a vars file has one `owner`, `group` and `mode` per machine (clan-core `nixosModules/clanCore/vars/secret/sops/generators-to-sops.nix:28-35,53-60`), and both the person's account and the worker account must read the key.
  Two files with equal content would change the worker credential contract's generator and file names, which `declaredCredentials` asserts; a shared group would break the contract's owner-is-the-worker, mode `0400` assertion (`modules/home/ai/omnigent/credentials.nix:152-166`).
  Chosen: the existing worker generator `omnigent-<owner>-signing-key` keeps its name, file, owner, mode and delivered path, and declares `dependencies = [ "<person>-commit-signing-key" ]` with a script that copies `$in/<person>-commit-signing-key/key` to `$out/key`, replacing its hidden prompt.
  clan regenerates dependents with the requested generator (`pkgs/clan-cli/clan_lib/vars/graph.py:131-139`, `requested_closure` calls `add_dependents`), so regenerating the person's generator regenerates every worker copy in the same run; `credentials.py` and the delivered path are unchanged.
- R2, path into the home: home modules already read machine facts through `osConfig` when embedded and see `null` when standalone (`modules/home/ai/cognee/default.nix:16-30`, `modules/home/ai/omnigent/credentials.nix:92-125`).
  `vcs-signing` takes the key path from `osConfig.clan.core.vars.generators.<person>-commit-signing-key.files.key.path`, which resolves each platform's layout (evaluated 2026-11-13: `/run/secrets/vars/shared/omnigent-cameron-signing-key/key` on both magnetite and stibnite for the existing worker var), and from its own sops entry only for ubuntu.
- R3, public key: `meta.signingKey` defaults to the committed `vars/shared/<person>-commit-signing-key/key.pub/value`, read at flake level, rather than to a machine configuration's `.value`, because `flake.users` is static data that check key sets and every machine read, and must not force a machine fixpoint (`preferences-nix-checks-architecture`, "Key-set strictness").
- R4, which machines: each machine declares the generator of every person with a home or a worker there, owned by that person's account where the home is and by `root` elsewhere (owner, group and mode may differ across machines for a shared generator, `pkgs/clan-cli/clan_lib/vars/generator.py:106-116`; every other attribute must match, `:272-296`).
  Cameron's generator reaches all ten clan machines, Janette's rosegold, magnetite and pyrite, Christopher's argentum, Raquel's blackphos and Tara's galena and scheelite.
  The person name is the canonical profile key after `flake.userAliases`, so `cameron` resolves to `crs58-commit-signing-key`.
  blackphos has no clan machine age key yet (no `sops/machines/blackphos`, no `sops/secrets/blackphos-age.key`), so it must be enrolled as a vars recipient before Cameron's and Raquel's homes there can receive the key.
  Revised later on 2026-11-13 (design.md D9): blackphos is excluded from this slice instead of enrolled; it is the one machine in `flake.lib.commitSigningLegacyMachines`, declares no generator, its homes sign with the login key file through the agent-free program, Raquel gets no new key yet, and enrolling blackphos becomes a prerequisite of the phase B cutover.
  ubuntu is the only profile on no clan machine.
  Standalone `homeConfigurations` entries of the other profiles have no `osConfig`, so they configure no signing key; [INFERENCE] they are not activated on any clan machine (`modules/apps/bootstrap/home-bootstrap.sh` targets sandbox profiles).
