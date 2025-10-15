# Claude Code multi-profile implementation plan

## Overview

Implementation plan for adding declarative, profile-based configuration to claude-code in nix-config, enabling seamless switching between multiple API providers (Anthropic official, GLM-4.6 via Z.ai, etc.) while maintaining full declarative reproducibility.

**Status**: Phase 1 & 2 complete (Discovery & Planning) - awaiting approval for implementation

**Date**: 2025-10-15

## Background

### Original request context

User investigated whether mirkolenz-nixos contained any GLM-4.6/Z.ai configuration (it did not).
A third party suggested creating multiple config directories via `CLAUDE_CONFIG_DIR` with shell wrapper functions.

### Current state

- `~/.claude/settings.json` is managed by home-manager in `nix-config/modules/home/all/tools/claude-code/default.nix`
- User's global Claude Code preferences are at `~/.claude/CLAUDE.md` and `~/.claude/commands/preferences/`
- Reference implementation exists in `mirkolenz-nixos/home/mlenz/common/programs/claude.nix` (simpler, conditional enable only)

## Phase 1: Discovery & Analysis

### Current configuration architecture

**Claude Code module location**: `modules/home/all/tools/claude-code/default.nix`

Current setup:
- Uses home-manager's built-in `programs.claude-code` module
- Manages settings, permissions, and directories declaratively
- Settings match `~/.claude/settings.json` exactly
- Creates shell alias `ccds` for `--dangerously-skip-permissions`
- Symlinks commands and agents directories
- Imports `mcp-servers.nix` for MCP server configuration

Current settings structure:
```nix
programs.claude-code = {
  enable = true;
  package = pkgs.claude-code-bin;
  commandsDir = ./commands;
  agentsDir = ./agents;
  settings = {
    statusLine = { type = "command"; command = "${pkgs.cc-statusline-rs}/bin/statusline"; };
    theme = "dark";
    autoCompactEnabled = false;
    spinnerTipsEnabled = false;
    cleanupPeriodDays = 1100;
    includeCoAuthoredBy = false;
    enableAllProjectMcpServers = false;
    alwaysThinkingEnabled = true;
    permissions = { /* ... */ };
  };
};
```

### Secrets management integration

Setup uses **sops-nix** with age encryption:
- Keys at: `~/.config/sops/age/keys.txt`
- Secrets in: `secrets/shared.yaml` (and other locations)
- Configuration at: `modules/home/all/core/sops.nix`
- `.sops.yaml` defines key groups for dev, ci, admin, users, and hosts

For GLM API key:
1. Add `GLM_API_KEY` to `secrets/shared.yaml` (sops-encrypted)
2. Use `sops.secrets` to expose it at runtime
3. Reference it in wrapper script environment

### Module system patterns

nix-config follows these patterns:
- **flake-parts** for modular flake structure
- **Cross-platform modules** in `modules/home/all/`
- **Type-safe module system** with proper options
- **No existing profile/variant pattern** - this will be new
- **nixos-unified** for system configurations

### Reference implementation analysis

The mirkolenz-nixos implementation is simpler (conditional enable only).
Our use case requires:
- Multiple API provider configurations
- Environment variable management
- Separate config directories per profile
- Secret resolution for API keys

## Phase 2: Implementation plan

### Architectural decision: extend vs. new module

**Decision: Extend the existing module** rather than create a separate `claude-code-profiles` module.

Rationale:
1. **Backward compatibility**: No profiles = current behavior preserved exactly
2. **Single source of truth**: One module manages all claude-code configuration
3. **Cleaner**: Avoids duplication between profile and non-profile setups
4. **Aligned with architectural principles**: Extension over replacement
5. **Co-location**: Keeps related configuration together

### Proposed module structure

```nix
# modules/home/all/tools/claude-code/default.nix (extended)
{
  programs.claude-code = {
    enable = true;
    package = pkgs.claude-code-bin;

    # Existing single-profile config (preserved for backward compat)
    commandsDir = ./commands;
    agentsDir = ./agents;
    settings = { /* ... */ };

    # NEW: Optional multi-profile support
    profiles = {
      anthropic = {
        # Inherits base settings by default
        # This becomes the default profile
      };

      glm = {
        settings = { /* same as anthropic */ };
        env = {
          ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic";
          ANTHROPIC_AUTH_TOKEN = "$GLM_API_KEY";  # resolved from sops
          ANTHROPIC_DEFAULT_OPUS_MODEL = "glm-4.6";
          ANTHROPIC_DEFAULT_SONNET_MODEL = "glm-4.6";
          ANTHROPIC_DEFAULT_HAIKU_MODEL = "glm-4.5-air";
        };
      };
    };
  };
}
```

