# ntfy-send: post a push notification to the fleet's ntfy server (ntfy.zt).
# One source for every delivery: the home-manager tools command installs it,
# system units and launchd jobs run it, and the agent permission hooks post
# through it.
#
# The preamble exports NTFY_CURL_BIN=curl, the curl from runtimeInputs on every
# platform, and NTFY_CACERT, the store copy of caddy's root, the public value
# of cinnabar's clan vars caddy-root-ca
# (vars/per-machine/cinnabar/caddy-root-ca/root.crt/value), which every post's
# --cacert names, so ntfy-send verifies ntfy.zt's certificate and posts
# nothing to a server that cannot present a chain to that root. The file may
# hold two roots while a rotation overlaps them (the fleet observability
# runbook, "caddy's root").
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
  curl,
  callPackage,
  writeShellApplication,
  caddyRootCa ? ../../../vars/per-machine/cinnabar/caddy-root-ca/root.crt/value,
}:
let
  ntfy-send = writeShellApplication {
    name = "ntfy-send";
    runtimeInputs = [ curl ];
    text = ''
      export NTFY_CURL_BIN=curl
      export NTFY_CACERT=${caddyRootCa}
      ${builtins.readFile ./ntfy-send.sh}
    '';
    passthru.tests = {
      token-transport = callPackage ./test-token-transport.nix { };
      tls-verification = callPackage ./test-tls-verification.nix {
        ntfySend = ntfy-send;
        inherit caddyRootCa;
      };
    };
    meta = {
      description = "Send push notification via ntfy.zt, verifying its certificate against caddy's root";
      license = lib.licenses.mit;
      mainProgram = "ntfy-send";
    };
  };
in
ntfy-send
