<!--
Raw capture of the brainstorming step for this change.

Procedural note, recorded rather than elided: the interactive `superpowers:brainstorming`
dialogue was not run inside this change. The exploration happened upstream on 2026-11-16:
a read-only diagnosis session (SopsToolingDiagnosis) read the `sops-*` recipes and
`scripts/sops/*`, their git history, `.sops.yaml`, every tracked file's sops metadata,
clan-core's vars and sops modules at the pinned revision, and the docs that describe the
arrangement. Only public-key data was read. The operator then decided D15–D22 on it.
This file is the decision log the interactive skill would have produced: each question,
the options, the answer taken, and the evidence. Answers the operator gave are marked
`[given]`; answers settled from source or repository evidence while writing this change
are marked `[decided]`.

Citation abbreviations used throughout this change:
- C: clan-core at the flake.lock pin `dbae21013aca`.
- N: sops-nix at the flake.lock pin `fe7b4228405a`.
- S2A: ssh-to-age 1.3.0, the version nixpkgs `6dadaf4375be` ships.
- SK: getsops.io, "Key management" (https://getsops.io/docs/usage/key-management/);
  the pinned sops is 3.13.3.
-->

# Background

vanixiets has two sops trees that share one admin identity.

Clan's store holds admin and machine keys. `sops/users/{cameron,crs58}/key.json` are both the
ssh-to-age image of crs58's login key (`modules/home/users/crs58/meta.nix:11`), which is also
the `.sops.yaml` anchor `&admin-user`. `sops/machines/<m>/key.json` covers the six NixOS hosts
plus stibnite, rosegold, argentum and gcp-vm; each machine's private key is in
`sops/secrets/<m>-age.key/secret`, encrypted to the admin user. Generated secrets live under
`vars/`. On the host, C sets `sops.age.keyFile = /var/lib/sops-nix/key.txt` whenever
`sops/secrets/<m>-age.key/secret` exists (C `nixosModules/clanCore/vars/secret/sops/default.nix:52-54`;
`nix eval .#darwinConfigurations.stibnite.config.sops.age.keyFile` prints `/var/lib/sops-nix/key.txt`
on 2026-11-16). That file is written only by `clan machines update`, `clan machines install` or
`clan vars upload <m>` (C `pkgs/clan-cli/clan_lib/vars/upload.py`,
`clan_lib/vars/secret_modules/sops.py:243-260`, `clan_lib/machines/update.py:612`).

The legacy `.sops.yaml` + `secrets/` tree carries home-manager user secrets, the NixOS
`hm-sops-bridge` keys under `secrets/bridge/`, operator and CI credentials in
`secrets/shared.yaml`, k3d cluster secrets in `secrets/clusters/local` (decrypted in CI through
`SOPS_AGE_KEY`, the `&ci` key, `.github/workflows/test-cluster.yaml:37`), and the Devin
`ubuntu` profile. Bitwarden holds the SSH keypairs whose ssh-to-age images are the legacy
recipients; it holds no clan machine key.

The `sops-*` family (`justfile:1938-2003`, `scripts/sops/*.sh`) was written in a two-day burst
(`c02cc2521` 2025-10-08 through `28568262a` 2025-10-09) for the model before clan: identities in a
root `config.nix`, host keys generated in Bitwarden and deployed to `/etc/ssh`, and a generated
`.sops.yaml`. `config.nix` was deleted in `ab10e1068` (2025-11-24), and every architectural
change since bypassed the scripts. The diagnosis classified them:

| Item | State today |
|---|---|
| `sops-validate-correspondences` | broken: exits at `validate-correspondences.sh:69` reading the deleted `config.nix` |
| `sops-update-yaml` | destructive: overwrites `.sops.yaml` with a 7-rule template whose paths lack `secrets/`; after `updatekeys` the bridge, cluster, home-manager and per-user rules fall through to the fallback |
| `sops-extract-keys` | read-only but stale (lists orb-nixos; misses four identities) |
| `sops-sync-keys` | destructive: rewrites `~/.config/sops/age/keys.txt` with dev + admin-user + the retired stibnite host key, dropping every other identity |
| `sops-deploy-host-key` | dangerous: would overwrite stibnite's `/etc/ssh` host key that `modules/system/ssh-known-hosts.nix:98` pins fleet-wide |
| `sops-rotate` | chains the above |
| `update-all-keys` | works; every tracked file's recipients equal its rule; `openspec/specs/bare-metal-install-path/spec.md:138` relies on it |
| `provision-bridge-key` | works; consumed by `modules/nixos/hm-sops-bridge.nix:81-104`; writes plaintext into the tracked target before encrypting in place |

Risks found: `&stibnite` (`age1a696…`) is the ssh-to-age image of stibnite's *retired*
hardware's host key (rehomed in `ba2cbaab7`, 2026-07-10), `&orb-nixos` names a machine that no
longer exists, and both, with raquel, janettesmith and christophersmith, can read
`secrets/shared.yaml` (GitHub, Cloudflare, Cachix and flake-updater credentials). Darwin hosts
activated locally by `just activate` never receive `/var/lib/sops-nix/key.txt`, so rosegold and
argentum, which gained per-machine secrets in `8f73d2566`, fail `sops-install-secrets` unless
someone ran `clan vars upload`.

# Decision chain

Q1. What happens to the five dead recipes, `sops-rotate` and `scripts/sops/*`? `[given]`
- Options: repair them against the clan model; delete them.
- Taken: delete all of them, including `sops-sync-keys`, which is dangerous today. Rotation
  becomes a documented procedure using clan and sops commands; no script writes `.sops.yaml`.

Q2. Which sops recipes survive? `[given]`
- `update-all-keys` stays (working, relied on by a spec). `provision-bridge-key` stays and is fixed
  to encrypt from stdin or a temporary file outside the repository, so plaintext never lands in a
  tracked path.

Q3 (D15). The `&stibnite` and `&orb-nixos` anchors. `[given]`
- Remove both and re-apply recipients with `just update-all-keys`.
- `[decided]` with operator confirmation: remove the now-fileless rules
  `secrets/hosts/{stibnite,orb-nixos}/.*` (only `secrets/hosts/.keep` exists) and strip both anchors
  from the fallback rule.

Q4 (D16). Who may read `secrets/shared.yaml`? `[given]`
- Narrow to the operator identity, plus `dev`/`ci` only where something verifiably uses them;
  remove raquel-user, janettesmith-user and christophersmith-user. No token rotation: the operator
  is certain the old stibnite disk was wiped.
- Operator principle (2026-11-16): operator credentials are readable by operator identities only,
  and no file may lose a recipient that something still decrypts it with.
- Follow-ups `[given]`: keep `&admin` (offline recovery). Drop `&blackphos` provided nothing on
  blackphos decrypts these files at activation. Drop `dev` and `ci` on the evidence below; leave
  `ci` on `secrets/clusters/local`. Narrow `test.yaml` and `services/*.yaml` with `shared.yaml` only
  if each file's consumers are satisfied by `&admin` + `&admin-user`; otherwise split the rule.
- Evidence `[decided]`:
  - `ci`: live workflows using `SOPS_AGE_KEY` are only `.github/workflows/test-cluster.yaml:37`,
    which decrypts `secrets/clusters/local` through `modules/apps/cluster/k3d-bootstrap-secrets.sh`;
    every `sops exec-env secrets/shared.yaml` in CI is under `.github/deprecated/`.
  - `dev`: no live reference outside `.sops.yaml`, the stale K8s note and the `sops-rotate` echo
    text; the operator's keys.txt also holds `admin-user`, so nothing loses access.
  - blackphos: `modules/machines/darwin/blackphos/default.nix` and `modules/darwin` set no
    system `sops.secrets`/`defaultSopsFile`; every home `defaultSopsFile` is
    `secrets/home-manager/users/<u>/secrets.yaml`; the only other `sopsFile` is the bridge.
  - Consumers of `shared.yaml` are operator-run recipes (`justfile:1030-1065` docs deploy,
    `:1417-1446`, `:1527-1532`, `:1609-1612`, `:1626`, `:1669-1715`, `:1814`), `Makefile:368`, and
    deprecated workflows. `test.yaml`: `just show` (`justfile:1423`) only. `secrets/services/`
    holds only `.keep`. All are satisfied by `&admin-user`.
- Additional `[decided]`: `sops updatekeys` re-wraps the existing data key; SK recommends
  `sops rotate --in-place` after removing a recipient, otherwise a former recipient that held the
  data key can read values written later. Rotating the data key is not rotating the tokens, so it
  stays within D16.

Q5 (D17). How does a locally activated darwin host get its machine key? `[given]`
- Add a fail-fast guard to darwin activation: when the host has `sops/secrets/<host>-age.key` and
  `/var/lib/sops-nix/key.txt` is missing or its public key differs from
  `sops/machines/<host>/key.json`, stop with a message naming `clan vars upload <host>`. Document it.
  argentum needs `clan vars upload` when next online (operator step).
- Placement `[decided]`: inside the `.#darwin` app (`modules/darwin/app.nix`) that
  `just activate-darwin` and `just activate` run, so a direct `nix run .#darwin` is guarded too; the
  expected public keys are baked in at evaluation from the repository's public files.

Q6 (D18). Bitwarden's role. `[given]`
- Bitwarden stays the source of the legacy tree's identities for now. Which client to use is
  researched separately and is out of scope.

Q7 (D19). One workstation-key convention. `[given]`
- Bitwarden-derived: a workstation's keys.txt entry is `ssh-to-age -private-key` of the person's
  Bitwarden SSH item. Remove setup-user's random-key path (`modules/apps/bootstrap/setup-user.sh`,
  `Makefile:354-356`).
