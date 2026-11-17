# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `retire-legacy-sops-tooling` (CAM-107)
**Verified at**: `2026-11-17 06:05 UTC`
**Verifier**: subagent `SopsRetirementChange`, against merged `main` (`3a2e049fac57`, change `nkpzxuxp`)

The implementation landed in three pull requests, each a stacked slice:

| PR | Slice | Head commit | Tasks | nixbot on head |
|---|---|---|---|---|
| #3932 | 1: readers of operator credentials | `74f6d1685e08` (`vvzlvkln`) | 1.1–1.6 | nix-eval, nix-build, effects: success |
| #3933 | 2: correspondence check, bridge assertion, darwin guard, provision-bridge-key | `e47332613e86` (`tnrwyovt`) | 2.1–2.5, 3.1, 3.2, 4.3, 1.7 | nix-eval, nix-build, effects: success |
| #3936 | 3: tooling deletions, D20, docs, integration | `94cf0473742c` (`tqmttxmk`) | 3.3, 4.1, 4.2, 4.4, 4.5, 5.1–5.3, 6.1–6.9, 7.1–7.4, 7.6 | nix-eval, nix-build, effects: success |

Each head commit's message carries the per-task evidence (public keys, exit codes and log names only; logs under the gitignored `logs/`).
No decrypted value, private key or plaintext digest was printed, logged or committed at any step.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [ ] All items report `"valid": true`

**Result**:

```text
54 items: 52 passed, 2 failed.
retire-legacy-sops-tooling: valid (also `openspec validate retire-legacy-sops-tooling --strict`: valid).
```

The two failures belong to other changes and predate this one; neither is caused by it:

| Item | Type | Issues |
|---|---|---|
| `stand-up-gitea-mq-on-magnetite` | change | requirement text over 500 characters (10); its MODIFIED "Grounded vocabulary for behavioral requirements" omits the scenario "The terms with two senses are read" |
| `stand-up-nixbot-on-magnetite` | change | requirement text over 500 characters (4); same omitted scenario in its MODIFIED designation requirement |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

38 of 40 checked.

**Incomplete tasks**:

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 3.4 **[operator]** argentum: check `/var/lib/sops-nix/key.txt` against `sops/machines/argentum/key.json` when the host is next online; `clan vars upload argentum` only if missing or mismatched | Pending, operator: argentum has not been online. Whether an upload is needed is unknown. The guard already enforces the condition on argentum's next `just activate`. | No |
| 7.7 Archive preparation: merge this change's MODIFIED designation table with rows added elsewhere (naming `stand-up-renovate-on-magnetite`) | Pending, archive-time by design. Checked now: the change's table contains every row of the current main table (0 missing) and adds 21; `stand-up-renovate-on-magnetite` has not archived, so its rows are not yet in main. | Yes, it is an archive step |

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| `secret-custody` | pending sync | new capability; not yet in `openspec/specs/` |
| `secret-custody-interface` | pending sync | new capability; not yet in `openspec/specs/` |
| `world-assumptions` | pending sync | adds A116–A121; MODIFIED "Grounded vocabulary for behavioral requirements" (+21 rows, multi-sense count 25) — merge per task 7.7 before archive |

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1 recipients | operator-credential rule `*admin` + `*admin-user`; `&dev`, `&stibnite`, `&orb-nixos` removed; `*admin-user` on every rule | interface: "Operator-credential files…", "No rule names the retired development key…", "No retired host's key is an anchor or a rule"; behavioral: "Operator credentials are readable only by the operator", "The operator identity can read every secret file" | none; main's `.sops.yaml` has no `&dev`/`&stibnite`/`&orb-nixos`/`secrets/users` |
| D2 data-key renewal | `sops rotate` after `updatekeys` on narrowed files | interface: "Narrowed files carry a renewed data key" | none |
| D4 check | sibling check, static key set, x86_64-linux only, mutants | the five "correspondence check …" interface requirements | none; 15 anchors, 11 rules, 13 files, 7 mutants fail as expected |
| D5 bridge assertion | per-host recipient assertion | "Each NixOS host asserts it is a recipient of the bridge files it uses" | none |
| D6 guard | in the `.#darwin` app, table baked in at evaluation | "The `.#darwin` app refuses activation…" | design says the app compares through `sudo age-keygen -y`; the implementation uses `sudo` only when the file is unreadable (task 3.1 reworded during apply) |
| D7 provision-bridge-key | pipe into `sops encrypt --filename-override`, temp ciphertext moved onto target | "`provision-bridge-key` keeps plaintext out of the repository tree" | none |
| D9/D10/D12 deletions | setup-user, legacy recipes, `secrets/users`, `hash-encrypt`, `verify-hash`, `npmbw` | "The retired recipes, scripts and app are absent" | none; all absent on main |

