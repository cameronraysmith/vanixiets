## Context

A person's version-control author is the pair git and jj record on each commit as `user.name` and `user.email`.
In this repository that pair is written in four places, each covering only what its originating commit needed: the crs58 profile (from `meta.email`), the janettesmith profile (git name and email, jj email only), the inventory's `janetteAuthor` block passed to Janette's workers through `extraHomeModules`, and the worker credential module, which sets email only and only when a signing key is delivered.
`modules/home/development/jujutsu.nix` defaults jj `user.name` and `user.email` to `lib.mkDefault ""`, and only crs58 and its alias cameron override both.

Evaluation on 2026-11-08 shows the consequence.
In `homeConfigurations`, jj `user` is `{ name = ""; email = ""; }` for christophersmith, raquel, tara and ubuntu on every system they are built for, and `{ name = ""; email = <git email>; }` for janettesmith, while git `user` is complete for all of them.
On magnetite, `home-manager.users.omnigent-cameron` has git `user = { email = "cameron.ray.smith@gmail.com"; }` and jj `user = { name = ""; email = "cameron.ray.smith@gmail.com"; }`, while `omnigent-janettesmith` is complete through `janetteAuthor`.
jj 0.47.1 refuses to push such a commit (`Won't push commit … since it has no author and/or committer set`), and re-running the push after configuring a name still refuses, because the commit keeps the empty author it was recorded with.
The omnigent-cameron checkout of this repository currently carries a repository-local `user.name` in both `.jj` and `.git` configuration, which hides the failure there only.

Four facts make a single rule possible without a new field.
`flake.users.cameron` already exists, materialized by `modules/home/users/aliases-fold.nix` from crs58 with only `meta.username` changed.
Every worker `owner` in the inventory and the check fixtures (cameron, janettesmith, raquel) is already a `flake.users` key, and the fleet obligations already require worker key, owner and `${machine}-${owner}` host name to agree.
`meta.gitEmail` equals `meta.email` for every profile except janettesmith, whose profile already uses `gitEmail`, so switching every consumer to `gitEmail` changes no rendered address.
Every home-manager user on every NixOS and nix-darwin host is a `flake.users` key (cameron, crs58, christophersmith, janettesmith, raquel, tara) apart from the `omnigent-*` worker accounts, and every human profile imports the `development` aggregate.

The stakeholders are each person with a profile, whose commits should carry their name, and the operator, who owns the Omnigent workers that commit on Cameron's and Janette's behalf.

## Goals / Non-Goals

**Goals:**

- One derivation from a person's profile to their author pair, used by every human home and every worker home.
- No home, human or worker, records an empty author name, and git and jj record the same author.
- Worker identity follows `owner`, which becomes a typed reference to a profile.
- One obligation regulates every Linux worker's author, with a fixture showing it can fail, at no new check attribute.
- Remove the repository-local workaround once the declarative fix is delivered.

**Non-Goals:**

- The `git.sign-on-push` deprecation in `jujutsu.nix` and `modules/home/ai/omnigent/worker.nix`.
- Deduplicating the ubuntu profile's meta, which repeats Cameron's identity.
- Any change to signing authority, token selection, `defaultOwner`, `expected.omnigentEmail` or the credential policy's JSON shape.
- Re-authoring commits other than those the workaround's removal would leave unpushable in the omnigent-cameron checkout.
- Directly observing the stibnite worker's standalone home-manager generation in a check.

## Decisions

### D1′: one derivation rule in flake-level lib

- **Choice**: `flake.lib.vcsAuthor = meta: { name = meta.fullname; email = meta.gitEmail; };`, declared beside `flake.users` in `modules/home/users/lib.nix`.
- **Rationale**: `gitEmail` is the field already typed as the git author address; `fullname` is documented as the name for git commits.
  Placing the rule beside the typed meta keeps the person record and its projection in one file.
- **Alternatives considered**: deriving from `meta.email` as the crs58 profile does today (F1), rejected because it would put Janette's sign-in address on her commits; per-profile literals, rejected because they are the restatement this change removes.
- **Boundary**: first-party source only; nothing delivered changes from this decision alone.

### D2′ (as refined): one home-manager option holding the resolved pair

