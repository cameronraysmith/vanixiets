## Context

The machine checks (`checks.x86_64-linux.nixos-<host>`, `checks.aarch64-darwin.darwin-<host>`, built by `modules/checks/machines.nix:154-172`) evaluate each host's configuration and are where every fleet-wide judge of that configuration runs. As of 2026-11-26:

- **Wiring by hand.** Eleven judges are bound (`machines.nix:44-54`), called (`:59-75`), tested (`:80-90`) and named in one message (`:93`) inside `withFleetObligations` (`:56-98`). A twelfth, `networkTargetObligations`, runs through `withNetworkTargets` (`:34-42`). Two judges apply to darwin only, chosen by `lib.hasSuffix "-darwin" machineSystems.${name}` (`:63`, `:67`).
- **Judge definitions**, each exporting `failures name hostConfig : [ string ]` under `flake.lib`:

  | Registry key (= current message name) | Defined at | Classes |
  |---|---|---|
  | `omnigentFleetObligations` | `lib/omnigent-fleet-obligations.nix:588` | nixos, darwin |
  | `deployRecordObligations` | `system/deploy-record.nix:143` | nixos, darwin |
  | `commitSigningObligations` | `lib/commit-signing.nix:273` (`failures` at `:185`) | nixos, darwin |
  | `resolverReloadObligations` | `darwin/resolver-reload.nix:74` | darwin |
  | `sopsBootInstallObligations` | `darwin/sops-boot-install.nix:85` | darwin |
  | `meshHostsObligations` | `system/mesh-hosts.nix:79` | nixos, darwin |
  | `harmoniaGcObligations` | `system/harmonia-gc.nix:75` | nixos, darwin |
  | `postgresqlBackupObligations` | `nixos/postgresql-backup.nix:386` | nixos, darwin |
  | `r2UsageObligations` | `nixos/r2-usage.nix:426` | nixos, darwin |
  | `fleetDeployer` | `lib/fleet-deployer.nix:360` (`failures` at `:348`) | nixos, darwin |
  | `nixEvalJobsObligations` | `lib/nix-eval-jobs-host.nix:188` | nixos, darwin |
  | `networkTargetObligations` | `lib/network-targets.nix:82` | nixos, darwin |

  `postgresqlBackupObligations` and `r2UsageObligations` run on darwin today and return `[ ]` there. Their class list keeps that behavior rather than narrowing it.
- **Judge fixture checks.** Ten files share the hand-copied `wrong`/`misjudges` shape: `checks/{darwin-resolver-reload,deploy-record-order,fleet-deployer-obligations,harmonia-gc-obligations,mesh-hosts-obligations,network-target-obligations,postgresql-backup-obligations,r2-usage,shared-vars-obligations,user-slice-guard-obligations}.nix`. Eight end in `pkgs.runCommand "<name>" { } "touch $out"`; `deploy-record-order.nix:92` and `r2-usage.nix:206` build real content. `perses-config.nix:294-340` judges by clause prefix and echoes each rejection. `flake.lib.mkEvalCheck` (`lib/mk-eval-check.nix:25`) runs nix-unit for seven test files.
- **Double system gates**: an outer `lib.optionalAttrs`/`lib.mkIf (system == "x86_64-linux")` (first number) and an inner `testSizes.checks = lib.optionalAttrs (system == "x86_64-linux")` (second number) in 25 files under `modules/checks/`: `commit-signing-key:274/278`, `darwin-machine-key-guard:16/20`, `darwin-mesh-resolver-flags:70/74`, `darwin-resolver-reload:97/101`, `deploy-record-order:69/73`, `fleet-deploy-request:378/382`, `fleet-deploy-resolve:27/31`, `fleet-deploy-watch:28/32`, `fleet-deployer-obligations:409/413`, `harmonia-gc-obligations:77/81`, `magnetite-zram-headroom:49/53`, `matrix-server-name-reset:19/23`, `mesh-hosts-obligations:108/112`, `network-target-obligations:102/106`, `omnigent-acp-spawn-env:42/46`, `postgresql-backup-obligations:121/125`, `pyrite-audio:9/13`, `pyrite-bluetooth:9/13`, `pyrite-desktop:29/33`, `pyrite-nix-concurrency:35/39`, `pyrite-wifi:9/13`, `renovate-allowed-commands:38/42`, `shared-vars-obligations:73/77`, `sops-correspondence:88/92`, `user-slice-guard-obligations:43/47`.
- **Extra nixpkgs instances**: eleven `nodePkgs` in `modules/vm-tests/` (`devloop-ingest:77`, `fleet-deployer:38`, `fleet-ingress:79`, `greptimedb-oom-order:42`, `greptimedb-pipeline:67`, `omnigent-worker-isolation:97`, `omnigraph-local-root:79`, `omnigraph-seed:49`, `omnigraph-state-directory-transitions:71`, `perses-greptimedb:55`, `shared-reference-tree:35`), `checks/omnigent-workers.nix:11-15`, and `checks/devin-worker.nix:71-77`, called by every home that check evaluates. The fleet instance is the perSystem `fleetPkgs` (`nixpkgs/base-defaults.nix:57-68`).
- **Channels overlay**: `nixpkgs/overlays/channels.nix:41-45` exports `patched`, which nothing in `modules/` or `pkgs/` reads; ADR-0017 Layer 1 and four documents describe it.
- **Untyped shapes**: `vanixiets.otelCollector.envelopeBudget` is `nullOr attrs` (`clan/services/otel-collector/flake-module.nix:165-174`), written at `:1722-1726` and `vm-tests/fleet-ingress.nix:2214-2221` and read by `flake.lib.otelEnvelope` (`lib/otel-envelope.nix:149-171,383-398`). `flake.lib.observabilityHosts` (`lib/observability-hosts.nix:38-156`) has no row schema.

