# Verification Report

**Change**: `seam-secrets-away-from-clan-vars`
**Verified at**: `2026-11-28 00:35` (UTC)
**Verifier**: verify subagent (openspec-verify-change), on stibnite

Implementation, both commits merged on `main`:

- Pull request 4472, commit `e84370a6259d`: the seam, the home view and the two checks.
- Pull request 4479, commit `1e8fb9ff6d66`: every remaining declaration and read moved, in one commit.

`git range-diff` shows that `1e8fb9ff6d66` and `edb38cc8a71b` differ only in `tasks.md`. `edb38cc8a71b` is the commit the move's full comparison ran on.

Code was read from main's tree: `git archive origin/main` (`1e8fb9ff6d66`) into `/tmp/ssv-verify`. Line numbers below are at that revision. The shared working copy differs from main in 40 module files from other sessions, so it was not used.

---

## 1. Structural Validation (`openspec validate`)

- [x] This change reports valid under `--strict`

```text
openspec validate seam-secrets-away-from-clan-vars --strict -> Change 'seam-secrets-away-from-clan-vars' is valid
```

`openspec validate --all` was not run.

---

## 2. Task Completion (`tasks.md`)

- [x] All `- [ ]` have been changed to `- [x]` (81 of 81)

The tasks closed at verify, with the evidence for each:

| Tasks | Evidence |
|---|---|
| 2.5, step 1's formatter/commit/comparison | pull request 4472; `logs/drv-diff-3d6b5448a310-e84370a6259d-20261127T225556Z/report` `result: PASS`; `logs/ssv-verify-treefmt-check-20261128T002618Z.log` (`checks.aarch64-darwin.treefmt` builds from main's tree) |
| 3.5, 4.4, 5.5, 6.4, 7.4, 8.7, 9.5, 10.6, 11.6, 12.9, 13.5, 14.6 | one commit, pull request 4479; `logs/drv-diff-4aed1cad702e-edb38cc8a71b-20261128T000146Z/report` `result: PASS` on `drv-delta/02-13-move.txt`; the same treefmt log |
| 4.1, 5.1, 6.1, 7.1, 8.1, 9.1, 10.1, 11.1, 12.1, 13.1 (closed-set searches) | the searches guarded a split between steps, which the one-commit delivery made moot. They were run on main instead (`logs/ssv-verify-closed-sets-20261128T002424Z.txt`). Every remaining hit outside the two commits and the confinement list names the secret only in prose, a generator-name setting, a `flake.lib.vars` read of a committed public value, or a fixture of `generatorsOf`. None names `clan.core.vars` |
| 8.4a | `logs/ssv-verify-obs-query-mutant-20261128T002449Z.log`. `obs-query` builds from main's tree. The mutant with `apps/obs-query.sh:46`'s literal ending `regulator-passwordX` fails, because the stub `ssh sudo` is never invoked |
| 14.4 | `logs/ssv-verify-fallbacks-20261128T003000Z.txt` |
| 15.1 | reworded to the two per-commit comparisons plus the generator data on main. `logs/ssv-verify-gendata-main-20261128T003100Z.log` is identical to `logs/ssv-batch-gendata-parent-20261127-181748.log` on all ten hosts. One comparison from `3d6b5448a310` to `1e8fb9ff6d66` would include six other changes' commits, which change homes |

Summary lines of the two comparisons:

```text
drv-diff 3d6b5448a310 -> e84370a6259d
nixos: 6 attributes; 6 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 4 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 20 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.x86_64-linux: 267 attributes; 261 identical, 4 changed, 2 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.aarch64-darwin: 116 attributes; 114 identical, 2 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.x86_64-linux: 21 attributes; 21 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.aarch64-linux: 3 attributes; 3 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS

drv-diff 4aed1cad702e -> edb38cc8a71b
nixos: 6 attributes; 6 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
darwin: 4 attributes; 4 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
home: 20 attributes; 20 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.x86_64-linux: 268 attributes; 263 identical, 5 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
checks.aarch64-darwin: 116 attributes; 114 identical, 2 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.x86_64-linux: 21 attributes; 21 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
vmTests.aarch64-linux: 3 attributes; 3 identical, 0 changed, 0 added, 0 removed, 0 failing-at-one, 0 failing-at-both
result: PASS
```

