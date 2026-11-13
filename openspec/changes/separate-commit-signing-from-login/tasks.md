## 1. Phase 0: keys, forge registrations and the before-state

Operator-run; agents do not decrypt, generate or register keys.
Scope follows the user's answers recorded in brainstorm.md ("Questions and accepted answers").

- [ ] 1.1 Record the before-state: for every `homeConfigurations` entry and every `home-manager.users` entry of the ten clan machines, git `signing.key`, git `gpg.ssh.program`, jj `signing.key` and `signing.backends.ssh.program`, and the signers text; each host's workers' `credentials.expected.signingPublicKey`; `loginSources`-equivalent `users.users.*.openssh.authorizedKeys.keys` and initrd keys per host; and both check key lists — verify: `nix eval` (evaluation only), saved under `$XDG_STATE_HOME/agent-logs/vanixiets/`; stibnite's crs58 git key is the `ssh-public-key` path and every worker's expected key is its owner's `head meta.sshKeys`
- [ ] 1.2 For christophersmith, raquel, tara and janettesmith, compare `sops -d --extract '["ssh-public-key"]' secrets/home-manager/users/<user>/secrets.yaml` with that profile's `sshKeys` (public halves only) — verify: a table of profile, match or no match, recorded in the PR description; Janette is expected to match (brainstorm F1)
- [ ] 1.3 For each profile needing a new key (crs58, janettesmith, ubuntu, and each 1.2 match), generate an ed25519 pair in a tmpfs with an empty passphrase and comment `<meta.gitEmail> commit signing`, set its private half as `commit-signing-key` with `sops set`, remove `ssh-public-key`, and shred the tmpfs copy; for each 1.2 non-match, set `commit-signing-key` to the existing `ssh-signing-key` value — verify: `sops -d --extract '["commit-signing-key"]' <file> | ssh-keygen -y -f /dev/stdin` prints the public key recorded for 2.2, and `ssh-to-age` of it is absent from `.sops.yaml`
- [ ] 1.4 Register Cameron's new public key on `cameronraysmith` (`gh auth refresh -h github.com -s admin:ssh_signing_key`, then `gh ssh-key add <pub> --type signing --title "commit signing <date>"`), and have the user or Janette register hers on `janetteasmith`, keeping every existing registration — verify: `curl -s https://api.github.com/users/<login>/ssh_signing_keys` lists the new key and still lists the login key
- [ ] 1.5 Re-set the worker generators from the new entry: `(set +x; set -o pipefail; sops -d --extract '["commit-signing-key"]' secrets/home-manager/users/crs58/secrets.yaml | CLAN_NO_COMMIT=1 clan vars set magnetite omnigent-cameron-signing-key/key)` and the same for janettesmith — verify: `git status` shows only `vars/shared/omnigent-{cameron,janettesmith}-signing-key/key/secret` changed, with unchanged `machines/` and `users/` recipient links

## 2. Phase A step 1: the signing key, the program and the home module

First of three commits on the bookmark `separate-commit-signing-from-login`, rebase-merged.

- [ ] 2.1 Add `signingKey` and `retiredSigningKeys` to the meta submodule in `modules/home/users/lib.nix` — verify: `nix eval .#users.raquel.meta.signingKey` fails naming `signingKey` before 2.2 (RED, evaluation)
- [ ] 2.2 Set `signingKey` in all six `meta.nix`, and `retiredSigningKeys = [ { key = <login key>; validBefore = null; } ]` where 1.3 generated a new key — verify: `nix eval --json .#users --apply 'u: builtins.mapAttrs (_: v: v.meta.signingKey) u'` lists seven keys (cameron and crs58 equal), none in any `sshKeys`
- [ ] 2.3 Add `flake.lib.allowedSigners` and `flake.lib.agentFreeSshKeygen` in `modules/lib/commit-signing.nix` — verify: `nix eval --raw --impure --expr` of `allowedSigners` on a fixture with one null and one dated retired entry returns the three expected lines (evaluation)
- [ ] 2.4 Create `modules/home/development/vcs-signing.nix` and import it from `development`; remove `signing` from `git.nix`, `key` and `allowed-signers` from `jujutsu.nix`, the `ssh-public-key` declarations and `allowed_signers` templates from five profiles, ubuntu's literal signers file, and the stale `ssh-add` comment in `bitwarden.nix` — verify: `nix eval` of `darwinConfigurations.stibnite.config.home-manager.users.crs58.programs.git.signing.key` is the `commit-signing-key` path and `.settings.gpg.ssh.program` is the `agentFreeSshKeygen` store path (evaluation)
- [ ] 2.5 Rerun the 1.1 projection — verify: `nix eval`; differences are exactly the signing key path, both programs, and the signers text, on every human home; worker homes and every `expected` are unchanged
- [ ] 2.6 Build the human home checks and seal the commit — verify: `nix build .#checks.x86_64-linux.home-manager-{crs58,christophersmith,janettesmith,raquel,ubuntu}` (build); `nix eval .#.checks.aarch64-darwin.home-manager-tara.drvPath` (evaluation); `just lint` exits 0

## 3. Phase A step 2: the worker contract

- [ ] 3.1 Set `expected.signingPublicKey = meta.signingKey` in `modules/clan/inventory/services/omnigent.nix` and in `declaredCredentials` in `modules/lib/omnigent-fleet-obligations.nix`, and route the 1.5 ciphertext into this commit — verify: `nix eval` of each worker's `expected.signingPublicKey` on magnetite, pyrite and stibnite equals its owner's `signingKey` (evaluation)
- [ ] 3.2 Seal the commit — verify: `nix build .#checks.x86_64-linux.nixos-magnetite .#checks.x86_64-linux.nixos-pyrite` (build); `nix eval .#.checks.aarch64-darwin.darwin-stibnite.drvPath` (evaluation)

