# MCP server configuration with SOPS-nix integration plan

## Executive summary

**Integration strategy**: Adopt fred-drake's proven `sops.templates` pattern within your existing nixos-unified structure to generate individual MCP server JSON files with secrets injected from SOPS-encrypted sources.

**Key innovation**: Manual MCP server selection per session via `--mcp-config` flags enables context window optimization by loading only the minimal required tooling for each task, avoiding context poisoning from unused MCP server metadata.

**Example usage**:
```bash
# Nix development session (minimal context)
claude --mcp-config ~/.mcp/nixos.json

# Web scraping with tools
claude --mcp-config ~/.mcp/firecrawl.json ~/.mcp/playwright.json

# General development with history
claude --mcp-config ~/.mcp/historian.json ~/.mcp/chrome.json
```

---

## Design goals

1. **Context optimization** (PRIMARY): Enable precise MCP server composition per session to minimize context window pollution
2. **Security**: All credentials encrypted with SOPS-nix, never in plaintext in nix store or VCS
3. **Modularity**: Each MCP server in separate JSON file for flexible composition
4. **Declarative**: Nix-managed configuration with reproducible secrets handling
5. **Cross-platform**: Works via home-manager on both NixOS and nix-darwin
6. **Minimal rebuild churn**: Secret updates apply via home-manager switch without full system rebuild

---

## Current state

- **nix-config architecture**: nixos-unified + flake-parts
- **SOPS-nix**: Already configured with age keys at `~/.config/sops/age/keys.txt`
- **Existing secrets**: `secrets/{users,hosts,services,shared.yaml}` structure in place
- **Current MCP servers**: 11 servers in `~/.mcp/` with hardcoded API keys (security risk)
- **Backup created**: `~/.mcp-backup-20251014` contains working configs for reference/rollback
- **Module organization**: `modules/{darwin,home/all,flake-parts,nixos}/`
- **Claude-code module**: Located at `modules/home/all/tools/claude-code/default.nix` with existing MCP permissions

### Your actual MCP servers

**With secrets (3)**:
- **firecrawl**: Web scraping with API key
- **huggingface**: AI model access with token
- **context7**: Context management with API key

**Without secrets (8)**:
- **chrome**: Browser DevTools integration
- **cloudflare**: Remote SSE documentation
- **duckdb**: In-memory database
- **historian**: Claude conversation history
- **mcp-prompt-server**: Local project-based prompts (special case)
- **nixos**: Nix ecosystem tools
- **playwright**: Browser automation
- **terraform**: Infrastructure as code

---

## Reference implementations analyzed

1. **fred-drake-nix-claude-mcp-sops-ccstatusline**: Uses `sops.templates` to generate MCP JSON files with secret placeholders - battle-tested pattern
2. **srid-nixos-config**: Uses `programs.claude-code` module but MCP servers disabled
3. **home-manager claude-code module**: Provides `programs.claude-code.mcpServers` option that wraps binary with `--mcp-config` flag pointing to nix store JSON

### Why file-based approach vs programs.claude-code.mcpServers

**Chosen approach**: Individual `~/.mcp/*.json` files with sops.templates

**Rationale**:
- Manual server selection via CLI requires individual files: `claude --mcp-config ~/.mcp/nixos.json ~/.mcp/firecrawl.json`
- SOPS template substitution requires runtime rendering (incompatible with nix store immutable paths)
- File-based approach allows sharing configs between Claude Code and Claude Desktop
- Enables context window optimization through precise tool composition
- Proven working pattern in current setup (pre-nix management)

---

## Key decisions

- ✅ Use fred-drake's `sops.templates` pattern (battle-tested, reliable)
- ✅ Module location: `modules/home/all/tools/claude-code/mcp-servers.nix` (co-located with existing claude-code config)
- ✅ Secrets location: `secrets/users/crs58/mcp-api-keys.yaml` (matches existing `.sops.yaml` rules)
- ✅ Generate files to: `~/.mcp/` directory (one JSON per server for manual composition)
- ✅ Three secret injection patterns: env wrapper, --api-key arg, --header arg (preserve exact source patterns)
- ✅ Backup reference: `~/.mcp-backup-20251014` for testing and rollback

---

## Detailed file structure

```
nix-config/
├── modules/
│   └── home/
│       └── all/
│           └── tools/
│               └── claude-code/
│                   ├── default.nix          # Existing: Import mcp-servers.nix here
│                   ├── mcp-servers.nix      # NEW: MCP server configurations with SOPS
│                   ├── commands/            # Existing
│                   └── agents/              # Existing
├── secrets/
│   ├── .sops.yaml                           # Existing: No changes needed
│   └── users/
│       └── crs58/
│           └── mcp-api-keys.yaml            # NEW: Encrypted API keys for 3 servers
└── docs/
    └── notes/
        └── development/
            └── mcp-servers-guide.md         # NEW: Usage patterns and maintenance
```

