{
  ...
}:
let
  content =
    {
      ...
    }:
    {
      home.stateVersion = "23.11";

      # Minimal initial secrets: the login key, which radicle.nix places.
      sops = {
        defaultSopsFile = ../../../../secrets/home-manager/users/tara/secrets.yaml;
        secrets = {
          ssh-signing-key = {
            mode = "0400";
          };
        };
      };
    };
in
{
  flake.users.tara.contentPrivate = content;
}
