{
  pkgs,
  flake,
  config,
  lib,
  ...
}:
let
in
{
  # Install Radicle node and CLI tools
  home.packages = [ pkgs.radicle-node ];

  # Deploy Radicle configuration to ~/.radicle/config.json
  # Configuration includes node identity, preferred seeds, and public explorer settings
  home.file.".radicle/config.json".source = pkgs.writers.writeJSON "config.json" {
    # Public explorer URL pattern for viewing Radicle content via browser
    publicExplorer = "https://app.radicle.xyz/nodes/$host/$rid$path";

    node = {
      # Human-readable alias for this node
      alias = "cameronraysmith";

      # Not listening for inbound connections (empty list)
      # This is a simpler configuration for a client node
      listen = [ ];
    };

    # Default public Radicle seeds for repository discovery and replication
    # These are the official community seeds maintained by the Radicle team
    preferredSeeds = [
      "z6MksmpU5b1dS7oaqF2bHXhQi1DWy2hB7Mh9CuN7y1DN6QSz@seed.radicle.xyz:8776"
      "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@iris.radicle.xyz:8776"
      "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@rosa.radicle.xyz:8776"
    ];
  };

  # Deploy public key to ~/.radicle/keys/radicle.pub
  # This is the same unified SSH key used for Git and Jujutsu signing
  home.file.".radicle/keys/radicle.pub".text = ''
    ${flake.config.me.sshKey} ${flake.config.me.email}
  '';

  # Deploy unified SSH private key via SOPS to ~/.radicle/keys/radicle
  # This key serves three purposes:
  # 1. Radicle node identity (P2P cryptographic identity)
  # 2. Git commit signing (gpg.ssh backend)
  # 3. Jujutsu commit signing (ssh backend)
  #
  # Following defelo-nixos pattern: each module explicitly declares its secret dependencies
  # Using explicit sopsFile pattern (not defaultSopsFile) for future flexibility
  sops.secrets."radicle/ssh-private-key" = {
    sopsFile = flake.inputs.self + "/secrets/radicle.yaml";
    path = "${config.home.homeDirectory}/.radicle/keys/radicle";
    mode = "0400";
  };

  # TODO: Service management on Darwin
  # Currently running radicle-node manually when needed.
  # Future enhancement: Implement launchd agent for automatic startup
  # (systemd.user.services is not available on Darwin)
  #
  # Manual operation:
  #   Start node: radicle-node
  #   Check identity: rad auth
  #   View node info: rad self
}