What each comparison changed:

- Step 1 (`e84370a6259d`): `secrets-seam-confinement` and `secrets-seam-translation` added and `fleet-alert` changed, all three declared in `01-seam.txt`. `gitleaks`, `treefmt` and `ntfy-tls-verification` changed under the base allow-list.
- The move (`edb38cc8a71b`): `secrets-seam-confinement` and `eval-users-lib` changed, both declared in `02-13-move.txt:12-13`, plus the same base-allowed checks.

Between `4aed1cad7` and the landed parent `494502977`, other commits touch `modules/README.md`, which the move also edits, and none of the move's other files.

The seam checks build from main's tree, exit 0 (`logs/ssv-verify-seam-checks-build-20261128T002309Z.log`):

- `nix-stock build .#checks.x86_64-linux.secrets-seam-confinement .#checks.x86_64-linux.secrets-seam-translation`
- outputs `1zpigqyj…-structure-secrets-seam-confinement` and `jvj0x2qg…-secrets-seam-translation`

---

## 3. Delta Spec Sync State

| Capability | Sync status | Notes |
|---|---|---|
| secret-consumption-seam | pending sync | new capability; no main spec |
| secret-consumption-seam-interface | pending sync | new capability; no main spec |
| world-assumptions | pending sync | A360-A364 are not in `openspec/specs/world-assumptions/spec.md` and no other change uses those ids; the modified grounded-vocabulary table must be merged by hand with rows other changes added (design, Risks) |

---

## 4. Design / Specs Coherence and Requirement Trace

### Interface requirements (`secret-consumption-seam-interface`)

