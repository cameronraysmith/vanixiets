# public key values should be set in user modules via sops.templates
{ ... }:
{
  flake.modules.homeManager.development =
    {
      pkgs,
      flake,
      config,
      lib,
      ...
    }:
    let
      radHome = "${config.home.homeDirectory}/.radicle";
      nodeArgv = [
        (lib.getExe' pkgs.radicle-node "radicle-node")
        "--force"
      ];
      nodeEnv.RAD_HOME = radHome;
    in
    {
      home.packages = [
        pkgs.radicle-node
        pkgs.radicle-tui
      ];

      sops.secrets.ssh-signing-key.path = "${radHome}/keys/radicle";

      # Deploy Radicle configuration to ~/.radicle/config.json
      home.file.".radicle/config.json".source = pkgs.writers.writeJSON "config.json" {
        # Public explorer URL pattern for viewing Radicle content via browser
        publicExplorer = "https://app.radicle.xyz/nodes/$host/$rid$path";

        node = {
          # Human-readable alias for this node
          alias = config.home.username;

          # Do not listen for inbound connections on client-only node
          listen = [ ];
        };

        # Default Radicle seeds for repository discovery and replication
        preferredSeeds = [
          "z6MkjAoHXtb7qQdVn1fDhiaQ4UGk1CmGNApYXKPP9dDSy68E@cinnabar.zt:8776"
          "z6MksmpU5b1dS7oaqF2bHXhQi1DWy2hB7Mh9CuN7y1DN6QSz@seed.radicle.xyz:8776"
          "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@iris.radicle.xyz:8776"
          "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@rosa.radicle.xyz:8776"
        ];
      };

      # Signing key: sops.secrets.ssh-signing-key decrypts to ~/.radicle/keys/radicle.
      # Same key serves radicle node identity, git signing, and jj signing.
      # Public key deployed via user module (e.g. modules/home/users/crs58/).

      # State only a running node maintains, such as the COB cache that
      # Radicle Desktop requires to be current, never exists unless a node
      # runs, so the user's service manager keeps one running. The node
      # migrates that cache itself on start, and the sops key is unencrypted,
      # so it needs neither `rad cob migrate` nor RAD_PASSPHRASE. The key is
      # rendered by sops-nix's own user agent or unit. systemd orders the node
      # after that oneshot unit; launchd cannot, so at login the node may find
      # no key, exit non-zero, and be relaunched after ThrottleInterval. On
      # both platforms the 30s retry spaces out permanent failures, and a
      # clean `rad node stop` exits zero and stays stopped. --force clears a
      # control socket left by a node that did not shut down cleanly, which
      # the supervisor's single instance makes safe.
      launchd.agents.radicle-node = lib.mkIf pkgs.stdenv.hostPlatform.isDarwin {
        enable = true;
        config = {
          ProgramArguments = nodeArgv;
          EnvironmentVariables = nodeEnv;
          RunAtLoad = true;
          KeepAlive.SuccessfulExit = false;
          ThrottleInterval = 30;
          ProcessType = "Background";
          StandardOutPath = "${config.home.homeDirectory}/Library/Logs/radicle-node.log";
          StandardErrorPath = "${config.home.homeDirectory}/Library/Logs/radicle-node.log";
        };
      };

      systemd.user.services.radicle-node = lib.mkIf pkgs.stdenv.hostPlatform.isLinux {
        Unit = {
          Description = "Radicle node";
          After = [ "sops-nix.service" ];
          Wants = [ "sops-nix.service" ];
        };
        Service = {
          ExecStart = lib.escapeShellArgs nodeArgv;
          Environment = lib.mapAttrsToList (name: value: "${name}=${value}") nodeEnv;
          Restart = "on-failure";
          RestartSec = 30;
        };
        Install.WantedBy = [ "default.target" ];
      };
    };
}
