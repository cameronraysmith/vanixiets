# Verification Report

> This file is produced by the `openspec-verify-change` skill after apply completes, to confirm that the
> implementation is consistent with the specs / design / tasks. Any failed check must be returned to its
> corresponding artifact for correction before re-running verify.

**Change**: `unify-vcs-author-identity`
**Verified at**: `2026-11-09 04:13 UTC`
**Verifier**: `VerifyAuthorIdentity worker agent (omnigent-cameron on magnetite), with operator-only evidence marked as such`

Two attributions are used throughout and never blurred.
`[operator]` marks evidence only the operator can produce: it needs a host activation, a read of a delivered path after that activation, or a push from a deployed account.
None of that evidence exists yet, and nothing marked `[operator]` in this report is claimed as observed.
`[verified here]` marks an observation this session made itself, with the command and its output given.

All evaluation evidence is taken against current `main`, `67f35eb2a5ecf62df60ebfbb7f68de964dcb2123`, pinned by revision rather than read from the working copy.
In the commands below, `F` abbreviates
`builtins.getFlake "git+file:///home/omnigent-cameron/projects/vanixiets?rev=67f35eb2a5ecf62df60ebfbb7f68de964dcb2123"`,
and every such command is run as `nix eval --impure --json --expr 'let f = F; in …'`.
`main` differs from the stack's head commit `71f0a8ec` only in `sops/secrets/hetzner-api-token/secret`, from the unrelated `2570096b sops: rotate the Hetzner Cloud API token` that shared the merge batch (`jj diff --stat --from 71f0a8ec --to 67f35eb2`).

Apply-phase logs are cited from `~/.local/state/agent-logs/vanixiets/` (`$XDG_STATE_HOME` is unset in this session, so the XDG default applies).
That directory holds the `before`, `step1`, `step2` and `step3` projections for `authors`, `checks-x86_64-linux`, `checks-aarch64-darwin`, the NixOS hosts magnetite, pyrite, galena, scheelite, cinnabar and electrum, the nix-darwin hosts argentum, blackphos, rosegold and stibnite, and `signers-postfmt.json`.

---

## Summary

| Dimension    | Status |
|--------------|--------|
| Completeness | 25/28 tasks; the 3 open tasks (4.1, 4.4, 4.5) are operator-run deploys of pyrite, stibnite and the remaining human hosts, plus the notification-topic read. 17/17 ADDED or MODIFIED requirements have implementation or witness evidence; 0 REMOVED, 0 RENAMED |
| Correctness  | 17/17 requirements mapped to `main` at the evaluation boundary. On magnetite the delivered path is verified (§11.8); on the other affected hosts it is not, because they are not yet deployed |
| Coherence    | Design D1′–D6 followed at the evaluation boundary; D5 (workaround removal) executed on magnetite, pending on pyrite and stibnite (4.4). 4 suggestions, no design contradiction |

No defect was found in the delivered code.
Three tasks remain open (§2, §12). Each one blocks archive, and none of them is a code defect.

---

## 1. Structural Validation (`openspec validate --all --json`)

- [x] All items for this change report `"valid": true`

**Result** `[verified here]`:

```text
$ openspec validate --all --json | jq '.summary'
  "totals": { "items": 48, "passed": 46, "failed": 2 },
  "byType": {
    "change": { "items": 19, "passed": 17, "failed": 2 },
    "spec":   { "items": 29, "passed": 29, "failed": 0 }
  }

$ openspec validate --all --json | jq -c '.items[] | select(.id=="unify-vcs-author-identity") | {id,type,valid,n:(.issues|length)}'
{"id":"unify-vcs-author-identity","type":"change","valid":true,"n":7}

$ openspec validate unify-vcs-author-identity            # exit 0
$ openspec validate unify-vcs-author-identity --strict   # exit 1, 7 warnings, all "Requirement text is very long (>500 characters)"
```

This change is valid.
Its seven issues are warnings, not failures. Each says that one ADDED requirement's text exceeds 500 characters. They concern three requirements in `commit-author-identity-interface`, one in `commit-author-identity` and two in `world-assumptions`.
`--strict` promotes the warnings to a non-zero exit (suggestion S3).

The two failing items belong to other changes and are outside this verification:

| Item | Type | Issues |
|---|---|---|
| `stand-up-gitea-mq-on-magnetite` | change | long-requirement warnings; not this change |
| `stand-up-nixbot-on-magnetite` | change | long-requirement warnings; not this change |

---

## 2. Task Completion (`tasks.md`)

- [ ] All `- [ ]` have been changed to `- [x]`

`openspec instructions apply --change unify-vcs-author-identity --json` reported `progress = { total: 28, complete: 21, remaining: 7 }` at the first verify run; tasks 4.2, 4.3, 5.1 and 5.2 have since been ticked on magnetite's delivered evidence (§11.8), leaving 3 open.
Tasks 1.1–3.5, 4.2, 4.3 and 5.1–5.3 are checked.
The open tasks are operator-run steps after landing (`tasks.md:38`: "Operator-run after the stack lands; agents do not activate hosts").

| Task | Reason incomplete | Blocks archive? |
|---|---|---|
| 4.1 Deploy magnetite, pyrite and stibnite; attribute every notice | Magnetite is deployed and its delivered author is verified (§11.8). Pyrite and stibnite are not yet deployed, and the notification topics have not been read: ntfy is not listening on magnetite `[operator]`. | **Yes** |
| 4.2 Remove the repository-local `user.name` workaround on magnetite | Done after magnetite's activation (§11.8) | No |
| 4.3 Re-author empty-author mutable commits in that checkout | Done after 4.2: no commit matched (§11.8) | No |
| 4.4 Check the pyrite and stibnite omnigent-cameron checkouts for the workaround | Needs access to those hosts `[operator]` | **Yes** |
| 4.5 Deploy argentum, blackphos, rosegold, galena and scheelite | Host activation, at the operator's discretion `[operator]` | **Yes** (it is still an unchecked task. If the operator defers it, `tasks.md` must record that before archive) |
| 5.1 Push a Cameron worker commit end to end | Done on magnetite (§11.8) | No |
| 5.2 Janette's delivered author vs. sign-in address | Done on magnetite: delivered half `[operator]`, evaluation half `[verified here]` (§11.3, §11.8) | No |

The exact steps and expected evidence for each task are in §12.

---

## 3. Delta Spec Sync State

Delta spec files reported by the CLI
(`openspec status --change "unify-vcs-author-identity" --json | jq -r '.artifactPaths.specs.existingOutputPaths[]'`):