---

## Implementation plan

### Phase 1: Prepare secrets file (5-10 minutes)

#### Step 1.1: Create MCP API keys secrets file

```bash
# Navigate to nix-config
cd /Users/crs58/projects/nix-workspace/nix-config

# Create secrets directory if it doesn't exist
mkdir -p secrets/users/crs58

# Create and encrypt secrets file
sops secrets/users/crs58/mcp-api-keys.yaml
```

#### Step 1.2: Add secrets to file

When sops editor opens, add the following structure (extract actual values from `~/.mcp-backup-20251014/`):

```yaml
# MCP server API keys (encrypted by SOPS)
# Extract actual values from ~/.mcp-backup-20251014/*.json before encrypting
firecrawl-api-key: <your-firecrawl-key>
huggingface-token: <your-huggingface-token>
context7-api-key: <your-context7-key>
```

**Notes**:
- Extract actual values from backup files (firecrawl.json, huggingface.json, context7.json)
- File will be encrypted automatically by sops on save
- Age key from `~/.config/sops/age/keys.txt` used for encryption
- Existing `.sops.yaml` creation_rules already match `users/crs58/.*\.yaml$` pattern (no changes needed)

#### Step 1.3: Verify encryption

```bash
# Verify file is encrypted
cat secrets/users/crs58/mcp-api-keys.yaml | head -5

# Should show sops metadata, not plaintext:
# firecrawl-api-key: ENC[AES256_GCM,data:...,iv:...,tag:...,type:str]

# Test decryption works
sops -d secrets/users/crs58/mcp-api-keys.yaml
```

---

### Phase 2: Create MCP servers module (20-30 minutes)

#### Step 2.1: Create the MCP servers module

Create `modules/home/all/tools/claude-code/mcp-servers.nix`:

