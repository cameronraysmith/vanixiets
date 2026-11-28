{ config, ... }:
{
  flake.users.janettesmith = {
    aggregates = config.flake.lib.defaultAggregates;
    meta = {
      fullname = "Janette Smith";
      email = "janette.a.smith@gmail.com";
      gitEmail = "125711642+janetteasmith@users.noreply.github.com";
      githubUser = "janetteasmith";
      sopsAgeKeyId = null;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
      ];
      retiredSigningKeys = [
        {
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0";
          validBefore = "20261114195233Z";
        }
      ];
    };
  };
}