```text
openspec/changes/unify-vcs-author-identity/specs/commit-author-identity-interface/spec.md
openspec/changes/unify-vcs-author-identity/specs/commit-author-identity/spec.md
openspec/changes/unify-vcs-author-identity/specs/world-assumptions/spec.md
```

| Capability | Sync status | Notes |
|---|---|---|
| `commit-author-identity` | pending sync | No `openspec/specs/commit-author-identity/` exists. This change introduces the capability. |
| `commit-author-identity-interface` | pending sync | No `openspec/specs/commit-author-identity-interface/` exists. This change introduces the capability. |
| `world-assumptions` | pending sync | The main spec exists. The delta MODIFIES `Grounded vocabulary for behavioral requirements` and ADDS A84 and A85, which the main spec does not yet contain. `[verified here]`: every row of the main designation table is present in the delta table (0 main-only rows), and the delta adds 13 rows: author, author name, author address, author setting, commit (local), profile (person), profile (home), push, sign-in address, signature (commit), signer principal, verifier (commit signature) and version-control tool. |

Pending sync is the correct state for an unarchived change.
Four other active changes also carry a MODIFIED `Grounded vocabulary` delta: `bind-mesh-writes-to-their-host`, `stand-up-gitea-mq-on-magnetite`, `stand-up-nixbot-on-magnetite` and `verify-ntfy-before-sending-tokens`.
Whichever of them archives later must rebase its table, as `design.md:127` anticipates for two of them (suggestion S4).

---

## 4. Design / Specs Coherence Spot Check

| Sampled item | design description | specs correspondence | Gap |
|---|---|---|---|
| D1′ derivation rule | `design.md:43`: `vcsAuthor = meta: { name = meta.fullname; email = meta.gitEmail; }` beside `flake.users` | `specs/commit-author-identity-interface/spec.md:17-18`. Implemented at `modules/home/users/lib.nix:34-37`, with the `gitEmail` default at `:69-72` | none |
| D2′ one option, non-empty pair | `design.md:51-57`: `vcs.author.{name,email}` as `nonEmptyStr`, default through the `flake` special argument, no `signing` | `interface spec:32-37`. Implemented at `modules/home/development/vcs-author.nix:3-37` (types `:18,:24`, special-arg read `:11`, setters `:32-33`, no `signing`) | none |
| D3′ owner typed; adapters set the author | `design.md:71-76` | `interface spec:66-67,81-83`. Implemented at `modules/system/omnigent-worker-options.nix:3,110-111`, `modules/clan/services/omnigent/flake-module.nix:6,83-84`, `modules/nixos/omnigent-host.nix:295`, `modules/darwin/omnigent-host.nix:114` and `modules/clan/inventory/services/omnigent.nix:3-41` | none |
| D4′ one obligation, Darwin excluded | `design.md:87-96`, with fields read directly from `meta` | `interface spec:111-115`. Implemented at `modules/lib/omnigent-fleet-obligations.nix:27-42` (`authorBound`), `:412-422` (`authorBinding` under `lib.optionalAttrs (!isDarwin)`) and `:427` (export) | none |
| D5 workaround removal after delivery | `design.md:107-109` | world assumption A85 (`world spec:275-285`), tasks 4.2–4.4 | not yet executed. It is operator work (§12). |
| D6 dated amendment | `design.md:114-115` | `docs/notes/development/omnigent/deployment-plan.md:1096-1106`, appended after `:1065` "ZeroTier MSS lifecycle recovery", with `:838` "Janette identity amendment" kept | none |
| Trust boundary | `proposal.md:57-61` | `interface spec:3-13`, honored by this report in §13 | none |

**Drift warnings** (non-blocking):

- `proposal.md:72` lists `modules/home/development/{git,jujutsu}.nix` under Impact. The stack changed `jujutsu.nix` but not `git.nix`, and `git.nix:64` still carries the comment "User modules should override user.name and user.email", which now contradicts the `vcs-author` convention (`interface spec:35`). Suggestions S1 and S2.

---

## 5. Implementation Signal

- [x] No unstaged files in the worktree, other than this report (`jj st --ignore-working-copy`: "The working copy has no changes"; `@` is an empty commit on top of an empty commit on top of `main`)
- [x] All related commits have been pushed (`main@origin` = `67f35eb2`)

**Commit range**: `ad22818a^..71f0a8ec`, PR #3793, rebase-merged into `main` through gitea-mq as `67f35eb2`:

```text
ad22818a home: derive git and jj author from the person record through one vcs.author option
30018f57 omnigent: type worker owner as a profile key and set each worker's author from it
71f0a8ec omnigent: regulate every Linux worker's author against its owner's profile, replacing Janette's binding
```

`jj diff --stat --from ad22818a- --to 71f0a8ec` reports 25 files, 316 insertions and 194 deletions.
The code files are exactly those `proposal.md:72-73` names, except `git.nix` (S2).

---

## 6. Front-Door Routing Leak Detector (warning, non-blocking)

```bash
$ ls docs/superpowers/specs/*.md 2>/dev/null
# no output, exit 2: the directory does not exist
```

- [x] No files

| File | Content captured into change? | Recommended action |
|---|---|---|
| — | — | — |

---

## 7. Deferred Manual Dogfood vs Automated Test Equivalence

`plan.md` contains no rows marked `[~]`.
Plan Task 11 (`plan.md:806-868`) holds the operator steps as `- [ ]` rows, and they mirror tasks 4.1–5.2.
Blank means PASS.

---

## 8. Designation Lint and Discharge Coherence (warning, non-blocking)

These checks were run by the agent. `openspec validate` checks none of them.

### 8a. Designation lint

`proposal.md:54` tags `commit-author-identity` as behavioral.
Its nouns were resolved against the designation table in `openspec/specs/world-assumptions/spec.md`, as MODIFIED by this change's delta (`specs/world-assumptions/spec.md:8-244`).

