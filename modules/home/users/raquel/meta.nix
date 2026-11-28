{ config, ... }:
{
  flake.users.raquel = {
    aggregates = config.flake.lib.defaultAggregates;
    meta = {
      fullname = "Raquel";
      email = "raquel@example.com";
      githubUser = null;
      sopsAgeKeyId = null;
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIBdSMsU0hZy7MPpnFmS+P7RlN/x6GwMPVp3g7BOUuf"
      ];
      # blackphos, raquel's only host, has no clan machine key, so no generated
      # signing key reaches her; a home there signs with the login key below,
      # whose signatures stop verifying at its cutover, until a machine of hers
      # is enrolled (see flake.lib.commitSigningLegacyMachines).
      signingKey = null;
      retiredSigningKeys = [
        {
          key = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIBdSMsU0hZy7MPpnFmS+P7RlN/x6GwMPVp3g7BOUuf";
          validBefore = "20261114195233Z";
        }
      ];
    };
  };
}
