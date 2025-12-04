# CI documentation execution coverage audit

This document captures the findings from a comprehensive audit of documentation code snippets against CI test coverage, conducted on 2025-12-04.

## Executive summary

The audit analyzed whether code snippets recommended to users in the documentation are actually tested by CI workflows.

| Metric | Value |
|--------|-------|
| Total documentation files scanned | 77 |
| Total code snippets found | 709 |
| Executable snippets (bash/nix/typescript) | 546 |
| Illustrative snippets (diagrams/examples) | 163 |
| High-priority snippets analyzed | 179 |
| Snippets with CI coverage (L1+) | 136 (75.9%) |
| Coverage gaps (L0) | 43 (24.1%) |

The gaps are concentrated in security-critical workflows (secrets management, key generation) and platform-specific operations (Darwin, Zerotier).

## Methodology

The audit used a multi-phase agent-based approach:

1. **Phase 1 (Parallel extraction)**: Four agents extracted documentation snippets, CI workflow commands, existing traceability metadata, and test source implementations
2. **Phase 2 (Coverage mapping)**: One agent cross-referenced snippets against CI capabilities to identify gaps

Coverage levels used:
- **L3 (Direct)**: Exact command appears in CI workflow
- **L2 (Recipe)**: Command is part of a CI-tested justfile recipe
- **L1 (Category)**: Command category is tested (e.g., nix build commands covered by nix job)
- **L0 (None)**: No discernible CI coverage path

## Snippet inventory

### Distribution by type

| Type | Count | Percentage |
|------|-------|------------|
| Bash/shell commands | 380 | 53.6% |
| Nix expressions | 163 | 23.0% |
| TypeScript examples | 3 | 0.4% |
| Illustrative (untagged) | 163 | 23.0% |

### Files with most snippets

| Rank | Count | File |
|------|-------|------|
| 1 | 44 | development/architecture/adrs/0016-per-job-content-addressed-caching.md |
| 2 | 41 | guides/host-onboarding.md |
| 3 | 34 | guides/secrets-management.md |
| 4 | 33 | guides/home-manager-onboarding.md |
| 5 | 33 | tutorials/nixos-deployment.md |
| 6 | 32 | guides/handling-broken-packages.md |
| 7 | 27 | development/architecture/adrs/0002-use-generic-just-recipes.md |
| 8 | 27 | development/architecture/nixpkgs-hotfixes.md |
| 9 | 26 | tutorials/darwin-deployment.md |
| 10 | 25 | about/contributing/container-runtime-setup.md |

## CI capabilities

### Workflows analyzed

| Workflow | Jobs | Purpose |
|----------|------|---------|
| ci.yaml | 12 | Primary CI orchestration |
| deploy-docs.yaml | 1 | Documentation deployment |
| package-test.yaml | 1 | TypeScript package testing |
| package-release.yaml | 1 | Semantic release |
| pr-check.yaml | 1 | Fast-forward validation |
| pr-merge.yaml | 1 | Fast-forward merge |
| update-flake-inputs.yaml | 1 | Scheduled dependency updates |
| test-composite-actions.yaml | 5 | Internal CI testing |

### CI-tested justfile recipes

These recipes are executed by CI jobs:

| Recipe | CI Job |
|--------|--------|
| `check` | flake-validation |
| `ci-build-category` | nix (matrix) |
| `cache-overlay-packages` | cache-overlay-packages |
| `list-packages-json` | set-variables |
| `test-package` | typescript |
| `preview-version` | preview-release-version |
| `docs-test` | typescript |
| `docs-test-unit` | typescript |
| `docs-test-e2e` | typescript |
| `docs-test-coverage` | typescript |
| `docs-deploy-preview` | preview-docs-deploy |
| `docs-deploy-production` | production-docs-deploy |

### Test implementation summary