| Requirement (`commit-author-identity/spec.md`) | Resolved against the table | Unresolved — machine noun | Unresolved — world-flavored gap |
|---|---|---|---|
| A commit names the person it is recorded for (`:3-9`) | commit (local), account, host, fleet, person (account), agent, Omnigent worker, owner, author, author name, author address, profile (person), version-control tool, author setting, repository | — | — |
| No commit is recorded with an empty author name (`:31-37`) | commit (local), account, host, fleet, person, Omnigent worker, author name, push, repository (forge-hosted), profile (person), configuration, deploy | — | **personal name** (`:34`), used here and named inside the `profile` and `author name` rows but with no row of its own |
| A person's commits carry their author address, not their sign-in address (`:54-58`) | person, author address, sign-in address, profile (person), Omnigent worker | — | — |
| A person's signed commits verify against their author address (`:70-74`) | account, Omnigent worker, signer principal, author address, verifier (commit signature), signature (commit), commit (local) | — | **public key** (`:72`), named only inside the `profile (person)` and `signature (commit)` rows |
| An Omnigent worker runs only for a person with a profile (`:86-90`) | fleet, Omnigent worker, owner, person, profile (person) | — | **identity** (`:88`, "every Omnigent worker's identity"). The table's only `identity` row is `identity provider` |
| A change to a profile reaches every account of that person at its host's next deploy (`:102-106`) | profile (person), author name, author address, commit (local), account, Omnigent worker, deploy, host | — | — |

Three nouns are unresolved (WARNING W3). Each should get its own row, or the requirement should name the profile's field through an existing row.
The table is present and was consulted, so this result is not vacuous.

### 8b. Discharge coherence

| Requirement | Discharged by (S) | Under (W) | Status |
|---|---|---|---|
| A commit names the person it is recorded for | interface: One rule derives an author from a profile; Every home sets git and jj author from one non-empty pair; A worker's author is its owner's profile, set by the host; Every Linux worker's author is regulated against its owner's profile | A85 | discharged at evaluation (§9, §11). The delivered half is not verified: 4.1, 4.5 and 5.1 are `[operator]`. |
| No commit is recorded with an empty author name | interface: Every home sets git and jj author from one non-empty pair; Every Linux worker's author is regulated against its owner's profile | A84 | discharged at evaluation (type error and `authorBoundEmptyName`, §11.4). The delivered half and re-authoring are not verified: 4.3 and 5.1 are `[operator]`. |
| A person's commits carry their author address, not their sign-in address | interface: One rule derives an author from a profile; The sign-in address is unchanged | — | discharged at evaluation (§11.3). The delivered half is not verified: 5.2 is `[operator]`. |
| A person's signed commits verify against their author address | interface: The signer principal is the author address | — | discharged at evaluation, as rendered `allowed_signers` text only. No task signs and verifies a commit (W1). |
| An Omnigent worker runs only for a person with a profile | interface: A worker's owner is a profile key; A worker's author is its owner's profile, set by the host | — | discharged (§11.4 `owner-nobody`, `ownerOutsideProfiles`) |
| A change to a profile reaches every account of that person at its host's next deploy | interface: One rule derives an author from a profile; Every home sets git and jj author from one non-empty pair; A worker's author is its owner's profile, set by the host | — | discharged by construction (one derivation, §11.2). No task edits a profile and redeploys (W2). |

The world assumptions are reported with the scope of what was observed:

| Assumption | Status |
|---|---|
| A84 — jj refuses to push a commit recorded while `user.name` was empty, until re-authored | `observed` on 2026-11-08 in a throwaway repository with jj 0.47.1, per the spec's own evidence (`world spec:268`). Not re-observed here. `[verified here]`: this session runs `jj 0.47.1`, the pinned release the assumption names. |
| A85 — Repository and environment author settings take precedence over account settings | `observed` for `user.name` at repository level over account level. `[verified here]`, in `/home/omnigent-cameron/projects/vanixiets` on magnetite: `jj config get user.name` prints an empty line from `~` and `Cameron Smith` inside the checkout, and `git config --global user.name` exits 1 while `git config user.name` prints `Cameron Smith` inside it. The environment level and the email counterparts were not exercised here; for those the status is `configured` (documented behavior). |

Every requirement has a named discharge, so none is `undischarged`.
The interface delta carries no `**Discharged by**` lines because it is itself the discharging stratum.

### 8c. Alphabet check

**Violations found**: none.
The behavioral requirements name tools only through "version-control tool" and "author setting".
The interface requirements mention world state (correct names, forge acceptance, deployment, A84 and A85) only to exclude it from their claims (`interface spec:5-8`).

---

## 9. Requirement Implementation Mapping (Correctness)

All file references are to `main` at `67f35eb2`.
Every requirement below is ADDED except `Grounded vocabulary`, which is MODIFIED. No delta has a REMOVED or RENAMED section.

### `commit-author-identity-interface` (interface)

| Requirement | Implementation evidence | Assessment |
|---|---|---|
| The author interface's trust boundary is evaluated and delivered configuration (`:3-8`) | `proposal.md:57-61`; `modules/clan/services/omnigent/README.md:135,146,148` (the `vcs-author` convention is listed at `:148` among things no check covers); `modules/lib/omnigent-fleet-obligations.nix:412-413` comment | matches. This report honors it (§13). |
| One rule derives an author from a profile (`:15-18`) | `modules/home/users/lib.nix:34-37`; `gitEmail` default `= config.meta.email` at `:69-72`. Every caller goes through `vcsAuthor`: `vcs-author.nix:11`, `modules/nixos/omnigent-host.nix:295`, `modules/darwin/omnigent-host.nix:114` | matches |
| Every home sets git and jj author from one non-empty pair (`:30-37`) | `modules/home/development/vcs-author.nix:3-37`: `nonEmptyStr` at `:18,:24`; defaults read through the `flake` special argument at `:7,:11`; both setters at `:32-33`; `development` import at `:37`; worker import `modules/home/ai/omnigent/worker.nix:106`. Removed from the stack: the `mkDefault ""` author in `modules/home/development/jujutsu.nix` (formerly `:174-177`) and the hand-written `user` blocks in the six profiles. `[verified here]`: a grep of `modules/home` finds no other `programs.{git,jujutsu}.settings.user` setter. | matches. The convention that no other module sets `user` remains unchecked, as the spec says. |
| The signer principal is the author address (`:49-52`) | `config.vcs.author.email` principal at `modules/home/users/crs58/default.nix:197`, `janettesmith/default.nix:39`, `christophersmith/default.nix:39`, `raquel/default.nix:44`, `tara/default.nix:28` and `ubuntu/default.nix:90` (literal key). Worker principal `policy.expected.gitEmail` at `modules/home/ai/omnigent/credentials.nix:263-265`; `expected.gitEmail == meta.gitEmail` enforced in `authorBound` at `omnigent-fleet-obligations.nix:42` | matches |
| A worker's owner is a profile key (`:64-67`) | `modules/system/omnigent-worker-options.nix:3,110-111`; `modules/clan/services/omnigent/flake-module.nix:6,83-84`. `extraHomeModules` exists only in the NixOS option set (`omnigent-worker-options.nix:148-151`) and is refused by the clan interface (`modules/checks/omnigent-workers.nix:566-582` `nixOnlyModules`) | matches |
| A worker's author is its owner's profile, set by the host (`:79-83`) | adapters at `modules/nixos/omnigent-host.nix:295` and `modules/darwin/omnigent-host.nix:114`; `workerCredentials owner user labels` reading `config.flake.users.${owner}.meta` at `modules/clan/inventory/services/omnigent.nix:3-41` (`expected` at `:35-39`), called at `:61,70,87,96,112`. `credentials.nix:297,300-303` no longer sets `user.*`. `janetteAuthor` and its `extraHomeModules` are gone from the inventory (stack diff) | matches |
| The sign-in address is unchanged (`:100-102`) | `modules/clan/inventory/services/omnigent.nix:38` `omnigentEmail = meta.email`, also enforced at `omnigent-fleet-obligations.nix:210-214` | matches |
| Every Linux worker's author is regulated against its owner's profile (`:109-115`) | `omnigent-fleet-obligations.nix:27-42` (reads `meta.fullname` and `meta.gitEmail` directly, with a non-empty guard at `:37`), `:412-422`, `:427`. Asserted by the machine checks at `modules/checks/machines.nix:34-47`. The fixtures are in `modules/checks/omnigent-workers.nix:511-540` (helpers) and `:583-631` (8 cases), with expectation all-true at `:813-815`. No check attribute was added (§11.5). | matches |

