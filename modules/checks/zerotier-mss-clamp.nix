# Structural check that the zerotier MSS clamp reaches exactly the NixOS
# members of the clan zerotier controller and peer roles, through the roles'
# extraModules (modules/clan/inventory/services/zerotier.nix). The module's
# own firewall branches and the clamp's behaviour are covered by
# vmTests.x86_64-linux.zerotier-mss-clamp-runtime. Linux hosts only, so the
# check is defined for x86_64-linux alone.
{ self, ... }:
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    let
      instance = self.clan.inventory.instances.zerotier;
      machines = self.clan.inventory.machines;
      roleMembers =
        role:
        lib.attrNames (role.machines or { })
        ++ lib.attrNames (
          lib.filterAttrs (
            _: machine: lib.any (tag: (role.tags or { }) ? ${tag}) (machine.tags or [ ])
          ) machines
        );
      members = lib.filter (name: (machines.${name}.machineClass or "nixos") == "nixos") (
        lib.unique (
          lib.concatMap roleMembers [
            instance.roles.controller
            instance.roles.peer
          ]
        )
      );
      hosts = lib.attrNames self.nixosConfigurations;
    in
    {
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        zerotier-mss-clamp = self.lib.mkStructuralCheck pkgs {
          name = "zerotier-mss-clamp";
          actual = lib.genAttrs hosts (
            name:
            lib.hasInfix "TCPMSS --set-mss 1300"
              self.nixosConfigurations.${name}.config.networking.firewall.extraCommands
          );
          expected = lib.genAttrs hosts (name: builtins.elem name members);
        };
      };
    };
}
