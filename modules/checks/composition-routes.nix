# checks.x86_64-linux.composition-routes: flake.lib.compositionRoutes
# (modules/lib/composition.nix) gives each named module in a fixture import
# tree the route of its nearest named or host ancestor, and the
# compositionRoutes judge finds one failure each for a named module under an
# unknown importer, a clan service under a label it does not know, and a
# tree without the host's own module. The fixtures are literals.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      node = file: imports: {
        key = file;
        inherit file imports;
        disabled = false;
      };
      # flake-parts' wrapper, the merged definitions, then one definition.
      named =
        class: written: defFile: imports:
        let
          via = "${defFile}, via option flake.modules.${class}.${written}";
        in
        node "/src/flake.nix#modules.${class}.${written}" [
          (node via [ (node via imports) ])
        ];
      nixos = named "nixos";
      quoted = name: "\"${name}\"";

      known = [
        (node "/src/modules/clan/machines.nix, via option flake.clan.machines.h" [
          (nixos (quoted "machines/nixos/h") "/src/modules/machines/nixos/h/default.nix" [
            (node "/nix/store/srvos-source/nixos/server.nix" [ ])
            (nixos "base" "/src/modules/nixos/base.nix" [
              (nixos "base-nix" "/src/modules/system/nix.nix" [ ])
            ])
            (nixos "foo" "/nix/store/aaaa-source/modules/nixos/foo.nix" [
              (nixos "bar" "/src/modules/nixos/bar.nix" [ ])
            ])
          ])
        ])
        (nixos (quoted "machines/nixos/h") "/src/modules/nixos/mesh-dns.nix" [
          (nixos (quoted "mesh-dns/h") "/src/modules/nixos/mesh-dns.nix" [ ])
        ])
        (node "Via s.perMachine - machine='h';" [
          (node "/src/modules/clan/services/s/flake-module.nix, via option perMachine.nixosModule" [
            (nixos "mesh-hosts" "/src/modules/system/mesh-hosts.nix" [ ])
          ])
        ])
        (node "Via instances.i.roles.r.machines.h" [
          (node "/src/modules/clan/services/s/flake-module.nix, via option perMachine.nixosModule" [
            (nixos "secrets" "/src/modules/system/secrets.nix" [ ])
          ])
        ])
        (
          (node "/src/modules/disabled.nix" [ (nixos "disabled-part" "/src/modules/nixos/d.nix" [ ]) ])
          // {
            disabled = true;
          }
        )
      ];

      unknownParent = known ++ [
        (node "/src/modules/other.nix" [ (nixos "stray" "/src/modules/nixos/stray.nix" [ ]) ])
      ];

      relabelledClan = known ++ [
        (node "Via s.perHost - machine='h';" [
          (node "/src/modules/clan/services/s/flake-module.nix, via option perHost.nixosModule" [
            (nixos "tincr-peer" "/src/modules/system/tincr.nix" [ ])
          ])
        ])
      ];

      show = map (r: "${r.name} ${r.route} ${r.parentFile}");
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      testSizes.checks.composition-routes = {
        class = "medium";
        measured = false;
      };
      checks.composition-routes = self.lib.mkJudgeCheck pkgs {
        name = "composition-routes";
        judge = case: self.lib.routeFailures "nixos" "h" case.graph;
        cases = {
          everyRouteKnown = {
            graph = known;
            problems = 0;
          };
          namedModuleUnderUnknownParent = {
            graph = unknownParent;
            problems = 1;
          };
          clanServiceRelabelled = {
            graph = relabelledClan;
            problems = 1;
          };
          labelsNoLongerMatched = {
            graph = [
              (node "/src/modules/clan/machines.nix" [ (node "/src/modules/machines/nixos/h/default.nix" [ ]) ])
            ];
            problems = 1;
          };
        };
        assertions = [
          {
            assertion =
              show (self.lib.compositionRoutes "nixos" known) == [
                "machines/nixos/h host /src/modules/clan/machines.nix"
                "base host /src/modules/machines/nixos/h/default.nix"
                "base-nix base /src/modules/nixos/base.nix"
                "foo host /src/modules/machines/nixos/h/default.nix"
                "bar include modules/nixos/foo.nix"
                "machines/nixos/h host (configuration root)"
                "mesh-dns/h generated /src/modules/nixos/mesh-dns.nix"
                "mesh-hosts clan /src/modules/clan/services/s/flake-module.nix"
                "secrets clan /src/modules/clan/services/s/flake-module.nix"
              ];
            message = "compositionRoutes gave ${builtins.toJSON (show (self.lib.compositionRoutes "nixos" known))}";
          }
          {
            assertion =
              self.lib.routeFailures "nixos" "h" unknownParent == [
                "stray reaches h from /src/modules/other.nix by no known route; its nearest unnamed importer is labelled \"/src/modules/other.nix\", and if that is a clan service, isClanService in modules/lib/composition.nix no longer matches clan-core's labels"
              ];
            message = "routeFailures gave ${
              builtins.toJSON (self.lib.routeFailures "nixos" "h" unknownParent)
            }";
          }
          {
            assertion =
              self.lib.routeFailures "nixos" "h" [ ] == [
                "machines/nixos/h is not among h's named modules; namedModule in modules/lib/composition.nix no longer matches the module system's labels"
              ];
            message = "routeFailures on an empty graph gave ${
              builtins.toJSON (self.lib.routeFailures "nixos" "h" [ ])
            }";
          }
          {
            assertion = lib.hasInfix "via option perHost.nixosModule" (
              builtins.head (self.lib.routeFailures "nixos" "h" relabelledClan)
            );
            message = "an unknown route's failure does not carry its importer's label";
          }
          {
            assertion =
              show (
                self.lib.compositionRoutes "homeManager" [
                  (named "homeManager" "core" "/src/modules/home/core/default.nix" [ ])
                ]
              ) == [ "core home (configuration root)" ];
            message = "a standalone home's direct module is not given the route home";
          }
        ];
      };
    };
}
