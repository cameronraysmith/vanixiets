---
title: MCP + SOPS-nix Integration Plan
---

## Objective
Integrate Model Context Protocol (MCP) server configurations into nix-config using SOPS-nix for secrets, aligned with nixos-unified patterns. Preserve portability across NixOS and nix-darwin and compatibility with Claude Desktop/Code.

## Summary of Findings (Context)
- nix-config already imports the home-manager SOPS module and centralizes SOPS defaults:
  - inputs.sops-nix.homeManagerModules.sops is imported in modules/home/default.nix
  - Age key location and default SOPS file set in modules/home/all/core/sops.nix
  - .sops.yaml exists with rules for users/, hosts/, and services/ (shared, CI, hosts)
  - secrets/ tree already present (services/, hosts/, users/)
- Existing HM structure (nixos-unified style): modules/home/all/* with topical modules (tools/claude-code present). Good place to add user-level MCP.
- Reference repo fred-drake-nix-claude-mcp-sops-ccstatusline provides examples of MCP server packaging (apps/gitea-mcp.nix) and SOPS modules (modules/secrets/*) that we can mirror conceptually (not necessarily the same servers).

## Design Goals
- Modularity: enable/disable each MCP server independently per user.
- Security: all credentials in SOPS, never in plain nix store or VCS.
- Declarative and reproducible: MCP JSON files generated from nix expressions/templates.
- Compatibility: generate ~/.mcp/*.json (Claude Desktop/Code and other clients).
- Cross-platform: works via home-manager on both NixOS and nix-darwin.
- Minimal rebuild churn: allow secrets/config updates without full system rebuild; home-manager switch is sufficient.

## Proposed File/Module Structure
- modules/home/all/tools/mcp/
  - default.nix            # HM module exposing programs.mcp.* options and generating ~/.mcp/*.json
  - servers/
    - github.nix           # Example server module (pattern)
    - <others>.nix         # Additional servers as needed
- secrets/services/mcp/
  - <server>.yaml          # Encrypted secrets per server (SOPS-managed)
- docs/development/auggie-gpt-mcp-sops-integration-plan.md (this file)

Optional (later):
- packages or overlays for MCP servers built from source (similar to gitea-mcp in the reference) if we need pinned binaries.

## Integration Architecture

### 1) Home-manager module (user-level; primary)
- Define programs.mcp with:
  - enable (bool)
  - servers (attrset of server definitions)
  - Each server:<
    - enable (bool)
    - name (string) -> results in ~/.mcp/<name>.json
    - package (optional) -> pkgs.<tool> for the MCP server executable if needed
    - config (attrset) -> non-secret JSON configuration portion
    - secrets (attrset) -> keys and references to SOPS secret paths under secrets/services/mcp/
- Implementation pattern:
  - For each enabled server, create a sops.template "mcp-<name>.json" owned by the user with 0400 mode; template content is JSON using SOPS placeholders for secret values.
  - Link ~/.mcp/<name>.json to that template via home.file.
  - Optionally add the server package to home.packages.

### 2) SOPS-nix integration (already present)
- We will rely on HM’s sops module (already imported) to define:
  - sops.secrets."services/mcp/<server>/<key>".sopsFile = ../../../../secrets/services/mcp/<server>.yaml
  - sops.templates."mcp-<server>.json" with owner, group, mode, and placeholder-driven content
- .sops.yaml already permits services/*.yaml; nesting services/mcp/ remains covered by the services rule.

### 3) System-level (optional/rare)
- If any MCP server must run as a long-lived daemon (systemd user service), add an optional programs.mcp.servers.<name>.service.enable to define a systemd.user unit with EnvironmentFile pointing at SOPS-managed files. Most MCP servers used by Claude are launched by the client and do not require this.

## SOPS-nix Conventions
- Age key path: already configured to $XDG_CONFIG_HOME/sops/age/keys.txt
- Default SOPS file: secrets/shared.yaml (can be overridden per secret)
- Per-server encrypted files under secrets/services/mcp/<server>.yaml
- Access control: template owner=user, mode=0400 to minimize exposure

## Configuration Management
- Convert ~/.mcp/*.json to nix:
  - Lift non-secret fields into programs.mcp.servers.<name>.config (pure attrset)
  - Map secret fields to SOPS placeholders via programs.mcp.servers.<name>.secrets
  - Generate JSON via sops.templates so final files contain actual secret values at activation time, not at evaluation time
- Multiple servers supported simply by adding entries to programs.mcp.servers
- Per-environment overrides through HM profiles (e.g., homeConfigurations) or by selective inclusion of secrets files

## Compatibility Notes
- Claude Desktop/Claude Code: both can consume ~/.mcp/*.json. This plan generates those files exactly.
- Updates without rebuilding system: changes to secrets or HM config applied via home-manager switch.
- Works on NixOS and nix-darwin by virtue of HM + sops-nix HM module.

## Example Key Integration Points (minimal examples)

### Example SOPS secrets file (encrypted): secrets/services/mcp/github.yaml
```yaml
# sops-encrypted
mcp:
  github:
    token: "<encrypted>"
```

### Example HM module usage (in a user’s HM config)
```nix
programs.mcp = {
  enable = true;
  servers.github = {
    enable = true;
    name = "github";
    config = {
      server = {
        command = "github-mcp";
        args = [ ];
      };
      env = { }; # non-secret env if needed
    };
    secrets = {
      # maps to .mcp JSON keys we’ll inject
      GITHUB_TOKEN = {
        sopsPath = "services/mcp/github/token";
        file = ../../../../secrets/services/mcp/github.yaml;
      };
    };
  };
};
```

### Example implementation pattern inside modules/home/all/tools/mcp/default.nix
```nix
# Pseudocode outline
{ config, lib, pkgs, ... }:
let cfg = config.programs.mcp; in
{
  options.programs.mcp = { enable = lib.mkEnableOption "MCP"; servers = lib.mkOption { type = lib.types.attrsOf (lib.types.submodule ...); default = {}; }; };

  config = lib.mkIf cfg.enable {
    # Ensure ~/.mcp exists
    home.file.".mcp/".directory = true;

    # For each server
    assertions = [ ];
    # Define sops.secrets + sops.templates per server, then link to ~/.mcp/<name>.json
  };
}
```

### Example sops.templates per server (render to ~/.mcp/github.json)
```nix
# For server = github; user is config.home.username
sops.secrets."services/mcp/github/token".sopsFile = ../../../../secrets/services/mcp/github.yaml;
sops.templates."mcp-github.json" = {
  owner = config.home.username;
  mode = "0400";
  content = builtins.toJSON {
    server = cfg.servers.github.config.server;
    env = {
      GITHUB_TOKEN = config.sops.placeholder."services/mcp/github/token";
    };
  };
};
home.file.".mcp/github.json".source = config.sops.templates."mcp-github.json".path;
```

## Migration Strategy (per MCP server)
1) Inventory current ~/.mcp/*.json for the target user(s) and list all fields. Identify secrets (tokens, API keys), non-secrets, and external dependencies.
2) For each server <name>:
   - Create secrets/services/mcp/<name>.yaml and add encrypted keys using sops (age) per existing .sops.yaml rules.
   - Add a programs.mcp.servers.<name> entry with non-secret config in config attrset.
   - Map each secret field to secrets.<key>.sopsPath in the server definition.
3) Implement/extend modules/home/all/tools/mcp/default.nix to:
   - Define sops.secrets for each referenced sopsPath
   - Create sops.templates "mcp-<name>.json" with placeholder substitution
   - Link to ~/.mcp/<name>.json
4) home-manager switch to generate files; verify chmod 0400 and ownership.
5) Launch Claude Desktop/Code and confirm MCP servers appear and connect.

## Testing Strategy
- Static
  - Validate generated JSON: jq . ~/.mcp/<name>.json
  - Ensure secrets present at runtime but not in nix store: nix-store --query --requisites ~/.mcp/<name>.json should not include secrets content paths
- Functional
  - Start Claude Desktop/Code; verify server discovery and status
  - For CLI MCP servers, run the binary with --version or a ping command
- Security
  - Confirm file permissions (0400) and ownership
  - Confirm secrets/services/mcp/*.yaml are encrypted (sops -d prompts for key)

## Rollback Plan
- Keep a backup of the original ~/.mcp directory (e.g., ~/.mcp.bak-<date>) before first switch.
- programs.mcp.enable = false or server.enable = false will remove links from ~/.mcp without touching SOPS data.
- If an MCP server misbehaves, disable that server, restore its ~/.mcp/<name>.json from backup, and relaunch the client.

## Next Steps
1) Implement modules/home/all/tools/mcp/default.nix skeleton with options and per-server loop.
2) Migrate a single low-risk server first (e.g., one with a single token) to validate template flow.
3) Extend to remaining servers; document each server’s fields and secret mappings in comments near their HM definitions.
4) Add a docs/README snippet describing how to add a new MCP server.

