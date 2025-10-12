# LazyVim configuration optimization analysis

Date: 2025-10-12

## Summary

Analysis of our LazyVim configuration in `modules/home/all/development/neovim/lazyvim.nix` revealed several optimization opportunities when compared to LazyVim-module upstream (cameronraysmith/LazyVim-module) and current LazyVim best practices.

## Issues identified

### 1. Redundant copilot configuration

**Current state:**
- Manually adding `copilot-lua` and `blink-cmp-copilot` to plugins list
- Have custom `copilot.lua` configuration file
- Have custom `blink.lua` configuration file
- Missing `extras.ai.copilot.enable = true`

**Issue:**
LazyVim-module added `ai.copilot` extra in commit `0031994` (May 13, 2025) which:
- Automatically includes `copilot-lua`
- Automatically includes `blink-cmp-copilot` when `coding.blink.enable = true`
- Configures copilot with proper binary path using `getExe`
- Handles platform-specific differences (FHS on Linux)

**Impact:** Duplication, potential configuration conflicts

### 2. Using deprecated picker (telescope instead of snacks)

**Current state:**
- Manually adding `telescope-nvim` and `telescope-fzf-native-nvim`
- Manually adding `mini-pick` (unused)
- Not using `extras.editor.snacks_picker`

**Issue:**
As of LazyVim commit `25d90b54` (Feb 8, 2025), new installs default to:
- `snacks_picker` (replaces telescope/fzf/mini-pick)
- `snacks_explorer` (replaces neo-tree)

LazyVim upstream picker priority (install_version >= 8):
1. snacks (editor.snacks_picker)
2. fzf (editor.fzf)
3. telescope (editor.telescope)

**Impact:** Using legacy picker instead of modern default

### 3. Python extra already includes dap/test plugins

**Current state:**
- Manually adding `neotest-python`
- Manually adding `nvim-dap-python`

**Issue:**
The `extras.lang.python` module automatically includes:
- `nvim-dap-python` when `extras.dap.core.enable = true`
- `neotest-python` when `extras.test.core.enable = true`

See `LazyVim-module/lazyvim/extras/lang/python.nix:42-43`

**Impact:** Plugin duplication

### 4. Avante configuration inconsistency

**Current state:**
- Manually adding `avante-nvim` to plugins
- Have `avante.lua` commented out in pluginsFile
- Manually adding avante dependencies (dressing-nvim, img-clip-nvim, render-markdown-nvim)

**Issue:**
Avante plugin is included but its configuration file is commented out, creating incomplete setup.

**Impact:** Plugin loaded but not properly configured

### 5. Dependency management issues

**Current state:**
Manually adding plugins that are:
- Already included by LazyVim core (dressing-nvim, nvim-web-devicons)
- Dependencies of other plugins (render-markdown-nvim for avante)

**Impact:** Unnecessary explicit declarations

## Comparison with phucisstupid's configuration

Their setup (much simpler):
```nix
extras = {
  ai.copilot.enable = true;  # ← Uses ai.copilot extra
  coding = {
    mini-surround.enable = true;
    yanky.enable = true;
  };
  editor = {
    dial.enable = true;
    inc-rename.enable = true;
  };
  lang = {
    nix.enable = true;
  };
  util.mini-hipatterns.enable = true;
};
```

Key differences:
- Uses `ai.copilot` extra (we don't)
- Doesn't manually add plugins (we add 12)
- Uses additional editor extras (dial, inc-rename)
- Uses util.mini-hipatterns extra (we have dot)

## Recommendations

### High priority

1. **Enable ai.copilot extra** - Replace manual copilot plugins
2. **Remove python plugin duplicates** - Already handled by lang.python extra
3. **Migrate to snacks_picker** - Modern default picker
4. **Clean up avante** - Either enable with config or remove entirely

### Medium priority

5. **Remove redundant plugin declarations** - Let extras handle dependencies
6. **Delete unused lua configs** - blink.lua, copilot.lua (if using extras)
7. **Consider additional editor extras** - dial, inc-rename, mini-hipatterns

### Available extras not currently used

From LazyVim-module upstream:
- `extras.ai.copilot-chat` - Chat interface for copilot
- `extras.coding.mini-snippets` - Snippet support
- `extras.editor.dial` - Enhanced increment/decrement
- `extras.editor.fzf` - FZF picker alternative
- `extras.editor.inc-rename` - Incremental LSP rename
- `extras.editor.leap` - Motion plugin
- `extras.editor.snacks_explorer` - File explorer (replaces neo-tree)
- `extras.editor.snacks_picker` - Picker (replaces telescope)
- `extras.formatting.prettier` - Prettier formatting
- `extras.lang.astro` - Astro support
- `extras.lang.go` - Go support
- `extras.lang.markdown` - Enhanced markdown
- `extras.lang.prisma` - Prisma support
- `extras.lang.svelte` - Svelte support
- `extras.lang.zig` - Zig support
- `extras.linting.eslint` - ESLint integration
- `extras.ui.mini-animate` - Animations
- `extras.util.mini-hipatterns` - Pattern highlighting

## Implementation plan

### Phase 1: Remove duplicates

- Remove `copilot-lua`, `blink-cmp-copilot` from plugins (handled by ai.copilot extra)
- Remove `neotest-python`, `nvim-dap-python` from plugins (handled by python extra)

### Phase 2: Add missing extras

- Add `extras.ai.copilot.enable = true`

### Phase 3: Modernize picker

- Add `extras.editor.snacks_picker.enable = true`
- Remove `telescope-nvim`, `telescope-fzf-native-nvim`, `mini-pick` from plugins

### Phase 4: Clean up avante

- Decide: either enable avante.lua or remove avante-nvim plugin
- Remove redundant dependencies if keeping avante

### Phase 5: Consider enhancements

- Evaluate `editor.dial`, `editor.inc-rename`, `util.mini-hipatterns`
- Consider `editor.snacks_explorer` vs current neo-tree

## References

- LazyVim-module: https://github.com/matadaniel/LazyVim-module
- Our fork: https://github.com/cameronraysmith/LazyVim-module
- LazyVim upstream: https://github.com/LazyVim/LazyVim
- Snacks default change: commit 25d90b54 (2025-02-08)
- ai.copilot extra added: commit 0031994 (2025-05-13)
