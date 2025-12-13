---
title: CI Testing Strategy
---

This document describes what our CI tests validate and why, organized by job.

## Testing Philosophy

Our CI validates the **user experience** described in the README, not just that code compiles. Tests are designed to:

1. **Mirror user workflows** - If a user following the README would do it, CI tests it
2. **Discover resources dynamically** - No hardcoded lists that drift out of sync
3. **Fail fast and clearly** - Errors should point to the exact problem
4. **Scale efficiently** - Tests should remain fast as the project grows

## Job: justfile-activation

**Purpose**: Validates that users can discover and use justfile recipes to manage configurations.

### What It Tests

#### 1. Justfile Recipe Discovery
```bash
just --list  # Shows all available recipes
```

**Validates**:
- Core recipes exist: `activate`, `verify`, `check`, `lint`
- Justfile is accessible in devshell
- Recipe descriptions are visible

**Why**: First thing users do is `just --list` to see what's available.

#### 2. Flake Structure
```bash
just check  # Runs nix flake check
```

**Validates**:
- Flake syntax is correct
- All outputs are properly defined
- No circular dependencies

**Why**: Users run `just check` before making changes. Must pass consistently.

#### 3. Home Configuration Discovery
```bash
find configurations/home -name "*.nix"  # Dynamic discovery
```

**Validates**:
- All home configs in filesystem are discoverable
- Configs follow naming convention (user@host.nix)
- No orphaned/broken config files

**Why**: Users should be able to see all available home configs without reading code.

#### 4. Activation Dry-Run
```bash
just -n activate <config>  # Test each discovered config
```

**Validates**:
- Each home config can be activated (dry-run)
- Activation logic works for all configs
- No hardcoded assumptions about config names

**Why**: Users will run `just activate user@host` - must work for ALL configs.

#### 5. Configuration Output Mapping
```bash
nix flake show --json | jq '...'  # Get flake outputs
```

**Validates**:
- All darwin configs in `configurations/darwin/` → `darwinConfigurations.*`
- All nixos configs in `configurations/nixos/` → `nixosConfigurations.*`
- Nixos-unified autowiring is working correctly
- No configs exist in filesystem but not in outputs

**Why**: Users expect file-based discovery to work. If `configurations/darwin/foo.nix` exists, `darwin-rebuild switch --flake .#foo` should work.

### What It Doesn't Test

- **Full builds** - tested in separate `nix` job (expensive)
- **Actual activation** - requires system-specific environment (sudo, /etc, etc)
- **Home config outputs** - legacyPackages structure harder to validate, deferred
- **Cross-platform behavior** - darwin-specific code can't run on ubuntu runners

### Expected Runtime

- **Duration**: 1-2 minutes
- **Bottleneck**: `nix develop` to build devshell (~30s first time, cached after)

### Failure Modes and Debugging

| Error | Cause | Fix |
|-------|-------|-----|
| "⊘ activate recipe not found" | Justfile missing `activate` recipe | Check justfile:25 exists |
| "⊘ $config dry-run failed" | Config syntax error or missing dependency | Run locally: `just -n activate $config` |
| "⊘ darwin:foo missing from flake outputs" | Config file exists but not in flake | Check auto-discovery or namespace exports |
| "⚠️  no home configurations found" | Empty configurations/home/ directory | Expected on fresh clone |

## Job: nix

**Purpose**: Validates that all flake outputs actually build.

### What It Tests

Builds all outputs for all systems:
- `nixosConfigurations.*`
- `darwinConfigurations.*`
- `packages.*`
- `devShells.*`
- `checks.*`

### Why Separate from justfile-activation

- **Different goals**: justfile-activation tests UX, nix tests builds
- **Different performance**: dry-run (fast) vs full build (slow)
- **Matrix strategy**: nix runs on native platforms (aarch64-darwin on macOS, etc)

## Job: sops

**Purpose**: Validates secrets management infrastructure.

### What It Tests

- Ephemeral sops-age key generation
- Encrypted file creation with sops-nix
- File decryption with generated keys
- Cleanup of test secrets

**Why**: Secrets are critical infrastructure. Test that sops-nix integration works.

## Job: docs-test

**Purpose**: Validates documentation site.

### What It Tests

- Dependency installation (bun)
- Build process
- Unit tests with coverage
- Docs site generation

**Why**: Documentation is part of the user experience. Must build and pass tests.

## Adding New Tests

### When to Add to justfile-activation

Add tests when:
- Users will interact with it via justfile
- It affects configuration discovery
- It validates a workflow described in README

Example: If you add `just deploy` recipe, test it exists and works.

### When to Create New Job

Create new job when:
- Test requires different environment (e.g., docker, cloud resources)
- Test has very different performance characteristics
- Test validates completely separate concern

Example: Terraform validation would be separate job.

### Dynamic vs Static Tests

**Prefer dynamic** when:
- Resource list changes frequently (configs, packages, etc)
- Maintaining hardcoded lists is error-prone
- Discovery logic is itself important to validate

**Use static** when:
- Testing specific known failures
- Validating backwards compatibility
- Performance is critical (discovery is expensive)

## Test Maintenance

### Updating Tests

When you add a configuration:
- **No action needed** - justfile-activation discovers it automatically

When you add a justfile recipe:
- **Consider** - Should it be in core recipes list?
- **Example**: If you add `just backup`, decide if CI should verify it exists

When you change directory structure:
- **Update** - Discovery logic in justfile-activation
- **Example**: If configs move from `configurations/` to `hosts/`, update `find` commands

### Monitoring Test Performance

Track in CI:
- `justfile-activation` should stay under 2min
- If it grows beyond 3min, consider splitting

Track locally:
- `just check` should stay under 30s
- If it grows beyond 1min, investigate what's being evaluated

## Job Execution Caching

As of ADR-0016, all jobs use per-job content-addressed caching via GitHub Checks API.
Each job independently decides whether to run based on:
1. Previous successful execution for the current commit SHA
2. Relevant file changes (via path filters)
3. Manual force-run override

This means jobs automatically skip if they've already succeeded for a given commit, providing optimal retry behavior and faster feedback loops.

## References

- **Implementation**: `.github/workflows/ci.yaml` (see job definitions for caching logic)
- **Caching architecture**: [ADR-0016: Per-job content-addressed caching](/development/architecture/adrs/0016-per-job-content-addressed-caching/)
- **User workflows**: Repository README (usage section)