Constraints carried from earlier decisions and not reopened here:
- The `testSizes` entries stay literal, beside their definitions (test-size design D1).
- Checks with too few runs keep `{ class = "medium"; measured = false; }` (test-size design D4).
- The literal check oracles stay literal: `checks/omnigent-workers.nix:594-600` (`hostMatrix`/`serverMatrix`), `checks/omnigent-acp-spawn-env.nix:19-22`, `checks/nix-builders-wiring.nix:11-12,43-55`, `checks/sops-correspondence.nix:35-62`.
- Scheelite stays `deferred` (`machines.nix:6`). Its only coverage is the fleet-wide sshd, zram and zerotier checks, which stay as they are.
- The perSystem name asserts (`machines.nix:99-123`) stay, because the flake-shape pin relies on them as its first layer.
- Two nixpkgs instances per system stay (`base-defaults.nix:16-18`), as does the channels layer apart from `patched`.
- `observabilityHosts` stays a static `flake.lib` table (fleet-ingress design D6).

## Goals / Non-Goals

**Goals:**
- Adding a host judge is one registration in the file that defines it, plus its key in the literal key list (design risks).
- Every judge applies to the host classes it declares. The machine check of a host in a class asserts every judge for that class and names each one that fails.
- Every judge-over-fixtures check reports a wrong case with its expected count, the actual count and the judge's messages.
- Fixture checks and runtime tests evaluate against the package set the hosts use.
- Nothing documents or exports a channel that nothing reads.
- The two shapes above are checked.
- Every NixOS, darwin and home toplevel and every `checks.{x86_64-linux,aarch64-darwin}` attribute keeps its derivation. Only `vmTests` may differ, and only where the oracle names a cause.

**Non-Goals:**
- Changing what any judge enforces, or its `flake.lib` export.
- Replacing the suffix tests inside `deploy-record.nix:148`, `harmonia-gc.nix:79` and `mesh-hosts.nix:84`; the host-registry change owns those.
- The poisoned `flake` argument at `checks/omnigent-workers.nix:16-21`; the host-user relations change replaces that guard.
- Moving `perses-config` or the nix-unit checks to the new constructor.
- `nixidy.nix:30` (a top-level output).
- The `nixpkgs` and `unstable` channel attributes.
- A behavioral capability: nothing a fleet user observes changes.

## Decisions

### D1: the registry is a flake-parts option outside `flake`

