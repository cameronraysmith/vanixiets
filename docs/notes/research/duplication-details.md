# agents-md Module Duplication: Detailed Comparison

## Side-by-Side Comparison

### Source of Truth: _agents-md.nix (43 lines)

Location: `/Users/crs58/projects/nix-workspace/test-clan/modules/home/modules/_agents-md.nix`

```nix
 1  # agents-md option module
 2  # Defines programs.agents-md option for generating AI agent configuration files
 3  # Generates 5 config files:
 4  #   - ~/.claude/CLAUDE.md
 5  #   - ~/.codex/AGENTS.md
 6  #   - ~/.gemini/GEMINI.md
 7  #   - ~/.config/crush/CRUSH.md
 8  #   - ~/.config/opencode/AGENTS.md
 9  {
10    lib,
11    config,
12    flake,
13    ...
14  }:
15  let
16    cfg = config.programs.agents-md;
17  in
18  {
19    options.programs.agents-md = {
20      enable = lib.mkEnableOption "AGENTS.md";
21
22      settings = lib.mkOption {
23        type = flake.lib.mdFormat;
24        default = { };
25        description = "Markdown content with frontmatter for AI agent configuration files";
26      };
27    };
28
29    config = lib.mkIf cfg.enable {
30      # XDG config files
31      xdg.configFile = {
32        "crush/CRUSH.md".text = cfg.settings.text;
33        "opencode/AGENTS.md".text = cfg.settings.text;
34      };
35
36      # Home directory files
37      home.file = {
38        ".claude/CLAUDE.md".text = cfg.settings.text;
39        ".codex/AGENTS.md".text = cfg.settings.text;
40        ".gemini/GEMINI.md".text = cfg.settings.text;
41      };
42    };
43  }
```

### Duplicate #1: cameron.nix (lines 93-126, 34 lines)

