## Context

The fleet's hosts are each one deferred module, imported once by `modules/clan/machines.nix`. Two modules break that independence by reading another host's evaluated configuration:
- `modules/system/ssh-known-hosts.nix:30-80` reads six NixOS hosts' `clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value`. All ten NixOS and darwin configurations import the module.
- `modules/machines/darwin/stibnite/default.nix:173` reads magnetite's `stibnite-agent-session` public value.

Both read a committed file whose location is the only thing the other host's configuration supplies. clan-core's `in_repo` public store defines `value = readFile (settings.directory + "/vars/${rel_dir}/${name}/value")` (`nixosModules/clanCore/vars/public/in_repo.nix:14-21`, clan-core 78d5de23). The sshd service's `openssh` generator is per-machine, with a public `ssh.id_ed25519.pub` produced by `ssh-keygen -C ""` (`clanServices/sshd/default.nix:41-51`).

The 2026-11-26 measurements on stibnite (`logs/cross-host-eval-cost-{b,b2,base-host,c,d}-20261126-*.stats.json`):

| quantity | CPU s | thunks | bytes |
|---|---|---|---|
| stibnite toplevel drvPath | 10.97 | 24,376,302 | 3,148,532,208 |
| host-only baseline | 0.39 | 681,965 | 138,745,408 |
| `programs.ssh.knownHosts` forced | 1.37 | 4,402,939 | 562,100,704 |
| magnetite's session key alone | 0.57 | 1,182,490 | 176,070,096 |

Forcing `knownHosts` costs 0.98 s, 3.72M thunks and 423 MB over the host-only baseline. With the session key, that is an upper bound of 9 to 12 % of the toplevel, found by subtraction.

Separately, about fifteen sites spell out clan's vars layout by hand (brainstorm.md, "The vars layout is known in many places"). `modules/lib/fleet-deployer.nix:305-310` already has a `varPath` that picks `vars/shared/…` or `vars/per-machine/<m>/…` from the generator's `share`.

Five vm-tests take `services.greptimedb.databases` from magnetite's configuration (`greptimedb-pipeline.nix:75-76`, `fleet-ingress.nix:91-92`, `devloop-ingest.nix:82-83`, `greptimedb-oom-order.nix:113`, `perses-greptimedb.nix:60-61`). magnetite sets that value from `flake.lib.otelCollectorSchema.databases` (`magnetite/default.nix:857`).

Constraints that bind this change:
- Independent judges and literal oracles stay unchanged, so that none of them comes to share the code it judges: `checks/sops-correspondence.nix` (its own `case` patterns over the committed tree), the literal fixture paths of `checks/fleet-deployer-obligations.nix`, and `checks/machines.nix`, including every perSystem assert at `:99-123`, on which `checks/flake-shape.nix:3-5` relies. Site-neutral feature modules keep their option interfaces; only their hand-written vars paths move to the accessor (D5). Of the judges, this change reads beside only `sops-correspondence.nix` and `fleet-deployer-obligations.nix`, and leaves both as they are (D7).
- The persons' and accounts' keys and the `machines/<class>/<h>` host keys are not renamed.
- `just eval-identity` is not a cross-commit oracle (`justfile:435-450`). Acceptance uses the before/after drvPath diff from the refactor-oracle change.

## Goals / Non-Goals

