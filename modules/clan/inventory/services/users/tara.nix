# External ML researcher on GPU/CPU cloud nodes
{
  config,
  inputs,
  lib,
  ...
}:
{
  flake.clan.inventory.instances.user-tara = {
    module = {
      name = "users";
      input = "clan-core";
    };

    # Every host with a tara attachment (modules/lib/host-users.nix): the
    # GPU and CPU cloud nodes
    roles.default.machines = lib.genAttrs (config.flake.lib.hostsOfAccount "tara") (_: { });

    roles.default.settings = {
      user = "tara";
      groups = [
        "video" # GPU device access
        "render" # GPU render node access
      ];
      share = true;
      prompt = false;
    };

    roles.default.extraModules = [
      (
        {
          pkgs,
          ...
        }:
        {
          users.users.tara.shell = pkgs.zsh;

          users.users.tara.openssh.authorizedKeys.keys = inputs.self.users.tara.meta.sshKeys;

          programs.zsh.enable = true;
        }
      )
    ];
  };
}
