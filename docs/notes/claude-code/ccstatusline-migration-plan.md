# Migration Plan: cc-statusline-rs → ccstatusline

## Executive summary

This document outlines the migration from cc-statusline-rs (Rust implementation) to ccstatusline (Node.js implementation) for Claude Code statusline integration.
The migration will enable additional features including git worktree display, session UUID access, and better color integration with starship.

## Current state

### Current implementation

- **Package**: `cc-statusline-rs` (Rust, v0.1.0)
- **Source**: `github:khoi/cc-statusline-rs` (commit 98e3440)
- **Overlay**: `overlays/packages/cc-statusline-rs.nix`
- **Binary**: `statusline`
- **Configuration**: `modules/home/all/tools/claude-code/default.nix:23`

### Current configuration

```nix
statusLine = {
  type = "command";
  command = "${pkgs.cc-statusline-rs}/bin/statusline";
};
```

## Target state

### Target implementation

- **Package**: `ccstatusline` (Node.js/TypeScript, v2.0.21)
- **Source**: `github:sirmalloc/ccstatusline` (tag v2.0.21)
- **Overlay**: `overlays/packages/ccstatusline.nix` (new)
- **Build method**: `buildNpmPackage` with `fetchFromGitHub`
- **Binary**: `ccstatusline`
- **Configuration**:
  - Claude Code integration: `modules/home/all/tools/claude-code/default.nix:23`
  - ccstatusline settings: Imperative initially (`~/.config/ccstatusline/settings.json`), declarative in follow-up

### New features available

1. **Git worktree widget** (v2.0.10+) - displays active worktree name
2. **Session UUID access** - via custom command widget with stdin JSON data
3. **Current working directory** - with configurable path segments
4. **preserveColors option** - for custom command widgets to pass through ANSI colors
5. **Interactive TUI configuration** - run `ccstatusline` without arguments to configure
6. **Multiple themes** - powerline support, 256-color, truecolor modes
7. **Custom command widgets** - execute shell commands with access to Claude Code session data

### Target configuration

```nix
statusLine = {
  type = "command";
  command = "${pkgs.ccstatusline}/bin/ccstatusline";
  padding = 0;  # explicit padding configuration
};
```

## Migration tasks

### Phase 1: Package creation

#### Task 1.1: Create ccstatusline overlay

**File**: `overlays/packages/ccstatusline.nix`

**Strategy**: Use `buildNpmPackage` with `fetchFromGitHub` following mirkolenz-nixos patterns (preferred over fetchurl for proper npm projects).

**Implementation**:
```nix
{
  lib,
  buildNpmPackage,
  fetchFromGitHub,
  versionCheckHook,
  nix-update-script,
}:
buildNpmPackage (finalAttrs: {
  pname = "ccstatusline";
  version = "2.0.21";

  src = fetchFromGitHub {
    owner = "sirmalloc";
    repo = "ccstatusline";
    rev = "v${finalAttrs.version}";
    hash = lib.fakeHash;  # Replace with actual hash after first build
  };

  npmDepsHash = lib.fakeHash;  # Replace with actual hash after first build

  # The package builds dist/ccstatusline.js via npm build script
  # No need to override build phase

  doInstallCheck = true;
  nativeInstallCheckInputs = [ versionCheckHook ];
  versionCheckProgramArg = "--version";

  passthru.updateScript = nix-update-script { };

  meta = {
    description = "Highly customizable status line formatter for Claude Code CLI";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    license = lib.licenses.mit;
    maintainers = [ ];
    mainProgram = "ccstatusline";
  };
})
```

**Notes**:
- Auto-wired by nixos-unified through `overlays/packages/` directory
- Follows mirkolenz-nixos patterns (buildNpmPackage + fetchFromGitHub)
- Uses `finalAttrs` pattern for self-referencing version
- Includes updateScript for easy version bumps: `nix run .#ccstatusline.passthru.updateScript`
- Version check ensures binary works correctly

