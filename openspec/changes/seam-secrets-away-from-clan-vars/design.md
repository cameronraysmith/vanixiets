## Context

### Current state, re-verified on main

This design is written against `main` at `9055ae0f1333` (type-the-fleet-host-registry merged), read on 2026-11-27 from `git archive main -- modules`. Every line number below is at that revision.

- 56 files under `modules/` name `clan.core.vars` (the proposal counted 55; the 56th is `checks/host-key-obligations.nix`, added by stop-reading-other-hosts-configs). 34 of them declare a generator.
- Cross-feature reads, as the proposal says: `nixos/nixbot.nix:269` reads `niks3-api-token` (declared `nixos/niks3.nix:79`); `nixos/matrix.nix:345` reads `kanidm-oauth2-synapse` (`nixos/kanidm.nix:106`). Also, not in the proposal: `clan/services/omnigent/flake-module.nix:55` reads `kanidm-oauth2-omnigent` (`kanidm.nix:123`); `machines/nixos/magnetite/default.nix:801` reads `kanidm-oauth2-perses` (`kanidm.nix:157`); `clan/services/openclaw/flake-module.nix:362` reads cinnabar's `tuwunel-registration-token` (`machines/nixos/cinnabar/matrix.nix:109`); `machines/nixos/cinnabar/matrix.nix:160` reads hermes-agent's `matrix-password-hermes`; `clan/services/otel-collector/flake-module.nix:1718,1730` read magnetite's `greptimedb-users` (`magnetite/default.nix:751`); `ntfy-alerter` (`nixos/ntfy-alerter.nix:23`) is read by `nixos/fleet-deployer.nix:150`, `machines/nixos/cinnabar/fleet-alert.nix:15` and `magnetite/default.nix:1054`.
- Generator names taken as settings: `clan/services/hermes-agent/flake-module.nix:482,498`, `clan/services/openclaw/flake-module.nix:187`, `nixos/omnigent.nix:80` (`cookieSecretGenerator`), `nixos/omnigraph-backup.nix:227,261`, `nixos/postgresql-backup.nix:329,363`, `nixos/r2-usage.nix:373`. `darwin/omnigent-host.nix:28` computes one.
- The `options ? clan.core.vars` guard is in five files, not one: `nixos/omnigent-host.nix:463`, `nixos/omnigraph-backup.nix:226`, `nixos/postgresql-backup.nix:328`, `nixos/r2-usage.nix:372`, `darwin/omnigent-host.nix:519`. Each module is evaluated somewhere without clan-core: `checks/omnigent-workers.nix:213,347` builds `nixosSystem` and `darwinSystem` fixtures from the omnigent host modules, and `vm-tests/postgresql-backup-restore.nix:59` imports `postgresql-backup`. Every NixOS and darwin fleet host is a clan machine, so the guard exists for those fixtures.
- Homes. `home/development/vcs-signing.nix:22-27` reads `osConfig.clan.core.settings.machine.name` and `osConfig.clan.core.vars.generators.<person>-commit-signing-key`, and `:44` names `clan.core.vars` in a `defaultText`. It runs in NixOS and darwin homes. Its generator is declared on both classes by `system/commit-signing-key.nix:49-55` (imported into `nixos.base` and `darwin.base`, `:61-62`), so stibnite, argentum and rosegold read it too. blackphos is the only legacy signing machine (`lib/commit-signing.nix:11`).
- `home/ai/omnigent/credentials.nix` is not a home module. It defines `flake.lib.mkOmnigentWorkerCredentials` (`:91-309`), which `nixos/omnigent-host.nix:32-40` and `darwin/omnigent-host.nix:60-68` call with `osConfig = config`, the host's own configuration. Its reads of `osConfig.clan.core.vars.generators` (`:102,129,177`), `osConfig.sops.placeholder."vars/${rel_dir}/${name}"` (`:127`) and `osConfig.clan.core.settings.directory` (`:114`) are host-side reads. `clan/services/omnigent/README.md:295` prohibits `hm-sops-bridge` enrolment for omnigent workers. The proposal's statement that these secrets reach homes through the bridge is corrected here (D5).
- `nixos/hm-sops-bridge.nix` exists only as `flake.modules.nixos.hm-sops-bridge` (`:43`). It is active only for users named in `hm-sops-bridge.users` (`:83`), and only sets `sops.age.keyFile` in their homes (`:133-135`). No darwin host imports it.
- Obligations that read a host's generator tree: `lib/commit-signing.nix:196`, `lib/shared-vars-recipients.nix:43`, `lib/host-keys.nix:39`, plus three the proposal did not list: `lib/omnigent-fleet-obligations.nix:183`, `lib/fleet-deployer.nix:306` (`localSecretsOf`, which iterates every generator) and `nixos/r2-usage.nix:237`. `shared-vars-recipients`' `missing` (`:23-35`) and `localSecretsOf` iterate every generator on the host, including generators declared by clan's own services.
- Checks and runtime tests that read a host's generators: the five vm-tests the proposal names (`vm-tests/fleet-ingress.nix:94,2188`, `devloop-ingest.nix:85,1732`, `greptimedb-oom-order.nix:51,135`, `greptimedb-pipeline.nix:78,174`, `perses-greptimedb.nix:64,217`) and `checks/greptimedb-envelope.nix:25,512-513,648`, all running `greptimedb-users`' `finalScript`; and, not in the proposal, `checks/nix-builders-wiring.nix:60,150,313`, `checks/ntfy-provisioning.nix:35-36`, `checks/omnigraph-retired-roots.nix:89`, `checks/host-key-obligations.nix:29,54` (fixtures) and `vm-tests/clan-test-vars-fixture.nix:83`, which lays out clan's on-disk vars for test nodes.
- Generators declared by clan-core's own services that the fleet reads: `openssh` (`clanServices/sshd`, world assumption A321), read by `lib/host-keys.nix:39-40`; `zerotier-network-<instance>` (`clanServices/zerotier/default.nix:222`), read by `machines/nixos/cinnabar/zt-dns.nix:99,121`. `darwin/ssh-ca-trust.nix:18-29` declares a first-party copy of clan sshd's shared `openssh-ca` generator, because clan's sshd service has no darwin module (`:2-4`).
- An existing seam to copy: `nixos/fleet-deployer.nix:148-153` (`notifyTokenFile`).
- The option manuals: no module sets `documentation.nixos.includeAllModules` (searched 2026-11-27), nix-darwin's manual evaluates its own modules only, and home-manager's evaluates its own `modules/modules.nix` (A362). Declaring a first-party option therefore moves no derivation.