### `commit-author-identity` (behavioral)

| Requirement | Implementation evidence | Assessment |
|---|---|---|
| A commit names the person it is recorded for (`:3-9`) | all of the above. `[verified here]`: 19/19 `homeConfigurations`, the magnetite and pyrite worker homes and the magnetite `cameron` home evaluate to git = jj = owner's `vcsAuthor` (§11.2) | evaluation boundary met. The delivered half is `[operator]` (4.1, 4.5, 5.1). |
| No commit is recorded with an empty author name (`:31-37`) | `nonEmptyStr` (`vcs-author.nix:18`); `authorBound` guard (`omnigent-fleet-obligations.nix:37`) | evaluation boundary met. The delivered half and re-authoring are `[operator]` (4.3, 5.1). |
| A person's commits carry their author address, not their sign-in address (`:54-58`) | `lib.nix:36` uses `gitEmail`, and `inventory omnigent.nix:36,38` keep the two addresses separate | evaluation boundary met. The delivered half is `[operator]` (5.2). |
| A person's signed commits verify against their author address (`:70-74`) | principals as above | evaluation boundary met as rendered text. Signing and verifying were not exercised (W1). |
| An Omnigent worker runs only for a person with a profile (`:86-90`) | owner `enum` (above); identity read only from `flake.users.${owner}.meta` | met |
| A change to a profile reaches every account of that person at its host's next deploy (`:102-106`) | the single derivation (`lib.nix:34-37`) feeds every human default and both adapters | met by construction (W2) |

### `world-assumptions` (world)

| Requirement | Evidence | Assessment |
|---|---|---|
| MODIFIED Grounded vocabulary for behavioral requirements (`:3-6`) | the delta table is a superset of the main table (§3). `[verified here]`: 26 terms carry more than one row in the delta table, matching the scenario's count at `:249` | met |
| ADDED A84 (`:263-266`) | spec evidence `:268`; the violation scenario at `:270-273` has not been observed | met as a world assumption (§8b) |
| ADDED A85 (`:275-278`) | spec evidence `:280`; partial re-observation in §8b | met as a world assumption (§8b) |

---

## 10. Scenario Coverage

Coverage keys:
- **inv**: an `omnigent-worker-inventory` case, at `modules/checks/omnigent-workers.nix:583-631`. The check's output `/nix/store/i7inydrngwym5b2724273z1pf1rjmv8n-structure-omnigent-worker-inventory` for `main` is present and valid (§11.5), so every case evaluates to `true`.
- **obl**: the `authorBinding` fleet obligation, asserted inside `checks.x86_64-linux.nixos-{magnetite,pyrite}`.
- **eval**: a `[verified here]` probe in §11.
- **op**: an outstanding `[operator]` task.

