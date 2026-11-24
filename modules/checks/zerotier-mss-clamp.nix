# Structural check that the zerotier MSS clamp reaches exactly the NixOS
# members of the clan zerotier controller and peer roles, through the roles'
# extraModules (modules/clan/inventory/services/zerotier.nix), and that each
# member carries the variant for its own firewall backend and no other. The
# clamp's behaviour on each backend is covered by
# vmTests.x86_64-linux.zerotier-mss-clamp-runtime{,-nftables}. Linux hosts
# only, so the check is defined for x86_64-linux alone.
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
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 8.6 s, slowest 66 s, all 9 runs 2026-09-17..2026-11-11
        zerotier-mss-clamp.class = "small";
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        zerotier-mss-clamp = self.lib.mkStructuralCheck pkgs {
          name = "zerotier-mss-clamp";
          actual = lib.genAttrs hosts (
            name:
            let
              cfg = self.nixosConfigurations.${name}.config.networking;
              table = cfg.nftables.tables.zerotier-mss-clamp or null;
            in
            lib.optional (lib.hasInfix "TCPMSS --set-mss 1300" cfg.firewall.extraCommands) "iptables"
            ++ lib.optional (
              cfg.nftables.enable
              && table != null
              && table.enable
              && lib.hasInfix "maxseg size set 1300" table.content
            ) "nftables"
          );
          expected = lib.genAttrs hosts (
            name:
            lib.optional (builtins.elem name members) (
              if self.nixosConfigurations.${name}.config.networking.nftables.enable then
                "nftables"
              else
                "iptables"
            )
          );
        };
      };
    };
}
