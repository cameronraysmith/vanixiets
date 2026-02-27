{ lib, ... }:
{
  flake.modules.darwin.zt-services-trust =
    { config, lib, ... }:
    let
      cfg = config.services.zt-services-trust;
      caddyCert = ../machines/nixos/cinnabar/pki/caddy-root-ca.crt;
    in
    {
      options.services.zt-services-trust.enable = lib.mkEnableOption "Caddy internal CA trust for .zt services";

      config = lib.mkIf cfg.enable {
        security.pki.certificateFiles = [ caddyCert ];

        system.activationScripts.postActivation.text = lib.mkAfter ''
          echo "Adding Caddy cinnabar internal CA to macOS Keychain..."
          CADDY_CERT_PATH="${caddyCert}"
          CADDY_CERT_NAME="Caddy Local Authority - 2026 ECC Root"

          if ! /usr/bin/security find-certificate -c "$CADDY_CERT_NAME" /Library/Keychains/System.keychain >/dev/null 2>&1; then
            echo "Installing $CADDY_CERT_NAME to System keychain..."
            /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CADDY_CERT_PATH"
          else
            echo "$CADDY_CERT_NAME already installed in System keychain"
          fi
        '';
      };
    };
}
