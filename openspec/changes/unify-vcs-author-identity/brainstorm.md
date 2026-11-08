<!--
Raw capture of superpowers:brainstorming output.

This file captures the output of the brainstorming skill verbatim; it does not impose any structure.
The skill's natural output is usually a decision-log format (background → decision chain Q1-Qn → design trade-offs),
but the organization may vary depending on the conversation.

design.md is extracted from this file and reorganized into a structured design document.

Do not copy this file's content into design.md — design.md is an independent, reorganized artifact;
the two are complementary but do not overlap.
-->

# Brainstorm: unify-vcs-author-identity

Session date: 2026-11-08.
The interactive session ran in the orchestrating agent's conversation with the user; this file is its decision log, written from that session's record.
Recorded user statements are limited to the questions' accepted answers and the acceptance wording quoted under "Acceptance mode".

## Background

Version-control author identity, meaning git's and jj's `user.name` and `user.email`, is restated in several places in this repository, and each restatement covers only what the commit that introduced it needed.
The observed effect is that jj `user.name` is empty for the raquel, tara, christophersmith and ubuntu human profiles, for janettesmith's human profile (whose jj email is set), for every Linux Omnigent worker home owned by cameron, and for the stibnite worker, and that git `user.name` is unset on Cameron's workers.
jj refuses to push a commit with an empty author name: `Won't push commit … since it has no author and/or committer set`, verified on 2026-11-08 with jj 0.47.1 in a throwaway repository.
A repository-local workaround, `jj config set --repo user.name "Cameron Smith"` and `git config --local user.name "Cameron Smith"`, masks the failure in the omnigent-cameron checkout of this repository only, and has to be removed once a declarative fix is deployed.

## History

Commit 759262860 (2026-09-13, the Janette worker assignment) added `janetteAuthor` and typed `meta.gitEmail`, defaulting to `meta.email`, in `modules/home/users/lib.nix`.
That commit's "Janette identity amendment" in `docs/notes/development/omnigent/deployment-plan.md` explicitly left Cameron's workers unchanged.
Commit c48790428 (worker credentials via Clan vars) added `modules/home/ai/omnigent/credentials.nix`, which sets an email-only identity so the signing principal stays consistent.
`git log -S'user.name'` over the omnigent, clan and system modules finds only c48790428 and 4c9570435, so there is no history of a name being set and later removed.

## Findings

F1: `modules/home/users/crs58/default.nix` sets jj `user` from `meta.fullname` and `meta.email`, not `meta.gitEmail`.

F2: `modules/home/ai/omnigent/credentials.nix` sets only `user.email = policy.expected.gitEmail` for git and jj, and only when a signing key is delivered.
The credential policy's `expected` carries `gitEmail`, `signingPublicKey` and `omnigentEmail`, and no name.

F3: `modules/clan/inventory/services/omnigent.nix` passes `janettesmith.extraHomeModules` that set git and jj `user = { name = fullname; email = gitEmail; }` (`janetteAuthor`), and has no equivalent for Cameron.
The inventory passes `config.flake.users.crs58.meta` by hand to `workerCredentials`.

F4: `modules/home/users/janettesmith/default.nix` sets git name and email but only `programs.jujutsu.settings.user.email`, so her human jj name is unset.

F5: `git log -S'user.name'` over the omnigent, clan and system modules finds only c48790428 and 4c9570435; no set-then-removed history exists.

F6: identity is restated in four places: the crs58 profile (using `meta.email`), the janettesmith profile (git name and email, jj email only), the inventory's `janetteAuthor` through `extraHomeModules` for Janette only, and `credentials.nix`'s `user.email` from `expected.gitEmail`.

F7: a worker's `owner = "cameron"` is a free-text label.
Its link to crs58 exists only because the inventory passes `config.flake.users.crs58.meta` by hand to `workerCredentials`; nothing ties `owner` to identity data.

F8: the fleet obligations hard-code `janetteAuthor`, so they are per person and could not catch Cameron's missing name.

F9: `modules/home/users/aliases.nix` declares `cameron = "crs58"`, and `aliases-fold.nix` builds `flake.users.cameron` from crs58's data with only the username changed.
Evaluated configurations for the alias pair are identical apart from username, home and the per-platform signing-key source.
The repository's agent context states that older machines use `crs58` and newer ones `cameron` as an alias of the same account, and that the authoritative user list is the directory set under `modules/home/users/`.

