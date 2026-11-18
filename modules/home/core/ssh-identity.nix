# SSH identity for interactive login: which agent serves keys, and which vault
# key each host is offered.
# Platform-specific only where the platform forces it: the agent socket path
# (modules/lib/bitwarden-socket-path.nix) and the default agent, since every
# darwin host installs the Mac App Store Bitwarden (Touch ID unlock) while
# Linux hosts opt in (pyrite unlocks through polkit and pam_u2f, system-side).
# The ssh binary is chosen in modules/home/security/tools.nix; commit signing
# never uses an agent (flake.lib.agentFreeSshKeygen).
{ inputs, config, ... }:
{
  flake.modules.homeManager.core =
    {
      config,
      pkgs,
      lib,
      ...
    }:
    let
      cfg = config.programs.bitwarden-ssh-agent;
      isDarwin = pkgs.stdenv.hostPlatform.isDarwin;

      # https://bitwarden.com/help/ssh-agent/#tab-macos-6VN1DmoAVFvm7ZWD95curS
      socketPath = inputs.self.lib.bitwardenSocketPath {
        inherit (config.home) homeDirectory;
        inherit isDarwin;
      };

      pinFile = name: ".ssh/bitwarden-${name}.pub";
    in
    {
      options.programs.bitwarden-ssh-agent = {
        enable = lib.mkOption {
          type = lib.types.bool;
          default = isDarwin;
          defaultText = lib.literalExpression "pkgs.stdenv.hostPlatform.isDarwin";
          description = ''
            Whether the Bitwarden Desktop SSH agent is the session's SSH agent.
            When enabled, SSH_AUTH_SOCK points at its socket and home-manager's
            ssh-agent is not started; when disabled, home-manager's ssh-agent
            provides SSH_AUTH_SOCK.
            https://bitwarden.com/help/ssh-agent/#configure-bitwarden-ssh-agent
          '';
        };

        pinnedKeys = lib.mkOption {
          type = lib.types.attrsOf (
            lib.types.submodule {
              options = {
                hosts = lib.mkOption {
                  type = lib.types.nonEmptyListOf lib.types.str;
                  description = "ssh Host patterns that are offered only this key.";
                };
                publicKey = lib.mkOption {
                  type = lib.types.strMatching "(ssh-ed25519|ssh-rsa|ecdsa-sha2-nistp[0-9]+) [A-Za-z0-9+/]+=*( .*)?";
                  description = "Public half of the vault key, written to ~/.ssh/bitwarden-<name>.pub.";
                };
              };
            }
          );
          default = { };
          description = ''
            Vault keys pinned to host patterns. Bitwarden's agent offers every
            vault key and has no per-request key selection
            (https://bitwarden.com/help/about-ssh/), so a server with a low
            MaxAuthTries refuses before the right key is tried. Each pin writes
            the public half to a file and sets `IdentitiesOnly yes` with that
            file as `IdentityFile`, which makes ssh offer only the agent key
            matching it.
          '';
        };
      };

      config = {
        assertions = [
          {
            assertion = cfg.pinnedKeys == { } || cfg.enable;
            message = "programs.bitwarden-ssh-agent.pinnedKeys selects keys from Bitwarden's agent, so programs.bitwarden-ssh-agent.enable must be true";
          }
        ];

        home.sessionVariables = lib.mkIf cfg.enable {
          SSH_AUTH_SOCK = socketPath;
        };
        # Ignored where systemd.user is off (darwin).
        systemd.user.sessionVariables = lib.mkIf cfg.enable {
          SSH_AUTH_SOCK = socketPath;
        };

        services.ssh-agent.enable = !cfg.enable;

        home.file = lib.mapAttrs' (
          name: pin: lib.nameValuePair (pinFile name) { text = "${pin.publicKey}\n"; }
        ) cfg.pinnedKeys;

        programs.ssh.settings = lib.mkMerge (
          [
            {
              # Bitwarden refuses keys added by clients
              # (https://bitwarden.com/help/about-ssh/#no-ssh-add-key-management),
              # so adding is attempted only for home-manager's agent.
              "*".AddKeysToAgent = if cfg.enable then "no" else "confirm";
            }
          ]
          ++ lib.concatLists (
            lib.mapAttrsToList (
              name: pin:
              map (host: {
                ${host} = {
                  IdentitiesOnly = true;
                  IdentityFile = "~/${pinFile name}";
                };
              }) pin.hosts
            ) cfg.pinnedKeys
          )
        );
      };
    };

  # crs58's vault keys, imported by the laptops that use Bitwarden's agent for
  # login (pyrite, stibnite). Other hosts keep ssh's default identity files.
  flake.modules.homeManager.bitwarden-key-pins = {
    programs.bitwarden-ssh-agent = {
      enable = true;
      pinnedKeys = {
        login = {
          # "*.zt" goes with ZeroTier's retirement.
          hosts = [
            "*.zt"
            "*.${config.flake.lib.fleet.domain}"
          ];
          publicKey = "ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAINdO9rInDa9HvdtZZxmkgeEdAlTupCy3BgA/sqSGyUH+";
        };
        # GitHub authenticates cameronraysmith with this RSA key; the login key
        # is registered there only as a signing key.
        github = {
          hosts = [ "github.com" ];
          publicKey = "ssh-rsa AAAAB3NzaC1yc2EAAAADAQABAAACAQDFGXo7HSSakYB5eEvp22xKmNrMwpI7OTlB3RqP+mGagbggljJP/YBmUCptstAMsZuKeMRXjm6UXUgNeUhECLZQHEDy2+Mrm42OM0svsMqlgZj1ZZdY1yYcquKQO4oyx7CjPOj7NXqSueZmpcwYRJFU7xQO421wb9rNewxCRs8jwRr5beTCUF0MuGLNEJGPMPk++d6Mkd3TYojE524AAoDWgx5z2WavZnewuYYd8PAGrFO4yWQn6LX50qYq2bPo53J/7CT9KwEo4ZaYl6TiSb9x3Oj+iUiTMNBmKBLSMYyj7eV8CU4iIXYqySvEf/mA7EytZnKT37cYo25CMAsobCHZ07htv6bbW+FPb1jehjT96Oo6i0zVGIs/gptw1k9xXSTS0GxfQ1P0XK7+9RZE7bWw/kxepF+OzLcvKKz3SdPEb/SOmqPoq4AFalljM0iwi8DXmH2dhp1Ughh4ImQQxVGrq+U2EwuSZEQHuSXlvfB/MKj2yvcF0BYhPaYfCLovq5LbXXu1QpnL/C9FiY21ehmVFZwHvo+L8y2NxwCaoXYuPGwGc5kH5fNjBh/S7RpypV+oHHGY90lGV6CoQpxXb65rI/ob7cTR2npWUC577fmidYTSmOqU3HhewcZDgxf2iZkVCm7F/Sb2tga3BClr3lV92EBFm9JsayzM9DLuAIz7rQ==";
        };
      };
    };
  };
}
