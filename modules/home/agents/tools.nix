{ ... }:
{
  flake.modules.homeManager.agents =
    {
      pkgs,
      flake,
      ...
    }:
    let
      cursor-agent = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.cursor-agent;
      droid = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.droid;
      gemini-cli = flake.inputs.llm-agents.packages.${pkgs.stdenv.hostPlatform.system}.gemini-cli;
    in
    {
      # backlog-md is absent: auto-patchelf fails on rosetta-builder
      home.packages = with pkgs; [
        claude-monitor
        apm
        cursor-agent
        droid
        gemini-cli
        golem-binary
        hindsight
        ouroboros
      ];
    };
}
