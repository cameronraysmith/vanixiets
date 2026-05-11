{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "claude-sessions-live";
          runtimeInputs = with pkgs; [
            coreutils
            gawk
            lsof
            procps
          ];
          text = builtins.readFile ./claude-sessions-live.sh;
          meta.description = "List live Claude Code CLI sessions grouped by working directory";
        })
      ];
    };
}
