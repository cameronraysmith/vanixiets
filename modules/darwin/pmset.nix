# nix-darwin's power.sleep.* goes through `systemsetup`, which sets every power
# source at once; `pmset -b` and `pmset -c` keep the battery and AC profiles apart.
# Each key is a mkDefault so a host overrides single keys and keeps the rest.
# AC never sleeps so every darwin host stays reachable for deployment and remote builds.
{ ... }:
{
  flake.modules.darwin.base =
    { config, lib, ... }:
    let
      cfg = config.custom.pmset;
      profile =
        source:
        lib.mkOption {
          type = lib.types.attrsOf lib.types.ints.unsigned;
          default = { };
          description = "`pmset -${source}` settings applied on activation; empty leaves this power source unmanaged.";
        };
      command =
        source: settings:
        "/usr/bin/pmset -${source} "
        + lib.concatStringsSep " " (lib.mapAttrsToList (key: value: "${key} ${toString value}") settings);
    in
    {
      options.custom.pmset = {
        battery = profile "b";
        ac = profile "c";
      };

      config = {
        custom.pmset = lib.mapAttrs (_: lib.mapAttrs (_: lib.mkDefault)) {
          battery = {
            displaysleep = 2;
            sleep = 1;
            powernap = 1;
            womp = 0;
            tcpkeepalive = 1;
            standby = 1;
            hibernatemode = 3;
          };
          ac = {
            displaysleep = 10;
            sleep = 0;
            powernap = 1;
            womp = 1;
            tcpkeepalive = 1;
            standby = 1;
            hibernatemode = 3;
          };
        };

        system.activationScripts.power.text = lib.mkAfter (
          lib.concatStringsSep "\n" (
            lib.optional (cfg.battery != { }) (command "b" cfg.battery)
            ++ lib.optional (cfg.ac != { }) (command "c" cfg.ac)
          )
        );
      };
    };
}
