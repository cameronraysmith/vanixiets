# Story 1.10E: Enable Remaining Features Using sops-nix Secrets and Flake Inputs

**Epic:** Epic 1 - Architectural Validation + Migration Pattern Rehearsal (Phase 0)

**Status:** ready-for-dev

**Dependencies:**
- Story 1.10C (done): sops-nix infrastructure established, 9/11 features enabled
- Story 1.10D (done): pkgs-by-name pattern validated (ccstatusline package created)
- Story 1.10DB (done): Overlay architecture migration (Layers 1,2,4,5 validated)

**Blocks:**
- Story 1.12 (backlog): GO/NO-GO decision benefits from complete feature enablement
- Epic 2-6 migration: Teams need validated flake.inputs integration patterns

**Strategic Value:** Completes Pattern A + sops-nix + flake.inputs validation trilogy by enabling remaining 3 features (claude-code package, ccstatusline feature, catppuccin tmux theme), proves flake.inputs integration patterns work alongside sops-nix secrets and custom packages, provides Epic 2-6 teams with complete feature enablement guide covering all 4 secret access patterns (direct path, sops.placeholder, runtime cat, activation scripts) plus flake.inputs module/package overrides, achieves ~98% Epic 1 coverage (architecture + features empirically validated).

**Effort:** 1.5-2 hours
**Risk Level:** Low (9/11 features already enabled in Story 1.10C, infrastructure validated, only flake.inputs configuration remaining)

---

## Story Description

As a system administrator,
I want to enable the remaining 3 disabled home-manager features using flake.inputs (for packages/themes) and custom packages (from Story 1.10D),
So that all production features are functional in test-clan demonstrating complete integration of sops-nix secrets + flake.inputs + custom packages.

**Context:**

Story 1.10C established sops-nix user-level secrets infrastructure (age encryption, multi-user support, sops.templates patterns) and during implementation (61 commits, 2025-11-15 to 2025-11-16), **9 of 11 Story 1.10E features were already enabled** using sops-nix patterns:
- SSH signing (git.nix, jujutsu.nix) via direct path pattern
- MCP API keys (firecrawl, huggingface) via sops.templates + sops.placeholder
- GLM wrapper via runtime cat pattern in shell script
- Atuin encryption key via activation script
- Bitwarden (rbw) email via sops.templates
- Git allowed_signers via sops.templates

Story 1.10D validated custom package overlays with pkgs-by-name pattern, implementing ccstatusline package infrastructure (provides `pkgs.ccstatusline` for Story 1.10E feature enablement).

Story 1.10DB migrated infra's 5-layer overlay architecture to test-clan dendritic structure and validated hybrid pattern (overlays + pkgs-by-name coexistence).

**Story 1.10E completes feature enablement arc** by:
1. Adding flake.inputs for external packages/themes (nix-ai-tools, catppuccin-nix)
2. Enabling claude-code package override (AC D)
3. Enabling catppuccin tmux theme (AC E)
4. Enabling ccstatusline feature integration (AC F)
5. Documenting all feature enablement patterns in Section 13 (AC H)

**Remaining Story 1.10E Scope (3 features):**

**Feature 1: claude-code package (AC D)**
- **Current state:** Commented out in default.nix:24 (blocks: nix-ai-tools flake input not configured)
- **Enablement:** Add nix-ai-tools flake input, uncomment package override
- **Pattern:** flake.inputs package override (`flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code`)
- **Estimated effort:** 30 min

**Feature 2: ccstatusline (AC F)**
- **Current state:** Package exists (`pkgs.ccstatusline` from Story 1.10D), settings configured (ccstatusline-settings.nix, 175 lines), feature commented out in default.nix
- **Enablement:** Uncomment statusLine config in claude-code/default.nix
- **Pattern:** Custom package integration (pkgs-by-name from Story 1.10D)
- **Estimated effort:** 15 min

**Feature 3: catppuccin tmux theme (AC E)**
- **Current state:** TODO comment in tmux.nix:40 (blocks: catppuccin-nix flake input not configured)
- **Enablement:** Add catppuccin-nix flake input, import module, configure theme
- **Pattern:** flake.inputs module import (`flake.inputs.catppuccin-nix.homeManagerModules.catppuccin`)
- **Estimated effort:** 45 min

**Story 1.10C Already-Enabled Features (9 features, documented in AC A-C):**
1. ✅ Git SSH signing (git.nix) - direct path pattern
2. ✅ Jujutsu SSH signing (jujutsu.nix) - direct path pattern
3. ✅ MCP firecrawl API key (mcp-servers.nix) - sops.templates + sops.placeholder
4. ✅ MCP huggingface token (mcp-servers.nix) - sops.templates + sops.placeholder
5. ✅ GLM wrapper (wrappers.nix) - runtime cat pattern
6. ✅ Atuin encryption key (atuin.nix) - activation script pattern
7. ✅ Bitwarden (rbw) email (wrappers.nix) - sops.templates pattern
8. ✅ Git allowed_signers (git.nix) - sops.templates pattern
9. ⚠️ MCP context7 - NOT in test-clan scope (implementation documents "Only 2 MCP servers")

---

## Implementation Notes

### Feature Enablement Architecture

**Architectural Context:**

Story 1.10E completes Epic 1's comprehensive validation of dendritic flake-parts + clan-core integration by proving all feature enablement patterns work together:

1. **sops-nix Secrets (Story 1.10C validated):** 4 distinct access patterns
2. **Custom Packages (Story 1.10D validated):** pkgs-by-name pattern
3. **Overlay Architecture (Story 1.10DB validated):** 5-layer overlay system
4. **Flake.inputs Integration (Story 1.10E validates):** Module imports + package overrides

**Pattern 1: sops-nix Direct Path Access**

Used for programs that read files directly (git, jujutsu SSH signing).

```nix
# Example: git.nix SSH signing
programs.git.signing = {
  key = config.sops.secrets.ssh-signing-key.path;
  format = "ssh";
  signByDefault = true;
};
```

**Access mechanism:** Program reads secret file directly via filesystem path
**Story 1.10C implementation:** git.nix:24-28, jujutsu.nix:41

**Pattern 2: sops-nix Templates with Placeholders**

Used for programs requiring structured config files with embedded secrets (MCP servers, rbw).

```nix
# Example: MCP firecrawl server
sops.templates.mcp-firecrawl = {
  content = builtins.toJSON {
    mcpServers.firecrawl.env = {
      FIRECRAWL_API_KEY = config.sops.placeholder."firecrawl-api-key";
    };
  };
  path = "${config.xdg.configHome}/claude/claude_desktop_config.json";
};
```

**Access mechanism:** sops-nix generates file with placeholders replaced by secret values
**Story 1.10C implementation:** mcp-servers.nix:34-73, wrappers.nix:54-85

**Pattern 3: sops-nix Runtime Cat in Shell Scripts**

Used for shell wrappers needing environment variables from secrets (GLM wrapper).

```nix
# Example: GLM wrapper
home.packages = [
  (pkgs.writeShellApplication {
    name = "claude-glm";
    text = ''
      GLM_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
      export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"
      exec claude "$@"
    '';
  })
];
```

**Access mechanism:** Shell script reads secret file at runtime and exports as environment variable
**Story 1.10C implementation:** wrappers.nix:23-44

**Pattern 4: sops-nix Activation Scripts**

Used for deploying secrets to non-XDG locations (atuin encryption key).

```nix
# Example: Atuin encryption key deployment
home.activation.atuinKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
  ${pkgs.coreutils}/bin/install -D -m600 \
    ${config.sops.secrets.atuin-encryption-key.path} \
    ${config.home.homeDirectory}/.local/share/atuin/key
'';
```

**Access mechanism:** Home-manager activation script copies secret to target location during activation
**Story 1.10C implementation:** atuin.nix:38-45

**Pattern 5: flake.inputs Package Override**

Used for packages from external flakes (claude-code from nix-ai-tools).

```nix
# Example: claude-code package override (Story 1.10E AC D)
programs.claude-code.package =
  flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;
```

**Access mechanism:** Override home-manager module's default package with package from flake input
**Story 1.10E scope:** default.nix:24 (currently commented out)

**Pattern 6: flake.inputs Module Import**

Used for home-manager modules from external flakes (catppuccin theme).

```nix
# Example: catppuccin tmux theme (Story 1.10E AC E)
imports = [ flake.inputs.catppuccin-nix.homeManagerModules.catppuccin ];

programs.tmux.catppuccin = {
  enable = true;
  flavor = "mocha";
  # ... 36 lines of theme configuration
};
```

**Access mechanism:** Import home-manager module from flake input, configure via module options
**Story 1.10E scope:** tmux.nix:40 (currently TODO comment)

**Pattern 7: Custom Package Integration**

Used for custom derivations via pkgs-by-name (ccstatusline).

```nix
# Example: ccstatusline feature (Story 1.10E AC F)
programs.claude-code.settings.statusLine = {
  type = "command";
  command = "${pkgs.ccstatusline}/bin/ccstatusline";
  padding = 0;
};
```

**Access mechanism:** Reference custom package from pkgs-by-name auto-discovery
**Story 1.10E scope:** default.nix statusLine config (currently commented out)
**Story 1.10D validation:** pkgs.ccstatusline package exists, builds successfully

### Story 1.10C Feature Review

**Objective:** Document already-enabled features for Epic 2-6 reference (AC A-C)

**Story 1.10C Implementation Evidence:**

Story 1.10C enabled 9 of 11 Story 1.10E features during sops-nix infrastructure implementation. The following features are **already functional** and require only documentation:

**AC A: Git and Jujutsu SSH Signing (Pattern 1: Direct Path)**

Feature enabled in Story 1.10C commit f9e9e92 (git) and 04c1617 (jujutsu).

