# MCP Server + SOPS-nix Integration Plan

**Generated:** 2025-10-14  
**Objective:** Integrate Model Context Protocol (MCP) server configurations from `fred-drake-nix-claude-mcp-sops-ccstatusline/` into `./nix-config/` with SOPS-nix secrets management

---

## Executive Summary

This plan provides a comprehensive strategy to integrate MCP server configurations into the nix-config repository while maintaining security through SOPS-nix encryption. The implementation follows nixos-unified patterns and leverages the existing home-manager claude-code module structure.

### Key Findings from Reference Implementation

**Fred Drake's Implementation (`fred-drake-nix-claude-mcp-sops-ccstatusline/`):**
- Uses `sops.templates` to generate MCP configuration JSON files at `~/mcp/*.json`
- Injects secrets via `config.sops.placeholder.*` references
- Separates MCP servers into individual JSON files (one per server or logical group)
- Integrates with home-manager's claude-code module
- Stores secrets in structured YAML files with age encryption

**Current nix-config State:**
- SOPS-nix already configured with age keys in `~/.config/sops/age/keys.txt`
- Existing `.sops.yaml` with comprehensive key management (dev, CI, admin, user, host keys)
- Home-manager claude-code module at `modules/home/all/tools/claude-code/default.nix`
- Secrets directory structure: `secrets/{hosts,services,users,shared.yaml}`
- Scripts for SOPS key management in `scripts/sops/`

---

## Phase 1: Context Gathering (Completed)

### 1.1 Reference Implementation Analysis

**MCP Servers Identified in Fred Drake's Config:**
1. **browser** - Browser automation via npx
2. **brave-search** - Brave Search API (requires API key)
3. **playwright** - Browser automation via Podman container
4. **context7** - Upstash context management
5. **sonarqube** - Code quality analysis (requires token + URL)
6. **gitea-personal** - Gitea integration (requires access token)
7. **gitea-engineer** - Gitea with engineer role token
8. **gitea-product-owner** - Gitea with product owner token
9. **gitea-code-architect** - Gitea with architect token
10. **gitea-reviewer** - Gitea with reviewer token
11. **github** - GitHub integration via Podman (requires PAT)
12. **ref** - Reference tools (requires API key)
13. **shadcn** - Shadcn UI components
14. **firecrawl** - Web scraping (requires API key)
15. **stripe-sandbox** - Stripe API sandbox (requires API key)

**Secrets Required:**
- `llm-brave` - Brave Search API key
- `sonarqube-token` - SonarQube authentication token
- `personal-gitea-token` - Personal Gitea access token
- `product-owner-gitea-token` - Product owner Gitea token
- `engineer-gitea-token` - Engineer Gitea token
- `code-architect-gitea-token` - Code architect Gitea token
- `reviewer-gitea-token` - Reviewer Gitea token
- `github-token` - GitHub personal access token
- `ref-mcp-api-key` - Ref tools API key
- `firecrawl-api-key` - Firecrawl API key
- `stripe-sandbox-api-key` - Stripe sandbox API key

### 1.2 Home-Manager Claude-Code Module Capabilities

The upstream home-manager module (`home-manager/modules/programs/claude-code.nix`) provides:
- `programs.claude-code.mcpServers` option (attrsOf jsonFormat.type)
- Direct integration with settings.json generation
- Support for stdio, http, and websocket MCP server types
- Environment variable injection via `env` attribute

**Key Insight:** The home-manager module generates a single `settings.json` with embedded MCP server configurations, NOT separate `~/mcp/*.json` files like Fred Drake's approach.

---

## Phase 2: Architecture Design

### 2.1 Module Organization Strategy

