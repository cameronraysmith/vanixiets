{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, config, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "tre";
          runtimeInputs = with pkgs; [
            tmux
            fzf
            coreutils
          ];
          text = ''
            export HM_HOME_DIR=${config.home.homeDirectory}
            export TMUX_RESURRECT_PATH=${pkgs.tmuxPlugins.resurrect}
            ${builtins.readFile ./tre.sh}
          '';
          meta.description = "Tmux resurrect restore with session selection";
        })
      ];
    };
}