**Implementation:**
```nix
# git.nix lines 24-28
programs.git.signing = lib.mkDefault {
  key = config.sops.secrets.ssh-signing-key.path;
  format = "ssh";
  signByDefault = true;
};

# jujutsu.nix line 41
user.signing-key = lib.mkDefault config.sops.secrets.ssh-signing-key.path;
```

**Pattern characteristics:**
- Secret access: Direct filesystem path (`config.sops.secrets.ssh-signing-key.path`)
- Use case: Programs reading secret files directly (git, jujutsu, SSH)
- Advantages: Simple, no file generation overhead, works with file-based tools
- Limitations: Cannot embed secrets in structured configs (use Pattern 2 instead)

**AC B: MCP Server API Keys (Pattern 2: sops.templates + Placeholders)**

Features enabled in Story 1.10C commit c63b61e.

**Implementation:**
```nix
# mcp-servers.nix lines 34-52 (firecrawl)
sops.templates.mcp-firecrawl = {
  content = builtins.toJSON {
    mcpServers.firecrawl = {
      command = "uvx";
      args = ["mcp-server-firecrawl"];
      env.FIRECRAWL_API_KEY = config.sops.placeholder."firecrawl-api-key";
    };
  };
  path = "${config.xdg.configHome}/claude/claude_desktop_config.json";
};

# mcp-servers.nix lines 56-73 (huggingface)
sops.templates.mcp-huggingface = {
  content = builtins.toJSON {
    mcpServers.huggingface = {
      command = "uvx";
      args = [
        "--from"
        "git+https://github.com/huggingface/mcp-server-huggingface"
        "mcp-server-huggingface"
        "--header"
        "Authorization: Bearer ${config.sops.placeholder."huggingface-token"}"
      ];
    };
  };
};
```

**Pattern characteristics:**
- Secret access: `config.sops.placeholder."secret-name"` in template content
- Use case: Structured config files (JSON, TOML, YAML) with embedded secrets
- Advantages: sops-nix generates complete file atomically, proper permissions, secret values never in nix store
- Limitations: Entire file regenerated when any secret changes

**Additional Pattern 2 Examples (Bonus Features):**

```nix
# wrappers.nix lines 54-85 (rbw email)
sops.templates.rbw-config = {
  content = builtins.toJSON {
    email = config.sops.placeholder."rbw-email";
    # ... other config
  };
  path = "${config.xdg.configHome}/rbw/config.json";
};

# git.nix lines 36-49 (allowed_signers)
sops.templates.git-allowed-signers = {
  content = ''
    cameron@cameronraysmith.com ${config.sops.placeholder."ssh-signing-key-public"}
    crs58@cameronraysmith.com ${config.sops.placeholder."ssh-signing-key-public"}
  '';
  path = "${config.xdg.configHome}/git/allowed_signers";
};
```

**AC C: GLM Wrapper (Pattern 3: Runtime Cat in Shell Scripts)**

Feature enabled in Story 1.10C commit f6b01e3.

**Implementation:**
```nix
# wrappers.nix lines 23-44
home.packages = [
  (pkgs.writeShellApplication {
    name = "claude-glm";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Read secret at runtime and export as environment variable
      GLM_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
      export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"

      # Execute claude with all arguments
      exec claude "$@"
    '';
  })
];
```

**Pattern characteristics:**
- Secret access: `$(cat ${config.sops.secrets.secret-name.path})` in shell script
- Use case: Shell wrappers needing environment variables from secrets
- Advantages: Runtime secret access, works with programs expecting env vars, no file generation
- Limitations: Secret read on every execution (minimal overhead but visible in process list briefly)

**Additional Pattern 4 Example (Bonus Feature):**

```nix
# atuin.nix lines 38-45 (activation script)
home.activation.atuinKey = lib.hm.dag.entryAfter ["writeBoundary"] ''
  # Deploy secret to non-XDG location during home-manager activation
  ${pkgs.coreutils}/bin/install -D -m600 \
    ${config.sops.secrets.atuin-encryption-key.path} \
    ${config.home.homeDirectory}/.local/share/atuin/key
'';
```

**Pattern characteristics:**
- Secret access: Reference `config.sops.secrets.secret-name.path` in activation script
- Use case: Deploying secrets to non-XDG locations, custom file permissions, multi-file setups
- Advantages: Full control over deployment, works with legacy programs, custom permissions
- Limitations: Only runs during home-manager activation (not on secret updates)

### Remaining Feature Enablement

**Objective:** Enable 3 remaining features using flake.inputs + custom packages (AC D-F)

**AC D: claude-code Package Override (Pattern 5: flake.inputs Package)**

**Current state:** Commented out in default.nix:24

**Enablement steps:**

1. **Add nix-ai-tools flake input to flake.nix:**
   ```nix
   # flake.nix inputs section
   inputs.nix-ai-tools = {
     url = "github:cameronraysmith/nix-ai-tools";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. **Uncomment package override in default.nix:24:**
   ```nix
   # modules/home-manager/claude-code/default.nix
   programs.claude-code.package =
     flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;
   ```

3. **Update flake.lock:**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nix flake lock
   ```

4. **Validate package accessible:**
   ```bash
   # Verify package evaluates
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.package
   # Expected: derivation from nix-ai-tools

   # Build package
   nix build .#homeConfigurations.crs58.config.programs.claude-code.package
   # Expected: build succeeds
   ```

**Pattern notes:**
- `flake.inputs.X.packages.${pkgs.system}.Y` accesses packages from flake inputs
- Use `inputs.nixpkgs.follows = "nixpkgs"` to prevent duplicate nixpkgs evaluations
- Package override pattern works for any home-manager module with `package` option

**AC E: catppuccin tmux Theme (Pattern 6: flake.inputs Module)**

**Current state:** TODO comment in tmux.nix:40

**Enablement steps:**

1. **Add catppuccin-nix flake input to flake.nix:**
   ```nix
   # flake.nix inputs section
   inputs.catppuccin-nix = {
     url = "github:catppuccin/nix";
   };
   ```

2. **Replace TODO in tmux.nix:40 with module import and configuration:**
   ```nix
   # modules/home-manager/tmux.nix
   { flake, ... }:
   {
     imports = [ flake.inputs.catppuccin-nix.homeManagerModules.catppuccin ];

     programs.tmux.catppuccin = {
       enable = true;
       flavor = "mocha";
       extraConfig = ''
         # Status bar configuration (36 lines from infra reference)
         set -g @catppuccin_window_left_separator ""
         set -g @catppuccin_window_right_separator " "
         set -g @catppuccin_window_middle_separator " █"
         set -g @catppuccin_window_number_position "right"
         set -g @catppuccin_window_default_fill "number"
         set -g @catppuccin_window_default_text "#W"
         set -g @catppuccin_window_current_fill "number"
         set -g @catppuccin_window_current_text "#W"
         set -g @catppuccin_status_modules_right "directory user host session"
         set -g @catppuccin_status_left_separator  " "
         set -g @catppuccin_status_right_separator ""
         set -g @catppuccin_status_right_separator_inverse "no"
         set -g @catppuccin_status_fill "icon"
         set -g @catppuccin_status_connect_separator "no"
         set -g @catppuccin_directory_text "#{pane_current_path}"
       '';
     };
   }
   ```

3. **Update flake.lock:**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nix flake lock
   ```

4. **Validate theme configuration:**
   ```bash
   # Build homeConfiguration
   nix build .#homeConfigurations.crs58.activationPackage
   # Expected: build succeeds

   # Check tmux.conf generation
   nix eval .#homeConfigurations.crs58.config.programs.tmux.extraConfig
   # Expected: catppuccin config present
   ```

5. **Visual validation (manual):**
   - Activate homeConfiguration on test machine
   - Launch tmux session
   - Verify catppuccin mocha theme renders (blue/pink/purple color scheme)
   - Verify status bar modules display (directory, user, host, session)

**Pattern notes:**
- `flake.inputs.X.homeManagerModules.Y` imports home-manager modules from flake inputs
- Module import pattern enables full module option system (type checking, merging, etc.)
- catppuccin-nix provides modules for tmux, zsh, bat, fzf, and other programs

**AC F: ccstatusline Feature (Pattern 7: Custom Package Integration)**

**Current state:** Package exists (Story 1.10D), settings configured, feature commented out

**Enablement steps:**

1. **Uncomment statusLine config in default.nix:**
   ```nix
   # modules/home-manager/claude-code/default.nix
   programs.claude-code.settings.statusLine = {
     type = "command";
     command = "${pkgs.ccstatusline}/bin/ccstatusline";
     padding = 0;
   };
   ```

2. **Validate package reference:**
   ```bash
   # Verify ccstatusline package accessible
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command
   # Expected: /nix/store/...-ccstatusline-.../bin/ccstatusline

   # Build ccstatusline package
   nix build .#ccstatusline
   # Expected: build succeeds (Story 1.10D validation)
   ```

3. **Validate settings integration:**
   ```bash
   # Check ccstatusline-settings.nix configuration
   nix eval .#homeConfigurations.crs58.config.programs.ccstatusline-settings.segments
   # Expected: 3 segments (git, shell, directory)

   # Verify powerline style
   nix eval .#homeConfigurations.crs58.config.programs.ccstatusline-settings.powerline_style
   # Expected: true
   ```

4. **Runtime validation (manual):**
   - Activate homeConfiguration on test machine
   - Launch Claude Code CLI
   - Verify status line displays at top (3-line powerline: git branch, shell, directory)
   - Verify ccstatusline-settings.nix config applied

**Pattern notes:**
- `${pkgs.ccstatusline}` references custom package from pkgs-by-name (Story 1.10D)
- Package available via pkgs-by-name-for-flake-parts auto-discovery
- Settings module (ccstatusline-settings.nix) already configured (175 lines, production-ready)

### Build Validation Strategy

**Objective:** Validate all features enabled without breaking existing builds (AC G)

**Quality Gate: Comprehensive Build Matrix**

Test all 4 configurations with new features enabled:

```bash
# homeConfiguration: crs58 (primary test user)
nix build .#homeConfigurations.crs58.activationPackage
# Expected: build succeeds, all features configured

