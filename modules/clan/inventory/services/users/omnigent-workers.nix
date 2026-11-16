{ lib, ... }:
let
  # Each host's existing allocation from its /var/lib/nixos/uid-map, pinned
  # because rootless container access names the worker's user manager and
  # runtime directory by uid. A new host pins a free uid before first creation.
  uids = {
    magnetite = {
      omnigent-cameron = 1003;
      omnigent-janettesmith = 1004;
    };
    pyrite = {
      omnigent-cameron = 1002;
      omnigent-janettesmith = 1003;
    };
  };
in
{
  flake.clan.machines = lib.mapAttrs (
    _: hostUids:
    { pkgs, ... }:
    {
      users.users = lib.mapAttrs (user: uid: {
        inherit uid;
        isNormalUser = true;
        home = "/home/${user}";
        homeMode = "0700";
        createHome = true;
        group = user;
        extraGroups = [ ];
        hashedPassword = "!";
        shell = pkgs.bashInteractive;
      }) hostUids;
      users.groups = lib.mapAttrs (_: _: { }) hostUids;
    }
  ) uids;
}
