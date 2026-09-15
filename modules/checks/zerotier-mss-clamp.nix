# Structural check that every NixOS member of the zerotier network carries the
# TCP MSS clamp from `flake.modules.nixos.zerotier-mss-clamp`.
#
# The clamp is attached through the clan zerotier service roles, so the set of
# hosts is derived from the inventory rather than listed here: any NixOS
# machine in the controller or peer role must render exactly four TCPMSS rules
# (IPv4/IPv6 x INPUT/OUTPUT). A host that joins the network without the clamp,
# or a role that loses its extraModules entry, changes the rendered count and
# fails the JSON diff. Darwin members run external zerotier-one and are out of
# scope.
{ self, ... }:
{
  perSystem =
    { pkgs, ... }:
    let
      lib = pkgs.lib;
      mkCheck = self.lib.mkStructuralCheck pkgs;
      instance = self.clan.inventory.instances.zerotier;
      machines = self.clan.inventory.machines;
      taggedPeers = lib.attrNames (
        lib.filterAttrs (
          _: m:
          (m.machineClass or "nixos") == "nixos"
          && lib.any (t: instance.roles.peer.tags ? ${t}) (m.tags or [ ])
        ) machines
      );
      members = lib.unique (lib.attrNames (instance.roles.controller.machines or { }) ++ taggedPeers);
      clampRules =
        host:
        builtins.length (
          builtins.filter (l: lib.hasInfix "TCPMSS --set-mss 1300" l) (
            lib.splitString "\n" self.nixosConfigurations.${host}.config.networking.firewall.extraCommands
          )
        );
    in
    {
      checks.zerotier-mss-clamp = mkCheck {
        name = "zerotier-mss-clamp";
        actual = lib.genAttrs members clampRules;
        expected = lib.genAttrs members (_: 4);
      };
    };
}
