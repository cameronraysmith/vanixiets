# CI Test Redesign: justfile-activation

## Problem Statement

The current `justfile-activation` CI job has several issues:

1. **Bug**: Runs `nix develop --command just --list` twice, second invocation produces no output
2. **Brittle**: Hardcodes configuration names that must be manually updated
3. **Shallow**: Only checks if "activate" recipe exists, doesn't validate actual workflows

## Root Cause Analysis

### The Second Invocation Bug

```bash
nix develop --command just --list    # First invocation - succeeds

if nix develop --command just --list 2>&1 | grep -q "activate"; then  # Second invocation - fails!
  echo "✅ activate recipe found"
else
  echo "❌ activate recipe not found"
  exit 1
fi
```

**Issue**: Only ONE "Available recipes" header appears in CI logs, meaning the second invocation never ran `just --list`. When piping to `grep -q`, grep exits immediately after matching, potentially causing SIGPIPE issues with `nix develop` process handling.

**Fix**: Capture output once in a variable, then test it.

### The Hardcoded Configs Problem

```bash
for config in "runner@stibnite" "runner@blackphos" "raquel@blackphos"; do
  just -n activate "$config"
done
```

**Issue**: Must manually update when configs are added/removed. Not scalable.

**Fix**: Dynamically discover configurations from filesystem.

## User Experience Validation Strategy

### What Users Actually Do (from README)

1. **Justfile workflows**:
   - `just activate` - auto-detects current user/host
   - `just activate <target>` - explicit target
   - `just verify` - checks builds before activation
   - `just check` - validates flake structure

2. **Direct nix run**:
   - `nix run . hostname` - system configs (darwin/nixos)
   - `nix run . user@hostname` - home-manager configs

3. **Discovery**:
   - `just --list` - see available recipes
   - `nix flake show` - see flake outputs

### What CI Should Validate

**Tier 1: Core UX** (always test)
- `just --list` shows activate recipe
- `just check` passes (flake structure valid)
- `just -n activate <target>` succeeds for all home configs (dry-run)

**Tier 2: Configuration Discovery** (always test)
- All home configs in `configurations/home/` are reachable
- All darwin/nixos configs exist in flake outputs
- No orphaned configs (file exists but not in outputs)

**Tier 3: Full Build Validation** (optional, expensive)
- Full `just verify` for system configs
- Build all configurations (done in separate job)

## Proposed Implementation

### Job Structure