```nix
{
  config,
  pkgs,
  lib,
  ...
}:
let
  home = config.home.homeDirectory;
in
{
  # Ensure ~/.mcp directory exists before templates are written
  home.file.".mcp/.keep".text = "";

  # Define sops secrets for the 3 MCP servers requiring API keys
  sops.secrets = {
    "mcp-firecrawl-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "firecrawl-api-key";
    };
    "mcp-huggingface-token" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "huggingface-token";
    };
    "mcp-context7-api-key" = {
      sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
      key = "context7-api-key";
    };
  };

  # Generate MCP server configuration files using sops templates
  # Each server gets its own JSON file for manual composition via --mcp-config
  sops.templates = {
    # --- Servers WITH secrets (3) ---

    # Firecrawl: Web scraping with API key
    # Pattern: env block (secure - secrets not in argv)
    # Note: Improved from backup which used env wrapper (exposed secrets in process args)
    mcp-firecrawl = {
      mode = "0400";
      path = "${home}/.mcp/firecrawl.json";
      content = builtins.toJSON {
        mcpServers = {
          firecrawl = {
            type = "stdio";
            command = "npx";
            args = ["-y" "firecrawl-mcp"];
            env = {
              FIRECRAWL_API_KEY = config.sops.placeholder."mcp-firecrawl-api-key";
            };
          };
        };
      };
    };

    # Context7: Context management with API key
    # Pattern: --api-key argument
    mcp-context7 = {
      mode = "0400";
      path = "${home}/.mcp/context7.json";
      content = builtins.toJSON {
        mcpServers = {
          context7 = {
            type = "stdio";
            command = "npx";
            args = [
              "-y"
              "@upstash/context7-mcp"
              "--api-key"
              config.sops.placeholder."mcp-context7-api-key"
            ];
            env = {};
          };
        };
      };
    };

    # Hugging Face: AI model access with token
    # Pattern: --header Authorization: Bearer <token>
    # Note: mcp-remote requires full header value as single arg (exposes token in process args)
    mcp-huggingface = {
      mode = "0400";
      path = "${home}/.mcp/huggingface.json";
      content = builtins.toJSON {
        mcpServers = {
          "hf-mcp-server" = {
            command = "npx";
            args = [
              "mcp-remote"
              "https://huggingface.co/mcp"
              "--header"
              "Authorization: Bearer ${config.sops.placeholder."mcp-huggingface-token"}"
            ];
          };
        };
      };
    };

    # --- Servers WITHOUT secrets (8) ---

    # Chrome DevTools: Browser automation
    mcp-chrome = {
      mode = "0400";
      path = "${home}/.mcp/chrome.json";
      content = builtins.toJSON {
        mcpServers = {
          "chrome-devtools" = {
            command = "npx";
            args = [ "chrome-devtools-mcp@latest" ];
          };
        };
      };
    };

    # Cloudflare: Documentation via SSE remote
    mcp-cloudflare = {
      mode = "0400";
      path = "${home}/.mcp/cloudflare.json";
      content = builtins.toJSON {
        mcpServers = {
          cloudflare = {
            command = "npx";
            args = [
              "mcp-remote"
              "https://docs.mcp.cloudflare.com/sse"
            ];
          };
        };
      };
    };

    # DuckDB: In-memory database via uvx
    mcp-duckdb = {
      mode = "0400";
      path = "${home}/.mcp/duckdb.json";
      content = builtins.toJSON {
        mcpServers = {
          "mcp-server-motherduck" = {
            command = "uvx";
            args = [
              "mcp-server-motherduck"
              "--db-path"
              ":memory:"
            ];
          };
        };
      };
    };

    # Historian: Claude conversation history
    mcp-historian = {
      mode = "0400";
      path = "${home}/.mcp/historian.json";
      content = builtins.toJSON {
        mcpServers = {
          "claude-historian" = {
            type = "stdio";
            command = "npx";
            args = [ "claude-historian" ];
            env = {};
          };
        };
      };
    };

    # MCP Prompt Server: Local project-based prompts
    # SPECIAL CASE: Uses local workspace project, not npm package
    # Requires separate build: cd ~/projects/planning-workspace/mcp-prompts-server && npm run build
    mcp-mcp-prompt-server = {
      mode = "0400";
      path = "${home}/.mcp/mcp-prompt-server.json";
      content = builtins.toJSON {
        mcpServers = {
          "mcp-prompt-server" = {
            command = "node";
            args = [
              "${home}/projects/planning-workspace/mcp-prompts-server/dist/server.js"
            ];
          };
        };
      };
    };

    # NixOS: Nix ecosystem tools via uvx
    mcp-nixos = {
      mode = "0400";
      path = "${home}/.mcp/nixos.json";
      content = builtins.toJSON {
        mcpServers = {
          nixos = {
            command = "uvx";
            args = [ "mcp-nixos" ];
          };
        };
      };
    };

    # Playwright: Browser automation
    mcp-playwright = {
      mode = "0400";
      path = "${home}/.mcp/playwright.json";
      content = builtins.toJSON {
        mcpServers = {
          playwright = {
            type = "stdio";
            command = "npx";
            args = [
              "@playwright/mcp@latest"
              "--extension"
            ];
            env = {};
          };
        };
      };
    };

    # Terraform: Infrastructure as code via docker
    mcp-terraform = {
      mode = "0400";
      path = "${home}/.mcp/terraform.json";
      content = builtins.toJSON {
        mcpServers = {
          terraform = {
            type = "stdio";
            command = "docker";
            args = [
              "run"
              "-i"
              "--rm"
              "hashicorp/terraform-mcp-server"
            ];
            env = {};
          };
        };
      };
    };
  };

  # Runtime dependencies for MCP servers
  home.packages = with pkgs; [
    nodejs_22  # For npx: firecrawl, huggingface, chrome, cloudflare, historian, playwright
               # Also provides node binary for mcp-prompt-server
    uv         # For uvx: duckdb, nixos
    docker     # For terraform container (requires OrbStack, Docker Desktop, or Colima on macOS)
  ];
}
```

**Key features of this module**:
- Creates `~/.mcp/.keep` to ensure directory exists before template rendering
- Three different secret injection patterns: env block (firecrawl - improved security), --api-key arg (context7), --header arg (huggingface)
- Firecrawl pattern improved from backup's env wrapper to env block (prevents secret exposure in process args)
- Consistent secret naming: `mcp-<service>-<credential-type>`
- Mode 0400 (read-only by owner) for all generated files
- Special handling for mcp-prompt-server local project
- Complete runtime dependencies specified (nodejs_22, uv, docker)

#### Step 2.2: Import the module

Edit `modules/home/all/tools/claude-code/default.nix`:

```nix
{
  config,
  pkgs,
  flake,
  ...
}:
{
  imports = [
    ./mcp-servers.nix  # Add this line
  ];

  programs.claude-code = {
    enable = true;
    package = flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;

    # ... rest of existing config ...

    settings = {
      # ... existing settings ...

      permissions = {
        defaultMode = "acceptEdits";
        allow = [
          # ... existing permissions ...

          # MCP servers - allow all MCP tools
          "mcp__*"  # Changed from "mcp__firecrawl__*" to allow all MCP servers
        ];
        # ... rest of permissions ...
      };
    };
  };

  # ... rest of existing config ...
}
```

---

### Phase 3: Testing and validation (15-20 minutes)

#### Step 3.1: Build configuration

```bash
# From nix-config directory
cd /Users/crs58/projects/nix-workspace/nix-config

# Build without switching (dry run)
darwin-rebuild build --flake .#stibnite

# If build succeeds, check what will change
nix store diff-closures /nix/var/nix/profiles/system ./result
```

