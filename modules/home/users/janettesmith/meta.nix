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
    profiles = with config.flake.lib.profiles.homeManager; [ core ];
  };
}
