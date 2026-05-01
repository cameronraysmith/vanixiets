{ config, ... }:
{
  flake.users.raquel = {
    meta = {
      username = "raquel";
      fullname = "Raquel";
      email = "raquel@example.com";
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
