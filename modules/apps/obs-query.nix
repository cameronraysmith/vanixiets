# Command-line queries to the telemetry store on magnetite (PromQL, SQL, TQL)
# as its read-only `regulator` user, whose password never leaves magnetite.
#
# ssh is deliberately absent from runtimeInputs: the operator's own client,
# with its configuration and agent, authenticates to magnetite.zt, and
# checks.x86_64-linux.obs-query substitutes a stub for it on PATH.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.obs-query = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "obs-query";
            runtimeInputs = [
              pkgs.jq
              pkgs.gawk
            ];
            text = builtins.readFile ./obs-query.sh;
          }
        );
        meta.description = "Query the telemetry store on magnetite with PromQL, SQL or TQL";
      };
    };
}
