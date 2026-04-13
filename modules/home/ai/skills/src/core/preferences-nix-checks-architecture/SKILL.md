---
name: preferences-nix-checks-architecture
description: >
  Design hermetic, cacheable nix flake checks for comprehensive repository validation.
  Use when structuring checks in flake-parts modules, wrapping language tools as pure
  derivations, designing nix-unit structural invariants, or planning NixOS VM integration
  tests. Also load when the 8-category check taxonomy (format, secrets-scan, lint,
  type-check, unit-test, integration/e2e, nix-infrastructure, build/eval) is relevant.
---

# Nix checks architecture

This skill covers the design of hermetic, cacheable nix flake checks that validate a repository across its full surface area.
The approach treats every check as a pure nix derivation, composable through flake-parts modules and distributable across CI workers.

## Check taxonomy

Eight canonical categories classify the validation surface of a nix-based repository.
Each category targets a distinct failure mode and has characteristic cacheability properties.
The categories are ordered roughly by cost: earlier categories are cheaper to run and should fail fast, while later categories are more expensive and validate deeper properties.

*Format* covers treefmt-equivalent enforcement of code formatting.
Formatters run as a single derivation that fails if any file would be reformatted.
This catches whitespace, import ordering, and style drift before any semantic analysis.
Formatting checks are typically the fastest to run and should be the first to fail in a pipeline, since formatting violations are trivial to fix and indicate the contributor has not run the formatter locally.

*Secrets-scan* covers gitleaks-equivalent detection of leaked credentials, API keys, and tokens in source files.
The derivation wraps a scanner tool over the full source tree, so it invalidates on any source change.
Unlike most other categories, secrets scanning has no language-specific variant; a single gitleaks derivation covers the entire repository.
The cost of a false negative (leaked credential) is severe enough that running this check on every change, despite its full-tree cache invalidation, is warranted.

*Lint* covers language-specific static analysis beyond formatting: clippy for Rust, ruff for Python, eslint or biome for JavaScript/TypeScript.
Linters catch correctness issues, unused imports, suspicious patterns, and style violations that formatters do not address.
The distinction between formatting and linting matters for cacheability: a formatting check depends on source text layout, while a lint check depends on semantic content.
Changing a comment may invalidate the formatter but leave the linter cached.

*Type-check* covers static type system validation: `cargo check` for Rust, basedpyright for Python, `tsc --noEmit` for TypeScript.
Python type checking uses basedpyright rather than mypy.
Wrapping basedpyright as a nix derivation requires running it inside a uv2nix-built virtual environment so that all type stubs and dependencies are available.
Type checking is typically more expensive than linting but cheaper than running tests, and it catches a different class of errors: interface mismatches, missing fields, incorrect return types, and violations of type-level invariants.

*Unit-test* covers workspace-level and per-package test suites: `cargo nextest`, pytest, vitest.
For Python, wrapping pytest as a nix check similarly requires the uv2nix virtual environment.
Per-crate or per-package isolation via `lib.genAttrs` allows targeted debugging without running the full workspace suite.
Unit tests provide the highest ratio of confidence-per-second for behavioral correctness: they exercise code paths with controlled inputs and assert on outputs.
When designing check derivations for unit tests, the granularity decision (one derivation per workspace vs one per package) trades debugging convenience against build system overhead.

*Integration/e2e* covers end-to-end validation: Playwright browser automation, NixOS VM tests, multi-service integration tests.
These checks tend to be the most resource-intensive and have the longest runtimes.
NixOS VM tests require `kvm` and `nixos-test` sandbox features.
Integration tests validate properties that unit tests cannot: cross-service communication, database migrations, browser rendering, and system-level behavior.
The cost of running these checks means they are often fan-out candidates for CI distribution rather than local `nix flake check` targets.
See `references/nixos-vm-tests.md` for the full framework.

*Nix-infrastructure* covers nix-unit tests on flake structure and declarative invariants.
These validate properties like "every package has a corresponding check" or "all machines in the fleet have consistent naming conventions."
Infrastructure invariants are unique among the categories because they test the build system itself rather than the software it produces.
They are cheap to evaluate (pure nix expression evaluation, no building) and catch structural drift that would otherwise go unnoticed until a deployment fails.
See `references/nix-unit-invariants.md` for the test case template and design pattern.

*Build/eval* covers the actual package derivations.
A successful `nix build` is itself a check that the derivation graph is well-formed and all build phases complete.
`nix flake check` evaluates all checks and packages for the current system.
Build checks are implicit: every derivation in the `packages` output is a build check.
Evaluation checks (via `nix flake check` or `nix eval`) validate that the nix expression graph is well-formed without building, catching infinite recursion, missing attributes, and type errors in module options.

