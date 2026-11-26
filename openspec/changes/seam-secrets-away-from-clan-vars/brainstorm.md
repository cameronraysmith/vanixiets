<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The operator opened this change on 2026-11-26 from a static audit of the repository's readiness for a den-style composition layer, with these points fixed: one typed option per secret is the only module that writes or reads clan's vars generators; homes receive secrets through the existing home-manager sops bridge instead of reading the host's clan configuration; features move one per delivery step; generator names and their custody attributes stay as they are.
The forks below were settled from the repository as read on 2026-11-26. Forks whose answer depends on contracts that other changes introduce first are left open and repeated in proposal.md.
Nothing was built or evaluated for this file. Line numbers were read from the working copy on 2026-11-26.
-->

# Brainstorm: give secret consumption one seam, away from clan vars

## Background

Every secret a feature needs is declared as a clan vars generator (`clan.core.vars.generators.<name>`), and every consumer reads the delivered file's path from that same attribute tree.
55 files under `modules/` mention `clan.core.vars`; 32 of them declare generators.
Nothing separates "this feature needs a token" from "clan generates and deploys that token".

Clan-core is in maintenance mode (operator statement, 2026-11-26; the repository has no record of it).
If a later change puts a den composition layer in front of clan, or replaces clan's vars, every one of those files has to change at once.
Confining clan to two files makes that later change a swap of two files: the committed-vars accessor introduced by stop-reading-other-hosts-configs, and the secrets module this change introduces.

### How features reach into each other's generators today

- `modules/nixos/nixbot.nix:269` reads the `niks3-api-token` generator that `modules/nixos/niks3.nix:79` declares.
- `modules/nixos/matrix.nix:345` reads the `kanidm-oauth2-synapse` generator that `modules/nixos/kanidm.nix:106` declares.
- `modules/clan/services/hermes-agent/flake-module.nix:28-39` and `modules/clan/services/openclaw/flake-module.nix:97` take a generator name as a string setting, then index `clan.core.vars.generators.${name}` with it (`hermes-agent/flake-module.nix:482,498`, `openclaw/flake-module.nix:187`).
- `modules/darwin/omnigent-host.nix:28` indexes generators by a computed name, and `:519` guards on `options ? clan.core.vars`.

Each reader therefore knows the other feature's generator name, its file name, and that clan is the backend.

### How homes read the host's clan configuration

- `modules/home/development/vcs-signing.nix:22-27` reads `osConfig.clan.core.settings.machine.name` and `osConfig.clan.core.vars.generators.${…}`, falling back to `null` when `osConfig == null` (a standalone home).
- `modules/home/ai/omnigent/credentials.nix:102,129,177` reads `osConfig.clan.core.vars.generators`, the generator's `share`, and the sops placeholder `osConfig.sops.placeholder."vars/${rel_dir}/${name}"`. That last read depends on how clan's sops backend names the secrets it installs, a second coupling beside the generator tree.
- `modules/nixos/hm-sops-bridge.nix:123-135` already crosses the host/home boundary, but only for one thing: it installs each bridged user's age key and points `home-manager.users.<u>.sops.age.keyFile` at it.

### Who reads a generator from outside the host that owns it

- Five VM tests read magnetite's `greptimedb-users` generator and run its `finalScript`: `vm-tests/fleet-ingress.nix:93,2185`, `devloop-ingest.nix:84,1729`, `greptimedb-oom-order.nix:50,132`, `greptimedb-pipeline.nix:77,171`, `perses-greptimedb.nix:62,213`.
- `checks/greptimedb-envelope.nix:25,513` reads the same generator and the `otel-cert` key file.
- `modules/lib/commit-signing.nix:191` (`commitSigningObligations.failures`) and `modules/lib/shared-vars-recipients.nix:43` (`sharedVarsObligations.failures`) read `hostConfig.clan.core.vars.generators` of the host passed to them: `checks/machines.nix:61` passes each host's evaluated configuration, and the shared-vars `assertionsModule` (`:55`) passes the host's own `config` and reads `config.clan.core.settings.machine.name`.
- `modules/lib/host-keys.nix`, which stop-reading-other-hosts-configs introduces, builds `flake.lib.hostKeys` from committed clan vars through the accessor and defines `hostKeyObligations.failures name hostConfig`, which compares the host's own `openssh` generator value with `hostKeys.${name}`; that comparison reads the host's clan generator tree.

stop-reading-other-hosts-configs migrates the committed-path reads beside these, `commit-signing.nix:166` (`readDir` of `vars/shared/<gen>/key/machines`) and `shared-vars-recipients.nix:45` (`pathExists` of a recipient entry), to the accessor. It leaves `:191`, `:43`, `:55` and the `openssh` generator read in `host-keys.nix` in place, so they are this change's to move behind the seam.

The VM tests use the real host's generator so the test cannot drift from production. That is why generator names, scripts, owner, mode, `restartUnits`, `share` and `validation` must not change: a changed script changes what the tests run, and a changed name or `share` moves files under `vars/`.

### An existing seam to copy

`modules/nixos/fleet-deployer.nix:148-151` declares `notifyTokenFile` as an option whose default reads `ntfy-alerter`'s path. Consumers read the option and never see the generator. This change generalises that shape.

## Decision chain