- **Choice**: `options.fleetObligations = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule { options = { classes = mkOption { type = listOf (enum [ "nixos" "darwin" ]); default = [ "nixos" "darwin" ]; }; failures = mkOption { type = functionTo (functionTo (listOf str)); }; }; }); default = { }; }` in a new `modules/lib/fleet-obligations.nix`. Each file in the table above adds `fleetObligations.<key> = { failures = <its judge>.failures; … }` beside its `flake.lib` export. machines.nix reads `config.fleetObligations`.
- **Rationale**: `flake.lib` is `lazyAttrsOf raw` (`lib/option.nix:3-6`), so a key defined from twelve files would collide. A `flake.*` option would add a flake output carrying functions only machines.nix calls. A flake-parts option merges per key, as den's policies do, and is not an output. Boundary: source-only and first-party. Nothing delivered to a host changes.
- **Alternatives considered**: (a) `flake.fleet.obligations` beside the planned `flake.fleet.hosts`. It would be an output, and it constrains the host-registry change to declare `flake.fleet.hosts` as a separate option path rather than a submodule-typed `flake.fleet`. (b) A literal list in machines.nix of `self.lib` names. It is still a hand list in a shared file.

### D2: the fold, and its message

- **Choice**: machines.nix's two mappers pass their class (`"nixos"` from `nixosConfigurations`, `"darwin"` from `darwinConfigurations`) to one function `withFleetObligations class name machineConfig toplevel`. The function concatenates `map (m: "${key}: ${m}") (entry.failures name machineConfig)` over the entries whose `classes` contain `class`, in `attrNames` order, and asserts that the result is `[ ]`. Its message is `Fleet obligations unmet on <name>:` followed by one line per message, then the host's own failing `assertions` messages as now. `withNetworkTargets` is deleted; `networkTargetObligations` is an entry.
- **Rationale**: one path for every judge; the class comes from the configuration set being mapped, not from a system string. An assertion leaves the asserted derivation unchanged (A332), so the machine checks keep their drvPaths. The function keeps its name: no spec requirement other than the database-backup one names it, and that one is restated in D9.
- **Alternatives considered**: (a) keep printing every judge with `[]`. That makes the message grow with the registry and does not help the reader. (b) Pass `class` into each judge. That changes twelve signatures and belongs to the host-registry change.

### D3: one judge-check constructor, for evaluation-time judges only

- **Choice**: new `modules/lib/judge-check.nix` exporting:
  - `flake.lib.judgeCases { name, judge, cases, assertions ? [ ] } : derivation -> derivation`.
    - `cases` is `attrsOf { problems : int; … }`. A case may carry its own `judge`, overriding the default, so files with two judges (`fleet-deployer-obligations`, `network-target-obligations`) pass one case set.
    - `assertions` is a list of `{ assertion; message; }` for invariants that are not cases (`fleet-deployer-obligations`'s `derivedTargets`, `r2-usage`'s cost-panel queries).
    - It returns the derivation unchanged when every case gives its count and every assertion holds. Otherwise it throws `<name>: <case>: expected <n> problems, the judge gave <m>: <messages as JSON>`, one line per wrong case, followed by the messages of any failing assertions.
  - `flake.lib.mkJudgeCheck pkgs args = judgeCases args (pkgs.runCommand args.name { } "touch $out")`.

  Eight files move to `mkJudgeCheck`. `deploy-record-order` and `r2-usage` wrap their existing derivation in `judgeCases`. `perses-config` and the seven `mkEvalCheck` users are left as they are. `mk-eval-check.nix`'s header gains one line: judge-over-fixtures checks use `mkJudgeCheck`.
- **Rationale**: the eight derivations are byte-identical to what they are now, and the other two keep their derivation, so drvPaths hold. Reporting expected and actual counts turns a failure into a diagnosis. The constructor never touches `testSizes`, so each file keeps its literal entry (test-size D1, D4).
- **Alternatives considered**: (a) migrate to `mkEvalCheck`. It runs nix-unit in a build, which changes every derivation and moves a cheap evaluation into a build. (b) a constructor that also emits the `testSizes` entry. D1 allows that only if both attributes stay literal, and a constructor returning a merged attrset would make every check file call it at the top level of `perSystem`. The gain is too small for that. (c) move `perses-config`. Its predicate is not a count, and its derivation would change.

### D4: the inner system gate goes

- **Choice**: in the 25 files above, `testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") { … }` becomes `testSizes.checks = { … }` inside the unchanged outer gate.
- **Rationale**: the outer gate already makes the whole value empty on other systems. The entry stays literal and keyed by the same name, so the structural test-size check sees the same key sets.
- **Alternatives considered**: drop the outer gate instead. That would emit the check value on every system.