**Recommended Structure:**
```
nix-config/
├── modules/home/all/tools/
│   ├── claude-code/
│   │   ├── default.nix              # Main claude-code config (existing)
│   │   ├── mcp-servers.nix          # NEW: MCP server definitions
│   │   ├── mcp-secrets.nix          # NEW: SOPS secrets for MCP
│   │   ├── commands/                # Existing commands
│   │   └── agents/                  # Existing agents
│   └── ...
├── secrets/
│   ├── users/crs58/
│   │   └── mcp-api-keys.yaml        # NEW: User-specific MCP secrets
│   ├── services/
│   │   └── mcp-services.yaml        # NEW: Service-level MCP secrets
│   └── shared.yaml                  # Existing shared secrets
└── packages/
    └── mcp-servers/                 # NEW: Custom MCP server packages
        ├── default.nix
        └── gitea-mcp.nix            # Port from Fred Drake's config
```

### 2.2 SOPS-nix Integration Pattern

**Two-Layer Approach:**

**Layer 1: SOPS Secrets Declaration** (`mcp-secrets.nix`)
```nix
{
  config,
  lib,
  ...
}:
{
  sops.secrets = {
    # API Keys
    "mcp/brave-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
    };
    "mcp/github-token" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
    };
    "mcp/firecrawl-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
    };
    # Service tokens
    "mcp/gitea-personal-token" = {
      sopsFile = ../../../../secrets/services/mcp-services.yaml;
    };
    "mcp/sonarqube-token" = {
      sopsFile = ../../../../secrets/services/mcp-services.yaml;
    };
  };
}
```

**Layer 2: MCP Server Definitions** (`mcp-servers.nix`)
```nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Helper to read secret file path
  secretPath = name: config.sops.secrets."mcp/${name}".path;
in
{
  programs.claude-code.mcpServers = {
    brave-search = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
      env = {
        BRAVE_API_KEY = "$(cat ${secretPath "brave-api-key"})";
      };
    };
    
    github = {
      command = "podman";
      args = [ "run" "-i" "--rm" "-e" "GITHUB_PERSONAL_ACCESS_TOKEN" 
               "ghcr.io/github/github-mcp-server" ];
      env = {
        GITHUB_PERSONAL_ACCESS_TOKEN = "$(cat ${secretPath "github-token"})";
      };
    };
    
    # ... more servers
  };
}
```

### 2.3 Alternative: SOPS Templates Approach (Fred Drake Style)

If the home-manager module doesn't support runtime secret injection properly, use SOPS templates:

```nix
{
  config,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
  sops.templates."mcp-brave-search" = {
    mode = "0400";
    path = "${home}/.config/claude-code/mcp/brave-search.json";
    content = builtins.toJSON {
      mcpServers = {
        brave-search = {
          command = "npx";
          args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
          env = {
            BRAVE_API_KEY = config.sops.placeholder."mcp/brave-api-key";
          };
        };
      };
    };
  };
}
```

---

## Phase 3: Implementation Plan

### 3.1 Step-by-Step Migration Strategy

**Step 1: Create Secrets Structure**
1. Create `secrets/users/crs58/mcp-api-keys.yaml` with encrypted API keys
2. Create `secrets/services/mcp-services.yaml` with service tokens
3. Update `.sops.yaml` if needed for new secret paths
4. Use `sops` CLI to encrypt secrets: `sops secrets/users/crs58/mcp-api-keys.yaml`

**Step 2: Create MCP Secrets Module**
1. Create `modules/home/all/tools/claude-code/mcp-secrets.nix`
2. Declare all SOPS secrets with appropriate `sopsFile` references
3. Set proper permissions (mode = "0400" for API keys)

**Step 3: Create MCP Servers Module**
1. Create `modules/home/all/tools/claude-code/mcp-servers.nix`
2. Define MCP servers using `programs.claude-code.mcpServers`
3. Reference secrets via `config.sops.secrets."mcp/...".path`
4. Test with non-sensitive servers first (browser, shadcn, playwright)

**Step 4: Package Custom MCP Servers**
1. Port `gitea-mcp` package from Fred Drake's config to `packages/mcp-servers/gitea-mcp.nix`
2. Add to overlays if needed
3. Test build: `nix build .#gitea-mcp`

**Step 5: Update Main Claude-Code Module**
1. Import `mcp-secrets.nix` and `mcp-servers.nix` in `default.nix`
2. Add MCP server packages to `home.packages` if needed
3. Update permissions to allow MCP tool usage