**Goals:**
- No NixOS or darwin configuration reads another host's evaluated configuration.
- Every `known_hosts` entry and stibnite's authorized session key keep their exact bytes, and every system and home drvPath is unchanged. Among checks, only the added `host-key-obligations`, `fleet-alert` (which renders every check's size entry) and `eval-users-lib` (which embeds `home/users/lib.nix`'s source) differ, apart from the checks that embed the whole flake source, which the refactor oracle's base allow-list covers on every run.
- A NixOS host whose generated host key no longer matches the committed file fails its own build.
- One accessor, `flake.lib.vars`, holds the vars layout. Every ad-hoc reader in scope uses it and keeps its result value, its read function and its trimming.
- The five vm-tests read magnetite's telemetry databases from flake data and still assert that magnetite declares them.
- The stibnite toplevel saving is measured A/B and recorded.

**Non-Goals:**
- Removing `_module.args.flake` (nine setters) or the poisoned `flake` in `checks/omnigent-workers.nix:16-21`.
- Typing or restructuring the host registry. Names still come from `flake.lib.hosts`.
- A seam for secret consumption (`clan.core.vars` access by features and homes).
- Lifting rendered configuration out of tests: electrum's and pyrite's collector settings, magnetite's tables, pipelines, OOM scores and postgresql package, the omnigraph module's rendered settings and seeds, and the `greptimedb-users` generator.
- Pinning or checking darwin host keys against the running hosts.
- Any change to the committed `vars/` or `sops/` trees.

## Decisions

### D1: Host keys come from the committed files through `flake.lib.hostKeys`
- **Choice**: a new `modules/lib/host-keys.nix` defines `flake.lib.hostKeys = genAttrs nixosKeyHosts (h: vars.public { machine = h; generator = "openssh"; file = "ssh.id_ed25519.pub"; }) // darwinHostKeys`. `nixosKeyHosts` is the literal list `[ cinnabar electrum galena scheelite magnetite pyrite ]`, the six names `ssh-known-hosts.nix` lists today. `ssh-known-hosts.nix` reads `config.flake.lib.hostKeys.<h>` for all ten entries and drops `lib.optionalAttrs (flake ? nixosConfigurations)` and its `{ flake, ... }` module argument.
- **Rationale**: the file is what clan reads, so the bytes are identical, including the trailing `" \n"`. The list stays literal so this change adds no new host to `known_hosts` and does not depend on the host registry. This change lands before type-the-fleet-host-registry; that change later replaces the literal list with the NixOS hosts derived from each host's class, without changing its six members.
- **Secrets seam**: `host-keys.nix` reads committed clan vars, through `flake.lib.vars`, and compares them with the host's own `clan.core.vars` generator. seam-secrets-away-from-clan-vars, which lands later, places both reads behind its seam; this change does not anticipate that seam's shape.
- **Alternatives considered**: deriving the list from `readDir vars/per-machine` would silently add any host that gains an `openssh` directory, such as `gcp-vm` if it ever did, and would change which entries exist. Pinning the NixOS keys as literals would duplicate a value clan rewrites on regeneration.
- **Boundary**: vendored versus first-party. The file layout and the untrimmed read are clan's (A320, A321); `hostKeys` is first-party data built on them.

### D2: An own-host obligation, not a fleet-wide check
- **Choice**: `modules/lib/host-keys.nix` also defines `flake.lib.hostKeyObligations.failures name hostConfig`. It returns one failure when `hostKeys ? name`, the host declares an `openssh` generator, and that generator's `ssh.id_ed25519.pub` value is not equal to `hostKeys.${name}`, and it returns none otherwise. An `assertionsModule` imported into `flake.modules.nixos.base` turns failures into assertions, which is the `lib/shared-vars-recipients.nix:49-64` pattern. A judge check `checks.x86_64-linux.host-key-obligations` runs it over literal fixtures: an accepted host; a host whose value differs by one character; a host whose value is trimmed (it must fail, because the trailing space and newline are part of the contract); a host absent from `hostKeys` (no failure); and a host without an `openssh` generator (no failure).
- **Rationale**: the comparison reads only the host's own configuration, which that host's build forces anyway. A rotated or moved key then fails the one host it belongs to, before deploy. Assertions do not enter the toplevel derivation, so drvPaths stay the same [INFERENCE: confirmed by the oracle diff]. `withFleetObligations` (`checks/machines.nix:54-98`) is reworked by later changes (type-the-fleet-host-registry, register-fleet-obligations), so this design does not touch it.
- **Alternatives considered**: a check evaluating all six hosts and comparing their values with `hostKeys` would rebuild the cross-host read inside `checks`. That is legal for a check but costs every check evaluation what the change saves the hosts, and the own-host assertion already catches the same drift.
- **Boundary**: source versus delivered. The obligation compares the source (committed file) with the evaluated generator, not with the key a running host presents.

### D3: stibnite reads magnetite's committed session key
- **Choice**: `services.stibnite-session-host.keys = [ (config.flake.lib.vars.public { machine = "magnetite"; generator = "stibnite-agent-session"; file = "key.pub"; }) ]`. The surrounding comment (lines 166-170) is reworded to say the key is read from the committed file and that `checks.nix-builders-wiring` holds it to magnetite's generator.
- **Rationale**: `checks/nix-builders-wiring.nix:311-317` already compares magnetite's evaluated value, with the newline removed, against stibnite's authorized keys. That is the cross-host correspondence, held in a check where reading two hosts is legitimate.
- **Alternatives considered**: an obligation on magnetite that the generator stays per-machine and public. It would duplicate what the existing check fails on, because a shared or renamed generator would make magnetite's value differ from the file stibnite reads, or make it absent.
- **Boundary**: none. Both sides are first-party.

### D4: `flake.lib.vars` and its five functions
- **Choice**: `modules/lib/vars.nix`:
  - `relPath { generator, file, machine ? null }` returns `"vars/shared/${generator}/${file}"` when `machine == null`, otherwise `"vars/per-machine/${machine}/${generator}/${file}"`.
  - `path args` returns `../.. + "/${relPath args}"`, a path value at the repository root.
  - `public args` returns `builtins.readFile (path args + "/value")`, untrimmed.
  - `exists ({ secret ? true, … } as args)` returns `builtins.pathExists (path args + (if secret then "/secret" else "/value"))`.
  - `isRecipient args { machine ? null, group ? null, user ? null }` returns `pathExists` of `…/machines/<m>`, `…/groups/<g>` or `…/users/<u>`, exactly one being non-null.

  `fleet-deployer.nix`'s `varPath generator file` becomes `vars.relPath { inherit generator file; machine = if generators.${generator}.share then null else name; }`, which returns the same strings.
- **Rationale**: one place holds clan's layout. The functions are the operations the sites actually perform. `path` exists because a path literal interpolated into a configuration copies one file to `/nix/store/<hash>-value`, where a `"${self}/…"` string refers into the whole flake source. Returning a path value keeps each such site's store paths (A322).
- **Alternatives considered**: a trimmed `public` (rejected: it would change every `known_hosts` line). A `recipients` export for `commit-signing.nix:166` (rejected: `readDir (vars.path {…} + "/machines")` needs no sixth function). Clan's own `clanLib.getPublicValue` (rejected: it needs a `flake` argument and returns the untrimmed value too, so it adds a dependency on clan's library without removing any layout knowledge from the existence and recipient readers).
- **Boundary**: vendored versus first-party. clan writes the layout; the accessor is the first-party reading of it, and A320 is the assumption it rests on.

