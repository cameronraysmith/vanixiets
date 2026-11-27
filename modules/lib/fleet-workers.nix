# The Omnigent worker relation: flake.fleet.workers.<owner> declares, once,
# the hosts that run a person's Omnigent worker and the owner's Linear labels.
# Generated from it: the omnigent clan instance's host settings
# (clan/inventory/services/omnigent.nix), the fleet deployer's requesters
# (lib/fleet-deployer.nix) and, through flake.lib.workerAccountsOn, the worker
# accounts among each host's shared-reference-tree participants.
# expectedOwners (lib/omnigent-fleet-obligations.nix), hostMatrix and
# serverMatrix (checks/omnigent-workers.nix) and omnigent-acp-spawn-env's host
# list stay literal: they are what the generated inventory is judged against.
{ config, lib, ... }:
let
  inherit (lib) types;
  flakeConfig = config;
in
{
  options.flake.fleet.workers = lib.mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          linearLabels = lib.mkOption {
            type = types.listOf types.str;
            description = "The Linear workspaces the owner's worker holds an API key for.";
          };
          hosts = lib.mkOption {
            type = types.attrsOf (
              types.submodule {
                options.containers = lib.mkOption {
                  type = types.attrs;
                  default = { };
                  description = "The worker's container settings on this host; omitted from the inventory when empty.";
                };
              }
            );
            description = "The hosts that run the owner's worker.";
          };
        };
      }
    );
    apply =
      workers:
      let
        unknown = lib.filter (owner: !(flakeConfig.flake.users ? ${owner})) (lib.attrNames workers);
      in
      assert lib.assertMsg (
        unknown == [ ]
      ) "flake.fleet.workers: ${lib.concatStringsSep ", " unknown} is not a flake.users key";
      workers;
    description = "Omnigent worker owners (flake.users keys) and the hosts that run their workers.";
  };

  config.flake.fleet.workers = {
    cameron = {
      linearLabels = [
        "personal"
        "work"
      ];
      hosts = {
        magnetite.containers.engine = "rootless-podman";
        pyrite.containers = {
          engine = "rootless-podman";
          incus = "restricted";
        };
        stibnite = { };
      };
    };
    janettesmith = {
      linearLabels = [ "personal" ];
      hosts = {
        magnetite.containers.engine = "rootless-podman";
        pyrite.containers = {
          engine = "rootless-podman";
          incus = "restricted";
        };
      };
    };
  };

  # The sorted worker account names (omnigent-<owner>) on a host.
  config.flake.lib.workerAccountsOn =
    host:
    map (owner: "omnigent-${owner}") (
      lib.attrNames (lib.filterAttrs (_: worker: worker.hosts ? ${host}) config.flake.fleet.workers)
    );
}