| Scenario | Coverage |
|---|---|
| interface: A delivered author is claimed from evaluation alone (`:10-13`) | honored. This report does not claim delivery, and §11.6 shows the delivered config still lacks the name. |
| interface: The author address differs from the primary address (`:20-23`) | inv `vcsAuthorFixture` (`:583-591`) |
| interface: Janette's profile is projected (`:25-28`) | eval §11.2 `vcsAuthor` |
| interface: Every home configuration is evaluated (`:39-42`) | eval §11.2, 19/19 entries; the before/step3 diff is in §11.7 |
| interface: A profile's name is empty (`:44-47`) | eval §11.4 `empty-name-raquel` (type error naming `vcs.author.name`) |
| interface: Janette's human signers file is rendered (`:54-57`) | eval §11.2 `janette-signers` |
| interface: A worker's expected email drifts from its author (`:59-62`) | inv `authorBoundExpectedDrift` (`:626-631`); obl `authorBound` clause at `omnigent-fleet-obligations.nix:42` |
| interface: An owner outside the profiles is declared (`:69-72`) | inv `ownerOutsideProfiles` (`:592`); eval §11.4 `owner-nobody` on magnetite |
| interface: Current inventory owners are evaluated (`:74-77`) | inv JSON round trip (`:559-565`); eval §11.3 owners `cameron` and `janettesmith` |
| interface: A worker home is evaluated with a throwing user set (`:85-88`) | `checks.x86_64-linux.omnigent-worker-capabilities` output present and valid; guard at `omnigent-workers.nix:20`, fixture author at `:43-46` |
| interface: Cameron's worker on magnetite is evaluated (`:90-93`) | eval §11.2; before-state in §11.7 |
| interface: A worker without a delivered signing key (`:95-98`) | by construction only: `vcs-author.nix:32-33` is unconditional and `credentials.nix:300` gates only `signing`. The capability fixture has `signingKey = null` (`omnigent-workers.nix:56`), but no case asserts `user.email` (suggestion S5). |
| interface: Janette's worker credentials are evaluated (`:104-107`) | eval §11.3 |
| interface: Cameron's worker loses its name (`:117-120`) | eval §11.4 `someone-else-magnetite` → `["authorBinding"]`; the message format is at `machines.nix:42`. Empty name: type error (§11.4). |
| interface: The mutants are evaluated (`:122-125`) | inv `authorBoundControl`, `authorBoundWrongName`, `authorBoundEmptyName`, `authorBoundJjMismatch`, `authorBoundMissingGitName` and `authorBoundExpectedDrift` (`:593-631`) |
| interface: The check key set is compared (`:127-130`) | eval §11.5: 161 = 161 and 108 = 108, identical lists |
| behavioral: Cameron records commits under both of his accounts (`:11-14`) | eval: magnetite `cameron` home (§11.2), and the stibnite `crs58` home is unchanged and complete in `darwin-stibnite-{before,step3}.json`. Commits on deployed accounts: op (4.1); nothing records the stibnite `crs58` commit. |
| behavioral: A person whose jj author was empty records a commit (`:16-19`) | eval §11.2 and §11.7; op 4.5 |
| behavioral: Omnigent workers for two people record commits on one host (`:21-24`) | eval §11.2 (magnetite and pyrite); op 4.1, 5.1, 5.2 |
| behavioral: An author setting held for the repository differs (`:26-29`) | A85. `[verified here]` in this checkout (§8b) |
| behavioral: Cameron's worker pushes a commit (`:39-42`) | op 5.1 |
| behavioral: A profile's personal name is emptied (`:44-47`) | eval §11.4 `empty-name-raquel`; inv `authorBoundEmptyName` |
| behavioral: A commit was recorded before the host deployed (`:49-52`) | A84; op 4.3. `[verified here]`: 0 empty-author mutable commits in this checkout today (§11.6) |
| behavioral: Janette's author address differs from her sign-in address (`:60-63`) | eval §11.2, §11.3, and `darwin-rosegold-step3.json`; op 5.2 |
| behavioral: Author address and sign-in address coincide (`:65-68`) | `lib.nix:69-72` default; inv `gitEmailDefault` (`omnigent-workers.nix:545`) |
| behavioral: Janette's signed commit is verified (`:76-79`) | eval `janette-signers` only. **No signing or verification is exercised (W1).** |
| behavioral: The signer principal is the sign-in address (`:81-84`) | the worker side is covered by `authorBoundExpectedDrift`. No human-side mutant exists; the human principal is only evaluated as rendered. |
| behavioral: A worker is declared for someone without a profile (`:92-95`) | eval §11.4 `owner-nobody`; inv `ownerOutsideProfiles` |
| behavioral: A worker's owner is named by the newer account name (`:97-100`) | eval §11.2: `vcsAuthor` of `cameron` equals that of `crs58` |
| behavioral: Janette's author address changes (`:108-111`) | **by construction only (W2)** |
| behavioral: A host has not yet deployed (`:113-116`) | `[verified here]` on magnetite (§11.6): `main` evaluates `Cameron Smith`, while the delivered config still has an empty name |
| world: The terms with two senses are read (`:246-249`) | §9: 26 terms |
| world: A term resolves to two phenomena (`:251-254`) | table structure, for example the two `profile` rows at `:237-238` |
| world: A behavioral requirement uses an unlisted term (`:256-259`) | §8a, which found 3 unresolved nouns (W3) |
| world: A84 violation scenario (`:270-273`) | not observed in this window |
| world: A85 violation scenario (`:282-285`) | not observed in this window. The precedence held in §8b. |

---

## 11. Evaluation evidence ledger `[verified here]`

### 11.1 Commands cited

```text
openspec status --change unify-vcs-author-identity --json
openspec instructions apply --change unify-vcs-author-identity --json
openspec instructions verify --change unify-vcs-author-identity --json
openspec validate unify-vcs-author-identity [--strict]
openspec validate --all --json
jj --ignore-working-copy log / diff --stat / st     (read-only)
nix eval --impure --json --expr 'let f = F; in …'    (probes below)
nix eval --raw 'git+file://…?rev=67f35eb2…#checks.x86_64-linux.nixos-{magnetite,pyrite}.outPath'
nix path-info <outPath>
jj config get user.name; jj config list --repo user; git config [--global|--local] user.name   (read-only)
```

### 11.2 Author projections on `main`

```text
f.lib.omnigentFleetObligations.failures "magnetite" f.nixosConfigurations.magnetite.config   → []
f.lib.omnigentFleetObligations.failures "pyrite"    f.nixosConfigurations.pyrite.config      → []
f.lib.omnigentFleetObligations.failures "stibnite"  f.darwinConfigurations.stibnite.config   → []

magnetite home-manager.users.<u>.programs.{git,jujutsu}.settings.user:
  omnigent-cameron      git = jj = { name = "Cameron Smith"; email = "cameron.ray.smith@gmail.com"; }
  omnigent-janettesmith git = jj = { name = "Janette Smith"; email = "125711642+janetteasmith@users.noreply.github.com"; }
  cameron               git = jj = { name = "Cameron Smith"; email = "cameron.ray.smith@gmail.com"; }
pyrite:
  omnigent-cameron      git = jj = { name = "Cameron Smith"; email = "cameron.ray.smith@gmail.com"; }
  omnigent-janettesmith git = jj = { name = "Janette Smith"; email = "125711642+janetteasmith@users.noreply.github.com"; }

f.lib.vcsAuthor f.users.{janettesmith,cameron,crs58}.meta:
  janettesmith { email = "125711642+janetteasmith@users.noreply.github.com"; name = "Janette Smith"; }
  cameron      { email = "cameron.ray.smith@gmail.com"; name = "Cameron Smith"; }
  crs58        { email = "cameron.ray.smith@gmail.com"; name = "Cameron Smith"; }

f.homeConfigurations.*.config.{programs.git.settings.user, programs.jujutsu.settings.user, vcs.author}:
  19 entries; in every one git == jj == vcs.author and the name is non-empty. Distinct authors:
  cameron, crs58, ubuntu  → Cameron Smith <cameron.ray.smith@gmail.com>
  christophersmith        → Christopher Smith <christophersmith@example.com>
  janettesmith            → Janette Smith <125711642+janetteasmith@users.noreply.github.com>
  raquel                  → Raquel <raquel@example.com>
  tara                    → Tara Chari <17519396+tarachari3@users.noreply.github.com>

f.homeConfigurations."janettesmith@x86_64-linux".config.sops.templates.allowed_signers.content
  → "125711642+janetteasmith@users.noreply.github.com namespaces=\"git\" <SOPS:…:PLACEHOLDER>\n"
```

### 11.3 Worker owner and credential expectations on magnetite

