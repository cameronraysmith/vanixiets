# Retrospective: seam-secrets-away-from-clan-vars

> Written: 2026-11-27 (after verify passed with warnings and its W1–W5 were corrected, before archive)
> Commit range: planning `68c045788`, `db0beed0d`, `209d6a2ea`, `c4c74110d`; then on `main` `e84370a62` (#4472, parented on `3d6b5448a310`), `1e8fb9ff6` (#4479, parented on `494502977`) and `cef10b75e` (#4489)
> Worktree: merged to main; this retrospective and the archive are one further commit

---

## What the change set out to do

Every feature that needed a secret declared and read clan's vars generators directly: 55 files under `modules/` named `clan.core.vars`, features read each other's generators, and homes read the host's clan configuration (proposal Why). The change put one seam, `vanixiets.secrets.<name>` in `modules/system/secrets.nix`, between first-party modules and clan, gave homes a read-only view of the secrets their user owns through `hm-sops-bridge`, and confined every remaining mention of clan vars to a literal list that `checks.x86_64-linux.secrets-seam-confinement` enforces (design D1–D10).

## 0. Evidence

- **Commit range**: `68c045788` (Den-ready fleet plan), `db0beed0d` (design), `209d6a2ea` (secrets-seam decisions), `c4c74110d` (plan brought up to date with the repository), `e84370a62` (the seam, the home view and two checks, #4472), `1e8fb9ff6` (every remaining declaration and read, #4479), `cef10b75e` (placeholder fix, spec corrections and verify record, #4489); 7 commits
- **Diff size**: `e84370a62` +778 / −50 across 18 files; `1e8fb9ff6` +775 / −466 across 78 files; `cef10b75e` +443 / −84 across 9 files; artifacts included
- **Tasks done**: 81/81 (`openspec list --json`)
- **Active hours**: about 2.6 h from the seam commit (2026-11-27 17:31 −05:00) to the placeholder fix (20:04 −05:00), the verification in between (`verify.md`, 2026-11-28 00:35 UTC)
- **New external dependencies**: none
- **Bugs encountered post-merge**: one, found by the verification after #4472 and #4479 landed: a file's `placeholder` failed to evaluate on every file of seven hosts and on part of the files of the other three, so evaluating any home's whole view failed (verify W1); no build reads the field for such a file, so no derivation changed. Fixed by #4489.
- **OpenSpec validate state at archive**: `openspec validate seam-secrets-away-from-clan-vars --strict` valid; the two new main specs valid under `openspec validate <spec> --type spec --strict`
- **Test coverage signal**: `checks.x86_64-linux.secrets-seam-translation` with the fixtures `everyField`, `onlySecret`, `provided`, `providedWritable`, `providedAbsent`, `readBack`, `resolvedBack`, `noBackend`, `placeholderAbsent` and `homeView`; mutants dropping `restartUnits`, setting a writable field on a provided entry, returning `owner = null` from `resolved`, and the old placeholder read, each failing its fixture; `secrets-seam-confinement` with two mutants adding a direct reader (`modules/system/ssh-known-hosts.nix`, `modules/nixos/gitea.nix`); the recipe mutant (task 3.4); the `obs-query` literal mutant (task 8.4a); `just drv-diff` PASS for each of the two delivering commits; the generator data of all ten hosts identical at the change's base and on `main`

Commit chain (chronological):

```
68c045788 docs(openspec): plan the den-ready fleet architecture changes
db0beed0d docs(openspec): design declare-host-user-relations-once and seam-secrets-away-from-clan-vars
209d6a2ea docs(openspec): split the blocked tasks out of register-fleet-obligations and record the secrets-seam decisions
c4c74110d docs(openspec): bring the secrets-seam plan up to date with the repository
e84370a62 feat(secrets): add the secrets seam, its home view and two checks
1e8fb9ff6 refactor(secrets): declare and read every secret through the secrets seam
cef10b75e fix(secrets): make a file's placeholder null where sops-nix defines none
(this commit) docs(openspec): archive seam-secrets-away-from-clan-vars
```

---

## 1. Wins

- Outside the two seam files, only the 14 files of the confinement check's final list name clan vars or the committed `vars/` layout, each with its reason; any other `.nix` file under `modules/` that does fails the check (verify §4).
- No NixOS, darwin or home toplevel and no runtime test changed in either delivering commit (verify §2), and the generator data of all ten hosts, every generator's files, prompts, dependencies, script text, runtime inputs and `finalScript`, is identical at the change's base and on `main` (task 15.1).
- Homes read their secrets' locations from a view the host sets; no file under `modules/home` reads `osConfig.clan.core.vars` (verify §4).

## 2. Misses

- [med] [painful | evidence: verify W1, tasks.md 2.3 evidence of 2026-11-28] `placeholder` read `sops.placeholder."vars/<rel_dir>/<f>"`, which sops-nix defines only on a host with `sops.templates`. The read-back fixture's stub defined the placeholder, so no fixture caught it, and no build reads the field for such a file, so no derivation showed it. The verification found it by evaluating whole home views after landing. `cef10b75e` makes the field `null` where sops-nix defines none; `placeholderAbsent` and `homeView` fail with the old read.
- [med] [painful | evidence: design D10, tasks.md 15.1, verify §2] The interface spec named a whole-change `just drv-diff` with `drv-delta/whole-change.txt`. It was not run: six other changes' commits that change homes landed between the two delivering commits. The two per-commit comparisons and the generator data replace it, and the spec says so (verify W3).
- [low] [nit | evidence: verify W2, W4, W5] The confinement check is its own `runCommand`, not `flake.lib.mkStructuralCheck`; `credentials.nix` reads `osConfig.sops` as a host-side function, which the spec's rule did not except; `modules/lib/vars.nix`'s header listed `credentials.nix` as exempt though it spells no `vars/` literal. Each was corrected on 2026-11-28.
- [low] [nit | evidence: verify W6] The confinement search covers `.nix` files only; `apps/obs-query.sh:46` spells a delivered vars path, pinned by `checks/obs-query.nix`. Not taken up.

## 3. Plan deviations

| Plan task | What changed | Why |
|-----------|--------------|-----|
| D10, groups 3–14 | Planned as thirteen deliveries; landed as three pull requests: #4472 the seam, #4479 every remaining declaration and read as one commit, #4489 the placeholder fix the verification found | Every step had the same acceptance, and a half-moved tree does not evaluate (design, resolved question 5) |
| 3.4, behavioral scenario "A recipe is changed while moving" | The scenario names the comparison of every host's generator data, not of host configurations; corrected in `1e8fb9ff6` | A derivation comparison of host systems cannot see a generator's recipe: the recipe mutant changes `script` and `finalScript` while magnetite's toplevel stays the same (`logs/sscv-3-recipe-mutant-20261127-175724.log`). The comparison of generator data on every host is what showed the move kept each recipe |
| 2.3a, D2 | The seam gained the read-only `resolved`, clan's evaluated generator in the option's field names with clan's defaults applied | Readers that need a value clan fills in, such as a file's default owner, read what clan evaluated rather than the entry's own `null` |
| 4.1–13.1 | The closed-set searches that guarded a split between steps were run once on `main` after the move | The one-commit delivery left no split to guard (verify §2) |
| 15.1 | Whole-change comparison replaced by the two per-commit comparisons and the generator data | See §2 |

## 4. Skill / workflow compliance

| Skill                                            | Used |
|--------------------------------------------------|------|
| superpowers:brainstorming                        | yes (`brainstorm.md`) |
| superpowers:writing-plans                        | yes (`plan.md`) |
| superpowers:using-git-worktrees                  | not evidenced in the change's files |
| superpowers:subagent-driven-development          | not evidenced in the change's files |
| (transitive) superpowers:test-driven-development | yes in the mutant form: each fixture and the confinement rule shown failing against a mutant |
| (transitive) superpowers:requesting-code-review  | yes, before landing: #4472 by one code review and a cold read of its message; #4479 by six parallel reviews by file group, which found no blocker and whose should-fix items were applied before the final derivation comparison |
| superpowers:finishing-a-development-branch       | yes (#4472, #4479 and #4489 merged) |

Review gates: verify.md records no In Review gate decision; no review.md. The verification in `verify.md` was run after #4472 and #4479 landed, and #4489 arose from its finding W1.

## 5. Surprises

- sops-nix defines `sops.placeholder` only on a host with `sops.templates`; elsewhere it is `{ }` (A361 as amended).
- A secret's recipe is not part of any host's system, so a drvPath diff of toplevels cannot show a recipe change; only the generator data can.
- The confinement check matches text: it does not see `inherit (config.clan.core) vars;`, a read through `flake.lib.secretsBackend.generatorsOf`, or a file outside `modules/`.

## 6. Promote candidates → long-term learning

- [ ] [med] **A fixture's stub must leave undefined what the real dependency leaves undefined; evaluate a read-only field on every host, not only where a build reads it.**
  → **Promote to** memory
  > **Why**: the read-back stub defined `sops.placeholder`, and no build read `placeholder` where sops-nix defines none, so W1 surfaced only when whole home views were evaluated after landing.
  > **How to apply**: adding a read-only option field derived from another module's option.
- [ ] [med] **A refactor that moves generator declarations is accepted on the generator data of every host, not on toplevel drvPaths alone.**
  → **Promote to** memory
  > **Why**: the recipe mutant left every toplevel unchanged.
  > **How to apply**: any change to clan vars generators or other data that reaches a host only at runtime.
- [ ] [low] **When every step of a planned split has the same acceptance and an intermediate tree does not evaluate, deliver the steps as one commit.**
  → **Promote to** one-off
  > **Why**: thirteen planned deliveries landed as the seam plus one move commit.

---

## Open items that outlive the change

| Item | Where it goes |
|------|---------------|
| The confinement search reads `.nix` source text only: an `inherit` of the attribute, a read through `generatorsOf`, a string-built path, a non-Nix file under `modules/` (`apps/obs-query.sh:46`, W6) or a file outside `modules/` are not seen | not taken up |
| The mesh address seam | migrate-mesh-to-tincr |
| A check that a required secret value exists | a later change |
| Scenarios "The backend is replaced" and "A step is reverted" have no witness | the first change that replaces the secret backend |
