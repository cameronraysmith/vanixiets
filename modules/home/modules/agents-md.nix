# agents-md option module
# Defines programs.agents-md option for generating AI agent configuration files
# Generates 6 config files:
#   - ~/.claude/CLAUDE.md
#   - ~/.codex/AGENTS.md
#   - ~/.factory/AGENTS.md
#   - ~/.gemini/GEMINI.md
#   - ~/.config/crush/CRUSH.md
#   - ~/.config/opencode/AGENTS.md
{ config, ... }:
let
  inherit (config.flake.lib) mdFormat;
in
{
  flake.modules.homeManager.agents-md =
    { lib, config, ... }:
    let
      cfg = config.programs.agents-md;
    in
    {
      options.programs.agents-md = {
        enable = lib.mkEnableOption "AGENTS.md";

        settings = lib.mkOption {
          type = mdFormat;
          default = { };
          description = "Markdown content with frontmatter for AI agent configuration files";
        };
      };

      config = lib.mkIf cfg.enable {
        # XDG config files
        xdg.configFile = {
          "crush/CRUSH.md".text = cfg.settings.text;
          "opencode/AGENTS.md".text = cfg.settings.text;
        };

        # Home directory files
        home.file = {
          ".claude/CLAUDE.md".text = cfg.settings.text;
          ".codex/AGENTS.md".text = cfg.settings.text;
          ".factory/AGENTS.md".text = cfg.settings.text;
          ".gemini/GEMINI.md".text = cfg.settings.text;
        };
      };
    };
}
