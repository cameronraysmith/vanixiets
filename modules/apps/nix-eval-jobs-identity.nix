# The drvPath-identity oracle between stock nix-eval-jobs and iets: the
# host's own nix-eval-jobs-stock and nix-eval-jobs (iets, where the host's
# memory gives it iets: modules/lib/nix-eval-jobs-host.nix) both evaluate
# checks.<system> of one commit with the same arguments, and every attribute
# must have the same drvPath, system and outputs, and fail in both or in
# neither. Running the names on PATH keeps both runs behind a host's
# evaluation lock. `just eval-identity` runs it. It is the evidence behind
# evaluating with iets: run it after an iets bump or before widening iets' use.
{
  perSystem =
    {
      pkgs,
      lib,
      ...
    }:
    {
      apps.nix-eval-jobs-identity = {
        type = "app";
        program = lib.getExe (
          pkgs.writeShellApplication {
            name = "nix-eval-jobs-identity";
            runtimeInputs = [
              pkgs.coreutils
              pkgs.diffutils
              pkgs.git
              pkgs.jq
            ];
            text = builtins.readFile ./nix-eval-jobs-identity.sh;
          }
        );
        meta.description = "Compare stock nix-eval-jobs and iets drvPaths over checks.<system> of a commit";
      };
    };
}
