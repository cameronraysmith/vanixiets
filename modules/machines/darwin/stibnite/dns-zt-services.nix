# ZeroTier network configuration for clawdbot infrastructure on cinnabar
#
# DNS entries resolve .zt hostnames to cinnabar's ZeroTier IPv6 address.
# Caddy CA cert enables HTTPS trust for its tls-internal certificates.
{ lib, ... }:
{
  flake.modules.darwin."machines/darwin/stibnite" = {
    clan.core.networking.extraHosts.clawdbot-services = ''
      fddb:4344:343b:14b9:399:93db:4344:343b matrix.zt
      fddb:4344:343b:14b9:399:93db:4344:343b clawdbot.zt
    '';

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
