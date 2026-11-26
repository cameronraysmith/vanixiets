<!--
Raw capture of the decision chain for this change.
No interactive brainstorming session ran. The operator approved opening this change on 2026-11-26 as part of the Linear project "Den-ready fleet architecture", with its scope fixed: register the host obligation judges once and fold them; one convention for judge fixture checks; drop redundant system gates; fixture checks and runtime tests on the fleet package set; drop the unused `patched` channel; give the envelope budget and the observability host table declared shapes.
The forks below were settled from the repository as read on 2026-11-26, the den-readiness audit of the same day (a session artifact outside the repository, restated here where used), and the locked nixpkgs source. Each fork the operator may want to overturn is repeated as an open question in design.md.
-->

# Brainstorm: register the fleet's obligations once

## Background

A fleet obligation is a fact every host configuration must satisfy, judged by a pure function `failures name hostConfig` that returns the unmet facts as strings. The machine checks (`checks.<system>.nixos-<host>`, `darwin-<host>`) already evaluate each host's configuration, so they are where every judge runs.

Today the judges are wired by hand in `modules/checks/machines.nix:44-97`:

- eleven judges are bound to local names (`:44-54`), each called in a `let` (`:59-75`), each tested `== [ ]` in one conjunction (`:80-90`), and each spelled again in one 1,000-character message (`:93`). Adding a judge means editing four places in one file; the last four changes that added one (devloop collection, garbage collection, PostgreSQL backup, R2 usage) each recorded that edit as its own task.
- a twelfth judge, `networkTargetObligations`, is wired separately as `withNetworkTargets` (`:34-42`) with its own message.
- two judges apply only to darwin hosts, and machines.nix decides that by testing the system string's suffix (`lib.hasSuffix "-darwin" machineSystems.${name}`, `:63`, `:67`), although the same function knows whether it is mapping `nixosConfigurations` or `darwinConfigurations` (`:155-172`).

The judges are defined in eleven files: `lib/omnigent-fleet-obligations.nix:588`, `system/deploy-record.nix:143`, `lib/commit-signing.nix:273`, `darwin/resolver-reload.nix:74`, `darwin/sops-boot-install.nix:85`, `system/mesh-hosts.nix:79`, `system/harmonia-gc.nix:75`, `nixos/postgresql-backup.nix:386`, `nixos/r2-usage.nix:426`, `lib/fleet-deployer.nix:360`, `lib/nix-eval-jobs-host.nix:188`, and `lib/network-targets.nix:82` for the twelfth.

Each judge also has a fixture check that runs it over literal cases and mutants. Ten of these share one hand-copied shape: a `wrong` filter comparing each case's problem count with the judge's, an `assert lib.assertMsg (wrong == { }) "<check>: the judge misjudges <names>"`, and `pkgs.runCommand "<check>" { } "touch $out"` (`checks/{darwin-resolver-reload,deploy-record-order,fleet-deployer-obligations,harmonia-gc-obligations,mesh-hosts-obligations,network-target-obligations,postgresql-backup-obligations,r2-usage,shared-vars-obligations,user-slice-guard-obligations}.nix`). A failure names the case but not the count it expected, the count it got, or the messages. A second convention, `flake.lib.mkEvalCheck` (`lib/mk-eval-check.nix:25`), runs nix-unit in a build; seven test files use it, and the fleet-topology spec requires it for `eval-fleet-topology`.

Twenty-five check modules gate `system == "x86_64-linux"` twice: the whole `perSystem` value is wrapped in `lib.optionalAttrs (system == "x86_64-linux")` or `lib.mkIf (system == "x86_64-linux")`, and the `testSizes.checks` entry inside it repeats `lib.optionalAttrs (system == "x86_64-linux")`. The audit named three such files; a search of the tree on 2026-11-26 found twenty-five (listed in design.md).