| Requirement / scenario | Code on main | Evidence | Status |
|---|---|---|---|
| Declared on both classes, one key, in both base aspects | `modules/system/secrets.nix:285-301` (`exportAs` key `secrets`, `base.imports` on both classes) | `logs/sscv-2-views-20261127-171609.log` | met |
| — Writable fields | `secrets.nix:189-236` (generator, prompts with `display`, files, `provided`) | `logs/sscv-2-fields-used-20261127-174848.json` | met |
| — Read-only fields | `secrets.nix:180-185` (`path`, `value`, `exists`, `placeholder`), `:237-243` (`resolved`) | translation fixtures `readBack`, `resolvedBack` | met in part; see W1 |
| — Every host has the option | `secrets.nix:248-252` | `{ }` at step 1 (`sscv-2-views`). At main, all ten hosts evaluate it, holding 1 to 55 entries (`logs/ssv-verify-evals-20261128T002812Z.log`) | met |
| — Clan-free fixture (self-import rule) | the module imports the seam itself: `clan/services/{hermes-agent:3,openclaw:3,nix-builders:46-47,tincr:15-16}/flake-module.nix`, `clan/services/omnigent/flake-module.nix:46`, `clan/services/otel-collector/service.nix:185,278,383`, `nixos/{fleet-deployer:24,omnigraph-backup:118,postgresql-backup:205,omnigent-host:158}.nix`, `darwin/omnigent-host.nix:233`. Omnigent's darwin service module imports `darwin.omnigent-host` (`flake-module.nix:200`). This matches design D6's import rule | omnigent-worker and translation checks build (`logs/ssv-batch-checks-build-20261127-183548.log`) | met |
| Only defined fields, only with clan | `secrets.nix:65,102-129,254-258`. `options ? clan.core.vars` appears only at `secrets.nix:154` | `secrets-seam-translation` builds | met |
| — Translation fixtures | `checks/secrets-seam-translation.nix:94-307` (`everyField`, `onlySecret`, `provided`, `providedWritable`, `providedAbsent`, `readBack`, `resolvedBack`, `noBackend`) | build log above | met |
| — Mutant dropping `restartUnits` | — | `logs/sscv-2-translation-mutant-20261127-174848.log` fails `everyField` | met |
| Read-only fields come from the backend | `secrets.nix:155-185` | `logs/sscv-3-eval-20261127-175724.json`; generator data identical on main | met for `path`, `value`, `exists`. `placeholder` fails to evaluate on most files (W1) |
| — A moved secret's path | — | generator data `path` identical on main (`logs/ssv-verify-gendata-main-20261128T003100Z.log`) | met |
| Provided entry | `secrets.nix:203-213` (writable field fails), `:156-162` (missing generator fails), `:255-257` (not translated). Readers: `lib/host-keys.nix:62` and `machines/nixos/cinnabar/zt-dns.nix:59-60,104,126`, each file declared by name only | — | met |
| — Host key through the option | `lib/host-keys.nix:44-45` | `cinnabarOpensshValueEqualsHostKey: true` (`logs/ssv-verify-evals-20261128T002812Z.log`) | met |
| — A provided entry sets a writable field | `secrets.nix:213` | `logs/sscv-2-provided-message-20261127-174848.log` (`… cannot set script, files.key.owner`); `logs/sscv-2-translation-provided-mutant-20261127-174848.log` | met |
| — Provided entry whose generator clan lacks | `secrets.nix:159` | translation fixture `providedAbsent` | met |
| Homes see a view | `secrets.nix:261-283`; `nixos/hm-sops-bridge.nix:56-73` (owner filter, `{ path, placeholder }` only), `:184-189` (both base aspects); `home/mk-home.nix:31` | stibnite crs58's view fields are `["path","placeholder"]` and entry fields `["files"]` | met in part: the view's `placeholder` fails (W1). `osConfig.sops` is read by `home/ai/omnigent/credentials.nix:123,131,179,180,189` (W4) |
| — A darwin home's signing key | `home/development/vcs-signing.nix:27` | view path = host path = `keyFile` = `/run/secrets/vars/shared/crs58-commit-signing-key/key` | met |
| — A standalone home | `home/mk-home.nix:31` | `standaloneViewsAllEmpty: true` over 20 entries; `keyFile` unchanged (comparison) | met |
| Obligations read the option or `generatorsOf` | by name: `lib/commit-signing.nix:217`, `lib/host-keys.nix:45`, `nixos/r2-usage.nix:237-240,259`. Backend: `lib/shared-vars-recipients.nix:56`, `lib/fleet-deployer.nix:303`, `lib/commit-signing.nix:249`, `lib/host-keys.nix:39`, `checks/nix-builders-wiring.nix:150`. `generatorsOf` is `secrets.nix:303`, with no fallback. No `lib/` file names `clan.core.vars` | machine checks unchanged in both comparisons | met |
| No module outside the seam names the backend | `checks/secrets-seam-confinement.nix:35-55` (search), `:56-85` (14 files) | builds on main | met. The 14 files equal design D8's set, and each comment is true of its file (checked line by line: `finalScript` runs, fixture literals, the clan option stub, `node.clan.core.vars.generators`). The check is a `runCommand` (`:100-118`), not `flake.lib.mkStructuralCheck` (W2) |
| — Mutant adding a direct reader | — | `logs/sscv-2-confinement-mutant-20261127-174848.log` (`+modules/system/ssh-known-hosts.nix`), `logs/ssv-batch-confinement-mutant-20261127-183548.log` (`+modules/nixos/gitea.nix`) | met |
| Every step's derivations unchanged except its allow-list | — | the two comparisons above | met; the spec's "once over the whole change with `whole-change.txt`" is replaced (W3) |
| Trust boundary | text | — | met |

### Behavioral requirements (`secret-consumption-seam`)

| Requirement / scenario | Discharged by | Status |
|---|---|---|
| A feature names its secrets without naming the backend | the confinement check with the final list | met |
| — Uses another feature's secret | for example `nixos/nixbot.nix` and `nixos/matrix.nix` read `config.vanixiets.secrets.<name>`. The closed-set log shows no remaining backend read | met |
| — A new reader of the backend appears | the two confinement mutants | met |
| Moving changes no delivered secret | the generator data is identical on all ten hosts at main; both comparisons pass | met |
| — A delivery step is compared | both reports | met |
| — A recipe is changed while moving | `logs/sscv-3-recipe-mutant-20261127-175724.log`: `script` and `finalScript` change while magnetite's toplevel stays `bzxkgaig…` | met (caught by the generator data, as the scenario states) |
| A home receives its secrets without reading the backend | `vcs-signing.nix:27` reads the view; `rg 'osConfig\.clan\.core\.vars' modules/home` finds nothing | met |
| — Standalone home | `{ }` view, no signing | met |
| Replacing the backend changes only the seam | the confinement check | met by the rule only; no witness replaces the backend (design, pre-apply alignment) |
| A runtime test that runs a recipe runs production's | the six `finalScript` readers in the final list; `vmTests` 21 of 21 and 3 of 3 identical | met |
| Each delivery step is shippable alone | closed-set log on main | met for two commits; "A step is reverted" has no witness |

