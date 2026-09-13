{ config, ... }:
let
  janetteAuthor = {
    name = config.flake.users.janettesmith.meta.fullname;
    email = config.flake.users.janettesmith.meta.gitEmail;
  };
  workerCredentials = user: meta: {
    signingKey = {
      enable = true;
      generator = "${user}-signing-key";
      file = "key";
    };
    githubToken = {
      enable = true;
      generator = "${user}-github-token";
      file = "token";
    };
    expected = {
      githubUser = meta.githubUser;
      gitEmail = meta.gitEmail;
      signingPublicKey = builtins.head meta.sshKeys;
      omnigentEmail = meta.email;
    };
  };
in
{
  clan.inventory.instances.omnigent = {
    module = {
      name = "omnigent";
      input = "self";
    };
    roles.server.machines.magnetite.settings.domain = "omni.scientistexperience.net";
    roles.host = {
      machines.magnetite.settings = {
        environment = {
          PI_ACP_PI_COMMAND = "atomic";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
        };
        workers = {
          cameron = {
            enable = false;
            owner = "cameron";
            user = "omnigent-cameron";
            credentials = workerCredentials "omnigent-cameron" config.flake.users.crs58.meta;
          };
          janettesmith = {
            enable = false;
            owner = "janettesmith";
            user = "omnigent-janettesmith";
            credentials = workerCredentials "omnigent-janettesmith" config.flake.users.janettesmith.meta;
          };
        };
      };
      machines.pyrite.settings = {
        environment = {
          PI_ACP_PI_COMMAND = "atomic";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
        };
        workers = {
          cameron = {
            enable = false;
            owner = "cameron";
            user = "omnigent-cameron";
            credentials = workerCredentials "omnigent-cameron" config.flake.users.crs58.meta;
          };
          janettesmith = {
            enable = false;
            owner = "janettesmith";
            user = "omnigent-janettesmith";
            credentials = workerCredentials "omnigent-janettesmith" config.flake.users.janettesmith.meta;
          };
        };
      };
      machines.stibnite.settings = {
        environment = {
          PI_ACP_PI_COMMAND = "atomic";
          OMNIGENT_RUNNER_ENV_PASSTHROUGH = "PI_ACP_PI_COMMAND,PI_CODING_AGENT_DIR";
        };
        workers.cameron = {
          enable = false;
          owner = "cameron";
          user = "omnigent-cameron";
          credentials = workerCredentials "omnigent-cameron" config.flake.users.crs58.meta;
        };
      };
      extraModules = [
        (
          { config, lib, ... }:
          {
            services.omnigent-host.environment.PI_CODING_AGENT_DIR = "${
              config.users.users.${config.services.omnigent-host.user}.home
            }/.atomic/agent";
            services.omnigent-host.workers =
              lib.mkIf
                (builtins.elem config.networking.hostName [
                  "magnetite"
                  "pyrite"
                ])
                {
                  janettesmith.extraHomeModules = [
                    {
                      programs.git.settings.user = janetteAuthor;
                      programs.jujutsu.settings.user = janetteAuthor;
                    }
                  ];
                };
          }
        )
      ];
    };
  };
}
