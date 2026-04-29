{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, config, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "claude-session-cwd";
          runtimeInputs = with pkgs; [
            findutils
            jq
            gnugrep
            gnused
            coreutils
          ];
          text = ''
            export HM_HOME_DIR=${config.home.homeDirectory}
            ${builtins.readFile ./claude-session-cwd.sh}
          '';
          meta.description = "Get Claude Code session working directory and metadata";
        })
      ];
    };
}
