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
    {
      home.packages = [
        pkgs.radicle-node
        pkgs.radicle-tui
      ];

      sops.secrets.ssh-signing-key.path = "${config.home.homeDirectory}/.radicle/keys/radicle";

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

        # Default public Radicle seeds for repository discovery and replication
        preferredSeeds = [
          "z6MksmpU5b1dS7oaqF2bHXhQi1DWy2hB7Mh9CuN7y1DN6QSz@seed.radicle.xyz:8776"
          "z6MkrLMMsiPWUcNPHcRajuMi9mDfYckSoJyPwwnknocNYPm7@iris.radicle.xyz:8776"
          "z6Mkmqogy2qEM2ummccUthFEaaHvyYmYBYh3dbe9W4ebScxo@rosa.radicle.xyz:8776"
        ];
      };

      # Signing key: sops.secrets.ssh-signing-key decrypts to ~/.radicle/keys/radicle.
      # Same key serves radicle node identity, git signing, and jj signing.
      # Public key deployed via user module (e.g. modules/home/users/crs58/).

      # TODO: Service management on Darwin
      # radicle-node can be run manually as needed
      # but would be more convenient to use a launchd agent
      # (systemd.user.services obviously not available on Darwin)
      #
      # For manual operation:
      #   Start node: radicle-node
      #   Check identity: rad auth
      #   View node info: rad self
    };
}