- Reach `[decided]`: the random-key path is the whole of `setup-user`, so the app
  (`modules/apps/bootstrap/setup-user.{nix,sh}`), `make setup-user`, `just bootstrap-setup-user`,
  the `bootstrap.sh:59` hint and the two `cd.yaml` steps that run it and check its output go;
  the Makefile header lines (`Makefile:7,80`) and the `Makefile:365` hint that point to it are
  rewritten. The derivation is a
  documented procedure rather than a new script, so the Bitwarden client choice (Q6) stays open.

Q8 (D20). Orphaned `secrets/users/{admin-user,raquel-user}/*`. `[given]`
- Delete after the operator confirms nothing in them needs migrating. Key names only (from the
  sops files' cleartext keys, no decryption):
  - admin-user: `llm-api-keys.yaml` (glm-api-key), `mcp-api-keys.yaml` (context7-api-key,
    firecrawl-api-key, huggingface-token), `signing-key.yaml` (admin-user),
    `NP3W1uaSSCXgMAJGatirTtTsHWnnxJNp-config.yaml` (a kubeconfig: apiVersion, clusters, contexts,
    current-context, kind, preferences, users).
  - raquel-user: `llm-api-keys.yaml` (glm-api-key), `mcp-api-keys.yaml` (context7-api-key,
    firecrawl-api-key, huggingface-token), `signing-key.yaml` (raquel-user).
  - crs58's home secrets already carry glm-api-key, context7-api-key, firecrawl-api-key and
    huggingface-token by name; raquel's carry none of those four. Whether values match is for the
    operator to check.

Q9 (D21). The six unknown identities in the operator's keys.txt. `[given]`
- They belong to other repositories. Leave them and the file untouched.

Q10 (D22). Process. `[given]`
- An OpenSpec change `retire-legacy-sops-tooling`, HIL mode.

Q11. How is correspondence checked from now on? `[decided]`
- A public-data flake check, `checks.x86_64-linux.sops-correspondence`, in a sibling module
  `modules/checks/sops-correspondence.nix` rather than inside `commit-signing-key.nix`, whose
  subject is signing keys. It checks the diagnosis's invariants 1–4: user anchors and clan user
  keys equal ssh-to-age of the users' first login key; machine anchors equal clan machine keys; the
  remaining host-key anchor equals ssh-to-age of the pinned known-hosts key; each file's
  recipients equal its first matching rule. Every anchor must be classified, so a new anchor
  cannot slip past unchecked.
- Invariant 5 (bridge files readable by every NixOS host that uses them) moves to an evaluation
  assertion in `hm-sops-bridge`, the cheaper rung, because it needs per-host facts that the
  host's own evaluation already computes.
- The darwin host keys that `ssh-known-hosts.nix` pins inside a function are hoisted to a static
  flake-level attribute so the check reads them without evaluating any host.

Q12. Which documentation changes? `[given]` every passage in the diagnosis's table, rewritten to
the current architecture or deleted; `[decided]` also `concepts/system-user-integration.md:309-326`,
which shows the same non-existent `secrets/users/*.sops.yaml` rules. ADRs 0001, 0019 and 0020 are
historical records and stay.

# Operator follow-ups after the first review (2026-11-16)

Q13 (operator Q28). Is all of `setup-user` key-related? `[given]` remove it whole only if so.
- `[decided]` yes: `setup-user.sh` only generates or re-prints the age key and prints back-up text;
  `setup-user.nix` wraps it with `coreutils` and `age`; `just bootstrap-setup-user` and
  `make setup-user` run or repeat it; `cd.yaml:88-101` runs it and checks the key file; the other
  steps of that job are untouched. design.md D9 cites each line.

Q14 (operator Q29). rosegold. `[given]` its `/var/lib/sops-nix/key.txt` was installed by hand on
2026-11-16 and matches `sops/machines/rosegold/key.json`; no task.

Q15 (operator Q30). `hash-encrypt`. `[given]` delete it with `secrets/users/`, its only target.

Q16 (operator Q31). The two changes replacing one designation table. `[given]` an archive-time
merge task in each change.

Q17 (operator Q32). `&dev`. `[given]` option (a): replace `*dev` with `*admin-user` on the
home-manager rules of raquel, janettesmith, christophersmith, tara and ubuntu, then remove `&dev`
everywhere. `[decided]` evidence: nothing outside the operator's own maintenance used it; those five
rules were the files the operator reached only through `&dev`. Its private copies (Bitwarden
`sops-dev-ssh`, the operator's keys.txt line) become inert here and stay where they are.

Q18 (operator D25). Bitwarden client for the sops tooling. `[given]` nixpkgs' `bw` only; remove the
`npmbw` alias (`modules/home/shell/aliases.nix:12`, `bunx -p @bitwarden/cli bw`).
