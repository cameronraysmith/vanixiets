{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "ccvers";
          runtimeInputs = with pkgs; [
            nodejs
            jq
            coreutils
            gawk
          ];
          text = builtins.readFile ./ccvers.sh;
          meta.description = "List Claude Code npm package versions with tags and release times";
        })
      ];
    };
}
