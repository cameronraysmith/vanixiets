# Runtime regulator for ACP state isolation. Atomic's pi-acp must receive
# PI_ACP_PI_COMMAND and PI_CODING_AGENT_DIR (set by its own ACP command), while
# Oh My Pi and any undeclared generic ACP agent must receive neither, even with
# both present in the host environment: since omnigent 0.23.0 every generic ACP
# child inherits the names in OMNIGENT_RUNNER_ENV_PASSTHROUGH. The packaged
# omnigent computes the runner and ACP spawn environments from each real NixOS
# worker's unit environment and rendered settings, and strace records the
# environment of each agent program's execve (omnigent-acp-spawn-env.py).
{ config, lib, ... }:
{
  perSystem =
    {
      pkgs,
      self',
      system,
      ...
    }:
    let
      hosts = [
        "magnetite"
        "pyrite"
      ];
      casesFor =
        host:
        let
          hostConfig = config.flake.nixosConfigurations.${host}.config;
        in
        lib.mapAttrsToList (name: worker: {
          label = "${host}-${name}";
          # The host's PATH and other store paths are not needed to compute names.
          hostEnvironment = builtins.fromJSON (
            builtins.unsafeDiscardStringContext (
              builtins.toJSON hostConfig.systemd.services."omnigent-host-${name}".environment
            )
          );
          inherit (hostConfig.home-manager.users.${worker.user}.programs.omnigent.settings) acp;
        }) hostConfig.services.omnigent-host.workers;
      cases = pkgs.writeText "omnigent-acp-spawn-env-cases.json" (
        builtins.toJSON (lib.concatMap casesFor hosts)
      );
    in
    lib.optionalAttrs (system == "x86_64-linux") {
      checks.omnigent-acp-spawn-env = pkgs.runCommand "omnigent-acp-spawn-env" { } ''
        ${self'.packages.omnigent.python.interpreter} -I ${./omnigent-acp-spawn-env.py} ${cases} ${lib.getExe pkgs.strace}
        touch $out
      '';
    };
}
