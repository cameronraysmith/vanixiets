# Deploy targets of the fleet deployer (openspec change
# delegate-fleet-deploys, design D3, D8, D10). Imported by every NixOS and
# darwin base; acts only on a machine in flake.lib.fleetDeployer.targets.
#
# - Installs fleet-deploy-watch, the rollback watcher the deployer starts
#   before each deploy.
# - Once the deployer's keys are committed (flake.lib.fleetDeployer.keys is
#   not null), adds its SSH key to the deploy account's authorized keys
#   (root on NixOS, flake.lib.hosts.<name>.deployUser on darwin), restricted
#   to the deployer's addresses, and on the deployer host also to loopback.
#
# The deployer reads a target's secrets through the sops group
# fleet-deployers, which is a reader of exactly what `clan machines update`
# decrypts on the deployer: the machine key and the activation-phase vars
# (design D3, option a). The group is added per file with clan's own
# `clan secrets groups add-secret` and group links, not through
# clan.core.sops.defaultGroups, which would make it a reader of every var of
# the machine and flag every existing var for `clan vars fix`.
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
          (fleetDeployer.targetKeyLine (name == fleetDeployer.deployerHost) fleetDeployer.keys.ssh)
        ];
      };
    };
in
{
  flake.modules.nixos.fleet-deploy-target = target;
  flake.modules.nixos.base.imports = [ modules.nixos.fleet-deploy-target ];

  flake.modules.darwin.fleet-deploy-target = target;
  flake.modules.darwin.base.imports = [ modules.darwin.fleet-deploy-target ];
}