### Requirements and the world they rest on

| Req | Statement (behavioral, `secret-consumption-seam`) | Rests on | Breaks if it fails | Discharged by |
|---|---|---|---|---|
| R1 | A feature names the secrets it owns and uses without naming the secret backend | — | a backend swap edits every feature | D1, D2, D6, D9 |
| R2 | Moving a feature behind the seam leaves every delivered secret's location, recipe, custody and restart behaviour unchanged, and every host, home, check and runtime test unchanged except declared differences | A361, A362, A363 | a host loses a secret or restarts a unit at deploy | D3, D10, D11 |
| R3 | A home configuration receives the secrets it reads from its host without reading the host's secret backend | A362 | a home breaks when the backend changes | D5 |
| R4 | Replacing the secret backend changes only the seam and the named judges that pin the backend | A360, A364 | a later swap is a fleet-wide rewrite | D7, D8, D9 |
| R5 | A runtime test that runs a secret's recipe runs the recipe production uses | — | a test passes on a recipe production never runs | D8 |
| R6 | Each delivery step is shippable alone and leaves no secret half moved | A363 | a revert leaves a generator written twice | D10 |

### Stakeholders

The operator, who reviews thirteen pull requests and deploys nothing (no host changes). The features' authors, who will declare secrets through one option. The later den or backend-replacement change, which inherits a two-file swap. The predecessor compose-hosts-from-cohesive-aspects, which rewrites the files most of these steps touch.

## Goals / Non-Goals

**Goals:**
- One option, `vanixiets.secrets.<name>`, on the NixOS and nix-darwin classes, through which every first-party module declares and reads secrets.
- One secrets module, `modules/system/secrets.nix`, the only first-party module that names `clan.core.vars` outside the named judges (D8). With `modules/lib/vars.nix` (the committed-store half) it is the seam.
- Homes read a host-provided view, never `osConfig.clan`.
- Every NixOS, darwin and home toplevel and every runtime test keeps its drvPath at every step; the checks that change are named in each step's allow-list.
- A structural check that fails when a module outside the seam names the backend, arriving as a shrinking allow-list in the first step and as the full rule in the last.

**Non-Goals:**
- Replacing clan, renaming any generator or file, moving anything under `vars/`, or changing who can decrypt any secret.
- `clan.core.settings.*` reads (`machine.name`, `directory`, `domain`): host identity and location, not secrets. `vcs-signing.nix:22`'s machine-name read stays; a later den change owns host identity in homes.
- Reading committed public values, which `flake.lib.vars` already owns.
- Deploying anything: no host's configuration changes.

## Decisions

### D1: `vanixiets.secrets.<name>` is the only declaration and read interface

