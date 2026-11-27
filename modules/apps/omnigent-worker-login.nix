{ config, lib, ... }:
let
  omnigent = config.flake.clan.inventory.instances.omnigent;
  # The omnigent server role's one member, which must be named under
  # `.machines` because its entry's `settings` carry the server's domain.
  servers = config.flake.lib.inventoryMembers omnigent "server";
  server = builtins.head servers;
  serverSettings =
    assert lib.assertMsg (builtins.length servers == 1)
      "omnigent-worker-login: the omnigent server role has ${toString (builtins.length servers)} members, not one";
    assert lib.assertMsg (
      omnigent.roles.server.machines ? ${server}
    ) "omnigent-worker-login: the omnigent server ${server} is not named under roles.server.machines";
    omnigent.roles.server.machines.${server}.settings;
  serverDomain =
    (lib.evalModules {
      modules = [
        { freeformType = lib.types.attrsOf lib.types.anything; }
        serverSettings
      ];
    }).config.domain;
in
{
  perSystem =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      packages.omnigent-worker-login = pkgs.writeShellApplication {
        name = "omnigent-worker-login";
        runtimeInputs = [ pkgs.openssh ];
        runtimeEnv.OMNIGENT_SERVER_URL = "https://${serverDomain}";
        text = builtins.readFile ./omnigent-worker-login.sh;
      };
      apps.omnigent-worker-login = {
        type = "app";
        program = lib.getExe config.packages.omnigent-worker-login;
      };
    };
}
