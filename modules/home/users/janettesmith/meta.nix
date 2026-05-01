{ config, ... }:
{
  flake.users.janettesmith = {
    meta = {
      username = "janettesmith";
      fullname = "Janette Smith";
      email = "janettesmith@example.com";
      githubUser = null;
      sopsAgeKeyId = null;
    };
    aggregates = with config.flake.modules.homeManager; [
      base-sops
      core
      development
      packages
      shell
      terminal
      tools
      agents-md
    ];
  };
}