### World assumptions

| Assumption | Evidence | Status |
|---|---|---|
| A360 clan-core in maintenance | `brainstorm.md:16` | recorded; not observable |
| A361 sops naming | `logs/sscv-1-rereads-20261127-171609.md:7` at 78d5de23 | holds at source. It does not cover `sops.placeholder`, which the seam's `placeholder` reads (W1) |
| A362 first-party option changes no derivation | step 1's comparison: nixos, darwin and home all identical | observed |
| A363 generator depends only on its definitions | the move's comparison and identical generator data | observed |
| A364 clan services declare `openssh`, `openssh-ca`, `zerotier-network-*` | `sscv-1-rereads:9`; cinnabar's `openssh` value equals `hostKeys.cinnabar` | holds |

### Drift warnings

- **W1, `placeholder` does not evaluate on most files.**
  - What fails: `secrets.nix:183-185` reads `hostConfig.sops.placeholder."vars/<rel_dir>/<f>"`. sops-nix defines `sops.placeholder` only when the host has `sops.templates` (sops-nix `modules/sops/templates/default.nix:131-134`), so the read fails with "attribute missing".
  - Where: every declared file on argentum, blackphos, cinnabar, electrum, galena, rosegold and scheelite, none of which has templates. On the hosts with templates, it fails for 36 of 104 files on magnetite, 15 of 42 on pyrite and 11 of 31 on stibnite (`logs/ssv-verify-placeholder-20261128T002748Z.log`).
  - Effect: no derivation reads it, so no derivation changes. But `nix eval` of any home's whole `vanixiets.secrets` fails, for example cameron's on cinnabar (`logs/ssv-verify-evals-20261128T002630Z.log`). That is the interface spec's own discharge for "Homes see a view".
  - Needs a decision: `placeholder` could be `null` where sops-nix defines none, or the spec could state the condition and A361 could gain the sops-nix fact.
  - Correction (2026-11-28): fixed in the seam. `modules/system/secrets.nix` reads `hostConfig.sops.placeholder."vars/<rel_dir>/<f>" or null`, so `placeholder` is `null` where sops-nix defines none and the same string where it does; `modules/nixos/hm-sops-bridge.nix` needed no change. The translation judge gained `placeholderAbsent` and `homeView` (a whole home view on a stub host without placeholders), and fails with the old read (`logs/ssv-w1-translation-{build,mutant}-20261128T004021Z.log`). With and without the fix, generator data on ten hosts and the ten toplevels and 20 homes are identical (`logs/ssv-w1-gendata-{before,after}-20261128T004021Z.log`, `logs/ssv-w1-toplevels-{before,after}-20261128T004021Z.log`). Every declared file's `placeholder` now evaluates on all ten hosts (68 of 104 non-null on magnetite, 27 of 42 on pyrite, 20 of 31 on stibnite, none elsewhere), each equal to sops-nix's or `null`, and every home's whole view evaluates (`logs/ssv-w1-placeholder-probe-20261128T004021Z.log`). Magnetite's 68 placeholders, the omnigent credentials' among them, are unchanged (`logs/ssv-w1-magnetite-placeholders-{before,after}-20261128T004021Z.log`). The interface spec and design D3 state the condition, and A361's evidence cites sops-nix d5abe5e53200 `modules/sops/templates/default.nix:116-127,130-134`.
