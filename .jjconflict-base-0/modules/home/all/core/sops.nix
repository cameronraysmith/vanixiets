{
  config,
  pkgs,
  lib,
  flake,
  ...
}:
{
  # Configure sops age key location using XDG paths
  # This provides cross-platform support:
  # - Linux: ~/.config/sops/age/keys.txt
  # - macOS with xdg.enable: ~/.config/sops/age/keys.txt
  # - macOS without xdg: ~/Library/Application Support/sops/age/keys.txt
  sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";

  # Default SOPS file for existing System 1 secrets (general secrets management)
  # Uses flake.inputs.self to reference files in the current repository
  sops.defaultSopsFile = flake.inputs.self + "/secrets/shared.yaml";

  # Note: System 2 (unified crypto) secrets explicitly override with sopsFile:
  # sops.secrets."radicle/ssh-private-key" = {
  #   sopsFile = inputs.secrets.secrets.<hostname>.radicle;  # Overrides default
  #   mode = "0400";
  # };
  #
  # This allows:
  # - System 1 (existing): Multi-key secrets in secrets/ directory (uses default)
  # - System 2 (new): Unified crypto secrets from nix-secrets flake (explicit sopsFile)
  # - Both systems use the same Age key from ~/.config/sops/age/keys.txt
}
