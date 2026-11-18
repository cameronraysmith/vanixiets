## Context

vanixiets keeps secrets in two sops trees that share one admin identity.
Clan's store (`sops/`, `vars/`) holds admin and machine keys and generated secrets; clan-core points sops-nix at `/var/lib/sops-nix/key.txt` whenever `sops/secrets/<m>-age.key/secret` exists (world assumption A117), and only `clan machines update|install` or `clan vars upload` write that file (A116).
The legacy `.sops.yaml` + `secrets/` tree holds home-manager user secrets, the NixOS `hm-sops-bridge` keys, operator credentials in `secrets/shared.yaml`, k3d cluster secrets read in CI through `&ci`, and the Devin `ubuntu` profile; its recipients are ssh-to-age images (A119) of SSH keys held in Bitwarden (A121).

The `sops-*` recipes and `scripts/sops/*` were written in October 2025 for the arrangement before clan and broke or became destructive when `config.nix` was deleted (`ab10e1068`) and stibnite was rehomed (`ba2cbaab7`); brainstorm.md carries the per-item diagnosis.
The design source is the read-only diagnosis of 2026-11-16 and the operator's decisions D15–D22 on it, with follow-up answers on D16's reach; brainstorm.md records each as Q1–Q12.
Stakeholders: the operator, who holds the admin identity, runs every recipe that reads operator credentials, and performs the steps marked **[operator]**; nixbot, which will run the new check on every push; the darwin hosts stibnite, rosegold and argentum, which activate locally.

## Goals / Non-Goals

**Goals:**

- Operator credentials are readable by the offline recovery key and the operator identity only, with no retired host key anywhere in `.sops.yaml`, and no reader any consumer still uses is lost.
- The six legacy recipes, `scripts/sops/` and the random-key `setup-user` path are gone; `update-all-keys` stays and `provision-bridge-key` never writes plaintext into the repository tree.
- Public-key correspondence is checked by a flake check on every push, without Bitwarden.
- A darwin host with a machine key in the repository is not activated without that key installed, and the operator is told the remedy.
- The documentation describes the arrangement as it is.

**Non-Goals:**

- Choosing or self-hosting a Bitwarden client (D18; researched separately).
- Rotating credential values in `secrets/shared.yaml` (D16; the old stibnite disk was wiped).
- Touching the operator's `~/.config/sops/age/keys.txt` or its six identities from other repositories (D21).
- Moving home secrets onto clan vars.
- Changing how NixOS hosts are deployed.

## Decisions

### D1: Recipient changes in `.sops.yaml` (D15, D16)

- **Choice**: delete `&stibnite` (`age1a696…`, stibnite's retired hardware) and `&orb-nixos` (`age140ev…`, machine gone); delete the fileless `secrets/hosts/stibnite/` and `secrets/hosts/orb-nixos/` rules (only `secrets/hosts/.keep` exists); strip both from the fallback rule; set the rule for `secrets/services/*.yaml|secrets/shared.yaml|secrets/test.yaml` to `*admin` + `*admin-user`; on the home-manager rules for raquel, janettesmith, christophersmith, tara and ubuntu replace `*dev` with `*admin-user`; then delete the `&dev` anchor and remove `*dev` from every rule; update the bridge-rule comment ("dev + admin-user required for local re-encryption") to name `admin-user` alone; re-apply with `just update-all-keys`. `&blackphos` stays as an anchor (it still matches blackphos's pinned host key and the `secrets/hosts/blackphos/` rule) but leaves the operator-credential rule. `&ci` stays on `secrets/clusters/local`.
- **Rationale**: the operator's principle: operator credentials are readable by operator identities only, and no file loses a recipient something still decrypts it with. The per-file consumer table below shows every consumer of the narrowed files is an operator-run command reading through `&admin-user`.
- **Evidence for dropping `&ci` from this rule**: the only live workflow with `SOPS_AGE_KEY` is `.github/workflows/test-cluster.yaml:37`, which decrypts `secrets/clusters/local/*` through `modules/apps/cluster/k3d-bootstrap-secrets.sh`; every `sops exec-env secrets/shared.yaml` in CI is under `.github/deprecated/` (`deploy-docs.yaml:106-127`, `scripts/cache-*.sh`, `ci-cache-category.sh`, `test-all-categories-unattended.sh`); `modules/apps/docs/deploy.nix:30` takes secrets from the inherited environment, never from sops.
- **Evidence for retiring `&dev` everywhere (operator decision Q32, option a)**: `&dev` has no live reference outside `.sops.yaml`, the stale `docs/notes/…/sops-secrets-operator.md` and the `sops-rotate` echo text this change deletes; no workflow, Devin blueprint or host reads it (Devin seeds the `ubuntu-user` key, `.devin/blueprint.yaml:159-178`). Its only use was the operator's own: the five home-manager rules for raquel, janettesmith, christophersmith, tara and ubuntu listed only `&admin` (offline), `&dev` and the user, so the operator's `update-all-keys`, `sops rotate` and edits of those files decrypted through `&dev`. Replacing `*dev` with `*admin-user` on those five rules keeps that access through the operator identity, which every other rule already lists, so who can read is unchanged and one key fewer exists. `&dev`'s private copies (Bitwarden `sops-dev-ssh` and the line in the operator's keys.txt) become inert for this repository; deleting them is out of scope, because other repositories may use them and the operator keeps keys.txt as it is (D21).
- **Evidence for dropping `&blackphos`**: `modules/machines/darwin/blackphos/default.nix` and `modules/darwin/` set no system `sops.secrets` or `sops.defaultSopsFile`; every home `defaultSopsFile` is `secrets/home-manager/users/<u>/secrets.yaml` (`modules/home/users/*/default.nix`); the only other `sopsFile` in `modules/` is the NixOS bridge (`hm-sops-bridge.nix:96`). Nothing on blackphos decrypts the narrowed files.
- **Boundary**: source-versus-delivered. `.sops.yaml` is source; the recipients carried by each encrypted file are the delivered form, which `update-all-keys` produces and the new check (D4) compares with the source.
- **Alternatives considered**: splitting the rule so `test.yaml` and `services/` keep broader readers — rejected because the consumer table shows none needs them.

