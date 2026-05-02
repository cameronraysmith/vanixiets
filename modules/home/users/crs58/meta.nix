{ config, ... }:
{
  flake.users.crs58 = {
    meta = {
      username = "crs58";
      fullname = "Cameron Smith";
      email = "cameron.ray.smith@gmail.com";
      githubUser = "cameronraysmith";
      sopsAgeKeyId = "crs58";
      sshKeys = [
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+"
        "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIFXI36PvOzvuJQKVXWbfQE7Mdb6avTKU1+rV1kgy8tvp pixel7-termux"
      ];
    };
    aggregates = with config.flake.modules.homeManager; [
      base-sops
      ai
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