**Step 6: Testing & Validation**
1. Build home-manager configuration: `nix build .#homeConfigurations.runner@stibnite.activationPackage`
2. Activate: `./result/activate`
3. Verify secrets are decrypted: `ls -la ~/.config/sops/age/keys.txt`
4. Test Claude Code with MCP servers: `claude --help`
5. Verify MCP server connections in Claude Code UI

### 3.2 Secrets File Structure

**`secrets/users/crs58/mcp-api-keys.yaml`** (encrypted with SOPS):
```yaml
brave-api-key: <encrypted>
github-token: <encrypted>
firecrawl-api-key: <encrypted>
ref-mcp-api-key: <encrypted>
stripe-sandbox-api-key: <encrypted>
```

**`secrets/services/mcp-services.yaml`** (encrypted with SOPS):
```yaml
gitea-personal-token: <encrypted>
gitea-engineer-token: <encrypted>
gitea-product-owner-token: <encrypted>
gitea-code-architect-token: <encrypted>
gitea-reviewer-token: <encrypted>
sonarqube-token: <encrypted>
sonarqube-url: https://sonarqube.example.com
```

### 3.3 Update `.sops.yaml` Creation Rules

Add to `.sops.yaml`:
```yaml
creation_rules:
  # ... existing rules ...
  
  # MCP API keys (user-specific)
  - path_regex: users/.*/mcp-api-keys\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *admin-user  # or *raquel-user depending on user
  
  # MCP service secrets (shared across hosts)
  - path_regex: services/mcp-services\.yaml$
    key_groups:
      - age:
        - *admin
        - *dev
        - *ci
        - *admin-user
        - *stibnite
        - *blackphos
        - *orb-nixos
```

---

## Phase 4: Detailed Code Snippets

### 4.1 Complete MCP Secrets Module

**File:** `modules/home/all/tools/claude-code/mcp-secrets.nix`
```nix
{
  config,
  lib,
  ...
}:
{
  # Declare SOPS secrets for MCP servers
  sops.secrets = {
    # API Keys (user-specific)
    "mcp/brave-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "brave-api-key";
    };
    "mcp/github-token" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "github-token";
    };
    "mcp/firecrawl-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "firecrawl-api-key";
    };
    "mcp/ref-mcp-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "ref-mcp-api-key";
    };
    "mcp/stripe-sandbox-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "stripe-sandbox-api-key";
    };
    
    # Service tokens (shared)
    "mcp/gitea-personal-token" = {
      sopsFile = ../../../../secrets/services/mcp-services.yaml;
      key = "gitea-personal-token";
    };
    "mcp/sonarqube-token" = {
      sopsFile = ../../../../secrets/services/mcp-services.yaml;
      key = "sonarqube-token";
    };
    "mcp/sonarqube-url" = {
      sopsFile = ../../../../secrets/services/mcp-services.yaml;
      key = "sonarqube-url";
    };
  };
}
```

### 4.2 Complete MCP Servers Module

