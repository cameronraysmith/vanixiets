{ config, lib, ... }:
let
  inherit (config.flake.lib) vars;
in
{
  flake.modules.darwin.fleet-services-trust =
    { config, lib, ... }:
    let
      cfg = config.services.fleet-services-trust;
      # caddy's root, the public file of cinnabar's clan vars generator caddy-root-ca.
      caddyCert =
        vars.path {
          machine = "cinnabar";
          generator = "caddy-root-ca";
          file = "root.crt";
        }
        + "/value";
    in
    {
      options.services.fleet-services-trust.enable = lib.mkEnableOption "Caddy internal CA trust for the fleet's services";

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
