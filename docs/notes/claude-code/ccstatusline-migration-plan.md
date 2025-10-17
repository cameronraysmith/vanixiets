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

- **Package**: `ccstatusline` (Node.js/TypeScript, v2.0.21+)
- **Source**: `github:sirmalloc/ccstatusline`
- **Overlay**: `overlays/packages/ccstatusline.nix` (new)
- **Binary**: `ccstatusline`
- **Configuration**: `modules/home/all/tools/claude-code/default.nix:23`

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

**Strategy**: Use `fetchurl` to download pre-built tarball from npm registry (simpler than fetcher infrastructure for single package).

**Implementation**:
```nix
{
  stdenv,
  fetchurl,
  nodejs,
  makeWrapper,
}:
let
  pname = "ccstatusline";
  version = "2.0.21"; # Update to latest stable version
in
stdenv.mkDerivation {
  inherit pname version;

  src = fetchurl {
    url = "https://registry.npmjs.org/ccstatusline/-/ccstatusline-${version}.tgz";
    hash = "sha256-+puIi9gALJw7EXLt0AT4fmQq8UmtLfZPxs8n0aFGyiE=";
    # Hash will need verification/update for current version
  };

  nativeBuildInputs = [ makeWrapper ];
  dontBuild = true;

  unpackPhase = ''
    mkdir -p source
    tar -xzf $src -C source
  '';

  installPhase = ''
    mkdir -p $out/lib/node_modules/ccstatusline
    mkdir -p $out/bin

    cp -r source/package/* $out/lib/node_modules/ccstatusline/

    makeWrapper ${nodejs}/bin/node $out/bin/ccstatusline \
      --add-flags "$out/lib/node_modules/ccstatusline/dist/ccstatusline.js"
  '';

  meta = {
    description = "Highly customizable status line formatter for Claude Code CLI";
    homepage = "https://github.com/sirmalloc/ccstatusline";
    mainProgram = "ccstatusline";
  };
}
```

**Notes**:
- Auto-wired by nixos-unified through `overlays/packages/` directory
- Follows existing overlay patterns (no manual import needed)
- Uses `fetchurl` for simplicity (no fetcher infrastructure needed)
- Hash needs verification with: `nix-prefetch-url https://registry.npmjs.org/ccstatusline/-/ccstatusline-2.0.21.tgz`

#### Task 1.2: Verify hash and test build

```bash
# From nix-config directory
cd ~/projects/nix-workspace/nix-config

# Fetch latest ccstatusline version info
curl -s https://registry.npmjs.org/ccstatusline/latest | jq -r '.version, .dist.tarball, .dist.shasum'

# Calculate nix hash for the tarball
nix-prefetch-url https://registry.npmjs.org/ccstatusline/-/ccstatusline-2.0.21.tgz

# Test build
nix build .#ccstatusline

# Test execution
./result/bin/ccstatusline --help
```

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

### Phase 3: Cleanup

#### Task 3.1: Remove cc-statusline-rs overlay

**Action**: Delete `overlays/packages/cc-statusline-rs.nix`

**Rationale**:
- No longer referenced by claude-code module
- Reduces maintenance burden
- Auto-removed from overlay by nixos-unified

#### Task 3.2: Update documentation references

**Files to check**:
- `README.md` (line references found by grep)
- `docs/notes/overlays/overlay-patterns.md`
- `docs/notes/mcp/auggie-mcp-sops-integration-plan.md`

**Action**: Replace references to cc-statusline-rs with ccstatusline where applicable.

### Phase 4: Optional enhancements

#### Task 4.1: Configure ccstatusline via TUI

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

#### Task 4.2: Add custom widgets for requested features

**Git worktree + starship integration**:

Create custom command widget in ccstatusline TUI:
```bash
# Example custom command for git worktree
git rev-parse --show-toplevel | xargs basename

# Example for session UUID (from Claude Code JSON stdin)
# The JSON is piped to custom commands automatically
jq -r '.session_uuid // "no-session"'
```

**preserveColors option**: Enable when adding custom command widgets that output ANSI colors (like starship).

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

- [ ] Package builds successfully: `nix build .#ccstatusline`
- [ ] Binary is executable: `./result/bin/ccstatusline --help`
- [ ] TUI launches without errors: `ccstatusline`
- [ ] Piped JSON input works: `echo '{"model":{"display_name":"test"}}' | ccstatusline`
- [ ] Home-manager rebuild succeeds
- [ ] Claude Code launches with new statusline
- [ ] Statusline displays correctly in Claude Code session
- [ ] Git worktree widget displays (if in worktree)
- [ ] Current working directory displays
- [ ] No errors in Claude Code logs

## Open questions

1. **Version pinning**: Should we pin to v2.0.21 or use latest?
   - **Recommendation**: Pin to specific version (2.0.21) for reproducibility, update periodically
   - Fred Drake uses v2.0.21, which is stable

2. **npm fetcher infrastructure**: Do we want to adopt Fred Drake's npm-packages fetcher system?
   - **Recommendation**: No, use simple `fetchurl` approach for single package
   - Consider fetcher infrastructure only if we add more npm packages

3. **Settings management**: Where should ccstatusline settings.json live?
   - **Current**: `~/.config/ccstatusline/settings.json` (ccstatusline default)
   - **Alternative**: Manage via home-manager (more declarative)
   - **Recommendation**: Start with ccstatusline default, evaluate declarative approach later

4. **Additional widgets**: Which additional widgets should we enable by default?
   - Git worktree (user requested)
   - Current working directory (user requested)
   - Session UUID (user requested) - via custom command widget
   - **Recommendation**: Configure via TUI after migration, document preferred configuration

5. **Overlay patterns**: Should ccstatusline follow any special patterns?
   - **Recommendation**: Follow existing pattern (simple package in overlays/packages/)
   - No special treatment needed

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

## Timeline estimate

- Phase 1 (Package creation): 15-30 minutes
- Phase 2 (Configuration): 10-15 minutes
- Phase 3 (Cleanup): 5-10 minutes
- Phase 4 (Optional enhancements): 30-60 minutes
- **Total core migration**: 30-55 minutes
- **Total with enhancements**: 60-115 minutes

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

### Color integration with starship

The user mentioned wanting ccstatusline to integrate with starship-based zsh shell coloring.
This can be achieved through:

1. **Custom command widgets**: Create a widget that executes starship commands
2. **preserveColors option**: Enable for the custom command widget to pass through starship's ANSI color codes
3. **Example configuration**:
   ```bash
   # In ccstatusline TUI, add custom command widget:
   # Command: echo "$STARSHIP_SESSION" or similar starship integration
   # Enable: preserve colors option
   ```

### Session UUID and git worktree display

These are the user's primary goals:

1. **Git worktree**: Available as built-in widget (v2.0.10+)
   - Configure via TUI: Add "Git Worktree" widget
   - Option to hide "no git" message when not in repository

2. **Session UUID**: Available via custom command widget
   - ccstatusline receives Claude Code JSON via stdin
   - Custom command can extract: `jq -r '.session_uuid'`
   - JSON includes: session_uuid, model info, transcript_path, workspace.current_dir, etc.

### Additional context for user

The local ccstatusline repository at `~/projects/nix-workspace/ccstatusline/` is the actual source code for the sirmalloc/ccstatusline project.
This can be useful for:
- Understanding implementation details
- Testing local modifications before upstreaming
- Contributing features back to the project

Consider using the local repository as a source if we need to:
- Apply custom patches
- Test unreleased features
- Contribute improvements upstream
