# vmTests.x86_64-linux.tincr-mesh: the clan service `tincr` on QEMU nodes named
# after fleet members, so their addresses and names are the registry's.
# cinnabar is public (vlan 1) and answers the zone through the fleet's own
# resolver module, flake.modules.nixos."mesh-dns/cinnabar"; pyrite and electrum
# sit behind separate MASQUERADE gateways (vlans 2 and 3) on the pattern of
# tincr's nix/nixos-test-nat.nix, knowing only cinnabar's endpoint. mallory, on
# vlan 1, runs tincr with a key no host file declares and claims pyrite's
# address; electrum's own host file additionally claims magnetite's address, a
# subnet no peer's copy of electrum's host file grants.
#
# The clan test harness generates every machine's tincr-vanixiets var with the
# service's generator, so the connections prove tincr loads the keys that
# generator writes.
#
# Non-gating, like every vmTest; it requires kvm, so it builds on pyrite.
{ inputs, config, ... }:
let
  inherit (config.flake.lib) mesh hosts;
  net = mesh.instance;
  nixosLib = import (inputs.nixpkgs + "/nixos/lib") { };
  snakeoil = import (inputs.tincr + "/nix/snakeoil-keys.nix");
  forgedSubnet = hosts.magnetite.address;

  gateway = lanVlan: {
    virtualisation.vlans = [
      1
      lanVlan
    ];
    # The firewall stays on, dropping unsolicited inbound as a home router
    # does. With it off, a probe from the other NAT that arrives first is
    # accepted by the gateway itself, its conntrack entry takes the gateway's
    # port 655, and the leaf's mapping moves to another port, so the punch
    # aims at a port that is never mapped (seen: 655 remapped to 680, 946,
    # 1007).
    networking = {
      useDHCP = false;
      nat = {
        enable = true;
        externalInterface = "eth1";
        internalInterfaces = [ "eth2" ];
      };
    };
  };

  behind =
    gatewayName: lanVlan:
    { nodes, pkgs, ... }:
    {
      virtualisation.vlans = [ lanVlan ];
      networking = {
        useDHCP = false;
        defaultGateway = {
          address = (builtins.head nodes.${gatewayName}.networking.interfaces.eth2.ipv4.addresses).address;
          interface = "eth1";
        };
      };
      environment.systemPackages = [ pkgs.dig ];
    };