Q1. What is the seam?
A typed option `vanixiets.secrets.<name>` on the NixOS and nix-darwin classes. A feature that owns a secret declares it there, and a feature that needs it reads the delivered path from there. One module, the secrets module, translates each declaration into `clan.core.vars.generators.<name>` and reads clan's paths back into the option.
`<name>` is the generator name, so nothing under `vars/` moves.
Rejected: a per-feature path option like `notifyTokenFile` for every secret. It hides the generator from consumers, but every owning feature still writes `clan.core.vars` itself, so clan stays spread across 32 files.
Rejected: a `flake.lib` function that returns a path from a name. A function cannot carry owner, mode or `restartUnits`, and it would have to read `config.clan` wherever it is called.

Q2. What does the option carry?
Everything a generator declaration fixes today and every consumer reads: files with `secret`, `owner`, `group`, `mode`, `neededFor`; `share`; `restartUnits`; `validation`; the dependencies on other secrets; the generation script and its prompts; and, read-only, each file's delivered path and, for public files, its value and existence.
Whether the option models clan's schema field for field or only what this fleet uses is open (OQ1).

Q3. How do homes receive secrets?
Through `hm-sops-bridge`. Next to the age key it already propagates, it gains a home-side read-only view, `vanixiets.secrets.<name>`, that a home module reads instead of `osConfig.clan`. A standalone home sees the view as absent, which keeps `vcs-signing.nix`'s `osConfig == null` behaviour.
The sops placeholder that `omnigent/credentials.nix:129` reads becomes part of that view, so homes stop computing clan's `vars/<rel_dir>/<name>` naming.
Rejected: homes keep reading `osConfig` but through the option, `osConfig.vanixiets.secrets`. It is smaller, but it keeps homes reading the host's evaluated configuration, which den's home class does not assume.

Q4. How is the move delivered?
One feature per delivery step, each with the before/after drvPath diff from establish-refactor-oracle showing no change to any NixOS, nix-darwin or home toplevel or any check. The secrets module lands first with no consumer. A feature's declaration and all its readers move in the same step, so no step leaves a generator half written by the option and half by hand.
The structural rule "no module outside the two seam files mentions `clan.core.vars`" arrives in the last step, when it can pass. Whether an intermediate ratchet (an allow list that only shrinks) runs before that is open (OQ6).
The change lands last in the den-ready-fleet order, after compose-hosts-from-cohesive-aspects: both edit magnetite's and cinnabar's feature files, and moving a generator declaration into the seam is simpler once those files have their final shape. Each step re-runs `just drv-diff` against its parent after rebasing onto that predecessor.

Q5. What must each step preserve?
Generator names, file names, generation scripts and prompts, `owner`, `group`, `mode`, `neededFor`, `restartUnits`, `share`, `validation` and `dependencies`. The oracle checks these indirectly: they all reach the toplevel through clan's activation and sops wiring, and the five VM tests embed `finalScript`. A change to any of them shows up as a drvPath difference.

## Open design questions (blocked on other changes or on the operator)

OQ1. Option schema: a full mirror of clan's generator submodule, or the subset this fleet uses with a pass-through attribute for the rest? A full mirror changes whenever clan's schema changes. A subset needs a pass-through, which leaks clan back into feature files.

OQ2. Clan inventory services (`modules/clan/services/{hermes-agent,nix-builders,omnigent,openclaw,otel-collector,tincr}/flake-module.nix`) are clan modules by construction and would be rewritten if clan were replaced. Should they also go through the seam, or are they on clan's side of it? `hermes-agent` and `openclaw` take generator names as settings, so at least their settings should name a secret rather than a generator.

OQ3. Test and check readers: do the five VM tests and `greptimedb-envelope` read magnetite's `greptimedb-users` through the seam (which then has to expose the generation script), or do they stay as declared clan readers so the test still pins clan's own generator? Either way the drvPath diff covers them, because each embeds `finalScript`; the question is which file the readers name.

OQ4. Generator-tree readers in `lib/` (`commit-signing.nix:191`, `shared-vars-recipients.nix:43,55`, and the `openssh` read in `host-keys.nix`): read `hostConfig.vanixiets.secrets.<name>` (the seam's read-only view) instead of `hostConfig.clan.core.vars.generators`, or move each obligation into the secrets module? The first keeps the obligations where they are; the second grows the seam. Either way none of these files may name `clan.core.vars` once the confinement rule arrives.

OQ5. nix-darwin: `darwin/omnigent-host.nix:519` writes generators only when `options ? clan.core.vars`. Is that guard still needed once the option exists on every nix-darwin host, and do darwin hosts without clan vars exist?

OQ6. Enforcement before the last step: an allow list of files still permitted to mention `clan.core.vars`, which each step shrinks, or no check until the rule can pass outright?

OQ7. Order of features. Pairs where one feature reads another's generator (niks3 → nixbot, kanidm → matrix) show the seam's value first and touch the fewest files. `greptimedb-users`, which six test and check readers depend on, should move only after OQ3 is settled.

## Trade-offs weighed

- One option for all secrets against a path option per feature: one place for clan, at the cost of a schema that must cover every generator shape the fleet uses.
- Home view through the bridge against `osConfig` reads: homes no longer read the host's evaluated configuration, at the cost of growing the bridge from one key to a view of every secret.
- One feature per step against one sweep: about 45 files move behind an oracle that proves each step unchanged, at the cost of a long tail during which both styles exist.
- Keeping generator names against renaming them to describe the secret: nothing under `vars/` moves and the VM tests keep running the production script, at the cost of names that describe clan generators rather than the secrets they produce.