#### Task 1.2: Calculate hashes and test build

```bash
# From nix-config directory
cd ~/projects/nix-workspace/nix-config

# First build will fail with hash mismatch - copy the correct hash
nix build .#ccstatusline

# Update the src hash in overlays/packages/ccstatusline.nix
# Then build again - will fail with npmDepsHash mismatch
nix build .#ccstatusline

# Update the npmDepsHash in overlays/packages/ccstatusline.nix
# Final build should succeed
nix build .#ccstatusline

# Test execution
./result/bin/ccstatusline --version

# Test with sample input (simulates Claude Code)
echo '{"model":{"display_name":"Claude 3.5 Sonnet"},"transcript_path":"test.jsonl","workspace":{"current_dir":"'"$PWD"'"}}' | ./result/bin/ccstatusline
```

**Expected output**: Should display a formatted status line with model name and current directory.

### Phase 2: Configuration update

#### Task 2.1: Update claude-code module

**File**: `modules/home/all/tools/claude-code/default.nix`

**Changes**:
```diff
     statusLine = {
       type = "command";
-      command = "${pkgs.cc-statusline-rs}/bin/statusline";
+      command = "${pkgs.ccstatusline}/bin/ccstatusline";
+      padding = 0;
     };
```

**Rationale**:
- Explicit `padding = 0` matches Fred Drake's configuration
- Maintains existing behavior
- Enables future customization

#### Task 2.2: Test configuration

```bash
# Rebuild home-manager configuration
home-manager switch --flake ~/projects/nix-workspace/nix-config

# Verify statusline command is accessible
which ccstatusline

# Test with sample JSON (simulate Claude Code input)
echo '{"model":{"display_name":"Claude 3.5 Sonnet"},"transcript_path":"test.jsonl","workspace":{"current_dir":"'"$PWD"'"}}' | ccstatusline

# Launch Claude Code to test in real environment
claude
```

### Phase 3: Interactive TUI configuration (deferred to post-migration)

**This phase is performed AFTER Phase 2 is complete and tested.**

#### Task 3.1: Launch ccstatusline TUI

```bash
# After home-manager switch completes and ccstatusline is in PATH
ccstatusline
```

**Navigation**:
- Main menu appears with options to configure status lines
- Press numbers to select menu items
- Use arrow keys to navigate
- Press Enter to confirm selections
- Press Ctrl+C to exit (settings auto-save)

#### Task 3.2: Configure widgets for requested features

**Goal**: Add the following widgets to status line:
1. Git worktree widget
2. Current working directory widget
3. Session UUID via custom command widget (optional)
4. Any desired starship integration via custom command widget

**TUI workflow**:

1. **Select "Configure Status Lines"** from main menu
2. **Add Git Worktree widget**:
   - Select "Add Widget"
   - Choose "Git Worktree" from list
   - Configure color (suggest: magenta)
   - Press 'h' to toggle "hide no git" option to `true`
   - Press 'r' to toggle raw value mode if desired
   - Confirm

3. **Add Current Working Directory widget**:
   - Select "Add Widget"
   - Choose "Current Working Dir"
   - Configure color (suggest: blue)
   - Press 'p' to set path segments (suggest: 2)
   - Press 'r' to toggle raw value mode if desired
   - Press 'f' to toggle fish-style abbreviation if desired
   - Confirm

4. **Add separators** between widgets as desired:
   - Select "Add Widget"
   - Choose "Separator"
   - Configure separator text (default: " | ")

5. **Add Flex Separator** (optional - for right-alignment):
   - Select "Add Widget"
   - Choose "Flex Separator"
   - All widgets after this will be right-aligned

6. **Configure Global Options** (optional):
   - Select "Global Options" from main menu
   - Set default padding: press 'p' to edit (suggest: " ")
   - Set default separator: press 's' to edit
   - Configure color overrides if desired
   - Toggle inherit colors: press 'i'

7. **Test and Preview**:
   - The TUI shows a live preview at the bottom
   - Make adjustments as needed