```text
builtins.mapAttrs (_: w: { inherit (w) owner; expected = w.credentials.expected; })
  f.nixosConfigurations.magnetite.config.services.omnigent-host.workers
  cameron      owner = "cameron";      expected = { gitEmail = "cameron.ray.smith@gmail.com"; omnigentEmail = "cameron.ray.smith@gmail.com"; signingPublicKey = "ssh-ed25519 …GyUH+"; }
  janettesmith owner = "janettesmith"; expected = { gitEmail = "125711642+janetteasmith@users.noreply.github.com"; omnigentEmail = "janette.a.smith@gmail.com"; signingPublicKey = "ssh-ed25519 …KnKP0"; }

(f.nixosConfigurations.magnetite.options.services.omnigent-host.workers.type.getSubOptions []).owner.type.description
  → one of "cameron", "christophersmith", "crs58", "janettesmith", "raquel", "tara", "ubuntu"
```

These `expected` values equal `nixos-magnetite-before.json` exactly; the before/step3 diff for magnetite touches only the `omnigent-cameron` name fields (§11.7).

### 11.4 Negative controls (overrides through `extendModules`, not committed)

```text
empty-name-raquel:
  (f.homeConfigurations."raquel@x86_64-linux".extendModules { modules = [ { vcs.author.name = ""; } ]; })
    .config.programs.jujutsu.settings.user.name
  → exit 1: A definition for option `vcs.author.name' is not of type `non-empty string'.

someone-else-magnetite:
  f.lib.omnigentFleetObligations.failures "magnetite"
    (f.nixosConfigurations.magnetite.extendModules { modules = [ ({ lib, ... }: {
      home-manager.users.omnigent-cameron.vcs.author.name = lib.mkForce "Someone Else"; }) ]; }).config
  → ["authorBinding"]

owner-nobody:
  (f.nixosConfigurations.magnetite.extendModules { modules = [ ({ lib, ... }: {
    services.omnigent-host.workers.cameron.owner = lib.mkForce "nobody"; }) ]; })
    .config.services.omnigent-host.workers.cameron.owner
  → exit 1: A definition for option `services.omnigent-host.workers.cameron.owner' is not of type
    `one of "cameron", "christophersmith", "crs58", "janettesmith", "raquel", "tara", "ubuntu"'.
```

### 11.5 Checks on `main`

```text
builtins.attrNames f.checks.x86_64-linux    → 161 names, identical to checks-x86_64-linux-before.json
builtins.attrNames f.checks.aarch64-darwin  → 108 names, identical to checks-aarch64-darwin-before.json
f.checks.aarch64-darwin ? omnigent-worker-inventory → false   (mutants are x86_64-linux only)

outPath, then nix path-info:
  x86_64-linux.omnigent-worker-inventory    /nix/store/i7inydrngwym5b2724273z1pf1rjmv8n-structure-omnigent-worker-inventory  VALID
  x86_64-linux.omnigent-worker-capabilities /nix/store/md8l33cps1wabmwhdbdimchvcy4b612r-omnigent-worker-capabilities        VALID
  x86_64-linux.omnigent-worker-linux        /nix/store/lcj0jm3w8xrd41ixkvakrpjv3dqikh1z-omnigent-worker-linux               VALID
  x86_64-linux.home-manager-janettesmith    /nix/store/cwkj8p6qjhhmzfv9056xf05im1p3wjfn-home-manager-generation             VALID
  x86_64-linux.home-manager-raquel          /nix/store/7k5xp1jw0jk7sg82zsa1c7wwh6fvvlqy-home-manager-generation             VALID
  x86_64-linux.nixos-magnetite              /nix/store/434d7hdllxdivcn8mz5a767gs57s8jk9-nixos-system-magnetite-…  evaluates; not built locally
  x86_64-linux.nixos-pyrite                 /nix/store/dp8kz8gfv6y0avywdv5m6hcrrh8ix1xv-nixos-system-pyrite-…     evaluates; not built locally
