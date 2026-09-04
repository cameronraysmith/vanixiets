{ ... }:
{
  flake.modules.homeManager.terminal =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        aria2
        curl
        restic
        autorestic
        wget
      ];
    };
}
