{ lib, ... }:
{
  clan.machines = lib.genAttrs [ "magnetite" "pyrite" ] (
    _:
    { pkgs, ... }:
    {
      users.users = lib.genAttrs [ "omnigent-cameron" "omnigent-janettesmith" ] (user: {
        isNormalUser = true;
        home = "/home/${user}";
        homeMode = "0700";
        createHome = true;
        group = user;
        extraGroups = [ ];
        hashedPassword = "!";
        shell = pkgs.bashInteractive;
      });
      users.groups = lib.genAttrs [ "omnigent-cameron" "omnigent-janettesmith" ] (_: { });
    }
  );
}
