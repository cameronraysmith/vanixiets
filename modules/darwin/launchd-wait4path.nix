# launchd can start a job before the Nix store volume is mounted. A job whose
# executable is a store path then fails with "Missing executable detected" and
# stays inactive, KeepAlive notwithstanding, until its plist is reloaded.
# nix-darwin's `command` and `script` start the job through /bin/wait4path;
# a job starting at load or kept alive must use them or prefix it itself.
{
  flake.modules.darwin.base =
    { config, lib, ... }:
    let
      exposed =
        kind: jobs:
        lib.mapAttrsToList (name: _: "launchd.${kind}.${name}") (
          lib.filterAttrs (
            _: job:
            let
              s = job.serviceConfig;
              executable =
                if s.Program != null then
                  s.Program
                else if s.ProgramArguments != null && s.ProgramArguments != [ ] then
                  builtins.head s.ProgramArguments
                else
                  "";
            in
            lib.hasPrefix "/nix/store/" executable
            && (
              s.RunAtLoad == true
              || !builtins.elem s.KeepAlive [
                null
                false
              ]
            )
          ) jobs
        );
      unguarded =
        exposed "daemons" config.launchd.daemons
        ++ exposed "agents" config.launchd.agents
        ++ exposed "user.agents" config.launchd.user.agents;
    in
    {
      assertions = [
        {
          assertion = unguarded == [ ];
          message = "launchd jobs start a store-path executable without /bin/wait4path /nix/store: ${lib.concatStringsSep ", " unguarded}";
        }
      ];
    };
}