Thirteen fixture checks and runtime tests instantiate nixpkgs themselves instead of reading the per-system `fleetPkgs` (`nixpkgs/base-defaults.nix:60-67`), which every host and home already uses:

- eleven runtime tests (`vm-tests/{devloop-ingest:77,fleet-deployer:38,fleet-ingress:79,greptimedb-oom-order:42,greptimedb-pipeline:67,omnigent-worker-isolation:97,omnigraph-local-root:79,omnigraph-seed:49,omnigraph-state-directory-transitions:71,perses-greptimedb:55,shared-reference-tree:35}.nix`), each `import inputs.nixpkgs { inherit system; overlays = [ self.overlays.default ]; }` with or without `allowUnfree`;
- `checks/omnigent-workers.nix:11-15`, the same arguments as `fleetPkgs` less `permittedInsecurePackages`;
- `checks/devin-worker.nix:71-77`, a function `probePkgs system` called afresh by every home it evaluates, for `x86_64-linux` and `aarch64-darwin`.

`nixidy.nix:30` also imports nixpkgs, but for a top-level output, not a check; it is out of scope.

The channels overlay (`nixpkgs/overlays/channels.nix:41-45`) exports `pkgs.patched`, an `import (applyPatches { patches = [ ]; … })`, which would be import-from-derivation if anything read it. Nothing in `modules/` or `pkgs/` reads it. The docs still describe it as the way to apply an upstream fix: ADR-0017 (Layer 1), `architecture/architecture.md:168,329`, `requirements/functional-hierarchy.md:172,206`, `requirements/usage-model.md:305`, and the guide `guides/handling-broken-packages.md` (its "patched" steps, around lines 200-250).

Two shapes are untyped. The collector option `vanixiets.otelCollector.envelopeBudget` is `nullOr attrs` (`clan/services/otel-collector/flake-module.nix:165-174`), though its description names exactly `{ storeUrl; notifiedUnits; databases; }` and both writers (`flake-module.nix:1722-1726`, `vm-tests/fleet-ingress.nix:2214-2221`) write those three. `flake.lib.observabilityHosts` (`lib/observability-hosts.nix:38-156`) is a static table with nine fields per row built by a local `agent` helper; nothing rejects a misspelled field, which a reader's `or` default would silently absorb.

## Decision chain

**Q1. Where does the registry live: a `flake.lib` attribute, a `flake.*` option, or a flake-parts option outside `flake`?**
`flake.lib` is `lazyAttrsOf raw` (`lib/option.nix:3-6`), so two files cannot both define `flake.lib.fleetObligations`. A typed option under `flake` (like `flake.users`) would become a flake output, and the registry's values are functions only the machine checks call. Decision: a top-level flake-parts option `fleetObligations`, declared once in a new `modules/lib/fleet-obligations.nix`, not a flake output. Each judge's defining file adds its own entry. The existing `flake.lib.<judge>` exports stay, because the fixture checks and `checks/nix-eval-jobs-iets.nix:107` read them.

**Q2. What is an entry?**
`{ classes; failures; }`: `classes` is a list drawn from `nixos` and `darwin`, default both; `failures` is `name: hostConfig: [ string ]`, the judge's existing function. The registry key is the name machines.nix's message prints today (`omnigentFleetObligations`, `fleetDeployer`, …), so the message a reader greps for keeps its words, and the database-backup scenario that expects a failure "naming `postgresqlBackupObligations`" still holds.

**Q3. Does `networkTargetObligations` join the registry?**
Yes. It has the same signature and the same "every machine check" scope. Keeping `withNetworkTargets` beside the registry would leave two wiring paths, the thing this change removes. Its message changes from its own line to an entry in the joint message.