### D5: fixture checks and runtime tests read `fleetPkgs`

- **Choice**:
  - The eleven runtime-test modules and `checks/omnigent-workers.nix` take `fleetPkgs` from their `perSystem` arguments and replace the local import with it. Every use of `nodePkgs` keeps its name, as a `let` alias `nodePkgs = fleetPkgs;`, so the test bodies are not edited.
  - `checks/devin-worker.nix` replaces `probePkgs` with an attribute set built once in its `let`, `fleetPkgsBySystem = lib.genAttrs [ "x86_64-linux" "aarch64-darwin" ] (s: withSystem s ({ fleetPkgs, ... }: fleetPkgs));`, read as `fleetPkgsBySystem.${system}`.
  - `shared-reference-tree.nix:35-38` keys its instance on `pkgs.stdenv.hostPlatform.system`, which equals `system` there. It takes `fleetPkgs` too.
- **Rationale**: a lazy attribute set is evaluated once per key, so each system's instance is shared by every home the check evaluates. Today `probePkgs` builds a new instance per call. `fleetPkgs` has the same overlay (`config.flake.overlays.default`, the value `self.overlays.default` names) and adds `allowUnfree` where it was missing, plus `permittedInsecurePackages`. In the locked nixpkgs those keys decide only whether evaluating a marked package throws (A330). Boundary: vendored-versus-first-party. nixpkgs and the NixOS test framework are used through their public `import`/`node.pkgs` interfaces and are not patched.
- **Declared drvPath effect**: the runtime tests built from the eleven modules may differ; these are the `may-change` entries of D10's allow-list. Every other dumped attribute must be identical, including `checks.*.omnigent-workers`, `checks.x86_64-linux.devin-worker`, and every `vmTests` attribute not in that list. A330 predicts no difference even in `vmTests`, so none is declared `changed`. Any difference there is accepted only with its cause named.
- **Alternatives considered**: (a) the perSystem `pkgs`. It lacks `flake.overlays.default` (`base-defaults.nix:16-18`). (b) a `withSystem` call inside each `evalHome` call. Flake-parts memoises `withSystem` per system, but a single `let` binding makes the sharing visible in the file and does not depend on that memoisation.

### D6: drop `patched`, amend ADR-0017

- **Choice**: delete `channels.nix:40-45` and the header line at `:10`. Add a dated "Amendment (2026-11-26)" section to ADR-0017: Layer 1 no longer exports `patched`. Nothing read it, and reading it would import a derivation's output during evaluation. A fix from an upstream pull request is applied as a per-package `overrideAttrs` that adds the patch with `fetchpatch` in an overlay; `stable` fallbacks are unchanged. Update `architecture/architecture.md:168,329`, `requirements/functional-hierarchy.md:172,206`, `requirements/usage-model.md:305`, and the guide's `patched` steps in `guides/handling-broken-packages.md` to match. ADR-0017's Decision text is left as written, and the amendment supersedes it in place.
- **Rationale**: the attribute is lazy (A331), so removing it changes no derivation. The documents are the only thing that still uses it. Boundary: source-versus-delivered. The ADR and guides are delivered as the docs site, so the edit is verified by building it (`just docs-build`), not by reading the source.
- **Alternatives considered**: keep `patched` with a non-empty patch list. That is a feature nobody asked for, and it carries an evaluation-time build.

### D7: `envelopeBudget` becomes a submodule

- **Choice**: `type = lib.types.nullOr (lib.types.submodule { options = { storeUrl = mkOption { type = str; }; notifiedUnits = mkOption { type = attrsOf (listOf str); }; databases = mkOption { type = attrsOf str; }; }; });`, with the description unchanged apart from dropping the inline shape.
- **Rationale**: both writers set exactly these three. The merged value has the same attributes and values, so `otelEnvelope`'s rendered script is unchanged and magnetite's toplevel and `vmTests.x86_64-linux.fleet-ingress` keep their derivations. A writer that misspells a field now fails evaluation. Boundary: first-party option on a vendored service. Only the first-party option type changes.
- **Alternatives considered**: `attrsOf anything` with an assertion. It is weaker, and the error arrives later.