**File:** `modules/home/all/tools/claude-code/mcp-servers.nix`
```nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  # Helper to read secret file path
  secretPath = name: config.sops.secrets."mcp/${name}".path;

  # Helper to create env var that reads from secret file
  secretEnv = name: "$(cat ${secretPath name})";
in
{
  programs.claude-code.mcpServers = {
    # No secrets required
    browser = {
      command = "npx";
      args = [ "@browsermcp/mcp@latest" ];
    };

    playwright = {
      command = "podman";
      args = [
        "run" "-i" "--rm" "--init" "--pull=always"
        "mcr.microsoft.com/playwright/mcp"
      ];
    };

    context7 = {
      command = "npx";
      args = [ "-y" "@upstash/context7-mcp" ];
    };

    shadcn = {
      command = "npx";
      args = [ "-y" "shadcn@latest" "mcp" ];
    };

    # Secrets required
    brave-search = {
      command = "npx";
      args = [ "-y" "@modelcontextprotocol/server-brave-search" ];
      env = {
        BRAVE_API_KEY = secretEnv "brave-api-key";
      };
    };

    github = {
      command = "podman";
      args = [
        "run" "-i" "--rm" "-e" "GITHUB_PERSONAL_ACCESS_TOKEN"
        "ghcr.io/github/github-mcp-server"
      ];
      env = {
        GITHUB_PERSONAL_ACCESS_TOKEN = secretEnv "github-token";
      };
    };

    firecrawl = {
      command = "npx";
      args = [ "-y" "firecrawl-mcp" ];
      env = {
        FIRECRAWL_API_KEY = secretEnv "firecrawl-api-key";
      };
    };

    ref = {
      command = "npx";
      args = [ "ref-tools-mcp@latest" ];
      env = {
        REF_API_KEY = secretEnv "ref-mcp-api-key";
      };
    };

    stripe-sandbox = {
      command = "npx";
      args = [ "-y" "@stripe/mcp" "--tools=all" ];
      env = {
        STRIPE_SECRET_KEY = secretEnv "stripe-sandbox-api-key";
      };
    };

    sonarqube = {
      command = "podman";
      args = [
        "run" "-i" "--rm"
        "-e" "SONARQUBE_TOKEN"
        "-e" "SONARQUBE_URL"
        "-e" "TELEMETRY_DISABLED"
        "mcp/sonarqube"
      ];
      env = {
        SONARQUBE_URL = secretEnv "sonarqube-url";
        SONARQUBE_TOKEN = secretEnv "sonarqube-token";
        TELEMETRY_DISABLED = "true";
      };
    };

    gitea-personal = {
      command = "${pkgs.gitea-mcp}/bin/gitea-mcp";
      args = [
        "-t" "stdio"
        "--host" "https://gitea.example.com"  # Update with actual URL
      ];
      env = {
        GITEA_ACCESS_TOKEN = secretEnv "gitea-personal-token";
      };
    };
  };
}
```

### 4.3 Updated Main Claude-Code Module

**File:** `modules/home/all/tools/claude-code/default.nix`
```nix
{
  config,
  pkgs,
  flake,
  ...
}:
{
  imports = [
    ./mcp-secrets.nix
    ./mcp-servers.nix
  ];

  programs.claude-code = {
    enable = true;
    package = flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;

    # symlink commands and agents directory trees
    commandsDir = ./commands;
    agentsDir = ./agents;

    # https://schemastore.org/claude-code-settings.json
    settings = {
      statusLine = {
        type = "command";
        command = "${pkgs.cc-statusline-rs}/bin/statusline";
      };

      theme = "dark";
      autoCompactEnabled = false;
      spinnerTipsEnabled = false;
      cleanupPeriodDays = 1100;
      includeCoAuthoredBy = false;
      enableAllProjectMcpServers = false;
      alwaysThinkingEnabled = true;

      permissions = {
        defaultMode = "acceptEdits";
        allow = [
          # Basics
          "Bash(cat:*)"
          "Bash(echo:*)"
          "Bash(find:*)"
          "Bash(grep:*)"
          "Bash(head:*)"
          "Bash(ls:*)"
          "Bash(mkdir:*)"
          "Bash(pwd)"
          "Bash(tail:*)"
          "Bash(which:*)"
          # Git operations
          "Bash(git add:*)"
          "Bash(git branch:*)"
          "Bash(git checkout:*)"
          "Bash(git commit:*)"
          "Bash(git config:*)"
          "Bash(git diff:*)"
          "Bash(git log:*)"
          "Bash(git push)"
          "Bash(git reset:*)"
          "Bash(git rev-parse:*)"
          "Bash(git show:*)"
          "Bash(git stash:*)"
          "Bash(git status:*)"
          "Bash(git tag:*)"
          # GitHub CLI
          "Bash(gh:*)"
          # Nix operations
          "Bash(nix build:*)"
          "Bash(nix develop:*)"
          "Bash(nix flake:*)"
          "Bash(nix run:*)"
          # Development tools
          "Bash(jq:*)"
          "Bash(test:*)"
          # MCP servers - allow all MCP tool usage
          "mcp__*"
        ];
        deny = [
          "Bash(sudo:*)"
          "Bash(rm -rf:*)"
        ];
        ask = [ ];
      };
    };
  };

  home.shellAliases = {
    ccds = "claude --dangerously-skip-permissions";
  };

  # symlink .local/bin to satisfy claude doctor
  home.file.".local/bin/claude".source =
    config.lib.file.mkOutOfStoreSymlink "${config.programs.claude-code.finalPackage}/bin/claude";
}
```