When a category does not apply to a repository, N/A is a valid and authorized state.
Do not manufacture speculative future coverage for categories that have no current relevance.
A Rust-only project has no Python type-check category.
A library with no network services has no NixOS VM test category.
Recording N/A explicitly communicates that the absence is intentional rather than an oversight.


## Composition rules

Three target-state values classify how a check derivation integrates with the build pipeline.
These values are not mutually exclusive in all combinations, and understanding their composition is necessary for designing checks that work correctly in both local and CI contexts.

`flake-check-native` means the derivation runs under `nix flake check`.
This is the default for checks that are pure, hermetic, and reasonably fast.
The derivation appears in `checks.<system>.<name>` and evaluates alongside all other flake checks.
Local development uses `nix flake check` as the primary validation command, so flake-check-native checks form the core feedback loop.
The tradeoff is that `nix flake check` evaluates all checks sequentially on a single machine, so expensive checks slow the entire pipeline.

`fan-out` means the derivation is exposed as a separate attribute for parallel execution.
Tools like nix-fast-build and buildbot-nix can distribute fan-out checks across workers, evaluating and building each independently.
Fan-out checks still appear under `checks.<system>` but are designed for granular scheduling rather than monolithic evaluation.
nix-fast-build evaluates derivations in parallel and distributes builds across remote builders, making it the natural choice for CI pipelines with multiple workers.
buildbot-nix goes further by evaluating the flake once, then scheduling individual derivation builds as independent buildbot steps with their own status reporting and retry logic.

`effect` means the operation has side effects: deploying, publishing, pushing artifacts, or mutating external state.
Effect operations never belong in `nix flake check` because they are not hermetic and their success depends on external state.
Deployment scripts, cache uploads, container registry pushes, and notification triggers are all effects.
They run in CI pipelines as post-check steps gated by the success of pure checks, but they are not themselves checks.

`flake-check-native` and `fan-out` compose naturally.
A check can be both: it runs under `nix flake check` locally and fans out in CI.
`effect` is mutually exclusive with both because side effects break the purity contract.
The composition table is straightforward: a derivation that is both flake-check-native and fan-out runs locally via `nix flake check` and in CI via nix-fast-build or buildbot-nix.
A derivation that is fan-out only (not flake-check-native) is too expensive for local runs but still distributes in CI.
This is appropriate for NixOS VM tests and Playwright e2e tests that require specialized hardware or take minutes to complete.


## Derivation purity principle

Every check must be a pure nix derivation: cacheable, reproducible, and content-addressed.
No impure wrappers around shell scripts.
Even security scanners like gitleaks run as `pkgs.runCommand` derivations that take the source tree as input and fail the build if violations are detected.

The pre-commit check anti-pattern illustrates why purity at the individual check level matters.
A monolithic `pre-commit.check` derivation bundles formatting, linting, and scanning into a single derivation.
When any source file changes, the entire pre-commit derivation invalidates and reruns all bundled checks from scratch.
The bundled derivation cannot cache intermediate results because it is a single build step.

Setting `pre-commit.check.enable = false` and running treefmt, gitleaks, and linters as independent check derivations yields finer cache granularity.
If only a Rust file changed, the treefmt check for Rust invalidates while the Python lint check (which depends only on Python source files via source filtering) remains cached.
The gitleaks check invalidates because it depends on the full tree, but it runs independently and does not force the linter to rerun.
Independent derivations also produce independent build logs, making failures easier to diagnose: a CI log that says "gitleaks-check failed" is immediately actionable, whereas "pre-commit-check failed" requires reading the log to determine which bundled tool failed.

Beyond cacheability, independent derivations enable fan-out scheduling.
CI systems can distribute independent check derivations across multiple workers, running them in parallel.
A monolithic pre-commit derivation forces serial execution of all bundled tools on a single machine.

See `references/derivation-patterns.md` for per-category derivation recipes.


## Source filtering for cacheability

Derivation hashes should change only when semantically relevant source content changes.
Source filtering is the primary mechanism for achieving this.

`builtins.path` with a fixed `name` parameter produces content-addressed store paths.
Without a fixed name, the store path includes the filesystem path, causing unnecessary rebuilds when the checkout location changes.
A developer checking out the same repository to `/home/alice/project` and `/home/bob/project` would get different store paths for identical source content.
The `filter` parameter excludes files irrelevant to the derivation (documentation, tests, CI config) so that changes to those files do not invalidate the build cache.
A well-designed filter is the single most impactful optimization for check cacheability because it determines which changes trigger rebuilds.

