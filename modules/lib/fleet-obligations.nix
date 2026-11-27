# The fleet's host judges, each registered once in the module that defines
# its flake.lib export (register-fleet-obligations design D1). Every machine
# check (modules/checks/machines.nix) folds the entries whose `classes`
# contain its configuration's class and fails naming each unmet judge.
# Adding a judge is its registration here plus its key in machines.nix's
# literal key list. This is a flake-parts option, not a flake output:
# flake.lib is lazyAttrsOf raw, so a key defined from twelve files would
# collide there, and nothing outside the machine checks calls the judges
# through it.
{ lib, ... }:
let
  inherit (lib) types;
in
{
  options.fleetObligations = lib.mkOption {
    type = types.attrsOf (
      types.submodule {
        options = {
          classes = lib.mkOption {
            type = types.nonEmptyListOf (
              types.enum [
                "nixos"
                "darwin"
              ]
            );
            default = [
              "nixos"
              "darwin"
            ];
            description = "The configuration classes whose machine checks assert this judge.";
          };
          failures = lib.mkOption {
            type = types.functionTo (types.functionTo (types.listOf types.str));
            description = "The judge: `name: hostConfig: [ message ]`, empty when the host meets it.";
          };
        };
      }
    );
    default = { };
    description = "Host judges asserted by the machine checks, keyed by the name their messages carry.";
  };
}
