{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "jj-linearize-join";
          runtimeInputs = with pkgs; [
            jujutsu
            coreutils
          ];
          text = builtins.readFile ./jj-linearize-join.sh;
          meta.description = "Linearize N parallel chains from a jj diamond-workflow development join onto a sequential chain on top of main";
        })
      ];
    };
}
