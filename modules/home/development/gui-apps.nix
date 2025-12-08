# Cross-platform GUI applications (NixOS and nix-darwin)
{ ... }:
{
  flake.modules.homeManager.development =
    {
      pkgs,
      lib,
      config,
      ...
    }:
    {
      # Platform-specific GUI applications
      # Note: Users can disable these by removing the development aggregate
      home.packages =
        with pkgs;
        # Linux-only GUI apps (GTK apps often don't build on Darwin)
        (lib.optionals pkgs.stdenv.isLinux [
          dino # Modern XMPP/Jabber client (GTK/Vala) - broken on Darwin due to libudev-zero dependency
        ])
        ++
          # Cross-platform GUI apps (both Linux and Darwin)
          [
            # Add truly cross-platform GUI apps here
          ];
    };
}
