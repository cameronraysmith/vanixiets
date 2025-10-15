# Claude Code multi-profile implementation plan

## Overview

Implementation plan for adding declarative, profile-based configuration to claude-code in nix-config, enabling seamless switching between multiple API providers (Anthropic official, GLM-4.6 via Z.ai, etc.) while maintaining full declarative reproducibility and complete profile isolation.

**Status**: Phase 1 & 2 complete (Discovery & Planning) - ready for implementation

**Date**: 2025-10-15

**Revision**: 2 - Corrected architecture based on CLAUDE_CONFIG_DIR support verification

## Background

### Original request context

User investigated whether mirkolenz-nixos contained any GLM-4.6/Z.ai configuration (it did not).
A third party suggested creating multiple config directories via `CLAUDE_CONFIG_DIR` with shell wrapper functions.
This approach is now confirmed to be the correct solution path.

### Current state

- `~/.claude/settings.json` is managed by home-manager in `nix-config/modules/home/all/tools/claude-code/default.nix`
- User's global Claude Code preferences are at `~/.claude/CLAUDE.md` and `~/.claude/commands/preferences/`
- Reference implementation exists in `mirkolenz-nixos/home/mlenz/common/programs/claude.nix` (simpler, conditional enable only)
- **No changes required** to existing claude-code configuration

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

This configuration is **completely preserved** - no modifications required.

### CLAUDE_CONFIG_DIR support verification

**Critical discovery**: Claude Code CLI supports the `CLAUDE_CONFIG_DIR` environment variable for specifying alternate configuration directories.

Evidence:
1. **Anthropic's own devcontainer.json** uses it: [github.com/anthropics/claude-code/.devcontainer/devcontainer.json#L50](https://github.com/anthropics/claude-code/blob/main/.devcontainer/devcontainer.json#L50)
2. **Experimental verification** confirms isolation:
   ```bash
   CLAUDE_CONFIG_DIR="$HOME/.claude-glm-test" claude --version
   ls -la "$HOME/.claude-glm-test/"
   # Creates: .claude.json, debug/, statsig/, settings.json
   ```

This enables **complete profile isolation**:
- ✅ Separate config directories
- ✅ Isolated chat history/sessions
- ✅ Independent settings (or shared via symlink)
- ✅ Zero interference between profiles

### Home-manager module capabilities

The upstream `home-manager/modules/programs/claude-code.nix` module:
- Provides a **single** `programs.claude-code` option
- Hardcodes output to `.claude/settings.json`
- Does **not** support multiple profiles or config directories
- Cannot be extended without `disabledModules` (fragile approach)

Implication: We must create a **separate wrapper module** rather than extending the existing module.

### Secrets management integration

Setup uses **sops-nix** with age encryption:
- Keys at: `~/.config/sops/age/keys.txt`
- Secrets in: `secrets/shared.yaml` (and other locations)
- Configuration at: `modules/home/all/core/sops.nix`
- `.sops.yaml` defines key groups for dev, ci, admin, users, and hosts

For GLM API key:
1. Add `api-keys/glm` to `secrets/shared.yaml` (sops-encrypted)
2. Expose via `sops.secrets."api-keys/glm"` in wrapper module
3. Reference in wrapper script: `$(cat ${config.sops.secrets."api-keys/glm".path})`

### Module system patterns

nix-config follows these patterns:
- **flake-parts** for modular flake structure
- **Cross-platform modules** in `modules/home/all/`
- **Type-safe module system** with proper options
- **Wrapper-based extensions** for profile-like behavior (new pattern)
- **nixos-unified** for system configurations

## Phase 2: Implementation Plan

### Architectural decision: wrapper module approach

**Decision**: Create a standalone wrapper module that generates profile-specific wrapper scripts.

**Do NOT**:
- ❌ Extend `programs.claude-code` module (requires `disabledModules`, fragile)
- ❌ Modify existing claude-code configuration (unnecessary)
- ❌ Duplicate settings manually (violates DRY)

