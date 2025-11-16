# Story 1.10D: Enable sops-nix Features - Dev Agent Hand-Off

**Status**: Ready for implementation (Story 1.10C infrastructure complete)
**Repository**: `~/projects/nix-workspace/test-clan/`
**Branch**: `phase-0-validation` (38 commits ahead of origin)
**Estimated Effort**: 2-3 hours

## Context: What Story 1.10C Accomplished

Story 1.10C established the **sops-nix infrastructure** for user-level secrets management:

✅ **Infrastructure Complete**:
- `.sops.yaml` with multi-user encryption (crs58, raquel, admin keys)
- sops-nix added to `flake.nix` inputs
- Base sops module created (`modules/home/base/sops.nix`)
- Encrypted secrets files created for both users
- Per-user sops declarations in `modules/home/users/{user}/default.nix`
- All 6 modules updated to reference `config.sops.secrets.*`

✅ **Build Validation**:
- `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage` ✓ SUCCESS
- `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage` ✓ SUCCESS

## Problem: Incorrect Placeholder Usage

Story 1.10C had to **comment out or use placeholders** for actual secret values because the initial implementation tried to access sops secrets at **BUILD TIME** (forbidden in pure evaluation mode).

**The core issue**: Using `builtins.readFile config.sops.secrets."secret-name".path` at build time causes:
```
error: access to absolute path '/Users' is forbidden in pure evaluation mode
```

**Why it fails**: sops-nix secrets are **only available at ACTIVATION TIME** (when home-manager activates), not during nix build evaluation.

## Solution: Use Correct sops-nix Patterns

The **infra repository** demonstrates the correct patterns. Search infra for working examples:

```bash
cd ~/projects/nix-workspace/infra
rg "config\.sops\.secrets" modules/home/
rg "sops\.placeholder" modules/home/
rg "sops\.templates" modules/home/
```

### Pattern Reference from infra

**Pattern 1: Direct Path Access (for programs that read from files)**
```nix
# Example: git.nix, jujutsu.nix - SSH signing keys
programs.git.signing.key = config.sops.secrets."ssh-signing-key".path;
# Resolves at activation time to: ~/.config/sops-nix/secrets/ssh-signing-key
```

**Pattern 2: Runtime Shell Script Access**
```nix
# Example: claude-code-wrappers.nix - GLM API key in wrapper script
text = ''
  GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
  export GLM_API_KEY
'';
# The $(cat ...) runs at script execution time, NOT build time
```

**Pattern 3: sops.templates with sops.placeholder (for JSON/config files)**
```nix
# Example: rbw.nix - Bitwarden config with secret email
sops.secrets."bitwarden-email" = { };

sops.templates."rbw-config" = {
  mode = "0400";
  path = "${config.home.homeDirectory}/Library/Application Support/rbw/config.json";
  content = builtins.toJSON {
    email = config.sops.placeholder."bitwarden-email";  # Placeholder replaced at activation
    lock_timeout = 86400;
    # ... other settings
  };
};

programs.rbw = {
  enable = true;
  settings = null;  # Use sops template instead of home-manager settings
};
```

**Pattern 4: sops.templates for MCP Server JSON Configs**
```nix
# Example: mcp-servers.nix - MCP servers with API keys
sops.secrets."firecrawl-api-key" = { };
sops.secrets."huggingface-token" = { };

sops.templates.mcp-firecrawl = {
  mode = "0400";
  path = "${config.home.homeDirectory}/.mcp/firecrawl.json";
  content = builtins.toJSON {
    mcpServers.firecrawl = {
      type = "stdio";
      command = "npx";
      args = [ "-y" "firecrawl-mcp" ];
      env = {
        FIRECRAWL_API_KEY = config.sops.placeholder."firecrawl-api-key";
      };
    };
  };
};

sops.templates.mcp-huggingface = {
  mode = "0400";
  path = "${config.home.homeDirectory}/.mcp/huggingface.json";
  content = builtins.toJSON {
    mcpServers."hf-mcp-server" = {
      command = "npx";
      args = [
        "mcp-remote"
        "https://huggingface.co/mcp"
        "--header"
        "Authorization: Bearer ${config.sops.placeholder."huggingface-token"}"
      ];
    };
  };
};
```

## Your Mission: Fix 6 Modules + 2 User Configs

### Files to Update

**Path**: All files in `~/projects/nix-workspace/test-clan/modules/home/`

1. **`development/git.nix`** (AC10)
   - Current: `key = config.sops.secrets.ssh-signing-key.path;` ✅ ALREADY CORRECT
   - No changes needed - Pattern 1 already used correctly

