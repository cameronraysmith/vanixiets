{ config, lib, ... }:
let
  # Enrolled 2026-11-19 with vars/shared/<worker-user>-deploy-request (CAM-115
  # task 3.3); false again would make every machine's credential-source
  # assertions drop the key.
  deployRequestEnrolled = true;
  workerCredentials =
    owner: user: labels:
    let
      meta = config.flake.users.${owner}.meta;
    in
    {
      signingKey = {
        enable = true;
        generator = "${user}-signing-key";
        file = "key";
      };
      deployRequestKey = {
        enable = deployRequestEnrolled;
        generator = "${user}-deploy-request";
        file = "key";
      };
      githubTokens = builtins.listToAttrs (
        map (owner: {
          name = owner;
          value = {
            enable = true;
            generator = "${user}-github-token-${owner}";
            file = "token";
            expectedLogin = meta.githubUser;
          };
        }) ([ "sciexp" ] ++ (if user == "omnigent-cameron" then [ "cameronraysmith" ] else [ ]))
      );
      defaultOwner = if user == "omnigent-cameron" then "cameronraysmith" else "sciexp";
      linearApiKeys = builtins.listToAttrs (
        map (label: {
          name = label;
          value = {
            enable = true;
            generator = "${user}-linear-${label}";
          };
        }) labels
      );
      expected = {
        gitEmail = meta.gitEmail;
        signingPublicKey = meta.signingKey;
        omnigentEmail = meta.email;
      };
    };
  workers = config.flake.fleet.workers;
  # Every host that runs some owner's worker (modules/lib/fleet-workers.nix).
  workerHosts = lib.unique (
    lib.concatMap (worker: lib.attrNames worker.hosts) (lib.attrValues workers)
  );
in
{
  flake.clan.inventory.instances.omnigent = {
    module = {
      name = "omnigent";
      input = "self";
    };
    roles.server.machines.magnetite.settings.domain = "omni.scientistexperience.net";
    roles.host.machines = lib.genAttrs workerHosts (host: {
      settings = {
        legacyEnable = false;
        workers = lib.mapAttrs (
          owner: worker:
          let
            user = "omnigent-${owner}";
            inherit (worker.hosts.${host}) containers;
          in
          {
            enable = true;
            inherit owner user;
            credentials = workerCredentials owner user worker.linearLabels;
          }
          // lib.optionalAttrs (containers != { }) { inherit containers; }
        ) (lib.filterAttrs (_: worker: worker.hosts ? ${host}) workers);
      };
    });
  };
}
