{
  config,
  lib,
  ...
}:
{
  flake.modules.darwin.users =
    { pkgs, ... }:
    {
      # Test admin user
      users.users.testuser = {
        uid = 550; # Darwin UID range starts at 550 per clan-infra pattern
        home = "/Users/testuser";
        shell = pkgs.zsh;
        description = "Test Darwin User";
      };

      # Root user with zsh (bash breaks SSH on darwin per research)
      users.users.root = {
        uid = 0;
        home = "/var/root";
        shell = pkgs.zsh;
      };

      # Darwin requires explicit knownUsers
      users.knownUsers = [
        "root"
        "testuser"
      ];
    };
}
