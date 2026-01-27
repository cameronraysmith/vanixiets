# Caddy CA cert trust for cinnabar's tls-internal certificates
{ lib, ... }:
{
  flake.modules.darwin."machines/darwin/stibnite" = {
    # Trust Caddy internal CA for curl/git/OpenSSL tools
    security.pki.certificateFiles = [
      ../../nixos/cinnabar/pki/caddy-root-ca.crt
    ];

    # Trust Caddy internal CA in macOS Keychain (for browsers and Element)
    system.activationScripts.postActivation.text = lib.mkAfter ''
      echo "Adding Caddy cinnabar internal CA to macOS Keychain..."
      CADDY_CERT_PATH="${../../nixos/cinnabar/pki/caddy-root-ca.crt}"
      CADDY_CERT_NAME="Caddy Local Authority - 2026 ECC Root"

      if ! /usr/bin/security find-certificate -c "$CADDY_CERT_NAME" /Library/Keychains/System.keychain >/dev/null 2>&1; then
        echo "Installing $CADDY_CERT_NAME to System keychain..."
        /usr/bin/security add-trusted-cert -d -r trustRoot -k /Library/Keychains/System.keychain "$CADDY_CERT_PATH"
      else
        echo "$CADDY_CERT_NAME already installed in System keychain"
      fi
    '';
  };
}
