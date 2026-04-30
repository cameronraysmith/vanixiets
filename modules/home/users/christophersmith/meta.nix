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
    profiles = with config.flake.profiles.homeManager; [
      core
      base-sops
    ];
  };
}
