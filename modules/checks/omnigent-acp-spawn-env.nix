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
      # Size classes (declare-test-size-classes design D1, D2): the median of
      # nixbot's uncached runs of at least 1 s, read 2026-11-24
      # (logs/tsc-4-durations-runs-20261124-141600.log).
      testSizes.checks = lib.optionalAttrs (system == "x86_64-linux") {
        # nixbot: median 8.0 s, slowest 21 s, 7 runs in 30 days
        omnigent-acp-spawn-env.class = "small";
      };
      checks.omnigent-acp-spawn-env = pkgs.runCommand "omnigent-acp-spawn-env" { } ''
        ${self'.packages.omnigent.python.interpreter} -I ${./omnigent-acp-spawn-env.py} ${cases} ${lib.getExe pkgs.strace}
        touch $out
      '';
    };
}
