# nix-unit cases for flake.lib.inventoryMembersIn (modules/lib/inventory-members.nix)
# over a literal four-machine fixture, so a defect in the function cannot
# move the expectation with it: a role's named members, its tagged members,
# the `all` tag, a role with neither, and a machine both named and tagged
# listed once.
{ config, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      check = config.flake.lib.mkEvalCheck pkgs {
        name = "inventory-members";
        testFile = pkgs.writeText "inventory-members.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
            inherit
              ((import ${./inventory-members.nix} {
                inherit lib;
                config.flake.clan.inventory.machines = { };
              }).flake.lib
              )
              inventoryMembersIn
              ;

            machines = {
              a = { tags = [ "peer" ]; };
              b = { tags = [ "peer" "gpu" ]; };
              c = { tags = [ ]; };
              d = { };
            };

            instance.roles = {
              named.machines = { d = { }; c = { }; };
              tagged.tags = { gpu = { }; peer = { }; };
              everywhere.tags.all = { };
              empty = { };
              both = {
                machines = { a = { }; };
                tags.peer = { };
              };
            };

            members = inventoryMembersIn machines instance;
          in
          {
            testNamed = {
              expr = members "named";
              expected = [ "c" "d" ];
            };

            testTagged = {
              expr = members "tagged";
              expected = [ "a" "b" ];
            };

            testAll = {
              expr = members "everywhere";
              expected = [ "a" "b" "c" "d" ];
            };

            testNeither = {
              expr = members "empty";
              expected = [ ];
            };

            testDeduplicated = {
              expr = members "both";
              expected = [ "a" "b" ];
            };
          }
        '';
      };
    in
    {
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # no nixbot run yet (modules/README.md: an unmeasured check is medium)
        eval-inventory-members = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { eval-inventory-members = check; };
    };
}
