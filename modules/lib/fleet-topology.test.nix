# nix-unit cases for flake.lib.mkFleetTopology (modules/lib/fleet-topology.nix)
# over a literal four-machine fixture, so a defect in the function cannot
# move the expectation with it. Each case pins one failure mode the
# freshness check (modules/checks/fleet-topology.nix) cannot isolate: user
# tag resolution, the `all` tag, a role naming a machine outside the
# inventory, a tag nobody carries, tincr devices declared inside nested
# deferred-module imports, ZeroTier external members matched by address, an
# unmatched address, an unknown facts key, the `on every host` legend, the
# line-per-entry fleet.json, the public-hostname edges and the table row.
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
        name = "fleet-topology";
        testFile = pkgs.writeText "fleet-topology.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
            inherit
              ((import ${./fleet-topology.nix} {
                inherit lib;
                config = {
                  flake.clan.inventory = { };
                  flake.lib = {
                    hosts = { };
                    topologyFacts = { };
                  };
                };
              }).flake.lib
              )
              mkFleetTopology
              ;

            inventory = {
              machines = {
                a = { machineClass = "nixos"; tags = [ "peer" ]; };
                b = { machineClass = "nixos"; tags = [ "peer" ]; };
                c = { machineClass = "darwin"; tags = [ ]; };
                d = { machineClass = "nixos"; tags = [ ]; };
              };
              instances = {
                everywhere = {
                  module.name = "e";
                  roles.default.tags.all = { };
                };
                tagged = {
                  module.name = "t";
                  roles.peer = {
                    tags.peer = { };
                    machines = { a = { }; ghost = { }; };
                  };
                  roles.none.tags.nobody = { };
                };
                vanixiets = {
                  module.name = "tincr";
                  roles.peer = {
                    machines = { a = { }; b = { }; c = { }; };
                    settings.imports = [
                      {
                        _file = "fixture";
                        imports = [ { devices.phone.publicKey = "k"; } ];
                      }
                    ];
                  };
                };
                zerotier = {
                  module.name = "zerotier";
                  roles.controller.machines.d.settings.allowedIps = [ "fd00::c" ];
                  roles.peer.tags.peer = { };
                };
              };
            };

            hosts = {
              a = { endpoints = [ "a.example.net" ]; zerotier.address = "fd00::a"; };
              b = { endpoints = [ ]; zerotier.address = "fd00::b"; };
              c = { endpoints = [ ]; zerotier.address = "fd00::c"; };
              d = { endpoints = [ ]; zerotier.address = "fd00::d"; };
              phone = { endpoints = [ ]; zerotier.address = "fd00::e"; };
            };

            facts.d.services = [
              {
                name = "web";
                hostnames = [ "web.example.net" ];
                ports = [ 443 ];
              }
            ];

            t = mkFleetTopology { inherit inventory hosts facts; };
            count = needle: haystack: builtins.length (lib.splitString needle haystack) - 1;
          in
          {
            testTagResolution = {
              expr = t.model.instances.tagged.roles.peer;
              expected = [ "a" "b" ];
            };

            testAll = {
              expr = t.model.instances.everywhere.roles.default;
              expected = [ "a" "b" "c" "d" ];
            };

            testAbsentMachine = {
              expr = builtins.elem "ghost" t.model.instances.tagged.roles.peer;
              expected = false;
            };

            testNoMemberTag = {
              expr = t.model.instances.tagged.roles.none;
              expected = [ ];
            };

            testDevices = {
              expr = t.model.networks.vanixiets.members;
              expected = { a = "peer"; b = "peer"; c = "peer"; phone = "device"; };
            };

            testExternal = {
              expr = t.model.networks.zerotier.members;
              expected = { a = "peer"; b = "peer"; c = "external"; d = "controller"; };
            };

            testUnmatchedAddress = {
              expr =
                (mkFleetTopology {
                  inherit hosts facts;
                  inventory = lib.recursiveUpdate inventory {
                    instances.zerotier.roles.controller.machines.d.settings.allowedIps = [ "fd00::9" ];
                  };
                }).files."network.d2";
              expectedError.type = "ThrownError";
              expectedError.msg = "fd00::9";
            };

            testUnknownFactsKey = {
              expr =
                (mkFleetTopology {
                  inherit inventory hosts;
                  facts.ghost.services = [ ];
                }).files."fleet.json";
              expectedError.type = "ThrownError";
              expectedError.msg = "topologyFacts key ghost";
            };

            testEveryHost = {
              expr = {
                inherit (t.model) everyHost;
                inFleetView = count "\"everywhere/default\"" t.files."fleet.d2";
              };
              expected = {
                everyHost = [ "everywhere/default" ];
                inFleetView = 1;
              };
            };

            testJsonLines = {
              expr = t.files."fleet.json";
              expected = lib.concatStringsSep "\n" [
                "{"
                "  \"facts/d\": {\"services\":[{\"hostnames\":[\"web.example.net\"],\"name\":\"web\",\"ports\":[443]}]},"
                "  \"instance/everywhere\": {\"module\":\"e\",\"roles\":{\"default\":[\"a\",\"b\",\"c\",\"d\"]}},"
                "  \"instance/tagged\": {\"module\":\"t\",\"roles\":{\"none\":[],\"peer\":[\"a\",\"b\"]}},"
                "  \"instance/vanixiets\": {\"module\":\"tincr\",\"roles\":{\"peer\":[\"a\",\"b\",\"c\"]}},"
                "  \"instance/zerotier\": {\"module\":\"zerotier\",\"roles\":{\"controller\":[\"d\"],\"peer\":[\"a\",\"b\"]}},"
                "  \"machine/a\": {\"class\":\"nixos\",\"description\":null,\"tags\":[\"peer\"]},"
                "  \"machine/b\": {\"class\":\"nixos\",\"description\":null,\"tags\":[\"peer\"]},"
                "  \"machine/c\": {\"class\":\"darwin\",\"description\":null,\"tags\":[]},"
                "  \"machine/d\": {\"class\":\"nixos\",\"description\":null,\"tags\":[]},"
                "  \"network/vanixiets\": {\"members\":{\"a\":\"peer\",\"b\":\"peer\",\"c\":\"peer\",\"phone\":\"device\"},\"module\":\"tincr\"},"
                "  \"network/zerotier\": {\"members\":{\"a\":\"peer\",\"b\":\"peer\",\"c\":\"external\",\"d\":\"controller\"},\"module\":\"zerotier\"}"
                "}"
                ""
              ];
            };

            testPublicEdges = {
              expr = map (line: lib.hasInfix line t.files."network.d2") [
                "internet -> m_a: \"a.example.net\""
                "internet -> m_d: \"web.example.net\""
                "m_phone -> net_vanixiets: \"device\""
              ];
              expected = [ true true true ];
            };

            testTableRow = {
              expr = lib.hasInfix "| d | nixos | zerotier/controller | web | zerotier (controller) |" t.files."fleet-table.md";
              expected = true;
            };
          }
        '';
      };
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 1 run, too few to class (design D4)
        eval-fleet-topology = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { eval-fleet-topology = check; };
    };
}