in
{
  perSystem =
    {
      pkgs,
      lib,
      system,
      ...
    }:
    {
      # Size class: the script measured 267.74 and 269.94 s on 2026-11-18
      # (logs/f34-vmtest-seq-dualstack-20261118-032609.log).
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        tincr-mesh.class = "medium";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        tincr-mesh = nixosLib.runTest {
          imports = [ inputs.clan-core.modules.nixosTest.clanTest ];
          hostPkgs = pkgs;
          defaults._module.args.clan-core = inputs.clan-core;
          name = "tincr-mesh";
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          # The harness adds clan-core's nixosTestLib, built against clan-core's
          # own nixpkgs, whose Python differs from this flake's; the script
          # uses none of it.
          extraPythonPackages = lib.mkForce (_: [ ]);

          clan = {
            directory = "${lib.fileset.toSource {
              root = ./.;
              fileset = ./tincr-mesh.nix;
            }}";
            test.useContainers = false;
            modules.tincr = config.flake.clan.modules.tincr;
            inventory = {
              machines = lib.genAttrs [
                "cinnabar"
                "pyrite"
                "electrum"
                "natpyrite"
                "natelectrum"
                "mallory"
                "pixel11"
              ] (_: { });
              instances.${net} = {
                module = {
                  name = "tincr";
                  input = "self";
                };
                roles.peer.machines = {
                  cinnabar.settings.endpoints = [ "cinnabar" ];
                  pyrite = { };
                  electrum = { };
                };
              };
            };
          };

          nodes = {
            cinnabar = {
              imports = [ config.flake.modules.nixos."mesh-dns/cinnabar" ];
              virtualisation.vlans = [ 1 ];
            };
            natpyrite = gateway 2;
            natelectrum = gateway 3;
            pyrite = behind "natpyrite" 2;
            electrum = {
              imports = [ (behind "natelectrum" 3) ];
              services.tincr.networks.${net}.hosts.electrum = "Subnet = ${forgedSubnet}/128";
            };
            mallory =
              { nodes, ... }:
              {
                imports = [ inputs.tincr.nixosModules.tincr ];
                virtualisation.vlans = [ 1 ];
                services.tincr.networks.${net} = {
                  nodeName = "mallory";
                  ed25519PrivateKeyFile = "/etc/tincr-mallory/ed25519_key.priv";
                  connectTo = [ "cinnabar" ];
                  hosts = {
                    mallory = ''
                      Subnet = ${hosts.pyrite.address}/128
                      Ed25519PublicKey = ${snakeoil.gamma.ed25519Public}
                    '';
                    inherit (nodes.cinnabar.services.tincr.networks.${net}.hosts) cinnabar;
                  };
                };
                environment.etc."tincr-mallory/ed25519_key.priv" = {
                  text = snakeoil.gamma.ed25519Private;
                  mode = "0400";
                };
              };
            pixel11 =
              { nodes, ... }:
              {
                virtualisation.vlans = [ 1 ];
                environment.systemPackages = [ nodes.cinnabar.services.tincr.package ];
              };
          };

          testScript = ''
            import ipaddress
            import time

            unit = "tincr-${net}.service"
            address = {
                "cinnabar": ipaddress.ip_address("${hosts.cinnabar.address}"),
                "pyrite": ipaddress.ip_address("${hosts.pyrite.address}"),
                "electrum": ipaddress.ip_address("${hosts.electrum.address}"),
                "pixel11": ipaddress.ip_address("${hosts.pixel11.address}"),
            }
            forged = ipaddress.ip_address("${forgedSubnet}")

            def subnets(node):
                """(address, owner) for every host subnet the node routes."""
                rows = []
                for line in node.succeed("tinc -n ${net} dump subnets").splitlines():
                    subnet, _, owner = line.partition(" owner ")
                    network = ipaddress.ip_network(subnet.split("#")[0])
                    if network.prefixlen == network.max_prefixlen:
                        rows.append((network.network_address, owner.strip()))
                return rows

            start_all()
            for node in (natpyrite, natelectrum):
                node.wait_for_unit("multi-user.target")
            for node in (cinnabar, pyrite, electrum, mallory):
                node.wait_for_unit(unit)
            pyrite.wait_until_succeeds("ping -4 -c1 -W2 cinnabar", timeout=120)
            pyrite.fail("ping -4 -c1 -W1 electrum")

            with subtest("members reach each other over the mesh with generated keys"):
                pyrite.wait_until_succeeds(f"ping -c1 -W2 {address['cinnabar']}", timeout=300)
                pyrite.wait_until_succeeds(f"ping -c1 -W2 {address['electrum']}", timeout=300)
                electrum.wait_until_succeeds(f"ping -c1 -W2 {address['pyrite']}", timeout=300)

            with subtest("the NATed members reach each other directly by UDP"):
                deadline = time.monotonic() + 300
                while True:
                    info = {
                        "pyrite": pyrite.succeed("tinc -n ${net} info electrum"),
                        "electrum": electrum.succeed("tinc -n ${net} info pyrite"),
                    }
                    if all("directly with UDP" in out for out in info.values()):
                        break
                    if time.monotonic() > deadline:
                        for gw in (natpyrite, natelectrum):
                            gw.execute("cat /proc/net/nf_conntrack >&2")
                        for node in (cinnabar, pyrite, electrum):
                            node.execute("tinc -n ${net} dump nodes >&2; ss -uanp >&2")
                        raise AssertionError(f"no direct UDP path: {info}")
                    pyrite.succeed(f"ping -c1 -W2 {address['electrum']}")
                    time.sleep(5)

            with subtest("the zone answers a member and a service name"):
                def aaaa(name):
                    out = pyrite.succeed(f"dig +short +tries=3 +time=5 AAAA {name} @{address['cinnabar']}").strip()
                    return ipaddress.ip_address(out)
                assert aaaa("electrum.${config.flake.lib.fleet.domain}") == address["electrum"]
                assert aaaa("ntfy.${config.flake.lib.fleet.domain}") == address["cinnabar"]

            with subtest("an undeclared key is refused at authentication"):
                cinnabar.wait_until_succeeds(f"journalctl -u {unit} | grep -q 'unknown identity'", timeout=300)
                for node in (cinnabar, pyrite, electrum):
                    owners = {owner for subnet, owner in subnets(node) if subnet == address["pyrite"]}
                    assert owners == {"pyrite"}, (node.name, owners)
                    assert "mallory" not in node.succeed("tinc -n ${net} dump nodes")

            with subtest("StrictSubnets: a declared node's undeclared subnet is ignored"):
                assert (forged, "electrum") in subnets(electrum), subnets(electrum)
                for node in (cinnabar, pyrite):
                    claimed = [owner for subnet, owner in subnets(node) if subnet == forged]
                    assert claimed == [], (node.name, claimed)

            with subtest("the invitation hook hands a device its derived address"):
                cinnabar.succeed("runuser -u tincr -- tinc -n ${net} invite pixel11")
                section = "/^Name = pixel11$/,/^Name = /{s/^Subnet = //p}"
                granted = cinnabar.succeed(f"cat /var/lib/tincr/${net}/invitations/* | sed -n '{section}'").split()
                assert [ipaddress.ip_network(s).network_address for s in granted] == [address["pixel11"]], granted

            with subtest("a device joins by invitation and cinnabar routes its address under StrictSubnets"):
                url = cinnabar.succeed("runuser -u tincr -- tinc -n ${net} invite pixel11").strip()
                pixel11.succeed(f"tinc -c /var/lib/pixel11 join {url} < /dev/null")
                pixel11.succeed("systemd-run --unit=tincd-pixel11 tincd -c /var/lib/pixel11 -D")
                cinnabar.wait_until_succeeds("grep -q '^Subnet' /var/lib/tincr/${net}/hosts/pixel11", timeout=60)
                # A redeploy restarts tincd (restartTriggers), which is when
                # StrictSubnets reads host files.
                cinnabar.systemctl(f"restart {unit}")
                cinnabar.wait_for_unit(unit)

                def routed(_: bool) -> bool:
                    reachable = cinnabar.succeed("tinc -n ${net} dump reachable nodes")
                    return "pixel11 " in reachable and (address["pixel11"], "pixel11") in subnets(cinnabar)

                retry(routed, timeout_seconds=120)
          '';
        };
      };
    };
}
