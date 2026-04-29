{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "gfork";
          runtimeInputs = with pkgs; [
            gh
            git
          ];
          text = builtins.readFile ./gfork.sh;
          meta.description = "Create a private GitHub fork of current repository";
        })
      ];
    };
}
