## Context

The machine checks (`checks.x86_64-linux.nixos-<host>`, `checks.aarch64-darwin.darwin-<host>`, built by `modules/checks/machines.nix`) evaluate each host's configuration and are where every fleet-wide judge of that configuration runs. As of `main` at `9055ae0f1333` (2026-11-27), after `type-the-fleet-host-registry` and `stop-reading-other-hosts-configs` landed:

- **Wiring by hand.** Eleven judges are bound (`machines.nix:43-53`), called (`:58-74`), conjoined (`:77-90`) and named in one message (`:92`) inside `withFleetObligations` (`:55-97`). A twelfth, `networkTargetObligations`, runs through `withNetworkTargets` (`:33-41`). The two darwin-only judges are chosen by `self.lib.hosts.${name}.class == "darwin"` (`:62`, `:66`), the class the typed host registry `flake.fleet.hosts` derives from `system` (`lib/hosts.nix`; `flake.lib.hosts` is its read-only view). The machines selected are the inventory's with `flake.fleet.hosts.<name>.checked` (`:20-28`).
- **Judge definitions**, each exporting `failures name hostConfig : [ string ]` under `flake.lib`:

  | Registry key (= current message name) | Defined at | Classes |
  |---|---|---|
  | `omnigentFleetObligations` | `lib/omnigent-fleet-obligations.nix:588` | nixos, darwin |
  | `deployRecordObligations` | `system/deploy-record.nix:143` | nixos, darwin |
  | `commitSigningObligations` | `lib/commit-signing.nix:278` (`failures` at `:190`) | nixos, darwin |
  | `resolverReloadObligations` | `darwin/resolver-reload.nix:74` | darwin |
  | `sopsBootInstallObligations` | `darwin/sops-boot-install.nix:85` | darwin |
  | `meshHostsObligations` | `system/mesh-hosts.nix:78` | nixos, darwin |
  | `harmoniaGcObligations` | `system/harmonia-gc.nix:75` | nixos, darwin |
  | `postgresqlBackupObligations` | `nixos/postgresql-backup.nix:390` | nixos, darwin |
  | `r2UsageObligations` | `nixos/r2-usage.nix:430` | nixos, darwin |
  | `fleetDeployer` | `lib/fleet-deployer.nix:362` (`failures` at `:350`) | nixos, darwin |
  | `nixEvalJobsObligations` | `lib/nix-eval-jobs-host.nix:188` | nixos, darwin |
  | `networkTargetObligations` | `lib/network-targets.nix:82` | nixos, darwin |

  `postgresqlBackupObligations` and `r2UsageObligations` run on darwin today and return `[ ]` there. Their class list keeps that behavior rather than narrowing it. The judges that still branch on the class inside (`deploy-record.nix:148`, `harmonia-gc.nix:79`, `mesh-hosts.nix:83`) already read `flake.lib.hosts.<name>.class`; the host-registry change replaced their system-suffix tests.
