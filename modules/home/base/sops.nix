{
  # OUTER: Flake-parts module signature
  # No 'flake' here - only config, inputs available
  config,
  inputs,
  ...
}:
{
  flake.modules = {
    # INNER: Home-manager module (the value we're defining)
    homeManager.base-sops =
      {
        config,
        lib,
        pkgs,
        flake,
        ...
      }: # flake from extraSpecialArgs
      {
        # Import sops-nix home-manager module
        imports = [ flake.inputs.sops-nix.homeManagerModules.sops ];

        # Configure sops age key location using XDG paths
        # This provides cross-platform support and reuses the same age key
        # used by clan secrets (~/.config/sops/age/keys.txt)
        sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";

        # Age plugins for hardware token support
        sops.age.plugins = [ pkgs.age-plugin-yubikey ];

        # Workaround: Darwin LaunchAgent needs system paths for getconf
        # The LaunchAgent sets PATH to only age plugin paths, but sops-install-secrets
        # needs /usr/bin/getconf to determine DARWIN_USER_TEMP_DIR.
        # TODO: Remove after sops-nix is updated with upstream fix that adds system paths
        launchd.agents.sops-nix.config.EnvironmentVariables.PATH = lib.mkIf pkgs.stdenv.isDarwin (
          lib.mkForce (
            lib.concatStringsSep ":" [
              (lib.makeBinPath config.sops.age.plugins)
              "/usr/bin"
              "/bin"
              "/usr/sbin"
              "/sbin"
            ]
          )
        );

        # Per-user modules will set defaultSopsFile to their specific secrets file
        # Example: secrets/home-manager/users/crs58/secrets.yaml
      };
  };
}
