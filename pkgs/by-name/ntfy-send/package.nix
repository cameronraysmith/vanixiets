# ntfy-send: post a push notification to the fleet's ntfy server.
# One source for every delivery: the home-manager tools command installs it,
# system units and launchd jobs run it, and the agent permission hooks post
# through it.
#
# NTFY_URL, which the preamble exports, is ntfy's base URL for the platform
# the package is built for; passthru.ntfyUrl carries it to checks and tests.
# Macs use the fleet's tincr name, ntfy.vanixiets.internal. ZeroTier's
# interface on a Mac is an Ethernet-like feth, so macOS Local Network privacy
# refuses a connection to ntfy.zt from a store binary whose responsible
# program holds no Local Network grant, an agent session under herdr for one;
# macOS tracks a grant by code signature, which for a store binary is ad hoc
# and changes with the binary. tincr's utun is a tunnel interface, which that
# privacy does not govern (Apple TN3179, "Local network operations"). NixOS
# keeps ntfy.zt until ZeroTier's retirement.
# checks.x86_64-linux.ntfy-tls-verification fails on a darwin sender whose
# ntfy-send names ntfy.zt.
#
# The preamble also exports NTFY_CURL_BIN=curl, the curl from runtimeInputs on
# every platform, and NTFY_CACERT, the store copy of caddy's root, the public
# value of cinnabar's clan vars caddy-root-ca
# (vars/per-machine/cinnabar/caddy-root-ca/root.crt/value), which every post's
# --cacert names, so ntfy-send verifies ntfy's certificate and posts nothing
# to a server that cannot present a chain to that root. The file may hold two
# roots while a rotation overlaps them (the fleet observability runbook,
# "caddy's root").
#
# NTFY_TOKEN_FILE, when set and non-empty, names a file holding an ntfy access
# token, such as the `alerter` token that fleet-* topics require. The script
# reads it with bash's $(< file) and prints `Authorization: Bearer <token>` with
# the printf builtin into curl's stdin, which curl reads with `-H @-`, so the
# token is on no process's argv. Unset, the post is anonymous, which host
# topics accept. passthru.tests.token-transport runs the source script against
# a recording curl stub, with a mutant that passes the header on argv;
# passthru.tests.tls-verification runs it and the built wrapper against a
# loopback TLS server, with a mutant that passes -k.
{
  lib,
  stdenv,
  curl,
  callPackage,
  writeShellApplication,
  caddyRootCa ? ../../../vars/per-machine/cinnabar/caddy-root-ca/root.crt/value,
  ntfyUrl ?
    if stdenv.hostPlatform.isDarwin then "https://ntfy.vanixiets.internal" else "https://ntfy.zt",
}:
let
  ntfy-send = writeShellApplication {
    name = "ntfy-send";
    runtimeInputs = [ curl ];
    text = ''
      export NTFY_CURL_BIN=curl
      export NTFY_CACERT=${caddyRootCa}
      export NTFY_URL=${ntfyUrl}
      ${builtins.readFile ./ntfy-send.sh}
    '';
    passthru = {
      inherit ntfyUrl;
      tests = {
        token-transport = callPackage ./test-token-transport.nix { };
        tls-verification = callPackage ./test-tls-verification.nix {
          ntfySend = ntfy-send;
          inherit caddyRootCa;
        };
      };
    };
    meta = {
      description = "Send push notification to the fleet's ntfy, verifying its certificate against caddy's root";
      license = lib.licenses.mit;
      mainProgram = "ntfy-send";
    };
  };
in
ntfy-send