F10: the root cause of the human-profile gaps is `modules/home/development/jujutsu.nix`, which sets jj `user.name` and `user.email` to `lib.mkDefault ""`; only crs58 and its alias cameron override both.

F11: every worker `owner` value in the repository, including the check fixtures (cameron, janettesmith, raquel), is already a `flake.users` key.
The fleet checks require worker key to equal owner, and the worker host name is `"${machine}-${owner}"`.
`modules/lib/omnigent-fleet-obligations.nix` hard-codes a cameron-to-crs58 lookup (`ownerMeta`) and hard-codes `janetteAuthor`.

F12: `gitEmail == email` for every profile except janettesmith, who already uses `gitEmail`, so switching every consumer to `gitEmail` changes no rendered value today.

F13: on workers, `user.email` in `credentials.nix` exists only for signing; `credentials.py` never reads it, and the `credentialWiring` obligation passes as long as the author email equals `expected.gitEmail`.

F14: the repository's agent context makes evaluation, not building, the binding CI cost.
Check attribute names must derive only from static data (literals, the system string, clan inventory metadata, flake-level `lib`), never from evaluated NixOS, nix-darwin or home-manager configurations, and a check whose derivation is identical on every system belongs to exactly one system.
The `preferences-nix-checks-architecture` skill's `references/evaluation-cost.md` and `references/check-vacuity.md` govern any new or restructured check.

Worker options live in `modules/system/omnigent-worker-options.nix`, with a parallel clan interface for the omnigent service; fixtures and `credentials-test.py` consume the schema.
`worker.nix` asserts the deprecated `git.sign-on-push` key; that deprecation is a separate change.

## Option chain

### O1: copy Janette's pattern for Cameron

Add `cameron.extraHomeModules` with a `cameronAuthor` built from `flake.users.crs58.meta` on magnetite, pyrite and stibnite, plus a matching obligation.
It was first recommended because it follows the existing convention.
It was superseded because it adds a fifth restatement of identity per person instead of removing the cause recorded in F6 to F8.

### O2: add a name to the credential policy

Add `expected.gitName` to the credential policy and set `user.name` for every worker in `credentials.nix`.
It covers every worker, but it changes a shared contract that tests and fixtures depend on, leaves the human profiles of F10 unfixed, and keeps identity inside the signing-credential policy.

Neither O1 nor O2 was adopted.

### Initial design, D1 to D4

D1: one derivation rule, `flake.lib.vcsAuthor meta = { name = meta.fullname; email = meta.gitEmail; }`.

D2: one home-manager module applying that rule to git and jj `user` for human and worker homes, removing the hand-written blocks in crs58 and janettesmith.

D3: a new worker option `profile`, constrained to `flake.users` keys, keeping `owner` as the Omnigent label; the adapter derives the author and `credentials.expected` from `flake.users.${profile}.meta`.

D4: one obligation over all workers: git user equals jj user equals the author for the profile, the signer principal equals the author email, and the name is non-empty.

### Revision trigger

The user asked whether the context was primed enough and noted that crs58 and cameron are aliases.
Three parallel read-only investigations then evaluated 28 home-manager configurations and the stibnite worker.
They found F9 (cameron is a declared alias already present in `flake.users`), F11 (every owner value already is a profile key, so no new field is needed), F10 (the `mkDefault ""` root cause affects seven human profiles, so the scope widens), F12 and F13.

### Revised design, D1′ to D4′

D1′: one derivation rule, `flake.lib.vcsAuthor meta = { name = meta.fullname; email = meta.gitEmail; }`.