- **Judge fixture checks.** Ten files share the hand-copied `wrong`/`misjudges` shape: `checks/{darwin-resolver-reload,deploy-record-order,fleet-deployer-obligations,harmonia-gc-obligations,mesh-hosts-obligations,network-target-obligations,postgresql-backup-obligations,r2-usage,shared-vars-obligations,user-slice-guard-obligations}.nix`. Eight end in `pkgs.runCommand "<name>" { } "touch $out"`; `deploy-record-order` and `r2-usage` build real content. `perses-config.nix` judges by clause prefix and echoes each rejection. `flake.lib.mkEvalCheck` (`lib/mk-eval-check.nix`) runs nix-unit for the `*.test.nix` files.
- **Double system conditions.** Since `declare-test-size-classes`, about a hundred modules declare `testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") { … }`. In 26 of them the whole `perSystem` value already sits under an outer `lib.optionalAttrs`/`lib.mkIf (system == "x86_64-linux")`, so the inner condition is unreachable: `checks/{commit-signing-key,darwin-machine-key-guard,darwin-mesh-resolver-flags,darwin-resolver-reload,deploy-record-order,fleet-deploy-request,fleet-deploy-resolve,fleet-deploy-watch,fleet-deployer-obligations,harmonia-gc-obligations,host-key-obligations,magnetite-zram-headroom,matrix-server-name-reset,mesh-hosts-obligations,network-target-obligations,omnigent-acp-spawn-env,postgresql-backup-obligations,pyrite-audio,pyrite-bluetooth,pyrite-desktop,pyrite-nix-concurrency,pyrite-wifi,renovate-allowed-commands,shared-vars-obligations,sops-correspondence,user-slice-guard-obligations}.nix`. In the others `testSizes.checks` sits beside a separately gated `checks`, so its own condition is the only one it has.
- **Extra nixpkgs instances**: eleven `nodePkgs` in `modules/vm-tests/` (`devloop-ingest`, `fleet-deployer`, `fleet-ingress`, `greptimedb-oom-order`, `greptimedb-pipeline`, `omnigent-worker-isolation`, `omnigraph-local-root`, `omnigraph-seed`, `omnigraph-state-directory-transitions`, `perses-greptimedb`, `shared-reference-tree`), `checks/omnigent-workers.nix:11-15`, and `checks/devin-worker.nix:71-77`, called by every home that check evaluates. The fleet instance is the perSystem `fleetPkgs` (`nixpkgs/base-defaults.nix`): the flake's nixpkgs with `[ config.flake.overlays.default ]`, `allowUnfree` and `permittedInsecurePackages`.
- **Channels overlay**: `nixpkgs/overlays/channels.nix` exports `patched`, which nothing in `modules/` or `pkgs/` reads; ADR-0017 Layer 1 and six documents describe it.
- **Untyped shapes**: `vanixiets.otelCollector.envelopeBudget` is `nullOr attrs` (`clan/services/otel-collector/flake-module.nix:165`), read by `flake.lib.otelEnvelope` (`lib/otel-envelope.nix`). `flake.lib.observabilityHosts` (`lib/observability-hosts.nix`) has no row schema; since the host-registry change its rows' `platform` is the host's `flake.fleet.hosts` class, whose type admits `android` as well as `nixos` and `darwin`.

Constraints carried from earlier decisions and not reopened here:
- The `testSizes` entries stay literal, beside their definitions (test-size design D1), declared by the same mechanism.
- Checks with too few runs keep `{ class = "medium"; measured = false; }` (test-size design D4).
- The literal check oracles stay literal: `checks/omnigent-workers.nix` (`hostMatrix`/`serverMatrix`), `checks/omnigent-acp-spawn-env.nix:19-22`, `checks/nix-builders-wiring.nix`, `checks/sops-correspondence.nix:35-62`.
- Scheelite stays unchecked (`flake.fleet.hosts.scheelite.checked = false`). Its only coverage is the fleet-wide sshd, zram and zerotier checks, which stay as they are.
- The perSystem name asserts in `machines.nix` stay, because the flake-shape pin relies on them as its first layer.
- Two nixpkgs instances per system stay (`base-defaults.nix`), as does the channels layer apart from `patched`.
- `observabilityHosts` stays a static `flake.lib` table (fleet-ingress design D6).
- The obligation modules stay imported by `base`; nixidy is excluded.

## Goals / Non-Goals

**Goals:**
- Adding a host judge is one registration in the file that defines it, plus its key in the literal key list (design risks).
- Every judge applies to the host classes it declares. The machine check of a host in a class asserts every judge for that class and names each one that fails.
- Every judge-over-fixtures check reports a wrong case with its expected count, the actual count and the judge's messages.
- Fixture checks and runtime tests evaluate against the package set the hosts use.
- Nothing documents or exports a channel that nothing reads.
- The two shapes above are checked.
- Every NixOS, darwin and home toplevel and every `checks.{x86_64-linux,aarch64-darwin}` attribute keeps its derivation, apart from the checks built from the docs site, whose source this change edits, and the checks built from the whole source, which the oracle's base allow-list covers. Only `vmTests` may otherwise differ, and only where the oracle names a cause.

