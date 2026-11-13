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

### D1: the person's sops file is the one source of each signing key

- **Choice**: the operator generates each new key pair once, writes the private half as `commit-signing-key` in `secrets/home-manager/users/<user>/secrets.yaml`, records the public half as `meta.signingKey`, and fills each worker's existing generator with `sops -d --extract '["commit-signing-key"]' … | CLAN_NO_COMMIT=1 clan vars set <machine> omnigent-<owner>-signing-key/key`.
- **Rationale**: home secrets already reach every crs58, cameron and janettesmith home this way on both platforms and in standalone `homeConfigurations`; the private key's recipients stay `admin`, `dev` and the person; the worker credential contract, `mkDelivery`, and the `declaredCredentials` and `credentialDelivery` obligations keep their hidden-prompt shape.
- **Alternatives considered**: a clan vars shared generator that runs `ssh-keygen`, delivered to human accounts as a system secret and copied into the worker generator through `dependencies`.
  Rejected because standalone home configurations cannot read a system secret path, every host carrying the home would become a recipient of the private key, and the worker generator's prompt type and every credential obligation would change.
- **Trade-off**: the worker copy is a second ciphertext kept equal by a pipeline; the enrollment check detects drift on workers, and the post-deploy signing smoke detects it on human homes.
- **Boundary**: source versus delivered. The sops entry and the vars ciphertext are sources; the delivered files are `~/.config/sops-nix/secrets/commit-signing-key` and `/run/secrets/vars/omnigent-<owner>-signing-key/key`, observed only after activation.

### D2: an explicit signing key in the person record

- **Choice**: `meta.signingKey` (an `ssh-ed25519` line, no default) and `meta.retiredSigningKeys` (`listOf { key; validBefore = null or "YYYYMMDDhhmmssZ"; }`, default `[]`) in `modules/home/users/lib.nix`, set in each `meta.nix`.
  `omnigent.nix:37` and `omnigent-fleet-obligations.nix:212` switch from `head meta.sshKeys` to `meta.signingKey`; every login consumer listed in brainstorm F8 keeps `sshKeys`.
- **Rationale**: one key per purpose (NIST SP 800-57 Part 1 Rev. 5 §5.2, reasons 2 and 3, as in Context): the signing key is copied wherever unattended signing runs, so it must be neither a login key nor a decryption identity; the worker contract and the signers file therefore need a public key that is neither, and the order of `sshKeys` should carry no meaning.
- **Alternatives considered**: a second position in `sshKeys`, rejected because `sshKeys` is exactly the login list and `admins.nix:24` copies every wheel user's list to root.
- **Boundary**: first-party source only.

### D3: one home module and one agent-free program for git and jj

- **Choice**: a new `flake.modules.homeManager.vcs-signing` (`modules/home/development/vcs-signing.nix`, key `vanixiets/vcs-signing-home-module`), imported by `development`, declares `sops.secrets.commit-signing-key` (mode 0400), sets git `signing` to that path with format `ssh`, `gpg.ssh.program` and jj `signing.backends.ssh.program` to `flake.lib.agentFreeSshKeygen pkgs`, jj `signing.key` to the same path, and both tools' signers path.
  `agentFreeSshKeygen` is `pkgs.writeShellScriptBin "ssh-keygen"` running `unset SSH_AUTH_SOCK` then `exec ${pkgs.openssh}/bin/ssh-keygen "$@"`.
  git.nix loses its `signing` block, including the darwin branch; jujutsu.nix keeps `behavior` and `backend` for personal homes and loses `key` and `allowed-signers`.
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

### D6: worker vars switch in the same commit as the expected key

- **Choice**: the commit that sets `expected.signingPublicKey = meta.signingKey` also carries the re-set `vars/shared/omnigent-cameron-signing-key/key/secret` and `vars/shared/omnigent-janettesmith-signing-key/key/secret`.
- **Rationale**: the enrollment check compares the delivered key with the declared one; both change at the same deploy, and the login key leaves the worker's delivered file then.
- **Boundary**: source versus delivered; the old ciphertext stays in history, readable only by the existing recipients.

### D7: regulation as fleet obligations plus one check

- **Choice**: `modules/lib/commit-signing.nix` defines `flake.lib.commitSigningObligations` with `loginSources`, the predicates `unauthorized`, `homeSigningBound` and `workerSigningKey`, and `failures name hostConfig` over the cases `signingKeyUnauthorized`, `homeSigningBound` and `workerSigningKey`; `modules/checks/machines.nix` asserts it beside `omnigentFleetObligations` and `deployRecordObligations`.
  A new `checks.x86_64-linux.commit-signing-key` (`modules/checks/commit-signing-key.nix`) holds the profile relation, each predicate's control and mutants, the agent test of `agentFreeSshKeygen`, the `valid-before` round trip, and the `ssh-to-age` recipient comparison with its fixture mutant.
  `declaredCredentials` switches to `meta.signingKey`, and `omnigent-worker-inventory` gains `expectedLoginKey`.