- **Choice**: `options.vanixiets.secrets = attrsOf (submodule secretModule)` on `flake.modules.nixos.secrets` and `flake.modules.darwin.secrets`, both defined in `modules/system/secrets.nix`. `<name>` is the generator name. A feature that owns a secret writes `vanixiets.secrets.<name> = { … }`; any module that needs it reads `config.vanixiets.secrets.<name>.files.<f>.path`.
- **Rationale**: one option keeps clan in one file. A typed submodule makes a misspelt field an evaluation error at the feature. Boundary: vendored-versus-first-party. The option is first-party; clan's generator interface is used through it, not patched.
- **Alternatives considered**: (a) a path option per feature like `notifyTokenFile`; every owner still writes `clan.core.vars`. (b) a `flake.lib` function from name to path; it cannot carry custody and must read `config.clan` wherever it is called.

### D2: the option carries the fields the fleet uses, with no pass-through

- **Choice**: writable fields, each `nullOr` with default `null` (lists default `[ ]`), so that only defined fields are written:
  - generator: `share`, `dependencies`, `validation`, `runtimeInputs`, `script`, `prompts.<p>.{description,type,persist}`;
  - file: `files.<f>.{secret,deploy,owner,group,mode,neededFor,restartUnits}`;
  - `provided : bool` (D4).

  Read-only fields: `files.<f>.{path,value,exists,placeholder}`, each `null` when no backend is evaluated (D3). The field list is the set used by the 34 declaring files on 2026-11-27 (`description` 228, `type` 183, `files` 99, `script` 86, `runtimeInputs` 53, `owner` 40, `group` 38, `mode` 28, `restartUnits` 25, `secret` 21, `prompts` 20, `persist` 17, `neededFor` 14, `share` 8, `dependencies` 4, `validation` 2, `deploy` 1 line hits), against clan's generator submodule (`modules/clan/export-modules/generic-generator.nix:79-325` in clan-core). `finalScript` is not exposed (D8).
- **Rationale**: answers proposal question 1. A pass-through attribute would put clan's vocabulary back into feature files. A field the fleet starts to need is a one-line seam edit, and the translation judge (D11) fails until it is added on both sides.
- **Alternatives considered**: a field-for-field mirror of clan's schema. It changes whenever clan's schema does and exposes fields no feature sets.

### D3: translation writes only defined fields, and only when clan is present

- **Choice**: `config = lib.optionalAttrs (options ? clan.core.vars) { clan.core.vars.generators = mapAttrs (_: toClan) (filterAttrs (_: s: !s.provided) cfg); }`, where `toClan` drops every `null` field and every empty list. Read-only fields are set from `config.clan.core.vars.generators.<name>.files.<f>` (`path`, `value`, `exists`) and `config.sops.placeholder."vars/${rel_dir}/${f}"` (`placeholder`, A361) when clan is present, and `null` otherwise. The five `options ? clan.core.vars` guards leave their feature files and exist once here.
- **Rationale**: clan's own defaults stay authoritative for every field a feature did not set, so the generator clan evaluates receives the same definitions as before (A363). Writing only defined fields is what keeps `mode`, `owner` and `neededFor` defaults identical. The guard answers proposal question 4: it is still needed, because clan-free fixtures import secret-owning modules, and it is now needed in one place. Boundary: source-versus-delivered. The translation decides what clan generates and installs; the drvPath diff shows the evaluated result is unchanged, not that clan installs the same file at runtime.
- **Alternatives considered**: the option sets its own defaults and always writes them. Equal values only for as long as the two sets of defaults agree, and every unset field would become a definition.

### D4: generators clan's own services declare are read as provided entries

- **Choice**: a module that reads a generator declared by a clan-core service declares `vanixiets.secrets.<name>.provided = true`. The secrets module translates nothing for it and fills its read-only fields from clan. Two readers use it: `lib/host-keys.nix` (`openssh`) and cinnabar's `zt-dns` (`zerotier-network-zerotier`). A provided entry whose generator clan does not declare fails when a read-only field is read, naming the entry.
- **Rationale**: the option's names are fixed by definitions and never computed from clan's tree, so declaring the generators from the option and reading paths back cannot recurse. Listing the clan-provided names statically at their readers keeps that property. Boundary: vendored-versus-first-party (A364).
- **Alternatives considered**: mirror every clan generator into the option automatically. The option's attribute names would then depend on clan's, which depend on the option's: infinite recursion.

### D5: homes read a view that hm-sops-bridge sets, on both classes

