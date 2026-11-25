# Maps the PIDs agent://peers reports to the omp session each one is on, by
# joining omp's per-process logs to its session files under ~/.omp.
#
# ps and lsof come from the host on darwin: nixpkgs' procps there lacks ps,
# and the system lsof is the one entitled to read other processes' cwd.
{ ... }:
{
  perSystem =
    { pkgs, lib, ... }:
    {
      apps.omp-peers = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "omp-peers";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.findutils
              pkgs.gawk
              pkgs.gnugrep
              pkgs.gnused
              pkgs.jq
            ]
            ++ lib.optionals pkgs.stdenv.hostPlatform.isLinux [
              pkgs.procps
              pkgs.lsof
            ];
            text = builtins.readFile ./omp-peers.sh;
          }
        );
        meta.description = "List the omp sessions running in a directory with their session ids and titles";
      };
    };
}
