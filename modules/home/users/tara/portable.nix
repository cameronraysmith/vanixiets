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
  # Typed-slot writer.
  flake.users.tara.contentPortable = content;
}
