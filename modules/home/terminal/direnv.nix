# Direnv with nix-direnv and direnv-instant for async shell integration
#
# direnv-instant makes shell prompts non-blocking by running direnv export
# asynchronously in a daemon. When builds take longer than mux_delay, it
# spawns a tmux pane showing progress.
{ ... }:
let
  content =
    {
      flake,
      lib,
      pkgs,
      ...
    }:
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
        # Layouts (nix-direnv's flake profiles and caches) live under the
        # account's cache rather than in the project's .direnv, so `use flake`
        # also works in repositories this account can read but not write, such
        # as a host-shared ghq tree.
        stdlib = ''
          direnv_layout_dir() {
            local hash
            hash=$(printf '%s' "$PWD" | ${pkgs.coreutils}/bin/sha256sum | ${pkgs.coreutils}/bin/cut -c1-32)
            printf '%s\n' "''${XDG_CACHE_HOME:-$HOME/.cache}/direnv/layouts/$hash-''${PWD##*/}"
          }
        '';
      };

      programs.direnv-instant = {
        enable = true;
        package =
          flake.inputs.direnv-instant.packages.${pkgs.stdenv.hostPlatform.system}.default.overrideAttrs
            (old: {
              # One daemon and env file per directory would serve every shell
              # in the format of whichever started it; keying the runtime dir
              # by shell too keeps fish and zsh in one project apart.
              patches = (old.patches or [ ]) ++ [ ./direnv-instant-per-shell-runtime-dir.patch ];
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

      # direnv-instant formats its output for DIRENV_INSTANT_SHELL, which its
      # fish hook exports and its bash and zsh hooks never set, so a bash or
      # zsh started under fish evals fish syntax (`(eval):1: unmatched "`).
      programs.zsh.initContent = lib.mkBefore "export DIRENV_INSTANT_SHELL=zsh";
      programs.bash.initExtra = lib.mkBefore "export DIRENV_INSTANT_SHELL=bash";
    };
in
{
  flake.modules.homeManager.terminal = content;
  flake.modules.homeManager.direnv = content;
}
