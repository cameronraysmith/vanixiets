# nix-unit invariants for flake.lib.mesh (modules/lib/mesh.nix).
#
# The vectors are computed outside Nix, so a defect in the function cannot
# move the expectation with it:
#
#   printf %s tincr-vanixiets | sha256sum | cut -c1-14   # 09836d82f83d7d
#   printf %s cinnabar | sha256sum | cut -c1-16          # 6e965884ed589f7e
#   printf %s pyrite | sha256sum | cut -c1-16            # af3e3862e89ed6d2
#
# The prefix is fd + hex 0-1, then hex 2-13 as three hextets; a host is the
# prefix plus hex 0-15 of its name's hash as four hextets.
#
# The invitation hook computes a phone's address in shell as
#
#   hash=$(printf %s "$NAME" | sha256sum | cut -c1-16)
#   echo "$network:${hash:0:4}:${hash:4:4}:${hash:8:4}:${hash:12:4}"
#
# and hookFormulaMatches reproduces that slicing over pixel7.
#
# addressesUnique covers every registry member, so two names that derive the
# same address, or an addressOf that ignores the name, fail here.
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
        name = "mesh";
        testFile = pkgs.writeText "mesh.tests.nix" ''
          let
            lib = import ${pkgs.path}/lib;
            inherit
              ((import ${./mesh.nix} {
                config.flake.lib.fleet.label = "vanixiets";
              }).flake.lib
              )
              mesh
              ;

            hash = builtins.hashString "sha256" "pixel7";
            hookAddress = "fd09:836d:82f8:3d7d:''${builtins.substring 0 4 hash}:''${builtins.substring 4 4 hash}:''${builtins.substring 8 4 hash}:''${builtins.substring 12 4 hash}";

            members = builtins.fromJSON '''${builtins.toJSON (builtins.attrNames config.flake.lib.hosts)}''';
          in
          {
            testPrefixVanixiets = {
              expr = mesh.prefixOf "vanixiets";
              expected = "fd09:836d:82f8:3d7d::/64";
            };

            testAddressCinnabar = {
              expr = mesh.addressOf "vanixiets" "cinnabar";
              expected = "fd09:836d:82f8:3d7d:6e96:5884:ed58:9f7e";
            };

            testAddressPyrite = {
              expr = mesh.addressOf "vanixiets" "pyrite";
              expected = "fd09:836d:82f8:3d7d:af3e:3862:e89e:d6d2";
            };

            testHookFormulaMatches = {
              expr = mesh.addressOf mesh.instance "pixel7";
              expected = hookAddress;
            };

            testAddressesUnique = {
              expr = lib.length (lib.unique (map (mesh.addressOf mesh.instance) members));
              expected = lib.length members;
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
        eval-mesh = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") { eval-mesh = check; };
    };
}