```yaml
justfile-activation:
  runs-on: ubuntu-latest
  steps:
    - name: checkout repository
      uses: actions/checkout@v5

    - name: setup nix
      uses: ./.github/actions/setup-nix
      with:
        system: x86_64-linux
        enable-cachix: true

    # Test 1: Verify justfile recipes exist and are usable
    - name: test justfile recipes
      run: |
        # Capture output once
        JUST_OUTPUT=$(nix develop --command just --list 2>&1)
        echo "$JUST_OUTPUT"

        # Verify core recipes exist
        echo "Verifying core recipes..."
        for recipe in activate verify check lint; do
          if echo "$JUST_OUTPUT" | grep -q "\b$recipe\b"; then
            echo "✅ $recipe recipe found"
          else
            echo "❌ $recipe recipe not found"
            exit 1
          fi
        done

    # Test 2: Validate flake structure
    - name: validate flake structure
      run: |
        nix develop --command just check

    # Test 3: Discover and test home configurations (dynamic!)
    - name: test home configurations (dry-run)
      run: |
        echo "Discovering home configurations..."

        # Find all home configs dynamically
        HOME_CONFIGS=$(find configurations/home -name "*.nix" -type f | \
          sed 's|configurations/home/||' | \
          sed 's|\.nix$||' | \
          sort)

        if [ -z "$HOME_CONFIGS" ]; then
          echo "⚠️  No home configurations found"
          exit 0
        fi

        echo "Found configurations:"
        echo "$HOME_CONFIGS" | while read config; do
          echo "  - $config"
        done
        echo ""

        # Test each config with dry-run
        echo "Testing activation with dry-run..."
        echo "$HOME_CONFIGS" | while read config; do
          echo "Testing: just -n activate $config"
          if nix develop --command just -n activate "$config"; then
            echo "  ✅ $config dry-run succeeds"
          else
            echo "  ❌ $config dry-run failed"
            exit 1
          fi
        done

        echo ""
        echo "✅ All home configurations validated"

    # Test 4: Verify configuration outputs exist in flake
    - name: verify configuration outputs
      run: |
        echo "Verifying all configurations are exposed in flake outputs..."

        # Get flake outputs
        FLAKE_OUTPUTS=$(nix flake show --json 2>/dev/null | jq -r '
          .darwinConfigurations // {} | keys[] as $k | "darwin:\($k)",
          .nixosConfigurations // {} | keys[] as $k | "nixos:\($k)"
        ')

        # Check each configuration file has corresponding output
        MISSING=0

        # Check darwin configs
        for config_file in configurations/darwin/*.nix; do
          if [ -f "$config_file" ]; then
            config=$(basename "$config_file" .nix)
            if echo "$FLAKE_OUTPUTS" | grep -q "^darwin:$config$"; then
              echo "✅ darwin:$config"
            else
              echo "❌ darwin:$config missing from flake outputs"
              MISSING=1
            fi
          fi
        done

        # Check nixos configs
        for config_file in configurations/nixos/*/default.nix configurations/nixos/*.nix; do
          if [ -f "$config_file" ]; then
            if [[ "$config_file" =~ configurations/nixos/([^/]+)/default.nix ]]; then
              config="${BASH_REMATCH[1]}"
            else
              config=$(basename "$config_file" .nix)
            fi
            if echo "$FLAKE_OUTPUTS" | grep -q "^nixos:$config$"; then
              echo "✅ nixos:$config"
            else
              echo "❌ nixos:$config missing from flake outputs"
              MISSING=1
            fi
          fi
        done

        # Home configs are in legacyPackages, harder to verify, skip for now
        # Future: could verify with nix eval .#legacyPackages.x86_64-linux.homeConfigurations

        if [ $MISSING -eq 1 ]; then
          echo ""
          echo "❌ Some configurations are not exposed in flake outputs"
          exit 1
        fi

        echo ""
        echo "✅ All configurations properly exposed"

    # Test 5: Verify justfile group structure
    - name: verify justfile groups
      run: |
        JUST_OUTPUT=$(nix develop --command just --list 2>&1)

        # Verify expected groups exist
        echo "Verifying justfile groups..."
        for group in nix secrets sops "CI/CD"; do
          if echo "$JUST_OUTPUT" | grep -q "\\[$group\\]"; then
            echo "✅ [$group] group found"
          else
            echo "⚠️  [$group] group not found (may be expected)"
          fi
        done
```

### Benefits of This Approach

1. **No hardcoded configs** - discovers configurations from filesystem
2. **Tests actual UX** - validates what users will actually run
3. **Fast** - dry-runs only, no full builds
4. **Maintainable** - automatically adapts to config additions/removals
5. **Comprehensive** - validates recipes, configs, and flake structure
6. **Clear output** - shows exactly what's being tested and why

### What This Doesn't Test (By Design)

- **Full builds** - tested in separate `nix` job
- **Actual activation** - would require system-specific environments
- **Secrets decryption** - requires actual keys
- **Platform-specific features** - Ubuntu CI can't test darwin-specific code

### Performance

- **Current job**: ~1min (but fails)
- **Proposed job**: ~1-2min (adds config discovery and validation)
- **Tradeoff**: Slightly longer, but much more comprehensive

## Migration Plan

1. Create new test file following proposed structure
2. Test in feature branch
3. Once passing, replace existing test
4. Remove hardcoded config list
5. Document in README what CI validates

## Alternative Approaches Considered

### Option A: Test with Act Locally

**Pros**: Can test full workflow locally
**Cons**: Complex setup, slow, doesn't solve hardcoding issue

### Option B: Generate Config List Dynamically but Keep Simple Test

**Pros**: Minimal changes
**Cons**: Still shallow validation, doesn't test UX

### Option C: Full Build Tests in CI

**Pros**: Maximum confidence
**Cons**: Very slow (10+ minutes), expensive, doesn't scale

**Decision**: Use proposed approach (discovery + dry-run) for fast, comprehensive validation