**Do**:
- ✅ Create `modules/home/all/tools/claude-code-wrappers.nix`
- ✅ Generate wrapper scripts with `CLAUDE_CONFIG_DIR` set
- ✅ Reuse settings.json from existing configuration via nix store reference
- ✅ Keep default `claude` command unchanged (managed by home-manager)

Rationale:
1. **Zero modification** to working configuration
2. **Single source of truth** for settings (reuse via symlink)
3. **Simple and maintainable** (no module system hacks)
4. **Clear separation** (wrappers are extensions, not replacements)
5. **Complete isolation** via `CLAUDE_CONFIG_DIR`

### Proposed module structure

```nix
# modules/home/all/tools/claude-code-wrappers.nix
{ config, pkgs, lib, ... }:
let
  # Reference to the JSON format used by claude-code module
  jsonFormat = pkgs.formats.json { };
in
{
  # Generate wrapper script for GLM profile
  home.packages = [
    (pkgs.writeShellApplication {
      name = "claude-glm";
      runtimeInputs = [ config.programs.claude-code.finalPackage ];
      text = ''
        # Set isolated config directory
        export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"

        # Create directory if needed (claude will also create it, but be explicit)
        mkdir -p "$CLAUDE_CONFIG_DIR"

        # Load GLM API key from sops-managed secret
        export GLM_API_KEY="$(cat ${config.sops.secrets."api-keys/glm".path})"

        # Configure Z.ai API endpoint
        export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
        export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"

        # Configure GLM model defaults
        export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"

        # Execute claude with isolated environment
        exec claude "$@"
      '';
    })
  ];

  # Reuse settings.json from default profile (single source of truth)
  xdg.configFile."claude-glm/settings.json" = {
    source = config.home.file.".claude/settings.json".source;
    # This references the SAME nix store path generated by programs.claude-code
  };

  # Share commands directory with default profile
  xdg.configFile."claude-glm/commands" = lib.mkIf (config.programs.claude-code.commandsDir != null) {
    source = config.programs.claude-code.commandsDir;
    recursive = true;
  };

  # Share agents directory with default profile
  xdg.configFile."claude-glm/agents" = lib.mkIf (config.programs.claude-code.agentsDir != null) {
    source = config.programs.claude-code.agentsDir;
    recursive = true;
  };

  # Expose GLM API key from sops
  sops.secrets."api-keys/glm" = {
    mode = "0400";
  };
}
```

Behavior:
- `claude` → default profile (`~/.claude/`), Anthropic API
- `claude-glm` → GLM profile (`~/.config/claude-glm/`), Z.ai API
- Both share identical settings, commands, and agents (via symlinks)
- Completely isolated sessions and chat history
- Independent API endpoints and authentication

### Settings.json sharing strategy

**Key insight**: The home-manager module generates settings.json in the nix store:

```nix
home.file.".claude/settings.json" = {
  source = jsonFormat.generate "claude-code-settings.json" (
    cfg.settings // { "$schema" = "..."; }
  );
};
```

The `source` attribute is a **nix store path** (e.g., `/nix/store/abc123.../claude-code-settings.json`).

**Reuse approach**:
```nix
xdg.configFile."claude-glm/settings.json" = {
  source = config.home.file.".claude/settings.json".source;
  # Both symlinks point to the SAME nix store file
};
```

Benefits:
- ✅ **Zero duplication**: Single source of truth
- ✅ **Automatic updates**: Changes to `programs.claude-code.settings` propagate to all profiles
- ✅ **Type-safe**: Uses the same JSON generation logic
- ✅ **Efficient**: Same file in nix store, multiple symlinks

Alternative (if per-profile customization needed later):
```nix
xdg.configFile."claude-glm/settings.json".source = jsonFormat.generate "claude-glm-settings.json" (
  config.programs.claude-code.settings // {
    "$schema" = "https://json.schemastore.org/claude-code-settings.json";
    # Optional profile-specific overrides here
  }
);
```

