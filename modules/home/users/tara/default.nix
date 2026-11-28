{ config, ... }:
{
  # Minimal secrets: the login key, which radicle.nix places.
  flake.users.tara.contentPrivate = config.flake.lib.mkUserContent "tara" {
    sops.secrets.ssh-signing-key = {
      mode = "0400";
    };
  };
}