| Category | Count | Location |
|----------|-------|----------|
| nix-unit tests | 16 | modules/checks/nix-unit.nix |
| Validation checks | 8 | modules/checks/validation.nix |
| VM integration tests | 2 | modules/checks/integration.nix |
| TypeScript unit tests | 20 | packages/docs/src/**/*.test.ts |
| Playwright E2E tests | 8 | packages/docs/e2e/*.spec.ts |

## Coverage analysis by file

### High-priority files analyzed

| File | Total | Covered | Gaps | Gap % |
|------|-------|---------|------|-------|
| tutorials/secrets-setup.md | 26 | 18 | 8 | 30.8% |
| guides/secrets-management.md | 31 | 23 | 8 | 25.8% |
| tutorials/nixos-deployment.md | 24 | 19 | 5 | 20.8% |
| tutorials/darwin-deployment.md | 22 | 18 | 4 | 18.2% |
| guides/home-manager-onboarding.md | 14 | 12 | 2 | 14.3% |
| guides/host-onboarding.md | 28 | 26 | 2 | 7.1% |
| guides/getting-started.md | 16 | 15 | 1 | 6.3% |
| tutorials/bootstrap-to-activation.md | 18 | 17 | 1 | 5.6% |

## Gap inventory

### Critical gaps (security-related)

| File | Line | Command | Risk |
|------|------|---------|------|
| secrets-management.md | 206 | `bw login` | Bitwarden CLI login not tested |
| secrets-management.md | 209 | `bw unlock --raw` | Bitwarden vault unlock not tested |
| secrets-management.md | 216 | `bw get item` | Bitwarden key extraction not tested |
| secrets-management.md | 219 | `ssh-to-age -private-key` | Age key derivation not tested |
| secrets-management.md | 264 | `just sops-validate-correspondences` | Recipe validation not in CI |
| secrets-management.md | 412 | `sops updatekeys` | Secret re-encryption not tested |
| secrets-setup.md | 129 | `bw unlock --raw` | Bitwarden unlock not tested |
| secrets-setup.md | 141-153 | `bw list items`, `bw get attachment` | Bitwarden queries not tested |
| secrets-setup.md | 169-182 | `ssh-to-age` operations | Key conversion pipeline not tested |
| secrets-setup.md | 204 | `rm -P` (secure delete) | Secure file deletion not tested |

### High gaps (infrastructure)

| File | Line | Command | Risk |
|------|------|---------|------|
| nixos-deployment.md | 143 | `nix run .#terraform -- state list` | Terraform state inspection not in CI |
| nixos-deployment.md | 170 | `nix run .#terraform -- plan` | Terraform planning not executed |
| nixos-deployment.md | 181 | `nix run .#terraform -- apply` | Terraform apply not executed |
| nixos-deployment.md | 192 | `nix run .#terraform -- output` | Terraform output extraction not in CI |
| host-onboarding.md | 184 | `sudo zerotier-cli join` | Zerotier network join not tested |
| host-onboarding.md | 328 | `ssh-to-age` derivation | Key conversion not tested |

### Medium gaps (platform-specific)

| File | Line | Command | Risk |
|------|------|---------|------|
| darwin-deployment.md | 172 | `nix build --dry-run` | Dry-run validation local-only |
| darwin-deployment.md | 197 | `darwin-rebuild --list-generations` | Generation listing not tested |
| darwin-deployment.md | 289 | `brew install --cask zerotier-one` | Homebrew cask not tested |
| darwin-deployment.md | 471 | Homebrew installer curl | Darwin bootstrap not tested |
| home-manager-onboarding.md | 185 | `age-keygen -o` | Age key generation not tested |
| home-manager-onboarding.md | 418 | `launchctl` | macOS service management not tested |

### Low gaps (user environment)

| File | Line | Command | Risk |
|------|------|---------|------|
| getting-started.md | 49 | `direnv reload` | Alternative to direnv allow |
| bootstrap-to-activation.md | 334 | `eval "$(direnv hook ...)"` | Shell hook installation |
| secrets-setup.md | 426 | `home-manager switch --show-trace` | Debugging flag variant |

## Root cause analysis

### Why these gaps exist

1. **External tool dependencies**: Bitwarden CLI, Zerotier, Homebrew require credentials or platform-specific environments that CI cannot easily provide

2. **Destructive operations**: Terraform apply, disk partitioning, and similar operations cannot run in CI without real infrastructure

3. **Platform constraints**: Darwin-specific operations require macOS runners which are not available in the current CI configuration

4. **User-interactive workflows**: Operations like `bw unlock` are inherently interactive and designed for human users

5. **Security boundaries**: Some operations intentionally avoid CI to prevent credential exposure

### Coverage pattern

The audit reveals a *boundary testing gap*: CI effectively tests internal systems (flake structure, machine configurations, TypeScript site) but does not test integration points with external tools and platforms.

## Remediation recommendations

### Priority 1: Secrets management workflows (critical)

**Objective**: Validate the core secrets onboarding path that all users must follow.

1. Add Bitwarden CLI testing via mock credentials or test vault
   - Test `bw list`, `bw get`, `bw unlock` with ephemeral test vault
   - Validate ssh-to-age derivation pipeline with test SSH keys

2. Add secrets rotation test to `secrets-workflow` job
   - Test `sops updatekeys` with ephemeral secrets
   - Validate `.sops.yaml` creation rule enforcement

3. Document CI environment variable setup
   - Add `SOPS_AGE_KEY` documentation to ci-jobs.md
   - Ensure `SOPS_AGE_KEY_FILE` path validation in CI

### Priority 2: Infrastructure/deployment coverage

**Objective**: Validate infrastructure provisioning workflows without executing destructive operations.

4. Add terraform validation testing
   - Add lightweight `terraform plan` validation (read-only, no credentials)
   - Test terranix compilation to HCL (schema validation)
   - Do NOT add `terraform apply` (destructive, requires credentials)

5. Add zerotier CLI simulation testing
   - Test zerotier network join simulation
   - Validate zerotier CLI output parsing

6. Extend home-manager activation testing
   - Add home-manager builds to `flake-validation` job
   - Validate sops secret path generation

### Priority 3: User-facing workflows

**Objective**: Improve confidence in user-facing documentation accuracy.

7. Add age-keygen validation test
   - Test `age-keygen` with throwaway keys
   - Validate key format and permissions

8. Add bootstrap sequence integration test
   - Create scenario test: `make bootstrap` -> `direnv allow` -> `make verify`
   - Run in sandbox environment

9. Document platform-specific limitations
   - Add "CI-tested" badges to documentation sections
   - Clearly mark Darwin-only operations as untested in CI

10. Add darwin CI runner (long-term)
    - Enables darwin-rebuild, Homebrew, launchctl testing
    - Blocked on infrastructure availability

## Implementation priority path

| Week | Focus | Impact |
|------|-------|--------|
| 1 | Secrets management (P1 items 1-3) | Unblocks user onboarding |
| 2 | Infrastructure testing (P2 items 4-6) | Improves deployment reliability |
| 3 | User workflows (P3 items 7-9) | Increases documentation confidence |
| Ongoing | Darwin runner (P3 item 10) | Full platform coverage |

## Existing traceability assets

The audit identified existing traceability infrastructure that should be maintained and extended:

1. **justfile-recipes.md**: Contains "CI-tested" column marking recipe coverage
2. **ci-jobs.md**: Contains "Local equivalent" column mapping CI jobs to local commands
3. **test-harness.md**: Contains CI-local parity matrix
4. **testing.md**: Contains test category tables with IDs

These documents provide partial traceability that this audit extends and validates.

## Monitoring recommendations

1. **New snippet detection**: When documentation changes, verify new code blocks have coverage paths

2. **Coverage regression**: Track coverage percentage over time; alert if it drops below 70%

3. **Gap prioritization**: Review gap list quarterly; promote high-risk gaps to remediation backlog

4. **Cross-reference validation**: Ensure ci-jobs.md "Local equivalent" column stays synchronized with actual CI commands

## Appendix: CI job to local command mapping

| CI Job | Local Equivalent | Tests |
|--------|------------------|-------|
| secrets-scan | `nix run nixpkgs#gitleaks -- detect --verbose --redact` | Secret detection |
| set-variables | `just list-packages-json` | Package discovery |
| preview-release-version | `just preview-version main packages/<name>` | Semantic-release preview |
| preview-docs-deploy | `just docs-deploy-preview` | Docs preview deployment |
| bootstrap-verification | `make bootstrap && make verify && make setup-user` | Bootstrap workflow |
| secrets-workflow | Manual encrypt/decrypt test | SOPS mechanics |
| flake-validation | `just check` | Full flake check |
| cache-overlay-packages | `just cache-overlay-packages <system>` | Package pre-caching |
| nix (packages) | `just ci-build-category <system> packages` | Overlay packages |
| nix (checks-devshells) | `just ci-build-category <system> checks-devshells` | Checks and devShells |
| nix (home) | `just ci-build-category <system> home` | Home configurations |
| nix (nixos) | `just ci-build-category <system> nixos <config>` | NixOS configurations |
| typescript | `just test-package docs` | Package tests |
| production-release-packages | `just release-package <package> true` | Semantic-release |
| production-docs-deploy | `just docs-deploy-production` | Production deployment |

## Appendix: nix-unit test inventory

| Test ID | Name | Validates |
|---------|------|-----------|
| - | testFrameworkWorks | nix-unit framework operational |
| TC-001 | testRegressionTerraformModulesExist | Terranix module exports |
| TC-002 | testRegressionNixosConfigExists | NixOS config structure |
| TC-003 | testInvariantClanInventoryMachines | Clan inventory machines |
| TC-004 | testInvariantNixosConfigurationsExist | NixOS configs present |
| TC-005 | testInvariantDarwinConfigurationsExist | Darwin configs present |
| TC-006 | testInvariantHomeConfigurationsExist | Home configs present |
| TC-008 | testFeatureDendriticModuleDiscovery | NixOS module discovery |
| TC-009 | testFeatureDarwinModuleDiscovery | Darwin module discovery |
| TC-010 | testFeatureNamespaceExports | Namespace exports |
| TC-013 | testTypeSafetyModuleEvaluationIsolation | Module structure |
| TC-014 | testTypeSafetySpecialargsProgpagation | specialArgs propagation |
| TC-015 | testTypeSafetyNixosConfigStructure | Config attribute presence |
| TC-016 | testTypeSafetyTerranixModulesStructured | Terranix module structure |
| TC-021 | testMetadataFlakeOutputsExist | Core flake outputs |

## Appendix: validation check inventory

| Check | Purpose |
|-------|---------|
| home-module-exports | Home modules export to flake.modules.homeManager |
| home-configurations-exposed | Nested homeConfigurations exposed for nh CLI |
| naming-conventions | Consistent kebab-case naming |
| terraform-validate | Terraform syntax validation |
| secrets-generation | Clan CLI availability |
| deployment-safety | No destructive terraform patterns |
| vars-user-password-validation | Clan vars system validation |