### Implementation files

Will create/modify:

1. **`modules/home/all/tools/claude-code-wrappers.nix`** (new)
   - Wrapper script generation for GLM profile
   - Settings, commands, agents symlinks
   - sops secret exposure

2. **`modules/home/all/tools/default.nix`** (modify)
   - Add `./claude-code-wrappers.nix` to imports

3. **`secrets/shared.yaml`** (modify)
   - Add encrypted `api-keys/glm` entry

Will **NOT** modify:
- `modules/home/all/tools/claude-code/default.nix` - unchanged
- `modules/home/all/core/sops.nix` - unchanged (secret exposure in wrapper module)

### Secrets integration strategy

**Runtime resolution via wrapper script**:

```nix
sops.secrets."api-keys/glm" = {
  mode = "0400";  # Read-only for owner
};

# In wrapper script:
export GLM_API_KEY="$(cat ${config.sops.secrets."api-keys/glm".path})"
export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
```

The sops-nix module:
1. Decrypts `api-keys/glm` from `secrets/shared.yaml` at activation time
2. Writes decrypted value to a runtime path (e.g., `/run/secrets/api-keys-glm`)
3. Wrapper script reads this file at execution time
4. Environment variable set for the claude process

**Why this approach**:
- ✅ Secrets never appear in nix store (derivations remain pure)
- ✅ Runtime resolution (decryption happens at activation, not build)
- ✅ Proper permissions (0400, owner-only read)
- ✅ Explicit effect handling at boundary (wrapper script, not nix config)

### Directory structure

After implementation:

```
~/.claude/                          # Default profile (unchanged)
├── settings.json → /nix/store/.../claude-code-settings.json
├── commands/ → /nix/store/.../commands/
├── agents/ → /nix/store/.../agents/
├── .claude.json                    # Session data
└── debug/                          # Logs

~/.config/claude-glm/               # GLM profile (new)
├── settings.json → /nix/store/.../claude-code-settings.json  (same file!)
├── commands/ → /nix/store/.../commands/  (same directory!)
├── agents/ → /nix/store/.../agents/  (same directory!)
├── .claude.json                    # Separate session data
└── debug/                          # Separate logs
```

Isolation points:
- **Shared** (via symlinks): settings.json, commands/, agents/
- **Isolated**: .claude.json (sessions), debug/ (logs), statsig/ (analytics)

## Design Decisions

### Confirmed decisions

1. **Wrapper module approach** - standalone, doesn't extend existing module
2. **`claude` = default** (unchanged), `claude-glm` = new wrapper
3. **Share settings/commands/agents** via symlinks to same nix store paths
4. **Use `secrets/shared.yaml`** for GLM key (path: `api-keys/glm`)
5. **Runtime environment variables** for API endpoint and authentication
6. **`CLAUDE_CONFIG_DIR` isolation** for session and history separation

### Rationale for sharing vs. isolation

**Shared** (via symlinks):
- `settings.json` - Same permissions, theme, preferences make sense
- `commands/` - Custom slash commands are API-agnostic
- `agents/` - Agent definitions are API-agnostic

**Isolated** (separate directories):
- `.claude.json` - Session state, active conversations
- `debug/` - Logs specific to API interactions
- `statsig/` - Analytics data

This maximizes consistency while enabling independent usage tracking and history.

## Phase 3: Implementation

### Phase 3a: Create wrapper module

1. Create `modules/home/all/tools/claude-code-wrappers.nix`:

