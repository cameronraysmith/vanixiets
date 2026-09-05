{ ... }:
{
  flake.modules.homeManager.languages =
    { pkgs, ... }:
    {
      home.packages = with pkgs; [
        beamPackages.elixir
        beamPackages.elixir-ls
      ];
    };
}