- **Choice**:
  - A home-manager module `flake.modules.homeManager.secrets`, also in `modules/system/secrets.nix`, declares a read-only-in-spirit `vanixiets.secrets` option in every home: an attribute set of `{ files.<f>.{path,placeholder} }`, default `{ }`.
  - `nixos/hm-sops-bridge.nix` gains, beside its age-key propagation, `home-manager.sharedModules = [ homeManager.secrets ]` and `home-manager.users.<u>.vanixiets.secrets = view u` for every home-manager user on the host, where `view u` holds the host's entries with at least one file whose `owner` is `u`. The view part does not depend on `hm-sops-bridge.users`.
  - The bridge file gains `flake.modules.darwin.hm-sops-bridge` with the view part only (darwin homes take their age key from `~/.config/sops/age/keys.txt`, `hm-sops-bridge.nix:11-13`), imported into `darwin.base`. The NixOS module is imported into `nixos.base` so every NixOS home gets the view.
  - A standalone home imports `homeManager.secrets` and sees `{ }`, as it sees `osConfig == null` today.
  - The view's first reader is `vcs-signing.nix` (D10 step 10). The omnigent credential adapter is host-side (Context) and reads `osConfig.vanixiets.secrets`, not the view.
- **Rationale**: homes receive secrets through the bridge, beside the age key it already propagates. The bridge is NixOS-only and per-user today, and stibnite, argentum and rosegold homes read their signing key from the host, so the bridge gains a darwin export carrying only the view, and the view is set for every home user rather than only those in `hm-sops-bridge.users`. Filtering by owner gives a home only what it can open. Boundary: source-versus-delivered; the view carries paths, never contents.
- **Alternatives considered**: (a) homes read `osConfig.vanixiets.secrets`. Smaller, but homes keep reading the host's configuration. (b) the view set by the secrets module, leaving the bridge as it is. Equivalent in effect, but it splits home secret delivery between two modules, the bridge for the age key and the secrets module for paths.

### D6: clan inventory services declare and read through the seam

- **Choice**: the `perInstance` NixOS and darwin modules of `clan/services/{hermes-agent,nix-builders,omnigent,openclaw,otel-collector,tincr}/flake-module.nix` write `vanixiets.secrets` like any feature. The settings `openrouterApiKeyGenerator` and `matrixBotPasswordGenerator` keep their names; their descriptions say they name a secret.
- **Rationale**: answers proposal question 2. These modules are first-party code inside clan's inventory framework. Their secrets are fleet secrets and would survive a backend swap; their inventory wiring would not. Renaming the settings would touch the inventory instances under `clan/inventory/` for no gain, since the value is the same string.
- **Alternatives considered**: exempt `modules/clan/**` from the rule. It keeps six files as clan readers and leaves cross-feature reads such as `otel-collector`'s of `greptimedb-users` naming a generator.

### D7: obligations read the option for one name and the seam's backend function for the whole tree

- **Choice**:
  - Per-name readers read `hostConfig.vanixiets.secrets.<name>`: `lib/commit-signing.nix:196`, `lib/host-keys.nix:39`, `lib/omnigent-fleet-obligations.nix:183`, `nixos/r2-usage.nix:237`.
  - Whole-tree readers take clan's full generator tree from `flake.lib.secretsBackend.generatorsOf hostConfig`, defined in `modules/system/secrets.nix`: `lib/shared-vars-recipients.nix:43` (`missing`) and `lib/fleet-deployer.nix:306` (`localSecretsOf`). Their logic stays in their files.
