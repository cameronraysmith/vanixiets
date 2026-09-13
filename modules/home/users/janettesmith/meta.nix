{ config, ... }:
{
  flake.users.janettesmith = {
    meta = {
      username = "janettesmith";
      fullname = "Janette Smith";
      email = "janette.a.smith@gmail.com";
      gitEmail = "125711642+janetteasmith@users.noreply.github.com";
      githubUser = "janetteasmith";
      sopsAgeKeyId = null;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
      ];
    };
    aggregates = with config.flake.modules.homeManager; [
      base-sops
      agents
      bioinformatics
      compute
      core
      database
      development
      languages
      publishing
      security
      shell
      terminal
      tools
      agents-md
    ];
  };
}
