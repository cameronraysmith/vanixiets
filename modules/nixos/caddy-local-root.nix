# flake.modules.nixos.caddy-local-root (CAM-87 design D11): caddy's local
# certificate authority signs with the root and key in certFile and keyFile
# instead of the root in its storage, so a host reinstalled with the same
# files serves the same root (caddy 2.11.7: caddyconfig/httpcaddyfile/
# pkiapp.go:32-55; modules/caddypki/ca.go:150-158). caddy refuses a key that
# does not match certFile's first certificate, never renews the root, and
# issues intermediates under it.
#
# system.checks gains caddy-root-from-vars, built with the host's toplevel:
# "configured root" adapts the rendered Caddyfile with caddy itself and
# requires apps.pki.certificate_authorities.local.root to name certFile and
# keyFile; "recorded root" requires certFile's first certificate to have the
# sha256 fingerprint `fingerprint`. Each is shown failing by an
# extendModules override on cinnabar (pkiDropped, fingerprintOther).
{ ... }:
{
  flake.modules.nixos.caddy-local-root =
    {
      config,
      lib,
      pkgs,
      ...
    }:
    let
      cfg = config.vanixiets.caddyLocalRoot;
      caddy = config.services.caddy;
    in
    {
      options.vanixiets.caddyLocalRoot = {
        certFile = lib.mkOption {
          type = lib.types.str;
          description = "PEM file whose first certificate is the local authority's root; further certificates are ignored by caddy and serve a rotation's overlap for clients.";
        };
        keyFile = lib.mkOption {
          type = lib.types.str;
          description = "PEM private key of certFile's first certificate, readable by caddy.";
        };
        fingerprint = lib.mkOption {
          type = lib.types.strMatching "([0-9A-F]{2}:){31}[0-9A-F]{2}";
          description = "sha256 fingerprint, as openssl prints it, recorded for certFile's first certificate.";
        };
      };
      config = {
        services.caddy.globalConfig = ''
          pki {
            ca local {
              root {
                cert ${cfg.certFile}
                key ${cfg.keyFile}
              }
            }
          }
        '';
        system.checks = [
          (pkgs.runCommand "caddy-root-from-vars"
            {
              nativeBuildInputs = [
                caddy.package
                pkgs.jq
                pkgs.openssl
                pkgs.gawk
              ];
            }
            ''
              set -euo pipefail
              adapted=$(caddy adapt --adapter caddyfile --config ${caddy.configFile})
              cert=$(jq -r '.apps.pki.certificate_authorities.local.root.certificate // empty' <<< "$adapted")
              key=$(jq -r '.apps.pki.certificate_authorities.local.root.private_key // empty' <<< "$adapted")
              if [ "$cert" != ${lib.escapeShellArg cfg.certFile} ] || [ "$key" != ${lib.escapeShellArg cfg.keyFile} ]; then
                echo "caddy-root-from-vars: configured root: caddy adapts the root to cert '$cert' key '$key', expected ${cfg.certFile} and ${cfg.keyFile}" >&2
                exit 1
              fi
              fp=$(awk '/BEGIN CERTIFICATE/{n++} n==1' ${cfg.certFile} | openssl x509 -noout -fingerprint -sha256 | cut -d= -f2)
              if [ "$fp" != ${lib.escapeShellArg cfg.fingerprint} ]; then
                echo "caddy-root-from-vars: recorded root: certFile's root is $fp, recorded ${cfg.fingerprint}" >&2
                exit 1
              fi
              echo "caddy-root-from-vars: caddy's root is ${cfg.certFile}, fingerprint $fp" > $out
            ''
          )
        ];
      };
    };
}
