# Deploy targets of the fleet deployer (openspec change
# delegate-fleet-deploys, design D3, D8, D10). Imported by every NixOS and
# darwin base; acts only on a machine in flake.lib.fleetDeployer.targets.
#
# - Installs fleet-deploy-watch, the rollback watcher the deployer starts
#   before each deploy. On darwin it also declares the watcher's launchd job
#   as data (vanixiets.fleetDeployWatch), rendered to /etc/fleet-deploy-watch:
#   `fleet-deploy-watch --arm`, run as root, bootstraps that job into the
#   domain named there. It must be launchd's system domain, so the watcher
#   runs as root whichever user armed it; a job submitted with sudo from an
#   SSH session lands in that user's domain and cannot roll back (F84).
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
# machine whose accounts carry the key, and a darwin target whose watcher job
# is not a root job in the system domain that runs the watcher once.
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

  # The darwin watcher's launchd job. Not a nix-darwin daemon: activation
  # reloads a daemon whose plist changed, which would end the watcher in the
  # middle of the deploy it watches, while a bootstrapped job is outside what
  # activation manages.
  darwinWatcher =
    { config, pkgs, ... }:
    let
      cfg = config.vanixiets.fleetDeployWatch;
      isTarget = lib.elem config.networking.hostName fleetDeployer.targets;
    in
    {
      options.vanixiets.fleetDeployWatch = {
        domain = lib.mkOption {
          type = lib.types.str;
          default = "system";
          internal = true;
          description = "The launchd domain `fleet-deploy-watch --arm` bootstraps the job into.";
        };
        job = lib.mkOption {
          type = lib.types.attrsOf lib.types.anything;
          default = { };
          internal = true;
          description = "The watcher's launchd job, written to /etc/fleet-deploy-watch/job.plist.";
        };
      };
      config = lib.mkIf isTarget {
        vanixiets.fleetDeployWatch.job = {
          Label = "org.vanixiets.fleet-deploy-watch";
          ProgramArguments = [
            (lib.getExe pkgs.fleet-deploy-watch)
            "--run"
          ];
          RunAtLoad = true;
          KeepAlive = false;
          StandardOutPath = "/var/log/fleet-deploy-watch.log";
          StandardErrorPath = "/var/log/fleet-deploy-watch.log";
        };
        environment.etc = {
          "fleet-deploy-watch/job.plist".text = lib.generators.toPlist { escape = true; } cfg.job;
          "fleet-deploy-watch/domain".text = cfg.domain;
          "fleet-deploy-watch/label".text = cfg.job.Label;
        };
      };
    };
in
{
  flake.modules.nixos.fleet-deploy-target = target;

  flake.modules.darwin.fleet-deploy-target.imports = [
    target
    darwinWatcher
  ];
  flake.modules.darwin.base.imports = [ modules.darwin.fleet-deploy-target ];
}