- **Rationale**: per-host facts ride on machine checks that already force each host (`check-vacuity.md`, mechanism mismatch); the profile relation, the program's runtime behaviour and the recipient scan are not host facts, need a build for the last two, and cost one gated attribute that evaluates no host.
  Expected values in `homeSigningBound` are assembled from `meta` fields inside the obligation, not by calling `allowedSigners`, so a defect in the renderer is not reproduced in its own expectation.
  `loginSources` fails closed on any source it cannot read, and iterates declared accounts rather than found keys.
- **Alternatives considered**: folding the mutants into `omnigent-worker-inventory` (rejected: unrelated check, and the agent test needs its own build); a check per property (rejected: evaluation cost).
- **Boundary**: source versus delivered; obligations judge evaluated configuration.

### D8: scope covers every profile

- **Choice**: every profile gets `signingKey`; for christophersmith, raquel and tara the operator first compares their sops `ssh-public-key` with their `sshKeys` (public halves only), keeping an existing signing key that is not a login key by copying it into `commit-signing-key`, and generating one otherwise; ubuntu gets a new key because its current one is its decryption identity (brainstorm F7).
- **Rationale**: the brief covers every commit by a person; the `signingKey` field is required, so a narrower scope would need a nullable field and a second convention.
- **Accepted**: the user confirmed this scope, the new key for ubuntu, and the "opens no secret" requirement (brainstorm, "Questions and accepted answers" 1, 2 and 4).

## Risks / Trade-offs

- [Risk] A host deploys phase A before the forge knows the new key → its pushes lose the verified mark (behavioral requirement violated) → Mitigation: tasks gate every deploy on the public API listing the new key.
- [Risk] The worker copy and the sops entry drift → the worker fails enrollment and stops being ready → Mitigation: both come from one pipeline run in the same commit; `omnigent-worker-verify` is a post-deploy task.
- [Risk] A home activates before sops-nix has decrypted `commit-signing-key` (darwin launchd ordering, `radicle.nix` comment) → signing fails until the agent runs → accepted; unchanged from today's jj behaviour.
- [Risk] Backdated commits signed by the retired key verify in git (A91) → accepted; the forge bound is D5.
- [Trade-off] jj shows pre-cutover commits as of unknown principal after phase B (A92) → accepted.
- [Trade-off] One new check attribute on `x86_64-linux` → accepted for the build-time cases; no host is evaluated in it.
- [Trade-off] Radicle stays on the login key (`modules/home/development/radicle.nix:21`), so the passphrase-less login key file remains on every human home that imports `development` after this change; the change removes it from git and jj signing and from worker accounts, not from human homes → recorded as a known remainder.
- [Risk] Other open changes also replace the designation table → whichever archives later rebases its table; A91 to A95 follow A90.
- [Risk] The `commit-author-identity-interface` delta is refused at archive until `unify-vcs-author-identity` archives (`openspec validate` reports it as INFO) → archive in that order.

## Migration Plan

Phase 0, operator, before any commit: discovery for christophersmith, raquel and tara; key generation into each sops file in a tmpfs; GitHub registrations; worker vars re-set.
Phase A, one pull request, three commits, each evaluable on its own:

1. Profile fields and values, `allowedSigners`, `agentFreeSshKeygen`, `vcs-signing`, git and jj edits, profile clean-up, sops entries.
2. Worker contract: inventory and `declaredCredentials` to `meta.signingKey`, the vars ciphertext, `expectedLoginKey`.
3. `commitSigningObligations`, `machines.nix`, `commit-signing-key`, README and the dated deployment-plan amendment.

Deploy order: magnetite, pyrite and stibnite first (workers and Cameron's homes, removing the login key from worker files), with `omnigent-worker-verify` and a signing smoke on each; then rosegold (Janette's home), cinnabar, electrum, galena, scheelite, argentum and blackphos.
Until a host deploys it keeps signing with the login key, which phase A still accepts and GitHub still registers.

Phase B, one commit, after every host has deployed and every checkout's mutable old-key commits are re-signed: `validBefore` set and made non-null; then the operator removes the login keys' GitHub signing registrations and confirms an old pushed commit keeps its verified mark.

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