---

## Phase 5: Testing Strategy

### 5.1 Pre-Deployment Testing

**Test 1: Secrets Encryption**
```bash
# Create test secret file
echo "brave-api-key: test-key-123" > secrets/users/crs58/mcp-api-keys.yaml

# Encrypt with SOPS
sops -e -i secrets/users/crs58/mcp-api-keys.yaml

# Verify encryption
cat secrets/users/crs58/mcp-api-keys.yaml  # Should show encrypted content

# Test decryption
sops -d secrets/users/crs58/mcp-api-keys.yaml  # Should show plaintext
```

**Test 2: Build Configuration**
```bash
# Build home-manager configuration
nix build .#homeConfigurations.runner@stibnite.activationPackage

# Check for errors
echo $?  # Should be 0
```

**Test 3: Dry-Run Activation**
```bash
# Dry-run to see what would change
./result/activate --dry-run
```

### 5.2 Post-Deployment Validation

**Test 4: Secret File Permissions**
```bash
# Check SOPS secrets are created with correct permissions
ls -la /run/user/$(id -u)/secrets/mcp/  # Should show mode 0400 files
```

**Test 5: Claude Code Configuration**
```bash
# Verify settings.json includes MCP servers
cat ~/.claude/settings.json | jq '.mcpServers'

# Should show all configured MCP servers
```

**Test 6: MCP Server Connectivity**
```bash
# Test Claude Code with a simple MCP server
claude --help

# In Claude Code UI, verify MCP servers are listed
# Try using a non-sensitive server first (browser, shadcn)
```

**Test 7: Secret Injection**
```bash
# Verify secrets are accessible (without exposing values)
test -f /run/user/$(id -u)/secrets/mcp/brave-api-key && echo "Secret file exists"

# Test MCP server that requires secrets (brave-search)
# Should connect without authentication errors
```

### 5.3 Rollback Testing

**Test 8: Rollback Procedure**
```bash
# If issues arise, rollback to previous generation
home-manager generations
home-manager switch --rollback

# Verify Claude Code still works with previous config
claude --help
```

---

## Phase 6: Optimization & Best Practices

### 6.1 Modularity

**Enable/Disable Individual MCP Servers:**
```nix
# In mcp-servers.nix, add conditional logic
{
  config,
  pkgs,
  lib,
  ...
}:
let
  cfg = config.programs.claude-code;
  enableGitea = true;  # Make this configurable
  enableGitHub = true;
in
{
  programs.claude-code.mcpServers = lib.mkMerge [
    # Always enabled
    {
      browser = { ... };
      shadcn = { ... };
    }

    # Conditionally enabled
    (lib.mkIf enableGitea {
      gitea-personal = { ... };
    })

    (lib.mkIf enableGitHub {
      github = { ... };
    })
  ];
}
```

### 6.2 Security Considerations

1. **Never commit plaintext secrets** - Always use SOPS encryption
2. **Restrict secret file permissions** - Use mode "0400" for API keys
3. **Separate user vs service secrets** - Different SOPS files for different access levels
4. **Use age keys, not GPG** - Age is simpler and more secure for this use case
5. **Backup age keys securely** - Store in Bitwarden or similar password manager
6. **Rotate secrets regularly** - Update API keys periodically
7. **Audit secret access** - Review who has access to which secrets in `.sops.yaml`

### 6.3 Maintainability