```nix
{ config, pkgs, lib, ... }:
{
  # GLM wrapper script
  home.packages = [
    (pkgs.writeShellApplication {
      name = "claude-glm";
      runtimeInputs = [ config.programs.claude-code.finalPackage ];
      text = ''
        export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"
        mkdir -p "$CLAUDE_CONFIG_DIR"

        export GLM_API_KEY="$(cat ${config.sops.secrets."api-keys/glm".path})"
        export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
        export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"

        exec claude "$@"
      '';
    })
  ];

  # Share settings from default profile
  xdg.configFile."claude-glm/settings.json" = {
    source = config.home.file.".claude/settings.json".source;
  };

  # Share commands directory
  xdg.configFile."claude-glm/commands" = lib.mkIf (config.programs.claude-code.commandsDir != null) {
    source = config.programs.claude-code.commandsDir;
    recursive = true;
  };

  # Share agents directory
  xdg.configFile."claude-glm/agents" = lib.mkIf (config.programs.claude-code.agentsDir != null) {
    source = config.programs.claude-code.agentsDir;
    recursive = true;
  };

  # Expose GLM API key
  sops.secrets."api-keys/glm" = {
    mode = "0400";
  };
}
```

2. Import in `modules/home/all/tools/default.nix`:

```nix
{
  imports = [
    # ... existing imports
    ./claude-code-wrappers.nix
  ];
}
```

### Phase 3b: Add GLM API key to sops

1. Edit secrets file:
   ```bash
   cd ~/projects/nix-workspace/nix-config
   sops secrets/shared.yaml
   ```

2. Add GLM API key:
   ```yaml
   # secrets/shared.yaml
   # ... existing secrets
   api-keys:
     glm: "your-glm-4.6-api-key-from-z.ai"
   ```

3. Verify encryption:
   ```bash
   sops -d secrets/shared.yaml | grep -A 2 "api-keys"
   ```

### Phase 3c: Build and test

1. Build system configuration:
   ```bash
   cd ~/projects/nix-workspace/nix-config
   nix build .#darwinConfigurations.blackphos.system
   ```

2. Apply configuration:
   ```bash
   darwin-rebuild switch --flake .
   ```

3. Verify wrapper script exists:
   ```bash
   which claude-glm
   # Should show: /etc/profiles/per-user/crs58/bin/claude-glm
   ```

4. Check config directory creation:
   ```bash
   claude-glm --version
   ls -la ~/.config/claude-glm/
   # Should show: settings.json, commands/, agents/, .claude.json, etc.
   ```

## Phase 4: Validation

### Validation checklist

1. **Verify `claude` command unchanged**:
   ```bash
   claude --version
   # Should use ~/.claude/ directory
   ls -la ~/.claude/.claude.json
   ```

2. **Verify `claude-glm` uses separate directory**:
   ```bash
   claude-glm --version
   # Should use ~/.config/claude-glm/ directory
   ls -la ~/.config/claude-glm/.claude.json
   ```

3. **Confirm settings are shared (same nix store path)**:
   ```bash
   readlink ~/.claude/settings.json
   readlink ~/.config/claude-glm/settings.json
   # Should be identical nix store paths
   ```

4. **Test GLM API connection**:
   ```bash
   claude-glm "What model are you? Please identify yourself."
   # Should respond as GLM-4.6 via Z.ai
   ```

5. **Test isolation (parallel usage)**:
   ```bash
   # Terminal 1
   claude "Start conversation A with Anthropic"

   # Terminal 2
   claude-glm "Start conversation B with GLM"

   # Verify sessions are separate:
   # ~/.claude/.claude.json should only have conversation A
   # ~/.config/claude-glm/.claude.json should only have conversation B
   ```

6. **Verify secrets resolution**:
   ```bash
   # Check secret file exists with correct permissions
   ls -la $(nix eval --raw .#darwinConfigurations.blackphos.config.sops.secrets.\"api-keys/glm\".path)
   # Should show: -r-------- (0400)
   ```

7. **Run nix checks**:
   ```bash
   nix fmt
   nix flake check
   ```

### Expected outcomes

