{ config, ... }:
{
  flake.users.crs58 = {
    meta = {
      username = "crs58";
      fullname = "Cameron Smith";
      email = "cameron.ray.smith@gmail.com";
      githubUser = "cameronraysmith";
      sopsAgeKeyId = "crs58";
    };
    profiles = with config.flake.lib.profiles.homeManager; [
      core
      development
      ai
      shell
    ];
  };
}
