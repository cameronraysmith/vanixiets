{
  ...
}:
let
  content =
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
in
{
  flake.users.tara.contentPortable = content;
}
