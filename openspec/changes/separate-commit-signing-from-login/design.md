## Context

This change is the next step of Omnigent's documented hardening sequence.
Native sessions first ran as `cameron` without sandbox enforcement, with the `cameron` account as the execution boundary (`openspec/changes/deploy-omnigent-magnetite/proposal.md:45`, `specs/omnigent-deployment-interface/spec.md:74`); the deployment plan fixed the order dedicated user first, `enforce_sandbox` second (`docs/notes/development/omnigent/deployment-plan.md:199`, `:335`), and commits d20ae8599 (2026-09-10) and a28464344 (2026-09-15) moved sessions into dedicated worker accounts.
Mode `0400` does not isolate credentials from the same UID (`:948`), so every agent running under a human account, omp and Claude Code among them, reads that account's sops secrets; worker accounts receive only `ssh-signing-key` (`:974`), which narrowed what agents read.
The plan states that a worker identity grants no personal age identity (`:856`), and also that a person's age recipient corresponds to their SSH public key with `sopsAgeKeyId` null (`:854`); since the delivered `ssh-signing-key` is that SSH key, `:856` does not yet hold, and this change makes it hold.

Each person's signing key is their login key.
For Cameron that key, `…INdO9…sqSGyUH+`, is authorized for `crs58`, `cameron` and `root` on every NixOS host and in the initrd unlock shell (`modules/system/admins.nix:20,24`, `modules/clan/inventory/services/users/cameron.nix:50`, `modules/system/initrd-networking.nix:26`) and for `crs58` on blackphos and stibnite.
Its private half is the sops secret `ssh-signing-key`, which every crs58 and cameron home decrypts (`modules/home/users/crs58/default.nix:155-157`), which Radicle uses as its node identity (`modules/home/development/radicle.nix:21`), and which jj signs with on every platform (`modules/home/development/jujutsu.nix:190`).
git signs with it on Linux and, on darwin, through whatever agent `SSH_AUTH_SOCK` names, given the sops `ssh-public-key` file (`modules/home/development/git.nix:27-38`); that agent is Bitwarden's (`modules/home/core/bitwarden.nix:29-31`).
Omnigent workers sign with a copy of it in `vars/shared/omnigent-<worker>-signing-key/key`, and their enrollment check (`modules/home/ai/omnigent/credentials.py:343-361`) requires its public half to equal `expected.signingPublicKey = builtins.head meta.sshKeys` (`modules/clan/inventory/services/omnigent.nix:37`, restated at `modules/lib/omnigent-fleet-obligations.nix:212`).
Janette's workers are built the same way from her login key.

The same key pair is also each person's sops decryption identity: `ssh-to-age` of Cameron's login key is the `admin-user` recipient of 198 files, among them the openssh host CA, the otel CA key, the cameron user password and the fleet Wi-Fi credentials, and every other profile's login key maps to its own recipient (brainstorm F2).

