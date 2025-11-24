{ ... }:
{
  flake.modules.homeManager.terminal =
    { ... }:
    {
      programs.fzf = {
        enable = true;
        tmux.enableShellIntegration = true;
      };
    };
}
