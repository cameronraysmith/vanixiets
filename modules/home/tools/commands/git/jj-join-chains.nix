{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "jj-join-chains";
          runtimeInputs = with pkgs; [
            jujutsu
            coreutils
          ];
          text = builtins.readFile ./jj-join-chains.sh;
          meta.description = "List the chain bookmarks in the current jj development join sorted by tip timestamp";
        })
      ];
    };
}
