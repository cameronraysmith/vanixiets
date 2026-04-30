{ config, ... }:
{
  flake.users.tara = {
    meta = {
      username = "tara";
      fullname = "Tara Chari";
      email = "17519396+tarachari3@users.noreply.github.com";
      githubUser = "tarachari3";
      sopsAgeKeyId = "tara";
    };
    profiles = with config.flake.profiles.homeManager; [ core ];
  };
}