2. **`development/jujutsu.nix`** (AC11)
   - Current: `key = lib.mkDefault config.sops.secrets.ssh-signing-key.path;` ✅ ALREADY CORRECT
   - No changes needed - Pattern 1 already used correctly

3. **`ai/claude-code/wrappers.nix`** (AC13)
   - Current (WRONG):
     ```nix
     GLM_API_KEY="placeholder-deferred-to-1.10D"
     ```
   - Fix to (Pattern 2):
     ```nix
     GLM_API_KEY="$(cat ${config.sops.secrets."glm-api-key".path})"
     ```
   - Reference: `infra/modules/home/all/tools/claude-code-wrappers.nix:25`

4. **`ai/claude-code/mcp-servers.nix`** (AC12)
   - Current (WRONG): Using `home.file.".mcp/firecrawl.json".text` with placeholders
   - Fix to (Pattern 4): Convert to `sops.templates`
   - Steps:
     a. Remove all `home.file.".mcp/*.json"` definitions for servers WITH secrets (firecrawl, huggingface)
     b. Add `sops.templates.mcp-firecrawl` and `sops.templates.mcp-huggingface`
     c. Keep `home.file` for servers WITHOUT secrets (chrome, cloudflare, duckdb, etc.)
   - Reference: `infra/modules/home/all/tools/claude-code/mcp-servers.nix:39-106`
   - **CRITICAL**: Only 2 MCP servers in test-clan (firecrawl, huggingface), NOT 3 like infra (which has context7)

5. **`shell/atuin.nix`** (AC14)
   - Current (WRONG): Commented out key deployment
   - Fix to (Pattern 1): Symlink or activation script to deploy key
   - Options:
     a. Use `home.file.".local/share/atuin/key".source = config.sops.secrets.atuin-key.path;` if it works
     b. OR use `home.activation` script to create symlink at activation time
   - **Test both approaches** - if `.source` with sops path works, use it (simpler)

6. **`shell/rbw.nix`** (AC15)
   - Current (WRONG):
     ```nix
     bitwardenEmail = "placeholder-deferred-to-1.10D";
     programs.rbw.settings.email = bitwardenEmail;
     ```
   - Fix to (Pattern 3):
     ```nix
     sops.secrets."bitwarden-email" = { };

     sops.templates."rbw-config" = {
       path = if pkgs.stdenv.isDarwin
         then "${config.home.homeDirectory}/Library/Application Support/rbw/config.json"
         else "${config.xdg.configHome}/rbw/config.json";
       content = builtins.toJSON {
         email = config.sops.placeholder."bitwarden-email";
         # ... copy all other settings from current programs.rbw.settings
       };
     };

     programs.rbw = {
       enable = true;
       settings = null;  # Disable home-manager settings, use sops template
     };
     ```
   - Reference: `infra/modules/home/all/tools/rbw.nix:17-45`

7. **`users/crs58/default.nix`** (AC10 - allowed_signers)
   - Current (WRONG): Commented out allowed_signers
   - Fix to: Extract public key from private key at activation time
   - Approach:
     ```nix
     home.activation.generateAllowedSigners = lib.hm.dag.entryAfter [ "writeBoundary" ] ''
       if [ -f ${config.sops.secrets.ssh-signing-key.path} ]; then
         pubkey=$(ssh-keygen -y -f ${config.sops.secrets.ssh-signing-key.path})
         echo "cameron.ray.smith@gmail.com namespaces=\"git\" $pubkey" > ${config.xdg.configHome}/git/allowed_signers
       fi
     '';
     ```

8. **`users/raquel/default.nix`** (AC10 - allowed_signers)
   - Same pattern as crs58, but with raquel's email

### Secrets Inventory (Reference)

**crs58/cameron secrets** (7 total):
- `github-token` - Git operations, gh CLI (NOT currently used in modules - future)
- `ssh-signing-key` - Git/jujutsu SSH signing (git.nix, jujutsu.nix) ✅
- `glm-api-key` - GLM wrapper (wrappers.nix) ❌ FIX NEEDED
- `firecrawl-api-key` - Firecrawl MCP (mcp-servers.nix) ❌ FIX NEEDED
- `huggingface-token` - HuggingFace MCP (mcp-servers.nix) ❌ FIX NEEDED
- `bitwarden-email` - Bitwarden config (rbw.nix) ❌ FIX NEEDED
- `atuin-key` - Shell history encryption (atuin.nix) ❌ FIX NEEDED