- **W2, the confinement check does not use the shared helper.** The spec says it compares "with `flake.lib.mkStructuralCheck`". The check is its own `runCommand` (`checks/secrets-seam-confinement.nix:100-118`), so that it can print one file per line; design D9 says "built as … builds". Reword the spec.
  - Correction (2026-11-28): the interface spec now says the check is its own `runCommand`, built from the two lists as `flake.lib.mkStructuralCheck` builds, so that a failure prints one file per line.
- **W3, the whole-change comparison is replaced.** The interface spec's "Discharged by" names a whole-change drv-diff with `drv-delta/whole-change.txt`. The two per-commit comparisons replace it (task 15.1). `whole-change.txt` and the per-step `02-*.txt` to `13-*.txt` are unused.
  - Correction (2026-11-28): the interface spec's "Discharged by" now names the two per-commit comparisons (`01-seam.txt`, `02-13-move.txt`) and the generator data, identical at the base and on `main`, and states why no single comparison over the whole change runs.
- **W4, the "no home module reads `osConfig.sops`" rule has no stated exception.** The interface spec says no home module reads `osConfig.sops`. `home/ai/omnigent/credentials.nix` lives under `modules/home` and reads it. That file is a host-side `flake.lib` function (`:310`), and design D5 and task 11.4 exempt it, but the spec does not. Reword the spec to "no home-manager module", or name the exception.
  - Correction (2026-11-28): the interface spec now says "no home-manager module" and names the exception: `credentials.nix` is host-side, evaluated with the host's configuration as `osConfig`, and reads the host's `sops.secrets` and `sops.templates`. Its discharge states that the `osConfig.sops` search finds only that file.
- **W5, `lib/vars.nix` names an exemption the list does not hold.** Its header (`:20-28`) lists `home/ai/omnigent/credentials.nix` as exempt from the committed-layout clause. That file spells no `vars/(shared|per-machine)/` literal (`:111,119` build the path from `rel_dir`) and is not in the confinement list. The spec's "Final list" includes "the committed-layout exemptions `modules/lib/vars.nix` documents", so the two disagree by that file.
  - Correction (2026-11-28): `modules/lib/vars.nix`'s header now names the four list files with vars literals (`sops-correspondence`, `fleet-deployer-obligations` and `langfuse-query` spelling the committed layout, `commit-signing-key` a delivered path) and says `credentials.nix` is not on the list because it builds the path from `rel_dir` read through `generatorsOf`. The spec's "Final list" names the same four files.
- **W6, non-Nix files are outside the search.** The search covers `.nix` files only. `apps/obs-query.sh:46` spells a delivered vars path, which `checks/obs-query.nix:391` pins (the 8.4a mutant shows this). The confinement header's list of known limits does not mention non-Nix files under `modules/`.

### Leftovers

- `rg -l 'clan\.core\.vars' modules --glob '*.nix'` lists:
  - `system/secrets.nix`;
  - `checks/secrets-seam-confinement.nix`, at `:4` in a comment only;
  - the ten final-list files that name clan vars: `checks/{greptimedb-envelope,host-key-obligations,ntfy-provisioning,secrets-seam-translation}.nix`, `vm-tests/{clan-test-vars-fixture,devloop-ingest,fleet-ingress,greptimedb-oom-order,greptimedb-pipeline,perses-greptimedb}.nix`.
- `rg 'vars/(shared|per-machine)/'` finds only list files, the seam, and comments in `lib/shared-vars-recipients.nix:3`, `clan/inventory/services/omnigent.nix:3`, `machines/darwin/stibnite/default.nix:101` and `machines/nixos/pyrite/default.nix:148`.
- Design ids added by the two commits are all ids of other changes, kept in reworded lines:
  - `declare-test-size-classes design D4` in the two new checks' `testSizes`, as other checks do;
  - `S2 design D11` in `greptimedb-server.nix`, `design D17` in `ntfy-alerter.nix`, `D3` in `r2-usage.nix` and `D8` in `sso-gateway.nix`.
  No step number and no id of this change appears.
- Documents:
  - `modules/README.md:60-68` describes the seam.
  - `packages/docs/src/content/docs/guides/secrets-management.md` describes no generator declaration. Its "Generated secrets" item (`:19`) could point to `vanixiets.secrets` (suggestion).
  - `docs/notes/development/architectural-principles.md` O25 (`:393-400`) still gives the current shape as "about 55 files declare or read `clan.core.vars` directly", and O24 (`:384-391`) does not mention the seam (section 8).