### D5: Migrating each reader keeps its value, its read function and its trimming

| site | today | after |
|---|---|---|
| `clan/inventory/services/tincr.nix:36` | `readFile "${inputs.self}/…/ed25519_key.pub/value"` | `vars.public { machine = name; generator = "tincr-${mesh.instance}"; file = "ed25519_key.pub"; }` |
| `darwin/fleet-services-trust.nix:8` | path literal `…/caddy-root-ca/root.crt/value` | `vars.path { machine = "cinnabar"; generator = "caddy-root-ca"; file = "root.crt"; } + "/value"` |
| `home/users/crs58/default.nix:94` | `"${<path literal>}"` | `"${vars.path {…} + "/value"}"` |
| `nixos/workstation-ca-trust.nix:10` | path literal | `vars.path {…} + "/value"` |
| `home/users/lib.nix:101-104` | `lib.fileContents (path …/key.pub/value)` | `lib.fileContents (vars.path { generator = …; file = "key.pub"; } + "/value")` |
| `checks/otel-collector-config.nix:96`, `otel-collector-darwin.nix:62` | `lib.trim (readFile "${self}/vars/shared/zerotier-ip-magnetite-zerotier/ip/value")` | `lib.trim (vars.public { generator = "zerotier-ip-magnetite-zerotier"; file = "ip"; })` |
| `lib/fleet-deployer.nix:99-105` | `pathExists` then `lib.trim (readFile …)` | `vars.exists { …; secret = false; }` then `lib.trim (vars.public {…})` |
| `lib/fleet-deployer.nix:305-310` | local `varPath` | `vars.relPath` (D4) |
| `nixos/postgresql-backup.nix:136,146-147`, `nixos/r2-usage.nix:236,250` | `pathExists "${toString hostConfig.clan.core.settings.directory}/vars/per-machine/${name}/…/secret"` | `vars.exists { machine = name; generator = …; file = …; }` |
| `lib/shared-vars-recipients.nix:45` | `pathExists (self + "/vars/shared/${gen}/${file}/machines/${name}")` | `vars.isRecipient { generator = gen; inherit file; } { machine = name; }` |
| `lib/commit-signing.nix:166` | `../../vars/shared + "/${gen}/key/machines"` | `vars.path { generator = gen; file = "key"; } + "/machines"` |
| `darwin/otel-collector-agent.nix:451` | `hashFile "sha256" "${self}/vars/shared/langfuse/secret-key/secret"` | `hashFile "sha256" (vars.path { generator = "langfuse"; file = "secret-key"; } + "/secret")` |

