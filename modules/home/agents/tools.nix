{ ... }:
{
  flake.modules.homeManager.agents =
    {
      pkgs,
      flake,
      ...
    }:
    let
      antigravity-cli =
        flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.antigravity-cli;
      cursor-agent = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cursor-agent;
      droid = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.droid;
    in
    {
      # backlog-md is absent: its build failed in auto-patchelf (2025-11)
      home.packages = with pkgs; [
        claude-monitor
        apm
        cursor-agent
        droid
        antigravity-cli
        golem-binary
        hindsight
        ouroboros
      ];
    };
}
