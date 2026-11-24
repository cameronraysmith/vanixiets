# checks.x86_64-linux.fleet-topology-fresh: the codegen drift check of the
# fleet map (openspec change diagram-fleet-topology, D6). It diffs each file
# committed under packages/docs/diagrams/topology/ against the string
# flake.lib.fleetTopology.files produces now, printing the stale file and the
# command that fixes it, then runs `d2 validate` on both committed views.
#
# The attribute name is a literal, so listing checks forces nothing; the
# value evaluates only the declared clan inventory, flake.lib.hosts and
# flake.lib.topologyFacts, never a host configuration. The derivation is the
# same on every system, so it exists on x86_64-linux only. Its source is the
# topology directory alone, so an unrelated file change does not rebuild it.
{ self, lib, ... }:
{
  perSystem =
    { pkgs, system, ... }:
    let
      inherit (self.lib.fleetTopology) files;
      dir = ../../packages/docs/diagrams/topology;
      committed = lib.fileset.toSource {
        root = dir;
        fileset = dir;
      };
      generated = pkgs.linkFarm "fleet-topology-generated" (
        lib.mapAttrsToList (name: text: {
          inherit name;
          path = pkgs.writeText name text;
        }) files
      );
    in
    {
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: 0 runs, too few to class (design D4)
        fleet-topology-fresh = {
          class = "medium";
          measured = false;
        };
      };
      checks = lib.optionalAttrs (system == "x86_64-linux") {
        fleet-topology-fresh =
          pkgs.runCommand "fleet-topology-fresh"
            {
              nativeBuildInputs = [ pkgs.d2 ];
              names = lib.attrNames files;
            }
            ''
              fail=0
              for name in $names; do
                if ! diff -u "${committed}/$name" "${generated}/$name"; then
                  echo "fleet-topology: packages/docs/diagrams/topology/$name is stale; run just topology-generate" >&2
                  fail=1
                fi
              done
              extra=$(cd "${committed}" && for f in *; do [ -e "${generated}/$f" ] || echo "$f"; done)
              if [ -n "$extra" ]; then
                echo "fleet-topology: packages/docs/diagrams/topology/ holds files the generator does not produce: $extra" >&2
                fail=1
              fi
              export HOME="$TMPDIR"
              for view in fleet.d2 network.d2; do
                d2 validate "${committed}/$view" || {
                  echo "fleet-topology: $view is not valid D2" >&2
                  fail=1
                }
              done
              [ "$fail" = 0 ]
              touch "$out"
            '';
      };
    };
}
