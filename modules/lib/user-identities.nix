# User identity SSH keys - single source of truth
# All machine configs and clan inventory modules reference these keys.
# Add new keys here; they propagate everywhere automatically.
{ ... }:
{
  flake.lib.userIdentities = {
    # crs58/cameron identity (same person, different usernames per machine)
    # - crs58: legacy username on stibnite, blackphos
    # - cameron: preferred username on newer machines (argentum, rosegold, nixos servers)
    crs58 = {
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFXI36PvOzvuJQKVXWbfQE7Mdb6avTKU1+rV1kgy8tvp pixel7-termux"
      ];
    };

    # raquel: primary user on blackphos
    raquel = {
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIAIBdSMsU0hZy7MPpnFmS+P7RlN/x6GwMPVp3g7BOUuf"
      ];
    };

    # christophersmith: primary user on argentum
    christophersmith = {
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIKPi1aUkaTAykqzTEQI1lr8qTpPMxXcyxZwilVECIzAM"
      ];
    };

    # janettesmith: primary user on rosegold
    janettesmith = {
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIIePSVx5J/JJ5eN4PSryuL7iP8WXow/SsZOIr96qnKP0"
      ];
    };

    # tara: external ML researcher on scheelite/galena
    tara = {
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIHwVoxa3ZO+DA+Tun3vthf2oiY2itTqSA5t9lm5Ac8vg"
      ];
    };
  };
}