- **Choice**: a new module `flake.modules.homeManager.vcs-author` (stable `key = "vanixiets/vcs-author-home-module"`) declares `vcs.author.name` and `vcs.author.email`, both `lib.types.nonEmptyStr`, and sets `programs.git.settings.user` and `programs.jujutsu.settings.user` to `{ inherit (config.vcs.author) name email; }`.
  Each option's default is the matching field of `flake.lib.vcsAuthor flake.users.${config.home.username}.meta`, read through the home-manager `flake` special argument.
  The `development` aggregate imports it, `jujutsu.nix` loses its `mkDefault ""` author, and the six human profiles (crs58, janettesmith, christophersmith, raquel, tara, ubuntu) lose their hand-written git and jj `user` blocks.
  Each profile's `allowed_signers` line uses `config.vcs.author.email` as its principal, while its key source stays per profile: a sops placeholder for five profiles and a literal public key for ubuntu.
  The module never sets `signing.*`.
  That no other module sets a human home's git or jj `user` is a review convention that no check verifies; worker homes are regulated by `authorBinding` (D4′).
  A differing second definition would fail with a conflicting-definition error, but that is a property of the nixpkgs module system, so a fixture asserting it would test nixpkgs rather than this repository, and none is added.
- **Rationale**: a typed non-empty pair makes an empty author an evaluation error in every home that imports it, and one setter makes git and jj agree by construction.
  No explicit alias resolution is needed, because `flake.users.cameron` already exists.
- **Supersedes**: the session's wording named the option `vcs.author.profile`, typed as a `flake.users` key.
  `modules/checks/omnigent-workers.nix` hands worker homes a `flake` whose `users` attribute throws `"worker imported a whole-user alias"`, enforcing that worker home-manager never reads `flake.users`.
  A profile-key option resolved inside home-manager would have to read `flake.users` and trip that guard; the resolved pair does not, because the worker adapters set it and the default is never forced.
  The module must read `flake.users` through the special argument rather than closing over the flake-parts `config.flake.users`, since a closure would bypass the guard silently.
- **Alternatives considered**: per-profile `programs.jujutsu.settings.user` blocks matching the git ones, rejected as the restatement pattern; setting only jj, rejected because git and jj would keep separate setters.
- **Boundary**: source versus delivered.
  The edited sources are the module and profile files; the delivered outputs are each account's `~/.config/git/config`, `~/.config/jj/config.toml` and `~/.config/git/allowed_signers`, which change only after a home or system activation and are verified by evaluation before it and by reading the delivered path after it.
  Vendored versus first-party: home-manager's `programs.git` and `programs.jujutsu` are vendored and only set, never patched.

### D3′: owner is a profile key; adapters set the worker author

- **Choice**: `owner` becomes `lib.types.enum (lib.attrNames config.flake.users)` in `modules/system/omnigent-worker-options.nix` and in the host role interface of `modules/clan/services/omnigent/flake-module.nix`.
  The NixOS and Darwin adapters add `{ vcs.author = flakeConfig.flake.lib.vcsAuthor flakeConfig.flake.users.${worker.owner}.meta; }` to each worker home's modules, and `modules/home/ai/omnigent/worker.nix` imports `vcs-author`.
  The inventory's `workerCredentials` takes the owner, the worker account name and the Linear labels (`workerCredentials owner user labels`) and reads `config.flake.users.${owner}.meta` itself; the account name stays explicit rather than being derived as `omnigent-${owner}`.
  Removed: the inventory's `janetteAuthor` and its `extraHomeModules`, the hand-passed meta, `ownerMeta` in the fleet obligations, and the `user.email` lines in `credentials.nix`.
  `janetteAuthor` and its `extraHomeModules` are removed in delivery step 3, together with the obligation that regulates them, not in step 2; until then they define the same strings the adapter sets, and equal definitions merge (verified on 2026-11-08 by evaluating magnetite with a duplicate equal author for `omnigent-janettesmith`: no conflict, `failures` returned `[]`).
  The credential policy keeps `expected.gitEmail`, which still feeds the worker's `allowed_signers` principal.
- **Rationale**: every current owner already is a profile key, so typing it adds no field and no migration of values.
  Setting the pair at system level keeps the worker invariant: two non-secret strings reach the worker home, and no human module, `contentPrivate`, sops material or age key does.
  Removing `user.email` from `credentials.nix` gives a worker without a delivered signing key its author email too.
- **Alternatives considered**: a new `profile` field beside the `owner` label (initial D3), rejected after F9 and F11 showed `owner` already holds profile keys; a name in the credential policy (O2), rejected because it widens a shared contract and leaves human homes unfixed; Cameron-specific `extraHomeModules` (O1), rejected as a fifth restatement.
- **Boundary**: vendored versus first-party.
  The clan interface is first-party but is evaluated by vendored clan-core, which requires inventory settings to be JSON-serializable; an `enum` of strings stays serializable, and `extraHomeModules` stays out of the interface.
  Source versus delivered: the worker's delivered git and jj configuration changes only after magnetite, pyrite and stibnite are deployed.

