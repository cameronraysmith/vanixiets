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
    profiles = with config.flake.profiles.homeManager; [
      core
      development
      shell
      base-sops
    ];
  };
}
