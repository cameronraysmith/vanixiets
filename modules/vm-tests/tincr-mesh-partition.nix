# vmTests.x86_64-linux.tincr-mesh-partition: mesh names keep resolving between
# peers while both name services of flake.lib.mesh.resolvers are down.
#
# cinnabar and magnetite run the tincr clan service and the fleet's resolver
# modules (flake.modules.nixos."mesh-dns/<name>"); pyrite and electrum run the
# service, systemd-resolved with both resolvers as their name servers, and
# the fleet's flake.modules.nixos.mesh-hosts. All four are on one vlan and
# every peer has an endpoint, so pyrite and electrum hold their own meta
# connection. After both resolvers shut down, pyrite and electrum still
# resolve each other's `<name>.vanixiets.internal` and a service name through
# glibc's getaddrinfo (resolved, which reads /etc/hosts first) and reach each
# other by name over the mesh: ICMP, and TCP to an HTTP listener.
#
# Without mesh-hosts on pyrite and electrum the names go to the stopped
# resolvers and the last subtest fails.
#
# Non-gating, like every vmTest; it requires kvm, so it builds on pyrite.
{ inputs, config, ... }:
let
  inherit (config.flake.lib) mesh hosts fleet;
  inherit (config.flake) modules;
  net = mesh.instance;
  nixosLib = import (inputs.nixpkgs + "/nixos/lib") { };
  resolverAddresses = map (name: hosts.${name}.address) mesh.resolvers;

  resolver = name: {
    imports = [ modules.nixos."mesh-dns/${name}" ];
    virtualisation.vlans = [ 1 ];
  };

  peer =
    { pkgs, ... }:
    {
      imports = [ modules.nixos.mesh-hosts ];
      virtualisation.vlans = [ 1 ];
      services.resolved.enable = true;
      networking.nameservers = resolverAddresses;
      networking.firewall.interfaces.${mesh.interface.nixos}.allowedTCPPorts = [ 8000 ];
      environment.systemPackages = [
        pkgs.curl
        pkgs.dig
        pkgs.python3
      ];
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
      # Size class: the script measured 38.60 s, 69 s for the whole build with
      # the driver already built, on pyrite on 2026-11-24
      # (logs/tsc-3-measure-tincr-mesh-partition-20261124-133626.log).
      testSizes.vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        tincr-mesh-partition.class = "small";
      };
      vmTests = lib.optionalAttrs (system == "x86_64-linux") {
        tincr-mesh-partition = nixosLib.runTest {
          imports = [ inputs.clan-core.modules.nixosTest.clanTest ];
          hostPkgs = pkgs;
          defaults._module.args.clan-core = inputs.clan-core;
          name = "tincr-mesh-partition";
          requiredFeatures = {
            kvm = true;
            nixos-test = true;
          };
          qemu.forceAccel = true;
          # As in tincr-mesh: clan-core's nixosTestLib is built against its own
          # nixpkgs, whose Python differs from this flake's; the script uses
          # none of it.
          extraPythonPackages = lib.mkForce (_: [ ]);

          clan = {
            directory = "${lib.fileset.toSource {
              root = ./.;
              fileset = ./tincr-mesh-partition.nix;
            }}";
            test.useContainers = false;
            modules.tincr = config.flake.clan.modules.tincr;
            inventory = {
              machines = lib.genAttrs [
                "cinnabar"
                "magnetite"
                "pyrite"
                "electrum"
              ] (_: { });
              instances.${net} = {
                module = {
                  name = "tincr";
                  input = "self";
                };
                roles.peer.machines =
                  lib.genAttrs
                    [
                      "cinnabar"
                      "magnetite"
                      "pyrite"
                      "electrum"
                    ]
                    (name: {
                      settings.endpoints = [ name ];
                    });
              };
            };
          };

          nodes = {
            cinnabar = resolver "cinnabar";
            magnetite = resolver "magnetite";
            pyrite = peer;
            electrum = peer;
          };

          testScript = ''
            import ipaddress

            unit = "tincr-${net}.service"
            domain = "${fleet.domain}"
            address = {
                "cinnabar": ipaddress.ip_address("${hosts.cinnabar.address}"),
                "magnetite": ipaddress.ip_address("${hosts.magnetite.address}"),
                "pyrite": ipaddress.ip_address("${hosts.pyrite.address}"),
                "electrum": ipaddress.ip_address("${hosts.electrum.address}"),
            }
            resolvers = (cinnabar, magnetite)

            def dig(node, name, server):
                return node.execute(f"dig +short +tries=1 +time=2 AAAA {name} @{address[server]}")

            def getaddrinfo(node, name):
                """The first address glibc's getaddrinfo returns for name, or None."""
                status, out = node.execute(f"getent ahostsv6 {name}")
                if status != 0 or not out.strip():
                    return None
                return ipaddress.ip_address(out.split()[0])

            start_all()
            for node in (*resolvers, pyrite, electrum):
                node.wait_for_unit(unit)
            electrum.succeed("systemd-run --unit=probe python3 -m http.server 8000 --bind ::")
            electrum.wait_for_open_port(8000)

            with subtest("the mesh is up and both resolvers answer the zone"):
                pyrite.wait_until_succeeds(f"ping -c1 -W2 {address['electrum']}", timeout=300)
                electrum.wait_until_succeeds(f"ping -c1 -W2 {address['pyrite']}", timeout=300)
                pyrite.wait_until_succeeds("tinc -n ${net} dump connections | grep -q '^electrum '", timeout=120)
                for server in ("cinnabar", "magnetite"):
                    status, out = dig(pyrite, f"electrum.{domain}", server)
                    assert status == 0 and ipaddress.ip_address(out.strip()) == address["electrum"], (server, out)

            with subtest("both resolvers go down"):
                for node in resolvers:
                    node.shutdown()
                for server in ("cinnabar", "magnetite"):
                    status, out = dig(pyrite, f"electrum.{domain}", server)
                    assert status != 0, (server, out)

            with subtest("peers resolve each other's names and connect without a resolver"):
                for node, other in ((pyrite, "electrum"), (electrum, "pyrite")):
                    got = getaddrinfo(node, f"{other}.{domain}")
                    assert got == address[other], (node.name, other, got)
                    node.succeed(f"ping -c1 -W2 {other}.{domain}")
                got = getaddrinfo(pyrite, f"ntfy.{domain}")
                assert got == address["cinnabar"], ("ntfy", got)
                pyrite.succeed(f"curl -sf --max-time 10 -o /dev/null http://electrum.{domain}:8000/")
          '';
        };
      };
    };
}