# homeConfiguration: raquel (secondary test user)
nix build .#homeConfigurations.raquel.activationPackage
# Expected: build succeeds (inherits features via base modules)

# darwinConfiguration: blackphos (nix-darwin laptop)
nix build .#darwinConfigurations.blackphos.system
# Expected: build succeeds (includes home-manager with features)

# nixosConfiguration: cinnabar (nixos VPS)
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
# Expected: build succeeds (includes home-manager with features)
```

**Pass criteria:**
- ✅ All 4 builds succeed (no evaluation errors)
- ✅ All 4 builds complete in reasonable time (< 10 min each)
- ✅ No new build failures introduced by feature enablement
- ✅ Story 1.10C/1.10D/1.10DB validations still pass (zero regression)

**Feature-Specific Validation:**

After builds succeed, validate each new feature:

```bash
# Feature 1: claude-code package override
nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.pname
# Expected: "claude-code" from nix-ai-tools

nix build .#homeConfigurations.crs58.config.programs.claude-code.package
# Expected: build succeeds

# Feature 2: ccstatusline feature
nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command
# Expected: /nix/store/...-ccstatusline-.../bin/ccstatusline

nix build .#ccstatusline
# Expected: build succeeds (Story 1.10D package)

# Feature 3: catppuccin tmux theme
nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable
# Expected: true

nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.flavor
# Expected: "mocha"
```

**Regression Prevention:**

Validate Story 1.10C/1.10D/1.10DB functionality maintained:

```bash
# Story 1.10C: sops-nix secrets
nix eval .#homeConfigurations.crs58.config.sops.secrets.ssh-signing-key.sopsFile
# Expected: path to secrets.yaml

nix eval .#homeConfigurations.crs58.config.programs.git.signing.key
# Expected: /run/user/1000/secrets/ssh-signing-key (sops secret path)

# Story 1.10D: pkgs-by-name custom packages
nix build .#checks.aarch64-darwin.home-module-exports
# Expected: build succeeds

nix build .#checks.aarch64-darwin.home-configurations-exposed
# Expected: build succeeds

# Story 1.10DB: overlay architecture
nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
# Expected: stable version (Layer 1 multi-channel)

nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version
# Expected: stable version (Layer 2 hotfix)
```

**Pass criteria:**
- ✅ All Story 1.10C validations pass (sops-nix working)
- ✅ All Story 1.10D validations pass (pkgs-by-name working)
- ✅ All Story 1.10DB validations pass (overlay layers working)
- ✅ Zero regressions introduced by Story 1.10E changes

### Documentation Strategy

**Objective:** Create Section 13 comprehensive feature enablement guide (AC H)

**Section 13 Structure:**

```markdown
## 13. Feature Enablement Patterns

### 13.1 sops-nix Secret Access Patterns

**Pattern 1: Direct Path Access**
- Use case: Programs reading secret files directly
- Example: Git/Jujutsu SSH signing
- Implementation: `config.sops.secrets.X.path`
- Code example from git.nix with validation

**Pattern 2: sops.templates with Placeholders**
- Use case: Structured config files with embedded secrets
- Example: MCP server configs, rbw config
- Implementation: `config.sops.placeholder."X"` in sops.templates
- Code example from mcp-servers.nix with validation

**Pattern 3: Runtime Cat in Shell Scripts**
- Use case: Shell wrappers with environment variables from secrets
- Example: GLM wrapper
- Implementation: `$(cat ${config.sops.secrets.X.path})`
- Code example from wrappers.nix with validation

**Pattern 4: Activation Scripts**
- Use case: Deploying secrets to non-XDG locations
- Example: Atuin encryption key
- Implementation: home.activation with install command
- Code example from atuin.nix with validation

### 13.2 flake.inputs Integration Patterns

**Pattern 5: Package Override**
- Use case: Packages from external flakes
- Example: claude-code from nix-ai-tools
- Implementation: `flake.inputs.X.packages.${pkgs.system}.Y`
- Code example from default.nix with validation

**Pattern 6: Module Import**
- Use case: Home-manager modules from external flakes
- Example: catppuccin theme
- Implementation: `imports = [ flake.inputs.X.homeManagerModules.Y ];`
- Code example from tmux.nix with validation

### 13.3 Custom Package Integration

**Pattern 7: pkgs-by-name Custom Packages**
- Use case: Custom derivations via pkgs-by-name
- Example: ccstatusline
- Implementation: `${pkgs.X}` reference to package from pkgs/by-name/
- Code example from default.nix with validation
- Reference: Section 13.1 (Story 1.10D pkgs-by-name tutorial)

### 13.4 Enabled Features Summary

**Complete Feature List (11 features):**

1. ✅ Git SSH signing (Pattern 1: direct path)
2. ✅ Jujutsu SSH signing (Pattern 1: direct path)
3. ✅ MCP firecrawl API key (Pattern 2: sops.templates)
4. ✅ MCP huggingface token (Pattern 2: sops.templates)
5. ✅ GLM wrapper (Pattern 3: runtime cat)
6. ✅ Atuin encryption key (Pattern 4: activation script)
7. ✅ Bitwarden (rbw) email (Pattern 2: sops.templates)
8. ✅ Git allowed_signers (Pattern 2: sops.templates)
9. ✅ claude-code package (Pattern 5: flake.inputs package)
10. ✅ ccstatusline (Pattern 7: custom package)
11. ✅ catppuccin tmux theme (Pattern 6: flake.inputs module)

**Pattern Coverage:**
- 4 sops-nix patterns (direct path, templates, runtime cat, activation)
- 2 flake.inputs patterns (package override, module import)
- 1 custom package pattern (pkgs-by-name)

**Story Coverage:**
- Story 1.10C: Features 1-8 (sops-nix infrastructure + enablement)
- Story 1.10D: ccstatusline package (pkgs-by-name validation)
- Story 1.10E: Features 9-11 (flake.inputs + custom package enablement)

### 13.5 Build Validation

**All 4 Configurations Build Commands:**
```bash
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage
nix build .#darwinConfigurations.blackphos.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
```

**Feature Inspection Commands:**
[Include validation commands from AC G with expected outputs]

### 13.6 Epic 2-6 Migration Guide

**Feature Enablement Checklist:**
1. Identify required secrets (sops-nix patterns 1-4)
2. Identify required external packages/modules (flake.inputs patterns 5-6)
3. Identify required custom packages (pkgs-by-name pattern 7)
4. Configure secrets in sops.yaml
5. Add flake.inputs for external dependencies
6. Create custom packages in pkgs/by-name/
7. Enable features in home-manager modules
8. Validate builds and runtime functionality

**Estimated Effort per Feature:**
- sops-nix secret: 15-30 min (pattern selection + configuration)
- flake.inputs package: 30 min (flake.nix + package override)
- flake.inputs module: 45 min (flake.nix + module import + configuration)
- custom package: 2-3 hours (package.nix + build validation + Section 13.1)

**Risk Assessment:** LOW (all patterns validated in Epic 1 Phase 0)
```

**Documentation Quality Target:**

Match Story 1.10D/1.10DB Section 13 baseline:
- ✅ Empirical examples (real code from implementation)
- ✅ Build validation commands with actual outputs
- ✅ Comprehensive tutorial (Epic 2-6 developers can execute)
- ✅ Production-ready guidance (9.5/10 clarity)
- ✅ Pattern coverage (all 7 enablement patterns documented)

---

## Acceptance Criteria

### AC-A: Document Story 1.10C SSH Signing Implementation (COMPLETED)

**Target:** Document git and jujutsu SSH signing feature enablement using sops-nix direct path pattern

**Implementation Evidence (Story 1.10C):**

**Git SSH signing (git.nix:24-28, commit f9e9e92):**
```nix
programs.git.signing = lib.mkDefault {
  key = config.sops.secrets.ssh-signing-key.path;
  format = "ssh";
  signByDefault = true;
};
```

**Jujutsu SSH signing (jujutsu.nix:41, commit 04c1617):**
```nix
user.signing-key = lib.mkDefault config.sops.secrets.ssh-signing-key.path;
```

**Validation Commands:**
```bash
# Verify signing key configured
nix eval .#homeConfigurations.crs58.config.programs.git.signing.key
# Expected: /run/user/1000/secrets/ssh-signing-key

nix eval .#homeConfigurations.crs58.config.programs.jujutsu.settings.user.signing-key
# Expected: /run/user/1000/secrets/ssh-signing-key

# Build homeConfiguration
nix build .#homeConfigurations.crs58.activationPackage
# Expected: build succeeds
```

**Documentation Scope (AC H):**

Include in Section 13.1 Pattern 1 (Direct Path Access):
- Pattern overview (programs reading secret files directly)
- Code examples (git.nix, jujutsu.nix implementations)
- Validation commands and expected outputs
- Use cases (SSH signing, GPG keys, certificates)

**Pass Criteria:**
- ✅ Feature already enabled in Story 1.10C
- ✅ Build validation passed (Story 1.10C comprehensive review)
- ✅ Signing key accessible via sops.secrets module
- ✅ Section 13.1 Pattern 1 documented with empirical evidence

**Estimated effort:** 10 min (documentation only, feature already validated)

---

### AC-B: Document Story 1.10C MCP Server Implementation (COMPLETED)

**Target:** Document MCP server API key enablement using sops-nix templates + placeholders pattern

**Implementation Evidence (Story 1.10C):**

**Firecrawl API key (mcp-servers.nix:34-52, commit c63b61e):**
```nix
sops.templates.mcp-firecrawl = {
  content = builtins.toJSON {
    mcpServers.firecrawl = {
      command = "uvx";
      args = ["mcp-server-firecrawl"];
      env.FIRECRAWL_API_KEY = config.sops.placeholder."firecrawl-api-key";
    };
  };
  path = "${config.xdg.configHome}/claude/claude_desktop_config.json";
};
```

**HuggingFace token (mcp-servers.nix:56-73, commit c63b61e):**
```nix
sops.templates.mcp-huggingface = {
  content = builtins.toJSON {
    mcpServers.huggingface = {
      command = "uvx";
      args = [
        "--from"
        "git+https://github.com/huggingface/mcp-server-huggingface"
        "mcp-server-huggingface"
        "--header"
        "Authorization: Bearer ${config.sops.placeholder."huggingface-token"}"
      ];
    };
  };
};
```

**Validation Commands:**
```bash
# Verify firecrawl API key configured
nix eval .#homeConfigurations.crs58.config.sops.templates.mcp-firecrawl.content
# Expected: JSON with FIRECRAWL_API_KEY placeholder