### D4′ (as refined): one author obligation inside the existing fleet obligations

- **Choice**: in `modules/lib/omnigent-fleet-obligations.nix`, replace `identityBoundHomeModules` and `identityBindingDiscriminates` with one `authorBinding` case.
  For each worker on a Linux host it reads `hostConfig.home-manager.users.${worker.user}` and requires git `user.name` and `user.email` to equal jj `user.name` and `user.email`, to equal `meta.fullname` and `meta.gitEmail` of `config.flake.users.${worker.owner}.meta`, the name to be non-empty, and `worker.credentials.expected.gitEmail` to equal the author email.
  The predicate is exposed as `flake.lib.omnigentFleetObligations.authorBound` so that `checks.x86_64-linux.omnigent-worker-inventory` can apply it to synthetic inputs: one correct control and five mutants (wrong author name; empty name; jj email differing from git email; a git author with an email and no name, the shape observed on Cameron's workers; and an expected `gitEmail` differing from the author email).
  The empty-name mutant is the only one that exercises the non-empty-name guard.
  The same inventory check gains a literal case for `vcsAuthor` on the gitEmail-override fixture and a case showing the clan interface rejects an owner that is not a profile key, so it evaluates eight new cases in all.
  On Darwin hosts `authorBinding` is not evaluated: `cases` merges it in through `lib.optionalAttrs (!isDarwin)`, so `failures` neither checks nor reports it there.
  stibnite's worker author is covered through the shared `vcs-author` module and adapter code that the Linux workers exercise.
  `credentialWiring` has the same limitation but is written `isDarwin || …`, so it is reported as met on Darwin; it is left unchanged here as an out-of-scope follow-up.
- **Rationale**: per `check-vacuity.md`, configuration facts belong in existing fleet obligations, and the expected values are read from `meta` fields directly rather than through `vcsAuthor`, so a defect in the rule under test (for example deriving from `meta.email`) fails Janette's workers instead of agreeing with itself.
  The mutants show the predicate can fail; the control shows it is not vacuously false.
- **Evaluation cost (F14)**: no check attribute is added or renamed.
  The obligation rides on `checks.x86_64-linux.nixos-magnetite` and `checks.x86_64-linux.nixos-pyrite`, whose names `modules/checks/machines.nix` derives from the clan inventory and `flake.lib.machineSystems`, and which already force the host configuration it reads, so its marginal cost is reading four strings per worker home; `checks.aarch64-darwin.darwin-stibnite` asserts the same `failures`, in which the case is absent.
  The fixtures run inside `omnigent-worker-inventory`, which is gated to `x86_64-linux` and evaluates no machine configuration, so they are evaluated once per run rather than once per machine or per system.
  A separate check attribute would add a key every evaluator worker pays for and would have to re-force host configurations the machine checks already hold.
- **Alternatives considered**: a new author check on `x86_64-linux` (rejected for the cost above); keeping the per-person `identityBinding` (rejected by F8).
- **Boundary**: source versus delivered.
  The obligation judges evaluated configurations, not delivered files; delivered state is verified after activation by reading the worker's configuration as that account.

### D5: remove the repository-local workaround only after delivery

- **Choice**: once the worker's delivered configuration shows the author, run `jj config unset --repo user.name` and `git config --local --unset user.name` in `/home/omnigent-cameron/projects/vanixiets`, then re-author any commit still recorded with an empty name using `jj metaedit --update-author`.
- **Rationale**: repository-local settings take precedence over account-level ones, so leaving the override would hide a future regression in that checkout.
  Removing it before delivery would reintroduce unpushable commits.
- **Boundary**: delivered state outside nix; neither file is nix-managed.

### D6: documentation as a dated amendment

- **Choice**: append a dated amendment at the end of `docs/notes/development/omnigent/deployment-plan.md`, after its last section ("ZeroTier MSS lifecycle recovery, 2026-09-15"), leaving "Janette identity amendment, 2026-09-13" unchanged as the record of that change, with one sentence cross-referencing this OpenSpec change, and update the current-state paragraphs of `modules/clan/services/omnigent/README.md` that describe Janette's `extraHomeModules` binding and the obligations' author case.
  The `deploy-omnigent-magnetite` change's artifacts are not edited.
- **Rationale**: Q4's accepted answer; the README describes the contract as it is, the plan records history.

## Risks / Trade-offs

- [Risk] Cameron's workers and the five human profiles change rendered configuration; a reviewer comparing closures could mistake it for drift → Mitigation: tasks record before and after `nix eval` projections of git and jj `user` for every home, and the intended differences are listed in the proposal.
- [Risk] Commits recorded while `user.name` was empty stay unpushable after deployment until re-authored (A84) → Mitigation: D5 re-authors them in the one checkout known to carry them.
- [Risk] A repository-local or environment author setting overrides the delivered one (A85), including `GIT_AUTHOR_NAME` defaults set by `modules/apps/release/release.sh` → Mitigation: stated in the interface trust boundary; the release path is intended and unchanged.
- [Risk] Forcing the human default in a worker home would throw in the fixture and fail evaluation on real hosts (no `flake.users."omnigent-cameron"`) → Mitigation: adapters always set `vcs.author`; the capability fixture sets it explicitly; the throw guard surfaces any regression.
- [Risk] The worker option change ripples into fixtures (R1) → Mitigation: under D3′ only the `owner` type changes and the credential policy shape does not, so `credentials-test.py` and its JSON fixtures are untouched; the Linux, Darwin and capability fixtures already use profile keys.
- [Risk] The README's controller gates compare protected projections against fixed baselines that permit only Janette's identity fields (R4); those gates are outside this repository → Mitigation: the amendment names the new author fields so a controller can widen its allowance; this change does not claim those gates pass.
- [Risk] The pull request is rebase-merged, so each of its three commits lands on `main` separately, but CI builds only the head commit → Mitigation: each commit leaves `main` correct and regulated on its own and is built locally against its named checks before it is sealed; step 2 keeps Janette's `extraHomeModules` binding and its `identityBinding` obligation, which still pass, and step 3 removes both in the same commit that adds `authorBinding` and its mutants.
- [Risk] Other open changes (`bind-mesh-writes-to-their-host`, `verify-ntfy-before-sending-tokens`) also replace the full designation table in `world-assumptions` → Mitigation: whichever archives later rebases its table on the synced one; assumption numbers A84 and A85 do not collide with A71 to A83.
- [Trade-off] stibnite's worker author is not observed directly by any check → accepted, matching `credentialWiring` (Q3); unlike `credentialWiring`, `authorBinding` is absent from Darwin hosts' cases rather than reported as met.
- [Trade-off] `modules/clan/services/omnigent/README.md` says stibnite's obligations are outside CI, while `nixbot.toml` (2026-10-13) evaluates `aarch64-darwin` checks best-effort → recorded as an open question, not changed here.

## Migration Plan

One pull request of three commits on the bookmark `unify-vcs-author-identity`, rebase-merged so each commit lands on `main` separately, each independently evaluable.

1. D1′ and D2′: rule, home-manager module, `jujutsu.nix` default removal, six human profiles.
   Worker homes do not import `vcs-author` yet; their jj `name = ""` disappears (unset), which jj treats the same.
2. D3′: owner type, adapters setting `vcs.author`, worker import of `vcs-author`, owner-derived `workerCredentials`, removal of `user.email` from the credential module, replacement of `ownerMeta`, fixture update.
   Janette's `extraHomeModules` binding and the obligation's `identityBoundHomeModules` and `identityBindingDiscriminates` stay, and still pass, because the binding and the adapter define equal strings.
3. D4′: removal of `janetteAuthor` and its `extraHomeModules` from the inventory and of `janetteMeta`, `janetteAuthor`, `identityBinding` and its two cases from the obligations, in the same commit that adds `authorBound`, `authorBinding` and the inventory fixtures; README paragraphs on Janette's binding and the obligations; dated amendment.

Each step is independently shippable: after step 1 human homes carry a complete author and workers are unchanged apart from the dropped empty jj name; after step 2 every worker carries its owner's author and Janette's binding obligation still regulates her workers; after step 3 every Linux worker is regulated.

Deployment order after landing: magnetite, pyrite and stibnite first (workers and Cameron's human home), then the hosts carrying the other affected human profiles (argentum, blackphos, rosegold, galena, scheelite) at the operator's discretion; a host's behavior changes only when it deploys.
Then D5 in the omnigent-cameron checkout on magnetite.
Rollback is reverting the stack and redeploying; the repository-local workaround can be reapplied with the same two commands as before.

## Gate 1 modality verdicts

This table is the pre-apply spec-and-feature alignment record required by `openspec-bdd-bridge`.
No row routes to a Gherkin scenario, so this change lays out no `.feature` file.
The repository has no BDD runner (no pytest-bdd, cucumber or behave dependency, and no `.feature` file in the tree), so a laid-out scenario would be an unbound surface nothing executes.
Every observable here is either a property of an evaluated configuration, witnessed by `nix eval`, the machine checks and the `omnigent-worker-inventory` mutants, or a property of a deployed account, witnessed by post-activation smoke run by the operator.
A `world`-stratum requirement is witnessed by its own violation condition; an `interface`-stratum requirement is witnessed at the machine boundary.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| A commit names the person it is recorded for | `commit-author-identity` | behavioral | build gate (`nix eval`) and smoke (deployment) | tasks 1.5, 2.2, 3.1, 4.1, 5.1 |
| No commit is recorded with an empty author name | `commit-author-identity` | behavioral | build gate (type error, fleet obligation, mutants) and smoke (deployment) | tasks 1.6, 3.1, 3.2, 4.3, 5.1 |
| A person's commits carry their author address, not their sign-in address | `commit-author-identity` | behavioral | build gate (`nix eval`) and smoke (deployment) | tasks 2.3, 2.4, 5.2 |
| A person's signed commits verify against their author address | `commit-author-identity` | behavioral | build gate (`nix eval` of `allowed_signers`, expected-drift mutant) | tasks 1.5, 3.2; no task signs and verifies a commit on a deployed account |
| An Omnigent worker runs only for a person with a profile | `commit-author-identity` | behavioral | build gate (`nix eval`, owner-refusal case) | tasks 2.1, 3.2 |
| A change to a profile reaches every account of that person at its host's next deploy | `commit-author-identity` | behavioral | build gate (single derivation evaluated for every home) | tasks 1.2, 1.5, 2.2; no task edits a profile and redeploys |
| The author interface's trust boundary is evaluated and delivered configuration | `commit-author-identity-interface` | interface | capability text and documentation | specs text, task 3.3 |
| One rule derives an author from a profile | `commit-author-identity-interface` | interface | build gate (`nix eval`, `vcsAuthorFixture`) | tasks 1.2, 3.2 |
| Every home sets git and jj author from one non-empty pair | `commit-author-identity-interface` | interface | build gate (`nix eval`, type error, home checks) | tasks 1.3, 1.5, 1.6, 1.7 |
| The signer principal is the author address | `commit-author-identity-interface` | interface | build gate (`nix eval`, `authorBoundExpectedDrift`) | tasks 1.5, 3.2 |
| A worker's owner is a profile key | `commit-author-identity-interface` | interface | build gate (`nix eval`, `ownerOutsideProfiles`, existing JSON round trip) | tasks 2.1, 3.2 |
| A worker's author is its owner's profile, set by the host | `commit-author-identity-interface` | interface | build gate (`nix eval`, capability fixture with throwing `users`) | tasks 2.2, 2.3, 2.6 |
| The sign-in address is unchanged | `commit-author-identity-interface` | interface | build gate (`nix eval`) and smoke (deployment) | tasks 2.4, 5.2 |
| Every Linux worker's author is regulated against its owner's profile | `commit-author-identity-interface` | interface | build gate (fleet obligation in machine checks, control and five mutants, check key lists) | tasks 3.1, 3.2, 3.5, 5.3 |
| A84 — jj refuses to push a commit recorded while user.name was empty, until the commit is re-authored | `world-assumptions` | world | violation-condition witness | its own scenario |
| A85 — Repository and environment author settings take precedence over account settings | `world-assumptions` | world | violation-condition witness | its own scenario |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | designation table and its lint | the table itself |

No row carries an `est-property`, `est-contract`, or `est-symbolic` modality, so this change carries no executable-specification-testing obligation and lays out no EST artifact.

## Open Questions

- Follow-up, out of scope: `modules/clan/services/omnigent/README.md` "Stibnite obligations are outside CI" conflicts with `nixbot.toml`'s description of `aarch64-darwin` best-effort evaluation; correct it in a separate change.
- Follow-up, out of scope: `credentialWiring` in `modules/lib/omnigent-fleet-obligations.nix` is `isDarwin || …`, so it is reported as met on Darwin without checking anything; it could be merged in only for Linux hosts as `authorBinding` is, in a separate change.
- Do pyrite and stibnite checkouts under the worker accounts carry the same repository-local workaround?
  Only the magnetite omnigent-cameron checkout was observed; task 4.4 checks the others.
