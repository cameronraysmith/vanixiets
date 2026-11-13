{ config, ... }:
{
  flake.users.raquel = {
    meta = {
      username = "raquel";
      fullname = "Raquel";
      email = "raquel@example.com";
      githubUser = null;
      sopsAgeKeyId = null;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIBdSMsU0hZy7MPpnFmS+P7RlN/x6GwMPVp3g7BOUuf"
      ];
      # blackphos, raquel's only host, has no clan machine key, so no generated
      # signing key reaches her; her homes sign with the login key below until
      # blackphos is enrolled (see flake.lib.commitSigningLegacyMachines).
      signingKey = null;
      retiredSigningKeys = [
        {
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIBdSMsU0hZy7MPpnFmS+P7RlN/x6GwMPVp3g7BOUuf";
          validBefore = null;
        }
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