Behavior:
- `claude` → uses default (anthropic) settings
- `claude-glm` → wrapper with GLM environment + Z.ai endpoint
- Both share same commands/ and agents/ directories

### Implementation files

Will modify/create:

1. **`modules/home/all/tools/claude-code/default.nix`** (extend existing)
   - Add optional `profiles` option with type-safe submodule
   - Generate wrapper scripts for each profile
   - Create separate `CLAUDE_CONFIG_DIR` for each profile
   - Preserve current behavior when profiles not used

2. **`modules/home/all/tools/claude-code/profiles.nix`** (new, imported by default.nix)
   - Profile type definition
   - Wrapper script generation logic
   - Config directory setup

3. **`secrets/shared.yaml`** (add GLM_API_KEY)
   - Encrypted GLM API key using sops

4. **`modules/home/all/core/sops.nix`** (minimal addition)
   - Expose `GLM_API_KEY` secret for runtime access

### Migration path

**Phase 3a: Refactor existing module to support profiles**
- Current single-profile setup becomes "anthropic" profile implicitly
- All existing settings preserved exactly
- No behavior change yet

**Phase 3b: Add GLM profile**
- Add GLM API key to sops secrets
- Define `glm` profile with Z.ai configuration
- Generate `claude-glm` wrapper script

**Phase 3c: Testing & validation**
- Verify `claude` behaves identically to current
- Test `claude-glm` connects to Z.ai endpoint
- Validate secrets resolution

### Type-safe module schema

```nix
profileType = types.submodule {
  options = {
    settings = mkOption {
      type = types.attrs;
      default = baseSettings;  # inherit from base config
      description = "Claude Code settings.json for this profile";
    };

    env = mkOption {
      type = types.attrsOf types.str;
      default = {};
      description = "Environment variables for this profile";
    };

    configDir = mkOption {
      type = types.str;
      default = "~/.claude-${name}";
      description = "Config directory for this profile";
    };
  };
};
```

### Secrets integration strategy

**Chosen approach: Runtime environment variable**

```nix
# sops.nix - expose secret
sops.secrets."api-keys/glm" = {};

# claude-code wrapper
pkgs.writeShellApplication {
  name = "claude-glm";
  text = ''
    export GLM_API_KEY="$(cat ${config.sops.secrets."api-keys/glm".path})"
    export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
    export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
    export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
    export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
    export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"
    export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"
    exec claude "$@"
  '';
}
```

Rationale: Clearer separation, easier debugging, explicit effect handling at boundaries.

## Design decisions

### Confirmed decisions

1. **Extend existing module** (vs. new separate module)
2. **`claude` = default**, `claude-glm` = wrapper
3. **Share commands/agents directories** across profiles
4. **Use `secrets/shared.yaml`** for GLM key (path: `api-keys/glm`)
5. **Runtime environment variable approach** for secrets

### Questions for clarification

1. **Naming convention**: Should wrappers be:
   - `claude` (default) + `claude-glm` ✓ (recommended)
   - `claude-anthropic` + `claude-glm` (explicit)

2. **Shared vs. separate commands/agents**: Should each profile have its own commands/ and agents/ directories, or share them?
   - **Share by default** ✓ (recommended) - less duplication, easier maintenance
   - Allow override if needed

3. **GLM API Key location in secrets**:
   - `secrets/shared.yaml` under `api-keys/glm` ✓ (recommended)
   - New file `secrets/services/glm.yaml`

4. **Should the default profile be configurable**, or always "anthropic"?
   - **Always use current settings as default** ✓ (recommended)
   - Add profiles as extensions

## Phase 3: Implementation (pending approval)

### Phase 3a: Refactor for profile support

1. Create `modules/home/all/tools/claude-code/profiles.nix`:
   - Define `profileType` submodule
   - Implement `mkProfileWrapper` function
   - Export helper functions

2. Modify `modules/home/all/tools/claude-code/default.nix`:
   - Import `profiles.nix`
   - Add `profiles` option (optional, default = {})
   - Preserve all existing behavior when profiles = {}

