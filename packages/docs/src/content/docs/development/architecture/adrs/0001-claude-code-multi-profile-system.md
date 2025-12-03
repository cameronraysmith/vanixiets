---
title: "ADR-0001: Claude Code Multi-Profile System"
---

- **Status**: Implemented
- **Date**: 2025-10-15
- **Scope**: Development tooling

## Context

Need for seamless switching between multiple Claude Code API providers (Anthropic official, GLM-4.6 via Z.ai) while maintaining complete isolation and reproducibility. The home-manager `programs.claude-code` module hardcodes output to `.claude/settings.json` and does not support multiple profiles.

## Decision

Implement wrapper-based configuration system using `CLAUDE_CONFIG_DIR` environment variable for profile isolation. Each profile gets a standalone wrapper module without modifying existing configuration, sharing settings/commands/agents via nix store symlinks (single source of truth) while managing secrets declaratively with sops-nix integration.

**Implementation commits**:
- `0be310c` - secrets: add llm-api-keys.yaml for GLM-4.6 profile
- `3ab6c90` - feat: add claude-code-wrappers module for multi-profile support
- `8628bb4` - feat: enable claude-code-wrappers module
- `23e968c` - fix: satisfy shellcheck SC2155 in claude-glm wrapper

## Consequences

### Positive

- Complete isolation: Separate config directories via `CLAUDE_CONFIG_DIR`
- Zero duplication: Settings shared via nix store symlinks
- Declarative: Fully managed in nix configuration
- Maintainable: No modification to existing working configuration
- Extensible: Easy to add more profiles following the same pattern
- Secure: Secrets managed via sops-nix with proper permissions
- Type-safe: Leverages module system and nix store guarantees

### Negative

- Additional wrapper modules to maintain
- Slightly more complex than single-profile setup
- Users must remember which command to use for which profile

## Architecture

### Key components

**Default profile** (`claude` command):
- Configuration: `modules/home/all/tools/claude-code/default.nix`
- Config directory: `~/.claude/`
- API endpoint: Anthropic official API
- Managed by: home-manager's `programs.claude-code` module