- **Rationale**: answers proposal question 7. Both whole-tree obligations judge clan's own custody (which shared files a host is a recipient of; what `clan machines update` decrypts on the deployer), including generators clan's services declare (sshd's shared `openssh-ca`), so they need the backend's whole tree; D4 cannot list it without recursion. The function lives in the seam file, so no obligation file names clan. Boundary: vendored-versus-first-party.
- **Alternatives considered**: move both obligations into the secrets module. It grows the seam with fleet policy that is not clan-specific.

### D8: the judges that run a generator's recipe stay clan readers

- **Choice**: the confinement rule's exempt set at the last step is: `modules/system/secrets.nix`; `vm-tests/{fleet-ingress,devloop-ingest,greptimedb-oom-order,greptimedb-pipeline,perses-greptimedb}.nix` and `checks/greptimedb-envelope.nix`, which run `greptimedb-users`' `finalScript`; and `vm-tests/clan-test-vars-fixture.nix`, which lays out clan's on-disk format for test nodes. Every other check reader moves to the option with its feature's step: `checks/ntfy-provisioning.nix` (step 4), `checks/omnigraph-retired-roots.nix` (step 8), `checks/omnigent-workers.nix` (step 9), `checks/host-key-obligations.nix` fixtures and `checks/nix-builders-wiring.nix:313` (step 11), `checks/nix-builders-wiring.nix:60,150` (step 12).
- **Rationale**: answers proposal question 3. These judges pin clan's own generator so the test cannot drift from production, as stop-reading-other-hosts-configs' independent judges do. Exposing `finalScript` through the option would put clan's execution model into the interface. A backend swap must revisit them anyway, because they run its recipe.
- **Alternatives considered**: expose `finalScript` read-only. The seam would then promise a clan-shaped script to every reader.

### D9: one confinement check, a shrinking allow-list from the first step

- **Choice**: `checks.x86_64-linux.secrets-seam-confinement`, built with `flake.lib.mkStructuralCheck`. `actual` is the sorted list of `.nix` files under `modules/` (skipping path components starting with `_`, as import-tree does) that have a non-comment line containing `clan.core.vars`, or containing `vars/shared/` or `vars/per-machine/` outside `modules/lib/vars.nix`; `expected` is a literal list. Step 1 sets it to the full list at that revision; each step deletes the files it clears; step 13 leaves the D8 set and `lib/vars.nix`'s documented exemptions. Declared `class = "medium"; measured = false;`.
- **Rationale**: answers proposal question 5. A ratchet catches a new direct reader in any intervening change. Because `mkStructuralCheck` embeds only the two JSON lists, its drvPath changes exactly when a step clears a file, which every step declares. The `vars/` clause is how `flake.lib.vars` sits behind the seam: `flake.lib.vars` and `flake.lib.hostKeys` keep their names and their readers, `lib/vars.nix` is the seam's committed-store half, no other module spells the committed layout, and `hostKeys`' obligation reads the option (D4). Boundary: source-only. It reads text and cannot see an attribute path built from strings (`clan.core.${"vars"}`).
- **Alternatives considered**: (a) no check until step 13. The long tail would carry no guard. (b) re-export `flake.lib.vars` and `flake.lib.hostKeys` under a `flake.lib.secrets` namespace. It edits about fifteen readers for no change in behaviour.

### D10: thirteen pull requests, one closed set of secrets each

- **Choice**: each step is one commit in one pull request, accepted on one full `just drv-diff <parent> <tip> openspec/changes/seam-secrets-away-from-clan-vars/drv-delta/<step>.txt` (about 16 minutes; the implementer returns the command, the operator or main session runs it). A step moves every definition and every reader of the secrets it covers.

  | Step | Allow-list | Moves |
  |---|---|---|
  | 1 | `01-seam.txt` | the secrets module, the home view, the two judge checks; no consumer |
  | 2 | `02-build-cache-and-ci.txt` | `nixos/{niks3,nixbot}.nix`, `effects/{vanixiets,ironstar}/secrets.nix` |
  | 3 | `03-identity.txt` | `nixos/{kanidm,sso-gateway}.nix`; readers `nixos/matrix.nix:345`, `clan/services/omnigent/flake-module.nix:55`, magnetite's `kanidm-oauth2-perses` read |
  | 4 | `04-notifications.txt` | `nixos/{ntfy-alerter,fleet-deployer}.nix`, cinnabar's `ntfy` and `fleet-alert` features, magnetite's `ntfy-alerter` read, `checks/ntfy-provisioning.nix` |
  | 5 | `05-matrix.txt` | `nixos/matrix.nix`, cinnabar's `matrix` feature, `clan/services/{openclaw,hermes-agent}` |
  | 6 | `06-forge.txt` | `nixos/{gitea,gitea-mq,renovate}.nix` |
  | 7 | `07-telemetry-store.txt` | magnetite's `greptimedb-users`, `greptimedb-r2`, `perses-encryption-key` and their readers; `clan/services/otel-collector`; `darwin/otel-collector-agent.nix` |
  | 8 | `08-omnigraph-and-backups.txt` | magnetite's `omnigraph-*`; `nixos/{omnigraph-backup,postgresql-backup,r2-usage}.nix`; `checks/omnigraph-retired-roots.nix` |
  | 9 | `09-omnigent.txt` | `nixos/{omnigent,omnigent-host}.nix`, `darwin/omnigent-host.nix`, `home/ai/omnigent/credentials.nix`, `lib/omnigent-fleet-obligations.nix`, `checks/omnigent-workers.nix` fixtures |
  | 10 | `10-commit-signing.txt` | `system/commit-signing-key.nix`, `home/development/vcs-signing.nix` (first view reader), `lib/commit-signing.nix` |
  | 11 | `11-host-access-and-boot.txt` | `system/{stibnite-access,initrd-networking}.nix`, pyrite's `disko.nix`, `darwin/ssh-ca-trust.nix`, cinnabar's `caddy-root-ca`, `caddy-root-check`, `radicle`, `zt-dns`; `lib/host-keys.nix`; `checks/{host-key-obligations,nix-builders-wiring}.nix` (`:313`) |
  | 12 | `12-mesh-and-builders.txt` | `clan/services/{tincr,nix-builders}`; `checks/nix-builders-wiring.nix:60,150` |
  | 13 | `13-close.txt` | `lib/{shared-vars-recipients,fleet-deployer}.nix` through `secretsBackend`; the full confinement rule; documents |

- **Why each is independently shippable**: a step changes only option plumbing for a closed set: no secret it moves is read or written by a file it leaves untouched (the cross-reads listed in Context are grouped accordingly), and the secrets it does not move stay on direct clan definitions, which the seam leaves alone. So any prefix of the steps is a consistent tree, and reverting the last merged step restores its parent. Each step's drv-diff proves every toplevel and runtime test unchanged on its own.
- **Rationale**: the operator settled one feature per step. A "feature" here is a closed set under cross-reads; step 11 groups seven small owners that share no secrets with any other step and are each one or two generators, to keep the count of 16-minute diffs at thirteen. The steps stay as listed, about three and a half hours of diffs in total, because each smaller step is a smaller bisection unit and a smaller review.
- **Alternatives considered**: (a) one pull request. It is one diff, but a 45-file move fails or passes as a whole and cannot be bisected. (b) fold steps 6 and 12 into neighbours to make eleven. It saves two diffs, about half an hour, at the cost of two larger unrelated steps.

### D11: a translation judge pins the field mapping

- **Choice**: `checks.x86_64-linux.secrets-seam-translation`: `lib.evalModules` over the NixOS secrets module and a stub declaring `options.clan.core.vars.generators = attrsOf (submodule { freeformType = attrsOf anything; })`, with fixtures: every writable field set once; a provided entry; an entry with only `files.<f>.secret`; and the absent-backend case. It asserts the stub receives exactly the defined fields and that no `null` or empty list is written. Declared `class = "medium"; measured = false;`.
- **Rationale**: D3's "only defined fields" is the property every later step's neutrality depends on, and the drvPath diff of one step only covers the fields that step happens to use.
- **Alternatives considered**: rely on each step's drv-diff. A field dropped by the translation would show up only in the step that first uses it, as an unexplained difference.

### D12: what each allow-list predicts

- Step 1: `checks.x86_64-linux.secrets-seam-confinement added`, `checks.x86_64-linux.secrets-seam-translation added`, `checks.x86_64-linux.fleet-alert changed` (its size-rule clause renders every `testSizes.checks` entry, and two are added).
- Steps 2-13: `checks.x86_64-linux.secrets-seam-confinement changed` (the step deletes entries from `expected` and the files from `actual`).
- `may-change`, each resolved to `changed` or removed before the step merges: checks whose source file the step edits and whose evaluated values could move: step 4 `ntfy-provisioning`; step 8 `omnigraph-retired-roots`; step 9 `omnigent-worker-{capabilities,inventory,linux,darwin}`, `omnigent-credential-policy` and `omnigent-credentials-unit` on both systems; step 11 `host-key-obligations` and `nix-builders-wiring`; step 12 `nix-builders-wiring`. The drafted files are in `drv-delta/`.
- Step 13, if any document under `packages/docs/` is edited: the twelve `package-vanixiets-docs*` checks and `apps-build` on both systems, and `agent-skills-index` and `deploy-docs-rehearsal` on `x86_64-linux` (as `type-the-fleet-host-registry/drv-delta.txt:20-47` lists them). If only `modules/README.md` is edited, none.
- No step adds a module file that a test imports by store path (`${./x.nix}`): the six such tests import `agents-md.nix`, `home/users/lib.nix`, `fleet-topology.nix`, `inventory-members.nix`, `md-format.nix` and `mesh.nix`, none edited here.

## Risks / Trade-offs

- [Risk] A generator defined in more than one place (`clan/services/otel-collector/flake-module.nix:1569,1690` both define `langfuse`; nix-builders' `clientFiles` and `generators`) moves partly, so list fields merge in a new order (A363) → Mitigation: a step moves every definition of a generator together; the drv-diff shows any reordering as a toplevel change, which blocks the step.
- [Risk] `mkDefault`/`mkForce` priorities inside a declaration are resolved by the option before clan sees them, changing which definition wins where clan or a vendored module also defines the generator → Mitigation: a search for `mkDefault|mkForce|mkOverride` inside each moved declaration in the step's first task; any hit is moved together with every competing definition, or the step's design note explains it.
- [Risk] A clan-free fixture now reads a `null` path where it used to hit a missing attribute caught by `or` (`r2-usage.nix:237` uses `… or null`) → Mitigation: readers that used `or` test `!= null` on the read-only field; the fixture checks of the step are listed `may-change` and resolved.
- [Risk] The view filters by owner, and a home that reads a secret it does not own gets nothing → Mitigation: today's only home reader, `vcs-signing.nix`, reads a file owned by the home's user (`commit-signing-key.nix:31`); a home reader added later states its owner.
- [Risk] Importing `nixos.hm-sops-bridge` into `nixos.base` and the darwin twin into `darwin.base` touches every host → Mitigation: the view module sets only a home option (A362), and step 1's drv-diff must show every toplevel unchanged.
- [Risk] compose-hosts-from-cohesive-aspects moves magnetite's and cinnabar's generators to new files, and register-fleet-obligations and declare-host-user-relations-once rework the obligation modules and `hm-sops-bridge.users` → Mitigation: the sections listed under Migration Plan are re-read after each lands, and the step tables' file names updated before the step starts.
- [Risk] An archive-time conflict on `world-assumptions`' grounded-vocabulary requirement, which several active changes modify in full → Mitigation: the delta copies the corpus requirement as of 2026-11-27 and only appends rows; rows other changes added since are merged by hand at archive.
- [Trade-off] Thirteen 16-minute diffs, about three and a half hours of evaluation, against one unbisectable sweep. Accepted (D10).
- [Trade-off] Two read paths into clan remain in the seam file: the option's read-only fields and `secretsBackend.generatorsOf` (D7). Accepted, because both are in one file.

## Migration Plan

1. Land after compose-hosts-from-cohesive-aspects; step 1's parent is its tip. Before step 1, and again before each step that touches the files below, re-read:
   - `machines/nixos/magnetite/default.nix:536-1058` (the generator region), which that change moves into `<svc>-server` aspects beside `nixos/{greptimedb,perses,fleet-alert,omnigraph}.nix`: steps 3, 4, 7, 8;
   - cinnabar's feature files (`machines/nixos/cinnabar/{caddy-root-ca,caddy-root-check,fleet-alert,matrix,ntfy,radicle,zt-dns}.nix`), which it re-keys under their own `flake.modules.nixos.<feature>` keys: steps 4, 5, 11;
   - `clan/services/otel-collector/flake-module.nix`, which it splits into `agent.nix`, `ingress.nix`, `service.nix`: step 7;
   - its module-key spelling and `flake.lib.exportAs` (its open question 1), which fix the secrets module's `key`: step 1;
   - `nixos.base`'s and `darwin.base`'s named sub-aspects and the `darwin-workstation` aspect, where steps 1 and 13 import the secrets and bridge modules;
   - the runtime tests it edits (`devloop-ingest`, `fleet-ingress`, `greptimedb-oom-order`), which D8 exempts;
   - register-fleet-obligations' registry of obligation modules (`lib/{commit-signing,shared-vars-recipients,host-keys}.nix`, `lib/omnigent-fleet-obligations.nix`): steps 9, 10, 11, 13;
   - declare-host-user-relations-once's generated `hm-sops-bridge.users`, its rename of `system/stibnite-access.nix` and its `accountOf` in `lib/commit-signing.nix`: steps 1, 10, 11.
2. Deliver steps 1 to 13 in order (D10), each as one commit in one pull request, rebased onto the previous step's merge, accepted on its own drv-diff. Steps 2 to 12 may be reordered among themselves; step 1 is first and step 13 last.
3. No host deploys: every toplevel is unchanged, so a host deployed later for unrelated reasons picks up nothing new. If a step's diff shows a toplevel change, the step does not merge.
4. Rollback: revert the step's pull request. No state is migrated and nothing under `vars/` or `sops/` changes.

## Pre-apply alignment

One row per requirement in this change's three delta specs. No row routes to a Gherkin scenario: the repository has no BDD runner and no `.feature` file, so scenarios are realized as Nix checks, evaluations, source searches and the drvPath diff. No row routes to an executable-specification modality: the translation judge is an example-based build gate over fixtures. Where a scenario has no task that observes it, the row says so.

| Requirement | Capability | Stratum | Modality | Witness |
|---|---|---|---|---|
| A feature names its secrets without naming the secret backend | `secret-consumption-seam` | behavioral | build gate (`secrets-seam-confinement`) and its mutant | tasks 2.4, the confinement task of each of groups 3-13, 14.2, 14.3 |
| Moving a feature behind the seam changes no delivered secret | `secret-consumption-seam` | behavioral | build gate (`just drv-diff` per step; `nix eval` projections against 1.2) | the drv-diff task of each of groups 2-14, and the second task of groups 3-13; the scenario "A recipe is changed while moving" by the 3.4 mutant |
| A home configuration receives its secrets without reading the host's secret backend | `secret-consumption-seam` | behavioral | build gate (`nix eval` of `vcs.signing.keyFile` and the view) and source search | tasks 2.2, 11.2, 11.4; the standalone scenario by 2.2's and 11.2's `homeConfigurations` evaluations |
| Replacing the secret backend changes only the seam | `secret-consumption-seam` | behavioral | build gate (`secrets-seam-confinement` with the final list) | tasks 14.2, 15.3; no task replaces the backend, so the scenario "The backend is replaced" has no witness beyond the rule |
| A runtime test that runs a secret's recipe runs production's | `secret-consumption-seam` | behavioral | build gate (vmTests driver drvPaths in step 7) and the final list | tasks 8.5, 14.2 |
| Each delivery step is shippable alone | `secret-consumption-seam` | behavioral | content search (closed set) and build gate (drv-diff per step) | the first task of each of groups 3-13; no task reverts a step, so the scenario "A step is reverted" has no witness |
| vanixiets.secrets is declared on both classes | `secret-consumption-seam-interface` | interface | build gate (`nix eval`) | tasks 2.1, 9.2, 10.4 |
| The secrets module writes only defined fields, and only when clan is present | `secret-consumption-seam-interface` | interface | build gate (`secrets-seam-translation` fixtures and mutant) | task 2.3 |
| Read-only fields come from the backend | `secret-consumption-seam-interface` | interface | build gate (translation fixtures; `nix eval` of moved paths) | tasks 2.3, and the second task of groups 3-13 |
| A generator clan's own service declares is read as a provided entry | `secret-consumption-seam-interface` | interface | build gate (`nix eval`, translation fixture, host-key mutant) | tasks 2.3, 12.4, 12.6 |
| Homes see a view of the secrets they own | `secret-consumption-seam-interface` | interface | build gate (`nix eval` of the view on a NixOS, a darwin and a standalone home) | tasks 2.2, 11.2 |
| Obligations read the option or the backend function | `secret-consumption-seam-interface` | interface | build gate (obligation checks; `failures` against 1.2) | tasks 9.2, 10.3, 11.3, 12.6, 14.1 |
| No module outside the seam names the backend | `secret-consumption-seam-interface` | interface | build gate (`secrets-seam-confinement`) and mutants | tasks 2.4, 14.2, 14.3 |
| Every step's derivations are unchanged except its allow-list | `secret-consumption-seam-interface` | interface | build gate (`just drv-diff`) | the drv-diff task of each of groups 2-14; 15.1 |
| Trust boundary of the seam interface | `secret-consumption-seam-interface` | interface | capability text | specs text |
| A360-A364 | `world-assumptions` | world | monitoring (violation scenarios) | A360 by the operator at each change's close-out; A361 by 1.1's re-read and 10.2's credential assertions; A362 by 2.5's drv-diff; A363 by every step's drv-diff; A364 by 1.1's re-read and 12.4, 12.6 |
| Grounded vocabulary for behavioral requirements | `world-assumptions` | world | capability text | specs text |

## Resolved Questions

Seven questions were raised during design. Each is resolved as follows and folded into the decision it names.

1. **Darwin homes and the bridge.** A darwin export of `hm-sops-bridge` carries only the read view, and the view is set for every home user (D5). Reason: stibnite, argentum and rosegold homes read their commit signing key from the host, and the NixOS bridge is per-user; keeping the view in the bridge keeps home secret delivery in one module.
2. **The whole-tree backend function.** `flake.lib.secretsBackend.generatorsOf` is accepted as a second reader of clan beside the option, in the same seam file (D7). Reason: `sharedVarsObligations` and the deployer's local secrets judge clan's own custody, including generators clan's services declare, so they need the backend's whole tree; both readers stay in one file.
3. **Clan inventory services.** They declare and read through the seam like any feature, and the settings `openrouterApiKeyGenerator` and `matrixBotPasswordGenerator` keep their names (D6). Reason: their secrets are fleet secrets that survive a backend swap, and renaming the settings would edit inventory instances for no change in value.
4. **Judges that run the recipe.** The six `finalScript` readers and `vm-tests/clan-test-vars-fixture.nix` stay named clan readers in the confinement rule's final list (D8). Reason: they pin clan's own generator so a test cannot drift from production, and exposing `finalScript` would put clan's execution model into the interface.
5. **Thirteen pull requests.** The thirteen steps are delivered as listed (D10). Reason: each step is a closed set under cross-reads with its own drv-diff, so each merge is a small, bisectable unit.
6. **`flake.lib.vars` and `flake.lib.hostKeys`.** Both keep their names and their readers; `lib/vars.nix` is the seam's committed-store half, and the confinement rule's second clause forbids spelling the committed vars layout anywhere else (D4, D9). Reason: a re-export under a new namespace edits about fifteen readers for no change in behaviour.
7. **vcs-signing's machine-name read.** Out of scope (Non-Goals). Reason: `clan.core.settings.machine.name` is host identity, not a secret, and host identity in homes belongs to a later den change.