- **Choice**: each row keeps its result value and its read function (`readFile`, `fileContents`, `trim`, `pathExists`, `readDir`, `hashFile`), so its trimming is unchanged. A row may change how it names the file: `tincr.nix:40`, `checks/otel-collector-{config,darwin}.nix`, `darwin/otel-collector-agent.nix:452`, `nixos/postgresql-backup.nix:142-147` and `nixos/r2-usage.nix:250` move from a `"${self}/…"` string to a path through `flake.lib.vars`, with unchanged results (A322).
- **Rationale**: drvPath identity is the acceptance test. These readers consume the file's contents or existence during evaluation, so the form that names it does not reach a store path; the drv-diff run proves every drvPath unchanged.
- **Alternatives considered**: normalising every site to one primitive. That would move drvPaths for no behavioural gain.
- **Boundary**: source versus delivered. `fleet-services-trust`, `workstation-ca-trust` and `crs58` deliver the file itself into a closure; the rest only read it during evaluation.
- The two existence readers previously rooted at the host's own `clan.core.settings.directory`, so they assumed that directory is the repository; `vars.exists` makes that explicit (A322 covers the root).

### D6: Telemetry databases in the vm-tests
- **Choice**: in each of the five vm-tests, `inherit (reference.services.greptimedb) databases` becomes `inherit (self.lib.otelCollectorSchema) databases`. The test adds `assert lib.assertMsg (reference.services.greptimedb.databases == databases) "<test>: magnetite does not declare flake.lib.otelCollectorSchema.databases: magnetite ${builtins.toJSON reference.services.greptimedb.databases}, flake data ${builtins.toJSON databases}"`, so the failure names the mismatch; the message is built only when the assertion fails, so it moves no drvPath. In `fleet-ingress.nix` and `devloop-ingest.nix`, which build two tests each from one function, the assertion sits in that function and both tests carry the file's name. `greptimedb-pipeline.nix:72-74`'s comment is reworded. Its existing TTL assertion (`:90-92`) stays.
- **Rationale**: the fact now has one declaration outside any host, and each test still fails if magnetite stops consuming it. The value passed to the test nodes is the same attrset, so the test derivations do not change.
- **Alternatives considered**: dropping the per-test assertion in favour of the ingress role's name check (`otel-collector/flake-module.nix:1098-1102`). Rejected: that compares names only, not TTLs, and the requirement is that each test keeps its own drift guard. Lifting the omnigraph graphs: rejected in brainstorm Q8, because the readers use rendered output that magnetite is meant to supply.
- **Boundary**: none.