## 4. Phase A step 3: regulation and documentation

- [ ] 4.1 Add `loginSources`, `unauthorized`, `homeSigningBound`, `workerSigningKey` and `failures` to `flake.lib.commitSigningObligations`, assert `failures` in `modules/checks/machines.nix`, and add the `expectedLoginKey` case to `omnigent-worker-inventory` — verify: `nix eval` of `unauthorized` over cinnabar's configuration with Cameron's `signingKey` appended to root's keys returns `false` (RED, evaluation); `nix build .#checks.x86_64-linux.nixos-{cinnabar,electrum,galena,magnetite,pyrite} .#checks.x86_64-linux.omnigent-worker-inventory` succeed, and removing `expectedLoginKey`'s negation locally fails naming it (build)
- [ ] 4.2 Create `modules/checks/commit-signing-key.nix` with the profile relation and its three mutants, the `unauthorized` control and seven mutants, the `homeSigningBound` cases on ubuntu's home, a control and four mutants, the agent test with its plain-`ssh-keygen` mutant, the `valid-before` round trip, and the `ssh-to-age` recipient scan with its fixture mutant — verify: `nix build .#checks.x86_64-linux.commit-signing-key` succeeds, and flipping each case's expected outcome locally fails naming it (build)
- [ ] 4.3 Update `modules/clan/services/omnigent/README.md` (signing source and the new obligation) and append the dated amendment "Commit signing key amendment" to `docs/notes/development/omnigent/deployment-plan.md`, replacing the enrollment pipeline's `ssh-signing-key` extraction with `commit-signing-key` — verify: `just lint`; `git diff` of the deployment plan shows only an appended section
- [ ] 4.4 Seal the commit — verify: the 1.1 key lists rerun show `checks.x86_64-linux` gained only `commit-signing-key` and `checks.aarch64-darwin` is unchanged (evaluation); `openspec validate separate-commit-signing-from-login --strict` is valid

## 5. Phase A deploy

Operator-run after the stack lands and only once 1.4 is verified.

- [ ] 5.1 Deploy magnetite, pyrite and stibnite, and record every alert and failure notice posted since each deploy started, each with its cause — verify: as each `omnigent-*` worker, `omnigent-worker-verify` prints `worker identity verification passed`; `ssh-keygen -y -f /run/secrets/vars/omnigent-cameron-signing-key/key` (as the worker) prints the new key; the notification topics' history since the deploy is attributed
- [ ] 5.2 Smoke the human homes on those hosts — verify: with the vault locked on stibnite and `SSH_AUTH_SOCK` still exported, `git commit --allow-empty -S -m smoke </dev/null` and `jj commit -m smoke` in a scratch repository complete without a prompt, and `git verify-commit HEAD` reports a good signature for the author address with the new key's fingerprint
- [ ] 5.3 Deploy rosegold, cinnabar, electrum, galena, scheelite, argentum and blackphos at the operator's discretion, recording alerts as in 5.1 — verify: on each, `git config --global gpg.ssh.program` prints the `agentFreeSshKeygen` path and a scratch signed commit verifies; Janette's on rosegold verifies for `125711642+janetteasmith@users.noreply.github.com`
- [ ] 5.4 Push one smoke commit from a human home and one from a worker to a scratch GitHub repository — verify: `gh api repos/<owner>/<repo>/commits/<sha> --jq .commit.verification` reports `verified: true` with reason `valid`

## 6. Phase B: cutover

- [ ] 6.1 In every checkout under the affected accounts and workers, re-sign mutable commits the login key signed: `jj sign -r 'mutable() & mine()'` — verify: `jj log -r 'mutable() & mine()' -T 'signature.key()'` shows only the new key's fingerprint
- [ ] 6.2 Set each `retiredSigningKeys` entry's `validBefore` to the UTC time of authoring, and narrow `validBefore` to a non-null timestamp, removing the null branch that phase A used — verify: `nix eval` of the signers text shows `valid-before="<cutover>"`; `nix build .#checks.x86_64-linux.commit-signing-key`
- [ ] 6.3 Deploy phase B everywhere, recording alerts as in 5.1 — verify: `git verify-commit` on a pre-cutover commit signed by the login key reports good; a scratch commit signed with the login key at the present time is rejected
- [ ] 6.4 Remove the login keys' signing registrations (`cameronraysmith` key 670975; Janette's) — verify: the public API no longer lists them, and a commit pushed before removal still shows `verified: true`

## 7. Integration Verification

- [ ] 7.1 No configured login source on any host carries a signing key — verify: every machine check's `commitSigningObligations.failures` is `[]` (build on x86_64-linux, evaluation on aarch64-darwin), and an attempted login with Cameron's signing key to `root@magnetite.zt` is refused
- [ ] 7.2 No worker holds a login key — verify: on magnetite, pyrite and stibnite, each worker's delivered key's public half is its owner's `signingKey`, and that key fails `ssh -i <key> -o IdentitiesOnly=yes root@<host>.zt true`
- [ ] 7.3 The check key lists equal 1.1 plus `commit-signing-key` — verify: `nix eval` (evaluation)
- [ ] 7.4 Follow-up check, not design-affecting: record whether stibnite's Bitwarden vault holds the login key (brainstorm F4) — verify: with the vault unlocked, `SSH_AUTH_SOCK=<Bitwarden socket> ssh-add -L` on stibnite does or does not list `…INdO9…sqSGyUH+`, recorded in the PR description
