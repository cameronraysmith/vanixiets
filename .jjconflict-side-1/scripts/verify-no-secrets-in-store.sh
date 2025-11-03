#!/usr/bin/env bash
# Verify no unencrypted secrets leaked into nix store
# Run before pushing to cachix to ensure security

set -euo pipefail

echo "=== Verifying No Secrets in Nix Store ==="
echo ""

# Color codes
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
NC='\033[0m' # No Color

# Track findings
SECRETS_FOUND=0
WARNINGS=0

# Get the system build output
if [ ! -e result ]; then
  echo -e "${RED}✗ No 'result' symlink found${NC}"
  echo "  Run: darwin-rebuild build --flake .#stibnite"
  exit 1
fi

SYSTEM_PATH=$(readlink result)
echo "Scanning build output: $SYSTEM_PATH"
echo ""

# 1. Check for SOPS placeholders (expected)
echo "1. Checking SOPS templates have placeholders..."
PLACEHOLDER_COUNT=$(nix-store -qR "$SYSTEM_PATH" | \
  xargs -I {} sh -c 'if [ -f {} ]; then cat {} 2>/dev/null || true; fi' | \
  grep -c "<SOPS:.*:PLACEHOLDER>" || true)

if [ "$PLACEHOLDER_COUNT" -gt 0 ]; then
  echo -e "  ${GREEN}✓${NC} Found $PLACEHOLDER_COUNT SOPS placeholders (expected)"
else
  echo -e "  ${YELLOW}⚠${NC}  No SOPS placeholders found (may not be using sops-nix)"
  ((WARNINGS++))
fi
echo ""

# 2. Check for actual secret patterns (should NOT exist)
echo "2. Scanning for potential secret patterns..."

# Define secret patterns to scan for
# Only check for patterns used in YOUR secrets (from mcp-api-keys.yaml)
declare -A SECRET_PATTERNS=(
  ["fc-[a-z0-9]\{32\}"]="Firecrawl API key (fc-{32 hex})"
  ["hf_[A-Za-z0-9]\{30,50\}"]="Hugging Face token (hf_{30-50 chars})"
  ["ctx7sk-[a-z0-9-]\{36\}"]="Context7 API key (ctx7sk-{uuid})"
)

for pattern in "${!SECRET_PATTERNS[@]}"; do
  desc="${SECRET_PATTERNS[$pattern]}"
  echo -n "  Scanning for $desc... "

  # Scan all files in closure for pattern (with timeout protection)
  MATCHES=$(timeout 30 sh -c "nix-store -qR '$SYSTEM_PATH' | \
    xargs -I {} sh -c 'if [ -f {} ]; then strings {} 2>/dev/null | grep -E \"$pattern\" || true; fi' | \
    grep -v '<SOPS:' | \
    head -3" || echo "")

  if [ -n "$MATCHES" ]; then
    echo -e "${RED}FOUND${NC}"
    echo "$MATCHES" | sed 's/^/    /'
    ((SECRETS_FOUND++))
  else
    echo -e "${GREEN}✓${NC}"
  fi
done
echo ""

# 3. Check encrypted files are still encrypted
echo "3. Verifying encrypted secret files..."
ENCRYPTED_FILES=$(find /nix/store -name "mcp-api-keys.yaml" 2>/dev/null | head -5 || true)

if [ -n "$ENCRYPTED_FILES" ]; then
  for file in $ENCRYPTED_FILES; do
    if head -1 "$file" | grep -q "#ENC\["; then
      echo -e "  ${GREEN}✓${NC} $(basename "$file") is encrypted (in $(dirname "$file" | rev | cut -d/ -f1 | rev))"
    else
      echo -e "  ${RED}✗ CRITICAL: $(basename "$file") appears unencrypted!${NC}"
      echo "    Path: $file"
      ((SECRETS_FOUND++))
    fi
  done
else
  echo -e "  ${YELLOW}⚠${NC}  No mcp-api-keys.yaml found (may not be using MCP secrets)"
fi
echo ""

# 4. Check for age keys (MUST NOT be in store)
echo "4. Checking age keys are not in store..."
AGE_KEY_FOUND=$(nix-store -qR "$SYSTEM_PATH" | \
  xargs -I {} sh -c 'if [ -f {} ]; then strings {} 2>/dev/null | grep -c "AGE-SECRET-KEY-" || true; fi' | \
  awk '{sum+=$1} END {print sum}')

if [ "$AGE_KEY_FOUND" -gt 0 ]; then
  echo -e "  ${RED}✗ CRITICAL: AGE secret key found in nix store!${NC}"
  echo "    This is a SEVERE security issue - age keys should never be in store"
  ((SECRETS_FOUND++))
else
  echo -e "  ${GREEN}✓${NC} No age secret keys in store"
fi
echo ""

# 5. Verify sops-install-secrets script exists
echo "5. Checking sops-nix activation infrastructure..."
SOPS_SCRIPT=$(nix-store -qR "$SYSTEM_PATH" | grep "sops-install-secrets" | head -1 || true)

if [ -n "$SOPS_SCRIPT" ]; then
  echo -e "  ${GREEN}✓${NC} sops-install-secrets found: $(basename "$SOPS_SCRIPT")"
else
  echo -e "  ${YELLOW}⚠${NC}  sops-install-secrets not found (may not be using sops-nix)"
  ((WARNINGS++))
fi
echo ""

# Summary
echo "=== Scan Summary ==="
if [ $SECRETS_FOUND -eq 0 ]; then
  echo -e "${GREEN}✓ No unencrypted secrets found in nix store${NC}"
  echo -e "${GREEN}✓ Safe to push to cachix${NC}"
  if [ $WARNINGS -gt 0 ]; then
    echo -e "${YELLOW}⚠  $WARNINGS warning(s) - review above${NC}"
  fi
  exit 0
else
  echo -e "${RED}✗ $SECRETS_FOUND secret leak(s) detected${NC}"
  echo -e "${RED}✗ DO NOT push to cachix until resolved${NC}"
  echo ""
  echo "Remediation steps:"
  echo "  1. Review files flagged above"
  echo "  2. Ensure secrets use sops-nix templates"
  echo "  3. Verify secrets are in sopsFile, not hardcoded"
  echo "  4. Re-run after fixes"
  exit 1
fi