### D8: a validator for `observabilityHosts`, run in an existing check

- **Choice**: `flake.lib.observabilityHostProblems : table -> [ string ]` in `lib/observability-hosts.nix`. It returns one message per unknown or missing field, and per value of the wrong type:
  - `platform` must be `"nixos"` or `"darwin"`.
  - `collect`, `alwaysOn`, `textfile`, `agentTelemetry` and `langfuse` must be booleans.
  - `smartDevices` and `notifiedUnits` must be lists of strings.
  - `agentSpanQueueMiB` must be a positive integer.

  `checks/otel-collector-config.nix` wraps its existing derivation in `judgeCases` with the real table (0 problems) and one mutant per rule (1 problem each). The `agent` helper and its defaults are unchanged. Rules that relate fields (`langfuse` requires `agentTelemetry`, `platform` equals the inventory class) stay where they are asserted now.
- **Rationale**: "typed" without an option fixpoint, as fleet-ingress D6 requires. The readers do not run it, so reading a row costs what it does now. The check already reads the table and keeps its derivation. Boundary: source-only.
- **Alternatives considered**: (a) validate on read. Every reader would pay for every row. (b) a new check. That adds one more key and one more size entry for one assertion.

### D9: spec deltas

- **Choice**:
  - MODIFIED `database-backup-interface` "A host's backup set is pinned by a fleet obligation": the judge is registered as `fleetObligations.postgresqlBackupObligations`, so it is asserted on every `nixos-<host>` and `darwin-<host>` check. The scenarios are unchanged.
  - ADDED two `fleet-ingress-interface` requirements: D7 and D8.
  - New `fleet-obligation-registry-interface` (D1–D4) and `fleet-package-set-interface` (D5, D6).
  - `world-assumptions` A330–A332.
- **Archive order**: `database-backup-interface` is not yet in `openspec/specs/`; it arrives when `back-up-postgresql-off-host` archives. This change archives after that one, or its MODIFIED delta has nothing to apply to.
- **Not modified**: `devloop-collection-interface:322` and `commit-signing-key-interface:126` say "`modules/checks/machines.nix` SHALL assert", which stays true. `delegate-fleet-deploys`'s design `:154` names `withFleetObligations`, which keeps its name (D2). The fleet-deploy-delegation-interface scenario ("its `darwin-<host>` machine check fails evaluation naming the problem") still holds.

### D10: the oracle and the cost points

- **Choice**:
  - Each group lands only after `just drv-diff <base> <head> <allow>` (from `establish-refactor-oracle`) passes. The allow-list is empty for every group except the runtime-test group. Its allow-list names, as `may-change`, each runtime test the eleven modules define, one exact attribute path per entry:
    - `vmTests.x86_64-linux.devloop-ingest`, `vmTests.x86_64-linux.devloop-ingest-reconcile`
    - `vmTests.x86_64-linux.fleet-deployer`
    - `vmTests.x86_64-linux.fleet-ingress`, `vmTests.x86_64-linux.fleet-ingress-outage`
    - `vmTests.x86_64-linux.greptimedb-oom-order`, `vmTests.x86_64-linux.greptimedb-pipeline`
    - `vmTests.x86_64-linux.omnigent-worker-isolation`, `vmTests.aarch64-linux.omnigent-worker-isolation`
    - `vmTests.x86_64-linux.omnigraph-local-root`, `vmTests.x86_64-linux.omnigraph-seed`, `vmTests.x86_64-linux.omnigraph-state-directory-transitions`
    - `vmTests.x86_64-linux.perses-greptimedb`
    - `vmTests.x86_64-linux.shared-reference-tree`, `vmTests.x86_64-linux.shared-reference-tree-migration`
  - The entries are `may-change`, not `changed`, because A330 predicts no difference. No `checks` attribute embeds a runtime test, so none is added. If a runtime test is added to or renamed in those modules before this group lands, the list is regenerated from `nix eval --json '.#vmTests.<system>' --apply builtins.attrNames` on base.
  - One cost point is measured with `just eval-cost`, interleaved base/candidate: `checks.x86_64-linux.nixos-magnetite.drvPath` for the registry fold, where any change should be within noise.
  - Two cost points are recorded but not gated: `checks.x86_64-linux.devin-worker.drvPath` and one runtime test's `.drvPath` (`vmTests.x86_64-linux.greptimedb-pipeline`). Lower allocation is expected [INFERENCE: one nixpkgs instance fewer per evaluation].