# Verify huggingface token configured
nix eval .#homeConfigurations.crs58.config.sops.templates.mcp-huggingface.content
# Expected: JSON with Authorization Bearer placeholder

# Build homeConfiguration
nix build .#homeConfigurations.crs58.activationPackage
# Expected: build succeeds
```

**Documentation Scope (AC H):**

Include in Section 13.1 Pattern 2 (sops.templates with Placeholders):
- Pattern overview (structured config files with embedded secrets)
- Code examples (firecrawl, huggingface implementations)
- Validation commands and expected outputs
- Use cases (MCP servers, application configs, API keys in JSON/TOML/YAML)

**Pass Criteria:**
- ✅ Features already enabled in Story 1.10C
- ✅ Build validation passed (Story 1.10C comprehensive review)
- ✅ Templates generate correctly with placeholders
- ✅ Section 13.1 Pattern 2 documented with empirical evidence

**Estimated effort:** 10 min (documentation only, features already validated)

---

### AC-C: Document Story 1.10C GLM Wrapper Implementation (COMPLETED)

**Target:** Document GLM wrapper enablement using sops-nix runtime cat pattern

**Implementation Evidence (Story 1.10C):**

**GLM wrapper (wrappers.nix:23-44, commit f6b01e3):**
```nix
home.packages = [
  (pkgs.writeShellApplication {
    name = "claude-glm";
    runtimeInputs = [ pkgs.coreutils ];
    text = ''
      # Read secret at runtime and export as environment variable
      GLM_API_KEY="$(cat ${config.sops.secrets.glm-api-key.path})"
      export ANTHROPIC_AUTH_TOKEN="$GLM_API_KEY"

      # Execute claude with all arguments
      exec claude "$@"
    '';
  })
];
```

**Validation Commands:**
```bash
# Verify GLM wrapper package exists
nix eval .#homeConfigurations.crs58.config.home.packages
# Expected: includes claude-glm shell application

# Build homeConfiguration
nix build .#homeConfigurations.crs58.activationPackage
# Expected: build succeeds

# Runtime validation (manual)
# Activate homeConfiguration, run: claude-glm --version
# Expected: claude CLI executes with GLM API key set
```

**Documentation Scope (AC H):**

Include in Section 13.1 Pattern 3 (Runtime Cat in Shell Scripts):
- Pattern overview (shell wrappers with environment variables from secrets)
- Code example (GLM wrapper implementation)
- Validation commands (build + runtime)
- Use cases (API key wrappers, proxy authentication, credential injection)

**Pass Criteria:**
- ✅ Feature already enabled in Story 1.10C
- ✅ Build validation passed (Story 1.10C comprehensive review)
- ✅ Runtime secret access verified (production-ready pattern)
- ✅ Section 13.1 Pattern 3 documented with empirical evidence

**Estimated effort:** 10 min (documentation only, feature already validated)

---

### AC-D: Enable claude-code Package Override

**Target:** Enable claude-code package from nix-ai-tools flake input (Pattern 5: flake.inputs package override)

**Implementation:**

1. **Add nix-ai-tools flake input to flake.nix:**
   ```nix
   # test-clan/flake.nix inputs section
   inputs.nix-ai-tools = {
     url = "github:cameronraysmith/nix-ai-tools";
     inputs.nixpkgs.follows = "nixpkgs";
   };
   ```

2. **Update flake.lock:**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nix flake lock
   ```

3. **Uncomment package override in default.nix:24:**
   ```nix
   # modules/home-manager/claude-code/default.nix line 24
   programs.claude-code.package =
     flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;
   ```

4. **Validate package override:**
   ```bash
   # Verify package evaluates
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.package
   # Expected: derivation from nix-ai-tools

   # Check package name
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.pname
   # Expected: "claude-code"

   # Build package
   nix build .#homeConfigurations.crs58.config.programs.claude-code.package
   # Expected: build succeeds

   # Verify version (optional)
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.version
   # Expected: version string from nix-ai-tools
   ```

5. **Build homeConfiguration:**
   ```bash
   nix build .#homeConfigurations.crs58.activationPackage
   # Expected: build succeeds with claude-code package from nix-ai-tools
   ```

6. **Document Pattern 5 in Section 13.2:**
   - Pattern overview (flake.inputs package override)
   - Code example (default.nix line 24)
   - flake.nix configuration (nix-ai-tools input)
   - Validation commands with outputs
   - Use cases (package overrides, external package sources)

**Pass Criteria:**
- ✅ nix-ai-tools flake input added to flake.nix
- ✅ flake.lock updated with nix-ai-tools dependency
- ✅ Package override uncommented in default.nix:24
- ✅ Package evaluation succeeds (derivation from nix-ai-tools)
- ✅ Package build succeeds
- ✅ homeConfiguration build succeeds
- ✅ Section 13.2 Pattern 5 documented with empirical evidence

**Estimated effort:** 30 min

---

### AC-E: Enable catppuccin tmux Theme

**Target:** Enable catppuccin tmux theme from catppuccin-nix flake input (Pattern 6: flake.inputs module import)

**Implementation:**

1. **Add catppuccin-nix flake input to flake.nix:**
   ```nix
   # test-clan/flake.nix inputs section
   inputs.catppuccin-nix = {
     url = "github:catppuccin/nix";
   };
   ```

2. **Update flake.lock:**
   ```bash
   cd ~/projects/nix-workspace/test-clan
   nix flake lock
   ```

3. **Replace TODO in tmux.nix:40 with module import and configuration:**
   ```nix
   # modules/home-manager/tmux.nix
   { flake, ... }:
   {
     imports = [ flake.inputs.catppuccin-nix.homeManagerModules.catppuccin ];

     programs.tmux = {
       enable = true;

       catppuccin = {
         enable = true;
         flavor = "mocha";
         extraConfig = ''
           # Status bar configuration (catppuccin theme customization)
           set -g @catppuccin_window_left_separator ""
           set -g @catppuccin_window_right_separator " "
           set -g @catppuccin_window_middle_separator " █"
           set -g @catppuccin_window_number_position "right"

           set -g @catppuccin_window_default_fill "number"
           set -g @catppuccin_window_default_text "#W"

           set -g @catppuccin_window_current_fill "number"
           set -g @catppuccin_window_current_text "#W"

           set -g @catppuccin_status_modules_right "directory user host session"
           set -g @catppuccin_status_left_separator  " "
           set -g @catppuccin_status_right_separator ""
           set -g @catppuccin_status_right_separator_inverse "no"
           set -g @catppuccin_status_fill "icon"
           set -g @catppuccin_status_connect_separator "no"

           set -g @catppuccin_directory_text "#{pane_current_path}"
         '';
       };

       # ... rest of tmux configuration
     };
   }
   ```

4. **Validate theme configuration:**
   ```bash
   # Verify catppuccin module imported
   nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable
   # Expected: true

   # Verify flavor configured
   nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.flavor
   # Expected: "mocha"

   # Check tmux.conf generation
   nix eval .#homeConfigurations.crs58.config.programs.tmux.extraConfig
   # Expected: catppuccin config present

   # Build homeConfiguration
   nix build .#homeConfigurations.crs58.activationPackage
   # Expected: build succeeds
   ```

5. **Visual validation (manual, post-deployment):**
   - Activate homeConfiguration on test machine
   - Launch tmux session: `tmux new-session`
   - Verify catppuccin mocha theme renders:
     - Status bar colors: blue/pink/purple/green (catppuccin palette)
     - Window separators: custom separators from config
     - Status modules: directory, user, host, session (right side)
   - Verify status bar layout matches configuration

6. **Document Pattern 6 in Section 13.2:**
   - Pattern overview (flake.inputs module import)
   - Code example (tmux.nix module import + configuration)
   - flake.nix configuration (catppuccin-nix input)
   - Validation commands with outputs
   - Visual validation checklist
   - Use cases (theme modules, plugin modules, external module sets)

**Pass Criteria:**
- ✅ catppuccin-nix flake input added to flake.nix
- ✅ flake.lock updated with catppuccin-nix dependency
- ✅ Module import added to tmux.nix
- ✅ catppuccin configuration complete (flavor + extraConfig)
- ✅ Theme evaluation succeeds (enable=true, flavor="mocha")
- ✅ homeConfiguration build succeeds
- ✅ Visual validation checklist documented (for post-deployment testing)
- ✅ Section 13.2 Pattern 6 documented with empirical evidence

**Estimated effort:** 45 min

---

### AC-F: Enable ccstatusline Feature

**Target:** Enable ccstatusline status line feature using custom package from Story 1.10D (Pattern 7: custom package integration)

**Implementation:**

1. **Uncomment statusLine config in default.nix:**
   ```nix
   # modules/home-manager/claude-code/default.nix
   programs.claude-code.settings.statusLine = {
     type = "command";
     command = "${pkgs.ccstatusline}/bin/ccstatusline";
     padding = 0;
   };
   ```

2. **Validate package reference:**
   ```bash
   # Verify ccstatusline package accessible
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command
   # Expected: /nix/store/...-ccstatusline-.../bin/ccstatusline

   # Build ccstatusline package
   nix build .#ccstatusline
   # Expected: build succeeds (Story 1.10D validation)

   # Check ccstatusline version
   nix eval .#ccstatusline.version
   # Expected: version from pkgs/by-name/ccstatusline/package.nix
   ```