**Q4. How does the fold decide applicability?**
machines.nix passes the class it is mapping (`nixos` for `nixosConfigurations`, `darwin` for `darwinConfigurations`) to the fold, which runs the entries whose `classes` contain it. This removes the two suffix tests at `:63` and `:67`. The suffix tests inside three judges (`deploy-record.nix:148`, `harmonia-gc.nix:79`, `mesh-hosts.nix:84`) stay: they choose which configuration path to read, not whether the judge applies. Replacing them is the host-registry change's work (it derives `class` from one declared `system`).

**Q5. What does the fold produce?**
The concatenation of `map (m: "${key}: ${m}") (entry.failures name hostConfig)` over applicable entries in key order, followed by the host's own failing `assertions` messages as now. The check fails when that list is non-empty; the message names only judges that failed. Asserting does not change the toplevel's derivation, so every machine check keeps its drvPath (world assumption A332).

**Q6. One judge-check convention: replace `mkEvalCheck` or the `misjudges` shape?**
They do different jobs. `mkEvalCheck` runs nix-unit over a test file in a build, and the fleet-topology spec requires it. The `misjudges` shape judges at evaluation and builds an empty marker. Decision: a new `flake.lib.judgeCases { name; judge; cases; }`, a function from a derivation to the same derivation that asserts every case first, and `flake.lib.mkJudgeCheck pkgs args = judgeCases args (pkgs.runCommand args.name { } "touch $out")`. Its failure lists each wrong case with expected count, actual count and the judge's messages. Eight files move to `mkJudgeCheck`. `deploy-record-order` and `r2-usage` build real content, so they wrap their derivation in `judgeCases`. `perses-config` is not moved: its predicate is "the first failure is this mutant's own clause", not a count, and its derivation echoes each rejection. `mkEvalCheck` stays for nix-unit tests, and its header gains one line pointing judge-over-fixtures checks to `mkJudgeCheck`. Each derivation is byte-for-byte what it was, so drvPaths hold.

**Q7. Do the `testSizes` entries move into the constructor?**
No. The test-size design (D1) requires each entry to be literal data beside its definition and rejects anything that forces a check's value to read its class. `mkJudgeCheck` returns only the check. Each file keeps its literal `testSizes.checks.<name>` entry.

**Q8. Which system gate is dropped?**
The inner one, inside `testSizes.checks`. The outer gate decides whether the module contributes anything on this system and stays. The entries stay literal, keyed by the same names.

**Q9. How do the fixture checks and runtime tests reach `fleetPkgs`?**
Through the perSystem argument `fleetPkgs` where the module is already in `perSystem` for the same system (the eleven runtime tests and `omnigent-workers`). `devin-worker` evaluates homes for two systems from one x86_64-linux check, so it reads `withSystem s ({ fleetPkgs, ... }: fleetPkgs)` through a two-entry attribute set built once in the `let`, so each system's instance is shared by every home that uses it rather than built per call. `omnigent-workers.nix:16-21`, which builds a deliberately poisoned `flake` argument, is not touched: replacing that guard belongs to the change that removes the ambient `flake` argument.