**GLM profile** (`claude-glm` command):
- Configuration: `modules/home/all/tools/claude-code-wrappers.nix`
- Config directory: `~/.config/claude-glm/`
- API endpoint: Z.ai (https://api.z.ai/api/anthropic)
- Managed by: Custom wrapper module

### Profile isolation mechanism

Each profile uses a separate `CLAUDE_CONFIG_DIR` to maintain complete isolation:

```
~/.claude/                          # Default profile
├── settings.json → /nix/store/.../claude-code-settings.json
├── commands/ → /nix/store/.../commands/
├── agents/ → /nix/store/.../agents/
├── .claude.json                    # Session data (isolated)
└── debug/                          # Logs (isolated)

~/.config/claude-glm/               # GLM profile
├── settings.json → /nix/store/.../claude-code-settings.json  (same file!)
├── commands/ → /nix/store/.../commands/  (same directory!)
├── agents/ → /nix/store/.../agents/  (same directory!)
├── .claude.json                    # Session data (isolated)
└── debug/                          # Logs (isolated)
```

**Shared resources** (via symlinks to identical nix store paths):
- `settings.json` - Permissions, theme, preferences
- `commands/` - Custom slash commands (API-agnostic)
- `agents/` - Agent definitions (API-agnostic)

**Isolated resources** (separate per profile):
- `.claude.json` - Session state, active conversations
- `debug/` - API interaction logs
- `statsig/` - Analytics data

### Secrets management

Secrets are managed using **sops-nix** with age encryption following the established pattern from `mcp-servers.nix`:

**Secrets file**: `secrets/users/crs58/llm-api-keys.yaml`
```yaml
glm-api-key: ENC[AES256_GCM,data:...] # Encrypted with age
```

**Module declaration**:
```nix
llmSecretsFile = flake.inputs.self + "/secrets/users/${config.home.username}/llm-api-keys.yaml";

sops.secrets."glm-api-key" = {
  sopsFile = llmSecretsFile;  # Explicit secrets file reference
  key = "glm-api-key";        # Key within the YAML file
  # mode = "0400" (default)   # Read-only for owner
};
```

**Runtime resolution**:
```bash
# Wrapper script reads decrypted secret at execution time
GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
export GLM_API_KEY
export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
```

**Security properties**:
- Secrets never appear in nix store (derivations remain pure)
- Decryption happens at system activation, not build time
- Runtime paths have 0400 permissions (owner-only read)
- Effects explicitly handled at wrapper boundary
- User-specific encryption (not shared across all hosts)

### Wrapper module implementation

**Location**: `modules/home/all/tools/claude-code-wrappers.nix`

**Module structure**:
```nix
{ config, pkgs, lib, flake, ... }:
let
  home = config.home.homeDirectory;
  llmSecretsFile = flake.inputs.self + "/secrets/users/${config.home.username}/llm-api-keys.yaml";
in
{
  # Declare sops secret
  sops.secrets."glm-api-key" = {
    sopsFile = llmSecretsFile;
    key = "glm-api-key";
  };

  # Generate wrapper script
  home.packages = [
    (pkgs.writeShellApplication {
      name = "claude-glm";
      runtimeInputs = [ config.programs.claude-code.finalPackage ];
      text = ''
        export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-glm"
        mkdir -p "$CLAUDE_CONFIG_DIR"

        GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
        export GLM_API_KEY
        export ANTHROPIC_BASE_URL="https://api.z.ai/api/anthropic"
        export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
        export ANTHROPIC_DEFAULT_OPUS_MODEL="glm-4.6"
        export ANTHROPIC_DEFAULT_SONNET_MODEL="glm-4.6"
        export ANTHROPIC_DEFAULT_HAIKU_MODEL="glm-4.5-air"

        exec claude "$@"
      '';
    })
  ];

  # Share configuration via symlinks
  xdg.configFile."claude-glm/settings.json" = {
    source = config.home.file.".claude/settings.json".source;
  };

  xdg.configFile."claude-glm/commands" = lib.mkIf (config.programs.claude-code.commandsDir != null) {
    source = config.programs.claude-code.commandsDir;
    recursive = true;
  };

  xdg.configFile."claude-glm/agents" = lib.mkIf (config.programs.claude-code.agentsDir != null) {
    source = config.programs.claude-code.agentsDir;
    recursive = true;
  };
}
```

**Import**: Added to `modules/home/all/tools/default.nix`:
```nix
{
  imports = [
    # ... existing imports
    ./claude-code
    ./claude-code-wrappers.nix
    # ... more imports
  ];
}
```

## Operations

### Verification commands

After applying the configuration, verify the system works correctly:

**1. Check wrapper script exists**:
```bash
which claude-glm
# Expected: /etc/profiles/per-user/crs58/bin/claude-glm
```

**2. Verify isolated config creation**:
```bash
claude-glm --version
ls -la ~/.config/claude-glm/
# Expected: settings.json, commands/, agents/, .claude.json, etc.
```

**3. Confirm settings are shared**:
```bash
readlink ~/.claude/settings.json
readlink ~/.config/claude-glm/settings.json
# Expected: Identical nix store paths
```

**4. Verify commands directory is shared**:
```bash
readlink ~/.claude/commands
readlink ~/.config/claude-glm/commands
# Expected: Identical nix store paths
```

**5. Verify agents directory is shared**:
```bash
readlink ~/.claude/agents
readlink ~/.config/claude-glm/agents
# Expected: Identical nix store paths
```

**6. Check secret accessibility**:
```bash
cat ~/.config/sops-nix/secrets/glm-api-key
# Expected: Your GLM API key (plaintext after decryption)
```

**7. Test profile isolation**:
```bash
# Terminal 1
claude "Start conversation A with Anthropic"

# Terminal 2
claude-glm "Start conversation B with GLM"

# Verify: ~/.claude/.claude.json only contains conversation A
# Verify: ~/.config/claude-glm/.claude.json only contains conversation B
```

### Managing secrets

**View encrypted secret**:
```bash
cat secrets/users/crs58/llm-api-keys.yaml
# Shows: glm-api-key: ENC[AES256_GCM,data:...]
```

**Update GLM API key**:
```bash
sops secrets/users/crs58/llm-api-keys.yaml
# Edit in opened editor, save, sops encrypts automatically
```

**Verify decryption**:
```bash
sops -d secrets/users/crs58/llm-api-keys.yaml
# Shows plaintext for verification
```

**After updating secrets, reapply configuration**:
```bash
sudo darwin-rebuild switch --flake .
```

## Design rationale

### Why wrapper modules?

The home-manager `programs.claude-code` module:
- Provides a single `programs.claude-code` option
- Hardcodes output to `.claude/settings.json`
- Does not support multiple profiles or config directories
- Cannot be extended without `disabledModules` (fragile approach)

A wrapper module approach:
- Requires zero modification to existing working configuration
- Maintains single source of truth for settings (via symlinks)
- Is simple and maintainable (no module system hacks)
- Provides clear separation (wrappers are extensions, not replacements)
- Enables complete isolation via `CLAUDE_CONFIG_DIR`

### Why share settings/commands/agents?

**Settings**: Permissions, theme, and preferences should be consistent across profiles. API-specific behavior is controlled by environment variables, not settings.

**Commands**: Custom slash commands (in `~/.claude/commands/`) are API-agnostic and work identically across providers.

**Agents**: Agent definitions are API-agnostic and benefit from consistency.

**Alternative**: If per-profile customization is needed later, settings can be overridden:
```nix
xdg.configFile."claude-glm/settings.json".source = jsonFormat.generate "..." (
  config.programs.claude-code.settings // {
    cleanupPeriodDays = 30;  # Profile-specific override
  }
);
```

### Why user-specific secrets?

Using `secrets/users/crs58/llm-api-keys.yaml` rather than `secrets/shared.yaml`:
- Separates LLM API keys from MCP server keys (logical organization)
- Encrypts only for keys that need access (dev, admin, user identity)
- Follows established pattern from `mcp-servers.nix`
- Enables per-user API key management in multi-user systems
- Allows future expansion for other LLM providers without polluting shared secrets

### Why runtime secret resolution?

Loading secrets in wrapper script rather than nix config:
- Keeps nix store pure (no secrets in derivations)
- Enables runtime decryption (secrets resolved at activation, not build)
- Provides proper permissions (0400, owner-only read)
- Makes effects explicit at system boundaries
- Follows functional programming principles (effects isolated at edges)

## Architectural principles applied

From `~/.claude/commands/preferences/architectural-patterns.md`:

**Side effects explicit in type signatures**: Environment variables declared explicitly in wrapper script

**Effects isolated at boundaries**: Secret resolution and API configuration at wrapper boundary, not in pure nix config

**Declarative over imperative**: All configuration in nix expressions, no manual file editing

**Single source of truth**: Settings reused via symlink, not duplicated

**Composable abstractions**: Wrapper approach allows arbitrary profile additions without modifying existing code

From `~/.claude/commands/preferences/nix-development.md`:

**Flake-based**: All configuration in flake, not channels

**Modular structure**: Wrapper module in `modules/home/all/tools/`

**Type-safe**: Uses module system options properly

**Cross-platform**: Uses `xdg.configHome` for portability

From `~/.claude/commands/preferences/secrets.md`:

**sops-nix integration**: Secrets encrypted in git, decrypted at activation

**Runtime resolution**: API keys loaded at execution time, not build time

**Proper permissions**: Secret files restricted to owner-only read (0400)

**Explicit handling**: Secret access explicit in wrapper script

## Future enhancements

### Per-profile settings customization

If profiles need different settings:
```nix
xdg.configFile."claude-glm/settings.json".source = jsonFormat.generate "..." (
  config.programs.claude-code.settings // {
    cleanupPeriodDays = 30;  # More aggressive cleanup for testing
  }
);
```

### Additional profiles

Adding profiles for other providers (OpenRouter, local LLM, etc.):
```nix
home.packages = [
  (pkgs.writeShellApplication {
    name = "claude-openrouter";
    runtimeInputs = [ config.programs.claude-code.finalPackage ];
    text = ''
      export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-openrouter"
      mkdir -p "$CLAUDE_CONFIG_DIR"

      OPENROUTER_API_KEY="$(cat ${config.sops.secrets."openrouter-api-key".path})"
      export OPENROUTER_API_KEY
      export ANTHROPIC_BASE_URL="https://openrouter.ai/api/v1"
      export ANTHROPIC_AUTH_TOKEN="$OPENROUTER_API_KEY"

      exec claude "$@"
    '';
  })
];
```

### Profile-specific shell aliases

For convenience:
```nix
home.shellAliases = {
  cg = "claude-glm";      # GLM/Z.ai
  ca = "claude";          # Anthropic
  cor = "claude-openrouter";  # OpenRouter
};
```

### Wrapper function abstraction

If managing many profiles, create a generic wrapper generator:
```nix
let
  mkClaudeProfile = { name, apiBase, apiKeySecret, models ? {} }:
    pkgs.writeShellApplication {
      name = "claude-${name}";
      runtimeInputs = [ config.programs.claude-code.finalPackage ];
      text = ''
        export CLAUDE_CONFIG_DIR="${config.xdg.configHome}/claude-${name}"
        mkdir -p "$CLAUDE_CONFIG_DIR"

        API_KEY="$(cat ${config.sops.secrets."${apiKeySecret}".path})"
        export API_KEY
        export ANTHROPIC_BASE_URL="${apiBase}"
        export ANTHROPIC_AUTH_TOKEN="$API_KEY"
        ${lib.optionalString (models ? opus) ''export ANTHROPIC_DEFAULT_OPUS_MODEL="${models.opus}"''}
        ${lib.optionalString (models ? sonnet) ''export ANTHROPIC_DEFAULT_SONNET_MODEL="${models.sonnet}"''}
        ${lib.optionalString (models ? haiku) ''export ANTHROPIC_DEFAULT_HAIKU_MODEL="${models.haiku}"''}

        exec claude "$@"
      '';
    };
in {
  home.packages = [
    (mkClaudeProfile {
      name = "glm";
      apiBase = "https://api.z.ai/api/anthropic";
      apiKeySecret = "glm-api-key";
      models = { opus = "glm-4.6"; sonnet = "glm-4.6"; haiku = "glm-4.5-air"; };
    })
    (mkClaudeProfile {
      name = "openrouter";
      apiBase = "https://openrouter.ai/api/v1";
      apiKeySecret = "openrouter-api-key";
    })
  ];
}
```

## References

### Internal documentation
- `~/.claude/commands/preferences/nix-development.md` - Nix development guidelines
- `~/.claude/commands/preferences/secrets.md` - Secrets management patterns
- `~/.claude/commands/preferences/architectural-patterns.md` - Architecture principles

### Configuration files
- `modules/home/all/tools/claude-code/default.nix` - Default profile configuration (unchanged)
- `modules/home/all/tools/claude-code-wrappers.nix` - Wrapper module implementation
- `modules/home/all/core/sops.nix` - sops-nix system configuration
- `.sops.yaml` - Secrets encryption rules

### Upstream references
- [home-manager claude-code module](https://github.com/nix-community/home-manager/blob/master/modules/programs/claude-code.nix)
- [Anthropic devcontainer.json](https://github.com/anthropics/claude-code/blob/main/.devcontainer/devcontainer.json#L50) - CLAUDE_CONFIG_DIR usage example
- [sops-nix documentation](https://github.com/Mic92/sops-nix)

## Current implementation

**Active profiles**:
- `claude` - Anthropic official API (default)
- `claude-glm` - GLM-4.6 via Z.ai API
