{ config, ... }:
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
in
{
  flake.clan.inventory.instances.omnigent = {
    module = {
      name = "omnigent";
      input = "self";
    };
    roles.server.machines.magnetite.settings.domain = "omni.scientistexperience.net";
    roles.host = {
      machines.magnetite.settings = {
        legacyEnable = false;
        workers = {
          cameron = {
            enable = true;
            owner = "cameron";
            user = "omnigent-cameron";
            credentials = workerCredentials "cameron" "omnigent-cameron" [
              "personal"
              "work"
            ];
            containers.engine = "rootless-podman";
          };
          janettesmith = {
            enable = true;
            owner = "janettesmith";
            user = "omnigent-janettesmith";
            credentials = workerCredentials "janettesmith" "omnigent-janettesmith" [
              "personal"
            ];
            containers.engine = "rootless-podman";
          };
        };
      };
      machines.pyrite.settings = {
        legacyEnable = false;
        workers = {
          cameron = {
            enable = true;
            owner = "cameron";
            user = "omnigent-cameron";
            credentials = workerCredentials "cameron" "omnigent-cameron" [
              "personal"
              "work"
            ];
            containers = {
              engine = "rootless-podman";
              incus = "restricted";
            };
          };
          janettesmith = {
            enable = true;
            owner = "janettesmith";
            user = "omnigent-janettesmith";
            credentials = workerCredentials "janettesmith" "omnigent-janettesmith" [
              "personal"
            ];
            containers = {
              engine = "rootless-podman";
              incus = "restricted";
            };
          };
        };
      };
      machines.stibnite.settings = {
        legacyEnable = false;
        workers.cameron = {
          enable = true;
          owner = "cameron";
          user = "omnigent-cameron";
          credentials = workerCredentials "cameron" "omnigent-cameron" [
            "personal"
            "work"
          ];
        };
      };
    };
  };
}
