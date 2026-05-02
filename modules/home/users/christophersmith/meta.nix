{ config, ... }:
{
  flake.users.christophersmith = {
    meta = {
      username = "christophersmith";
      fullname = "Christopher Smith";
      email = "christophersmith@example.com";
      githubUser = null;
      sopsAgeKeyId = null;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPi1aUkaTAykqzTEQI1lr8qTpPMxXcyxZwilVECIzAM"
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
