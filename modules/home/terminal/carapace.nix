# Carapace multi-shell completion engine (fish + zsh interactive integration)
{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.carapace = {
        enable = true;
        enableFishIntegration = true;
        enableZshIntegration = true;
      };
    };
}