Expected output:
- New files will appear in `~/.mcp/` directory
- Secrets will be decrypted at activation time

#### Step 3.2: Apply configuration

```bash
# Switch to new configuration (macOS)
darwin-rebuild switch --flake .#stibnite

# For NixOS (orb-nixos):
# nixos-rebuild switch --flake .#orb-nixos
```

#### Step 3.3: Verify MCP server configurations

```bash
# Check that all 11 files were created
ls -la ~/.mcp/
# Should show: chrome.json, cloudflare.json, context7.json, duckdb.json, firecrawl.json,
#              historian.json, huggingface.json, mcp-prompt-server.json, nixos.json,
#              playwright.json, terraform.json

# Verify files are readable but not writable (mode 0400)
stat -f "%Sp %N" ~/.mcp/*.json
# Expected: -r-------- for all files

# Verify secrets are properly injected (not placeholders)
# Should contain actual API key, not "config.sops.placeholder..."
grep -q "config.sops.placeholder" ~/.mcp/firecrawl.json && echo "ERROR: Placeholder not substituted" || echo "✓ Secrets injected"

# Comprehensive placeholder leakage check across all files
grep -r "config.sops.placeholder" ~/.mcp/ && echo "ERROR: Placeholders not substituted" || echo "✓ No placeholder leakage"

# Verify all JSON is valid
for f in ~/.mcp/*.json; do
  jq empty "$f" && echo "✓ $(basename $f) valid" || echo "✗ $(basename $f) invalid"
done
```

#### Step 3.4: Compare with backup

```bash
# Compare structure with backup (ignoring secret values)
for file in ~/.mcp/*.json; do
  base=$(basename "$file")
  if [ -f ~/.mcp-backup-20251014/"$base" ]; then
    echo "Comparing $base..."
    # Compare server names and basic structure
    diff <(jq -S '.mcpServers | keys' "$file") \
         <(jq -S '.mcpServers | keys' ~/.mcp-backup-20251014/"$base") \
      && echo "✓ $base structure matches" \
      || echo "✗ $base structure differs"
  fi
done
```

#### Step 3.4.5: Verify Docker daemon (for terraform server)

```bash
# Check if Docker is available and daemon is running
# Required for terraform MCP server which uses docker containers
if command -v docker &>/dev/null; then
  docker info &>/dev/null && echo "✓ Docker daemon running" || echo "⚠️  Docker daemon not running - terraform MCP server will fail"
else
  echo "⚠️  Docker not installed - terraform MCP server will not work"
fi

# On macOS: Ensure OrbStack, Docker Desktop, or Colima is running
# On NixOS: Ensure virtualisation.docker.enable = true in system config
```

#### Step 3.5: Test individual MCP servers

```bash
# Test server without secrets (should work immediately)
claude --mcp-config ~/.mcp/nixos.json --help

# Test server with secrets (should authenticate successfully)
claude --mcp-config ~/.mcp/firecrawl.json --help

# Test combination (context optimization in action)
claude --mcp-config ~/.mcp/historian.json ~/.mcp/chrome.json
```

#### Step 3.6: Verify mcp-prompt-server special case

```bash
# Check if local project is built
if [ ! -f ~/projects/planning-workspace/mcp-prompts-server/dist/server.js ]; then
  echo "⚠️  mcp-prompt-server not built - building now..."
  cd ~/projects/planning-workspace/mcp-prompts-server
  npm install
  npm run build
else
  echo "✓ mcp-prompt-server already built"
fi

# Test it works
claude --mcp-config ~/.mcp/mcp-prompt-server.json --help
```

---

### Phase 4: Cleanup and documentation (10 minutes)

#### Step 4.1: Migration complete - no cleanup needed

The backup `~/.mcp-backup-20251014` is already created. The new nix-managed files will coexist with or replace the old files depending on activation behavior. Keep the backup for rollback purposes.

#### Step 4.2: Create usage documentation

Create `docs/notes/development/mcp-servers-guide.md`:

```markdown
# MCP servers usage guide

## Philosophy

MCP servers are manually selected per Claude session to optimize context window usage.
Each server's tool metadata consumes context space, so load only what you need.

## Available servers

| Server | Secrets | Purpose | Common use cases |
|--------|---------|---------|------------------|
| chrome | No | Browser DevTools | Debugging web applications |
| cloudflare | No | CF docs via SSE | Cloudflare API reference |
| context7 | Yes | Context management | Managing conversation context |
| duckdb | No | In-memory database | Data analysis, SQL queries |
| firecrawl | Yes | Web scraping | Extracting content from websites |
| historian | No | Conversation history | Browsing past Claude sessions |
| huggingface | Yes | AI model access | Model information, downloads |
| mcp-prompt-server | No | Local prompts | Project-specific prompt templates |
| nixos | No | Nix ecosystem tools | Nix development, package search |
| playwright | No | Browser automation | End-to-end testing, scraping |
| terraform | No | Infrastructure as code | Terraform workflows (requires Docker daemon) |

## Common usage patterns

```bash
# Shell aliases for frequent combinations
alias cln='claude --mcp-config ~/.mcp/nixos.json'
alias clh='claude --mcp-config ~/.mcp/historian.json'
alias clw='claude --mcp-config ~/.mcp/firecrawl.json ~/.mcp/playwright.json'
alias cld='claude --mcp-config ~/.mcp/duckdb.json ~/.mcp/terraform.json'
alias clc='claude --mcp-config ~/.mcp/chrome.json ~/.mcp/playwright.json'

