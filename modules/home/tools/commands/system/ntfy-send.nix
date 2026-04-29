# Send push notification via ntfy.zt
# Endpoint security software on Darwin blocks ad-hoc signed (Nix store)
# binaries from TCP connections over ZeroTier. The preamble injects
# NTFY_CURL_BIN — the eval-time-resolved curl path — so darwin uses
# /usr/bin/curl while linux uses PATH curl.
{ ... }:
{
  flake.modules.homeManager.tools =
    { pkgs, ... }:
    {
      home.packages = [
        (pkgs.writeShellApplication {
          name = "ntfy-send";
          text = ''
            export NTFY_CURL_BIN=${if pkgs.stdenv.isDarwin then "/usr/bin/curl" else "curl"}
            ${builtins.readFile ./ntfy-send.sh}
          '';
          meta.description = "Send push notification via ntfy.zt (Apple-signed curl on Darwin)";
        })
      ];
    };
}
