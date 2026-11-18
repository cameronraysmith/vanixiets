# Deploy targets of the fleet deployer (openspec change
# delegate-fleet-deploys, design D3, D8, D10). Imported by every NixOS and
# darwin base; acts only on a machine in flake.lib.fleetDeployer.targets.
#
# - Installs fleet-deploy-watch, the rollback watcher the deployer starts
#   before each deploy.
# - Once the deployer's keys are committed (flake.lib.fleetDeployer.keys is
#   not null), adds its SSH key to the deploy account's authorized keys
#   (root on NixOS, flake.lib.hosts.<name>.deployUser on darwin), restricted
#   to the deployer's addresses, and lists the sops group fleet-deployers in
#   clan's default groups, so `clan vars fix` makes the deployer a reader of
#   this machine's key and activation-phase vars and of nothing else.
#
# flake.lib.fleetDeployer.failures, asserted by modules/checks/machines.nix,
# fails a target whose deploy account lacks exactly that line and any other
# machine whose accounts carry the key.
{ config, lib, ... }:
let
  inherit (config.flake) modules;
  inherit (config.flake.lib) fleetDeployer hosts;
  provisioned = fleetDeployer.keys != null;

  target =
    { config, pkgs, ... }:
    let
      name = config.networking.hostName;
      isTarget = lib.elem name fleetDeployer.targets;
      deployUser = hosts.${name}.deployUser or null;
    in
    lib.mkIf isTarget {
      environment.systemPackages = [ pkgs.fleet-deploy-watch ];
      users.users = lib.mkIf provisioned {
        ${deployUser}.openssh.authorizedKeys.keys = [
          (fleetDeployer.targetKeyLine fleetDeployer.keys.ssh)
        ];
      };
      clan.core.sops.defaultGroups = lib.mkIf provisioned [ "fleet-deployers" ];
    };
in
{
  flake.modules.nixos.fleet-deploy-target = target;
  flake.modules.nixos.base.imports = [ modules.nixos.fleet-deploy-target ];

  flake.modules.darwin.fleet-deploy-target = target;
  flake.modules.darwin.base.imports = [ modules.darwin.fleet-deploy-target ];
}