# Minimal context (just one server)
claude --mcp-config ~/.mcp/nixos.json

# Heavy tooling (accepts context cost)
claude --mcp-config ~/.mcp/nixos.json ~/.mcp/firecrawl.json ~/.mcp/playwright.json
```

## Adding a new MCP server

1. Determine if server requires secrets
2. If yes, add to `secrets/users/crs58/mcp-api-keys.yaml`:
   ```bash
   sops secrets/users/crs58/mcp-api-keys.yaml
   # Add: new-service-api-key: <value>
   ```

3. Add to `modules/home/all/tools/claude-code/mcp-servers.nix`:
   ```nix
   # If secrets needed:
   sops.secrets."mcp-new-service-api-key" = {
     sopsFile = ../../../../secrets/users/crs58/mcp-api-keys.yaml;
     key = "new-service-api-key";
   };

   sops.templates.mcp-new-service = {
     mode = "0400";
     path = "${home}/.mcp/new-service.json";
     content = builtins.toJSON {
       mcpServers = {
         "new-service" = {
           command = "npx";
           args = [ "-y" "new-service-mcp" ];
           env = {
             API_KEY = config.sops.placeholder."mcp-new-service-api-key";
           };
         };
       };
     };
   };
   ```

4. Rebuild: `darwin-rebuild switch --flake .#stibnite`
5. Test: `claude --mcp-config ~/.mcp/new-service.json --help`

## Special case: mcp-prompt-server

This server uses a local workspace project, not an npm package.

**Build requirement**:
```bash
cd ~/projects/planning-workspace/mcp-prompts-server
npm run build
```

**Update when changed**:
The nix config references `${home}/projects/planning-workspace/mcp-prompts-server/dist/server.js`.
When you update the project, rebuild it with `npm run build` - no nix rebuild needed.

## Secret rotation

```bash
# 1. Generate new API keys from service providers
# 2. Update secrets file
sops secrets/users/crs58/mcp-api-keys.yaml

# 3. Rebuild configuration
darwin-rebuild switch --flake .#stibnite

# 4. Test servers with new keys
claude --mcp-config ~/.mcp/firecrawl.json --help

# 5. Revoke old API keys from service providers
```

## Troubleshooting

**Server not found**:
- Check file exists: `ls ~/.mcp/<server>.json`
- Verify permissions: `stat -f "%Sp" ~/.mcp/<server>.json` (should be `-r--------`)

**Authentication failures** (servers with secrets):
- Verify secret was substituted: `cat ~/.mcp/<server>.json` (should NOT contain "placeholder")
- Test decryption: `sops -d secrets/users/crs58/mcp-api-keys.yaml`
- Check age key exists: `ls ~/.config/sops/age/keys.txt`

**JSON syntax errors**:
- Validate: `jq empty ~/.mcp/<server>.json`
- Check module syntax: `nix-instantiate --parse modules/home/all/tools/claude-code/mcp-servers.nix`

**mcp-prompt-server not working**:
- Ensure project is built: `ls ~/projects/planning-workspace/mcp-prompts-server/dist/server.js`
- Rebuild if needed: `cd ~/projects/planning-workspace/mcp-prompts-server && npm run build`

## Rollback procedures

**Restore from backup**:
```bash
# Keep nix-managed files but restore old configs to test
mv ~/.mcp ~/.mcp-nix-managed
cp -r ~/.mcp-backup-20251014 ~/.mcp

# Test
claude --mcp-config ~/.mcp/nixos.json

# Switch back
rm -rf ~/.mcp
mv ~/.mcp-nix-managed ~/.mcp
```

**Disable nix management**:
```bash
cd ~/projects/nix-workspace/nix-config

# Comment out import in claude-code/default.nix
# Remove line: ./mcp-servers.nix

# Rebuild
darwin-rebuild switch --flake .#stibnite

# Manually manage ~/.mcp/ files
```
```

---

## Testing strategy

### Unit testing

Test each component independently:

```bash
# 1. Secrets decryption
sops -d secrets/users/crs58/mcp-api-keys.yaml
# Expected: Plaintext YAML with API keys

# 2. Module syntax
nix-instantiate --parse modules/home/all/tools/claude-code/mcp-servers.nix
# Expected: No syntax errors

