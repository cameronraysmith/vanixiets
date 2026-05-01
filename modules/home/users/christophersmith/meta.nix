{ config, ... }:
{
  flake.users.christophersmith = {
    meta = {
      username = "christophersmith";
      fullname = "Christopher Smith";
      email = "christophersmith@example.com";
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