3. **Validate settings integration:**
   ```bash
   # Verify ccstatusline-settings.nix configuration
   nix eval .#homeConfigurations.crs58.config.programs.ccstatusline-settings.segments
   # Expected: array with 3 segments (git, shell, directory)

   # Check powerline style
   nix eval .#homeConfigurations.crs58.config.programs.ccstatusline-settings.powerline_style
   # Expected: true

   # Verify settings file generation
   nix eval .#homeConfigurations.crs58.config.xdg.configHome
   # Expected: path includes ccstatusline/config.toml
   ```

4. **Build homeConfiguration:**
   ```bash
   nix build .#homeConfigurations.crs58.activationPackage
   # Expected: build succeeds with ccstatusline feature enabled
   ```

5. **Runtime validation (manual, post-deployment):**
   - Activate homeConfiguration on test machine
   - Launch Claude Code CLI
   - Verify status line displays at top:
     - 3-line powerline format
     - Git branch indicator (first segment)
     - Shell name (second segment)
     - Current directory (third segment)
   - Verify styling matches ccstatusline-settings.nix configuration

6. **Regression prevention:**
   ```bash
   # Verify Story 1.10D checks still pass
   nix build .#checks.aarch64-darwin.home-module-exports
   # Expected: build succeeds

   nix build .#checks.aarch64-darwin.home-configurations-exposed
   # Expected: build succeeds
   ```

7. **Document Pattern 7 in Section 13.3:**
   - Pattern overview (custom package integration via pkgs-by-name)
   - Code example (default.nix statusLine config)
   - Package reference (Story 1.10D ccstatusline package)
   - Settings integration (ccstatusline-settings.nix)
   - Validation commands with outputs
   - Runtime validation checklist
   - Cross-reference Section 13.1 (Story 1.10D pkgs-by-name tutorial)

**Pass Criteria:**
- ✅ statusLine config uncommented in default.nix
- ✅ Package reference evaluation succeeds
- ✅ ccstatusline package builds (Story 1.10D regression test)
- ✅ Settings configuration accessible
- ✅ homeConfiguration build succeeds
- ✅ Runtime validation checklist documented
- ✅ Story 1.10D checks still pass (zero regression)
- ✅ Section 13.3 Pattern 7 documented with empirical evidence

**Estimated effort:** 15 min

---

### AC-G: Build Validation

**Target:** Validate all 4 configurations build successfully with new features enabled (zero regressions)

**Implementation:**

1. **Build all configurations:**
   ```bash
   cd ~/projects/nix-workspace/test-clan

   # homeConfiguration: crs58 (primary test user)
   nix build .#homeConfigurations.crs58.activationPackage
   # Expected: build succeeds

   # homeConfiguration: raquel (secondary test user)
   nix build .#homeConfigurations.raquel.activationPackage
   # Expected: build succeeds

   # darwinConfiguration: blackphos (nix-darwin laptop)
   nix build .#darwinConfigurations.blackphos.system
   # Expected: build succeeds

   # nixosConfiguration: cinnabar (nixos VPS)
   nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel
   # Expected: build succeeds
   ```

2. **Validate new features (AC D-F):**
   ```bash
   # Feature 1: claude-code package override (AC D)
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.pname
   # Expected: "claude-code" from nix-ai-tools

   nix build .#homeConfigurations.crs58.config.programs.claude-code.package
   # Expected: build succeeds

   # Feature 2: catppuccin tmux theme (AC E)
   nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable
   # Expected: true

   nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.flavor
   # Expected: "mocha"

   # Feature 3: ccstatusline feature (AC F)
   nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command
   # Expected: /nix/store/...-ccstatusline-.../bin/ccstatusline

   nix build .#ccstatusline
   # Expected: build succeeds
   ```

3. **Regression testing (Story 1.10C/1.10D/1.10DB):**
   ```bash
   # Story 1.10C: sops-nix secrets
   nix eval .#homeConfigurations.crs58.config.sops.secrets.ssh-signing-key.sopsFile
   # Expected: path to secrets.yaml

   nix eval .#homeConfigurations.crs58.config.programs.git.signing.key
   # Expected: /run/user/1000/secrets/ssh-signing-key

   # Story 1.10D: pkgs-by-name custom packages
   nix build .#checks.aarch64-darwin.home-module-exports
   # Expected: build succeeds

   nix build .#checks.aarch64-darwin.home-configurations-exposed
   # Expected: build succeeds

   # Story 1.10DB: overlay architecture
   nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
   # Expected: stable version (Layer 1 multi-channel)

   nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version
   # Expected: stable version (Layer 2 hotfix)
   ```

4. **Performance validation:**
   - Build times: All builds complete in reasonable time (< 10 min each)
   - Evaluation performance: No significant slowdown from flake.inputs additions
   - Disk usage: New features don't cause excessive store growth

5. **Document validation evidence:**
   - Record build outputs (success/failure, timing)
   - Capture feature inspection outputs
   - Document regression test results
   - Include validation evidence in Section 13.5 (Build Validation)

**Pass Criteria:**
- ✅ All 4 builds succeed (crs58, raquel, blackphos, cinnabar)
- ✅ All 4 builds complete in reasonable time (< 10 min each)
- ✅ No new build failures introduced
- ✅ All new features validate successfully (AC D-F)
- ✅ All Story 1.10C validations pass (sops-nix working)
- ✅ All Story 1.10D validations pass (pkgs-by-name working)
- ✅ All Story 1.10DB validations pass (overlay layers working)
- ✅ Zero regressions from prior stories
- ✅ Build validation documented in Section 13.5 with evidence

**Estimated effort:** 30 min

---

### AC-H: Document Feature Enablement Patterns in Section 13

**Target:** Create comprehensive Section 13 in test-clan-validated-architecture.md documenting all 7 feature enablement patterns

**Implementation:**

1. **Create Section 13 structure in test-clan-validated-architecture.md:**
   ```markdown
   ## 13. Feature Enablement Patterns

   ### 13.1 sops-nix Secret Access Patterns
   ### 13.2 flake.inputs Integration Patterns
   ### 13.3 Custom Package Integration
   ### 13.4 Enabled Features Summary
   ### 13.5 Build Validation
   ### 13.6 Epic 2-6 Migration Guide
   ```

2. **Document Section 13.1 - sops-nix Secret Access Patterns:**

   **Pattern 1: Direct Path Access (AC A implementation)**
   - Use case description
   - Code example from git.nix (lines 24-28)
   - Code example from jujutsu.nix (line 41)
   - Validation commands with outputs
   - Advantages/limitations
   - When to use this pattern

   **Pattern 2: sops.templates with Placeholders (AC B implementation)**
   - Use case description
   - Code example from mcp-servers.nix (firecrawl, huggingface)
   - Code example from wrappers.nix (rbw config)
   - Code example from git.nix (allowed_signers)
   - Validation commands with outputs
   - Advantages/limitations
   - When to use this pattern

   **Pattern 3: Runtime Cat in Shell Scripts (AC C implementation)**
   - Use case description
   - Code example from wrappers.nix (GLM wrapper, lines 23-44)
   - Validation commands with outputs
   - Advantages/limitations
   - When to use this pattern

   **Pattern 4: Activation Scripts**
   - Use case description
   - Code example from atuin.nix (lines 38-45)
   - Validation commands with outputs
   - Advantages/limitations
   - When to use this pattern

3. **Document Section 13.2 - flake.inputs Integration Patterns:**

   **Pattern 5: Package Override (AC D implementation)**
   - Use case description
   - Code example from default.nix (claude-code package override)
   - flake.nix configuration (nix-ai-tools input)
   - Validation commands with outputs
   - Advantages/limitations
   - When to use this pattern

   **Pattern 6: Module Import (AC E implementation)**
   - Use case description
   - Code example from tmux.nix (catppuccin module import + config)
   - flake.nix configuration (catppuccin-nix input)
   - Validation commands with outputs
   - Visual validation checklist
   - Advantages/limitations
   - When to use this pattern

4. **Document Section 13.3 - Custom Package Integration:**

   **Pattern 7: pkgs-by-name Custom Packages (AC F implementation)**
   - Use case description
   - Code example from default.nix (ccstatusline statusLine config)
   - Package reference (Story 1.10D ccstatusline package)
   - Settings integration (ccstatusline-settings.nix)
   - Validation commands with outputs
   - Runtime validation checklist
   - Cross-reference to Section 13.1 (Story 1.10D pkgs-by-name tutorial)

5. **Document Section 13.4 - Enabled Features Summary:**
   - Complete feature list (11 features)
   - Pattern mapping (which pattern used for each feature)
   - Story coverage (which story enabled which features)
   - Implementation timeline (Story 1.10C → 1.10D → 1.10E)

6. **Document Section 13.5 - Build Validation:**
   - All 4 configurations build commands
   - Feature inspection commands (AC D-F validations)
   - Regression test commands (Story 1.10C/1.10D/1.10DB)
   - Expected outputs for all commands
   - Performance notes (build times, evaluation speed)

7. **Document Section 13.6 - Epic 2-6 Migration Guide:**
   - Feature enablement checklist (8 steps)
   - Pattern selection decision tree
   - Estimated effort per pattern
   - Risk assessment (all patterns validated in Epic 1)
   - Troubleshooting guide (common issues + solutions)

8. **Ensure Section 13 matches Story 1.10D/1.10DB quality baseline:**
   - Empirical examples (real code from implementation)
   - Build validation commands with actual outputs
   - Comprehensive tutorial (Epic 2-6 developers can execute)
   - Production-ready guidance (9.5/10 clarity)
   - Pattern coverage (all 7 enablement patterns documented)

9. **Cross-reference with other sections:**
   - Reference Section 13.1 (Story 1.10D pkgs-by-name tutorial)
   - Reference Story 1.10C implementation commits
   - Reference infra source files for pattern origins

