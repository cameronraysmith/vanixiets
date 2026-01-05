#!/usr/bin/env bash
# Validation script for MCP servers post-switch testing
# Run this after: darwin-rebuild switch --flake .#stibnite

set -e

echo "=== MCP Servers Validation ==="
echo ""

# Color codes
GREEN='\033[0;32m'
RED='\033[0;31m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track errors
ERRORS=0

# 1. Check all 14 files were created
echo "1. Checking all 14 MCP server JSON files exist..."
EXPECTED_FILES=(
  "agent-mail.json"
  "chrome.json"
  "cloudflare.json"
  "context7.json"
  "duckdb.json"
  "firecrawl.json"
  "gcloud.json"
  "gcs.json"
  "historian.json"
  "huggingface.json"
  "mcp-prompt-server.json"
  "nixos.json"
  "playwright.json"
  "terraform.json"
)

for file in "${EXPECTED_FILES[@]}"; do
  if [ -f ~/.mcp/"$file" ]; then
    echo -e "  ${GREEN}✓${NC} $file exists"
  else
    echo -e "  ${RED}✗${NC} $file missing"
    ((ERRORS++))
  fi
done
echo ""

# 2. Verify file permissions (mode 0400)
echo "2. Verifying file permissions (should be -r--------)..."
for file in ~/.mcp/*.json; do
  if [ -f "$file" ]; then
    PERMS=$(stat -f "%Sp" "$file")
    if [ "$PERMS" = "-r--------" ]; then
      echo -e "  ${GREEN}✓${NC} $(basename "$file"): $PERMS"
    else
      echo -e "  ${RED}✗${NC} $(basename "$file"): $PERMS (expected -r--------)"
      ((ERRORS++))
    fi
  fi
done
echo ""

# 3. Check for placeholder leakage
echo "3. Checking for SOPS placeholder leakage..."
if grep -r "config.sops.placeholder" ~/.mcp/ 2>/dev/null; then
  echo -e "  ${RED}✗${NC} ERROR: Placeholders not substituted"
  ((ERRORS++))
else
  echo -e "  ${GREEN}✓${NC} No placeholder leakage"
fi
echo ""

# 4. Validate JSON syntax
echo "4. Validating JSON syntax..."
for file in ~/.mcp/*.json; do
  if [ -f "$file" ]; then
    if jq empty "$file" 2>/dev/null; then
      echo -e "  ${GREEN}✓${NC} $(basename "$file") valid"
    else
      echo -e "  ${RED}✗${NC} $(basename "$file") invalid JSON"
      ((ERRORS++))
    fi
  fi
done
echo ""

# 5. Verify secrets are injected (not placeholders)
echo "5. Verifying secrets are injected in servers with secrets..."
# Firecrawl (env block)
if jq -e '.mcpServers.firecrawl.env.FIRECRAWL_API_KEY' ~/.mcp/firecrawl.json >/dev/null 2>&1; then
  KEY=$(jq -r '.mcpServers.firecrawl.env.FIRECRAWL_API_KEY' ~/.mcp/firecrawl.json)
  if [[ "$KEY" == fc-* ]]; then
    echo -e "  ${GREEN}✓${NC} firecrawl: API key injected (env block)"
  else
    echo -e "  ${RED}✗${NC} firecrawl: Invalid API key format"
    ((ERRORS++))
  fi
else
  echo -e "  ${RED}✗${NC} firecrawl: API key missing"
  ((ERRORS++))
fi

# Context7 (env block)
if jq -e '.mcpServers.context7.env.CONTEXT7_API_KEY' ~/.mcp/context7.json >/dev/null 2>&1; then
  KEY=$(jq -r '.mcpServers.context7.env.CONTEXT7_API_KEY' ~/.mcp/context7.json)
  if [[ "$KEY" == ctx7sk-* ]]; then
    echo -e "  ${GREEN}✓${NC} context7: API key injected (env block)"
  else
    echo -e "  ${RED}✗${NC} context7: Invalid API key format"
    ((ERRORS++))
  fi
else
  echo -e "  ${RED}✗${NC} context7: API key missing"
  ((ERRORS++))
fi

# Huggingface (--header arg)
if jq -e '.mcpServers."hf-mcp-server".args' ~/.mcp/huggingface.json >/dev/null 2>&1; then
  HEADER=$(jq -r '.mcpServers."hf-mcp-server".args[-1]' ~/.mcp/huggingface.json)
  if [[ "$HEADER" == "Authorization: Bearer hf_"* ]]; then
    echo -e "  ${GREEN}✓${NC} huggingface: Token injected (--header arg)"
  else
    echo -e "  ${RED}✗${NC} huggingface: Invalid header format"
    ((ERRORS++))
  fi
else
  echo -e "  ${RED}✗${NC} huggingface: Token missing"
  ((ERRORS++))
fi

# Agent-mail (HTTP transport with Bearer token)
if jq -e '.mcpServers."mcp-agent-mail".headers.Authorization' ~/.mcp/agent-mail.json >/dev/null 2>&1; then
  AUTH=$(jq -r '.mcpServers."mcp-agent-mail".headers.Authorization' ~/.mcp/agent-mail.json)
  if [[ "$AUTH" == "Bearer "* ]] && [[ ${#AUTH} -gt 20 ]]; then
    echo -e "  ${GREEN}✓${NC} agent-mail: Bearer token injected (HTTP headers)"
  else
    echo -e "  ${RED}✗${NC} agent-mail: Invalid Authorization header format"
    ((ERRORS++))
  fi
else
  echo -e "  ${RED}✗${NC} agent-mail: Authorization header missing"
  ((ERRORS++))
fi
echo ""

# 6. Compare structure with backup
echo "6. Comparing structure with backup..."
for file in ~/.mcp/*.json; do
  base=$(basename "$file")
  if [ -f ~/.mcp-backup-20251014/"$base" ]; then
    if diff <(jq -S '.mcpServers | keys' "$file") \
            <(jq -S '.mcpServers | keys' ~/.mcp-backup-20251014/"$base") >/dev/null 2>&1; then
      echo -e "  ${GREEN}✓${NC} $base structure matches backup"
    else
      echo -e "  ${YELLOW}⚠${NC}  $base structure differs from backup (may be expected)"
    fi
  else
    echo -e "  ${YELLOW}⚠${NC}  $base not in backup (new file)"
  fi
done
echo ""

# 7. Check Docker daemon (for terraform server)
echo "7. Checking Docker daemon (for terraform server)..."
if command -v docker &>/dev/null; then
  if docker info &>/dev/null; then
    echo -e "  ${GREEN}✓${NC} Docker daemon running"
  else
    echo -e "  ${YELLOW}⚠${NC}  Docker daemon not running - terraform MCP server will fail"
    echo "     Start OrbStack, Docker Desktop, or run: colima start"
  fi
else
  echo -e "  ${YELLOW}⚠${NC}  Docker not installed - terraform MCP server will not work"
fi
echo ""

# 8. Check mcp-prompt-server build
echo "8. Checking mcp-prompt-server build..."
if [ -f ~/projects/planning-workspace/mcp-prompts-server/dist/server.js ]; then
  echo -e "  ${GREEN}✓${NC} mcp-prompt-server already built"
else
  echo -e "  ${YELLOW}⚠${NC}  mcp-prompt-server not built"
  echo "     Build with: cd ~/projects/planning-workspace/mcp-prompts-server && npm run build"
fi
echo ""

# Summary
echo "=== Validation Summary ==="
if [ $ERRORS -eq 0 ]; then
  echo -e "${GREEN}✓ All critical validations passed!${NC}"
  echo ""
  echo "Next steps:"
  echo "  1. Test individual server: claude --mcp-config ~/.mcp/nixos.json"
  echo "  2. Test combination: claude --mcp-config ~/.mcp/historian.json ~/.mcp/chrome.json"
  echo "  3. Test with secrets: claude --mcp-config ~/.mcp/firecrawl.json"
  exit 0
else
  echo -e "${RED}✗ $ERRORS critical error(s) found${NC}"
  echo ""
  echo "Troubleshooting:"
  echo "  - Check home-manager activation: /nix/var/nix/profiles/per-user/\$USER/home-manager/activate"
  echo "  - Verify SOPS can decrypt: sops -d secrets/home-manager/users/crs58/secrets.yaml"
  echo "  - Check age key: ls ~/.config/sops/age/keys.txt"
  exit 1
fi
