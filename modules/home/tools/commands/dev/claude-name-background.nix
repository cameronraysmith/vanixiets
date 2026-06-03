{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "claude-name-background";
          runtimeInputs = with pkgs; [ coreutils ];
          text = builtins.readFile ./claude-name-background.sh;
          meta.description = "Start a named, backgrounded Claude Code session";
        })
      ];
    };
}