`crane.filterCargoSources` applies Rust-specific filtering: it includes `*.rs` files, `Cargo.toml`, `Cargo.lock`, and build scripts while excluding tests, benches, and examples.
This is the standard filter for crane-based Rust builds.
Combining `crane.filterCargoSources` with `builtins.path` (for the fixed name) is the idiomatic pattern: `builtins.path { path = craneLib.filterCargoSources ./.; name = "rust-source"; }`.

`lib.fileset.toSource` combined with `lib.fileset.unions` provides fine-grained file set composition for JavaScript packages and other ecosystems.
You declare exactly which files and directories constitute the source, and the resulting store path reflects only those contents.
This is more explicit than `builtins.path` with a filter function because the inclusion list is declarative rather than imperative.
Adding a new file type to the project requires adding it to the union, which is a visible code change rather than a silent filter rule.

Lockfile-based dependency fetchers like `bun2nix.fetchBunDeps` and uv2nix workspace loading derive their store paths from lockfile contents.
When the lockfile does not change, the dependency fetch is a cache hit regardless of source changes.
This separation of dependency resolution from source compilation is the foundation of the two-phase build pattern used across all language ecosystems.


## Shared artifact caching

Several patterns allow expensive intermediate artifacts to be computed once and shared across multiple checks.

Crane's `buildDepsOnly` produces a single compiled-dependencies artifact that `cargoClippy`, `cargoNextest`, and `buildPackage` all share.
Compiling dependencies is the most expensive phase of a Rust build, and sharing this artifact across clippy, tests, and the final build avoids tripling the compile time.
The artifact is keyed on `Cargo.toml` and `Cargo.lock` contents, so adding a source file or changing implementation code does not trigger dependency recompilation.
Only adding, removing, or updating a dependency invalidates this artifact.

The `passthru.tests` pattern attaches test derivations to a package.
A package's `passthru.tests.unit` and `passthru.tests.e2e` attributes are derivations that can be referenced from the flake's `checks` output.
This keeps the test definition co-located with the package while exposing it for CI.
The pattern supports the relational invariant from nix-unit: TC-006 can verify that every package's `passthru.tests` attributes are wired into the checks output.

Per-crate isolation via `lib.genAttrs` generates one check derivation per crate in a workspace.
This allows debugging a single failing crate without rebuilding or retesting the entire workspace.
The per-crate derivations share the same `buildDepsOnly` artifact.
In CI, per-crate derivations enable finer-grained fan-out: if only one crate's source changed, only that crate's tests need to rebuild.

See `references/derivation-patterns.md` for concrete nix expression skeletons.


## Relational invariants via nix-unit

Beyond testing that individual derivations build successfully, nix-unit can enforce structural relationships between flake outputs.
Structural invariants operate at the meta-level: they test the shape of the build system rather than the behavior of the software it produces.

The canonical example is the TC-006 pattern: every package in `packages.<system>` has a corresponding entry in `checks.<system>`, enforced by a nix expression that enumerates both attribute sets and asserts coverage.
An explicit exclusion list documents packages that intentionally lack a check (the `default` alias, release meta-packages, per-crate test derivations that are themselves checks).
The exclusion list is itself a reviewable artifact: adding a package to it requires a justification comment, which means the decision to skip test coverage is deliberate and visible in code review.

Structural validation extends to other flake output relationships.
Does every system have a devShell?
Is a formatter configured?
Do infrastructure-specific outputs (machine configurations, deployment specs) satisfy naming conventions?
For declarative infrastructure repositories like vanixiets, invariants validate clan inventory consistency, secrets tier separation, and machine registry completeness, properties that are not exercised by building any single package.

The value of invariants is highest for cross-cutting relationships between independently-defined outputs.
If a property is guaranteed by the nix module system's type checking, an invariant test is redundant.
If it depends on conventions that the type system cannot enforce, an invariant catches drift.
A practical heuristic: if two developers can independently add outputs that should be related (a package and its test, a machine config and its inventory entry), an invariant ensures the relationship holds.

See `references/nix-unit-invariants.md` for the full test case template and guidance on when invariants add value.


## NixOS VM tests