### D7: What stays on the hand-written layout
- `checks/sops-correspondence.nix:213-214` stays. It is the independent judge of the committed tree, and deriving its `case` patterns from the accessor would make it share the code it judges.
- The literal fixture paths in `checks/fleet-deployer-obligations.nix:152,207` stay. D4 keeps `localSecretsOf`'s output strings identical. If that changes during implementation, the fixtures change in the same commit.
- `home/ai/omnigent/credentials.nix:106-114` stays (it uses clan's `rel_dir`), and so does `checks/langfuse-query.nix:114` (it interpolates encrypted files into a test script on purpose).

### D8: Acceptance by the drvPath diff, then an A/B measurement
- **Choice**: after rebasing onto the tip of `establish-refactor-oracle`, run `just drv-diff <parent> <tip> openspec/changes/stop-reading-other-hosts-configs/drv-delta.txt`. The oracle dumps the drvPath of every NixOS and darwin toplevel, every home activation package, every attribute of `checks.{x86_64-linux,aarch64-darwin}` and of `vmTests.{x86_64-linux,aarch64-linux}` at both revisions, applies its own committed base allow-list for checks that embed the whole flake source, and fails on any other difference not in `drv-delta.txt` or any `changed`/`added` entry that did not happen. `drv-delta.txt` declares:
  - `checks.x86_64-linux.host-key-obligations added`, the judge of D2;
  - `checks.x86_64-linux.fleet-alert changed`: its size-rule clause renders every `testSizes.checks` entry and echoes their count, and D2's check adds one entry;
  - `checks.x86_64-linux.eval-users-lib changed`: `modules/home/users/lib.test.nix:26` imports `${./lib.nix}` by store path, so any edit to `lib.nix`, here D5's `signingKey` default reading through `flake.lib.vars.path`, gives it a new source path. No home configuration moves.

  The design first predicted only the first two. The full run from `390f72f0c809` to `bbb7c5ccc978` (909.4 s, `logs/drv-diff-390f72f0c809-bbb7c5ccc978-20261127T033555Z`) failed on one undeclared difference, `eval-users-lib`, explained above and then declared; the re-judgement (`report.20261127T035524Z`) passed with exit 0. The seven tests of the five vm-test files D6 edits were listed `may-change` before the run and were all identical, so they were removed from `drv-delta.txt`; every NixOS, darwin and home toplevel was identical.

  No check or vm-test embeds a toplevel this change moves, because none moves.

  Then on stibnite, with the same nix, run interleaved A/B/A/B `NIX_SHOW_STATS=1` evaluations of `darwinConfigurations.stibnite.config.system.build.toplevel.drvPath`, one fresh process each, and the same for `nixosConfigurations.cinnabar`. Record `cpuTime`, `nrThunks` and total bytes allocated in the change's verify evidence.
- **Rationale**: identity proves the change is a refactor. The measurement proves the motivation and replaces the subtraction-based upper bound with an observed figure.
- **Alternatives considered**: `just eval-identity`. Rejected, because it compares stock nix with iets at one revision.

## Risks / Trade-offs

- [Risk] A string-versus-path change at one site alters a store path, for example `"${self}/…"` becoming a path value that is copied separately. → Mitigation: the sites that change form only read the file during evaluation (D5); the drvPath diff names any site whose store path moved, and that site is reverted to its old form.
- [Risk] `readFile` of a path in the flake source carries a different string context from the evaluated `.value` (A322). → Mitigation: the diff of `known_hosts`-bearing toplevels decides; if it moves, `public` is changed to read through `settings.directory`'s form and re-measured.
- [Risk] A future clan-core changes the `in_repo` layout or starts trimming. → Mitigation: A320's violation scenario; the own-host obligation fails on all six NixOS hosts at once, rather than `known_hosts` drifting silently.
- [Risk] The obligation's fixtures pass while the assertion module is not imported. → Mitigation: a mutant in a throwaway tree forces cinnabar's generated public value to another key, leaving the committed file unchanged, and must see `nixos-cinnabar` fail on the assertion.
- [Risk] A vm-test or fixture node that imports `nixos.base` under the name of a real host, with an `openssh` generator of its own, would fail the obligation. → Mitigation: the obligation keys on `config.clan.core.settings.machine.name`, the same name `sharedVarsObligations` uses. A task lists every `nixos.base` importer outside `nixosConfigurations` whose machine name is in `hostKeys`, and the oracle evaluates every check.
- [Trade-off] `known_hosts` trusts the committed file without checking the running host. → Accepted. Today's source is equally untethered from the running host; it came from the same file.
- [Trade-off] The five vm-tests still evaluate magnetite, for the assertion and for `greptimedb-users`, so D6 saves no evaluation. → Accepted. Its value is a single declaration, not cost.
- [Trade-off] Adding a check attribute adds one key to `checks.x86_64-linux`, which needs a `testSizes` entry (`medium` with `measured = false`, the repository's form for a check no nixbot run has measured), and that entry moves `checks.x86_64-linux.fleet-alert`'s drvPath. → The task list declares the entry, and `drv-delta.txt` lists `fleet-alert` as `changed`.

## Migration Plan

- One stacked chain, in this order:
  1. `lib/vars.nix` with the `fleet-deployer` `varPath` rewrite.
  2. The reader migrations, one commit per file group.
  3. `hostKeys` and the obligation with its judge.
  4. The `ssh-known-hosts` and stibnite rewrites, with the six comment corrections.
  5. The vm-test databases.

  Each commit evaluates alone.
- This change lands second, directly after establish-refactor-oracle and before type-the-fleet-host-registry; declare-host-user-relations-once depends on it, because removing the ambient `flake` argument needs `ssh-known-hosts` to stop reading `flake.nixosConfigurations`. The oracle diff runs at the parent revision and at the chain tip; any unexplained difference blocks landing.
- No deploy is required: unchanged drvPaths mean every host's closure is identical, so the next routine deploy is a no-op for this change. Rollback is reverting the chain, which is again drvPath-neutral.

## Open Questions

1. Should the omnigraph graphs also become `flake.lib` data (brainstorm Q8)? Recommended: no. Their readers test magnetite's rendered output, and the cookbook list is already held to the package by `checks.omnigraph-cookbook-seeds`. A yes adds a data file and five reader edits, with a risk of vm-test drvPath movement through the seed paths.
   - Answer (operator, 2026-11-26): "no". The vm-tests read magnetite's rendered omnigraph settings, not a list, so lifting the graphs would add a second source without removing a read.
2. Should the own-host obligation also fail a NixOS host that declares an `openssh` generator but has no `hostKeys` entry, so that a new host cannot be missing from `known_hosts`? Recommended: no. It would fail any vm-test node that imports `nixos.base` with the sshd service. The gap closes without it once type-the-fleet-host-registry derives `nixosKeyHosts` from each host's class, since a new NixOS host then enters `hostKeys` by its record.
   - Answer (operator, 2026-11-26): "no". Failing a host missing from `hostKeys` belongs with type-the-fleet-host-registry, which derives `nixosKeyHosts` from each host's class.