**Non-Goals:**
- Changing what any judge enforces, or its `flake.lib` export.
- Changing how a judge reads the class inside itself; it already reads the host registry.
- The poisoned `flake` argument at `checks/omnigent-workers.nix:16-21`; the host-user relations change replaces that guard.
- Moving `perses-config` or the nix-unit checks to the new constructor.
- Moving `testSizes.checks` and `checks` under one outer condition where each has its own; that changes how the entries are declared.
- `nixidy.nix` (a top-level output).
- The `nixpkgs` and `unstable` channel attributes.
- A behavioral capability: nothing a fleet user observes changes.

## Decisions

### D1: the registry is a flake-parts option outside `flake`

- **Choice**: `options.fleetObligations = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { options = { classes = mkOption { type = nonEmptyListOf (enum [ "nixos" "darwin" ]); default = [ "nixos" "darwin" ]; }; failures = mkOption { type = functionTo (functionTo (listOf str)); }; }; }); default = { }; }` in a new `modules/lib/fleet-obligations.nix`. Each file in the table above adds `fleetObligations.<key> = { failures = <its judge>.failures; … }` beside its `flake.lib` export. machines.nix reads `config.fleetObligations`.
- **Rationale**: `flake.lib` is `lazyAttrsOf raw` (`lib/option.nix`), so a key defined from twelve files would collide. A `flake.*` option would add a flake output carrying functions only machines.nix calls. A flake-parts option merges per key, as den's policies do, and is not an output (flake-parts' `debug` output, which exposes the whole module configuration, is not an interface). Boundary: source-only and first-party. Nothing delivered to a host changes.
- **Alternatives considered**: (a) `flake.fleet.obligations` beside `flake.fleet.hosts`. The host registry declares `options.flake.fleet.hosts` as its own option path, so this would not collide, but it would be an output carrying functions nothing outside the machine checks calls. (b) A literal list in machines.nix of `self.lib` names. It is still a hand list in a shared file.

### D2: the fold, and its message

- **Choice**: machines.nix's two mappers pass their class (`"nixos"` from `nixosConfigurations`, `"darwin"` from `darwinConfigurations`) to one function `withFleetObligations class name machineConfig toplevel`. The function concatenates `map (m: "${key}: ${m}") (entry.failures name machineConfig)` over the entries whose `classes` contain `class`, in `attrNames` order, and asserts that the result is `[ ]`. Its message is `Fleet obligations unmet on <name>:` followed by one line per message, then the host's own failing `assertions` messages as now. `withNetworkTargets` is deleted; `networkTargetObligations` is an entry.
- **Rationale**: one path for every judge; the class comes from the configuration set being mapped, so a darwin-only judge is never called on a NixOS configuration, whatever the registry says about the host. An assertion leaves the asserted derivation unchanged (A332), so the machine checks keep their drvPaths. The function keeps its name: no spec requirement other than the database-backup one names it, and that one is restated in D9.
- **Alternatives considered**: (a) keep printing every judge with `[]`. That makes the message grow with the registry and does not help the reader. (b) Pass `class` into each judge. That changes twelve signatures for a value each judge can already read from the host registry.

### D3: one judge-check constructor, for evaluation-time judges only

