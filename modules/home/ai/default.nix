# The one definition of the ai aggregate: the agent tooling a home imports.
# A part is a flake.modules.homeManager module defined in one file and named
# here (ai-claude-code alone spans the files of claude-code/). A list option
# that two parts define merges their definitions in import order, so
# reordering the entries can change the homes; home.packages is sorted instead
# (system/package-order.nix).
{ config, ... }:
{
  flake.lib.homeAiParts = [
    "atomic"
    "ai-capabilities"
    "ai-claude-code"
    "ai-codex"
    "ai-devin"
    "ai-moshi"
    "ai-omnigent"
    "ai-omp"
    "ai-opencode"
    "openspec"
    "ai-pi"
    "ai-tuicr"
    "worktrunk"
    "ai-gh-dash"
    "ai-omnigraph"
  ];
  flake.modules.homeManager.ai.imports = map (
    name: config.flake.modules.homeManager.${name}
  ) config.flake.lib.homeAiParts;
}
