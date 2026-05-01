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
