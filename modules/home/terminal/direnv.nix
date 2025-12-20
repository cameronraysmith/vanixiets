# Direnv with nix-direnv and direnv-instant for async shell integration
#
# direnv-instant makes shell prompts non-blocking by running direnv export
# asynchronously in a daemon. When builds take longer than mux_delay, it
# spawns a tmux pane showing progress.
{ ... }:
{
  flake.modules.homeManager.terminal =
    { flake, ... }:
    {
      # Import direnv-instant home-manager module
      # Provides programs.direnv-instant options and shell integration
      imports = [ flake.inputs.direnv-instant.homeModules.direnv-instant ];

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global = {
          warn_timeout = "10m";
        };
      };

      programs.direnv-instant = {
        enable = true;
        enableZshIntegration = true;
        settings = {
          use_cache = true;
          # Delay before spawning tmux pane for long builds
          # Set low (2s) for testing visibility; tune to 4-12s for production
          mux_delay = 2;
        };
      };
    };
}
