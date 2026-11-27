# Home-manager sops secrets on a Mac live on a RAM disk, so every restart
# loses them until something runs the home's install again.
#
# sops-nix's home module decrypts into %r/secrets.d, %r being
# `getconf DARWIN_USER_TEMP_DIR`, and mounts a 64 MB `hdiutil ram://` HFS disk
# there whenever its marker file is absent (sops-nix 7c637afd
# pkgs/sops-install-secrets/darwin.go:13-72), then repoints
# ~/.config/sops-nix/secrets at the new generation. Its only runs are those of
# its per-user LaunchAgent, which modules/home/base/sops.nix places in
# user/<uid> with RunAtLoad off and starts at every activation, so nothing
# runs the install after a restart until the next activation, as on an account
# that never logs in at the screen such as cameron on rosegold.
#
# For each home of the host that declares secrets, a system LaunchDaemon runs
# that home's install program at boot as the account, with the agent's
# environment and through nix-darwin's `command` (/bin/wait4path /nix/store).
# The agent stays for activation. home-manager's launchd-primer daemon loads
# it at boot without running it, so this daemon is the only install at boot.
# Boot ordering:
# - getconf resolves the temp directory from the process's euid and the
#   account's UUID, and asks the system dirhelper to create it when missing
#   (Libc-997.1.1 darwin/_dirhelper.c:196-209,282-338), so no login session
#   is needed.
# - launchd runs `dirhelper -machineBoot`, which empties the temp
#   directories, as a boot task it waits for (strings of /sbin/launchd on
#   macOS 26.7.1). Should it run after the mount, its walk uses FTS_XDEV and
#   rmdir, which neither enters nor removes a mounted RAM disk
#   (system_cmds-550.10 dirhelper.tproj/dirhelper.c:192-260); the daily
#   cleanup deletes only regular files it reaches without crossing a mount.
# - /Users and /Library/LaunchDaemons share the Data volume, so the age key
#   file is readable whenever this plist has been loaded; a missing key fails
#   the run, and the agent or the next activation installs instead.
# Loading a changed plist runs the install once at activation as well.
#
# flake.lib.sopsBootInstallObligations.failures, asserted by
# modules/checks/machines.nix on every darwin machine check, fails unless each
# home with secrets has its daemon, running as that account at load, whose
# arguments run that home's install program.
{ config, lib, ... }:
let
  daemonName = user: "sops-nix-${user}";

  # The homes of a host that declare secrets. sops-nix defines its launchd
  # agent only for them, and that agent's Program is the install program
  # (the same handle modules/home/base/sops-install-without-systemd.nix reads).
  homesWithSecrets =
    hostConfig:
    lib.filterAttrs (_: home: home.sops.secrets != { }) (hostConfig.home-manager.users or { });

  agentOf = home: home.launchd.agents.sops-nix.config;

  # nix-darwin's rendering of `command`.
  argumentsFor = program: [
    "/bin/sh"
    "-c"
    "/bin/wait4path /nix/store && exec ${program}"
  ];

  # The problems with `daemons`, a host's launchd.daemons, for `homes`, its
  # homes with secrets.
  missingInstalls =
    { homes, daemons }:
    lib.concatLists (
      lib.mapAttrsToList (
        user: home:
        let
          name = daemonName user;
          daemon = daemons.${name} or null;
          s = daemon.serviceConfig;
        in
        if daemon == null then
          [ "no launchd.daemons.${name} for ${user}'s secrets" ]
        else
          lib.optional (
            s.UserName != user
          ) "launchd.daemons.${name} runs as ${toString s.UserName}, not ${user}"
          ++ lib.optional (s.RunAtLoad != true) "launchd.daemons.${name} does not run at load"
          ++ lib.optional (
            s.ProgramArguments != argumentsFor (agentOf home).Program
          ) "launchd.daemons.${name} does not run ${user}'s sops-nix install program"
      ) homes
    );
in
{
  flake.lib.sopsBootInstallObligations = {
    inherit daemonName homesWithSecrets missingInstalls;
    failures =
      name: hostConfig:
      map (problem: "${name}: ${problem}") (missingInstalls {
        homes = homesWithSecrets hostConfig;
        daemons = hostConfig.launchd.daemons;
      });
  };

  # Darwin only: NixOS homes install secrets from their systemd user unit.
  fleetObligations.sopsBootInstallObligations = {
    classes = [ "darwin" ];
    inherit (config.flake.lib.sopsBootInstallObligations) failures;
  };

  flake.modules.darwin.base =
    { config, ... }:
    {
      launchd.daemons = lib.mapAttrs' (
        user: home:
        let
          agent = agentOf home;
        in
        lib.nameValuePair (daemonName user) {
          command = agent.Program;
          environment = agent.EnvironmentVariables;
          serviceConfig = {
            UserName = user;
            RunAtLoad = true;
            KeepAlive = false;
            # launchd opens these as UserName; they are the agent's own.
            StandardOutPath = agent.StandardOutPath;
            StandardErrorPath = agent.StandardErrorPath;
          };
        }
      ) (homesWithSecrets config);
    };
}