Reusing a login key for git signing is permitted by the forges and is not a cryptographic weakness: GitHub ("You can even upload your existing authentication key to GitHub to also use as a signing key", https://docs.github.com/en/authentication/managing-commit-signature-verification/about-commit-signature-verification) and GitLab ("You may use the same SSH keys for git+ssh authentication to GitLab and signing commit signatures as long as their usage type is Authentication & Signing", https://docs.gitlab.com/user/project/repository/signed_commits/ssh/) both allow it, and OpenSSH's signature namespace "prevents cross-protocol attacks caused by signatures intended for one intended domain being accepted in another" (https://github.com/openssh/openssh-portable/blob/master/PROTOCOL.sshsig, lines 53-56).
The separation here rests on NIST SP 800-57 Part 1 Rev. 5 §5.2 (https://nvlpubs.nist.gov/nistpubs/SpecialPublications/NIST.SP.800-57pt1r5.pdf), "In general, a single key shall be used for only one purpose", which lists the private signature key and the private authentication key as distinct key types, and on two of its reasons that this fleet's facts bring into play.
Reason (3), uses that interfere, illustrated by one key pair used for key transport (decryption) and signatures with conflicting retention requirements, applies because the login key is a decryption identity (the 198 files above).
Reason (2), limiting damage on compromise, applies because of custody: unattended signing needs the key as a passphrase-less file in every human home and worker account, while root login and decryption need few, tightly held copies; it applies because of that distribution, not because login and signing differ as operations.

`ssh-keygen -Y sign` signs through any agent that holds the key named by `-f`, even when `-f` is a private key file (A93), so a key file alone does not keep signing off Bitwarden.
git judges `valid-before` at the commit's claimed time (A91) and jj at the time of verification (A92).
GitHub gives the verified mark only for registered signing keys and keeps it once given (A94); `cameronraysmith` currently registers the login key as signing key 670975.

The stakeholders are each person with a profile, the operator, who holds every person's sops file through the `admin` and `dev` recipients and runs every deploy, and the Omnigent workers' owners.
This change depends on `unify-vcs-author-identity`, which fixes the signer principal and which it modifies; it is delivered ahead of the workstation-parity program's SSH slice.

## Goals / Non-Goals

**Goals:**

- Each person has one signing key that no host authorizes for login and that opens no secret.
- Every commit, by a person or an agent, signs with that key from a file, never through an agent and never with a prompt, on Linux and on darwin.
- Omnigent workers hold their owner's signing key and no login key.
- Old signatures keep verifying in git and on GitHub; no commit pushed during the migration lacks GitHub's verified mark.
- Every property that configuration can express is regulated by a check with a mutant that fails.

**Non-Goals:**

- Rotating any login key or decryption identity, an optional later hardening step (brainstorm Q8).
- Changing login authorization, the Bitwarden agent's role in login, or Radicle's identity.
- Retiring the inert `allowedKeys` literal in `modules/clan/inventory/services/emergency-access.nix`.
- Giving workers the retired keys for verification.
- Making jj honour `valid-before` for historical signatures.

## Decisions

### D1′ (2026-11-13, replacing D1): one clan vars shared generator per person holds the signing key

- **Choice**: each machine that carries a person's home or Omnigent worker declares `clan.core.vars.generators."<person>-commit-signing-key"` with `share = true`, `runtimeInputs = [ pkgs.openssh ]`, a secret file `key` (mode `0400`, owned by the person's account where the home is and by `root` elsewhere) and a public file `key.pub` (`secret = false`), and the script `ssh-keygen -q -t ed25519 -N '' -C '<meta.gitEmail> commit signing' -f $out/key`, with `$out/key.pub` written by the same call.
  `<person>` is the canonical profile key after `flake.userAliases`, so the cameron and crs58 accounts share `crs58-commit-signing-key`.
  No key is made by hand; rotation is `clan vars generate --regenerate --generator <person>-commit-signing-key`.
  The one documented exception is `ubuntu`, a standalone home on no clan machine, which keeps a home-manager sops entry `commit-signing-key` holding an already generated key (public half ending `…QRSIrRtD`, `logs/parity/new-signing-keys.pub`).
- **Rationale**: the person's homes and workers read one generated key, so no second ciphertext is synchronized by hand and the deployment plan's `sops -d --extract | clan vars set` signing pipeline (`docs/notes/development/omnigent/deployment-plan.md:974-982`) is retired.
  This repository's home-manager sops arrangement for personal secrets (`modules/nixos/hm-sops-bridge.nix:5-6`) has no OpenSpec change or ADR (`:33-34`); clan-core documents vars for shared and user-scoped material (`docs/src/guides/vars/vars-concepts.md:69,75`, `vars-advanced-examples.md:84,127,145`, pinned `dbae21013`), and clan-infra uses them for machine keys and per-user service credentials (`modules/mailserver.nix:166`, `modules/samba.nix:136`, `008b3ecb`); none of these references delivers a person's git signing key either way.
- **Withdrawn choice (D1)**: the operator generated each key by hand into the person's `secrets/home-manager/users/<user>/secrets.yaml` and piped it into each worker generator with `clan vars set`.
  It kept the worker contract's hidden prompt and reached standalone home configurations, but carried a second ciphertext kept equal only by that pipeline, with drift detected only by the worker enrollment check and a signing smoke; the user withdrew it for the generated source above.
- **Trade-off**: every machine carrying the person's home or worker becomes a recipient of the private key; root on those machines can already read the home-manager-decrypted copy, so no new reader is added.
  Owner, group and mode may differ per machine for a shared generator, and every other attribute must match (clan-core `pkgs/clan-cli/clan_lib/vars/generator.py:106-116,272-296`), which is why `key` is deployed on every declaring machine and owned by `root` where the person has no home.
  blackphos has no clan machine age key yet (no `sops/machines/blackphos`), so it declares no generator in this slice and its homes keep the login key file (D9).
  Standalone `homeConfigurations` of clan profiles see no `osConfig` and configure no signing key.
- **Boundary**: source versus delivered. The vars ciphertext and public file are sources; the delivered file is the sops-nix path of `vars/shared/<person>-commit-signing-key/key` on each machine, observed only after activation. Vendored versus first-party: clan-core's vars and sops backends are used unmodified.

### D2: an explicit signing key in the person record

- **Choice**: `meta.signingKey` (an `ssh-ed25519` line) and `meta.retiredSigningKeys` (`listOf { key; validBefore = null or "YYYYMMDDhhmmssZ"; }`, default `[]`) in `modules/home/users/lib.nix`; `signingKey` defaults to `lib.fileContents` of the committed `vars/shared/<person>-commit-signing-key/key.pub/value`, and ubuntu sets its literal.
  Reading the committed public file at flake level, rather than a machine configuration's `.value`, keeps `flake.users` static data that check key sets and every machine can read without forcing a machine fixpoint (`preferences-nix-checks-architecture`, "Key-set strictness").
  `omnigent.nix:37` and `omnigent-fleet-obligations.nix:212` switch from `head meta.sshKeys` to `meta.signingKey`; every login consumer listed in brainstorm F8 keeps `sshKeys`.
- **Rationale**: one key per purpose (NIST SP 800-57 Part 1 Rev. 5 §5.2, reasons 2 and 3, as in Context): the signing key is copied wherever unattended signing runs, so it must be neither a login key nor a decryption identity; the worker contract and the signers file therefore need a public key that is neither, and the order of `sshKeys` should carry no meaning.
- **Alternatives considered**: a second position in `sshKeys`, rejected because `sshKeys` is exactly the login list and `admins.nix:24` copies every wheel user's list to root.
- **Boundary**: first-party source only.

### D3: one home module and one agent-free program for git and jj

- **Choice**: a new `flake.modules.homeManager.vcs-signing` (`modules/home/development/vcs-signing.nix`, key `vanixiets/vcs-signing-home-module`), imported by `development`, declares `vcs.signing.keyFile` (null or a path), defaulting to `osConfig.clan.core.vars.generators."<person>-commit-signing-key".files.key.path` when the home is embedded in a machine that declares the generator, the same pattern by which `modules/home/ai/cognee/default.nix:16-30` and `modules/home/ai/omnigent/credentials.nix:92-125` read machine facts, and to null when standalone; ubuntu's profile sets it to its own `sops.secrets.commit-signing-key.path`.
  When `keyFile` is set it sets git `signing` to it with format `ssh`, `gpg.ssh.program` and jj `signing.backends.ssh.program` to `flake.lib.agentFreeSshKeygen pkgs`, jj `signing.key` to the same path, and both tools' signers path; `.path` resolves each platform's layout (evaluated 2026-11-13 as `/run/secrets/vars/shared/<generator>/key` on magnetite and stibnite).
  `agentFreeSshKeygen` is `pkgs.writeShellScriptBin "ssh-keygen"` running `unset SSH_AUTH_SOCK` then `exec ${pkgs.openssh}/bin/ssh-keygen "$@"`.
  git.nix loses its `signing` block, including the darwin branch; jujutsu.nix loses its personal `signing` block, so `behavior`, `backend`, `key` and both paths are set by `vcs-signing` only when a key file exists, and its `git-sign-on-push` revset is `none()` in a home without one, so a standalone home is neither told to sign nor to sign on push.
- **Rationale**: removing `SSH_AUTH_SOCK` is the only way to make A93 irrelevant; one program used by both tools is one artifact a Linux build can exercise.
  nixpkgs' `ssh-keygen` by store path is withheld from darwin `PATH` only for the SSH client's ZeroTier routing (A90), which signing does not involve.
- **Alternatives considered**: Apple's `/usr/bin/ssh-keygen` behind the same `unset` on darwin (works, but untestable in a Linux build and versioned by macOS updates); `IdentityAgent none` (an `ssh_config` option `ssh-keygen -Y` does not read); relying on the new key being absent from every agent (true today, unenforceable).
- **Boundary**: vendored versus first-party. home-manager's `programs.git` and `programs.jujutsu` are set, not patched; OpenSSH is used unmodified. Source versus delivered: the delivered `~/.config/git/config` and `~/.config/jj/config.toml` change at activation.
- Workers keep `ssh-keygen` from `PATH`; `omnigent-worker-capabilities` already rejects an inherited agent socket in a worker home.

### D4: signers rendered from the profile, with a two-phase cutover

- **Choice**: `flake.lib.allowedSigners { principal; signingKey; retiredSigningKeys; }` renders `~/.config/git/allowed_signers` as a plain `xdg.configFile`; the five sops `allowed_signers` templates, the `ssh-public-key` declarations and ubuntu's literal go.
  Phase A records the login key in `retiredSigningKeys` with `validBefore = null`; phase B sets `validBefore` to the cutover, the UTC time at which phase B is authored, after every host has deployed phase A.
  The phase B commit also narrows `validBefore` to a non-null timestamp, removing the null branch.
- **Rationale**: public keys are not secret; a `valid-before` written before every host signs with the new key would make the old key's fresh commits fail git verification on hosts not yet deployed.
- **Limits**: git admits backdated forgeries by any holder of the retired key (A91), and jj shows old signatures as of unknown principal after the cutover (A92); the forge's registration removal is the bound that counts (D5).
- **Boundary**: source versus delivered.

### D5: GitHub registration precedes every deploy and is withdrawn last

- **Choice**: before phase A deploys anywhere, the operator registers `cameronraysmith`'s new key (`gh auth refresh -h github.com -s admin:ssh_signing_key`, then `gh ssh-key add <pub> --type signing --title …`) and Janette registers hers on `janetteasmith`; both are confirmed through `https://api.github.com/users/<login>/ssh_signing_keys`.
  The login keys' signing registrations are removed only in phase B, after every host and worker has deployed and every mutable commit the login key signed has been pushed or re-signed with `jj sign`.
- **Rationale**: A94; jj's `git-sign-on-push` revset `~signed() & mine()` (`jujutsu.nix:109`) treats an old-key signature as signed and would push it unchanged.
- **Boundary**: external forge state; no check observes it.

### D6′ (2026-11-13, replacing D6): the worker generator derives its key from the person's generator

- **Choice**: `mkDelivery` in `modules/home/ai/omnigent/credentials.nix` gives the signing source's generator `omnigent-<owner>-signing-key` `dependencies = [ "<person>-commit-signing-key" ]` and the script `cp "$in/<person>-commit-signing-key/key" "$out/key"`, with no prompt; its name, file `key`, `share = true`, owner `omnigent-<owner>`, mode `0400` and delivered path stay, so `credentials.py` and the credential contract's delivery assertions are unchanged.
  `declaredCredentials` and the generator-shape assertion in `omnigent-fleet-obligations.nix` (`prompts.<file>.type == "hidden"`, line 221) require the dependency form for the signing source instead of a hidden prompt; the other credential sources keep their prompts.
  The commit that sets `expected.signingPublicKey = meta.signingKey` also carries the regenerated worker ciphertext.
- **Rationale**: a vars file has one owner per machine (clan-core `nixosModules/clanCore/vars/secret/sops/generators-to-sops.nix:28-35,53-60`), and both the person's account and the worker must read the key.
  Two equal files in the person's generator would rename the worker's source, which `declaredCredentials` asserts; a shared group with mode `0440` would break the contract's owner-is-the-worker, mode `0400` assertion (`credentials.nix:152-166`) and add a group to worker accounts.
  clan regenerates dependents with a requested generator (`pkgs/clan-cli/clan_lib/vars/graph.py:131-139`), so rotating the person's key rotates every worker copy in the same run.
- **Boundary**: source versus delivered; the old worker ciphertext stays in history, readable only by its existing recipients.

### D7: regulation as fleet obligations plus one check

- **Choice**: `modules/lib/commit-signing.nix` defines `flake.lib.commitSigningObligations` with `loginSources`, the predicates `unauthorized`, `personGenerator`, `homeSigningBound`, `workerSigningKey`, `signingKeyPresent` and `unenrolled`, and `failures name hostConfig` over the cases `signingKeyUnauthorized`, `signingKeyPresence` and `homeSigningBound` on every host, `personGenerator` and `workerSigningKey` off the legacy list, and `legacyNoGenerator` and `legacyUnenrolled` on it (D9); `modules/checks/machines.nix` asserts it beside `omnigentFleetObligations` and `deployRecordObligations`.
  `personGenerator` requires every person with a home or worker on the host to have a declared `<person>-commit-signing-key` with `share = true`, no prompt, a secret `key` owned by that person's account where the home is (else `root`) with mode `0400`, and a public `key.pub`; `homeSigningBound` compares each embedded home's `vcs.signing.keyFile` with that generator's `key` path; `workerSigningKey` also requires the worker generator's `dependencies` to be exactly `[ "<person>-commit-signing-key" ]` with no prompt.
  A new `checks.x86_64-linux.commit-signing-key` (`modules/checks/commit-signing-key.nix`) holds the profile relation, each predicate's control and mutants, the agent test of `agentFreeSshKeygen`, the `valid-before` round trip, and the `ssh-to-age` recipient comparison with its fixture mutant.
  `declaredCredentials` switches to `meta.signingKey` and the dependency form, and `omnigent-worker-inventory` gains `workerSigningControl`, `expectedLoginKey` and `workerKeyPrompted`.
- **Rationale**: per-host facts ride on machine checks that already force each host (`check-vacuity.md`, mechanism mismatch); the profile relation, the program's runtime behaviour and the recipient scan are not host facts, need a build for the last two, and cost one gated attribute that evaluates no host.
  Expected values in `homeSigningBound` are assembled from `meta` fields inside the obligation, not by calling `allowedSigners`, so a defect in the renderer is not reproduced in its own expectation.
  `loginSources` fails closed on any source it cannot read, and iterates declared accounts rather than found keys.
- **Alternatives considered**: folding the mutants into `omnigent-worker-inventory` (rejected: unrelated check, and the agent test needs its own build); a check per property (rejected: evaluation cost).
- **Boundary**: source versus delivered; obligations judge evaluated configuration.

### D8: scope covers every profile

- **Choice**: every profile gets `signingKey`: crs58 (with its cameron alias), janettesmith, christophersmith and tara from their generators, ubuntu from its sops exception, and raquel null until blackphos is enrolled (D9); the operator first compares each person's sops `ssh-public-key` with their `sshKeys` (public halves only) to decide which old public key `retiredSigningKeys` keeps for past commits (2026-11-13: for every person it is the login key).
- **Rationale**: the brief covers every commit by a person; `signingKey` is null only where D9's legacy list allows it, and `signingKeyPresence` keeps that one exception from becoming a second convention.
- **Accepted**: the user confirmed this scope, the new key for ubuntu, and the "opens no secret" requirement (brainstorm, "Questions and accepted answers" 1, 2 and 4).

### D9 (2026-11-13): blackphos stays on the login key until it is enrolled

- **Choice**: `flake.lib.commitSigningLegacyMachines = [ "blackphos" ]` is the one named list of machines without a clan machine key.
  A listed machine declares no `*-commit-signing-key` generator and no signing worker; each of its homes sets `vcs.signing.keyFile` to its sops `ssh-signing-key` path (the login key file, which Radicle already places at `~/.radicle/keys/radicle`) and signs through `agentFreeSshKeygen`, with signers rendered from the profile, so no signing path anywhere goes through an agent and git's darwin Bitwarden branch is deleted rather than kept for one machine.
  `meta.signingKey` is nullable; raquel, whose only host is blackphos, sets it to null and keeps her login key as a `retiredSigningKeys` entry, and gets no new key in this slice; crs58's home on blackphos signs with the login key while its signers list the new key and the login key.
- **Regulation**: `signingKeyPresence` fails a host where a home's or worker's person has a null key off the list, or a key while every machine their generated key is encrypted to is on the list (read from `vars/shared/<person>-commit-signing-key/key/machines`), so the null keys are exactly the people whose every host is listed; `legacyNoGenerator` fails a listed machine that declares a generator or a signing worker, and `legacyUnenrolled` fails a listed machine that has `sops/machines/<name>`, so enrolling a machine forces its removal from the list.
- **Rationale**: the user excluded blackphos from this slice on 2026-11-13; making the exclusion a named, checked list keeps it from spreading silently.
- **Consequence**: enrolling blackphos, removing it from the list, generating `raquel-commit-signing-key` and dropping raquel's null are prerequisites of phase B (task 6.0); until then the login key still signs commits on blackphos, so the phase B `valid-before` cannot be authored.

## Risks / Trade-offs

- [Risk] A host deploys phase A before the forge knows the new key → its pushes lose the verified mark (behavioral requirement violated) → Mitigation: tasks gate every deploy on the public API listing the new key.
- [Risk] A worker copy drifts from its person's key → the worker fails enrollment and stops being ready → Mitigation: under D6′ the worker generator copies the person's generator and is regenerated with it (`graph.py:131-139`); `workerSigningKey` regulates the dependency and `omnigent-worker-verify` is a post-deploy task.
- [Risk] A machine that carries a person's home or worker is not a vars recipient (blackphos today) → that home cannot decrypt a generated key → Mitigation: D9 lists blackphos as the one legacy machine, whose homes sign with the login key file through the agent-free program; `legacyUnenrolled` forces its removal from the list once enrolled, and `personGenerator` fails any unlisted machine where the generator is missing.
- [Risk] The legacy path keeps the login key signing commits on blackphos → that machine does not yet meet "a signing key admits no login" → accepted as a recorded transitional state of phase A; enrolling blackphos is a prerequisite of phase B (D9).
- [Risk] Shared generator definitions differ between machines in anything but owner, group or mode → `clan vars` refuses to generate (`generator.py:272-296`) → Mitigation: one function builds the generator for every machine; only `owner` varies.
- [Risk] A home activates before sops-nix has decrypted the key (darwin launchd ordering) → signing fails until it is decrypted → accepted; unchanged from today's jj behaviour.
- [Risk] Backdated commits signed by the retired key verify in git (A91) → accepted; the forge bound is D5.
- [Trade-off] jj shows pre-cutover commits as of unknown principal after phase B (A92) → accepted.
- [Trade-off] One new check attribute on `x86_64-linux` → accepted for the build-time cases; no host is evaluated in it.
- [Trade-off] Radicle stays on the login key (`modules/home/development/radicle.nix:21`), so the passphrase-less login key file remains on every human home that imports `development` after this change; the change removes it from git and jj signing and from worker accounts, not from human homes → recorded as a known remainder.
- [Risk] Other open changes also replace the designation table → whichever archives later rebases its table; A91 to A95 follow A90.
- [Risk] The `commit-author-identity-interface` delta is refused at archive until `unify-vcs-author-identity` archives (`openspec validate` reports it as INFO) → archive in that order.

## Migration Plan

Phase 0, before any deploy: discover each person's old signing public key; once step 1's generator module is in the working copy, run `CLAN_NO_COMMIT=1 clan vars generate <machine> --generator <person>-commit-signing-key` once per person for crs58, janettesmith, christophersmith and tara (the generator is shared, so one run serves every machine) and route the result into step 1; once step 2 declares the worker dependency, run `CLAN_NO_COMMIT=1 clan vars generate magnetite --generator omnigent-<owner>-signing-key --regenerate` for cameron and janettesmith and route the result into step 2; then register the generated public keys on GitHub before any deploy.
blackphos is not enrolled in phase A (D9).
ubuntu's key is already generated and stored in its sops file.
Phase A, one pull request, three commits, each evaluable on its own:

1. Profile fields and values, the per-person generator module, `allowedSigners`, `agentFreeSshKeygen`, `vcs-signing`, git and jj edits, profile clean-up, the generated `vars/shared/<person>-commit-signing-key` files, ubuntu's sops entry.
2. Worker contract: `mkDelivery`'s dependency form, inventory and `declaredCredentials` to `meta.signingKey`, the regenerated worker ciphertext.
3. `commitSigningObligations`, `machines.nix`, `commit-signing-key`, the worker-inventory mutants, README and the dated deployment-plan amendment retiring the manual signing pipeline.

Deploy order: magnetite, pyrite and stibnite first (workers and Cameron's homes, removing the login key from worker files), with `omnigent-worker-verify` and a signing smoke on each; then rosegold (Janette's home), cinnabar, electrum, galena, scheelite and argentum; blackphos deploys too, where git moves from the Bitwarden agent to the login key file through the agent-free program.
Until a host deploys it keeps signing with the login key, which phase A still accepts and GitHub still registers.

Phase B, one commit, after blackphos is enrolled and removed from the legacy list with raquel's key generated (task 6.0), every host has deployed, and every checkout's mutable old-key commits are re-signed: `validBefore` set and made non-null; then the operator removes the login keys' GitHub signing registrations and confirms an old pushed commit keeps its verified mark.

Rollback in phase A is a revert and redeploy; GitHub still accepts the login key.
Rollback after phase B also needs the login key's registration re-added.

## Open Questions

The user answered the session's questions (brainstorm, "Questions and accepted answers"); what remains is recorded here.

- O1 (answered): christophersmith, raquel and tara are in scope, starting with the comparison of their signing and login public halves (task 1.2).
- O2 (answered): ubuntu gets a new signing key.
- O3 (answered): Janette's GitHub registration is an operator step, performed by the user or by Janette (task 1.4).
- O4 (answered): "a signing key opens no secret" is kept.
- O5 (deferred): rotating the login keys, which are also decryption identities (brainstorm F2), is an optional later hardening step in its own change.
- O6 (follow-up): whether stibnite's vault holds the login key (brainstorm F4) is a follow-up check and affects no decision here.
- O7 (option to weigh later, not in scope): a dedicated age identity per person through `meta.sopsAgeKeyId` and `hm-sops-bridge`, which would decouple decryption from SSH keys entirely (brainstorm Q9).