**Pass Criteria:**
- ✅ Section 13 exists in test-clan-validated-architecture.md
- ✅ All 7 patterns documented with real code examples
- ✅ All 4 sops-nix patterns (direct path, templates, runtime cat, activation)
- ✅ Both flake.inputs patterns (package override, module import)
- ✅ Custom package pattern (pkgs-by-name integration)
- ✅ Build validation commands and outputs included
- ✅ Complete feature summary (11 features, pattern mapping)
- ✅ Epic 2-6 migration guide actionable
- ✅ Quality matches Story 1.10D/1.10DB baseline (9.5/10 clarity)
- ✅ Comprehensive tutorial (self-contained, production-ready)

**Estimated effort:** 30 min

---

**Total Acceptance Criteria Effort:** 2 hours
- AC-A: 10 min (documentation only, Story 1.10C complete)
- AC-B: 10 min (documentation only, Story 1.10C complete)
- AC-C: 10 min (documentation only, Story 1.10C complete)
- AC-D: 30 min (flake.inputs configuration + validation)
- AC-E: 45 min (flake.inputs + module config + validation)
- AC-F: 15 min (uncomment + validation)
- AC-G: 30 min (build matrix + regression testing)
- AC-H: 30 min (Section 13 comprehensive documentation)

**Sum:** 3h 0min (aligns with story estimate of 1.5-2 hours with 1h buffer for documentation comprehensiveness)

---

## Tasks / Subtasks

### Task Group 1: Document Story 1.10C Implementations (AC-A, AC-B, AC-C)

**Objective:** Document already-enabled features from Story 1.10C for Epic 2-6 reference

**Estimated Time:** 30 minutes

**Subtasks:**

- [ ] 1.1: Review Story 1.10C SSH signing implementation (AC-A)
  - Read git.nix lines 24-28 (SSH signing config)
  - Read jujutsu.nix line 41 (SSH signing key)
  - Validate signing key configured: `nix eval .#homeConfigurations.crs58.config.programs.git.signing.key`
  - Document Pattern 1 (Direct Path Access) notes for Section 13.1

- [ ] 1.2: Review Story 1.10C MCP server implementation (AC-B)
  - Read mcp-servers.nix lines 34-52 (firecrawl template)
  - Read mcp-servers.nix lines 56-73 (huggingface template)
  - Validate templates: `nix eval .#homeConfigurations.crs58.config.sops.templates.mcp-firecrawl.content`
  - Document Pattern 2 (sops.templates) notes for Section 13.1

- [ ] 1.3: Review Story 1.10C GLM wrapper implementation (AC-C)
  - Read wrappers.nix lines 23-44 (GLM wrapper shell script)
  - Validate wrapper package: `nix eval .#homeConfigurations.crs58.config.home.packages`
  - Document Pattern 3 (Runtime Cat) notes for Section 13.1

- [ ] 1.4: Review Story 1.10C bonus features (Additional Documentation)
  - Read atuin.nix lines 38-45 (activation script pattern)
  - Read wrappers.nix lines 54-85 (rbw config template)
  - Read git.nix lines 36-49 (allowed_signers template)
  - Document Pattern 4 (Activation Scripts) notes for Section 13.1

**Acceptance Criteria Covered:** AC-A (Git/Jujutsu SSH signing), AC-B (MCP servers), AC-C (GLM wrapper)

---

### Task Group 2: Enable Remaining Features (AC-D, AC-E, AC-F)

**Objective:** Enable 3 remaining features using flake.inputs and custom packages

**Estimated Time:** 90 minutes

**Subtasks:**

- [ ] 2.1: Add nix-ai-tools flake input (AC-D.1)
  - Edit `test-clan/flake.nix`
  - Add to inputs section:
    ```nix
    inputs.nix-ai-tools = {
      url = "github:cameronraysmith/nix-ai-tools";
      inputs.nixpkgs.follows = "nixpkgs";
    };
    ```
  - Execute: `nix flake lock` to update flake.lock
  - Verify input available: `nix flake metadata`

- [ ] 2.2: Enable claude-code package override (AC-D.2)
  - Edit `modules/home-manager/claude-code/default.nix`
  - Uncomment line 24:
    ```nix
    programs.claude-code.package =
      flake.inputs.nix-ai-tools.packages.${pkgs.system}.claude-code;
    ```
  - Validate package: `nix eval .#homeConfigurations.crs58.config.programs.claude-code.package`
  - Build package: `nix build .#homeConfigurations.crs58.config.programs.claude-code.package`
  - Document Pattern 5 notes for Section 13.2

- [ ] 2.3: Add catppuccin-nix flake input (AC-E.1)
  - Edit `test-clan/flake.nix`
  - Add to inputs section:
    ```nix
    inputs.catppuccin-nix = {
      url = "github:catppuccin/nix";
    };
    ```
  - Execute: `nix flake lock` to update flake.lock
  - Verify input available: `nix flake metadata`

- [ ] 2.4: Enable catppuccin tmux theme (AC-E.2)
  - Edit `modules/home-manager/tmux.nix`
  - Replace TODO at line 40 with:
    ```nix
    imports = [ flake.inputs.catppuccin-nix.homeManagerModules.catppuccin ];

    programs.tmux.catppuccin = {
      enable = true;
      flavor = "mocha";
      extraConfig = ''
        # 15 lines of status bar configuration
        # (reference infra implementation for complete config)
      '';
    };
    ```
  - Validate theme: `nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable`
  - Verify flavor: `nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.flavor`
  - Document Pattern 6 notes for Section 13.2

- [ ] 2.5: Enable ccstatusline feature (AC-F)
  - Edit `modules/home-manager/claude-code/default.nix`
  - Uncomment statusLine config:
    ```nix
    programs.claude-code.settings.statusLine = {
      type = "command";
      command = "${pkgs.ccstatusline}/bin/ccstatusline";
      padding = 0;
    };
    ```
  - Validate package reference: `nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command`
  - Verify ccstatusline builds: `nix build .#ccstatusline`
  - Document Pattern 7 notes for Section 13.3

**Acceptance Criteria Covered:** AC-D (claude-code package), AC-E (catppuccin theme), AC-F (ccstatusline feature)

---

### Task Group 3: Validate and Document (AC-G, AC-H)

**Objective:** Validate all builds and create comprehensive Section 13 documentation

**Estimated Time:** 60 minutes

**Subtasks:**

- [ ] 3.1: Build all configurations (AC-G.1)
  - Execute: `nix build .#homeConfigurations.crs58.activationPackage`
  - Execute: `nix build .#homeConfigurations.raquel.activationPackage`
  - Execute: `nix build .#darwinConfigurations.blackphos.system`
  - Execute: `nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel`
  - Verify all 4 builds succeed (no evaluation errors)
  - Record build times for documentation

- [ ] 3.2: Validate new features (AC-G.2)
  - **claude-code package (AC-D):**
    - `nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.pname` → "claude-code"
    - `nix build .#homeConfigurations.crs58.config.programs.claude-code.package` → succeeds
  - **catppuccin theme (AC-E):**
    - `nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable` → true
    - `nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.flavor` → "mocha"
  - **ccstatusline feature (AC-F):**
    - `nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command` → /nix/store/.../ccstatusline
    - `nix build .#ccstatusline` → succeeds
  - Document all validation outputs in Dev Notes

- [ ] 3.3: Regression testing (AC-G.3)
  - **Story 1.10C regressions:**
    - `nix eval .#homeConfigurations.crs58.config.sops.secrets.ssh-signing-key.sopsFile` → secrets.yaml path
    - `nix eval .#homeConfigurations.crs58.config.programs.git.signing.key` → sops secret path
  - **Story 1.10D regressions:**
    - `nix build .#checks.aarch64-darwin.home-module-exports` → succeeds
    - `nix build .#checks.aarch64-darwin.home-configurations-exposed` → succeeds
  - **Story 1.10DB regressions:**
    - `nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version` → stable version
    - `nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version` → stable version
  - Verify zero regressions (all prior validations pass)

- [ ] 3.4: Create Section 13 structure (AC-H.1)
  - Open `test-clan/docs/architecture/test-clan-validated-architecture.md`
  - Create section: "## 13. Feature Enablement Patterns"
  - Create subsections: 13.1-13.6 (structure from AC-H implementation notes)

- [ ] 3.5: Document Section 13.1 - sops-nix patterns (AC-H.2)
  - **Pattern 1 (Direct Path):** Use AC-A notes, git.nix/jujutsu.nix examples
  - **Pattern 2 (sops.templates):** Use AC-B notes, mcp-servers.nix examples
  - **Pattern 3 (Runtime Cat):** Use AC-C notes, wrappers.nix GLM example
  - **Pattern 4 (Activation Scripts):** Use Task 1.4 notes, atuin.nix example
  - Include validation commands and outputs for each pattern

- [ ] 3.6: Document Section 13.2 - flake.inputs patterns (AC-H.3)
  - **Pattern 5 (Package Override):** Use Task 2.2 notes, default.nix claude-code example
  - **Pattern 6 (Module Import):** Use Task 2.4 notes, tmux.nix catppuccin example
  - Include flake.nix input configurations
  - Include validation commands and outputs

- [ ] 3.7: Document Section 13.3 - custom packages (AC-H.4)
  - **Pattern 7 (pkgs-by-name):** Use Task 2.5 notes, default.nix ccstatusline example
  - Cross-reference Story 1.10D Section 13.1 (pkgs-by-name tutorial)
  - Include ccstatusline-settings.nix integration details
  - Include validation and runtime testing checklists

- [ ] 3.8: Document Section 13.4 - features summary (AC-H.5)
  - List all 11 features with pattern mapping
  - Document Story 1.10C features (1-8)
  - Document Story 1.10E features (9-11)
  - Include implementation timeline

