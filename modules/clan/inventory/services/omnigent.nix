{ config, ... }:
let
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
        signingPublicKey = builtins.head meta.sshKeys;
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
        environment = {
          PI_ACP_PI_COMMAND = "atomic";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
        };
        workers = {
          cameron = {
            enable = true;
            owner = "cameron";
            user = "omnigent-cameron";
            credentials = workerCredentials "cameron" "omnigent-cameron" [
              "personal"
              "work"
            ];
          };
          janettesmith = {
            enable = true;
            owner = "janettesmith";
            user = "omnigent-janettesmith";
            credentials = workerCredentials "janettesmith" "omnigent-janettesmith" [
              "personal"
            ];
          };
        };
      };
      machines.pyrite.settings = {
        legacyEnable = false;
        environment = {
          PI_ACP_PI_COMMAND = "atomic";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
        };
        workers = {
          cameron = {
            enable = true;
            owner = "cameron";
            user = "omnigent-cameron";
            credentials = workerCredentials "cameron" "omnigent-cameron" [
              "personal"
              "work"
            ];
          };
          janettesmith = {
            enable = true;
            owner = "janettesmith";
            user = "omnigent-janettesmith";
            credentials = workerCredentials "janettesmith" "omnigent-janettesmith" [
              "personal"
            ];
          };
        };
      };
      machines.stibnite.settings = {
        legacyEnable = false;
        environment = {
          PI_ACP_PI_COMMAND = "atomic";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
        };
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
      extraModules = [
        (
          { config, ... }:
          {
            services.omnigent-host.environment.PI_CODING_AGENT_DIR = "${
              config.users.users.${config.services.omnigent-host.user}.home
            }/.atomic/agent";
          }
        )
      ];
    };
  };
}