NixOS VM tests run full virtual machines with real systemd services, network stacks, and multi-machine topologies.
They are appropriate for validating NixOS module interaction, service lifecycle, network configuration, and multi-machine coordination.
The decision to use a VM test rather than a pure derivation check should be deliberate: VM tests are the right tool when the property under test requires a running init system, real network connectivity between services, or multi-machine coordination.

VM tests require `kvm` and `nixos-test` sandbox features and are significantly more resource-intensive than pure derivation checks.
A single VM test boots one or more QEMU virtual machines, each running a full NixOS system with systemd, networking, and the configured services.
Multi-machine tests use VLANs implemented via `vde_switch` for network isolation, enabling tests of client-server architectures, mesh networks, and distributed systems.

The test framework provides a Python driver API for interacting with VMs.
The driver communicates with each VM through a virtio-console backdoor rather than the network, so test commands work even when the VM's networking is misconfigured.
Common operations include waiting for systemd units, asserting on command output, transferring files, and taking screenshots for debugging.

Properties that benefit from VM testing include NixOS module correctness (does enabling a service produce the expected systemd units and firewall rules?), multi-service integration (does the reverse proxy correctly route to backend services?), secrets decryption (do sops-encrypted secrets decrypt correctly during system activation?), and network topology (do VPN mesh nodes discover each other?).

Properties that do not benefit from VM testing include pure function behavior, data transformation logic, and CLI tool output, all of which are better served by unit-test or build/eval checks.

clan-core extends the framework with shared test runners, container-based alternatives to QEMU for lighter weight testing, helpers for secrets and evaluation-only checks, and VM image minification for faster boot times.

See `references/nixos-vm-tests.md` for the complete framework architecture, driver API, debugging workflow, and clan-core extensions.


## Check module organization in flake-parts

Checks are organized as flake-parts modules, one per check category or logical group.
A repository might have `checks/gitleaks.nix`, `checks/e2e.nix`, `checks/nix-unit.nix`, and `checks/rust.nix` (combining clippy, nextest, and build for a Rust workspace).
The grouping decision balances module count against cohesion: a Rust workspace with clippy, nextest, and build checks benefits from colocating them in a single module because they share `commonArgs` and `cargoArtifacts`, while gitleaks and treefmt are independent enough to warrant their own modules.

import-tree auto-discovers these modules from the directory structure, so adding a new check module requires no manual wiring in `flake.nix`.
Each module defines its check derivations under `perSystem.checks.<name>`.
The convention is to name check attributes with a language or tool prefix: `rust-clippy`, `rust-nextest`, `python-typecheck`, `python-test`, `js-typecheck`, `gitleaks`, `treefmt`.
Prefixed names sort together in `nix flake check` output and make it clear which language ecosystem a failure originates from.

The devShell `inputsFrom` pattern connects checks to the development environment:

```nix
devShells.default = pkgs.mkShell {
  inputsFrom = builtins.attrValues self'.checks;
};
```

This makes all native build inputs from check derivations available in the dev shell.
A developer entering the shell has all formatters, linters, type checkers, and test runners on their PATH without manually listing them.
The pattern ensures that the development environment stays synchronized with the check suite: adding a new check that requires a new tool automatically makes that tool available in the dev shell.

When a check requires inputs that are inappropriate for the dev shell (for example, a large VM test dependency), exclude it from `inputsFrom` and add its tool dependencies to the dev shell explicitly.
The `inputsFrom` pattern pulls `nativeBuildInputs` and `buildInputs`, so be aware of what each check declares.


## Cross-references

The following skills provide complementary context:

- `preferences-nix-development` covers flake conventions, module structure, and derivation best practices that underpin check derivation design.
- `preferences-validation-assurance` provides the theoretical foundations for test design: the severity criterion (would this test fail under plausible incorrect implementations?) and the confidence promotion chain (how evidence accumulates across check categories). The 8 check categories in this skill map to confidence levels in the validation assurance framework: format and lint provide low confidence (style correctness), type-check and unit-test provide medium confidence (behavioral correctness), integration/e2e and nix-infrastructure provide high confidence (system-level correctness), and build/eval provides baseline confidence (the code compiles).
- `preferences-algebraic-laws` covers property-based testing approaches for generating high-severity evidence, relevant when designing checks that go beyond example-based assertion. Property-based tests can be wrapped as nix check derivations using the same patterns described in `references/derivation-patterns.md`.
- `preferences-production-readiness` covers CI/CD pipeline integration, progressive delivery, and how checks gate deployment. The composition rules in this skill (flake-check-native, fan-out, effect) align with the production readiness stages: local development uses flake-check-native, CI uses fan-out, and deployment uses effects gated by check success.
