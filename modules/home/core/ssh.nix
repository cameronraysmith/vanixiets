# SSH client configuration with platform-aware defaults and zerotier network
# Integrates:
# - includes (colima, augment, orbstack, custom_config)
# - zerotier network hosts
# - security key handling (FIDO/U2F)
{ config, lib, ... }:
let
  inherit (config.flake.lib) hosts;

  # Login per member reachable over ssh: every NixOS and darwin host, plus
  # each phone's Termux sshd (port 8022; Termux accepts any username).
  # Written by hand, since a NixOS host has no admin attachment to derive a
  # login from; checks.x86_64-linux.host-list-keys compares its keys with
  # the registry's hosts through flake.lib.sshLogins.
  logins = {
    cinnabar.User = "cameron";
    electrum.User = "cameron";
    blackphos.User = "crs58";
    stibnite.User = "crs58";
    argentum.User = "cameron";
    rosegold.User = "cameron";
    galena.User = "cameron";
    scheelite.User = "cameron";
    magnetite.User = "cameron";
    pyrite.User = "cameron";
    pixel7 = {
      Port = 8022;
      User = "termux";
    };
    pixel11 = {
      Port = 8022;
      User = "termux";
    };
  };

  # One block per login under a host name: HostName is the member's address
  # on that network, and hosts whose keys are pinned in known_hosts
  # (modules/system/ssh-known-hosts.nix; not the phone) look the key up under
  # that name.
  blocksNamed =
    hostName: address:
    lib.mapAttrs' (
      name: login:
      lib.nameValuePair (hostName name) (
        {
          HostName = address hosts.${name};
        }
        // login
        // lib.optionalAttrs (hosts.${name}.class != "android") { HostKeyAlias = hostName name; }
      )
    ) logins;

  # ZeroTier blocks, `<name>.zt`, until ZeroTier is retired.
  ztBlocks = blocksNamed (name: "${name}.zt") (host: host.zerotier.address);

  # Mesh blocks under each member's canonical name.
  meshBlocks = blocksNamed (name: hosts.${name}.fqdn) (host: host.address);
in
{
  flake.lib.sshLogins = logins;

  flake.modules.homeManager.core =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      programs.ssh = {
        enable = true;

        # explicitly disable home-manager's default config
        enableDefaultConfig = false;

        # include ordered external SSH configurations
        includes = [
          # Custom user config (highest priority for overrides)
          "${config.home.homeDirectory}/.ssh/custom_config"
        ]
        ++ lib.optionals pkgs.stdenv.hostPlatform.isDarwin [
          # Darwin-specific includes
          "${config.home.homeDirectory}/.config/colima/ssh_config"
          "${config.home.homeDirectory}/.orbstack/ssh/config"
        ];

        # programs.ssh.settings replaces the deprecated programs.ssh.matchBlocks
        # (home-manager RFC 42 SSH refactor). Each block is keyed by host or match
        # pattern; directive bodies use upstream OpenSSH PascalCase directive names.
        # The "*" block is special-cased by home-manager to always render last, so
        # its values act as the lowest-priority defaults.
        settings = {
          # Security keys (FIDO/U2F) must NOT be auto-added to the agent.
          # Expressed as a Match-exec block via the `header` option, which carries
          # the match expression (including the interpolated home directory).
          # Because "*" always renders last, this AddKeysToAgent override wins over
          # the global default below.
          "sk-keys" = {
            header = ''Match exec "sh -c 'test -e ${config.home.homeDirectory}/.ssh/id_*_sk 2>/dev/null'"'';
            AddKeysToAgent = "no";
          };

        }
        // ztBlocks
        // meshBlocks
        // {
          # Wildcard for all zerotier hosts
          "*.zt" = {
            # Enable compression for zerotier (encrypted tunnel over encrypted tunnel)
            Compression = true;
            # Keepalive for NAT traversal
            ServerAliveInterval = 60;
            ServerAliveCountMax = 3;
          };

          # ====================
          # Global Defaults (always rendered last)
          # ====================

          "*" = {
            # The agent (SSH_AUTH_SOCK), AddKeysToAgent and per-host key pins
            # are set by modules/home/core/ssh-identity.nix. Without a pin,
            # identities come from the agent, so no IdentityFile is needed on
            # hosts that lack the default key files.

            # security defaults
            ForwardAgent = false; # override per-host as needed
            Compression = false; # override for zerotier hosts
            HashKnownHosts = false;
            UserKnownHostsFile = "~/.ssh/known_hosts";

            # connection persistence defaults
            ControlMaster = "no";
            ControlPath = "~/.ssh/master-%r@%n:%p";
            ControlPersist = "no";

            # keepalive (disabled by default, enable per-host)
            ServerAliveInterval = 0;
            ServerAliveCountMax = 3;
          }
          # macOS-specific options.
          # Note: UseKeychain removed - only works with Apple's SSH, not Nix OpenSSH;
          # we use the Bitwarden SSH agent via SSH_AUTH_SOCK instead.
          // lib.optionalAttrs pkgs.stdenv.hostPlatform.isDarwin {
            # XAuthLocation for X11 forwarding (XQuartz)
            XAuthLocation = "/opt/X11/bin/xauth";
          };
        };
      };
    };
}