3. Test with `nix build` and `nix flake check`

### Phase 3b: Add GLM profile

1. Add GLM API key to secrets:
   ```bash
   sops secrets/shared.yaml
   # Add: api-keys/glm: "your-glm-api-key"
   ```

2. Update `modules/home/all/core/sops.nix`:
   ```nix
   sops.secrets."api-keys/glm" = {
     mode = "0400";
   };
   ```

3. Add GLM profile to claude-code configuration:
   ```nix
   programs.claude-code.profiles.glm = {
     # settings inherited from base
     env = {
       ANTHROPIC_BASE_URL = "https://api.z.ai/api/anthropic";
       ANTHROPIC_AUTH_TOKEN = "$GLM_API_KEY";
       ANTHROPIC_DEFAULT_OPUS_MODEL = "glm-4.6";
       ANTHROPIC_DEFAULT_SONNET_MODEL = "glm-4.6";
       ANTHROPIC_DEFAULT_HAIKU_MODEL = "glm-4.5-air";
     };
   };
   ```

4. Build and test:
   ```bash
   nix build .#darwinConfigurations.blackphos.system
   # or
   darwin-rebuild switch --flake .
   ```

### Phase 3c: Generate wrapper scripts

Wrapper generation logic:
```nix
mkProfileWrapper = name: profile: pkgs.writeShellApplication {
  name = "claude-${name}";
  runtimeInputs = [ pkgs.claude-code-bin ];
  text = ''
    # Load secret if needed
    ${lib.optionalString (profile.env ? ANTHROPIC_AUTH_TOKEN &&
                          profile.env.ANTHROPIC_AUTH_TOKEN == "$GLM_API_KEY") ''
      export GLM_API_KEY="$(cat ${config.sops.secrets."api-keys/glm".path})"
    ''}

    # Export environment variables
    ${lib.concatStringsSep "\n" (lib.mapAttrsToList (k: v:
      ''export ${k}="${v}"''
    ) profile.env)}

    # Set config directory
    export CLAUDE_CONFIG_DIR="${profile.configDir}"

    # Execute claude
    exec claude "$@"
  '';
};
```

## Phase 4: Validation (pending approval)

### Validation checklist

1. **Verify `claude` command unchanged**:
   ```bash
   claude --version
   claude doctor
   # Test basic conversation
   ```

2. **Test `claude-glm` connects to Z.ai**:
   ```bash
   claude-glm --version
   # Should show GLM model when queried
   claude-glm "What model are you?"
   ```

3. **Confirm secrets resolution**:
   ```bash
   # Verify secret file exists and has correct permissions
   ls -la $(nix eval --raw .#darwinConfigurations.blackphos.config.sops.secrets.\"api-keys/glm\".path)

   # Test wrapper can read secret
   claude-glm "test connection"
   ```

4. **Run formatting and checks**:
   ```bash
   nix fmt
   nix flake check
   ```

5. **Test both profiles in parallel**:
   ```bash
   # Terminal 1
   claude "anthropic test"

   # Terminal 2
   claude-glm "glm test"
   ```

## Key architectural principles applied

From `~/.claude/commands/preferences/architectural-patterns.md`:

1. **Side effects explicit in type signatures**: Environment variables and config directories explicitly declared in profile type
2. **Effects isolated at boundaries**: Secret resolution happens at wrapper script boundary, not in pure Nix config
3. **Type-safe composition**: Module system enforces structure through `profileType` submodule
4. **Declarative over imperative**: All configuration in Nix expressions, no manual file editing
5. **Composable abstractions**: Profiles compose with base settings, can be arbitrarily extended

## References

- User preferences:
  - `~/.claude/commands/preferences/nix-development.md`
  - `~/.claude/commands/preferences/secrets.md`
  - `~/.claude/commands/preferences/architectural-patterns.md`

- Existing configuration:
  - `modules/home/all/tools/claude-code/default.nix`
  - `modules/home/all/core/sops.nix`
  - `.sops.yaml`

- Reference implementation:
  - `mirkolenz-nixos/home/mlenz/common/programs/claude.nix`

## Next steps

Awaiting user approval of this plan before proceeding to Phase 3 implementation.

Once approved:
1. Implement profiles.nix with type-safe profile definitions
2. Extend default.nix with profile support
3. Add GLM API key to sops secrets
4. Generate wrapper scripts
5. Test and validate
6. Document usage
