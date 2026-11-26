<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The operator settled the surrounding decisions for the fleet's den-readiness work on 2026-11-26 and was not available to answer questions while this was written.
The forks below were settled from the repository at revision 53c949b30, the locked clan-core source and the evaluation-cost measurements of 2026-11-26 under logs/cross-host-eval-cost-*-20261126-*. Each fork the operator may want to overturn is repeated as an open question in design.md.
The den-readiness audit that motivated this change is a session artifact outside the repository; every figure and file reference used from it was re-read in the tree and is restated here so this file stands alone.
-->

# Brainstorm: stop reading other hosts' evaluated configurations

## Background

Each host's configuration in this fleet is one nix module evaluated on its own. Two places break that.

- `modules/system/ssh-known-hosts.nix:30,40,50,60,70,80` set the `known_hosts` key of each of the six NixOS hosts (cinnabar, electrum, galena, scheelite, magnetite, pyrite) from `flake.nixosConfigurations.<h>.config.clan.core.vars.generators.openssh.files."ssh.id_ed25519.pub".value`. All ten NixOS and darwin configurations import the module: the six NixOS hosts, blackphos and stibnite directly, and argentum and rosegold through `darwin/laptop.nix:40`. Building any one of them therefore evaluates all six NixOS configurations far enough to reach their clan vars.
- `modules/machines/darwin/stibnite/default.nix:173` authorizes stibnite's session key from `inputs.self.nixosConfigurations.magnetite.config.clan.core.vars.generators.stibnite-agent-session.files."key.pub".value`.

The value read in both places is a committed file. clan-core at the locked revision 78d5de23 defines a public var's `value` as `readFile (settings.directory + "/vars/${rel_dir}/${name}/value")` (`nixosModules/clanCore/vars/public/in_repo.nix:14-21`). The other host's configuration contributes only the file's location.

### What it costs (measured 2026-11-26 on stibnite, one fresh process each)

| run | CPU s | thunks | bytes allocated |
|---|---|---|---|
| stibnite toplevel drvPath (run b; b2 repeats it) | 10.97 (10.70) | 24.38M | 3.15 GB |
| stibnite host only, no known_hosts (base-host) | 0.39 | 0.68M | 139 MB |
| stibnite `programs.ssh.knownHosts` forced (c) | 1.37 | 4.40M | 562 MB |
| magnetite's session key value alone (d) | 0.57 | 1.18M | 176 MB |

Forcing `knownHosts` costs about 0.98 s, 3.7M thunks and 423 MB over the host-only baseline (c minus base-host). With the 0.57 s session-key read, where it is not already shared with the `knownHosts` reads, that is 9 to 12 % of the toplevel. This is an upper bound found by subtraction: some of the work may be shared with what the toplevel forces anyway. Only an A/B measurement after the change says what was saved.

The forced values show the exact strings. Each NixOS key is `"ssh-ed25519 AAAA… \n"`: a trailing space (the empty comment) and a newline, because clan reads the file untrimmed. The darwin keys in `lib/darwin-host-keys.nix` are literals with neither.

### The vars layout is known in many places

The same layout (`vars/per-machine/<m>/<generator>/<file>/{value,secret,machines,users,groups}` and `vars/shared/<generator>/<file>/…`) is written out by hand at these sites:

- public values read: `clan/inventory/services/tincr.nix:36` (`readFile "${inputs.self}/…"`; clan's own `getPublicValue` does the same at `clan/services/tincr/flake-module.nix:89`), `darwin/fleet-services-trust.nix:8` (path literal), `home/users/crs58/default.nix:94` (path literal interpolated), `nixos/workstation-ca-trust.nix:10` (path literal), `home/users/lib.nix:101-104` (`fileContents`), `checks/otel-collector-config.nix:96` and `checks/otel-collector-darwin.nix:62` (magnetite's ZeroTier IP, `lib.trim (readFile "${self}/…")`, read twice), `lib/fleet-deployer.nix:99-103` (`pathExists` then `lib.trim (readFile …)`).
- existence: `nixos/postgresql-backup.nix:136,146-147` and `nixos/r2-usage.nix:236,250` (`pathExists "${toString hostConfig.clan.core.settings.directory}/vars/per-machine/${name}/…/secret"`).
- recipients: `lib/shared-vars-recipients.nix:45` (`pathExists (self + "/vars/shared/${gen}/${file}/machines/${name}")`), `lib/fleet-deployer.nix:322` (`…/groups/fleet-deployers`), `lib/commit-signing.nix:166` (`readDir` of `…/key/machines`).
- hash of a secret: `darwin/otel-collector-agent.nix:451` (`hashFile "sha256" "${self}/vars/shared/langfuse/secret-key/secret"`).
- the relative path itself: `lib/fleet-deployer.nix:305-310` (`varPath`, choosing shared or per-machine by the generator's `share`).

Others look like readers but are not:
- `checks/sops-correspondence.nix:213-214` parses paths in a shell `case`. It is the check that judges the committed tree.
- `checks/fleet-deployer-obligations.nix:152,207` are literal fixture paths.
- `checks/langfuse-query.nix:114` interpolates two encrypted files into a test script.
- `home/ai/omnigent/credentials.nix:106-114` already uses clan's `rel_dir`.

### Tests that read magnetite for a shared fact

`vm-tests/greptimedb-pipeline.nix:75-76`, `fleet-ingress.nix:91-92`, `devloop-ingest.nix:82-83`, `greptimedb-oom-order.nix:113` and `perses-greptimedb.nix:60-61` take `databases` from `self.nixosConfigurations.magnetite.config.services.greptimedb`. That value is already flake data: magnetite sets `inherit (collectorSchema) databases` (`magnetite/default.nix:857`) from `flake.lib.otelCollectorSchema.databases` (`clan/services/otel-collector/schema.nix:347-351`). The tests read it from the host so that, in the words of `greptimedb-pipeline.nix:72-74`, "an inventory change cannot drift past this test silently", and `greptimedb-pipeline.nix:90-92` asserts what magnetite declares.

Other host reads in the vm-tests are rendered configuration, not shared facts:
- `fleet-ingress.nix:109`: electrum's collector settings.
- `fleet-ingress.nix:171-173`: pyrite's agent-session collector and unit.
- magnetite's `tables`, `pipelines`, `OOMScoreAdjust` and `postgresql.package`.
- the omnigraph module's rendered `cluster.settings`, `policies`, `extraFiles` and per-graph `seed` paths.
- `clan.core.vars.generators.greptimedb-users`, which the planned secrets seam must keep readable.

## Decision chain

**Q1. Where do other hosts' public keys come from?**
Chosen: from the committed `vars/per-machine/<h>/openssh/ssh.id_ed25519.pub/value` files, read through a shared accessor and merged with `darwinHostKeys` into `flake.lib.hostKeys`. This is the file clan reads, so the bytes are identical. Rejected: pinning the NixOS keys as literals like the darwin ones. That would add a second copy of a value clan regenerates, and the two copies would drift on the next rotation.

**Q2. What keeps the committed file honest?**
Each NixOS host asserts that its own evaluated `openssh` public value equals `hostKeys.<its name>`. That reads only the host's own configuration. With it, a host whose generator moves, is renamed or becomes shared fails its own build instead of shipping a stale `known_hosts` to the rest of the fleet. Darwin keys are not generated by clan and stay literals, so they get no counterpart. Rejected: a fleet-wide check that evaluates all six hosts. That brings back the cross-host read the change removes, only in a different attribute.

**Q3. stibnite's session key.**
stibnite reads magnetite's committed `stibnite-agent-session/key.pub/value` through the accessor. `checks/nix-builders-wiring.nix:311-317` already compares magnetite's evaluated value with stibnite's authorized keys, and it reads both hosts because it is a check. It keeps that job, so no new obligation is added. Rejected: an own-host obligation on magnetite. The fact it would protect is a relation between two hosts, and the existing check already holds it.

**Q4. Trimming.**
The accessor's `public` returns `readFile` unchanged, exactly as clan's `.value` does. Each site keeps its own post-processing: `lib.trim` at the two otel checks and the deployer, `fileContents` at the user signing key, none at known_hosts and the session key. Rejected: a trimmed accessor. It would change every `known_hosts` line, because the trailing space and newline would go.

**Q5. Paths versus strings.**
The sites differ in kind. A path literal interpolated into a configuration (`"${../../vars/…/root.crt/value}"`, or a path in `security.pki.certificateFiles`) copies the one file into the store under the name `value`. A string built from `"${self}/…"` refers into the whole flake source. To keep each site's store paths, the accessor offers `path`, which returns a path value rooted at the repository (`../..` from `modules/lib`). Sites that interpolated a path literal use `path`; sites that read through a string read through `public`, `exists` or `isRecipient`. The result is identical bytes. Whether `readFile` of a path and of a `"${self}/…"` string produce the same string context is not proven here [INFERENCE: both are empty, because the flake source has no references]. The before/after drvPath diff settles it.

**Q6. The API.**
`flake.lib.vars = { relPath; path; public; exists; isRecipient; }`, defined in `modules/lib/vars.nix`.
- `relPath { generator, file, machine ? null }` returns `vars/shared/…` when `machine` is null and `vars/per-machine/<machine>/…` otherwise. `fleet-deployer.nix`'s `varPath` becomes a call to it, with `machine = if share then null else name`.
- `path` is the repository root joined to a `relPath`.
- `public` is `readFile (path … + "/value")`.
- `exists` is `pathExists` of `…/secret` or, for a public file, `…/value`.
- `isRecipient { …, machine | group | user }` is `pathExists` of `…/machines/<m>`, `…/groups/<g>` or `…/users/<u>`.

`lib/commit-signing.nix:166` lists recipients with `readDir` of `path {…}/machines`; this adds no sixth export.

**Q7. What stays out.**
These stay as they are:
- `sops-correspondence.nix:213-214`: it is the independent judge of the committed tree, and deriving its patterns from the accessor would make it share the code it judges.
- the fixtures at `fleet-deployer-obligations.nix:152,207`: they are literal oracles. They change in the same commit only if `localSecretsOf`'s output shape changes, which this design avoids.
- `credentials.nix:106-114`: it already uses clan's accessor.
- `langfuse-query.nix:114`: it puts encrypted files into a test script by design.

**Q8. Magnetite-shared facts in tests.**
The greptimedb `databases` map moves from "read from magnetite" to "read from `flake.lib.otelCollectorSchema.databases`" in the five vm-tests. Each test keeps an assertion that magnetite's `services.greptimedb.databases` equals the data, so the drift guard survives. The tests still evaluate magnetite for the assertion and for the users generator, so this saves no evaluation. Its value is that the fact has one declaration outside any host.

The omnigraph graphs are left alone. The tests and checks that read them (`omnigraph-local-root`, `omnigraph-seed`, `omnigraph-state-directory-transitions`, `checks/omnigraph-bootstrap-rehearsal.nix:124`, `checks/omnigraph-cookbook-seeds.nix:253-275`) read the module's rendered output: seed store paths, queries, policies. magnetite is the intended oracle for that, and the one list-like fact, the cookbook names, is already held to the package by `omnigraph-cookbook-seeds`. Rejected: lifting `cookbooks` into `flake.lib`. Nothing in a test reads the bare list, and the seed file paths depend on which package set builds them, which risks moving vm-test drvPaths for no reader.

**Q9. The ambient `flake` module argument.**
Today `ssh-known-hosts` is the only NixOS or darwin module that reads the `flake` module argument. After this change it reads `config.flake.lib` by closure, as it already does for `hosts`, and no system-level module reads `flake` at all. The nine `_module.args.flake = inputs.self` setters stay: removing them belongs with the poisoned-`flake` guard in `checks/omnigent-workers.nix:16-21`, which the change removing the ambient argument replaces in the same step. This change only corrects the six comments that call the setter "required by ssh-known-hosts". The `lib.optionalAttrs (flake ? nixosConfigurations)` guard goes, because every importer passes `inputs.self` and the module no longer reads `flake`.

**Q10. Oracle and measurement.**
The change is intended to leave every drvPath unchanged. It is accepted on the before/after drvPath diff of all `nixosConfigurations`, `darwinConfigurations` and `homeConfigurations` toplevels and of `checks.{x86_64-linux,aarch64-darwin}`, using the recipe from the refactor-oracle change, not `just eval-identity`, which compares stock nix with iets at one revision. Because the motivation is performance, the stibnite toplevel is then measured with `NIX_SHOW_STATS` in interleaved A/B/A/B runs, one fresh process each, on the same host and nix, and the result is recorded against the baseline above. One NixOS toplevel (cinnabar) is measured too.

## Trade-offs

- A host's `known_hosts` now trusts a committed file without asking whether the configuration that owns it still generates it. The own-host obligation covers NixOS. A darwin host still relies on a person updating `darwinHostKeys`, as before.
- The accessor puts knowledge of clan's layout into one file. A clan layout change breaks every reader at once, where today it might break some of them silently.
- The magnetite-databases change saves no evaluation. It is kept because the audit counts it toward a host body that holds no fleet facts, and because it costs five two-line edits.