- **Choice**: new `modules/lib/judge-check.nix` exporting:
  - `flake.lib.judgeCases { name, judge, cases, assertions ? [ ] } : derivation -> derivation`.
    - `cases` is `attrsOf { problems : int; … }`. A case may carry its own `judge`, overriding the default, so files with two judges (`fleet-deployer-obligations`, `network-target-obligations`) pass one case set.
    - `assertions` is a list of `{ assertion; message; }` for invariants that are not cases (`fleet-deployer-obligations`'s `derivedTargets`, `darwin-resolver-reload`'s target list, `r2-usage`'s cost-panel queries).
    - It returns the derivation unchanged when every case gives its count and every assertion holds. Otherwise it throws `<name>: <case>: expected <n> problems, the judge gave <m>: <messages as JSON>`, one line per wrong case, followed by the messages of any failing assertions.
  - `flake.lib.mkJudgeCheck pkgs args = judgeCases args (pkgs.runCommand args.name { } "touch $out")`.

  Eight files move to `mkJudgeCheck`. `deploy-record-order` and `r2-usage` wrap their existing derivation in `judgeCases`. `perses-config` and the `mkEvalCheck` users are left as they are. `mk-eval-check.nix`'s header gains one line: judge-over-fixtures checks use `mkJudgeCheck` or `judgeCases`.
- **Rationale**: the eight derivations are byte-identical to what they are now, and the other two keep their derivation, so drvPaths hold. Reporting expected and actual counts turns a failure into a diagnosis. The constructor never touches `testSizes`, so each file keeps its literal entry (test-size D1, D4).
- **Sequencing**: `checks/host-key-obligations.nix`, added by `stop-reading-other-hosts-configs` after this design was written, judges its fixtures by count with its own filter and `runCommand`. It is not among the ten this commit moves; task 3.5 moves it to `mkJudgeCheck`, and the change does not archive until it has, or until that task is split off.
- **Alternatives considered**: (a) migrate to `mkEvalCheck`. It runs nix-unit in a build, which changes every derivation and moves a cheap evaluation into a build. (b) a constructor that also emits the `testSizes` entry. D1 allows that only if both attributes stay literal, and a constructor returning a merged attrset would make every check file call it at the top level of `perSystem`. The gain is too small for that. (c) move `perses-config`. Its predicate is not a count, and its derivation would change.

### D4: an unreachable inner system condition goes

- **Choice**: in the 26 modules listed in Context, `testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") { … }` becomes `testSizes.checks = { … }` inside the unchanged outer condition. A module whose `testSizes.checks` sits beside a separately gated `checks` (about seventy, among them `r2-usage`, `otel-collector-config`, `devin-worker` and the `modules/lib/*.test.nix` checks) keeps its condition: there it is the only one, not a repetition.
- **Rationale**: the outer condition already makes the whole value empty on other systems, so the entry set per system is identical before and after and the declaration mechanism is unchanged. `test-size-classes` on each system fails on an entry naming no attribute, so its drvPath on both systems witnesses the equal key sets.
- **Alternatives considered**: (a) drop the outer condition instead. That would emit the check value on every system. (b) move `testSizes.checks` and `checks` under one outer condition in the other seventy modules. That restructures how their entries are declared, which the test-size design keeps as it is.

### D5: fixture checks and runtime tests read `fleetPkgs`

- **Choice**:
  - Nine runtime-test modules (`devloop-ingest`, `fleet-deployer`, `fleet-ingress`, `greptimedb-oom-order`, `greptimedb-pipeline`, `omnigent-worker-isolation`, `omnigraph-local-root`, `omnigraph-seed`, `omnigraph-state-directory-transitions`) and `checks/omnigent-workers.nix` take `fleetPkgs` from their `perSystem` arguments and replace the local import with it. Every use of `nodePkgs` keeps its name, as a `let` alias `nodePkgs = fleetPkgs;`, so the test bodies are not edited. `fleet-ingress`, whose import added its own `ntfy-send` overlay after the flake's, binds `nodePkgs = fleetPkgs.appendOverlays [ <that overlay> ]`, the same overlays in the same order.
  - `omnigent-worker-isolation`'s import keyed on `pkgs.stdenv.hostPlatform.system`, which equals the perSystem `system` for both of its systems.
  - `checks/devin-worker.nix` replaces `probePkgs` with an attribute set built once in its `let`, `fleetPkgsBySystem = lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (s: withSystem s ({ fleetPkgs, ... }: fleetPkgs));`, read as `fleetPkgsBySystem.${system}`. Its check is `checks.x86_64-linux.devin-worker-structural`.
  - `vm-tests/shared-reference-tree.nix` and `vm-tests/perses-greptimedb.nix` are held by another change in flight; they keep their own nixpkgs in this commit, and moving them the same way is `finish-fleet-package-set-and-budget-typing`'s work. Nothing in this commit depends on them.
- **Rationale**: a lazy attribute set is evaluated once per key, so each system's instance is shared by every home the check evaluates. Before, `probePkgs` built a new instance per call. `fleetPkgs` has the same overlay (`config.flake.overlays.default`, the value `self.overlays.default` names) and adds `allowUnfree` where it was missing, plus `permittedInsecurePackages`. In the locked nixpkgs those keys decide only whether evaluating a marked package throws (A330). Boundary: vendored-versus-first-party. nixpkgs and the NixOS test framework are used through their public `import`/`node.pkgs` interfaces and are not patched.
- **Declared drvPath effect**: none. Evaluated against the parent, every runtime test the nine modules define, both `omnigent-workers` check sets and `devin-worker-structural` keep their drvPaths, as A330 predicts (tasks 4.1-4.3), so `drv-delta.txt` names no `vmTests` attribute. A difference the oracle finds there is a violation of A330 and is explained before the change lands.
- **Alternatives considered**: (a) the perSystem `pkgs`. It lacks `flake.overlays.default` (`base-defaults.nix`). (b) a `withSystem` call inside each `evalHome` call. Flake-parts memoises `withSystem` per system, but a single `let` binding makes the sharing visible in the file and does not depend on that memoisation.

### D6: drop `patched`, amend ADR-0017

- **Choice**: delete `patched` and its header line from `channels.nix`. Add a dated "Amendment (2026-11-27)" section to ADR-0017: Layer 1 no longer exports `patched`. Nothing read it, and reading it would import a derivation's output during evaluation. A fix from an upstream pull request is applied as a per-package `overrideAttrs` that adds the patch with `fetchpatch` in an overlay; `stable` fallbacks are unchanged. Update `architecture/architecture.md`, `requirements/functional-hierarchy.md`, `requirements/usage-model.md`, `concepts/architecture-overview.md`, `reference/repository-structure.md` and the guide's `patched` steps in `guides/handling-broken-packages.md` to match. ADR-0017's Decision text is left as written, and the amendment supersedes it in place.
- **Rationale**: the attribute is lazy (A331), so removing it changes no derivation that reads the overlay. The documents are the only thing that still uses it. Boundary: source-versus-delivered. The ADR and guides are delivered as the docs site, so the edit is verified by building it (`just docs-build`), not by reading the source, and the checks built from the site change with its source (`drv-delta.txt`).
- **Alternatives considered**: keep `patched` with a non-empty patch list. That is a feature nobody asked for, and it carries an evaluation-time build.

### D7: `envelopeBudget` becomes a submodule

- **Choice**: `type = lib.types.nullOr (lib.types.submodule { options = { storeUrl = mkOption { type = str; }; notifiedUnits = mkOption { type = attrsOf (listOf str); }; databases = mkOption { type = attrsOf str; }; }; });`, with the description unchanged apart from dropping the inline shape.
- **Rationale**: both writers set exactly these three. The merged value has the same attributes and values, so `otelEnvelope`'s rendered script is unchanged and magnetite's toplevel and `vmTests.x86_64-linux.fleet-ingress` keep their derivations. A writer that misspells a field now fails evaluation. Boundary: first-party option on a vendored service. Only the first-party option type changes.
- **Sequencing**: `modules/clan/services/otel-collector/**` is held by another change in flight, so this decision is applied after that change lands, by `finish-fleet-package-set-and-budget-typing`. This change's commit leaves the option as it is; nothing else in it depends on the type.
- **Alternatives considered**: `attrsOf anything` with an assertion. It is weaker, and the error arrives later.

### D8: a validator for `observabilityHosts`, run in an existing check

- **Choice**: `flake.lib.observabilityHostProblems : table -> [ string ]` in `lib/observability-hosts.nix`. It returns one message per unknown or missing field, and per value of the wrong type:
  - `platform` must be `"nixos"` or `"darwin"`. The row's platform is its host's class, whose type also admits `android`, so this rule is not implied by the registry's type.
  - `collect`, `alwaysOn`, `textfile`, `agentTelemetry` and `langfuse` must be booleans.
  - `smartDevices` and `notifiedUnits` must be lists of strings.
  - `agentSpanQueueMiB` must be a positive integer.

  `checks/otel-collector-config.nix` wraps its existing derivation in `judgeCases` with the real table (0 problems) and one mutant row per rule (1 problem each). The `agent` helper and its defaults are unchanged. Rules that relate fields (`langfuse` requires `agentTelemetry`) stay where they are asserted now.
- **Rationale**: "typed" without an option fixpoint, as fleet-ingress D6 requires. The readers do not run it, so reading a row costs what it does now. The check already reads the table and keeps its derivation. Boundary: source-only.
- **Alternatives considered**: (a) validate on read. Every reader would pay for every row. (b) a new check. That adds one more key and one more size entry for one assertion.

### D9: spec deltas

- **Choice**:
  - ADDED two `fleet-ingress-interface` requirements: D8's. D7's requirement moved to `finish-fleet-package-set-and-budget-typing`.
  - New `fleet-obligation-registry-interface` (D1–D4) and `fleet-package-set-interface` (D5, D6).
  - `world-assumptions` A330–A332.
- **Archive order**: none. The MODIFIED `database-backup-interface` delta this change first carried was dropped on 2026-11-27; `back-up-postgresql-off-host` names the registered judge in its own delta. D7's requirement and the runtime-test half of D5's moved to `finish-fleet-package-set-and-budget-typing`, which archives after this change.
- **Not modified**: `devloop-collection-interface` and `commit-signing-key-interface` say "`modules/checks/machines.nix` SHALL assert", which stays true. `delegate-fleet-deploys`'s design D15 (`design.md:154`) named `withFleetObligations`; this commit rewrites that sentence to name the `fleetObligations.fleetDeployer` registration and the fold in `machines.nix` (task 7.3 tells its owner). The fleet-deploy-delegation-interface scenario ("its `darwin-<host>` machine check fails evaluation naming the problem") still holds.

### D10: the oracle and the cost points

- **Choice**:
  - The change lands as one commit. Each task group keeps its evidence by evaluating the attributes it touches against the parent, and the commit is accepted on one run of `just drv-diff <parent> <commit> openspec/changes/register-fleet-obligations/drv-delta.txt` (about 16 minutes). `drv-delta.txt` declares, by exact attribute path, the 28 checks that build or consume the docs site (D6) as `changed`, and nothing else; the base allow-list covers the checks built from the whole source.
  - No `vmTests` attribute is declared: D5's evaluations found every one unchanged. If the oracle finds a difference there, its cause is found by `nix derivation show` on both drvs and recorded before the change lands.
  - One cost point is measured with `just eval-cost`, interleaved parent/commit: `checks.x86_64-linux.nixos-magnetite.drvPath` for the registry fold, where any change should be within noise. Measured (task 2.5): thunks +7,296 (+0.03%) and GC bytes +0.02%, deterministic, with CPU time not above run-to-run spread, so `failures` stays `functionTo`.
  - Two cost points are recorded but not gated: `checks.x86_64-linux.devin-worker-structural.drvPath` and one runtime test's `.drvPath` (`vmTests.x86_64-linux.greptimedb-pipeline`). Lower allocation is expected [INFERENCE: one nixpkgs instance fewer per evaluation]. Measured (task 4.5): GC bytes -39% and -4.4%, thunks -28% and -1.7%. The direction holds; that the saving is one instance is not shown.
- **Rationale**: a refactor declared neutral is accepted on the cross-revision oracle, not on `just eval-identity`, which compares two evaluators at one revision. The task groups are not separately shippable, and one full diff per group would cost five times as much for no added coverage.

## Spec and feature alignment

This table is the pre-apply spec-and-feature alignment record.
It carries one row per requirement in this change's four delta specs, with the capability's stratum tag from the proposal and the modality that witnesses the requirement.

No row routes to a Gherkin scenario, so this change lays out no `.feature` file.
The repository has no BDD runner (no pytest-bdd, cucumber or behave dependency, and no `.feature` file in the tree), so a laid-out scenario would be an unbound surface nothing executes.
Every observable this change asserts is a value of the evaluated flake or a drvPath, which `nix eval`, the flake checks and their mutants, and `just drv-diff` witness.
No row routes to an executable-specification modality (`est-property`, `est-contract`, `est-symbolic`): each fixture check is an example-based build gate, not a ∀-quantified property.
Where a scenario has no task that observes it, the row says so rather than naming a witness.

| Requirement | Capability | Stratum | Modality | Nix check that realizes it | Witness |
|---|---|---|---|---|---|
| Each host judge is registered once, beside its definition | `fleet-obligation-registry-interface` | interface | build gate (`nix eval` of output names) and content search | every `nixos-<host>`/`darwin-<host>` check through the key-list assertion in `checks/machines.nix` | tasks 2.1, 2.2 |
| The registry holds exactly the fleet's twelve judges | `fleet-obligation-registry-interface` | interface | build gate (key-list assertion, deletion and probe mutants) | the key-list assertion evaluated by every machine check | tasks 2.3, 2.4 |
| Every machine check asserts every judge registered for its class | `fleet-obligation-registry-interface` | interface | build gate (darwin-only throwing mutant; drvPath comparison) | `checks.x86_64-linux.nixos-<host>`, `checks.aarch64-darwin.darwin-<host>` | tasks 2.3, 2.4, 7.1 |
| A failing machine check names each unmet judge | `fleet-obligation-registry-interface` | interface | build gate (cinnabar harmonia mutant) | `checks.x86_64-linux.nixos-cinnabar` | task 2.4 |
| A judge-over-fixtures check reports each wrong case | `fleet-obligation-registry-interface` | interface | build gate (wrong-count mutant) | `checks.x86_64-linux.harmonia-gc-obligations` (and every `mkJudgeCheck`/`judgeCases` user) | tasks 3.3, 6.3 |
| Every count-judged fixture check is built by one constructor | `fleet-obligation-registry-interface` | interface | build gate (drvPath comparison) and content search | the ten migrated checks, `otel-collector-config` and `host-key-obligations` | tasks 3.1, 3.2, 3.5, 6.3, 7.1 |
| A check module states its system condition once | `fleet-obligation-registry-interface` | interface | build gate (drvPath comparison) | `checks.{x86_64-linux,aarch64-darwin}.test-size-classes` | task 3.4 |
| Fixture checks evaluate against the fleet package set | `fleet-package-set-interface` | interface | build gate (drvPath comparison) and content search | `omnigent-workers`' checks, `devin-worker-structural` | tasks 4.2, 4.3, 7.1; the nine runtime-test modules (task 4.1) are covered by `finish-fleet-package-set-and-budget-typing`'s requirement |
| The channels overlay offers no patched channel | `fleet-package-set-interface` | interface | content search and build gate (`just docs-build`, drvPath comparison) | `checks.*.package-vanixiets-docs*` build the amended pages | tasks 5.1, 5.2, 7.1 |
| (moved) The envelope budget has a declared shape; the backup-set judge's registration | — | — | — | — | moved to `finish-fleet-package-set-and-budget-typing`; the backup requirement is stated by `back-up-postgresql-off-host` |
| Each observability host row conforms to one schema | `fleet-ingress-interface` | interface | build gate (`judgeCases` cases) | `checks.x86_64-linux.otel-collector-config` | task 6.3 |
| The observability host row schema has nine typed fields | `fleet-ingress-interface` | interface | build gate (one mutant row per rule) | `checks.x86_64-linux.otel-collector-config` | task 6.3 |
| A330 | `world-assumptions` | world | monitoring (violation scenario) | the oracle over `vmTests` and the moved checks | tasks 4.1-4.3, 7.1 |
| A331 | `world-assumptions` | world | monitoring (violation scenario) | the oracle over every check | tasks 5.1, 7.1 |
| A332 | `world-assumptions` | world | monitoring (violation scenario) | the oracle over the machine and fixture checks | tasks 2.3, 3.2, 7.1 |

## Risks / Trade-offs

- [Risk] A judge's entry is dropped and nothing notices, because a missing registration is silent. → Mitigation: `machines.nix` asserts that `attrNames config.fleetObligations` equals a literal list of the twelve keys, an oracle in the style of the flake-shape pin, so adding or removing a judge is a deliberate two-place edit. A mutant that deletes one registration fails it.
- [Risk] The fold's `functionTo` type checks every result list element, which costs evaluation on every machine check. → Mitigation: the cost point in D10; if it is outside noise, declare `failures` as `raw`. Measured at +7,296 thunks on `nixos-magnetite` with no CPU rise (task 2.5); kept.
- [Risk] `fleetPkgs` changes a runtime test's derivation through a path A330 does not cover. → Mitigation: the evaluations of task 4.1 found none; the oracle would name one, and the change lands only with its cause recorded. If the cause is the insecure-package allowance, the test is right to see the fleet's policy.
- [Risk] Collisions with the changes in flight. Another session holds `vm-tests/shared-reference-tree.nix`, `vm-tests/perses-greptimedb.nix`, `checks/fleet-alert.nix`, `checks/test-sizes.nix` and `clan/services/otel-collector/**`; this commit does not edit them, and tasks 4.4, 6.1 and 6.2 wait for them. `declare-host-user-relations-once` edits `omnigent-workers.nix:16-21`, which this change leaves untouched; `compose-hosts-from-cohesive-aspects` adds a mutant to `deploy-record-order.nix`, which now passes its cases to `judgeCases`.
- [Trade-off] Judges become twelve entries in twelve files instead of a list in one. Accepted for den alignment: the judge, its registration and its classes live together, and the literal key list keeps the set visible and makes every addition or removal deliberate.
- [Trade-off] The joint message omits judges that passed. Accepted.

## Migration Plan

N/A for deployment: no host's derivation changes, and no host deploys for this change.

The change lands as one commit on `main` (D10), accepted on one `just drv-diff` run with `drv-delta.txt`. The held runtime tests and the budget typing follow in `finish-fleet-package-set-and-budget-typing`, with its own oracle run. Rollback is a revert of the commit; nothing outside the repository holds state.

## Open Questions

1. Should `fleetObligations` move under `flake.fleet` beside `flake.fleet.hosts`, for den naming? This change keeps it outside `flake` (D1). Moving it later is a rename confined to the registrations and machines.nix.

## Resolved Questions

1. **The `controller` tag on stibnite.** Decided by the operator on 2026-11-26 in `type-the-fleet-host-registry` (its D12): renamed to `deployer-workstation` (`clan/inventory/machines.nix:100`). This change neither reads nor edits the tag.
