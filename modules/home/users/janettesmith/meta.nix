{ config, ... }:
{
  flake.users.janettesmith = {
    meta = {
      username = "janettesmith";
      fullname = "Janette Smith";
      email = "janettesmith@example.com";
      githubUser = null;
      sopsAgeKeyId = null;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
      ];
    };
    aggregates = with config.flake.modules.homeManager; [
      base-sops
      core
      development
      packages
      shell
      terminal
      tools
      agents-md
    ];
  };
}
