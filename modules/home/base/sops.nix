{
  # OUTER: Flake-parts module signature. The import below reads it: a home's
  # `flake` is a `_module.args` value, which `imports` cannot read.
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
        ...
      }:
      let
        # sops-nix defines its agent only for a home that declares secrets.
        onDarwinWithSecrets = pkgs.stdenv.hostPlatform.isDarwin && config.sops.secrets != { };
      in
      {
        # Import sops-nix home-manager module
        imports = [ inputs.sops-nix.homeManagerModules.sops ];

        # Configure sops age key location using XDG paths
        # This provides cross-platform support and reuses the same age key
        # used by clan secrets (~/.config/sops/age/keys.txt)
        sops.age.keyFile = lib.mkDefault "${config.xdg.configHome}/sops/age/keys.txt";

        # Age plugins for hardware token support
        sops.age.plugins = [ pkgs.age-plugin-yubikey ];

        # Workaround: Darwin LaunchAgent needs system paths for getconf
        # The LaunchAgent sets PATH to only age plugin paths, but sops-install-secrets
        # needs /usr/bin/getconf to determine DARWIN_USER_TEMP_DIR.
        # TODO: Remove after sops-nix is updated with upstream fix that adds system paths
        launchd.agents.sops-nix.config.EnvironmentVariables.PATH =
          lib.mkIf pkgs.stdenv.hostPlatform.isDarwin
            (
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

        # sops-nix's own darwin activation entry boots the agent out of and into
        # gui/<uid>, which fails the activation for an account with no screen
        # session. The agent lives in user/<uid> instead, which home-manager's
        # setupLaunchAgents loads and the launchd-primer daemon loads at boot.
        # RunAtLoad is off so that load, at the same moment as
        # org.nixos.sops-nix-<user> (modules/darwin/sops-boot-install.nix), does
        # not run a second install that races it to mount the RAM disk; the
        # boot install is that daemon's, and activation starts the agent here.
        launchd.agents.sops-nix.domain = lib.mkIf onDarwinWithSecrets "user";
        launchd.agents.sops-nix.config.RunAtLoad = lib.mkIf onDarwinWithSecrets (lib.mkForce false);
        home.activation.sops-nix = lib.mkIf onDarwinWithSecrets (
          lib.mkForce (
            lib.hm.dag.entryAfter [ "setupLaunchAgents" ] ''
              run /bin/launchctl kickstart -k "user/$(id -u)/${config.launchd.agents.sops-nix.config.Label}"
            ''
          )
        );

        # Per-user modules will set defaultSopsFile to their specific secrets file
        # Example: secrets/home-manager/users/crs58/secrets.yaml
      };
  };
}
