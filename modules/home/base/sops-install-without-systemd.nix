{ ... }:
{
  flake.modules.homeManager.base-sops =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.sopsInstallWithoutSystemd;

      # sops-nix builds a single script that renders the secrets manifest and
      # runs sops-install-secrets against it, then hands the same script to
      # three consumers: the systemd user unit, the launchd agent, and its own
      # activation entry. Only the launchd agent exposes it through a declared
      # option, and sops-nix sets that agent on every platform, so
      # `launchd.agents.sops-nix.config.Program` is the one public handle on
      # the script. Reading it costs nothing on Linux, where home-manager
      # renders no launchd agents.
      installScript = config.launchd.agents.sops-nix.config.Program;

      environment = lib.concatStringsSep " " (
        lib.mapAttrsToList (name: value: "'${name}=${value}'") config.sops.environment
      );

      ageKeyFile = config.sops.age.keyFile;
      systemctl = config.systemd.user.systemctlPath;

      # A null key file means sops decrypts with something other than an age
      # key, so the skip branch is never taken and the install decides.
      ageKeyAbsent =
        if ageKeyFile == null then "false" else "[[ ! -f ${lib.escapeShellArg ageKeyFile} ]]";

      # sops-install-secrets resolves $XDG_RUNTIME_DIR before it inspects any
      # path and fails when it is unset, so a profile that supplies one through
      # sops.environment is also responsible for the directory existing. Creating
      # it here rather than in the profile keeps that obligation next to the
      # invocation that carries the variable.
      runtimeDir = config.sops.environment.XDG_RUNTIME_DIR or null;
      # A runtime directory commonly sits under /dev/shm or /tmp, which are
      # world-writable and sticky, so it is created rather than adopted and an
      # existing one is used only when this user owns it and it is not a symlink.
      # Written as one interpolated value because nix does not re-indent what it
      # substitutes.
      ensureRuntimeDir =
        lib.optionalString (runtimeDir != null) ''
          if [[ -L ${lib.escapeShellArg runtimeDir} ]]; then
              errorEcho "sops-nix: ${runtimeDir} is a symlink; refusing to use it"
              exit 1
            elif [[ -d ${lib.escapeShellArg runtimeDir} ]]; then
              if [[ ! -O ${lib.escapeShellArg runtimeDir} ]]; then
                errorEcho "sops-nix: ${runtimeDir} is not owned by this user; refusing to use it"
                exit 1
              fi
              run chmod 700 ${lib.escapeShellArg runtimeDir}
            else
              run mkdir -m 0700 ${lib.escapeShellArg runtimeDir}
            fi
        ''
        # Re-indents the interpolation's last line so the install call that
        # follows it keeps the surrounding block's indentation.
        + "  ";

    in
    {
      options.sopsInstallWithoutSystemd.enable = lib.mkEnableOption ''
        installing sops secrets from a home-manager activation entry when no
        systemd user manager is running.

        On Linux sops-nix installs secrets through a systemd user service, and
        its own activation entry only restarts that unit. Where standalone
        home-manager runs without a session bus and user manager, as in a
        container or a hosted agent sandbox, the unit never starts and secrets
        are never installed. This option runs the same sops-nix install script
        directly instead.

        An absent `sops.age.keyFile` is treated as the secrets coeffect not
        being present: the entry reports that it skipped the install and
        continues, so a profile can be activated where no key exists, as an
        image or snapshot build must be. Where the key file exists the install
        runs and any failure is fatal. Activating again once the key is in place
        is what installs the secrets.

        The entry probes `systemctl --user is-system-running` and, when a user
        manager is present, restarts the sops-nix unit as sops-nix's own entry
        would. That entry is replaced rather than left in place because it
        restarts unconditionally, and a restart with no key present fails the
        unit and with it the whole activation. Enabling this on a NixOS
        workstation therefore changes nothing but the no-key case. It has no
        effect on darwin, where sops-nix bootstraps its launchd agent from its
        own entry, and none when no secrets are declared.

        The entry runs after `writeBoundary`. Activation entries that read the
        installed secrets should declare `entryAfter [ "sopsInstallWithoutSystemd" ]`
        rather than relying on entry order.
      '';

      options.sopsInstallWithoutSystemd.atActivation = lib.mkOption {
        type = lib.types.bool;
        default = true;
        description = ''
          Whether activation installs the secrets. When false, activation
          carries no install step at all, and sops-nix's own entry stays
          replaced, so activating never decrypts whatever key is present; the
          install is then owed by a session-start hook, such as the `sandbox`
          aggregate's `session-env.sh`. For a profile activated by a step that
          must hold no secret, whose result may be snapshotted.
        '';
      };

      config = lib.mkIf (cfg.enable && pkgs.stdenv.hostPlatform.isLinux && config.sops.secrets != { }) {
        home.activation.sops-nix = lib.mkForce "";

        # warnEcho on the skip: a profile whose secrets are not installed is
        # worth seeing on every activation, not only a verbose one.
        home.activation.sopsInstallWithoutSystemd = lib.mkIf cfg.atActivation (
          lib.hm.dag.entryAfter [ "writeBoundary" ] ''
            systemdStatus=$(${systemctl} --user is-system-running 2>&1 || true)

            if ${ageKeyAbsent}; then
              warnEcho "sops-nix: no age key at ${toString ageKeyFile}; skipping secret installation until an activation runs with the key present"
            elif [[ $systemdStatus == 'running' || $systemdStatus == 'degraded' ]]; then
              verboseEcho "sops-nix: user systemd manager is $systemdStatus; restarting the sops-nix unit"
              run ${systemctl} restart --user sops-nix
            else
              verboseEcho "sops-nix: no user systemd manager; installing secrets directly"
              ${ensureRuntimeDir}run env ${environment} ${installScript}
            fi

            unset systemdStatus
          ''
        );
      };
    };
}