Location: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/cameron.nix`

```nix
93  # agents-md option module (requires flake arg from extraSpecialArgs)
94  # Defined inline since _agents-md.nix isn't exported as flake module
95  (
96    {
97      lib,
98      config,
99      flake,
100     ...
101   }:
102   let
103     cfg = config.programs.agents-md;
104   in
105   {
106     options.programs.agents-md = {
107       enable = lib.mkEnableOption "AGENTS.md";
108       settings = lib.mkOption {
109         type = flake.lib.mdFormat;
110         default = { };
111         description = "Markdown content with frontmatter for AI agent configuration files";
112       };
113     };
114     config = lib.mkIf cfg.enable {
115       xdg.configFile = {
116         "crush/CRUSH.md".text = cfg.settings.text;
117         "opencode/AGENTS.md".text = cfg.settings.text;
118       };
119       home.file = {
120         ".claude/CLAUDE.md".text = cfg.settings.text;
121         ".codex/AGENTS.md".text = cfg.settings.text;
122         ".gemini/GEMINI.md".text = cfg.settings.text;
123       };
124     };
125   }
126 )
```

### Duplicate #2: crs58.nix (lines 91-124, 34 lines)

Location: `/Users/crs58/projects/nix-workspace/test-clan/modules/clan/inventory/services/users/crs58.nix`

```nix
91  # agents-md option module (requires flake arg from extraSpecialArgs)
92  # Defined inline since _agents-md.nix isn't exported as flake module
93  (
94    {
95      lib,
96      config,
97      flake,
98      ...
99    }:
100   let
101     cfg = config.programs.agents-md;
102   in
103   {
104     options.programs.agents-md = {
105       enable = lib.mkEnableOption "AGENTS.md";
106       settings = lib.mkOption {
107         type = flake.lib.mdFormat;
108         default = { };
109         description = "Markdown content with frontmatter for AI agent configuration files";
110       };
111     };
112     config = lib.mkIf cfg.enable {
113       xdg.configFile = {
114         "crush/CRUSH.md".text = cfg.settings.text;
115         "opencode/AGENTS.md".text = cfg.settings.text;
116       };
117       home.file = {
118         ".claude/CLAUDE.md".text = cfg.settings.text;
119         ".codex/AGENTS.md".text = cfg.settings.text;
120         ".gemini/GEMINI.md".text = cfg.settings.text;
121       };
122     };
123   }
124 )
```

## Exact Content Matching

### Cameron.nix inline (lines 96-125) vs _agents-md.nix (lines 9-42)

```
cameron.nix lines 96-125 are IDENTICAL to _agents-md.nix lines 9-42
Only differences:
- cameron.nix has 2 extra comment lines (93-94)
- cameron.nix wraps module function in parentheses for inline usage
- cameron.nix lines 107, 116-122 have extra indentation (module function body)
- Content is otherwise identical
```

### crs58.nix inline (lines 94-123) vs _agents-md.nix (lines 9-42)

```
crs58.nix lines 94-123 are IDENTICAL to _agents-md.nix lines 9-42
Only differences:
- crs58.nix has 2 extra comment lines (91-92)
- crs58.nix wraps module function in parentheses for inline usage
- crs58.nix lines 95-122 have extra indentation (module function body)
- Content is otherwise identical
```

## Consolidation: Before vs After

### cameron.nix: BEFORE

```nix
users.cameron = {
  imports = [
    inputs.self.modules.homeManager."users/crs58"
    inputs.self.modules.homeManager.base-sops
    inputs.self.modules.homeManager.ai
    inputs.self.modules.homeManager.core
    inputs.self.modules.homeManager.development
    inputs.self.modules.homeManager.packages
    inputs.self.modules.homeManager.shell
    inputs.self.modules.homeManager.terminal
    inputs.self.modules.homeManager.tools
    inputs.lazyvim-nix.homeManagerModules.default
    inputs.nix-index-database.homeModules.nix-index
    # agents-md option module (requires flake arg from extraSpecialArgs)
    # Defined inline since _agents-md.nix isn't exported as flake module
    (
      {
        lib,
        config,
        flake,
        ...
      }:
      let
        cfg = config.programs.agents-md;
      in
      {
        options.programs.agents-md = {
          enable = lib.mkEnableOption "AGENTS.md";
          settings = lib.mkOption {
            type = flake.lib.mdFormat;
            default = { };
            description = "Markdown content with frontmatter for AI agent configuration files";
          };
        };
        config = lib.mkIf cfg.enable {
          xdg.configFile = {
            "crush/CRUSH.md".text = cfg.settings.text;
            "opencode/AGENTS.md".text = cfg.settings.text;
          };
          home.file = {
            ".claude/CLAUDE.md".text = cfg.settings.text;
            ".codex/AGENTS.md".text = cfg.settings.text;
            ".gemini/GEMINI.md".text = cfg.settings.text;
          };
        };
      }
    )
  ];
  home.username = "cameron";
};
```

### cameron.nix: AFTER

```nix
users.cameron = {
  imports = [
    inputs.self.modules.homeManager."users/crs58"
    inputs.self.modules.homeManager.base-sops
    inputs.self.modules.homeManager.ai
    inputs.self.modules.homeManager.core
    inputs.self.modules.homeManager.development
    inputs.self.modules.homeManager.packages
    inputs.self.modules.homeManager.shell
    inputs.self.modules.homeManager.terminal
    inputs.self.modules.homeManager.tools
    inputs.lazyvim-nix.homeManagerModules.default
    inputs.nix-index-database.homeModules.nix-index
    ../../../home/modules/_agents-md.nix
  ];
  home.username = "cameron";
};
```

**Reduction**: 34 lines → 1 line (97% reduction)

### crs58.nix: BEFORE

```nix
users.crs58 = {
  imports = [
    inputs.self.modules.homeManager."users/crs58"
    inputs.self.modules.homeManager.base-sops
    inputs.self.modules.homeManager.ai
    inputs.self.modules.homeManager.core
    inputs.self.modules.homeManager.development
    inputs.self.modules.homeManager.packages
    inputs.self.modules.homeManager.shell
    inputs.self.modules.homeManager.terminal
    inputs.self.modules.homeManager.tools
    inputs.lazyvim-nix.homeManagerModules.default
    inputs.nix-index-database.homeModules.nix-index
    # agents-md option module (requires flake arg from extraSpecialArgs)
    # Defined inline since _agents-md.nix isn't exported as flake module
    (
      {
        lib,
        config,
        flake,
        ...
      }:
      let
        cfg = config.programs.agents-md;
      in
      {
        options.programs.agents-md = {
          enable = lib.mkEnableOption "AGENTS.md";
          settings = lib.mkOption {
            type = flake.lib.mdFormat;
            default = { };
            description = "Markdown content with frontmatter for AI agent configuration files";
          };
        };
        config = lib.mkIf cfg.enable {
          xdg.configFile = {
            "crush/CRUSH.md".text = cfg.settings.text;
            "opencode/AGENTS.md".text = cfg.settings.text;
          };
          home.file = {
            ".claude/CLAUDE.md".text = cfg.settings.text;
            ".codex/AGENTS.md".text = cfg.settings.text;
            ".gemini/GEMINI.md".text = cfg.settings.text;
          };
        };
      }
    )
  ];
  home.username = "crs58";
};
```

### crs58.nix: AFTER

```nix
users.crs58 = {
  imports = [
    inputs.self.modules.homeManager."users/crs58"
    inputs.self.modules.homeManager.base-sops
    inputs.self.modules.homeManager.ai
    inputs.self.modules.homeManager.core
    inputs.self.modules.homeManager.development
    inputs.self.modules.homeManager.packages
    inputs.self.modules.homeManager.shell
    inputs.self.modules.homeManager.terminal
    inputs.self.modules.homeManager.tools
    inputs.lazyvim-nix.homeManagerModules.default
    inputs.nix-index-database.homeModules.nix-index
    ../../../home/modules/_agents-md.nix
  ];
  home.username = "crs58";
};
```

**Reduction**: 34 lines → 1 line (97% reduction)

## Total Consolidation Impact

### Current State (with duplication)

- File: cameron.nix - 135 lines total
- File: crs58.nix - 133 lines total
- File: _agents-md.nix - 43 lines (source of truth)
- **Total lines of code**: 311 lines

### Consolidated State (without duplication)

- File: cameron.nix - 101 lines total
- File: crs58.nix - 99 lines total
- File: _agents-md.nix - 43 lines (source of truth, unchanged)
- **Total lines of code**: 243 lines

**Reduction**: 68 lines eliminated (22% reduction)

**Maintenance benefit**: Single location for option definition means:
- One place to fix bugs
- One place to add features
- One place to document changes
- Two places to verify imports work
