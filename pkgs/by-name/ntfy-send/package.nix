# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# and system units run it from ExecStart.
#
# The preamble injects NTFY_CURL_BIN, the eval-time-resolved curl path:
# /usr/bin/curl on Darwin, the curl from runtimeInputs on Linux. Both run with
# -sfk, so neither verifies ntfy.zt's certificate. The Darwin choice came from
# a note of 2026-03-10 that endpoint security blocks Nix store binaries from
# TCP over ZeroTier; on 2026-11-06 a store-built otelcol-contrib on stibnite
# reached the ingress over ZeroTier, and the store curl, run as _otelcol with
# --cacert modules/machines/nixos/cinnabar/pki/caddy-root-ca.crt, fetched
# https://ntfy.zt/v1/health with HTTP 200 and verification on (without the CA,
# exit 60), so that reason no longer holds. Verifying ntfy.zt in every ntfy
# client, and correcting the same endpoint-security claim in ntfy-send.sh's
# --help text, is tracked in Linear (CAM-87).
#
# NTFY_TOKEN_FILE, when set and non-empty, names a file holding an ntfy access
# token, such as the `alerter` token that fleet-* topics require. The script
# reads it with bash's $(< file) and prints `Authorization: Bearer <token>` with
# the printf builtin into curl's stdin, which curl reads with `-H @-`, so the
# token is on no process's argv. Unset, the post is anonymous, which host
# topics accept. passthru.tests.token-transport runs the source script against
# a recording curl stub, with a mutant that passes the header on argv.
{
  lib,
  stdenv,
  curl,
  callPackage,
  writeShellApplication,
}:
writeShellApplication {
  name = "ntfy-send";
  runtimeInputs = lib.optional (!stdenv.hostPlatform.isDarwin) curl;
  text = ''
    export NTFY_CURL_BIN=${if stdenv.hostPlatform.isDarwin then "/usr/bin/curl" else "curl"}
    ${builtins.readFile ./ntfy-send.sh}
  '';
  passthru.tests.token-transport = callPackage ./test-token-transport.nix { };
  meta = {
    description = "Send push notification via ntfy.zt (Apple-signed curl on Darwin)";
    license = lib.licenses.mit;
    mainProgram = "ntfy-send";
  };
}
