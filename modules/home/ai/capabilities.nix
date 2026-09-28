{ config, ... }:
let
  modules = config.flake.modules.homeManager;
in
{
  # Shared capabilities, without choosing harnesses or importing personal credentials.
  flake.modules.homeManager.ai-capabilities = {
    key = "vanixiets/ai-capabilities-home-module";
    imports = map (name: modules.${name}) [
      "agent-settings"
      "ai-skills-compose"
      "ai-skills"
      "playwright-cli"
    ];
  };

  flake.modules.homeManager.ai.imports = [ modules.ai-capabilities ];
}
