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
        # Also fixes Darwin launchd PATH issue (sops-nix#890) by ensuring
        # PATH is non-empty, allowing getconf to be found
        sops.age.plugins = [ pkgs.age-plugin-yubikey ];

        # Per-user modules will set defaultSopsFile to their specific secrets file
        # Example: secrets/home-manager/users/crs58/secrets.yaml
      };
  };
}