```

`mkStructuralCheck` (`modules/lib/mk-structural-check.nix:22-40`) creates `$out` only when actual equals expected.
For `omnigent-worker-inventory` the expected value is every case `true` (`omnigent-workers.nix:813-815`).
A valid output path for `main`'s derivation therefore shows that all eight new cases hold.
The machine checks' fleet-obligation `assert` (`machines.nix:41-47`) is evaluated when `outPath` is forced, so it passes on `main`.
Their realized builds come from tasks 2.7 and 3.5 at the stack commits, not from this session.

### 11.6 Delivered state on magnetite before any operator action

Read-only, as `omnigent-cameron` on `magnetite`, with `jj 0.47.1`:

```text
readlink /run/current-system → /nix/store/kg490h0lfx7fsbfnl2a03rizv0s350ng-nixos-system-magnetite-…   (≠ main's 434d7hdl…)
cd ~ && jj config get user.name          → ""            (empty: the pre-change jj default is still delivered)
git config --global user.name            → exit 1        (no global git name delivered)
cd ~/projects/vanixiets:
  jj config list --repo user             → user.name = "Cameron Smith"   (workaround present)
  git config --local --get user.name     → Cameron Smith, exit 0         (workaround present)
  jj log -r 'mutable() & author_name(exact:"")' → no output (0 commits)
```

This shows magnetite has not been deployed with this change and the repository-local workaround is still in place.
Tasks 4.1 and 4.2 have therefore not started.

### 11.7 Before vs. after projections (`~/.local/state/agent-logs/vanixiets/*-before.json` vs `*-step3.json`)

Every difference is one of the proposal's intended value changes (`proposal.md:30`):

| Projection | Differences (before → step3) |
|---|---|
| `authors` (homeConfigurations) | jj name and email `""` → git's values for christophersmith, raquel and tara on 3 systems each and ubuntu on 1; jj name `""` → `Janette Smith` for janettesmith on 3 systems. 23 fields in total. |
| `nixos-magnetite`, `nixos-pyrite` | `omnigent-cameron`: git name absent → `Cameron Smith`, jj name `""` → `Cameron Smith` |
| `nixos-galena`, `nixos-scheelite` | `tara`: jj name and email `""` → `Tara Chari`, `17519396+tarachari3@users.noreply.github.com` |
| `darwin-argentum` | `christophersmith`: jj name and email `""` → git's values |
| `darwin-blackphos` | `raquel`: jj name and email `""` → git's values |
| `darwin-rosegold` | `janettesmith`: jj name `""` → `Janette Smith` |
| `darwin-stibnite`, `nixos-cinnabar`, `nixos-electrum` | none |

No signer text, signing key, git email or `credentials.expected` value differs.

### 11.8 Delivered state on magnetite after activating PR #3793

Magnetite system generation 222 was activated at 2026-11-09T04:31:16Z (`/run/current-system` → `zz2gs1p4…`, a switch without reboot from generation 221 `kg490h0l…`), built by the operator from a local checkout at `a680f9a` with uncommitted edits rather than from `main`. Only the identity fields below are attributed to this change.

```text
home-manager files, generation 221 → 222:
  omnigent-cameron  jj  name ""            → "Cameron Smith"
  omnigent-cameron  git name (absent)      → "Cameron Smith"
  cameron, omnigent-janettesmith           unchanged; every email unchanged

as omnigent-cameron, cd /tmp (4.1 delivered half):
  jj config get user.name / user.email     → Cameron Smith / cameron.ray.smith@gmail.com
  git config --global user.name / email    → Cameron Smith / cameron.ray.smith@gmail.com

5.1, scratch jj repo with local bare remote: push succeeded;
  jj log -T author and the remote's git log → Cameron Smith <cameron.ray.smith@gmail.com>

5.2 [operator], as omnigent-janettesmith via sudo -u, cd /tmp:
  jj config get user.email → 125711642+janetteasmith@users.noreply.github.com
  jj config get user.name  → Janette Smith
  (plus the out-of-scope git.sign-on-push deprecation warning)

4.2, in /home/omnigent-cameron/projects/vanixiets:
  jj config unset --repo user.name; git config --local --unset user.name
  jj config list --repo user               → "No matching config key for: user"
  git config --local --get user.name       → exit 1
  jj config get user.name / git config user.name → Cameron Smith (both, from the delivered user config)

4.3:
  jj log -r 'mutable() & author_name(exact:"")' → no output, before and after
  jj metaedit --update-author -r '…'       → "No revisions to modify."
  every mutable commit's author            → Cameron Smith <cameron.ray.smith@gmail.com>
```

---

## 12. Outstanding operator tasks

Each task below is `[operator]`; those still unchecked in `tasks.md` **block archive**.
The steps and expected evidence are copied from `tasks.md:40-49`, with the exact commands from plan Task 11 (`plan.md:810-868`).
§12.2, §12.3, §12.6 and §12.7 are complete on magnetite (§11.8); §12.1 is complete for magnetite's delivered author only.

### 12.1 Task 4.1 — Deploy magnetite, pyrite and stibnite

- **Operator steps**: deploy magnetite, pyrite and stibnite. After each deploy, read every post on the fleet's notification topics since that deploy started and attribute each one to a cause (`plan.md:810-812`). Then, as `omnigent-cameron` on magnetite and outside any repository:
  `cd ~ && jj config get user.name && jj config get user.email && git config --global user.name` (`plan.md:816-820`).
- **Expected evidence** (`tasks.md:40`): "delivered path after activation: as `omnigent-cameron` on magnetite, `jj config get user.name` prints `Cameron Smith` outside any repository and `git config --global user.name` prints `Cameron Smith`; the notification topics' history since the deploy is read and every post is attributed". Plan Step 2 expects `Cameron Smith`, `cameron.ray.smith@gmail.com`, `Cameron Smith`.
- **Current state**: magnetite is deployed and its delivered author is `[verified here]` (§11.8). Pyrite and stibnite are not deployed. The notification topics are not read: nothing listens on magnetite's `[::1]:2586`, consistent with `modules/nixos/fleet-alert.nix` placing the dead-man's ntfy on its own host.
- **Blocks archive**: yes.

### 12.2 Task 4.2 — Remove the repository-local workaround on magnetite

- **Operator steps** (after 4.1 passes), from `plan.md:826-833`:
  ```bash
  cd /home/omnigent-cameron/projects/vanixiets
  jj config unset --repo user.name
  git config --local --unset user.name
  jj config list --repo user
  git config --local --get user.name; echo "exit=$?"
  jj config get user.name
  ```
- **Expected evidence** (`tasks.md:41`): "`jj config list --repo user` prints nothing for `user.name`, `git config --local --get user.name` exits 1, and `jj config get user.name` in that checkout still prints `Cameron Smith`".
- **Current state** `[verified here]`: done (§11.8).
- **Blocks archive**: no.

### 12.3 Task 4.3 — Re-author empty-author mutable commits

- **Operator steps**, from `plan.md:839-846`:
  ```bash
  jj log -r 'mutable() & author_name(exact:"")' --no-graph -T 'change_id.short() ++ "\n"'
  jj metaedit --update-author -r 'mutable() & author_name(exact:"")'   # skip if the first command printed nothing
  jj log -r 'mutable() & author_name(exact:"")' --no-graph -T 'change_id.short() ++ "\n"'
  ```
- **Expected evidence** (`tasks.md:42`): "`jj log -r 'mutable() & author_name(exact:"")' --no-graph -T 'change_id ++ "\n"'` prints nothing, and a dry `jj git push --dry-run` of a bookmark on such a commit reports no author error".
- **Current state** `[verified here]`: done after 4.2; no commit matched (§11.8).
- **Blocks archive**: no.

### 12.4 Task 4.4 — Check the pyrite and stibnite omnigent-cameron checkouts

- **Operator steps**: on pyrite and stibnite, as `omnigent-cameron`, check each checkout for a repository-local `user.name`. If one is present, remove it with the 4.2 commands (`plan.md:848`). This also answers the open question at `design.md:181-182`.
- **Expected evidence** (`tasks.md:43`): "delivered state on each host, as in 4.2".
- **Blocks archive**: yes.

### 12.5 Task 4.5 — Deploy the remaining affected hosts

- **Operator steps**: deploy argentum, blackphos, rosegold, galena and scheelite at the operator's discretion (`plan.md:866-868`).
- **Expected evidence** (`tasks.md:44`): "delivered path after activation: `jj config get user.name` as each affected account prints that person's `meta.fullname`". On evaluated `main` those names are `Christopher Smith` (argentum), `Raquel` (blackphos), `Janette Smith` (rosegold) and `Tara Chari` (galena and scheelite) (§11.7).
- **Blocks archive**: yes, while the box is unchecked. If the operator chooses to defer these deploys, `tasks.md` must record that before archive.

### 12.6 Task 5.1 — Push a Cameron worker commit end to end

- **Operator steps** (as `omnigent-cameron` on magnetite, after 4.1), from `plan.md:852-858`:
  ```bash
  t=$(mktemp -d) && cd "$t" && git init -q --bare remote.git && jj git init --colocate repo >/dev/null && cd repo
  jj git remote add origin ../remote.git && echo x > f && jj commit -m probe && jj bookmark create probe -r @-
  jj log -r @- --no-graph -T 'author ++ "\n"'
  jj git push --bookmark probe --allow-new
  cd / && rm -rf "$t"
  ```
- **Expected evidence** (`tasks.md:48`): "the push succeeds and `jj log -r @- -T 'author'` shows `Cameron Smith <cameron.ray.smith@gmail.com>`".
- **Current state** `[verified here]`: done on magnetite (§11.8).
- **Blocks archive**: no.

### 12.7 Task 5.2 — Janette's author and sign-in addresses stay distinct after delivery

- **Operator steps** (after 4.1): as `omnigent-janettesmith` on magnetite, run `jj config get user.email`. Then evaluate
  `nix eval '.#.nixosConfigurations.magnetite.config.services.omnigent-host.workers.janettesmith.credentials.expected.omnigentEmail'` (`plan.md:862-864`).
- **Expected evidence** (`tasks.md:49`): "`jj config get user.email` prints `125711642+janetteasmith@users.noreply.github.com` while the worker's credential policy still expects `janette.a.smith@gmail.com` as its Omnigent identity".
- **Current state**: done. The delivered half is `[operator]` and the evaluation half `[verified here]` (§11.3, §11.8).
- **Blocks archive**: no.

---

## 13. Trust boundary

`specs/commit-author-identity-interface/spec.md:3-13` limits what this report may claim.
Everything marked `[verified here]` in §9–§11 holds of evaluated configurations on `main`.
None of it establishes that any host delivers the new author, that no repository-local or environment setting overrides it (A85), or that commits recorded earlier are pushable (A84).
§11.6 shows the opposite on magnetite today.
The stibnite worker's author is claimed only through the shared `vcs-author` module and the Darwin adapter line `modules/darwin/omnigent-host.nix:114`. The `authorBinding` obligation is absent from Darwin hosts' cases, and `failures "stibnite"` returns `[]` without checking it.
The convention that no module other than `vcs-author` sets a human home's git or jj `user` is unchecked. It is recorded as such at `modules/clan/services/omnigent/README.md:148`, and the grep in §9 is a point-in-time observation, not a regulator.

---

## 14. Issues by Priority

### CRITICAL (must be resolved before archive; none is a code defect)

- C1. Task 4.1 is incomplete: deploy pyrite and stibnite, and attribute the notices on the fleet topics. Magnetite is done (§11.8). See §12.1.
- C4. Task 4.4 is incomplete: check the pyrite and stibnite checkouts for the workaround. See §12.4.
- C5. Task 4.5 is incomplete: deploy argentum, blackphos, rosegold, galena and scheelite, or record the deferral in `tasks.md`. See §12.5.

C2, C3, C6 and C7 (tasks 4.2, 4.3, 5.1 and 5.2) are resolved on magnetite (§11.8).

### WARNING (should fix)

- W1. Scenario not covered: "Janette's signed commit is verified" (`commit-author-identity/spec.md:76-79`). Only the rendered `allowed_signers` text is evaluated; no task signs and verifies a commit (`design.md:160` already says so). Recommendation: add an operator step, after 4.5, in which Janette's account on rosegold signs and verifies a scratch commit, or record the gap in the retrospective.
- W2. Scenario not covered: "Janette's author address changes" (`commit-author-identity/spec.md:108-111`). It is discharged by construction through `lib.nix:34-37`; no task edits a profile and redeploys (`design.md:162`). Recommendation: record the gap in the retrospective. An `extendModules` probe that overrides `flake.users.janettesmith.meta.gitEmail` would cover the evaluation half.
- W3. Designation lint (§8a): the behavioral nouns "personal name" (`commit-author-identity/spec.md:34`), "public key" (`:72`) and "identity" (`:88`) resolve to no row of the designation table. Recommendation: add rows to `specs/world-assumptions/spec.md`, or reword those requirements to use the existing `profile (person)`, `author name` and `signature (commit)` rows.

### SUGGESTION (nice to fix)

- S1. `modules/home/development/git.nix:64` still says "User modules should override user.name and user.email", which contradicts the `vcs-author` convention (`interface spec:35`). Recommendation: reword it to point at `vcs.author`.
- S2. `proposal.md:72` lists `modules/home/development/{git,jujutsu}.nix` under Impact, but the stack did not change `git.nix`. Recommendation: correct the Impact line, or note it in the retrospective.
- S3. `openspec validate --strict` exits 1 with 7 warnings that requirement text exceeds 500 characters. The non-strict result is valid. Recommendation: move edge cases into scenarios before sync if strict validation is wanted.
- S4. `design.md:127` names two other changes that replace the designation table, but four active changes carry a MODIFIED `Grounded vocabulary` delta (§3). Recommendation: name all four in the retrospective so the archive order is planned.
- S5. Scenario "A worker without a delivered signing key" (`interface spec:95-98`) is met by construction only. The capability fixture has `signingKey = null` (`modules/checks/omnigent-workers.nix:56`) but asserts nothing about `user.email`. Recommendation: assert the fixture home's git and jj `user.email` there if a regulator is wanted.

### Final assessment

3 critical issues are open: the operator tasks 4.1 (pyrite, stibnite and the notification read), 4.4 and 4.5. They must be completed before archiving.
None of them is a code defect.
On magnetite the delivered-state half of `A commit names the person it is recorded for`, `No commit is recorded with an empty author name` and `A person's commits carry their author address, not their sign-in address` is verified (§11.8); on the other affected hosts it is not.
There are 3 warnings and 5 suggestions.
The change is not ready for archive.

---

## Overall Decision

- [ ] (pass) PASS — may proceed to finishing-a-development-branch and archive
- [ ] (warn) PASS WITH WARNINGS — may proceed to subsequent steps but note: `<explanation>`
- [ ] (fail) FAIL — return to the failed artifact, correct it, then re-run verify

No box is checked.
No defect was found in the delivered code: every ADDED and MODIFIED requirement is implemented on `main` at the evaluation boundary, and the negative controls fail the way the specs require (§11.4).
The decision waits on the operator tasks 4.1, 4.4 and 4.5 (§12). All three block archive.

**Next step**:

The operator deploys pyrite and stibnite and reads the notification topics (§12.1), checks their checkouts (§12.4), and deploys or defers the remaining hosts (§12.5).
Verify then records that evidence, ticks the tasks in `tasks.md`, and sets the Overall Decision.
