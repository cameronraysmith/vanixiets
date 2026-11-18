# Retrospective: retire-legacy-sops-tooling

> Written: 2026-11-18 (after verify passed with warnings, re-run after one re-queue)
> Commit range: `a52e80260054^..d8874070d00d`, plus this archive commit
> Worktree: merged to main (jj chains from `main@origin`, joined in the working copy; no workspaces)

---

## 0. Evidence

- **Commit range**: `a52e80260054^..d8874070d00d` (8 change commits, each merged through the queue), plus the archive commit
- **Diff size**: +2735 / −3288 lines across 71 files (union of the eight commits' files, `git diff --shortstat a52e80260054^ d8874070d00d -- <files>`); the deletions are the retired recipes, `scripts/sops/`, `secrets/users/`, setup-user and the rewritten docs
- **Tasks done**: 40/40 at archive (39/40 at re-verify; 7.7 done in the archive commit)
- **Active hours**: about 27 h wall clock, from the proposal (2026-11-17 00:02 UTC) to the re-verify (2026-11-18 02:56 UTC), including roughly 19 h waiting for argentum to come online; the apply slices took about 1 h (04:50–05:38 UTC)
- **Subagent dispatches**: 2 named: `SopsToolingDiagnosis` (read-only diagnosis before the proposal) and `SopsRetirementChange` (proposal, all slices, verify, guard fix, archive), steered by the orchestrator
- **New external dependencies**: none (`age`, `sops`, `ssh-to-age`, `jq` and `bitwarden-cli` were already in nixpkgs use)
- **Bugs encountered post-merge**: 1. The darwin machine-key guard reported a present, matching key as "missing" on a host whose `/var/lib/sops-nix` is root-only (argentum); fixed in #3985
- **OpenSpec validate state at archive**: `openspec validate retire-legacy-sops-tooling --strict` valid before the archive. After the sync, `openspec validate --all` passes 55 of 57 items; the two failures belong to other changes and predate this one (`stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite`). `openspec validate --all --strict` fails 33 items, the same 33 that fail on `main` before this archive (placeholder Purposes and requirement texts over 500 characters). The two new specs pass strict once their Purposes are written.
- **Test coverage signal**: two new x86_64-linux checks with mutants: `sops-correspondence` (7 mutants fail as expected) and `darwin-machine-key-guard` (six cases plus a control for the old unprivileged test); one evaluation assertion in `hm-sops-bridge` with a negative control; host witnesses on stibnite (7.4), magnetite (7.6) and argentum (3.4)

Commit chain (chronological):

```
a52e80260054 openspec: propose retire-legacy-sops-tooling                                  (#3923)
74f6d1685e08 sops: narrow operator-credential readers, retire dev and retired host keys    (#3932)
e47332613e86 sops: correspondence check, bridge-recipient assertion, darwin machine-key guard, provision-bridge-key from a pipe (#3933)
94cf0473742c sops: retire legacy sops tooling and rewrite secrets docs to the current architecture (#3936)
bf1d7e294911 openspec: verify retire-legacy-sops-tooling                                   (#3937, PASS WITH WARNINGS)
7d3aa6dbc74f openspec(sops): record argentum key check (task 3.4)                          (#3983, verify FAIL)
1e4781a0c318 fix(darwin): machine-key guard reads a root-only /var/lib/sops-nix through sudo (#3985)
d8874070d00d openspec(sops): re-verify retire-legacy-sops-tooling after the guard fix     (PASS WITH WARNINGS)
<archive>    openspec(sops): retrospective and archive of retire-legacy-sops-tooling
```

### In-Review sub-gates: waived

The operator waived both In-Review sub-gates, roborev (code review) and documenter (docs review), on 2026-11-18: "we don't need to do them right now". The orchestrator relayed the waiver. Neither review was run, so no approval exists. The archive gate proceeds on the waiver, which stands in place of joint approval. No review findings exist to carry forward.

### Re-queue history (review round 1 of 3)

- 2026-11-17 06:05 UTC: first verify, PASS WITH WARNINGS (#3937).
- 2026-11-18 01:31 UTC: task 3.4's guard dry run on argentum reported "found: missing" for a key that `sudo age-keygen -y` had matched to `sops/machines/argentum/key.json` nine minutes earlier (`logs/cam-107-task-3.4-guard-dry-20261117-203116.log`). Verify was set to FAIL (#3983), which was the In Review → In Progress re-queue.
- 2026-11-18, #3985: fix. The guard moved to the shared `modules/darwin/machine-key-guard.sh`, which decides existence and reads the key through `sudo`, plus `checks.x86_64-linux.darwin-machine-key-guard`.
- 2026-11-18 02:52:51 UTC: witness on argentum. The app from `main` `6b0e623d` passed the guard with `--dry` and exited 0 (`logs/cam-107-task-3.4-guard-witness-20261117-215251.log`). An earlier witness attempt had produced an empty log (see §2). Re-verify: PASS WITH WARNINGS (`d8874070`).
- The review-round counter reached 1 of 3 and resets at this archive.

---

## 1. Wins

- The narrowing landed without rotating credential values: `sops rotate` renewed the data keys of `secrets/shared.yaml` and `secrets/test.yaml` after `update-all-keys` (§0, #3932), so old recipients' wrapped keys no longer open current contents. D16 accepted the residual for history.
- The public-key correspondences that used to live in operator memory are now a check: `sops-correspondence` (#3933) catches a renamed anchor, a stale host key, a missing rule and a file whose recipients drift from its rule; all 7 mutants fail it.
- Deletion dominated: −3288 lines against +2735, most of the additions being specs and the two checks. Six recipes, `scripts/sops/`, setup-user's random-key path, `npmbw`, `hash-encrypt`, `verify-hash` and the orphaned `secrets/users/` are gone (#3936).
- Secret handling held throughout: no decrypted value, private key or plaintext digest was printed, logged or committed. Isolated decryption tests ran under `env -i HOME=<empty>`, because sops 3.13.3 otherwise loads the operator's default key files.
- The host witnesses found the one real defect. The guard passed every scripted outcome on stibnite (3.2) and a real activation (7.4); only argentum's root-only directory exposed the bug, and the witness requirement in task 3.4 is what put the guard in front of it.

## 2. Misses

- [high] [blocking | evidence: `logs/cam-107-task-3.4-guard-dry-20261117-203116.log`, #3983, #3985] The guard decided existence with an unprivileged `[ -e "$key_file" ]` and only used `sudo` for reading. clan's upload creates `/var/lib/sops-nix` as `drwx------ root`, so on argentum the guard reported a present, matching key as missing. Without `--dry`, it would have refused every correctly keyed host whose directory clan created. stibnite's directory predates clan (`0755`), so 3.2 and 7.4 passed on the one host where it was tested. The scripted outcomes (3.2) varied the file but never the directory's permissions.
- [med] [painful | evidence: the orchestrator's 2026-11-18 session; `4d25801a` (#3990)] Running clan from the jj join broke it twice on 2026-11-18, once from an agent's command and once from the operator's. clan auto-commits by default, and `clan machines update` or `clan vars` run from the join regenerate vars whose generators differ from `main`'s, then commit them. Both incidents needed a jj repair. Mitigations: `CLAN_NO_COMMIT=1` is now exported by the devshell whenever `.jj/` exists (#3990). Deploys of `main` run from a throwaway `git clone --shared` of `main`, where vars already match their generators, never from the join.
- [med] [painful | evidence: the first argentum witness attempt, 2026-11-18] A witness passed on an empty log. argentum was asleep and ssh timed out, so the gate "0 guard-failure lines" counted lines in a log of a run that never happened. It was caught before anything was recorded as passing. The witness that counted required an `app_exit=` line as well as no failure line.
- [low] [nit | evidence: `logs/cam-107-task-3.4-guard-witness-20261117-215159.log`] One witness run passed a wrong argument and never reached the guard; it was discarded rather than counted.
- [low] [nit | evidence: verify §4, design.md D6] D6 described an inline `sudo age-keygen -y` comparison. The implementation first used `sudo` only for an unreadable file, and after #3985 moved to a shared script. The design text was corrected only at archive.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| 1.x (`.sops.yaml`) | `&dev` retired from every rule, with the operator identity replacing it as maintenance reader | Operator decision D25 before apply: dev had no remaining user |
| 3.1 | `sudo` only when the key file is unreadable, not always | Avoids a prompt for a readable file; this choice let the existence test go unprivileged, which caused the §2 [high] miss |
| 3.4 | Split into a key half (done 01:22Z) and a guard half (failed, fixed in #3985, witnessed 02:52Z) | The guard defect was found by this task |
| new | `checks.x86_64-linux.darwin-machine-key-guard` and `flake.lib.darwinMachineKeyGuard` | Fix for the §2 [high] miss; the guard is now testable without a darwin host |
| 5.1–5.3 | All seven `secrets/users/` files deleted, none migrated | Operator chose delete-all (D20) on the key-name evidence |
| 6.x | Documentation table extended with passages the retired-name sweep found | Operator-approved during apply |
| 7.7 | CAM-106's rows taken from `main` while CAM-106 is in progress; the four §8a lint nouns added in the same pass | CAM-106 has not archived; the lint nouns were deferred to archive by verify |
| T3 (Linear) | In Progress → In Review recorded as dropped | CAM-107 was already Done 2 s after #3932 merged |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`, from the diagnosis and operator decisions D15–D22) |
| superpowers:writing-plans                        | yes (`plan.md`, `tasks.md`) |
| superpowers:using-git-worktrees                  | no |
| superpowers:subagent-driven-development          | yes (orchestrator plus worker subagent, one chain per slice) |
| (transitive) superpowers:test-driven-development | partly (mutants and negative controls for every new check; the guard's directory-permission case was not written first) |
| (transitive) superpowers:requesting-code-review  | no |
| superpowers:finishing-a-development-branch       | yes (each slice published as a PR and merged through the queue) |

### Deliberately Skipped Skills

- **`superpowers:using-git-worktrees`**
  - **What was skipped**: the whole skill; no worktree or jj workspace was created.
  - **Why this cycle**: this repository's version-control discipline is jj chains from `main@origin`, merged into a working-copy join, with `@` never moving and workspaces forbidden. Every slice (`vvzlvkln`, `tnrwyovt`, `tqmttxmk`, `ruxtpxmn`, …) was a chain, which gives the same isolation.
  - **How to prevent recurrence**: `scope-judgment rule`. In jj-colocated repositories, chains in a join satisfy the isolation this skill provides, and §4 should record that as "yes (jj chain)" rather than "no".
- **`superpowers:requesting-code-review`** (and the roborev and documenter sub-gates)
  - **What was skipped**: the In-Review code review and documentation review.
  - **Why this cycle**: the operator waived both sub-gates on 2026-11-18 ("we don't need to do them right now").
  - **How to prevent recurrence**: `scope-judgment rule`. A waiver is an operator decision, recorded with its date and words (§0). The next cycle runs the sub-gates unless waived again. Repeated waivers would be a §6 schema candidate, because they would mean the sub-gates do not fit this repository's cadence.

## 5. Surprises

- clan creates `/var/lib/sops-nix` root-only. Hosts whose directory predates clan (stibnite) are world-traversable, so the same code behaves differently by host history.
- Linear moved CAM-107 to Done 2 s after #3932, the first implementation slice, merged, apparently through its GitHub integration closing an issue named in a merged PR. The board's Done-only-at-archive invariant was broken from outside the workflow.
- sops 3.13.3 reads `~/.config/sops/age/keys.txt` and `~/.ssh/id_ed25519` even when `SOPS_AGE_KEY_FILE` names another file, so a "decrypts only with the throwaway key" test passes vacuously unless HOME is emptied.
- `nix build .#apps.aarch64-darwin.darwin.program` fails with a string-context error even on `main`; the app's program has to be realised through its string context instead.

## 6. Promote candidates → long-term learning

- [ ] [high] **A privilege-boundary check must test every predicate on the privileged side, including existence** → **Promote to memory** (type: feedback)
  > **Why**: the darwin guard read the key through `sudo` but tested existence without it, and reported a present key as missing on a host with a root-only directory (#3985).
  > **How to apply**: when a script inspects a root-owned path from an unprivileged account, write the test fixture with an untraversable parent directory before writing the check.

- [ ] [high] **A witness passes only on positive evidence that the run happened** → **Promote to skill** (`verification-before-completion`)
  > **Why**: a count of zero failure lines from an empty log (sleeping host, ssh timeout) was nearly read as a pass for task 3.4.
  > **How to apply**: every host witness requires a terminal marker such as `app_exit=` or a final status line, and treats its absence as "not run".

- [ ] [med] **Never run clan from a jj join; deploy `main` from a throwaway clone of `main`** → **Promote to project CLAUDE.md** (the fleet-wide agent context's version-control section)
  > **Why**: clan auto-commits and regenerates vars from the join's generators; it broke the join twice on 2026-11-18. `CLAN_NO_COMMIT=1` (#3990) stops the commit but not the regeneration.
  > **How to apply**: before any `clan machines update|install` or `clan vars generate`, check that the working directory is a clone of the commit being deployed, not the join, and that `CLAN_NO_COMMIT=1` is set in shells that do not load the devshell.

- [ ] [med] **Linear's GitHub integration can close an issue on the first merged PR that names it** → **Promote to skill** (`openspec-linear-sync`)
  > **Why**: CAM-107 went to Done after slice 1 merged, two states early, and T3 had to be recorded as dropped.
  > **How to apply**: slice PRs of a multi-PR change should reference the issue without a closing keyword, or the integration's auto-close should be disabled for the team.

- [ ] [low] **"The documentation describes only current procedures" has no interface property** → **One-off** (carry to the next secrets change)
  > **Why**: verify §8b left it undischarged by S; the retired-name sweep and docs build/link check witness it only at one point in time.
  > **How to apply**: decide in the next change touching secrets docs whether to add a docs-command existence check or accept it as a review obligation.
