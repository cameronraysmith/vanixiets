{ ... }:
{
  flake.modules.homeManager.ai =
    {
      pkgs,
      lib,
      config,
      flake,
      ...
    }:
    {
      imports = [ flake.inputs.hunk.homeManagerModules.hunk ];
      programs.hunk = {
        enable = true;
        package = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.hunk;
        enableGitIntegration = true;
        enableJujutsuIntegration = true;
        settings = {
          theme = "catppuccin-mocha";
          line_numbers = false;
          hunk_headers = false;
          wrap_lines = true;
          agent_notes = true;
        };
      };
    };
}
