# LazyVim nvim-treesitter compatibility fix

## Problem summary

LazyVim displays the following error on startup:
```
Error  23:12:24 notify.error LazyVim Please use `:Lazy` and update `nvim-treesitter`
```

## Root cause analysis

### Version mismatch

1. **LazyVim expects**: nvim-treesitter from the `main` branch
   - Requires the `get_installed()` function
   - Source: `/Users/crs58/projects/nix-workspace/LazyVim/lua/lazyvim/plugins/treesitter.lua:77-78`

2. **nixpkgs provides**: nvim-treesitter from the `master` branch
   - Commit: `42fc28ba918343ebfd5565147a42a26580579482`
   - This is literally the "announce archiving of master branch" commit
   - The master branch is frozen/archived
   - Does NOT have the `get_installed()` function

3. **LazyVim-module uses**: `pkgs.vimPlugins.nvim-treesitter` without overriding

### API change details

The nvim-treesitter project underwent a major rewrite on the `main` branch:
- The `master` branch was archived in 2025
- The `main` branch is the actively maintained version
- Major API changes include the addition of `get_installed()` function
- LazyVim's check at treesitter.lua:77-78:
  ```lua
  if not TS.get_installed then
    return LazyVim.error("Please use `:Lazy` and update `nvim-treesitter`")
  end
  ```

### Nixpkgs nvim-treesitter structure

The nixpkgs nvim-treesitter derivation includes important custom logic:
- Location: `pkgs/applications/editors/vim/plugins/nvim-treesitter/overrides.nix`
- **postPatch**: Removes the parser directory
- **passthru attributes**:
  - `withPlugins`: Function to select specific grammars
  - `withAllGrammars`: Include all available grammars
  - `builtGrammars`: All built grammar packages
  - `grammarPlugins`: Grammar plugins mapping
- **Generated grammars**: From `./generated.nix`
- **Tests**: Query validation tests

LazyVim-module relies on `withPlugins` functionality (line 326 of lazyvim/default.nix):
```nix
nvim-treesitter = pkgs.vimPlugins.nvim-treesitter.withPlugins (plugins: ...)
```

## Solution implemented

Created an overlay in `/Users/crs58/projects/nix-workspace/nix-config/overlays/default.nix` to override nvim-treesitter to use the main branch:

```nix
vimPlugins = super.vimPlugins // {
  nvim-treesitter = super.vimPlugins.nvim-treesitter.overrideAttrs (oldAttrs: {
    src = super.fetchFromGitHub {
      owner = "nvim-treesitter";
      repo = "nvim-treesitter";
      rev = "main";
      hash = "sha256-1zVgNJJiKVskWF+eLllLB51iwg10Syx9IDzp90fFDWU=";
    };
    version = "unstable-2025-10-09";
    # Main branch has different structure: no parser/ directory
    postPatch = ''
      [ -d parser ] && rm -r parser || true
    '';
    # Skip Lua Language Server meta annotation files from require check
    nvimSkipModules = [ "nvim-treesitter._meta.parsers" ];
  });

  # nvim-treesitter-textobjects must also use main branch to be compatible
  nvim-treesitter-textobjects = super.vimPlugins.nvim-treesitter-textobjects.overrideAttrs (oldAttrs: {
    src = super.fetchFromGitHub {
      owner = "nvim-treesitter";
      repo = "nvim-treesitter-textobjects";
      rev = "main";
      hash = "sha256-+KmOpRi4JAqm6UqYdtk80jwFrJhLCs0lZM/Liofq0R4=";
    };
    version = "unstable-2025-10-09";
  });
};
```

### Directory structure differences

The main and master branches have significantly different directory structures:

**Master branch** (archived):
- Has `parser/` directory (with pre-built parsers)
- Has `parser-info/` directory
- Has `queries/` directory (with all query files)
- Has `lockfile.json`

**Main branch** (current):
- NO `parser/` directory (parsers managed separately)
- NO `parser-info/` directory
- NO `queries/` directory (queries now per-parser)
- NO `lockfile.json`

The nixpkgs override includes `postPatch = ''rm -r parser''` which was designed for the master branch.
This fails on main branch because the directory does not exist, requiring our conditional postPatch override.

### Build hook compatibility

The main branch includes a `lua/nvim-treesitter/_meta/` directory containing Lua Language Server type annotation files.
These files (like `_meta/parsers.lua`) are not meant to be required at runtime and will error if loaded.
The nixpkgs `neovim-require-check-hook` auto-discovers all lua modules and tests them, but its exclusion pattern doesn't catch the `_meta` directory.
We use `nvimSkipModules` to explicitly exclude these meta files from the require check.

### nvim-treesitter-textobjects compatibility

**Critical discovery**: The main branch rewrite removed the `define_modules` API that the master branch used for its module system.
This means `nvim-treesitter-textobjects` from the master branch (which nixpkgs uses) is **incompatible** with main branch nvim-treesitter.

When using main branch nvim-treesitter with master branch textobjects, you get:
```
Error: attempt to call field 'define_modules' (a nil value)
```

**Solution**: Both plugins must use the same branch. Since LazyVim requires main branch nvim-treesitter, we must also override nvim-treesitter-textobjects to use main branch.

### Why this works

1. **overrideAttrs preserves passthru**: The `passthru` attributes (including `withPlugins`) are automatically preserved when using `overrideAttrs`
2. **Only changes source**: We only override the `src` and `version`, leaving all the nixpkgs custom logic intact
3. **Maintains compatibility**: LazyVim-module's use of `.withPlugins()` continues to work

## Alternative approaches considered

1. **Upstream fix in LazyVim-module**: Add an input for nvim-treesitter from main branch
   - More complex
   - Would need PR to LazyVim-module

2. **Downgrade LazyVim**: Use older version that supports master branch
   - Not desirable as we want latest features

3. **Fork and modify LazyVim-module**:
   - Maintenance burden
   - Not necessary

## Maintenance notes

- The hash `sha256-1zVgNJJiKVskWF+eLllLB51iwg10Syx9IDzp90fFDWU=` points to the main branch as of 2025-10-09
- To update: `nix-prefetch-url --unpack https://github.com/nvim-treesitter/nvim-treesitter/archive/refs/heads/main.tar.gz`
- Convert hash to SRI format: `nix hash convert --to sri <hash>`
- Eventually, nixpkgs will likely switch to main branch, at which point this overlay can be removed

## Testing

After applying this fix:
1. Rebuild home-manager configuration: `nix run .#activate`
2. Launch nvim/LazyVim
3. Verify no error message appears
4. Check that treesitter functionality works: `:TSInstall` commands, syntax highlighting, etc.

## References

- nvim-treesitter master→main migration: https://github.com/nvim-treesitter/nvim-treesitter/discussions/7901
- LazyVim treesitter plugin: `~/projects/nix-workspace/LazyVim/lua/lazyvim/plugins/treesitter.lua`
- nixpkgs nvim-treesitter overrides: `~/projects/nix-workspace/nixpkgs/pkgs/applications/editors/vim/plugins/nvim-treesitter/overrides.nix`