D2′: one home-manager module and option (named `vcs.author.profile` in the session's wording, typed as a `flake.users` key, defaulting to `home.username` resolved through aliases) that sets git and jj `user` from D1′.
It removes `mkDefault ""` in `jujutsu.nix` and the hand-written user blocks in every human profile file.
The `allowed_signers` principal derives from the same author email, while per-profile key sourcing (sops, literal, store file) stays per profile.
The module never touches `signing.*`.

D3′: no new worker field.
`owner` is restricted to `flake.users` keys in the worker options and the clan interface.
The NixOS and Darwin adapters set the worker home's author from `worker.owner`, `workerCredentials` derives meta from the owner, and the `janetteAuthor` `extraHomeModules`, the hand-passed meta, `ownerMeta` and the `user.email` lines in `credentials.nix` are removed.

D4′: one obligation for every worker: git user equals jj user equals `vcsAuthor` of the owner's profile, the name is non-empty, and the signer principal equals the author email, with a negative fixture that rejects a wrong author.
Linux worker configurations are checked directly; Darwin (stibnite) is covered through the shared module, the same limit `credentialWiring` has.
Following F14, it is one check on a single system, with attribute names from inventory or other static data.

## Questions and accepted answers

Q1: restrict `owner` to `flake.users` keys instead of adding a `profile` field?
Accepted: yes, because every current value qualifies and the checks already treat worker key as owner.

Q2: fix all human profiles in this change?
Accepted: yes, because they share the `mkDefault ""` root cause.

Q3: accept that D4′ checks Linux workers directly and covers stibnite only through the shared module?
Accepted: yes, matching `credentialWiring` today, and, following F14, implemented as one check with names from inventory or static data.

Q4: how to document the change?
Accepted: as a new dated amendment, leaving the Janette identity amendment text as the record of that change.

Acceptance mode: the questions were presented with recommendations, and the user replied "if your context is optimally primed, you can proceed"; silence on each number keeps its recommendation.

## Invariants to preserve

Workers receive only two non-secret strings, a name and a git email; no human modules, `contentPrivate`, sops material or age keys reach them.
`expected.omnigentEmail` stays `meta.email`, because Janette's SSO address deliberately differs from her git address.
Signing is unchanged: worker jj `behavior = mkForce "own"`, `drop` when no key is delivered, and no sign-on-push on workers.
`extraHomeModules` stays out of the clan interface.
Per-person token shapes (the cameronraysmith and work tokens, `defaultOwner`) are unchanged, because they are access policy, not identity.

## Intended value changes

The jj author becomes populated for the raquel, tara, christophersmith, ubuntu and janettesmith human profiles.
Cameron's workers gain a git and jj name.
A worker without a delivered signing key still receives its author email.

## Risks recorded in session

R1: a worker option schema change ripples to the fixtures and `credentials-test.py`.
R4: the omnigent service README mentions controller gates with fixed baselines that permit only Janette's identity fields; those gates are not in this repository.
R5: the ubuntu profile's meta duplicates Cameron's identity; out of scope.
R6: the repository-local workaround must be removed after deployment and is recorded as a task.
Out of scope: the `git.sign-on-push` deprecation in `jujutsu.nix` and `worker.nix`, a separate change.

## Post-session refinements during artifact authoring

Two points were raised while writing the planning artifacts and answered by the orchestrating agent on 2026-11-08.

Refinement A, the author option's shape.
`modules/checks/omnigent-workers.nix` hands worker homes a `flake` argument whose `users` attribute throws `"worker imported a whole-user alias"`, which enforces the invariant that worker home-manager never reads `flake.users`.
An option typed as a `flake.users` key and resolved inside home-manager would trip that guard in worker homes.
Accepted resolution: the home-manager option is the resolved pair `vcs.author = { name; email; }`, each a non-empty string.
Its default, used only by human homes, is `flake.lib.vcsAuthor flake.users.${config.home.username}.meta`.
The NixOS and Darwin adapters set it at system level from `flake.users.${worker.owner}.meta`, so workers still receive only two strings and the guard stays.
The owner restriction stays in the system-level worker options and the clan interface.
This supersedes the session's `vcs.author.profile` wording.

Refinement B, where the D4′ obligation lives.
The fleet obligations already run inside the per-machine checks whose names come from the clan inventory, and the Janette `identityBinding` and `identityBindingDiscriminates` cases live in `modules/lib/omnigent-fleet-obligations.nix`.
Accepted resolution: replace those two cases with one `authorBinding` case plus a discriminating negative case, adding no new check attribute, with the negative case evaluated once rather than once per machine where the structure allows.

Refinement C, landing independence.
The first draft relied on the three steps landing in one queue batch, because step 2 removed Janette's binding obligation before step 3 added `authorBinding`.
The orchestrating agent rejected that on 2026-11-08: a batch can split on failure, so each step must leave `main` correct and regulated on its own.
Accepted resolution: step 2 keeps Janette's `extraHomeModules` binding and its `identityBinding` obligation, which still pass because they define the same strings the adapter sets, and step 3 removes both in the same commit that adds `authorBinding` and its mutants.
The amendment goes in `deployment-plan.md` only, with one sentence cross-referencing this change, and the `deploy-omnigent-magnetite` artifacts are not edited.
