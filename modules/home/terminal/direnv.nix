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
      # Disable home-manager's direnv module: has readOnly on enableFishIntegration
      # which conflicts with direnv-instant's mkForce for mutual exclusivity
      disabledModules = [ "programs/direnv.nix" ];

      imports = [
        # Patched home-manager direnv module (readOnly removed)
        ../../../lib/hm-patches/direnv.nix
        # direnv-instant for async shell integration
        flake.inputs.direnv-instant.homeModules.direnv-instant
      ];

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
        enableFishIntegration = true;
        settings = {
          use_cache = true;
          mux_delay = 5;
        };
      };
    };
}