**Q10. What drvPath effect is declared?**
`fleetPkgs` differs from the local instances in `config.allowUnfree` (absent from `fleet-deployer`'s) and `config.permittedInsecurePackages`. In the locked nixpkgs those two keys only decide whether evaluating a marked package throws, so no derivation should change (world assumption A330). The declared allowance is still the whole `vmTests.{x86_64-linux,aarch64-linux}` set, because a node's NixOS evaluation reads `pkgs` in ways not audited here. Checks, systems and homes are declared unchanged. The cross-revision oracle decides, and any `vmTests` difference is named with its cause before it is accepted.

**Q11. What happens to `pkgs.patched`?**
It is dropped, and `nixpkgs` and `unstable` stay. They are plain imports that cost nothing unless read (A331); ADR-0017 documents them, and removing them is outside this change's scope. ADR-0017 gains a dated amendment saying Layer 1 no longer exports `patched`, why (no consumer, and reading it would be import-from-derivation), and what replaces it: a per-package `overrideAttrs` that adds the upstream patch with `fetchpatch` in an overlay. The four documents that describe `patched` are updated to match.

**Q12. How is `observabilityHosts` typed without an option fixpoint?**
The table stays a static `flake.lib` value (fleet-ingress design D6), and the `agent` helper keeps its defaults. A pure validator `flake.lib.observabilityHostProblems table` returns one message per unknown field, missing field, or value of the wrong type (`platform` must be `nixos` or `darwin`; `collect`, `alwaysOn`, `textfile`, `agentTelemetry` and `langfuse` must be booleans; `smartDevices` and `notifiedUnits` must be lists of strings; `agentSpanQueueMiB` must be a positive integer). The validator runs inside `checks.x86_64-linux.otel-collector-config`, which already reads the table (`checks/otel-collector-config.nix:94`), through `judgeCases` over the real table plus one mutant per rule. This adds no check attribute and does not change that check's derivation. The readers do not run the validator, so reading one row costs no more than now.
Rejected: validating on every read (every reader pays for every row), or a new check (one more key and one more size entry for one assert).

**Q13. How is `envelopeBudget` typed?**
`nullOr (submodule { storeUrl : str; notifiedUnits : attrsOf (listOf str); databases : attrsOf str; })`. The merged value has the same three attributes, so `otelEnvelope`'s rendered script, and with it magnetite's toplevel and the `fleet-ingress` test, is unchanged. The oracle confirms this. Both writers already conform.

**Q14. Which specs change?**
- One requirement names `withFleetObligations`: `database-backup-interface` "A host's backup set is pinned by a fleet obligation". That spec is still in the unarchived `back-up-postgresql-off-host` change, so this change's MODIFIED delta can apply only after that change archives. The archive-order dependency is recorded.
- `devloop-collection-interface` (corpus, `:322`) and `commit-signing-key-interface` (unarchived) say "modules/checks/machines.nix SHALL assert …". That stays true, because the fold runs there. They are not modified.
- `delegate-fleet-deploys`'s design (`:154`) names `withFleetObligations`. It is a design record, not a requirement; its owner is told, and its fleet-deploy-delegation-interface scenario ("its machine check fails naming the problem") still holds.
- The two untyped shapes (the collector's `envelopeBudget` option and the `observabilityHosts` row schema) are new requirements in `fleet-ingress-interface`, ADDED rather than MODIFIED, because `bind-mesh-writes-to-their-host` already modifies that spec's host-table requirement.

**Q15. What must not change?**
- The literal `testSizes` entries.
- The literal check oracles (`omnigent-workers.nix:600` `hostMatrix`, `omnigent-acp-spawn-env.nix:19-22`, `nix-builders-wiring.nix:11-12,43-55`, `sops-correspondence.nix:35-62`).
- The fleet-wide checks that are the only coverage of deferred scheelite (sshd, zram, zerotier); scheelite stays in `deferred` and gets no machine check.
- The perSystem asserts in `machines.nix:99-123` and the `expectedOwners` assert (`:118-120`).
- The two pkgs instances per system (`base-defaults.nix:16-18`).
- The rest of the channels layer.

## Trade-offs

- The registry turns a visible list in one file into entries spread over twelve files. A reader who wants "which judges run" reads `attrNames config.fleetObligations`, or the option's definitions with `nix eval .#… --apply`. It is no longer a grep of one file. Accepted, because a judge's registration then sits beside its definition, the shape den's policies take. (The design later adds a literal key list in machines.nix, so an addition is the registration plus one line there.)
- The joint message drops judges that passed. It is shorter, but a reader no longer sees the full list of judges that ran on a failure. Accepted.
- `judgeCases` adds one function call per case at evaluation, and the cost is noise beside a fixture check's own evaluation.
- Moving the runtime tests onto `fleetPkgs` couples them to the fleet's insecure-package allowance. That allowance is the fleet's own policy, so the tests now see what the hosts see.