1. **Document each MCP server** - Add comments explaining purpose and requirements
2. **Group related servers** - Organize by function (git, search, code quality, etc.)
3. **Use consistent naming** - Follow pattern: `mcp/<service>-<credential-type>`
4. **Version control secrets structure** - Commit encrypted YAML files to git
5. **Test on multiple hosts** - Ensure portability across stibnite, blackphos, etc.

### 6.4 Flexibility

**Environment-Specific Overrides:**
```nix
# In user-specific home config (e.g., runner@stibnite.nix)
{
  programs.claude-code.mcpServers.sonarqube.env.SONARQUBE_URL =
    lib.mkForce "https://sonarqube-dev.example.com";
}
```

**Per-User MCP Server Selection:**
```nix
# runner might not need all MCP servers
{
  programs.claude-code.mcpServers = lib.mkForce {
    browser = { ... };
    github = { ... };
    # Minimal set for CI/automation user
  };
}
```

---

## Phase 7: Rollback Plan

### 7.1 Immediate Rollback (< 5 minutes)

If MCP integration breaks Claude Code:

```bash
# Step 1: Rollback to previous home-manager generation
home-manager generations
home-manager switch --rollback

# Step 2: Verify Claude Code works
claude --help

# Step 3: Remove problematic MCP config files if needed
rm -rf ~/.claude/mcp/
rm -rf ~/.config/claude-code/mcp/
```

### 7.2 Partial Rollback (Keep some MCP servers)

If only specific MCP servers are problematic:

```nix
# Comment out problematic servers in mcp-servers.nix
programs.claude-code.mcpServers = {
  browser = { ... };  # Works
  # github = { ... };  # DISABLED: Authentication issues
  shadcn = { ... };   # Works
};
```

### 7.3 Complete Removal

If MCP integration needs to be completely removed:

```bash
# Step 1: Remove imports from default.nix
# Remove: ./mcp-secrets.nix and ./mcp-servers.nix

# Step 2: Remove MCP-related files
rm modules/home/all/tools/claude-code/mcp-secrets.nix
rm modules/home/all/tools/claude-code/mcp-servers.nix

# Step 3: Rebuild and activate
nix build .#homeConfigurations.runner@stibnite.activationPackage
./result/activate

# Step 4: Clean up secrets (optional)
# Keep encrypted files in git, but remove from SOPS config if needed
```

---

## Phase 8: Documentation & Examples

### 8.1 Adding New MCP Servers

**Example: Adding a new MCP server with secrets**

1. **Add secret to SOPS file:**
```bash
# Edit secrets file
sops secrets/users/crs58/mcp-api-keys.yaml

# Add new key:
# new-service-api-key: your-api-key-here
```

2. **Declare secret in mcp-secrets.nix:**
```nix
sops.secrets."mcp/new-service-api-key" = {
  sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
  key = "new-service-api-key";
};
```

3. **Add MCP server in mcp-servers.nix:**
```nix
programs.claude-code.mcpServers.new-service = {
  command = "npx";
  args = [ "-y" "new-service-mcp" ];
  env = {
    NEW_SERVICE_API_KEY = secretEnv "new-service-api-key";
  };
};
```

4. **Rebuild and test:**
```bash
nix build .#homeConfigurations.runner@stibnite.activationPackage
./result/activate
claude --help  # Verify new server appears
```

### 8.2 Troubleshooting Guide

**Issue: Secret not found**
```
Error: /run/user/1000/secrets/mcp/api-key: No such file or directory
```
**Solution:** Check SOPS secret declaration and ensure sopsFile path is correct

**Issue: MCP server authentication fails**
```
Error: Invalid API key
```
**Solution:** Verify secret value in SOPS file: `sops -d secrets/users/crs58/mcp-api-keys.yaml`

**Issue: Claude Code doesn't see MCP servers**
```
No MCP servers configured
```
**Solution:** Check `~/.claude/settings.json` for mcpServers section. Rebuild home-manager config.

---

## Phase 9: Future Enhancements

### 9.1 Potential Improvements

