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
  # Typed-slot writer (nix-0pd.17 A5: registry-key dual-write dropped).
  flake.users.tara.contentPortable = content;
}
