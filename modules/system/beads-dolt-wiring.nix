# Bridge dolt-sql-server port into home-manager for beads CLI configuration.
# Assumes all machines in this fleet use home-manager (clan inventory provides it).
{ ... }:
let
  beadsDoltPortOption =
    { lib, ... }:
    {
      options.services.beads.doltServerPort = lib.mkOption {
        type = lib.types.port;
        default = 3307;
        description = "Port of the dolt SQL server for beads CLI connections.";
      };
    };

  mkWiringModule =
    { config, lib, ... }:
    {
      home-manager.sharedModules = [
        beadsDoltPortOption
      ]
      ++ lib.optionals config.services.dolt-sql-server.enable [
        { services.beads.doltServerPort = config.services.dolt-sql-server.port; }
      ];
    };
in
{
  flake.modules.darwin.beads-dolt-wiring = mkWiringModule;
  flake.modules.nixos.beads-dolt-wiring = mkWiringModule;
}