---

## 5. Implementation Signal

- [x] Code committed: `e84370a6259d` (pull request 4472, `MERGED`), `1e8fb9ff6d66` (pull request 4479, `MERGED`; `gh pr view`)
- [x] All related commits are on `origin/main`

**Commit range**: `3d6b5448a310..e84370a6259d` and `494502977..1e8fb9ff6d66`. The full comparison of the second ran on `4aed1cad702e..edb38cc8a71b`, which has the same code.

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

- [x] No files under `docs/superpowers/specs/` (the directory does not exist)

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` has no `[~]` rows. No host deploys: every toplevel is unchanged, so no task waits on a host.

---

## 8. Designation Lint and Discharge Coherence

**8a.** Every content noun of the behavioral requirements resolves to a row: feature, secret, secret backend, secret seam, delivered secret, custody, recipe, home configuration, host, workstation, check, runtime test, delivery step, comparison, base commit, candidate commit, declared difference, operator, telemetry store. "location" and "tool" have no row; "location" is covered by the row for delivered secret ("installed … at a fixed location"). Suggestion: none needed beyond that.

**8b.**

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A feature names its secrets without naming the backend | the confinement rule | — | built; mutants killed |
| Moving changes no delivered secret | the translation (only defined fields) and the per-step comparison | A362, A363 | observed |
| A home receives its secrets without reading the backend | the home view | A362 | met; W1 for `placeholder` |
| Replacing the backend changes only the seam | the confinement rule's final list | A360 (motivation) | rule only |
| A runtime test runs production's recipe | the final list keeps the `finalScript` readers | — | met |
| Each step shippable alone | the closed sets | A363 | met as one commit |
| Read-only fields come from the backend | `secrets.nix:180-185` | A361 | `path`, `value`, `exists` met; `placeholder` W1 |
| Provided entry | `secrets.nix:156-213` | A364 | met |

**8c.** No behavioral requirement names a machine phenomenon. The interface requirements name options, checks and files only.

### Edits needed outside the change directory before archive

1. `docs/notes/development/architectural-principles.md`, O25:
   - Replace the "Current shape" line and "Closed by seam-secrets-away-from-clan-vars." with a Status line: "Status: resolved by seam-secrets-away-from-clan-vars (pull requests 4472 and 4479). Every first-party module declares and reads secrets through `vanixiets.secrets.<name>` (`modules/system/secrets.nix`); homes read a view set by `hm-sops-bridge`; outside the seam only the fourteen checks and runtime tests listed in `checks.x86_64-linux.secrets-seam-confinement` name clan vars or the committed layout."
   - Update table row A6 (`:135`) to match.
2. The same file, O24: add after "Closed by stop-reading-other-hosts-configs.": "`modules/lib/vars.nix` is the committed-store half of the secret seam, and `secrets-seam-confinement` fails on a `vars/shared/` or `vars/per-machine/` literal outside its list (pull request 4479)."
3. `modules/lib/vars.nix:20-28`: drop `credentials.nix` from the committed-layout exemptions, or say it builds the path from `rel_dir` and so is not on the list (W5).
4. `modules/system/secrets.nix:183-185` and `modules/nixos/hm-sops-bridge.nix:63`: resolve W1.
5. Optional: `packages/docs/src/content/docs/guides/secrets-management.md:19`, a sentence naming `vanixiets.secrets` as how a module declares a generated secret. This adds the docs-package checks as declared differences.

Inside the change directory, before archive: reword the interface spec for W2, W3 and W4, and state the `placeholder` condition if W1 is resolved by rewording.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [x] (warn) PASS WITH WARNINGS — every task is closed and both comparisons pass. Do not archive until:
  - W1 is decided: `placeholder` fails to evaluate on 7 of 10 hosts, and the home-view discharge fails;
  - W2-W4 are reworded in the spec;
  - the principles O24/O25 Status lines and `lib/vars.nix`'s header are updated.
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

**Next step**: decide W1, by a seam fix with its translation fixture or by a spec restatement. Then apply the edits above and archive.
