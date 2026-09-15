{ self, ... }:
{
  perSystem =
    { pkgs, lib, ... }:
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
      nonmembers = lib.filter (name: !(builtins.elem name members)) (
        lib.attrNames self.nixosConfigurations
      );
      commands =
        text:
        builtins.filter (line: lib.hasInfix "-t mangle -A " line || lib.hasInfix "-t mangle -D " line) (
          map lib.trim (lib.splitString "\n" text)
        );
      hooks = config: {
        start = commands config.networking.firewall.extraCommands;
        stop = commands config.networking.firewall.extraStopCommands;
      };
      expectedHooks =
        ipv6:
        let
          tools = [ "iptables" ] ++ lib.optional ipv6 "ip6tables";
          lines =
            operation:
            lib.concatMap (tool: [
              "${tool} -w 5 -t mangle ${operation} INPUT -i zt+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300 || exit $?"
              "${tool} -w 5 -t mangle ${operation} OUTPUT -o zt+ -p tcp -m tcp --tcp-flags SYN,RST SYN -j TCPMSS --set-mss 1300 || exit $?"
            ]) tools;
        in
        {
          start = lines "-D" ++ lines "-A";
          stop = lines "-D";
        };
      fixture =
        settings:
        (self.inputs.nixpkgs.lib.nixosSystem {
          system = "x86_64-linux";
          modules = [
            self.modules.nixos.zerotier-mss-clamp
            settings
          ];
        }).config;
      emptyHooks = {
        start = [ ];
        stop = [ ];
      };
    in
    {
      checks.zerotier-mss-clamp = self.lib.mkStructuralCheck pkgs {
        name = "zerotier-mss-clamp";
        actual = {
          members = lib.genAttrs members (name: hooks self.nixosConfigurations.${name}.config);
          nonmembers = lib.genAttrs nonmembers (
            name:
            lib.hasInfix "TCPMSS" self.nixosConfigurations.${name}.config.networking.firewall.extraCommands
          );
          ipv4 = hooks (fixture {
            networking.enableIPv6 = false;
          });
          disabled = hooks (fixture {
            networking.firewall.enable = false;
          });
          nftables = hooks (fixture {
            networking.nftables.enable = true;
          });
        };
        expected = {
          members = lib.genAttrs members (_: expectedHooks true);
          nonmembers = lib.genAttrs nonmembers (_: false);
          ipv4 = expectedHooks false;
          disabled = emptyHooks;
          nftables = emptyHooks;
        };
      };
    };
}
