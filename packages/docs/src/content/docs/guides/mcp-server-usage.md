---
title: MCP Server Usage
sidebar:
  order: 9
---

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
2. If yes, add to your user's secrets file (`secrets/users/{username}/mcp-api-keys.yaml`):
   ```bash
   # Replace {username} with your actual username (e.g., crs58)
   sops secrets/users/{username}/mcp-api-keys.yaml
   # Add: new-service-api-key: <value>
   ```

3. Add to `modules/home/all/tools/claude-code/mcp-servers.nix`:
   ```nix
   # If secrets needed (uses config.home.username automatically):
   sops.secrets."mcp-new-service-api-key" = {
     sopsFile = mcpSecretsFile;  # Automatically resolves to secrets/users/{username}/
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
cd /path/to/mcp-prompts-server  # Your local clone
npm run build
```

**Update when changed**:
The nix config references `${home}/path/to/mcp-prompts-server/dist/server.js`.
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
- Ensure project is built: `ls /path/to/mcp-prompts-server/dist/server.js`
- Rebuild if needed: `cd /path/to/mcp-prompts-server && npm run build`

**terraform server fails to start**:
- Check Docker daemon: `docker info`
- **macOS**: Start OrbStack, Docker Desktop, or run `colima start`
- **NixOS**: Ensure `virtualisation.docker.enable = true;` in system configuration
- **Alternative**: Replace `docker` with `podman` in mcp-terraform template (untested)

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
cd /path/to/infra  # Your local clone of this repository

# Comment out import in claude-code/default.nix
# Remove line: ./mcp-servers.nix

# Rebuild
darwin-rebuild switch --flake .#<hostname>

# Manually manage ~/.mcp/ files
```