# 3. Template generation (after activation)
cat ~/.mcp/firecrawl.json | jq .
# Expected: Valid JSON with actual API key (not placeholder)

# 4. Individual server tests
for server in nixos historian chrome; do
  echo "Testing $server..."
  claude --mcp-config ~/.mcp/$server.json --help
done
```

### Integration testing

Test complete workflow:

```bash
# 1. Build test
darwin-rebuild build --flake .#stibnite |& tee /tmp/build.log
grep -i "error" /tmp/build.log
# Expected: No errors

# 2. Activation test
darwin-rebuild switch --flake .#stibnite

# 3. Verify all files generated
test $(ls ~/.mcp/*.json | wc -l) -eq 11 && echo "✓ All 11 servers generated"

# 4. Verify permissions
for f in ~/.mcp/*.json; do
  perms=$(stat -f "%Sp" "$f")
  [ "$perms" = "-r--------" ] && echo "✓ $(basename $f) perms correct" || echo "✗ $(basename $f) perms wrong: $perms"
done

# 5. Test combinations
claude --mcp-config ~/.mcp/nixos.json ~/.mcp/firecrawl.json --help
```

### Cross-platform testing

```bash
# macOS (stibnite, blackphos)
darwin-rebuild switch --flake .#stibnite
# Verify launchd sops-nix agent renders templates
ls -la ~/.mcp/*.json

# NixOS (orb-nixos)
nixos-rebuild switch --flake .#orb-nixos
# Verify systemd.user sops-nix activation runs
systemctl --user status sops-nix
ls -la ~/.mcp/*.json
```

---

## Rollback plan

### Immediate rollback (< 1 minute)

If something breaks after activation:

```bash
# Rollback to previous darwin generation
darwin-rebuild --rollback

# Or manually switch to previous generation
darwin-rebuild --list-generations
sudo /nix/var/nix/profiles/system-<N>-link/activate
```

### Restore from backup

If only MCP configuration is broken:

```bash
# Restore backup (keep nix files for comparison)
mv ~/.mcp ~/.mcp-nix-broken
cp -r ~/.mcp-backup-20251014 ~/.mcp

# Test backup works
claude --mcp-config ~/.mcp/nixos.json

# If backup works, debug nix version separately
```

### Module-level rollback

Remove MCP module without full system rollback:

```bash
cd /Users/crs58/projects/nix-workspace/nix-config

# Comment out the import
# Edit modules/home/all/tools/claude-code/default.nix
# Remove or comment: ./mcp-servers.nix

# Rebuild
darwin-rebuild switch --flake .#stibnite

# Manually manage MCP files in ~/.mcp/
```

---

## Security considerations

### Current security posture

**Before (with backup)**:
- API keys in plaintext JSON files in `~/.mcp/`
- Files readable by owner but visible in filesystem
- Risk: Accidental commit to git, backup exposure, logs

**After (with SOPS)**:
- API keys encrypted at rest in `secrets/users/crs58/mcp-api-keys.yaml`
- Decrypted only at activation time by home-manager
- Generated files have mode 0400 (read-only by owner)
- Age key protected in `~/.config/sops/age/keys.txt`
- Encrypted file version controlled safely in git

### Best practices

1. **Never commit** `~/.config/sops/age/keys.txt` to git
2. **Backup age key** in password manager (e.g., Bitwarden)
3. **Rotate API keys** periodically (every 90 days recommended)
4. **Separate keys** for different environments if needed
5. **Monitor API usage** for anomalies at service provider dashboards
6. **Audit access** - review who can decrypt via `.sops.yaml` rules

### Secret exposure risks

**Nix store**:
- ✅ Secrets NOT in nix store (templates render outside store)
- ✅ Only encrypted SOPS files in store paths

**Process environment**:
- ⚠️ Secrets visible in process args for: context7 (--api-key), huggingface (--header Authorization: Bearer)
- ✅ Firecrawl improved: now uses env block (secrets not in argv)
- ⚠️ Known limitation: mcp-remote tool requires --header in args, unavoidable without wrapper scripts
- ✅ Limited exposure: Only visible to user's own processes (mode 0400 ensures file-level protection)

**System logs**:
- ⚠️ Command-line args may appear in shell history
- 🔧 Mitigation: Use ` ` prefix for sensitive commands (bash) or configure history ignore

---

## Compatibility matrix

| Component | Version | Compatibility | Notes |
|-----------|---------|--------------|-------|
| nixpkgs | unstable / 25.05 | ✓ Full | SOPS-nix works on all versions |
| home-manager | master | ✓ Full | sops.templates supported |
| sops-nix | Latest | ✓ Full | Age and GPG both supported |
| nix-darwin | master | ✓ Full | Darwin-specific features work |
| Claude Code | Latest | ✓ Full | Manual --mcp-config flag usage |
| Claude Desktop | Latest | ✓ Partial | Can use same files but check docs |
| NixOS | 24.05+ | ✓ Full | Same module works on Linux |

### Runtime dependencies

| Dependency | Used by | Provided by |
|------------|---------|-------------|
| nodejs_22 | 7 servers (npx) | home.packages |
| node | mcp-prompt-server | nodejs_22 |
| uv | 2 servers (uvx) | home.packages |
| docker | terraform | home.packages |

---

## Migration checklist

Use this checklist to track progress:

- [ ] **Phase 1: Prepare secrets**
  - [ ] Extract API keys from `~/.mcp-backup-20251014/{firecrawl,huggingface,context7}.json`
  - [ ] Create `secrets/users/crs58/mcp-api-keys.yaml` with sops
  - [ ] Add three secrets: firecrawl-api-key, huggingface-token, context7-api-key
  - [ ] Verify encryption: `cat secrets/users/crs58/mcp-api-keys.yaml | head -5`
  - [ ] Test decryption: `sops -d secrets/users/crs58/mcp-api-keys.yaml`

- [ ] **Phase 2: Create module**
  - [ ] Create `modules/home/all/tools/claude-code/mcp-servers.nix`
  - [ ] Add sops.secrets definitions for 3 servers with secrets
  - [ ] Add sops.templates for all 11 MCP servers
  - [ ] Add home.packages: nodejs_22, uv, docker
  - [ ] Import in `modules/home/all/tools/claude-code/default.nix`
  - [ ] Update permissions to `"mcp__*"` in claude-code settings

- [ ] **Phase 3: Testing**
  - [ ] Run `darwin-rebuild build --flake .#stibnite`
  - [ ] Verify build succeeds
  - [ ] Run `darwin-rebuild switch --flake .#stibnite`
  - [ ] Check all 11 files in `~/.mcp/` directory
  - [ ] Verify secrets injected (not placeholders)
  - [ ] Compare structure with backup files
  - [ ] Test individual servers: `claude --mcp-config ~/.mcp/nixos.json`
  - [ ] Test combinations: `claude --mcp-config ~/.mcp/historian.json ~/.mcp/chrome.json`
  - [ ] Build mcp-prompt-server if not already: `cd ~/projects/planning-workspace/mcp-prompts-server && npm run build`

- [ ] **Phase 4: Documentation**
  - [ ] Create `docs/notes/development/mcp-servers-guide.md`
  - [ ] Add usage patterns and shell aliases
  - [ ] Document troubleshooting procedures
  - [ ] Document mcp-prompt-server special case
  - [ ] Commit changes to git (encrypted secrets and nix code)

- [ ] **Post-deployment validation**
  - [ ] All 11 MCP servers working individually
  - [ ] No plaintext secrets in filesystem (verified with grep)
  - [ ] File permissions correct (0400 for all)
  - [ ] Can rotate secrets via sops and rebuild
  - [ ] Backup still accessible at `~/.mcp-backup-20251014`

---

## Troubleshooting guide

### Common issues and solutions

**Issue: `error: placeholder 'mcp-firecrawl-api-key' in template 'mcp-firecrawl' not defined as secret`**

Solution:
- Ensure secret is defined in `sops.secrets` section
- Check that secret name matches exactly (no typos)
- Verify `sopsFile` path is correct relative to module location

**Issue: Secrets file cannot be decrypted**

```bash
# Check age key exists
test -f ~/.config/sops/age/keys.txt && echo "✓ Key exists" || echo "✗ Key missing"

# Verify key can decrypt file
sops -d secrets/users/crs58/mcp-api-keys.yaml

# If error, check .sops.yaml includes your key
grep -A 10 "users/crs58/" .sops.yaml
```

Solution: Ensure your age key is in the key_groups for the users/crs58 path_regex rule

**Issue: MCP server files not generated**

```bash
# Check home-manager activation log
darwin-rebuild switch --flake .#stibnite |& grep -i mcp

# Check if directory exists
ls -la ~/.mcp/

# Verify templates section in module
nix-instantiate --parse modules/home/all/tools/claude-code/mcp-servers.nix
```

Solution: Verify `.mcp/.keep` file creation ensures directory exists before template rendering

**Issue: JSON files have placeholders instead of actual secrets**

```bash
# Check if placeholder string appears (BAD)
grep "config.sops.placeholder" ~/.mcp/firecrawl.json

# Manually trigger sops-nix activation
/nix/var/nix/profiles/per-user/$USER/home-manager/activate
```

Solution: This indicates sops-nix activation didn't run. Check systemd/launchd service logs.

**Issue: MCP server authentication failures**

```bash
# Verify secret was injected for firecrawl (env wrapper pattern)
cat ~/.mcp/firecrawl.json | jq -r '.mcpServers.firecrawl.args[0]'
# Should show: FIRECRAWL_API_KEY=<actual-key>

# Verify secret was injected for context7 (--api-key pattern)
cat ~/.mcp/context7.json | jq -r '.mcpServers.context7.args[-1]'
# Should show actual API key

# Verify secret was injected for huggingface (--header pattern)
cat ~/.mcp/huggingface.json | jq -r '.mcpServers["hf-mcp-server"].args[-1]'
# Should show: Authorization: Bearer <actual-token>
```

Solution: If placeholders remain, secret substitution failed - check sops-nix activation logs

**Issue: mcp-prompt-server not working**

```bash
# Check if dist/server.js exists
ls -la ~/projects/planning-workspace/mcp-prompts-server/dist/server.js

# If missing, build the project
cd ~/projects/planning-workspace/mcp-prompts-server
npm install
npm run build

# Verify build succeeded
ls -la dist/server.js
```

Solution: This server requires manual build in local workspace, not nix-managed

**Issue: Terraform server fails to start**

```bash
# Check if Docker daemon is running
docker info
```

Solution:
- **macOS**: Start OrbStack, Docker Desktop, or run `colima start`
- **NixOS**: Ensure `virtualisation.docker.enable = true;` in system configuration
- **Alternative**: Replace `docker` with `podman` in mcp-terraform template (untested but should work)

**Issue: Build takes very long time**

Solution:
- Normal for first build (downloads Node packages, Docker images)
- Subsequent builds should be fast (cached)
- Use cachix if available: `cachix use cameronraysmith`

---

## Maintenance schedule

### Weekly
- No regular maintenance needed (declarative configuration)

### Monthly
- Review MCP server usage patterns
- Check for updated MCP server packages
- Verify API usage stays within service quotas

### Quarterly
- **Rotate API keys** (security best practice)
  1. Generate new keys from service providers
  2. Update `secrets/users/crs58/mcp-api-keys.yaml` with sops
  3. Rebuild: `darwin-rebuild switch --flake .#stibnite`
  4. Test servers with new keys
  5. Revoke old keys from service providers
- Review and remove unused MCP servers
- Update runtime dependencies if needed (nodejs, uv, docker)

### Annually
- Audit all MCP configurations
- Review age key security and backup status
- Update documentation with new patterns or servers

---

## References

### Documentation
- [SOPS-nix documentation](https://github.com/Mic92/sops-nix)
- [home-manager manual](https://nix-community.github.io/home-manager/)
- [nixos-unified documentation](https://nixos-unified.org/)
- [MCP specification](https://modelcontextprotocol.io/)
- [Age encryption tool](https://age-encryption.org/)
- [Claude Code MCP usage](https://docs.anthropic.com/claude-code/mcp)

### Example configurations
- **fred-drake-nix-claude-mcp-sops-ccstatusline**: Reference implementation of sops.templates pattern
- **srid-nixos-config**: Alternative programs.claude-code approach

### Related files in nix-config
- `modules/home/all/core/sops.nix` - Existing sops configuration (age key location)
- `modules/home/all/tools/claude-code/default.nix` - Claude Code settings and permissions
- `.sops.yaml` - SOPS key management and creation rules
- `secrets/users/crs58/mcp-api-keys.yaml` - Encrypted MCP API keys (NEW)

### Backup reference
- `~/.mcp-backup-20251014` - Original working configs for comparison and rollback

---

## Conclusion

This implementation plan provides a **production-ready**, **secure**, and **context-optimized** approach to managing MCP server configurations with SOPS-nix encryption.

**Key innovations**:
- ✅ Manual server selection per session minimizes context window pollution
- ✅ Individual JSON files enable precise tool composition
- ✅ Three secret injection patterns with security improvement (firecrawl: env wrapper → env block)
- ✅ Special handling for local project-based server (mcp-prompt-server)
- ✅ Complete runtime dependencies specified (nodejs_22, uv, docker with OrbStack support)
- ✅ Module co-located with claude-code config for maintainability
- ✅ Backup reference maintained for validation and rollback
- ✅ Comprehensive validation: placeholder leakage check, Docker daemon verification

**Estimated time to complete:** 40-60 minutes
**Difficulty level:** Intermediate (requires Nix and SOPS knowledge)
**Risk level:** Low (full rollback capability, backup preserved, incremental testing)

**Success criteria**:
- All 11 MCP servers generate individual JSON files
- Secrets encrypted at rest, decrypted only at activation
- File permissions correct (0400)
- Individual and combined server usage works
- Backup comparison validates correctness
- Documentation enables future maintenance

**Next steps**:
1. Review this plan thoroughly
2. Extract API keys from backup files
3. Begin Phase 1 (secrets preparation)
4. Proceed incrementally through each phase
5. Test thoroughly at each step
6. Document any deviations or improvements discovered during implementation