Per-file consumer table for the narrowed rule:

| File | Consumers found (`rg` over the tree, CI, hosts' `sops.secrets`, scripts, recipes, docs deploy) | Reader each uses | Satisfied by `&admin` + `&admin-user` |
|---|---|---|---|
| `secrets/shared.yaml` | `justfile:1030-1065` (`docs-deploy-preview`, `docs-deploy-production`, `docs-deployments`, `docs-tail`, `docs-versions`), `:1417-1446` (`show`, `export`, `check-secrets`, `get-kubeconfig`), `:1527-1532` (`get-shared-secret`, `run-with-secrets`), `:1609-1612` (CI secret upload), `:1626` (`act`), `:1669-1715` (cachix pushes), `:1814` (local Renovate token fallback); `Makefile:368` (`check-secrets`); `.github/deprecated/*` only in CI; no host or home `sops.secrets` | the operator's keys.txt (`&admin-user`) | yes |
| `secrets/test.yaml` | `justfile:1423` (`show`) only | `&admin-user` | yes |
| `secrets/services/*.yaml` | none; the directory holds only `.keep` | — | yes (vacuously; the rule governs future files) |

Rules that lose `&dev` and gain `&admin-user` (operator decision, applied in slice 1): the home-manager rules for raquel, janettesmith, christophersmith, tara and ubuntu, and the two `secrets/users/raquel-user/` rules, which had the same `&admin` + `&dev` + user shape. Each file under them is decrypted by its user through that user's key (unchanged) and by the operator through `&admin-user` instead of `&dev`; the `secrets/users/raquel-user/` files are deleted later under D10.

### D2: Renew the data key of narrowed files, not the credentials

- **Choice**: after `update-all-keys`, run `sops rotate --in-place` on `secrets/shared.yaml` and `secrets/test.yaml`.
- **Rationale**: `updatekeys` keeps the data key (A120), so a removed recipient that ever unwrapped it could read values written later; `rotate` closes that for future values. It changes no credential value, so it stays inside D16. Files that lose only `&dev` are not rotated: its only holder is the operator, who remains a reader through `&admin-user`, so no former holder gains anything from the old data key.
- **Residual**: earlier commits stay readable by their recipients of the time (A120); with no credential rotation that is the exposure the operator accepted under D16, and the trust boundary in `secret-custody-interface` says so.

### D3: Darwin host keys become static flake data

- **Choice**: move the literal darwin host keys (blackphos, stibnite, argentum, rosegold) from inside `mkKnownHosts` in `modules/system/ssh-known-hosts.nix` to `flake.lib.darwinHostKeys` in a new `modules/lib/darwin-host-keys.nix`, which `ssh-known-hosts.nix` reads.
- **Rationale**: the correspondence check needs blackphos's pinned key; reading it today means evaluating a host configuration, which the evaluation-cost rule forbids in a check (skill `preferences-nix-checks-architecture`, "Key-set strictness"). One source keeps the known-hosts pin and the anchor comparison from drifting apart.
- **Boundary**: source-versus-delivered. Task 2.1 proves the delivered `programs.ssh.knownHosts` values are unchanged on a darwin and a NixOS host.

### D4: A sibling flake check, `sops-correspondence`

- **Choice**: new `modules/checks/sops-correspondence.nix`, `checks.x86_64-linux.sops-correspondence` gated with `lib.optionalAttrs (system == "x86_64-linux")`, a `runCommand` over `lib.fileset.toSource` of `.sops.yaml`, `sops/users`, `sops/machines` and `secrets`, with `ssh-to-age`, `jq` and `yq-go`. A static table in the module classifies every anchor: users `{ admin-user = "crs58"; raquel-user = "raquel"; janettesmith-user = "janettesmith"; christophersmith-user = "christophersmith"; tara-user = "tara"; }`; clan users `{ cameron = "crs58"; crs58 = "crs58"; raquel = …; janettesmith = …; christophersmith = …; }`; machines cinnabar, electrum, galena, scheelite, magnetite, pyrite; host keys `{ blackphos = "blackphos"; }`; runners `ci`, `ubuntu-user` (the Devin profile, which has no `meta.sshKeys`); recovery `admin`. `dev` is in no class, so reintroducing it fails the check. The users' first `meta.sshKeys` and `flake.lib.darwinHostKeys` are passed as files. It checks the diagnosis's invariants 1–4 and fails on an unclassified anchor, a classified name without an anchor, or an empty scan. Anchors are read with yq's `anchor` and rule entries with `alias`; a file's rule is the first whose `path_regex` matches its repository-relative path under `jq`'s `test`.
- **Rationale**: drift is caught on the push that introduces it, from public data, with no Bitwarden session. A sibling keeps `commit-signing-key.nix` about signing keys; that check's recipient scan answers a different question (is any signing key a recipient) and stays as it is. Static names and one system keep the key set free of host evaluation. Mutant cases inside the derivation, one per failure mode, give the check its integrity witness without rerunning the whole case set per mutant.
- **Alternatives considered**: extending `commit-signing-key.nix`'s scan — it would couple two unrelated regulators so a signing-key change rebuilds the correspondence check and vice versa; a `just` doctor recipe — it runs only when someone remembers; computing ssh-to-age in Nix — no pure implementation exists in the repository, so it is a build-time comparison.
- **Known approximation**: sops matches `path_regex` with Go's RE2; the check uses Oniguruma through `jq`. The patterns in `.sops.yaml` use only anchors, literal dots, `.*`, alternation and groups, on which both agree; a rule using an RE2-only or Oniguruma-only construct would need the check revisited.

### D5: Bridge recipients asserted at host evaluation

- **Choice**: in `modules/nixos/hm-sops-bridge.nix`, add per bridged user an assertion that `sops/machines/<host>/key.json`'s public key is among `secrets/bridge/<sopsIdentity>-age-key.enc`'s `.sops.age[].recipient`, both read with `builtins.fromJSON (builtins.readFile …)` from `inputs.self`.
- **Rationale**: invariant 5 needs per-host facts the host's own evaluation already has; the placement ladder puts a fact about configuration values in a module assertion, checked on real hosts by `modules/checks/machines.nix` and every deploy, at no new evaluation cost. The binary sops store is JSON on disk, as `validation.nix:135-188` already relies on.
- **Boundary**: source-versus-delivered; the assertion reads the committed ciphertext metadata, which is what the host will decrypt.

### D6: The machine-key guard lives in the `.#darwin` app

- **Choice**: `modules/darwin/app.nix` gains, at evaluation, a table of expected machine public keys (`flake.lib.darwinMachineKeys`) for every darwin configuration whose `sops/secrets/<host>-age.key/secret` exists, read from `sops/machines/<host>/key.json`. Before `nh darwin switch`, for a hostname in the table, the app runs the shared guard script `modules/darwin/machine-key-guard.sh`, packaged as `flake.lib.darwinMachineKeyGuard pkgs` and exercised by `checks.x86_64-linux.darwin-machine-key-guard`. The script reads `age-keygen -y "${MACHINE_KEY_FILE:-/var/lib/sops-nix/key.txt}"` directly when the file is readable. Otherwise it decides existence and reads the key as root through `sudo`, because clan's upload leaves `/var/lib/sops-nix` root-only (`0700`), so an unprivileged existence test cannot see the file. It uses `sudo -n` under `--dry`, so a dry run never blocks on a prompt, and plain `sudo` otherwise. It compares the result with the expected key. On a missing file, a mismatch, an unreadable file or a `sudo` that cannot run, it prints the host, both public keys (or "missing", "present but unreadable" or "not checked") and `clan vars upload <host>`, and exits 1. The app then stops, or continues under `--dry`. `MACHINE_KEY_FILE` exists so the guard can be exercised without touching the real key. (Revised at archive: the comparison first lived inline in the app and tested existence without `sudo`; see the retrospective.)
- **Rationale**: `just activate` and `just activate-darwin` both run this app, and so does a direct `nix run .#darwin`, so one guard covers every local activation path (D17 names `activate-darwin`; this placement satisfies it and also covers the direct path). Local activation never installs the key (A116), and sops-nix then fails the secret install (A118), so stopping first, with the remedy, replaces a late, obscure failure. `age-keygen -y` prints only the public key. `nh` elevates with sudo for activation anyway, so the guard's `sudo` adds no new privilege.
- **Alternatives considered**: a check in the `justfile` recipe only (misses `nix run .#darwin`); an activation-script assertion inside nix-darwin (runs after the build, as root, and cannot stop `nh` before it starts); switching darwin deploys to `clan machines update` (the diagnosis's D3 alternative, not chosen by the operator).
- **Boundary**: source-versus-delivered. The table is baked in from the flake the app was built from; a remote flake argument whose keys differ from the app's own would be compared against the app's table. Activation through `darwin-rebuild` directly bypasses the guard; the trust boundary says so.

### D7: `provision-bridge-key` encrypts from a pipe

- **Choice**: `bw get item … | jq -r '.sshKey.privateKey' | ssh-to-age -private-key | sops encrypt --filename-override "$target" --input-type binary --output-type binary /dev/stdin > "$tmp"`, with `set -euo pipefail`, `tmp=$(mktemp)` and a trap removing it, then `mv "$tmp" "$target"` only after sops exits 0 and `$tmp` is a non-empty sops JSON envelope.
- **Rationale**: the plaintext age key exists only in the pipe; `$tmp` and the target only ever hold ciphertext; a failure leaves the previous target as it was. sops 3.13.3 reads stdin and needs `--filename-override` to find the creation rule (`sops encrypt --help`).
- **Alternatives considered**: encrypting a `mktemp` plaintext file — leaves plaintext on disk briefly outside the repository, which the pipe avoids.

### D8: The current-architecture description the docs converge on

The secrets guide is rewritten around this description, from the diagnosis:

> vanixiets has two sops trees that share one admin identity. Clan's store holds admin keys (`sops/users/{cameron,crs58}/key.json`, the ssh-to-age image of crs58's login key, also the `.sops.yaml` anchor `&admin-user`) and machine keys (`sops/machines/<m>/key.json`, whose private keys are `sops/secrets/<m>-age.key`, encrypted to the admin user). `clan vars generate` writes generated secrets under `vars/`. On a host, sops-nix reads the machine key from `/var/lib/sops-nix/key.txt`, which only `clan machines update|install` or `clan vars upload <m>` install; darwin hosts activated with `just activate` need `clan vars upload <host>` once, and the activation guard enforces it.
> The legacy `.sops.yaml` + `secrets/` tree carries home-manager user secrets (`secrets/home-manager/users/<u>/secrets.yaml`, decrypted with `~/.config/sops/age/keys.txt`), the NixOS bridge keys (`secrets/bridge/<id>-age-key.enc`, encrypted to the NixOS machine keys), operator credentials (`secrets/shared.yaml`, operator only), k3d cluster secrets (`secrets/clusters/local`, also read by CI through `SOPS_AGE_KEY`) and the Devin `ubuntu` profile.
> Bitwarden holds the SSH key pairs whose ssh-to-age images are the legacy-tree recipients; it is the source for a workstation's keys.txt entry and for bridge keys, and holds no clan machine key. The `&admin` key is an offline recovery key. `checks.x86_64-linux.sops-correspondence` keeps the public keys in agreement.

### D9: One workstation-key convention, documented, with no new script (D19)

- **Choice**: delete `setup-user` (app, Makefile target, recipe, bootstrap hint, `cd.yaml` steps) and document the procedure: `bw get item sops-<id>-user-ssh | jq -r .sshKey.privateKey | ssh-to-age -private-key`, appended to `~/.config/sops/age/keys.txt` only when `age-keygen -y` of the file lacks that public key, never overwriting the file.
- **Scope check (operator Q28)**: every part of `setup-user` serves the random key, so D19 removes all of it rather than only a key path:
  - `modules/apps/bootstrap/setup-user.sh:27-46` checks for `~/.config/sops/age/keys.txt` (re-printing its public key if present), else runs `age-keygen -o`, `chmod 600` and prints the public key; `:48-58` and `:5-16` are the back-up-to-Bitwarden-note and usage text for that key. Nothing else.
  - `modules/apps/bootstrap/setup-user.nix:9-24` wraps that script with `coreutils` and `age` only.
  - `justfile:442-447` `bootstrap-setup-user` runs only `nix run .#setup-user`.
  - `Makefile:338-359` `setup-user` repeats the same key generation inline (`age-keygen -o`, `chmod 600`, the Bitwarden-note text, a pointer to the deleted `docs/new-user-host.md`); `Makefile:7` and `:80` are header lines telling the reader to run it.
  - `.github/workflows/cd.yaml:88-90` runs `make setup-user`; `:92-101` checks that `keys.txt` exists and prints its public key. The job's other steps (`make bootstrap`, the nix and direnv checks, `make verify`, the result marker) are untouched.
  - `modules/apps/bootstrap/bootstrap.sh:59` is a hint to run it.
- **Rationale**: a Bitwarden-derived key is the same on every workstation (A119) and matches the anchor the check verifies. The procedure is three commands, so it stays documented rather than scripted; `provision-bridge-key` remains the one recipe that calls `bw` (D12).
- **Impact**: the CD bootstrap job stops generating and checking a throwaway key; its other steps are unchanged.

### D10: Orphans are deleted after an operator check (D20)

- **Choice**: the operator decides per file from the key names in tasks.md 5.1; migrations go through `sops set`; then `secrets/users/` and its four rules are deleted, together with the `hash-encrypt` recipe (`justfile:1448-1472`), whose only target is `secrets/users/<user>/` (operator Q30), and the `verify-hash` recipe (`justfile:1473-1512`), which only checks files named by `hash-encrypt`'s content-hash scheme and so has no subject once those files are gone (operator, same principle).

### D11: Rotation is a documented procedure

- **Choice**: machine keys rotate through clan (`clan vars generate`, `clan vars fix`, `clan secrets key update`, then `clan machines update` or `clan vars upload`); legacy recipients through the `.sops.yaml` anchor, `just update-all-keys`, `sops rotate --in-place` on files that lost a recipient, and `just provision-bridge-key` for affected bridge identities; the correspondence check confirms the result. No tool writes `.sops.yaml` or a host key.

### D12: The sops tooling uses only nixpkgs' `bw` (operator D25)

- **Choice**: `bw` from nixpkgs (`modules/home/security/tools.nix:11` `bitwarden-cli`, wrapped by `modules/nixpkgs/overlays/bitwarden-cli.nix`) is the only Bitwarden client the sops tooling and its documented procedures use; remove the `npmbw` alias (`modules/home/shell/aliases.nix:12`, `bunx -p @bitwarden/cli bw`), which runs an unpinned client fetched from npm at call time.
- **Rationale**: a key-handling command should run a client whose version the flake pins and the binary cache serves, not whatever npm resolves that day. The wider client choice and self-hosting remain out of scope (D18).
- **Boundary**: vendored-versus-first-party. nixpkgs' `bitwarden-cli` is vendored and pinned by `flake.lock`; the alias was a first-party bypass of that pin.

### Documentation table

| Location | Action | Task |
|---|---|---|
| `justfile:1938-2003` (six recipes, the "config.nix ↔ Bitwarden" comment) | delete | 4.1 |
| `scripts/sops/*.sh` | delete | 4.2 |
| `.sops.yaml:9`, `:17-20` | rewrite comments; drop orb-nixos and stibnite | 1.2 |
| `packages/docs/…/guides/secrets-management.md:117-271`, `:20,37,425,440-472`, `:297-418,474-526` | rewrite (D8 and three procedures) | 6.1 |
| `packages/docs/…/reference/justfile-recipes.md:182-183,192-203` | delete the six `sops-*` rows and the `hash-encrypt` and `verify-hash` rows, keep `update-all-keys`, add `provision-bridge-key`, drop `bootstrap-setup-user` | 6.2 |
| `packages/docs/…/development/traceability/test-harness.md:58` | rewrite | 6.8 |
| `packages/docs/…/tutorials/secrets-setup.md:15-19,39-91,118-196`; `tutorials/index.md:59,112` | rewrite | 6.3 |
| `packages/docs/…/concepts/clan-integration.md:146-201,227-274,247-250` | rewrite | 6.4 |
| `packages/docs/…/concepts/system-user-integration.md:309-326` (found while writing this change) | rewrite | 6.5 |
| `packages/docs/…/guides/host-onboarding.md:14-15,127-172` | rewrite; `:316-331` kept | 6.6 |
| `packages/docs/…/development/architecture/adrs/0011-sops-secrets-management.md` | keep; add "superseded in part" note | 6.7 |
| ADRs 0001, 0019, 0020 (`secrets/users/…` examples) | keep as historical records | — |
| `docs/notes/development/research/ci-docs-execution-coverage.md:133-140,285` | rewrite or regenerate | 6.8 |
| `docs/notes/development/kubernetes/components/sops-secrets-operator.md:143-144,392` | rewrite | 6.8 |
| `modules/nixos/hm-sops-bridge.nix:9-12` | rewrite | 6.8 |
| `modules/apps/bootstrap/setup-user.{nix,sh}`, `Makefile:7,80,338-359,365`, `justfile:442-447`, `bootstrap.sh:59`, `.github/workflows/cd.yaml` setup-user steps | delete or rewrite | 4.4 |
| `justfile:1448-1512` (`hash-encrypt`, `verify-hash`) | delete | 5.3 |
| `modules/home/shell/aliases.nix:12` (`npmbw`) | delete | 4.5 |
| `openspec/specs/bare-metal-install-path/spec.md:138` | keep (`update-all-keys` stays) | — |
| `modules/home/ai/plugins/preferences-nix-and-secrets/.apm/skills/preferences-secrets/SKILL.md:567-580` | keep (general guidance) | — |

Passages found by the retired-name sweep during apply (operator-approved, same principle), rewritten in slice 3:

| Location | Action | Task |
|---|---|---|
| `packages/docs/…/guides/getting-started.md:39,84-93,280-289` (`make setup-user`) | rewrite to the workstation-key procedure | 6.9 |
| `packages/docs/…/guides/mcp-server-usage.md:48-121` (`secrets/users/<u>/mcp-api-keys.yaml`) | rewrite to the home-manager secrets file | 6.9 |
| `packages/docs/…/guides/home-manager-onboarding.md` (`secrets/users/*.sops.yaml`, `age-keygen -o`) | rewrite | 6.9 |
| `packages/docs/…/development/architecture/architecture.md:293-296,442,567,696` | rewrite paths | 6.9 |
| `packages/docs/…/development/context/glossary.md:156`, `tutorials/darwin-deployment.md:63-64,334-335` ("clan vars NixOS-only") | rewrite | 6.9 |
| `packages/docs/…/reference/ci-jobs.md:234`, `development/traceability/test-harness.md:24` (`make setup-user`) | rewrite | 6.9 |
| `docs/notes/development/kubernetes/workflows/04-hetzner-deployment.md:527-536` (`--field notes` into a `/tmp` file), `03-clusterapi-bootstrap.md:80-88` (overwrote `keys.txt`) | rewrite | 6.9 |
| `.gitleaksignore:13,15`, `docs/notes/development/hardware/mbp141-nixos-clan-research.md:109` | keep (history allow-list; dated research note) | — |
| `scripts/verify-no-secrets-in-store.sh:78-91` (looks for `mcp-api-keys.yaml` in the store) | keep; after D20 it only reports its "not found" warning (operator: leave as is) | — |

## Risks / Trade-offs

- [Risk] Two in-flight changes replace the same `world-assumptions` requirement "Grounded vocabulary for behavioral requirements" (this one and `stand-up-renovate-on-magnetite`); MODIFIED applies by full replacement, so whichever archives second drops the other's rows. → Mitigation: an archive-time task in each change (tasks.md 7.7 here, 9.7 there) merges the table with every row the other change added before the second archives.
- [Risk] Earlier commits of `secrets/shared.yaml` stay decryptable by the removed identities. → Accepted under D16 (no credential rotation); stated in the trust boundary and the behavioral requirement on narrowing.
- [Risk] A consumer of `shared.yaml` was missed and loses access. → Mitigation: the consumer table's search covered recipes, scripts, CI (live and deprecated), hosts' and homes' `sops.secrets`, and docs deploy; tasks 1.5–1.7 decrypt as each remaining consumer; the change is a revert of `.sops.yaml` plus `update-all-keys` away if one appears (the data key rotation does not need reverting).
- [Risk] The guard's `sudo` prompts earlier than `nh` would. → Accepted; `nh` prompts in the same run.
- [Risk] The guard compares against the app's own table when given a remote flake argument. → Accepted; documented in D6 and the trust boundary.
- [Risk] Regex dialect difference between sops and the check (D4). → Accepted for today's patterns; noted in the module header.
- [Trade-off] `ubuntu-user` is classified as a runner and not compared with any login key, because the Devin profile has no `meta.sshKeys`. → Accepted; the classification table makes the exemption explicit.
- [Trade-off] The CD bootstrap job no longer exercises key generation. → Accepted; there is no longer a key-generation step to exercise.
- [Risk] Removing `&dev` re-wraps every file under `secrets/`, including the bridge keys and home secrets that hosts and homes decrypt. → Mitigation: their machine and user recipients are unchanged, so the delivered files still decrypt; task 1.5 decrypts each home file with its user's key and the operator's, and task 7.6 deploys one bridged NixOS host to observe it.

## Migration Plan

1. Group 1 first, as one commit: `.sops.yaml`, `update-all-keys`, `sops rotate`, consumer checks. The narrowed operator-credential files are in no host's closure. The `&dev` removal re-wraps `secrets/bridge/*.enc` and `secrets/home-manager/users/*/secrets.yaml`, which NixOS host and home closures carry; only recipient metadata changes and every machine and user recipient stays, so each host picks the new files up at its next `clan machines update` (or `just activate` for darwin homes) with no behaviour change. Task 7.6 deploys one bridged NixOS host to observe this; the rest follow at their next routine deploy.
2. Groups 2–6 in any order; group 2's check must pass before the pull request is enqueued.
3. Land through nixbot and gitea-mq.
4. Activate stibnite locally (task 7.4), which exercises the guard. Beyond task 7.6, no NixOS deploy is required: the bridge assertion and the known-hosts hoist change no evaluated value (task 2.1 proves the latter), and the darwin app is a local tool.
5. **[operator]** `clan vars upload argentum` when argentum is next online. rosegold needs nothing: its `/var/lib/sops-nix/key.txt` was installed by hand on 2026-11-16 and matches `sops/machines/rosegold/key.json` (operator, Q29).

Rollback: revert the pull request. For group 1, reverting `.sops.yaml` and running `just update-all-keys` restores the broader recipients; the rotated data key needs no revert.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record.
It carries one row per requirement in this change's three delta specs, with the capability's stratum tag from the proposal and the modality that witnesses the requirement.

No row routes to a Gherkin scenario, so this change lays out no `.feature` file.
The repository has no BDD runner (no pytest-bdd, cucumber or behave dependency, and no `.feature` file in the tree), so a laid-out scenario would be an unbound surface nothing executes.
Every observable this change asserts is a property of `.sops.yaml` and the encrypted files' metadata, of the evaluated flake, or of a recipe or app run, which the flake check, `nix eval`, and smoke runs against the repository and stibnite witness.
Where a scenario has no task that observes it, the row says so rather than naming a witness.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| Operator credentials are readable only by the operator | `secret-custody` | behavioral | smoke (sops decryption) | tasks 1.2, 1.3, 1.5, 1.6 |
| The operator identity can read every secret file | `secret-custody` | behavioral | smoke (sops decryption) and content search | tasks 1.2, 1.3, 1.5 |
| No retired host is a reader of any secret file | `secret-custody` | behavioral | content search and build gate (flake check) | tasks 1.2, 2.2, 2.3; the scenario's rehoming case is witnessed only through the `&blackphos` mutant, not by a rehoming |
| Narrowing a secret file's readers keeps every reader still in use and renews its protection | `secret-custody` | behavioral | smoke (decryption, digests) | tasks 1.3–1.7; the scenario "A removed reader holds an earlier commit" has no witnessing task (residual exposure, accepted under D16) |
| Every public key the repository names corresponds to the person or machine it names | `secret-custody` | behavioral | build gate (flake check, mutants) | tasks 2.2, 2.3, 7.1, 7.5 |
| Every host can read the personal keys it delivers to its users | `secret-custody` | behavioral | build gate (evaluation assertion, negative control) | tasks 2.5, 7.3 |
| A darwin host is not activated without its machine key | `secret-custody` | behavioral | smoke (app runs on stibnite, activation) | tasks 3.1, 3.2, 3.4, 7.4; the scenario "The host has no machine key in the repository" is witnessed only by the evaluated table excluding blackphos (3.1), not by a run on blackphos |
| Provisioning a key never leaves a private key in the repository's working tree | `secret-custody` | behavioral | smoke (scratch run with fake key store, negative control) | task 4.3 |
| A workstation's personal key is derived from the person's SSH key in the key store | `secret-custody` | behavioral | content search and documentation | tasks 4.4, 6.1; the scenario "A person sets up a second workstation" has no witnessing task — its argument rests on A119 |
| No maintenance tool rewrites readers or host identities from an external source | `secret-custody` | behavioral | content search (recipe and app listing) | tasks 4.1, 4.2, 4.4; the scenario "The operator rotates a person's reader" has no witnessing task, since no rotation is performed |
| The documentation describes only current procedures | `secret-custody` | behavioral | content search and docs build | tasks 6.1–6.9; existence of every named command and path is checked for the secrets guide (6.1) and by the retired-name sweep (6.9), not page by page |
| This capability states its own trust boundary | `secret-custody-interface` | interface | capability text and documentation | specs text, task 6.1 |
| Operator-credential files are encrypted to the recovery key and the operator identity only | `secret-custody-interface` | interface | content search and smoke | tasks 1.2, 1.3, 1.6 |
| No rule names the retired development key, and every rule names the operator identity | `secret-custody-interface` | interface | content search, build gate and smoke | tasks 1.2, 1.3, 1.6, 2.3 |
| No retired host's key is an anchor or a rule | `secret-custody-interface` | interface | content search | task 1.2 |
| Narrowed files carry a renewed data key | `secret-custody-interface` | interface | content comparison (MAC, plaintext digest) | task 1.4 |
| The correspondence check runs on public data at static cost | `secret-custody-interface` | interface | build gate and content search | tasks 2.2, 2.3, 2.4 |
| The correspondence check compares user anchors and clan user keys with login keys | `secret-custody-interface` | interface | build gate (mutant) | tasks 2.2, 2.3 |
| The correspondence check compares machine anchors with clan machine keys | `secret-custody-interface` | interface | build gate (mutant) | tasks 2.2, 2.3 |
| The correspondence check compares host-key anchors with pinned darwin host keys | `secret-custody-interface` | interface | build gate (mutant) | tasks 2.1, 2.2, 2.3 |
| The correspondence check compares each file's recipients with its rule | `secret-custody-interface` | interface | build gate (mutant) | tasks 2.2, 2.3 |
| The correspondence check accounts for every anchor | `secret-custody-interface` | interface | build gate (mutant) | tasks 2.2, 2.3 |
| Darwin host keys are static flake data | `secret-custody-interface` | interface | build gate (`nix eval`, before/after identity) | tasks 2.1, 2.4 |
| Each NixOS host asserts it is a recipient of the bridge files it uses | `secret-custody-interface` | interface | build gate (evaluation, negative control) | task 2.5 |
| The `.#darwin` app refuses activation without the host's machine key | `secret-custody-interface` | interface | build gate (`nix eval` of the table) and smoke (app runs) | tasks 3.1, 3.2, 7.4; the scenario "Host without a machine key" is witnessed only by the table's evaluation |
| `provision-bridge-key` keeps plaintext out of the repository tree | `secret-custody-interface` | interface | smoke (scratch run, negative control) | task 4.3 |
| The retired recipes, scripts and app are absent | `secret-custody-interface` | interface | content search (`just --summary`, `nix eval` of apps and aliases) | tasks 4.1, 4.2, 4.4, 4.5, 5.3 |
| A116 — Only clan's deployment and upload commands install a host's machine key | `world-assumptions` | world | violation-condition witness | its own scenario |
| A117 — clan-core points sops-nix at the uploaded machine key exactly when the repository holds one | `world-assumptions` | world | violation-condition witness | its own scenario |
| A118 — sops-nix fails to install secrets when its configured age key file cannot be read | `world-assumptions` | world | violation-condition witness | its own scenario |
| A119 — ssh-to-age maps one ed25519 key to one age key, deterministically | `world-assumptions` | world | violation-condition witness | its own scenario |
| A120 — sops updatekeys keeps a file's data key, and only sops rotate renews it | `world-assumptions` | world | violation-condition witness | its own scenario |
| A121 — A Bitwarden SSH key item carries its key pair in the sshKey fields | `world-assumptions` | world | violation-condition witness | its own scenario |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | designation table and its lint | the table itself |

No row carries an `est-property`, `est-contract`, or `est-symbolic` modality, so this change carries no executable-specification-testing obligation.

## Open Questions

- None open. Resolved by the operator and recorded above: rosegold's key is installed (Q29, Migration Plan step 5); `hash-encrypt` and `verify-hash` are deleted (Q30 and its follow-up, D10); the designation-table merge is a task in both changes (Q31, Risks); `&dev` is retired from every rule (Q32, D1); only nixpkgs' `bw` is used (D25, D12); `setup-user` is all key-related and removed whole (Q28, D9).