✅ `claude` continues to work exactly as before
✅ `claude-glm` creates isolated config directory
✅ Both share settings, commands, agents (confirmed via readlink)
✅ Sessions and history are completely separate
✅ GLM profile connects to Z.ai endpoint
✅ Anthropic profile connects to official Anthropic API
✅ Secrets properly resolved at runtime
✅ No nix evaluation errors

## Key Architectural Principles Applied

From `~/.claude/commands/preferences/architectural-patterns.md`:

1. **Side effects explicit in type signatures**: Environment variables declared explicitly in wrapper script
2. **Effects isolated at boundaries**: Secret resolution and API configuration at wrapper boundary, not in pure Nix config
3. **Declarative over imperative**: All configuration in Nix expressions, no manual file editing
4. **Single source of truth**: Settings reused via symlink, not duplicated
5. **Composable abstractions**: Wrapper approach allows arbitrary profile additions without modifying existing code

From `~/.claude/commands/preferences/nix-development.md`:

1. **Flake-based**: All configuration in flake, not channels
2. **Modular structure**: Wrapper module in `modules/home/all/tools/`
3. **Type-safe**: Uses module system options properly
4. **Cross-platform**: Uses `xdg.configHome` for portability

From `~/.claude/commands/preferences/secrets.md`:

1. **sops-nix integration**: Secrets encrypted in git, decrypted at activation
2. **Runtime resolution**: API keys loaded at execution time, not build time
3. **Proper permissions**: Secret files restricted to owner-only read (0400)
4. **Explicit handling**: Secret access explicit in wrapper script

## Future Enhancements

Potential extensions (not part of initial implementation):

1. **Per-profile settings customization**:
   ```nix
   xdg.configFile."claude-glm/settings.json".source = jsonFormat.generate "..." (
     config.programs.claude-code.settings // {
       # Override specific settings for GLM
       cleanupPeriodDays = 30;  # More aggressive cleanup for testing
     }
   );
   ```

2. **Additional profiles** (e.g., local LLM, different providers):
   ```nix
   home.packages = [
     (mkClaudeWrapper {
       name = "claude-local";
       configDir = "${config.xdg.configHome}/claude-local";
       env = {
         ANTHROPIC_BASE_URL = "http://localhost:8000";
         # ...
       };
     })
   ];
   ```

3. **Profile-specific aliases**:
   ```nix
   home.shellAliases = {
     cg = "claude-glm";
     ca = "claude";  # anthropic
   };
   ```

4. **Wrapper function abstraction** (if many profiles needed):
   ```nix
   let
     mkClaudeProfile = { name, apiBase, apiKey, models }: {
       # Generic wrapper generator
     };
   in {
     home.packages = [
       (mkClaudeProfile { name = "glm"; ... })
       (mkClaudeProfile { name = "openrouter"; ... })
     ];
   }
   ```

## References

- User preferences:
  - `~/.claude/commands/preferences/nix-development.md`
  - `~/.claude/commands/preferences/secrets.md`
  - `~/.claude/commands/preferences/architectural-patterns.md`

- Existing configuration:
  - `modules/home/all/tools/claude-code/default.nix` (unchanged)
  - `modules/home/all/core/sops.nix`
  - `.sops.yaml`

- Upstream references:
  - home-manager claude-code module: `home-manager/modules/programs/claude-code.nix`
  - Anthropic devcontainer.json: [github.com/anthropics/claude-code](https://github.com/anthropics/claude-code/blob/main/.devcontainer/devcontainer.json#L50)

## Summary

This implementation provides:

✅ **Complete isolation**: Separate config directories via `CLAUDE_CONFIG_DIR`
✅ **Zero duplication**: Settings shared via nix store symlinks
✅ **Declarative**: Fully managed in Nix configuration
✅ **Maintainable**: No modification to existing working configuration
✅ **Extensible**: Easy to add more profiles following the same pattern
✅ **Secure**: Secrets managed via sops-nix with proper permissions
✅ **Type-safe**: Leverages module system and nix store guarantees

Ready for Phase 3 implementation.
