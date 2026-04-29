{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "rosetta-manage";
          runtimeInputs = with pkgs; [
            openssh # explicit dep for reproducibility; system SSH works for localhost
            nix
            procps # for pgrep
          ];
          text = builtins.readFile ./rosetta-manage.sh;
          meta.description = "Manage nix-rosetta-builder VM (stop/start/restart/gc)";
        })
      ];
    };
}