- [ ] 3.9: Document Section 13.5 - build validation (AC-H.6)
  - Include all build commands from Task 3.1
  - Include feature validation commands from Task 3.2
  - Include regression test commands from Task 3.3
  - Document expected outputs for all commands
  - Include performance notes (build times from Task 3.1)

- [ ] 3.10: Document Section 13.6 - Epic 2-6 migration guide (AC-H.7)
  - Feature enablement checklist (8 steps)
  - Pattern selection decision tree
  - Effort estimates per pattern
  - Risk assessment (LOW - all patterns validated)
  - Troubleshooting guide

- [ ] 3.11: Verify Section 13 quality (AC-H.8)
  - Empirical examples (real code, not hypothetical)
  - Build validation commands with actual outputs
  - Comprehensive tutorial (Epic 2-6 developers can execute)
  - Production-ready documentation (9.5/10 clarity target)
  - Pattern coverage (all 7 patterns documented)

**Acceptance Criteria Covered:** AC-G (build validation), AC-H (Section 13 documentation)

---

**Total Task Group Effort:** 3 hours (180 min)

---

## Dev Notes

### Architectural Context

**Story 1.10E Position in Epic 1 Arc:**

Epic 1 validates dendritic flake-parts + clan-core integration through comprehensive architectural validation:

**Phase 1: Infrastructure Validation (Stories 1.1-1.9)**
- Pattern A structure (dendritic flake-parts organization)
- Clan-core integration (machines, secrets, networking)
- Build validation (all configurations build)

**Phase 2: Feature Infrastructure (Stories 1.10A-1.10DB)**
- Story 1.10C: sops-nix secrets infrastructure + 9/11 features enabled
- Story 1.10D: pkgs-by-name custom package pattern (Layer 3)
- Story 1.10DB: Overlay architecture migration (Layers 1,2,4,5)

**Phase 3: Feature Completion (Story 1.10E) ← CURRENT**
- Enable remaining 3 features using validated infrastructure
- Prove all patterns work together (sops-nix + flake.inputs + custom packages)
- Document complete feature enablement guide (Section 13)

**Phase 4: Deployment & Wrap-Up (Stories 1.11-1.14)**
- Story 1.11: home-manager refinement
- Story 1.12: GO/NO-GO decision
- Story 1.13: Physical deployment
- Story 1.14: Testing & validation

**Story 1.10E completes architectural validation** by proving all feature enablement patterns work:
1. ✅ 4 sops-nix secret access patterns (Story 1.10C validated)
2. ✅ 1 custom package pattern (Story 1.10D validated)
3. ✅ 5-layer overlay architecture (Story 1.10DB validated)
4. ➡️ 2 flake.inputs patterns (Story 1.10E validates)

**Epic 1 Coverage After Story 1.10E:**
- Architecture validation: 95% (Story 1.10DB complete)
- Feature enablement: 100% (all 11 features enabled)
- Pattern validation: 100% (all 7 patterns documented)
- Epic 1 total: ~98% complete

### Feature Enablement Patterns Reference

**Pattern Matrix:**

| Pattern | Type | Use Case | Story | Example Feature |
|---------|------|----------|-------|-----------------|
| 1 | sops-nix direct path | File-based secrets | 1.10C | Git SSH signing |
| 2 | sops-nix templates | Structured configs | 1.10C | MCP servers |
| 3 | sops-nix runtime cat | Shell env vars | 1.10C | GLM wrapper |
| 4 | sops-nix activation | Non-XDG deployment | 1.10C | Atuin key |
| 5 | flake.inputs package | External packages | 1.10E | claude-code |
| 6 | flake.inputs module | External modules | 1.10E | catppuccin |
| 7 | pkgs-by-name | Custom packages | 1.10E | ccstatusline |

**Pattern Selection Decision Tree:**

```
Need to enable a feature?
│
├─ Requires secrets?
│  ├─ Yes → sops-nix patterns (1-4)
│  │  ├─ Program reads file directly? → Pattern 1 (direct path)
│  │  ├─ Need structured config (JSON/TOML)? → Pattern 2 (templates)
│  │  ├─ Need environment variable? → Pattern 3 (runtime cat)
│  │  └─ Need non-XDG location? → Pattern 4 (activation script)
│  │
│  └─ No → Continue to package/module selection
│
├─ Package from external flake?
│  └─ Yes → Pattern 5 (flake.inputs package override)
│
├─ Module from external flake?
│  └─ Yes → Pattern 6 (flake.inputs module import)
│
└─ Custom package needed?
   └─ Yes → Pattern 7 (pkgs-by-name)
```

**Pattern Combinations:**

Some features use multiple patterns:
- **claude-code:** Pattern 5 (package override) + Pattern 7 (ccstatusline custom package for status line)
- **MCP servers:** Pattern 2 (templates for config) + secrets (firecrawl API key, huggingface token)
- **GLM wrapper:** Pattern 3 (runtime cat) + Pattern 2 (template for rbw config)

### Story 1.10C Feature Review Summary

**Already-Enabled Features (9 features, 61 commits, 2025-11-15 to 2025-11-16):**

**Category A: SSH Signing (Pattern 1)**
1. Git SSH signing (git.nix:24-28, commit f9e9e92)
2. Jujutsu SSH signing (jujutsu.nix:41, commit 04c1617)

**Category B: MCP Servers (Pattern 2)**
3. Firecrawl API key (mcp-servers.nix:34-52, commit c63b61e)
4. HuggingFace token (mcp-servers.nix:56-73, commit c63b61e)

**Category C: Shell Wrappers (Pattern 3)**
5. GLM wrapper (wrappers.nix:23-44, commit f6b01e3)

**Category D: Bonus Features (Patterns 2, 4)**
6. Atuin encryption key (atuin.nix:38-45, activation script)
7. Bitwarden (rbw) email (wrappers.nix:54-85, template)
8. Git allowed_signers (git.nix:36-49, template)

**Context7 MCP Server:**
9. ⚠️ NOT in test-clan scope (implementation documents "Only 2 MCP servers")

**Story 1.10C Validation Evidence:**
- Comprehensive review report (2025-11-16)
- Build validation: 4/4 configurations PASS
- All features functional in production
- Zero evaluation errors or build failures

**Story 1.10E Task:** Document these implementations for Epic 2-6 reference (AC A-C, ~30 min)

### Testing Standards

**Quality Gate 1: Feature Enablement (Task Group 2)**

**Objective:** Verify all 3 remaining features enabled correctly

**Validation Commands:**
```bash
# Feature 1: claude-code package (AC-D)
nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.pname
# Expected: "claude-code" from nix-ai-tools

nix build .#homeConfigurations.crs58.config.programs.claude-code.package
# Expected: build succeeds

# Feature 2: catppuccin theme (AC-E)
nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable
# Expected: true

nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.flavor
# Expected: "mocha"

# Feature 3: ccstatusline (AC-F)
nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command
# Expected: /nix/store/...-ccstatusline-.../bin/ccstatusline

nix build .#ccstatusline
# Expected: build succeeds
```

**Pass Criteria:**
- ✅ nix-ai-tools flake input configured
- ✅ claude-code package override evaluates and builds
- ✅ catppuccin-nix flake input configured
- ✅ catppuccin theme module imported and configured
- ✅ ccstatusline feature config uncommented
- ✅ All feature validations succeed

**Troubleshooting:**
- Package evaluation error: Check flake.nix input configuration, verify inputs.nixpkgs.follows
- Module import error: Verify homeManagerModules path, check flake.lock updated
- Package reference error: Verify pkgs.ccstatusline accessible (Story 1.10D regression)

---

**Quality Gate 2: Build Validation (Task Group 3.1-3.3)**

**Objective:** Verify all configurations build with zero regressions

**Validation Commands:**
```bash
# All 4 configurations build
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage
nix build .#darwinConfigurations.blackphos.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Story 1.10C regression prevention
nix eval .#homeConfigurations.crs58.config.sops.secrets.ssh-signing-key.sopsFile
nix eval .#homeConfigurations.crs58.config.programs.git.signing.key

# Story 1.10D regression prevention
nix build .#checks.aarch64-darwin.home-module-exports
nix build .#checks.aarch64-darwin.home-configurations-exposed

# Story 1.10DB regression prevention
nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
nix eval .#darwinConfigurations.blackphos.pkgs.micromamba.version
```

**Pass Criteria:**
- ✅ All 4 builds succeed
- ✅ All builds complete in reasonable time (< 10 min each)
- ✅ All Story 1.10C validations pass (sops-nix working)
- ✅ All Story 1.10D validations pass (pkgs-by-name working)
- ✅ All Story 1.10DB validations pass (overlay layers working)
- ✅ Zero new evaluation errors or build failures

**Troubleshooting:**
- Build failure: Check flake.lock (nix flake lock), verify all inputs configured
- sops-nix regression: Check secrets.yaml, verify age keys configured
- pkgs-by-name regression: Verify pkgsDirectory still configured in modules/flake-parts/nixpkgs.nix
- Overlay regression: Verify overlays array intact in modules/flake-parts/nixpkgs.nix

---

**Quality Gate 3: Documentation Review (Task Group 3.4-3.11)**

**Objective:** Verify Section 13 comprehensive and matches Story 1.10D/1.10DB quality baseline

**Validation Criteria:**
- ✅ Section 13 exists in test-clan-validated-architecture.md
- ✅ All 7 patterns documented with real code examples
- ✅ Build validation commands with actual outputs
- ✅ Comprehensive tutorial (Epic 2-6 developers can execute)
- ✅ Production-ready guidance (9.5/10 clarity)
- ✅ Pattern coverage (all enablement patterns documented)

**Content Verification:**
- Pattern overview: All 7 patterns explained with use cases
- Example completeness: Full code + validation commands + outputs
- Migration guide: Actionable checklist with effort estimates
- Tutorial quality: Comprehensive enough for independent execution
- Empirical evidence: Based on real implementation (not hypothetical)

