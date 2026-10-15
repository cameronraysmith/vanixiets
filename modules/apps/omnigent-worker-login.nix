{ config, lib, ... }:
let
  serverSettings =
    (builtins.head (
      builtins.attrValues config.flake.clan.inventory.instances.omnigent.roles.server.machines
    )).settings;
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