1. **Dynamic MCP Server Discovery** - Auto-detect available MCP servers from packages
2. **MCP Server Health Checks** - Systemd services to monitor MCP server availability
3. **Centralized MCP Server Registry** - Shared flake input for common MCP servers
4. **Per-Project MCP Configurations** - Override global MCP servers per project
5. **MCP Server Metrics** - Track usage and performance of each MCP server
6. **Automated Secret Rotation** - Scripts to rotate API keys periodically

### 9.2 Integration with Other Tools

- **Zed Editor** - Port MCP configuration to Zed's context_servers format
- **VSCode/Cursor** - Integrate MCP servers with Continue.dev or similar extensions
- **Neovim** - Explore MCP integration with Neovim LSP clients

---

## Appendix A: Reference Files

### A.1 Complete File Listing

**New Files to Create:**
1. `modules/home/all/tools/claude-code/mcp-secrets.nix`
2. `modules/home/all/tools/claude-code/mcp-servers.nix`
3. `secrets/users/crs58/mcp-api-keys.yaml` (encrypted)
4. `secrets/services/mcp-services.yaml` (encrypted)
5. `packages/mcp-servers/default.nix`
6. `packages/mcp-servers/gitea-mcp.nix`

**Files to Modify:**
1. `modules/home/all/tools/claude-code/default.nix` - Add imports
2. `.sops.yaml` - Add creation rules for MCP secrets
3. `overlays/packages/default.nix` - Add MCP server packages (if needed)

### A.2 Key Dependencies

**Required Packages:**
- `sops` - Secret encryption/decryption
- `age` - Age encryption tool
- `ssh-to-age` - Convert SSH keys to age keys
- `podman` - Container runtime for containerized MCP servers
- `nodejs` - For npx-based MCP servers
- `claude-code` - Claude Code CLI (from nix-ai-tools)

**Optional Packages:**
- `gitea-mcp` - Custom Gitea MCP server (to be packaged)
- `jq` - JSON processing for debugging

---

## Appendix B: Compatibility Matrix

### B.1 Platform Support

| MCP Server | Linux | macOS | Container | Notes |
|------------|-------|-------|-----------|-------|
| browser | ✅ | ✅ | ❌ | Requires npx |
| brave-search | ✅ | ✅ | ❌ | Requires API key |
| playwright | ✅ | ✅ | ✅ | Podman container |
| context7 | ✅ | ✅ | ❌ | Requires npx |
| sonarqube | ✅ | ✅ | ✅ | Podman container |
| gitea-personal | ✅ | ✅ | ❌ | Custom package |
| github | ✅ | ✅ | ✅ | Podman container |
| ref | ✅ | ✅ | ❌ | Requires API key |
| shadcn | ✅ | ✅ | ❌ | Requires npx |
| firecrawl | ✅ | ✅ | ❌ | Requires API key |
| stripe-sandbox | ✅ | ✅ | ❌ | Requires API key |

### B.2 Host Compatibility

| Host | Platform | SOPS Support | MCP Support | Notes |
|------|----------|--------------|-------------|-------|
| stibnite | macOS | ✅ | ✅ | Primary development machine |
| blackphos | macOS | ✅ | ✅ | Secondary machine |
| orb-nixos | NixOS | ✅ | ✅ | Linux testing |

---

## Conclusion

This implementation plan provides a comprehensive, secure, and maintainable approach to integrating MCP server configurations with SOPS-nix secrets management in the nix-config repository. The modular design allows for easy addition/removal of MCP servers, while SOPS-nix ensures all sensitive credentials remain encrypted at rest and in version control.

**Key Success Factors:**
1. ✅ Follows nixos-unified patterns
2. ✅ Maintains security with SOPS-nix encryption
3. ✅ Modular and maintainable structure
4. ✅ Portable across multiple hosts
5. ✅ Comprehensive testing strategy
6. ✅ Clear rollback procedures
7. ✅ Well-documented for future maintenance

**Next Steps:**
1. Review this plan with stakeholders
2. Begin Phase 3 implementation (Step 1: Create secrets structure)
3. Iterate through testing phases
4. Document any deviations or improvements discovered during implementation