**Drift warnings** (non-blocking):

- D6 wording vs implementation on when `sudo` is used (above); the behavior the spec requires is unchanged.
- The design's documentation table was extended during apply with passages the retired-name sweep found (operator-approved).

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree (`jj st`: the working copy has no changes)
- [x] All related commits have been pushed (merged as #3932, #3933, #3936)

**Commit range**: `a52e80260054` (proposal) `..` `94cf0473742c` (slice 3), merged into `main` at `3a2e049fac57`.

Implementation present on merged `main`: `modules/checks/sops-correspondence.nix`, `modules/lib/darwin-host-keys.nix`, the guard in `modules/darwin/app.nix`, the assertion in `modules/nixos/hm-sops-bridge.nix`, the piped `provision-bridge-key`; absent: `scripts/sops/`, `secrets/users/`, `modules/apps/bootstrap/setup-user.nix`, the six `sops-*` recipes, `hash-encrypt`, `verify-hash`, `bootstrap-setup-user`, `npmbw`.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```bash
ls docs/superpowers/specs/*.md 2>/dev/null
```

- [x] No files

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

plan.md has no `[~]` rows.
The host-level checks were run, not deferred: 7.4 (stibnite activation) and 7.6 (magnetite deploy).

| Host check | Observed | Automated coverage of the same property |
|---|---|---|
| 7.4 stibnite `just activate` (operator, 2026-11-17 00:33:53, generation `82282czy…-darwin-system-26.11.ff0e21a`, built from the join containing all three slices) | guard passed; `/var/lib/sops-nix/key.txt` public key equals `sops/machines/stibnite/key.json`; home sops-nix agent exit 0, 23/23 declared secrets present and non-empty; `sops -d secrets/shared.yaml` and `sops exec-env … true` succeed as the operator; no `fleet-alerts` message since, `fleet-heartbeat` only `ok` | guard logic: task 3.2's runs of all outcomes; key correspondence: `sops-correspondence` (public side) |
| 7.6 magnetite `clan machines update` from `main` `e4733261` (slices 1–2) | rc 0; `home-manager-cameron` Result=success; `/run/secrets/crs58-age-key` 75 bytes, 0400, cameron; all 23 secrets cameron's home declares installed and non-empty; user sops-nix Result=success, no journal errors; no failed units; no `fleet-alerts` message | bridge recipients: the `hm-sops-bridge` evaluation assertion (negative control in task 2.5) |

Real gaps: none for these rows. Raquel's, janettesmith's, christophersmith's, tara's and ubuntu's home secrets are witnessed by recipient presence only (the operator holds none of their keys), as task 1.5 states.

---

## 8. Designation Lint and Discharge Coherence (agent-executed, non-blocking)

Not validation: `openspec validate` checks structure only.

**8a. Designation lint.** The behavioral capability `secret-custody` was lexed against the designation table as this change modifies it (its rows are not yet in `openspec/specs/world-assumptions/spec.md` because the change is unsynced). Resolved: secret, secret file, reader, operator, operator credential, operator identity, recovery key, person, host, retired host, public key, machine key, host key, personal key, key store, workstation, maintenance tool, working tree, automated runner, change, reader rule, repository, darwin host, activation, documentation, procedure, commit, history, field, credential, correspondence.

| Unresolved noun | Where | Disposition |
|---|---|---|
| command | "names the command that installs the machine key"; "every command, path, field and item" | add a row (a command a person runs) at archive with task 7.7 |
| item | "every command, path, field and item it names" (a key-store item) | add a row, or reword as "key-store entry", at archive |
| hardware | "a host's earlier hardware" | covered in prose by the `retired host` row; add an explicit row or fold into it at archive |
| key (bare) | "Provisioning a key …", "rotates a person's reader" | uses are qualified by context (personal, machine, host, public); add a generic `key` row at archive |

**8b. Discharge coherence.**

| Requirement (`secret-custody`) | Discharged by (S, `secret-custody-interface`) | Under (W) | Status |
|---|---|---|---|
| Operator credentials are readable only by the operator | Operator-credential files are encrypted to the recovery key and the operator identity only; Narrowed files carry a renewed data key | A120 | discharged; A120 configured, not violated (2026-11-16..17) |
| The operator identity can read every secret file | No rule names the retired development key, and every rule names the operator identity; The correspondence check compares each file's recipients with its rule | — | discharged |
| No retired host is a reader of any secret file | No retired host's key is an anchor or a rule; The correspondence check compares host-key anchors with pinned darwin host keys; … accounts for every anchor | A119 | discharged; A119 observed (ssh-to-age images matched on every comparison, 2026-11-16..17) |
| Narrowing a secret file's readers keeps every reader still in use and renews its protection | Operator-credential files…; Narrowed files carry a renewed data key | A120 | discharged for current contents; the "earlier commit" scenario is the accepted residual (D16) |
| Every public key the repository names corresponds to the person or machine it names | the five correspondence-check requirements; Darwin host keys are static flake data | A119 | discharged |
| Every host can read the personal keys it delivers to its users | Each NixOS host asserts it is a recipient of the bridge files it uses | A118 | discharged; A118 configured, not violated |
| A darwin host is not activated without its machine key | The `.#darwin` app refuses activation without the host's machine key | A116, A117, A118 | discharged; A117 observed (stibnite `sops.age.keyFile` = `/var/lib/sops-nix/key.txt`); A116 not violated (no local activation wrote key.txt) |
| Provisioning a key never leaves a private key in the repository's working tree | `provision-bridge-key` keeps plaintext out of the repository tree | A121 | discharged; A121 configured (scratch run with a fake `bw`; the real item shape is observational) |
| A workstation's personal key is derived from the person's SSH key in the key store | The retired recipes, scripts and app are absent (the random-key path is gone); correspondence check (user anchors) | A119, A121 | partly discharged: the derivation itself is a documented procedure with no interface property; the check witnesses only its public result |
| No maintenance tool rewrites readers or host identities from an external source | The retired recipes, scripts and app are absent | — | discharged |
| The documentation describes only current procedures | — (no interface property) | — | undischarged by S; witnessed by the retired-name sweep and docs-build/linkcheck (task 6.9). Follow-up: promote a docs-command existence check, or accept as a review obligation, at retrospective §6 |

**8c. Alphabet check.**

- Behavioral: no interface phenomena; command names were reworded out of the behavioral scenarios during proposal ("the command that installs the machine key"). No violation.
- Interface: the trust-boundary requirement names what lies outside the boundary (host-held keys, key store, history) only to exclude it; no interface requirement asserts unobservable world state. No violation.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: 3.4 (operator, argentum key check when online) and 7.7 (designation-table merge at archive) are pending; four designation-lint nouns and one undischarged behavioral requirement are recorded in §8 as follow-ups; `openspec validate --all` fails only on two other changes.
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**:

In Review: roborev, then documenter. Then the retrospective, then archive, with task 7.7 run immediately before archive and 3.4 recorded whenever argentum is next online.
