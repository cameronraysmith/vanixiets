{
  ...
}:
{
  flake.modules.homeManager."portable/tara" =
    {
      pkgs,
      ...
    }:
    {
      home.stateVersion = "23.11";

      home.packages = with pkgs; [
        gh
      ];
    };
}
