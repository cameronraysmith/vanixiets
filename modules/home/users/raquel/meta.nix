{ ... }:
{
  flake.users.raquel = {
    meta = {
      username = "raquel";
      fullname = "Raquel";
      email = "raquel@example.com";
      githubUser = null;
      sopsAgeKeyId = null;
    };
    aggregates = [
      "core"
      "development"
      "shell"
    ];
  };
}
