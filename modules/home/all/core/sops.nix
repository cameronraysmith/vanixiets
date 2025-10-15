{
  config,
  pkgs,
  lib,
  self,
  ...
}:
{
  # Configure sops age key location using XDG paths
  # This provides cross-platform support:
  # - Linux: ~/.config/sops/age/keys.txt
  # - macOS with xdg.enable: ~/.config/sops/age/keys.txt
  # - macOS without xdg: ~/Library/Application Support/sops/age/keys.txt
  sops.age.keyFile = "${config.xdg.configHome}/sops/age/keys.txt";

  # Note: No defaultSopsFile set - each secret will specify its sopsFile
  # Secrets are now sourced from the secrets flake input via:
  # sops.secrets."secret-name" = {
  #   sopsFile = inputs.secrets.secrets.<hostname>.<secret-name>;
  # };
  #
  # This allows per-secret file specification and integration with the
  # separate nix-secrets repository for the unified crypto infrastructure.
}
