{ config, ... }:
{
  flake.users.tara = {
    aggregates = config.flake.lib.defaultAggregates;
    meta = {
      fullname = "Tara Chari";
      email = "17519396+tarachari3@users.noreply.github.com";
      githubUser = "tarachari3";
      sopsAgeKeyId = "tara";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHwVoxa3ZO+DA+Tun3vthf2oiY2itTqSA5t9lm5Ac8vg"
      ];
      retiredSigningKeys = [
        {
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHwVoxa3ZO+DA+Tun3vthf2oiY2itTqSA5t9lm5Ac8vg";
          validBefore = "20261114195233Z";
        }
      ];
    };
  };
}