- **Rationale**: a refactor declared neutral is accepted on the cross-revision oracle, not on `just eval-identity`, which compares two evaluators at one revision.

## Risks / Trade-offs

- [Risk] A judge's entry is dropped and nothing notices, because a missing registration is silent. → Mitigation: `machines.nix` asserts that `attrNames config.fleetObligations` equals a literal list of the twelve keys, an oracle in the style of the flake-shape pin, so adding or removing a judge is a deliberate two-place edit. A mutant that deletes one registration fails it.
- [Risk] The fold's `functionTo` type checks every result list element, which costs evaluation on every machine check. → Mitigation: the cost point in D10; if it is outside noise, declare `failures` as `raw`.
- [Risk] `fleetPkgs` changes a runtime test's derivation through a path A330 does not cover. → Mitigation: the oracle names it; the runtime-test group lands only with each changed `vmTests` attribute's cause recorded. If the cause is the insecure-package allowance, the test is right to see the fleet's policy.
- [Risk] Merge collisions. This change lands after `type-the-fleet-host-registry` and `stop-reading-other-hosts-configs`, and before `declare-host-user-relations-once` and `compose-hosts-from-cohesive-aspects`. `type-the-fleet-host-registry` edits `machines.nix:56-97` (its suffix tests at `:63`, `:67`). `stop-reading-other-hosts-configs` edits five files this change also edits: `checks/otel-collector-config.nix` (`:96`), `nixos/postgresql-backup.nix` (`:136`), `nixos/r2-usage.nix` (`:236`), `lib/fleet-deployer.nix` (`:99-105`, `:305-310`) and `lib/commit-signing.nix` (`:166`). `compose-hosts-from-cohesive-aspects` adds a mutant to `deploy-record-order.nix` and splits `otel-collector/flake-module.nix`. `declare-host-user-relations-once` edits `omnigent-workers.nix:16-21`. → Mitigation: this change's machines.nix group removes the two suffix tests outright, so the registry's edit there is dropped on rebase. In the four judge files, this change edits only the judge definition and its new registration entry (`postgresql-backup.nix:386`, `r2-usage.nix:426`, `fleet-deployer.nix:360`, `commit-signing.nix:273` before the rebase), away from the lines `stop-reading-other-hosts-configs` edits; after the rebase the judges are located by name, since those line numbers shift. `checks/otel-collector-config.nix` is the one real overlap: D8 wraps its whole derivation in `judgeCases`, so the wrap is reapplied by hand over the rebased file, keeping that change's edit at `:96`. The other files are touched at disjoint lines, and a rebase resolves them; the oracle runs again after each rebase.
- [Trade-off] Judges become twelve entries in twelve files instead of a list in one. Accepted for den alignment: the judge, its registration and its classes live together, and the literal key list keeps the set visible and makes every addition or removal deliberate.
- [Trade-off] The joint message omits judges that passed. Accepted.

## Migration Plan

N/A for deployment: no host's derivation changes, and no host deploys for this change.

Landing order, each group one pull request passing `just drv-diff` with its allow-list:
1. Registry and fold (D1, D2): `fleet-obligations.nix`, the twelve registrations, machines.nix.
2. Judge-check constructor and gates (D3, D4).
3. Package set (D5), with the `vmTests` allow-list.
4. Channels and docs (D6).
5. Shapes (D7, D8).

Groups 2–5 are independent of each other and of 1. Rollback is a revert of the group's commit; nothing outside the repository holds state.

## Open Questions

1. **[operator]** Should stibnite's `controller` inventory tag (`clan/inventory/machines.nix:112`), which means "deployment controller" there and "ZeroTier controller" on cinnabar (`:29`), be renamed to `deployer-workstation`? It depends on whether `clan machines update --tags controller` is part of your habits. This change does not read or edit the tag; it records the question because the den-ready project carries it.
2. Should `fleetObligations` move under `flake.fleet` once the host registry exists, for den naming? This change keeps it outside `flake` (D1). Moving it later is a rename confined to the registrations and machines.nix.
