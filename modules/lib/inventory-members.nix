# flake.lib.inventoryMembers instance role: the machines clan deploys a
# service role to, read from the declared inventory alone. A machine is a
# member when the role names it under `machines`, or when it carries one of
# the role's `tags`, where `all` matches every inventory machine. This is
# clan-core's own rule (lib/inventory/default.nix `resolveTags`, applied in
# modules/clan/distributed-services.nix, at the locked revision 78d5de23;
# world assumption A302), restated so that no reader forces clan's inventory
# evaluation or a machine configuration. The result is sorted and unique.
#
# flake.lib.inventoryMembersIn machines instance role takes the inventory
# machines as an argument, for fleet-topology's fixtures.
# checks.x86_64-linux.eval-inventory-members (inventory-members.test.nix)
# tests it over a literal fixture.
{ config, lib, ... }:
let
  namesOf = x: if builtins.isList x then x else builtins.attrNames x;

  inventoryMembersIn =
    machines: instance: role:
    let
      r = instance.roles.${role} or { };
      tags = namesOf (r.tags or { });
      byTag = builtins.filter (
        name:
        lib.elem "all" tags || lib.any (tag: lib.elem tag (namesOf (machines.${name}.tags or [ ]))) tags
      ) (builtins.attrNames machines);
    in
    lib.sort lib.lessThan (lib.unique (byTag ++ namesOf (r.machines or { })));
in
{
  flake.lib = {
    inherit inventoryMembersIn;
    inventoryMembers = inventoryMembersIn config.flake.clan.inventory.machines;
  };
}