8. **Exit** to save: Press Ctrl+C

**Settings location**: `~/.config/ccstatusline/settings.json`

#### Task 3.3: Test custom command widgets (optional, advanced)

**For session UUID display**:

1. Test the command manually first:
```bash
# Claude Code passes JSON via stdin to statusline commands
echo '{"session_uuid":"test-uuid-123","model":{"display_name":"Claude 3.5 Sonnet"}}' | jq -r '.session_uuid // "no-session"'
```

Expected output: `test-uuid-123`

2. In ccstatusline TUI:
   - Add Widget → Custom Command
   - Command: `jq -r '.session_uuid // "no-session"'`
   - Color: cyan (or any preference)
   - Timeout: 1000ms (default)
   - Preserve colors: false (jq doesn't output colors)

**For starship integration**:

Research starship's status line capabilities and test commands:
```bash
# Example: Get git status from starship
starship module git_status

# Or get current directory with starship styling
starship module directory
```

If starship outputs ANSI colors, enable "preserve colors" option in the custom command widget:
- Press 't' to set timeout (starship is fast, 1000ms is fine)
- Press 'p' to toggle preserve colors to `true`

#### Task 3.4: Document the generated configuration

```bash
# View the generated settings
cat ~/.config/ccstatusline/settings.json

# Pretty-print with jq for documentation
cat ~/.config/ccstatusline/settings.json | jq
```

**Save this output** - we'll use it to create the declarative nix configuration in Phase 5.

### Phase 4: Cleanup

#### Task 4.1: Remove cc-statusline-rs overlay

**Action**: Delete `overlays/packages/cc-statusline-rs.nix`

**Rationale**:
- No longer referenced by claude-code module
- Reduces maintenance burden
- Auto-removed from overlay by nixos-unified

#### Task 4.2: Update documentation references

**Files to check**:
- `README.md` (line references found by grep)
- `docs/notes/overlays/overlay-patterns.md`
- `docs/notes/mcp/auggie-mcp-sops-integration-plan.md`

**Action**: Replace references to cc-statusline-rs with ccstatusline where applicable.

### Phase 5: Convert to declarative configuration (deferred to post-TUI-configuration)

**This phase converts the imperative TUI-generated settings to declarative nix configuration.**

**Prerequisites**: Phase 3 must be complete with satisfactory settings.json configuration.

#### Task 5.1: Extract and analyze current settings

```bash
# Read the current settings
cat ~/.config/ccstatusline/settings.json | jq

# Copy to clipboard for reference (macOS)
cat ~/.config/ccstatusline/settings.json | pbcopy

# Or save to a reference file
cat ~/.config/ccstatusline/settings.json > /tmp/ccstatusline-reference.json
```

#### Task 5.2: Create declarative configuration module

**Option A: Add to existing claude-code module**

**File**: `modules/home/all/tools/claude-code/default.nix`

Add after the `programs.claude-code` block:

```nix
# Declarative ccstatusline configuration
home.file.".config/ccstatusline/settings.json".text = builtins.toJSON {
  version = 3;
  lines = [
    [
      # Example widgets - replace with your TUI-generated configuration
      {
        id = "1";
        type = "model";
        color = "cyan";
        rawValue = true;
      }
      {
        id = "2";
        type = "separator";
      }
      {
        id = "3";
        type = "git-worktree";
        color = "magenta";
        hideNoGit = true;
        rawValue = false;
      }
      {
        id = "4";
        type = "separator";
      }
      {
        id = "5";
        type = "current-working-dir";
        color = "blue";
        segments = 2;
        rawValue = true;
        fishStyle = false;
      }
      {
        id = "6";
        type = "separator";
      }
      {
        id = "7";
        type = "git-branch";
        color = "yellow";
      }
      {
        id = "8";
        type = "flex-separator";  # Right-align remaining widgets
      }
      {
        id = "9";
        type = "context-percentage";
        color = "yellow";
      }
      {
        id = "10";
        type = "separator";
      }
      {
        id = "11";
        type = "session-clock";
        color = "green";
        rawValue = true;
      }
      {
        id = "12";
        type = "separator";
      }
      {
        id = "13";
        type = "session-cost";
        color = "red";
        rawValue = true;
      }
    ]
  ];

  # Global options
  colorLevel = 2;  # 0=none, 1=basic 16, 2=256-color, 3=truecolor
  flexMode = "full-minus-40";  # or "full" or "full-until-compact"
  compactThreshold = 60;  # 1-99, used with "full-until-compact"

  # Optional global formatting
  defaultPadding = " ";
  defaultSeparator = " | ";
  inheritSeparatorColors = false;
  globalBold = false;

  # Powerline mode (if desired)
  powerline = {
    enabled = false;
    separators = [];
    separatorInvertBackground = [];
    startCaps = [];
    endCaps = [];
    theme = null;
    autoAlign = false;
  };
};
```

**Option B: Create separate ccstatusline configuration module**

**File**: `modules/home/all/tools/claude-code/ccstatusline-settings.nix`

```nix
{ ... }:
{
  home.file.".config/ccstatusline/settings.json".text = builtins.toJSON {
    # ... same content as Option A
  };
}
```

Then import in `default.nix`:
```nix
{
  imports = [
    ./mcp-servers.nix
    ./ccstatusline-settings.nix  # Add this line
  ];

  programs.claude-code = {
    # ... existing config
  };
}
```

#### Task 5.3: Widget type reference

**Complete widget options** (from ccstatusline source):

```nix
# Common to all widgets:
{
  id = "unique-id";  # Must be unique across all widgets
  type = "widget-type";  # See types below
  color = "color-name";  # See color reference below
}

# Widget-specific options:

# Git Worktree
{ type = "git-worktree"; hideNoGit = true; rawValue = false; }

# Current Working Directory
{ type = "current-working-dir"; segments = 2; rawValue = true; fishStyle = false; }

# Custom Command
{
  type = "custom-command";
  command = "jq -r '.session_uuid'";
  timeout = 1000;  # milliseconds
  preserveColors = false;  # true to pass through ANSI colors
  rawValue = false;
}

# Session Clock
{ type = "session-clock"; rawValue = true; }

# Session Cost
{ type = "session-cost"; rawValue = true; }

# Block Timer
{
  type = "block-timer";
  rawValue = false;
  progressBar = false;  # or "short" for compact
}

# Context Percentage
{
  type = "context-percentage";
  usableContext = false;  # true for 160k usable context mode
  remainingMode = false;  # true to show remaining instead of used
}

# Git Branch
{ type = "git-branch"; hideNoGit = false; rawValue = false; }

# Git Changes
{ type = "git-changes"; hideNoGit = false; rawValue = false; }

# Model
{ type = "model"; rawValue = false; }

# Tokens (input, output, cached, total)
{ type = "tokens-input"; rawValue = false; }
{ type = "tokens-output"; rawValue = false; }
{ type = "tokens-cached"; rawValue = false; }
{ type = "tokens-total"; rawValue = false; }

# Other standard widgets (no extra options)
{ type = "version"; }
{ type = "output-style"; }
{ type = "context-length"; }
{ type = "terminal-width"; }

# Separators and text
{ type = "separator"; }
{ type = "flex-separator"; }
{ type = "custom-text"; text = "Your Text Here"; }
```

**Color reference**:
```nix
# Basic colors (colorLevel 1+)
"black" | "red" | "green" | "yellow" | "blue" | "magenta" | "cyan" | "white"
"bright-black" | "bright-red" | "bright-green" | "bright-yellow"
"bright-blue" | "bright-magenta" | "bright-cyan" | "bright-white"

# 256-color (colorLevel 2+) - use ANSI codes
"ansi-XXX"  # where XXX is 0-255

# Truecolor (colorLevel 3) - use hex codes
"#RRGGBB"  # e.g., "#FF5733"
```

#### Task 5.4: Test declarative configuration

```bash
# After adding the declarative config
cd ~/projects/nix-workspace/nix-config

# Rebuild home-manager
home-manager switch --flake .

# Verify the file was created correctly
cat ~/.config/ccstatusline/settings.json | jq

# Test with Claude Code
claude
```

**Expected behavior**: ccstatusline should use the declarative configuration instead of the TUI-generated one.

#### Task 5.5: Backup and remove imperative config (optional)

Once the declarative config is working:

```bash
# Backup the TUI-generated config
mv ~/.config/ccstatusline/settings.json ~/.config/ccstatusline/settings.json.tui-backup

# Rebuild to create the declarative version
home-manager switch --flake ~/projects/nix-workspace/nix-config

# Test - should work identically
claude
```

### Phase 6: Optional enhancements

#### Task 6.1: Configure ccstatusline via TUI (completed in Phase 3)

```bash
# Run interactive configuration
ccstatusline

# Features to configure:
# - Git worktree widget (toggle with key in TUI)
# - Current working directory (configure path segments)
# - Custom command widgets for session UUID or starship integration
# - Color themes and powerline support
```

**Configuration location**: `~/.config/ccstatusline/settings.json`

**Integration**: The TUI can also install/update Claude Code settings.json directly.

#### Task 6.2: Advanced customizations

**Powerline mode**:
- Enable via TUI: "Powerline Setup" menu
- Choose theme or customize
- Requires Nerd Font (JetBrains Mono Nerd Font, FiraCode Nerd Font, etc.)
- Auto-alignment option for multi-line status displays

**Multiple status lines**:
- ccstatusline supports multiple independent status lines
- Configure via TUI: "Add Line" in Line Selector
- Each line can have different widgets and layout
- Useful for separating project info from session metrics

**Themes**:
- Built-in themes available in TUI
- Copy and customize themes
- Export/import theme configurations

## Rollback plan

If migration fails:

### Immediate rollback
```bash
cd ~/projects/nix-workspace/nix-config

# Revert claude-code module changes
git checkout modules/home/all/tools/claude-code/default.nix

# Rebuild
home-manager switch --flake .
```

### If overlay was deleted
```bash
# Restore cc-statusline-rs overlay
git checkout overlays/packages/cc-statusline-rs.nix

# Rebuild
home-manager switch --flake .
```

## Testing checklist

### Phase 1-2: Core migration
- [ ] Package builds successfully: `nix build .#ccstatusline`
- [ ] Binary is executable: `./result/bin/ccstatusline --version`
- [ ] Piped JSON input works: `echo '{"model":{"display_name":"test"}}' | ./result/bin/ccstatusline`
- [ ] Home-manager rebuild succeeds
- [ ] Binary is in PATH: `which ccstatusline`
- [ ] Claude Code launches with new statusline
- [ ] Statusline displays correctly in Claude Code session
- [ ] No errors in Claude Code logs

### Phase 3: TUI configuration (when performed)
- [ ] TUI launches without errors: `ccstatusline`
- [ ] Git worktree widget can be added and configured
- [ ] Current working directory widget can be added and configured
- [ ] Custom command widgets work (test with jq)
- [ ] Settings saved to `~/.config/ccstatusline/settings.json`
- [ ] Settings persist after TUI exit
- [ ] Claude Code uses new configuration after TUI exit

### Phase 5: Declarative configuration (when performed)
- [ ] Declarative config creates settings.json correctly
- [ ] JSON is valid: `cat ~/.config/ccstatusline/settings.json | jq`
- [ ] Claude Code displays status line with declarative config
- [ ] All configured widgets display correctly
- [ ] Custom commands execute correctly (if configured)
- [ ] Git worktree displays in worktree repositories
- [ ] No errors after home-manager rebuild

## Decision log

### Resolved decisions

1. **Version pinning**: ✓ Pin to v2.0.21 for reproducibility
2. **npm package builder**: ✓ Use `buildNpmPackage` with `fetchFromGitHub` (not fetchurl)
3. **Settings management**: ✓ Imperative initially, declarative in follow-up
4. **Additional widgets**: ✓ Configure via TUI after migration, then make declarative
5. **Source location**: ✓ Fetch from GitHub (not local source)
6. **Update script**: ✓ Include `nix-update-script` for easy version updates
7. **Commit structure**: ✓ Multiple commits for easier rollback

### Rationale

**buildNpmPackage over fetchurl**:
- ccstatusline is a proper npm project with dependencies (React/Ink, etc.)
- Not a precompiled binary like claude-code-bin
- Follows mirkolenz-nixos patterns for npm packages
- Examples: markdown-tree-parser, gemini-cli, mcp-inspector all use buildNpmPackage

**GitHub over npm registry**:
- Better source transparency
- Easier to apply patches if needed
- Consistent with mirkolenz-nixos patterns
- Same approach as markdown-tree-parser, gemini-cli

**Imperative → declarative workflow**:
- TUI is the best way to discover and test widget options
- Allows experimentation before committing to declarative config
- Reduces risk of syntax errors in nix configuration
- Follows principle: "make it work, then make it declarative"

**Multiple commits**:
- Easier to rollback individual changes
- Clearer git history
- Can test each phase independently
- Facilitates code review

## Risk assessment

### Low risk
- Package build (straightforward Node.js wrapper)
- Configuration update (simple substitution)
- Rollback (git revert)

### Medium risk
- Hash verification (manual step)
- Testing in real Claude Code environment (requires active session)

### Mitigation
- Verify hash before committing
- Test in separate terminal before committing
- Keep cc-statusline-rs overlay until after successful test

## Phased commit structure

Following the recommendation for multiple commits for easier rollback:

**Commit 1: Add ccstatusline package**
- File: `overlays/packages/ccstatusline.nix`
- Message: `feat(packages): add ccstatusline v2.0.21`

**Commit 2: Update claude-code to use ccstatusline**
- File: `modules/home/all/tools/claude-code/default.nix`
- Message: `feat(claude-code): migrate from cc-statusline-rs to ccstatusline`

**Commit 3: Remove cc-statusline-rs package**
- File: `overlays/packages/cc-statusline-rs.nix` (delete)
- Message: `refactor(packages): remove cc-statusline-rs`

**Commit 4 (later): Add declarative ccstatusline configuration**
- File: `modules/home/all/tools/claude-code/default.nix` or `ccstatusline-settings.nix`
- Message: `feat(claude-code): add declarative ccstatusline configuration`

## Timeline estimate

- Phase 1 (Package creation): 20-30 minutes (hash calculation + testing)
- Phase 2 (Configuration): 10-15 minutes (config update + testing)
- Phase 3 (Interactive TUI): Deferred, 15-30 minutes when performed
- Phase 4 (Cleanup): 5-10 minutes
- Phase 5 (Declarative config): Deferred, 20-30 minutes when performed
- Phase 6 (Optional enhancements): Optional, 30-60 minutes

**Core migration timeline** (Phases 1, 2, 4): 35-55 minutes
**Deferred enhancements** (Phases 3, 5, 6): 65-120 minutes when performed

## References

### Source repositories
- cc-statusline-rs: https://github.com/khoi/cc-statusline-rs
- ccstatusline: https://github.com/sirmalloc/ccstatusline
- Fred Drake's config: `~/projects/nix-workspace/fred-drake-nix-claude-mcp-sops-ccstatusline/`

### Documentation
- ccstatusline README: `~/projects/nix-workspace/ccstatusline/README.md`
- Claude Code statusline docs: https://docs.claude.com/en/docs/claude-code/statusline
- npm registry: https://registry.npmjs.org/ccstatusline

### Internal documentation
- Overlay patterns: `docs/notes/overlays/overlay-patterns.md`
- Home-manager module: `~/projects/nix-workspace/home-manager/modules/programs/claude-code.nix`

## Post-migration validation

After migration is complete and working:

1. Document final ccstatusline configuration in `docs/notes/claude-code/`
2. Consider adding screenshot of new statusline to documentation
3. Update any references in other projects that might reference the statusline configuration
4. Consider contributing back to ccstatusline project if we make improvements
5. Monitor for new ccstatusline releases and update version periodically

## Additional notes

### Required features implementation guide

#### Git worktree display
**Status**: Built-in widget available since v2.0.10

**Configuration** (Phase 3):
1. In TUI: Add Widget → Git Worktree
2. Color: magenta (suggested)
3. Press 'h': Toggle hideNoGit = true
4. Press 'r': Toggle rawValue as desired

**Declarative** (Phase 5):
```nix
{
  id = "git-worktree-1";
  type = "git-worktree";
  color = "magenta";
  hideNoGit = true;
  rawValue = false;
}
```

#### Session UUID display
**Status**: Available via custom command widget

**Test command first**:
```bash
# Test that jq can extract session_uuid from Claude Code JSON
echo '{"session_uuid":"test-123","model":{"display_name":"Claude 3.5 Sonnet"}}' | jq -r '.session_uuid // "no-session"'
```

**Configuration** (Phase 3):
1. In TUI: Add Widget → Custom Command
2. Command: `jq -r '.session_uuid // "no-session"'`
3. Color: cyan (suggested)
4. Timeout: 1000ms (default is fine)
5. Preserve colors: false (jq doesn't output ANSI colors)

**Declarative** (Phase 5):
```nix
{
  id = "session-uuid-1";
  type = "custom-command";
  command = "jq -r '.session_uuid // \"no-session\"'";
  color = "cyan";
  timeout = 1000;
  preserveColors = false;
  rawValue = false;
}
```

#### Starship integration
**Status**: Possible via custom command widget with preserveColors

**Research needed**:
1. Determine which starship modules are relevant for Claude Code context
2. Test starship command output: `starship module git_status`
3. Verify ANSI color codes in output

**Configuration** (Phase 3):
1. Test command: `starship module <module-name>`
2. In TUI: Add Widget → Custom Command
3. Command: `starship module <module-name>`
4. Press 't': Set appropriate timeout (starship is fast, 1000ms should suffice)
5. Press 'p': Toggle preserveColors = true (enables ANSI color passthrough)

**Declarative** (Phase 5):
```nix
{
  id = "starship-git-1";
  type = "custom-command";
  command = "starship module git_status";
  color = "white";  # Will be overridden by starship colors
  timeout = 1000;
  preserveColors = true;  # Key setting for starship integration
  rawValue = false;
}
```

### Local ccstatusline repository reference

The local repository at `~/projects/nix-workspace/ccstatusline/` contains:
- **Source code**: For understanding widget implementation
- **Type definitions**: `src/types/Settings.ts` - complete settings schema
- **Widget implementations**: `src/widgets/*.ts` - all available widgets
- **TUI components**: `src/tui/components/*.tsx` - configuration interface
- **Documentation**: README.md with comprehensive feature list

**Useful for**:
- Understanding widget options before configuring
- Verifying settings.json schema structure
- Checking available colors and color modes
- Learning about advanced features (powerline, themes, etc.)
- Contributing improvements upstream

### Settings.json schema reference

**From source**: `~/projects/nix-workspace/ccstatusline/src/types/Settings.ts`

**Key constants**:
- `CURRENT_VERSION = 3` - always use this in declarative config
- Color levels: 0 (none), 1 (basic 16), 2 (256-color), 3 (truecolor)
- Flex modes: "full", "full-minus-40", "full-until-compact"

**Widget ID requirements**:
- Must be unique across all widgets
- Can be any string (suggest: "type-number" format)
- Used for widget identification in TUI

**Migration handling**:
- ccstatusline automatically migrates old settings versions
- Declarative config should always use version 3
- If settings.json is missing, ccstatusline uses sensible defaults
