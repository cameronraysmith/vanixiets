# Direnv with nix-direnv and direnv-instant for async shell integration
#
# direnv-instant makes shell prompts non-blocking by running direnv export
# asynchronously in a daemon. When builds take longer than mux_delay, it
# spawns a tmux pane showing progress.
{ ... }:
{
  flake.modules.homeManager.terminal =
    { flake, pkgs, ... }:
    {
      # Import direnv-instant home-manager module
      # Provides programs.direnv-instant options and shell integration
      imports = [ flake.inputs.direnv-instant.homeModules.direnv-instant ];

      programs.direnv = {
        enable = true;
        nix-direnv.enable = true;
        config.global = {
          warn_timeout = "10m";
          hide_env_diff = true;
        };
      };

      programs.direnv-instant = {
        enable = true;
        package =
          flake.inputs.direnv-instant.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
            (old: {
              # blocking_envrc_calls_tmux hangs in the darwin nix sandbox under nixpkgs 26.05; no upstream fix or CI exists
              checkFlags = (old.checkFlags or [ ]) ++ [
                "--skip"
                "blocking_envrc"
              ];
            });
        enableZshIntegration = true;
        enableFishIntegration = true;
        settings = {
          use_cache = true;
          mux_delay = 5;
        };
      };
    };
}
