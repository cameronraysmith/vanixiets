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
- Secrets in: `secrets/users/{username}/` (user-specific) and `secrets/shared.yaml` (shared)
- Configuration pattern: User-specific secrets files with explicit `sopsFile` reference
- `.sops.yaml` defines key groups for dev, ci, admin, users, and hosts

**Established pattern** (from mcp-servers.nix):
```nix
mcpSecretsFile = flake.inputs.self + "/secrets/users/${config.home.username}/mcp-api-keys.yaml";

sops.secrets."mcp-firecrawl-api-key" = {
  sopsFile = mcpSecretsFile;
  key = "firecrawl-api-key";
};
```

For GLM API key (following established pattern):
1. Create `secrets/users/crs58/llm-api-keys.yaml` (separate from MCP keys)
2. Add `glm-api-key` entry (sops-encrypted)
3. Expose via `sops.secrets."glm-api-key"` with explicit `sopsFile` and `key` in wrapper module
4. Reference in wrapper script: `$(cat ${config.sops.secrets."glm-api-key".path})`

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
{ config, pkgs, lib, flake, ... }:
let
  home = config.home.homeDirectory;
  # User-specific LLM API keys (separate from MCP server keys)
  # Pattern: secrets/users/{username}/llm-api-keys.yaml
  llmSecretsFile = flake.inputs.self + "/secrets/users/${config.home.username}/llm-api-keys.yaml";
in
{
  # Define sops secret for GLM API key (following established pattern)
  sops.secrets."glm-api-key" = {
    sopsFile = llmSecretsFile;
    key = "glm-api-key";
  };

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
        export GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"

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
   - sops secret exposure with explicit `sopsFile` and `key`

2. **`modules/home/all/tools/default.nix`** (modify)
   - Add `./claude-code-wrappers.nix` to imports

3. **`secrets/users/crs58/llm-api-keys.yaml`** (new)
   - Create new user-specific secrets file for LLM API keys
   - Add encrypted `glm-api-key` entry
   - Allows future addition of other LLM provider keys (OpenRouter, local models, etc.)

4. **`.sops.yaml`** (verify/update if needed)
   - Ensure `users/crs58/.*\.yaml$` rule exists for encrypting user-specific secrets

Will **NOT** modify:
- `modules/home/all/tools/claude-code/default.nix` - unchanged
- `modules/home/all/core/sops.nix` - unchanged (secret exposure in wrapper module)
- `secrets/shared.yaml` - unchanged (using user-specific secrets instead)

### Secrets integration strategy

**Runtime resolution via wrapper script** (following established pattern from mcp-servers.nix):

```nix
# User-specific secrets file reference
llmSecretsFile = flake.inputs.self + "/secrets/users/${config.home.username}/llm-api-keys.yaml";

# Explicit sops secret declaration with sopsFile and key
sops.secrets."glm-api-key" = {
  sopsFile = llmSecretsFile;
  key = "glm-api-key";
  # mode defaults to 0400 (read-only for owner)
};

# In wrapper script:
export GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
```

The sops-nix module:
1. Decrypts `glm-api-key` from `secrets/users/crs58/llm-api-keys.yaml` at activation time
2. Writes decrypted value to a runtime path (e.g., `/run/user/501/secrets/glm-api-key`)
3. Wrapper script reads this file at execution time
4. Environment variable set for the claude process

**Why this approach**:
- ✅ Secrets never appear in nix store (derivations remain pure)
- ✅ Runtime resolution (decryption happens at activation, not build)
- ✅ Proper permissions (0400, owner-only read by default)
- ✅ Explicit effect handling at boundary (wrapper script, not nix config)
- ✅ Consistent with established mcp-servers.nix pattern
- ✅ User-specific secrets (encrypted for user keys, not all hosts)

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
4. **Use user-specific secrets file** `secrets/users/crs58/llm-api-keys.yaml` for GLM key (following mcp-servers.nix pattern)
5. **Runtime environment variables** for API endpoint and authentication
6. **`CLAUDE_CONFIG_DIR` isolation** for session and history separation
7. **Explicit sops pattern** with `sopsFile` and `key` attributes (consistent with existing usage)

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
{ config, pkgs, lib, flake, ... }:
let
  home = config.home.homeDirectory;
  # User-specific LLM API keys (separate from MCP server keys)
  llmSecretsFile = flake.inputs.self + "/secrets/users/${config.home.username}/llm-api-keys.yaml";
in
{
  # Define sops secret for GLM API key (following mcp-servers.nix pattern)
  sops.secrets."glm-api-key" = {
    sopsFile = llmSecretsFile;
    key = "glm-api-key";
  };

  # GLM wrapper script
  home.packages = [
    (pkgs.writeShellApplication {
      name = "claude-glm";
      runtimeInputs = [ config.programs.claude-code.finalPackage ];
      text = ''
        export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"
        mkdir -p "$CLAUDE_CONFIG_DIR"

        export GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
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

1. Create new LLM secrets file:
   ```bash
   cd ~/projects/nix-workspace/nix-config

   # Create the file with sops (will encrypt on save)
   sops secrets/users/crs58/llm-api-keys.yaml
   ```

2. Add GLM API key (in editor that sops opens):
   ```yaml
   # secrets/users/crs58/llm-api-keys.yaml
   glm-api-key: "your-glm-4.6-api-key-from-z.ai"
   ```

   Or use a test value initially:
   ```yaml
   glm-api-key: "test-glm-api-key-replace-later"
   ```

3. Verify encryption:
   ```bash
   # File should be encrypted
   cat secrets/users/crs58/llm-api-keys.yaml | head -5
   # Should show: glm-api-key: ENC[AES256_GCM,data:...

   # Verify decryption works
   sops -d secrets/users/crs58/llm-api-keys.yaml
   # Should show plaintext: glm-api-key: your-glm-4.6-api-key-from-z.ai
   ```

4. Verify `.sops.yaml` rule exists:
   ```bash
   grep -A 5 "users/crs58/" .sops.yaml
   # Should show encryption rule for users/crs58/*.yaml files
   ```

   Expected rule (already exists in your `.sops.yaml`):
   ```yaml
   - path_regex: users/crs58/.*\.yaml$
     key_groups:
       - age:
         - *admin
         - *dev
         - *admin-user
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
   ls -la $(nix eval --raw .#darwinConfigurations.blackphos.config.sops.secrets.\"glm-api-key\".path)
   # Should show: -r-------- (0400)

   # Verify secret can be read
   cat $(nix eval --raw .#darwinConfigurations.blackphos.config.sops.secrets.\"glm-api-key\".path)
   # Should show your GLM API key
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