**raquel secrets** (4 total):
- `github-token`, `ssh-signing-key` ✅, `bitwarden-email` ❌, `atuin-key` ❌

### Acceptance Criteria (from Story Work Item)

**AC10**: ✅ git.nix already correct
**AC11**: ✅ jujutsu.nix already correct
**AC12**: ❌ mcp-servers.nix needs sops.templates conversion
**AC13**: ❌ wrappers.nix needs runtime cat access
**AC14**: ❌ atuin.nix needs key deployment
**AC15**: ❌ rbw.nix needs sops.templates conversion

**AC16-AC18**: Build validation (re-run after fixes)
- `nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage`
- `nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage`

**AC19**: Test activation (optional, if time permits)
- Deploy to test machine and verify secrets are accessible

## Critical Gotchas

### 1. Build Time vs Activation Time

**WRONG** (causes pure eval error):
```nix
bitwardenEmail = builtins.readFile config.sops.secrets."bitwarden-email".path;
```

**CORRECT** (activation time):
```nix
email = config.sops.placeholder."bitwarden-email";  # In sops.templates
```

### 2. Two-Layer Module System (from Architecture Doc)

**OUTER** (flake-parts module):
```nix
{ config, inputs, ... }:  # NO 'flake' parameter
```

**INNER** (home-manager module):
```nix
{ config, pkgs, flake, ... }:  # 'flake' via extraSpecialArgs
```

Reference: `~/projects/nix-workspace/infra/docs/notes/development/test-clan-validated-architecture.md:728-1105`

### 3. Secret Names in test-clan vs infra

**test-clan** (flat structure):
- `config.sops.secrets."ssh-signing-key".path`
- `config.sops.secrets."glm-api-key".path`

**infra** (per-user structure):
- `config.sops.secrets."${user.sopsIdentifier}/signing-key".path`
- `config.sops.secrets."glm-api-key".path`

**Use test-clan flat names** - don't copy infra's per-user path structure.

### 4. MCP Servers: 2 vs 3

**test-clan**: 2 MCP servers with secrets (firecrawl, huggingface)
**infra**: 3 MCP servers with secrets (firecrawl, huggingface, context7)

Don't create context7 template - test-clan doesn't have that secret.

## Validation Commands

```bash
cd ~/projects/nix-workspace/test-clan

# 1. Build validation
nix build .#homeConfigurations.aarch64-darwin.crs58.activationPackage
nix build .#homeConfigurations.aarch64-darwin.raquel.activationPackage

# 2. Verify sops templates are generated
ls -la result/home-path/  # Look for sops-nix activation scripts

# 3. Check template paths (if activation works)
# Templates will be in ~/.config/sops-nix/secrets/ after activation
```

## Commit Strategy

**Atomic commits per module** (follow infra git workflow):
1. `refactor(story-1.10D): enable glm-api-key in wrappers.nix`
2. `refactor(story-1.10D): convert mcp-servers to sops.templates`
3. `refactor(story-1.10D): enable atuin-key deployment`
4. `refactor(story-1.10D): convert rbw to sops.templates`
5. `refactor(story-1.10D): enable SSH allowed_signers generation`
6. Final validation commit

## Success Criteria

✅ **All builds pass** (crs58, raquel)
✅ **No placeholder values** in final code
✅ **All 6 modules use correct sops patterns** from infra reference
✅ **Secrets accessible at activation time** (not build time)
✅ **Git commits follow atomic pattern** (one logical change per file)

## Key References

**Architecture**: `~/projects/nix-workspace/infra/docs/notes/development/test-clan-validated-architecture.md:728-1105`
**infra sops patterns**:
- `infra/modules/home/all/tools/claude-code-wrappers.nix` (runtime cat)
- `infra/modules/home/all/tools/claude-code/mcp-servers.nix` (sops.templates)
- `infra/modules/home/all/tools/rbw.nix` (sops.templates)
- `infra/modules/home/all/development/git.nix` (direct path)

**Story context**: `~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10c-establish-sops-nix-secrets-home-manager.md`

## Estimated Timeline

- 30min: wrappers.nix (simple runtime cat fix)
- 45min: mcp-servers.nix (convert to sops.templates, reference infra)
- 30min: atuin.nix (test .source approach, fallback to activation script)
- 45min: rbw.nix (convert to sops.templates, reference infra)
- 30min: allowed_signers (activation script for both users)
- 30min: Build validation + fixes

**Total**: 2.5-3 hours

Good luck! The infrastructure is solid from 1.10C - you just need to enable the features using the correct activation-time patterns from infra. 🚀