**Pass Criteria:**
- ✅ Documentation comprehensive (self-contained tutorial)
- ✅ Code examples correct and tested (from actual implementation)
- ✅ Migration path clear and actionable (8-step checklist)
- ✅ Cross-references accurate (Section 13.1, Story 1.10C/1.10D)
- ✅ Quality matches Story 1.10D/1.10DB baseline (9.5/10 clarity)

---

### Project Structure Notes

**test-clan Repository Layout (Story 1.10E additions):**

```
test-clan/
├── flake.nix                                    # UPDATE: Add nix-ai-tools, catppuccin-nix inputs
├── flake.lock                                   # UPDATE: Lock new inputs
├── modules/
│   └── home-manager/
│       ├── claude-code/
│       │   └── default.nix                      # UPDATE: Uncomment claude-code package override, statusLine config
│       └── tmux.nix                             # UPDATE: Replace TODO with catppuccin module import + config
├── docs/
│   └── architecture/
│       └── test-clan-validated-architecture.md  # UPDATE: Add Section 13 (feature enablement patterns)
└── pkgs/
    └── by-name/
        └── ccstatusline/                        # EXISTING: Story 1.10D package
            └── package.nix
```

**File Change Summary:**

**Modified Files:**
- `flake.nix` (add nix-ai-tools, catppuccin-nix inputs)
- `flake.lock` (update with new dependencies)
- `modules/home-manager/claude-code/default.nix` (uncomment package override + statusLine config)
- `modules/home-manager/tmux.nix` (replace TODO with catppuccin module import + configuration)
- `docs/architecture/test-clan-validated-architecture.md` (add Section 13)

**No New Files Created:** All changes are configuration updates to existing files

**Integration Points:**

1. **flake.nix → modules/home-manager/default.nix:**
   - flake.nix provides inputs (nix-ai-tools, catppuccin-nix)
   - default.nix accesses inputs via flake parameter
   - Connection: flake.inputs.X.packages / flake.inputs.X.homeManagerModules

2. **nix-ai-tools input → claude-code package:**
   - Input provides claude-code package
   - default.nix overrides programs.claude-code.package
   - Connection: Pattern 5 (flake.inputs package override)

3. **catppuccin-nix input → tmux module:**
   - Input provides catppuccin homeManagerModule
   - tmux.nix imports module, configures theme
   - Connection: Pattern 6 (flake.inputs module import)

4. **ccstatusline package → claude-code status line:**
   - Package from Story 1.10D (pkgs-by-name)
   - default.nix references pkgs.ccstatusline
   - Connection: Pattern 7 (custom package integration)

5. **All patterns → Section 13 documentation:**
   - Section 13 documents all 7 patterns
   - Real code examples from implementations
   - Connection: Comprehensive tutorial for Epic 2-6

### Quick Reference

**Target Repository:**
```bash
~/projects/nix-workspace/test-clan/
```

**Key Commands:**

```bash
# Build all configurations
cd ~/projects/nix-workspace/test-clan
nix build .#homeConfigurations.crs58.activationPackage
nix build .#homeConfigurations.raquel.activationPackage
nix build .#darwinConfigurations.blackphos.system
nix build .#nixosConfigurations.cinnabar.config.system.build.toplevel

# Validate new features (AC D-F)
nix eval .#homeConfigurations.crs58.config.programs.claude-code.package.pname
nix eval .#homeConfigurations.crs58.config.programs.tmux.catppuccin.enable
nix eval .#homeConfigurations.crs58.config.programs.claude-code.settings.statusLine.command
nix build .#ccstatusline

# Regression testing (Story 1.10C/1.10D/1.10DB)
nix eval .#homeConfigurations.crs58.config.sops.secrets.ssh-signing-key.sopsFile
nix build .#checks.aarch64-darwin.home-module-exports
nix eval .#darwinConfigurations.blackphos.pkgs.stable.hello.version
```

**Files to Edit:**

```bash
# Flake inputs
~/projects/nix-workspace/test-clan/flake.nix

# Feature enablement
~/projects/nix-workspace/test-clan/modules/home-manager/claude-code/default.nix
~/projects/nix-workspace/test-clan/modules/home-manager/tmux.nix

# Documentation
~/projects/nix-workspace/test-clan/docs/architecture/test-clan-validated-architecture.md
```

**Reference Files (Story 1.10C implementations):**

```bash
# sops-nix pattern examples
~/projects/nix-workspace/test-clan/modules/home-manager/git.nix              # Pattern 1: direct path (SSH signing)
~/projects/nix-workspace/test-clan/modules/home-manager/jujutsu.nix          # Pattern 1: direct path (SSH signing)
~/projects/nix-workspace/test-clan/modules/home-manager/mcp-servers.nix      # Pattern 2: templates (API keys)
~/projects/nix-workspace/test-clan/modules/home-manager/wrappers.nix         # Pattern 3: runtime cat (GLM wrapper)
~/projects/nix-workspace/test-clan/modules/home-manager/atuin.nix            # Pattern 4: activation script (encryption key)

# Custom package reference (Story 1.10D)
~/projects/nix-workspace/test-clan/pkgs/by-name/ccstatusline/package.nix
~/projects/nix-workspace/test-clan/modules/home-manager/ccstatusline-settings.nix

# Documentation reference
~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10d-validate-custom-package-overlays.md  # Section 13.1 quality baseline
~/projects/nix-workspace/infra/docs/notes/development/work-items/1-10db-execute-overlay-architecture-migration.md  # Section 13.2 quality baseline
```

**External References:**

- **nix-ai-tools:** https://github.com/cameronraysmith/nix-ai-tools
  - claude-code package source
  - Package override pattern

- **catppuccin-nix:** https://github.com/catppuccin/nix
  - Home-manager module source
  - Theme configuration documentation

- **sops-nix:** https://github.com/Mic92/sops-nix
  - Secret management patterns
  - sops.templates documentation

**Estimated Effort:** 1.5-2 hours

**Risk Level:** Low
- 9/11 features already validated (Story 1.10C)
- Infrastructure complete (sops-nix, pkgs-by-name, overlays)
- Only flake.inputs configuration remaining
- Clear pattern examples from reference implementations

### Constraints

1. **Zero Regression Requirement:**
   - All Story 1.10C validations MUST still pass (sops-nix working)
   - All Story 1.10D validations MUST still pass (pkgs-by-name working)
   - All Story 1.10DB validations MUST still pass (overlay layers working)
   - Zero tolerance for breaking existing features

2. **Documentation Quality Baseline:**
   - Section 13 MUST match Story 1.10D/1.10DB quality (9.5/10 clarity)
   - All code examples MUST be from actual implementation (empirical)
   - All validation commands MUST include expected outputs
   - Tutorial MUST be comprehensive (Epic 2-6 developers can execute independently)

3. **Pattern Coverage Completeness:**
   - All 7 feature enablement patterns MUST be documented
   - Each pattern MUST have real code example
   - Each pattern MUST have validation commands
   - Each pattern MUST have use case description

4. **Feature Enablement Verification:**
   - Each enabled feature MUST build successfully
   - Each enabled feature MUST have validation commands
   - Each enabled feature MUST have runtime testing checklist (manual validation)
   - Build matrix MUST pass (all 4 configurations)

5. **Epic 1 Coverage Target:**
   - Story 1.10E completion achieves ~98% Epic 1 coverage
   - All feature enablement patterns empirically validated
   - Epic 2-6 teams receive complete enablement guide
   - Documentation comprehensive enough for independent migration

---

## Dev Agent Record

### Context Reference

- Context file: `docs/notes/development/work-items/1-10e-enable-remaining-features.context.xml` (will be generated via story-context workflow)

### Agent Model Used

<!-- Model name and version will be recorded during implementation -->

### Debug Log References

<!-- Commit hashes and links will be recorded during implementation -->

### Completion Notes List

<!-- Implementation notes, challenges, solutions will be recorded during implementation -->

### File List

<!-- Files created, modified, deleted will be recorded during implementation -->

---

## Learnings

<!-- Post-implementation insights, architectural discoveries, pattern validations -->
<!-- This section will be populated during implementation or Party Mode checkpoint -->

---

## Change Log

### 2025-11-16 - Story Created

- Story 1.10E work item created following Story 1.10D template structure
- Comprehensive story definition based on Epic 1 lines 1641-1838 (198 lines)
- Story scope: Enable remaining 3 features (claude-code, catppuccin, ccstatusline) using flake.inputs + custom packages
- Context: Story 1.10C enabled 9/11 features (sops-nix patterns), leaving only flake.inputs-dependent features for Story 1.10E
- 8 acceptance criteria (A-H) covering documentation (AC A-C), feature enablement (AC D-F), validation (AC G), and comprehensive Section 13 (AC H)
- 3 task groups with detailed subtasks mapped to ACs (30min + 90min + 60min = 3h)
- 3 quality gates with explicit validation commands (Feature Enablement, Build Validation, Documentation Review)
- Strategic value: Completes Pattern A + sops-nix + flake.inputs validation trilogy, provides Epic 2-6 teams with complete feature enablement guide (all 7 patterns)
- Work item structure: 10 sections following Story 1.10D/1.10DB template (9.5/10 clarity target)
- Documentation scope: Section 13 comprehensive tutorial (7 patterns, 11 features, Epic 2-6 migration guide)
- Implementation guidance: Detailed (exact enablement steps, validation commands, pattern decision tree)
- Total estimated effort: 1.5-2 hours (lighter than Stories 1.10D/1.10DB due to infrastructure already complete)
- Template source: Story 1.10D (2138 lines, 9.5/10 clarity) and Story 1.10DB (1563 lines, 9.5/10 clarity)
- Work item length: 1,089 lines (within target 800-1,200 range for feature enablement story)
- Risk level: LOW (9/11 features validated, infrastructure complete, only flake.inputs configuration remaining)
- Epic 1 coverage: ~98% after Story 1.10E completion (architecture + features + patterns all validated)
